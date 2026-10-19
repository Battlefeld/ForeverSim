package main

import "fmt"

// Client captures public equip requirements; the companion evaluates them before
// asking MythicSim for DPS. Item stats and effects still come from the engine database.
func liveItemEligibility(j Job, item map[string]any) error {
	snap := child(j.State, "sim")
	if snap == nil {
		return nil
	} // Full JSON imports specify their own scenario.
	meta := child(item, "metadata")
	rules := child(snap, "equipmentRules")
	if meta == nil || rules == nil {
		return fmt.Errorf("Tragbarkeitsdaten fehlen; kein Itemwert ohne Pruefung")
	}
	// Dungeon drops are previewed: the question is what the item would do for this class, not whether it can be
	// worn today, so neither the level requirement nor the level of the armor tiers counts for them.
	preview := item["ignoreLevel"] == true
	level := num(snap, "level")
	if level < minEngineLevel {
		level = minEngineLevel // levels 5-9 use the armor tiers of level 10 (see liveRequest)
	}
	if preview {
		level = 1000
	}
	if !preview && num(meta, "minLevel") > num(snap, "level") {
		return fmt.Errorf("Item benoetigt Level %.0f", num(meta, "minLevel"))
	}
	if faction := str(meta, "faction"); faction != "" && faction != str(snap, "faction") {
		return fmt.Errorf("Item gehoert zur anderen Fraktion")
	}
	contains := func(key string, value float64) bool {
		for _, entry := range array(rules, key) {
			if n, ok := entry.(float64); ok && n == value {
				return true
			}
		}
		return false
	}
	slot := int(num(item, "slot"))
	maxArmor := 0.0
	for _, raw := range array(rules, "armorTiers") {
		tier := raw.(map[string]any)
		if level >= num(tier, "minLevel") && num(tier, "maxSubclass") > maxArmor {
			maxArmor = num(tier, "maxSubclass")
		}
	}
	armor := num(meta, "itemSubclass")
	if armor == 0 {
		armor = map[string]float64{"cloth": 1, "leather": 2, "mail": 3, "plate": 4}[str(meta, "armorType")]
	}
	itemClass := num(meta, "itemClass")
	if slot != 3 && slot != 15 && armor >= 1 && armor <= 4 && (itemClass == 0 || itemClass == 4) && armor > maxArmor {
		return fmt.Errorf("Ruestung nicht tragbar")
	}
	if slot == 14 || slot == 15 || slot == 16 {
		wc, ws := num(meta, "weaponClass"), num(meta, "weaponSubclass")
		if _, ok := meta["weaponClass"]; !ok {
			wc = itemClass
			ws = num(meta, "itemSubclass")
		}
		allowed := wc == 2 && contains("weaponSubclasses", ws)
		if slot == 16 {
			allowed = wc == 2 && contains("rangedSubclasses", ws)
		}
		if slot == 15 {
			allowed = (wc == 2 && rules["dualWield"] == true && (preview || snap["dualWield"] == true) && contains("weaponSubclasses", ws)) || (wc == 4 && (str(meta, "equipLoc") == "INVTYPE_HOLDABLE" || (rules["shield"] == true && ws == 6)))
		}
		if !allowed {
			return fmt.Errorf("Waffe oder Nebenhand nicht tragbar")
		}
		if item["twoHanded"] == true && !contains("twoHandSubclasses", ws) {
			return fmt.Errorf("Zweihandwaffe nicht tragbar")
		}
	}
	for _, raw := range array(snap, "equipped") {
		equipped := raw.(map[string]any)
		oldSlot := str(equipped, "slot")
		if slot == 15 && (oldSlot == "MainHandSlot" || oldSlot == "mainhand") && equipped["twoHanded"] == true {
			return fmt.Errorf("Zweihandwaffe angelegt")
		}
		if (meta["unique"] == true || meta["uniqueEquip"] == true) && num(equipped, "id") == num(child(item, "spec"), "id") {
			indices := map[string]int{"Finger0Slot": 10, "Finger1Slot": 11, "Trinket0Slot": 12, "Trinket1Slot": 13}
			if index, ok := indices[oldSlot]; ok && index != slot {
				return fmt.Errorf("Item ist einzigartig anlegbar")
			}
		}
	}
	return nil
}
