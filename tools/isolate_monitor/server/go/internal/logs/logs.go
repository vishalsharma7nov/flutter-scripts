package logs

import (
	"bufio"
	"os/exec"
	"strings"
	"sync"
)

type Streamer struct {
	Package  string
	BundleID string
	DeviceID string

	mu              sync.Mutex
	lines           []string
	revision        int
	sessionRevision int
	streaming       bool
	err             string
	cmd             *exec.Cmd
	listeners       []chan struct{}
}

func (s *Streamer) LineCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.lines)
}

func (s *Streamer) Revision() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.revision
}

func (s *Streamer) SessionRevision() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sessionRevision
}

func (s *Streamer) IsStreaming() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.streaming
}

func (s *Streamer) Error() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.err
}

func (s *Streamer) Lines() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]string, len(s.lines))
	copy(out, s.lines)
	return out
}

func (s *Streamer) Notify() <-chan struct{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	ch := make(chan struct{}, 1)
	s.listeners = append(s.listeners, ch)
	return ch
}

func (s *Streamer) notify() {
	for _, ch := range s.listeners {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

func (s *Streamer) appendLine(line string) {
	s.mu.Lock()
	s.lines = append(s.lines, line)
	if len(s.lines) > 20000 {
		s.lines = s.lines[len(s.lines)-20000:]
	}
	s.revision++
	s.mu.Unlock()
	s.notify()
}

func (s *Streamer) Start() {
	s.Stop()
	args := []string{"-s", s.DeviceID, "logcat", "-v", "time"}
	cmd := exec.Command("adb", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		s.mu.Lock()
		s.err = err.Error()
		s.mu.Unlock()
		return
	}
	if err := cmd.Start(); err != nil {
		s.mu.Lock()
		s.err = "adb logcat failed: " + err.Error()
		s.streaming = false
		s.mu.Unlock()
		return
	}
	s.mu.Lock()
	s.cmd = cmd
	s.streaming = true
	s.err = ""
	s.sessionRevision++
	s.lines = nil
	s.revision++
	s.mu.Unlock()
	s.notify()

	go func() {
		sc := bufio.NewScanner(stdout)
		buf := make([]byte, 0, 64*1024)
		sc.Buffer(buf, 1024*1024)
		pkg := s.Package
		for sc.Scan() {
			line := sc.Text()
			if pkg != "" && !strings.Contains(line, pkg) && !interestingLine(line) {
				continue
			}
			s.appendLine(line)
		}
		s.mu.Lock()
		s.streaming = false
		s.cmd = nil
		s.mu.Unlock()
		s.notify()
	}()
}

func interestingLine(line string) bool {
	lower := strings.ToLower(line)
	return strings.Contains(lower, "flutter") ||
		strings.Contains(lower, "dartvm") ||
		strings.Contains(lower, "fatal") ||
		strings.Contains(lower, "exception") ||
		strings.Contains(lower, " error") ||
		strings.Contains(line, "TripStreamWorker") ||
		strings.Contains(line, "TripStreamIsolate") ||
		strings.Contains(line, "TripStreamNavForwarder") ||
		strings.Contains(line, "TripStreamSession")
}

func (s *Streamer) Stop() {
	s.mu.Lock()
	cmd := s.cmd
	s.cmd = nil
	s.streaming = false
	s.mu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}
}

func (s *Streamer) RestartForReinstall() {
	s.mu.Lock()
	s.sessionRevision++
	s.lines = nil
	s.revision++
	s.mu.Unlock()
	s.notify()
	s.Start()
}

func AdbAvailable() bool {
	_, err := exec.LookPath("adb")
	return err == nil
}

func ListAdbDevices() []map[string]any {
	out, err := exec.Command("adb", "devices", "-l").Output()
	if err != nil {
		return nil
	}
	var devices []map[string]any
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "List of devices") {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		serial, state := parts[0], parts[1]
		if state != "device" {
			continue
		}
		model := ""
		for _, p := range parts[2:] {
			if strings.HasPrefix(p, "model:") {
				model = strings.TrimPrefix(p, "model:")
			}
		}
		devices = append(devices, map[string]any{
			"id":     serial,
			"serial": serial,
			"state":  state,
			"model":  model,
			"name":   model,
		})
	}
	return devices
}
