package core

import "testing"

func TestForeverCoreLiveSpellbookDoesNotBlockPetsOrProcs(t *testing.T) {
	oldClass := ForeverCoreClassSpell
	defer func() { ForeverCoreClassSpell = oldClass }()
	ForeverCoreClassSpell = func(int32) bool { return true }
	old := foreverCoreKnownSpells
	defer func() { foreverCoreKnownSpells = old }()
	foreverCoreKnownSpells = map[int32]bool{1: true}
	player := &Unit{Type: PlayerUnit}
	pet := &Unit{Type: PetUnit}
	for _, tc := range []struct {
		unit    *Unit
		flags   SpellFlag
		id      int32
		blocked bool
	}{
		{player, SpellFlagAPL, 2, true}, {player, SpellFlagAPL, 1, false},
		{pet, SpellFlagAPL, 2, false}, {player, SpellFlagAPL | SpellFlagPassiveSpell, 2, false},
		{player, SpellFlagAPL | SpellFlagProc, 2, false},
	} {
		spell := &Spell{Unit: tc.unit, Flags: tc.flags, ActionID: ActionID{SpellID: tc.id}}
		if foreverCoreSpellbookBlocks(spell) != tc.blocked {
			t.Fatalf("unexpected availability: %+v", tc)
		}
	}
}

func TestForeverCoreRegisteredUntrainedRankFallsBack(t *testing.T) {
	oldClass := ForeverCoreClassSpell
	defer func() { ForeverCoreClassSpell = oldClass }()
	ForeverCoreClassSpell = func(int32) bool { return true }
	oldBook, oldFamily := foreverCoreKnownSpells, ForeverCoreRankFamily
	defer func() { foreverCoreKnownSpells = oldBook; ForeverCoreRankFamily = oldFamily }()
	foreverCoreKnownSpells = map[int32]bool{1: true}
	ForeverCoreRankFamily = func(int32) []int32 { return []int32{2, 1} }
	unit := &Unit{Type: PlayerUnit}
	low := &Spell{Unit: unit, Flags: SpellFlagAPL, ActionID: ActionID{SpellID: 1}}
	high := &Spell{Unit: unit, Flags: SpellFlagAPL, ActionID: ActionID{SpellID: 2}}
	unit.Spellbook = []*Spell{high, low}
	if got := foreverCoreRankFallback(unit, ActionID{SpellID: 2}); got != low {
		t.Fatal("untrained registered rank selected")
	}
}

func TestForeverCoreLiveBookDoesNotBlockItemCooldowns(t *testing.T) {
	oldBook, oldClass := foreverCoreKnownSpells, ForeverCoreClassSpell
	defer func() { foreverCoreKnownSpells = oldBook; ForeverCoreClassSpell = oldClass }()
	foreverCoreKnownSpells = map[int32]bool{1: true}
	ForeverCoreClassSpell = func(int32) bool { return false }
	spell := &Spell{Unit: &Unit{Type: PlayerUnit}, Flags: SpellFlagAPL, ActionID: ActionID{SpellID: 999}}
	if foreverCoreSpellbookBlocks(spell) {
		t.Fatal("item cooldown requires a player spellbook entry")
	}
}
