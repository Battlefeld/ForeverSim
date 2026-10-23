package main

import (
	"os"
	"testing"
)

func TestEnhancementWeaponRestrictions(t *testing.T) {
	cases := []struct {
		name                          string
		enchant, weapon, hand, ranged float64
		slot                          int
		want                          bool
	}{
		{"staff", 4, 8, 4, 0, 14, true}, {"staff on sword", 4, 9, 4, 0, 14, false},
		{"two hand on dagger", 1, 2, 2, 0, 14, false}, {"shield", 2, 7, 3, 0, 15, true},
		{"normal on shield", 0, 7, 3, 0, 15, false}, {"offhand", 5, 5, 3, 0, 15, true},
		{"normal on held item", 0, 5, 3, 0, 15, false}, {"scope bow", 0, 0, 0, 1, 16, true},
		{"scope wand", 0, 0, 0, 5, 16, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			typ := 13.0
			if c.slot == 16 {
				typ = 14
			}
			entry := map[string]any{"type": typ, "enchantType": c.enchant}
			item := map[string]any{"id": 1.0, "weaponType": c.weapon, "handType": c.hand, "rangedWeaponType": c.ranged}
			if got := enhancementFits(entry, item, c.slot); got != c.want {
				t.Fatalf("fits=%v, want %v", got, c.want)
			}
		})
	}
}

func TestFoodUsesTooltipStatsAndKeepsXPSeparate(t *testing.T) {
	m := manifestForTest(t)
	c, e := enhancementCatalog(m)
	if e != nil {
		t.Fatal(e)
	}
	entries := map[int]map[string]any{}
	for _, raw := range array(c, "entries") {
		r := raw.(map[string]any)
		if str(r, "kind") == "food" {
			entries[int(num(r, "itemId"))] = r
		}
	}
	if num(child(entries[249869], "stats"), "StatHealingPower") != 33 || num(child(entries[249869], "stats"), "StatSpellDamage") != 0 {
		t.Fatal("Sunny Tea must not grant spell damage")
	}
	if num(child(entries[274971], "stats"), "StatSpellDamage") != 14 {
		t.Fatal("duplicate Briny value must not overwrite tooltip")
	}
	req := map[string]any{"raid": map[string]any{"parties": []any{map[string]any{"players": []any{map[string]any{}}}}}}
	if e = addEnhancementFood(req, entries[6290], m); e != nil {
		t.Fatal(e)
	}
	p, _ := playerOf(req)
	values := array(child(p, "bonusStats"), "stats")
	total := 0.0
	for _, v := range values {
		total += v.(float64)
	}
	if total != 4 || values[int(num(child(m, "stats"), "StatAttackPower"))] != 2.0 || values[int(num(child(m, "stats"), "StatRangedAttackPower"))] != 2.0 {
		t.Fatal("AP must reach both attack types without adding the XP bonus")
	}
}

func enhancementSnapshot(t *testing.T, m map[string]any) map[string]any {
	snap := mageSnapshot(t, m, fireTalents)
	snap["equipped"] = []any{map[string]any{"slot": "ChestSlot", "id": 10021.0}, map[string]any{"slot": "MainHandSlot", "id": 13937.0}}
	snap["enhancementEnchants"] = map[string]any{"chest": 24.0, "mainhand": 0.0}
	return snap
}

func TestEnhancementsRequireKnownCurrentEffects(t *testing.T) {
	s, m := fakeService(t)
	snap := enhancementSnapshot(t, m)
	child(snap, "enhancementEnchants")["chest"] = 99999999.0
	if _, e := s.Run(t.Context(), Job{Kind: "enhancements", State: map[string]any{"sim": snap}}); e == nil {
		t.Fatal("unknown baseline enchant must not silently disappear")
	}
}

func TestEnhancementsAgainstActualEngine(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	s, m := fakeService(t)
	s.Config.Engine = engine
	snap := enhancementSnapshot(t, m)
	result, e := s.Run(t.Context(), Job{Kind: "enhancements", State: map[string]any{"sim": snap}, Payload: map[string]any{"iterations": 50.0}})
	if e != nil {
		t.Fatal(e)
	}
	r := result.(map[string]any)
	if num(r, "baselineDps") <= 0 || num(r, "tested") < 80 || num(r, "failed") != 0 || len(array(r, "foods")) != 3 {
		t.Fatalf("incomplete actual-engine comparison: %v", r)
	}
	chest, food := false, false
	last := 1e9
	for _, raw := range array(r, "recommendations") {
		row := raw.(map[string]any)
		if num(row, "delta") > last {
			t.Fatal("recommendations are not ranked")
		}
		last = num(row, "delta")
		if str(row, "slot") == "chest" {
			chest = true
			if num(row, "delta") < 0 {
				t.Fatal("must retain current enchant instead of recommending downgrade")
			}
		}
		if str(row, "slot") == "food" {
			food = true
			if num(row, "delta") <= 0 {
				t.Fatal("mage must have a food upgrade")
			}
		}
	}
	if !chest || !food {
		t.Fatal("missing chest/food recommendations")
	}
	// Compare baseline with the same explicit current enchant, not an unenchanted reference.
	req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"iterations": 50.0}})
	if e != nil {
		t.Fatal(e)
	}
	p, _ := playerOf(req)
	array(child(p, "equipment"), "items")[4].(map[string]any)["enchant"] = 24.0
	base, e := s.once(t.Context(), req)
	if e != nil || simDPS(base) != num(r, "baselineDps") {
		t.Fatalf("wrong baseline: %v", e)
	}
}
