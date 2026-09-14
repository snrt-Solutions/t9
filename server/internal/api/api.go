package api

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/t9-messenger/t9/server/internal/auth"
	"github.com/t9-messenger/t9/server/internal/config"
	"github.com/t9-messenger/t9/server/internal/crypto"
	"github.com/t9-messenger/t9/server/internal/store"
)

type Server struct {
	Cfg   *config.Config
	Store *store.Store
	Mux   *http.ServeMux
	Static http.Handler
}

func New(cfg *config.Config, st *store.Store, static http.Handler) *Server {
	s := &Server{Cfg: cfg, Store: st, Mux: http.NewServeMux(), Static: static}
	s.routes()
	return s
}

func (s *Server) Handler() http.Handler {
	return s.noSessionCookies(s.Mux)
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
	s.Mux.HandleFunc("POST /v1/accounts", s.handleCreateAccount)
	s.Mux.HandleFunc("POST /v1/accounts/totp/confirm", s.handleConfirmTOTP)
	s.Mux.HandleFunc("POST /v1/device/login", s.handleDeviceLogin)
	s.Mux.HandleFunc("GET /v1/device/login/{id}", s.handleDeviceLoginPoll)
	s.Mux.HandleFunc("POST /v1/device/release", s.handleDeviceRelease)
	s.Mux.HandleFunc("POST /v1/device/revoke", s.handleDeviceRevoke)
	s.Mux.HandleFunc("POST /v1/messages", s.handlePostMessage)
	s.Mux.HandleFunc("GET /v1/messages", s.handleGetMessages)
	if s.Static != nil {
		s.Mux.Handle("GET /", s.Static)
		s.Mux.Handle("GET /assets/", s.Static)
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
	if err := json.Unmarshal(body, dst); err != nil {
		return raw, err
	}
	return raw, nil
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":   true,
		"time": time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"name":            "t9",
		"base_url":        s.Cfg.BaseURL,
		"fingerprint":     s.Store.Fingerprint(),
		"message_ttl_h":   24,
		"max_graphemes":   auth.MaxMessageGraphemes,
		"web_login":       false,
		"pii":             false,
		"fetch_once":      true,
		"one_device":      true,
	})
}

type createAccountReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) handleCreateAccount(w http.ResponseWriter, r *http.Request) {
	var req createAccountReq
	if _, err := readJSON(r, &req); err != nil {
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
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
	hash, err := crypto.HashPassword(req.Password)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "hash failed")
		return
	}
	key, err := auth.GenerateTOTP("T9", req.Username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "totp failed")
		return
	}
	acc, err := s.Store.CreateAccountInactive(req.Username, hash, key.Secret())
	if err != nil {
		if errors.Is(err, store.ErrConflict) {
			writeErr(w, http.StatusConflict, "username taken")
			return
		}
		writeErr(w, http.StatusInternalServerError, "create failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"account_id":    acc.ID,
		"username":      acc.Username,
		"totp_secret":   key.Secret(),
		"totp_uri":      key.URL(),
		"active":        false,
		"message":       "Confirm TOTP to finalize. No web session is issued.",
		"session":       nil,
	})
}

type confirmReq struct {
	Username string `json:"username"`
	Code     string `json:"code"`
}

func (s *Server) handleConfirmTOTP(w http.ResponseWriter, r *http.Request) {
	var req confirmReq
	if _, err := readJSON(r, &req); err != nil {
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
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

type deviceLoginReq struct {
	Username  string `json:"username"`
	Password  string `json:"password"`
	DeviceID  string `json:"device_id"`
	Assertion string `json:"assertion"`
}

func (s *Server) handleDeviceLogin(w http.ResponseWriter, r *http.Request) {
	var req deviceLoginReq
	if _, err := readJSON(r, &req); err != nil {
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.DeviceID == "" || len(req.DeviceID) > 128 {
		writeErr(w, http.StatusBadRequest, "invalid device_id")
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
	// MVP: accept any non-empty assertion from signed app builds; App Attest later.
	if strings.TrimSpace(req.Assertion) == "" {
		writeErr(w, http.StatusBadRequest, "assertion required")
		return
	}
	p, err := s.Store.CreatePendingLogin(acc.ID, req.DeviceID, req.Assertion, s.Cfg.PendingTTL)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "pending failed")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"pending_id": p.ID,
		"status":     "pending",
		"expires_at": p.ExpiresAt.Format(time.RFC3339),
		"release_url": s.Cfg.BaseURL + "/release.html?pending_id=" + p.ID,
	})
}

func (s *Server) handleDeviceLoginPoll(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
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
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
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
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
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
		if errors.Is(err, auth.ErrPIIRejected) {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, "invalid json")
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
	recip, err := s.Store.GetAccountByUsername(req.ToUsername)
	if err != nil || !recip.Active {
		writeErr(w, http.StatusNotFound, "recipient not found")
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
			"id":              m.ID,
			"from_username":   m.SenderUsername,
			"ciphertext":      store.CiphertextB64(m.Ciphertext),
			"created_at":      m.CreatedAt.Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": out})
}
