package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestOpenMapUpdate(t *testing.T) {
	var ab bytes.Buffer
	zw := zip.NewWriter(&ab)
	for n, body := range map[string]string{"OpenMap/OpenMap.toc": "## Interface: 16001\nCore.lua\n", "OpenMap/Core.lua": "-- v0.8.4"} {
		w, _ := zw.Create(n)
		w.Write([]byte(body))
	}
	zw.Close()
	zb := ab.Bytes()
	sum := sha256.Sum256(zb)
	shaBody := hex.EncodeToString(sum[:]) + "  OpenMap.zip\n"
	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/OpenMap.version":
			w.Write([]byte("v0.8.4 dc61140\n"))
		case "/OpenMap.zip":
			hits++
			w.Write(zb)
		case "/OpenMap.zip.sha256":
			w.Write([]byte(shaBody))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	old := openMapBase
	openMapBase = srv.URL + "/"
	defer func() { openMapBase = old }()
	base := t.TempDir()
	addons := filepath.Join(base, "AddOns")
	os.MkdirAll(filepath.Join(addons, "OpenMap"), 0o755)
	os.WriteFile(filepath.Join(addons, "OpenMap", "Stale.lua"), []byte("-- old"), 0o644)
	cfg := Config{RoutesData: filepath.Join(base, "app", "ForeverRoutes", "routes-data.json.gz"), Addons: addons}
	os.MkdirAll(filepath.Join(base, "app"), 0o755)
	if err := updateOpenMap(context.Background(), cfg); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(addons, "OpenMap", "Core.lua")); string(b) != "-- v0.8.4" {
		t.Fatalf("OpenMap not installed: %q", b)
	}
	if _, err := os.Stat(filepath.Join(addons, "OpenMap", "Stale.lua")); !os.IsNotExist(err) {
		t.Fatal("old OpenMap file left behind")
	}
	// the same version again: nothing is downloaded
	if err := updateOpenMap(context.Background(), cfg); err != nil {
		t.Fatal(err)
	}
	if hits != 1 {
		t.Fatalf("zip fetched %d times, want 1", hits)
	}
	// a damaged checksum changes nothing
	os.Remove(filepath.Join(base, "app", openMapMarker))
	shaBody = "00" + shaBody[2:]
	if err := updateOpenMap(context.Background(), cfg); err == nil {
		t.Fatal("damaged checksum accepted")
	}
	if b, _ := os.ReadFile(filepath.Join(addons, "OpenMap", "Core.lua")); string(b) != "-- v0.8.4" {
		t.Fatal("installed OpenMap touched by a failed update")
	}
}
