package main

import (
	"os"
	"path/filepath"
	"testing"
)

// The personal kill profile is the live character's engine request at each level: its talents and items stay, the
// level changes, and the own spellbook only counts at its own level.
func TestPersonalKillProfile(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	snap["level"] = float64(30)
	live, e := s.liveRequest(Job{Kind: "route-profile", State: map[string]any{"sim": snap}})
	if e != nil {
		t.Fatal(e)
	}
	got, e := s.personalKillProfile(t.Context(), live, "mage", 30, 31)
	if e != nil {
		t.Fatal(e)
	}
	if got["schema"] != killProfileSchema || got["gear"] != "live character" || got["talents"] == "" || got["race"] != "Troll" {
		t.Fatalf("header %v", got)
	}
	levels := got["levels"].([]*killLevel)
	if len(levels) != 2 || levels[0].Level != 30 || levels[1].Level != 31 || len(levels[0].Targets["0"]) != len(killWindows) {
		t.Fatalf("levels %+v", levels)
	}
	for _, p := range levels[1].Targets["2"] {
		if p.Damage <= 0 {
			t.Errorf("point %+v", p)
		}
	}
	if _, has := live[engineSpellsKey]; !has {
		t.Fatal("the live request lost its spellbook")
	}
}

func TestPersonalRouteFiles(t *testing.T) {
	dir := t.TempDir()
	if e := atomicWrite(personalLua(dir), []byte("-- route\n")); e != nil {
		t.Fatal(e)
	}
	addon := filepath.Join(t.TempDir(), "ForeverRoutes")
	restorePersonalRoute(dir, addon)
	b, e := os.ReadFile(filepath.Join(addon, "Data", "Personal.lua"))
	if e != nil || string(b) != "-- route\n" {
		t.Fatalf("not restored: %v %q", e, b)
	}
	a := personalKey(map[string]any{"x": 1.0}, 30, "e", "r")
	if a == personalKey(map[string]any{"x": 1.0}, 31, "e", "r") || a == personalKey(map[string]any{"x": 2.0}, 30, "e", "r") || a != personalKey(map[string]any{"x": 1.0}, 30, "e", "r") {
		t.Fatal("key does not follow level and request")
	}
}
