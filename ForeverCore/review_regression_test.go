package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLiveSpellbookRequiredAndCanonical(t *testing.T) {
	if _, e := liveSpellIDs(map[string]any{}); e == nil {
		t.Fatal("missing book accepted")
	}
	snap := map[string]any{"spellbookStatus": map[string]any{"state": "valid"}, "spells": []any{map[string]any{"id": float64(2)}, map[string]any{"id": float64(1)}, map[string]any{"id": float64(2)}}}
	ids, e := liveSpellIDs(snap)
	if e != nil || len(ids) != 2 || ids[0] != float64(1) {
		t.Fatal(ids, e)
	}
	snap["spells"] = []any{}
	if _, e = liveSpellIDs(snap); e == nil {
		t.Fatal("empty book accepted")
	}
}
func TestIncompleteHunterNeverUsesNoPetAmmoDefaults(t *testing.T) {
	if _, e := liveClassOptions(map[string]any{}, nil, "hunter"); e == nil {
		t.Fatal("incomplete hunter accepted")
	}
	explicit := map[string]any{"ammo": float64(2), "petType": float64(1)}
	got, e := liveClassOptions(nil, map[string]any{"classOptions": explicit}, "hunter")
	if e != nil || num(got, "ammo") != 2 || num(got, "petType") != 1 {
		t.Fatal(got, e)
	}
}
func TestLevelValidationAndZeroArmor(t *testing.T) {
	m := map[string]any{"levelRange": []any{float64(10), float64(60)}}
	for _, bad := range []any{float64(9), float64(61), float64(20.5), "20", nil} {
		if validateEngineLevel(map[string]any{engineLevelKey: bad}, m, true) == nil {
			t.Fatalf("accepted %v", bad)
		}
	}
	if manifestHasLevels(map[string]any{"levelRange": []any{float64(10), float64(20)}}) {
		t.Fatal("incomplete level range accepted")
	}
	_, armor, est := defaultTarget(20, map[string]any{"targetArmor": float64(0)})
	if armor != 0 || est {
		t.Fatal("explicit zero armor replaced by estimate")
	}
}
func TestResultContextRetainsLevelAndEstimates(t *testing.T) {
	r := withResultContext(map[string]any{}, map[string]any{engineLevelKey: float64(20), engineArmorEstimatedKey: true})
	if num(r, "level") != 20 || r["targetArmorEstimated"] != true || len(array(r, "warnings")) < 2 {
		t.Fatal(r)
	}
	r = withResultContext(map[string]any{}, map[string]any{})
	if num(r, "level") != 60 || len(array(r, "warnings")) != 0 {
		t.Fatal(r)
	}
}
func TestEngineEnvDoesNotLeakLiveSpellbook(t *testing.T) {
	t.Setenv("FOREVERCORE_SPELLBOOK", "foreign.json")
	for _, v := range engineEnv(60) {
		if strings.HasPrefix(v, "FOREVERCORE_SPELLBOOK=") {
			t.Fatal("foreign book leaked")
		}
	}
}
func TestWrongBinaryRejectedBeforeCachedResult(t *testing.T) {
	root := t.TempDir()
	m := manifestForTest(t)
	m["engineSHA256"] = "wrong"
	if e := atomicWrite(filepath.Join(root, "ForeverCore", "engine-data.json"), jsonBytes(m)); e != nil {
		t.Fatal(e)
	}
	engine := filepath.Join(root, "engine")
	atomicWrite(engine, []byte("old binary"))
	var job Job
	loadJSON("tests/mythicsim-request.json", &job)
	s := SimService{Config: Config{Runtime: root, Data: t.TempDir(), Engine: engine, EngineRevision: str(m, "engineRevision")}}
	if _, e := s.once(context.Background(), child(job.Payload, "request")); e == nil || !strings.Contains(e.Error(), "Engine-Datei") {
		t.Fatal(e)
	}
}

func TestActualEngineOnlyCastsLearnedRankAndSeparatesCache(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	root, _ := filepath.Abs("..")
	s := SimService{Config: Config{Runtime: root, Data: t.TempDir(), Engine: engine, EngineRevision: str(manifestForTest(t), "engineRevision")}}
	var job Job
	if e := loadJSON("tests/mythicsim-request.json", &job); e != nil {
		t.Fatal(e)
	}
	req := cloneMap(child(job.Payload, "request"))
	player, _ := playerOf(req)
	player["rotation"] = map[string]any{"type": "TypeAPL", "priorityList": []any{map[string]any{"action": map[string]any{"castSpell": map[string]any{"spellId": map[string]any{"spellId": float64(25307)}}}}}}
	child(req, "simOptions")["iterations"] = float64(10)
	child(req, "encounter")["duration"] = float64(20)
	for _, level := range []int{20, 60} {
		req[engineLevelKey] = float64(level)
		var dps []float64
		for _, id := range []int{686, 695} {
			req[engineSpellsKey] = []any{float64(id)}
			result, e := s.once(context.Background(), req)
			if e != nil {
				t.Fatal(level, id, e)
			}
			summary := summarizeAnalysis(result, req)
			found := false
			for _, raw := range array(summary, "actions") {
				action := raw.(map[string]any)
				sid := int(num(child(action, "id"), "spellId"))
				if sid == id {
					found = true
				}
				if sid == 25307 || (id == 686 && sid == 695) {
					t.Fatal("untrained rank cast", level, id, sid)
				}
			}
			if !found {
				t.Fatal("learned rank was not cast", level, id)
			}
			dps = append(dps, simDPS(result))
		}
		if dps[0] == dps[1] {
			t.Fatal("spellbooks shared a cache entry", level, dps)
		}
	}
}

func TestTalentDraftCanGrantNewActiveSpell(t *testing.T) {
	req := map[string]any{engineSpellsKey: []any{float64(686)}}
	trees := []any{map[string]any{"talents": []any{map[string]any{"fieldName": "newAbility", "spellId": float64(999)}, map[string]any{"fieldName": "untaken", "spellId": float64(1000)}}}}
	grantDraftSpells(req, trees, map[string]int{"newAbility": 1})
	ids := array(req, engineSpellsKey)
	if len(ids) != 2 || ids[1] != float64(999) {
		t.Fatal(ids)
	}
	imported := map[string]any{}
	grantDraftSpells(imported, trees, map[string]int{"newAbility": 1})
	if imported[engineSpellsKey] != nil {
		t.Fatal("imported scenario changed")
	}
}

func TestHunterPartialOptionsCannotSilentlyDropPetAndAmmo(t *testing.T) {
	if _, e := liveClassOptions(nil, map[string]any{"classOptions": map[string]any{}}, "hunter"); e == nil {
		t.Fatal("empty hunter options accepted")
	}
	snap := map[string]any{"petActive": true}
	payload := map[string]any{"classOptions": map[string]any{"ammo": float64(1), "petType": float64(0)}}
	if _, e := liveClassOptions(snap, payload, "hunter"); e == nil {
		t.Fatal("active pet discarded")
	}
}
