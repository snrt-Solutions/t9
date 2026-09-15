package ratelimit

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Class groups routes that share a budget.
type Class string

const (
	ClassAuthHeavy Class = "auth_heavy"
	ClassAuthLight Class = "auth_light"
	ClassMailbox   Class = "mailbox"
	ClassGlobal    Class = "global"
)

// Limit is a token-bucket budget.
type Limit struct {
	Rate  float64 // tokens per second
	Burst int
}

// Defaults are hard enough to blunt Argon2 floods while remaining usable for a single operator node.
func Defaults() map[Class]Limit {
	return map[Class]Limit{
		ClassAuthHeavy: {Rate: 5.0 / 60.0, Burst: 5},   // ~5/min
		ClassAuthLight: {Rate: 30.0 / 60.0, Burst: 15}, // ~30/min
		ClassMailbox:   {Rate: 60.0 / 60.0, Burst: 30}, // ~60/min
		ClassGlobal:    {Rate: 120.0 / 60.0, Burst: 60},
	}
}

type bucket struct {
	tokens float64
	last   time.Time
}

// Limiter is an in-process per-source token bucket set.
type Limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	limits  map[Class]Limit
	now     func() time.Time
}

// New builds a limiter. Empty limits use Defaults().
func New(limits map[Class]Limit) *Limiter {
	if limits == nil {
		limits = Defaults()
	}
	return &Limiter{
		buckets: make(map[string]*bucket),
		limits:  limits,
		now:     time.Now,
	}
}

// Allow reports whether source may consume one token of class.
func (l *Limiter) Allow(source string, class Class) bool {
	if l == nil {
		return true
	}
	lim, ok := l.limits[class]
	if !ok || lim.Burst <= 0 || lim.Rate <= 0 {
		return true
	}
	key := string(class) + "|" + source
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()
	b, ok := l.buckets[key]
	if !ok {
		l.buckets[key] = &bucket{tokens: float64(lim.Burst - 1), last: now}
		return true
	}
	elapsed := now.Sub(b.last).Seconds()
	if elapsed > 0 {
		b.tokens += elapsed * lim.Rate
		if b.tokens > float64(lim.Burst) {
			b.tokens = float64(lim.Burst)
		}
		b.last = now
	}
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// ClientIP returns CF-Connecting-IP when the peer is private/local (Tunnel/proxy hop), else RemoteAddr.
func ClientIP(r *http.Request) string {
	host := remoteHost(r.RemoteAddr)
	if cf := strings.TrimSpace(r.Header.Get("CF-Connecting-IP")); cf != "" && isTrustedProxy(host) {
		if ip := net.ParseIP(cf); ip != nil {
			return cf
		}
	}
	return host
}

func remoteHost(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}

func isTrustedProxy(host string) bool {
	ip := net.ParseIP(host)
	if ip == nil {
		return host == "localhost"
	}
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast()
}

// Classify maps method+path to a rate class (global is always applied separately).
func Classify(method, path string) Class {
	switch {
	case method == http.MethodPost && path == "/v1/accounts":
		return ClassAuthHeavy
	case method == http.MethodPost && path == "/v1/device/login":
		return ClassAuthHeavy
	case method == http.MethodPost && path == "/v1/device/release":
		return ClassAuthHeavy
	case method == http.MethodPost && path == "/v1/accounts/totp/confirm":
		return ClassAuthLight
	case method == http.MethodPost && path == "/v1/accounts/abandon":
		return ClassAuthLight
	case method == http.MethodGet && strings.HasPrefix(path, "/v1/device/login/"):
		return ClassAuthLight
	case method == http.MethodPost && path == "/v1/device/revoke":
		return ClassAuthLight
	case path == "/v1/messages" || path == "/v1/events" || path == "/v1/device/push-token":
		return ClassMailbox
	default:
		return ClassGlobal
	}
}

// Middleware enforces global + class budgets before the next handler.
func (l *Limiter) Middleware(next http.Handler) http.Handler {
	if l == nil {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/v1/") {
			next.ServeHTTP(w, r)
			return
		}
		src := ClientIP(r)
		if !l.Allow(src, ClassGlobal) {
			writeLimited(w)
			return
		}
		class := Classify(r.Method, r.URL.Path)
		if class != ClassGlobal && !l.Allow(src, class) {
			writeLimited(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeLimited(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Retry-After", "60")
	w.WriteHeader(http.StatusTooManyRequests)
	_, _ = w.Write([]byte(`{"error":"rate limit exceeded"}` + "\n"))
}
