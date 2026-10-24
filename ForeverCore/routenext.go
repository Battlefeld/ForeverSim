package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
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
// The fight times come from this character's class and race in MythicSim (kill-profile, cached per engine revision).
// While a profile is still being calculated, the route is planned with ForeverRoutes' default estimate and says so.

// routeProfileLevels is the level range of the kill profiles route-next calculates (the levels ForeverRoutes plans).
var routeProfileLevels = [2]float64{10, 30}

var profileJobs sync.Map // profile path -> true while running, or the error that stopped it (not retried until restart)

// routeNext answers job "route-next". State: {race, class, live}, live as ForeverRoutes reads it (route.Live).
func (s *Service) routeNext(ctx context.Context, j Job) (any, error) {
	race := strings.ReplaceAll(str(j.State, "race"), " ", "")
	class := strings.ToLower(str(j.State, "class"))
	live := child(j.State, "live")
	if race == "" || class == "" || live == nil {
		return nil, fmt.Errorf("Route: Volk, Klasse und Spielstand fehlen")
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
	if horizon < 600 || horizon > 14400 {
		return nil, fmt.Errorf("Route: Planungszeitraum 600-14400 Sekunden")
	}
	dir, e := os.MkdirTemp("", "forevercore-route-")
	if e != nil {
		return nil, e
	}
	defer os.RemoveAll(dir)
	in, out := filepath.Join(dir, "live.json"), filepath.Join(dir, "next.json")
	// ForeverRoutes spells classes like the game's English names ("Warlock").
	request := map[string]any{"race": race, "class": strings.ToUpper(class[:1]) + class[1:], "live": live}
	if e = os.WriteFile(in, jsonBytes(request), 0o600); e != nil {
		return nil, e
	}
	args := []string{"next", "-data", data, "-live", in, "-out", out, "-horizon", fmt.Sprint(horizon)}
	profile, pending := s.killProfileFor(class, race)
	if profile != "" {
		args = append(args, "-profile", profile)
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	logs, e := exec.CommandContext(ctx, exe, args...).CombinedOutput()
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
	if _, e := os.Stat(file); e == nil {
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
				profileJobs.Store(file, "kein MythicSim-Kampfprofil ("+e.Error()+")")
				return
			}
			profileJobs.Delete(file)
		}()
	}
	return "", "Kampfzeiten geschaetzt: das MythicSim-Kampfprofil fuer diese Klasse wird gerade berechnet"
}
