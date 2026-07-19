package runner

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Event is a log or lifecycle line for SSE clients.
type Event struct {
	Type    string `json:"type"` // log | started | exited | error
	Line    string `json:"line,omitempty"`
	File    string `json:"file,omitempty"`
	Code    *int   `json:"code,omitempty"`
	Ts      int64  `json:"ts"`
}

// Hub broadcasts events to SSE subscribers.
type Hub struct {
	mu   sync.Mutex
	subs map[chan Event]struct{}
}

func NewHub() *Hub {
	return &Hub{subs: make(map[chan Event]struct{})}
}

func (h *Hub) Subscribe() chan Event {
	ch := make(chan Event, 64)
	h.mu.Lock()
	h.subs[ch] = struct{}{}
	h.mu.Unlock()
	return ch
}

func (h *Hub) Unsubscribe(ch chan Event) {
	h.mu.Lock()
	delete(h.subs, ch)
	h.mu.Unlock()
	close(ch)
}

func (h *Hub) Publish(ev Event) {
	if ev.Ts == 0 {
		ev.Ts = time.Now().UnixMilli()
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs {
		select {
		case ch <- ev:
		default:
			// Drop if subscriber is slow.
		}
	}
}

// Runner runs at most one script at a time.
type Runner struct {
	Hub        *Hub
	ScriptsDir string
	ProjectDir string

	mu      sync.Mutex
	cmd     *exec.Cmd
	cancel  context.CancelFunc
	running bool
	file    string
}

func New(hub *Hub, scriptsDir, projectDir string) *Runner {
	return &Runner{
		Hub:        hub,
		ScriptsDir: scriptsDir,
		ProjectDir: projectDir,
	}
}

func (r *Runner) Active() (bool, string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.running, r.file
}

func (r *Runner) GetProjectDir() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.ProjectDir
}

// SetProjectDir updates the cwd for future script runs (not while running).
func (r *Runner) SetProjectDir(dir string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.running {
		return fmt.Errorf("cannot change project while a script is running")
	}
	r.ProjectDir = dir
	return nil
}

func (r *Runner) Start(file string, args []string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.running {
		return fmt.Errorf("a script is already running: %s", r.file)
	}
	rel, err := sanitizeScriptRel(file)
	if err != nil {
		return err
	}
	target := filepath.Join(r.ScriptsDir, filepath.FromSlash(rel))
	info, err := os.Stat(target)
	if err != nil || info.IsDir() {
		return fmt.Errorf("script not found: %s", file)
	}
	_ = os.Chmod(target, 0o755)

	ctx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(ctx, target, args...)
	cmd.Dir = r.ProjectDir
	cmd.Env = os.Environ()
	if os.Getenv("PROJECT_ROOT") == "" && r.ProjectDir != "" {
		cmd.Env = append(cmd.Env, "PROJECT_ROOT="+r.ProjectDir)
	}
	cmd.Env = append(cmd.Env, "SCRIPTS_DIR="+r.ScriptsDir)
	cmd.Env = append(cmd.Env, "FLUTTER_SCRIPTS_HOME="+r.ScriptsDir)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		cancel()
		return err
	}

	if err := cmd.Start(); err != nil {
		cancel()
		return err
	}

	r.cmd = cmd
	r.cancel = cancel
	r.running = true
	r.file = rel

	r.Hub.Publish(Event{Type: "started", File: rel, Line: "Started " + rel})

	go r.pump(stdout)
	go r.pump(stderr)
	go r.wait()
	return nil
}

func (r *Runner) Stop() error {
	r.mu.Lock()
	cmd := r.cmd
	cancel := r.cancel
	running := r.running
	r.mu.Unlock()
	if !running || cmd == nil || cmd.Process == nil {
		return fmt.Errorf("no script is running")
	}
	if cancel != nil {
		cancel()
	}
	pgid, err := syscall.Getpgid(cmd.Process.Pid)
	if err == nil {
		_ = syscall.Kill(-pgid, syscall.SIGTERM)
	} else {
		_ = cmd.Process.Signal(syscall.SIGTERM)
	}
	return nil
}

func (r *Runner) pump(rc io.Reader) {
	sc := bufio.NewScanner(rc)
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 1024*1024)
	for sc.Scan() {
		r.Hub.Publish(Event{Type: "log", Line: sc.Text()})
	}
}

func (r *Runner) wait() {
	r.mu.Lock()
	cmd := r.cmd
	file := r.file
	r.mu.Unlock()
	err := cmd.Wait()
	code := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			code = 1
			r.Hub.Publish(Event{Type: "error", Line: err.Error(), File: file})
		}
	}
	r.Hub.Publish(Event{Type: "exited", File: file, Code: &code, Line: fmt.Sprintf("Exited %s (code %d)", file, code)})

	r.mu.Lock()
	r.running = false
	r.cmd = nil
	r.cancel = nil
	r.file = ""
	r.mu.Unlock()
}

func sanitizeScriptRel(file string) (string, error) {
	file = strings.TrimSpace(file)
	if file == "" {
		return "", fmt.Errorf("invalid script file")
	}
	clean := filepath.Clean(filepath.FromSlash(file))
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("invalid script file")
	}
	if filepath.IsAbs(clean) {
		return "", fmt.Errorf("invalid script file")
	}
	rel := filepath.ToSlash(clean)
	if !strings.HasSuffix(rel, ".sh") {
		return "", fmt.Errorf("invalid script file")
	}
	return rel, nil
}

func stringsContainsSlash(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] == '/' || s[i] == '\\' {
			return true
		}
	}
	return false
}
