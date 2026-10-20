package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"hash/crc32"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// variantWorkers is the number of engine processes that run at the same time for one job.
// MythicSim uses several threads itself, so half the logical CPUs is a safe upper bound.
func variantWorkers(n int) int {
	w := runtime.NumCPU() / 2
	if w < 1 {
		w = 1
	}
	if w > 6 {
		w = 6
	}
	if n < w {
		w = n
	}
	if w < 1 {
		w = 1
	}
	return w
}

type SimService struct {
	Config    Config
	mu        sync.Mutex
	manifests manifestCache
}

func manifestPath(cfg Config) string {
	return filepath.Join(cfg.Runtime, "ForeverCore", "engine-data.json")
}

// fileStamp changes whenever the file's size or modification time does; 0 for a missing file.
func fileStamp(path string) int64 {
	info, e := os.Stat(path)
	if e != nil {
		return 0
	}
	return info.ModTime().UnixNano() ^ info.Size()
}

func cloneMap(m map[string]any) map[string]any {
	b, _ := json.Marshal(m)
	var n map[string]any
	_ = json.Unmarshal(b, &n)
	return n
}
func child(m map[string]any, k string) map[string]any { v, _ := m[k].(map[string]any); return v }
func array(m map[string]any, k string) []any          { v, _ := m[k].([]any); return v }
func playerOf(r map[string]any) (map[string]any, error) {
	parties := array(child(r, "raid"), "parties")
	if len(parties) != 1 {
		return nil, fmt.Errorf("Genau eine Gruppe benoetigt")
	}
	p, _ := parties[0].(map[string]any)
	players := array(p, "players")
	if len(players) != 1 {
		return nil, fmt.Errorf("Genau ein Charakter benoetigt")
	}
	v, ok := players[0].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Charakter fehlt")
	}
	return v, nil
}
func (s *SimService) liveRequest(j Job) (map[string]any, error) {
	snap := child(j.State, "sim")
	level := int(num(snap, "level"))
	class := strings.ToLower(str(snap, "class"))
	// Levels 5 to 9: the engine's level tables start at 10. The character is calculated as a level 10 one, with its
	// real items, talents and spellbook, and the result carries a note that it is an approximation.
	approxLevel := 0
	if level >= minPlayableLevel && level < minEngineLevel {
		approxLevel = level
		snap = cloneMap(snap)
		snap["level"] = float64(minEngineLevel)
		level = minEngineLevel
	}
	var manifest map[string]any
	if e := loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest); e != nil {
		if level != 60 {
			return nil, levelUnsupported(nil, level)
		}
		return nil, e
	}
	if e := levelUnsupported(manifest, level); e != nil {
		return nil, e
	}
	classes := child(manifest, "classes")
	profile := child(classes, class)
	if profile == nil {
		return nil, fmt.Errorf("Klasse nicht unterstuetzt")
	}
	if str(child(snap, "talentSnapshotStatus"), "state") != "valid" {
		return nil, fmt.Errorf("Live-Talente sind nicht vollstaendig lesbar")
	}
	trees := array(profile, "trees")
	encoded, liveRanks, e := encodeTalentEntries(trees, liveTalentEntries(snap), false, 0)
	if e != nil {
		return nil, e
	}
	// payload.talentsString: the same character with another talent build (see builds.go).
	buildRanks, overridden := liveRanks, false
	if text := str(j.Payload, "talentsString"); text != "" {
		if buildRanks, encoded, e = checkedTalentString(trees, text, 51); e != nil {
			return nil, e
		}
		overridden = true
	}
	items := make([]any, 17)
	for i := range items {
		items[i] = map[string]any{}
	}
	gearOverride := false
	if gear := child(j.Payload, "gear"); gear != nil {
		if items, e = gearItems(gear); e != nil {
			return nil, e
		}
		gearOverride = true
	}
	slots := map[string]int{"HeadSlot": 0, "NeckSlot": 1, "ShoulderSlot": 2, "BackSlot": 3, "ChestSlot": 4, "WristSlot": 5, "HandsSlot": 6, "WaistSlot": 7, "LegsSlot": 8, "FeetSlot": 9, "Finger0Slot": 10, "Finger1Slot": 11, "Trinket0Slot": 12, "Trinket1Slot": 13, "MainHandSlot": 14, "SecondaryHandSlot": 15, "RangedSlot": 16}
	for _, entry := range array(snap, "equipped") {
		if gearOverride {
			break
		}
		it := entry.(map[string]any)
		index, ok := slots[str(it, "slot")]
		if !ok {
			continue
		}
		spec := map[string]any{"id": it["id"]}
		if raw := str(it, "link"); raw != "" {
			spec = parseItemLink(raw, spec)
		}
		items[index] = spec
	}
	race := str(snap, "race")
	race = strings.ReplaceAll(race, " ", "")
	race = "Race" + race
	if _, ok := child(manifest, "races")[race]; !ok {
		return nil, fmt.Errorf("Volk nicht in MythicSim: %s", race)
	}
	var selectedProfile map[string]any
	if overridden {
		tree, largest := largestTreeOf(treePoints(trees, buildRanks))
		selectedProfile, e = resolveSimProfileFor(manifest, class, str(snap, "form"), tree, largest, str(j.Payload, "spec"))
	} else {
		selectedProfile, e = resolveSimProfile(manifest, snap, str(j.Payload, "spec"))
	}
	if e != nil {
		return nil, e
	}
	rotations := child(selectedProfile, "rotations")
	names := make([]string, 0, len(rotations))
	for name := range rotations {
		names = append(names, name)
	}
	sort.Strings(names)
	if len(names) == 0 {
		return nil, fmt.Errorf("Keine Referenzrotation")
	}
	selected := str(j.Payload, "rotation")
	if selected == "" {
		if rotations["default"] != nil {
			selected = "default"
		} else {
			selected = names[0]
		}
	}
	rotation, ok := rotations[selected]
	if !ok {
		return nil, fmt.Errorf("Rotation fehlt: %s", selected)
	}
	knownSpells, e := liveSpellIDs(snap)
	if e != nil {
		return nil, e
	}
	if manifest["liveSpellbook"] != true {
		return nil, fmt.Errorf("Engine hat keinen Live-Zauberbuchadapter; neu bauen/installieren")
	}
	var live *classLive
	var options map[string]any
	if child(j.Payload, "classOptions") == nil {
		pet := child(snap, "petLive")
		if class == "hunter" {
			pet = child(child(snap, "hunter"), "pet")
		}
		var families map[string]any
		if snap["petActive"] == true {
			if families, e = loadCreatureFamilies(s.Config.Runtime, str(manifest, "clientBuild"), str(pet, "locale")); e != nil {
				return nil, e
			}
		}
		if live, e = liveClassState(snap, manifest, families, class, str(selectedProfile, "spec"), level); e != nil {
			return nil, e
		}
		options = live.options
		if class == "hunter" {
			hunter, e := liveHunter(snap, manifest, families, level)
			if e != nil {
				return nil, e
			}
			for k, v := range hunter.options {
				options[k] = v
			}
			live.privates[engineHunterKey] = hunter.private
			live.warnings = append(hunter.warnings, live.warnings...)
		}
	} else if options, e = liveClassOptions(snap, j.Payload, class); e != nil {
		return nil, e
	}
	specOptions := map[string]any{"classOptions": options}
	if live != nil {
		for k, v := range live.specOptions {
			specOptions[k] = v
		}
	}
	player := map[string]any{"apiVersion": manifest["apiVersion"], "name": "ForeverCore", "race": race, "class": "Class" + strings.ToUpper(class[:1]) + class[1:], "talentsString": encoded, "equipment": map[string]any{"items": items}, "rotation": rotation, str(selectedProfile, "spec"): map[string]any{"options": specOptions}}
	if d := num(selectedProfile, "distanceFromTarget"); d > 0 {
		player["distanceFromTarget"] = d
	}
	targetLevel, armor, estimated := defaultTarget(level, j.Payload)
	target := map[string]any{"level": targetLevel, "name": fmt.Sprintf("Referenzziel Level %d", targetLevel), "stats": make([]float64, int(num(manifest, "statCount")))}
	stats := target["stats"].([]float64)
	stats[int(num(manifest, "armorStat"))] = armor
	req := map[string]any{"raid": map[string]any{"parties": []any{map[string]any{"players": []any{player}}}}, "encounter": map[string]any{"duration": 120, "targets": []any{target}}, "simOptions": map[string]any{"iterations": 1000, "randomSeed": "31211"}, engineLevelKey: float64(level), engineSpellsKey: knownSpells}
	if !gearOverride {
		for _, raw := range array(snap, "equipped") {
			if e := addLiveItem(req, raw.(map[string]any), manifest); e != nil {
				return nil, e
			}
		}
	}
	if overridden {
		swapTalentSpells(req, trees, liveRanks, buildRanks)
	}
	req["foreverCoreSpec"] = str(selectedProfile, "spec")
	if it := int(num(j.Payload, "iterations")); it >= 50 && it <= 20000 {
		child(req, "simOptions")["iterations"] = float64(it)
	}
	if estimated {
		req[engineArmorEstimatedKey] = true
	}
	if live != nil {
		for k, v := range live.privates {
			req[k] = v
		}
		if len(live.warnings) > 0 {
			warnings := make([]any, len(live.warnings))
			for i, w := range live.warnings {
				warnings[i] = w
			}
			req[engineWarningsKey] = warnings
		}
	}
	if approxLevel > 0 {
		req[engineWarningsKey] = append(array(req, engineWarningsKey), fmt.Sprintf("Stufe %d: Die Engine rechnet erst ab Stufe 10, es wurde mit Stufe 10 genaehert (Items, Talente und Zauberbuch sind echt).", approxLevel))
	}
	// Display-only rank mapping; stripped before passing JSON to MythicSim.
 // Spell availability still comes exclusively from the real player spellbook.
 req["foreverCoreSpellRankFamilies"] = child(snap,"spellRankFamilies")
 return req, nil
}
func (s *SimService) once(ctx context.Context, req map[string]any) (map[string]any, error) {
	opt := child(req, "simOptions")
	if opt == nil {
		opt = map[string]any{}
		req["simOptions"] = opt
	}
	if num(opt, "iterations") == 0 {
		opt["iterations"] = 1000
	}
	if num(opt, "iterations") < 1 || num(opt, "iterations") > 20000 {
		return nil, fmt.Errorf("Iterationen muessen zwischen 1 und 20000 liegen")
	}
	if _, exists := opt["ruleset"]; exists {
		return nil, fmt.Errorf("Das importierte Profil nutzt eine andere MythicSim-API (ruleset-Feld)")
	}
	if opt["randomSeed"] == nil {
		opt["randomSeed"] = "31211"
	}
	enc := child(req, "encounter")
	if num(enc, "duration") < 1 || num(enc, "duration") > 600 || len(array(enc, "targets")) < 1 || len(array(enc, "targets")) > 5 {
		return nil, fmt.Errorf("Szenario: 1-600 Sekunden, 1-5 Ziele")
	}
	if _, e := playerOf(req); e != nil {
		return nil, e
	}
	var manifest map[string]any
	if s.Config.Runtime != "" {
		if e := loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest); e != nil {
			return nil, fmt.Errorf("Engine-Manifest fehlt: %w", e)
		}
		if s.Config.EngineRevision == "" || str(manifest, "engineRevision") != s.Config.EngineRevision {
			return nil, fmt.Errorf("Engine und Adapterdaten gehoeren zu unterschiedlichen Revisionen; ForeverCore neu bauen/installieren")
		}
		known := child(manifest, "items")
		player, _ := playerOf(req)
		extra := map[int]bool{}
		for _, raw := range array(child(player, "database"), "items") {
			if it, ok := raw.(map[string]any); ok {
				extra[int(num(it, "id"))] = true
			}
		}
		for _, raw := range array(child(player, "equipment"), "items") {
			it, ok := raw.(map[string]any)
			if !ok {
				return nil, fmt.Errorf("Itemeintrag ungueltig")
			}
			id := int(num(it, "id"))
			if id > 0 && known[strconv.Itoa(id)] != true && !extra[id] {
				return nil, fmt.Errorf("Item %d fehlt im gepinnten MythicSim-Datenbestand", id)
			}
		}
	}
	level := engineLevel(req)
	if e := validateEngineLevel(req, manifest, s.Config.Runtime != ""); e != nil {
		return nil, e
	}
	if _, live := req[engineSpellsKey]; live && manifest["liveSpellbook"] != true {
		return nil, fmt.Errorf("Engine unterstuetzt kein Live-Zauberbuch")
	}
	privateBook := req[engineSpellsKey]
	identity := s.Config.EngineRevision
	if expected := str(manifest, "engineSHA256"); expected != "" {
		actual, e := fileSHA256(s.Config.Engine)
		if e != nil {
			return nil, e
		}
		if actual != expected {
			return nil, fmt.Errorf("Engine-Datei passt nicht zum Adaptermanifest; neu installieren")
		}
		identity += "/" + actual
	}
	privateJSON, _ := json.Marshal(privateBook)
	identity += "/" + string(privateJSON)
	privates := map[string][]byte{}
	for key, flag := range enginePrivateFiles {
		if v := req[key]; v != nil {
			if manifest != nil && manifest[flag.manifest] != true {
				return nil, fmt.Errorf("Engine unterstuetzt keine Livewerte fuer %s; ForeverCore neu bauen/installieren", key)
			}
			b, _ := json.Marshal(v)
			privates[key] = b
		}
	}
	for _, key := range sortedKeys(privates) {
		identity += "/" + key + ":" + string(privates[key])
	}
	req = engineRequest(req)
	b, _ := json.Marshal(req)
	sum := sha256.Sum256(append(append([]byte(fmt.Sprintf("%s\x00L%d", identity, level)), 0), b...))
	key := hex.EncodeToString(sum[:])
	cache := filepath.Join(s.Config.Data, "Sims", key+".json")
	var result map[string]any
	if loadJSON(cache, &result) == nil {
		return result, nil
	}
	dir, e := os.MkdirTemp("", "forevercore-sim-")
	if e != nil {
		return nil, e
	}
	defer os.RemoveAll(dir)
	in, out := filepath.Join(dir, "input.json"), filepath.Join(dir, "output.json")
	if e = os.WriteFile(in, b, 0600); e != nil {
		return nil, e
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, s.Config.Engine, "sim", "--strict", "--infile", in, "--outfile", out)
	cmd.Env = engineEnv(level)
	if privateBook != nil {
		bookPath := filepath.Join(dir, "spellbook.json")
		if e = os.WriteFile(bookPath, privateJSON, 0600); e != nil {
			return nil, e
		}
		cmd.Env = append(cmd.Env, "FOREVERCORE_SPELLBOOK="+bookPath)
	}
	for key, b := range privates {
		path := filepath.Join(dir, key+".json")
		if e = os.WriteFile(path, b, 0600); e != nil {
			return nil, e
		}
		cmd.Env = append(cmd.Env, enginePrivateFiles[key].env+"="+path)
	}
	logs, e := cmd.CombinedOutput()
	if e != nil {
		return nil, fmt.Errorf("MythicSim fehlgeschlagen: %v: %.600s", e, logs)
	}
	if e = loadJSON(out, &result); e != nil {
		return nil, e
	}
	if er := child(result, "error"); str(er, "message") != "" {
		return nil, fmt.Errorf("MythicSim: %s", str(er, "message"))
	}
	if num(child(child(result, "raidMetrics"), "dps"), "avg") < 0 {
		return nil, fmt.Errorf("Ungueltiges Ergebnis")
	}
	if e = atomicWrite(cache, jsonBytes(result)); e != nil {
		return nil, e
	}
	return result, nil
}
func (s *SimService) Run(ctx context.Context, j Job) (any, error) {
 if j.Kind=="leveling" && j.Payload["benchmark"]==true { j.Payload=levelingBenchmark(j) }
	s.mu.Lock()
	defer s.mu.Unlock()
	timeout := 170 * time.Second
	if j.Kind == "item" && j.Payload["partial"] == true {
		timeout = 20 * time.Minute
	}
	if j.Kind == "talent-compare" {
		timeout = 5 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	switch j.Kind {
	case "presets":
		return s.presetsFor(ctx, j)
	case "talent-compare":
		return s.compareBuilds(ctx, j)
	}
	req := child(j.Payload, "request")
	var e error
	if req == nil {
		req, e = s.liveRequest(j)
		if e != nil {
			return nil, e
		}
	}
	req = cloneMap(req)
	if j.Kind == "leveling" && len(array(j.Payload, "mobs")) == 0 {
		return nil, fmt.Errorf("Leveling benoetigt explizite Gegnerdaten im Auftrag; automatische Kampferfassung wurde entfernt")
	}
	base, e := s.once(ctx, req)
	if e != nil {
		return nil, e
	}
	dps := num(child(child(base, "raidMetrics"), "dps"), "avg")
	if dps <= 0 {
		return nil, fmt.Errorf("Referenzrotation erzeugt keinen Schaden; Szenario/Rotation pruefen")
	}
	res := map[string]any{"engine": "MythicSim Go", "engineRevision": s.Config.EngineRevision, "baselineDps": dps, "dps": dps, "pct": 100, "selected": "baseline", "scenario": "Explizites MythicSim-Szenario; Live-Buffs werden nicht automatisch rekonstruiert"}
	playerForDisplay, _ := playerOf(req)
	res["priority"]=s.rotationPriorityFor(req,child(playerForDisplay,"rotation"))
	withResultContext(res, req)
	if j.Kind == "weights" {
		return s.statSensitivity(ctx, req, base, j)
	}
	if j.Kind == "talents" {
		return s.compareTalents(ctx, req, base, j)
	}
	if j.Kind == "talent-next" {
		return s.recommendNextTalent(ctx, req, base, j)
	}
	if j.Kind == "talent-build" {
		return s.optimizeTalentBuild(ctx, req, base, j)
	}
	if j.Kind == "leveling" {
		rating, e := levelingRating(dps, j.Payload)
		if e != nil {
			return nil, e
		}
		if j.Payload["benchmark"]==true {
            rating["source"]=str(j.Payload,"benchmarkSource")
            rating["xpKnown"]=false
            req[engineWarningsKey]=append(array(req,engineWarningsKey),"Durchsatzmodell aus MythicSim-Referenz-DPS; keine exakte Kurz-Kampf-/Ressourcen-/Erholungssimulation. EP pro Stunde mangels NPC-EP nicht bekannt.")
        }
        return withResultContext(rating, req), nil
	}
	if j.Kind == "analysis" {
		return withResultContext(summarizeAnalysis(base, req), req), nil
	}
	if j.Kind == "sim" {
		return res, nil
	}
	variants := array(j.Payload, "variants")
	if j.Kind == "rotation" && j.Payload["autoRotations"] == true {
		var manifest map[string]any
		if loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest) == nil {
			player, _ := playerOf(req)
			var rotations map[string]any
			for spec, raw := range child(manifest, "specs") {
				if player[spec] != nil {
					rotations = child(raw.(map[string]any), "rotations")
					break
				}
			}
			names := make([]string, 0, len(rotations))
			for name := range rotations {
				names = append(names, name)
			}
			sort.Strings(names)
			for _, name := range names {
				variants = append(variants, map[string]any{"name": name, "rotation": rotations[name]})
			}
		}
	}
	if j.Kind == "item" {
		items := array(j.Payload, "items")
		if len(items) > 0 {
			for _, item := range items {
				variants = append(variants, map[string]any{"item": item})
			}
		}
	}
	// Pixel jobs carry at most 24 candidates; the auction house export (SavedVariables) may carry more.
	limit := 24
	if j.Kind == "item" && j.Payload["partial"] == true {
		limit = 600
	}
	if len(variants) > limit {
		return nil, fmt.Errorf("Maximal %d Kandidaten je Auftrag", limit)
	}
	if len(variants) == 0 {
		return nil, fmt.Errorf("Keine Kandidaten uebergeben")
	}
	var compared []any
	best := dps
	type candResult struct {
		name   string
		nd     float64
		pct    float64
		need   bool
		r      map[string]any
		player map[string]any
	}
	// One engine run per candidate. The runs are independent, so they are evaluated in parallel
	// (see variantWorkers); the choice of the best candidate stays sequential and deterministic.
	eval := func(i int, v any) (*candResult, error) {
		m, ok := v.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("Kandidat %d ungueltig", i+1)
		}
		r := cloneMap(req)
		player, _ := playerOf(r)
		name := str(m, "name")
		if name == "" {
			name = fmt.Sprintf("Kandidat %d", i+1)
		}
		if rotation := child(m, "rotation"); rotation != nil {
			player["rotation"] = rotation
		} else if item := child(m, "item"); item != nil {
			if e := liveItemEligibility(j, item); e != nil {
				return nil, e
			}
			slot := int(num(item, "slot"))
			if item["slot"] == nil || num(item, "slot") != float64(slot) || slot < 0 || slot > 16 {
				return nil, fmt.Errorf("Ungueltiger Itemslot")
			}
			var manifest map[string]any
			if e := loadJSON(filepath.Join(s.Config.Runtime,"ForeverCore","engine-data.json"), &manifest); e != nil { return nil,e }
			// Lean candidates carry no item snapshot (only the id). Items the engine database knows
			// need nothing more; for the others the client is asked to send the full snapshot.
			variant := item["variant"] == true
			snapshot := child(item, "snapshot")
			fromClient := snapshot != nil
			unknownToEngine := variant || child(manifest, "items")[strconv.Itoa(int(num(child(item, "spec"), "id")))] != true
			learnedKey := str(item, "variantKey")
			if learnedKey == "" {
				learnedKey = "id:" + strconv.Itoa(int(num(child(item, "spec"), "id")))
			}
			// An item the engine does not know but this PC has seen before needs no snapshot any more.
			if snapshot == nil && unknownToEngine {
				if learned, ok := learnedItems.get(s.Config.Data, learnedKey); ok {
					snapshot = learned
				}
			}
			if snapshot == nil && unknownToEngine {
				return &candResult{name: name, need: true}, nil
			}
			clientSnapshot := snapshot
			variantID := 0
			if variant {
				// A variant of a known item ("of Agility": item bonus ids or a random suffix) has other stats
				// than the engine's record for that id. It runs as an item of its own, with the stats the
				// client read, under an id that cannot clash with a real one.
				variantID = variantItemID(str(item, "variantKey"), int(num(snapshot, "id")))
				snapshot = cloneMap(snapshot)
				snapshot["id"] = float64(variantID)
			}
			if e := addLiveItem(r, snapshot, manifest); e != nil { return nil,e }
			if fromClient && unknownToEngine {
				learnedItems.put(s.Config.Data, learnedKey, clientSnapshot) // from now on the id alone is enough
			}
			spec := child(item, "spec")
			if spec != nil && str(item, "link") != "" {
				spec = parseItemLink(str(item, "link"), spec)
			}
			if variant {
				if spec == nil {
					spec = map[string]any{}
				} else {
					spec = cloneMap(spec)
				}
				spec["id"] = float64(variantID)
				delete(spec, "randomSuffix")
			}
			if num(spec, "id") < 1 {
				return nil, fmt.Errorf("Item-ID fehlt")
			}
			equipment := child(player, "equipment")
			items := array(equipment, "items")
			for len(items) < 17 {
				items = append(items, map[string]any{})
			}
			items[slot] = spec
			equipment["items"] = items
			if item["twoHanded"] == true {
				items[15] = map[string]any{}
			}
		} else {
			return nil, fmt.Errorf("Kandidat enthaelt weder Item noch Rotation")
		}
		got, e := s.once(ctx, r)
		if e != nil {
			return nil, e
		}
		nd := num(child(child(got, "raidMetrics"), "dps"), "avg")
		pct := 0.0
		if dps > 0 {
			pct = nd / dps * 100
		}
		return &candResult{name: name, nd: nd, pct: pct, r: r, player: player}, nil
	}
	results := make([]*candResult, len(variants))
	errs := make([]error, len(variants))
	workers := variantWorkers(len(variants))
	sem := make(chan struct{}, workers)
	var wg sync.WaitGroup
	for i, v := range variants {
		sem <- struct{}{}
		wg.Add(1)
		go func(i int, v any) {
			defer wg.Done()
			defer func() { <-sem }()
			defer func() {
				if p := recover(); p != nil {
					errs[i] = fmt.Errorf("Kandidat %d: interner Fehler: %v", i+1, p)
				}
			}()
			results[i], errs[i] = eval(i, v)
		}(i, v)
	}
	wg.Wait()
	for i := range variants {
		if errs[i] != nil {
			if j.Kind == "item" && j.Payload["partial"] == true {
				// bulk jobs: one unusable item must not discard the others
				compared = append(compared, map[string]any{"name": fmt.Sprintf("Kandidat %d", i+1), "dps": 0, "pct": 0, "error": errs[i].Error()})
				continue
			}
			return nil, errs[i]
		}
		c := results[i]
		if c.need {
			compared = append(compared, map[string]any{"name": c.name, "dps": 0, "pct": 0, "need": true})
			continue
		}
		compared = append(compared, map[string]any{"name": c.name, "dps": c.nd, "pct": c.pct})
		if c.nd > best {
			best = c.nd
			res["dps"] = c.nd
			res["pct"] = c.pct
			res["selected"] = c.name
			res["priority"] = s.rotationPriorityFor(c.r, child(c.player, "rotation"))
		}
	}
	if j.Kind == "item" && len(compared) > 0 {
		first := compared[0].(map[string]any)
		if first["need"] == true || first["error"] != nil {
			res["candidates"] = compared
			return res, nil
		}
		res["candidateDps"] = first["dps"]
		res["percent"] = num(first, "pct") - 100
		res["delta"] = num(first, "dps") - dps
	}
	res["candidates"] = compared
	return res, nil
}

// variantItemID gives a variant its own engine item id: far above every real id, derived from the item and
// its variant key so that the same variant always gets the same id.
func variantItemID(key string, base int) int {
	sum := crc32.ChecksumIEEE([]byte(key))
	return 2000000000 + int(sum%90000000) + base%10
}

func parseItemLink(raw string, fallback map[string]any) map[string]any {
	pos := strings.Index(raw, "item:")
	if pos < 0 {
		return fallback
	}
	parts := strings.Split(strings.SplitN(raw[pos+5:], "|", 2)[0], ":")
	if len(parts) == 0 {
		return fallback
	}
	out := cloneMap(fallback)
	if id, e := strconv.Atoi(parts[0]); e == nil && id > 0 {
		out["id"] = float64(id)
	}
	if len(parts) > 1 {
		if id, e := strconv.Atoi(parts[1]); e == nil && id > 0 {
			out["enchant"] = float64(id)
		}
	}
	if len(parts) > 6 {
		if id, e := strconv.Atoi(parts[6]); e == nil && id != 0 {
			out["randomSuffix"] = math.Abs(float64(id))
		}
	}
	var gems []any
	for i := 2; i <= 5 && i < len(parts); i++ {
		id, _ := strconv.Atoi(parts[i])
		gems = append(gems, float64(id))
	}
	if len(gems) > 0 {
		out["gems"] = gems
	}
	return out
}
