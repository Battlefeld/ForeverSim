package warlock

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"os"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/core/stats"
)

// Live demon values measured by the addon in the client (ForeverCore passes them as a JSON file in
// FOREVERCORE_WARLOCK). Upstream's demon attributes, melee damage and Firebolt/Lash of Pain rows are
// level 60 values; below 60 the active demon gets what the client shows for it. Without the
// variable nothing here changes upstream behaviour.
type foreverCoreDemonSpell struct {
	Min  float64  `json:"min"`
	Max  float64  `json:"max"`
	Cost *float64 `json:"cost"`
}

type foreverCoreDemonData struct {
	Summon    int32    `json:"summon"`
	Strength  float64  `json:"strength"`
	Agility   float64  `json:"agility"`
	Stamina   float64  `json:"stamina"`
	Intellect float64  `json:"intellect"`
	Spirit    float64  `json:"spirit"`
	Mana      float64  `json:"mana"`
	MeleeMin  *float64 `json:"meleeMin"`
	MeleeMax  *float64 `json:"meleeMax"`

	Spells map[string]foreverCoreDemonSpell `json:"spells"`
}

var foreverCoreDemon = loadForeverCoreDemon(os.Getenv("FOREVERCORE_WARLOCK"))

func loadForeverCoreDemon(path string) *foreverCoreDemonData {
	if path == "" {
		return nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Errorf("FOREVERCORE_WARLOCK: %w", err))
	}
	d, err := parseForeverCoreDemon(b)
	if err != nil {
		panic(fmt.Errorf("FOREVERCORE_WARLOCK: %w", err))
	}
	return d
}

func parseForeverCoreDemon(b []byte) (*foreverCoreDemonData, error) {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.DisallowUnknownFields()
	var d foreverCoreDemonData
	if err := dec.Decode(&d); err != nil {
		return nil, err
	}
	ok := func(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) && v >= 0 }
	if d.Summon < 1 {
		return nil, fmt.Errorf("summon missing")
	}
	for _, v := range []float64{d.Strength, d.Agility, d.Stamina, d.Intellect, d.Spirit, d.Mana} {
		if !ok(v) {
			return nil, fmt.Errorf("invalid demon attribute")
		}
	}
	if (d.MeleeMin == nil) != (d.MeleeMax == nil) || (d.MeleeMin != nil && (!ok(*d.MeleeMin) || *d.MeleeMax < *d.MeleeMin || *d.MeleeMax == 0)) {
		return nil, fmt.Errorf("invalid demon melee damage")
	}
	for name, s := range d.Spells {
		if name != "firebolt" && name != "lashOfPain" {
			return nil, fmt.Errorf("unknown demon spell %q", name)
		}
		if !ok(s.Min) || s.Max < s.Min || s.Max == 0 || (s.Cost != nil && !ok(*s.Cost)) {
			return nil, fmt.Errorf("invalid demon spell %q", name)
		}
	}
	return &d, nil
}

func foreverCoreDemonActive(summon proto.WarlockOptions_Summon) *foreverCoreDemonData {
	if foreverCoreDemon == nil || foreverCoreDemon.Summon != int32(summon) {
		return nil
	}
	return foreverCoreDemon
}

// Wraps upstream's level 60 attributes for the demon the live data describes.
func foreverCoreWarlockPetStats(summon proto.WarlockOptions_Summon, upstream stats.Stats) stats.Stats {
	d := foreverCoreDemonActive(summon)
	if d == nil {
		return upstream
	}
	upstream[stats.Strength] = d.Strength
	upstream[stats.Agility] = d.Agility
	upstream[stats.Stamina] = d.Stamina
	upstream[stats.Intellect] = d.Intellect
	upstream[stats.Spirit] = d.Spirit
	upstream[stats.Mana] = d.Mana
	return upstream
}

// Wraps upstream's level 60 melee damage.
func foreverCoreWarlockPetMelee(summon proto.WarlockOptions_Summon, upstream [2]float64) [2]float64 {
	d := foreverCoreDemonActive(summon)
	if d == nil || d.MeleeMin == nil {
		return upstream
	}
	return [2]float64{*d.MeleeMin, *d.MeleeMax}
}

// Wraps upstream's Firebolt rank 7 / Lash of Pain rank 6 damage with the live rank's range.
func foreverCorePetSpellDamage(sim *core.Simulation, spell string, upstream float64) float64 {
	if foreverCoreDemon == nil {
		return upstream
	}
	s, ok := foreverCoreDemon.Spells[spell]
	if !ok {
		return upstream
	}
	return sim.Roll(s.Min, s.Max)
}

func foreverCorePetSpellCost(spell string, upstream float64) float64 {
	if foreverCoreDemon == nil {
		return upstream
	}
	if s, ok := foreverCoreDemon.Spells[spell]; ok && s.Cost != nil {
		return *s.Cost
	}
	return upstream
}

func foreverCorePetSpellFlatCost(spell string, upstream int32) int32 {
	v := foreverCorePetSpellCost(spell, float64(upstream))
	if v < 1 {
		return upstream
	}
	return int32(math.Round(v))
}
