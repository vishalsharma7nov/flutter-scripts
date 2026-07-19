package server

import (
	"encoding/json"
	"fmt"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/localization"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type localizationRequest struct {
	Mode    string   `json:"mode"` // hardcoded | full | suggestions
	Path    []string `json:"path,omitempty"`
	Apply   bool     `json:"apply,omitempty"`
	Analyze bool     `json:"analyze,omitempty"`
}

func (s *Server) decodeLocalizationRequest(w http.ResponseWriter, r *http.Request) (localizationRequest, bool) {
	var req localizationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && r.ContentLength > 0 {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return req, false
	}
	req.Mode = strings.TrimSpace(req.Mode)
	if req.Mode == "" {
		req.Mode = "full"
	}
	switch req.Mode {
	case "hardcoded", "full", "suggestions":
	default:
		http.Error(w, "mode must be hardcoded|full|suggestions", http.StatusBadRequest)
		return req, false
	}
	return req, true
}

func (s *Server) runLocalizationTool(req localizationRequest) (any, error) {
	projectDir := s.run.GetProjectDir()
	if projectDir == "" {
		return nil, fmt.Errorf("no project selected")
	}
	if _, err := os.Stat(filepath.Join(projectDir, "pubspec.yaml")); err != nil {
		return nil, fmt.Errorf("active project is not a Flutter app (missing pubspec.yaml)")
	}
	return localization.Run(projectDir, localization.Request{
		Mode:    req.Mode,
		Path:    req.Path,
		Apply:   req.Apply,
		Analyze: req.Analyze,
	})
}

func (s *Server) handleLocalizationCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	req, ok := s.decodeLocalizationRequest(w, r)
	if !ok {
		return
	}
	payload, err := s.runLocalizationTool(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, payload)
}

func (s *Server) handleLocalizationApply(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	req, ok := s.decodeLocalizationRequest(w, r)
	if !ok {
		return
	}
	req.Mode = "suggestions"
	req.Apply = true
	req.Analyze = true
	payload, err := s.runLocalizationTool(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, payload)
}
