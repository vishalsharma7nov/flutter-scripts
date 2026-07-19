package project

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	gitURLRe = regexp.MustCompile(`(?i)^(https?://|git@|ssh://|git://)`)
	ghShort  = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
)

// IsFlutterProject matches lib/flutter_project.sh _is_flutter_project.
func IsFlutterProject(dir string) bool {
	pubspec := filepath.Join(dir, "pubspec.yaml")
	data, err := os.ReadFile(pubspec)
	if err != nil {
		return false
	}
	if _, err := os.Stat(filepath.Join(dir, "lib")); err != nil {
		return false
	}
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "flutter:") {
			return true
		}
	}
	return false
}

// IsFlutterApp prefers apps with android/ or ios/ (build scripts).
func IsFlutterApp(dir string) bool {
	if !IsFlutterProject(dir) {
		return false
	}
	_, androidErr := os.Stat(filepath.Join(dir, "android"))
	_, iosErr := os.Stat(filepath.Join(dir, "ios"))
	return androidErr == nil || iosErr == nil
}

// NormalizeSource turns a pasted value into a local path or git clone URL.
func NormalizeSource(raw string) (kind string, value string, err error) {
	raw = strings.TrimSpace(raw)
	raw = strings.Trim(raw, `"'`)
	if raw == "" {
		return "", "", fmt.Errorf("empty project source")
	}

	// Expand ~
	if strings.HasPrefix(raw, "~/") {
		home, _ := os.UserHomeDir()
		raw = filepath.Join(home, raw[2:])
	}

	// Local path
	if strings.HasPrefix(raw, "/") || strings.HasPrefix(raw, ".") || strings.HasPrefix(raw, "~") {
		abs, err := filepath.Abs(raw)
		if err != nil {
			return "", "", err
		}
		return "path", abs, nil
	}
	if info, err := os.Stat(raw); err == nil && info.IsDir() {
		abs, err := filepath.Abs(raw)
		if err != nil {
			return "", "", err
		}
		return "path", abs, nil
	}

	// owner/repo shorthand → GitHub
	if ghShort.MatchString(raw) && !strings.Contains(raw, ":") {
		return "git", "https://github.com/" + raw + ".git", nil
	}

	if gitURLRe.MatchString(raw) {
		return "git", raw, nil
	}

	// file://
	if strings.HasPrefix(raw, "file://") {
		return "path", strings.TrimPrefix(raw, "file://"), nil
	}

	return "", "", fmt.Errorf("not a local path or git URL: %s", raw)
}

// RepoNameFromURL derives a folder name from a git remote.
func RepoNameFromURL(url string) string {
	u := strings.TrimSpace(url)
	u = strings.TrimSuffix(u, "/")
	u = strings.TrimSuffix(u, ".git")
	if i := strings.LastIndex(u, "/"); i >= 0 {
		u = u[i+1:]
	}
	if i := strings.LastIndex(u, ":"); i >= 0 {
		u = u[i+1:]
		if j := strings.LastIndex(u, "/"); j >= 0 {
			u = u[j+1:]
		}
	}
	u = strings.ReplaceAll(u, " ", "-")
	if u == "" {
		return "flutter-project"
	}
	return u
}

// DefaultCloneParent prefers ~/StudioProjects when present.
func DefaultCloneParent() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	studio := filepath.Join(home, "StudioProjects")
	if info, err := os.Stat(studio); err == nil && info.IsDir() {
		return studio
	}
	dir := filepath.Join(home, "Documents", "flutter-scripts-clones")
	_ = os.MkdirAll(dir, 0o755)
	return dir
}

// ResolveLocalPath validates a local Flutter project directory.
func ResolveLocalPath(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(abs)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("path is not a directory: %s", abs)
	}
	if !IsFlutterProject(abs) {
		return "", fmt.Errorf("not a Flutter project (need pubspec.yaml with flutter: and lib/): %s", abs)
	}
	return abs, nil
}

// LogFn receives clone progress lines.
type LogFn func(line string)

// CloneOrReuse clones url into parent/name, or reuses an existing Flutter checkout.
func CloneOrReuse(url, parent string, log LogFn) (string, error) {
	if log == nil {
		log = func(string) {}
	}
	name := RepoNameFromURL(url)
	dest := filepath.Join(parent, name)

	if info, err := os.Stat(dest); err == nil && info.IsDir() {
		if IsFlutterProject(dest) {
			log(fmt.Sprintf("Reusing existing Flutter project at %s", dest))
			return dest, nil
		}
		return "", fmt.Errorf("destination exists but is not a Flutter project: %s", dest)
	}

	log(fmt.Sprintf("Cloning %s → %s", url, dest))
	cmd := exec.Command("git", "clone", "--progress", url, dest)
	cmd.Env = os.Environ()
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", err
	}
	if err := cmd.Start(); err != nil {
		return "", err
	}
	pump := func(r *bufio.Scanner) {
		for r.Scan() {
			log(r.Text())
		}
	}
	go pump(bufio.NewScanner(stdout))
	go pump(bufio.NewScanner(stderr))
	if err := cmd.Wait(); err != nil {
		_ = os.RemoveAll(dest)
		return "", fmt.Errorf("git clone failed: %w", err)
	}

	if !IsFlutterProject(dest) {
		return dest, fmt.Errorf("cloned successfully but not Flutter-compatible (need pubspec.yaml with flutter: and lib/): %s", dest)
	}
	log(fmt.Sprintf("Flutter project ready: %s", dest))
	return dest, nil
}

// Nearby lists Flutter apps under common local roots (parity with flutter_project.sh).
type Nearby struct {
	Path         string `json:"path"`
	Name         string `json:"name"`
	IsFlutterApp bool   `json:"isFlutterApp"`
	IsCurrent    bool   `json:"isCurrent,omitempty"`
}

func DiscoverNearby(current string, maxDepth int) []Nearby {
	if maxDepth <= 0 {
		maxDepth = 2
	}
	home, _ := os.UserHomeDir()
	roots := []string{}
	seenRoot := map[string]struct{}{}
	addRoot := func(dir string) {
		if dir == "" {
			return
		}
		info, err := os.Stat(dir)
		if err != nil || !info.IsDir() {
			return
		}
		abs, err := filepath.Abs(dir)
		if err != nil {
			return
		}
		if _, ok := seenRoot[abs]; ok {
			return
		}
		seenRoot[abs] = struct{}{}
		roots = append(roots, abs)
	}

	if cwd, err := os.Getwd(); err == nil {
		addRoot(cwd)
		if IsFlutterApp(cwd) {
			// Prefer showing the cwd project even when scanning parent later.
		}
	}
	if home != "" {
		addRoot(filepath.Join(home, "StudioProjects"))
		addRoot(filepath.Join(home, "Documents", "StudioProjects"))
		addRoot(filepath.Join(home, "dev"))
		addRoot(filepath.Join(home, "Projects"))
	}
	if current != "" {
		addRoot(filepath.Dir(current))
	}

	seen := map[string]struct{}{}
	out := make([]Nearby, 0, 16)
	addProj := func(dir string) {
		abs, err := filepath.Abs(dir)
		if err != nil {
			return
		}
		if _, ok := seen[abs]; ok {
			return
		}
		if !IsFlutterProject(abs) {
			return
		}
		seen[abs] = struct{}{}
		out = append(out, Nearby{
			Path:         abs,
			Name:         filepath.Base(abs),
			IsFlutterApp: IsFlutterApp(abs),
			IsCurrent:    current != "" && abs == current,
		})
	}

	if current != "" && IsFlutterProject(current) {
		addProj(current)
	}

	for _, root := range roots {
		if IsFlutterApp(root) {
			addProj(root)
		}
		_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if !d.IsDir() {
				return nil
			}
			rel, relErr := filepath.Rel(root, path)
			if relErr != nil {
				return nil
			}
			if rel == "." {
				return nil
			}
			depth := strings.Count(rel, string(os.PathSeparator)) + 1
			if depth > maxDepth {
				return filepath.SkipDir
			}
			base := d.Name()
			if base == ".git" || base == "build" || base == ".dart_tool" ||
				base == "node_modules" || base == "ios" || base == "android" ||
				base == "macos" || base == "linux" || base == "windows" || base == "web" {
				return filepath.SkipDir
			}
			if IsFlutterProject(path) {
				addProj(path)
				return filepath.SkipDir
			}
			return nil
		})
	}

	return out
}

