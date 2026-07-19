package project

import "testing"

func TestNormalizeSource(t *testing.T) {
  k, v, err := NormalizeSource("acme/widget")
  if err != nil || k != "git" || v != "https://github.com/acme/widget.git" {
    t.Fatalf("got %s %s %v", k, v, err)
  }
  if RepoNameFromURL(v) != "widget" { t.Fatal(RepoNameFromURL(v)) }
}
