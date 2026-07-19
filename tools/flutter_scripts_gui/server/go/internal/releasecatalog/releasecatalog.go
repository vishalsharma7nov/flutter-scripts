package releasecatalog

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Package is a configured git package release target.
type Package struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

var (
	idRe    = regexp.MustCompile(`(?m)^PR_PACKAGE_ID="([^"]+)"`)
	titleRe = regexp.MustCompile(`(?m)^PR_PACKAGE_TITLE="([^"]+)"`)
	descRe  = regexp.MustCompile(`(?m)^PR_PACKAGE_DESCRIPTION="([^"]+)"`)
)

func fieldFromConfig(data, key string, re *regexp.Regexp) string {
	if m := re.FindStringSubmatch(data); len(m) > 1 {
		return m[1]
	}
	return ""
}

// Discover lists packages with release.config.sh under packages/*/ (preferred)
// and other top-level package folders (excluding tooling trees).
func Discover(scriptsDir string) ([]Package, error) {
	var matches []string
	preferred, _ := filepath.Glob(filepath.Join(scriptsDir, "packages", "*", "release.config.sh"))
	matches = append(matches, preferred...)
	legacy, _ := filepath.Glob(filepath.Join(scriptsDir, "*", "release.config.sh"))
	skip := map[string]struct{}{
		"scripts": {}, "tools": {}, "lib": {}, "docs": {}, "examples": {}, "config": {}, "packages": {},
	}
	for _, path := range legacy {
		dir := filepath.Base(filepath.Dir(path))
		if _, bad := skip[dir]; bad {
			continue
		}
		matches = append(matches, path)
	}
	sort.Strings(matches)

	out := make([]Package, 0, len(matches))
	seen := map[string]struct{}{}
	for _, path := range matches {
		if _, ok := seen[path]; ok {
			continue
		}
		seen[path] = struct{}{}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		text := string(data)
		id := fieldFromConfig(text, "id", idRe)
		if id == "" {
			continue
		}
		title := fieldFromConfig(text, "title", titleRe)
		if title == "" {
			title = id
		}
		desc := fieldFromConfig(text, "description", descRe)
		if desc == "" {
			desc = "Release " + title
		}
		out = append(out, Package{
			ID:          id,
			Title:       title,
			Description: strings.TrimSpace(desc),
		})
	}
	return out, nil
}
