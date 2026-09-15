package ratelimit

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestAllowBurstThenBlock(t *testing.T) {
	l := New(map[Class]Limit{
		ClassAuthHeavy: {Rate: 0.001, Burst: 2},
		ClassGlobal:    {Rate: 100, Burst: 100},
	})
	src := "1.2.3.4"
	if !l.Allow(src, ClassAuthHeavy) || !l.Allow(src, ClassAuthHeavy) {
		t.Fatal("burst should allow")
	}
	if l.Allow(src, ClassAuthHeavy) {
		t.Fatal("expected block")
	}
}

func TestClientIPFromCFWhenPrivatePeer(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "172.18.0.2:1234"
	r.Header.Set("CF-Connecting-IP", "203.0.113.9")
	if got := ClientIP(r); got != "203.0.113.9" {
		t.Fatalf("got %q", got)
	}
	r2 := httptest.NewRequest(http.MethodGet, "/", nil)
	r2.RemoteAddr = "198.51.100.1:9"
	r2.Header.Set("CF-Connecting-IP", "203.0.113.9")
	if got := ClientIP(r2); got != "198.51.100.1" {
		t.Fatalf("untrusted peer must ignore CF header, got %q", got)
	}
}

func TestClassify(t *testing.T) {
	if Classify(http.MethodPost, "/v1/accounts") != ClassAuthHeavy {
		t.Fatal()
	}
	if Classify(http.MethodPost, "/v1/accounts/totp/confirm") != ClassAuthLight {
		t.Fatal()
	}
	if Classify(http.MethodGet, "/v1/messages") != ClassMailbox {
		t.Fatal()
	}
}

func TestMiddleware429(t *testing.T) {
	l := New(map[Class]Limit{
		ClassAuthHeavy: {Rate: 0.001, Burst: 1},
		ClassGlobal:    {Rate: 100, Burst: 100},
	})
	h := l.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	req := httptest.NewRequest(http.MethodPost, "/v1/accounts", nil)
	req.RemoteAddr = "10.0.0.1:1"
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusNoContent {
		t.Fatalf("first: %d", rr.Code)
	}
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("second: %d", rr.Code)
	}
	if rr.Header().Get("Retry-After") == "" {
		t.Fatal("missing Retry-After")
	}
	_ = time.Second
}
