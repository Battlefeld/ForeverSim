package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
)

// The client's expected stats per class and level, the same table the engine's level overlay is built from.
//
//go:embed leveling-data.json
var levelingData []byte

// The voidwalker of each level from cmangos (prepare_demons.py): without it the engine fights with a level 60 demon.
//
//go:embed warlock-demons.json
var warlockDemons []byte

// Kill profile for ForeverRoutes: how much damage a character deals in the first seconds of a fight and how much mana
// and health that costs, per character level, from MythicSim with the level overlay. ForeverRoutes turns it into the
// fight and rest time of every mob in a route (route.TableProfile).
//
// The character is synthetic: the given class and race without items and talents, the spell ranks the overlay picks
// for the level (no live spellbook), the class's leveling rotation. That is a lower bound; quest rewards and talents
// make real characters faster. Each fight starts with full mana and health, as after resting. Every window is its own
// engine run, so damage over time that ticks after the window ends is not counted, as for a mob that died. Mob health,
// mob damage and the time spent resting stay ForeverRoutes' part: the engine target does not attack.
const killProfileSchema = "foreverroutes.killprofile.v1"

var (
	killWindows = []float64{6, 10, 15, 22, 30} // fight lengths in seconds
	killOffsets = []int{0, 2}                  // target level minus character level
	// A rotation for questing mobs: the class's own spell order without raid cooldowns.
	killRotations = map[string]string{"warlock": "affliction", "mage": "fire"}
	// The warlock fights with the voidwalker, as most do while leveling.
	killClassOptions = map[string]map[string]any{"warlock": {"summon": float64(2)}}
)

type killPoint struct {
	Seconds     float64 `json:"seconds"`
	Damage      float64 `json:"damage"`      // average damage dealt in the window, pet included
	ManaSpent   float64 `json:"manaSpent"`   // mana spent minus mana regenerated in the fight (consumables not counted)
	HealthSpent float64 `json:"healthSpent"` // health the character spends itself (Life Tap)
	SecondsOOM  float64 `json:"secondsOom"`  // seconds without mana in the window
}

type killLevel struct {
	Level   int                    `json:"level"`
	Health  float64                `json:"health"` // naked character, from the client's expected stats (leveling-data.json)
	Mana    float64                `json:"mana"`
	Targets map[string][]killPoint `json:"targets"` // key: target level offset ("0", "2")
}

func (s *SimService) killProfile(ctx context.Context, j Job) (any, error) {
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	class := strings.ToLower(str(j.Payload, "class"))
	race := strings.ReplaceAll(str(j.Payload, "race"), " ", "")
	if class == "" || race == "" {
		return nil, fmt.Errorf("Kill-Profil: class und race angeben")
	}
	if _, ok := child(manifest, "races")["Race"+race]; !ok {
		return nil, fmt.Errorf("Volk nicht in MythicSim: %s", race)
	}
	if child(child(manifest, "classes"), class) == nil {
		return nil, fmt.Errorf("Klasse nicht unterstuetzt")
	}
	from, to := int(num(j.Payload, "fromLevel")), int(num(j.Payload, "toLevel"))
	if from == 0 {
		from = minEngineLevel
	}
	if to == 0 {
		to = 30
	}
	if from < minEngineLevel || to > 59 || from > to {
		return nil, fmt.Errorf("Kill-Profil: Level %d-%d, erlaubt 10-59", from, to)
	}
	profile, e := resolveSimProfileFor(manifest, class, "", 0, 0, str(j.Payload, "spec"))
	if e != nil {
		return nil, e
	}
	selected := str(j.Payload, "rotation")
	if selected == "" {
		selected = killRotations[class]
	}
	rotations := child(profile, "rotations")
	if selected == "" || rotations[selected] == nil {
		if rotations["default"] != nil {
			selected = "default"
		} else {
			var names []string
			for name := range rotations {
				names = append(names, name)
			}
			sort.Strings(names)
			if len(names) == 0 {
				return nil, fmt.Errorf("Keine Referenzrotation")
			}
			selected = names[0]
		}
	}
	rotation, ok := lookupRotation(rotations, selected)
	if !ok {
		return nil, fmt.Errorf("Rotation fehlt: %s", selected)
	}
	options := map[string]any{}
	if o := killClassOptions[class]; o != nil {
		options = o
	}
	if o := child(j.Payload, "classOptions"); o != nil {
		options = o
	}
	if class == "hunter" && (options["ammo"] == nil || options["petType"] == nil) {
		return nil, fmt.Errorf("Jaeger-classOptions muessen Munition und Begleiter ausdruecklich angeben")
	}
	iterations := 300.0
	if it := num(j.Payload, "iterations"); it >= 50 && it <= 20000 {
		iterations = it
	}
	var stats map[string]any
	if e := json.Unmarshal(levelingData, &stats); e != nil {
		return nil, e
	}
	base := child(child(stats, "classes"), class)
	for l := from; l <= to; l++ {
		if child(base, fmt.Sprint(l)) == nil {
			return nil, fmt.Errorf("Kill-Profil: keine Grundwerte fuer %s Level %d", class, l)
		}
	}

	var demons map[int]map[string]any
	if class == "warlock" && num(options, "summon") != 0 {
		if num(options, "summon") != 2 {
			return nil, fmt.Errorf("Kill-Profil: synthetischer Hexer nur mit Leerwandler (summon 2) oder ohne Daemon (summon 0)")
		}
		var file struct {
			Voidwalker map[int]map[string]any `json:"voidwalker"`
		}
		if e := json.Unmarshal(warlockDemons, &file); e != nil {
			return nil, e
		}
		demons = file.Voidwalker
		for l := from; l <= to; l++ {
			if demons[l] == nil {
				return nil, fmt.Errorf("Kill-Profil: keine Leerwandlerwerte fuer Level %d", l)
			}
		}
	}
	spec := str(profile, "spec")
	request := func(level, target int, seconds float64) map[string]any {
		player := map[string]any{"apiVersion": manifest["apiVersion"], "name": "ForeverCore", "race": "Race" + race, "class": "Class" + strings.ToUpper(class[:1]) + class[1:], "talentsString": "", "equipment": map[string]any{"items": emptyItems()}, "rotation": rotation, spec: map[string]any{"options": map[string]any{"classOptions": cloneMap(options)}}}
		if d := num(profile, "distanceFromTarget"); d > 0 {
			player["distanceFromTarget"] = d
		}
		_, armor, _ := defaultTarget(target, map[string]any{"targetLevel": float64(target)})
		t := map[string]any{"level": target, "name": fmt.Sprintf("Questgegner Level %d", target), "stats": make([]float64, int(num(manifest, "statCount")))}
		t["stats"].([]float64)[int(num(manifest, "armorStat"))] = armor
		req := map[string]any{"raid": map[string]any{"parties": []any{map[string]any{"players": []any{player}}}}, "encounter": map[string]any{"duration": seconds, "targets": []any{t}}, "simOptions": map[string]any{"iterations": iterations, "randomSeed": "31211"}, engineLevelKey: float64(level)}
		if d := demons[level]; d != nil {
			demon := cloneMap(d)
			demon["summon"] = float64(2)
			req[engineWarlockKey] = demon
		}
		return req
	}

	type job struct {
		level, offset int
		seconds       float64
	}
	var jobs []job
	for l := from; l <= to; l++ {
		for _, off := range killOffsets {
			for _, w := range killWindows {
				jobs = append(jobs, job{l, off, w})
			}
		}
	}
	points := make([]killPoint, len(jobs))
	errs := make([]error, len(jobs))
	var wg sync.WaitGroup
	next := make(chan int)
	for w := 0; w < variantWorkers(len(jobs)); w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range next {
				jb := jobs[i]
				res, e := s.once(ctx, request(jb.level, jb.level+jb.offset, jb.seconds))
				if e != nil {
					errs[i] = e
					continue
				}
				points[i], errs[i] = killPointOf(res, jb.seconds, iterations)
			}
		}()
	}
	for i := range jobs {
		next <- i
	}
	close(next)
	wg.Wait()
	byLevel := map[int]*killLevel{}
	var levels []*killLevel
	for i, jb := range jobs {
		if errs[i] != nil {
			return nil, fmt.Errorf("Level %d, Ziel %+d, %gs: %w", jb.level, jb.offset, jb.seconds, errs[i])
		}
		lv := byLevel[jb.level]
		if lv == nil {
			row := child(base, fmt.Sprint(jb.level))
			lv = &killLevel{Level: jb.level, Health: poolOf(num(row, "health"), num(row, "stamina"), 10), Mana: poolOf(num(row, "mana"), num(row, "intellect"), 15), Targets: map[string][]killPoint{}}
			if num(row, "mana") == 0 {
				lv.Mana = 0
			}
			byLevel[jb.level] = lv
			levels = append(levels, lv)
		}
		key := fmt.Sprint(jb.offset)
		lv.Targets[key] = append(lv.Targets[key], points[i])
	}
	sort.Slice(levels, func(a, b int) bool { return levels[a].Level < levels[b].Level })
	return map[string]any{
		"schema": killProfileSchema, "source": "ForeverCore " + Version + " / MythicSim " + s.Config.EngineRevision,
		"class": class, "race": race, "spec": spec, "rotation": selected, "classOptions": options,
		"gear": "none", "talents": "none", "spellbook": "ranks by level", "iterations": iterations,
		"targetArmorEstimated": true, "levels": levels,
		"note": "Synthetischer Charakter ohne Ausruestung und Talente (Untergrenze). Jeder Kampf beginnt mit vollem Mana; das Ziel greift nicht an.",
	}, nil
}

func emptyItems() []any {
	items := make([]any, 17)
	for i := range items {
		items[i] = map[string]any{}
	}
	return items
}

// poolOf is Classic's health or mana from the base value and stamina or intellect: the first 20 points give one
// each, every further point gives `per`.
func poolOf(base, stat, per float64) float64 {
	return base + math.Min(stat, 20) + math.Max(stat-20, 0)*per
}

func killPointOf(res map[string]any, seconds, iterations float64) (killPoint, error) {
	parties := array(child(res, "raidMetrics"), "parties")
	if len(parties) == 0 {
		return killPoint{}, fmt.Errorf("Ergebnis ohne Gruppe")
	}
	list := array(parties[0].(map[string]any), "players")
	if len(list) == 0 {
		return killPoint{}, fmt.Errorf("Ergebnis ohne Spieler")
	}
	p := list[0].(map[string]any)
	// the raid's DPS: the character alone with its pet
	pt := killPoint{Seconds: seconds, Damage: num(child(child(res, "raidMetrics"), "dps"), "avg") * seconds, SecondsOOM: num(p, "secondsOomAvg")}
	for _, raw := range array(p, "resources") {
		r := raw.(map[string]any)
		if child(r, "id")["itemId"] != nil {
			continue
		}
		gain := num(r, "actualGain")
		switch str(r, "type") {
		case "ResourceTypeMana":
			pt.ManaSpent -= gain
		case "ResourceTypeHealth":
			if gain < 0 {
				pt.HealthSpent -= gain
			}
		}
	}
	pt.ManaSpent /= iterations
	pt.HealthSpent /= iterations
	return pt, nil
}
