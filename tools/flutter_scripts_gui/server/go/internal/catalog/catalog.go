package catalog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"unicode"
)

// Script is one menu entry (parity with lib/script_catalog.sh).
type Script struct {
	Index       int    `json:"index"`
	File        string `json:"file"`
	Label       string `json:"label"`
	Description string `json:"description"`
}

type sharedEntry struct {
	Label       string `json:"label"`
	Description string `json:"description"`
}

type sharedFile struct {
	Scripts map[string]sharedEntry `json:"scripts"`
}

var (
	sharedOnce sync.Once
	shared     map[string]sharedEntry
)

var internalScripts = map[string]struct{}{
	"build-android.sh":         {},
	"build-ios-ipa.sh":         {},
	"build_android_apk.sh":     {},
	"build_ios_ipa.sh":         {},
	"classify-version-bump.sh": {},
	"rtk-locate.sh":            {},
}

var labels = map[string]string{
	"build_android.sh":              "flutter-build-android",
	"build_ios.sh":                  "flutter-build-ios",
	"clear_pub_cache.sh":            "flutter-clear-pub-cache",
	"get_iam_token.sh":              "flutter-get-iam-token",
	"inspect_apk_environment.sh":    "flutter-inspect-apk",
	"classify_version_bump.sh":      "flutter-classify-version-bump",
	"build_mobile_release.sh":       "flutter-build-mobile",
	"setup_packages.sh":             "flutter-setup-packages",
	"device-logs.sh":                "device-logs",
	"android-logcat.sh":             "android-logcat",
	"ios-device-logs.sh":             "ios-device-logs",
	"open-isolate-monitor.sh":       "isolate-monitor",
	"open-flutter-scripts-gui.sh":   "flutter-scripts-gui",
	"release_package.sh":            "release-package",
	"build_both_release_apks.sh":    "flutter-build-both-release-apks",
	"check_git_identity.sh":         "check-git-identity",
	"install_global.sh":             "install-global",
	"install-device-logs-global.sh": "install-device-logs-global",
	"setup.sh":                      "setup (first-time)",
}

var descriptions = map[string]string{
	"android-logcat.sh":             "Stream Android logcat for the app package on a connected device",
	"build_android.sh":              "Build a release Android APK or App Bundle with env checks",
	"build_both_release_apks.sh":    "Build release APKs for two Flutter apps in one run",
	"build_ios.sh":                  "Build a release iOS IPA with env checks",
	"build_mobile_release.sh":       "Build apk or ipa for prod/dev with a single command",
	"check_git_identity.sh":         "Show git commit author vs GitHub account used by gh",
	"classify_version_bump.sh":      "Classify semver bump (major/minor/patch) for a release",
	"clear_pub_cache.sh":            "Clear or repair Dart/Flutter pub cache entries",
	"device-logs.sh":                "Stream device logs for android or ios (wrapper)",
	"get_iam_token.sh":              "Run tool/get_iam_token.dart OTP helper in the project",
	"inspect_apk_environment.sh":    "Guess prod vs dev build from host strings inside an APK",
	"install-device-logs-global.sh": "Install device-log commands to ~/.local/bin",
	"install_global.sh":             "Install or relink all script commands to ~/.local/bin",
	"ios-device-logs.sh":             "Stream iOS simulator or device logs for the app bundle id",
	"open-isolate-monitor.sh":       "Deploy debug/release to device; isolates (debug) or device logs (release)",
	"open-flutter-scripts-gui.sh":   "Open this flutter-scripts web GUI",
	"release_package.sh":            "Config-driven release for any Flutter git package (see release.config.sh per package)",
	"setup.sh":                      "One-time bootstrap after clone (chmod, setup.env, global install)",
	"setup_packages.sh":             "Clone shared git packages listed in packages.list",
}

func loadShared(scriptsDir string) {
	sharedOnce.Do(func() {
		path := filepath.Join(scriptsDir, "tools", "flutter_scripts_gui", "shared", "script_catalog.json")
		data, err := os.ReadFile(path)
		if err != nil {
			shared = map[string]sharedEntry{}
			return
		}
		var file sharedFile
		if err := json.Unmarshal(data, &file); err != nil || file.Scripts == nil {
			shared = map[string]sharedEntry{}
			return
		}
		shared = file.Scripts
	})
}

func shouldInclude(base string, rel string) bool {
	if base == "flutter-scripts.sh" || base == "open-flutter-scripts-gui.sh" {
		return false
	}
	// Prefer scripts/… paths over repo-root wrapper stubs
	if rel == base {
		switch base {
		case "open-isolate-monitor.sh", "setup.sh", "install_global.sh":
			return false
		}
	}
	if _, ok := internalScripts[base]; ok {
		return false
	}
	return true
}

func labelFor(base string) string {
	if shared != nil {
		if v, ok := shared[base]; ok && strings.TrimSpace(v.Label) != "" {
			return v.Label
		}
	}
	if v, ok := labels[base]; ok {
		return v
	}
	name := strings.TrimSuffix(base, ".sh")
	name = strings.ReplaceAll(name, "_", " ")
	name = strings.ReplaceAll(name, "-", " ")
	parts := strings.Fields(name)
	for i, p := range parts {
		runes := []rune(p)
		if len(runes) == 0 {
			continue
		}
		runes[0] = unicode.ToUpper(runes[0])
		parts[i] = string(runes)
	}
	return strings.Join(parts, " ")
}

func descriptionFor(base string) string {
	if shared != nil {
		if v, ok := shared[base]; ok && strings.TrimSpace(v.Description) != "" {
			return v.Description
		}
	}
	if v, ok := descriptions[base]; ok {
		return v
	}
	name := strings.TrimSuffix(filepath.Base(base), ".sh")
	return "Run " + name + " helper script"
}

// Discover lists runnable *.sh under scripts/<category>/ (and legacy top-level).
func Discover(scriptsDir string) ([]Script, error) {
	loadShared(scriptsDir)
	seen := map[string]struct{}{}
	var names []string

	collect := func(dir string, maxDepth int) error {
		return filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if d.IsDir() {
				if path == dir {
					return nil
				}
				rel, relErr := filepath.Rel(dir, path)
				if relErr != nil {
					return nil
				}
				depth := 1
				if rel != "." {
					depth = len(strings.Split(rel, string(os.PathSeparator)))
				}
				if depth > maxDepth {
					return filepath.SkipDir
				}
				return nil
			}
			name := d.Name()
			if !strings.HasSuffix(name, ".sh") {
				return nil
			}
			rel, relErr := filepath.Rel(scriptsDir, path)
			if relErr != nil {
				return nil
			}
			rel = filepath.ToSlash(rel)
			base := filepath.Base(rel)
			if !shouldInclude(base, rel) {
				return nil
			}
			if _, ok := seen[rel]; ok {
				return nil
			}
			seen[rel] = struct{}{}
			names = append(names, rel)
			return nil
		})
	}

	scriptsRoot := filepath.Join(scriptsDir, "scripts")
	if st, err := os.Stat(scriptsRoot); err == nil && st.IsDir() {
		_ = collect(scriptsRoot, 2)
	}
	// Legacy top-level *.sh
	entries, err := os.ReadDir(scriptsDir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".sh") {
			continue
		}
		if !shouldInclude(name, name) {
			continue
		}
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}
		names = append(names, name)
	}

	sort.Strings(names)

	out := make([]Script, 0, len(names))
	for i, name := range names {
		base := filepath.Base(name)
		out = append(out, Script{
			Index:       i + 1,
			File:        name,
			Label:       labelFor(base),
			Description: descriptionFor(base),
		})
	}
	return out, nil
}
