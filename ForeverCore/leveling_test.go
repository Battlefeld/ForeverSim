package main

import (
	"math"
	"testing"
)

func TestLevelingRating(t *testing.T) {
	p := map[string]any{"downtime": float64(10), "mobs": []any{
		map[string]any{"name": "klein", "health": float64(500), "xp": float64(100)},
		map[string]any{"name": "gross", "health": float64(2000), "xp": float64(500)},
	}}
	r, err := levelingRating(50, p)
	if err != nil {
		t.Fatal(err)
	}
	rows := r["rows"].([]any)
	// klein: 10s+10 = 20s -> 18000 xp/h; gross: 40s+10 = 50s -> 36000 xp/h
	if r["best"] != "gross" || math.Abs(num(rows[0].(map[string]any), "xpPerHour")-36000) > 1e-6 || math.Abs(num(rows[1].(map[string]any), "xpPerHour")-18000) > 1e-6 {
		t.Fatalf("unexpected rating %v", r)
	}
}

func TestLevelingRatingRejectsBadInput(t *testing.T) {
	good := []any{map[string]any{"health": float64(100), "xp": float64(10)}}
	for name, c := range map[string]struct {
		dps float64
		p   map[string]any
	}{
		"zero dps":   {0, map[string]any{"mobs": good}},
		"no mobs":    {10, map[string]any{}},
		"no health":  {10, map[string]any{"mobs": []any{map[string]any{"xp": float64(1)}}}},
		"neg xp":     {10, map[string]any{"mobs": []any{map[string]any{"health": float64(1), "xp": float64(-1)}}}},
		"neg pause":  {10, map[string]any{"mobs": good, "downtime": float64(-1)}},
		"inf health": {10, map[string]any{"mobs": []any{map[string]any{"health": math.Inf(1), "xp": float64(1)}}}},
	} {
		if _, err := levelingRating(c.dps, c.p); err == nil {
			t.Errorf("%s accepted", name)
		}
	}
	if r, err := levelingRating(10, map[string]any{"mobs": good, "downtime": float64(0)}); err != nil || r["downtime"] != float64(0) {
		t.Fatalf("explicit zero downtime not honoured: %v %v", r, err)
	}
}
