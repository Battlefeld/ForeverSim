package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// The tests in this package cannot run the real MythicSim engine (it is built from an upstream repository in CI).
// For the jobs that only orchestrate engine runs, the test binary itself acts as a stand-in engine: it is started
// as "<test binary> sim --strict --infile in --outfile out" and writes a result whose DPS depends on exactly the
// inputs a job is supposed to change (talents, rotation, gear, iterations), so a test can tell they arrived.
func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == "sim" {
		fakeEngine()
		return
	}
	os.Exit(m.Run())
}

func fakeEngine() {
	var in, out string
	for i, a := range os.Args {
		if a == "--infile" && i+1 < len(os.Args) {
			in = os.Args[i+1]
		}
		if a == "--outfile" && i+1 < len(os.Args) {
			out = os.Args[i+1]
		}
	}
	b, e := os.ReadFile(in)
	if e != nil {
		os.Exit(2)
	}
	var req map[string]any
	if json.Unmarshal(b, &req) != nil {
		os.Exit(2)
	}
	dps := fakeDPS(req)
	duration := num(child(req, "encounter"), "duration")
	iterations := num(child(req, "simOptions"), "iterations")
	total := dps * duration * iterations
	target := func(share float64) []any {
		return []any{map[string]any{"damage": total * share, "casts": 10.0, "hits": 10.0}}
	}
	player := map[string]any{
		"actions": []any{
			map[string]any{"id": map[string]any{"spellId": 133.0}, "targets": target(.59)},
			map[string]any{"id": map[string]any{"spellId": 116.0}, "targets": target(.25)},
			map[string]any{"id": map[string]any{"otherId": "OtherActionIgnite"}, "targets": target(.1)},
			map[string]any{"id": map[string]any{"spellId": 2948.0}, "targets": target(.04)},
			map[string]any{"id": map[string]any{"spellId": 5.0}, "targets": target(.01)},
			map[string]any{"id": map[string]any{"spellId": 6.0}, "targets": target(.01)},
		},
		"resources": []any{map[string]any{"type": "ResourceTypeMana", "actualGain": -5 * duration * iterations}, map[string]any{"type": "ResourceTypeEnergy", "actualGain": 9.0}},
	}
	os.WriteFile(out, jsonBytes(map[string]any{"raidMetrics": map[string]any{"dps": map[string]any{"avg": dps},
		"parties": []any{map[string]any{"players": []any{player}}}}}), 0o600)
}

// fakeDPS: talents +3 per point, gear +17 per item, rotation +7 per priority row, each known spell +0.01.
func fakeDPS(req map[string]any) float64 {
	player, e := playerOf(req)
	if e != nil {
		return 1
	}
	dps := 1000.0
	for _, ch := range str(player, "talentsString") {
		if ch >= '0' && ch <= '9' {
			dps += 3 * float64(ch-'0')
		}
	}
	for _, raw := range array(child(player, "equipment"), "items") {
		if it, ok := raw.(map[string]any); ok && num(it, "id") > 0 {
			dps += 17
		}
	}
	dps += 7 * float64(len(array(child(player, "rotation"), "priorityList")))
	// rows in ascending spell order pay a little: a tuned rotation has something to find
	prev := -1
	for _, raw := range array(child(player, "rotation"), "priorityList") {
		id := int(num(child(child(child(raw.(map[string]any), "action"), "castSpell"), "spellId"), "spellId"))
		if prev >= 0 && id >= prev {
			dps += 0.1
		}
		prev = id
	}
	dps += 0.5 * num(child(req, "encounter"), "duration") / 10 // longer fights pay more: the curve rises
	dps += 0.01 * float64(len(array(req, engineSpellsKey)))
	return dps
}

// mageSnapshot is a level 60 troll mage as the addon reports it, with the real engine manifest of this repository.
// Every item is one the manifest knows; talents are given by their real spell ids.
func mageSnapshot(t *testing.T, m map[string]any, talentText string) map[string]any {
	t.Helper()
	trees := array(child(child(m, "classes"), "mage"), "trees")
	ranks, e := decodeTalentString(trees, talentText)
	if e != nil {
		t.Fatal(e)
	}
	var captured []any
	var spells []any
	for _, raw := range trees {
		var entries []any
		for _, n := range array(raw.(map[string]any), "talents") {
			node := n.(map[string]any)
			if r := ranks[str(node, "fieldName")]; r > 0 {
				entries = append(entries, map[string]any{"classKey": "addon-" + str(node, "fieldName"), "spellID": node["spellId"], "rank": float64(r)})
			}
		}
		captured = append(captured, map[string]any{"entries": entries})
	}
	for _, id := range []int{133, 116, 2136, 2948, 12051} {
		spells = append(spells, map[string]any{"id": float64(id)})
	}
	for id := range talentSpellIDs(trees, ranks) {
		spells = append(spells, map[string]any{"id": float64(id)})
	}
	slots := []string{"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot"}
	var equipped []any
	known := child(m, "items")
	found := 0
	for id := 647; found < len(slots) && id < 20000; id++ {
		if known[strconv.Itoa(id)] == true {
			equipped = append(equipped, map[string]any{"slot": slots[found], "id": float64(id)})
			found++
		}
	}
	return map[string]any{"class": "MAGE", "race": "Troll", "faction": "Horde", "level": float64(60),
		"talentSnapshotStatus": map[string]any{"state": "valid"}, "spellbookStatus": map[string]any{"state": "valid"},
		"spells": spells, "talents": captured, "equipped": equipped, "unspentTalentPoints": float64(0)}
}

// fakeService is a SimService wired to the stand-in engine and the real manifest.
func fakeService(t *testing.T) (*SimService, map[string]any) {
	t.Helper()
	m := manifestForTest(t)
	delete(m, "engineSHA256") // the returned manifest also belongs to the stand-in
	exe, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	runtime := runtimeForTest(t)
	// This fixture runs the test binary as an engine. The production manifest may
	// be bound to the freshly built real engine; do not bind the stand-in to it.
	var fixture map[string]any
	path := filepath.Join(runtime, "ForeverCore", "engine-data.json")
	if e := loadJSON(path, &fixture); e != nil {
		t.Fatal(e)
	}
	delete(fixture, "engineSHA256")
	if e := os.WriteFile(path, jsonBytes(fixture), 0o600); e != nil {
		t.Fatal(e)
	}
	return &SimService{Config: Config{Engine: exe, EngineRevision: str(m, "engineRevision"), Runtime: runtime, Data: t.TempDir()}}, m
}

const fireTalents = "05002252000003-23550000130135031-"

func TestFakeEngineRunsALiveRequest(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	got, e := s.Run(t.Context(), Job{Kind: "sim", State: map[string]any{"sim": snap}})
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	if num(r, "dps") < 1000 || !strings.HasPrefix(str(r, "engine"), "MythicSim") {
		t.Fatalf("unexpected result %v", r)
	}
	if _, e = os.Stat(filepath.Join(s.Config.Data, "Sims")); e != nil {
		t.Fatal("result not cached")
	}
}
