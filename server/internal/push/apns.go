package push

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// APNs sends alert pushes when credentials are configured.
type APNs struct {
	keyID    string
	teamID   string
	bundle   string
	prod     bool
	key      *ecdsa.PrivateKey
	mu       sync.Mutex
	jwt      string
	jwtUntil time.Time
	client   *http.Client
}

func NewAPNs(keyID, teamID, keyPath, bundle string, prod bool) (*APNs, error) {
	if keyID == "" || teamID == "" || keyPath == "" {
		return nil, nil
	}
	raw, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("apns: invalid pem")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("apns: not ecdsa key")
	}
	return &APNs{
		keyID:  keyID,
		teamID: teamID,
		bundle: bundle,
		prod:   prod,
		key:    key,
		client: &http.Client{Timeout: 10 * time.Second},
	}, nil
}

func (a *APNs) token() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.jwt != "" && time.Now().Before(a.jwtUntil) {
		return a.jwt, nil
	}
	now := time.Now()
	t := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": a.teamID,
		"iat": now.Unix(),
	})
	t.Header["kid"] = a.keyID
	s, err := t.SignedString(a.key)
	if err != nil {
		return "", err
	}
	a.jwt = s
	a.jwtUntil = now.Add(50 * time.Minute)
	return s, nil
}

func (a *APNs) Notify(deviceToken string) {
	if a == nil || deviceToken == "" {
		return
	}
	tok, err := a.token()
	if err != nil {
		log.Printf("apns token: %v", err)
		return
	}
	host := "https://api.sandbox.push.apple.com"
	if a.prod {
		host = "https://api.push.apple.com"
	}
	body := []byte(`{"aps":{"alert":{"title":"T-9","body":"New message"},"sound":"default"}}`)
	req, err := http.NewRequest(http.MethodPost, host+"/3/device/"+deviceToken, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("authorization", "bearer "+tok)
	req.Header.Set("apns-topic", a.bundle)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	res, err := a.client.Do(req)
	if err != nil {
		log.Printf("apns send: %v", err)
		return
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 512))
		log.Printf("apns status %d: %s", res.StatusCode, b)
	}
}
