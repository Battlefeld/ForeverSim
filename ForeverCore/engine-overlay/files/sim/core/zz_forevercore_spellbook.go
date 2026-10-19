package core

import (
	"encoding/json"
	"fmt"
	"os"
)

// A nil book means an imported reference scenario. A live request always supplies a complete
// public player spellbook. Pets/procs are not player spellbook entries and are handled separately.
var foreverCoreKnownSpells map[int32]bool

// Filled by spelldata: activated item spells are not trained class spells.
var ForeverCoreClassSpell func(int32) bool

func init() {
	path := os.Getenv("FOREVERCORE_SPELLBOOK")
	if path == "" {
		return
	}
	b, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Errorf("FOREVERCORE_SPELLBOOK: %w", err))
	}
	var ids []int32
	if err = json.Unmarshal(b, &ids); err != nil || len(ids) == 0 {
		panic("FOREVERCORE_SPELLBOOK: complete nonempty spellbook required")
	}
	foreverCoreKnownSpells = make(map[int32]bool, len(ids))
	for _, id := range ids {
		if id < 1 {
			panic("FOREVERCORE_SPELLBOOK: invalid spell id")
		}
		foreverCoreKnownSpells[id] = true
	}
}

func ForeverCoreRankSelectionActive() bool {
	return foreverCoreLevelActive || foreverCoreKnownSpells != nil
}

// Only constrain a ladder to the live book when one of its ranks is explicitly present. This
// changes trained player ranks without confusing triggered spells or pet ladders with the player.
func ForeverCoreKnownRank(id int32) (bool, bool) {
	if foreverCoreKnownSpells == nil || ForeverCoreRankFamily == nil {
		return false, false
	}
	for _, rank := range ForeverCoreRankFamily(id) {
		if foreverCoreKnownSpells[rank] {
			return foreverCoreKnownSpells[id], true
		}
	}
	return false, false
}

func foreverCoreSpellbookBlocks(spell *Spell) bool {
	return foreverCoreKnownSpells != nil && spell.Unit.Type == PlayerUnit &&
		spell.ActionID.SpellID != 0 && ForeverCoreClassSpell != nil && ForeverCoreClassSpell(spell.ActionID.SpellID) && spell.Flags.Matches(SpellFlagAPL) &&
		!spell.Flags.Matches(SpellFlagPassiveSpell|SpellFlagProc) &&
		!foreverCoreKnownSpells[spell.ActionID.SpellID]
}
