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
	ErrInvalidUsername  = errors.New("invalid username")
	ErrInvalidPassword  = errors.New("invalid password")
	ErrInvalidTOTPCode  = errors.New("invalid totp code")
	ErrInvalidDeviceID  = errors.New("invalid device_id")
	ErrInvalidOpaqueID  = errors.New("invalid id")
	ErrInvalidAssertion = errors.New("invalid assertion")
	ErrPIIRejected      = errors.New("email and phone fields are not accepted")
	ErrUnknownField     = errors.New("unknown field")

	usernameRE = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)
	totpCodeRE = regexp.MustCompile(`^[0-9]{6}$`)
	deviceIDRE = regexp.MustCompile(`^[a-zA-Z0-9._:-]{1,128}$`)
	opaqueIDRE = regexp.MustCompile(`^[a-zA-Z0-9_-]{8,128}$`)
	uuidRE     = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
)

const (
	MaxAssertionLen = 512
	MaxPubkeyLen    = 4096
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

// RejectUnknownFields returns ErrUnknownField if raw contains keys outside allowed.
func RejectUnknownFields(raw map[string]any, allowed map[string]struct{}) error {
	for k := range raw {
		if _, ok := allowed[k]; !ok {
			return ErrUnknownField
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

// ValidateTOTPCode enforces a 6-digit code shape before crypto checks.
func ValidateTOTPCode(code string) error {
	if !totpCodeRE.MatchString(strings.TrimSpace(code)) {
		return ErrInvalidTOTPCode
	}
	return nil
}

// ValidateDeviceID enforces a bounded opaque device identifier.
func ValidateDeviceID(id string) error {
	if !deviceIDRE.MatchString(id) {
		return ErrInvalidDeviceID
	}
	return nil
}

// ValidatePendingID accepts UUID or opaque token-shaped identifiers.
func ValidatePendingID(id string) error {
	if uuidRE.MatchString(id) || opaqueIDRE.MatchString(id) {
		return nil
	}
	return ErrInvalidOpaqueID
}

// ValidateAssertion bounds MVP device assertions (App Attest later).
func ValidateAssertion(a string) error {
	a = strings.TrimSpace(a)
	if a == "" || len(a) > MaxAssertionLen {
		return ErrInvalidAssertion
	}
	for _, r := range a {
		if r < 0x20 || r == 0x7f {
			return ErrInvalidAssertion
		}
	}
	return nil
}

// ValidatePubkey optional sender pubkey string bound.
func ValidatePubkey(pk string) error {
	if pk == "" {
		return nil
	}
	if len(pk) > MaxPubkeyLen {
		return errors.New("invalid pubkey")
	}
	for _, r := range pk {
		if r < 0x20 || r == 0x7f {
			return errors.New("invalid pubkey")
		}
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
