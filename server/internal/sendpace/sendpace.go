package sendpace

import (
	"context"
	"sync"
	"time"
)

// DefaultInterval is the SMS-paced gap between accepted sends per account.
const DefaultInterval = 1500 * time.Millisecond

// Gate enforces at most one in-flight send per account and a minimum spacing
// between send starts. Callers should Hold() after Begin succeeds, then End.
type Gate struct {
	mu       sync.Mutex
	inflight map[string]bool
	last     map[string]time.Time
	interval time.Duration
	now      func() time.Time
	sleep    func(context.Context, time.Duration) error
}

// New builds a gate. interval <= 0 disables spacing (still serializes in-flight).
func New(interval time.Duration) *Gate {
	return &Gate{
		inflight: make(map[string]bool),
		last:     make(map[string]time.Time),
		interval: interval,
		now:      time.Now,
		sleep: func(ctx context.Context, d time.Duration) error {
			t := time.NewTimer(d)
			defer t.Stop()
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-t.C:
				return nil
			}
		},
	}
}

// Begin reserves a send slot for accountID. On failure, retryAfter is how long
// the client should wait before trying again.
func (g *Gate) Begin(accountID string) (retryAfter time.Duration, ok bool) {
	if g == nil || accountID == "" {
		return 0, true
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	if g.inflight[accountID] {
		ra := g.interval
		if ra <= 0 {
			ra = DefaultInterval
		}
		if t, ok := g.last[accountID]; ok && g.interval > 0 {
			if left := g.interval - now.Sub(t); left > 0 {
				ra = left
			}
		}
		return ra, false
	}
	if g.interval > 0 {
		if t, ok := g.last[accountID]; ok {
			elapsed := now.Sub(t)
			if elapsed < g.interval {
				return g.interval - elapsed, false
			}
		}
	}
	g.inflight[accountID] = true
	g.last[accountID] = now
	return 0, true
}

// Hold sleeps for the gate interval (SMS pacing). No-op when interval <= 0.
func (g *Gate) Hold(ctx context.Context) error {
	if g == nil || g.interval <= 0 {
		return nil
	}
	return g.sleep(ctx, g.interval)
}

// End releases the in-flight slot. Spacing still uses last from Begin.
func (g *Gate) End(accountID string) {
	if g == nil || accountID == "" {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.inflight, accountID)
}
