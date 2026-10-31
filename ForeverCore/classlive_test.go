package main

import (
	"context"
	"os"
	"strings"
	"testing"
)

func FCTestEngine(t *testing.T) string {
	t.Helper()
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	return engine
}

func ruleIDs(t *testing.T, m map[string]any, class, field string, value float64) []int {
	t.Helper()
	for _, raw := range array(child(child(m, "liveOptions"), "rules"), class) {
		r := raw.(map[string]any)
		if str(r, "field") == field && (r["value"] == value || (value == 1 && r["value"] == true)) {
			return ids(array(r, "ids"))
		}
	}
	t.Fatalf("no rule %s.%s=%v", class, field, value)
	return nil
}

func auraSnap(auras ...int) map[string]any {
	list, info := []any{}, []any{}
	for _, a := range auras {
		list = append(list, float64(a))
		info = append(info, map[string]any{"id": float64(a), "name": "Aura"})
	}
	return map[string]any{"activeAuras": list, "activeAuraInfo": info}
}

func TestClassOptionsFromLiveState(t *testing.T) {
	m := manifestForTest(t)
	mageArmor := ruleIDs(t, m, "mage", "defaultMageArmor", 1)
	got, e := liveClassState(auraSnap(mageArmor[0]), m, nil, "mage", "mage", 40)
	if e != nil || got.options["defaultMageArmor"] != float64(1) || len(got.warnings) != 0 {
		t.Fatalf("mage armor: %v %v", got, e)
	}
	// Two armors at once cannot be represented.
	ice := ruleIDs(t, m, "mage", "defaultMageArmor", 2)
	if _, e = liveClassState(auraSnap(mageArmor[0], ice[0]), m, nil, "mage", "mage", 40); e == nil {
		t.Fatal("two armors accepted")
	}
	// Frost Armor (168) has no engine model: reported, not mapped to Ice Armor.
	got, _ = liveClassState(auraSnap(168), m, nil, "mage", "mage", 20)
	if got.options["defaultMageArmor"] != nil || len(got.warnings) != 1 || !strings.Contains(got.warnings[0], "nicht in der SIM") {
		t.Fatalf("frost armor: %v %v", got.options, got.warnings)
	}
	// A self buff from the player's own book is the rotation's business, not a missing buff.
	s := auraSnap(168)
	s["spells"] = []any{map[string]any{"id": float64(168)}}
	if got, _ = liveClassState(s, m, nil, "mage", "mage", 20); len(got.warnings) != 0 {
		t.Fatalf("own spell reported: %v", got.warnings)
	}

	stance := ruleIDs(t, m, "warrior", "defaultStance", 3)
	got, _ = liveClassState(map[string]any{"formSpell": float64(stance[0])}, m, nil, "warrior", "dpsWarrior", 40)
	if got.options["defaultStance"] != float64(3) {
		t.Fatalf("stance: %v", got.options)
	}

	wf := ruleIDs(t, m, "shaman", "imbueMh", 1)
	ench := map[string]any{"weaponEnchants": map[string]any{"mainhand": float64(wf[0]), "offhand": float64(wf[0])}}
	got, _ = liveClassState(ench, m, nil, "shaman", "enhancementShaman", 30)
	if got.options["imbueMh"] != float64(1) || got.specOptions["imbueOh"] != float64(1) || len(got.warnings) != 0 {
		t.Fatalf("enhancement imbues: %v %v %v", got.options, got.specOptions, got.warnings)
	}
	got, _ = liveClassState(ench, m, nil, "shaman", "elementalShaman", 30)
	if got.specOptions["imbueOh"] != nil || len(got.warnings) != 1 {
		t.Fatalf("elemental offhand: %v %v", got.specOptions, got.warnings)
	}
	got, _ = liveClassState(map[string]any{"weaponEnchants": map[string]any{"mainhand": float64(9999)}}, m, nil, "rogue", "rogue", 30)
	if len(got.warnings) != 1 || !strings.Contains(got.warnings[0], "9999") {
		t.Fatalf("unknown enchant: %v", got.warnings)
	}

	shadow := ruleIDs(t, m, "priest", "preShadowform", 1)
	fire := ruleIDs(t, m, "priest", "armor", 1)
	got, _ = liveClassState(map[string]any{"formSpell": float64(shadow[0]), "activeAuras": []any{float64(fire[0])}}, m, nil, "priest", "dpsPriest", 50)
	if got.options["preShadowform"] != true || got.options["armor"] != float64(1) {
		t.Fatalf("priest: %v", got.options)
	}
}

func impSnapForTest(level float64) map[string]any {
	return map[string]any{"petActive": true,
		"petLive": map[string]any{"status": "ok", "family": "Wichtel", "locale": "deDE", "level": level, "mana": float64(250), "speed": float64(2),
			"stats": map[string]any{"strength": float64(20), "agility": float64(15), "stamina": float64(25), "intellect": float64(60), "spirit": float64(55)}},
		"petSpellInfo": []any{map[string]any{"id": float64(7799), "described": true, "values": []any{float64(13), float64(18), float64(10)}, "cost": float64(25)}}}
}

func TestWarlockDemonFromLiveState(t *testing.T) {
	m := manifestForTest(t)
	f := familiesForTest()
	got, e := liveClassState(impSnapForTest(20), m, f, "warlock", "warlock", 20)
	if e != nil {
		t.Fatal(e)
	}
	d := child(got.privates, engineWarlockKey)
	fb := child(child(d, "spells"), "firebolt")
	if got.options["summon"] != float64(1) || num(fb, "min") != 13 || num(fb, "max") != 18 || num(fb, "cost") != 25 || num(d, "mana") != 250 || d["meleeMin"] != nil {
		t.Fatalf("imp: %v %v", got.options, d)
	}
	// An imp whose attributes the client reports as 0 is still calculated, with a note.
	z := impSnapForTest(20)
	child(child(z, "petLive"), "stats")["strength"] = float64(0)
	child(child(z, "petLive"), "stats")["intellect"] = float64(0)
	if gz, ez := liveClassState(z, m, f, "warlock", "warlock", 20); ez != nil || num(child(gz.privates, engineWarlockKey), "strength") != 0 || !strings.Contains(strings.Join(gz.warnings, "|"), "nicht lesbar") {
		t.Fatalf("zero attributes: %v %v", gz.warnings, ez)
	}
	// Succubus: melee base damage per engine swing from the client's damage line.
	s := impSnapForTest(20)
	pet := child(s, "petLive")
	pet["family"], pet["speed"] = "Sukkubus", float64(2)
	pet["attackPower"] = map[string]any{"base": float64(28), "pos": float64(0), "neg": float64(0)}
	pet["damage"] = map[string]any{"min": float64(14), "max": float64(18), "pos": float64(0), "neg": float64(0), "percent": float64(1)}
	s["petSpellInfo"] = []any{map[string]any{"id": float64(7815), "described": true, "values": []any{float64(33)}}}
	got, e = liveClassState(s, m, f, "warlock", "warlock", 20)
	d = child(got.privates, engineWarlockKey)
	if e != nil || got.options["summon"] != float64(3) || num(d, "meleeMin") != 10 || num(d, "meleeMax") != 14 || num(child(child(d, "spells"), "lashOfPain"), "max") != 33 {
		t.Fatalf("succubus: %v %v %v", got.options, d, e)
	}
	// Felguard has no engine model.
	pet["family"] = "Teufelswache"
	if _, e = liveClassState(s, m, f, "warlock", "warlock", 50); e == nil || !strings.Contains(e.Error(), "Felguard") {
		t.Fatalf("felguard: %v", e)
	}
	// A demon spell the client does not describe is not guessed.
	s = impSnapForTest(20)
	s["petSpellInfo"] = []any{map[string]any{"id": float64(7799), "described": false}}
	if _, e = liveClassState(s, m, f, "warlock", "warlock", 20); e == nil {
		t.Fatal("undescribed firebolt accepted")
	}
	// Sacrificed before the pull, no demon out.
	sac := ruleIDs(t, m, "warlock", "sacrificeDemon", 3)
	got, _ = liveClassState(auraSnap(sac[0]), m, f, "warlock", "warlock", 40)
	if got.options["summon"] != float64(3) || got.options["sacrificeSummon"] != true {
		t.Fatalf("sacrifice: %v", got.options)
	}
	got, _ = liveClassState(map[string]any{}, m, f, "warlock", "warlock", 20)
	if got.options["summon"] != float64(0) || len(got.warnings) != 1 {
		t.Fatalf("no demon: %v %v", got.options, got.warnings)
	}
}

// Full path with the real engine: a level 20 imp from the client against the level 60 imp.
func TestActualEngineLiveWarlockLevel20(t *testing.T) {
	engine := FCTestEngine(t)
	m := manifestForTest(t)
	s := SimService{Config: Config{Engine: engine, EngineRevision: str(m, "engineRevision"), Runtime: runtimeForTest(t), Data: t.TempDir()}}
	base := map[string]any{"class": "WARLOCK", "race": "Orc", "level": float64(20), "talents": []any{}, "talentSnapshotStatus": map[string]any{"state": "valid"},
		"spellbookStatus": map[string]any{"state": "valid"},
		// Shadow Bolt rank 3, Immolate rank 2, Corruption rank 2 (learned by 20).
		"spells": []any{map[string]any{"id": float64(695)}, map[string]any{"id": float64(707)}, map[string]any{"id": float64(6222)}}}
	run := func(extra map[string]any) (float64, map[string]any) {
		snap := cloneMap(base)
		for k, v := range extra {
			snap[k] = v
		}
		req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}})
		if e != nil {
			t.Fatal(e)
		}
		child(req, "simOptions")["iterations"] = float64(40)
		res, e := s.once(context.Background(), req)
		if e != nil {
			t.Fatal(e)
		}
		return simDPS(res), req
	}
	live, req := run(impSnapForTest(20))
	if req[engineWarlockKey] == nil || !(live > 0) {
		t.Fatalf("live imp: %v", live)
	}
	strong := impSnapForTest(20)
	strong["petSpellInfo"] = []any{map[string]any{"id": float64(7799), "described": true, "values": []any{float64(130), float64(180)}, "cost": float64(25)}}
	if more, _ := run(strong); more <= live {
		t.Fatalf("stronger Firebolt %.2f not above %.2f", more, live)
	}
}
