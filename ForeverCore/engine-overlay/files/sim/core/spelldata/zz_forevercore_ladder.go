// ForeverCore overlay: a character below level 60 only knows the ranks taught at or below its level.
//
// Not part of MythicSim; copied in by ForeverCore/engine-overlay. At level 60 every function here
// answers "no change", so upstream behaviour stays byte-identical.

package spelldata

import (
	"sync"

	"github.com/wowsims/forever/sim/core"
)

// A talent ladder is one spell copied per rank (same ID); its ranks are points, not trained ranks.
func foreverCoreTrainedLadder(ranks []*Spell) bool {
	if len(ranks) < 2 {
		return len(ranks) == 1
	}
	for _, s := range ranks[1:] {
		if s.ID == ranks[0].ID {
			return false
		}
	}
	return true
}

// SpellLevel 60 with MaxLevel 0 is the generator's "no SpellLevels row": the level is unknown, so the
// rank stays available rather than vanishing.
func foreverCoreRankKnown(s *Spell) bool {
	if known, constrained := core.ForeverCoreKnownRank(s.ID); constrained {
		return known && (!core.ForeverCoreLevelActive() || int32(s.SpellLevel) <= core.CharacterLevel)
	}
	if !core.ForeverCoreLevelActive() {
		return true
	}
	if s.SpellLevel == 60 && s.MaxLevel == 0 {
		return true
	}
	return int32(s.SpellLevel) <= core.CharacterLevel
}

// The highest rank the character has been taught. When no rank is taught yet the lowest rank is
// returned so registration stays intact; ForeverCore keeps such spells out of the rotation.
func foreverCoreHighest(ranks []*Spell) (*Spell, bool) {
	if !core.ForeverCoreRankSelectionActive() || len(ranks) == 0 || !foreverCoreTrainedLadder(ranks) {
		return nil, false
	}
	for i := len(ranks) - 1; i >= 0; i-- {
		if foreverCoreRankKnown(ranks[i]) {
			return ranks[i], true
		}
	}
	return ranks[0], true
}

// Whether Each should hand this rank to a registration loop.
func foreverCoreEachRank(ranks []*Spell, s *Spell) bool {
	if !core.ForeverCoreLevelActive() || !foreverCoreTrainedLadder(ranks) {
		return true
	}
	if s == ranks[0] {
		return true
	}
	return foreverCoreRankKnown(s)
}

// Rank families by spell name and class family, built once from the store.
func init() {
	var families map[int32][]int32
	var once sync.Once
	core.ForeverCoreRankFamily = func(spellID int32) []int32 {
		once.Do(func() {
			type key struct {
				name   string
				family uint32
			}
			groups := map[key][]*Spell{}
			for _, s := range All() {
				if s.RankNumber() <= 0 || s.ClassFlags.Family == 0 {
					continue
				}
				k := key{s.Name, uint32(s.ClassFlags.Family)}
				groups[k] = append(groups[k], s)
			}
			families = map[int32][]int32{}
			for _, ranks := range groups {
				ids := make([]int32, 0, len(ranks))
				for r := int32(60); r >= 1 && len(ids) < len(ranks); r-- {
					for _, s := range ranks {
						if s.RankNumber() == r {
							ids = append(ids, s.ID)
						}
					}
				}
				for _, s := range ranks {
					families[s.ID] = ids
				}
			}
		})
		return families[spellID]
	}
}

// Taught levels of class spell ranks; spells without a SpellLevels row stay unknown (0).
func init() {
	var levels map[int32]int32
	var once sync.Once
	core.ForeverCoreSpellLevel = func(spellID int32) int32 {
		once.Do(func() {
			levels = map[int32]int32{}
			for _, s := range All() {
				if s.ClassFlags.Family == 0 || s.RankNumber() <= 0 || (s.SpellLevel == 60 && s.MaxLevel == 0) {
					continue
				}
				levels[s.ID] = int32(s.SpellLevel)
			}
		})
		return levels[spellID]
	}
}

func init() {
	core.ForeverCoreClassSpell = func(id int32) bool {
		s := Find(id)
		return s != nil && s.ClassFlags.Family != 0
	}
}
