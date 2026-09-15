package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/hkdf"
)

const (
	fileMagic       = "AESMS1\n"
	fileMagicLegacy = "T9DB1\n"
	fileHKDF        = "aesms-db-file-v1"
	fileHKDFLegacy  = "t9-db-file-v1"
	ColumnHKDF      = "aesms-column-v1"
	ColumnHKDFLegacy = "t9-column-v1"
)

// DeriveAESKey expands master into a 32-byte AES key using HKDF-SHA256.
func DeriveAESKey(master []byte, info string) []byte {
	h := hkdf.New(sha256.New, master, nil, []byte(info))
	out := make([]byte, 32)
	if _, err := io.ReadFull(h, out); err != nil {
		panic(err)
	}
	return out
}

// Seal encrypts plaintext with AES-256-GCM. Output is nonce||ciphertext||tag.
func Seal(key, plaintext, aad []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, plaintext, aad), nil
}

// Open decrypts output from Seal.
func Open(key, sealed, aad []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(sealed) < gcm.NonceSize() {
		return nil, errors.New("ciphertext too short")
	}
	nonce, ct := sealed[:gcm.NonceSize()], sealed[gcm.NonceSize():]
	return gcm.Open(nil, nonce, ct, aad)
}

// SealFile wraps a whole SQLite file for at-rest storage (current format only).
func SealFile(master, plaintext []byte) ([]byte, error) {
	key := DeriveAESKey(master, fileHKDF)
	sealed, err := Seal(key, plaintext, []byte(fileMagic))
	if err != nil {
		return nil, err
	}
	out := make([]byte, 0, len(fileMagic)+len(sealed))
	out = append(out, fileMagic...)
	out = append(out, sealed...)
	return out, nil
}

// OpenFile unwraps SealFile output. Also accepts legacy pre-rename seals.
func OpenFile(master, sealedFile []byte) ([]byte, error) {
	type attempt struct {
		magic string
		info  string
	}
	for _, a := range []attempt{
		{fileMagic, fileHKDF},
		{fileMagicLegacy, fileHKDFLegacy},
	} {
		if len(sealedFile) < len(a.magic) || string(sealedFile[:len(a.magic)]) != a.magic {
			continue
		}
		key := DeriveAESKey(master, a.info)
		plain, err := Open(key, sealedFile[len(a.magic):], []byte(a.magic))
		if err == nil {
			return plain, nil
		}
	}
	return nil, errors.New("invalid sealed database magic")
}

// HashPassword returns argon2id encoded hash.
func HashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	const timeCost = 3
	const memory = 64 * 1024
	const threads = 4
	const keyLen = 32
	hash := argon2.IDKey([]byte(password), salt, timeCost, memory, threads, keyLen)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		memory, timeCost, threads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

// VerifyPassword checks password against HashPassword output.
func VerifyPassword(encoded, password string) bool {
	if !strings.HasPrefix(encoded, "$argon2id$v=19$") {
		return false
	}
	parts := strings.Split(encoded, "$")
	// "", "argon2id", "v=19", "m=...,t=...,p=...", salt, hash
	if len(parts) != 6 {
		return false
	}
	var memory, timeCost uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &timeCost, &threads); err != nil {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(password), salt, timeCost, memory, threads, uint32(len(want)))
	if len(got) != len(want) {
		return false
	}
	var v byte
	for i := range got {
		v |= got[i] ^ want[i]
	}
	return v == 0
}

// RandomToken returns URL-safe base64 random bytes.
func RandomToken(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// HashToken SHA-256 hex of token for storage.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return fmt.Sprintf("%x", sum[:])
}

// FingerprintHex returns first 16 hex chars of SHA-256 of material.
func FingerprintHex(material []byte) string {
	sum := sha256.Sum256(material)
	return fmt.Sprintf("%x", sum[:8])
}
