package main

import (
 "context"
 "fmt"
 "os"
 "path/filepath"
 "testing"
)

func starterForClass(class string) map[string]any {
 subclass:=float64(10);loc:="INVTYPE_2HWEAPON"
 if class=="warrior"||class=="rogue"{subclass=7;loc="INVTYPE_WEAPON"}
 if class=="paladin"||class=="shaman"{subclass=4;loc="INVTYPE_WEAPON"}
 return map[string]any{"id":float64(25),"name":"Public test weapon","slot":"MainHandSlot","itemClass":float64(2),"weaponClass":float64(2),"weaponSubclass":subclass,"equipLoc":loc,"statsComplete":true,"rawStats":map[string]any{},"weapon":map[string]any{"min":float64(3),"max":float64(5),"speed":float64(2)}}
}
func TestOrdinaryUnknownItemUsesNativeDatabase(t *testing.T) {
 m:=manifestForTest(t);it:=starterForClass("warrior")
 it["rawStats"]=map[string]any{"ITEM_MOD_STRENGTH_SHORT":float64(3)}
 got,e:=liveItemDatabase(it,m);if e!=nil{t.Fatal(e)}
 scaling:=child(child(got,"scalingOptions"),"0")
 if num(scaling,"weaponDamageMin")!=3||num(child(scaling,"stats"),"0")!=3{t.Fatal(got)}
 it["hasUnmodeledEffects"]=true;if _,e=liveItemDatabase(it,m);e==nil{t.Fatal("proc item approximated")}
 it["hasUnmodeledEffects"]=false;it["rawStats"]=map[string]any{"UNKNOWN_STAT":float64(2)}
 if _,e=liveItemDatabase(it,m);e==nil{t.Fatal("unknown stat discarded")}
}
func TestActualAllNineClassesThroughCore(t *testing.T) {
 engine:=os.Getenv("FC_TEST_ENGINE");if engine==""{t.Skip("FC_TEST_ENGINE not set")}
 spells:=map[string][]int{"warrior":{78,6673},"rogue":{1752,2098},"paladin":{21084,20271},"hunter":{75,1978,3044},"mage":{133,116},"priest":{585,589},"warlock":{686,172},"shaman":{403,8042},"druid":{5176,8921}}
 root,_:=filepath.Abs("..")
 for class,book:=range spells{for _,level:=range []int{10,20,59,60}{t.Run(fmt.Sprintf("%s/L%d",class,level),func(t *testing.T){
  race:="Human";if class=="hunter"{race="Dwarf"};if class=="shaman"||class=="druid"{race="Tauren"}
  rows:=[]any{};for _,id:=range book{rows=append(rows,map[string]any{"id":float64(id)})}
  equipment:=[]any{starterForClass(class)}
  snap:=map[string]any{"class":class,"race":race,"level":float64(level),"talentSnapshotStatus":map[string]any{"state":"valid"},"talents":[]any{},"spellbookStatus":map[string]any{"state":"valid"},"spells":rows,"equipped":equipment}
  if class=="hunter"{
   ranged:=starterForClass(class);ranged["id"]=float64(2504);ranged["slot"]="RangedSlot";ranged["weaponSubclass"]=float64(2);ranged["equipLoc"]="INVTYPE_RANGED";snap["equipped"]=append(equipment,ranged)
   snap["hunter"]=map[string]any{"ammo":map[string]any{"status":"ok","dps":float64(2)},"quiver":map[string]any{"status":"none"}}
  }
  service:=SimService{Config:Config{Runtime:root,Data:t.TempDir(),Engine:engine,EngineRevision:str(manifestForTest(t),"engineRevision")}}
  req,e:=service.liveRequest(Job{State:map[string]any{"sim":snap},Payload:map[string]any{}});if e!=nil{t.Fatal(e)}
  child(req,"simOptions")["iterations"]=float64(10);child(req,"encounter")["duration"]=float64(20)
  result,e:=service.once(context.Background(),req);if e!=nil{t.Fatal(e)}
  if simDPS(result)<=0{t.Fatalf("no damage: %v",result)}
  t.Logf("MythicSim %.3f DPS",simDPS(result))
 })}}
}
