package localization

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

type Request struct {
	Mode    string   `json:"mode"`
	Path    []string `json:"path,omitempty"`
	Apply   bool     `json:"apply,omitempty"`
	Analyze bool     `json:"analyze,omitempty"`
}

type Placeholder struct {
	Name string `json:"name"`
	Expr string `json:"expr"`
}

type SuggestionApply struct {
	Key          string        `json:"key"`
	ArbValue     string        `json:"arbValue"`
	Placeholders []Placeholder `json:"placeholders"`
	DartBefore   string        `json:"dartBefore,omitempty"`
	DartAfter    string        `json:"dartAfter,omitempty"`
	Line         int           `json:"line,omitempty"`
	Text         string        `json:"text,omitempty"`
	Safe         bool          `json:"safe,omitempty"`
}

type Suggestion struct {
	Kind         string          `json:"kind"`
	File         string          `json:"file"`
	Relative     string          `json:"relative"`
	Line         *int            `json:"line,omitempty"`
	Text         string          `json:"text"`
	SuggestedKey string          `json:"suggestedKey"`
	ArbEn        string          `json:"arbEn"`
	ArbEs        string          `json:"arbEs"`
	ArbFr        string          `json:"arbFr"`
	DartBefore   string          `json:"dartBefore"`
	DartAfter    string          `json:"dartAfter"`
	Steps        []string        `json:"steps"`
	Apply        SuggestionApply `json:"apply"`
}

type HardcodedItem struct {
	File     string `json:"file"`
	Relative string `json:"relative"`
	Line     int    `json:"line"`
	Text     string `json:"text"`
	Snippet  string `json:"snippet,omitempty"`
}

type MissingKey struct {
	Key      string   `json:"key"`
	Refs     []string `json:"refs"`
	File     string   `json:"file,omitempty"`
	Relative string   `json:"relative,omitempty"`
	Line     *int     `json:"line,omitempty"`
}

type CommandResult struct {
	Command  string `json:"command"`
	ExitCode int    `json:"exit_code"`
	OK       bool   `json:"ok"`
	Output   string `json:"output"`
}

type ApplyResult struct {
	Applied      bool     `json:"applied"`
	AppliedFiles []string `json:"applied_files"`
	ChangedKeys  []string `json:"changed_keys"`
	Skipped      []string `json:"skipped"`
}

type Result struct {
	Project          string         `json:"project"`
	Mode             string         `json:"mode"`
	ArbFiles         []string       `json:"arb_files"`
	Template         string         `json:"template"`
	TemplateKeyCount int            `json:"template_key_count"`
	Hardcoded        []HardcodedItem `json:"hardcoded"`
	HardcodedCount   int            `json:"hardcoded_count"`
	ParityIssues     []string       `json:"parity_issues"`
	MissingKeys      []MissingKey   `json:"missing_keys"`
	HardIssues       []string       `json:"hard_issues"`
	SoftIssues       []string       `json:"soft_issues"`
	HardIssueCount   int            `json:"hard_issue_count"`
	SoftIssueCount   int            `json:"soft_issue_count"`
	Suggestions      []Suggestion   `json:"suggestions"`
	SuggestionCount  int            `json:"suggestion_count"`
	ApplyResult      *ApplyResult   `json:"apply_result,omitempty"`
	L10nResult       *CommandResult `json:"l10n_result,omitempty"`
	AnalysisResult   *CommandResult `json:"analysis_result,omitempty"`
}

type arbData map[string]any

var (
	textRe       = regexp.MustCompile(`\bText\s*\(\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
	textViewRe   = regexp.MustCompile(`(?s)\bTextViewWidget\s*\([^;]*?\btext\s*:\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
	tabRe        = regexp.MustCompile(`(?s)\bTab\s*\([^)]*?\btext\s*:\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
	labelRe      = regexp.MustCompile(`\b(?:title|label|hintText|helperText|tooltip|message|buttonText|emptyMessage)\s*:\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
	l10nUsageRe  = regexp.MustCompile(`(?:context\.)?l10n\.([A-Za-z_][A-Za-z0-9_]*)`)
	interpRe     = regexp.MustCompile(`\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)`)
	camelIgnore  = regexp.MustCompile(`^[a-z]+([A-Z][a-z0-9]+)+$`)
	shortVarRe   = regexp.MustCompile(`^[a-z0-9_]+$`)
	lettersRe    = regexp.MustCompile(`[A-Za-zÀ-ÿ]`)
	allCapsRe    = regexp.MustCompile(`^[A-Z0-9_]{2,}$`)
	numericRe    = regexp.MustCompile(`^[0-9.\s:+\-/%]+$`)
	colorRe      = regexp.MustCompile(`^#[0-9A-Fa-f]{3,8}$`)
	braceOnlyRe  = regexp.MustCompile(`^\{.+\}$`)
	assetExtRe   = regexp.MustCompile(`^[a-z0-9_./-]+\.(png|jpg|jpeg|svg|webp|json|arb|dart|ttf|otf)$`)
	quotedRe     = regexp.MustCompile(`\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'`)
)

var ignoreLineHints = []string{
	"debugPrint", "print(", "log(", "developer.log", "Logger(", "// ignore", "assert(", "Key(", "ValueKey(",
}

func Run(project string, req Request) (Result, error) {
	project, _ = filepath.Abs(project)
	if req.Mode == "" {
		req.Mode = "full"
	}
	if _, err := os.Stat(filepath.Join(project, "pubspec.yaml")); err != nil {
		return Result{}, fmt.Errorf("not a Flutter project (missing pubspec.yaml): %s", project)
	}
	libRoot := filepath.Join(project, "lib")
	if st, err := os.Stat(libRoot); err != nil || !st.IsDir() {
		return Result{}, fmt.Errorf("missing Dart lib directory: %s", libRoot)
	}
	allow, err := normalizeAllow(libRoot, req.Path)
	if err != nil {
		return Result{}, err
	}
	discovery, err := discoverOrBootstrapArb(project)
	if err != nil {
		return Result{}, err
	}
	if len(discovery.Files) == 0 {
		return Result{}, fmt.Errorf("no .arb localization files found in %s (checked l10n.yaml arb-dir, lib/l10n, and project tree)", project)
	}
	healed, healNotes := healArbFiles(discovery.Files)
	discovery.Notes = append(discovery.Notes, healNotes...)
	if len(healed) > 0 {
		discovery.Files = healed
		discovery.ByBaseName = map[string]string{}
		for _, p := range healed {
			discovery.ByBaseName[filepath.Base(p)] = p
		}
		if discovery.TemplatePath == "" || !pathInList(discovery.TemplatePath, healed) {
			discovery.TemplatePath = chooseTemplateArb(healed)
			discovery.ArbDir = filepath.Dir(discovery.TemplatePath)
		}
	}
	arbFiles := discovery.Files
	template := templateLocaleFromDiscovery(arbFiles, discovery.TemplatePath)
	templateKeys, _, err := loadArbKeys(template)
	if err != nil {
		return Result{}, err
	}
	arbDirRel := arbDirHint(project, discovery.ArbDir)

	res := Result{
		Project:          project,
		Mode:             req.Mode,
		Template:         filepath.Base(template),
		TemplateKeyCount: len(templateKeys),
		Hardcoded:        []HardcodedItem{},
		ParityIssues:     []string{},
		MissingKeys:      []MissingKey{},
		HardIssues:       []string{},
		SoftIssues:       []string{},
		Suggestions:      []Suggestion{},
	}
	for _, note := range discovery.Notes {
		res.SoftIssues = append(res.SoftIssues, note)
	}
	for _, p := range arbFiles {
		res.ArbFiles = append(res.ArbFiles, filepath.Base(p))
	}

	doHardcoded := req.Mode == "hardcoded" || req.Mode == "full" || req.Mode == "suggestions"
	doParity := req.Mode == "full" || req.Mode == "suggestions"
	doMissing := req.Mode == "full" || req.Mode == "suggestions"

	if doParity {
		res.ParityIssues, err = checkParity(arbFiles)
		if err != nil {
			return Result{}, err
		}
		res.HardIssues = append(res.HardIssues, res.ParityIssues...)
	}
	if doMissing {
		usages, err := findL10nUsages(libRoot, allow, project)
		if err != nil {
			return Result{}, err
		}
		for key, refs := range usages {
			if _, ok := templateKeys[key]; ok {
				continue
			}
			sort.Strings(refs)
			msg := fmt.Sprintf("[missing-key] l10n.%s used but not in %s (%s)", key, filepath.Base(template), strings.Join(head(refs, 3), ", "))
			res.HardIssues = append(res.HardIssues, msg)
			mk := MissingKey{Key: key, Refs: head(refs, 10)}
			if len(refs) > 0 {
				file, line := splitRef(refs[0])
				mk.File = file
				mk.Relative = relToProject(file, project)
				if line > 0 { mk.Line = &line }
			}
			res.MissingKeys = append(res.MissingKeys, mk)
		}
		sort.Slice(res.MissingKeys, func(i, j int) bool { return res.MissingKeys[i].Key < res.MissingKeys[j].Key })
	}
	if doHardcoded {
		res.Hardcoded, err = findHardcoded(libRoot, project, allow)
		if err != nil { return Result{}, err }
		for _, h := range res.Hardcoded {
			res.SoftIssues = append(res.SoftIssues, fmt.Sprintf(`[hardcoded] %s:%d %q`, h.Relative, h.Line, h.Text))
		}
	}
	if req.Mode == "suggestions" || req.Mode == "full" {
		res.Suggestions = buildSuggestions(res.Hardcoded, res.MissingKeys, templateKeys, arbDirRel, filepath.Base(template))
	}
	res.HardcodedCount = len(res.Hardcoded)
	res.HardIssueCount = len(res.HardIssues)
	res.SoftIssueCount = len(res.SoftIssues)
	res.SuggestionCount = len(res.Suggestions)

	if req.Apply {
		applied, dartPending, err := applyArbChanges(res.Suggestions, arbPathsForApply(discovery.ByBaseName))
		if err != nil {
			return Result{}, err
		}
		gen := generateL10n(project)
		res.L10nResult = &gen
		if gen.OK {
			dartApplied, dartSkipped, err := applyDartChanges(dartPending)
			if err != nil {
				return Result{}, err
			}
			for f := range dartApplied {
				applied.files[f] = struct{}{}
			}
			applied.Skipped = append(applied.Skipped, dartSkipped...)
		} else {
			for _, s := range dartPending {
				applied.Skipped = append(applied.Skipped,
					fmt.Sprintf("Skipped Dart change for l10n.%s — gen-l10n failed", s.Apply.Key))
			}
		}
		res.ApplyResult = finalizeApplyResult(applied)
		if req.Analyze {
			an := analyzeProject(project)
			res.AnalysisResult = &an
			if !an.OK {
				res.ApplyResult.Skipped = append(res.ApplyResult.Skipped,
					"Analyze failed after apply — fix remaining issues before committing")
			}
		}
	}
	return res, nil
}

func normalizeAllow(libRoot string, in []string) ([]string, error) {
	if len(in) == 0 { return nil, nil }
	var out []string
	for _, rel := range in {
		rel = strings.TrimSpace(rel)
		if rel == "" { continue }
		cand := filepath.Clean(filepath.Join(libRoot, rel))
		libAbs, _ := filepath.Abs(libRoot)
		candAbs, _ := filepath.Abs(cand)
		if !strings.HasPrefix(candAbs, libAbs) { return nil, fmt.Errorf("path escapes lib/: %s", rel) }
		if _, err := os.Stat(candAbs); err != nil { return nil, fmt.Errorf("path not found: %s", candAbs) }
		out = append(out, candAbs)
	}
	return out, nil
}

func loadArbKeys(path string) (map[string]string, arbData, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	var data arbData
	if err := json.Unmarshal(b, &data); err != nil {
		repaired, ok := repairLiteralEscapesInARB(b)
		if !ok {
			return nil, nil, fmt.Errorf("%s: %w", path, err)
		}
		if err2 := json.Unmarshal(repaired, &data); err2 != nil {
			return nil, nil, fmt.Errorf("%s: %w (after repair attempt)", path, err)
		}
		if writeErr := os.WriteFile(path, append(repaired, '\n'), 0o644); writeErr != nil {
			return nil, nil, fmt.Errorf("%s: repaired in memory but failed to write: %w", path, writeErr)
		}
	}
	keys := map[string]string{}
	for k, v := range data {
		if strings.HasPrefix(k, "@") {
			continue
		}
		if s, ok := v.(string); ok {
			keys[k] = s
		}
	}
	return keys, data, nil
}

// healArbFiles repairs known ARB corruption in any project and returns usable paths.
func healArbFiles(paths []string) ([]string, []string) {
	var out []string
	var notes []string
	seen := map[string]struct{}{}
	for _, path := range paths {
		if path == "" {
			continue
		}
		if _, ok := seen[path]; ok {
			continue
		}
		seen[path] = struct{}{}
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if json.Valid(b) {
			out = append(out, path)
			continue
		}
		repaired, ok := repairLiteralEscapesInARB(b)
		if !ok {
			notes = append(notes, fmt.Sprintf("Skipped unreadable ARB (invalid JSON): %s", path))
			continue
		}
		if err := os.WriteFile(path, append(repaired, '\n'), 0o644); err != nil {
			notes = append(notes, fmt.Sprintf("Could not rewrite repaired ARB %s: %v", path, err))
			continue
		}
		out = append(out, path)
		notes = append(notes, fmt.Sprintf("Auto-repaired invalid ARB JSON escapes in %s", filepath.Base(path)))
	}
	sort.Strings(out)
	return out, notes
}

func pathInList(path string, list []string) bool {
	for _, p := range list {
		if p == path {
			return true
		}
	}
	return false
}

// repairLiteralEscapesInARB fixes ARBs corrupted by an older writer that
// emitted literal "\n" / "\t" in JSON structure (Go raw-string bug).
// Only structural escapes are rewritten so values like "a\nb" stay intact.
func repairLiteralEscapesInARB(b []byte) ([]byte, bool) {
	s := string(b)
	if !strings.Contains(s, `{\n`) && !strings.Contains(s, `}\n`) && !strings.Contains(s, `,\n`) {
		return nil, false
	}
	fixed := s
	fixed = strings.ReplaceAll(fixed, `{\n`, "{\n")
	fixed = strings.ReplaceAll(fixed, `}\n`, "}\n")
	fixed = strings.ReplaceAll(fixed, `,\n`, ",\n")
	reKey := regexp.MustCompile(`\\n([ \t]+")`)
	fixed = reKey.ReplaceAllString(fixed, "\n$1")
	if json.Valid([]byte(fixed)) {
		return []byte(fixed), true
	}
	return nil, false
}

func checkParity(files []string) ([]string, error) {
	all := map[string]struct{}{}
	byLocale := map[string]map[string]string{}
	for _, p := range files {
		keys, _, err := loadArbKeys(p)
		if err != nil { return nil, err }
		byLocale[filepath.Base(p)] = keys
		for k := range keys { all[k] = struct{}{} }
	}
	allKeys := sortedKeys(all)
	var issues []string
	for locale, keys := range byLocale {
		for _, key := range allKeys {
			if _, ok := keys[key]; !ok { issues = append(issues, fmt.Sprintf("[parity] %s missing key: %s", locale, key)) }
		}
		for k, v := range keys {
			if strings.TrimSpace(v) == "" { issues = append(issues, fmt.Sprintf("[empty] %s key '%s' has empty value", locale, k)) }
		}
	}
	sort.Strings(issues)
	return issues, nil
}

func findL10nUsages(libRoot string, allow []string, project string) (map[string][]string, error) {
	out := map[string][]string{}
	err := walkDartFiles(libRoot, allow, func(path string) error {
		b, err := os.ReadFile(path)
		if err != nil { return nil }
		sc := bufio.NewScanner(bytes.NewReader(b))
		lineNo := 0
		for sc.Scan() {
			lineNo++
			line := sc.Text()
			if lineIgnored(line) { continue }
			matches := l10nUsageRe.FindAllStringSubmatch(line, -1)
			for _, m := range matches {
				key := m[1]
				if key == "of" || key == "delegate" || key == "supportedLocales" { continue }
				out[key] = append(out[key], fmt.Sprintf("%s:%d", path, lineNo))
			}
		}
		return nil
	})
	return out, err
}

func findHardcoded(libRoot, project string, allow []string) ([]HardcodedItem, error) {
	patterns := []*regexp.Regexp{textRe, textViewRe, tabRe, labelRe}
	seen := map[string]struct{}{}
	var items []HardcodedItem
	err := walkDartFiles(libRoot, allow, func(path string) error {
		b, err := os.ReadFile(path)
		if err != nil { return nil }
		content := string(b)
		lines := strings.Split(content, "\n")
		for _, pattern := range patterns {
			matches := pattern.FindAllStringIndex(content, -1)
			for _, m := range matches {
				start, end := m[0], m[1]
				segment := content[start:end]
				raw := quotedRe.FindString(segment)
				if len(raw) >= 2 && ((raw[0] == '"' && raw[len(raw)-1] == '"') || (raw[0] == '\'' && raw[len(raw)-1] == '\'')) {
					raw = raw[1 : len(raw)-1]
				}
				if raw == "" { continue }
				display := decodeEscapes(raw)
				if isInterpolationOnly(display) || !looksUserFacing(display) { continue }
				lineNo := 1 + strings.Count(content[:start], "\n")
				line := ""
				if lineNo-1 >= 0 && lineNo-1 < len(lines) { line = lines[lineNo-1] }
				if lineIgnored(line) || strings.Contains(line, "l10n.") || strings.Contains(line, "AppLocalizations") { continue }
				if lineHasComplexInterpolation(line) { continue }
				key := fmt.Sprintf("%s:%d:%s", path, lineNo, display)
				if _, ok := seen[key]; ok { continue }
				seen[key] = struct{}{}
				items = append(items, HardcodedItem{File: path, Relative: relToProject(path, project), Line: lineNo, Text: strings.ReplaceAll(display, "\n", `\n`), Snippet: trimLine(line)})
			}
		}
		return nil
	})
	sort.Slice(items, func(i,j int) bool { if items[i].Relative == items[j].Relative { return items[i].Line < items[j].Line }; return items[i].Relative < items[j].Relative })
	return items, err
}

func walkDartFiles(libRoot string, allow []string, fn func(string) error) error {
	return filepath.WalkDir(libRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil { return nil }
		if d.IsDir() {
			name := d.Name()
			if name == ".dart_tool" || name == "build" || name == ".git" || name == "generated" || name == "l10n" || name == "gen" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".dart") || strings.HasPrefix(filepath.Base(path), "app_localizations") { return nil }
		if !pathAllowed(path, allow) { return nil }
		return fn(path)
	})
}

func pathAllowed(path string, allow []string) bool {
	if len(allow) == 0 { return true }
	p, _ := filepath.Abs(path)
	for _, root := range allow {
		r, _ := filepath.Abs(root)
		if p == r || strings.HasPrefix(p, r+string(os.PathSeparator)) { return true }
	}
	return false
}

func decodeEscapes(s string) string {
	s = strings.ReplaceAll(s, `\n`, "\n")
	s = strings.ReplaceAll(s, `\"`, `"`)
	s = strings.ReplaceAll(s, `\'`, `'`)
	return s
}

func looksUserFacing(s string) bool {
	s = strings.TrimSpace(s)
	if len(s) < 2 || ignoreString(s) || !lettersRe.MatchString(s) { return false }
	if camelIgnore.MatchString(s) && !strings.Contains(s, " ") { return false }
	if shortVarRe.MatchString(s) && !strings.Contains(s, " ") && len(s) <= 24 { return false }
	return true
}

func ignoreString(s string) bool {
	if s == "" || strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://") || strings.HasPrefix(s, "assets/") || strings.HasPrefix(s, "package:") { return true }
	if assetExtRe.MatchString(s) || allCapsRe.MatchString(s) || numericRe.MatchString(s) || colorRe.MatchString(s) || braceOnlyRe.MatchString(s) { return true }
	return false
}

func lineIgnored(line string) bool {
	trimmed := strings.TrimSpace(line)
	if strings.HasPrefix(trimmed, "//") || strings.HasPrefix(trimmed, "*") { return true }
	for _, hint := range ignoreLineHints { if strings.Contains(line, hint) { return true } }
	return false
}

func isInterpolationOnly(text string) bool {
	stripped := interpRe.ReplaceAllString(strings.TrimSpace(text), "")
	return strings.TrimSpace(stripped) == "" && strings.TrimSpace(text) != ""
}

func localizeInterpolatedText(text string) (string, []Placeholder) {
	used := map[string]struct{}{}
	var placeholders []Placeholder
	out := interpRe.ReplaceAllStringFunc(text, func(m string) string {
		expr := strings.TrimPrefix(m, "$")
		expr = strings.TrimPrefix(expr, "{")
		expr = strings.TrimSuffix(expr, "}")
		name := placeholderName(expr, used)
		placeholders = append(placeholders, Placeholder{Name: name, Expr: strings.TrimSpace(expr)})
		return "{" + name + "}"
	})
	return out, placeholders
}

func placeholderName(expr string, used map[string]struct{}) string {
	cleaned := regexp.MustCompile(`[^A-Za-z0-9]+`).ReplaceAllString(strings.TrimSpace(expr), " ")
	words := strings.Fields(cleaned)
	base := "value"
	if len(words) > 0 {
		base = strings.ToLower(words[0])
		for _, w := range words[1:] { base += strings.ToUpper(w[:1]) + w[1:] }
	}
	if !regexp.MustCompile(`^[A-Za-z_]`).MatchString(base) { base = "value" + base }
	candidate := base
	for i:=2;;i++ {
		if _, ok := used[candidate]; !ok { used[candidate]=struct{}{}; return candidate }
		candidate = fmt.Sprintf("%s%d", base, i)
	}
}

func featurePrefix(relative string) string {
	parts := strings.Split(filepath.ToSlash(relative), "/")
	for i, part := range parts {
		if part == "features" && i+1 < len(parts) {
			feat := strings.TrimSuffix(parts[i+1], "-feature")
			feat = strings.ReplaceAll(feat, "-", "_")
			words := strings.FieldsFunc(feat, func(r rune) bool { return r == '_' })
			if len(words) > 0 { return words[0] }
		}
	}
	if strings.Contains(strings.ToLower(relative), "trip") { return "trips" }
	return "ui"
}

func toCamelKey(text string) string {
	cleaned := regexp.MustCompile(`[^A-Za-z0-9\s]`).ReplaceAllString(text, " ")
	words := strings.Fields(cleaned)
	if len(words) == 0 { return "message" }
	key := strings.ToLower(words[0])
	for _, w := range words[1:] { key += strings.ToUpper(w[:1]) + strings.ToLower(w[1:]) }
	if !regexp.MustCompile(`^[A-Za-z_]`).MatchString(key) { key = "msg" + key }
	if len(key) > 48 { key = key[:48] }
	return key
}

func suggestKey(text, relative string, existing map[string]string) string {
	prefix := featurePrefix(relative)
	base := toCamelKey(text)
	candidate := base
	if prefix != "" && len(base) > 0 { candidate = prefix + strings.ToUpper(base[:1]) + base[1:] }
	if strings.EqualFold(strings.TrimSpace(text), "schedule") || strings.EqualFold(strings.TrimSpace(text), "scheduled") { candidate = "tripsTabSchedule" }
	if _, ok := existing[candidate]; ok {
		for i:=2;;i++ {
			next := fmt.Sprintf("%s%d", candidate, i)
			if _, ok := existing[next]; !ok { candidate = next; break }
		}
	}
	existing[candidate] = text
	return candidate
}

func buildSuggestions(hardcoded []HardcodedItem, missing []MissingKey, existingKeys map[string]string, arbDir, templateBase string) []Suggestion {
	used := map[string]string{}
	for k, v := range existingKeys { used[k] = v }
	var out []Suggestion
	for _, item := range hardcoded {
		key := suggestKey(item.Text, item.Relative, used)
		localized, placeholders := localizeInterpolatedText(item.Text)
		callSuffix := ""
		if len(placeholders) > 0 {
			parts := make([]string, 0, len(placeholders))
			for _, p := range placeholders { parts = append(parts, p.Expr) }
			callSuffix = "(" + strings.Join(parts, ", ") + ")"
		}
		dartAfter := suggestionDart(item.Snippet, key, callSuffix)
		placeholderMeta := ""
		if len(placeholders) > 0 {
			parts := make([]string, 0, len(placeholders))
			for _, p := range placeholders {
				parts = append(parts, fmt.Sprintf(`"%s": {"type": "String"}`, p.Name))
			}
			placeholderMeta = fmt.Sprintf("\n  \"@%s\": {\n    \"placeholders\": { %s }\n  }", key, strings.Join(parts, ", "))
		}
		line := item.Line
		safe := len(placeholders) == 0 &&
			!lineHasComplexInterpolation(item.Snippet) &&
			isSafeDartReplacement(dartAfter)
		steps := []string{
			fmt.Sprintf("Step 1 — Add to %s/%s: %q: %s", arbDir, templateBase, key, mustJSON(localized)),
		}
		if len(placeholders) > 0 {
			steps = append(steps, fmt.Sprintf("Add @%s.placeholders for: %s", key, joinPlaceholderNames(placeholders)))
		}
		steps = append(steps,
			fmt.Sprintf("Step 2 — Add the same key to other locale ARB files under %s (translate %q)", arbDir, localized),
			"Step 3 — Run: fvm flutter gen-l10n",
			fmt.Sprintf("Step 4 — Replace hardcoded string with l10n.%s%s (positional args) in %s:%d", key, callSuffix, item.Relative, item.Line),
		)
		if needsL10nParam(item.File, item.Line) {
			steps = append(steps, "Step 5 — Pass AppLocalizations l10n into the helper (l10n is not in scope outside build())")
			safe = false
		}
		if !safe {
			steps = append(steps, "Auto-apply skipped — apply this change manually")
		}
		out = append(out, Suggestion{
			Kind: "hardcoded", File: item.File, Relative: item.Relative, Line: &line, Text: item.Text, SuggestedKey: key,
			ArbEn: fmt.Sprintf(`  "%s": %s%s`, key, mustJSON(localized), placeholderMeta),
			ArbEs: fmt.Sprintf(`  "%s": %s  // TODO: translate%s`, key, mustJSON(localized), placeholderMeta),
			ArbFr: fmt.Sprintf(`  "%s": %s  // TODO: translate%s`, key, mustJSON(localized), placeholderMeta),
			DartBefore: item.Snippet, DartAfter: dartAfter, Steps: steps,
			Apply: SuggestionApply{
				Key: key, ArbValue: localized, Placeholders: placeholders,
				DartBefore: item.Snippet, DartAfter: dartAfter,
				Line: item.Line, Text: item.Text, Safe: safe,
			},
		})
	}
	for _, item := range missing {
		english := inferEnglishFromKey(item.Key)
		out = append(out, Suggestion{
			Kind: "missing-key", File: item.File, Relative: item.Relative, Line: item.Line, SuggestedKey: item.Key,
			ArbEn: fmt.Sprintf(`  "%s": %s`, item.Key, mustJSON(english)),
			ArbEs: fmt.Sprintf(`  "%s": %s  // TODO: translate`, item.Key, mustJSON(english)),
			ArbFr: fmt.Sprintf(`  "%s": %s  // TODO: translate`, item.Key, mustJSON(english)),
			DartBefore: fmt.Sprintf("l10n.%s", item.Key),
			DartAfter:  fmt.Sprintf("l10n.%s  // already in Dart; ARB key was missing", item.Key),
			Steps: []string{
				fmt.Sprintf("Step 1 — Add missing key %q to %s/%s (+ other locale ARBs)", item.Key, arbDir, templateBase),
				"Step 2 — Run: fvm flutter gen-l10n",
				"Step 3 — Keep existing l10n usage in Dart (do not edit Dart for missing-key fixes)",
			},
			Apply: SuggestionApply{Key: item.Key, ArbValue: english, Safe: false},
		})
	}
	return out
}

func lineHasComplexInterpolation(line string) bool {
	if strings.Contains(line, ".toStringAsFixed(") || strings.Contains(line, "replaceAll(") ||
		strings.Contains(line, "moneyToDouble(") || strings.Contains(line, "convertPointsAmount(") {
		return true
	}
	return strings.Count(line, "${") > 1
}

func l10nReplacement(key, callSuffix string) string {
	return fmt.Sprintf("l10n.%s%s", key, callSuffix)
}

func quotedForms(text string) []string {
	escaped := strings.ReplaceAll(text, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `"`, `\"`)
	double := `"` + escaped + `"`
	single := `'` + strings.ReplaceAll(text, `'`, `\'`) + `'`
	return []string{double, single}
}

func replaceQuotedOnLine(path string, lineNo int, text, replacement string) (bool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	lines := strings.Split(string(b), "\n")
	if lineNo < 1 || lineNo > len(lines) {
		return false, nil
	}
	line := lines[lineNo-1]
	for _, quoted := range quotedForms(text) {
		if !strings.Contains(line, quoted) {
			continue
		}
		lines[lineNo-1] = strings.Replace(line, quoted, replacement, 1)
		return true, os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644)
	}
	return false, nil
}

func needsL10nParam(path string, lineNo int) bool {
	b, err := os.ReadFile(path)
	if err != nil || lineNo < 1 {
		return false
	}
	lines := strings.Split(string(b), "\n")
	if lineNo > len(lines) {
		return false
	}
	start := lineNo - 1
	for start > 0 && !strings.Contains(lines[start], ") {") && !strings.HasPrefix(strings.TrimSpace(lines[start]), "Widget build(") {
		start--
	}
	end := lineNo
	for end < len(lines) && !strings.HasPrefix(strings.TrimSpace(lines[end]), "}") {
		end++
	}
	block := strings.Join(lines[start:end+1], "\n")
	if strings.Contains(block, "final l10n = context.l10n") || strings.Contains(block, "AppLocalizations l10n") {
		return false
	}
	return !strings.Contains(block, "Widget build(")
}

func suggestionDart(snippet, key, callSuffix string) string {
	replacement := l10nReplacement(key, callSuffix)
	if strings.Contains(snippet, `text: "`) || strings.Contains(snippet, `text: '`) {
		re := regexp.MustCompile(`text\s*:\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
		return re.ReplaceAllString(snippet, "text: "+replacement)
	}
	if strings.Contains(snippet, "Text(") {
		re := regexp.MustCompile(`Text\s*\(\s*(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
		return re.ReplaceAllString(snippet, "Text("+replacement)
	}
	re := regexp.MustCompile(`(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*')`)
	if re.MatchString(snippet) {
		return re.ReplaceAllString(snippet, replacement)
	}
	return fmt.Sprintf("// manual: replace %q with %s", key, replacement)
}

func isSafeDartReplacement(dartAfter string) bool {
	trimmed := strings.TrimSpace(dartAfter)
	if trimmed == "" || strings.HasPrefix(trimmed, "//") {
		return false
	}
	return strings.Contains(trimmed, "l10n.")
}

func inferEnglishFromKey(key string) string {
	var words []string
	var current []rune
	flush := func() {
		if len(current) == 0 {
			return
		}
		word := strings.ToLower(string(current))
		if len(word) > 0 {
			word = strings.ToUpper(word[:1]) + word[1:]
		}
		words = append(words, word)
		current = current[:0]
	}
	for _, r := range key {
		if unicode.IsUpper(r) && len(current) > 0 {
			flush()
		}
		current = append(current, r)
	}
	flush()
	if len(words) == 0 {
		return "TODO"
	}
	return strings.Join(words, " ")
}

type applyAccumulator struct {
	files       map[string]struct{}
	changedKeys []string
	Skipped     []string
}

func applyArbChanges(suggestions []Suggestion, arbPaths []string) (*applyAccumulator, []Suggestion, error) {
	acc := &applyAccumulator{files: map[string]struct{}{}}
	var dartPending []Suggestion
	for _, s := range suggestions {
		key := s.Apply.Key
		if key == "" {
			continue
		}
		for _, path := range arbPaths {
			changed, err := writeArbEntry(path, key, s.Apply.ArbValue, s.Apply.Placeholders)
			if err != nil {
				return nil, nil, err
			}
			if changed {
				acc.files[path] = struct{}{}
			}
		}
		acc.changedKeys = append(acc.changedKeys, key)
		if s.Kind == "hardcoded" {
			if s.Apply.Safe {
				dartPending = append(dartPending, s)
			} else {
				acc.Skipped = append(acc.Skipped,
					fmt.Sprintf("Skipped unsafe auto-apply for %s:%d (%q)", s.Relative, s.Apply.Line, s.Apply.Text))
			}
		}
	}
	return acc, dartPending, nil
}

func applyDartChanges(pending []Suggestion) (map[string]struct{}, []string, error) {
	applied := map[string]struct{}{}
	var skipped []string
	for _, s := range pending {
		if s.Apply.Line <= 0 || s.Apply.Text == "" || !s.Apply.Safe {
			continue
		}
		replacement := l10nReplacement(s.Apply.Key, callSuffixFor(s.Apply))
		if !isSafeDartReplacement(replacement) {
			skipped = append(skipped, fmt.Sprintf("Unsafe Dart replacement for %s:%d", s.Relative, s.Apply.Line))
			continue
		}
		ok, err := replaceQuotedOnLine(s.File, s.Apply.Line, s.Apply.Text, replacement)
		if err != nil {
			return nil, nil, err
		}
		if ok {
			applied[s.File] = struct{}{}
		} else {
			skipped = append(skipped, fmt.Sprintf("Could not replace %q on line %d in %s", s.Apply.Text, s.Apply.Line, s.Relative))
		}
	}
	return applied, skipped, nil
}

func finalizeApplyResult(acc *applyAccumulator) *ApplyResult {
	files := make([]string, 0, len(acc.files))
	for f := range acc.files {
		files = append(files, f)
	}
	sort.Strings(files)
	return &ApplyResult{
		Applied:      len(files) > 0 || len(acc.changedKeys) > 0,
		AppliedFiles: files,
		ChangedKeys:  acc.changedKeys,
		Skipped:      acc.Skipped,
	}
}

func writeArbEntry(path, key, value string, placeholders []Placeholder) (bool, error) {
	_, data, err := loadArbKeys(path)
	if err != nil {
		return false, err
	}
	if _, ok := data[key]; ok {
		return false, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	text := strings.TrimRight(string(b), "\n")
	closing := strings.LastIndex(text, "\n}")
	if closing < 0 {
		return false, fmt.Errorf("invalid ARB file: %s", path)
	}
	var buf strings.Builder
	buf.WriteString(text[:closing])
	buf.WriteString(",\n")
	buf.WriteString(fmt.Sprintf("  %q: %s", key, mustJSON(value)))
	if len(placeholders) > 0 {
		buf.WriteString(",\n")
		meta := map[string]any{
			"placeholders": map[string]any{},
		}
		ph := meta["placeholders"].(map[string]any)
		for _, p := range placeholders {
			ph[p.Name] = map[string]any{"type": "String"}
		}
		metaBytes, err := json.MarshalIndent(meta, "  ", "  ")
		if err != nil {
			return false, err
		}
		buf.WriteString(fmt.Sprintf("  %q: ", "@"+key))
		buf.Write(metaBytes)
	}
	buf.WriteString("\n}\n")
	out := buf.String()
	// Validate before writing so a bad append never corrupts the ARB.
	if err := json.Unmarshal([]byte(out), &map[string]any{}); err != nil {
		return false, fmt.Errorf("refusing to write invalid ARB %s: %w", path, err)
	}
	if err := os.WriteFile(path, []byte(out), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

func callSuffixFor(apply SuggestionApply) string {
	if len(apply.Placeholders) == 0 {
		return ""
	}
	parts := make([]string, 0, len(apply.Placeholders))
	for _, p := range apply.Placeholders {
		parts = append(parts, p.Expr)
	}
	return "(" + strings.Join(parts, ", ") + ")"
}

func replaceSnippet(path, before, after string) (bool, error) {
	b, err := os.ReadFile(path)
	if err != nil { return false, err }
	text := string(b)
	idx := strings.Index(text, before)
	if idx < 0 { return false, nil }
	text = text[:idx] + after + text[idx+len(before):]
	return true, os.WriteFile(path, []byte(text), 0o644)
}

func generateL10n(project string) CommandResult {
	cmd := []string{"flutter", "gen-l10n"}
	if exists(filepath.Join(project, ".fvmrc")) { cmd = append([]string{"fvm"}, cmd...) }
	return runCmd(project, cmd)
}

func analyzeProject(project string) CommandResult {
	args := []string{"dart", "analyze", "--fatal-warnings"}
	if exists(filepath.Join(project, "lib")) { args = append(args, "lib") }
	if exists(filepath.Join(project, "test")) { args = append(args, "test") }
	if exists(filepath.Join(project, ".fvmrc")) { args = append([]string{"fvm"}, args...) }
	return runCmd(project, args)
}

func runCmd(project string, cmd []string) CommandResult {
	proc := exec.Command(cmd[0], cmd[1:]...)
	proc.Dir = project
	var outb, errb bytes.Buffer
	proc.Stdout = &outb
	proc.Stderr = &errb
	err := proc.Run()
	exit := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok { exit = ee.ExitCode() } else { exit = 1 }
	}
	output := strings.TrimSpace(outb.String())
	if strings.TrimSpace(errb.String()) != "" {
		if output != "" { output += "\n" }
		output += strings.TrimSpace(errb.String())
	}
	return CommandResult{Command: strings.Join(cmd, " "), ExitCode: exit, OK: exit == 0, Output: output}
}

func relToProject(path, project string) string {
	rel, err := filepath.Rel(project, path)
	if err != nil { return path }
	return filepath.ToSlash(rel)
}

func splitRef(ref string) (string, int) {
	i := strings.LastIndex(ref, ":")
	if i < 0 { return ref, 0 }
	line := 0
	fmt.Sscanf(ref[i+1:], "%d", &line)
	return ref[:i], line
}

func trimLine(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 240 { return s[:240] }
	return s
}

func mustJSON(s string) string { b, _ := json.Marshal(s); return string(b) }
func joinPlaceholderNames(p []Placeholder) string { var out []string; for _, x := range p { out = append(out, x.Name) }; return strings.Join(out, ", ") }
func head[T any](in []T, n int) []T { if len(in) <= n { return in }; return in[:n] }
func sortedKeys(m map[string]struct{}) []string { out := make([]string,0,len(m)); for k := range m { out = append(out,k) }; sort.Strings(out); return out }
func exists(path string) bool { _, err := os.Stat(path); return err == nil }
func deepEqualJSON(a, b any) bool { ab, _ := json.Marshal(a); bb, _ := json.Marshal(b); return bytes.Equal(ab, bb) }
