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
	key, err := GenerateTOTP("T9", "alice_user")
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
