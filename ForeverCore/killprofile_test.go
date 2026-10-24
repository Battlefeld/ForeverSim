package main

import (
	"math"
	"testing"
)

func TestKillProfile(t *testing.T) {
	s, _ := fakeService(t)
	got, e := s.killProfile(t.Context(), Job{Kind: "kill-profile", Payload: map[string]any{"class": "warlock", "race": "Orc", "fromLevel": float64(12), "toLevel": float64(13), "iterations": float64(50)}})
	if e != nil {
		t.Fatal(e)
	}
	r := got.(map[string]any)
	if r["schema"] != killProfileSchema || r["rotation"] != "affliction" || num(child(r, "classOptions"), "summon") != 2 {
		t.Fatalf("header %v", r)
	}
	levels := r["levels"].([]*killLevel)
	if len(levels) != 2 || levels[0].Level != 12 || levels[1].Level != 13 {
		t.Fatalf("levels %+v", levels)
	}
	l := levels[0]
	if l.Health <= 100 || l.Mana <= 100 || len(l.Targets["0"]) != len(killWindows) || len(l.Targets["2"]) != len(killWindows) {
		t.Fatalf("level 12 %+v", l)
	}
	// the stand-in engine deals its DPS for the window and spends 5 mana per second
	for _, p := range l.Targets["0"] {
		if p.Damage/p.Seconds < 1000 || math.Abs(p.ManaSpent-5*p.Seconds) > 1e-9 {
			t.Errorf("point %+v", p)
		}
	}
	for _, bad := range []map[string]any{{"class": "warlock"}, {"class": "warlock", "race": "Pandaren"}, {"class": "warlock", "race": "Orc", "fromLevel": float64(5)}} {
		if _, e := s.killProfile(t.Context(), Job{Kind: "kill-profile", Payload: bad}); e == nil {
			t.Errorf("%v accepted", bad)
		}
	}
}
