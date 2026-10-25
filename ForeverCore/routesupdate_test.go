package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func testBundle(t *testing.T, version string, files map[string]string, tamper bool) ([]byte, []byte) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	man := routesBundleManifest{Schema: "foreverroutes.bundle.v1", Version: version, Files: map[string]string{}}
	for n, body := range files {
		w, _ := zw.Create(n)
		w.Write([]byte(body))
		s := sha256.Sum256([]byte(body))
		man.Files[n] = hex.EncodeToString(s[:])
	}
	zw.Close()
	zb := buf.Bytes()
	s := sha256.Sum256(zb)
	man.ZipSHA = hex.EncodeToString(s[:])
	if tamper {
		man.Files["routes-data.json.gz"] = "00"
	}
	mb, _ := json.Marshal(man)
	return zb, mb
}

func TestRoutesUpdate(t *testing.T) {
	files := map[string]string{"routes-data.json.gz": "new data", "routes/orc-warlock.json": "{}", "foreverroutes.exe": "exe"}
	zb, mb := testBundle(t, "v2", files, false)
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/x/y/releases/latest":
			json.NewEncoder(w).Encode(map[string]any{"tag_name": "v2", "assets": []map[string]string{
				{"name": routesBundle, "browser_download_url": srv.URL + "/b.zip"}, {"name": routesManifest, "browser_download_url": srv.URL + "/b.json"}}})
		case "/b.zip":
			w.Write(zb)
		case "/b.json":
			w.Write(mb)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	routesAPI = srv.URL
	base := t.TempDir()
	dir := filepath.Join(base, "ForeverRoutes")
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "routes-data.json.gz"), []byte("old data"), 0o644)
	cfg := Config{RoutesData: filepath.Join(dir, "routes-data.json.gz"), RoutesRepo: "x/y"}
	v, changed, err := updateRoutes(context.Background(), cfg)
	if err != nil || !changed || v != "v2" {
		t.Fatalf("update: %v %v %v", v, changed, err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "routes-data.json.gz")); string(b) != "new data" {
		t.Fatalf("dataset not replaced: %q", b)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "routes", "orc-warlock.json")); string(b) != "{}" {
		t.Fatal("route not unpacked")
	}
	if _, err := os.Stat(dir + ".alt"); !os.IsNotExist(err) {
		t.Fatal("old folder left behind")
	}
	// the same version again: nothing to do
	if _, changed, err := updateRoutes(context.Background(), cfg); err != nil || changed {
		t.Fatalf("second update: %v %v", changed, err)
	}
	// a damaged bundle leaves the installed routes alone
	zb, mb = testBundle(t, "v3", files, true)
	if _, _, err := updateRoutes(context.Background(), cfg); err == nil {
		t.Fatal("damaged bundle accepted")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "routes-data.json.gz")); string(b) != "new data" {
		t.Fatal("installed routes touched by a failed update")
	}
	if _, err := os.Stat(dir + ".neu"); !os.IsNotExist(err) {
		t.Fatal("partial folder left behind")
	}
}
