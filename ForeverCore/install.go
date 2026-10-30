package main

// The installation ForeverCore.exe does itself, without PowerShell: the WoW folder found and confirmed in the window,
// the program files in the user's app folder, the addons staged and swapped in with a backup of the old ones, the
// reply slots, the configuration. Install.ps1 did the same from a console; it stays for the old ZIP package.

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// SlotCount reply slots (protocol.go) are installed as LoadOnDemand addons FC3_S0001.. beside the bridge.

// installManifest is what an installation wrote, kept in the app folder: for checking and repairing it.
type installManifest struct {
	Version   string            `json:"version"`
	Installed string            `json:"installed"`
	Addons    string            `json:"addons"`
	AddonSet  []string          `json:"addonSet"`
	Files     map[string]string `json:"files"` // app-folder file -> SHA-256
	Backup    string            `json:"backup,omitempty"`
}

const installManifestName = "installed.json"

// payloadRequired: an installation package without these is incomplete.
var payloadRequired = []string{"MythicSim.exe", "Lua.exe", "engine.lock.json", "AddOns/ForeverCoreBridge/ForeverCoreBridge.toc",
	"AddOns/ForeverSimBridge/ForeverSimBridge.toc"}

// payloadSkip: parts of the package that are not installed (the sources and the old console installer).
var payloadSkip = []string{"Source/", "Install.ps1", "Installieren.cmd", "Starten.cmd", "Restore.ps1", "ForeverCore.exe"}

// userData: what belongs to the user in the app folder and is never replaced by an installation.
var userData = map[string]bool{"config.json": true, "Data": true, "Backups": true, "ForeverRoutes": true, installManifestName: true,
	"ForeverCore.log": true}

// wowRunning reports a running WoW client (window_windows.go); nothing runs WoW elsewhere.
var wowRunning = func() bool { return false }

// WoWInstall is an AddOns folder of a WoW installation.
type WoWInstall struct {
	Addons  string `json:"addons"`
	Flavor  string `json:"flavor"`  // _classic_beta_, _classic_, ...
	Forever bool   `json:"forever"` // the client WoW: Forever runs in (wow_classic_beta)
	Current bool   `json:"current"` // the folder of the existing installation
}

// foreverFlavor is the folder of the client WoW: Forever runs in.
const foreverFlavor = "_classic_beta_"

// wowInstalls lists the AddOns folders below the given WoW folders (the folder of World of Warcraft, or one of its
// flavors), the Forever client first.
func wowInstalls(roots []string, current string) []WoWInstall {
	seen := map[string]bool{}
	var out []WoWInstall
	add := func(flavorDir string) {
		addons := filepath.Join(flavorDir, "Interface", "AddOns")
		if !isDir(flavorDir) || seen[strings.ToLower(addons)] {
			return
		}
		if !isDir(filepath.Join(flavorDir, "Interface")) && !hasWowExe(flavorDir) {
			return
		}
		seen[strings.ToLower(addons)] = true
		flavor := filepath.Base(flavorDir)
		out = append(out, WoWInstall{Addons: addons, Flavor: flavor, Forever: flavor == foreverFlavor,
			Current: current != "" && strings.EqualFold(filepath.Clean(current), filepath.Clean(addons))})
	}
	for _, root := range roots {
		if root == "" {
			continue
		}
		root = filepath.Clean(root)
		if strings.EqualFold(filepath.Base(root), "AddOns") {
			add(filepath.Dir(filepath.Dir(root)))
			continue
		}
		if strings.HasPrefix(filepath.Base(root), "_") {
			add(root)
			continue
		}
		entries, _ := os.ReadDir(root)
		for _, e := range entries {
			if e.IsDir() && strings.HasPrefix(e.Name(), "_") && strings.HasSuffix(e.Name(), "_") {
				add(filepath.Join(root, e.Name()))
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Current != out[j].Current {
			return out[i].Current
		}
		return out[i].Forever && !out[j].Forever
	})
	return out
}

func hasWowExe(dir string) bool {
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		n := strings.ToLower(e.Name())
		if strings.HasPrefix(n, "wow") && strings.HasSuffix(n, ".exe") {
			return true
		}
	}
	return false
}

func isDir(p string) bool { s, err := os.Stat(p); return err == nil && s.IsDir() }

// checkPayload tells what an installation package lacks.
func checkPayload(p fs.FS) error {
	if p == nil {
		return fmt.Errorf("Dieses Programm enthaelt kein Installationspaket")
	}
	for _, name := range payloadRequired {
		if _, err := fs.Stat(p, name); err != nil {
			return fmt.Errorf("Installationspaket unvollstaendig: %s fehlt", name)
		}
	}
	return nil
}

// payloadRoot: a package with everything in one top folder (package.py's) is read from inside it.
func payloadRoot(p fs.FS) fs.FS {
	entries, err := fs.ReadDir(p, ".")
	if err != nil || len(entries) != 1 || !entries[0].IsDir() {
		return p
	}
	sub, err := fs.Sub(p, entries[0].Name())
	if err != nil {
		return p
	}
	return sub
}

// payloadAddons: the addon folders of the package.
func payloadAddons(p fs.FS) []string {
	entries, _ := fs.ReadDir(p, "AddOns")
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			if _, err := fs.Stat(p, path.Join("AddOns", e.Name(), e.Name()+".toc")); err == nil {
				out = append(out, e.Name())
			}
		}
	}
	sort.Strings(out)
	return out
}

// InstallReport says what an installation did.
type InstallReport struct {
	AppDir   string   `json:"appDir"`
	Addons   string   `json:"addons"`
	AddonSet []string `json:"addonSet"`
	Slots    int      `json:"slots"`
	Backup   string   `json:"backup,omitempty"`
	Files    int      `json:"files"`
}

// install puts the package into appDir and its addons into the AddOns folder. Old addons of the package are moved
// to a backup first; other addons, the WTF folder and the user's data in appDir stay as they are. A failure leaves the
// old addons in place (each is swapped in from a complete staged copy).
func install(p fs.FS, addons, appDir, version string, now time.Time) (InstallReport, error) {
	rep := InstallReport{AppDir: appDir, Addons: addons}
	if err := checkPayload(p); err != nil {
		return rep, err
	}
	if wowRunning() {
		return rep, fmt.Errorf("WoW laeuft noch: bitte WoW vollstaendig schliessen und dann erneut installieren")
	}
	if addons == "" || !filepath.IsAbs(addons) || !strings.EqualFold(filepath.Base(addons), "AddOns") {
		return rep, fmt.Errorf("Bitte den Ordner Interface\\AddOns der WoW-Installation waehlen")
	}
	if err := os.MkdirAll(addons, 0o755); err != nil {
		return rep, fmt.Errorf("AddOns-Ordner nicht beschreibbar: %w", err)
	}
	if err := writable(addons); err != nil {
		return rep, fmt.Errorf("AddOns-Ordner nicht beschreibbar: %w", err)
	}
	if err := os.MkdirAll(appDir, 0o755); err != nil {
		return rep, err
	}
	// the program files
	files := map[string]string{}
	err := fs.WalkDir(p, ".", func(name string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if name == "." || strings.HasPrefix(name, "AddOns") {
			if d.IsDir() && name != "." && name != "AddOns" {
				return fs.SkipDir
			}
			return nil
		}
		for _, s := range payloadSkip {
			if name == strings.TrimSuffix(s, "/") || strings.HasSuffix(s, "/") && strings.HasPrefix(name+"/", s) {
				if d.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
		}
		if top := strings.SplitN(name, "/", 2)[0]; userData[top] {
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}
		sum, err := copyOut(p, name, filepath.Join(appDir, filepath.FromSlash(name)))
		if err != nil {
			return err
		}
		files[name] = sum
		return nil
	})
	if err != nil {
		return rep, fmt.Errorf("Programmdateien: %w", err)
	}
	rep.Files = len(files)
	// the addons: each staged complete, the old one moved to the backup, the staged one renamed into place
	backup := filepath.Join(appDir, "Backups", now.Format("20060102-150405"))
	staging := filepath.Join(addons, ".forevercore-neu")
	os.RemoveAll(staging)
	defer os.RemoveAll(staging)
	set := payloadAddons(p)
	for _, name := range set {
		dst := filepath.Join(staging, name)
		if err := copyFSTree(p, path.Join("AddOns", name), dst); err != nil {
			return rep, fmt.Errorf("Addon %s: %w", name, err)
		}
	}
	for _, name := range set {
		target := filepath.Join(addons, name)
		if isDir(target) {
			if err := moveDir(target, filepath.Join(backup, name)); err != nil {
				return rep, fmt.Errorf("Sicherung von %s: %w", name, err)
			}
			rep.Backup = backup
		}
		if err := os.Rename(filepath.Join(staging, name), target); err != nil {
			if rep.Backup != "" {
				moveDir(filepath.Join(backup, name), target) // put the old one back
			}
			return rep, fmt.Errorf("Addon %s: %w", name, err)
		}
	}
	rep.AddonSet = set
	// the reply slots
	n, err := installSlots(addons, tocInterface(p))
	if err != nil {
		return rep, fmt.Errorf("Antwortslots: %w", err)
	}
	rep.Slots = n
	// the configuration: the user's settings kept, the paths of this installation set
	cfgPath := filepath.Join(appDir, "config.json")
	cfg := map[string]any{}
	if b, err := os.ReadFile(cfgPath); err == nil {
		json.Unmarshal(b, &cfg)
	}
	var lock struct {
		BuildIdentity string `json:"buildIdentity"`
	}
	if b, err := fs.ReadFile(p, "engine.lock.json"); err == nil {
		json.Unmarshal(b, &lock)
	}
	cfg["addons"], cfg["engine"], cfg["engineRevision"] = addons, "MythicSim.exe", lock.BuildIdentity
	cfg["runtime"], cfg["data"], cfg["lua"] = "Runtime", "Data", "Lua.exe"
	if _, ok := cfg["autoSync"]; !ok {
		cfg["autoSync"] = true
	}
	if err := atomicWrite(cfgPath, jsonBytes(cfg)); err != nil {
		return rep, err
	}
	m := installManifest{Version: version, Installed: now.UTC().Format(time.RFC3339), Addons: addons, AddonSet: set, Files: files, Backup: rep.Backup}
	return rep, atomicWrite(filepath.Join(appDir, installManifestName), jsonBytes(m))
}

// verifyInstall lists what is missing or changed in an installation (empty: intact).
func verifyInstall(appDir string) ([]string, error) {
	var m installManifest
	if err := loadJSON(filepath.Join(appDir, installManifestName), &m); err != nil {
		return nil, fmt.Errorf("keine Installation gefunden")
	}
	var bad []string
	names := make([]string, 0, len(m.Files))
	for name := range m.Files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if sum, err := fileSHA(filepath.Join(appDir, filepath.FromSlash(name))); err != nil || sum != m.Files[name] {
			bad = append(bad, name)
		}
	}
	for _, name := range m.AddonSet {
		if !isDir(filepath.Join(m.Addons, name)) {
			bad = append(bad, "AddOns/"+name)
		}
	}
	for i := 1; i <= SlotCount; i++ {
		name := fmt.Sprintf("FC3_S%04d", i)
		if _, err := os.Stat(filepath.Join(m.Addons, name, name+".toc")); err != nil {
			bad = append(bad, "AddOns/FC3_S*")
			break
		}
	}
	return bad, nil
}

// installSlots writes the reply slots that are missing or out of date; a slot holds an empty inbox until ForeverCore
// writes a reply into it.
func installSlots(addons, iface string) (int, error) {
	n := 0
	for i := 1; i <= SlotCount; i++ {
		name := fmt.Sprintf("FC3_S%04d", i)
		dir := filepath.Join(addons, name)
		toc := fmt.Sprintf("## Interface: %s\n## Title: ForeverCore Antwort %d\n## LoadOnDemand: 1\n## Dependencies: ForeverCoreBridge\nInbox.lua\n", iface, i)
		if b, err := os.ReadFile(filepath.Join(dir, name+".toc")); err == nil && string(b) == toc {
			n++
			continue
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return n, err
		}
		if err := os.WriteFile(filepath.Join(dir, name+".toc"), []byte(toc), 0o644); err != nil {
			return n, err
		}
		if err := os.WriteFile(filepath.Join(dir, "Inbox.lua"), []byte("ForeverCore_Reply=nil\n"), 0o644); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

// tocInterface: the interface version the package's bridge declares (16001 when it says none).
func tocInterface(p fs.FS) string {
	f, err := p.Open("AddOns/ForeverCoreBridge/ForeverCoreBridge.toc")
	if err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := strings.TrimPrefix(sc.Text(), "\ufeff")
			if v, ok := strings.CutPrefix(line, "## Interface:"); ok && strings.TrimSpace(v) != "" {
				return strings.TrimSpace(v)
			}
		}
	}
	return "16001"
}

func writable(dir string) error {
	f, err := os.CreateTemp(dir, ".forevercore-test-*")
	if err != nil {
		return err
	}
	name := f.Name()
	f.Close()
	return os.Remove(name)
}

// copyOut writes one file of the package to dst through a temporary file, and returns its SHA-256.
func copyOut(p fs.FS, name, dst string) (string, error) {
	src, err := p.Open(name)
	if err != nil {
		return "", err
	}
	defer src.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return "", err
	}
	tmp := dst + ".neu"
	out, err := os.Create(tmp)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	_, err = io.Copy(io.MultiWriter(out, h), src)
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Rename(tmp, dst)
	}
	if err != nil {
		os.Remove(tmp)
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func copyFSTree(p fs.FS, root, dst string) error {
	return fs.WalkDir(p, root, func(name string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel := name
		if root != "." {
			rel = strings.TrimPrefix(strings.TrimPrefix(name, root), "/")
		} else if name == "." {
			rel = ""
		}
		target := filepath.Join(dst, filepath.FromSlash(rel))
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		_, err = copyOut(p, name, target)
		return err
	})
}

// moveDir moves a folder, also across drives (copy, then remove).
func moveDir(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	if err := copyFSTree(os.DirFS(src), ".", dst); err != nil {
		return err
	}
	return os.RemoveAll(src)
}

func fileSHA(name string) (string, error) {
	f, err := os.Open(name)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
