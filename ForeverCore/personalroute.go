package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

// Personal route: the route ForeverRoutes ships is planned with a synthetic character (no items, no talents: the
// lower bound). Job "route-profile" takes the live character instead (the SIM snapshot: its items, talents,
// spellbook, class options and the rotation the addon uses), calculates its kill profile in the engine from its level
// to 40, plans the route from its level on with it (foreverroutes extend -from) and writes it into the ForeverRoutes
// addon (Data/Personal.lua, taken with /reload). It runs in the background, a few minutes; the job answers at once
// with the state of the last run.

// personalRouteTarget: the level the personal route goes to (the shipped routes past 20 go to 40).
const personalRouteTarget = 40

type personalStatus struct {
	State    string  `json:"state"` // running, done, error
	Message  string  `json:"message"`
	Started  string  `json:"started,omitempty"`
	Finished string  `json:"finished,omitempty"`
	Level    int     `json:"level,omitempty"`
	Hours    float64 `json:"hours,omitempty"`
	Key      string  `json:"key,omitempty"` // the character's items, talents and rotation the profile was calculated for
}

var personalMu sync.Mutex

func personalDir(cfg Config) string { return filepath.Join(cfg.Data, "Personal") }

// personalLua is ForeverCore's copy of Data/Personal.lua: an addon update brings an empty one, the install puts
// this one back (restorePersonalRoute).
func personalLua(dataDir string) string { return filepath.Join(dataDir, "Personal", "Personal.lua") }

func (s *Service) personalStatus() personalStatus {
	var st personalStatus
	if loadJSON(filepath.Join(personalDir(s.cfg), "status.json"), &st) != nil {
		st = personalStatus{State: "none", Message: "Noch keine eigene Route berechnet"}
	}
	return st
}

func (s *Service) setPersonalStatus(st personalStatus) {
	_ = atomicWrite(filepath.Join(personalDir(s.cfg), "status.json"), jsonBytes(st))
}

// routeProfile answers job "route-profile": starts the personal route for the live character unless one is being
// calculated or the last one was made for the same items, talents and level (payload.force: anyway).
func (s *Service) routeProfile(ctx context.Context, j Job) (any, error) {
	if s.cfg.Addons == "" {
		return nil, fmt.Errorf("Eigene Route: AddOns-Ordner nicht eingerichtet")
	}
	if !fileOK(s.cfg.Routes) || !fileOK(s.cfg.RoutesData) {
		return nil, fmt.Errorf("Eigene Route: foreverroutes.exe oder Routen-Datensatz fehlt")
	}
	snap := child(j.State, "sim")
	level := int(num(snap, "level"))
	if level < minEngineLevel || level >= personalRouteTarget {
		return nil, fmt.Errorf("Eigene Route: ab Stufe %d bis %d (Stufe %d)", minEngineLevel, personalRouteTarget-1, level)
	}
	req, e := s.sim.liveRequest(j)
	if e != nil {
		return nil, fmt.Errorf("Eigene Route: %w", e)
	}
	key := personalKey(req, level, s.cfg.EngineRevision, routesBuild(s.cfg))
	personalMu.Lock()
	defer personalMu.Unlock()
	st := s.personalStatus()
	if st.State == "running" && time.Since(parseTime(st.Started)) < 30*time.Minute {
		return st, nil
	}
	if st.State == "done" && st.Key == key && j.Payload["force"] != true {
		return st, nil
	}
	dungeons := true
	if v, ok := j.Payload["dungeons"].(bool); ok {
		dungeons = v
	}
	st = personalStatus{State: "running", Message: "Eigene Route wird berechnet (einige Minuten)", Started: time.Now().UTC().Format(time.RFC3339), Level: level, Key: key}
	s.setPersonalStatus(st)
	go func() {
		hours, e := s.planPersonal(context.Background(), j, req, level, dungeons)
		personalMu.Lock()
		defer personalMu.Unlock()
		done := st
		done.Finished = time.Now().UTC().Format(time.RFC3339)
		if e != nil {
			log.Printf("Eigene Route: %v", e)
			done.State, done.Message = "error", "Eigene Route: "+e.Error()
		} else {
			done.State, done.Hours = "done", hours
			done.Message = fmt.Sprintf("Eigene Route bis Stufe %d berechnet (%.1f h): im Spiel /reload eingeben", personalRouteTarget, hours)
		}
		s.setPersonalStatus(done)
	}()
	return st, nil
}

// planPersonal: kill profile, route, addon file. Returns the route's hours from the character's level.
func (s *Service) planPersonal(ctx context.Context, j Job, req map[string]any, level int, dungeons bool) (float64, error) {
	snap := child(j.State, "sim")
	class := strings.ToLower(str(snap, "class"))
	race, _, faction, e := routeIdentity(str(snap, "race"), class, str(snap, "faction"))
	if e != nil {
		return 0, e
	}
	profile, e := s.sim.personalKillProfile(ctx, req, class, level, personalRouteTarget)
	if e != nil {
		return 0, e
	}
	dir, e := os.MkdirTemp("", "forevercore-personal-")
	if e != nil {
		return 0, e
	}
	defer os.RemoveAll(dir)
	profiles := filepath.Join(dir, "profiles")
	if e = atomicWrite(filepath.Join(profiles, class+".json"), jsonBytes(profile)); e != nil {
		return 0, e
	}
	_ = atomicWrite(filepath.Join(personalDir(s.cfg), "profile-"+strings.ToLower(race)+"-"+class+".json"), jsonBytes(profile))
	base := routeFile(s.cfg.RoutesData, race, class, faction, dungeons)
	if base == "" {
		return 0, fmt.Errorf("keine Route fuer %s %s im Routen-Datensatz", race, class)
	}
	routes := filepath.Join(dir, "routes")
	planned := filepath.Join(routes, filepath.Base(base))
	if e = os.MkdirAll(routes, 0o755); e != nil {
		return 0, e
	}
	ctx, cancel := context.WithTimeout(ctx, 20*time.Minute)
	defer cancel()
	run := func(args ...string) error {
		logs, e := noWindow(exec.CommandContext(ctx, s.cfg.Routes, args...)).CombinedOutput()
		if e != nil {
			return fmt.Errorf("foreverroutes %s: %v: %.600s", args[0], e, logs)
		}
		return nil
	}
	if e = run("extend", "-data", s.cfg.RoutesData, "-route", base, "-profiles", profiles, "-from", fmt.Sprint(level),
		"-target", fmt.Sprint(personalRouteTarget), "-stages", "20s", "-budget", "0", "-out", planned); e != nil {
		return 0, e
	}
	lua := filepath.Join(dir, "Personal.lua")
	if e = run("export-addon", "-personal", "-data", s.cfg.RoutesData, "-routes", routes, "-profiles", profiles, "-out", lua); e != nil {
		return 0, e
	}
	b, e := os.ReadFile(lua)
	if e != nil {
		return 0, e
	}
	if e = atomicWrite(personalLua(s.cfg.Data), b); e != nil {
		return 0, e
	}
	if e = atomicWrite(filepath.Join(s.cfg.Addons, "ForeverRoutes", "Data", "Personal.lua"), b); e != nil {
		return 0, e
	}
	return personalHours(planned), nil
}

// personalHours: the planned route's time from the character's level to its end (extend writes the hours of the
// route up to -from as base and of the whole route as improved).
func personalHours(path string) float64 {
	var r struct {
		Hours map[string]float64 `json:"hours"`
	}
	if loadJSON(path, &r) != nil {
		return 0
	}
	return r.Hours["improved"] - r.Hours["base"]
}

// restorePersonalRoute puts ForeverCore's copy of the personal route into a freshly installed ForeverRoutes addon.
func restorePersonalRoute(dataDir, addon string) {
	if b, e := os.ReadFile(personalLua(dataDir)); e == nil {
		_ = atomicWrite(filepath.Join(addon, "Data", "Personal.lua"), b)
	}
}

// personalKey identifies what a personal route was calculated for: the engine request of the live character (items,
// talents, rotation, class options, spellbook), its level, the engine and the routes dataset.
func personalKey(req map[string]any, level int, engine, routes string) string {
	b, _ := json.Marshal(req)
	sum := sha256.Sum256(append([]byte(fmt.Sprintf("%d\x00%s\x00%s\x00", level, engine, routes)), b...))
	return hex.EncodeToString(sum[:8])
}

func routesBuild(cfg Config) string {
	info, e := os.Stat(cfg.RoutesData)
	if e != nil {
		return ""
	}
	return fmt.Sprint(info.ModTime().UnixNano(), info.Size())
}

func parseTime(s string) time.Time { t, _ := time.Parse(time.RFC3339, s); return t }

// personalKillProfile is the kill profile (as killProfile) of the live character: its engine request with each
// level, fight length and target level. At its own level it fights with its own spellbook; above it the ranks of
// each level (the overlay's choice), items and talents as they are now: still a lower bound for later levels.
func (s *SimService) personalKillProfile(ctx context.Context, live map[string]any, class string, from, to int) (map[string]any, error) {
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
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	armorStat := int(num(manifest, "armorStat"))
	iterations := 300.0
	request := func(level, target int, seconds float64) map[string]any {
		req := cloneMap(live)
		req[engineLevelKey] = float64(level)
		if level != from {
			delete(req, engineSpellsKey)
		}
		child(req, "simOptions")["iterations"] = iterations
		enc := child(req, "encounter")
		enc["duration"] = seconds
		targets := array(enc, "targets")
		if len(targets) > 0 {
			t := targets[0].(map[string]any)
			_, armor, estimated := defaultTarget(target, map[string]any{"targetLevel": float64(target)})
			t["level"], t["name"] = float64(target), fmt.Sprintf("Questgegner Level %d", target)
			if st, ok := t["stats"].([]any); ok {
				if armorStat >= 0 && armorStat < len(st) {
					st[armorStat] = armor
				}
			}
			if estimated {
				req[engineArmorEstimatedKey] = true
			}
		}
		return req
	}
	levels, e := s.killLevels(ctx, base, from, to, iterations, request)
	if e != nil {
		return nil, e
	}
	player, _ := playerOf(live)
	return map[string]any{
		"schema": killProfileSchema, "source": "ForeverCore " + Version + " / Engine " + s.Config.EngineRevision,
		"class": class, "race": strings.TrimPrefix(str(player, "race"), "Race"), "spec": str(live, "foreverCoreSpec"), "rotation": "live",
		"classOptions": map[string]any{}, "gear": "live character", "talents": str(player, "talentsString"),
		"spellbook": fmt.Sprintf("live at level %d, ranks by level above", from), "iterations": iterations,
		"targetArmorEstimated": true, "levels": levels,
		"note": "Eigener Charakter: Gegenstaende, Talente und Rotation wie im Spiel, darueber hinaus unveraendert (Untergrenze fuer spaetere Stufen). Leben und Mana ohne Ausruestung; jeder Kampf beginnt mit vollem Mana; das Ziel greift nicht an.",
	}, nil
}
