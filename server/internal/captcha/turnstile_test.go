package captcha

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestVerifySuccessAndFail(t *testing.T) {
	okSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":true}`))
	}))
	t.Cleanup(okSrv.Close)

	v := &Turnstile{Secret: "test-secret", VerifyURL: okSrv.URL, Client: okSrv.Client()}
	if err := v.Verify(context.Background(), "token", "1.1.1.1"); err != nil {
		t.Fatal(err)
	}
	if err := v.Verify(context.Background(), "", ""); err != ErrMissingToken {
		t.Fatalf("missing: %v", err)
	}

	failSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":false}`))
	}))
	t.Cleanup(failSrv.Close)
	v.VerifyURL = failSrv.URL
	v.Client = failSrv.Client()
	if err := v.Verify(context.Background(), "bad", ""); err != ErrFailed {
		t.Fatalf("fail: %v", err)
	}
}

func TestDisabledSkips(t *testing.T) {
	var v *Turnstile
	if v.Enabled() {
		t.Fatal()
	}
	if err := (*Turnstile)(nil).Verify(context.Background(), "", ""); err != nil {
		t.Fatal(err)
	}
}
