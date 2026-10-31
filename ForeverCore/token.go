package main

// An optional GitHub access for updates of ForeverCore and of the routes (needed only while a repository is private):
// entered once in the window, kept in the app folder encrypted for the Windows user (DPAPI, token_windows.go), never shown again. An
// environment variable (FOREVER_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN) still wins.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

const tokenFile = "github-zugang.bin"

var (
	tokenMu  sync.Mutex
	tokenDir string // the app folder of a running app; "" elsewhere
)

func setTokenDir(dir string) { tokenMu.Lock(); tokenDir = dir; tokenMu.Unlock() }

// storedToken: the token saved in the app folder ("" without one).
func storedToken() string {
	tokenMu.Lock()
	dir := tokenDir
	tokenMu.Unlock()
	if dir == "" {
		return ""
	}
	b, err := os.ReadFile(filepath.Join(dir, tokenFile))
	if err != nil {
		return ""
	}
	plain, err := unprotect(b)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(plain))
}

// saveToken keeps a token in the app folder ("" removes it).
func saveToken(dir, token string) error {
	token = strings.TrimSpace(token)
	path := filepath.Join(dir, tokenFile)
	if token == "" {
		os.Remove(path)
		return nil
	}
	if strings.ContainsAny(token, " \t\r\n") || len(token) < 20 || len(token) > 300 {
		return fmt.Errorf("Das sieht nicht wie ein GitHub-Zugangsschluessel aus")
	}
	b, err := protect([]byte(token))
	if err != nil {
		return err
	}
	return atomicWrite(path, b)
}
