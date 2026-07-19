package localization

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type l10nYAMLConfig struct {
	ArbDir                 string
	TemplateArbFile        string
	OutputLocalizationFile string
	SyntheticPackage       bool
}

type arbDiscoveryResult struct {
	Files        []string
	ByBaseName   map[string]string
	ArbDir       string
	TemplatePath string
	Bootstrapped bool
	Notes        []string
}

var (
	arbLocaleSuffixRe = regexp.MustCompile(`^(.+)_([a-z]{2}(?:_[A-Za-z0-9]+)?)$`)
	arbBareLocaleRe   = regexp.MustCompile(`^([a-z]{2}(?:_[A-Za-z0-9]+)?)$`)
)

func discoverOrBootstrapArb(project string) (arbDiscoveryResult, error) {
	if found, err := discoverArbFiles(project); err != nil {
		return arbDiscoveryResult{}, err
	} else if len(found.Files) > 0 {
		return found, nil
	}
	bootstrapped, err := bootstrapL10n(project, readL10nYAMLConfig(project))
	if err != nil {
		return arbDiscoveryResult{}, err
	}
	return bootstrapped, nil
}

func discoverArbFiles(project string) (arbDiscoveryResult, error) {
	cfg := readL10nYAMLConfig(project)
	var dirs []string
	seenDir := map[string]struct{}{}
	addDir := func(rel string) {
		rel = strings.TrimSpace(rel)
		if rel == "" {
			return
		}
		abs := filepath.Clean(filepath.Join(project, filepath.FromSlash(rel)))
		if _, ok := seenDir[abs]; ok {
			return
		}
		if st, err := os.Stat(abs); err == nil && st.IsDir() {
			seenDir[abs] = struct{}{}
			dirs = append(dirs, abs)
		}
	}

	if cfg.ArbDir != "" {
		addDir(cfg.ArbDir)
	}
	for _, rel := range []string{"lib/l10n", "l10n", "lib/localization", "assets/l10n", "res/l10n"} {
		addDir(rel)
	}

	files := map[string]struct{}{}
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".arb") {
				continue
			}
			path := filepath.Join(dir, e.Name())
			// Include even temporarily invalid ARBs — Run() heals known corruption.
			if looksLikeArbCandidate(path) {
				files[path] = struct{}{}
			}
		}
	}

	if len(files) == 0 {
		_ = filepath.WalkDir(project, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				if d != nil && d.IsDir() && shouldSkipArbSearchDir(d.Name()) {
					return filepath.SkipDir
				}
				return nil
			}
			if !strings.HasSuffix(strings.ToLower(d.Name()), ".arb") {
				return nil
			}
			if looksLikeArbCandidate(path) {
				files[path] = struct{}{}
			}
			return nil
		})
	}

	if len(files) == 0 {
		return arbDiscoveryResult{}, nil
	}

	result := arbDiscoveryResult{
		Files:      make([]string, 0, len(files)),
		ByBaseName: map[string]string{},
	}
	for path := range files {
		result.Files = append(result.Files, path)
		result.ByBaseName[filepath.Base(path)] = path
	}
	sort.Strings(result.Files)

	if cfg.TemplateArbFile != "" {
		for _, path := range result.Files {
			if filepath.Base(path) == cfg.TemplateArbFile {
				result.TemplatePath = path
				result.ArbDir = filepath.Dir(path)
				break
			}
		}
	}
	if result.TemplatePath == "" {
		result.TemplatePath = chooseTemplateArb(result.Files)
		result.ArbDir = filepath.Dir(result.TemplatePath)
	}
	return result, nil
}

func bootstrapL10n(project string, cfg l10nYAMLConfig) (arbDiscoveryResult, error) {
	arbDirRel := cfg.ArbDir
	if arbDirRel == "" {
		arbDirRel = "lib/l10n"
	}
	templateName := cfg.TemplateArbFile
	if templateName == "" {
		templateName = "app_en.arb"
	}
	outputFile := cfg.OutputLocalizationFile
	if outputFile == "" {
		outputFile = "app_localizations.dart"
	}

	arbDir := filepath.Join(project, filepath.FromSlash(arbDirDirRel(arbDirRel)))
	if err := os.MkdirAll(arbDir, 0o755); err != nil {
		return arbDiscoveryResult{}, fmt.Errorf("create arb dir %s: %w", arbDir, err)
	}

	l10nPath := filepath.Join(project, "l10n.yaml")
	if _, err := os.Stat(l10nPath); err != nil {
		content := fmt.Sprintf(`arb-dir: %s
template-arb-file: %s
output-localization-file: %s
`, arbDirRel, templateName, outputFile)
		if err := os.WriteFile(l10nPath, []byte(content), 0o644); err != nil {
			return arbDiscoveryResult{}, fmt.Errorf("write l10n.yaml: %w", err)
		}
	}

	templatePath := filepath.Join(arbDir, templateName)
	if _, err := os.Stat(templatePath); err != nil {
		locale := localeFromArbName(templateName)
		if locale == "" {
			locale = "en"
		}
		stub := fmt.Sprintf("{\n  \"@@locale\": %q\n}\n", locale)
		if err := os.WriteFile(templatePath, []byte(stub), 0o644); err != nil {
			return arbDiscoveryResult{}, fmt.Errorf("write template arb: %w", err)
		}
	}

	notes := []string{
		fmt.Sprintf("Created Flutter l10n scaffold (%s, l10n.yaml). Add locale ARB files as needed.", arbDirRel),
	}
	return arbDiscoveryResult{
		Files:        []string{templatePath},
		ByBaseName:   map[string]string{templateName: templatePath},
		ArbDir:       arbDir,
		TemplatePath: templatePath,
		Bootstrapped: true,
		Notes:        notes,
	}, nil
}

func arbDirDirRel(rel string) string {
	return strings.TrimPrefix(strings.TrimSpace(rel), "./")
}

func readL10nYAMLConfig(project string) l10nYAMLConfig {
	path := filepath.Join(project, "l10n.yaml")
	b, err := os.ReadFile(path)
	if err != nil {
		return l10nYAMLConfig{}
	}
	cfg := l10nYAMLConfig{}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		val = strings.Trim(strings.TrimSpace(val), `"'`)
		switch key {
		case "arb-dir":
			cfg.ArbDir = val
		case "template-arb-file":
			cfg.TemplateArbFile = val
		case "output-localization-file":
			cfg.OutputLocalizationFile = val
		case "synthetic-package":
			cfg.SyntheticPackage = strings.EqualFold(val, "true")
		}
	}
	return cfg
}

func shouldSkipArbSearchDir(name string) bool {
	switch name {
	case ".dart_tool", "build", ".git", "node_modules", "Pods", ".symlinks", "ios", "android", "macos", "windows", "linux", "web", "coverage", "dist", ".fvm", "vendor":
		return true
	default:
		return strings.HasPrefix(name, ".")
	}
}

func isValidArbFile(path string) bool {
	if !looksLikeArbCandidate(path) {
		return false
	}
	b, err := os.ReadFile(path)
	if err != nil || len(bytesTrimSpace(b)) == 0 {
		return false
	}
	if json.Valid(b) {
		return true
	}
	if repaired, ok := repairLiteralEscapesInARB(b); ok {
		_ = os.WriteFile(path, append(repaired, '\n'), 0o644)
		return true
	}
	return false
}

func looksLikeArbCandidate(path string) bool {
	if !strings.HasSuffix(strings.ToLower(filepath.Base(path)), ".arb") {
		return false
	}
	b, err := os.ReadFile(path)
	if err != nil || len(bytesTrimSpace(b)) == 0 {
		return false
	}
	trimmed := strings.TrimSpace(string(b))
	return strings.HasPrefix(trimmed, "{")
}

func bytesTrimSpace(b []byte) []byte {
	return []byte(strings.TrimSpace(string(b)))
}

func chooseTemplateArb(files []string) string {
	prefs := []string{"app_en.arb", "app_en_US.arb", "intl_en.arb", "en.arb", "en_US.arb"}
	for _, pref := range prefs {
		for _, path := range files {
			if filepath.Base(path) == pref {
				return path
			}
		}
	}
	for _, path := range files {
		if strings.Contains(filepath.Base(path), "_en") || strings.HasPrefix(filepath.Base(path), "en") {
			return path
		}
	}
	return files[0]
}

func localeFromArbName(name string) string {
	base := strings.TrimSuffix(name, ".arb")
	if m := arbLocaleSuffixRe.FindStringSubmatch(base); len(m) == 3 {
		return m[2]
	}
	if m := arbBareLocaleRe.FindStringSubmatch(base); len(m) == 2 {
		return m[1]
	}
	return ""
}

func templateLocaleFromDiscovery(files []string, templatePath string) string {
	if templatePath != "" {
		return templatePath
	}
	return chooseTemplateArb(files)
}

func arbPathsForApply(byBase map[string]string) []string {
	out := make([]string, 0, len(byBase))
	for _, path := range byBase {
		out = append(out, path)
	}
	sort.Strings(out)
	return out
}

func arbDirHint(project, arbDir string) string {
	if rel, err := filepath.Rel(project, arbDir); err == nil && !strings.HasPrefix(rel, "..") {
		return filepath.ToSlash(rel)
	}
	return filepath.ToSlash(arbDir)
}
