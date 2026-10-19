package main

import (
	"strings"
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestFrameCRCAndAssembly(t *testing.T) {
	payload := bytes.Repeat([]byte("Questä中"), 1000)
	total := (len(payload) + PayloadBytes - 1) / PayloadBytes
	a := Assembler{}
	var out []byte
	for i := total - 1; i >= 0; i-- {
		end := (i + 1) * PayloadBytes
		if end > len(payload) {
			end = len(payload)
		}
		frame := encodeFrame(Fragment{ID: 3344, Index: uint16(i), Total: uint16(total), Data: payload[i*PayloadBytes : end]})
		f, e := decodeFrame(frame)
		if e != nil {
			t.Fatal(e)
		}
		out, e = a.Add(f)
		if e != nil {
			t.Fatal(e)
		}
		bad := append([]byte(nil), frame...)
		bad[18] ^= 1
		if _, e = decodeFrame(bad); e == nil {
			t.Fatal("corruption accepted")
		}
	}
	if !bytes.Equal(out, payload) {
		t.Fatal("roundtrip failed")
	}
}
func TestFragmentConflicts(t *testing.T) {
	a := Assembler{}
	_, _ = a.Add(Fragment{1, 0, 2, []byte("A")})
	if _, e := a.Add(Fragment{1, 0, 2, []byte("B")}); e == nil {
		t.Fatal("conflict accepted")
	}
}
func TestLuaSerializationDoesNotExecute(t *testing.T) {
	v := map[string]any{"evil": "\"};os.execute('anything')--\n\x00", "783": true}
	s := luaLiteral(v, 0)
	if !bytes.Contains([]byte(s), []byte("[783]=true")) {
		t.Fatal(s)
	}
	L := newTestLua()
	defer L.Close()
	if e := L.DoString("out=" + s); e != nil {
		t.Fatal(e)
	}
	got := fromLua(L.GetGlobal("out"), 0, mapLuaSeen())
	if got.(map[string]any)["evil"] != v["evil"] {
		t.Fatalf("%#v", got)
	}
}
func TestArchiveTraversalRejected(t *testing.T) {
	var b bytes.Buffer
	w := zip.NewWriter(&b)
	f, _ := w.Create("repo/../../escape.lua")
	f.Write([]byte("bad"))
	w.Close()
	if e := extractSource(b.Bytes(), t.TempDir()); e == nil {
		t.Fatal("path escape accepted")
	}
}
func TestArchiveFiltersExecutable(t *testing.T) {
	var b bytes.Buffer
	w := zip.NewWriter(&b)
	f, _ := w.Create("repo/payload.exe")
	f.Write([]byte("bad"))
	f, _ = w.Create("repo/Guides/ok.lua")
	f.Write([]byte("data"))
	w.Close()
	dir := t.TempDir()
	if e := extractSource(b.Bytes(), dir); e != nil {
		t.Fatal(e)
	}
	if _, e := os.Stat(filepath.Join(dir, "payload.exe")); !os.IsNotExist(e) {
		t.Fatal("executable extracted")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "Guides", "ok.lua")); string(b) != "data" {
		t.Fatal("data missing")
	}
}
func TestJobValidation(t *testing.T) {
	s := Service{}
	r := s.Execute(context.Background(), Job{Schema: 2})
	if r.Status != "error" {
		t.Fatal(r)
	}
}
func TestLowLevelNotPromoted(t *testing.T) {
	s := SimService{}
	_, e := s.liveRequest(Job{State: map[string]any{"sim": map[string]any{"level": float64(10)}}})
	if e == nil {
		t.Fatal("invented level 60")
	}
}
func TestReplyUsesOnlyOwnWindow(t *testing.T) {
	dir := t.TempDir()
	for i := 1; i <= SlotCount; i++ {
		p := filepath.Join(dir, slotName(i))
		os.MkdirAll(p, 0755)
		os.WriteFile(filepath.Join(p, "Inbox.lua"), []byte("old"), 0644)
	}
	r := Reply{Schema: 3, Session: "S", Sequence: 1, ReplyStart: 75, Status: "ok"}
	if e := publishReply(dir, r); e != nil {
		t.Fatal(e)
	}
	for _, i := range []int{74, 203, 2048} {
		b, _ := os.ReadFile(filepath.Join(dir, slotName(i), "Inbox.lua"))
		if string(b) != "old" {
			t.Fatalf("outside reply window changed: %d", i)
		}
	}
	b, _ := os.ReadFile(filepath.Join(dir, slotName(75), "Inbox.lua"))
	if !bytes.Contains(b, []byte("ForeverCore_Reply")) {
		t.Fatal("missing reply")
	}
}
func TestNativeRouteProgression(t *testing.T) {
	root := os.Getenv("FC_TEST_RUNTIME")
	native := os.Getenv("FC_TEST_LUA")
	if root == "" || native == "" {
		t.Skip("set FC_TEST_RUNTIME and FC_TEST_LUA")
	}
	skipWithoutRouteAddon(t, root)
	s := RouteService{Root: root, Lua: native}
	state := map[string]any{"race": "Human", "class": "WARRIOR", "faction": "Alliance", "level": float64(1), "map": float64(1429), "x": float64(48), "y": float64(42), "xp": float64(0), "xpMax": float64(400), "money": float64(0), "mode": "speed"}
	a, e := s.Build(context.Background(), state)
	if e != nil {
		t.Fatal(e)
	}
	state["active"] = map[string]any{"783": true}
	b, e := s.Build(context.Background(), state)
	if e != nil {
		t.Fatal(e)
	}
	ja, _ := json.Marshal(a["chapters"])
	jb, _ := json.Marshal(b["chapters"])
	if bytes.Equal(ja, jb) {
		t.Fatal("quest acceptance did not change route")
	}
}

func TestActualMythicSimAndStrictInput(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	var j Job
	if e := loadJSON("tests/mythicsim-request.json", &j); e != nil {
		t.Fatal(e)
	}
	root, _ := filepath.Abs("..")
	s := SimService{Config: Config{Runtime: root, Engine: engine, EngineRevision: str(manifestForTest(t), "engineRevision"), Data: t.TempDir()}}
	out, e := s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	r := out.(map[string]any)
	if num(r, "baselineDps") <= 0 {
		t.Fatal("no DPS")
	}
	rows := r["candidates"].([]any)
	if num(rows[0].(map[string]any), "pct") != 100 {
		t.Fatal("identical item changed result")
	}
	if str(r, "selected") != "baseline" {
		t.Fatal("downgrade selected")
	}
	bad := cloneMap(child(j.Payload, "request"))
	bad["inventedField"] = true
	if _, e = s.once(context.Background(), bad); e == nil {
		t.Fatal("unknown field silently discarded")
	}
}
func TestItemLinkPreservesIdentity(t *testing.T) {
	got := parseItemLink("|cff00ff00|Hitem:123:456:11:22:0:0:-789:0|h[Name]|h|r", map[string]any{"id": float64(123)})
	if num(got, "enchant") != 456 || num(got, "randomSuffix") != 789 || num(got, "id") != 123 {
		t.Fatal(got)
	}
	if len(got["gems"].([]any)) != 4 {
		t.Fatal(got)
	}
}

func TestRemovedCombatLogJobRejected(t *testing.T) {
 s := Service{cfg: Config{Data: t.TempDir()}}
 r := s.Execute(context.Background(), Job{Schema: 3, Session: "offline", Sequence: 1, Revision: "1", Kind: "logs"})
 if r.Status != "error" { t.Fatal("removed combat log job accepted", r) }
}

// Lean candidates (no snapshot) work for items the engine database knows; for unknown items the
// job answers "need" so the client can resend the full snapshot, instead of failing the whole job.
func TestLeanItemCandidates(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	var j Job
	if e := loadJSON("tests/mythicsim-request.json", &j); e != nil {
		t.Fatal(e)
	}
	known := map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(22267), "enchant": float64(1509)}}
	unknown := map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(999999999)}}
	delete(j.Payload, "variants")
	j.Payload["items"] = []any{known, unknown}
	root, _ := filepath.Abs("..")
	s := SimService{Config: Config{Runtime: root, Engine: engine, EngineRevision: str(manifestForTest(t), "engineRevision"), Data: t.TempDir()}}
	out, e := s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	rows := out.(map[string]any)["candidates"].([]any)
	if len(rows) != 2 || num(rows[0].(map[string]any), "pct") != 100 || rows[0].(map[string]any)["need"] == true {
		t.Fatal("known lean item must be computed", rows)
	}
	if rows[1].(map[string]any)["need"] != true {
		t.Fatal("unknown lean item must ask for its snapshot", rows)
	}
}

func TestReadAHJobFromSavedVariables(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ForeverCoreBridge.lua")
	data := "ForeverCoreBridgeDB = {\n[\"pixelFrame\"] = 0.1,\n[\"ahJob\"] = {\n[\"json\"] = \"{\\\"schema\\\":3,\\\"session\\\":\\\"s1\\\",\\\"sequence\\\":7,\\\"revision\\\":\\\"4\\\",\\\"kind\\\":\\\"item\\\",\\\"replyStart\\\":1,\\\"payload\\\":{\\\"partial\\\":true,\\\"items\\\":[]}}\",\n},\n}\n"
	if e := os.WriteFile(path, []byte(data), 0600); e != nil {
		t.Fatal(e)
	}
	j, ok, e := readAHJob(path)
	if e != nil || !ok || j.Sequence != 7 || j.Kind != "item" || j.ReplyStart != 1 || j.Payload["partial"] != true {
		t.Fatal(j, ok, e)
	}
	if e := os.WriteFile(path, []byte("ForeverCoreBridgeDB = {}\n"), 0600); e != nil {
		t.Fatal(e)
	}
	if _, ok, e := readAHJob(path); ok || e != nil {
		t.Fatal("empty database must report no job", ok, e)
	}
	// WoW folder layout: …\_classic_beta_\Interface\AddOns → …\_classic_beta_\WTF\Account\X\SavedVariables
	wow := filepath.Join(dir, "wow")
	sv := filepath.Join(wow, "WTF", "Account", "ACC", "SavedVariables")
	os.MkdirAll(sv, 0700)
	os.WriteFile(filepath.Join(sv, "ForeverCoreBridge.lua"), []byte("x=1"), 0600)
	if got := savedVariablesFiles(filepath.Join(wow, "Interface", "AddOns")); len(got) != 1 {
		t.Fatal("SavedVariables file not found", got)
	}
}

// A variant of a known item (item bonus ids, random suffix) must be computed with the stats the client read,
// not with the engine's record of the base item.
func TestVariantOfKnownItemUsesItsOwnStats(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	var j Job
	if e := loadJSON("tests/mythicsim-request.json", &j); e != nil {
		t.Fatal(e)
	}
	known := map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(22267), "enchant": float64(1509)}}
	snapshot := map[string]any{"id": float64(22267), "slot": "head", "quality": float64(2), "statsComplete": true, "armorType": "cloth",
		"rawStats": map[string]any{"ITEM_MOD_INTELLECT_SHORT": float64(400), "ITEM_MOD_STAMINA_SHORT": float64(100)}}
	variant := map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(22267), "enchant": float64(1509)}, "variant": true,
		"variantKey": "item:22267:0:0:0:0:0:0:0:12:0:0:0:1:12728", "snapshot": snapshot}
	leanVariant := map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(22267), "enchant": float64(1509)}, "variant": true,
		"variantKey": "item:22267:0:0:0:0:0:0:0:12:0:0:0:1:99999"}
	delete(j.Payload, "variants")
	j.Payload["items"] = []any{known, variant, leanVariant}
	root, _ := filepath.Abs("..")
	s := SimService{Config: Config{Runtime: root, Engine: engine, EngineRevision: str(manifestForTest(t), "engineRevision"), Data: t.TempDir()}}
	out, e := s.Run(context.Background(), j)
	if e != nil {
		t.Fatal(e)
	}
	rows := out.(map[string]any)["candidates"].([]any)
	if len(rows) != 3 {
		t.Fatal(rows)
	}
	same := rows[0].(map[string]any)
	diff := rows[1].(map[string]any)
	if num(same, "pct") != 100 {
		t.Fatal("the known item itself must stay at 100 %", same)
	}
	if num(diff, "pct") == 100 || diff["error"] != nil {
		t.Fatal("the variant must be computed with its own stats, not the base record", diff)
	}
	if rows[2].(map[string]any)["need"] != true {
		t.Fatal("a lean variant has no stats to use: it must ask for the snapshot", rows[2])
	}
	// the PC has learned the variant from the full candidate: the id alone is enough from now on
	learnedRun := j
	learnedRun.Payload = cloneMap(j.Payload)
	learnedRun.Payload["items"] = []any{variant, map[string]any{"slot": float64(0), "spec": map[string]any{"id": float64(22267), "enchant": float64(1509)}, "variant": true,
		"variantKey": "item:22267:0:0:0:0:0:0:0:12:0:0:0:1:12728"}}
	out2, e2 := s.Run(context.Background(), learnedRun)
	if e2 != nil {
		t.Fatal(e2)
	}
	rows2 := out2.(map[string]any)["candidates"].([]any)
	if rows2[1].(map[string]any)["need"] == true || num(rows2[1].(map[string]any), "pct") != num(rows2[0].(map[string]any), "pct") {
		t.Fatal("a learned variant must be computed from its id alone, with the same result", rows2)
	}
	if variantItemID("a", 22267) < 2000000000 || variantItemID("a", 22267) != variantItemID("a", 22267) || variantItemID("a", 22267) == variantItemID("b", 22267) {
		t.Fatal("variant ids must be high, stable and different per variant")
	}
}

// A dungeon drop whose level requirement is not reached yet is still computed (preview); the same item is refused
// without the preview flag.
func TestPreviewIgnoresLevelRequirementWithRealEngine(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	m := manifestForTest(t)
	runtime := t.TempDir()
	os.MkdirAll(filepath.Join(runtime, "ForeverCore"), 0o755)
	b, _ := os.ReadFile("engine-data.json")
	fam, _ := json.Marshal(familiesForTest())
	os.WriteFile(filepath.Join(runtime, "ForeverCore", "engine-data.json"), b, 0o600)
	os.WriteFile(filepath.Join(runtime, "ForeverCore", "creature-families.json"), fam, 0o600)
	snap := hunterSnapForTest()
	snap["level"] = float64(12)
	snap["faction"] = "Horde"
	for k, v := range map[string]any{"class": "HUNTER", "race": "Orc", "talents": []any{}, "talentSnapshotStatus": map[string]any{"state": "valid"},
		"spellbookStatus": map[string]any{"state": "valid"},
		"spells":          []any{map[string]any{"id": float64(75)}, map[string]any{"id": float64(2973)}, map[string]any{"id": float64(3044)}, map[string]any{"id": float64(1978)}, map[string]any{"id": float64(1130)}, map[string]any{"id": float64(13165)}},
		"equipped":        []any{map[string]any{"slot": "RangedSlot", "id": float64(18713)}}} {
		snap[k] = v
	}
	var rules map[string]any
	_ = json.Unmarshal([]byte(`{"armorTypes":["cloth","leather","mail"],"weaponSubclasses":[0,1,6,7,8,10,13,15],"dualWield":true,"shield":false,"armorTiers":[{"minLevel":1,"maxSubclass":2},{"minLevel":40,"maxSubclass":3}],"twoHandSubclasses":[1,6,8,10],"rangedSubclasses":[2,3,18]}`), &rules)
	snap["equipmentRules"] = rules
	s := &SimService{Config: Config{Engine: engine, EngineRevision: str(m, "engineRevision"), Runtime: runtime, Data: t.TempDir()}}
	// a mail chest (armor class 3, only wearable from level 40 by a hunter) needing level 30
	mail := func(preview bool) map[string]any {
		item := map[string]any{"slot": float64(4), "spec": map[string]any{"id": float64(999002)}, "name": "Mail Chest",
			"metadata": map[string]any{"slot": "chest", "minLevel": float64(30), "itemClass": float64(4), "itemSubclass": float64(3), "armorType": "mail", "equipLoc": "INVTYPE_CHEST"},
			"snapshot": map[string]any{"id": float64(999002), "slot": "chest", "quality": float64(2), "statsComplete": true, "armorType": "mail", "itemClass": float64(4), "equipLoc": "INVTYPE_CHEST",
				"rawStats": map[string]any{"ITEM_MOD_AGILITY_SHORT": float64(20), "ITEM_MOD_ARMOR_SHORT": float64(200)}}}
		if preview {
			item["ignoreLevel"] = true
		}
		return item
	}
	run := func(preview bool) (map[string]any, error) {
		out, e := s.Run(context.Background(), Job{Kind: "item", State: map[string]any{"sim": snap}, Payload: map[string]any{"items": []any{mail(preview)}}})
		if e != nil {
			return nil, e
		}
		return out.(map[string]any), nil
	}
	if _, e := run(false); e == nil {
		t.Fatal("without the preview flag the level requirement must block the item")
	}
	r, e := run(true)
	if e != nil {
		t.Fatal("a preview must compute the item although the level is not reached:", e)
	}
	if num(r, "candidateDps") <= 0 || num(r, "percent") <= 0 {
		t.Fatal("the previewed item (+20 agility) must raise the damage", r)
	}
}

// Levels 5 to 9 are calculated as level 10 with a note; below 5 nothing is calculated.
func TestLevelsFiveToNineAreApproximatedWithRealEngine(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	m := manifestForTest(t)
	runtime := t.TempDir()
	os.MkdirAll(filepath.Join(runtime, "ForeverCore"), 0o755)
	b, _ := os.ReadFile("engine-data.json")
	fam, _ := json.Marshal(familiesForTest())
	os.WriteFile(filepath.Join(runtime, "ForeverCore", "engine-data.json"), b, 0o600)
	os.WriteFile(filepath.Join(runtime, "ForeverCore", "creature-families.json"), fam, 0o600)
	var rules map[string]any
	_ = json.Unmarshal([]byte(`{"armorTypes":["cloth","leather"],"weaponSubclasses":[0,1,6,7,8,10,13,15],"dualWield":true,"shield":false,"armorTiers":[{"minLevel":10,"maxSubclass":2},{"minLevel":40,"maxSubclass":3}],"twoHandSubclasses":[1,6,8,10],"rangedSubclasses":[2,3,18]}`), &rules)
	run := func(level float64) (map[string]any, error) {
		snap := hunterSnapForTest()
		snap["level"] = level
		snap["faction"] = "Horde"
		for k, v := range map[string]any{"class": "HUNTER", "race": "Orc", "talents": []any{}, "talentSnapshotStatus": map[string]any{"state": "valid"},
			"spellbookStatus": map[string]any{"state": "valid"},
			"spells":          []any{map[string]any{"id": float64(75)}, map[string]any{"id": float64(2973)}, map[string]any{"id": float64(3044)}},
			"equipped":        []any{map[string]any{"slot": "RangedSlot", "id": float64(18713)}}, "equipmentRules": rules} {
			snap[k] = v
		}
		s := &SimService{Config: Config{Engine: engine, EngineRevision: str(m, "engineRevision"), Runtime: runtime, Data: t.TempDir()}}
		item := map[string]any{"slot": float64(4), "spec": map[string]any{"id": float64(999003)}, "name": "Leather Chest",
			"metadata": map[string]any{"slot": "chest", "minLevel": float64(1), "itemClass": float64(4), "itemSubclass": float64(2), "armorType": "leather", "equipLoc": "INVTYPE_CHEST"},
			"snapshot": map[string]any{"id": float64(999003), "slot": "chest", "quality": float64(2), "statsComplete": true, "armorType": "leather", "itemClass": float64(4), "equipLoc": "INVTYPE_CHEST",
				"rawStats": map[string]any{"ITEM_MOD_AGILITY_SHORT": float64(10), "ITEM_MOD_ARMOR_SHORT": float64(60)}}}
		out, e := s.Run(context.Background(), Job{Kind: "item", State: map[string]any{"sim": snap}, Payload: map[string]any{"items": []any{item}}})
		if e != nil {
			return nil, e
		}
		return out.(map[string]any), nil
	}
	r, e := run(7)
	if e != nil {
		t.Fatal("level 7 must be calculated as an approximation:", e)
	}
	if num(r, "candidateDps") <= 0 || num(r, "percent") <= 0 {
		t.Fatal("the leather chest (+10 agility) must raise the damage at level 7", r)
	}
	note := false
	for _, w := range array(r, "warnings") {
		if s, ok := w.(string); ok && strings.Contains(s, "Stufe 7") && strings.Contains(s, "genaehert") {
			note = true
		}
	}
	if !note {
		t.Fatal("the approximation must be named in the warnings", r["warnings"])
	}
	if _, e := run(4); e == nil {
		t.Fatal("level 4 must still be refused")
	}
}

// Resistance, defense and avoidance stats do not change a player's damage: they must not make an item unusable.
func TestNonDamageStatsDoNotRejectAnItem(t *testing.T) {
	m := manifestForTest(t)
	item := map[string]any{"id": float64(999010), "name": "Warded Helm", "slot": "head", "quality": float64(2), "statsComplete": true, "armorType": "mail",
		"rawStats": map[string]any{"ITEM_MOD_AGILITY_SHORT": float64(5), "ITEM_MOD_NATURE_RESISTANCE_SHORT": float64(10), "ITEM_MOD_SHADOW_RESISTANCE_SHORT": float64(10),
			"ITEM_MOD_DEFENSE_SKILL_RATING_SHORT": float64(3), "ITEM_MOD_DODGE_RATING_SHORT": float64(2), "RESISTANCE0_NAME": float64(40)}}
	if _, e := liveItemDatabase(item, m); e != nil {
		t.Fatal("resistance, defense and dodge must be ignored:", e)
	}
	item["rawStats"].(map[string]any)["ITEM_MOD_TOTALLY_NEW_STAT_SHORT"] = float64(4)
	if _, e := liveItemDatabase(item, m); e == nil {
		t.Fatal("an unknown stat that might matter must still be refused")
	}
}
