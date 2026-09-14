package crypto

import (
	"testing"
)

func TestSealOpenRoundTrip(t *testing.T) {
	key := DeriveAESKey([]byte("test-master-key-32b!!!!!!!!"), "col")
	pt := []byte("hello secret")
	sealed, err := Seal(key, pt, []byte("aad"))
	if err != nil {
		t.Fatal(err)
	}
	out, err := Open(key, sealed, []byte("aad"))
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != string(pt) {
		t.Fatalf("got %q", out)
	}
}

func TestSealFileRoundTrip(t *testing.T) {
	master := []byte("sixteen-byte-key!")
	pt := []byte("SQLite format 3\x00fake")
	sealed, err := SealFile(master, pt)
	if err != nil {
		t.Fatal(err)
	}
	out, err := OpenFile(master, sealed)
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != string(pt) {
		t.Fatal("mismatch")
	}
	if _, err := OpenFile([]byte("wrong-key-xxxxxxxx"), sealed); err == nil {
		t.Fatal("expected failure with wrong key")
	}
}

func TestPasswordHash(t *testing.T) {
	h, err := HashPassword("correct horse")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword(h, "correct horse") {
		t.Fatal("verify failed")
	}
	if VerifyPassword(h, "wrong") {
		t.Fatal("should fail")
	}
}
