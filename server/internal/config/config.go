package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/aesms-io/aesms/server/internal/setup"
)

// Config holds process configuration from env + optional /data setup file.
type Config struct {
	Listen  string
	DataDir string
	BaseURL string
	DBKey   []byte

	PendingTTL  time.Duration
	MessageTTL  time.Duration
	EnrollTTL   time.Duration
	PurgeEvery  time.Duration
	TokenBytes  int
	Fingerprint string

	// SetupNeeded means mailbox is offline until the operator finishes /setup.html.
	SetupNeeded bool

	// Optional APNs (HTTP/2 token auth). Empty = skip remote push.
	APNsKeyID   string
	APNsTeamID  string
	APNsKeyPath string
	APNsBundle  string
	APNsProd    bool

	// Cloudflare Turnstile (empty secret = skip captcha; for local/dev).
	TurnstileSiteKey string
	TurnstileSecret  string

	// RateLimitDisabled turns off in-process per-source limits (tests / deliberate opt-out).
	RateLimitDisabled bool
}

// Load merges environment with aesms.setup.json in the data directory.
// If no DB key is available yet, SetupNeeded is true and the process can still serve the setup UI.
func Load() (*Config, error) {
	listen := envOr("AESMS_LISTEN", ":8080")
	data := envOr("AESMS_DATA", "./data")
	_ = os.MkdirAll(data, 0o700)

	sf, _ := setup.Load(data)
	key := os.Getenv("AESMS_DB_KEY")
	base := os.Getenv("AESMS_BASE_URL")
	if sf != nil {
		if key == "" && sf.DBKey != "" {
			key = sf.DBKey
		}
		if base == "" && sf.BaseURL != "" {
			base = sf.BaseURL
		}
	}
	if base == "" {
		base = "http://127.0.0.1" + listen
	}
	base = strings.TrimRight(base, "/")

	cfg := &Config{
		Listen:      listen,
		DataDir:     data,
		BaseURL:     base,
		PendingTTL:  15 * time.Minute,
		MessageTTL:  24 * time.Hour,
		EnrollTTL:   15 * time.Minute,
		PurgeEvery:  time.Minute,
		TokenBytes:  32,
		APNsKeyID:   os.Getenv("AESMS_APNS_KEY_ID"),
		APNsTeamID:  os.Getenv("AESMS_APNS_TEAM_ID"),
		APNsKeyPath: os.Getenv("AESMS_APNS_KEY_PATH"),
		APNsBundle:  envOr("AESMS_APNS_BUNDLE_ID", "io.aesms.app"),
		APNsProd:    os.Getenv("AESMS_APNS_PRODUCTION") == "1",

		TurnstileSiteKey:  strings.TrimSpace(os.Getenv("AESMS_TURNSTILE_SITE_KEY")),
		TurnstileSecret:   strings.TrimSpace(os.Getenv("AESMS_TURNSTILE_SECRET")),
		RateLimitDisabled: os.Getenv("AESMS_RATE_LIMIT_DISABLED") == "1",
	}

	if len(key) < 16 {
		cfg.SetupNeeded = true
		return cfg, nil
	}
	cfg.DBKey = []byte(key)
	return cfg, nil
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func (c *Config) ValidateMailbox() error {
	if len(c.DBKey) < 16 {
		return fmt.Errorf("database key not configured — open /setup.html")
	}
	return nil
}
