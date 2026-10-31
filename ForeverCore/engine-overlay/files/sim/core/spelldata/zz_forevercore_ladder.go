// ForeverCore overlay: a character below level 60 only knows the ranks taught at or below its level.
//
// Not part of Engine; copied in by ForeverCore/engine-overlay. At level 60 every function here
// answers "no change", so upstream behaviour stays byte-identical.

package spelldata

import (
	"sync"

	"github.com/wowsims/forever/sim/core"
)

// Whether the ladder is one spell trained in ranks. A talent ladder is one spell copied per rank (same ID): its ranks are
// points. A ladder of different spells (Demonic Sacrifice's effect of each demon, the marks of Light's Vigil) is no
// ladder of ranks either: the ranks of a spell all carry its name and count up.
func foreverCoreTrainedLadder(ranks []*Spell) bool {
	if len(ranks) < 2 {
		return len(ranks) == 1
	}
	previous := ranks[0].RankNumber()
	if previous <= 0 {
		return false
	}
	for _, s := range ranks[1:] {
		if s.ID == ranks[0].ID || s.Name != ranks[0].Name || s.RankNumber() <= previous {
			return false
		}
		previous = s.RankNumber()
	}
	return true
}

// A rank is known once the character's level has reached the level it is taught at. A rank taught at 60 (the last rank
// of most ladders, Backstab rank 8) is known at 60 only: the client data has no "level unknown" case any more.
func foreverCoreRankKnown(s *Spell) bool {
	if known, constrained := core.ForeverCoreKnownRank(s.ID); constrained {
		return known && (!core.ForeverCoreLevelActive() || int32(s.SpellLevel) <= core.CharacterLevel)
	}
	if !core.ForeverCoreLevelActive() {
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

// Rank(n) below 60 when the character has not been taught rank n: the highest rank below it that it has, so a class
// that registers one fixed rank (Frostbolt rank 10) still casts what it knows.
func foreverCoreRankAtMost(ranks []*Spell, n int32) (*Spell, bool) {
	if !core.ForeverCoreRankSelectionActive() || n <= 0 || int(n) > len(ranks) || !foreverCoreTrainedLadder(ranks) || foreverCoreRankKnown(ranks[n-1]) {
		return nil, false
	}
	for i := int(n) - 2; i >= 0; i-- {
		if foreverCoreRankKnown(ranks[i]) {
			core.ForeverCoreNoteSubstituted(ranks[i].ID)
			return ranks[i], true
		}
	}
	core.ForeverCoreNoteSubstituted(ranks[0].ID)
	return ranks[0], true
}

// ByID below 60 when the character has not been taught that rank: the highest rank below it that it has (see
// foreverCoreRankAtMost). A class that names ranks by id (Shadow Bolt rank 9 and 10) still gets something it can cast.
func foreverCoreByIDAtMost(ranks []*Spell, id int32) (*Spell, bool) {
	for i, s := range ranks {
		if s.ID == id {
			return foreverCoreRankAtMost(ranks, int32(i+1))
		}
	}
	return nil, false
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
				if s.ClassFlags.Family == 0 || s.RankNumber() <= 0 {
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

// The rank at this position as the ladder holds it, with no substitution for a rank the character has not been taught:
// a lookup of a rank by its spell id walks these.
func (l Ladder) RankExact(n int32) *Spell {
	if n <= 0 || int(n) > len(l.ranks) {
		return Nil
	}
	return l.ranks[n-1]
}

// ForeverCoreAllRanks is true while the rank selection is on (a level below 60 or a live spellbook): a class that
// registers only the ranks taught at or after some level (the shaman's damage spells, from 44) must register every rank
// the character has been taught.
func ForeverCoreAllRanks() bool { return core.ForeverCoreRankSelectionActive() }
