package push

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
)

// Hub fans out online-device events (SSE). APNs is optional and separate.
type Hub struct {
	mu   sync.Mutex
	subs map[string]map[chan []byte]struct{} // accountID -> set of channels
}

func NewHub() *Hub {
	return &Hub{subs: make(map[string]map[chan []byte]struct{})}
}

func (h *Hub) Subscribe(accountID string) chan []byte {
	ch := make(chan []byte, 4)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.subs[accountID] == nil {
		h.subs[accountID] = make(map[chan []byte]struct{})
	}
	h.subs[accountID][ch] = struct{}{}
	return ch
}

func (h *Hub) Unsubscribe(accountID string, ch chan []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.subs[accountID]; m != nil {
		delete(m, ch)
		if len(m) == 0 {
			delete(h.subs, accountID)
		}
	}
	close(ch)
}

func (h *Hub) Notify(accountID string, event string) {
	payload, _ := json.Marshal(map[string]string{"event": event})
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs[accountID] {
		select {
		case ch <- payload:
		default:
		}
	}
}

// ServeSSE streams events for an authenticated device session.
func (h *Hub) ServeSSE(w http.ResponseWriter, r *http.Request, accountID string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "stream unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	ch := h.Subscribe(accountID)
	defer h.Unsubscribe(accountID, ch)

	_, _ = w.Write([]byte("event: ready\ndata: {}\n\n"))
	flusher.Flush()

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			_, _ = w.Write([]byte("event: message\ndata: "))
			_, _ = w.Write(msg)
			_, _ = w.Write([]byte("\n\n"))
			flusher.Flush()
			log.Printf("push: sse to %s", accountID[:8])
		}
	}
}
