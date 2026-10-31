package main

import (
	"context"
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

func simDPS(result map[string]any) float64 {
	return num(child(child(result, "raidMetrics"), "dps"), "avg")
}

// Small finite differences in the engine's raw stat units, not mixed percentage/rating units.
func (s *SimService) statSensitivity(ctx context.Context, req, base map[string]any, j Job) (any, error) {
	var manifest map[string]any
	if e := loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest); e != nil {
		return nil, e
	}
	indices := child(manifest, "stats")
	count := int(num(manifest, "statCount"))
	if count < 1 {
		return nil, fmt.Errorf("Stat-Schema fehlt")
	}
	list := array(j.Payload, "stats")
	if len(list) == 0 {
		for _, key := range []string{"StatSpellDamage", "StatHitRating", "StatCritRating", "StatHasteRating", "StatIntellect", "StatAgility", "StatStrength", "StatAttackPower", "StatRangedAttackPower", "StatFeralAttackPower", "StatExpertiseRating", "StatArmorPenetration"} {
			list = append(list, map[string]any{"key": key, "increment": float64(10)})
		}
	}
	if len(list) > 16 {
		return nil, fmt.Errorf("Maximal 16 Stats pro Auftrag")
	}
	before := simDPS(base)
	var rows []any
	for _, raw := range list {
		st, ok := raw.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("Ungueltiger Stat")
		}
		key := str(st, "key")
		index, ok := indices[key].(float64)
		step := num(st, "increment")
		if !ok || step <= 0 || step > 100 || int(index) < 0 || int(index) >= count {
			return nil, fmt.Errorf("Ungueltiger Stat-Schritt: %s", key)
		}
		r := cloneMap(req)
		p, _ := playerOf(r)
		bonus := child(p, "bonusStats")
		if bonus == nil {
			bonus = map[string]any{}
			p["bonusStats"] = bonus
		}
		stats := array(bonus, "stats")
		for len(stats) < count {
			stats = append(stats, float64(0))
		}
		v, ok := stats[int(index)].(float64)
		if !ok {
			return nil, fmt.Errorf("Ungueltige Bonusstats")
		}
		stats[int(index)] = v + step
		bonus["stats"] = stats
		got, e := s.once(ctx, r)
		if e != nil {
			return nil, e
		}
		dps := simDPS(got)
		rows = append(rows, map[string]any{"key": key, "increment": step, "perPoint": (dps - before) / step, "dps": dps, "delta": dps - before, "unit": "DPS pro rohem Engine-Statpunkt"})
	}
	player, _ := playerOf(req)
	return withResultContext(map[string]any{"engine": "Engine Go", "engineRevision": s.Config.EngineRevision, "base": before, "class": strings.ToLower(strings.TrimPrefix(str(player, "class"), "Class")), "level": engineLevel(req), "rows": rows, "comparison": "Gleiche Rotation und gleicher Seed; lokale Stat-Sensitivitaet, keine allgemeinen BiS-Gewichte"}, req), nil
}

// Aggregate engine metrics, preserving actor and spell IDs. This is not a fabricated event trace.
func summarizeAnalysis(base, req map[string]any) map[string]any {
	iterations := num(child(req, "simOptions"), "iterations")
	if iterations < 1 {
		iterations = 1
	}
	var actions []any
	var visit func(map[string]any, string)
	visit = func(unit map[string]any, actor string) {
		if str(unit, "name") != "" {
			actor = str(unit, "name")
		}
		for _, raw := range array(unit, "actions") {
			a := raw.(map[string]any)
			damage, casts, hits := 0.0, 0.0, 0.0
			for _, target := range array(a, "targets") {
				t := target.(map[string]any)
				damage += num(t, "damage")
				casts += num(t, "casts")
				hits += num(t, "hits")
			}
			if damage > 0 || casts > 0 {
				actions = append(actions, map[string]any{"actor": actor, "id": a["id"], "damage": damage / iterations, "casts": casts / iterations, "hits": hits / iterations, "isPassive": a["isPassive"]})
			}
		}
		for _, raw := range array(unit, "pets") {
			visit(raw.(map[string]any), actor+" / Pet")
		}
	}
	for _, party := range array(child(base, "raidMetrics"), "parties") {
		for _, player := range array(party.(map[string]any), "players") {
			visit(player.(map[string]any), "Spieler")
		}
	}
	sort.Slice(actions, func(i, j int) bool {
		return num(actions[i].(map[string]any), "damage") > num(actions[j].(map[string]any), "damage")
	})
	return map[string]any{"dps": simDPS(base), "duration": num(child(req, "encounter"), "duration"), "actions": actions, "comparison": "Engine-Mittelwerte pro Kampf ueber alle Iterationen; kein zeitlicher Kampfverlauf"}
}

// Resolve spell references inside APL conditions as well: a level-60
// Serpent Sting aura/cooldown ID must be mapped to its learned rank at level 11.
func resolvePriorityCondition(value any, resolve func(int)int) any {
 switch v:=value.(type) {
 case map[string]any:
  result:=make(map[string]any,len(v))
  for key,raw:=range v {
   if key=="spellId" {
    if ref,ok:=raw.(map[string]any);ok {
     copied:=make(map[string]any,len(ref))
     for k,item:=range ref{copied[k]=resolvePriorityCondition(item,resolve)}
     if id:=int(num(ref,"spellId"));id>0 {
      if learned:=resolve(id);learned>0 {copied["spellId"]=float64(learned)}
     }
     result[key]=copied
     continue
    }
   }
   result[key]=resolvePriorityCondition(raw,resolve)
  }
  return result
 case []any:
  result:=make([]any,len(v))
  for i,item:=range v{result[i]=resolvePriorityCondition(item,resolve)}
  return result
 default:
  return value
 }
}

// Display the selected APL using the player's truly learned rank IDs.
// Upstream APLs use level-60 rank IDs even at level 11. The rank families
// come from Engine's own generated client spell data, not display names.
func rotationPriority(rotation map[string]any, knownIDs []any, families map[string]any, class string) []any {
 rows := []any{}
 seen := map[int]bool{}
 known := map[int]bool{}
 for _, raw := range knownIDs {
  if id, ok := raw.(float64); ok && id > 0 { known[int(id)] = true }
 }
 resolve := func(id int) int {
  if knownIDs == nil || known[id] { return id }
  // Highest known rank of the same trained spell.
  ranks := array(families, strconv.Itoa(id))
  for i := len(ranks)-1; i >= 0; i-- {
   if rid, ok := ranks[i].(float64); ok && known[int(rid)] { return int(rid) }
  }
  return 0 // Unlearned ability: never recommend it.
 }
 var walk func(map[string]any,int)
 walk = func(action map[string]any, depth int) {
  if depth > 8 || len(rows) >= 24 { return }
  id := int(num(child(child(action, "castSpell"), "spellId"), "spellId"))
  if id > 0 {
   id = resolve(id)
   if id > 0 {
    seen[id] = true
    row := map[string]any{"spellId":id}
    // Keep the original APL predicate. A priority list without conditions
    // incorrectly rotates between spells after every cast, even when its
    // DoT, mana, cooldown or target requirement is not satisfied.
    if condition:=child(action,"condition");len(condition)>0 {
     row["condition"]=resolvePriorityCondition(condition,resolve)
    }
    rows = append(rows,row)
   }
  }
  for _, key := range []string{"sequence", "strictSequence"} {
   for _, raw := range array(child(action,key),"actions") {
    if a, ok := raw.(map[string]any); ok { walk(a,depth+1) }
   }
  }
 }
 for _, raw := range array(rotation, "priorityList") {
  if row, ok := raw.(map[string]any); ok { walk(child(row, "action"), 0) }
 }
 // Auto Shot (75) is not an APL cast action: Engine fires it automatically.
 // Expose it as a distinct, clearly marked passive action for hunters.
 if class == "hunter" && known[75] && !seen[75] {
  rows = append(rows, map[string]any{"spellId":75, "automatic":true})
 }
 return rows
}

func (s *SimService) rotationPriorityFor(req, rotation map[string]any) []any {
 player, err := playerOf(req)
 if err != nil { return nil }
 class := strings.ToLower(strings.TrimPrefix(str(player, "class"), "Class"))
 var manifest map[string]any
 if s.Config.Runtime != "" {
  _ = loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest)
 }
 families := child(child(manifest, "spellRankFamilies"), class)
 // Older engine manifests omit spellRankFamilies entirely. In that case use
 // source-derived rank chains supplied by the addon for this class only.
 if len(families)==0 { families=child(req,"foreverCoreSpellRankFamilies") }
 return rotationPriority(rotation, array(req, engineSpellsKey), families, class)
}
