package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Route while playing: the addon sends what the game shows of the character (level, XP, position, quest log with
// progress, finished quests), ForeverRoutes plans the next stretch from there (`foreverroutes next`), and the addon
// shows it. Every quest event plans again from the new state, so the route always fits this character.
//
// The fight times come from this character's class and race in Engine (kill-profile, cached per engine revision).
// While a profile is still being calculated, the route is planned with ForeverRoutes' default estimate and says so.

// routeProfileLevels is the level range of the kill profiles route-next calculates (the levels ForeverRoutes plans).
var routeProfileLevels = [2]float64{10, 40}

var profileJobs sync.Map // profile path -> true while running, or the error that stopped it (not retried until restart)

// routeNext answers job "route-next". State: {race, class, live}, live as ForeverRoutes reads it (route.Live).
func (s *Service) routeNext(ctx context.Context, j Job) (any, error) {
	routesAccessMu.RLock()
	defer routesAccessMu.RUnlock()
	live := child(j.State, "live")
	if str(j.State, "race") == "" || str(j.State, "class") == "" || live == nil {
		return nil, fmt.Errorf("Route: Volk, Klasse und Spielstand fehlen")
	}
	race, class, faction, identityErr := routeIdentity(str(j.State, "race"), str(j.State, "class"), str(j.State, "faction"))
	if identityErr != nil {
		return nil, identityErr
	}
	if child(live, "pos") == nil {
		return nil, fmt.Errorf("Route: Position nicht lesbar (in Instanzen wird nicht geplant)")
	}
	exe, data := s.cfg.Routes, s.cfg.RoutesData
	if _, e := os.Stat(exe); e != nil {
		return nil, fmt.Errorf("Route: foreverroutes.exe fehlt (%s)", exe)
	}
	if _, e := os.Stat(data); e != nil {
		return nil, fmt.Errorf("Route: Routen-Datensatz fehlt (%s)", data)
	}
	horizon := num(j.Payload, "horizon")
	if horizon == 0 {
		horizon = 3600
	}
	if math.IsNaN(horizon) || math.IsInf(horizon, 0) || horizon < 600 || horizon > 14400 {
		return nil, fmt.Errorf("Route: Planungszeitraum 600-14400 Sekunden")
	}
	dir, e := os.MkdirTemp("", "forevercore-route-")
	if e != nil {
		return nil, e
	}
	defer os.RemoveAll(dir)
	in, out := filepath.Join(dir, "live.json"), filepath.Join(dir, "next.json")
	// ForeverRoutes spells classes like the game's English names ("Warlock").
	request := map[string]any{"race": race, "class": strings.ToUpper(class[:1]) + class[1:], "faction": faction, "live": live}
	if opts, ok := j.State["options"].([]any); ok && len(opts) > 0 {
		request["options"] = opts // the route's options switched on in the addon (/fr option)
	}
	if e = os.WriteFile(in, jsonBytes(request), 0o600); e != nil {
		return nil, e
	}
	args := []string{"next", "-data", data, "-live", in, "-out", out, "-horizon", fmt.Sprint(horizon)}
	if routesSupportClientQuests(s.cfg) && fileOK(clientQuestsPath(s.cfg)) {
		args = append(args, "-client-quests", clientQuestsPath(s.cfg))
	}
	// the character's best route (ForeverRoutes' improve, shipped beside the dataset) is followed from where it stands
	// "Solo mit Dungeon" (dungeon runs) when the player chose it in the addon
	dungeons, _ := j.State["dungeons"].(bool)
	if r := routeFile(data, race, class, faction, dungeons); r != "" {
		args = append(args, "-route", r)
	}
	// the class's kill profile ForeverRoutes ships beside the dataset, else one calculated here
	// (the character's own one first, when ForeverCore calculated it for the personal route: job route-profile)
	profile, pending := filepath.Join(personalDir(s.cfg), "profile-"+strings.ToLower(race)+"-"+class+".json"), ""
	if !fileOK(profile) {
		profile = filepath.Join(filepath.Dir(data), "profiles", class+".json")
	}
	if !fileOK(profile) {
		profile, pending = s.killProfileFor(class, race)
	}
	if profile != "" {
		args = append(args, "-profile", profile)
	}
	if dungeons {
		args = append(args, "-dungeons=true")
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	logs, e := noWindow(exec.CommandContext(ctx, exe, args...)).CombinedOutput()
	if e != nil {
		return nil, fmt.Errorf("Route: %v: %.600s", e, logs)
	}
	var reply map[string]any
	if e = loadJSON(out, &reply); e != nil {
		return nil, e
	}
	if pending != "" {
		reply["profileNote"] = pending
	}
	return reply, nil
}

// killProfileFor is the kill profile file of the class and race for the installed engine. When none exists yet it
// starts calculating one in the background (about a minute the first time) and returns why there is none.
func (s *Service) killProfileFor(class, race string) (path, note string) {
	if s.cfg.Engine == "" || s.cfg.EngineRevision == "" {
		return "", "Kampfzeiten geschaetzt: keine Engine eingerichtet"
	}
	rev := s.cfg.EngineRevision
	if len(rev) > 16 {
		rev = rev[:16]
	}
	file := filepath.Join(s.cfg.Data, "Profiles", fmt.Sprintf("%s-%s-%s.json", class, strings.ToLower(race), rev))
	if fileOK(file) {
		return file, ""
	}
	if v, known := profileJobs.LoadOrStore(file, true); known {
		if issue, failed := v.(string); failed {
			return "", "Kampfzeiten geschaetzt: " + issue
		}
	} else {
		go func() {
			simRace := race
			if simRace == "Scourge" { // the game's name of the Undead
				simRace = "Undead"
			}
			result, e := s.sim.killProfile(context.Background(), Job{Kind: "kill-profile", Payload: map[string]any{"class": class, "race": simRace, "fromLevel": routeProfileLevels[0], "toLevel": routeProfileLevels[1]}})
			if e == nil {
				var b []byte
				if b, e = json.MarshalIndent(result, "", " "); e == nil {
					e = atomicWrite(file, b)
				}
			}
			if e != nil {
				log.Printf("Kampfprofil %s %s: %v", class, race, e)
				profileJobs.Store(file, "kein Engine-Kampfprofil ("+e.Error()+")")
				return
			}
			profileJobs.Delete(file)
		}()
	}
	return "", "Kampfzeiten geschaetzt: das Engine-Kampfprofil fuer diese Klasse wird gerade berechnet"
}

// routeFile is the best route ForeverRoutes ships for a race and class (routes/<race>-<class>.json beside the dataset;
// the Skyborne per side: skyborne-a, skyborne-h), or "" when there is none.
func routeFile(data, race, class, faction string, dungeons bool) string {
	race, class, faction, err := routeIdentity(race, class, faction)
	if err != nil {
		return ""
	}
	name := strings.ToLower(race)
	if name == "skyborne" {
		switch faction {
		case "Alliance":
			name += "-a"
		case "Horde":
			name += "-h"
		default:
			return ""
		}
	}
	path := filepath.Join(filepath.Dir(data), "routes", name+"-"+strings.ToLower(class)+".json")
	if dungeons {
		// the route with dungeons when there is one, else the one without
		if g := strings.TrimSuffix(path, ".json") + "-dungeons.json"; fileOK(g) {
			return g
		}
	}
	if !fileOK(path) {
		return ""
	}
	return path
}

func fileOK(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// Keep the live request, route filename and class profile on the same canonical identity. In particular, the
// client calls Undead "Scourge", and Skyborne routes are separate for each faction. Only supported identifiers may
// become path components; a malformed state must never select another character's route or profile.
func routeIdentity(race, class, faction string) (string, string, string, error) {
	races := map[string]string{
		"human": "Human", "orc": "Orc", "dwarf": "Dwarf", "nightelf": "NightElf", "undead": "Undead",
		"scourge": "Undead", "tauren": "Tauren", "gnome": "Gnome", "troll": "Troll", "skyborne": "Skyborne",
	}
	canonicalRace := races[strings.ToLower(strings.Join(strings.Fields(race), ""))]
	if canonicalRace == "" {
		return "", "", "", fmt.Errorf("Route: unbekanntes Volk %q", race)
	}
	canonicalClass := strings.ToLower(strings.TrimSpace(class))
	switch canonicalClass {
	case "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid":
	default:
		return "", "", "", fmt.Errorf("Route: unbekannte Klasse %q", class)
	}
	canonicalFaction := ""
	switch strings.ToLower(strings.TrimSpace(faction)) {
	case "":
		if canonicalRace == "Skyborne" {
			return "", "", "", fmt.Errorf("Route: Skyborne brauchen eine Fraktion (Alliance oder Horde)")
		}
	case "a", "alliance":
		canonicalFaction = "Alliance"
	case "h", "horde":
		canonicalFaction = "Horde"
	default:
		return "", "", "", fmt.Errorf("Route: unbekannte Fraktion %q", faction)
	}
	if canonicalRace != "Skyborne" && canonicalFaction != "" {
		expected := "Alliance"
		switch canonicalRace {
		case "Orc", "Undead", "Tauren", "Troll":
			expected = "Horde"
		}
		if canonicalFaction != expected {
			return "", "", "", fmt.Errorf("Route: Fraktion %s passt nicht zu %s", canonicalFaction, canonicalRace)
		}
	}
	return canonicalRace, canonicalClass, canonicalFaction, nil
}
