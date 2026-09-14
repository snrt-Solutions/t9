package config

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// Config holds process configuration from the environment.
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
	Fingerprint string // set after store open from server identity
}

// Load reads required env vars. T9_DB_KEY must be at least 16 characters.
func Load() (*Config, error) {
	key := os.Getenv("T9_DB_KEY")
	if len(key) < 16 {
		return nil, fmt.Errorf("T9_DB_KEY must be set and at least 16 characters")
	}
	listen := envOr("T9_LISTEN", ":8080")
	data := envOr("T9_DATA", "./data")
	base := strings.TrimRight(envOr("T9_BASE_URL", "http://127.0.0.1"+listen), "/")

	return &Config{
		Listen:     listen,
		DataDir:    data,
		BaseURL:    base,
		DBKey:      []byte(key),
		PendingTTL: 15 * time.Minute,
		MessageTTL: 24 * time.Hour,
		EnrollTTL:  15 * time.Minute,
		PurgeEvery: time.Minute,
		TokenBytes: 32,
	}, nil
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
