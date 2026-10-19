// ForeverCore overlay tests. Not part of MythicSim.
package warlock

import (
	"math"
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/core/stats"
)

func foreverCoreDemonSim(t *testing.T, summon proto.WarlockOptions_Summon) float64 {
	t.Helper()
	player := &proto.Player{
		Name: "fc", Class: proto.Class_ClassWarlock, Race: proto.Race_RaceOrc, TalentsString: AfflictionTalents,
		Equipment: &proto.EquipmentSpec{},
		Spec: &proto.Player_Warlock{Warlock: &proto.Warlock{Options: &proto.Warlock_Options{ClassOptions: &proto.WarlockOptions{
			Summon: summon, Armor: proto.WarlockOptions_DemonArmor, CurseOptions: proto.WarlockOptions_Elements}}}},
		Rotation: core.GetAplRotation("../../ui/specs/warlock/dps/apls", "affliction").Rotation,
	}
	raid := &proto.Raid{Parties: []*proto.Party{{Players: []*proto.Player{player}, Buffs: &proto.PartyBuffs{}}}, Buffs: &proto.RaidBuffs{}, Debuffs: &proto.Debuffs{}, NumActiveParties: 1}
	res := core.RunRaidSim(&proto.RaidSimRequest{Raid: raid, Encounter: core.MakeSingleTargetEncounter(0), SimOptions: &proto.SimOptions{Iterations: 40, RandomSeed: 3}})
	if res.Error != nil {
		t.Fatal(res.Error.Message)
	}
	total := 0.0
	for _, pet := range res.RaidMetrics.Parties[0].Players[0].Pets {
		total += pet.Dps.Avg
	}
	return total
}

func withForeverCoreDemon(t *testing.T, d *foreverCoreDemonData) {
	t.Helper()
	old := foreverCoreDemon
	foreverCoreDemon = d
	t.Cleanup(func() { foreverCoreDemon = old })
}

func TestForeverCoreDemonParse(t *testing.T) {
	good := `{"summon":1,"strength":20,"agility":15,"stamina":25,"intellect":60,"spirit":55,"mana":300,"spells":{"firebolt":{"min":13,"max":18,"cost":25}}}`
	if d, err := parseForeverCoreDemon([]byte(good)); err != nil || d.Spells["firebolt"].Max != 18 {
		t.Fatalf("valid file rejected: %v", err)
	}
	for _, bad := range []string{
		`{"strength":20}`,
		`{"summon":1,"spells":{"shadowBolt":{"min":1,"max":2}}}`,
		`{"summon":1,"spells":{"firebolt":{"min":9,"max":2}}}`,
		`{"summon":1,"meleeMin":5}`,
		`{"summon":1,"unknown":1}`,
	} {
		if _, err := parseForeverCoreDemon([]byte(bad)); err == nil {
			t.Errorf("accepted %s", bad)
		}
	}
}

func TestForeverCoreDemonInactiveKeepsUpstream(t *testing.T) {
	withForeverCoreDemon(t, nil)
	if foreverCorePetSpellCost("firebolt", 115) != 115 || foreverCorePetSpellFlatCost("lashOfPain", 160) != 160 {
		t.Fatal("cost changed without live data")
	}
	if foreverCoreWarlockPetMelee(proto.WarlockOptions_Succubus, [2]float64{95, 131}) != [2]float64{95, 131} {
		t.Fatal("melee changed without live data")
	}
}

// Upstream's own level 60 attributes through the live path give upstream's numbers; a level 20 imp
// with its rank 2 Firebolt is far weaker.
func TestForeverCoreLiveImp(t *testing.T) {
	withForeverCoreDemon(t, nil)
	upstream := foreverCoreDemonSim(t, proto.WarlockOptions_Imp)
	same := petBaseStats[proto.WarlockOptions_Imp]
	withForeverCoreDemon(t, &foreverCoreDemonData{Summon: int32(proto.WarlockOptions_Imp), Strength: same[stats.Strength], Agility: same[stats.Agility], Stamina: same[stats.Stamina],
		Intellect: same[stats.Intellect], Spirit: same[stats.Spirit], Mana: same[stats.Mana]})
	if got := foreverCoreDemonSim(t, proto.WarlockOptions_Imp); math.Abs(got-upstream) > 1e-6 {
		t.Fatalf("upstream attributes via live path: %.4f vs %.4f", got, upstream)
	}
	cost := 25.0
	withForeverCoreDemon(t, &foreverCoreDemonData{Summon: int32(proto.WarlockOptions_Imp), Strength: 20, Agility: 15, Stamina: 25, Intellect: 60, Spirit: 55, Mana: 300,
		Spells: map[string]foreverCoreDemonSpell{"firebolt": {Min: 11, Max: 15, Cost: &cost}}})
	if got := foreverCoreDemonSim(t, proto.WarlockOptions_Imp); !(got > 0 && got < upstream*0.6) {
		t.Fatalf("level 20 imp %.2f, level 60 imp %.2f", got, upstream)
	}
	// Live data for another demon leaves the active one alone.
	withForeverCoreDemon(t, &foreverCoreDemonData{Summon: int32(proto.WarlockOptions_Succubus), Strength: 1, Agility: 1, Stamina: 1, Intellect: 1, Spirit: 1, Mana: 1})
	if got := foreverCoreDemonSim(t, proto.WarlockOptions_Imp); math.Abs(got-upstream) > 1e-6 {
		t.Fatal("other demon's data reached the imp")
	}
}

func TestForeverCoreLiveSuccubusMelee(t *testing.T) {
	withForeverCoreDemon(t, nil)
	upstream := foreverCoreDemonSim(t, proto.WarlockOptions_Succubus)
	lo, hi := 12.0, 17.0
	withForeverCoreDemon(t, &foreverCoreDemonData{Summon: int32(proto.WarlockOptions_Succubus), Strength: 30, Agility: 25, Stamina: 40, Intellect: 30, Spirit: 30, Mana: 200,
		MeleeMin: &lo, MeleeMax: &hi, Spells: map[string]foreverCoreDemonSpell{"lashOfPain": {Min: 20, Max: 20}}})
	if got := foreverCoreDemonSim(t, proto.WarlockOptions_Succubus); !(got > 0 && got < upstream*0.5) {
		t.Fatalf("level 20 succubus %.2f, level 60 %.2f", got, upstream)
	}
}
