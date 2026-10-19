package main

import (
	"strings"
	"testing"
)

func TestEngineRequestDropsForeverCoreKeys(t *testing.T) {
	req := map[string]any{"raid": 1, engineLevelKey: float64(30), engineArmorEstimatedKey: true}
	out := engineRequest(req)
	if len(out) != 1 || out["raid"] != 1 {
		t.Fatalf("engine request %v", out)
	}
	if engineLevel(req) != 30 || engineLevel(out) != 60 {
		t.Fatal("level not read from the private key")
	}
}

func TestEngineEnvOnlyBelow60(t *testing.T) {
	has := func(env []string) bool {
		for _, kv := range env {
			if strings.HasPrefix(kv, "FOREVERCORE_LEVEL=") {
				return true
			}
		}
		return false
	}
	t.Setenv("FOREVERCORE_LEVEL", "12")
	if has(engineEnv(60)) {
		t.Fatal("level 60 must run the engine as upstream")
	}
	env := engineEnv(35)
	if !has(env) || env[len(env)-1] != "FOREVERCORE_LEVEL=35" {
		t.Fatalf("level 35 env %v", env[len(env)-1])
	}
}

func TestLevelNeedsOverlayEngine(t *testing.T) {
	if levelUnsupported(map[string]any{}, 30) == nil {
		t.Fatal("engine without overlay accepted level 30")
	}
	if levelUnsupported(map[string]any{"levelRange": []any{float64(10), float64(60)}}, 30) != nil {
		t.Fatal("overlay engine rejected level 30")
	}
	if levelUnsupported(map[string]any{"levelRange": []any{float64(10), float64(60)}}, 9) == nil {
		t.Fatal("level 9 accepted")
	}
	if levelUnsupported(nil, 60) != nil {
		t.Fatal("level 60 must always work")
	}
}

func TestDefaultTargetBands(t *testing.T) {
	cases := []struct{ level, target int }{{20, 20}, {30, 30}, {40, 42}, {55, 58}, {60, 63}}
	for _, c := range cases {
		got, armor, est := defaultTarget(c.level, nil)
		if got != c.target {
			t.Errorf("level %d: target %d, want %d", c.level, got, c.target)
		}
		if c.level == 60 && (armor != 3731 || est) {
			t.Errorf("level 60 target must stay upstream's 3731 armor")
		}
		if c.level < 60 && !est {
			t.Errorf("level %d armor must be marked estimated", c.level)
		}
	}
	if lv, armor, est := defaultTarget(25, map[string]any{"targetLevel": float64(27), "targetArmor": float64(900)}); lv != 27 || armor != 900 || est {
		t.Fatal("payload target not honoured")
	}
}
