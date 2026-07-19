package localization

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestIsSafeDartReplacement(t *testing.T) {
	t.Parallel()
	cases := []struct {
		in   string
		want bool
	}{
		{"l10n.tripsTabSchedule", true},
		{"text: l10n.homeUnnamed", true},
		{"// manual: replace foo with l10n.foo", false},
		{"// use: l10n.foo", false},
		{"", false},
	}
	for _, tc := range cases {
		if got := isSafeDartReplacement(tc.in); got != tc.want {
			t.Fatalf("isSafeDartReplacement(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
}

func TestInferEnglishFromKey(t *testing.T) {
	t.Parallel()
	if got := inferEnglishFromKey("tripDetailsTitle"); got != "Trip Details Title" {
		t.Fatalf("inferEnglishFromKey(tripDetailsTitle) = %q", got)
	}
	if got := inferEnglishFromKey("tripCanceledNoCharge"); got != "Trip Canceled No Charge" {
		t.Fatalf("inferEnglishFromKey(tripCanceledNoCharge) = %q", got)
	}
}

func TestReplaceQuotedOnLine(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := dir + "/sample.dart"
	content := "      name: remote.label.isNotEmpty ? remote.label : 'Unnamed',\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ok, err := replaceQuotedOnLine(path, 1, "Unnamed", "l10n.homeUnnamed")
	if err != nil || !ok {
		t.Fatalf("replaceQuotedOnLine failed: ok=%v err=%v", ok, err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	want := "      name: remote.label.isNotEmpty ? remote.label : l10n.homeUnnamed,\n"
	if string(got) != want {
		t.Fatalf("got %q want %q", string(got), want)
	}
}

func TestWriteArbEntryWithPlaceholdersProducesValidJSON(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := dir + "/app_en.arb"
	if err := os.WriteFile(path, []byte("{\n  \"@@locale\": \"en\",\n  \"hello\": \"Hello\"\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err := writeArbEntry(path, "greetName", "Hello {name}", []Placeholder{
		{Name: "name", Expr: "name"},
	})
	if err != nil {
		t.Fatalf("writeArbEntry: %v", err)
	}
	if !changed {
		t.Fatal("expected change")
	}
	keys, data, err := loadArbKeys(path)
	if err != nil {
		t.Fatalf("loadArbKeys after write: %v", err)
	}
	if keys["greetName"] != "Hello {name}" {
		t.Fatalf("greetName = %q", keys["greetName"])
	}
	meta, ok := data["@greetName"].(map[string]any)
	if !ok {
		t.Fatalf("missing @greetName metadata: %#v", data["@greetName"])
	}
	ph, ok := meta["placeholders"].(map[string]any)
	if !ok || ph["name"] == nil {
		t.Fatalf("placeholders missing: %#v", meta)
	}
}

func TestHealArbFilesAutoRepairsCorruptProject(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	lib := filepath.Join(dir, "lib")
	arbDir := filepath.Join(lib, "l10n")
	if err := os.MkdirAll(arbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "pubspec.yaml"), []byte("name: any_app\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	corrupt := []byte(`{
  "@@locale": "en",
  "title": "Hi {name}",
  "@title": {\n    "placeholders": { "name": {"type": "String"} }\n  }
}
`)
	arbPath := filepath.Join(arbDir, "app_en.arb")
	if err := os.WriteFile(arbPath, corrupt, 0o644); err != nil {
		t.Fatal(err)
	}
	res, err := Run(dir, Request{Mode: "hardcoded"})
	if err != nil {
		t.Fatalf("Run should auto-heal any project: %v", err)
	}
	if res.TemplateKeyCount < 1 {
		t.Fatalf("expected keys after heal, got %d", res.TemplateKeyCount)
	}
	got, _ := os.ReadFile(arbPath)
	if !json.Valid(got) {
		t.Fatalf("ARB still invalid after Run: %s", got)
	}
}

