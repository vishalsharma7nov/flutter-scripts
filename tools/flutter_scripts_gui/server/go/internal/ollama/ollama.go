package ollama

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultBase = "http://127.0.0.1:11434"

type Status struct {
	Available bool     `json:"available"`
	BaseURL   string   `json:"baseURL"`
	Model     string   `json:"model"`
	Models    []string `json:"models"`
	Error     string   `json:"error,omitempty"`
}

type ChatRequest struct {
	Model    string        `json:"model"`
	Messages []ChatMessage `json:"messages"`
	Stream   bool          `json:"stream"`
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatResponse struct {
	Message ChatMessage `json:"message"`
}

func BaseURL() string {
	if v := strings.TrimSpace(os.Getenv("OLLAMA_HOST")); v != "" {
		if strings.HasPrefix(v, "http://") || strings.HasPrefix(v, "https://") {
			return strings.TrimRight(v, "/")
		}
		return "http://" + strings.TrimRight(v, "/")
	}
	return defaultBase
}

func DefaultModel() string {
	if v := strings.TrimSpace(os.Getenv("GIT_LLM_MODEL")); v != "" {
		return v
	}
	return "qwen2.5-coder:7b"
}

func Check() Status {
	base := BaseURL()
	st := Status{BaseURL: base, Model: DefaultModel()}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(base + "/api/tags")
	if err != nil {
		st.Available = false
		st.Error = "Ollama not reachable — keyword matching still works"
		return st
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		st.Available = false
		st.Error = fmt.Sprintf("Ollama returned HTTP %d", resp.StatusCode)
		return st
	}
	var payload struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		st.Available = false
		st.Error = "Could not parse Ollama tags"
		return st
	}
	for _, m := range payload.Models {
		st.Models = append(st.Models, m.Name)
	}
	st.Available = true
	// Prefer configured model if installed; else first model.
	want := DefaultModel()
	for _, name := range st.Models {
		if name == want || strings.HasPrefix(name, want) || strings.HasPrefix(want, strings.Split(name, ":")[0]) {
			st.Model = name
			return st
		}
	}
	if len(st.Models) > 0 {
		st.Model = st.Models[0]
	}
	return st
}

func Chat(system, user, model string) (string, error) {
	if model == "" {
		model = DefaultModel()
	}
	body, _ := json.Marshal(ChatRequest{
		Model: model,
		Messages: []ChatMessage{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
		Stream: false,
	})
	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Post(BaseURL()+"/api/chat", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("ollama HTTP %d: %s", resp.StatusCode, string(raw))
	}
	var parsed chatResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	return strings.TrimSpace(parsed.Message.Content), nil
}
