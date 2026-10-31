package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
	"time"
)

func testPayload() fstest.MapFS {
	f := func(s string) *fstest.MapFile { return &fstest.MapFile{Data: []byte(s)} }
	return fstest.MapFS{
		"ForeverEngine.exe":                    f("engine"),
		"Lua.exe":                          f("lua"),
		"engine.lock.json":                 f(`{"buildIdentity":"abc+def"}`),
		"Runtime/ForeverCore/headless.lua": f("-- headless"),
		"AddOns/ForeverCoreBridge/ForeverCoreBridge.toc": f("## Interface: 16001\nBridge.lua\n"),
		"AddOns/ForeverCoreBridge/Bridge.lua":            f("-- bridge"),
		"AddOns/ForeverSimBridge/ForeverSimBridge.toc":   f("## Interface: 16001\n"),
		"AddOns/ForeverRoutes/ForeverRoutes.toc":         f("## Interface: 16001\n"),
		"AddOns/ForeverRoutes/Data/Routes.lua":           f("-- routes"),
		"Source/ForeverCore/main.go":                     f("package main"),
		"Lizenzen/QUELLEN.txt":                           f("licences"),
	}
}

func TestInstallFreshAndAgain(t *testing.T) {
	dir := t.TempDir()
	addons := filepath.Join(dir, "WoW", "_classic_beta_", "Interface", "AddOns")
	app := filepath.Join(dir, "App")
	os.MkdirAll(filepath.Join(addons, "SomeoneElses"), 0o755)
	os.MkdirAll(filepath.Join(addons, "ForeverSimBridge"), 0o755)
	os.WriteFile(filepath.Join(addons, "ForeverSimBridge", "old.lua"), []byte("old"), 0o644)
	os.MkdirAll(filepath.Join(app, "Data"), 0o755)
	os.WriteFile(filepath.Join(app, "config.json"), []byte(`{"routesNoUpdate":true}`), 0o644)
	now := time.Date(2026, 11, 2, 10, 0, 0, 0, time.UTC)
	rep, err := install(testPayload(), addons, app, "1.0.0", now)
	if err != nil {
		t.Fatal(err)
	}
	if rep.Slots != SlotCount || len(rep.AddonSet) != 3 || rep.Backup == "" {
		t.Fatalf("report %+v", rep)
	}
	for _, p := range []string{"ForeverEngine.exe", "Lua.exe", "Runtime/ForeverCore/headless.lua", "Lizenzen/QUELLEN.txt"} {
		if _, err := os.Stat(filepath.Join(app, p)); err != nil {
			t.Errorf("%s not installed", p)
		}
	}
	for _, p := range []string{"Source"} {
		if _, err := os.Stat(filepath.Join(app, p)); err == nil {
			t.Errorf("%s installed", p)
		}
	}
	if _, err := os.Stat(filepath.Join(addons, "SomeoneElses")); err != nil {
		t.Error("another addon was touched")
	}
	if _, err := os.Stat(filepath.Join(addons, "ForeverSimBridge", "old.lua")); err == nil {
		t.Error("the old addon is still in place")
	}
	if _, err := os.Stat(filepath.Join(rep.Backup, "ForeverSimBridge", "old.lua")); err != nil {
		t.Error("the old addon was not backed up")
	}
	b, _ := os.ReadFile(filepath.Join(addons, "FC3_S2048", "FC3_S2048.toc"))
	if !strings.Contains(string(b), "## LoadOnDemand: 1") || !strings.Contains(string(b), "## Interface: 16001") {
		t.Errorf("slot toc %q", b)
	}
	cfg, _ := os.ReadFile(filepath.Join(app, "config.json"))
	for _, want := range []string{`"routesNoUpdate": true`, `"engineRevision": "abc+def"`, `"addons": "` + strings.ReplaceAll(addons, `\`, `\\`)} {
		if !strings.Contains(string(cfg), want) {
			t.Errorf("config lacks %s: %s", want, cfg)
		}
	}
	if bad, err := verifyInstall(app); err != nil || len(bad) != 0 {
		t.Fatalf("verify: %v %v", bad, err)
	}
	// a changed program file is found, and installing again repairs it without a second backup of the user's data
	os.WriteFile(filepath.Join(app, "Lua.exe"), []byte("broken"), 0o644)
	if bad, _ := verifyInstall(app); len(bad) != 1 || bad[0] != "Lua.exe" {
		t.Fatalf("verify after damage: %v", bad)
	}
	if _, err := install(testPayload(), addons, app, "1.0.0", now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if bad, _ := verifyInstall(app); len(bad) != 0 {
		t.Fatalf("not repaired: %v", bad)
	}
	if _, err := os.Stat(filepath.Join(addons, ".forevercore-neu")); err == nil {
		t.Error("staging folder left behind")
	}
}

func TestInstallRefuses(t *testing.T) {
	dir := t.TempDir()
	addons := filepath.Join(dir, "Interface", "AddOns")
	now := time.Now()
	if _, err := install(nil, addons, dir, "1", now); err == nil {
		t.Error("installed without a package")
	}
	if _, err := install(testPayload(), filepath.Join(dir, "Interface"), dir, "1", now); err == nil {
		t.Error("installed into a folder that is not AddOns")
	}
	wowRunning = func() bool { return true }
	defer func() { wowRunning = func() bool { return false } }()
	if _, err := install(testPayload(), addons, dir, "1", now); err == nil || !strings.Contains(err.Error(), "WoW") {
		t.Errorf("installed while WoW runs: %v", err)
	}
}

func TestWoWInstallsForeverFirst(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"_retail_", "_classic_", "_classic_beta_"} {
		os.MkdirAll(filepath.Join(dir, "World of Warcraft", f, "Interface", "AddOns"), 0o755)
	}
	os.MkdirAll(filepath.Join(dir, "World of Warcraft", "Data"), 0o755)
	got := wowInstalls([]string{filepath.Join(dir, "World of Warcraft"), filepath.Join(dir, "missing")}, "")
	if len(got) != 3 || !got[0].Forever || got[0].Flavor != "_classic_beta_" {
		t.Fatalf("installs %+v", got)
	}
	cur := filepath.Join(dir, "World of Warcraft", "_classic_", "Interface", "AddOns")
	got = wowInstalls([]string{filepath.Join(dir, "World of Warcraft"), cur}, cur)
	if len(got) != 3 || !got[0].Current {
		t.Fatalf("the current installation is not first: %+v", got)
	}
}
