package main

import (
	"fmt"
	"sort"
	"strings"
)

// Live class state for every class. The rules (which aura, stance or weapon enchantment sets which
// engine option) are read from the engine source into engine-data.json (prepare_engine.py,
// class_live_options); the values come from the client snapshot. Whatever is active in the game but
// has no engine model is listed in the result, never silently dropped and never guessed.

const engineWarlockKey = "foreverCoreWarlock"

type classLive struct {
	options     map[string]any // classOptions
	specOptions map[string]any // siblings of classOptions in the spec's options (e.g. imbueOh)
	privates    map[string]any // ForeverCore-only request keys handed to the engine as files
	warnings    []string
	used        map[int]bool    // aura/form IDs taken over
	usedHands   map[string]bool // weapon enchantments taken over, by hand
}

func ids(raw []any) []int {
	out := make([]int, 0, len(raw))
	for _, v := range raw {
		if f, ok := v.(float64); ok {
			out = append(out, int(f))
		}
	}
	return out
}

func liveClassState(snap, manifest, families map[string]any, class, spec string, level int) (*classLive, error) {
	live := &classLive{options: map[string]any{}, specOptions: map[string]any{}, privates: map[string]any{}, used: map[int]bool{}, usedHands: map[string]bool{}}
	lo := child(manifest, "liveOptions")
	if lo == nil {
		return nil, fmt.Errorf("Engine-Manifest ohne Live-Klassenoptionen; ForeverCore neu bauen/installieren")
	}
	auras := map[int]bool{}
	for _, id := range ids(array(snap, "activeAuras")) {
		auras[id] = true
	}
	form := int(num(snap, "formSpell"))
	enchants := map[string]int{"mainhand": int(num(child(snap, "weaponEnchants"), "mainhand")), "offhand": int(num(child(snap, "weaponEnchants"), "offhand"))}
	sacrifice := 0.0
	for _, raw := range array(child(lo, "rules"), class) {
		r, _ := raw.(map[string]any)
		if s := str(r, "spec"); s != "" && s != spec {
			continue
		}
		hit := 0
		for _, id := range ids(array(r, "ids")) {
			switch str(r, "source") {
			case "aura":
				if auras[id] {
					hit = id
				}
			case "form":
				if form == id || auras[id] {
					hit = id
				}
			case "mainhand", "offhand":
				if enchants[str(r, "source")] == id {
					hit = id
				}
			}
		}
		if hit == 0 {
			continue
		}
		if src := str(r, "source"); src == "mainhand" || src == "offhand" {
			live.usedHands[src] = true
		} else {
			live.used[hit] = true
		}
		field := str(r, "field")
		if field == "sacrificeDemon" {
			sacrifice = num(r, "value")
			continue
		}
		target := live.options
		if str(r, "scope") == "options" {
			target = live.specOptions
		}
		if old, exists := target[field]; exists && old != r["value"] {
			return nil, fmt.Errorf("Mehrdeutiger Spielzustand fuer %s", field)
		}
		target[field] = r["value"]
	}
	if class == "warlock" {
		if e := live.warlock(snap, manifest, families, sacrifice, level); e != nil {
			return nil, e
		}
	}
	live.reportUnmodeled(snap, enchants)
	return live, nil
}

func (live *classLive) warlock(snap, manifest, families map[string]any, sacrifice float64, level int) error {
	opts := child(manifest, "liveOptions")
	summons := child(opts, "warlockSummon")
	registered := map[string]bool{}
	for _, n := range array(opts, "warlockPets") {
		if s, ok := n.(string); ok {
			registered[s] = true
		}
	}
	if snap["petActive"] != true {
		if sacrifice > 0 {
			live.options["summon"], live.options["sacrificeSummon"] = sacrifice, true
		} else {
			live.options["summon"] = float64(0)
			live.warnings = append(live.warnings, "Kein Daemon aktiv: ohne Daemon gerechnet.")
		}
		return nil
	}
	if manifest["liveWarlock"] != true {
		return fmt.Errorf("Engine hat keinen Daemon-Live-Adapter; ForeverCore mit aktueller Engine neu bauen/installieren")
	}
	pet := child(snap, "petLive")
	if pet == nil || str(pet, "status") != "ok" || !(num(pet, "mana") > 0) {
		return fmt.Errorf("Daemon konnte im Spiel nicht vollstaendig gelesen werden (im Kampf geschuetzte Werte?)")
	}
	name, e := hunterFamilyName(pet, families)
	if e != nil {
		return e
	}
	value, ok := summons[name].(float64)
	if !ok {
		return fmt.Errorf("Daemon %s hat keine Engine-Entsprechung", name)
	}
	if !registered[name] {
		return fmt.Errorf("Daemon %s wird von Engine nicht simuliert", name)
	}
	live.options["summon"] = value
	if sacrifice > 0 {
		live.options["pactSacrifice"] = sacrifice
	}
	stats := child(pet, "stats")
	demon := map[string]any{"summon": value, "mana": num(pet, "mana")}
	// The Forever client often reports 0 for some demon attributes although the character sheet shows
	// the demon (an imp read as 0 for everything but spirit). The engine accepts 0; it is used as read and
	// the result says so, instead of refusing the whole calculation.
	var zero []string
	for _, k := range []string{"strength", "agility", "stamina", "intellect", "spirit"} {
		v := num(stats, k)
		if v <= 0 {
			v = 0
			zero = append(zero, k)
		}
		demon[k] = v
	}
	if len(zero) > 0 {
		live.warnings = append(live.warnings, "Daemon-Attribute im Spiel nicht lesbar ("+strings.Join(zero, ", ")+"): mit 0 gerechnet.")
	}
	// Melee demons: base damage per swing at the engine's 2.0 s swing, same damage per second.
	if name != "Imp" {
		speed := num(pet, "speed")
		lo, hi, e := hunterPetDamage(pet, speed)
		if e != nil {
			return e
		}
		demon["meleeMin"], demon["meleeMax"] = lo*2/speed, hi*2/speed
	}
	spells := map[string]any{}
	modeled := child(opts, "warlockPetSpells")
	for _, raw := range array(snap, "petSpellInfo") {
		info, _ := raw.(map[string]any)
		id := num(info, "id")
		for key, list := range modeled {
			for _, known := range ids(list.([]any)) {
				if float64(known) != id {
					continue
				}
				values := ids(array(info, "values"))
				if info["described"] != true || len(values) == 0 {
					return fmt.Errorf("Daemonzauber %d: Beschreibung im Spiel nicht lesbar", int(id))
				}
				lo, hi := float64(values[0]), float64(values[0])
				if key == "firebolt" && len(values) > 1 {
					hi = float64(values[1])
				}
				row := map[string]any{"min": lo, "max": hi}
				if c := num(info, "cost"); c > 0 {
					row["cost"] = c
				}
				spells[key] = row
			}
		}
	}
	if len(spells) > 0 {
		demon["spells"] = spells
	}
	live.privates[engineWarlockKey] = demon
	if pl := int(num(pet, "level")); pl > 0 && pl < level {
		live.warnings = append(live.warnings, fmt.Sprintf("Daemon Level %d liegt unter dem Spielerlevel; Trefferchance des Daemons wird mit Spielerlevel gerechnet.", pl))
	}
	return nil
}

// Active buffs and weapon enchantments the SIM does not take over. Self buffs of spells in the
// player's own spellbook are cast by the rotation itself and are not listed.
func (live *classLive) reportUnmodeled(snap map[string]any, enchants map[string]int) {
	book := map[int]bool{}
	for _, raw := range array(snap, "spells") {
		row, _ := raw.(map[string]any)
		book[int(num(row, "id"))] = true
	}
	var names []string
	for _, raw := range array(snap, "activeAuraInfo") {
		row, _ := raw.(map[string]any)
		id := int(num(row, "id"))
		if live.used[id] || book[id] {
			continue
		}
		name := str(row, "name")
		if name == "" {
			name = fmt.Sprintf("Aura %d", id)
		}
		names = append(names, name)
	}
	sort.Strings(names)
	if len(names) > 8 {
		names = append(names[:8], fmt.Sprintf("und %d weitere", len(names)-8))
	}
	if len(names) > 0 {
		live.warnings = append(live.warnings, "Aktive Buffs nicht in der SIM: "+strings.Join(names, ", ")+".")
	}
	for _, hand := range []string{"mainhand", "offhand"} {
		if id := enchants[hand]; id > 0 && !live.usedHands[hand] {
			label := map[string]string{"mainhand": "Haupthand", "offhand": "Nebenhand"}[hand]
			live.warnings = append(live.warnings, fmt.Sprintf("Temporaere Waffenverzauberung %d (%s) nicht in der SIM.", id, label))
		}
	}
}

// ForeverCore-only request keys the engine receives as JSON files, with the manifest flag that says
// the installed engine was built with the overlay reading them.
var enginePrivateFiles = map[string]struct{ env, manifest string }{
	engineHunterKey:  {"FOREVERCORE_HUNTER", "liveHunter"},
	engineWarlockKey: {"FOREVERCORE_WARLOCK", "liveWarlock"},
}

func sortedKeys(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
