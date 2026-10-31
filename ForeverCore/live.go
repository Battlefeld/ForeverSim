package main

import (
	"fmt"
	"sort"
)

const engineSpellsKey = "foreverCoreKnownSpells"

func liveSpellIDs(snap map[string]any) ([]any, error) {
	if str(child(snap, "spellbookStatus"), "state") != "valid" {
		return nil, fmt.Errorf("Live-Zauberbuch ist nicht vollstaendig lesbar")
	}
	seen := map[int]bool{}
	for _, raw := range array(snap, "spells") {
		row, ok := raw.(map[string]any)
		n := num(row, "id")
		if !ok || n < 1 || n != float64(int(n)) {
			return nil, fmt.Errorf("Ungueltiger Zauberbucheintrag")
		}
		seen[int(n)] = true
	}
	if len(seen) == 0 {
		return nil, fmt.Errorf("Live-Zauberbuch ist leer")
	}
	ids := make([]int, 0, len(seen))
	for id := range seen {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	out := make([]any, 0, len(ids))
	for _, id := range ids {
		out = append(out, float64(id))
	}
	return out, nil
}

func liveClassOptions(snap, payload map[string]any, class string) (map[string]any, error) {
	if options := child(payload, "classOptions"); options != nil {
		if class == "hunter" {
			if options["ammo"] == nil || options["petType"] == nil {
				return nil, fmt.Errorf("Jaeger-classOptions muessen Munition und Begleiter ausdruecklich angeben")
			}
			if snap["petActive"] == true && num(options, "petType") == 0 {
				return nil, fmt.Errorf("Aktiver Jaegerbegleiter darf nicht als PetNone simuliert werden")
			}
		}
		return cloneMap(options), nil
	}
	options := map[string]any{}
	if class == "warlock" && snap["petActive"] == true {
		pets := map[string]int{"imp": 1, "voidwalker": 2, "succubus": 3, "sayaad": 3, "felhunter": 4, "felguard": 5}
		id, ok := pets[str(child(snap, "pet"), "type")]
		if !ok {
			return nil, fmt.Errorf("Aktiver Daemon nicht zugeordnet")
		}
		options["summon"] = id
	}
	if class == "hunter" {
		// The upstream reference has no automatic mapping for all low-level ammunition and pet
		// training. Refuse incomplete live data instead of silently simulating AmmoNone/PetNone.
		return nil, fmt.Errorf("Jaeger: Munition und Begleitertraining sind noch nicht vollstaendig zugeordnet; explizite Engine-classOptions oder ein vollstaendiges JSON-Szenario erforderlich")
	}
	return options, nil
}

func resultContext(req map[string]any) map[string]any {
	level := engineLevel(req)
	warnings := []any{}
	if level < 60 {
		warnings = append(warnings, "Levelmodell in Entwicklung: Grund-Krit und Kampfwertumrechnung noch nicht pro Level validiert.")
	}
	estimated := req[engineArmorEstimatedKey] == true
	if estimated {
		warnings = append(warnings, "Gegnerruestung ist geschaetzt; DPS und Itemvergleiche gelten nur fuer dieses Referenzszenario.")
	}
	warnings = append(warnings, array(req, engineWarningsKey)...)
	return map[string]any{"level": level, "targetArmorEstimated": estimated, "warnings": warnings}
}
func withResultContext(result map[string]any, req map[string]any) map[string]any {
	for key, value := range resultContext(req) {
		result[key] = value
	}
	return result
}

// A talent draft can grant an active spell which is not in the current live book yet.
// Reference imports have no book and retain the engine's normal talent behaviour.
func grantDraftSpells(req map[string]any, trees []any, ranks map[string]int) {
	if req[engineSpellsKey] == nil {
		return
	}
	ids := map[int]bool{}
	for _, raw := range array(req, engineSpellsKey) {
		if id, ok := raw.(float64); ok {
			ids[int(id)] = true
		}
	}
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
	list := make([]int, 0, len(ids))
	for id := range ids {
		list = append(list, id)
	}
	sort.Ints(list)
	out := make([]any, 0, len(list))
	for _, id := range list {
		out = append(out, float64(id))
	}
	req[engineSpellsKey] = out
}
