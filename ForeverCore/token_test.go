package main

import (
	"os"
	"testing"
)

func TestTokenSavedAndUsed(t *testing.T) {
	for _, n := range []string{"FOREVER_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"} {
		t.Setenv(n, "")
		os.Unsetenv(n)
	}
	dir := t.TempDir()
	setTokenDir(dir)
	defer setTokenDir("")
	if githubToken() != "" {
		t.Fatal("a token without one saved")
	}
	if err := saveToken(dir, "short"); err == nil {
		t.Error("a malformed token was saved")
	}
	if err := saveToken(dir, "github_pat_0123456789abcdefghijklmnop"); err != nil {
		t.Fatal(err)
	}
	if githubToken() != "github_pat_0123456789abcdefghijklmnop" {
		t.Fatalf("token %q", githubToken())
	}
	saveToken(dir, "")
	if githubToken() != "" {
		t.Error("the removed token is still used")
	}
}
