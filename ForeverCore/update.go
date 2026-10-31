package main

// Updates of ForeverCore.exe itself. The workflow publishes the new program with a manifest signed with the release
// key (ed25519; the public half is built in). ForeverCore believes no manifest without a valid signature, downloads
// the program, checks its SHA-256 and size, and swaps it in when the user restarts: the running program is renamed
// (Windows allows that), the new one takes its place, the old one stays as ForeverCore.old.exe for going back. The
// addons the new program carries are installed by it once WoW is closed (app.go). A build without a build number (a
// developer's) never updates.

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Build is the release's build number (UTC yyyymmddhhmmss, set by build_app.py with -ldflags -X main.Build=...);
// empty in a developer's build.
var Build = ""

// updatePublicKey is the public release key (base64); the private half is the repository secret
// FOREVERCORE_SIGNING_KEY. Empty: updates are off.
var updatePublicKey = "mY8688LGM2UeoA7sDo3FXy80c7qnwLYbDOe7hrcl3Hs="

// updateManifestURL: the manifest beside the program in the release "forevercore" (public; downloads of release
// assets have no request limit; the manifest names the program's URL).
var updateManifestURL = "https://github.com/Battlefeld/ForeverSim/releases/download/forevercore/forevercore-update.json"

// updateManifest says which program is the newest.
type updateManifest struct {
	Build     string `json:"build"`
	Version   string `json:"version"`
	URL       string `json:"url"`
	SHA256    string `json:"sha256"`
	Size      int64  `json:"size"`
	Signature string `json:"signature"` // ed25519 over signedUpdate
}

// signedUpdate: what the signature covers.
func signedUpdate(m updateManifest) []byte {
	return []byte(fmt.Sprintf("forevercore-update\n%s\n%s\n%s\n%s\n%d\n", m.Build, m.Version, m.URL, m.SHA256, m.Size))
}

func signUpdate(m *updateManifest, key ed25519.PrivateKey) {
	m.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(key, signedUpdate(*m)))
}

func verifyUpdate(m updateManifest, pub string) error {
	key, err := base64.StdEncoding.DecodeString(pub)
	if err != nil || len(key) != ed25519.PublicKeySize {
		return fmt.Errorf("kein Update-Schluessel")
	}
	sig, err := base64.StdEncoding.DecodeString(m.Signature)
	if err != nil || !ed25519.Verify(ed25519.PublicKey(key), signedUpdate(m), sig) {
		return fmt.Errorf("Update-Signatur ungueltig")
	}
	if _, err := strconv.ParseUint(m.Build, 10, 64); err != nil || len(m.SHA256) != 64 || m.Size <= 0 {
		return fmt.Errorf("Update-Angaben ungueltig")
	}
	return nil
}

// newer: build a is later than build b.
func newer(a, b string) bool {
	x, err1 := strconv.ParseUint(a, 10, 64)
	y, err2 := strconv.ParseUint(b, 10, 64)
	return err1 == nil && err2 == nil && x > y
}

// updateState is what the window shows about updates.
type updateState struct {
	Enabled   bool   `json:"enabled"`
	Checked   string `json:"checked,omitempty"`
	Available string `json:"available,omitempty"` // version ready to be swapped in
	Error     string `json:"error,omitempty"`
	Previous  bool   `json:"previous"` // ForeverCore.old.exe is there to go back to
}

// checkUpdate fetches and checks the manifest and, when it names a newer build, downloads the program into
// appDir/Updates; it returns the path of the program ready to be swapped in ("" when there is none).
func checkUpdate(ctx context.Context, appDir string) (string, *updateManifest, error) {
	if updatePublicKey == "" || Build == "" {
		return "", nil, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	b, err := fetchBounded(ctx, updateManifestURL, 1<<16)
	if err != nil {
		return "", nil, err
	}
	var m updateManifest
	if err := json.Unmarshal(b, &m); err != nil {
		return "", nil, err
	}
	if err := verifyUpdate(m, updatePublicKey); err != nil {
		return "", nil, err
	}
	if !newer(m.Build, Build) {
		return "", &m, nil
	}
	dst := filepath.Join(appDir, "Updates", m.Build, "ForeverCore.exe")
	if sum, err := fileSHA(dst); err == nil && sum == m.SHA256 {
		return dst, &m, nil
	}
	exe, err := fetchBounded(ctx, m.URL, m.Size)
	if err != nil {
		return "", nil, err
	}
	sum := sha256.Sum256(exe)
	if int64(len(exe)) != m.Size || hex.EncodeToString(sum[:]) != m.SHA256 {
		return "", nil, fmt.Errorf("Update beschaedigt heruntergeladen")
	}
	if err := atomicWrite(dst, exe); err != nil {
		return "", nil, err
	}
	return dst, &m, nil
}

// swapProgram puts the downloaded program in place of the installed one; the old one stays as ForeverCore.old.exe.
func swapProgram(appDir, fresh string) error {
	target := filepath.Join(appDir, "ForeverCore.exe")
	old := filepath.Join(appDir, "ForeverCore.old.exe")
	os.Remove(old)
	if _, err := os.Stat(target); err == nil {
		if err := os.Rename(target, old); err != nil {
			return err
		}
	}
	b, err := os.ReadFile(fresh)
	if err == nil {
		err = atomicWrite(target, b)
	}
	if err != nil {
		os.Rename(old, target) // the old one back
		return err
	}
	return nil
}

// goBack puts ForeverCore.old.exe back in place of the installed program.
func goBack(appDir string) error {
	target := filepath.Join(appDir, "ForeverCore.exe")
	old := filepath.Join(appDir, "ForeverCore.old.exe")
	if _, err := os.Stat(old); err != nil {
		return fmt.Errorf("keine vorherige Version vorhanden")
	}
	cur := filepath.Join(appDir, "ForeverCore.new.exe")
	os.Remove(cur)
	if err := os.Rename(target, cur); err != nil {
		return err
	}
	if err := os.Rename(old, target); err != nil {
		os.Rename(cur, target)
		return err
	}
	return os.Rename(cur, old) // going back again goes forward
}

// writeUpdateManifest signs the manifest for a released program with the private release key (base64 of the
// 64-byte ed25519 key) and writes it.
func writeUpdateManifest(exe, build, version, url, out, key string) error {
	priv, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(priv) != ed25519.PrivateKeySize {
		return fmt.Errorf("FOREVERCORE_SIGNING_KEY fehlt oder ist ungueltig")
	}
	b, err := os.ReadFile(exe)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(b)
	m := updateManifest{Build: build, Version: version, URL: url, SHA256: hex.EncodeToString(sum[:]), Size: int64(len(b))}
	signUpdate(&m, ed25519.PrivateKey(priv))
	if err := verifyUpdate(m, base64.StdEncoding.EncodeToString(ed25519.PrivateKey(priv).Public().(ed25519.PublicKey))); err != nil {
		return err
	}
	if updatePublicKey != "" {
		if err := verifyUpdate(m, updatePublicKey); err != nil {
			return fmt.Errorf("der Schluessel passt nicht zum eingebauten oeffentlichen Schluessel: %w", err)
		}
	}
	return atomicWrite(out, jsonBytes(m))
}
