package vm

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

type Connector struct {
	VMPort      int
	URIOverride string

	mu        sync.Mutex
	connected bool
	vmURI     string
	listeners []chan struct{}
}

func (c *Connector) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connected
}

func (c *Connector) VMURI() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.vmURI
}

func (c *Connector) Notify() <-chan struct{} {
	c.mu.Lock()
	defer c.mu.Unlock()
	ch := make(chan struct{}, 1)
	c.listeners = append(c.listeners, ch)
	return ch
}

func (c *Connector) notify() {
	for _, ch := range c.listeners {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

func (c *Connector) StartPolling() {
	go func() {
		ticker := time.NewTicker(1500 * time.Millisecond)
		defer ticker.Stop()
		for range ticker.C {
			c.pollOnce()
		}
	}()
}

func (c *Connector) pollOnce() {
	uri := strings.TrimSpace(c.URIOverride)
	if uri == "" {
		uri = c.discover()
	}
	c.mu.Lock()
	was := c.connected
	prev := c.vmURI
	if uri != "" {
		c.connected = true
		c.vmURI = uri
	} else {
		c.connected = false
		c.vmURI = ""
	}
	changed := was != c.connected || prev != c.vmURI
	c.mu.Unlock()
	if changed {
		c.notify()
	}
}

func (c *Connector) discover() string {
	port := c.VMPort
	if port <= 0 {
		port = 58888
	}
	url := fmt.Sprintf("http://127.0.0.1:%d/json", port)
	client := &http.Client{Timeout: 800 * time.Millisecond}
	res, err := client.Get(url)
	if err != nil {
		return ""
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	var decoded any
	if err := json.Unmarshal(body, &decoded); err != nil {
		return ""
	}
	return extractWS(decoded, port)
}

func extractWS(decoded any, port int) string {
	switch v := decoded.(type) {
	case []any:
		for _, item := range v {
			if s := extractWS(item, port); s != "" {
				return s
			}
		}
	case map[string]any:
		for _, key := range []string{"webSocketDebuggerUrl", "wsUri", "uri"} {
			if raw, ok := v[key].(string); ok && strings.HasPrefix(raw, "ws") {
				return normalizeWS(raw, port)
			}
		}
	}
	return ""
}

func normalizeWS(raw string, port int) string {
	if strings.HasPrefix(raw, "ws://") || strings.HasPrefix(raw, "wss://") {
		return raw
	}
	if strings.HasPrefix(raw, "/") {
		return fmt.Sprintf("ws://127.0.0.1:%d%s", port, raw)
	}
	return raw
}

func (c *Connector) ListIsolates() []map[string]any {
	if !c.IsConnected() {
		return []map[string]any{}
	}
	// Lightweight placeholder until full VM service client is ported.
	// React UI handles empty / waiting state.
	return []map[string]any{
		{
			"id":     "go-monitor",
			"name":   "main",
			"number": 0,
			"runnable": true,
			"isSystemIsolate": false,
			"pauseEvent": map[string]any{"kind": "Resume"},
		},
	}
}
