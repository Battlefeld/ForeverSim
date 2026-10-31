package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func manifestForTest(t *testing.T) map[string]any {
	t.Helper()
	var m map[string]any
	if e := loadJSON("engine-data.json", &m); e != nil {
		t.Fatal(e)
	}
	return m
}

func TestEngineManifestRevisionMustMatch(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var job Job
	if err := loadJSON("tests/engine-request.json", &job); err != nil {
		t.Fatal(err)
	}
	s := SimService{Config: Config{EngineRevision: "different-engine", Runtime: root, Data: t.TempDir()}}
	if _, err := s.once(context.Background(), child(job.Payload, "request")); err == nil || !strings.Contains(err.Error(), "unterschiedlichen Revisionen") {
		t.Fatalf("mismatched engine was not rejected: %v", err)
	}
}
func TestTalentIdentityAndDraftValidation(t *testing.T) {
	m := manifestForTest(t)
	trees := array(child(child(m, "classes"), "warlock"), "trees")
	// Addon's key "tap" differs from protobuf "improvedLifeTap"; spell ID is authoritative.
	entries := []any{map[string]any{"classKey": "tap", "spellID": float64(18182), "rank": float64(2)}}
	encoded, ranks, e := encodeTalentEntries(trees, entries, true, 2)
	if e != nil || encoded != "2--" || ranks["improvedLifeTap"] != 2 {
		t.Fatalf("%s %v %v", encoded, ranks, e)
	}
	if _, _, e = encodeTalentEntries(trees, append(entries, entries[0]), true, 4); e == nil {
		t.Fatal("duplicate talent accepted")
	}
	if _, _, issue := encodeTalentEntries(trees, []any{map[string]any{"classKey": "unknown", "rank": float64(1)}}, true, 51); issue == nil {
		t.Fatal("unknown talent accepted")
	}
	if _, _, e = encodeTalentEntries(trees, entries, true, 1); e == nil {
		t.Fatal("overspent draft accepted")
	}
	if _, _, e = encodeTalentEntries(trees, []any{map[string]any{"spellID": float64(18223), "rank": float64(1)}}, true, 51); e == nil {
		t.Fatal("missing tier and prerequisite accepted")
	}
}
func TestRoleProfilesAndNonemptyRotations(t *testing.T) {
	m := manifestForTest(t)
	for _, tc := range []struct{ cl, form, spec string }{{"DRUID", "cat", "feralCatDruid"}, {"DRUID", "bear", "feralBearDruid"}, {"SHAMAN", "caster", "elementalShaman"}, {"WARLOCK", "caster", "warlock"}} {
		p, e := resolveSimProfile(m, map[string]any{"class": tc.cl, "form": tc.form}, "")
		if e != nil || str(p, "spec") != tc.spec {
			t.Fatalf("%v %v", p, e)
		}
	}
	for spec, raw := range child(m, "specs") {
		for name, r := range child(raw.(map[string]any), "rotations") {
			if len(array(r.(map[string]any), "priorityList")) == 0 {
				t.Fatalf("blank APL %s %s", spec, name)
			}
		}
	}
	if _, e := resolveSimProfile(m, map[string]any{"class": "DRUID"}, "enhancementShaman"); e == nil {
		t.Fatal("cross-class spec accepted")
	}
}
func TestAnalysisIsMeanPerFight(t *testing.T) {
	result := map[string]any{"raidMetrics": map[string]any{"parties": []any{map[string]any{"players": []any{map[string]any{"name": "Player", "actions": []any{map[string]any{"id": map[string]any{"spellId": float64(133)}, "targets": []any{map[string]any{"damage": float64(400), "casts": float64(20)}}}}}}}}}}
	r := summarizeAnalysis(result, map[string]any{"simOptions": map[string]any{"iterations": float64(10)}})
	row := r["actions"].([]any)[0].(map[string]any)
	if num(row, "damage") != 40 || num(row, "casts") != 2 {
		t.Fatal(row)
	}
}
// The shipped engine manifest currently omits spellRankFamilies. The UI must
// still recover trained Hunter ranks from verified class source metadata.
func TestCorePriorityUsesSnapshotRankFamilies(t *testing.T) {
 s:=SimService{Config:Config{Runtime:".."}}
 req:=map[string]any{
  "raid":map[string]any{"parties":[]any{map[string]any{"players":[]any{map[string]any{"class":"ClassHunter"}}}}},
  engineSpellsKey:[]any{float64(75),float64(3044),float64(1978)},
  "foreverCoreSpellRankFamilies":map[string]any{
   "14287":[]any{float64(3044),float64(14281),float64(14287)},
   "25295":[]any{float64(1978),float64(13549),float64(25295)},
  },
 }
 rotation:=map[string]any{"priorityList":[]any{
  map[string]any{"action":map[string]any{"castSpell":map[string]any{"spellId":map[string]any{"spellId":float64(14287)}}}},
  map[string]any{"action":map[string]any{"castSpell":map[string]any{"spellId":map[string]any{"spellId":float64(25295)}}}},
 }}
 rows:=s.rotationPriorityFor(req,rotation)
 if len(rows)!=3 { t.Fatalf("trained shots plus automatic shot expected: %#v",rows) }
 for i,id:=range []float64{3044,1978,75} {
  if num(rows[i].(map[string]any),"spellId")!=id {t.Fatalf("rank %d missing: %#v",i,rows)}
 }
}

func TestActualEngineWeightsTalentsAndAnalysis(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	var original Job
	if e := loadJSON("tests/engine-request.json", &original); e != nil {
		t.Fatal(e)
	}
	root, e := filepath.Abs("..")
	if e != nil {
		t.Fatal(e)
	}
	s := SimService{Config: Config{Engine: engine, EngineRevision: str(manifestForTest(t), "engineRevision"), Data: t.TempDir(), Runtime: root}}
	req := cloneMap(child(original.Payload, "request"))
	child(req, "simOptions")["iterations"] = float64(40)
	j := original
	j.Kind = "weights"
	j.Payload = map[string]any{"request": req, "stats": []any{map[string]any{"key": "StatSpellDamage", "increment": float64(10)}}}
	got, e := s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	if num(r, "base") <= 0 || num(r["rows"].([]any)[0].(map[string]any), "perPoint") <= 0 {
		t.Fatal(r)
	}
	m := manifestForTest(t)
	trees := array(child(child(m, "classes"), "warlock"), "trees")
	p, _ := playerOf(req)
	var entries []any
	// Recreate the identical imported build through canonical upstream spell IDs.
	parts := strings.Split(str(p, "talentsString"), "-")
	for i, raw := range trees {
		for k, n := range array(raw.(map[string]any), "talents") {
			if i < len(parts) && k < len(parts[i]) && parts[i][k] > '0' {
				entries = append(entries, map[string]any{"spellID": num(n.(map[string]any), "spellId"), "rank": float64(parts[i][k] - '0')})
			}
		}
	}
	j.Kind = "talents"
	j.Payload = map[string]any{"request": req, "talents": entries}
	got, e = s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	r = got.(map[string]any)
	if num(r, "pct") != 0 || num(r, "base") != num(r, "cand") {
		t.Fatal("identical talents changed DPS", r)
	}
	j.Kind = "analysis"
	got, e = s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	if len(got.(map[string]any)["actions"].([]any)) == 0 {
		t.Fatal("no engine action metrics")
	}
}

func TestLiveAdapterUsesActualTalentAndItemIdentities(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	var original Job
	if e := loadJSON("tests/engine-request.json", &original); e != nil {
		t.Fatal(e)
	}
	p, _ := playerOf(child(original.Payload, "request"))
	m := manifestForTest(t)
	trees := array(child(child(m, "classes"), "warlock"), "trees")
	parts := strings.Split(str(p, "talentsString"), "-")
	var captured []any
	for i, raw := range trees {
		var entries []any
		for k, n := range array(raw.(map[string]any), "talents") {
			if i < len(parts) && k < len(parts[i]) && parts[i][k] > '0' {
				node := n.(map[string]any)
				entries = append(entries, map[string]any{"classKey": "addonAlias-" + str(node, "fieldName"), "modelSpellID": node["spellId"], "rank": float64(parts[i][k] - '0')})
			}
		}
		captured = append(captured, map[string]any{"entries": entries})
	}
	slots := []string{"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot"}
	var equipped []any
	for i, it := range array(child(p, "equipment"), "items") {
		equipped = append(equipped, map[string]any{"slot": slots[i], "id": it.(map[string]any)["id"]})
	}
	snap := map[string]any{"class": "WARLOCK", "race": "Gnome", "level": float64(60), "talentSnapshotStatus": map[string]any{"state": "valid"}, "spellbookStatus": map[string]any{"state": "valid"}, "spells": []any{map[string]any{"id": float64(686)}}, "talents": captured, "equipped": equipped, "petActive": true,
		"petLive": map[string]any{"status": "ok", "family": "Wichtel", "locale": "deDE", "level": float64(60), "mana": float64(800), "speed": float64(2),
			"stats": map[string]any{"strength": float64(122), "agility": float64(35), "stamina": float64(86), "intellect": float64(264), "spirit": float64(260)}}}
	s := SimService{Config: Config{Engine: engine, EngineRevision: str(m, "engineRevision"), Runtime: runtimeForTest(t), Data: t.TempDir()}}
	req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}})
	if e != nil {
		t.Fatal(e)
	}
	player, _ := playerOf(req)
	if num(child(child(child(player, "warlock"), "options"), "classOptions"), "summon") != 1 {
		t.Fatal("pet/options not passed")
	}
	if len(array(child(player, "rotation"), "priorityList")) == 0 {
		t.Fatal("blank live APL")
	}
	child(req, "simOptions")["iterations"] = float64(30)
	result, e := s.once(context.Background(), req)
	if e != nil {
		t.Fatal(e)
	}
	if simDPS(result) <= 0 {
		t.Fatal("live snapshot produced no DPS")
	}
}

func TestConcurrentSourceUpdateDoesNotQueueAnotherBuild(t *testing.T) {
	syncMu.Lock()
	defer syncMu.Unlock()
	r, e := syncSources(context.Background(), Config{})
	if e != nil || str(r.(map[string]any), "status") != "running" {
		t.Fatal(r, e)
	}
}
func TestRouteRuntimeHashTracksPlannerChanges(t *testing.T) {
	root := t.TempDir()
	for _, folder := range []string{"ForeverDungeonQuest", "ForeverDungeonQuestRoutes60", "_dev"} {
		os.MkdirAll(filepath.Join(root, folder), 0755)
	}
	file := filepath.Join(root, "_dev", "compiler.lua")
	os.WriteFile(file, []byte("version1"), 0644)
	first, e := routeRuntimeHash(root)
	if e != nil {
		t.Fatal(e)
	}
	os.WriteFile(file, []byte("version2"), 0644)
	second, e := routeRuntimeHash(root)
	if e != nil || first == second {
		t.Fatal("planner changed without invalidating generation", e)
	}
}

func TestLiveItemRequirementsAreCheckedOutsideAddon(t *testing.T) {
	j := Job{State: map[string]any{"sim": map[string]any{"level": float64(60), "faction": "Alliance", "equipmentRules": map[string]any{"armorTiers": []any{map[string]any{"minLevel": float64(1), "maxSubclass": float64(1)}}}}}}
	item := map[string]any{"slot": float64(4), "metadata": map[string]any{"itemClass": float64(4), "itemSubclass": float64(4), "minLevel": float64(1)}}
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("cloth class accepted plate")
	}
	child(item, "metadata")["itemSubclass"] = float64(1)
	if e := liveItemEligibility(j, item); e != nil {
		t.Fatal(e)
	}
	child(item, "metadata")["minLevel"] = float64(61)
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("level requirement ignored")
	}
	// a dungeon preview ignores the level requirement but still refuses what the class can never wear
	item["ignoreLevel"] = true
	if e := liveItemEligibility(j, item); e != nil {
		t.Fatal("a previewed item must not be blocked by its level requirement", e)
	}
	child(item, "metadata")["itemSubclass"] = float64(4)
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("a preview must still refuse armor the class cannot wear")
	}
	child(item, "metadata")["itemSubclass"] = float64(1)
	delete(item, "ignoreLevel")
	delete(j.State["sim"].(map[string]any), "equipmentRules")
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("missing requirements silently ignored")
	}
}

func TestNativeHighLevelRoutes(t *testing.T) {
	root, native := os.Getenv("FC_TEST_RUNTIME"), os.Getenv("FC_TEST_LUA")
	if root == "" || native == "" {
		t.Skip("native route runtime not set")
	}
	skipWithoutRouteAddon(t, root)
	service := RouteService{Root: root, Lua: native}
	for _, sample := range []struct {
		race, class, faction, mode string
		level                      int
	}{{"Human", "WARRIOR", "Alliance", "speed", 35}, {"Orc", "SHAMAN", "Horde", "balanced", 45}, {"NightElf", "DRUID", "Alliance", "completion", 59}} {
		route, e := service.Build(context.Background(), map[string]any{"race": sample.race, "class": sample.class, "faction": sample.faction, "mode": sample.mode, "level": float64(sample.level), "xp": float64(0), "money": float64(0)})
		if e != nil || len(array(route, "chapters")) == 0 {
			t.Fatalf("%s level %d: %v", sample.race, sample.level, e)
		}
	}
}

 
// Level-60 APL ranks must resolve to real trained spells, not be dropped.
func TestRotationPriorityMapsTrainedHunterRanksAndAutoShot(t *testing.T) {
 rotation := map[string]any{"priorityList":[]any{
  map[string]any{"action":map[string]any{"castSpell":map[string]any{"spellId":map[string]any{"spellId":float64(14287)}}}},
  map[string]any{"action":map[string]any{"castSpell":map[string]any{"spellId":map[string]any{"spellId":float64(3045)}}}},
 }}
 known := []any{float64(75),float64(3044)}
 families := map[string]any{"14287":[]any{float64(3044),float64(14281),float64(14287)}}
 priority := rotationPriority(rotation, known, families, "hunter")
 if len(priority) != 2 {
  t.Fatalf("expected Arcane Shot rank 1 plus automatic Auto Shot: %v",priority)
 }
 first := priority[0].(map[string]any)
 second := priority[1].(map[string]any)
 if num(first,"spellId") != 3044 || num(second,"spellId") != 75 || second["automatic"] != true {
  t.Fatalf("incorrect live hunter priority: %v",priority)
 }
}

func TestRotationPriorityPreservesDotConditions(t *testing.T) {
 rotation:=map[string]any{"priorityList":[]any{
  map[string]any{"action":map[string]any{
   "castSpell":map[string]any{"spellId":map[string]any{"spellId":float64(25295)}},
   "condition":map[string]any{"cmp":map[string]any{
    "op":"OpLt",
    "lhs":map[string]any{"dotRemainingTime":map[string]any{"spellId":map[string]any{"spellId":float64(25295)}}},
    "rhs":map[string]any{"const":map[string]any{"val":"1s"}},
   }},
  }},
 }}
 rows:=rotationPriority(rotation,[]any{float64(1978)},map[string]any{
  "25295":[]any{float64(1978),float64(13549),float64(25295)},
 },"hunter")
 if len(rows)!=1 {t.Fatalf("wanted single conditional shot: %v",rows)}
 row:=rows[0].(map[string]any)
 cond:=child(row,"condition")
 lhs:=child(child(cond,"cmp"),"lhs")
 if int(num(child(child(lhs,"dotRemainingTime"),"spellId"),"spellId"))!=1978 {
  t.Fatalf("expected learned rank 1978 in dot check: %#v",row)
 }
}

// A previewed offhand weapon only needs the class to be able to dual wield, not the skill at this level.
func TestPreviewOffhandNeedsOnlyTheClassAbility(t *testing.T) {
	rules := map[string]any{"dualWield": true, "weaponSubclasses": []any{float64(0), float64(15)}, "armorTiers": []any{map[string]any{"minLevel": float64(1), "maxSubclass": float64(2)}}}
	j := Job{State: map[string]any{"sim": map[string]any{"level": float64(12), "faction": "Horde", "dualWield": false, "equipmentRules": rules}}}
	item := map[string]any{"slot": float64(15), "metadata": map[string]any{"itemClass": float64(2), "weaponClass": float64(2), "itemSubclass": float64(15), "weaponSubclass": float64(15), "minLevel": float64(1)}}
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("without the dual wield skill a normal offhand weapon must be refused")
	}
	item["ignoreLevel"] = true
	if e := liveItemEligibility(j, item); e != nil {
		t.Fatal("a previewed offhand weapon must be accepted when the class can dual wield", e)
	}
	rules["dualWield"] = false
	if e := liveItemEligibility(j, item); e == nil {
		t.Fatal("a class that cannot dual wield must still be refused in the preview")
	}
}
