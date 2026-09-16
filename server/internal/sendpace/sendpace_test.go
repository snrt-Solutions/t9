package sendpace

import (
	"context"
	"testing"
	"time"
)

func TestBeginSpacing(t *testing.T) {
	g := New(1500 * time.Millisecond)
	now := time.Unix(0, 0)
	g.now = func() time.Time { return now }

	if _, ok := g.Begin("a"); !ok {
		t.Fatal("first begin")
	}
	if ra, ok := g.Begin("a"); ok || ra <= 0 {
		t.Fatalf("in-flight should block, ra=%v ok=%v", ra, ok)
	}
	g.End("a")

	if ra, ok := g.Begin("a"); ok || ra != 1500*time.Millisecond {
		t.Fatalf("want blocked 1.5s, ra=%v ok=%v", ra, ok)
	}

	now = now.Add(1500 * time.Millisecond)
	if _, ok := g.Begin("a"); !ok {
		t.Fatal("after interval")
	}
	g.End("a")
}

func TestHoldRespectsContext(t *testing.T) {
	g := New(time.Hour)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := g.Hold(ctx); err == nil {
		t.Fatal("expected cancel")
	}
}

func TestZeroInterval(t *testing.T) {
	g := New(0)
	if _, ok := g.Begin("a"); !ok {
		t.Fatal("begin")
	}
	if err := g.Hold(context.Background()); err != nil {
		t.Fatal(err)
	}
	g.End("a")
	if _, ok := g.Begin("a"); !ok {
		t.Fatal("second begin with zero interval")
	}
	g.End("a")
}
