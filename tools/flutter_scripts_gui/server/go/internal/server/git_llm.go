package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/flutter-scripts/flutter_scripts_gui/internal/gitstatus"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/ollama"
)

func (s *Server) handleGitRepo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, gitstatus.Collect(s.run.GetProjectDir()))
}

type gitAnalyzeReq struct {
	Error          string `json:"error"`
	MatchedIssueID string `json:"matchedIssueId"`
	MatchedTitle   string `json:"matchedTitle"`
	MatchedWhy     string `json:"matchedWhy"`
	UseLLM         bool   `json:"useLLM"`
}

type gitAnalyzeResp struct {
	Source   string `json:"source"` // llm | catalog | fallback
	Summary  string `json:"summary"`
	Why      string `json:"why"`
	Warning  string `json:"warning,omitempty"`
	LLMRaw   string `json:"llmRaw,omitempty"`
	Model    string `json:"model,omitempty"`
	LLMError string `json:"llmError,omitempty"`
}

func (s *Server) handleGitAnalyze(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req gitAnalyzeReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	errText := strings.TrimSpace(req.Error)
	if errText == "" {
		http.Error(w, "error text required", http.StatusBadRequest)
		return
	}

	repo := gitstatus.Collect(s.run.GetProjectDir())
	resp := gitAnalyzeResp{
		Source:  "catalog",
		Summary: req.MatchedTitle,
		Why:     req.MatchedWhy,
	}
	if resp.Summary == "" {
		resp.Source = "fallback"
		resp.Summary = "Unrecognized Git error"
		resp.Why = "No catalog match. Paste a fuller error, pick an issue, or enable Ollama for LLM help."
	}

	if !req.UseLLM {
		writeJSON(w, resp)
		return
	}

	ollamaSt := ollama.Check()
	if !ollamaSt.Available {
		resp.LLMError = ollamaSt.Error
		writeJSON(w, resp)
		return
	}

	system := `You are Git Assist, a local Git/GitHub recovery assistant.
Respond in plain text with exactly these sections:
SUMMARY: one-line title of the problem
WHY: 1-2 sentences explaining the cause
WARNING: one safety note (or "none")
Do not invent destructive commands. Prefer reversible fixes. Never recommend force-push to main/master unless the user explicitly asked.`

	var user strings.Builder
	user.WriteString("Terminal error:\n```\n")
	user.WriteString(errText)
	user.WriteString("\n```\n\n")
	user.WriteString("Repo context:\n")
	fmt.Fprintf(&user, "- branch: %s\n", repo.Branch)
	fmt.Fprintf(&user, "- upstream: %s\n", repo.Upstream)
	fmt.Fprintf(&user, "- ahead/behind: %d/%d\n", repo.Ahead, repo.Behind)
	fmt.Fprintf(&user, "- dirty files: %d\n", repo.DirtyCount)
	if req.MatchedTitle != "" {
		fmt.Fprintf(&user, "\nCatalog match hint: %s — %s\n", req.MatchedTitle, req.MatchedWhy)
	}

	raw, err := ollama.Chat(system, user.String(), ollamaSt.Model)
	if err != nil {
		resp.LLMError = err.Error()
		writeJSON(w, resp)
		return
	}
	resp.Source = "llm"
	resp.Model = ollamaSt.Model
	resp.LLMRaw = raw
	resp.Summary, resp.Why, resp.Warning = parseGitLLMSections(raw)
	if resp.Summary == "" {
		resp.Summary = req.MatchedTitle
		if resp.Summary == "" {
			resp.Summary = "LLM diagnosis"
		}
	}
	if resp.Why == "" {
		resp.Why = raw
	}
	writeJSON(w, resp)
}

func parseGitLLMSections(raw string) (summary, why, warning string) {
	lines := strings.Split(raw, "\n")
	var cur string
	var buf strings.Builder
	flush := func() {
		text := strings.TrimSpace(buf.String())
		buf.Reset()
		switch cur {
		case "SUMMARY":
			summary = text
		case "WHY":
			why = text
		case "WARNING":
			if !strings.EqualFold(text, "none") {
				warning = text
			}
		}
	}
	for _, line := range lines {
		upper := strings.ToUpper(strings.TrimSpace(line))
		if strings.HasPrefix(upper, "SUMMARY:") {
			flush()
			cur = "SUMMARY"
			buf.WriteString(strings.TrimSpace(line[len("SUMMARY:"):]))
			continue
		}
		if strings.HasPrefix(upper, "WHY:") {
			flush()
			cur = "WHY"
			buf.WriteString(strings.TrimSpace(line[len("WHY:"):]))
			continue
		}
		if strings.HasPrefix(upper, "WARNING:") {
			flush()
			cur = "WARNING"
			buf.WriteString(strings.TrimSpace(line[len("WARNING:"):]))
			continue
		}
		if cur != "" {
			if buf.Len() > 0 {
				buf.WriteByte('\n')
			}
			buf.WriteString(line)
		}
	}
	flush()
	return
}
