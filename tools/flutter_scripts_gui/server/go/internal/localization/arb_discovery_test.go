package localization

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverArbFiles_appPrefix(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	arbDir := filepath.Join(dir, "lib", "l10n")
	if err := os.MkdirAll(arbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(arbDir, "app_en.arb"), `{"@@locale":"en","title":"Hi"}`)
	writeTestFile(t, filepath.Join(arbDir, "app_es.arb"), `{"@@locale":"es","title":"Hola"}`)

	got, err := discoverArbFiles(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Files) != 2 {
		t.Fatalf("files = %d, want 2", len(got.Files))
	}
	if filepath.Base(got.TemplatePath) != "app_en.arb" {
		t.Fatalf("template = %s", got.TemplatePath)
	}
}

func TestDiscoverArbFiles_fromL10nYAML(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	arbDir := filepath.Join(dir, "assets", "i18n")
	if err := os.MkdirAll(arbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(dir, "l10n.yaml"), "arb-dir: assets/i18n\ntemplate-arb-file: intl_en.arb\n")
	writeTestFile(t, filepath.Join(arbDir, "intl_en.arb"), `{"@@locale":"en"}`)
	writeTestFile(t, filepath.Join(arbDir, "intl_de.arb"), `{"@@locale":"de"}`)

	got, err := discoverArbFiles(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Files) != 2 {
		t.Fatalf("files = %d, want 2", len(got.Files))
	}
	if filepath.Base(got.TemplatePath) != "intl_en.arb" {
		t.Fatalf("template = %s", got.TemplatePath)
	}
}

func TestBootstrapL10n_createsScaffold(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeTestFile(t, filepath.Join(dir, "pubspec.yaml"), "name: demo\n")

	got, err := discoverOrBootstrapArb(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Bootstrapped {
		t.Fatal("expected bootstrapped=true")
	}
	if len(got.Files) != 1 {
		t.Fatalf("files = %d", len(got.Files))
	}
	if _, err := os.Stat(filepath.Join(dir, "l10n.yaml")); err != nil {
		t.Fatalf("missing l10n.yaml: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "lib", "l10n", "app_en.arb")); err != nil {
		t.Fatalf("missing app_en.arb: %v", err)
	}
}

func TestLocaleFromArbName(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"app_en.arb":    "en",
		"app_en_US.arb": "en_US",
		"intl_de.arb":   "de",
		"en.arb":        "en",
	}
	for name, want := range cases {
		if got := localeFromArbName(name); got != want {
			t.Fatalf("localeFromArbName(%q) = %q, want %q", name, got, want)
		}
	}
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
