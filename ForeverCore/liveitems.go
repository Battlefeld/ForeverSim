package main

import (
 "fmt"
 "math"
 "strconv"
 "strings"
)

// Unknown ordinary items use the client's public base stats via MythicSim's native
// per-player database. Proc/set items are never approximated as plain stat items.
func liveItemDatabase(item, manifest map[string]any) (map[string]any, error) {
 id := int(num(item,"id"))
 if id < 1 || num(item,"quality")>2 || item["statsComplete"] != true || item["hasUnmodeledEffects"] == true {
  return nil, fmt.Errorf("Item %d: vollstaendige Basiswerte fehlen oder Spezialeffekt nicht modelliert",id)
 }
 types := map[string]int{"HeadSlot":1,"head":1,"NeckSlot":2,"neck":2,"ShoulderSlot":3,"shoulder":3,"BackSlot":4,"back":4,"ChestSlot":5,"chest":5,"WristSlot":6,"wrist":6,"HandsSlot":7,"hands":7,"WaistSlot":8,"waist":8,"LegsSlot":9,"legs":9,"FeetSlot":10,"feet":10,"Finger0Slot":11,"Finger1Slot":11,"finger1":11,"finger2":11,"Trinket0Slot":12,"Trinket1Slot":12,"trinket1":12,"trinket2":12,"MainHandSlot":13,"SecondaryHandSlot":13,"mainhand":13,"offhand":13,"RangedSlot":14,"ranged":14}
 typ:=types[str(item,"slot")];if typ==0{return nil,fmt.Errorf("Item %d: Slot fehlt",id)}
 mapping:=map[string][]string{
 "ITEM_MOD_STRENGTH_SHORT":{"StatStrength"},"ITEM_MOD_AGILITY_SHORT":{"StatAgility"},"ITEM_MOD_STAMINA_SHORT":{"StatStamina"},"ITEM_MOD_INTELLECT_SHORT":{"StatIntellect"},"ITEM_MOD_SPIRIT_SHORT":{"StatSpirit"},
 "ITEM_MOD_ATTACK_POWER_SHORT":{"StatAttackPower"},"ITEM_MOD_RANGED_ATTACK_POWER_SHORT":{"StatRangedAttackPower"},"ITEM_MOD_FERAL_ATTACK_POWER_SHORT":{"StatFeralAttackPower"},"ITEM_MOD_SPELL_PENETRATION_SHORT":{"StatSpellPiercing"},
 "ITEM_MOD_SPELL_POWER_SHORT":{"StatSpellDamage","StatHealingPower"},"ITEM_MOD_SPELL_DAMAGE_DONE_SHORT":{"StatSpellDamage"},"ITEM_MOD_SPELL_HEALING_DONE_SHORT":{"StatHealingPower"},
 "ITEM_MOD_HIT_RATING_SHORT":{"StatMeleeHitRating","StatSpellHitRating"},"ITEM_MOD_CRIT_RATING_SHORT":{"StatMeleeCritRating","StatSpellCritRating"},"ITEM_MOD_HASTE_RATING_SHORT":{"StatMeleeHasteRating","StatSpellHasteRating"},
 "ITEM_MOD_SPELL_HIT_RATING_SHORT":{"StatSpellHitRating"},"ITEM_MOD_SPELL_CRIT_RATING_SHORT":{"StatSpellCritRating"},"ITEM_MOD_SPELL_HASTE_RATING_SHORT":{"StatSpellHasteRating"},
 "ITEM_MOD_HEALTH_SHORT":{"StatHealth"},"ITEM_MOD_MANA_SHORT":{"StatMana"},"ITEM_MOD_MANA_REGENERATION_SHORT":{"StatMP5"},"RESISTANCE0_NAME":{"StatArmor"},"ITEM_MOD_ARMOR_SHORT":{"StatArmor"},
 "ITEM_MOD_HOLY_DAMAGE_SHORT":{"StatHolyDamage"},"ITEM_MOD_FIRE_DAMAGE_SHORT":{"StatFireDamage"},"ITEM_MOD_NATURE_DAMAGE_SHORT":{"StatNatureDamage"},"ITEM_MOD_FROST_DAMAGE_SHORT":{"StatFrostDamage"},"ITEM_MOD_SHADOW_DAMAGE_SHORT":{"StatShadowDamage"},"ITEM_MOD_ARCANE_DAMAGE_SHORT":{"StatArcaneDamage"},
 }
 stats:=map[string]any{}
 for key,raw:=range child(item,"rawStats") {
  value,ok:=raw.(float64);if !ok||math.IsNaN(value)||math.IsInf(value,0){return nil,fmt.Errorf("Item %d: ungueltiger Stat",id)}
  if key=="ITEM_MOD_DAMAGE_PER_SECOND_SHORT" {continue}
  // Stats that never change the damage a player deals (resistances, defense, avoidance, block, resilience, damage
  // taken) have no engine value and must not make the item unusable.
  if nonDamageStat(key) {continue}
  names:=mapping[key];if len(names)==0 && value!=0{return nil,fmt.Errorf("Item %d: Stat %s nicht zugeordnet",id,key)}
  for _,name:=range names{index,exists:=child(manifest,"stats")[name];if !exists{return nil,fmt.Errorf("Engine-Stat fehlt: %s",name)};k:=strconv.Itoa(int(index.(float64)));stats[k]=num(stats,k)+value}
 }
 scaling:=map[string]any{"stats":stats}
 out:=map[string]any{"id":float64(id),"name":str(item,"name"),"type":typ,"scalingOptions":map[string]any{"0":scaling}}
 out["armorType"]=map[string]int{"cloth":1,"leather":2,"mail":3,"plate":4}[str(item,"armorType")]
 subclass:=int(num(item,"weaponSubclass"));loc:=str(item,"equipLoc")
 if num(item,"itemClass")==2 || num(item,"weaponClass")==2 {
  weapon:=child(item,"weapon");lo,hi,speed:=num(weapon,"min"),num(weapon,"max"),num(weapon,"speed")
  if !(speed>0)||lo<0||hi<lo||weapon["includesAttackPower"]==true{return nil,fmt.Errorf("Item %d: Basis-Waffenschaden fehlt",id)}
  scaling["weaponDamageMin"],scaling["weaponDamageMax"]=lo,hi;out["weaponSpeed"]=speed
  out["weaponType"]=map[int]int{0:1,1:1,4:4,5:4,6:6,7:9,8:9,10:8,13:3,15:2}[subclass]
  out["rangedWeaponType"]=map[int]int{2:1,3:3,16:4,18:2,19:5}[subclass]
  out["handType"]=2;if loc=="INVTYPE_2HWEAPON"{out["handType"]=4}else if loc=="INVTYPE_WEAPONMAINHAND"{out["handType"]=1}else if loc=="INVTYPE_WEAPONOFFHAND"{out["handType"]=3}
 } else if loc=="INVTYPE_SHIELD" {out["weaponType"],out["handType"]=7,3
 } else if loc=="INVTYPE_HOLDABLE" {out["weaponType"],out["handType"]=5,3}
 return out,nil
}

// nonDamageStat: resistances (but not armor), defense, dodge, parry, block, resilience and "taken" ratings.
func nonDamageStat(key string) bool {
 if strings.Contains(key,"RESISTANCE") && key != "RESISTANCE0_NAME" {
  return true
 }
 for _, part := range []string{"DEFENSE_SKILL", "DODGE_RATING", "PARRY_RATING", "BLOCK_RATING", "BLOCK_VALUE", "RESILIENCE", "_TAKEN_", "HEALTH_REGEN"} {
  if strings.Contains(key, part) {
   return true
  }
 }
 return false
}

func addLiveItem(req,item,manifest map[string]any) error {
 id:=int(num(item,"id"));if id==0||child(manifest,"items")[strconv.Itoa(id)]==true{return nil}
 player,e:=playerOf(req);if e!=nil{return e}
 database:=child(player,"database");if database==nil{database=map[string]any{};player["database"]=database}
 for _,raw:=range array(database,"items"){if int(num(raw.(map[string]any),"id"))==id{return nil}}
 spec:=parseItemLink(str(item,"link"),map[string]any{})
 if num(spec,"enchant")!=0||num(spec,"randomSuffix")!=0{return fmt.Errorf("Item %d: unbekanntes verzaubertes/Suffix-Item braucht Quelldaten",id)}
 record,e:=liveItemDatabase(item,manifest);if e!=nil{return e}
 database["items"]=append(array(database,"items"),record)
 return nil
}
