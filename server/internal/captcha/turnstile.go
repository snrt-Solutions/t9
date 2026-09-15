package captcha

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const defaultVerifyURL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

var (
	ErrMissingToken = errors.New("captcha required")
	ErrFailed       = errors.New("captcha failed")
)

// Turnstile verifies Cloudflare Turnstile tokens server-side.
type Turnstile struct {
	Secret    string
	VerifyURL string
	Client    *http.Client
}

// Enabled reports whether verification is configured.
func (t *Turnstile) Enabled() bool {
	return t != nil && strings.TrimSpace(t.Secret) != ""
}

// Verify checks a browser token. remoteIP may be empty.
func (t *Turnstile) Verify(ctx context.Context, token, remoteIP string) error {
	if !t.Enabled() {
		return nil
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return ErrMissingToken
	}
	form := url.Values{}
	form.Set("secret", t.Secret)
	form.Set("response", token)
	if remoteIP != "" {
		form.Set("remoteip", remoteIP)
	}
	verifyURL := t.VerifyURL
	if verifyURL == "" {
		verifyURL = defaultVerifyURL
	}
	client := t.Client
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, verifyURL, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrFailed, err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("%w: %v", ErrFailed, err)
	}
	var out struct {
		Success bool `json:"success"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return fmt.Errorf("%w: bad response", ErrFailed)
	}
	if !out.Success {
		return ErrFailed
	}
	return nil
}
