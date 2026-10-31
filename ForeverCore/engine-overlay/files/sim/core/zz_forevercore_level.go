// ForeverCore overlay: character level 10-59 on top of the upstream Engine engine.
//
// This file is not part of Engine. ForeverCore copies it into a clean upstream checkout
// (ForeverCore/engine-overlay). Without FOREVERCORE_LEVEL, or with level 60, nothing here changes
// any value: level 60 stays byte-identical to upstream, which the update pipeline checks.
//
// The file name starts with zz_ so its init runs after base_stats.go has built the level-60 tables.

package core

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"sync"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/core/stats"
)

// ForeverCoreMinLevel is the lowest level the overlay accepts.
const ForeverCoreMinLevel = 10

// foreverCoreLevelActive is true only while a level below 60 is in effect.
var foreverCoreLevelActive bool

// ForeverCoreLevelActive reports whether the overlay changed the character level.
func ForeverCoreLevelActive() bool { return foreverCoreLevelActive }

func init() {
	raw := os.Getenv("FOREVERCORE_LEVEL")
	if raw == "" {
		return
	}
	level, err := strconv.Atoi(raw)
	if err != nil {
		panic(fmt.Sprintf("FOREVERCORE_LEVEL=%q is not a number", raw))
	}
	if err := ForeverCoreApplyLevel(int32(level)); err != nil {
		panic(err)
	}
}

// ForeverCoreApplyLevel switches the engine to a character level before any simulation is built.
// It must run once per process, before the first raid is constructed.
func ForeverCoreApplyLevel(level int32) error {
	if level == 60 {
		return nil
	}
	if level < ForeverCoreMinLevel || level > 60 {
		return fmt.Errorf("FOREVERCORE_LEVEL %d outside %d-60", level, ForeverCoreMinLevel)
	}
	if foreverCoreLevelActive {
		return fmt.Errorf("FOREVERCORE_LEVEL already applied")
	}
	for class, row := range foreverCoreBaseStatsByLevel {
		if _, ok := ClassBaseStats[class]; !ok {
			continue
		}
		if _, ok := row[level]; !ok {
			return fmt.Errorf("no level %d base stats for %v", level, class)
		}
	}
	old := float64(CharacterLevel)
	CharacterLevel = level
	foreverCoreLevelActive = true

	for class, rows := range foreverCoreBaseStatsByLevel {
		row := rows[level]
		base, ok := ClassBaseStats[class]
		if !ok {
			continue
		}
		base[stats.Health] = row.Health
		base[stats.Agility] = row.Agility
		base[stats.Strength] = row.Strength
		base[stats.Intellect] = row.Intellect
		base[stats.Spirit] = row.Spirit
		base[stats.Stamina] = row.Stamina
		base[stats.AttackPower] = foreverCoreRescaleAP(base[stats.AttackPower], old, float64(level))
		base[stats.RangedAttackPower] = foreverCoreRescaleAP(base[stats.RangedAttackPower], old, float64(level))
		ClassBaseStats[class] = base

		extra := ExtraClassBaseStats[class]
		extra[stats.Mana] = row.Mana
		ExtraClassBaseStats[class] = extra

		CritPerAgiMaxLevel[class] = row.CritPerAgility
		CritPerIntMaxLevel[class] = row.CritPerIntellect
	}
	for class, races := range ClassRaceCapabilities {
		for _, race := range races {
			AddBaseStatsCombo(race, class)
		}
	}
	return nil
}

// Upstream writes level-based attack power as level*k - 20 (k = 3 or 2) and constants otherwise.
// Recognise those two shapes at the old level and re-evaluate them at the new one; keep any other
// value, so a future upstream formula is never silently rewritten.
func foreverCoreRescaleAP(value, oldLevel, newLevel float64) float64 {
	for _, k := range []float64{3, 2} {
		if math.Abs(value-(oldLevel*k-20)) < 1e-9 {
			return newLevel*k - 20
		}
	}
	return value
}

type foreverCoreLevelRow struct {
	Health, Mana                                  float64
	Agility, Strength, Intellect, Spirit, Stamina float64
	CritPerAgility, CritPerIntellect              float64
}

var _ = proto.Class_ClassUnknown

// ForeverCoreRankFamily answers every rank id of the spell a rank id belongs to, highest rank first.
// spelldata fills it in (core may not import spelldata).
var ForeverCoreRankFamily func(spellID int32) []int32

// foreverCoreRankFallback lets a rotation written for level 60 keep pressing a spell below 60: when it
// names a rank the character has not learnt, the highest rank it knows takes its place.
func foreverCoreRankFallback(unit *Unit, actionID ActionID) *Spell {
	if !ForeverCoreRankSelectionActive() || ForeverCoreRankFamily == nil || actionID.SpellID == 0 {
		return nil
	}
	for _, id := range ForeverCoreRankFamily(actionID.SpellID) {
		want := ActionID{SpellID: id, Tag: actionID.Tag}
		for _, s := range unit.Spellbook {
			if s.ActionID.SameAction(want) && s.Flags.Matches(SpellFlagAPL) && !foreverCoreUnlearned(s) {
				return s
			}
		}
		for _, s := range unit.Spellbook {
			// A proc or passive spell of the same name (the damage a seal deals, the effect a trap leaves) is no rank to press:
			// casting it uses no time.
			if s.ActionID.SameAction(want) && !foreverCoreUnlearned(s) && !s.Flags.Matches(SpellFlagProc|SpellFlagPassiveSpell) && foreverCoreConsumes(s) {
				return s
			}
		}
	}
	return nil
}

// ForeverCoreSpellLevel answers the level a class spell rank is taught at, or 0 when unknown.
// spelldata fills it in.
var ForeverCoreSpellLevel func(spellID int32) int32

// foreverCoreUnlearned keeps a rank the character cannot know yet from being cast. Upstream still
// registers it (its registration code expects the spell), but the rotation never presses it.
func foreverCoreUnlearned(spell *Spell) bool {
	if foreverCoreSpellbookBlocks(spell) {
		return true
	}
	if !foreverCoreLevelActive || ForeverCoreSpellLevel == nil || spell.ActionID.SpellID == 0 {
		return false
	}
	return ForeverCoreSpellLevel(spell.ActionID.SpellID) > CharacterLevel
}

// foreverCoreAuraFallback lets a rotation condition on a level-60 rank's aura ("Seal of Righteousness
// rank 9 has under 1 s left") read the aura of the rank the character actually cast. Without it the
// condition never sees the aura and the rotation recasts the spell every global cooldown.
func foreverCoreAuraFallback(at *auraTracker, actionID ActionID) *Aura {
	if !ForeverCoreRankSelectionActive() || ForeverCoreRankFamily == nil || actionID.SpellID == 0 {
		return nil
	}
	for _, aura := range at.auras {
		if aura.ActionID.SameAction(actionID) && foreverCoreAuraKnown(aura.ActionID.SpellID) {
			return aura
		}
	}
	for _, id := range ForeverCoreRankFamily(actionID.SpellID) {
		want := ActionID{SpellID: id, Tag: actionID.Tag}
		for _, aura := range at.auras {
			if aura.ActionID.SameAction(want) && foreverCoreAuraKnown(aura.ActionID.SpellID) {
				return aura
			}
		}
	}
	return nil
}

func foreverCoreAuraKnown(id int32) bool {
	if known, constrained := ForeverCoreKnownRank(id); constrained && !known {
		return false
	}
	return !foreverCoreLevelActive || ForeverCoreSpellLevel == nil || ForeverCoreSpellLevel(id) <= CharacterLevel
}

// The spell ids the rank substitution handed out in place of a rank the character has not been taught.
var foreverCoreSubstituted sync.Map

// ForeverCoreNoteSubstituted records that a spell id stands in for a rank that is not known yet.
func ForeverCoreNoteSubstituted(id int32) { foreverCoreSubstituted.Store(id, true) }

// foreverCoreRegistered answers the spell already in the book under the same action id when that id is a stand-in rank.
// Two fixed ranks (Shadow Bolt rank 9 and 10) both fall back to the one rank the character has been taught; the second
// registration must not create a duplicate, so it gets the first one back. Any other id is registered as upstream says
// (a class may register two spells under one id on purpose).
func foreverCoreRegistered(unit *Unit, id ActionID) *Spell {
	if !ForeverCoreRankSelectionActive() || id.SpellID == 0 {
		return nil
	}
	if _, standIn := foreverCoreSubstituted.Load(id.SpellID); !standIn {
		return nil
	}
	for _, s := range unit.Spellbook {
		if s.ActionID == id {
			return s
		}
	}
	return nil
}

// foreverCoreConsumes is whether casting the spell uses anything: a global cooldown, a cast time, a cooldown or a cost. A
// spell that uses nothing (a helper row of the same name) can be "cast" again and again at the same instant, so the
// rotation would never move on.
func foreverCoreConsumes(s *Spell) bool {
	return s.Cost != nil || s.DefaultCast.GCD > 0 || s.DefaultCast.CastTime > 0 || s.CD.Timer != nil || s.SharedCD.Timer != nil
}
