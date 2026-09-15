package api_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/pquerna/otp/totp"
	"github.com/aesms-io/aesms/server/internal/api"
	"github.com/aesms-io/aesms/server/internal/captcha"
	"github.com/aesms-io/aesms/server/internal/config"
	"github.com/aesms-io/aesms/server/internal/crypto"
	"github.com/aesms-io/aesms/server/internal/push"
	"github.com/aesms-io/aesms/server/internal/ratelimit"
	"github.com/aesms-io/aesms/server/internal/store"
	"github.com/aesms-io/aesms/server/internal/webembed"
)

func testEnv(t *testing.T) (*api.Server, *store.Store, *config.Config) {
	t.Helper()
	dir := t.TempDir()
	key := []byte("integration-test-key!!")
	st, err := store.Open(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	cfg := &config.Config{
		Listen:            ":0",
		DataDir:           dir,
		BaseURL:           "http://test.local",
		DBKey:             key,
		PendingTTL:        15 * time.Minute,
		MessageTTL:        24 * time.Hour,
		EnrollTTL:         15 * time.Minute,
		PurgeEvery:        time.Minute,
		TokenBytes:        32,
		RateLimitDisabled: true,
	}
	cfg.Fingerprint = st.Fingerprint()
	srv := api.New(cfg, st, webembed.Handler(), push.NewHub(), nil)
	return srv, st, cfg
}

func doJSON(t *testing.T, h http.Handler, method, path string, body any, hdr map[string]string) (int, http.Header, map[string]any) {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rdr)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	var out map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &out)
	return rr.Code, rr.Header(), out
}

func createActiveAccount(t *testing.T, h http.Handler, user, pass string) string {
	t.Helper()
	code, _, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": user, "password": pass,
	}, nil)
	if code != 201 {
		t.Fatalf("create: %d %#v", code, out)
	}
	if qr, _ := out["totp_qr_png"].(string); !strings.HasPrefix(qr, "data:image/png;base64,") {
		t.Fatalf("expected totp_qr_png data url, got %#v", out["totp_qr_png"])
	}
	secret := out["totp_secret"].(string)
	otp, err := totp.GenerateCode(secret, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	code, _, out = doJSON(t, h, "POST", "/v1/accounts/totp/confirm", map[string]any{
		"username": user, "code": otp,
	}, nil)
	if code != 200 {
		t.Fatalf("confirm: %d %#v", code, out)
	}
	if out["session"] != nil {
		t.Fatalf("confirm must not issue session: %#v", out["session"])
	}
	return secret
}

func TestMessagesRejectNonDeviceToken(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()

	code, _, out := doJSON(t, h, "GET", "/v1/messages", nil, nil)
	if code != 401 {
		t.Fatalf("expected 401 got %d %#v", code, out)
	}
	code, _, out = doJSON(t, h, "GET", "/v1/messages", nil, map[string]string{
		"Authorization": "Bearer not-a-real-token",
	})
	if code != 401 {
		t.Fatalf("expected 401 got %d %#v", code, out)
	}
	code, _, out = doJSON(t, h, "POST", "/v1/messages", map[string]any{
		"to_username": "x", "ciphertext": "YQ==", "graphemes": 1,
	}, map[string]string{"Authorization": "Bearer web-session-pretend"})
	if code != 401 {
		t.Fatalf("post expected 401 got %d %#v", code, out)
	}
}

func TestPendingCannotFetchUntilReleased(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()
	secret := createActiveAccount(t, h, "alice", "password1234")

	code, _, out := doJSON(t, h, "POST", "/v1/device/login", map[string]any{
		"username": "alice", "password": "password1234",
		"device_id": "dev-1", "assertion": "signed-app-mvp",
	}, nil)
	if code != 202 {
		t.Fatalf("login: %d %#v", code, out)
	}
	pendingID := out["pending_id"].(string)

	// Still pending — no device token yet
	code, _, poll := doJSON(t, h, "GET", "/v1/device/login/"+pendingID, nil, nil)
	if code != 200 || poll["status"] != "pending" {
		t.Fatalf("poll pending: %d %#v", code, poll)
	}
	if _, ok := poll["device_token"]; ok {
		t.Fatal("must not have device_token while pending")
	}

	// Cannot fetch mail
	code, _, _ = doJSON(t, h, "GET", "/v1/messages", nil, map[string]string{
		"Authorization": "Bearer " + pendingID,
	})
	if code != 401 {
		t.Fatalf("pending id must not work as token: %d", code)
	}

	otp, _ := totp.GenerateCode(secret, time.Now())
	code, hdr, rel := doJSON(t, h, "POST", "/v1/device/release", map[string]any{
		"username": "alice", "code": otp, "pending_id": pendingID, "action": "approve",
	}, nil)
	if code != 200 {
		t.Fatalf("release: %d %#v", code, rel)
	}
	if rel["session"] != nil {
		t.Fatal("release must not create web session")
	}
	if v := hdr.Get("Set-Cookie"); v != "" {
		t.Fatalf("unexpected Set-Cookie: %s", v)
	}

	code, _, poll = doJSON(t, h, "GET", "/v1/device/login/"+pendingID, nil, nil)
	if code != 200 || poll["status"] != "approved" {
		t.Fatalf("poll approved: %d %#v", code, poll)
	}
	tok, _ := poll["device_token"].(string)
	if tok == "" {
		t.Fatal("expected device_token")
	}

	// Second poll should not re-issue token
	code, _, poll2 := doJSON(t, h, "GET", "/v1/device/login/"+pendingID, nil, nil)
	if code != 200 {
		t.Fatal(poll2)
	}
	if _, ok := poll2["device_token"]; ok && poll2["device_token"] != "" {
		t.Fatal("token should be one-shot")
	}

	code, _, msgs := doJSON(t, h, "GET", "/v1/messages", nil, map[string]string{
		"Authorization": "Bearer " + tok,
	})
	if code != 200 {
		t.Fatalf("fetch: %d %#v", code, msgs)
	}
}

func TestFetchOnceDeletes(t *testing.T) {
	srv, st, _ := testEnv(t)
	h := srv.Handler()
	secret := createActiveAccount(t, h, "bob", "password1234")
	_ = createActiveAccount(t, h, "carol", "password1234")

	// bind bob
	code, _, out := doJSON(t, h, "POST", "/v1/device/login", map[string]any{
		"username": "bob", "password": "password1234", "device_id": "d1", "assertion": "a",
	}, nil)
	pending := out["pending_id"].(string)
	otp, _ := totp.GenerateCode(secret, time.Now())
	_, _, _ = doJSON(t, h, "POST", "/v1/device/release", map[string]any{
		"username": "bob", "code": otp, "pending_id": pending, "action": "approve",
	}, nil)
	_, _, poll := doJSON(t, h, "GET", "/v1/device/login/"+pending, nil, nil)
	tok := poll["device_token"].(string)

	_, err := st.InsertMessage(
		mustAccountID(t, st, "bob"),
		"carol",
		[]byte("cipher"),
		24*time.Hour,
	)
	if err != nil {
		t.Fatal(err)
	}

	code, _, msgs := doJSON(t, h, "GET", "/v1/messages", nil, map[string]string{
		"Authorization": "Bearer " + tok,
	})
	if code != 200 {
		t.Fatal(msgs)
	}
	arr := msgs["messages"].([]any)
	if len(arr) != 1 {
		t.Fatalf("want 1 got %d", len(arr))
	}
	code, _, msgs = doJSON(t, h, "GET", "/v1/messages", nil, map[string]string{
		"Authorization": "Bearer " + tok,
	})
	arr = msgs["messages"].([]any)
	if len(arr) != 0 {
		t.Fatal("fetch-once failed")
	}
}

func mustAccountID(t *testing.T, st *store.Store, user string) string {
	t.Helper()
	a, err := st.GetAccountByUsername(user)
	if err != nil {
		t.Fatal(err)
	}
	return a.ID
}

func TestNoAccountSessionCookiesOnWebFlows(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()
	secret := createActiveAccount(t, h, "dave", "password1234")

	paths := []struct {
		method string
		path   string
		body   any
	}{
		{"POST", "/v1/accounts", map[string]any{"username": "eve", "password": "password1234"}},
		{"GET", "/v1/health", nil},
		{"GET", "/v1/info", nil},
	}
	for _, p := range paths {
		code, hdr, _ := doJSON(t, h, p.method, p.path, p.body, nil)
		if code >= 500 {
			t.Fatalf("%s %s -> %d", p.method, p.path, code)
		}
		if c := hdr.Values("Set-Cookie"); len(c) > 0 {
			t.Fatalf("Set-Cookie on %s: %v", p.path, c)
		}
	}

	// release path
	code, _, out := doJSON(t, h, "POST", "/v1/device/login", map[string]any{
		"username": "dave", "password": "password1234", "device_id": "x", "assertion": "a",
	}, nil)
	if code != 202 {
		t.Fatal(out)
	}
	otp, _ := totp.GenerateCode(secret, time.Now())
	code, hdr, _ := doJSON(t, h, "POST", "/v1/device/release", map[string]any{
		"username": "dave", "code": otp, "pending_id": out["pending_id"], "action": "deny",
	}, nil)
	if code != 200 {
		t.Fatal(code)
	}
	if c := hdr.Values("Set-Cookie"); len(c) > 0 {
		t.Fatalf("Set-Cookie on release: %v", c)
	}
}

func TestSealedDBNotPlaintext(t *testing.T) {
	dir := t.TempDir()
	key := []byte("sixteen-byte-key!")
	st, err := store.Open(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	_, err = st.CreateAccountInactive("z", "hash", "TOTPSECRET", 15*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.Close()

	sealedPath := filepath.Join(dir, "aesms.db.sealed")
	raw, err := os.ReadFile(sealedPath)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("SQLite format 3")) {
		t.Fatal("sealed file contains plaintext SQLite header")
	}
	if bytes.Contains(raw, []byte("TOTPSECRET")) {
		t.Fatal("totp visible in sealed file")
	}
	if !strings.HasPrefix(string(raw), "AESMS1\n") {
		t.Fatal("missing seal magic")
	}
	plain, err := crypto.OpenFile(key, raw)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(plain, []byte("SQLite format 3")) {
		t.Fatal("decrypt should yield sqlite")
	}
}

func TestPIIRejected(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()
	code, _, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "frank", "password": "password1234", "email": "a@b.c",
	}, nil)
	if code != 400 {
		t.Fatalf("expected 400 got %d %#v", code, out)
	}
}

func TestUnknownJSONFieldRejected(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()
	code, _, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "frank2", "password": "password1234", "extra": true,
	}, nil)
	if code != 400 || out["error"] != "unknown field" {
		t.Fatalf("expected unknown field, got %d %#v", code, out)
	}
}

func TestConfirmRejectsBadUsername(t *testing.T) {
	srv, _, _ := testEnv(t)
	h := srv.Handler()
	code, _, out := doJSON(t, h, "POST", "/v1/accounts/totp/confirm", map[string]any{
		"username": "ab", "code": "123456",
	}, nil)
	if code != 400 {
		t.Fatalf("expected 400 got %d %#v", code, out)
	}
}

func TestCaptchaRequiredWhenConfigured(t *testing.T) {
	srv, _, _ := testEnv(t)
	failSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":false}`))
	}))
	t.Cleanup(failSrv.Close)
	okSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":true}`))
	}))
	t.Cleanup(okSrv.Close)

	srv.Cfg.TurnstileSiteKey = "site"
	srv.Cfg.TurnstileSecret = "secret"
	srv.Captcha = &captcha.Turnstile{
		Secret:    "secret",
		VerifyURL: failSrv.URL,
		Client:    failSrv.Client(),
	}

	code, _, info := doJSON(t, srv.Handler(), "GET", "/v1/info", nil, nil)
	if code != 200 || info["captcha_required"] != true {
		t.Fatalf("info captcha: %d %#v", code, info)
	}

	code, _, out := doJSON(t, srv.Handler(), "POST", "/v1/accounts", map[string]any{
		"username": "capuser", "password": "password1234",
	}, nil)
	if code != 400 || out["error"] != "captcha failed" {
		t.Fatalf("missing token: %d %#v", code, out)
	}
	code, _, out = doJSON(t, srv.Handler(), "POST", "/v1/accounts", map[string]any{
		"username": "capuser", "password": "password1234",
		"cf-turnstile-response": "bad",
	}, nil)
	if code != 400 {
		t.Fatalf("bad captcha: %d %#v", code, out)
	}

	srv.Captcha.VerifyURL = okSrv.URL
	srv.Captcha.Client = okSrv.Client()
	code, _, out = doJSON(t, srv.Handler(), "POST", "/v1/accounts", map[string]any{
		"username": "capuser", "password": "password1234",
		"cf-turnstile-response": "good",
	}, nil)
	if code != 201 {
		t.Fatalf("good captcha: %d %#v", code, out)
	}
}

func TestRateLimitOnAccountCreate(t *testing.T) {
	srv, _, cfg := testEnv(t)
	cfg.RateLimitDisabled = false
	srv.Limiter = ratelimit.New(map[ratelimit.Class]ratelimit.Limit{
		ratelimit.ClassAuthHeavy: {Rate: 0.001, Burst: 2},
		ratelimit.ClassAuthLight: {Rate: 100, Burst: 100},
		ratelimit.ClassMailbox:   {Rate: 100, Burst: 100},
		ratelimit.ClassGlobal:    {Rate: 100, Burst: 100},
	})
	h := srv.Handler()
	for i := 0; i < 2; i++ {
		code, _, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
			"username": "rl" + string(rune('a'+i)), "password": "password1234",
		}, nil)
		if code != 201 {
			t.Fatalf("create %d: %d %#v", i, code, out)
		}
	}
	code, hdr, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "rlz", "password": "password1234",
	}, nil)
	if code != 429 {
		t.Fatalf("expected 429 got %d %#v", code, out)
	}
	if hdr.Get("Retry-After") == "" {
		t.Fatal("missing Retry-After")
	}
}

func TestUnfinishedEnrollmentReleasesUsername(t *testing.T) {
	srv, st, _ := testEnv(t)
	h := srv.Handler()

	code, _, out := doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "gina", "password": "password1234",
	}, nil)
	if code != 201 {
		t.Fatalf("create: %d %#v", code, out)
	}
	firstID := out["account_id"]

	code, _, out = doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "gina", "password": "password9999xx",
	}, nil)
	if code != 201 {
		t.Fatalf("recreate unfinished: %d %#v", code, out)
	}
	if out["account_id"] == firstID {
		t.Fatal("expected a new row after replacing unfinished enrollment")
	}

	code, _, out = doJSON(t, h, "POST", "/v1/accounts/abandon", map[string]any{
		"username": "gina", "password": "password9999xx",
	}, nil)
	if code != 200 || out["released"] != true {
		t.Fatalf("abandon: %d %#v", code, out)
	}
	if _, err := st.GetAccountByUsername("gina"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("username should be free after abandon, got %v", err)
	}

	_, err := st.CreateAccountInactive("ivy", "xhashxxxxxxxxxx", "SECRETTOTPIVY", -time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	n, err := st.PurgeExpired(time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	if n < 1 {
		t.Fatalf("expected purge of expired enrollment, n=%d", n)
	}
	if _, err := st.GetAccountByUsername("ivy"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("ivy should be released, got %v", err)
	}

	secret := createActiveAccount(t, h, "gina", "password1234")
	if secret == "" {
		t.Fatal("active account missing secret")
	}
	code, _, out = doJSON(t, h, "POST", "/v1/accounts", map[string]any{
		"username": "gina", "password": "password1234",
	}, nil)
	if code != 409 {
		t.Fatalf("active username must stay taken: %d %#v", code, out)
	}
}
