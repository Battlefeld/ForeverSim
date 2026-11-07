package main

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRouteIdentityCanonicalizesClientNames(t *testing.T) {
	for _, tc := range []struct {
		race, class, faction, wantRace, wantClass, wantFaction string
	}{
		{"Scourge", "WARLOCK", "Horde", "Undead", "warlock", "Horde"},
		{" undead ", " Priest ", " h ", "Undead", "priest", "Horde"},
		{"Night Elf", "DRUID", "A", "NightElf", "druid", "Alliance"},
		{"Skyborne", "MAGE", "A", "Skyborne", "mage", "Alliance"},
		{" skyborne ", "SHAMAN", "h", "Skyborne", "shaman", "Horde"},
		{"Orc", "Warrior", "", "Orc", "warrior", ""},
	} {
		t.Run(tc.race+"/"+tc.class+"/"+tc.faction, func(t *testing.T) {
			race, class, faction, err := routeIdentity(tc.race, tc.class, tc.faction)
			if err != nil || race != tc.wantRace || class != tc.wantClass || faction != tc.wantFaction {
				t.Fatalf("got %q/%q/%q, %v; want %q/%q/%q", race, class, faction, err, tc.wantRace, tc.wantClass, tc.wantFaction)
			}
		})
	}
}

func TestRouteNextRejectsWrongIdentityBeforePlanning(t *testing.T) {
	s := &Service{} // no planner or engine: bad identities must be rejected before either is used
	for _, tc := range []struct{ race, class, faction string }{
		{"Orc", "../mage", "Horde"},
		{"../Orc", "Warlock", "Horde"},
		{"Orc", "DeathKnight", "Horde"},
		{"Orc", "Warlock", "Alliance"},
		{"Human", "Mage", "Horde"},
		{"Skyborne", "Mage", ""},
		{"Skyborne", "Mage", "Neutral"},
	} {
		t.Run(tc.race+"/"+tc.class+"/"+tc.faction, func(t *testing.T) {
			state := map[string]any{"race": tc.race, "class": tc.class, "faction": tc.faction,
				"live": map[string]any{"pos": map[string]any{"m": 1.0, "x": 0.0, "y": 0.0}}}
			if _, err := s.routeNext(t.Context(), Job{Kind: "route-next", State: state}); err == nil || strings.Contains(err.Error(), "foreverroutes.exe") {
				t.Fatalf("invalid identity reached planner: %v", err)
			}
			if path := routeFile(filepath.Join(t.TempDir(), "data.json"), tc.race, tc.class, tc.faction, false); path != "" {
				t.Fatalf("invalid identity selected %s", path)
			}
		})
	}
}

func TestRouteNextKeepsEveryClassOnItsOwnRouteAndProfile(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	data := filepath.Join(dir, "routes-data.json.gz")
	write := func(path, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write(data, "fixture")
	s := &Service{cfg: Config{Routes: exe, RoutesData: data}}
	for _, tc := range []struct{ race, key, class, faction, wantFaction string }{
		{"Orc", "orc", "Warrior", "H", "Horde"},
		{"Human", "human", "Paladin", "A", "Alliance"},
		{"Orc", "orc", "Hunter", "H", "Horde"},
		{"Orc", "orc", "Rogue", "H", "Horde"},
		{"Scourge", "undead", "Priest", "H", "Horde"},
		{"Orc", "orc", "Shaman", "H", "Horde"},
		{"Gnome", "gnome", "Mage", "A", "Alliance"},
		{"Undead", "undead", "Warlock", "H", "Horde"},
		{"Night Elf", "nightelf", "Druid", "A", "Alliance"},
		{"Skyborne", "skyborne-h", "Shaman", "H", "Horde"},
		{"Skyborne", "skyborne-a", "Mage", "A", "Alliance"},
	} {
		t.Run(tc.key+"/"+tc.class, func(t *testing.T) {
			class := tc.class
			lower := strings.ToLower(class)
			profile := filepath.Join(dir, "profiles", lower+".json")
			route := filepath.Join(dir, "routes", tc.key+"-"+lower+".json")
			write(profile, "{}") // fakeRoutes reports paths; real profile parsing belongs to ForeverRoutes
			write(route, "[]")
			state := map[string]any{"race": " " + strings.ToLower(tc.race) + " ", "class": " " + strings.ToUpper(class) + " ", "faction": tc.faction,
				"live": map[string]any{"level": 12.0, "pos": map[string]any{"m": 1.0, "x": 0.0, "y": 0.0}}}
			got, err := s.routeNext(t.Context(), Job{Kind: "route-next", State: state})
			if err != nil {
				t.Fatal(err)
			}
			r := got.(map[string]any)
			if r["class"] != class || r["profile"] != profile || r["route"] != route || r["faction"] != tc.wantFaction {
				t.Fatalf("wrong route/profile identity: %v", r)
			}
		})
	}
	for _, bad := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		state := map[string]any{"race": "Orc", "class": "Warlock", "live": map[string]any{"pos": map[string]any{}}}
		if _, err := s.routeNext(t.Context(), Job{Kind: "route-next", State: state, Payload: map[string]any{"horizon": bad}}); err == nil || !strings.Contains(err.Error(), "Planungszeitraum") {
			t.Fatalf("non-finite planning horizon accepted: %v", err)
		}
	}
}

func TestRouteFileAliasesAndDirectories(t *testing.T) {
	dir := t.TempDir()
	data := filepath.Join(dir, "routes-data.json.gz")
	if err := os.MkdirAll(filepath.Join(dir, "routes"), 0o755); err != nil {
		t.Fatal(err)
	}
	undead := filepath.Join(dir, "routes", "undead-warlock.json")
	if err := os.WriteFile(undead, []byte("[]"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := routeFile(data, "Scourge", "WARLOCK", "H", false); got != undead {
		t.Fatalf("Scourge must use Undead route, got %s", got)
	}
	rogue := filepath.Join(dir, "routes", "orc-rogue.json")
	if err := os.Mkdir(rogue, 0o755); err != nil {
		t.Fatal(err)
	}
	if fileOK(rogue) || routeFile(data, "Orc", "Rogue", "Horde", false) != "" {
		t.Fatal("directory accepted as route file")
	}
	if !fileOK(undead) {
		t.Fatal("regular route rejected")
	}
}
