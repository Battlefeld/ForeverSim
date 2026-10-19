package main

import (
 "context"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "fmt"
 "math"
 "path/filepath"
 "sort"
 "strings"
 "time"
)

// A search over complete allocations, not three isolated trees or the next point.
// A bounded beam keeps the job usable on desktop hardware. We disclose that
// this is the best simulated build found, not a mathematical global optimum.
type buildNode struct {
 key,name string
 tree,spellID,definition,max,row,col int
 prereqRow,prereqCol int
 prereq bool
}
type buildState struct {
 ranks map[string]int
 score float64
}
func talentNodes(trees []any) ([]buildNode,error) {
 nodes:=[]buildNode{}
 for ti,raw:=range trees {
  t,ok:=raw.(map[string]any);if !ok{return nil,fmt.Errorf("Talentbaum fehlt")}
  for _,x:=range array(t,"talents"){
   n,ok:=x.(map[string]any);if !ok {continue}
   loc:=child(n,"location")
   if str(n,"fieldName")=="" || int(num(n,"maxPoints"))<1 {continue}
   node:=buildNode{key:str(n,"fieldName"),name:str(n,"fancyName"),
    tree:ti,spellID:int(num(n,"spellId")),definition:int(num(n,"definitionId")),
    max:int(num(n,"maxPoints")),row:int(num(loc,"rowIdx")),col:int(num(loc,"colIdx"))}
   if p:=child(n,"prereqLocation");p!=nil{node.prereq=true;node.prereqRow=int(num(p,"rowIdx"));node.prereqCol=int(num(p,"colIdx"))}
   if node.name==""{node.name=node.key}
   nodes=append(nodes,node)
  }
 }
 sort.Slice(nodes,func(i,j int)bool{
  if nodes[i].tree!=nodes[j].tree{return nodes[i].tree<nodes[j].tree}
  if nodes[i].row!=nodes[j].row{return nodes[i].row<nodes[j].row}
  if nodes[i].col!=nodes[j].col{return nodes[i].col<nodes[j].col}
  return nodes[i].key<nodes[j].key
 })
 return nodes,nil
}
func legalBuildAddition(nodes []buildNode,ranks map[string]int,n buildNode)bool{
 if ranks[n.key]>=n.max{return false}
 earlier:=0
 for _,other:=range nodes{
  if other.tree==n.tree && other.row<n.row {earlier+=ranks[other.key]}
 }
 if earlier<5*n.row{return false}
 if n.prereq{
  found:=false
  for _,other:=range nodes{
   if other.tree==n.tree&&other.row==n.prereqRow&&other.col==n.prereqCol{
    found=ranks[other.key]==other.max;break
   }
  }
  if !found{return false}
 }
 return true
}
func cloneRanks(original map[string]int)map[string]int{
 out:=make(map[string]int,len(original)+1);for k,v:=range original{out[k]=v};return out
}
func rankKey(nodes []buildNode,ranks map[string]int)string{
 var b strings.Builder
 for _,node:=range nodes{if v:=ranks[node.key];v>0{fmt.Fprintf(&b,"%d=%d;",node.tree*100+node.row*10+node.col,v)}}
 return b.String()
}
func talentEntries(nodes []buildNode,ranks map[string]int)[]any{
 entries:=[]any{}
 for _,n:=range nodes{if r:=ranks[n.key];r>0{
  entries=append(entries,map[string]any{"fieldName":n.key,"rank":float64(r)})
 }}
 return entries
}
func buildRows(nodes []buildNode,ranks map[string]int)[]any{
 rows:=[]any{}
 for _,n:=range nodes{if r:=ranks[n.key];r>0{
  rows=append(rows,map[string]any{"key":n.key,"name":n.name,
   "tree":n.tree+1,"rank":r,"spellID":n.spellID})
 }}
 return rows
}
func totalRanks(ranks map[string]int)int{
 sum:=0;for _,r:=range ranks{sum+=r};return sum
}
// Search results are reusable when only the currently allocated talent
// points change. The key still includes gear, level, spells, buffs,
// encounter, engine revision and every other sim input.
type talentSearchRecord struct {
 Version int `json:"version"`
 Points int `json:"points"`
 Ranks map[string]int `json:"ranks"`
 Tested int `json:"tested"`
}

func (s *SimService) talentSearchCache(req map[string]any,points int)(string,error){
 normalized:=cloneMap(req)
 player,err:=playerOf(normalized);if err!=nil{return "",err}
 player["talentsString"]=""
 b,err:=json.Marshal(normalized);if err!=nil{return "",err}
 h:=sha256.New()
 fmt.Fprintf(h,"talent-search-v2/%s/%d/",s.Config.EngineRevision,points)
 h.Write(b)
 return filepath.Join(s.Config.Data,"TalentBuilds",hex.EncodeToString(h.Sum(nil))+".json"),nil
}

func (s *SimService) optimizeTalentBuild(ctx context.Context,req,base map[string]any,j Job)(any,error){
 var manifest map[string]any
 if err:=loadJSON(filepath.Join(s.Config.Runtime,"ForeverCore","engine-data.json"),&manifest);err!=nil{return nil,err}
 player,_:=playerOf(req)
 class:=strings.ToLower(strings.TrimPrefix(str(player,"class"),"Class"))
 profile:=child(child(manifest,"classes"),class)
 if profile==nil{return nil,fmt.Errorf("MythicSim: Talentbaum fehlt")}
 trees:=array(profile,"trees")
 nodes,err:=talentNodes(trees);if err!=nil{return nil,err}
 if len(nodes)==0{return nil,fmt.Errorf("Keine Talente im Engine-Modell")}
 current:=map[string]int{}
 currentEntries:=liveTalentEntries(child(j.State,"sim"))
 _,current,err=encodeTalentEntries(trees,currentEntries,false,0)
 if err!=nil{return nil,err}
 total:=totalRanks(current)+int(num(child(j.State,"sim"),"unspentTalentPoints"))
 // The client may provide exactly the intended budget. Never permit extra points.
 if requested:=int(num(j.Payload,"points"));requested>0 {
  if requested!=total{return nil,fmt.Errorf("Talentpunkte widerspruechlich: live %d, angefordert %d",total,requested)}
 }
 if total<1{return nil,fmt.Errorf("Keine Talentpunkte verfuegbar")}
 if total>51{return nil,fmt.Errorf("Ungueltiges Talentbudget")}
 start:=simDPS(base)
 if start<=0{return nil,fmt.Errorf("Referenzschaden fehlt")}
 // Bounded deterministic search over ALL three trees. 8 points means 8 layers
 // of choices; full allocations are ranked by actual MythicSim DPS.
 // The low-iteration search is followed by a full precision final measurement.
 width:=2
 limit:=110
 if total>15 {width=1;limit=135}
 file,e:=s.talentSearchCache(req,total)
 if e!=nil{return nil,e}
 var saved talentSearchRecord
 cached:=loadJSON(file,&saved)==nil&&saved.Version==2&&saved.Points==total&&saved.Tested>0&&totalRanks(saved.Ranks)==total
 if cached {
  allowed:=map[string]int{}
  for _,n:=range nodes{allowed[n.key]=n.max}
  for key,r:=range saved.Ranks{if r<0||r>allowed[key]||allowed[key]==0{cached=false;break}}
 }
 count:=0
 cache:=map[string]float64{}
 failed:=0
 beam:=[]buildState{{ranks:map[string]int{},score:0}}
 deadline:=time.Now().Add(100*time.Second)
 partial:=false
 if !cached { for step:=1;step<=total;step++{
  seen:=map[string]bool{}
  next:=[]buildState{}
  // Different tree allocations remain eligible at every depth.
  for _,state:=range beam{
   for _,node:=range nodes{
    if !legalBuildAddition(nodes,state.ranks,node){continue}
    ranks:=cloneRanks(state.ranks);ranks[node.key]++
    key:=rankKey(nodes,ranks)
    if seen[key]{continue};seen[key]=true
    if count>=limit || time.Now().After(deadline){partial=true;break}
    score,found:=cache[key]
    if !found{
     encoded,parsed,e:=encodeTalentEntries(trees,talentEntries(nodes,ranks),true,total)
     if e!=nil{failed++;continue}
     simulated:=cloneMap(req)
     p,_:=playerOf(simulated);p["talentsString"]=encoded
     grantDraftSpells(simulated,trees,parsed)
     // Same iterations/seed for each candidate at this search stage.
     child(simulated,"simOptions")["iterations"]=float64(150)
     result,e:=s.once(ctx,simulated)
     if e!=nil{failed++;continue}
     score=simDPS(result);cache[key]=score;count++
    }
    next=append(next,buildState{ranks:ranks,score:score})
   }
   if partial{break}
  }
  if len(next)==0{return nil,fmt.Errorf("Keine vollstaendige Skillung berechenbar (%d/%d Punkte, %d fehlgeschlagene Varianten)",step-1,total,failed)}
  sort.Slice(next,func(i,j int)bool{
   if math.Abs(next[i].score-next[j].score)>0.00001{return next[i].score>next[j].score}
   return rankKey(nodes,next[i].ranks)<rankKey(nodes,next[j].ranks)
  })
  // Preserve diversity: second branch should start in a different tree when
  // scores are similar, so a whole mixed build can beat a greedy single branch.
  beam=next[:1]
  for _,cand:=range next[1:]{
   if len(beam)>=width{break}
   distinct:=rankKey(nodes,cand.ranks)!=rankKey(nodes,beam[0].ranks)
   if distinct{beam=append(beam,cand)}
  }
  if partial && step<total{return nil,fmt.Errorf("Talentvergleich unvollstaendig nach %d von %d Punkten; kein fertiges Build empfohlen",step,total)}
 }
 }
 winning:=beam[0]
 if cached {winning=buildState{ranks:saved.Ranks};count=saved.Tested}
 encoded,parsed,e:=encodeTalentEntries(trees,talentEntries(nodes,winning.ranks),true,total)
 if e!=nil{return nil,e}
 final:=cloneMap(req);p,_:=playerOf(final);p["talentsString"]=encoded
 grantDraftSpells(final,trees,parsed)
 measured,e:=s.once(ctx,final)
 if e!=nil{return nil,e}
 dps:=simDPS(measured)
 if !cached {
  // Cache only a complete, successfully verified search.
  _=atomicWrite(file,jsonBytes(talentSearchRecord{Version:2,Points:total,Ranks:winning.ranks,Tested:count}))
 }
 // Current points may have been allocated already: never encourage spending
 // an unavailable point or claim the plan is usable without a talent reset.
 respec:=false
 for _,n:=range nodes{if current[n.key]>winning.ranks[n.key]{respec=true;break}}
 result:=map[string]any{"engine":"MythicSim Go","status":"ok",
  "points":total,"base":start,"dps":dps,"delta":dps-start,"percent":100*(dps-start)/start,
  "build":buildRows(nodes,winning.ranks),"requiresRespec":respec,"tested":count,
  "exhaustive":false,"method":"bounded-beam-search","complete":!partial,"cached":cached,
  "comparison":"Beste unter den geprueften ganzen Skillungen (Mischungen der drei Baeume); kein Vollstaendigkeitsbeweis"}
 return withResultContext(result,req),nil
}
