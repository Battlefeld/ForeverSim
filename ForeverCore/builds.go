package main

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
)

// Alternative characters: "what if I had these talents, this rotation, this gear". Every simulation job may carry
// payload.talentsString, payload.spec, payload.rotation and payload.gear; liveRequest applies them to the live
// character and changes nothing else of its state (class options, buffs and spellbook stay the player's own).

// treePoints counts the points spent in each tree.
func treePoints(trees []any, ranks map[string]int) []int {
	points := make([]int, len(trees))
	for i, raw := range trees {
		for _, n := range array(raw.(map[string]any), "talents") {
			points[i] += ranks[str(n.(map[string]any), "fieldName")]
		}
	}
	return points
}

// largestTreeOf returns the index of the tree with the most points (the first one on a tie) and its points.
func largestTreeOf(points []int) (tree, largest int) {
	for i, p := range points {
		if p > largest {
			largest, tree = p, i
		}
	}
	return tree, largest
}

// decodeTalentString turns "05002252000003-23550000130135031-" into ranks by engine field name. Per tree one digit per
// talent in the engine's own order, trees joined by "-", trailing zeros may be missing.
func decodeTalentString(trees []any, text string) (map[string]int, error) {
	parts := strings.Split(strings.TrimSpace(text), "-")
	if len(parts) > len(trees) {
		return nil, fmt.Errorf("Talenttext hat zu viele Baeume")
	}
	ranks := map[string]int{}
	for ti, raw := range trees {
		talents := array(raw.(map[string]any), "talents")
		digits := ""
		if ti < len(parts) {
			digits = parts[ti]
		}
		if len(digits) > len(talents) {
			return nil, fmt.Errorf("Talenttext passt nicht zu Baum %d (%d Zeichen, %d Talente)", ti+1, len(digits), len(talents))
		}
		for i, ch := range digits {
			if ch < '0' || ch > '9' {
				return nil, fmt.Errorf("Talenttext enthaelt ein ungueltiges Zeichen")
			}
			rank := int(ch - '0')
			if rank == 0 {
				continue
			}
			node := talents[i].(map[string]any)
			if rank > int(num(node, "maxPoints")) {
				return nil, fmt.Errorf("Talentrang passt nicht: %s", str(node, "fieldName"))
			}
			ranks[str(node, "fieldName")] = rank
		}
	}
	return ranks, nil
}

// checkedTalentString decodes a talent text and proves it is a legal build (tier points, prerequisites, budget).
// It returns the ranks and the canonical text.
func checkedTalentString(trees []any, text string, budget int) (map[string]int, string, error) {
	ranks, e := decodeTalentString(trees, text)
	if e != nil {
		return nil, "", e
	}
	nodes, e := talentNodes(trees)
	if e != nil {
		return nil, "", e
	}
	encoded, ranks, e := encodeTalentEntries(trees, talentEntries(nodes, ranks), true, budget)
	if e != nil {
		return nil, "", e
	}
	return ranks, encoded, nil
}

// talentSpellIDs lists the spells that the given talent ranks grant or change.
func talentSpellIDs(trees []any, ranks map[string]int) map[int]bool {
	ids := map[int]bool{}
	for _, raw := range trees {
		for _, entry := range array(raw.(map[string]any), "talents") {
			node := entry.(map[string]any)
			if ranks[str(node, "fieldName")] < 1 {
				continue
			}
			if id := int(num(node, "spellId")); id > 0 {
				ids[id] = true
			}
			for _, rawID := range array(node, "spellIds") {
				if id, ok := rawID.(float64); ok && id > 0 {
					ids[int(id)] = true
				}
			}
		}
	}
	return ids
}

// swapTalentSpells moves the live spellbook from one talent build to another: spells that only the old build
// granted go, spells the new build grants arrive. Everything else the player knows stays.
func swapTalentSpells(req map[string]any, trees []any, from, to map[string]int) {
	if req[engineSpellsKey] == nil {
		return
	}
	known := map[int]bool{}
	for _, raw := range array(req, engineSpellsKey) {
		if id, ok := raw.(float64); ok {
			known[int(id)] = true
		}
	}
	old, next := talentSpellIDs(trees, from), talentSpellIDs(trees, to)
	for id := range old {
		if !next[id] {
			delete(known, id)
		}
	}
	for id := range next {
		known[id] = true
	}
	list := make([]int, 0, len(known))
	for id := range known {
		list = append(list, id)
	}
	sort.Ints(list)
	out := make([]any, 0, len(list))
	for _, id := range list {
		out = append(out, float64(id))
	}
	req[engineSpellsKey] = out
}

// gearItems turns an engine equipment spec ({"items":[{id,enchant,gems},...]}) into the 17 slots of a player.
func gearItems(gear map[string]any) ([]any, error) {
	raw := array(gear, "items")
	if len(raw) > 17 {
		return nil, fmt.Errorf("Ausruestung hat mehr als 17 Plaetze")
	}
	items := make([]any, 17)
	for i := range items {
		items[i] = map[string]any{}
		if i < len(raw) {
			it, ok := raw[i].(map[string]any)
			if !ok {
				return nil, fmt.Errorf("Ausruestungseintrag %d ungueltig", i+1)
			}
			if len(it) > 0 {
				items[i] = cloneMap(it)
			}
		}
	}
	return items, nil
}

// compareBuilds answers the "talent-compare" job: every build of payload.builds is simulated with the live
// character's gear and options and with its best rotation. A build is {id, name, talentsString, spec?, rotation?,
// gear?, gearPreset?}. Without a rotation every rotation of the build's engine spec is tried at a low iteration
// count and the best one is measured again at the full count, so the numbers of different builds are comparable
// (payload.screenOnly keeps the quick measurement: used by the search for the best talents, which tries many builds).
func (s *SimService) compareBuilds(ctx context.Context, j Job) (any, error) {
	builds := array(j.Payload, "builds")
	if len(builds) < 1 || len(builds) > 12 {
		return nil, fmt.Errorf("1 bis 12 Skillungen je Auftrag")
	}
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	class := classKeyOf(child(j.State, "sim"))
	screen, full := int(num(j.Payload, "screenIterations")), int(num(j.Payload, "iterations"))
	if screen < 50 || screen > 5000 {
		screen = 300
	}
	if full < 50 || full > 20000 {
		full = 1000
	}
	screenOnly := j.Payload["screenOnly"] == true
	type prepared struct {
		req   map[string]any
		spec  string
		names []string
		dps   map[string]float64
		errs  map[string]error
		best  string
	}
	rows := make([]map[string]any, len(builds))
	prep := make([]*prepared, len(builds))
	for i, raw := range builds {
		b, ok := raw.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("Skillung %d ungueltig", i+1)
		}
		rows[i] = map[string]any{"id": str(b, "id"), "name": str(b, "name")}
		payload, e := buildPayload(j, manifest, class, b)
		if e != nil {
			rows[i]["error"] = e.Error()
			continue
		}
		req, e := s.liveRequest(Job{Schema: j.Schema, Kind: "sim", State: j.State, Payload: payload})
		if e != nil {
			rows[i]["error"] = e.Error()
			continue
		}
		p := &prepared{req: req, spec: str(req, "foreverCoreSpec"), dps: map[string]float64{}, errs: map[string]error{}}
		all := rotationNames(manifest, p.spec)
		switch want := str(b, "rotation"); {
		case want != "":
			p.names = []string{want}
		case str(j.Payload, "rotations") == "default":
			p.names = []string{""}
		default:
			p.names = all
		}
		prep[i] = p
	}
	type task struct {
		p    *prepared
		name string
		req  map[string]any
		iter int
	}
	rotationReq := func(p *prepared, name string, iterations int) (map[string]any, error) {
		r := cloneMap(p.req)
		child(r, "simOptions")["iterations"] = float64(iterations)
		if name != "" {
			rotations := child(child(child(manifest, "specs"), p.spec), "rotations")
			chosen, found := rotations[name]
			if !found {
				return nil, fmt.Errorf("Rotation fehlt: %s", name)
			}
			pl, _ := playerOf(r)
			pl["rotation"] = chosen
		}
		return r, nil
	}
	run := func(tasks []task, store func(t task, dps float64, e error)) {
		sem := make(chan struct{}, variantWorkers(len(tasks)))
		var wg sync.WaitGroup
		var mu sync.Mutex
		for _, t := range tasks {
			sem <- struct{}{}
			wg.Add(1)
			go func(t task) {
				defer wg.Done()
				defer func() { <-sem }()
				var dps float64
				var e error
				func() {
					defer func() {
						if p := recover(); p != nil {
							e = fmt.Errorf("interner Fehler: %v", p)
						}
					}()
					var got map[string]any
					if got, e = s.once(ctx, t.req); e == nil {
						dps = simDPS(got)
					}
				}()
				mu.Lock()
				store(t, dps, e)
				mu.Unlock()
			}(t)
		}
		wg.Wait()
	}
	var tasks []task
	for _, p := range prep {
		if p == nil {
			continue
		}
		for _, name := range p.names {
			r, e := rotationReq(p, name, screen)
			if e != nil {
				p.errs[name] = e
				continue
			}
			tasks = append(tasks, task{p: p, name: name, req: r, iter: screen})
		}
	}
	run(tasks, func(t task, dps float64, e error) {
		if e != nil {
			t.p.errs[t.name] = e
			return
		}
		t.p.dps[t.name] = dps
	})
	var finals []task
	for _, p := range prep {
		if p == nil {
			continue
		}
		for _, name := range p.names {
			if p.dps[name] > 0 && (p.best == "" && p.dps[name] > 0 || p.dps[name] > p.dps[p.best]) {
				p.best = name
			}
		}
		if len(p.dps) == 0 {
			continue
		}
		iter := full
		if screenOnly {
			iter = screen
		}
		r, _ := rotationReq(p, p.best, iter)
		finals = append(finals, task{p: p, name: p.best, req: r, iter: iter})
	}
	final := map[*prepared]float64{}
	finalReq := map[*prepared]map[string]any{}
	if screenOnly {
		// A search that tries many builds only needs the quick measurement of each.
		for _, t := range finals {
			final[t.p] = t.p.dps[t.name]
			finalReq[t.p] = t.req
		}
	} else {
		run(finals, func(t task, dps float64, e error) {
			if e != nil {
				t.p.errs[t.name] = e
				return
			}
			final[t.p] = dps
			finalReq[t.p] = t.req
		})
	}
	var resultReq map[string]any
	for i, p := range prep {
		if p == nil {
			continue
		}
		row := rows[i]
		row["spec"] = p.spec
		if dps, ok := final[p]; ok {
			row["dps"], row["rotation"] = dps, p.best
		} else {
			for name, e := range p.errs {
				row["error"] = fmt.Sprintf("%s: %v", name, e)
				break
			}
			if row["error"] == nil {
				row["error"] = "Keine Rotation erzeugt Schaden"
			}
			continue
		}
		list := make([]any, 0, len(p.names))
		for _, name := range p.names {
			if d, ok := p.dps[name]; ok {
				list = append(list, map[string]any{"name": name, "dps": d})
			}
		}
		sort.SliceStable(list, func(a, b int) bool {
			return num(list[a].(map[string]any), "dps") > num(list[b].(map[string]any), "dps")
		})
		row["rotations"] = list
		trees := array(child(child(manifest, "classes"), class), "trees")
		if ranks, e := decodeTalentString(trees, str(player(finalReq[p]), "talentsString")); e == nil {
			points := treePoints(trees, ranks)
			pts := make([]any, len(points))
			for k, v := range points {
				pts[k] = float64(v)
			}
			row["points"] = pts
		}
		if j.Payload["priority"] == true {
			pl := player(finalReq[p])
			row["priority"] = s.rotationPriorityFor(finalReq[p], child(pl, "rotation"))
		}
		resultReq = finalReq[p]
	}
	out := []any{}
	best, bestDPS := "", 0.0
	for _, row := range rows {
		out = append(out, row)
		if d := num(row, "dps"); d > bestDPS {
			best, bestDPS = str(row, "id"), d
		}
	}
	if resultReq == nil {
		return nil, fmt.Errorf("Keine Skillung berechenbar: %v", rows[0]["error"])
	}
	return withResultContext(map[string]any{"engine": "MythicSim Go", "engineRevision": s.Config.EngineRevision, "builds": out, "best": best,
		"iterations": float64(full), "comparison": "Gleiche Ausruestung, gleiches Ziel, gleicher Seed; jede Skillung mit ihrer besten Rotation"}, resultReq), nil
}

func player(req map[string]any) map[string]any {
	p, _ := playerOf(req)
	return p
}

// buildPayload is the payload of the plain simulation job for one build of a comparison: the build's own talents, spec
// and gear on top of the job's target settings.
func buildPayload(j Job, manifest map[string]any, class string, b map[string]any) (map[string]any, error) {
	payload := map[string]any{}
	for _, key := range []string{"talentsString", "talents", "spec", "gear"} {
		if v, ok := b[key]; ok {
			payload[key] = v
		}
	}
	for _, key := range []string{"targetLevel", "targetArmor", "classOptions"} {
		if v, ok := j.Payload[key]; ok {
			payload[key] = v
		}
	}
	if name := str(b, "gearPreset"); name != "" {
		gear, e := presetGear(manifest, class, name)
		if e != nil {
			return nil, e
		}
		payload["gear"] = gear
	}
	return payload, nil
}
