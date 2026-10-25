package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeRoutes stands in for `foreverroutes next`: it answers with what it was given, so a test can see the live state,
// the class spelling and the kill profile arrive.
func fakeRoutes() {
	flags := map[string]string{}
	for i := 2; i+1 < len(os.Args); i += 2 {
		flags[os.Args[i]] = os.Args[i+1]
	}
	var req map[string]any
	if b, e := os.ReadFile(flags["-live"]); e != nil || json.Unmarshal(b, &req) != nil {
		os.Exit(2)
	}
	reply := map[string]any{"schema": "foreverroutes.next.v1", "class": req["class"], "level": num(child(req, "live"), "level"), "profile": flags["-profile"], "horizon": flags["-horizon"], "route": flags["-route"], "faction": req["faction"],
		"steps": []any{map[string]any{"op": "accept", "quest": 788.0, "name": "Cutting Teeth"}}}
	for _, a := range os.Args {
		if a == "-dungeons=true" {
			reply["group"] = true
		}
	}
	os.WriteFile(flags["-out"], jsonBytes(reply), 0o600)
}

func TestRouteNext(t *testing.T) {
	routeProfileLevels = [2]float64{10, 11}
	defer func() { routeProfileLevels = [2]float64{10, 40} }()
	exe, _ := os.Executable()
	sim, _ := fakeService(t)
	data := filepath.Join(t.TempDir(), "routes-data.json.gz")
	os.WriteFile(data, []byte("x"), 0o600)
	cfg := sim.Config
	cfg.Routes, cfg.RoutesData = exe, data
	s := &Service{cfg: cfg, sim: sim}
	state := map[string]any{"race": "Orc", "class": "WARLOCK", "live": map[string]any{"level": 12.0, "pos": map[string]any{"m": 1.0, "x": -607.0, "y": -4251.0}}}
	got, e := s.routeNext(t.Context(), Job{Kind: "route-next", State: state})
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	if r["class"] != "Warlock" || num(r, "level") != 12 || r["horizon"] != "3600" || len(array(r, "steps")) != 1 {
		t.Fatalf("reply %v", r)
	}
	// the first call has no kill profile yet: it is calculated in the background and the route says so
	if r["profile"] != "" || !strings.Contains(str(r, "profileNote"), "berechnet") {
		t.Errorf("first call: profile %q note %q", r["profile"], r["profileNote"])
	}
	path, note := s.killProfileFor("warlock", "Orc")
	for i := 0; path == "" && i < 200; i++ {
		waitShort()
		path, note = s.killProfileFor("warlock", "Orc")
	}
	if path == "" {
		t.Fatal("kill profile not written:", note)
	}
	got, _ = s.routeNext(t.Context(), Job{Kind: "route-next", State: state})
	if r := got.(map[string]any); r["profile"] != path || r["profileNote"] != nil {
		t.Errorf("second call: profile %q note %v", r["profile"], r["profileNote"])
	}
	for _, bad := range []map[string]any{{"race": "Orc", "class": "WARLOCK"}, {"race": "Orc", "class": "WARLOCK", "live": map[string]any{"level": 3.0}}} {
		if _, e := s.routeNext(t.Context(), Job{Kind: "route-next", State: bad}); e == nil {
			t.Errorf("%v accepted", bad)
		}
	}
	// shipped beside the dataset: the class's profile and the character's best route (Skyborne per side)
	dir := filepath.Dir(data)
	os.MkdirAll(filepath.Join(dir, "routes"), 0o755)
	os.MkdirAll(filepath.Join(dir, "profiles"), 0o755)
	os.WriteFile(filepath.Join(dir, "routes", "skyborne-h-warrior.json"), []byte("[]"), 0o600)
	os.WriteFile(filepath.Join(dir, "profiles", "warrior.json"), []byte("{}"), 0o600)
	sky := map[string]any{"race": "Skyborne", "class": "WARRIOR", "faction": "Horde", "live": state["live"]}
	got, e = s.routeNext(t.Context(), Job{Kind: "route-next", State: sky})
	if r := got.(map[string]any); e != nil || r["faction"] != "Horde" || !strings.HasSuffix(str(r, "route"), "skyborne-h-warrior.json") || !strings.HasSuffix(str(r, "profile"), filepath.Join("profiles", "warrior.json")) {
		t.Errorf("skyborne: %v %v", r, e)
	}
	os.WriteFile(filepath.Join(dir, "routes", "skyborne-h-warrior-group.json"), []byte("[]"), 0o600)
	sky["group"] = true
	got, e = s.routeNext(t.Context(), Job{Kind: "route-next", State: sky})
	if r := got.(map[string]any); e != nil || r["group"] != true || !strings.HasSuffix(str(r, "route"), "skyborne-h-warrior-group.json") {
		t.Errorf("group route: %v %v", r, e)
	}
	if routeFile(data, "Skyborne", "warrior", "", false) != "" || routeFile(data, "Orc", "warrior", "Horde", false) != "" {
		t.Error("route file for an unknown side or a missing route")
	}
	s.cfg.Routes = filepath.Join(t.TempDir(), "missing.exe")
	if _, e := s.routeNext(t.Context(), Job{Kind: "route-next", State: state}); e == nil || !strings.Contains(e.Error(), "foreverroutes.exe") {
		t.Errorf("missing planner: %v", e)
	}
}

func waitShort() { <-time.After(50 * time.Millisecond) }
