package main

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
)

// The "build-detail" job: one build simulated in full. Besides its DPS it tells where the damage comes from (the share of
// every action) and how the fight develops: the engine reports averages over the whole fight, so the growth over time
// comes from the same build simulated for shorter fights.

// curveSeconds are the fight lengths of the DPS-over-time curve.
var curveSeconds = []int{15, 30, 45, 60, 90, 120, 180}

// actionSpellID reads a spell id out of an engine action id ({"spellId":N}); 0 for anything else.
func actionSpellID(id any) int {
	if m, ok := id.(map[string]any); ok {
		return int(num(m, "spellId"))
	}
	return 0
}

// actionLabel is the name the engine gives an action that has no spell id (Ignite and the like).
func actionLabel(id any) string {
	if m, ok := id.(map[string]any); ok {
		if s := str(m, "otherId"); s != "" {
			return strings.TrimPrefix(s, "OtherAction")
		}
	}
	return ""
}

// damageShares groups the engine's actions by spell and returns the biggest `top` with their share of the total
// damage; everything else is summed into one row without a spell id.
func damageShares(actions []any, top int) []any {
	type row struct {
		spell  int
		label  string
		damage float64
		casts  float64
	}
	bySpell := map[string]*row{}
	order := []string{}
	total := 0.0
	for _, raw := range actions {
		a, ok := raw.(map[string]any)
		if !ok || num(a, "damage") <= 0 {
			continue
		}
		spell, label := actionSpellID(a["id"]), actionLabel(a["id"])
		key := fmt.Sprintf("%d/%s", spell, label)
		r := bySpell[key]
		if r == nil {
			r = &row{spell: spell, label: label}
			bySpell[key] = r
			order = append(order, key)
		}
		r.damage += num(a, "damage")
		r.casts += num(a, "casts")
		total += num(a, "damage")
	}
	if total <= 0 {
		return []any{}
	}
	rows := make([]*row, 0, len(order))
	for _, k := range order {
		rows = append(rows, bySpell[k])
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].damage > rows[j].damage })
	out := []any{}
	rest := 0.0
	for i, r := range rows {
		if i >= top {
			rest += r.damage
			continue
		}
		e := map[string]any{"pct": 100 * r.damage / total, "damage": r.damage, "casts": r.casts}
		if r.spell > 0 {
			e["spellId"] = float64(r.spell)
		}
		if r.label != "" {
			e["label"] = r.label
		}
		out = append(out, e)
	}
	if rest > 0 {
		out = append(out, map[string]any{"pct": 100 * rest / total, "damage": rest, "rest": true})
	}
	return out
}

// manaChange is the net mana the player gained (negative: spent) per fight, summed over the engine's mana resources.
func manaChange(result map[string]any, iterations ...float64) (float64, bool) {
	net, found := 0.0, false
	for _, party := range array(child(result, "raidMetrics"), "parties") {
		for _, p := range array(party.(map[string]any), "players") {
			for _, raw := range array(p.(map[string]any), "resources") {
				r, ok := raw.(map[string]any)
				if !ok {
					continue
				}
				kind := fmt.Sprint(r["type"])
				if kind != "1" && !strings.Contains(strings.ToLower(kind), "mana") {
					continue
				}
				v := num(r, "actualGain")
				if r["actualGain"] == nil {
					v = num(r, "gain")
				}
				net += v
				found = true
			}
		}
	}
	if len(iterations) > 0 && iterations[0] > 0 {
		net /= iterations[0]
	}
	return net, found
}

func (s *SimService) buildDetail(ctx context.Context, j Job) (any, error) {
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	class := classKeyOf(child(j.State, "sim"))
	b := child(j.Payload, "build")
	if b == nil {
		b = map[string]any{}
	}
	common := map[string]any{}
	for _, key := range []string{"targetLevel", "targetArmor", "classOptions"} {
		if v, ok := j.Payload[key]; ok {
			common[key] = v
		}
	}
	// the best rotation of this build (or the given one), with its priority list
	cmpPayload := map[string]any{"builds": []any{b}, "priority": true}
	for k, v := range common {
		cmpPayload[k] = v
	}
	got, e := s.compareBuilds(ctx, Job{Schema: j.Schema, Kind: "talent-compare", State: j.State, Payload: cmpPayload})
	if e != nil {
		return nil, e
	}
	row, _ := array(got.(map[string]any), "builds")[0].(map[string]any)
	if row == nil {
		return nil, fmt.Errorf("Keine Skillung zurueckgegeben")
	}
	if row["dps"] == nil {
		return nil, fmt.Errorf("%v", row["error"])
	}
	payload, e := buildPayload(j, manifest, class, b)
	if e != nil {
		return nil, e
	}
	payload["rotation"] = row["rotation"]
	req, e := s.liveRequest(Job{Schema: j.Schema, Kind: "sim", State: j.State, Payload: payload})
	if e != nil {
		return nil, e
	}
	base, e := s.once(ctx, req)
	if e != nil {
		return nil, e
	}
	res := map[string]any{"engine": "Engine Go", "engineRevision": s.Config.EngineRevision, "dps": simDPS(base), "rotation": row["rotation"],
		"rotations": row["rotations"], "priority": row["priority"], "spec": row["spec"], "duration": num(child(req, "encounter"), "duration")}
	summary := summarizeAnalysis(base, req)
	res["breakdown"] = damageShares(array(summary, "actions"), 5)
	if j.Payload["curve"] == false {
		return withResultContext(res, req), nil
	}
	// DPS (and net mana) after t seconds: the same build in a fight that ends at t
	type point struct {
		t    int
		dps  float64
		mana float64
		has  bool
		err  error
	}
	points := make([]point, len(curveSeconds))
	sem := make(chan struct{}, variantWorkers(len(curveSeconds)))
	var wg sync.WaitGroup
	for i, t := range curveSeconds {
		sem <- struct{}{}
		wg.Add(1)
		go func(i, t int) {
			defer wg.Done()
			defer func() { <-sem }()
			defer func() {
				if p := recover(); p != nil {
					points[i].err = fmt.Errorf("%v", p)
				}
			}()
			r := cloneMap(req)
			child(r, "simOptions")["iterations"] = float64(300)
			child(r, "encounter")["duration"] = float64(t)
			got, e := s.once(ctx, r)
			if e != nil {
				points[i].err = e
				return
			}
			points[i] = point{t: t, dps: simDPS(got)}
			points[i].mana, points[i].has = manaChange(got, num(child(r, "simOptions"), "iterations"))
		}(i, t)
	}
	wg.Wait()
	curve := []any{}
	for _, p := range points {
		if p.err != nil || p.dps <= 0 {
			continue
		}
		e := map[string]any{"t": float64(p.t), "dps": p.dps}
		if p.has {
			e["mana"] = p.mana
		}
		curve = append(curve, e)
	}
	res["curve"] = curve
	return withResultContext(res, req), nil
}
