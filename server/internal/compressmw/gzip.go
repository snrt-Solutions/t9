package compressmw

import (
	"compress/gzip"
	"io"
	"net/http"
	"strings"
	"sync"
)

var gzipPool = sync.Pool{
	New: func() any {
		w, _ := gzip.NewWriterLevel(io.Discard, gzip.BestSpeed)
		return w
	},
}

// Middleware gzip-compresses responses when the client accepts it.
// Skips SSE and already-encoded responses. Prefer small sealed payloads;
// this mainly shrinks JSON envelopes and static HTML/JS.
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead ||
			!strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") ||
			strings.HasPrefix(r.URL.Path, "/v1/events") {
			next.ServeHTTP(w, r)
			return
		}
		gw := &gzipWriter{ResponseWriter: w}
		defer gw.Close()
		next.ServeHTTP(gw, r)
	})
}

type gzipWriter struct {
	http.ResponseWriter
	gz     *gzip.Writer
	wrote  bool
	skip   bool
}

func (g *gzipWriter) WriteHeader(status int) {
	if g.wrote {
		return
	}
	g.wrote = true
	if g.Header().Get("Content-Encoding") != "" {
		g.skip = true
		g.ResponseWriter.WriteHeader(status)
		return
	}
	ct := g.Header().Get("Content-Type")
	if ct != "" && !compressible(ct) {
		g.skip = true
		g.ResponseWriter.WriteHeader(status)
		return
	}
	g.Header().Del("Content-Length")
	g.Header().Set("Content-Encoding", "gzip")
	g.Header().Add("Vary", "Accept-Encoding")
	g.ResponseWriter.WriteHeader(status)
	gz := gzipPool.Get().(*gzip.Writer)
	gz.Reset(g.ResponseWriter)
	g.gz = gz
}

func (g *gzipWriter) Write(b []byte) (int, error) {
	if !g.wrote {
		g.WriteHeader(http.StatusOK)
	}
	if g.skip || g.gz == nil {
		return g.ResponseWriter.Write(b)
	}
	return g.gz.Write(b)
}

func (g *gzipWriter) Close() {
	if g.gz != nil {
		_ = g.gz.Close()
		gzipPool.Put(g.gz)
		g.gz = nil
	}
}

func compressible(ct string) bool {
	ct = strings.ToLower(ct)
	switch {
	case strings.Contains(ct, "application/json"),
		strings.Contains(ct, "text/"),
		strings.Contains(ct, "javascript"),
		strings.Contains(ct, "xml"),
		strings.Contains(ct, "svg"):
		return true
	default:
		return false
	}
}
