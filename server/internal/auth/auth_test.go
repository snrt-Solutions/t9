package auth

import "testing"

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
