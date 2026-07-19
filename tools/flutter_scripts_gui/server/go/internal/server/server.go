package server

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/flutter-scripts/flutter_scripts_gui/internal/catalog"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/gitstatus"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/ollama"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/project"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/releasecatalog"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/runner"
)

// Config for the GUI HTTP server.
type Config struct {
	Port       int
	BindHost   string
	ToolRoot   string
	WebDir     string
	ScriptsDir string
	ProjectDir string
	AutoOpen   bool
}

// Server serves the React UI and script APIs.
type Server struct {
	cfg    Config
	hub    *runner.Hub
	run    *runner.Runner
	mux    *http.ServeMux
	server *http.Server
	mu     sync.Mutex
}

func New(cfg Config) *Server {
	hub := runner.NewHub()
	s := &Server{
		cfg: cfg,
		hub: hub,
		run: runner.New(hub, cfg.ScriptsDir, cfg.ProjectDir),
		mux: http.NewServeMux(),
	}
	s.routes()
	return s
}

func (s *Server) routes() {
	s.mux.HandleFunc("/api/status", s.handleStatus)
	s.mux.HandleFunc("/api/scripts", s.handleScripts)
	s.mux.HandleFunc("/api/projects", s.handleProjects)
	s.mux.HandleFunc("/api/release-packages", s.handleReleasePackages)
	s.mux.HandleFunc("/api/project", s.handleProject)
	s.mux.HandleFunc("/api/run", s.handleRun)
	s.mux.HandleFunc("/api/stop", s.handleStop)
	s.mux.HandleFunc("/api/logs", s.handleLogs)
	s.mux.HandleFunc("/api/git/repo", s.handleGitRepo)
	s.mux.HandleFunc("/api/git/analyze", s.handleGitAnalyze)
	s.mux.HandleFunc("/api/localization/check", s.handleLocalizationCheck)
	s.mux.HandleFunc("/api/localization/apply", s.handleLocalizationApply)
	s.mux.Handle("/", s.staticHandler())
}

func (s *Server) staticHandler() http.Handler {
	web := s.cfg.WebDir
	fs := http.FileServer(http.Dir(web))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			http.NotFound(w, r)
			return
		}
		// Avoid stale UI after rebuilds (especially index.html).
		if r.URL.Path == "/" || strings.HasSuffix(r.URL.Path, ".html") {
			w.Header().Set("Cache-Control", "no-cache")
		}
		path := filepath.Join(web, filepath.Clean("/"+r.URL.Path))
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			fs.ServeHTTP(w, r)
			return
		}
		// SPA fallback
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFile(w, r, filepath.Join(web, "index.html"))
	})
}

func (s *Server) Start() error {
	addr := net.JoinHostPort(s.cfg.BindHost, strconv.Itoa(s.cfg.Port))
	s.server = &http.Server{
		Addr:              addr,
		Handler:           withCORS(s.mux),
		ReadHeaderTimeout: 10 * time.Second,
	}
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	url := fmt.Sprintf("http://127.0.0.1:%d/", s.cfg.Port)
	fmt.Printf("flutter-scripts GUI listening on %s\n", url)
	fmt.Printf("  scripts: %s\n", s.cfg.ScriptsDir)
	fmt.Printf("  project: %s\n", s.run.GetProjectDir())
	if s.cfg.AutoOpen {
		go openBrowser(url)
	}
	return s.server.Serve(ln)
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	active, file := s.run.Active()
	projectDir := s.run.GetProjectDir()
	writeJSON(w, map[string]any{
		"port":         s.cfg.Port,
		"scriptsDir":   s.cfg.ScriptsDir,
		"projectDir":   projectDir,
		"isFlutter":    project.IsFlutterProject(projectDir),
		"isFlutterApp": project.IsFlutterApp(projectDir),
		"running":      active,
		"runningFile":  file,
		"git":          gitstatus.Collect(projectDir),
		"ollama":       ollama.Check(),
	})
}

func (s *Server) handleScripts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	scripts, err := catalog.Discover(s.cfg.ScriptsDir)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{"scripts": scripts})
}

func (s *Server) handleReleasePackages(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	packages, err := releasecatalog.Discover(s.cfg.ScriptsDir)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{"packages": packages})
}

func (s *Server) handleProjects(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	current := s.run.GetProjectDir()
	projects := project.DiscoverNearby(current, 2)
	writeJSON(w, map[string]any{
		"projects":   projects,
		"current":    current,
		"isFlutter":  project.IsFlutterProject(current),
		"isFlutterApp": project.IsFlutterApp(current),
	})
}

type runRequest struct {
	File string   `json:"file"`
	Args []string `json:"args"`
}

type projectRequest struct {
	Source string `json:"source"`
}

func (s *Server) handleProject(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req projectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	kind, value, err := project.NormalizeSource(req.Source)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s.hub.Publish(runner.Event{Type: "log", Line: "Resolving project: " + strings.TrimSpace(req.Source)})

	var dir string
	switch kind {
	case "path":
		dir, err = project.ResolveLocalPath(value)
	case "git":
		parent := project.DefaultCloneParent()
		dir, err = project.CloneOrReuse(value, parent, func(line string) {
			s.hub.Publish(runner.Event{Type: "log", Line: line})
		})
	default:
		http.Error(w, "unsupported source", http.StatusBadRequest)
		return
	}
	if err != nil {
		s.hub.Publish(runner.Event{Type: "error", Line: err.Error()})
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := s.run.SetProjectDir(dir); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	s.mu.Lock()
	s.cfg.ProjectDir = dir
	s.mu.Unlock()
	_ = os.Setenv("PROJECT_ROOT", dir)

	s.hub.Publish(runner.Event{
		Type: "log",
		Line: fmt.Sprintf("Active project set to %s (flutter=%v app=%v)",
			dir, project.IsFlutterProject(dir), project.IsFlutterApp(dir)),
	})
	writeJSON(w, map[string]any{
		"ok":           true,
		"projectDir":   dir,
		"isFlutter":    project.IsFlutterProject(dir),
		"isFlutterApp": project.IsFlutterApp(dir),
		"kind":         kind,
	})
}

func (s *Server) handleRun(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req runRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	req.File = strings.TrimSpace(req.File)
	if req.File == "" {
		http.Error(w, "file required", http.StatusBadRequest)
		return
	}
	if err := s.run.Start(req.File, req.Args); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "file": req.File})
}

func (s *Server) handleStop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := s.run.Stop(); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, map[string]any{"ok": true})
}

func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	ch := s.hub.Subscribe()
	defer s.hub.Unsubscribe(ch)

	notify := r.Context().Done()
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-notify:
			return
		case <-ticker.C:
			fmt.Fprintf(w, ": ping\n\n")
			flusher.Flush()
		case ev, ok := <-ch:
			if !ok {
				return
			}
			data, _ := json.Marshal(ev)
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func openBrowser(url string) {
	// Best-effort; launcher also opens via open_browser_url.sh.
	cmd := execOpen(url)
	if cmd != nil {
		_ = cmd.Start()
	}
}
