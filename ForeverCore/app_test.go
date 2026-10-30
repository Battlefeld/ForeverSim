package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppWindowInstallsAndGuards(t *testing.T) {
	dir := t.TempDir()
	addons := filepath.Join(dir, "WoW", "_classic_beta_", "Interface", "AddOns")
	os.MkdirAll(addons, 0o755)
	a := &app{dir: filepath.Join(dir, "App"), token: "secret", payload: testPayload(), log: &logRing{max: 10}}
	srv := httptest.NewServer(a.routes())
	defer srv.Close()
	do := func(method, path, body string, hdr map[string]string) (*http.Response, map[string]any) {
		req, _ := http.NewRequest(method, srv.URL+path, strings.NewReader(body))
		for k, v := range hdr {
			req.Header.Set(k, v)
		}
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer r.Body.Close()
		var v map[string]any
		json.NewDecoder(r.Body).Decode(&v)
		return r, v
	}
	tok := map[string]string{"X-FC-Token": "secret"}
	if r, _ := do("GET", "/api/status", "", nil); r.StatusCode != http.StatusForbidden {
		t.Errorf("status without token: %d", r.StatusCode)
	}
	if r, _ := do("POST", "/api/install", `{}`, map[string]string{"X-FC-Token": "secret", "Origin": "http://evil.example"}); r.StatusCode != http.StatusForbidden {
		t.Errorf("request from another page: %d", r.StatusCode)
	}
	if r, _ := do("GET", "/", "", nil); r.StatusCode != http.StatusNotFound {
		t.Errorf("page without token: %d", r.StatusCode)
	}
	if r, _ := do("GET", "/?t=secret", "", nil); r.StatusCode != http.StatusOK {
		t.Errorf("page: %d", r.StatusCode)
	}
	_, st := do("GET", "/api/status", "", tok)
	if st["installed"] != false || st["package"] != true {
		t.Fatalf("status before installing: %v", st)
	}
	r, rep := do("POST", "/api/install", `{"addons":"`+strings.ReplaceAll(addons, `\`, `\\`)+`"}`, tok)
	if r.StatusCode != http.StatusOK || rep["slots"] != float64(SlotCount) {
		t.Fatalf("install: %d %v", r.StatusCode, rep)
	}
	_, st = do("GET", "/api/status", "", tok)
	if st["installed"] != true || st["addons"] != addons {
		t.Fatalf("status after installing: %v", st)
	}
	if r, v := do("POST", "/api/install", `{"addons":"C:\\nowhere"}`, tok); r.StatusCode != http.StatusBadRequest || v["error"] == nil {
		t.Errorf("a wrong folder was accepted: %d %v", r.StatusCode, v)
	}
}
