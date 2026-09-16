package compressmw_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/aesms-io/aesms/server/internal/compressmw"
)

func TestGzipJSON(t *testing.T) {
	h := compressmw.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"ok":true,"pad":"`+strings.Repeat("x", 2000)+`"}`)
	}))
	req := httptest.NewRequest(http.MethodGet, "/v1/info", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != 200 {
		t.Fatalf("status %d", rr.Code)
	}
	if rr.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("expected gzip, got %q", rr.Header().Get("Content-Encoding"))
	}
	if rr.Body.Len() >= 2000 {
		t.Fatalf("expected compressed body smaller than plaintext, got %d", rr.Body.Len())
	}
}

func TestGzipSkipsSSE(t *testing.T) {
	h := compressmw.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(w, "data: hi\n\n")
	}))
	req := httptest.NewRequest(http.MethodGet, "/v1/events", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Header().Get("Content-Encoding") == "gzip" {
		t.Fatal("SSE must not be gzip-wrapped")
	}
}
