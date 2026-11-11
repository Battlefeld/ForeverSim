package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Routes update: ForeverRoutes publishes a bundle with every release (dataset, walk grid, routes, kill profiles, the
// Windows planner) and a manifest with the SHA-256 of the zip and of each file. ForeverCore fetches the latest
// release's manifest; when its version is not the one installed it downloads the bundle, checks both hashes, unpacks
// it beside the ForeverRoutes folder and only then swaps the folders. Anything wrong on the way leaves the installed
// routes as they are.

// routesAPI is GitHub's API (a test points it at its own server).
var routesAPI = "https://api.github.com"

const (
	routesBundle      = "foreverroutes-bundle.zip"
	routesManifest    = "foreverroutes-bundle.json"
	routesBundleLimit = 256 << 20
	routesEvery       = 24 * time.Hour
)

var routesUpdateMu sync.Mutex
var routesAccessMu sync.RWMutex

type routesBundleManifest struct {
	Schema  string            `json:"schema"`
	Version string            `json:"version"`
	ZipSHA  string            `json:"zipSHA256"`
	Files   map[string]string `json:"files"`
}

// routesDir is the ForeverRoutes folder: where the dataset lies.
func routesDir(cfg Config) string { return filepath.Dir(cfg.RoutesData) }

// updateRoutes brings the ForeverRoutes folder to the latest release. It returns the version installed afterwards and
// whether it changed.
func updateRoutes(ctx context.Context, cfg Config) (string, bool, error) {
	routesUpdateMu.Lock()
	defer routesUpdateMu.Unlock()
	repo := cfg.RoutesRepo
	if repo == "" {
		repo = "Battlefeld/ForeverRoutes"
	}
	b, err := fetchBounded(ctx, routesAPI+"/repos/"+repo+"/releases/latest", 4<<20)
	if err != nil {
		return "", false, err
	}
	var rel struct {
		Tag    string `json:"tag_name"`
		Assets []struct {
			Name   string `json:"name"`
			URL    string `json:"browser_download_url"`
			APIURL string `json:"url"`
		} `json:"assets"`
	}
	if err := json.Unmarshal(b, &rel); err != nil {
		return "", false, fmt.Errorf("ForeverRoutes-Release: %w", err)
	}
	urls := map[string]string{}
	for _, a := range rel.Assets {
		urls[a.Name] = a.URL
		if githubToken() != "" && a.APIURL != "" {
			urls[a.Name] = a.APIURL
		}
	}
	if urls[routesBundle] == "" || urls[routesManifest] == "" {
		return "", false, fmt.Errorf("ForeverRoutes-Release %s ohne Paket", rel.Tag)
	}
	mb, err := fetchBounded(ctx, urls[routesManifest], 4<<20)
	if err != nil {
		return "", false, err
	}
	var man routesBundleManifest
	if err := json.Unmarshal(mb, &man); err != nil || man.Version == "" || len(man.Files) == 0 {
		return "", false, fmt.Errorf("ForeverRoutes-Manifest unlesbar")
	}
	dir := routesDir(cfg)
	var have routesBundleManifest
	if raw, err := os.ReadFile(filepath.Join(dir, routesManifest)); err == nil && json.Unmarshal(raw, &have) == nil && have.Version == man.Version {
		updateRoutesAddon(ctx, cfg, rel.Tag, urls)
		return have.Version, false, nil
	}
	zb, err := fetchBounded(ctx, urls[routesBundle], routesBundleLimit)
	if err != nil {
		return "", false, err
	}
	if sum := sha256.Sum256(zb); hex.EncodeToString(sum[:]) != man.ZipSHA {
		return "", false, fmt.Errorf("ForeverRoutes-Paket: Pruefsumme stimmt nicht")
	}
	fresh := dir + ".neu"
	os.RemoveAll(fresh)
	if err := unpackRoutes(zb, fresh, man.Files); err != nil {
		os.RemoveAll(fresh)
		return "", false, err
	}
	if err := os.WriteFile(filepath.Join(fresh, routesManifest), mb, 0o644); err != nil {
		os.RemoveAll(fresh)
		return "", false, err
	}
	routesAccessMu.Lock()
	defer routesAccessMu.Unlock()
	old := dir + ".alt"
	os.RemoveAll(old)
	if _, err := os.Stat(dir); err == nil {
		if err := os.Rename(dir, old); err != nil {
			os.RemoveAll(fresh)
			return "", false, err
		}
	}
	if err := os.Rename(fresh, dir); err != nil {
		os.Rename(old, dir) // put the installed routes back
		return "", false, err
	}
	os.RemoveAll(old)
	updateRoutesAddon(ctx, cfg, rel.Tag, urls)
	return man.Version, true, nil
}

// The ForeverRoutes addon in WoW's AddOns folder comes with the same release (ForeverRoutes-addon.zip and its
// SHA-256): before, only an installation from ForeverCore's own package put it there, so new routes never reached the
// game. updateRoutesAddon brings it to the release's version: checked, unpacked beside the installed one, then swapped
// in; the character's personal route goes back in; SavedVariables (WTF) are not touched. With WoW running only when
// the addon's file list (its .toc) stays the same (WoW takes it with /reload), else at the next check. Failures are
// logged and change nothing.
const (
	routesAddonZip    = "ForeverRoutes-addon.zip"
	routesAddonName   = "ForeverRoutes"
	routesAddonMarker = "ForeverRoutes-addon.version"
	routesAddonLimit  = 64 << 20
)

func updateRoutesAddon(ctx context.Context, cfg Config, tag string, urls map[string]string) {
	if err := updateRoutesAddonErr(ctx, cfg, tag, urls); err != nil {
		log.Printf("ForeverRoutes-Addon: %v", err)
	}
}

func updateRoutesAddonErr(ctx context.Context, cfg Config, tag string, urls map[string]string) error {
	if cfg.Addons == "" || urls[routesAddonZip] == "" || urls[routesAddonZip+".sha256"] == "" {
		return nil // no WoW folder set up, or a release without the addon
	}
	appDir := filepath.Dir(routesDir(cfg))
	marker := filepath.Join(appDir, routesAddonMarker)
	target := filepath.Join(cfg.Addons, routesAddonName)
	if b, err := os.ReadFile(marker); err == nil && strings.TrimSpace(string(b)) == tag {
		if _, err := os.Stat(filepath.Join(target, routesAddonName+".toc")); err == nil {
			return nil
		}
	}
	sb, err := fetchBounded(ctx, urls[routesAddonZip+".sha256"], 4<<10)
	if err != nil {
		return err
	}
	want := strings.ToLower(strings.TrimSpace(strings.Fields(string(sb) + " ")[0]))
	zb, err := fetchBounded(ctx, urls[routesAddonZip], routesAddonLimit)
	if err != nil {
		return err
	}
	if sum := sha256.Sum256(zb); hex.EncodeToString(sum[:]) != want {
		return fmt.Errorf("Pruefsumme stimmt nicht")
	}
	zr, err := zip.NewReader(bytes.NewReader(zb), int64(len(zb)))
	if err != nil {
		return err
	}
	fresh, old := target+".neu", target+".alt"
	os.RemoveAll(fresh)
	var toc []byte
	for _, f := range zr.File {
		name := path.Clean(f.Name)
		if f.FileInfo().IsDir() {
			continue
		}
		rest, ok := strings.CutPrefix(name, routesAddonName+"/")
		if !ok || rest == "" || strings.HasPrefix(rest, "../") || strings.Contains(rest, "/../") {
			os.RemoveAll(fresh)
			return fmt.Errorf("unerwartete Datei %s", name)
		}
		rc, err := f.Open()
		if err != nil {
			os.RemoveAll(fresh)
			return err
		}
		b, err := io.ReadAll(io.LimitReader(rc, routesAddonLimit))
		rc.Close()
		if err != nil {
			os.RemoveAll(fresh)
			return err
		}
		if rest == routesAddonName+".toc" {
			toc = b
		}
		dest := filepath.Join(fresh, filepath.FromSlash(rest))
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			os.RemoveAll(fresh)
			return err
		}
		if err := os.WriteFile(dest, b, 0o644); err != nil {
			os.RemoveAll(fresh)
			return err
		}
	}
	if toc == nil {
		os.RemoveAll(fresh)
		return fmt.Errorf("Paket ohne %s.toc", routesAddonName)
	}
	if wowRunning() {
		have, _ := os.ReadFile(filepath.Join(target, routesAddonName+".toc"))
		norm := func(b []byte) []byte { return bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n")) }
		if !bytes.Equal(norm(have), norm(toc)) {
			os.RemoveAll(fresh)
			return fmt.Errorf("WoW laeuft und die Dateiliste hat sich geaendert: Update %s beim naechsten Start ohne WoW", tag)
		}
	}
	// (no routesAccessMu: the planner does not read the addon, and updateRoutes holds that lock already)
	os.RemoveAll(old)
	if _, err := os.Stat(target); err == nil {
		if err := os.Rename(target, old); err != nil {
			os.RemoveAll(fresh)
			return err
		}
	}
	if err := os.Rename(fresh, target); err != nil {
		os.Rename(old, target) // put the installed addon back
		os.RemoveAll(fresh)
		return err
	}
	os.RemoveAll(old)
	dataDir := cfg.Data
	if dataDir == "" {
		dataDir = filepath.Join(appDir, "Data")
	}
	restorePersonalRoute(dataDir, target)
	if err := os.WriteFile(marker, []byte(tag+"\n"), 0o644); err != nil {
		return err
	}
	log.Printf("ForeverRoutes-Addon aktualisiert: %s", tag)
	return nil
}

// unpackRoutes writes the bundle's files below dir, each checked against the manifest; no file outside it, none
// missing.
func unpackRoutes(zb []byte, dir string, want map[string]string) error {
	r, err := zip.NewReader(bytes.NewReader(zb), int64(len(zb)))
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, f := range r.File {
		name := path.Clean(f.Name)
		if strings.HasPrefix(name, "../") || strings.HasPrefix(name, "/") || name == ".." || f.FileInfo().IsDir() {
			continue
		}
		sum, ok := want[name]
		if !ok {
			return fmt.Errorf("ForeverRoutes-Paket: unbekannte Datei %s", name)
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		b, err := io.ReadAll(io.LimitReader(rc, routesBundleLimit))
		rc.Close()
		if err != nil {
			return err
		}
		if s := sha256.Sum256(b); hex.EncodeToString(s[:]) != sum {
			return fmt.Errorf("ForeverRoutes-Paket: %s beschaedigt", name)
		}
		dest := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dest, b, 0o644); err != nil {
			return err
		}
		seen[name] = true
	}
	for name := range want {
		if !seen[name] {
			return fmt.Errorf("ForeverRoutes-Paket: %s fehlt", name)
		}
	}
	return nil
}

// keepRoutesUpdated checks for new routes at start and then every routesEvery, unless switched off.
func keepRoutesUpdated(ctx context.Context, cfg Config) {
	if cfg.RoutesNoUpdate {
		return
	}
	for {
		if v, changed, err := updateRoutes(ctx, cfg); err != nil {
			log.Printf("ForeverRoutes-Update: %v", err)
		} else if changed {
			log.Printf("ForeverRoutes aktualisiert: %s", v)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(routesEvery):
		}
	}
}
