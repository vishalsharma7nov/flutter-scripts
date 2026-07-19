package gitstatus

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

type Status struct {
	RepoRoot     string `json:"repoRoot"`
	IsRepo       bool   `json:"isRepo"`
	Branch       string `json:"branch"`
	Upstream     string `json:"upstream"`
	Ahead        int    `json:"ahead"`
	Behind       int    `json:"behind"`
	DirtyCount   int    `json:"dirtyCount"`
	StatusShort  string `json:"statusShort"`
	RemoteURL    string `json:"remoteURL"`
	HeadDetached bool   `json:"headDetached"`
	Error        string `json:"error,omitempty"`
}

func Collect(dir string) Status {
	dir = filepath.Clean(dir)
	out := Status{}

	root, err := run(dir, "rev-parse", "--show-toplevel")
	if err != nil {
		out.IsRepo = false
		out.Error = "Not a git repository"
		out.RepoRoot = dir
		return out
	}
	out.IsRepo = true
	out.RepoRoot = strings.TrimSpace(root)

	if v, err := run(out.RepoRoot, "rev-parse", "--abbrev-ref", "HEAD"); err == nil {
		br := strings.TrimSpace(v)
		out.Branch = br
		out.HeadDetached = br == "HEAD"
	}

	if v, err := run(out.RepoRoot, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"); err == nil {
		out.Upstream = strings.TrimSpace(v)
	}

	if v, err := run(out.RepoRoot, "rev-list", "--left-right", "--count", "HEAD...@{u}"); err == nil {
		parts := strings.Fields(strings.TrimSpace(v))
		if len(parts) == 2 {
			out.Ahead, _ = strconv.Atoi(parts[0])
			out.Behind, _ = strconv.Atoi(parts[1])
		}
	}

	if v, err := run(out.RepoRoot, "status", "-sb"); err == nil {
		out.StatusShort = strings.TrimSpace(v)
		lines := strings.Split(out.StatusShort, "\n")
		if len(lines) > 1 {
			out.DirtyCount = len(lines) - 1
		}
	}

	if v, err := run(out.RepoRoot, "remote", "get-url", "origin"); err == nil {
		out.RemoteURL = strings.TrimSpace(v)
	}

	return out
}

func run(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", err
	}
	return stdout.String(), nil
}
