package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/flutter-scripts/isolate_monitor/internal/deploy"
	"github.com/flutter-scripts/isolate_monitor/internal/server"
)

func main() {
	port := flag.Int("port", 8765, "Web GUI port")
	project := flag.String("project", "", "Flutter project root")
	pkg := flag.String("package", "", "Android applicationId")
	bundleID := flag.String("bundle-id", "", "iOS bundle identifier")
	device := flag.String("device", "", "Flutter device id / adb serial")
	mode := flag.String("mode", "debug", "debug, profile, or release")
	envFile := flag.String("env-file", "", "dart-define-from-file path")
	appEnv := flag.String("app-env", "", "APP_ENV dart-define value")
	uri := flag.String("uri", "", "Dart VM service URI override")
	releaseLogs := flag.Bool("release-logs", false, "Stream native device logs")
	useFVM := flag.Bool("use-fvm", false, "Run flutter through fvm")
	noFVM := flag.Bool("no-fvm", false, "Run flutter without fvm")
	autoDeploy := flag.Bool("auto-deploy", false, "Start flutter run when the monitor boots")
	autoOpenOnVM := flag.Bool("auto-open-on-vm", false, "Open browser when VM service connects")
	noAutoOpen := flag.Bool("no-auto-open", false, "Do not open browser")
	lan := flag.Bool("lan", false, "Listen on all network interfaces")
	host := flag.String("host", "", "Bind address")
	_ = releaseLogs
	_ = autoOpenOnVM
	_ = noAutoOpen
	flag.Parse()

	toolRoot, err := os.Getwd()
	if err != nil {
		fatal(err)
	}
	// Prefer server/go cwd -> tool root is ../..
	if filepath.Base(toolRoot) == "go" && filepath.Base(filepath.Dir(toolRoot)) == "server" {
		toolRoot = filepath.Clean(filepath.Join(toolRoot, "..", ".."))
	}

	monitorMode := normalizeMode(*mode)
	bindHost := resolveBindHost(*lan, *host)
	vmPort := 58888
	if v := strings.TrimSpace(os.Getenv("FLUTTER_VM_SERVICE_PORT")); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			vmPort = n
		}
	}
	fvm := !*noFVM && (*useFVM || deploy.DetectFVM())

	webDir := filepath.Join(toolRoot, "web")
	cfg := server.Config{
		Port:          *port,
		ToolRoot:      toolRoot,
		WebDir:        webDir,
		ProjectRoot:   strings.TrimSpace(*project),
		PackageName:   strings.TrimSpace(*pkg),
		BundleID:      strings.TrimSpace(*bundleID),
		DeviceID:      strings.TrimSpace(*device),
		MonitorMode:   monitorMode,
		EnvFile:       strings.TrimSpace(*envFile),
		AppEnv:        strings.TrimSpace(*appEnv),
		VMServicePort: vmPort,
		UseFVM:        fvm,
		BindHost:      bindHost,
		AutoDeploy:    *autoDeploy,
		URIOverride:   strings.TrimSpace(*uri),
	}

	m := server.New(cfg)
	if err := m.Start(); err != nil {
		fatal(err)
	}
}

func normalizeMode(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "profile":
		return "profile"
	case "release":
		return "release"
	default:
		return "debug"
	}
}

func resolveBindHost(lan bool, hostOption string) string {
	h := strings.ToLower(strings.TrimSpace(hostOption))
	if h == "lan" || h == "all" || h == "0.0.0.0" {
		return "0.0.0.0"
	}
	if h != "" {
		return hostOption
	}
	if lan {
		return "0.0.0.0"
	}
	return "127.0.0.1"
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
