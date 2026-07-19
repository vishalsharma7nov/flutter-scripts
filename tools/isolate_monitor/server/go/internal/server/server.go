package server

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/flutter-scripts/isolate_monitor/internal/backend"
	"github.com/flutter-scripts/isolate_monitor/internal/deploy"
	"github.com/flutter-scripts/isolate_monitor/internal/logs"
	"github.com/flutter-scripts/isolate_monitor/internal/threads"
	"github.com/flutter-scripts/isolate_monitor/internal/vm"
)

type Config struct {
	Port           int
	ToolRoot       string
	WebDir         string
	ProjectRoot    string
	PackageName    string
	BundleID       string
	DeviceID       string
	MonitorMode    string
	EnvFile        string
	AppEnv         string
	VMServicePort  int
	UseFVM         bool
	BindHost       string
	AutoDeploy     bool
	URIOverride    string
}

type Monitor struct {
	cfg      Config
	deployer *deploy.Deployer
	streamer *logs.Streamer
	vm       *vm.Connector
	mu       sync.Mutex
}

func New(cfg Config) *Monitor {
	m := &Monitor{cfg: cfg}
	m.vm = &vm.Connector{VMPort: cfg.VMServicePort, URIOverride: cfg.URIOverride}
	if cfg.DeviceID != "" {
		m.streamer = &logs.Streamer{
			Package:  cfg.PackageName,
			BundleID: cfg.BundleID,
			DeviceID: cfg.DeviceID,
		}
	}
	if cfg.ProjectRoot != "" && cfg.DeviceID != "" {
		m.deployer = &deploy.Deployer{
			ProjectRoot:   cfg.ProjectRoot,
			DeviceID:      cfg.DeviceID,
			BuildMode:     cfg.MonitorMode,
			EnvFile:       cfg.EnvFile,
			AppEnv:        cfg.AppEnv,
			VMServicePort: cfg.VMServicePort,
			UseFVM:        cfg.UseFVM,
		}
	}
	return m
}

func (m *Monitor) Start() error {
	m.vm.StartPolling()
	if m.streamer != nil {
		m.streamer.Start()
	}
	if m.cfg.AutoDeploy && m.deployer != nil {
		go func() {
			time.Sleep(400 * time.Millisecond)
			m.deployer.Reinstall()
		}()
	}

	mux := http.NewServeMux()
	m.routes(mux)

	web := http.FileServer(http.Dir(m.cfg.WebDir))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			http.NotFound(w, r)
			return
		}
		// SPA fallback to index.html for unknown paths
		path := filepath.Join(m.cfg.WebDir, filepath.Clean(r.URL.Path))
		if r.URL.Path == "/" || !fileExists(path) {
			http.ServeFile(w, r, filepath.Join(m.cfg.WebDir, "index.html"))
			return
		}
		web.ServeHTTP(w, r)
	})

	addr := fmt.Sprintf("%s:%d", m.cfg.BindHost, m.cfg.Port)
	fmt.Fprintf(os.Stdout, "Isolate monitor (go) listening on http://127.0.0.1:%d\n", m.cfg.Port)
	if m.cfg.BindHost == "0.0.0.0" {
		if lan := lanIPv4(); lan != "" {
			fmt.Fprintf(os.Stdout, "LAN access: http://%s:%d\n", lan, m.cfg.Port)
		}
	}
	fmt.Fprintf(os.Stdout, "Backend: go · preferred: %s\n", backend.ReadPreferred(m.cfg.ToolRoot))
	return http.ListenAndServe(addr, mux)
}

func (m *Monitor) routes(mux *http.ServeMux) {
	mux.HandleFunc("/api/status", m.handleStatus)
	mux.HandleFunc("/api/backend", m.handleBackend)
	mux.HandleFunc("/api/mode", m.handleMode)
	mux.HandleFunc("/api/isolates", m.handleIsolates)
	mux.HandleFunc("/api/threads", m.handleThreads)
	mux.HandleFunc("/api/logs", m.handleLogs)
	mux.HandleFunc("/api/logs/search", m.handleLogsSearch)
	mux.HandleFunc("/api/events", m.handleEvents)
	mux.HandleFunc("/api/devices", m.handleDevices)
	mux.HandleFunc("/api/devices/connect", m.handleDeviceConnect)
	mux.HandleFunc("/api/devices/pair", m.handleDevicePair)
	mux.HandleFunc("/api/devices/disconnect", m.handleDeviceDisconnect)
	mux.HandleFunc("/api/devices/select", m.handleDeviceSelect)
	mux.HandleFunc("/api/screen/frame", m.handleScreenFrame)
	mux.HandleFunc("/api/screen/tap", m.handleJSONOK)
	mux.HandleFunc("/api/screen/swipe", m.handleJSONOK)
	mux.HandleFunc("/api/screen/scrcpy", m.handleScrcpy)
	mux.HandleFunc("/api/open-file", m.handleOpenFile)
	mux.HandleFunc("/api/flutter/hot-reload", m.handleHotReload)
	mux.HandleFunc("/api/flutter/hot-restart", m.handleHotRestart)
	mux.HandleFunc("/api/flutter/stop", m.handleStop)
	mux.HandleFunc("/api/reinstall", m.handleReinstall)
}

func (m *Monitor) statusBody() map[string]any {
	preferred := backend.ReadPreferred(m.cfg.ToolRoot)
	logCount := 0
	logsStreaming := false
	logsRevision := 0
	sessionRevision := 0
	var logsErr any
	if m.streamer != nil {
		logCount = m.streamer.LineCount()
		logsStreaming = m.streamer.IsStreaming()
		logsRevision = m.streamer.Revision()
		sessionRevision = m.streamer.SessionRevision()
		if e := m.streamer.Error(); e != "" {
			logsErr = e
		}
	}
	deployRev := 0
	deployGen := 0
	reinstallRunning := false
	var reinstallErr any
	canReinstall := false
	flutterRunActive := false
	if m.deployer != nil {
		deployRev = m.deployer.OutputRevision()
		deployGen = m.deployer.DeployGeneration()
		reinstallRunning = m.deployer.IsRunning()
		canReinstall = m.deployer.CanDeploy()
		flutterRunActive = m.deployer.HasActiveProcess()
		if e := m.deployer.Error(); e != "" {
			reinstallErr = e
		}
	}
	mode := m.cfg.MonitorMode
	debug := mode == "debug"
	profile := mode == "profile"
	hotCapable := debug || profile
	vmConnected := m.vm.IsConnected()
	lan := ""
	if m.cfg.BindHost == "0.0.0.0" {
		if ip := lanIPv4(); ip != "" {
			lan = fmt.Sprintf("http://%s:%d", ip, m.cfg.Port)
		}
	}
	pkgName := ""
	if m.cfg.ProjectRoot != "" {
		pkgName = readPubName(m.cfg.ProjectRoot)
	}
	opener := strings.TrimSpace(os.Getenv("ISOLATE_MONITOR_FILE_OPENER"))
	return map[string]any{
		"mode":                    mode,
		"backend":                 backend.Go,
		"preferredBackend":        preferred,
		"availableBackends":       backend.Available(),
		"runnableBackends":        backend.Runnable(),
		"backendHint":             backend.Hint(preferred),
		"vmConnected":             vmConnected,
		"vmUri":                   nullIfEmpty(m.vm.VMURI()),
		"logsStreaming":           logsStreaming,
		"logsConnected":           logsStreaming && logCount > 0,
		"logLineCount":            logCount,
		"logsRevision":            logsRevision,
		"logSessionRevision":      sessionRevision,
		"deployRevision":          deployRev,
		"flutterDeployGeneration": deployGen,
		"flutterOutputRevision":   deployRev,
		"logsError":               logsErr,
		"package":                 m.cfg.PackageName,
		"bundleId":                m.cfg.BundleID,
		"device":                  m.cfg.DeviceID,
		"deviceLogsEnabled":       m.streamer != nil,
		"canReinstall":            canReinstall,
		"reinstallRunning":        reinstallRunning,
		"reinstallError":          reinstallErr,
		"projectRoot":             m.cfg.ProjectRoot,
		"dartPackageName":         pkgName,
		"fileOpener":              opener,
		"canOpenFiles":            m.cfg.ProjectRoot != "",
		"screenMirrorAvailable":   false,
		"screenMirrorError":       "Screen mirror not yet ported in Go backend",
		"screenWidth":             0,
		"screenHeight":            0,
		"screenFrameSequence":     0,
		"screenTargetFps":         0,
		"screenDevice":            m.cfg.DeviceID,
		"adbAvailable":            logs.AdbAvailable(),
		"flutterAvailable":        deploy.HasFlutter(),
		"bindHost":                m.cfg.BindHost,
		"lanUrl":                  nullIfEmpty(lan),
		"networkAccessEnabled":    m.cfg.BindHost != "127.0.0.1" && m.cfg.BindHost != "localhost",
		"flutterRunActive":        flutterRunActive,
		"canHotReload":            hotCapable && (flutterRunActive || vmConnected),
		"canHotRestart":           hotCapable && (flutterRunActive || vmConnected),
		"canStopFlutter":          flutterRunActive || (hotCapable && vmConnected),
		"workerIsolates":          false,
	}
}

func (m *Monitor) handleStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, m.statusBody())
}

func (m *Monitor) handleBackend(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	requested := backend.Normalize(fmt.Sprint(body["backend"]))
	restart := true
	if v, ok := body["restart"]; ok {
		if b, ok := v.(bool); ok {
			restart = b
		}
	}
	_ = backend.WritePreferred(m.cfg.ToolRoot, requested)
	runnable := backend.IsRunnable(requested)
	if restart {
		go func() {
			time.Sleep(250 * time.Millisecond)
			os.Exit(backend.RestartCode)
		}()
	}
	writeJSON(w, map[string]any{
		"ok":               true,
		"backend":          backend.Go,
		"preferredBackend": requested,
		"runnable":         runnable,
		"directory":        backend.Hint(requested),
		"message":          backend.StatusMessage(requested),
		"restarting":       restart,
		"needsRestart":     false,
	})
}

func (m *Monitor) handleIsolates(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"isolates": m.vm.ListIsolates()})
}

func (m *Monitor) handleThreads(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, threads.Fetch(m.cfg.DeviceID, m.cfg.PackageName))
}

func (m *Monitor) handleLogs(w http.ResponseWriter, r *http.Request) {
	lines := []string{}
	revision := 0
	session := 0
	if m.streamer != nil {
		lines = m.streamer.Lines()
		revision = m.streamer.Revision()
		session = m.streamer.SessionRevision()
	}
	reinstallOut := []string{}
	deployGen := 0
	deployRev := 0
	if m.deployer != nil {
		reinstallOut = m.deployer.RecentOutput()
		deployGen = m.deployer.DeployGeneration()
		deployRev = m.deployer.OutputRevision()
	}
	writeJSON(w, map[string]any{
		"lines":                   lines,
		"revision":                revision,
		"sessionRevision":         session,
		"reinstallOutput":         reinstallOut,
		"reinstallRunning":        m.deployer != nil && m.deployer.IsRunning(),
		"deployRevision":          deployRev,
		"flutterDeployGeneration": deployGen,
		"flutterOutputRevision":   deployRev,
	})
}

func (m *Monitor) handleLogsSearch(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	caseSensitive := r.URL.Query().Get("case") == "sensitive"
	lines := []string{}
	if m.streamer != nil {
		lines = m.streamer.Lines()
	}
	var matches []string
	if q != "" {
		needle := q
		if !caseSensitive {
			needle = strings.ToLower(q)
		}
		for _, line := range lines {
			hay := line
			if !caseSensitive {
				hay = strings.ToLower(line)
			}
			if strings.Contains(hay, needle) {
				matches = append(matches, line)
			}
		}
	} else {
		matches = lines
	}
	writeJSON(w, map[string]any{
		"query":           q,
		"matches":         matches,
		"matchCount":      len(matches),
		"lineCount":       len(lines),
		"sessionRevision": 0,
	})
}

func (m *Monitor) handleEvents(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	push := func(event string) {
		payload, _ := json.Marshal(m.statusBody())
		fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, payload)
		flusher.Flush()
	}
	push("ready")

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			push("status")
		}
	}
}

func (m *Monitor) handleDevices(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{
		"devices":          logs.ListAdbDevices(),
		"selected":         m.cfg.DeviceID,
		"adbAvailable":     logs.AdbAvailable(),
		"flutterAvailable": deploy.HasFlutter(),
	})
}

func (m *Monitor) handleDeviceConnect(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	address := strings.TrimSpace(fmt.Sprint(body["address"]))
	if address == "" {
		writeJSON(w, map[string]any{"ok": false, "error": "Enter device address as host:port"})
		return
	}
	out, err := exec.Command("adb", "connect", address).CombinedOutput()
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": string(out)})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": strings.TrimSpace(string(out))})
}

func (m *Monitor) handleDevicePair(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	host := strings.TrimSpace(fmt.Sprint(body["host"]))
	port := strings.TrimSpace(fmt.Sprint(body["port"]))
	code := strings.TrimSpace(fmt.Sprint(body["code"]))
	if host == "" || port == "" || code == "" {
		writeJSON(w, map[string]any{"ok": false, "error": "Host, port, and pairing code are required"})
		return
	}
	out, err := exec.Command("adb", "pair", host+":"+port, code).CombinedOutput()
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": string(out)})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": strings.TrimSpace(string(out))})
}

func (m *Monitor) handleDeviceDisconnect(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	serial := strings.TrimSpace(fmt.Sprint(body["device"]))
	if serial == "" || serial == "<nil>" {
		serial = strings.TrimSpace(fmt.Sprint(body["serial"]))
	}
	if serial == "" || serial == "<nil>" {
		serial = m.cfg.DeviceID
	}
	out, err := exec.Command("adb", "disconnect", serial).CombinedOutput()
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": string(out)})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": strings.TrimSpace(string(out))})
}

func (m *Monitor) handleDeviceSelect(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	device := strings.TrimSpace(fmt.Sprint(body["device"]))
	if device == "" || device == "<nil>" {
		device = strings.TrimSpace(fmt.Sprint(body["serial"]))
	}
	if device == "" || device == "<nil>" {
		writeJSON(w, map[string]any{"ok": false, "error": "device (or serial) required"})
		return
	}

	if modeRaw, ok := body["mode"]; ok {
		mode := strings.TrimSpace(fmt.Sprint(modeRaw))
		if mode != "" && mode != "<nil>" {
			if err := m.setMode(mode); err != "" {
				writeJSON(w, map[string]any{"ok": false, "error": err})
				return
			}
		}
	}

	m.mu.Lock()
	m.cfg.DeviceID = device
	if m.streamer != nil {
		m.streamer.DeviceID = device
		m.streamer.Start()
	} else {
		m.streamer = &logs.Streamer{
			Package:  m.cfg.PackageName,
			BundleID: m.cfg.BundleID,
			DeviceID: device,
		}
		m.streamer.Start()
	}
	if m.deployer != nil {
		m.deployer.DeviceID = device
		m.deployer.BuildMode = m.cfg.MonitorMode
	} else if m.cfg.ProjectRoot != "" {
		m.deployer = &deploy.Deployer{
			ProjectRoot:   m.cfg.ProjectRoot,
			DeviceID:      device,
			BuildMode:     m.cfg.MonitorMode,
			EnvFile:       m.cfg.EnvFile,
			AppEnv:        m.cfg.AppEnv,
			VMServicePort: m.cfg.VMServicePort,
			UseFVM:        m.cfg.UseFVM,
		}
	}
	m.mu.Unlock()

	status := m.statusBody()
	status["ok"] = true
	status["message"] = "Connected to " + device + " (" + m.cfg.MonitorMode + ")"
	status["device"] = device
	status["mode"] = m.cfg.MonitorMode
	writeJSON(w, status)
}

func (m *Monitor) setMode(raw string) string {
	mode := strings.ToLower(strings.TrimSpace(raw))
	switch mode {
	case "debug", "profile", "release":
	case "release-build", "store":
		mode = "release"
	default:
		return "mode must be debug, profile, or release"
	}
	m.mu.Lock()
	m.cfg.MonitorMode = mode
	if m.deployer != nil {
		m.deployer.BuildMode = mode
	}
	m.mu.Unlock()
	return ""
}

func (m *Monitor) handleMode(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	mode := strings.TrimSpace(fmt.Sprint(body["mode"]))
	if err := m.setMode(mode); err != "" {
		writeJSON(w, map[string]any{"ok": false, "error": err})
		return
	}
	hint := "Debug mode: hot reload + isolates + device logs"
	switch m.cfg.MonitorMode {
	case "release":
		hint = "Release mode: device logs + native threads (no Dart VM / isolates)"
	case "profile":
		hint = "Profile mode: near-release with VM isolates + device logs"
	}
	status := m.statusBody()
	status["ok"] = true
	status["message"] = hint
	status["mode"] = m.cfg.MonitorMode
	writeJSON(w, status)
}

func (m *Monitor) handleScreenFrame(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "screen mirror not available in Go backend yet", http.StatusServiceUnavailable)
}

func (m *Monitor) handleJSONOK(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"ok": true})
}

func (m *Monitor) handleScrcpy(w http.ResponseWriter, r *http.Request) {
	cmd := exec.Command("scrcpy", "-s", m.cfg.DeviceID)
	if err := cmd.Start(); err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": "scrcpy launched"})
}

func (m *Monitor) handleOpenFile(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	ref := strings.TrimSpace(fmt.Sprint(body["reference"]))
	if ref == "" || m.cfg.ProjectRoot == "" {
		writeJSON(w, map[string]any{"ok": false, "error": "File open unavailable"})
		return
	}
	path, line, col := parseRef(ref)
	resolved := resolvePath(m.cfg.ProjectRoot, path)
	if resolved == "" {
		writeJSON(w, map[string]any{"ok": false, "error": "Could not resolve " + path})
		return
	}
	opener := strings.TrimSpace(os.Getenv("ISOLATE_MONITOR_FILE_OPENER"))
	if opener == "" {
		opener = defaultOpener()
	}
	var err error
	switch opener {
	case "cursor":
		err = exec.Command("cursor", "-g", fmt.Sprintf("%s:%d:%d", resolved, line, col)).Start()
	case "code", "vscode":
		err = exec.Command("code", "-g", fmt.Sprintf("%s:%d:%d", resolved, line, col)).Start()
	default:
		if runtime.GOOS == "darwin" {
			err = exec.Command("open", resolved).Start()
		} else {
			err = exec.Command("xdg-open", resolved).Start()
		}
	}
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "path": resolved, "line": line, "opener": opener})
}

func (m *Monitor) handleHotReload(w http.ResponseWriter, r *http.Request) {
	mode := m.cfg.MonitorMode
	if (mode != "debug" && mode != "profile") || m.deployer == nil || !m.deployer.HasActiveProcess() {
		writeJSON(w, map[string]any{"ok": false, "error": "Hot reload needs a running debug/profile flutter session"})
		return
	}
	ok := m.deployer.HotReload()
	writeJSON(w, map[string]any{"ok": ok, "message": ternary(ok, "Hot reload sent (r)", m.deployer.Error())})
}

func (m *Monitor) handleHotRestart(w http.ResponseWriter, r *http.Request) {
	mode := m.cfg.MonitorMode
	if (mode != "debug" && mode != "profile") || m.deployer == nil || !m.deployer.HasActiveProcess() {
		writeJSON(w, map[string]any{"ok": false, "error": "Hot restart needs a running debug/profile flutter session"})
		return
	}
	ok := m.deployer.HotRestart()
	writeJSON(w, map[string]any{"ok": ok, "message": ternary(ok, "Hot restart sent (R)", m.deployer.Error())})
}

func (m *Monitor) handleStop(w http.ResponseWriter, r *http.Request) {
	if m.deployer == nil {
		writeJSON(w, map[string]any{"ok": false, "error": "No flutter process"})
		return
	}
	ok := m.deployer.Quit()
	if !ok {
		m.deployer.Stop()
		ok = true
	}
	writeJSON(w, map[string]any{"ok": ok, "message": "Stop sent"})
}

func (m *Monitor) handleReinstall(w http.ResponseWriter, r *http.Request) {
	if m.deployer == nil {
		writeJSON(w, map[string]any{"ok": false, "error": "Deployer unavailable"})
		return
	}
	if m.streamer != nil {
		m.streamer.RestartForReinstall()
	}
	ok := m.deployer.Reinstall()
	if !ok {
		writeJSON(w, map[string]any{"ok": false, "error": m.deployer.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": "Reinstall started"})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func ternary(cond bool, a, b string) string {
	if cond {
		return a
	}
	return b
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func lanIPv4() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ip = ip.To4()
			if ip != nil {
				return ip.String()
			}
		}
	}
	return ""
}

func readPubName(root string) string {
	data, err := os.ReadFile(filepath.Join(root, "pubspec.yaml"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "name:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "name:"))
		}
	}
	return ""
}

func parseRef(ref string) (string, int, int) {
	parts := strings.Split(ref, ":")
	if len(parts) < 2 {
		return ref, 1, 1
	}
	// Windows drive letter: C:\...
	path := parts[0]
	idx := 1
	if len(parts[0]) == 1 && len(parts) >= 3 {
		path = parts[0] + ":" + parts[1]
		idx = 2
	} else {
		// package:foo/bar.dart:10:2 — join until .dart
		if strings.HasPrefix(ref, "package:") || strings.Contains(ref, ".dart:") {
			dartIdx := strings.LastIndex(ref, ".dart:")
			if dartIdx >= 0 {
				path = ref[:dartIdx+5]
				rest := strings.Split(ref[dartIdx+6:], ":")
				line, col := 1, 1
				fmt.Sscanf(rest[0], "%d", &line)
				if len(rest) > 1 {
					fmt.Sscanf(rest[1], "%d", &col)
				}
				return path, line, col
			}
		}
	}
	line, col := 1, 1
	if idx < len(parts) {
		fmt.Sscanf(parts[idx], "%d", &line)
	}
	if idx+1 < len(parts) {
		fmt.Sscanf(parts[idx+1], "%d", &col)
	}
	return path, line, col
}

func resolvePath(projectRoot, path string) string {
	if strings.HasPrefix(path, "package:") {
		rest := strings.TrimPrefix(path, "package:")
		slash := strings.Index(rest, "/")
		if slash < 0 {
			return ""
		}
		pkg, rel := rest[:slash], rest[slash+1:]
		name := readPubName(projectRoot)
		if pkg == name {
			candidate := filepath.Join(projectRoot, "lib", rel)
			if fileExists(candidate) {
				return candidate
			}
		}
		return ""
	}
	if filepath.IsAbs(path) && fileExists(path) {
		return path
	}
	candidate := filepath.Join(projectRoot, path)
	if fileExists(candidate) {
		return candidate
	}
	return ""
}

func defaultOpener() string {
	if deploy.Which("cursor") {
		return "cursor"
	}
	if deploy.Which("code") {
		return "code"
	}
	return "open"
}
