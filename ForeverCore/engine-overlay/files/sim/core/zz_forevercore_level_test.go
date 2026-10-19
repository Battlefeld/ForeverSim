// ForeverCore overlay tests. Not part of MythicSim.
package core

import (
	"math"
	"testing"

	"github.com/wowsims/forever/sim/core/stats"
)

// The level-60 row of the overlay data must equal upstream's own level-60 tables. A mismatch means
// upstream moved its base stats and ForeverCore's level data is stale: the pipeline stops there.
func TestForeverCoreLevel60RowMatchesUpstream(t *testing.T) {
	if ForeverCoreLevelActive() {
		t.Skip("runs only at level 60")
	}
	for class, rows := range foreverCoreBaseStatsByLevel {
		base, ok := ClassBaseStats[class]
		if !ok {
			continue
		}
		row, ok := rows[60]
		if !ok {
			t.Fatalf("%v: no level 60 row", class)
		}
		check := func(name string, got, want float64) {
			if math.Abs(got-want) > 1e-6 {
				t.Errorf("%v %s: overlay data %v, upstream %v", class, name, got, want)
			}
		}
		check("health", row.Health, base[stats.Health])
		check("agility", row.Agility, base[stats.Agility])
		check("strength", row.Strength, base[stats.Strength])
		check("intellect", row.Intellect, base[stats.Intellect])
		check("spirit", row.Spirit, base[stats.Spirit])
		check("stamina", row.Stamina, base[stats.Stamina])
		check("mana", row.Mana, ExtraClassBaseStats[class][stats.Mana])
		check("critPerAgility", row.CritPerAgility, CritPerAgiMaxLevel[class])
		check("critPerIntellect", row.CritPerIntellect, CritPerIntMaxLevel[class])
	}
}

func TestForeverCoreLevelDataComplete(t *testing.T) {
	for class, rows := range foreverCoreBaseStatsByLevel {
		for level := int32(ForeverCoreMinLevel); level <= 60; level++ {
			if _, ok := rows[level]; !ok {
				t.Errorf("%v: missing level %d", class, level)
			}
		}
	}
}

func TestForeverCoreRescaleAP(t *testing.T) {
	cases := []struct{ in, old, new, want float64 }{
		{160, 60, 20, 40},  // 3*L-20
		{100, 60, 20, 20},  // 2*L-20
		{-10, 60, 20, -10}, // constant stays
	}
	for _, c := range cases {
		if got := foreverCoreRescaleAP(c.in, c.old, c.new); got != c.want {
			t.Errorf("rescale(%v,%v->%v) = %v, want %v", c.in, c.old, c.new, got, c.want)
		}
	}
}

func TestForeverCoreUnitLevelSilentAt60(t *testing.T) {
	if ForeverCoreLevelActive() {
		t.Skip("runs only at level 60")
	}
	if _, ok := foreverCoreUnitLevel(CharacterLevel-1, 1, 2); ok {
		t.Fatal("overlay must not answer at level 60")
	}
}
