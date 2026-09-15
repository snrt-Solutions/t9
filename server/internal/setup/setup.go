package setup

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const (
	FileName   = "aesms.setup.json"
	TunnelFile = "cloudflare.token"
)

// File is persisted under AESMS_DATA so operators never edit host files.
type File struct {
	BaseURL     string `json:"base_url"`
	DBKey       string `json:"db_key"`
	TunnelToken string `json:"tunnel_token,omitempty"`
	Configured  bool   `json:"configured"`
}

func Path(dataDir string) string {
	return filepath.Join(dataDir, FileName)
}

func TunnelPath(dataDir string) string {
	return filepath.Join(dataDir, TunnelFile)
}

func Load(dataDir string) (*File, error) {
	b, err := os.ReadFile(Path(dataDir))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return &File{}, nil
		}
		return nil, err
	}
	var f File
	if err := json.Unmarshal(b, &f); err != nil {
		return nil, err
	}
	return &f, nil
}

func Save(dataDir string, f *File) error {
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return err
	}
	f.Configured = len(f.DBKey) >= 16 && strings.TrimSpace(f.BaseURL) != ""
	b, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	tmp := Path(dataDir) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, Path(dataDir)); err != nil {
		return err
	}
	tok := strings.TrimSpace(f.TunnelToken)
	tp := TunnelPath(dataDir)
	if tok == "" {
		_ = os.Remove(tp)
		return nil
	}
	return os.WriteFile(tp, []byte(tok+"\n"), 0o600)
}

func GenerateDBKey() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func Ready(dataDir string, envKey string) bool {
	if len(envKey) >= 16 {
		return true
	}
	f, err := Load(dataDir)
	if err != nil || f == nil {
		return false
	}
	return f.Configured && len(f.DBKey) >= 16
}
