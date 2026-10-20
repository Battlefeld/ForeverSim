package main

import (
	"strconv"
	"strings"
	"testing"
)

func trees(m map[string]any) []any { return array(child(child(m, "classes"), "mage"), "trees") }

func TestTalentStringRoundTripAndValidation(t *testing.T) {
	m := manifestForTest(t)
	ranks, text, e := checkedTalentString(trees(m), fireTalents, 51)
	if e != nil || text != fireTalents {
		t.Fatalf("%q %v", text, e)
	}
	if pts := treePoints(trees(m), ranks); pts[0] != 19 || pts[1] != 32 || pts[2] != 0 {
		t.Fatalf("points %v", pts)
	}
	if tree, n := largestTreeOf(treePoints(trees(m), ranks)); tree != 1 || n != 32 {
		t.Fatalf("largest %d %d", tree, n)
	}
	for _, bad := range []string{"9", "x", "1-1-1-1", "0000000000000000000000000000000"} {
		if _, _, e := checkedTalentString(trees(m), bad, 51); e == nil && bad != "0000000000000000000000000000000" {
			t.Fatalf("%q accepted", bad)
		}
	}
	// a tier-3 talent without the points below it is not a legal build
	if _, _, e := checkedTalentString(trees(m), "000000000000003", 51); e == nil {
		t.Fatal("illegal build accepted")
	}
	if _, _, e := checkedTalentString(trees(m), fireTalents, 40); e == nil {
		t.Fatal("budget ignored")
	}
}

func TestSwapTalentSpellsKeepsTheRestOfTheBook(t *testing.T) {
	m := manifestForTest(t)
	fire, _, _ := checkedTalentString(trees(m), fireTalents, 51)
	frost := map[string]int{"improvedFrostbolt": 5}
	req := map[string]any{engineSpellsKey: []any{float64(133), float64(11366), float64(11129)}}
	swapTalentSpells(req, trees(m), fire, frost)
	got := map[int]bool{}
	for _, v := range array(req, engineSpellsKey) {
		got[int(v.(float64))] = true
	}
	if !got[133] {
		t.Fatal("a non-talent spell was removed")
	}
	if got[11366] || got[11129] {
		t.Fatal("pyroblast/combustion should go with the fire build")
	}
}

func TestLiveRequestAppliesABuildOverride(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	live, e := s.liveRequest(Job{State: map[string]any{"sim": snap}})
	if e != nil {
		t.Fatal(e)
	}
	arcane := legalBuild(t, m, 0)
	over, e := s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talentsString": arcane, "rotation": "arcane"}})
	if e != nil {
		t.Fatal(e)
	}
	if str(player(over), "talentsString") == str(player(live), "talentsString") {
		t.Fatal("talents were not replaced")
	}
	if fakeDPS(over) == fakeDPS(live) {
		t.Fatal("override changed nothing the engine would see")
	}
	if _, e = s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talentsString": "99"}}); e == nil || !strings.Contains(e.Error(), "Talentrang") {
		t.Fatalf("bad text accepted: %v", e)
	}
	if str(live, "foreverCoreSpec") != "mage" {
		t.Fatalf("spec %q", str(live, "foreverCoreSpec"))
	}
}

// legalBuild fills 51 points: the given tree first (top to bottom), the rest of the points in the next trees.
func legalBuild(t *testing.T, m map[string]any, first int) string {
	t.Helper()
	tr := trees(m)
	nodes, e := talentNodes(tr)
	if e != nil {
		t.Fatal(e)
	}
	ranks := map[string]int{}
	order := []int{first}
	for i := range tr {
		if i != first {
			order = append(order, i)
		}
	}
	for _, tree := range order {
		for progress := true; progress && totalRanks(ranks) < 51; {
			progress = false
			for _, n := range nodes {
				if n.tree == tree && totalRanks(ranks) < 51 && legalBuildAddition(nodes, ranks, n) {
					ranks[n.key]++
					progress = true
				}
			}
		}
	}
	_, text, e := checkedTalentString(tr, talentTextOf(tr, nodes, ranks), 51)
	if e != nil {
		t.Fatal(e)
	}
	return text
}

func talentTextOf(tr []any, nodes []buildNode, ranks map[string]int) string {
	text, _, _ := encodeTalentEntries(tr, talentEntries(nodes, ranks), false, 0)
	return text
}

func TestCompareBuildsPicksTheBestRotationPerBuild(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	arcane := legalBuild(t, m, 0)
	job := Job{Kind: "talent-compare", State: map[string]any{"sim": snap}, Payload: map[string]any{"priority": true, "builds": []any{
		map[string]any{"id": "live", "name": "Im Spiel"},
		map[string]any{"id": "arcane", "name": "Arkan", "talentsString": arcane},
		map[string]any{"id": "bad", "name": "Kaputt", "talentsString": "99"},
		map[string]any{"id": "fixed", "name": "Feuer fest", "talentsString": fireTalents, "rotation": "fire"},
	}}}
	got, e := s.Run(t.Context(), job)
	if e != nil {
		t.Fatal(e)
	}
	rows := array(got.(map[string]any), "builds")
	if len(rows) != 4 {
		t.Fatalf("%d rows", len(rows))
	}
	// the stand-in engine pays 7 per priority row, so the best rotation is the longest one
	longest, most := "", -1
	for _, name := range rotationNames(m, "mage") {
		if n := len(array(child(child(child(child(m, "specs"), "mage"), "rotations"), name), "priorityList")); n > most {
			longest, most = name, n
		}
	}
	live := rows[0].(map[string]any)
	if str(live, "rotation") != longest || num(live, "dps") < 1000 || len(array(live, "rotations")) != len(rotationNames(m, "mage")) {
		t.Fatalf("live row %v (want %s)", live, longest)
	}
	list := array(live, "rotations")
	if num(list[0].(map[string]any), "dps") < num(list[len(list)-1].(map[string]any), "dps") {
		t.Fatal("rotations not sorted")
	}
	if len(array(live, "priority")) == 0 {
		t.Fatal("priority list missing")
	}
	if num(rows[1].(map[string]any), "dps") <= 1000 || str(rows[1].(map[string]any), "spec") != "mage" {
		t.Fatalf("arcane row %v", rows[1])
	}
	if bad := rows[2].(map[string]any); str(bad, "error") == "" || bad["dps"] != nil {
		t.Fatalf("bad build row %v", bad)
	}
	fixed := rows[3].(map[string]any)
	if str(fixed, "rotation") != "fire" || len(array(fixed, "rotations")) != 1 {
		t.Fatalf("fixed rotation row %v", fixed)
	}
	if str(got.(map[string]any), "best") == "" || str(got.(map[string]any), "best") == "bad" {
		t.Fatalf("best %v", got.(map[string]any)["best"])
	}
}

func TestCompareBuildsGearPresetAndLimits(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	state := map[string]any{"sim": snap}
	setPresets(t, s, m, "mage", map[string]any{"gear": []any{map[string]any{"name": "Mini", "items": []any{map[string]any{"id": firstKnownItem(m)}}}}})
	got, e := s.Run(t.Context(), Job{Kind: "talent-compare", State: state, Payload: map[string]any{"rotations": "default", "builds": []any{
		map[string]any{"id": "live"},
		map[string]any{"id": "mini", "gearPreset": "mini"},
		map[string]any{"id": "nogear", "gearPreset": "gibt es nicht"},
	}}})
	if e != nil {
		t.Fatal(e)
	}
	rows := array(got.(map[string]any), "builds")
	live, mini := rows[0].(map[string]any), rows[1].(map[string]any)
	if num(live, "dps")-num(mini, "dps") < 17*10 {
		t.Fatalf("the one-item gear set should be far weaker: live %v mini %v", live["dps"], mini["dps"])
	}
	if str(rows[2].(map[string]any), "error") == "" {
		t.Fatal("unknown gear preset accepted")
	}
	if _, e = s.Run(t.Context(), Job{Kind: "talent-compare", State: state, Payload: map[string]any{"builds": []any{}}}); e == nil {
		t.Fatal("empty build list accepted")
	}
}

func firstKnownItem(m map[string]any) float64 {
	for id := 647; id < 20000; id++ {
		if child(m, "items")[strconv.Itoa(id)] == true {
			return float64(id)
		}
	}
	return 0
}

// setPresets writes a copy of the manifest whose "presets" section holds the given class entry.
func setPresets(t *testing.T, s *SimService, m map[string]any, class string, set map[string]any) {
	t.Helper()
	copyOf := make(map[string]any, len(m))
	for k, v := range m {
		copyOf[k] = v
	}
	copyOf["presets"] = map[string]any{class: set}
	if e := atomicWrite(manifestPath(s.Config), jsonBytes(copyOf)); e != nil {
		t.Fatal(e)
	}
}

func TestPresetsAreDecodedAndChecked(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	arcane := legalBuild(t, m, 0)
	setPresets(t, s, m, "mage", map[string]any{
		"talents": []any{
			map[string]any{"name": "Fire DPS", "talentsString": fireTalents},
			map[string]any{"name": "Arcane", "talentsString": arcane},
			map[string]any{"name": "Short", "talentsString": "05002252000003-2355000013013503"},
			map[string]any{"name": "Broken", "talentsString": "zz"},
		},
		"gear":   []any{map[string]any{"name": "Pre-BiS", "items": []any{map[string]any{"id": float64(647), "enchant": float64(1)}, map[string]any{}, map[string]any{"id": float64(720)}}}},
		"builds": []any{map[string]any{"name": "Fire", "talents": "Fire DPS", "gear": "Pre-BiS"}},
	})
	got, e := s.Run(t.Context(), Job{Kind: "presets", State: map[string]any{"sim": snap}})
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	talents := array(r, "talents")
	if len(talents) != 4 {
		t.Fatalf("%d presets", len(talents))
	}
	fire := talents[0].(map[string]any)
	if fire["valid"] != true || num(fire, "tree") != 2 || len(array(fire, "entries")) == 0 || num(fire, "total") != 51 {
		t.Fatalf("fire %v", fire)
	}
	entry := array(fire, "entries")[0].(map[string]any)
	if entry["spellId"] == nil || entry["definitionId"] == nil || entry["row"] == nil || entry["col"] == nil {
		t.Fatalf("entry lacks identities: %v", entry)
	}
	if short := talents[2].(map[string]any); short["valid"] != false || !strings.Contains(str(short, "error"), "Punkte") {
		t.Fatalf("a short build must be marked: %v", short)
	}
	if broken := talents[3].(map[string]any); broken["valid"] != false || str(broken, "error") == "" || broken["entries"] != nil {
		t.Fatalf("broken %v", broken)
	}
	gear := array(r, "gear")[0].(map[string]any)
	if len(array(gear, "items")) != 2 || num(array(gear, "items")[1].(map[string]any), "slot") != 2 {
		t.Fatalf("gear %v", gear)
	}
	if len(array(r, "builds")) != 1 {
		t.Fatal("builds lost")
	}
	if _, e = s.Run(t.Context(), Job{Kind: "presets", State: map[string]any{"sim": map[string]any{"class": "NOPE"}}}); e == nil {
		t.Fatal("unknown class accepted")
	}
}

func TestTalentEntriesByPlaceInTheTree(t *testing.T) {
	s, m := fakeService(t)
	tr := trees(m)
	snap := mageSnapshot(t, m, fireTalents)
	ranks, _ := decodeTalentString(tr, fireTalents)
	var entries []any
	for ti, raw := range tr {
		for _, n := range array(raw.(map[string]any), "talents") {
			node := n.(map[string]any)
			if r := ranks[str(node, "fieldName")]; r > 0 {
				loc := child(node, "location")
				// spellID deliberately wrong: the place in the tree decides
				entries = append(entries, map[string]any{"treeIndex": float64(ti + 1), "rowIdx": loc["rowIdx"], "colIdx": loc["colIdx"], "spellID": float64(1), "rank": float64(r)})
			}
		}
	}
	req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talents": entries}})
	if e != nil {
		t.Fatal(e)
	}
	if str(player(req), "talentsString") != fireTalents {
		t.Fatalf("got %q", str(player(req), "talentsString"))
	}
	// an entry for a place that does not exist is refused, not guessed
	bad := []any{map[string]any{"treeIndex": float64(1), "rowIdx": float64(6), "colIdx": float64(3), "rank": float64(1)}}
	if _, e = s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talents": bad}}); e == nil {
		t.Fatal("an unknown place was accepted")
	}
}
