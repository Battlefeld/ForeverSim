package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Live hunter reconstruction. Everything comes from two kinds of data, never typed in here:
//   - the client, read by the addon (ammo DPS, quiver spell, pet family/speed/attributes/damage);
//   - the engine source, read into engine-data.json at build time (enum values, quiver spells,
//     pet attack speeds, level 60 pet damage) and the client's CreatureFamily table
//     (creature-families.json) for the family names in every client language.
// What the engine cannot represent is refused with a reason, never replaced by a default.

const engineHunterKey = "foreverCoreHunter"
const engineWarningsKey = "foreverCoreWarnings"

type hunterLive struct {
	options  map[string]any
	private  map[string]any
	warnings []string
}

// The table normally ships with the engine update. When it is missing, the companion fetches the
// same client table itself (CreatureFamily on wago.tools, the source prepare_families.py uses).
var creatureFamilyURL = "https://wago.tools/db2/CreatureFamily/csv"

func loadCreatureFamilies(runtime, build, locale string) (map[string]any, error) {
	path := filepath.Join(runtime, "ForeverCore", "creature-families.json")
	var families map[string]any
	if loadJSON(path, &families) == nil && len(array(families, "families")) > 0 {
		if locale == "" || locale == "enUS" || familiesHaveLocale(families, locale) {
			return families, nil
		}
	}
	fetched, e := fetchCreatureFamilies(build, locale)
	if e != nil {
		return nil, fmt.Errorf("Begleitertabelle creature-families.json fehlt und konnte nicht aus der Client-Tabelle CreatureFamily geladen werden: %w", e)
	}
	if e = atomicWrite(path, jsonBytes(fetched)); e != nil {
		return nil, e
	}
	return fetched, nil
}

func familiesHaveLocale(families map[string]any, locale string) bool {
	for _, raw := range array(families, "families") {
		row, _ := raw.(map[string]any)
		if str(child(row, "names"), locale) != "" {
			return true
		}
	}
	return false
}

func fetchFamilyCSV(build, locale string) (map[int]string, string, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	var last error
	for _, query := range []string{"build=" + url.QueryEscape(build) + "&locale=" + url.QueryEscape(locale), "locale=" + url.QueryEscape(locale)} {
		if build == "" && strings.HasPrefix(query, "build=") {
			continue
		}
		src := creatureFamilyURL + "?" + query
		resp, e := client.Get(src)
		if e != nil {
			last = e
			continue
		}
		rows, e := csv.NewReader(io.LimitReader(resp.Body, 4<<20)).ReadAll()
		resp.Body.Close()
		if e != nil || resp.StatusCode != http.StatusOK || len(rows) < 2 {
			last = fmt.Errorf("%s: Status %d", src, resp.StatusCode)
			continue
		}
		idCol, nameCol := -1, -1
		for i, h := range rows[0] {
			switch strings.TrimPrefix(h, "\ufeff") {
			case "ID":
				idCol = i
			case "Name_lang":
				nameCol = i
			}
		}
		if idCol < 0 || nameCol < 0 {
			last = fmt.Errorf("%s: Spalten ID/Name_lang fehlen", src)
			continue
		}
		out := map[int]string{}
		for _, r := range rows[1:] {
			if len(r) <= idCol || len(r) <= nameCol {
				continue
			}
			id, e := strconv.Atoi(r[idCol])
			if e == nil && strings.TrimSpace(r[nameCol]) != "" {
				out[id] = strings.TrimSpace(r[nameCol])
			}
		}
		if len(out) > 0 {
			return out, src, nil
		}
		last = fmt.Errorf("%s: leer", src)
	}
	return nil, "", last
}

func fetchCreatureFamilies(build, locale string) (map[string]any, error) {
	english, enSrc, e := fetchFamilyCSV(build, "enUS")
	if e != nil {
		return nil, e
	}
	localized := map[string]map[int]string{"enUS": english}
	sources := map[string]any{"enUS": enSrc}
	if locale != "" && locale != "enUS" {
		names, src, e := fetchFamilyCSV(build, locale)
		if e != nil {
			return nil, e
		}
		localized[locale], sources[locale] = names, src
	}
	ids := make([]int, 0, len(english))
	for id := range english {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	rows := make([]any, 0, len(ids))
	for _, id := range ids {
		names := map[string]any{}
		for loc, m := range localized {
			if n := m[id]; n != "" {
				names[loc] = n
			}
		}
		rows = append(rows, map[string]any{"id": float64(id), "name": english[id], "names": names})
	}
	return map[string]any{"schema": float64(1), "clientBuild": build, "table": "CreatureFamily", "sources": sources, "families": rows}, nil
}

// English family name (MythicSim's pet names) for the pet the client reports.
func hunterFamilyName(pet, families map[string]any) (string, error) {
	rows := array(families, "families")
	if len(rows) == 0 {
		return "", fmt.Errorf("Begleitertabelle ist leer")
	}
	if id := num(pet, "familyId"); id > 0 {
		for _, raw := range rows {
			row, _ := raw.(map[string]any)
			if num(row, "id") == id {
				return str(row, "name"), nil
			}
		}
		return "", fmt.Errorf("Begleiterfamilie %d fehlt in der Client-Tabelle", int(id))
	}
	shown := strings.ToLower(strings.TrimSpace(str(pet, "family")))
	if shown == "" {
		return "", fmt.Errorf("Begleiterfamilie konnte im Spiel nicht gelesen werden")
	}
	locale := str(pet, "locale")
	match := ""
	for _, raw := range rows {
		row, _ := raw.(map[string]any)
		names := child(row, "names")
		// Prefer the client's own language; other languages only resolve unambiguous names.
		if locale != "" && strings.ToLower(str(names, locale)) == shown {
			return str(row, "name"), nil
		}
		for _, n := range names {
			if s, ok := n.(string); ok && strings.ToLower(s) == shown {
				if match != "" && match != str(row, "name") {
					return "", fmt.Errorf("Begleiterfamilie %q ist ohne Sprachangabe nicht eindeutig", str(pet, "family"))
				}
				match = str(row, "name")
			}
		}
	}
	if match == "" {
		return "", fmt.Errorf("Begleiterfamilie %q nicht in der Client-Tabelle", str(pet, "family"))
	}
	return match, nil
}

func hunterPetSpeed(seconds float64, spec map[string]any) (float64, error) {
	for _, raw := range array(spec, "petAttackSpeeds") {
		row, _ := raw.(map[string]any)
		if math.Abs(num(row, "seconds")-seconds) < 0.005 {
			return num(row, "value"), nil
		}
	}
	return 0, fmt.Errorf("Begleiter-Angriffstempo %.2f s passt zu keinem MythicSim-Wert; ohne Tempo-Buffs und ausserhalb des Kampfes erneut erfassen", seconds)
}

func hunterQuiver(q, spec map[string]any) (float64, error) {
	switch str(q, "status") {
	case "none":
		return num(spec, "quiverNone"), nil
	case "ok":
	default:
		return 0, fmt.Errorf("Koecher/Munitionsbeutel konnte nicht gelesen werden")
	}
	rows := array(spec, "quiver")
	for _, raw := range rows {
		row, _ := raw.(map[string]any)
		if id := num(q, "spellId"); id > 0 && num(row, "spellId") == id {
			return num(row, "value"), nil
		}
	}
	// Forever may use other spell IDs than the engine; the client's own haste value then decides.
	if pct := num(q, "hastePct"); pct > 0 {
		for _, raw := range rows {
			row, _ := raw.(map[string]any)
			if math.Abs(num(row, "hastePct")-pct) < 1e-6 {
				return num(row, "value"), nil
			}
		}
		return 0, fmt.Errorf("Koecher mit %.0f%% Tempo hat keinen MythicSim-Wert", pct)
	}
	return 0, fmt.Errorf("Koecherbonus (Zauber %d) unbekannt", int(num(q, "spellId")))
}

// Base weapon damage the engine expects: the client's min/max include buffs, the percent modifier
// and attack power; the character sheet removes them in exactly this order.
func hunterPetDamage(pet map[string]any, speed float64) (float64, float64, error) {
	d, ap := child(pet, "damage"), child(pet, "attackPower")
	percent := num(d, "percent")
	if d == nil || ap == nil || percent <= 0 || speed <= 0 {
		return 0, 0, fmt.Errorf("Begleiterschaden konnte nicht gelesen werden")
	}
	apTotal := num(ap, "base") + num(ap, "pos") + num(ap, "neg")
	base := func(v float64) float64 {
		return v/percent - num(d, "pos") - num(d, "neg") - apTotal*speed/14
	}
	lo, hi := base(num(d, "min")), base(num(d, "max"))
	if !(lo > 0 && hi >= lo) || math.IsInf(hi, 0) || math.IsNaN(hi) {
		return 0, 0, fmt.Errorf("Begleiterschaden ergibt keinen gueltigen Grundschaden (%.2f-%.2f)", lo, hi)
	}
	return lo, hi, nil
}

func liveHunter(snap, manifest, families map[string]any, level int) (*hunterLive, error) {
	spec := child(manifest, "hunter")
	if spec == nil || manifest["liveHunter"] != true {
		return nil, fmt.Errorf("Engine hat keinen Jaeger-Live-Adapter; ForeverCore mit aktueller Engine neu bauen/installieren")
	}
	h := child(snap, "hunter")
	if h == nil {
		return nil, fmt.Errorf("Jaegerdaten fehlen im Snapshot; Addon aktualisieren")
	}
	out := &hunterLive{options: map[string]any{"petUptime": float64(1)}, private: map[string]any{}}

	ammo := child(h, "ammo")
	switch str(ammo, "status") {
	case "ok":
		dps := num(ammo, "dps")
		if dps <= 0 {
			return nil, fmt.Errorf("Munitions-DPS ungueltig")
		}
		out.private["ammoDps"] = dps
	case "none":
		out.private["ammoDps"] = float64(0)
		out.warnings = append(out.warnings, "Keine Munition angelegt: ohne Munitionsschaden gerechnet.")
	default:
		return nil, fmt.Errorf("Munition konnte im Spiel nicht gelesen werden")
	}
	// The DPS travels separately; the enum stays neutral so it cannot add a second value.
	out.options["ammo"] = num(spec, "ammoNone")

	quiver, e := hunterQuiver(child(h, "quiver"), spec)
	if e != nil {
		return nil, e
	}
	out.options["quiverBonus"] = quiver

	if snap["petActive"] != true {
		out.options["petType"] = num(spec, "petNone")
		out.options["petAttackSpeed"] = float64(0)
		out.warnings = append(out.warnings, "Kein Begleiter aktiv: ohne Begleiter gerechnet.")
		return out, nil
	}
	pet := child(h, "pet")
	if pet == nil || str(pet, "status") != "ok" {
		return nil, fmt.Errorf("Begleiter konnte im Spiel nicht vollstaendig gelesen werden (im Kampf geschuetzte Werte?)")
	}
	name, e := hunterFamilyName(pet, families)
	if e != nil {
		return nil, e
	}
	petType, ok := child(spec, "petTypes")[name].(float64)
	if !ok {
		return nil, fmt.Errorf("Begleiterfamilie %s wird von MythicSim nicht simuliert", name)
	}
	out.options["petType"] = petType
	seconds := num(pet, "speed")
	speed, e := hunterPetSpeed(seconds, spec)
	if e != nil {
		return nil, e
	}
	out.options["petAttackSpeed"] = speed
	// Take the actual attack power shown by the client instead of deriving it
	// from pet Strength, which Forever may report as zero or unavailable.
	ap := child(pet, "attackPower")
	if ap == nil {
		return nil, fmt.Errorf("Begleiter-Angriffskraft fehlt")
	}
	apTotal := 0.0
	for _, k := range []string{"base", "pos", "neg"} {
		v, ok := ap[k].(float64)
		if !ok || math.IsNaN(v) || math.IsInf(v, 0) {
			return nil, fmt.Errorf("Begleiter-Angriffskraft %s fehlt", k)
		}
		apTotal += v
	}
	if apTotal <= 0 {
		return nil, fmt.Errorf("Begleiter-Angriffskraft ungueltig")
	}
	lo, hi, e := hunterPetDamage(pet, seconds)
	if e != nil {
		return nil, e
	}
	values := map[string]any{"attackPower": apTotal, "baseDamageMin": lo, "baseDamageMax": hi}
	// Preserve other real attributes where available. Never use Strength
	// to rebuild AP: MythicSim receives the measured total directly.
	if stats := child(pet, "stats"); stats != nil {
		for _, k := range []string{"agility", "stamina", "intellect", "spirit"} {
			if v, ok := stats[k].(float64); ok && v >= 0 && !math.IsNaN(v) && !math.IsInf(v, 0) {
				values[k] = v
			}
		}
	}
	out.private["pet"] = values
	if pl := int(num(pet, "level")); pl > 0 && pl < level {
		out.warnings = append(out.warnings, "Begleiter Level "+strconv.Itoa(pl)+" liegt unter dem Spielerlevel; Trefferchance des Begleiters wird mit Spielerlevel gerechnet.")
	}
	// Self-check of the damage derivation at 60, where the engine has its own reference value.
	if ref := child(spec, "petLevel60Damage"); level == 60 && num(ref, "min") > 0 {
		want := (num(ref, "min") + num(ref, "max")) / 2 * seconds
		if dev := math.Abs((lo+hi)/2-want) / want; dev > 0.15 {
			out.warnings = append(out.warnings, fmt.Sprintf("Gemessener Begleiterschaden weicht %.0f%% vom MythicSim-Referenzwert ab; Messung im Spiel pruefen.", dev*100))
		}
	}
	return out, nil
}
