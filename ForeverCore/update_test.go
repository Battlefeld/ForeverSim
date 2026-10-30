package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestUpdateSignedDownloadSwapAndBack(t *testing.T) {
	pub, priv, _ := ed25519.GenerateKey(rand.Reader)
	program := []byte("the new ForeverCore")
	sum := sha256.Sum256(program)
	var srv *httptest.Server
	manifest := func(tamper bool) []byte {
		m := updateManifest{Build: "20261102120000", Version: "1.0.1", URL: srv.URL + "/ForeverCore.exe", SHA256: hex.EncodeToString(sum[:]), Size: int64(len(program))}
		signUpdate(&m, priv)
		if tamper {
			m.URL = "http://evil.example/x.exe"
		}
		b, _ := json.Marshal(m)
		return b
	}
	tamper := false
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/m.json" {
			w.Write(manifest(tamper))
			return
		}
		w.Write(program)
	}))
	defer srv.Close()
	oldURL, oldKey, oldBuild := updateManifestURL, updatePublicKey, Build
	defer func() { updateManifestURL, updatePublicKey, Build = oldURL, oldKey, oldBuild }()
	updateManifestURL, updatePublicKey = srv.URL+"/m.json", base64.StdEncoding.EncodeToString(pub)
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "ForeverCore.exe"), []byte("the old ForeverCore"), 0o644)

	Build = ""
	if p, _, err := checkUpdate(context.Background(), dir); p != "" || err != nil {
		t.Fatalf("a developer's build updated: %q %v", p, err)
	}
	Build = "20261102120000"
	if p, _, err := checkUpdate(context.Background(), dir); p != "" || err != nil {
		t.Fatalf("the same build updated: %q %v", p, err)
	}
	Build = "20261101000000"
	tamper = true
	if p, _, err := checkUpdate(context.Background(), dir); p != "" || err == nil {
		t.Fatalf("a tampered manifest was believed: %q %v", p, err)
	}
	tamper = false
	p, m, err := checkUpdate(context.Background(), dir)
	if err != nil || p == "" || m.Version != "1.0.1" {
		t.Fatalf("update: %q %v %v", p, m, err)
	}
	if err := swapProgram(dir, p); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "ForeverCore.exe")); string(b) != "the new ForeverCore" {
		t.Fatalf("installed %q", b)
	}
	if err := goBack(dir); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "ForeverCore.exe")); string(b) != "the old ForeverCore" {
		t.Fatalf("after going back %q", b)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "ForeverCore.old.exe")); string(b) != "the new ForeverCore" {
		t.Fatalf("going back again would not go forward: %q", b)
	}
}

func TestNewer(t *testing.T) {
	if !newer("20261102120000", "20261101000000") || newer("20261101000000", "20261102120000") || newer("x", "1") {
		t.Fatal("build order")
	}
}
