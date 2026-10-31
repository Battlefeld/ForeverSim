package main

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Test data in the shape of creature-families.json (the real file comes from the client table).
func familiesForTest() map[string]any {
	var f map[string]any
	_ = json.Unmarshal([]byte(`{"families":[
		{"id":1,"name":"Wolf","names":{"enUS":"Wolf","deDE":"Wolf"}},
		{"id":2,"name":"Cat","names":{"enUS":"Cat","deDE":"Katze"}},
		{"id":27,"name":"Wind Serpent","names":{"enUS":"Wind Serpent","deDE":"Windnatter"}},
		{"id":99,"name":"Fox","names":{"enUS":"Fox","deDE":"Fuchs"}},
		{"id":23,"name":"Imp","names":{"enUS":"Imp","deDE":"Wichtel"}},
		{"id":17,"name":"Succubus","names":{"enUS":"Succubus","deDE":"Sukkubus"}},
		{"id":29,"name":"Felguard","names":{"enUS":"Felguard","deDE":"Teufelswache"}}]}`), &f)
	return f
}

// A level 20 cat as the addon captures it: base 2.0 s, 25% happiness in the percent modifier.
func hunterSnapForTest() map[string]any {
	var s map[string]any
	_ = json.Unmarshal([]byte(`{"level":20,"petActive":true,"hunter":{
		"ammo":{"status":"ok","itemId":2512,"dps":2},
		"quiver":{"status":"ok","itemId":7278,"spellId":14824,"hastePct":10},
		"pet":{"status":"ok","family":"Katze","locale":"deDE","level":20,"speed":2,
			"stats":{"strength":40,"agility":35,"stamina":50,"intellect":20,"spirit":25},
			"attackPower":{"base":60,"pos":10,"neg":0},
			"damage":{"min":37.5,"max":50,"pos":0,"neg":0,"percent":1.25}}}}`), &s)
	return s
}

func TestHunterLiveMapping(t *testing.T) {
	m := manifestForTest(t)
	got, e := liveHunter(hunterSnapForTest(), m, familiesForTest(), 20)
	if e != nil {
		t.Fatal(e)
	}
	spec := child(m, "hunter")
	if got.options["petType"] != child(spec, "petTypes")["Cat"] {
		t.Fatalf("Katze not mapped to Cat: %v", got.options)
	}
	if num(got.options, "ammo") != num(spec, "ammoNone") || num(got.private, "ammoDps") != 2 {
		t.Fatalf("ammo: %v %v", got.options, got.private)
	}
	// Forever's quiver spell is not one of the engine's; the client's 10% decides.
	want10 := float64(-1)
	for _, raw := range array(spec, "quiver") {
		if row, _ := raw.(map[string]any); num(row, "hastePct") == 10 {
			want10 = num(row, "value")
		}
	}
	if want10 < 0 || num(got.options, "quiverBonus") != want10 {
		t.Fatalf("quiver: %v", got.options["quiverBonus"])
	}
	// 2.0 s is the engine's "Two" entry.
	for _, raw := range array(spec, "petAttackSpeeds") {
		row := raw.(map[string]any)
		if num(row, "seconds") == 2 && num(got.options, "petAttackSpeed") != num(row, "value") {
			t.Fatal("pet speed")
		}
	}
	// Character-sheet order: 37.5/1.25 - 0 - 0 - 70*2/14 = 20; 50/1.25 - 10 = 30.
	pet := child(got.private, "pet")
	if math.Abs(num(pet, "baseDamageMin")-20) > 1e-9 || math.Abs(num(pet, "baseDamageMax")-30) > 1e-9 || num(pet, "attackPower") != 70 {
		t.Fatalf("pet values: %v", pet)
	}
	if len(got.warnings) != 0 {
		t.Fatalf("unexpected warnings %v", got.warnings)
	}
}

// Forever can expose zero primary attributes but still provide authoritative combat-sheet AP.
func TestHunterLiveDirectAttackPowerWithoutPrimaryStats(t *testing.T) {
	m := manifestForTest(t)
	s := hunterSnapForTest()
	pet := child(child(s, "hunter"), "pet")
	pet["stats"] = map[string]any{"strength": float64(0), "agility": float64(0), "stamina": float64(0), "intellect": float64(0), "spirit": float64(0)}
	pet["attackPower"] = map[string]any{"base": float64(36), "pos": float64(8), "neg": float64(0)}
	got, e := liveHunter(s, m, familiesForTest(), 20)
	if e != nil {
		t.Fatalf("zero pet attributes should not block the sim: %v", e)
	}
	v := child(got.private, "pet")
	if num(v, "attackPower") != 44 || v["strength"] != nil {
		t.Fatalf("measured 44 AP not preserved or strength invented: %v", v)
	}
	delete(pet, "stats")
	if _, e := liveHunter(s, m, familiesForTest(), 20); e != nil {
		t.Fatalf("unavailable pet primary attributes should not block the sim: %v", e)
	}
}

func TestHunterFamilyResolution(t *testing.T) {
	f := familiesForTest()
	for _, c := range []struct {
		pet  map[string]any
		want string
	}{
		{map[string]any{"familyId": float64(27), "family": "irrelevant"}, "Wind Serpent"},
		{map[string]any{"family": "Windnatter", "locale": "deDE"}, "Wind Serpent"},
		{map[string]any{"family": "cat"}, "Cat"},
	} {
		if got, e := hunterFamilyName(c.pet, f); e != nil || got != c.want {
			t.Fatalf("%v: %q %v", c.pet, got, e)
		}
	}
	for _, bad := range []map[string]any{{"family": "Drache"}, {"familyId": float64(500)}, {"family": ""}} {
		if _, e := hunterFamilyName(bad, f); e == nil {
			t.Fatalf("accepted %v", bad)
		}
	}
}

func TestHunterLiveRefusesWhatItCannotRepresent(t *testing.T) {
	m := manifestForTest(t)
	f := familiesForTest()
	edit := func(fn func(h map[string]any)) map[string]any {
		s := hunterSnapForTest()
		fn(child(s, "hunter"))
		return s
	}
	for name, s := range map[string]map[string]any{
		"family the engine lacks": edit(func(h map[string]any) { child(h, "pet")["family"] = "Sukkubus" }),
		"hasted pet speed":        edit(func(h map[string]any) { child(h, "pet")["speed"] = 1.82 }),
		"protected pet":           edit(func(h map[string]any) { child(h, "pet")["status"] = "unreadable" }),
		"unreadable ammo":         edit(func(h map[string]any) { h["ammo"] = map[string]any{"status": "unreadable"} }),
		"unknown quiver haste": edit(func(h map[string]any) {
			h["quiver"] = map[string]any{"status": "ok", "spellId": float64(1), "hastePct": float64(9)}
		}),
		"missing pet AP": edit(func(h map[string]any) { delete(child(child(h, "pet"), "attackPower"), "base") }),
		"no hunter data":        {"petActive": true},
	} {
		if _, e := liveHunter(s, m, f, 20); e == nil {
			t.Errorf("%s accepted", name)
		}
	}
	old := cloneMap(m)
	old["liveHunter"] = false
	if _, e := liveHunter(hunterSnapForTest(), old, f, 20); e == nil {
		t.Error("engine without hunter overlay accepted")
	}
}

func TestHunterLiveWarnsInsteadOfHiding(t *testing.T) {
	m := manifestForTest(t)
	s := hunterSnapForTest()
	s["petActive"] = false
	child(s, "hunter")["ammo"] = map[string]any{"status": "none"}
	child(s, "hunter")["quiver"] = map[string]any{"status": "none"}
	got, e := liveHunter(s, m, familiesForTest(), 20)
	if e != nil {
		t.Fatal(e)
	}
	if got.options["petType"] != num(child(m, "hunter"), "petNone") || num(got.private, "ammoDps") != 0 || len(got.warnings) != 2 {
		t.Fatalf("%v %v %v", got.options, got.private, got.warnings)
	}
	s = hunterSnapForTest()
	child(child(s, "hunter"), "pet")["level"] = float64(18)
	if got, _ = liveHunter(s, m, familiesForTest(), 20); len(got.warnings) != 1 || !strings.Contains(got.warnings[0], "18") {
		t.Fatalf("pet below player level: %v", got.warnings)
	}
	// At 60 the measured pet is checked against the engine's own reference damage.
	s = hunterSnapForTest()
	child(child(s, "hunter"), "pet")["level"] = float64(60)
	if got, _ = liveHunter(s, m, familiesForTest(), 60); len(got.warnings) != 1 || !strings.Contains(got.warnings[0], "Referenzwert") {
		t.Fatalf("level 60 self-check: %v", got.warnings)
	}
}

func TestEngineEnvDoesNotLeakHunterFile(t *testing.T) {
	t.Setenv("FOREVERCORE_HUNTER", "foreign.json")
	for _, v := range engineEnv(20) {
		if strings.HasPrefix(v, "FOREVERCORE_HUNTER=") {
			t.Fatal("inherited hunter file reached the engine")
		}
	}
}

// Full path: live snapshot -> request -> real engine with the hunter overlay.
func TestActualEngineLiveHunterLevel20(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	m := manifestForTest(t)
	runtime := t.TempDir()
	if e := os.MkdirAll(filepath.Join(runtime, "ForeverCore"), 0o755); e != nil {
		t.Fatal(e)
	}
	b, _ := os.ReadFile("engine-data.json")
	fam, _ := json.Marshal(familiesForTest())
	if os.WriteFile(filepath.Join(runtime, "ForeverCore", "engine-data.json"), b, 0o600) != nil || os.WriteFile(filepath.Join(runtime, "ForeverCore", "creature-families.json"), fam, 0o600) != nil {
		t.Fatal("runtime files")
	}
	snap := hunterSnapForTest()
	for k, v := range map[string]any{"class": "HUNTER", "race": "Orc", "talents": []any{}, "talentSnapshotStatus": map[string]any{"state": "valid"},
		"spellbookStatus": map[string]any{"state": "valid"},
		// Auto Shot, Raptor Strike, Arcane Shot, Serpent Sting, Hunter's Mark, Aspect of the Hawk (rank 1).
		"spells":   []any{map[string]any{"id": float64(75)}, map[string]any{"id": float64(2973)}, map[string]any{"id": float64(3044)}, map[string]any{"id": float64(1978)}, map[string]any{"id": float64(1130)}, map[string]any{"id": float64(13165)}},
		"equipped": []any{map[string]any{"slot": "RangedSlot", "id": float64(18713)}}} {
		snap[k] = v
	}
	s := SimService{Config: Config{Engine: engine, EngineRevision: str(m, "engineRevision"), Runtime: runtime, Data: t.TempDir()}}
	run := func(snap map[string]any) (float64, map[string]any) {
		req, e := s.liveRequest(Job{State: map[string]any{"sim": snap}})
		if e != nil {
			t.Fatal(e)
		}
		child(req, "simOptions")["iterations"] = float64(30)
		result, e := s.once(context.Background(), req)
		if e != nil {
			t.Fatal(e)
		}
		return simDPS(result), req
	}
	dps, req := run(snap)
	if dps <= 0 || req[engineHunterKey] == nil {
		t.Fatalf("live hunter: dps %v", dps)
	}
	// Better ammunition must raise DPS through the live value alone.
	better := hunterSnapForTest()
	for k, v := range snap {
		if k != "hunter" {
			better[k] = v
		}
	}
	child(child(better, "hunter"), "ammo")["dps"] = float64(7.5)
	if more, _ := run(better); more <= dps {
		t.Fatalf("ammo DPS 7.5 gave %.2f, 2.0 gave %.2f", more, dps)
	}
}

// Missing table: the companion loads the client table itself and keeps it.
func TestCreatureFamiliesFetchedWhenMissing(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.URL.Query().Get("build") != "" {
			http.NotFound(w, r) // build not on the server: fall back to the newest export
			return
		}
		switch r.URL.Query().Get("locale") {
		case "enUS":
			_, _ = w.Write([]byte("\ufeffID,Name_lang,MinScale\n2,Cat,1\n27,Wind Serpent,1\n"))
		case "deDE":
			_, _ = w.Write([]byte("ID,Name_lang,MinScale\n2,Katze,1\n27,Windnatter,1\n"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	old := creatureFamilyURL
	creatureFamilyURL = srv.URL
	defer func() { creatureFamilyURL = old }()
	runtime := t.TempDir()
	f, e := loadCreatureFamilies(runtime, "1.60.1.70425", "deDE")
	if e != nil {
		t.Fatal(e)
	}
	if name, e := hunterFamilyName(map[string]any{"family": "Windnatter", "locale": "deDE"}, f); e != nil || name != "Wind Serpent" {
		t.Fatalf("%q %v", name, e)
	}
	before := calls
	if _, e = loadCreatureFamilies(runtime, "1.60.1.70425", "deDE"); e != nil || calls != before {
		t.Fatalf("stored table not reused (%d calls) %v", calls-before, e)
	}
	if _, e = loadCreatureFamilies(runtime, "1.60.1.70425", "frFR"); e == nil {
		t.Fatal("missing language accepted")
	}
	creatureFamilyURL = "http://127.0.0.1:1"
	if _, e = loadCreatureFamilies(t.TempDir(), "b", "enUS"); e == nil {
		t.Fatal("unreachable source accepted")
	}
}

// A runtime folder with this build's manifest and the family table fixture.
func runtimeForTest(t *testing.T) string {
	t.Helper()
	runtime := t.TempDir()
	if e := os.MkdirAll(filepath.Join(runtime, "ForeverCore"), 0o755); e != nil {
		t.Fatal(e)
	}
	b, _ := os.ReadFile("engine-data.json")
	fam, _ := json.Marshal(familiesForTest())
	if os.WriteFile(filepath.Join(runtime, "ForeverCore", "engine-data.json"), b, 0o600) != nil || os.WriteFile(filepath.Join(runtime, "ForeverCore", "creature-families.json"), fam, 0o600) != nil {
		t.Fatal("runtime files")
	}
	return runtime
}
