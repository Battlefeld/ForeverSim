-- Addon code manages widgets only; combat evaluation belongs to MythicSim.
local C=ForeverCoreClient
local function enabled()return ForeverCoreBridgeDB and ForeverCoreBridgeDB.enabled~=false end
local function classKey()local _,key=UnitClass('player');return key and string.lower(key)end
local function combat()return InCombatLockdown and InCombatLockdown()end
local function request(kind,payload,done)
 local revision=C.simRevision
 return C.Request(kind,payload,function(result,issue)if revision==C.simRevision then done(result,issue)else done(nil,'Zustand geaendert; bitte erneut berechnen')end end)
end
local function weightsPayload()
 local snap=FUSLive.capture(true);local cl=classKey();local physical=snap.form=='cat'or snap.form=='bear'or cl=='warrior'or cl=='rogue'or cl=='hunter'
 return{stats={{key='StatSpellDamage',increment=10},{key=physical and'StatMeleeHitRating'or'StatSpellHitRating',increment=10},{key=physical and'StatMeleeCritRating'or'StatSpellCritRating',increment=14},{key=physical and'StatMeleeHasteRating'or'StatSpellHasteRating',increment=10},{key='StatIntellect',increment=10},{key='StatAgility',increment=10},{key='StatStrength',increment=10},{key=cl=='hunter'and'StatRangedAttackPower'or'StatAttackPower',increment=20}}}
end
local aliases={'sp','hitPct','critPct','hastePct','int','agi','str','ap'}
local labels={'Zaubermacht','Trefferchance','Kritische Treffer','Tempo','Intelligenz','Beweglichkeit','Staerke','Angriffskraft'}
local function displayWeights(r)
 -- Existing widgets label secondaries in percent; convert the raw rating derivative
 -- with the pinned engine's level-60 constants. No combat formula is reimplemented.
 for i,row in ipairs(r.rows or{})do
  row.engineStat=row.key;row.key=aliases[i];row.name=labels[i]
  if i==2 or i==4 then row.perPoint=row.perPoint*10;row.increment=1 elseif i==3 then row.perPoint=row.perPoint*14;row.increment=1 end
 end
 if r.warnings and #r.warnings>0 then r.comparison=(r.comparison or "").."\n"..table.concat(r.warnings,"\n")end
 return r
end
local previous=C.InstallAdapters
C.InstallAdapters=function()
 previous();local P=FUSLive;if not P or C.analysisInstalled then return end;C.analysisInstalled=true
 local D=P.dashboard;if not D or not D.state then return end
 local S=D.state
 local oldWeights=D.RunWeights
 D.RunWeights=function()
  if not enabled()then return oldWeights()end
  if combat()or(S.weightsBusy and S.weightsRevision==P.revision)then return end
  local rev=P.revision;S.weightsBusy=true;S.weightsRevision=rev;S.weightsError=nil;D.Refresh()
  local function finish(r,issue)
   if S.weightsRevision~=rev then return end;S.weightsBusy=false;if S.run then S.run.done.weights=true end
   if issue then S.weightsError=issue else S.weights=displayWeights(r);S.weights.revision=rev end;D.Refresh()
  end
  if not request('weights',weightsPayload(),finish)then finish(nil,'Auftrag konnte nicht gestartet werden')end
 end
 local oldCompare=D.CompareTalents
 D.CompareTalents=function()
  if not enabled()then return oldCompare()end
  if combat()or S.talentBusy then return end
  local cl=classKey();local drafts=ForeverSimBridgeDB.talentPlannerDrafts or{};local draft=drafts[cl];local entries={}
  if draft and draft.touched then
   local model=FUSLiveData and FUSLiveData[cl]
   for _,tree in ipairs(model and model.talentTrees or{})do for _,node in ipairs(tree.talents or{})do local rank=(draft.ranks or{})[node.key]or 0;if rank>0 then entries[#entries+1]={classKey=node.key,spellID=node.spellId,rank=rank}end end end
  else local snap=C.Capture('talents').sim;for _,tree in ipairs(snap.talents or{})do for _,entry in ipairs(tree.entries or{})do entries[#entries+1]=entry end end end
  local rev=P.revision;S.talentBusy=rev;S.talentError=nil;S.talentMessage='MythicSim vergleicht den Talententwurf ...';D.Refresh()
  local function finish(r,issue)
   if S.talentBusy~=rev then return end;S.talentBusy=false
   if issue then S.talentMessage=issue;S.talentError=true else S.talentMessage=r.comparison;S.talentCompare={base=r.base,cand=r.cand,pct=r.pct,per=r.per or{},unmodeled={}}end;D.Refresh()
  end
  if not request('talents',{talents=entries},finish)then finish(nil,'Auftrag konnte nicht gestartet werden')end
 end
 local oldTrace=D.RunTrace
 D.RunTrace=function()
  if not enabled()then return oldTrace()end
  if combat()or S.traceBusy then return end
  local rev=P.revision;S.traceBusy=true;S.traceRevision=rev;S.traceError=nil;D.Refresh()
  local function finish(r,issue)
   if S.traceRevision~=rev then return end;S.traceBusy=false;if S.run then S.run.done.trace=true end
   if issue then S.traceError=issue else S.traceError='MythicSim-Zauberauswertung im Ergebnisfenster';C.ShowResult(r)end;D.Refresh()
  end
  if not request('analysis',{},finish)then finish(nil,'Auftrag konnte nicht gestartet werden')end
 end
end

local installAnalysis=C.InstallAdapters
C.InstallAdapters=function()
 installAnalysis();local P=FUSLive;local D=P and P.dashboard;if not D or C.gearAnalysisInstalled then return end;C.gearAnalysisInstalled=true
 local S=D.state;local check=D.CheckGear
 D.CheckGear=function()
  if not enabled()then return check()end
  if combat()or(S.gear.busy and S.gear.revision==P.revision)then return end
  local snap=P.capture(false);local items,seen={},{}
  local function add(item,origin)
   if type(item)~='table'or not item.id then return end
   local key=tostring(item.link or item.id);if seen[key]then return end;seen[key]=true;item.origin=origin;items[#items+1]=item
  end
  local containers=C_Container
  if containers and containers.GetContainerNumSlots and containers.GetContainerItemLink then
   for bag=0,4 do local ok,count=pcall(containers.GetContainerNumSlots,bag)
    if ok and C.public(count)and type(count)=='number'then for slot=1,count do
     local good,link=pcall(containers.GetContainerItemLink,bag,slot)
     if good and C.public(link)and type(link)=='string'then local item=P.readItem(link,'Tasche');if item then item.link=link;add(item,'Tasche')end end
    end end
   end
  else for _,item in ipairs(snap and snap.bagItems or{})do add(item,'Tasche')end end
  for _,item in ipairs(S.questItems or{})do add(item,'Questbelohnung')end
  for _,link in ipairs(P.itemScore and P.itemScore.BankLinks and P.itemScore.BankLinks()or{})do local item=P.readItem(link,'Bank');if item then item.link=link;add(item,'Bank')end end
  local api=ForeverSimDungeonAPI
  for _,candidate in ipairs(api and api.LootCandidates and api.LootCandidates(UnitLevel('player'),30)or{})do local item=P.readItem('item:'..candidate.id,'Dungeon');if item then item.boss=candidate.boss;item.dungeon=candidate.dungeon;add(item,'Dungeon')end end
  local rev=P.revision;local g=S.gear;g.rows={};g.revision=rev;g.busy=true;g.done=0;g.total=#items;g.error=nil;D.Refresh()
  if #items==0 then g.busy=false;g.error='Keine geladenen Ausruestungskandidaten';D.Refresh();return end
  local index=0
  local function nextItem()
   if rev~=P.revision then g.busy=false;g.error='Profil geaendert; bitte neu berechnen';D.Refresh();return end
   index=index+1;local item=items[index]
   if not item then
    g.busy=false;if S.run then S.run.done.gear=true end
    table.sort(g.rows,function(a,b)return(a.result and a.result.delta or -1e9)>(b.result and b.result.delta or -1e9)end);D.Refresh();return
   end
   local candidate=C.ItemCandidate(item,item.link);local slot=candidate.slot
   if slot==nil then g.rows[#g.rows+1]={item=item,reason='Itemslot nicht unterstuetzt'};g.done=index;return nextItem()end
   local cached,context,key=C.CachedItemComparison(item,candidate,item.link)
   if cached and cached.result then
    g.rows[#g.rows+1]={item=item,result=cached.result}
    g.done=index;D.Refresh()
    return nextItem()
   end
   local function finish(r,issue)
    if rev~=P.revision then g.busy=false;g.error='Profil geaendert; bitte neu berechnen';D.Refresh();return end
    local row={item=item,reason=issue}
    if r then C.StoreItemComparison(context,key,r)end
    if r then row.result={eligible=true,item=item,baselineDps=r.baselineDps,dps=r.candidateDps,delta=r.delta,percent=r.percent,warnings=r.warnings,targetArmorEstimated=r.targetArmorEstimated,status=(r.percent or 0)>0 and'upgrade'or((r.percent or 0)<0 and'downgrade'or'equal')}end
    g.rows[#g.rows+1]=row;g.done=index;D.Refresh();nextItem()
   end
   if not request('item',{items={candidate}},finish)then g.busy=false;g.error='Warteschlange belegt; Gear-Vergleich erneut starten';D.Refresh()end
  end
  nextItem()
 end
 local all=D.RunAll
 D.RunAll=function()
  if not enabled()then return all()end
  if combat()then return end
  S.chain=nil;S.run={start=GetTime(),done={},leveling=false};P.actions.RunRotation();C.afterRotationRun=C.simRun;D.Refresh()
 end
 local apply=C.ApplySim
 C.ApplySim=function(result,issue)
  apply(result,issue)
  if C.afterRotationRun and C.afterRotationRun==C.simRun then
   C.afterRotationRun=nil
   if not issue and result then D.RunWeights();D.RunTrace();D.CheckGear()end
  end
 end
end
