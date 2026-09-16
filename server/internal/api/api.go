package api

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/aesms-io/aesms/server/internal/auth"
	"github.com/aesms-io/aesms/server/internal/captcha"
	"github.com/aesms-io/aesms/server/internal/config"
	"github.com/aesms-io/aesms/server/internal/crypto"
	"github.com/aesms-io/aesms/server/internal/push"
	"github.com/aesms-io/aesms/server/internal/ratelimit"
	"github.com/aesms-io/aesms/server/internal/sendpace"
	"github.com/aesms-io/aesms/server/internal/setup"
	"github.com/aesms-io/aesms/server/internal/store"
)

type Server struct {
	Cfg     *config.Config
	Store   *store.Store // nil while SetupNeeded
	Mux     *http.ServeMux
	Static  http.Handler
	Hub     *push.Hub
	APNs    *push.APNs
	Limiter *ratelimit.Limiter
	// SendPace enforces one message / 1.5s per account (SMS pacing).
	SendPace *sendpace.Gate
	Captcha  *captcha.Turnstile
	// OnConfigured is called after a successful setup save (usually os.Exit so Docker restarts).
	OnConfigured func()
}

func New(cfg *config.Config, st *store.Store, static http.Handler, hub *push.Hub, apns *push.APNs) *Server {
	s := &Server{
		Cfg:      cfg,
		Store:    st,
		Mux:      http.NewServeMux(),
		Static:   static,
		Hub:      hub,
		APNs:     apns,
		SendPace: sendpace.New(sendpace.DefaultInterval),
	}
	if cfg != nil && cfg.TurnstileSecret != "" {
		s.Captcha = &captcha.Turnstile{Secret: cfg.TurnstileSecret}
	}
	if cfg == nil || !cfg.RateLimitDisabled {
		s.Limiter = ratelimit.New(nil)
	}
	s.routes()
	return s
}

func (s *Server) Handler() http.Handler {
	h := http.Handler(s.Mux)
	if s.Limiter != nil {
		h = s.Limiter.Middleware(h)
	}
	return s.noSessionCookies(h)
}

// noSessionCookies strips any Set-Cookie that looks like an account session.
func (s *Server) noSessionCookies(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rw := &cookieFilter{ResponseWriter: w}
		next.ServeHTTP(rw, r)
	})
}

type cookieFilter struct {
	http.ResponseWriter
}

func (c *cookieFilter) Header() http.Header { return c.ResponseWriter.Header() }

func (c *cookieFilter) WriteHeader(status int) {
	// Drop Set-Cookie entirely — web has no account sessions.
	c.ResponseWriter.Header().Del("Set-Cookie")
	c.ResponseWriter.WriteHeader(status)
}

func (c *cookieFilter) Write(b []byte) (int, error) {
	c.ResponseWriter.Header().Del("Set-Cookie")
	return c.ResponseWriter.Write(b)
}

func (s *Server) routes() {
	s.Mux.HandleFunc("GET /v1/health", s.handleHealth)
	s.Mux.HandleFunc("GET /v1/info", s.handleInfo)
	s.Mux.HandleFunc("GET /v1/setup", s.handleSetupGet)
	s.Mux.HandleFunc("POST /v1/setup", s.handleSetupPost)
	s.Mux.HandleFunc("POST /v1/setup/generate-key", s.handleSetupGenerateKey)

	s.Mux.HandleFunc("POST /v1/accounts", s.requireReady(s.handleCreateAccount))
	s.Mux.HandleFunc("POST /v1/accounts/totp/confirm", s.requireReady(s.handleConfirmTOTP))
	s.Mux.HandleFunc("POST /v1/accounts/abandon", s.requireReady(s.handleAbandonEnrollment))
	s.Mux.HandleFunc("POST /v1/device/login", s.requireReady(s.handleDeviceLogin))
	s.Mux.HandleFunc("GET /v1/device/login/{id}", s.requireReady(s.handleDeviceLoginPoll))
	s.Mux.HandleFunc("POST /v1/device/release", s.requireReady(s.handleDeviceRelease))
	s.Mux.HandleFunc("POST /v1/device/revoke", s.requireReady(s.handleDeviceRevoke))
	s.Mux.HandleFunc("POST /v1/device/push-token", s.requireReady(s.handlePushToken))
	s.Mux.HandleFunc("GET /v1/events", s.requireReady(s.handleEvents))
	s.Mux.HandleFunc("POST /v1/messages", s.requireReady(s.handlePostMessage))
	s.Mux.HandleFunc("GET /v1/messages", s.requireReady(s.handleGetMessages))
	if s.Static != nil {
		s.Mux.HandleFunc("GET /{$}", s.handleRoot)
		s.Mux.Handle("GET /setup.html", s.Static)
		s.Mux.Handle("GET /release.html", s.Static)
		s.Mux.Handle("GET /status.html", s.Static)
		s.Mux.Handle("GET /assets/", s.Static)
	}
}

func (s *Server) requireReady(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.Cfg.SetupNeeded || s.Store == nil {
			writeErr(w, http.StatusServiceUnavailable, "server setup required — open /setup.html")
			return
		}
		next(w, r)
	}
}

func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if s.Cfg.SetupNeeded {
		http.Redirect(w, r, "/setup.html", http.StatusFound)
		return
	}
	if s.Static != nil {
		s.Static.ServeHTTP(w, r)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func jsonFieldNames(dst any) map[string]struct{} {
	t := reflect.TypeOf(dst)
	if t == nil {
		return nil
	}
	if t.Kind() == reflect.Ptr {
		t = t.Elem()
	}
	if t.Kind() != reflect.Struct {
		return nil
	}
	out := make(map[string]struct{})
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		tag := f.Tag.Get("json")
		if tag == "" || tag == "-" {
			continue
		}
		name := strings.Split(tag, ",")[0]
		if name == "" || name == "-" {
			continue
		}
		out[name] = struct{}{}
	}
	return out
}

func readJSON(r *http.Request, dst any) (map[string]any, error) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, err
	}
	if err := auth.RejectPIIFields(raw); err != nil {
		return raw, err
	}
	if allowed := jsonFieldNames(dst); allowed != nil {
		if err := auth.RejectUnknownFields(raw, allowed); err != nil {
			return raw, err
		}
	}
	if err := json.Unmarshal(body, dst); err != nil {
		return raw, err
	}
	return raw, nil
}

func readJSONErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrPIIRejected):
		writeErr(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, auth.ErrUnknownField):
		writeErr(w, http.StatusBadRequest, "unknown field")
	default:
		writeErr(w, http.StatusBadRequest, "invalid json")
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":           true,
		"setup_needed": s.Cfg.SetupNeeded,
		"time":         time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	captchaRequired := s.Captcha != nil && s.Captcha.Enabled()
	writeJSON(w, http.StatusOK, map[string]any{
		"name":               "aesms",
		"base_url":           s.Cfg.BaseURL,
		"fingerprint":        s.Cfg.Fingerprint,
		"message_ttl_h":      24,
		"max_graphemes":      auth.MaxMessageGraphemes,
		"send_interval_ms":   int(sendpace.DefaultInterval / time.Millisecond),
		"web_login":          false,
		"pii":                false,
		"fetch_once":         true,
		"one_device":         true,
		"setup_needed":       s.Cfg.SetupNeeded,
		"push":               true,
		"turnstile_site_key": s.Cfg.TurnstileSiteKey,
		"captcha_required":   captchaRequired,
	})
}

func (s *Server) handleSetupGet(w http.ResponseWriter, r *http.Request) {
	sf, _ := setup.Load(s.Cfg.DataDir)
	hasTunnel := false
	if _, err := os.Stat(setup.TunnelPath(s.Cfg.DataDir)); err == nil {
		hasTunnel = true
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"configured":       !s.Cfg.SetupNeeded,
		"base_url":         s.Cfg.BaseURL,
		"has_db_key":       len(s.Cfg.DBKey) >= 16 || (sf != nil && len(sf.DBKey) >= 16),
		"has_tunnel_token": hasTunnel || (sf != nil && sf.TunnelToken != ""),
		"data_dir":         s.Cfg.DataDir,
		"message":          "Configure public URL and DB key here. No host file edits required.",
	})
}

type setupPostReq struct {
	BaseURL     string `json:"base_url"`
	DBKey       string `json:"db_key"`
	TunnelToken string `json:"tunnel_token"`
}

func (s *Server) handleSetupPost(w http.ResponseWriter, r *http.Request) {
	var req setupPostReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	base := strings.TrimRight(strings.TrimSpace(req.BaseURL), "/")
	if base == "" {
		writeErr(w, http.StatusBadRequest, "base_url required")
		return
	}
	key := strings.TrimSpace(req.DBKey)
	if key == "" {
		if sf, _ := setup.Load(s.Cfg.DataDir); sf != nil && sf.DBKey != "" {
			key = sf.DBKey
		}
	}
	if len(os.Getenv("AESMS_DB_KEY")) >= 16 && key == "" {
		key = os.Getenv("AESMS_DB_KEY")
	}
	if len(key) < 16 {
		writeErr(w, http.StatusBadRequest, "db_key must be at least 16 characters")
		return
	}
	f := &setup.File{
		BaseURL:     base,
		DBKey:       key,
		TunnelToken: strings.TrimSpace(req.TunnelToken),
	}
	if err := setup.Save(s.Cfg.DataDir, f); err != nil {
		writeErr(w, http.StatusInternalServerError, "save failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"message": "Saved to volume. Server is restarting to apply mailbox config.",
	})
	if s.OnConfigured != nil {
		go func() {
			time.Sleep(300 * time.Millisecond)
			s.OnConfigured()
		}()
	}
}

func (s *Server) handleSetupGenerateKey(w http.ResponseWriter, r *http.Request) {
	k, err := setup.GenerateDBKey()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "generate failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"db_key": k})
}

func (s *Server) handlePushToken(w http.ResponseWriter, r *http.Request) {
	authz := r.Header.Get("Authorization")
	if !strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		writeErr(w, http.StatusUnauthorized, "device token required")
		return
	}
	tok := strings.TrimSpace(authz[7:])
	var req struct {
		PushToken string `json:"push_token"`
	}
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := s.Store.SetPushToken(tok, strings.TrimSpace(req.PushToken)); err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid device token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	_, acc, ok := s.requireDevice(w, r)
	if !ok {
		return
	}
	if s.Hub == nil {
		writeErr(w, http.StatusServiceUnavailable, "events unavailable")
		return
	}
	s.Hub.ServeSSE(w, r, acc.ID)
}

type createAccountReq struct {
	Username          string `json:"username"`
	Password          string `json:"password"`
	TurnstileResponse string `json:"cf-turnstile-response"`
}

type abandonReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) handleCreateAccount(w http.ResponseWriter, r *http.Request) {
	var req createAccountReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if s.Captcha != nil && s.Captcha.Enabled() {
		if err := s.Captcha.Verify(r.Context(), req.TurnstileResponse, ratelimit.ClientIP(r)); err != nil {
			writeErr(w, http.StatusBadRequest, "captcha failed")
			return
		}
	}
	hash, err := crypto.HashPassword(req.Password)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "hash failed")
		return
	}
	key, err := auth.GenerateTOTP("AeSMS", req.Username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "totp failed")
		return
	}
	qrPNG, err := auth.TOTPQRDataURL(key.URL())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "qr failed")
		return
	}
	acc, err := s.Store.CreateAccountInactive(req.Username, hash, key.Secret(), s.Cfg.EnrollTTL)
	if err != nil {
		if errors.Is(err, store.ErrConflict) {
			writeErr(w, http.StatusConflict, "username taken")
			return
		}
		writeErr(w, http.StatusInternalServerError, "create failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"account_id":        acc.ID,
		"username":          acc.Username,
		"totp_secret":       key.Secret(),
		"totp_uri":          key.URL(),
		"totp_qr_png":       qrPNG,
		"active":            false,
		"enroll_expires_at": acc.EnrollExpiresAt.UTC().Format(time.RFC3339),
		"message":           "Confirm TOTP to finalize. Unfinished enrollments expire and free the username. No web session is issued.",
		"session":           nil,
	})
}

type confirmReq struct {
	Username string `json:"username"`
	Code     string `json:"code"`
}

func (s *Server) handleConfirmTOTP(w http.ResponseWriter, r *http.Request) {
	var req confirmReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidateTOTPCode(req.Code); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	err := s.Store.ConfirmTOTP(req.Username, strings.TrimSpace(req.Code), auth.ValidateTOTP)
	if err != nil {
		switch {
		case errors.Is(err, store.ErrNotFound):
			writeErr(w, http.StatusNotFound, "account not found")
		case errors.Is(err, store.ErrConflict):
			writeErr(w, http.StatusConflict, "already active")
		case errors.Is(err, store.ErrDenied):
			writeErr(w, http.StatusUnauthorized, "invalid totp")
		default:
			writeErr(w, http.StatusInternalServerError, "confirm failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"active":  true,
		"session": nil,
		"message": "Account ready. Use the signed app + web release to bind a device.",
	})
}

func (s *Server) handleAbandonEnrollment(w http.ResponseWriter, r *http.Request) {
	var req abandonReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	err := s.Store.AbandonEnrollment(req.Username, req.Password, crypto.VerifyPassword)
	if err != nil {
		switch {
		case errors.Is(err, store.ErrNotFound):
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "released": true})
		case errors.Is(err, store.ErrConflict):
			writeErr(w, http.StatusConflict, "account already active")
		case errors.Is(err, store.ErrDenied):
			writeErr(w, http.StatusUnauthorized, "invalid credentials")
		default:
			writeErr(w, http.StatusInternalServerError, "abandon failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "released": true, "session": nil})
}

type deviceLoginReq struct {
	Username  string `json:"username"`
	Password  string `json:"password"`
	DeviceID  string `json:"device_id"`
	Assertion string `json:"assertion"`
}

func (s *Server) handleDeviceLogin(w http.ResponseWriter, r *http.Request) {
	var req deviceLoginReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidateDeviceID(req.DeviceID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidateAssertion(req.Assertion); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	acc, err := s.Store.GetAccountByUsername(req.Username)
	if err != nil || !crypto.VerifyPassword(acc.PasswordHash, req.Password) {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	if !acc.Active {
		writeErr(w, http.StatusForbidden, "account not active")
		return
	}
	p, err := s.Store.CreatePendingLogin(acc.ID, req.DeviceID, req.Assertion, s.Cfg.PendingTTL)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "pending failed")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"pending_id":  p.ID,
		"status":      "pending",
		"expires_at":  p.ExpiresAt.Format(time.RFC3339),
		"release_url": s.Cfg.BaseURL + "/release.html?pending_id=" + p.ID,
	})
}

func (s *Server) handleDeviceLoginPoll(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := auth.ValidatePendingID(id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	status, tok, err := s.Store.ConsumePendingPoll(id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeErr(w, http.StatusNotFound, "not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "poll failed")
		return
	}
	resp := map[string]any{"pending_id": id, "status": status}
	if tok != "" {
		resp["device_token"] = tok
		resp["token_type"] = "device"
	}
	writeJSON(w, http.StatusOK, resp)
}

type releaseReq struct {
	Username  string `json:"username"`
	Code      string `json:"code"`
	PendingID string `json:"pending_id"`
	Action    string `json:"action"` // approve|deny
}

func (s *Server) handleDeviceRelease(w http.ResponseWriter, r *http.Request) {
	var req releaseReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidateTOTPCode(req.Code); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidatePendingID(req.PendingID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	acc, err := s.Store.GetAccountByUsername(req.Username)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	secret, err := s.Store.TOTPSecret(acc)
	if err != nil || !auth.ValidateTOTP(secret, strings.TrimSpace(req.Code)) {
		writeErr(w, http.StatusUnauthorized, "invalid totp")
		return
	}
	p, err := s.Store.GetPending(req.PendingID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "pending not found")
		return
	}
	if p.AccountID != acc.ID {
		writeErr(w, http.StatusForbidden, "pending mismatch")
		return
	}
	action := strings.ToLower(req.Action)
	approve := action == "approve" || action == "allow"
	if !approve && action != "deny" {
		writeErr(w, http.StatusBadRequest, "action must be approve or deny")
		return
	}
	status, err := s.Store.ReleasePending(req.PendingID, approve, func() (string, string, error) {
		tok, err := crypto.RandomToken(s.Cfg.TokenBytes)
		if err != nil {
			return "", "", err
		}
		return tok, crypto.HashToken(tok), nil
	})
	if err != nil {
		switch {
		case errors.Is(err, store.ErrPendingExpired):
			writeErr(w, http.StatusGone, "pending expired")
		case errors.Is(err, store.ErrConflict):
			writeErr(w, http.StatusConflict, "already resolved")
		default:
			log.Printf("release: %v", err)
			writeErr(w, http.StatusInternalServerError, "release failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"status":  status,
		"session": nil,
		"message": "No web session retained.",
	})
}

type revokeReq struct {
	// Either device bearer, or usr+TOTP (web-style, still no session).
	Username string `json:"username"`
	Code     string `json:"code"`
}

func (s *Server) handleDeviceRevoke(w http.ResponseWriter, r *http.Request) {
	authz := r.Header.Get("Authorization")
	if strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		tok := strings.TrimSpace(authz[7:])
		if err := s.Store.RevokeByToken(tok); err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid token")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "revoked": true})
		return
	}
	var req revokeReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.Username); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := auth.ValidateTOTPCode(req.Code); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	acc, err := s.Store.GetAccountByUsername(req.Username)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	secret, err := s.Store.TOTPSecret(acc)
	if err != nil || !auth.ValidateTOTP(secret, strings.TrimSpace(req.Code)) {
		writeErr(w, http.StatusUnauthorized, "invalid totp")
		return
	}
	_ = s.Store.RevokeByAccount(acc.ID)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "revoked": true, "session": nil})
}

func (s *Server) requireDevice(w http.ResponseWriter, r *http.Request) (*store.DeviceSession, *store.Account, bool) {
	authz := r.Header.Get("Authorization")
	if !strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		writeErr(w, http.StatusUnauthorized, "device token required")
		return nil, nil, false
	}
	tok := strings.TrimSpace(authz[7:])
	if tok == "" {
		writeErr(w, http.StatusUnauthorized, "device token required")
		return nil, nil, false
	}
	d, acc, err := s.Store.LookupDeviceToken(tok)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid device token")
		return nil, nil, false
	}
	return d, acc, true
}

type postMsgReq struct {
	ToUsername string `json:"to_username"`
	Ciphertext string `json:"ciphertext"` // base64
	PlainHint  string `json:"plain_hint"` // optional plaintext for server grapheme check of sealed length N/A — client sends grapheme_count
	Graphemes  int    `json:"graphemes"`
	Pubkey     string `json:"pubkey"` // optional upload of sender pubkey
}

func (s *Server) handlePostMessage(w http.ResponseWriter, r *http.Request) {
	_, sender, ok := s.requireDevice(w, r)
	if !ok {
		return
	}
	var req postMsgReq
	if _, err := readJSON(r, &req); err != nil {
		readJSONErr(w, err)
		return
	}
	if err := auth.ValidateUsername(req.ToUsername); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Graphemes <= 0 || req.Graphemes > auth.MaxMessageGraphemes {
		writeErr(w, http.StatusBadRequest, "graphemes must be 1..160")
		return
	}
	ct, err := store.DecodeCiphertextB64(req.Ciphertext)
	if err != nil || len(ct) == 0 || len(ct) > 4096 {
		writeErr(w, http.StatusBadRequest, "invalid ciphertext")
		return
	}
	if err := auth.ValidatePubkey(req.Pubkey); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	recip, err := s.Store.GetAccountByUsername(req.ToUsername)
	if err != nil || !recip.Active {
		writeErr(w, http.StatusNotFound, "recipient not found")
		return
	}
	if retry, ok := s.SendPace.Begin(sender.ID); !ok {
		sec := int(math.Ceil(retry.Seconds()))
		if sec < 1 {
			sec = 1
		}
		w.Header().Set("Retry-After", strconv.Itoa(sec))
		writeErr(w, http.StatusTooManyRequests, "wait before sending again — one message every 1.5 seconds")
		return
	}
	defer s.SendPace.End(sender.ID)
	if err := s.SendPace.Hold(r.Context()); err != nil {
		writeErr(w, http.StatusRequestTimeout, "send cancelled")
		return
	}
	if req.Pubkey != "" {
		_ = s.Store.SetPubkey(sender.ID, req.Pubkey)
	}
	msg, err := s.Store.InsertMessage(recip.ID, sender.Username, ct, s.Cfg.MessageTTL)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "store failed")
		return
	}
	if s.Hub != nil {
		s.Hub.Notify(recip.ID, "message")
	}
	if s.APNs != nil {
		if pt, err := s.Store.PushTokenForAccount(recip.ID); err == nil && pt != "" {
			go s.APNs.Notify(pt)
		}
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"id":         msg.ID,
		"expires_at": msg.ExpiresAt.Format(time.RFC3339),
	})
}

func (s *Server) handleGetMessages(w http.ResponseWriter, r *http.Request) {
	_, acc, ok := s.requireDevice(w, r)
	if !ok {
		return
	}
	msgs, err := s.Store.FetchAndDelete(acc.ID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "fetch failed")
		return
	}
	out := make([]map[string]any, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, map[string]any{
			"id":            m.ID,
			"from_username": m.SenderUsername,
			"ciphertext":    store.CiphertextB64(m.Ciphertext),
			"created_at":    m.CreatedAt.Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": out})
}
