package backend

import (
	"os"
	"path/filepath"
	"strings"
)

const (
	Dart       = "dart"
	Go         = "go"
	TypeScript = "typescript"
	RestartCode = 100
)

func Normalize(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "go":
		return Go
	case "ts", "typescript", "node":
		return TypeScript
	default:
		return Dart
	}
}

func IsRunnable(backend string) bool {
	switch Normalize(backend) {
	case Dart, Go:
		return true
	default:
		return false
	}
}

func Available() []string {
	return []string{Dart, Go, TypeScript}
}

func Runnable() []string {
	return []string{Dart, Go}
}

func Hint(backend string) string {
	switch Normalize(backend) {
	case Go:
		return "server/go"
	case TypeScript:
		return "server/typescript"
	default:
		return "server/dart (live: bin/ + lib/)"
	}
}

func PrefFile(toolRoot string) string {
	return filepath.Join(toolRoot, ".backend-lang")
}

func ReadPreferred(toolRoot string) string {
	data, err := os.ReadFile(PrefFile(toolRoot))
	if err == nil {
		if v := strings.TrimSpace(string(data)); v != "" {
			return Normalize(v)
		}
	}
	if v := strings.TrimSpace(os.Getenv("ISOLATE_MONITOR_BACKEND")); v != "" {
		return Normalize(v)
	}
	return Dart
}

func WritePreferred(toolRoot, backend string) error {
	return os.WriteFile(PrefFile(toolRoot), []byte(Normalize(backend)+"\n"), 0o644)
}

func StatusMessage(preferred string) string {
	p := Normalize(preferred)
	if IsRunnable(p) {
		return "Restarting monitor with " + p + " backend…"
	}
	return "Preference set to " + p + " (" + Hint(p) + "). Only Dart/Go are runnable today."
}
