// ForeverCore overlay tests. Not part of Engine.
package hunter

import (
	"math"
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/core/stats"
	googleProto "google.golang.org/protobuf/proto"
)

func foreverCoreHunterSim(t *testing.T, ammo proto.HunterOptions_Ammo) (playerDPS, petDPS float64) {
	t.Helper()
	spec := &proto.Player_Hunter{Hunter: googleProto.Clone(DefaultOptions.Hunter).(*proto.Hunter)}
	opts := spec.Hunter.Options.ClassOptions
	opts.Ammo, opts.PetType, opts.PetAttackSpeed, opts.PetUptime = ammo, proto.HunterOptions_Cat, proto.HunterOptions_FasterAttackIII, 1
	player := &proto.Player{
		Name: "fc", Class: proto.Class_ClassHunter, Race: proto.Race_RaceOrc, TalentsString: DefaultMMTalents,
		Equipment: core.GetGearSet("../../ui/specs/hunter/dps/gear_sets", "p1").GearSet, DistanceFromTarget: 30,
		Spec:     spec,
		Rotation: core.GetAplRotation("../../ui/specs/hunter/dps/apls", "default").Rotation,
	}
	raid := &proto.Raid{Parties: []*proto.Party{{Players: []*proto.Player{player}, Buffs: &proto.PartyBuffs{}}}, Buffs: &proto.RaidBuffs{}, Debuffs: &proto.Debuffs{}, NumActiveParties: 1}
	res := core.RunRaidSim(&proto.RaidSimRequest{Raid: raid, Encounter: core.MakeSingleTargetEncounter(0), SimOptions: &proto.SimOptions{Iterations: 50, RandomSeed: 7}})
	if res.Error != nil {
		t.Fatal(res.Error.Message)
	}
	p := res.RaidMetrics.Parties[0].Players[0]
	for _, pet := range p.Pets {
		petDPS += pet.Dps.Avg
	}
	return p.Dps.Avg, petDPS
}

func withForeverCoreHunter(t *testing.T, data *foreverCoreHunterData) {
	t.Helper()
	old := foreverCoreHunter
	foreverCoreHunter = data
	t.Cleanup(func() { foreverCoreHunter = old })
}

func TestForeverCoreHunterParse(t *testing.T) {
	good := `{"ammoDps":4.5,"pet":{"attackPower":44,"baseDamageMin":10,"baseDamageMax":14}}`
	if d, err := parseForeverCoreHunter([]byte(good)); err != nil || *d.AmmoDPS != 4.5 || d.Pet.BaseDamageMax != 14 {
		t.Fatalf("valid file rejected: %v", err)
	}
	for _, bad := range []string{
		`{"ammoDps":-1}`,
		`{"ammo":4.5}`,
		`{"pet":{"attackPower":44,"baseDamageMin":14,"baseDamageMax":10}}`,
		`{"pet":{"attackPower":44,"baseDamageMin":0,"baseDamageMax":0}}`,
		`{"pet":{"baseDamageMin":10,"baseDamageMax":14}}`,
		`{"pet":{"attackPower":-1,"baseDamageMin":10,"baseDamageMax":14}}`,
		`{"pet":{"attackPower":44,"strength":99,"baseDamageMin":10,"baseDamageMax":14}}`,
		`not json`,
	} {
		if _, err := parseForeverCoreHunter([]byte(bad)); err == nil {
			t.Errorf("accepted %s", bad)
		}
	}
}

// Without live data the overlay must not change a single number.
func TestForeverCoreHunterInactiveKeepsUpstream(t *testing.T) {
	withForeverCoreHunter(t, nil)
	if foreverCorePetDamage(36.34, false) != 36.34 || foreverCorePetDamage(55.32, true) != 55.32 {
		t.Fatal("pet damage changed without live data")
	}
	if foreverCoreAmmoDPS(17.5) != 17.5 {
		t.Fatal("ammo changed without live data")
	}
}

// Live ammunition replaces the enum's value: leveling ammo with AmmoNone still adds its DPS.
func TestForeverCoreHunterLiveAmmo(t *testing.T) {
	withForeverCoreHunter(t, nil)
	none, _ := foreverCoreHunterSim(t, proto.HunterOptions_AmmoNone)
	thorium, _ := foreverCoreHunterSim(t, proto.HunterOptions_ThoriumHeadedArrow)
	dps := 17.5
	withForeverCoreHunter(t, &foreverCoreHunterData{AmmoDPS: &dps})
	live, _ := foreverCoreHunterSim(t, proto.HunterOptions_AmmoNone)
	if math.Abs(live-thorium) > 1e-6 {
		t.Fatalf("live 17.5 ammo DPS %.4f, Thorium enum %.4f", live, thorium)
	}
	small := 2.0
	withForeverCoreHunter(t, &foreverCoreHunterData{AmmoDPS: &small})
	rough, _ := foreverCoreHunterSim(t, proto.HunterOptions_AmmoNone)
	if !(none < rough && rough < thorium) {
		t.Fatalf("ammo order wrong: none %.2f rough %.2f thorium %.2f", none, rough, thorium)
	}
}

// The live sheet total AP replaces upstream's -20 penalty and Strength-derived AP.
func TestForeverCoreHunterDirectPetAttackPower(t *testing.T) {
	withForeverCoreHunter(t, &foreverCoreHunterData{Pet: &foreverCorePetData{AttackPower: 44, BaseDamageMin: 9, BaseDamageMax: 13}})
	base := stats.Stats{}
	base[stats.Strength], base[stats.AttackPower] = 136, -20
	got := foreverCorePetBaseStats(base)
	if got[stats.Strength] != 0 || got[stats.AttackPower] != 44 {
		t.Fatalf("AP must be 44 with no Strength-derived AP: Strength %.2f AP %.2f", got[stats.Strength], got[stats.AttackPower])
	}
}

// Live pet values replace the level 60 constants; weaker live values give a weaker pet.
func TestForeverCoreHunterLivePet(t *testing.T) {
	withForeverCoreHunter(t, nil)
	_, upstream := foreverCoreHunterSim(t, proto.HunterOptions_ThoriumHeadedArrow)
	// Feeding upstream's own level 60 values back in must reproduce upstream exactly.
	same := &foreverCorePetData{AttackPower: petBaseStats[stats.AttackPower],
		BaseDamageMin: petSwingAverage * (1 - 0.2), BaseDamageMax: petSwingAverage * (1 + 0.2)}
	withForeverCoreHunter(t, &foreverCoreHunterData{Pet: same})
	if _, got := foreverCoreHunterSim(t, proto.HunterOptions_ThoriumHeadedArrow); math.Abs(got-upstream) > 1e-6 {
		t.Fatalf("upstream values via live path: pet %.4f, upstream %.4f", got, upstream)
	}
	low := &foreverCorePetData{AttackPower: 60, Agility: 30, Stamina: 60, Intellect: 20, Spirit: 30, BaseDamageMin: 9, BaseDamageMax: 13}
	withForeverCoreHunter(t, &foreverCoreHunterData{Pet: low})
	if _, got := foreverCoreHunterSim(t, proto.HunterOptions_ThoriumHeadedArrow); !(got > 0 && got < upstream*0.95) {
		t.Fatalf("low-level pet %.2f, upstream level 60 pet %.2f", got, upstream)
	}
}
