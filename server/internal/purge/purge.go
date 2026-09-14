package purge

import (
	"context"
	"log"
	"time"

	"github.com/t9-messenger/t9/server/internal/store"
)

// Runner periodically deletes expired messages and pending logins.
type Runner struct {
	Store    *store.Store
	Interval time.Duration
}

func (r *Runner) Start(ctx context.Context) {
	t := time.NewTicker(r.Interval)
	defer t.Stop()
	r.tick()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.tick()
		}
	}
}

func (r *Runner) tick() {
	n, err := r.Store.PurgeExpired(time.Now().UTC())
	if err != nil {
		log.Printf("purge: %v", err)
		return
	}
	if n > 0 {
		log.Printf("purge: removed %d expired messages", n)
	}
}
