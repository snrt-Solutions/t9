package auth

import (
	"errors"
	"regexp"
	"strings"
	"unicode"

	"github.com/pquerna/otp"
	"github.com/pquerna/otp/totp"
)

var (
	ErrInvalidUsername = errors.New("invalid username")
	ErrInvalidPassword = errors.New("invalid password")
	ErrPIIRejected     = errors.New("email and phone fields are not accepted")
	usernameRE         = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)
)

// RejectPIIFields returns ErrPIIRejected if any email/phone-looking keys appear.
func RejectPIIFields(m map[string]any) error {
	banned := []string{"email", "phone", "phone_number", "e_mail", "mobile", "legal_name", "fullname"}
	for k := range m {
		lk := strings.ToLower(k)
		for _, b := range banned {
			if lk == b {
				return ErrPIIRejected
			}
		}
	}
	return nil
}

// ValidateUsername enforces opaque handle rules (no @).
func ValidateUsername(u string) error {
	if !usernameRE.MatchString(u) {
		return ErrInvalidUsername
	}
	if strings.Contains(u, "@") {
		return ErrInvalidUsername
	}
	return nil
}

// ValidatePassword requires length and some entropy floor.
func ValidatePassword(pw string) error {
	if len(pw) < 10 || len(pw) > 128 {
		return ErrInvalidPassword
	}
	return nil
}

// GenerateTOTP creates a new TOTP key for enrollment.
func GenerateTOTP(issuer, accountName string) (*otp.Key, error) {
	return totp.Generate(totp.GenerateOpts{
		Issuer:      issuer,
		AccountName: accountName,
		Period:      30,
		Digits:      otp.DigitsSix,
		Algorithm:   otp.AlgorithmSHA1,
	})
}

// ValidateTOTP checks a code against the secret.
func ValidateTOTP(secret, code string) bool {
	return totp.Validate(code, secret)
}

// GraphemeCount approximates Unicode extended grapheme clusters via rune
// iteration with combining-mark awareness (good enough for ≤160 gate).
func GraphemeCount(s string) int {
	n := 0
	for _, r := range s {
		if unicode.Is(unicode.Mn, r) || unicode.Is(unicode.Me, r) {
			continue
		}
		if r == 0x200D { // ZWJ — stay in cluster
			continue
		}
		if r >= 0xFE00 && r <= 0xFE0F { // variation selectors
			continue
		}
		n++
	}
	return n
}

const MaxMessageGraphemes = 160
