package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/t9-messenger/t9/server/internal/api"
	"github.com/t9-messenger/t9/server/internal/config"
	"github.com/t9-messenger/t9/server/internal/purge"
	"github.com/t9-messenger/t9/server/internal/store"
	"github.com/t9-messenger/t9/server/internal/webembed"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}
	st, err := store.Open(cfg.DataDir, cfg.DBKey)
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	defer func() {
		if err := st.Close(); err != nil {
			log.Printf("store close: %v", err)
		}
	}()
	cfg.Fingerprint = st.Fingerprint()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go (&purge.Runner{Store: st, Interval: cfg.PurgeEvery}).Start(ctx)

	srvAPI := api.New(cfg, st, webembed.Handler())
	httpSrv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srvAPI.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("t9d listening on %s base=%s fp=%s", cfg.Listen, cfg.BaseURL, st.Fingerprint())
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	<-ctx.Done()
	shutdownCtx, c2 := context.WithTimeout(context.Background(), 10*time.Second)
	defer c2()
	_ = httpSrv.Shutdown(shutdownCtx)
}
