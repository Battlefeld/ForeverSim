-- The search for the best talents of a tree ("Beste Skillung finden"): starts from the build MythicSim ships for the tree
-- and moves single points while the engine says the damage rises. ForeverCore.exe only measures builds (talent-compare,
-- quick measurement); which builds to try comes from the editor rules in Sim.lua, so a build proposed here is always legal.
-- It runs in the background: the window stays usable and every step is one job; a click on the button cancels it.
local C=ForeverCoreClient
local Sim=C.Sim
local ROUNDS=8          -- at most this many moves of a point
local BATCH=12          -- builds per job (the engine's limit is 12)
local CHEAPEST=2        -- the least valuable points tried as the one to give up
local MIN_GAIN=0.001    -- a move has to bring 0.1 % to count
Sim.search=nil
function Sim.Searching()return Sim.search~=nil end
function Sim.CancelSearch()if Sim.search then Sim.search.cancel=true end end

local function report()
 local s=Sim.search;if not s then return end
 if s.progress then pcall(s.progress,s)end
 Sim.Changed()
end
-- Measures candidates ({id,entries}) in batches. cb(map id -> dps) or cb(nil, issue).
local function measure(cands,rotation,cb)
 local s=Sim.search;local out={};local i=1
 local function nextBatch()
  if not Sim.search then return cb(nil,'abgebrochen')end
  if s.cancel then return cb(nil,'abgebrochen')end
  if i>#cands then return cb(out)end
  local builds={}
  for k=i,math.min(#cands,i+BATCH-1)do builds[#builds+1]={id=cands[k].id,talents=Sim.Payload(cands[k].entries),rotation=rotation}end
  i=i+BATCH
  local ok=C.Request('talent-compare',{builds=builds,screenOnly=true,priority=false},function(result,issue)
   if type(result)~='table'or type(result.builds)~='table'then return cb(nil,issue or'Keine Antwort')end
   for _,row in ipairs(result.builds)do
    local d=tonumber(row.dps);if d and d>0 then out[row.id]=d;if row.rotation and not s.rotation then s.rotation=row.rotation end end
   end
   s.sims=s.sims+#builds;report();nextBatch()
  end,{timeout=300})
  if not ok then cb(nil,'Anfrage nicht moeglich')end
 end
 nextBatch()
end

local function allPlaces()
 local _,byPlace=Sim.Places();local list={}
 for t=1,3 do local tree=byPlace[t];if tree then for _,info in pairs(tree)do list[#list+1]=info end end end
 table.sort(list,function(a,b)if a.t~=b.t then return a.t<b.t end;if a.r~=b.r then return a.r<b.r end;return a.c<b.c end)
 return list
end
local function treeName(tree)
 local model=Sim.Model();local t=model and model.talentTrees and model.talentTrees[tree];return t and t.name or('Baum '..tostring(tree))
end

-- opts={tree=1..3}. progress(search) is called after every job; done(build, gainPct) or done(nil, text) at the end.
function Sim.FindBest(opts,progress,done)
 opts=opts or{}
 if Sim.search or Sim.running then return false,'Es läuft schon eine Berechnung'end
 if not Sim.Available('talents')then return false,'Erst ab Stufe 60'end
 local tree=tonumber(opts.tree)or 1
 local start
 for _,t in ipairs(Sim.TopBuilds())do if t.tree==tree then start=Sim.CopyEntries(t.entries)end end
 if not start then return false,'Für diesen Baum gibt es noch keine Vorlage (Vorlagen werden beim Simulieren geladen)'end
 local s={tree=tree,round=0,rounds=ROUNDS,sims=0,label='Start',progress=progress}
 Sim.search=s
 local function finish(build,info)
  Sim.search=nil;Sim.Changed()
  if done then pcall(done,build,info)end
 end
 local entries=start
 local function best(cands)local top,topDps;for _,c in ipairs(cands)do local d=s.scores[c.id];if d and(not topDps or d>topDps)then top,topDps=c,d end end;return top,topDps end
 local function conclude(base)
  -- the build found, measured properly next to the character's own
  local first=start;local changed=Sim.Signature(entries)~=Sim.Signature(first)
  if not changed then return finish(nil,'Die Vorlage ist schon die beste Skillung, die ich finde.')end
  local store=Sim.Store()
  for i=#store.builds,1,-1 do if store.builds[i].source=='search'and store.builds[i].searchTree==tree then Sim.DeleteBuild(store.builds[i].id)end end
  if not Sim.CanAddBuild()then return finish(nil,'Alle '..Sim.MAX_BUILDS..' Plätze für Skillungen sind belegt. Lösche eine und starte die Suche noch einmal.')end
  local b=Sim.AddBuild('Beste '..treeName(tree):sub(1,20),entries,'search');b.searchTree=tree
  s.label='Ergebnis prüfen';report()
  Sim.Compare({{id='live',name='Im Spiel'},{id=b.id,name=b.name,entries=b.entries}},function(rows,issue)
   if not rows then return finish(b,'Gefunden, aber nicht nachgerechnet: '..tostring(issue))end
   local mine,live
   for _,row in ipairs(rows)do if row.id==b.id then mine=row elseif row.id=='live'then live=row end end
   local gain=mine and live and tonumber(mine.dps)and tonumber(live.dps)and live.dps>0 and 100*(mine.dps/live.dps-1)or nil
   finish(b,gain)
  end)
 end
 local function round(base)
  s.round=s.round+1
  if s.round>ROUNDS then return conclude(base)end
  s.label='Runde '..s.round..' von '..ROUNDS..': Punkte prüfen';report()
  -- 1. which point is the least valuable?
  local removals={}
  for i,e in ipairs(entries)do
   local out=Sim.Change(entries,e.t,e.r,e.c,-1)
   if out then removals[#removals+1]={id='r'..i,entries=out,place=e}end
  end
  measure(removals,s.rotation,function(scores,issue)
   if not scores then return finish(nil,issue)end
   s.scores=scores
   table.sort(removals,function(a,b)return(scores[a.id]or-1)>(scores[b.id]or-1)end)   -- dropping it costs the least
   local keep={};for _,r in ipairs(removals)do if scores[r.id]and #keep<CHEAPEST then keep[#keep+1]=r end end
   if #keep==0 then return conclude(base)end
   -- 2. where is a point worth more?
   local adds={};local places=allPlaces();local n=0
   for _,r in ipairs(keep)do
    for _,info in ipairs(places)do
     if not(info.t==r.place.t and info.r==r.place.r and info.c==r.place.c)then
      local out=Sim.Change(r.entries,info.t,info.r,info.c,1)
      if out then n=n+1;adds[#adds+1]={id='a'..n,entries=out}end
     end
    end
   end
   s.label='Runde '..s.round..' von '..ROUNDS..': Punkte verteilen';report()
   measure(adds,s.rotation,function(scores2,issue2)
    if not scores2 then return finish(nil,issue2)end
    s.scores=scores2
    local top,topDps=best(adds)
    if top and topDps>base*(1+MIN_GAIN)then entries=top.entries;s.best=topDps;round(topDps)
    else conclude(base)end
   end)
  end)
 end
 -- the start build first: its damage is what has to be beaten, and its best rotation is used for everything after
 s.label='Vorlage messen';report()
 measure({{id='start',entries=start}},nil,function(scores,issue)
  if not scores or not scores.start then return finish(nil,issue or'Die Vorlage konnte nicht berechnet werden')end
  s.base,s.best=scores.start,scores.start
  round(scores.start)
 end)
 return true
end

-- Refining the rotation ("Eigene Rota verfeinern") -------------------------------------------------------------------
-- ForeverCore.exe tries one row of the best rotation at a new place (rota-tune) and answers with the best neighbour; this
-- repeats while the damage rises, then the result is measured next to the engine's rotation with the full count. A tuned
-- rotation is a name ("eigen:fire:1,0,2,3"), so it goes through every job like any other rotation.
local TUNE_ROUNDS=6
local TUNE_GAIN=0         -- every strictly positive improvement remains a candidate
local TUNE_CONFIRM=0      -- only a strictly positive full-count result is accepted
function Sim.TunedBase(name)return type(name)=='string'and(name:match('^eigen:([^:]+):'))or name end
local function buildFields(spec)
 local b={}
 if spec.entries then b.talents=Sim.Payload(spec.entries)end
 if spec.talentsString and not spec.entries then b.talentsString=spec.talentsString end
 b.gearPreset=spec.gearPreset;b.spec=spec.spec
 return b
end
-- spec = Sim.BuildSpec(id). done(record, gainPct) or done(nil, text). insideRun: called as a step of Sim.RunAll.
function Sim.Tune(spec,progress,done,insideRun)
 if Sim.search or(Sim.running and not insideRun)then return false,'Es läuft schon eine Berechnung'end
 if not Sim.Available('rotation')then return false,'Erst ab Stufe 50'end
 local res=Sim.Result(spec.id)
 local base=res and Sim.TunedBase(res.rotation)
 if not base then return false,'Erst „Beste Rota simmen“ drücken'end
 local s={tune=true,round=0,rounds=TUNE_ROUNDS,sims=0,label='Rotation verfeinern',progress=progress}
 Sim.search=s
 local fields=buildFields(spec)
 local function finish(rec,info)
  Sim.search=nil;Sim.Changed()
  if done then pcall(done,rec,info)end
 end
 local order
 local function confirm()
  local name='eigen:'..base..':'..table.concat(order,',')
  s.label='Ergebnis prüfen';report()
  local function with(rotation)local t={id=rotation==name and'tuned'or'base',rotation=rotation};for k,v in pairs(fields)do t[k]=v end;return t end
  local ctx=Sim.Context()
  local ok=C.Request('talent-compare',{builds={with(name),with(base)},priority=true},function(result,issue)
   if s.cancel then return finish(nil,'abgebrochen')end
   if type(result)~='table'or type(result.builds)~='table'then return finish(nil,issue or'Keine Antwort')end
   local tuned,plain
   for _,row in ipairs(result.builds)do if row.id=='tuned'then tuned=row elseif row.id=='base'then plain=row end end
   if not(tuned and plain and tonumber(tuned.dps)and tonumber(plain.dps))then return finish(nil,'Die verfeinerte Rotation konnte nicht berechnet werden')end
   local gain=100*(tuned.dps/plain.dps-1)
   if plain.dps<=0 or tuned.dps<=plain.dps*(1+TUNE_CONFIRM)then return finish(nil,'Die Änderungen haben sich im genauen Durchlauf nicht bestätigt.')end
   local rec=Sim.Store().results[spec.id]or{}
   local list={{name=name,dps=tonumber(tuned.dps),custom=true}}
   for _,r in ipairs(rec.rotations or{})do if not r.custom then list[#list+1]=r end end
   rec.dps=tonumber(tuned.dps);rec.rotation=name;rec.rotations=C.clean(list);rec.error=nil
   rec.context=ctx;rec.engine=C.engineRevision;rec.at=os and os.time and os.time()or 0
   if spec.id=='live'then rec.priority=C.clean(tuned.priority)end
   Sim.Store().results[spec.id]=rec
   if spec.id=='live'then Sim.SetRotation(rec)end
   finish(rec,gain)
  end,{timeout=300})
  if not ok then finish(nil,'Anfrage nicht moeglich')end
 end
 local function step()
  if s.cancel then return finish(nil,'abgebrochen')end
  s.round=s.round+1
  if s.round>TUNE_ROUNDS then if order then return confirm()end;return finish(nil,'Keine Verbesserung gefunden.')end
  s.label='Runde '..s.round..' von '..TUNE_ROUNDS..': Reihenfolge prüfen';report()
  local ok=C.Request('rota-tune',{build=fields,rotation=base,order=order,iterations=300},function(r,issue)
   if type(r)~='table'or not tonumber(r.dps)then return finish(nil,issue or'Keine Antwort')end
   s.sims=s.sims+(tonumber(r.tried)or 0)+1;report()
   if type(r.bestOrder)=='table'and tonumber(r.bestDps)and r.bestDps>r.dps*(1+TUNE_GAIN)then
    order={};for i,v in ipairs(r.bestOrder)do order[i]=math.floor(v)end
    step()
   else
    if order then confirm()else finish(nil,'Die beste Rotation der Engine lässt sich nicht verbessern.')end
   end
  end,{timeout=300})
  if not ok then finish(nil,'Anfrage nicht moeglich')end
 end
 step()
 return true
end
