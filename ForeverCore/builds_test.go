package main

import (
	"os"
	"path/filepath"
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
	if pts := treePoints(trees(m), ranks); pts[0] != 16 || pts[1] != 32 || pts[2] != 3 {
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
		map[string]any{"id": "fixed", "name": "Feuer fest", "talentsString": fireTalents, "rotation": "deepFire"},
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
	if str(fixed, "rotation") != "deepFire" || len(array(fixed, "rotations")) != 1 {
		t.Fatalf("fixed rotation row %v", fixed)
	}
	if str(got.(map[string]any), "best") == "" || str(got.(map[string]any), "best") == "bad" {
		t.Fatalf("best %v", got.(map[string]any)["best"])
	}
}

func TestCompareBuildsScreenOnlyMeasuresOnce(t *testing.T) {
	count := func(screenOnly bool) (int, float64) {
		s, m := fakeService(t)
		snap := mageSnapshot(t, m, fireTalents)
		payload := map[string]any{"builds": []any{
			map[string]any{"id": "a", "talentsString": fireTalents, "rotation": "deepFire"},
			map[string]any{"id": "b", "talentsString": legalBuild(t, m, 0), "rotation": "deepFire"},
		}}
		if screenOnly {
			payload["screenOnly"] = true
		}
		got, e := s.Run(t.Context(), Job{Kind: "talent-compare", State: map[string]any{"sim": snap}, Payload: payload})
		if e != nil {
			t.Fatal(e)
		}
		files, _ := os.ReadDir(filepath.Join(s.Config.Data, "Sims"))
		return len(files), num(array(got.(map[string]any), "builds")[0].(map[string]any), "dps")
	}
	quick, dpsQuick := count(true)
	full, dpsFull := count(false)
	if quick != 2 || full != 4 {
		t.Fatalf("engine runs: quick %d (want 2), full %d (want 4)", quick, full)
	}
	if dpsQuick < 1000 || dpsFull < 1000 {
		t.Fatalf("dps %v %v", dpsQuick, dpsFull)
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
			map[string]any{"name": "Short", "talentsString": "0502-555"},
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
	layout := array(r, "layout")
	if len(layout) != 18+17+18 {
		t.Fatalf("the current mage tree has 53 talents, layout has %d", len(layout))
	}
	prereqs := 0
	for _, raw := range layout {
		n := raw.(map[string]any)
		if n["preRow"] != nil {
			prereqs++
			if n["preCol"] == nil || num(n, "preRow") >= num(n, "row") && num(n, "preCol") == num(n, "col") {
				t.Fatalf("prerequisite must lie above: %v", n)
			}
		}
	}
	if prereqs != 7 {
		t.Fatalf("seven mage talents have a prerequisite, got %d", prereqs)
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
	// the compact form [treeIndex,rowIdx,colIdx,rank] gives the same build
	var compact []any
	for _, raw := range entries {
		e := raw.(map[string]any)
		compact = append(compact, []any{e["treeIndex"], e["rowIdx"], e["colIdx"], e["rank"]})
	}
	if req, e = s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talents": compact}}); e != nil || str(player(req), "talentsString") != fireTalents {
		t.Fatalf("compact entries: %v", e)
	}
	// an entry for a place that does not exist is refused, not guessed
	bad := []any{map[string]any{"treeIndex": float64(1), "rowIdx": float64(6), "colIdx": float64(3), "rank": float64(1)}}
	if _, e = s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"talents": bad}}); e == nil {
		t.Fatal("an unknown place was accepted")
	}
}

func TestRememberedRotationOfAnotherSpecFallsBackToTheDefault(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	state := map[string]any{"sim": snap}
	if _, e := s.liveRequest(Job{State: state, Payload: map[string]any{"rotation": "does-not-exist"}}); e == nil {
		t.Fatal("an explicit unknown rotation must be an error")
	}
	req, e := s.liveRequest(Job{State: state, Payload: map[string]any{"rotation": "does-not-exist", "rotationSoft": true}})
	if e != nil {
		t.Fatal(e)
	}
	if len(array(child(player(req), "rotation"), "priorityList")) == 0 {
		t.Fatal("no rotation chosen")
	}
	want := rotationNames(m, "mage")[0]
	if child(child(child(child(m, "specs"), "mage"), "rotations"), "default") == nil {
		pl := child(child(child(child(m, "specs"), "mage"), "rotations"), want)
		if len(array(child(player(req), "rotation"), "priorityList")) != len(array(pl, "priorityList")) {
			t.Fatal("not the alphabetically first rotation")
		}
	}
}

func TestBuildDetailBreakdownAndCurve(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	got, e := s.Run(t.Context(), Job{Kind: "build-detail", State: map[string]any{"sim": snap}, Payload: map[string]any{}})
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	if num(r, "dps") < 1000 || str(r, "rotation") == "" || len(array(r, "rotations")) == 0 || len(array(r, "priority")) == 0 {
		t.Fatalf("basic fields missing: %v", r)
	}
	shares := array(r, "breakdown")
	if len(shares) != 6 {
		t.Fatalf("five rows and the rest: %d", len(shares))
	}
	first := shares[0].(map[string]any)
	if num(first, "spellId") != 133 || num(first, "pct") < 58 || num(first, "pct") > 60 {
		t.Fatalf("biggest share %v", first)
	}
	if label := shares[2].(map[string]any); str(label, "label") != "Ignite" || label["spellId"] != nil {
		t.Fatalf("an action without a spell id keeps its name: %v", label)
	}
	if rest := shares[5].(map[string]any); rest["rest"] != true || num(rest, "pct") <= 0 {
		t.Fatalf("rest row %v", rest)
	}
	sum := 0.0
	for _, raw := range shares {
		sum += num(raw.(map[string]any), "pct")
	}
	if sum < 99.9 || sum > 100.1 {
		t.Fatalf("shares add up to %v", sum)
	}
	curve := array(r, "curve")
	if len(curve) != len(curveSeconds) {
		t.Fatalf("curve points %d", len(curve))
	}
	for i := 1; i < len(curve); i++ {
		a, b := curve[i-1].(map[string]any), curve[i].(map[string]any)
		if num(b, "t") <= num(a, "t") || num(b, "dps") <= num(a, "dps") {
			t.Fatalf("the curve must rise with the fight length: %v then %v", a, b)
		}
		if num(b, "mana") >= num(a, "mana") {
			t.Fatalf("mana is spent over time: %v then %v", a, b)
		}
	}
	if num(curve[0].(map[string]any), "mana") != -5*15 {
		t.Fatalf("mana change of the first point %v", curve[0])
	}
	// without the curve, and with a build of its own
	got, e = s.Run(t.Context(), Job{Kind: "build-detail", State: map[string]any{"sim": snap}, Payload: map[string]any{"curve": false, "build": map[string]any{"talents": []any{[]any{1.0, 0.0, 1.0, 5.0}}}}})
	if e != nil {
		t.Fatal(e)
	}
	if got.(map[string]any)["curve"] != nil {
		t.Fatal("curve was asked to be skipped")
	}
	if _, e = s.Run(t.Context(), Job{Kind: "build-detail", State: map[string]any{"sim": snap}, Payload: map[string]any{"build": map[string]any{"talentsString": "99"}}}); e == nil {
		t.Fatal("a broken build must be an error")
	}
}

func TestDamageSharesAndManaChange(t *testing.T) {
	if got := damageShares(nil, 5); len(got) != 0 {
		t.Fatal("no actions, no shares")
	}
	rows := damageShares([]any{
		map[string]any{"id": map[string]any{"spellId": 1.0}, "damage": 50.0, "casts": 2.0},
		map[string]any{"id": map[string]any{"spellId": 1.0}, "damage": 50.0, "casts": 3.0}, // pet or second target of the same spell
		map[string]any{"id": map[string]any{"spellId": 2.0}, "damage": 0.0},
	}, 5)
	if len(rows) != 1 || num(rows[0].(map[string]any), "pct") != 100 || num(rows[0].(map[string]any), "casts") != 5 {
		t.Fatalf("same spell is one row: %v", rows)
	}
	res := map[string]any{"raidMetrics": map[string]any{"parties": []any{map[string]any{"players": []any{map[string]any{"resources": []any{
		map[string]any{"type": 1.0, "actualGain": -30.0}, map[string]any{"type": "ResourceTypeMana", "gain": 10.0}, map[string]any{"type": "ResourceTypeRage", "actualGain": 99.0},
	}}}}}}}
	if net, ok := manaChange(res); !ok || net != -20 {
		t.Fatalf("mana change %v %v", net, ok)
	}
	if _, ok := manaChange(map[string]any{}); ok {
		t.Fatal("no resources, no mana data")
	}
}

func TestTunedRotationNamesAndLookup(t *testing.T) {
	rotations := map[string]any{"fire": map[string]any{"name": "fire", "priorityList": []any{"a", "b", "c", "d"}}}
	name := tunedRotationName("fire", []int{2, 0, 1, 3})
	if name != "eigen:fire:2,0,1,3" {
		t.Fatal(name)
	}
	base, order, ok := parseTunedName(name)
	if !ok || base != "fire" || len(order) != 4 || order[0] != 2 {
		t.Fatalf("%v %v %v", base, order, ok)
	}
	got, ok := lookupRotation(rotations, name)
	if !ok {
		t.Fatal("tuned rotation not found")
	}
	rows := array(got.(map[string]any), "priorityList")
	if rows[0] != "c" || rows[1] != "a" || len(rows) != 4 {
		t.Fatalf("rows %v", rows)
	}
	if _, ok := lookupRotation(rotations, "fire"); !ok {
		t.Fatal("plain name")
	}
	for _, bad := range []string{"eigen:fire:0", "eigen:fire:0,1,2", "eigen:fire", "eigen:fire:", "eigen:fire:0,0,1,2", "eigen:fire:0,1,2,9", "eigen:nope:0,1", "eigen:fire:a,b", "fire:0,1"} {
		if _, ok := lookupRotation(rotations, bad); ok {
			t.Fatalf("%q must not resolve", bad)
		}
	}
	if len(array(rotations["fire"].(map[string]any), "priorityList")) != 4 || array(rotations["fire"].(map[string]any), "priorityList")[0] != "a" {
		t.Fatal("the original rotation was changed")
	}
	moves := tuneNeighbours([]int{0, 1, 2, 3, 4}, 1)
	if len(moves) != 4 {
		t.Fatalf("one-place moves of five rows: %d (want the 4 adjacent swaps)", len(moves))
	}
}

func TestRotaTuneFindsABetterOrder(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	names := rotationNames(m, "mage")
	var base string
	for _, n := range names {
		if rows := array(child(child(child(child(m, "specs"), "mage"), "rotations"), n), "priorityList"); len(rows) >= 4 {
			base = n
			break
		}
	}
	if base == "" {
		t.Skip("no rotation with four rows in the manifest")
	}
	step := func(order []any) map[string]any {
		payload := map[string]any{"rotation": base, "build": map[string]any{"talentsString": fireTalents}, "iterations": 100.0}
		if order != nil {
			payload["order"] = order
		}
		got, e := s.Run(t.Context(), Job{Kind: "rota-tune", State: map[string]any{"sim": snap}, Payload: payload})
		if e != nil {
			t.Fatal(e)
		}
		return got.(map[string]any)
	}
	first := step(nil)
	if num(first, "rows") < 4 || num(first, "dps") < 1000 || num(first, "tried") < 3 {
		t.Fatalf("first step %v", first)
	}
	// the stand-in pays for ascending spell order; follow the steps until nothing better is found
	cur, gained := first, false
	for i := 0; i < 40 && cur["bestOrder"] != nil; i++ {
		gained = true
		if num(cur, "bestDps") <= num(cur, "dps") {
			t.Fatalf("the best neighbour is not better: %v", cur)
		}
		cur = step(cur["bestOrder"].([]any))
	}
	t.Logf("tuned: improved=%v rows=%v tried=%v", gained, num(first, "rows"), num(first, "tried"))
	// whatever the order, the tuned name works as a rotation everywhere
	order := make([]int, 0)
	for _, v := range array(cur, "order") {
		order = append(order, int(v.(float64)))
	}
	name := tunedRotationName(base, order)
	got, e := s.Run(t.Context(), Job{Kind: "talent-compare", State: map[string]any{"sim": snap}, Payload: map[string]any{"builds": []any{
		map[string]any{"id": "tuned", "talentsString": fireTalents, "rotation": name}}}})
	if e != nil {
		t.Fatal(e)
	}
	row := array(got.(map[string]any), "builds")[0].(map[string]any)
	if str(row, "rotation") != name || num(row, "dps") < 1000 {
		t.Fatalf("tuned rotation in a comparison: %v", row)
	}
	if _, e := s.Run(t.Context(), Job{Kind: "rota-tune", State: map[string]any{"sim": snap}, Payload: map[string]any{"rotation": base, "order": []any{0.0, 0.0}}}); e == nil {
		t.Fatal("an order that does not fit must be refused")
	}
	if _, e := s.Run(t.Context(), Job{Kind: "rota-tune", State: map[string]any{"sim": snap}, Payload: map[string]any{}}); e == nil {
		t.Fatal("a missing rotation must be refused")
	}
}

func TestEmptyTalentOverrideAndInvalidRotationOrder(t *testing.T) {
	s, m := fakeService(t)
	snap := mageSnapshot(t, m, fireTalents)
	for _, payload := range []map[string]any{{"talents": []any{}}, {"talents": map[string]any{}}, {"talentsString": ""}} {
		req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}, Payload: payload})
		if e != nil {
			t.Fatal(e)
		}
		if text := str(player(req), "talentsString"); strings.Trim(text, "-0") != "" {
			t.Fatalf("empty build reused live talents: %s", text)
		}
	}
	for _, order := range [][]any{{"bad"}, {0.5}, {0.0}} {
		_, e := s.rotaTune(t.Context(), Job{State: map[string]any{"sim": snap}, Payload: map[string]any{"rotation": "deepFire", "order": order}})
		if e == nil {
			t.Fatalf("invalid order accepted: %v", order)
		}
	}
}
