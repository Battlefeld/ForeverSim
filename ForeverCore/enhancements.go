package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"sync"
	"time"
)

//go:embed enhancements-data.json
var enhancementData []byte

var enhancementSlots = []string{"head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger1", "finger2", "trinket1", "trinket2", "mainhand", "offhand", "ranged"}
var enhancementTypes = []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 11, 12, 12, 13, 13, 14}

func enhancementCatalog(manifest map[string]any) (map[string]any, error) {
	var c map[string]any
	if e := json.Unmarshal(enhancementData, &c); e != nil {
		return nil, e
	}
	if str(c, "upstreamRevision") != str(manifest, "upstreamRevision") {
		return nil, fmt.Errorf("VZ-/Food-Daten gehoeren zu einer anderen Engine-Version; Katalog aktualisieren")
	}
	return c, nil
}

// Eligibility follows MythicSim's item/enchant geometry. Recipe skill is a crafting
// requirement, not a recipient level. Unknown recipes/effects never become zero-DPS entries.
func enhancementFits(e, item map[string]any, slot int) bool {
	if slot < 0 || slot >= len(enhancementSlots) || num(item, "id") <= 0 {
		return false
	}
	typ := enhancementTypes[slot]
	matches := int(num(e, "type")) == typ
	for _, v := range array(e, "extraTypes") {
		if v == float64(typ) {
			matches = true
		}
	}
	if !matches {
		return false
	}
	if typ != 13 && typ != 14 {
		return true
	}
	wt, ht, rt := int(num(item, "weaponType")), int(num(item, "handType")), int(num(item, "rangedWeaponType"))
	et := int(num(e, "enchantType"))
	if typ == 14 {
		return rt == 1 || rt == 2 || rt == 3
	}
	if wt == 0 {
		return false
	}
	if et == 1 && ht != 4 || et == 4 && wt != 8 || et == 2 && wt != 7 {
		return false
	}
	if (et == 5) != (wt == 5) {
		return false
	}
	return wt != 7 || et == 2
}

func addEnhancementFood(req, entry, manifest map[string]any) error {
	p, e := playerOf(req)
	if e != nil {
		return e
	}
	count := int(num(manifest, "statCount"))
	if count < 1 {
		return fmt.Errorf("Stat-Schema fehlt")
	}
	b := child(p, "bonusStats")
	if b == nil {
		b = map[string]any{}
		p["bonusStats"] = b
	}
	values := array(b, "stats")
	for len(values) < count {
		values = append(values, float64(0))
	}
	for key, raw := range child(entry, "stats") {
		index, ok := child(manifest, "stats")[key].(float64)
		amount, valid := raw.(float64)
		if !ok || !valid || index < 0 || int(index) >= count || amount < 0 || amount > 10000 {
			return fmt.Errorf("Food-Stat ungueltig: %s", key)
		}
		values[int(index)] = values[int(index)].(float64) + amount
	}
	b["stats"] = values
	return nil
}

func enhancementGeometry(c, p, item map[string]any) map[string]any {
	out := cloneMap(item)
	id := int(num(item, "id"))
	geometry := child(child(c, "itemGeometry"), strconv.Itoa(id))
	for _, raw := range array(child(p, "database"), "items") {
		row, _ := raw.(map[string]any)
		if int(num(row, "id")) == id {
			geometry = row
			break
		}
	}
	for _, key := range []string{"type", "weaponType", "handType", "rangedWeaponType"} {
		if geometry[key] != nil {
			out[key] = geometry[key]
		}
	}
	return out
}

// Every candidate changes exactly one slot, or one mutually exclusive food. The
// baseline keeps all current enchants; gains must never be summed as a combined result.
func (s *SimService) compareEnhancements(ctx context.Context, j Job) (any, error) {
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	catalog, e := enhancementCatalog(manifest)
	if e != nil {
		return nil, e
	}
	req, e := s.liveRequest(j)
	if e != nil {
		return nil, e
	}
	p, _ := playerOf(req)
	items := array(child(p, "equipment"), "items")
	current := child(child(j.State, "sim"), "enhancementEnchants")
	if current == nil {
		return nil, fmt.Errorf("Aktuelle Verzauberungen nicht gelesen; Addon aktualisieren und neu anfragen")
	}
	// Keep the interactive calculation bounded, using the same seed and iteration count for all candidates.
	iter := int(num(j.Payload, "iterations"))
	if iter < 50 || iter > 2000 {
		iter = 500
	}
	child(req, "simOptions")["iterations"] = float64(iter)
	var baselineRows []map[string]any
	for slot, raw := range items {
		item := raw.(map[string]any)
		key := enhancementSlots[slot]
		if num(item, "id") == 0 {
			continue
		}
		id, exists := current[key].(float64)
		if !exists || id < 0 || id != float64(int(id)) {
			return nil, fmt.Errorf("Verzauberung fuer %s nicht lesbar", key)
		}
		name := "Keine Verzauberung"
		if id > 0 {
			name = str(child(catalog, "engineEnchants"), strconv.Itoa(int(id)))
			if name == "" {
				return nil, fmt.Errorf("Aktuelle VZ %d (%s) noch nicht in der Engine; kein verlaesslicher Vergleich", int(id), key)
			}
		}
		item["enchant"] = id
		if enhancementTypes[slot] != 12 {
			baselineRows = append(baselineRows, map[string]any{"slot": key, "slotIndex": float64(slot), "name": name, "effectId": id, "kind": "enchant", "current": true})
		}
	}
	base, e := s.once(ctx, req)
	if e != nil {
		return nil, e
	}
	before := simDPS(base)
	if before <= 0 {
		return nil, fmt.Errorf("Referenzrotation erzeugt keinen Schaden")
	}
	type candidate struct {
		entry map[string]any
		slot  int
	}
	var candidates []candidate
	skipped := map[string]int{}
	level := int(num(child(j.State, "sim"), "level"))
	for _, raw := range array(catalog, "entries") {
		entry := raw.(map[string]any)
		if entry["supported"] != true {
			skipped["unmodeled"]++
			continue
		}
		if str(entry, "kind") == "food" {
			if int(num(entry, "minLevel")) > level {
				skipped["level"]++
				continue
			}
			if num(child(req, "encounter"), "duration") > num(entry, "duration") {
				skipped["duration"]++
				continue
			}
			candidates = append(candidates, candidate{entry, -1})
			continue
		}
		// A recipe requiring a profession is only eligible when the engine player has it.
		if profession := entry["requiredProfession"]; profession != nil && profession != float64(0) {
			skipped["profession"]++
			continue
		}
		for slot, rawItem := range items {
			item := enhancementGeometry(catalog, p, rawItem.(map[string]any))
			if enhancementFits(entry, item, slot) {
				candidates = append(candidates, candidate{entry, slot})
			}
		}
	}
	rows := make([]map[string]any, len(candidates))
	tasks := make(chan int, len(candidates))
	for i := range candidates {
		tasks <- i
	}
	close(tasks)
	var wg sync.WaitGroup
	for worker := 0; worker < variantWorkers(len(candidates)); worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range tasks {
				c := candidates[i]
				r := cloneMap(req)
				row := cloneMap(c.entry)
				rows[i] = row
				pl, _ := playerOf(r)
				var issue error
				if c.slot < 0 {
					issue = addEnhancementFood(r, c.entry, manifest)
					row["slot"] = "food"
				} else {
					row["slot"] = enhancementSlots[c.slot]
					row["slotIndex"] = float64(c.slot)
					array(child(pl, "equipment"), "items")[c.slot].(map[string]any)["enchant"] = c.entry["effectId"]
				}
				if issue == nil {
					var got map[string]any
					got, issue = s.once(ctx, r)
					if issue == nil {
						row["dps"] = simDPS(got)
						row["delta"] = simDPS(got) - before
						row["pct"] = 100 * (simDPS(got)/before - 1)
					}
				}
				if issue != nil {
					row["error"] = issue.Error()
				}
			}
		}()
	}
	wg.Wait()
	if e := ctx.Err(); e != nil {
		return nil, e
	}
	best := map[string]map[string]any{}
	for _, row := range baselineRows {
		row["dps"] = before
		row["delta"] = float64(0)
		row["pct"] = float64(0)
		best[str(row, "slot")] = row
	}
	errors := 0
	var foods []any
	for _, row := range rows {
		if row["error"] != nil {
			errors++
			continue
		}
		slot := str(row, "slot")
		if slot == "food" {
			foods = append(foods, row)
		}
		if best[slot] == nil || num(row, "dps") > num(best[slot], "dps") {
			best[slot] = row
		}
	}
	var recommendations []any
	for _, row := range best {
		recommendations = append(recommendations, row)
	}
	sort.Slice(recommendations, func(i, k int) bool {
		a, b := recommendations[i].(map[string]any), recommendations[k].(map[string]any)
		if num(a, "delta") == num(b, "delta") {
			return str(a, "slot") < str(b, "slot")
		}
		return num(a, "delta") > num(b, "delta")
	})
	sort.Slice(foods, func(i, k int) bool {
		return num(foods[i].(map[string]any), "dps") > num(foods[k].(map[string]any), "dps")
	})
	if len(foods) > 3 {
		foods = foods[:3]
	}
	return withResultContext(map[string]any{"engine": "MythicSim Go", "engineRevision": s.Config.EngineRevision,
		"baselineDps": before, "recommendations": recommendations, "foods": foods, "tested": len(rows) - errors,
		"failed": errors, "skipped": skipped, "provisional": true, "sources": catalog["sources"], "asOf": catalog["asOf"],
		"iterations": iter, "computedAt": time.Now().Unix(), "comparison": "Aktuell getragene VZ, ohne Food; gleiche Rotation/Seed. Jeweils eine Aenderung; Gewinne nicht addieren. Food fuer volle Kampfdauer aktiv; XP-Bonus ist kein DPS-Bonus. VZ-Empfaenger-/Itemlevel-Voraussetzungen im Spiel pruefen."}, req), nil
}
