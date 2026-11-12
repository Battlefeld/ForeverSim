package main

import (
	"os"
	"path/filepath"
	"sync/atomic"
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
	var calls, last, total atomic.Int64
	got, e := s.personalKillProfile(t.Context(), live, "mage", 30, 31, func(done, all int) {
		calls.Add(1)
		if int64(done) > last.Load() {
			last.Store(int64(done))
		}
		total.Store(int64(all))
	})
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
	if n := int64(2 * len(killOffsets) * len(killWindows)); calls.Load() != n || last.Load() != n || total.Load() != n {
		t.Fatalf("progress %d calls, last %d of %d", calls.Load(), last.Load(), total.Load())
	}
	if _, has := live[engineSpellsKey]; !has {
		t.Fatal("the live request lost its spellbook")
	}
}

func TestPersonalRouteFiles(t *testing.T) {
	dir := t.TempDir()
	if e := atomicWrite(personalLua(dir), []byte("ForeverRoutesData.personal = {}\n")); e != nil {
		t.Fatal(e)
	}
	addon := filepath.Join(t.TempDir(), "ForeverRoutes")
	restorePersonalRoute(dir, addon)
	b, e := os.ReadFile(filepath.Join(addon, "Data", "Personal.lua"))
	if e != nil || string(b) != "ForeverRoutesData.personal = {}\n" {
		t.Fatalf("not restored: %v %q", e, b)
	}
	// an earlier personal route (it replaced the shipped one whatever the data) is not put back
	_ = atomicWrite(personalLua(dir), []byte("ForeverRoutesData.routes[\"x\"] = {}\n"))
	old := filepath.Join(t.TempDir(), "ForeverRoutes")
	restorePersonalRoute(dir, old)
	if _, e := os.Stat(filepath.Join(old, "Data", "Personal.lua")); e == nil {
		t.Fatal("an old-form personal route was put back")
	}
	a := personalKey(map[string]any{"x": 1.0}, 30, "e", "r")
	if a == personalKey(map[string]any{"x": 1.0}, 31, "e", "r") || a == personalKey(map[string]any{"x": 2.0}, 30, "e", "r") || a != personalKey(map[string]any{"x": 1.0}, 30, "e", "r") {
		t.Fatal("key does not follow level and request")
	}
}

func TestChosenDungeons(t *testing.T) {
	if _, ok, e := chosenDungeons(map[string]any{}); ok || e != nil {
		t.Fatal("no choice read as one")
	}
	if keys, ok, e := chosenDungeons(map[string]any{"dungeonKeys": map[string]any{}}); !ok || e != nil || len(keys) != 0 {
		t.Fatal("an empty choice (no dungeon) not read")
	}
	keys, ok, e := chosenDungeons(map[string]any{"dungeonKeys": []any{"wailing-caverns", "shadowfang-keep"}})
	if !ok || e != nil || len(keys) != 2 || keys[1] != "shadowfang-keep" {
		t.Fatalf("choice %v %v %v", keys, ok, e)
	}
	for _, bad := range []any{[]any{"a b"}, []any{"-x --flag"}, []any{float64(3)}, "wailing-caverns", []any{"../x"}} {
		if _, _, e := chosenDungeons(map[string]any{"dungeonKeys": bad}); e == nil {
			t.Errorf("%v accepted", bad)
		}
	}
}
