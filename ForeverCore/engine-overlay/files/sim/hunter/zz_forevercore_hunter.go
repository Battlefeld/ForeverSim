package hunter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"os"

	"github.com/wowsims/forever/sim/core/stats"
)

// Live hunter values measured by the addon in the client (ForeverCore passes them as a JSON file in
// FOREVERCORE_HUNTER). Without the variable nothing here changes upstream behaviour.
//
//	ammoDps: the equipped ammunition's damage per second as the client reports it. Upstream only
//	         knows the level 25+ ammo enum; leveling ammo has no enum value.
//	pet:     measured total pet attack power, optional non-strength attributes and
//	         base weapon damage derived from its character sheet at its current level.
type foreverCorePetData struct {
	AttackPower   float64 `json:"attackPower"`
	Agility       float64 `json:"agility"`
	Stamina       float64 `json:"stamina"`
	Intellect     float64 `json:"intellect"`
	Spirit        float64 `json:"spirit"`
	BaseDamageMin float64 `json:"baseDamageMin"`
	BaseDamageMax float64 `json:"baseDamageMax"`
}

type foreverCoreHunterData struct {
	AmmoDPS *float64            `json:"ammoDps"`
	Pet     *foreverCorePetData `json:"pet"`
}

var foreverCoreHunter = loadForeverCoreHunter(os.Getenv("FOREVERCORE_HUNTER"))

func loadForeverCoreHunter(path string) *foreverCoreHunterData {
	if path == "" {
		return nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Errorf("FOREVERCORE_HUNTER: %w", err))
	}
	data, err := parseForeverCoreHunter(b)
	if err != nil {
		panic(fmt.Errorf("FOREVERCORE_HUNTER: %w", err))
	}
	return data
}

func parseForeverCoreHunter(b []byte) (*foreverCoreHunterData, error) {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.DisallowUnknownFields()
	var data foreverCoreHunterData
	if err := dec.Decode(&data); err != nil {
		return nil, err
	}
	finite := func(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) && v >= 0 }
	if data.AmmoDPS != nil && !finite(*data.AmmoDPS) {
		return nil, fmt.Errorf("invalid ammoDps")
	}
	if p := data.Pet; p != nil {
		for _, v := range []float64{p.AttackPower, p.Agility, p.Stamina, p.Intellect, p.Spirit, p.BaseDamageMin, p.BaseDamageMax} {
			if !finite(v) {
				return nil, fmt.Errorf("invalid pet value")
			}
		}
		if p.AttackPower <= 0 {
			return nil, fmt.Errorf("invalid pet attack power")
		}
		if p.BaseDamageMax < p.BaseDamageMin || p.BaseDamageMax == 0 {
			return nil, fmt.Errorf("invalid pet damage range")
		}
	}
	return &data, nil
}

// Wraps the damage per second upstream credits the chosen ammunition with (arrows only).
func foreverCoreAmmoDPS(upstream float64) float64 {
	if foreverCoreHunter != nil && foreverCoreHunter.AmmoDPS != nil {
		return *foreverCoreHunter.AmmoDPS
	}
	return upstream
}

// Replace the upstream AP penalty with the measured total AP and suppress
// Strength -> AttackPower conversion so the client value is counted exactly once.
func foreverCorePetBaseStats(upstream stats.Stats) stats.Stats {
	if foreverCoreHunter == nil || foreverCoreHunter.Pet == nil {
		return upstream
	}
	p := foreverCoreHunter.Pet
	upstream[stats.Strength] = 0
	upstream[stats.AttackPower] = p.AttackPower
	upstream[stats.Agility] = p.Agility
	upstream[stats.Stamina] = p.Stamina
	upstream[stats.Intellect] = p.Intellect
	upstream[stats.Spirit] = p.Spirit
	return upstream
}

// Wraps upstream's level 60 weapon damage (already multiplied by the attack speed).
func foreverCorePetDamage(upstream float64, maximum bool) float64 {
	if foreverCoreHunter == nil || foreverCoreHunter.Pet == nil {
		return upstream
	}
	if maximum {
		return foreverCoreHunter.Pet.BaseDamageMax
	}
	return foreverCoreHunter.Pet.BaseDamageMin
}
