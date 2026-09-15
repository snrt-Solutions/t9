package auth

import (
	"bytes"
	"encoding/base64"
	"image/png"
	"strings"
	"testing"
)

func TestGraphemeCount(t *testing.T) {
	if GraphemeCount("hi") != 2 {
		t.Fatal()
	}
	if GraphemeCount("👨‍👩‍👧‍👦") < 1 {
		t.Fatal()
	}
	s := ""
	for i := 0; i < 160; i++ {
		s += "a"
	}
	if GraphemeCount(s) != 160 {
		t.Fatal(GraphemeCount(s))
	}
}

func TestTOTPQRDataURL(t *testing.T) {
	key, err := GenerateTOTP("AeSMS", "alice_user")
	if err != nil {
		t.Fatal(err)
	}
	dataURL, err := TOTPQRDataURL(key.URL())
	if err != nil {
		t.Fatal(err)
	}
	const prefix = "data:image/png;base64,"
	if !strings.HasPrefix(dataURL, prefix) {
		t.Fatalf("prefix: %q", dataURL[:min(40, len(dataURL))])
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(dataURL, prefix))
	if err != nil {
		t.Fatal(err)
	}
	img, err := png.Decode(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if img.Bounds().Dx() < 160 || img.Bounds().Dy() < 160 {
		t.Fatalf("QR too small to scan: %v", img.Bounds())
	}
}

func TestValidateUsername(t *testing.T) {
	if ValidateUsername("ab") == nil {
		t.Fatal("too short")
	}
	if ValidateUsername("good_user") != nil {
		t.Fatal()
	}
	if RejectPIIFields(map[string]any{"email": "x"}) == nil {
		t.Fatal()
	}
}

func TestValidateFields(t *testing.T) {
	if ValidateTOTPCode("12345") == nil || ValidateTOTPCode("123456") != nil {
		t.Fatal("totp shape")
	}
	if ValidateDeviceID("") == nil || ValidateDeviceID("dev-1") != nil {
		t.Fatal("device id")
	}
	if ValidatePendingID("not") == nil {
		t.Fatal("pending too short")
	}
	if ValidatePendingID("550e8400-e29b-41d4-a716-446655440000") != nil {
		t.Fatal("uuid pending")
	}
	if ValidateAssertion("") == nil || ValidateAssertion("ok") != nil {
		t.Fatal("assertion")
	}
	if RejectUnknownFields(map[string]any{"x": 1}, map[string]struct{}{"y": {}}) == nil {
		t.Fatal("unknown field")
	}
}
