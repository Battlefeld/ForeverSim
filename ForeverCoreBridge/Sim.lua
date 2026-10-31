-- What the ForeverSim window and the combat HUD know about this character: its talent builds, the rotation that is
-- active, and the results ForeverCore.exe computed for them. No frames here; the windows only display this.
-- Everything is kept per character in ForeverCoreBridgeDB.sim[<guid>]; a result carries the state it was computed for
-- (C.SimCacheContext) so the window can say "veraltet" when gear, talents, level or the engine changed since.
local C=ForeverCoreClient
local Sim={};C.Sim=Sim
-- Levels from which each part is offered (the combat HUD from the first level).
Sim.MIN={hud=1,talents=60,rotation=50,loot=50}
Sim.MAX_BUILDS=10
local function now()return GetTime and GetTime()or 0 end
local function stamp()return time and time()or 0 end
local function classKey()local ok,_,c=pcall(UnitClass,'player');if ok and type(c)=='string'then return c:lower()end end
local function charKey()
 local ok,guid=pcall(UnitGUID,'player');if ok and type(guid)=='string'and guid~=''then return guid end
 local ok2,name=pcall(UnitName,'player');return ok2 and name or'unknown'
end
function Sim.Context()
 local f=C.SimCharacterContext or C.SimCacheContext
 return f and f()or nil
end
function Sim.Class()return classKey()end
local editorModels={}
function Sim.Model()
 local k=classKey();local model=k and FUSLiveData and FUSLiveData[k]
 local canonical=k and ForeverSimTalentData and ForeverSimTalentData[k]
 if not model or not canonical then return model end
 if editorModels[k]then return editorModels[k]end
 local out={};for key,value in pairs(model)do out[key]=value end
 local bySpell={}
 for _,tree in ipairs(model.talentTrees or{})do for _,node in ipairs(tree.talents or{})do if node.spellId then bySpell[node.spellId]=node end end end
 out.talentTrees={}
 for ti,tree in ipairs(canonical.talentTrees)do
  local t={name=tree.name,talents={}};out.talentTrees[ti]=t
  for _,node in ipairs(tree.talents)do
   local n={};for key,value in pairs(node)do n[key]=value end
   local original=bySpell[n.spellId]
   if original then n.key=original.key;n.name=original.name else n.name=n.fieldName:gsub('(%u)',' %1'):gsub('^%l',string.upper)end
   t.talents[#t.talents+1]=n
  end
 end
 editorModels[k]=out;return out
end
function Sim.Level()local ok,l=pcall(UnitLevel,'player');return ok and tonumber(l)or 0 end
function Sim.Available(feature)return Sim.Level()>=(Sim.MIN[feature]or 1)end

-- Saved data ---------------------------------------------------------------------------------------------------
function Sim.Store()
 ForeverCoreBridgeDB=ForeverCoreBridgeDB or{enabled=true}
 local db=ForeverCoreBridgeDB;if type(db.sim)~='table'then db.sim={}end
 local key=charKey();local s=db.sim[key]
 if type(s)~='table'then s={version=1};db.sim[key]=s end
 if type(s.builds)~='table'then s.builds={}end
 if type(s.results)~='table'then s.results={}end
 s.nextId=tonumber(s.nextId)or 1
 return s
end
local listeners={}
function Sim.OnChange(fn)listeners[#listeners+1]=fn end
local function changed()for _,fn in ipairs(listeners)do pcall(fn)end end
Sim.Changed=changed

-- Talent builds -------------------------------------------------------------------------------------------------
-- A build is a list of {t=tree 1..3, r=row, c=column, n=rank}, the same coordinates the talent tree window draws and
-- ForeverCore.exe resolves against the engine's own tree (so the addon's spell ids never matter).
local function places()
 local model=Sim.Model();local byKey,byPlace,bySpell={}, {}, {}
 for ti,tree in ipairs(model and model.talentTrees or{})do
  byPlace[ti]={}
  for _,node in ipairs(tree.talents or{})do
   local info={t=ti,r=tonumber(node.row)or 0,c=tonumber(node.column)or 0,max=tonumber(node.maxRank)or 1,key=node.key,name=node.name,spellId=node.spellId,node=node}
   byKey[node.key]=info;byKey[node.fieldName or node.key]=info;bySpell[node.spellId]=info;byPlace[ti][info.r*10+info.c]=info
  end
 end
 return byKey,byPlace,bySpell
end
Sim.Places=places
-- The talents the character has right now, from the same capture the item values use.
function Sim.LiveEntries()
 local P=FUSLive;if not P or not P.capture then return nil,'ForeverSim fehlt'end
 -- in combat the last reading is used: the full character snapshot is only taken out of combat
 if InCombatLockdown and InCombatLockdown()and Sim.liveCache then return Sim.CopyEntries(Sim.liveCache)end
 local ok,snap=pcall(P.capture,true);if not ok or type(snap)~='table'then return nil,'Charakter nicht lesbar'end
 local byKey,_,bySpell=places();local out={}
 for _,tree in ipairs(snap.talents or{})do
  for _,e in ipairs(tree.entries or{})do
   local info=bySpell[e.spellID or e.spellId]or byKey[e.classKey];local n=tonumber(e.rank)or 0
   if info and n>0 then out[#out+1]={t=info.t,r=info.r,c=info.c,n=n}end
  end
 end
 Sim.liveCache=out
 return out
end
function Sim.Points(entries)
 local pts={0,0,0};local total=0
 for _,e in ipairs(entries or{})do pts[e.t]=(pts[e.t]or 0)+e.n;total=total+e.n end
 return pts,total
end
-- Compact form for the job: [tree,row,column,rank]. Keeps a ten-build comparison far below the pixel strip's limit.
function Sim.Payload(entries)
 local out={};for _,e in ipairs(entries or{})do out[#out+1]={e.t,e.r,e.c,e.n}end;return out
end
function Sim.Signature(entries)
 local list={};for _,e in ipairs(entries or{})do list[#list+1]=string.format('%d.%d.%d=%d',e.t,e.r,e.c,e.n)end
 table.sort(list);return table.concat(list,';')
end
function Sim.CopyEntries(entries)
 local out={};for _,e in ipairs(entries or{})do out[#out+1]={t=e.t,r=e.r,c=e.c,n=e.n}end;return out
end
function Sim.Builds()return Sim.Store().builds end
function Sim.Build(id)for _,b in ipairs(Sim.Store().builds)do if b.id==id then return b end end end
function Sim.CanAddBuild()return #Sim.Store().builds<Sim.MAX_BUILDS end
function Sim.AddBuild(name,entries,source)
 local s=Sim.Store()
 if #s.builds>=Sim.MAX_BUILDS then return nil,'Es sind schon '..Sim.MAX_BUILDS..' Skillungen gespeichert'end
 name=tostring(name or''):gsub('^%s+',''):gsub('%s+$','');if name==''then name='Skillung '..s.nextId end
 local build={id='b'..s.nextId,name=name:sub(1,28),source=source or'own',entries=Sim.CopyEntries(entries),created=stamp()}
 s.nextId=s.nextId+1;s.builds[#s.builds+1]=build;changed();return build
end
function Sim.DeleteBuild(id)
 local s=Sim.Store()
 for i,b in ipairs(s.builds)do if b.id==id then table.remove(s.builds,i);s.results[id]=nil;changed();return true end end
end
function Sim.RenameBuild(id,name)
 local b=Sim.Build(id);if not b then return false end
 name=tostring(name or''):gsub('^%s+',''):gsub('%s+$','');if name==''then return false end
 b.name=name:sub(1,28);changed();return true
end
function Sim.UpdateBuild(id,entries)
 local b=Sim.Build(id);if not b then return false end
 b.entries=Sim.CopyEntries(entries);Sim.Store().results[id]=nil;changed();return true
end

-- Rules of the talent editor ---------------------------------------------------------------------------------------
-- The same rules the engine applies (tier points, prerequisites, budget); the engine's tree layout comes with the presets.
function Sim.Layout()
 local p=Sim.Presets();local map={}
 local m=Sim.Model()
 for ti,t in ipairs(m and m.talentTrees or{})do for _,n in ipairs(t.talents or{})do
  map[ti*1000+n.row*10+n.column]={tree=ti,row=n.row,col=n.column,max=n.maxRank,preRow=n.preRow,preCol=n.preCol}
 end end
 for _,n in ipairs(p and p.layout or{})do map[n.tree*1000+n.row*10+n.col]=n end
 return map
end
local function rankMap(entries)local m={};for _,e in ipairs(entries or{})do m[e.t*1000+e.r*10+e.c]=e.n end;return m end
-- true, or false and the reason (German text for the tooltip). budget defaults to the 51 points of level 60.
function Sim.Valid(entries,budget)
 budget=budget or 51
 if type(entries)~='table'then return false,'Ungültige Talentliste'end
 local _,byPlace=places();local layout=Sim.Layout();local ranks={};local total=0
 for _,e in ipairs(entries)do
  if type(e)~='table'then return false,'Ungültiges Talent'end
  for _,k in ipairs({'t','r','c','n'})do
   local v=e[k];if type(v)~='number'or v~=v or v%1~=0 then return false,'Ungültiger Talentrang oder Platz'end
  end
  local key=e.t*1000+e.r*10+e.c
  if ranks[key]~=nil then return false,'Talent doppelt angegeben'end
  ranks[key]=e.n
 end
 for _,e in ipairs(entries)do
  local info=byPlace[e.t]and byPlace[e.t][e.r*10+e.c]
  if not info then return false,'Unbekanntes Talent'end
  if e.n<0 or e.n>info.max then return false,'Maximaler Rang erreicht'end
  total=total+e.n
  local above=0
  for _,o in ipairs(entries)do if o.t==e.t and o.r<e.r then above=above+o.n end end
  if e.n>0 and above<5*e.r then return false,'Es fehlen Punkte in den Reihen darueber ('..above..' von '..(5*e.r)..')'end
  local l=layout[e.t*1000+e.r*10+e.c]
  if e.n>0 and l and l.preRow then
   local need=byPlace[e.t][l.preRow*10+l.preCol]
   if not need or(ranks[e.t*1000+l.preRow*10+l.preCol]or 0)<need.max then return false,'Benoetigt zuerst '..tostring(need and need.name or'das Talent darueber')end
  end
 end
 if total>budget then return false,'Alle '..budget..' Talentpunkte sind verteilt'end
 return true
end
function Sim.Rank(entries,t,r,c)for _,e in ipairs(entries or{})do if e.t==t and e.r==r and e.c==c then return e.n end end;return 0 end
-- A copy of the build with one talent changed by delta (+1 or -1); nil and the reason when the result would be illegal.
function Sim.Change(entries,t,r,c,delta,budget)
 local out,found={}, false
 for _,e in ipairs(entries or{})do
  if e.t==t and e.r==r and e.c==c then found=true;if e.n+delta>0 then out[#out+1]={t=t,r=r,c=c,n=e.n+delta}end
  else out[#out+1]={t=e.t,r=e.r,c=e.c,n=e.n}end
 end
 if not found then if delta>0 then out[#out+1]={t=t,r=r,c=c,n=delta}else return nil,'Kein Punkt vergeben'end end
 local ok,why=Sim.Valid(out,budget);if not ok then return nil,why end
 return out
end
-- Text for sharing a build and the way back: "FSB1:mage:2.0.1=5;2.1.0=2".
function Sim.Export(entries)return'FSB1:'..tostring(classKey())..':'..Sim.Signature(entries)end
function Sim.Import(text)
 local class,body=tostring(text or''):match('^%s*FSB1:(%a+):([%d%.=;]*)%s*$')
 if not class then return nil,'Das ist keine ForeverSim-Skillung'end
 if class~=classKey()then return nil,'Diese Skillung gehoert zur Klasse '..class end
 local out={}
 for token in (body..';'):gmatch('(.-);')do
  local t,r,c,n=token:match('^(%d+)%.(%d+)%.(%d+)=(%d+)$')
  if not t then return nil,'Ungültiger Talenttext'end
  out[#out+1]={t=tonumber(t),r=tonumber(r),c=tonumber(c),n=tonumber(n)}
 end
 if #out==0 then return nil,'Die Skillung ist leer'end
 local ok,why=Sim.Valid(out);if not ok then return nil,why end
 return out
end

-- Engine presets ("Engine Top") ---------------------------------------------------------------------------------
function Sim.Presets()return Sim.Store().presets end
local function presetBuildEntries(p)
 local out={};for _,e in ipairs(p.entries or{})do out[#out+1]={t=e.tree,r=e.row,c=e.col,n=e.rank}end;return out
end
Sim.PresetEntries=presetBuildEntries
function Sim.LoadPresets(cb,force)
 local s=Sim.Store();local have=s.presets
 if have and have.engine==C.engineRevision and have.class==classKey()and(have.adapterVersion==2)and not force then if cb then cb(have)end;return true end
 -- a request is on its way already (every tab switch asks): the answer goes to everybody who waits
 if Sim.presetWaiters then if cb then table.insert(Sim.presetWaiters,cb)end;return true end
 Sim.presetWaiters={cb}
 local function answer(a,b)local list=Sim.presetWaiters;Sim.presetWaiters=nil;for _,fn in ipairs(list)do pcall(fn,a,b)end end
 local ok=C.Request('presets',{class=classKey()},function(result,issue)
  if type(result)=='table'and type(result.talents)=='table'then
   result.adapterVersion=2;result.at=stamp();result.engine=result.engineRevision or C.engineRevision;s.presets=C.clean(result);changed()
   answer(s.presets)
  else answer(nil,issue or'Keine Antwort')end
 end)
 if not ok then answer(nil,'Anfrage nicht moeglich')end
 return ok
end
local function findByName(list,name)
 for _,x in ipairs(list or{})do if x.name==name then return x end end
end
-- One Engine build per tree: the builds the engine pairs up (talents + gear), else its legal talent builds.
-- Returns {{id,name,talentsString,gearPreset,tree,entries,spec}}.
function Sim.TopBuilds()
 local p=Sim.Presets();if not p then return{}end
 local byTree,list={}, {}
 local function offer(name,talentPreset,gearName)
  if not talentPreset or talentPreset.valid~=true then return end
  local tree=tonumber(talentPreset.tree)or 0;if tree<1 or byTree[tree]then return end
  byTree[tree]=true
  list[#list+1]={id='top:'..tree,name=name,talentsString=talentPreset.talentsString,gearPreset=gearName,tree=tree,spec=talentPreset.spec,entries=presetBuildEntries(talentPreset)}
 end
 for _,b in ipairs(p.builds or{})do offer(b.name,findByName(p.talents,b.talents),b.gear)end
 for _,t in ipairs(p.talents or{})do
  local gear;for _,g in ipairs(p.gear or{})do if(not g.spec or not t.spec or g.spec==t.spec)and tostring(g.name):lower():find('bis',1,true)then gear=g.name;break end end
  offer(t.name,t,gear)
 end
 table.sort(list,function(a,b)return a.tree<b.tree end)
 return list
end

-- Results -------------------------------------------------------------------------------------------------------
function Sim.Result(id)return Sim.Store().results[id]end
-- True when the result was computed for another character state or engine than the current one.
function Sim.IsStale(result)
 if type(result)~='table'then return true end
 if C.engineRevision and result.engine and result.engine~=C.engineRevision then return true end
 local ctx=Sim.Context()
 return(ctx~=nil and result.context~=nil and result.context~=ctx)or false
end
local function storeRows(rows,ctx)
 local s=Sim.Store();local engine=C.engineRevision
 for _,row in ipairs(rows or{})do
  local id=row.id
  if type(id)=='string'and id~=''then
   local rec={dps=tonumber(row.dps),rotation=row.rotation,rotations=row.rotations,points=row.points,spec=row.spec,error=row.error,
    context=ctx,engine=engine,at=stamp()}
   -- Keep priorities for the selected build's detail panel; only live sets the combat HUD.
   -- A later comparison of the same state may preserve matching detail.
   local old=s.results[id]
   local same=old and old.context==ctx and old.engine==engine
   rec.priority=row.priority or(same and old.rotation==rec.rotation and old.priority or nil)
   if same and old.detail and rec.dps and old.rotation==rec.rotation then rec.detail=old.detail end
   s.results[id]=C.clean(rec)
  end
 end
end
-- Simulates builds: list = {{id,name,entries|talentsString,gearPreset,rotation}}. The character's own gear and options
-- are the base, each build gets its best rotation. cb(rows) or cb(nil,issue); a build that could not be computed has
-- row.error. The row with id "live" also sets the active rotation.
function Sim.Compare(list,cb,opts)
 opts=opts or{}
 if #list==0 then if cb then cb({})end;return true end
 local builds={}
 for i,b in ipairs(list)do
  local row={id=b.id,name=b.name}
  if b.entries then row.talents=Sim.Payload(b.entries)end
  if b.talentsString and not b.entries then row.talentsString=b.talentsString end
  row.gearPreset=b.gearPreset;row.rotation=b.rotation;row.spec=b.spec
  builds[i]=row
 end
 local ctx=Sim.Context()
 -- the talents of the saved builds as they were sent: a build edited or deleted while the PC calculates gets no result
 local sent={};for _,b in ipairs(list)do if b.entries and Sim.Build(b.id)then sent[b.id]=Sim.Signature(b.entries)end end
 local ok=C.Request('talent-compare',{builds=builds,priority=opts.priority~=false},function(result,issue)
  if type(result)~='table'or type(result.builds)~='table'then if cb then cb(nil,issue or'Keine Antwort')end;return end
  local valid={}
  for _,row in ipairs(result.builds)do
   local was=sent[row.id]
   if was==nil and Sim.Build(row.id)==nil and tostring(row.id):match('^b%d+$')then -- deleted meanwhile
   elseif was~=nil and(Sim.Build(row.id)==nil or Sim.Signature(Sim.Build(row.id).entries)~=was)then -- edited meanwhile
   else valid[#valid+1]=row end
  end
  storeRows(valid,ctx)
  for _,row in ipairs(result.builds)do
   if row.id=='live'and row.rotation and Sim.Result('live')and Sim.Result('live').priority then Sim.SetRotation(Sim.Result('live'))end
  end
  changed();if cb then cb(result.builds)end
 end,{timeout=300})
 if not ok and cb then cb(nil,'Anfrage nicht moeglich')end
 return ok
end
-- The character's own builds: what it plays now plus every saved build.
function Sim.CompareOwn(cb)
 local list={{id='live',name='Im Spiel'}}
 for _,b in ipairs(Sim.Store().builds)do list[#list+1]={id=b.id,name=b.name,entries=b.entries}end
 return Sim.Compare(list,cb)
end
-- The engine's top builds, each with its own gear.
function Sim.CompareTop(cb)
 local list={};for _,b in ipairs(Sim.TopBuilds())do list[#list+1]={id=b.id,name=b.name,talentsString=b.talentsString,gearPreset=b.gearPreset,spec=b.spec}end
 return Sim.Compare(list,cb,{priority=false})
end
-- Which damage spec is best with the gear worn now: each tree's top build talents, current gear.
function Sim.CompareSpecs(cb)
 local list={{id='live',name='Im Spiel'}}
 for _,b in ipairs(Sim.TopBuilds())do list[#list+1]={id='spec:'..b.tree,name=b.name,talentsString=b.talentsString,spec=b.spec}end
 return Sim.Compare(list,cb,{priority=false})
end

-- One build in full: its DPS, the share of every spell and the DPS/mana curve over the fight. b = {id,name,entries|
-- talentsString,gearPreset} (id "live" and no entries: the character as it is). cb(detail) or cb(nil,issue).
function Sim.Detail(b,cb)
 local build={}
 if b.entries then build.talents=Sim.Payload(b.entries)end
 if b.talentsString and not b.entries then build.talentsString=b.talentsString end
 build.gearPreset=b.gearPreset;build.spec=b.spec;build.rotation=b.rotation
 local ctx=Sim.Context()
 local ok=C.Request('build-detail',{build=build,curve=true},function(result,issue)
  if type(result)~='table'or not tonumber(result.dps)then if cb then cb(nil,issue or'Keine Antwort')end;return end
  local rec=Sim.Store().results[b.id]or{}
  rec.dps=tonumber(result.dps);rec.rotation=result.rotation;rec.rotations=C.clean(result.rotations);rec.spec=result.spec;rec.error=nil
  rec.context=ctx;rec.engine=C.engineRevision;rec.at=stamp()
  rec.detail=C.clean({breakdown=result.breakdown,curve=result.curve,duration=result.duration,context=ctx,at=stamp()})
  rec.priority=C.clean(result.priority)
  Sim.Store().results[b.id]=rec
  if b.id=='live'then Sim.SetRotation(rec)end
  changed();if cb then cb(rec.detail,nil,rec)end
 end,{timeout=300})
 if not ok and cb then cb(nil,'Anfrage nicht moeglich')end
 return ok
end

-- The build behind an id of the window's lists: "live", a saved build ("b3"), the engine's top build of a tree
-- ("top:2", with its gear) or that build's talents alone ("spec:2").
function Sim.BuildSpec(id)
 if id==nil or id=='live'then return{id='live',name='Im Spiel'}end
 local b=Sim.Build(id);if b then return{id=b.id,name=b.name,entries=b.entries}end
 local kind,tree=tostring(id):match('^(%a+):(%d+)$')
 if kind=='top'or kind=='spec'then
  for _,t in ipairs(Sim.TopBuilds())do
   if t.tree==tonumber(tree)then return{id=id,name=t.name,talentsString=t.talentsString,gearPreset=kind=='top'and t.gearPreset or nil,spec=t.spec}end
  end
 end
end

-- Everything for the window in one go: presets, the character's builds, the selected build in detail, the best spec for
-- the gear and the engine's top builds. Below level 60 only the live build's rotation is worked out (from level 50).
-- progress(step,total,label) is called before each step; done(true) or done(false,issue) at the end.
Sim.running=false
-- the refinement as a step of the full run; a refinement that cannot start must not stop the run
local function tuneStep(n)
 local done=false;local function finish()if not done then done=true;n(true)end end
 if Sim.Tune({id='live',name='Im Spiel'},nil,finish,true)==false then finish()end
end
local function gameBuild()
 if not GetBuildInfo then return nil end
 local ok,version,build=pcall(GetBuildInfo);return ok and(tostring(version)..'.'..tostring(build))or nil
end
function Sim.RunAll(opts,progress,done)
 opts=opts or{}
 if Sim.running or Sim.search then return false end
 local steps={}
 if Sim.Available('talents')then
  steps={
   {'Vorlagen laden',function(n)Sim.LoadPresets(n)end},
   {'Skillungen vergleichen',function(n)Sim.CompareOwn(n)end},
   {'Ergebnis berechnen',function(n)local spec=Sim.BuildSpec(opts.selected)or Sim.BuildSpec('live');Sim.Detail(spec,n)end},
   {'Bester Spec fuer dein Gear',function(n)Sim.CompareSpecs(n)end},
   {'Engine-Top-Skillungen',function(n)Sim.CompareTop(n)end},
  }
  -- last, because every comparison above sets the engine's own best rotation again
  if Sim.Store().refine and Sim.Tune then
   steps[#steps+1]={'Eigene Rota verfeinern',tuneStep}
  end
 elseif Sim.Available('rotation')then
  steps={{'Rotationen vergleichen',function(n)Sim.Detail({id='live',name='Im Spiel'},n)end}}
  if Sim.Store().refine and Sim.Tune then
   steps[#steps+1]={'Eigene Rota verfeinern',tuneStep}
  end
 else return false end
 Sim.running=true;Sim.progress={step=0,total=#steps}
 local function finish(ok,issue)
  Sim.running=false;Sim.progress=nil
  if ok then Sim.Store().lastRun={context=Sim.Context(),engine=C.engineRevision,build=gameBuild(),level=Sim.Level(),at=stamp(),seen=Sim.ScanBags()}end
  changed();if done then pcall(done,ok,issue)end
 end
 local function run(i)
  if i>#steps then return finish(true)end
  Sim.progress={step=i,total=#steps,label=steps[i][1]};if progress then pcall(progress,i,#steps,steps[i][1])end
  changed()
  local called=false
  -- a step that fails with an error must not leave the run hanging
  local ok,err=pcall(steps[i][2],function(result,issue)
   if called then return end;called=true
   if result==nil and issue then return finish(false,issue)end
   run(i+1)
  end)
  if not ok and not called then called=true;finish(false,tostring(err))end
 end
 run(1)
 return true
end

-- Is a new calculation due? (checked once after the login; during the session only the user starts one) ---------------------
-- The equippable items in the bags: new ones since the last calculation are a reason to calculate again.
function Sim.ScanBags()
 local seen={}
 local numSlots=(C_Container and C_Container.GetContainerNumSlots)or GetContainerNumSlots
 local itemID=(C_Container and C_Container.GetContainerItemID)or GetContainerItemID
 if not numSlots or not itemID then return seen end
 for bag=0,4 do
  local ok,n=pcall(numSlots,bag)
  if ok and type(n)=='number' then
   for slot=1,n do
    local ok2,id=pcall(itemID,bag,slot)
    if ok2 and type(id)=='number' then
     local eq=true
     if IsEquippableItem then local ok3,v=pcall(IsEquippableItem,id);if ok3 then eq=v and true or false end end
     if eq then seen[id]=true end
    end
   end
  end
 end
 return seen
end
function Sim.AutoLogin(on)
 local s=Sim.Store()
 if on~=nil then s.autoLogin=on and true or false end
 return s.autoLogin~=false
end
-- The reasons (German texts) why a new calculation is due; empty when the last one still fits.
function Sim.RecalcReasons()
 if not Sim.Available('rotation')then return{}end
 local s=Sim.Store();local last=s.lastRun;local out={}
 if not last then return{'Erste Berechnung'}end
 if C.engineRevision and last.engine and last.engine~=C.engineRevision then out[#out+1]='Neue Engine-Version'end
 local build=gameBuild()
 if build and last.build and last.build~=build then out[#out+1]='Neuer Spielpatch'end
 if tonumber(last.level)and Sim.Level()~=last.level then out[#out+1]='Neue Stufe'end
 local ctx=Sim.Context()
 if ctx and last.context and ctx~=last.context and #out==0 then out[#out+1]='Ausrüstung oder Talente haben sich geändert'end
 if type(last.seen)=='table' then
  local new=0;for id in pairs(Sim.ScanBags())do if not last.seen[id]then new=new+1 end end
  if new>0 then out[#out+1]=new==1 and'1 neues Item'or(new..' neue Items')end
 end
 return out
end

-- The active rotation --------------------------------------------------------------------------------------------
-- The best rotation for the build the character plays now. Item values, the dungeon list and every simulation use it
-- (Bridge.lua adds it to the jobs), and the combat HUD follows its priority list.
function Sim.SetRotation(result)
 if type(result)~='table'or not result.rotation then return end
 -- the item values depend on the rotation: values computed with another one are asked for again
 local old=Sim.Store().rotation
 if not old or old.name~=result.rotation then
  C.simRevision=(tonumber(C.simRevision)or 0)+1
  local P=FUSLive;if P and P.itemScore and P.itemScore.Changed then pcall(P.itemScore.Changed)end
 end
 Sim.Store().rotation={name=result.rotation,dps=result.dps,priority=result.priority,rotations=result.rotations,context=result.context,engine=result.engine,at=stamp()}
end
function Sim.Rotation()return Sim.Store().rotation end
function C.ActiveRotation()
 local r=Sim.Store().rotation;return r and not Sim.IsStale(r)and r.name or nil
end
