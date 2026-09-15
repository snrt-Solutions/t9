package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aesms-io/aesms/server/internal/api"
	"github.com/aesms-io/aesms/server/internal/config"
	"github.com/aesms-io/aesms/server/internal/purge"
	"github.com/aesms-io/aesms/server/internal/push"
	"github.com/aesms-io/aesms/server/internal/store"
	"github.com/aesms-io/aesms/server/internal/webembed"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	hub := push.NewHub()
	apns, err := push.NewAPNs(cfg.APNsKeyID, cfg.APNsTeamID, cfg.APNsKeyPath, cfg.APNsBundle, cfg.APNsProd)
	if err != nil {
		log.Printf("apns disabled: %v", err)
	}

	var st *store.Store
	if !cfg.SetupNeeded {
		st, err = store.Open(cfg.DataDir, cfg.DBKey)
		if err != nil {
			log.Fatalf("store: %v", err)
		}
		defer func() {
			if err := st.Close(); err != nil {
				log.Printf("store close: %v", err)
			}
		}()
		cfg.Fingerprint = st.Fingerprint()
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if st != nil {
		go (&purge.Runner{Store: st, Interval: cfg.PurgeEvery}).Start(ctx)
	}

	srvAPI := api.New(cfg, st, webembed.Handler(), hub, apns)
	srvAPI.OnConfigured = func() {
		log.Printf("setup saved — exiting so Docker restarts with mailbox enabled")
		os.Exit(0)
	}
	if cfg.TurnstileSecret == "" {
		log.Printf("turnstile: disabled (set AESMS_TURNSTILE_SECRET for internet-facing create)")
	} else {
		log.Printf("turnstile: enabled on account create")
	}
	if cfg.RateLimitDisabled {
		log.Printf("rate limit: disabled")
	}

	httpSrv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srvAPI.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		if cfg.SetupNeeded {
			log.Printf("aesmsd SETUP MODE on %s — open http://127.0.0.1%s/setup.html", cfg.Listen, cfg.Listen)
		} else {
			log.Printf("aesmsd listening on %s base=%s fp=%s", cfg.Listen, cfg.BaseURL, cfg.Fingerprint)
		}
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	<-ctx.Done()
	shutdownCtx, c2 := context.WithTimeout(context.Background(), 10*time.Second)
	defer c2()
	_ = httpSrv.Shutdown(shutdownCtx)
}
