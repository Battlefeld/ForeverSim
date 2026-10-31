package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
)

// Character level for the engine. The engine reads the request as protojson and would not know a level field, so
// the level travels in a ForeverCore-only key and reaches the engine as FOREVERCORE_LEVEL, which the
// level overlay (engine-overlay/) reads. Level 60 never sets the variable: the engine then runs
// exactly as upstream.
const (
	engineLevelKey          = "foreverCoreLevel"
	engineArmorEstimatedKey = "foreverCoreTargetArmorEstimated"
	minEngineLevel          = 10
	minPlayableLevel        = 5 // from level 5 on a character can be calculated (approximated up to level 9)
)

func engineLevel(req map[string]any) int {
	if v, ok := req[engineLevelKey]; ok {
		if f, ok := v.(float64); ok && f > 0 {
			return int(f)
		}
	}
	return 60
}

// The request as the engine sees it: without ForeverCore's own keys.
func engineRequest(req map[string]any) map[string]any {
	out := make(map[string]any, len(req))
	for k, v := range req {
		if strings.HasPrefix(k, "foreverCore") {
			continue
		}
		out[k] = v
	}
	return out
}

func engineEnv(level int) []string {
	env := make([]string, 0, len(os.Environ())+2)
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "FOREVERCORE_LEVEL=") && !strings.HasPrefix(kv, "FOREVERCORE_SPELLBOOK=") && !strings.HasPrefix(kv, "FOREVERCORE_HUNTER=") && !strings.HasPrefix(kv, "FOREVERCORE_WARLOCK=") && !strings.HasPrefix(kv, "FOREVERCORE_STRICT=") {
			env = append(env, kv)
		}
	}
	env = append(env, "FOREVERCORE_STRICT=1") // the engine refuses a request field it does not know
	if level != 60 {
		env = append(env, "FOREVERCORE_LEVEL="+strconv.Itoa(level))
	}
	return env
}

// manifestHasLevels: the installed engine was built with the level overlay.
func manifestHasLevels(manifest map[string]any) bool {
	r := array(manifest, "levelRange")
	if len(r) != 2 {
		return false
	}
	low, ok := r[0].(float64)
	high, highOK := r[1].(float64)
	return ok && highOK && low <= minEngineLevel && high >= 60
}

func levelUnsupported(manifest map[string]any, level int) error {
	if level == 60 {
		return nil
	}
	if level < minEngineLevel || level > 60 {
		return fmt.Errorf("ENGINE_LEVEL_UNSUPPORTED: Level %d liegt ausserhalb 10-60", level)
	}
	if manifest == nil || !manifestHasLevels(manifest) {
		return fmt.Errorf("ENGINE_LEVEL_UNSUPPORTED: Die installierte Engine hat kein Level-Overlay. ForeverCore mit der aktuellen Engine neu installieren.")
	}
	return nil
}

// defaultTarget picks the reference target for a character level.
//
// payload.targetLevel and payload.targetArmor win. Otherwise the target follows the content bands
// of the SIM goals: quest mobs at the character's level up to 30, dungeon bosses two levels above
// from 31 to 49, raid bosses three above from 50; level 60 keeps upstream's 63 with 3731 armor.
// Below 60 there is no measured armor table yet, so the boss armor is scaled by level and the
// request is marked as estimated; the mob data set replaces this.
func defaultTarget(level int, payload map[string]any) (int, float64, bool) {
	target := level + 3
	switch {
	case level <= 30:
		target = level
	case level < 50:
		target = level + 2
	}
	if v := int(num(payload, "targetLevel")); v > 0 {
		target = v
	}
	if a := num(payload, "targetArmor"); a >= 0 && payload["targetArmor"] != nil {
		return target, a, false
	}
	if level == 60 && target == 63 {
		return target, 3731, false
	}
	return target, 3731 * float64(target) / 63, true
}

func validateEngineLevel(req, manifest map[string]any, requireManifest bool) error {
	if raw, exists := req[engineLevelKey]; exists {
		v, ok := raw.(float64)
		if !ok || math.IsNaN(v) || math.IsInf(v, 0) || v != math.Trunc(v) || v < 10 || v > 60 {
			return fmt.Errorf("ENGINE_LEVEL_UNSUPPORTED: ganzzahliges Level 10-60 erforderlich")
		}
	}
	level := engineLevel(req)
	if requireManifest {
		return levelUnsupported(manifest, level)
	}
	return nil
}
func fileSHA256(path string) (string, error) {
	f, e := os.Open(path)
	if e != nil {
		return "", e
	}
	defer f.Close()
	h := sha256.New()
	if _, e = io.Copy(h, f); e != nil {
		return "", e
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
