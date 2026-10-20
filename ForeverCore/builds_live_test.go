package main

import (
	"os"
	"testing"
)

func TestShippedPresetsContainLegalBuildsForEveryClass(t *testing.T) {
	s, m := fakeService(t)
	for class := range child(m, "classes") {
		t.Run(class, func(t *testing.T) {
			result, e := s.presetsFor(t.Context(), Job{Payload: map[string]any{"class": class}})
			if e != nil {
				t.Fatal(e)
			}
			legal := 0
			for _, raw := range array(result.(map[string]any), "talents") {
				if raw.(map[string]any)["valid"] == true {
					legal++
				}
			}
			if legal == 0 {
				t.Fatalf("no legal preset for %s", class)
			}
		})
	}
}

func TestBuildJobsAgainstActualEngine(t *testing.T) {
	engine := os.Getenv("FC_TEST_ENGINE")
	if engine == "" {
		t.Skip("FC_TEST_ENGINE not set")
	}
	s, m := fakeService(t)
	s.Config.Engine = engine
	state := map[string]any{"sim": mageSnapshot(t, m, fireTalents)}
	result, e := s.compareBuilds(t.Context(), Job{State: state, Payload: map[string]any{
		"builds":     []any{map[string]any{"id": "live"}, map[string]any{"id": "copy", "talentsString": fireTalents}},
		"iterations": 50.0, "screenIterations": 50.0, "priority": true,
	}})
	if e != nil {
		t.Fatal(e)
	}
	rows := array(result.(map[string]any), "builds")
	a, b := rows[0].(map[string]any), rows[1].(map[string]any)
	if a["error"] != nil || b["error"] != nil || num(a, "dps") <= 0 || num(a, "dps") != num(b, "dps") {
		t.Fatalf("identical builds must agree in the actual engine: %v / %v", a, b)
	}
	detail, e := s.buildDetail(t.Context(), Job{State: state, Payload: map[string]any{"build": map[string]any{"rotation": a["rotation"]}, "curve": true}})
	if e != nil {
		t.Fatal(e)
	}
	d := detail.(map[string]any)
	if num(d, "dps") <= 0 || len(array(d, "priority")) == 0 || len(array(d, "breakdown")) == 0 || len(array(d, "curve")) != len(curveSeconds) {
		t.Fatalf("incomplete actual engine detail: %v", d)
	}
}

func TestDefaultWeightsIncludePhysicalStats(t *testing.T) {
	s, m := fakeService(t)
	result, e := s.Run(t.Context(), Job{Kind: "weights", State: map[string]any{"sim": mageSnapshot(t, m, fireTalents)}})
	if e != nil {
		t.Fatal(e)
	}
	found := map[string]bool{}
	for _, raw := range array(result.(map[string]any), "rows") {
		found[str(raw.(map[string]any), "key")] = true
	}
	for _, key := range []string{"StatRangedAttackPower", "StatFeralAttackPower", "StatMeleeHitRating", "StatMeleeCritRating", "StatMeleeHasteRating"} {
		if !found[key] {
			t.Fatalf("missing physical weight: %s", key)
		}
	}
}
