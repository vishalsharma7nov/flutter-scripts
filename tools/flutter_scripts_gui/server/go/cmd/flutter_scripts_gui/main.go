package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/flutter-scripts/flutter_scripts_gui/internal/localization"
	"github.com/flutter-scripts/flutter_scripts_gui/internal/server"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "localization-check" {
		runLocalizationCLI(os.Args[2:])
		return
	}
	port := flag.Int("port", 8766, "Web GUI port")
	scriptsDir := flag.String("scripts-dir", "", "Flutter-scripts home (*.sh catalog)")
	project := flag.String("project", "", "Working directory for script runs")
	host := flag.String("host", "127.0.0.1", "Bind address")
	lan := flag.Bool("lan", false, "Listen on all interfaces (0.0.0.0)")
	noOpen := flag.Bool("no-open", false, "Do not open the browser")
	openFlag := flag.Bool("open", true, "Open the browser (default true)")
	flag.Parse()

	toolRoot, err := resolveToolRoot()
	if err != nil {
		fatal(err)
	}
	webDir := filepath.Join(toolRoot, "web")
	scripts := strings.TrimSpace(*scriptsDir)
	if scripts == "" {
		scripts = filepath.Clean(filepath.Join(toolRoot, "..", ".."))
	}
	projectDir := strings.TrimSpace(*project)
	if projectDir == "" {
		projectDir, _ = os.Getwd()
	}
	projectDir, _ = filepath.Abs(projectDir)
	scripts, _ = filepath.Abs(scripts)

	bind := strings.TrimSpace(*host)
	if *lan {
		bind = "0.0.0.0"
	}
	autoOpen := *openFlag && !*noOpen

	cfg := server.Config{
		Port:       *port,
		BindHost:   bind,
		ToolRoot:   toolRoot,
		WebDir:     webDir,
		ScriptsDir: scripts,
		ProjectDir: projectDir,
		AutoOpen:   autoOpen,
	}

	srv := server.New(cfg)
	if err := srv.Start(); err != nil {
		fatal(err)
	}
}

func runLocalizationCLI(args []string) {
	fs := flag.NewFlagSet("localization-check", flag.ExitOnError)
	project := fs.String("project", "", "Flutter project root")
	libDir := fs.String("lib", "lib", "Relative lib dir (accepted for compatibility)")
	mode := fs.String("mode", "full", "hardcoded | full | suggestions")
	jsonOut := fs.Bool("json", false, "Emit JSON")
	apply := fs.Bool("apply", false, "Apply generated localization changes")
	analyze := fs.Bool("analyze", false, "Run analyze after apply")
	warnOnly := fs.Bool("warn-only", false, "Always exit 0")
	var paths multiString
	fs.Var(&paths, "path", "Only scan this path under lib/ (repeatable)")
	fs.Parse(args)
	_ = libDir

	proj := strings.TrimSpace(*project)
	if proj == "" {
		cwd, _ := os.Getwd()
		proj = cwd
	}
	res, err := localization.Run(proj, localization.Request{
		Mode:    strings.TrimSpace(*mode),
		Path:    paths,
		Apply:   *apply,
		Analyze: *analyze,
	})
	if err != nil {
		fatal(err)
	}
	if *jsonOut {
		b, _ := json.MarshalIndent(res, "", "  ")
		fmt.Println(string(b))
	} else {
		fmt.Printf("Project: %s\nMode: %s\n", res.Project, res.Mode)
		if len(res.Hardcoded) > 0 {
			fmt.Printf("Hardcoded: %d\n", len(res.Hardcoded))
		}
		if len(res.HardIssues) > 0 {
			fmt.Println(strings.Join(res.HardIssues, "\n"))
		}
	}
	if *warnOnly {
		return
	}
	if res.L10nResult != nil && !res.L10nResult.OK {
		os.Exit(1)
	}
	if res.AnalysisResult != nil && !res.AnalysisResult.OK {
		os.Exit(1)
	}
	if res.Mode != "hardcoded" && res.HardIssueCount > 0 {
		os.Exit(1)
	}
}

type multiString []string

func (m *multiString) String() string { return strings.Join(*m, ",") }
func (m *multiString) Set(v string) error {
	*m = append(*m, v)
	return nil
}

func resolveToolRoot() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	// Prefer server/go cwd -> tool root is ../..
	if filepath.Base(wd) == "go" && filepath.Base(filepath.Dir(wd)) == "server" {
		return filepath.Clean(filepath.Join(wd, "..", "..")), nil
	}
	// Binary in tools/flutter_scripts_gui/bin
	exe, err := os.Executable()
	if err == nil {
		dir := filepath.Dir(exe)
		if filepath.Base(dir) == "bin" {
			return filepath.Dir(dir), nil
		}
	}
	return wd, nil
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
