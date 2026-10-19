-- Short single-target fights use the same engine as boss DPS. Recovery is explicit.
local P=FUSLive;local L={};P.leveling=L
local function settings()ForeverSimBridgeDB=ForeverSimBridgeDB or {};ForeverSimBridgeDB.leveling=ForeverSimBridgeDB.leveling or {};return ForeverSimBridgeDB.leveling end
local function usableHealth(value)
 if P.publicNumber then value=P.publicNumber(value)
 elseif P.isProtected and P.isProtected(value)then return nil end
 if type(value)~='number'or value~=value or value==math.huge or value==-math.huge or value<=0 or value>=10000000 then return nil end
 return value
end
function L.Context(profile)
 local opts={}
 for _,key in ipairs({"targetHealth","targetLevel","moveSeconds","manaPerSecond","healthPerSecond","incomingDamage","hitEvery"})do opts[key]=settings()[key]end
 local observed=P.combatAudit and P.combatAudit.levelingContext and P.combatAudit.levelingContext(profile)
 if not observed and P.targetHealth then observed=P.targetHealth.Observation(profile)end
 local health,problem
 if P.targetHealth then health,problem=P.targetHealth.Resolve(profile,opts,observed)end
 if health then for k,v in pairs(health)do opts[k]=v end
 elseif problem then opts.targetHealth=nil;opts.healthError=problem
 else opts.source=opts.targetHealth and 'Manuelle HP-Eingabe (nicht verifiziert)' or 'HP-Provider nicht verfügbar'end
 -- Recovery and incoming damage belong to the observed enemy level. Never mix
 -- a previous mob's damage into a different manually selected benchmark.
 if observed and observed.targetLevel==opts.targetLevel then
  for _,k in ipairs({'incomingDamage','hitEvery'})do if opts[k]==nil then opts[k]=observed[k]end end
 end
 opts.targetLevel=opts.targetLevel or profile.level;opts.moveSeconds=opts.moveSeconds or 3
 return opts
end
local function evaluate(data,profile,gear,choice,opts)
 opts=opts or L.Context(profile)
 if profile.level<(profile.minSimLevel or P.minSimLevel()) then return {available=false,reason='SIM erst ab Level '..P.minSimLevel()}end
 local targetHealth=usableHealth(opts.targetHealth)
 if not targetHealth then return {available=false,reason=opts.healthError and opts.healthError.message or 'Gegnerleben fehlt oder ist nicht öffentlich verfügbar; HP-Modell oder /fus leveling health ZAHL verwenden',error=opts.healthError}end
 local p=P.copy(profile);p.bossPlus=(opts.targetLevel or p.level)-p.level;p.encounter=P.copy(p.encounter or {})
 p.encounter.levelDifference=p.bossPlus;p.encounter.targetLevel=opts.targetLevel or p.level
 -- Re-resolve the defense model for the actual leveling-target level, not a cached boss.
 if P.encounters and (p.encounter.armorAssumed or p.encounter.armor==nil) then
  p.encounter.armor=nil;p.encounter.mode='quest';p.encounter._profileResolved=nil
  local resolved=P.encounters.Apply(p)
  if resolved then p=resolved end
 end
 p.encounter.hitEvery=opts.hitEvery or 0;p.encounter.incomingDamage=opts.incomingDamage
 p.targetHealthPct=nil
 local total,kill,mana,health,recovery,failures,scored=0,0,0,0,0,0,0;local runs=opts.runs or 8
 for n=1,runs do
  local spec=P.compile(data,p,gear,choice,opts.maxFightSeconds or 90,99173+n*7919);spec.targetHP=targetHealth
  local r=P.run(spec);local duration=r.killTime or r.deathTime or spec.duration
  if r.killed then
   local manaSpent=math.max(0,spec.initial.mana-r.manaEnd);local healthSpent=math.max(0,spec.initial.health-r.healthEnd)
   local move=opts.moveSeconds or 3
   local manaRate=opts.manaPerSecond or math.max(0,spec.naturalRegen+(spec.mp5 or 0)/5)
   local healthRate=opts.healthPerSecond
   local delay=opts.manaPerSecond and 0 or 5
   local remainingMana=math.max(0,manaSpent-manaRate*math.max(0,move-delay))
   local manaWait=remainingMana==0 and 0 or manaRate>0 and (math.max(0,delay-move)+remainingMana/manaRate) or nil
   local healthWait=healthSpent==0 and 0 or healthRate and healthRate>0 and math.max(0,healthSpent-healthRate*move)/healthRate or nil
   if manaWait and healthWait then
    scored=scored+1;local rest=math.max(manaWait,healthWait);recovery=recovery+rest;total=total+duration+move+rest
   end
   kill=kill+duration;mana=mana+manaSpent;health=health+healthSpent
  else failures=failures+1 end
  if P.checkpoint then P.checkpoint()end
 end
 local complete=failures==0 and scored==runs and total>0
 return {available=true,sustainable=complete,killsPerMinute=complete and runs*60/total or nil,
  killSeconds=failures<runs and kill/(runs-failures) or nil,recoverySeconds=complete and recovery/runs or nil,
  manaSpent=failures<runs and mana/(runs-failures)or nil,healthSpent=failures<runs and health/(runs-failures)or nil,
  failures=failures,runs=runs,context=P.copy(opts),reason=failures>0 and 'Nicht jeder Modellkampf gewonnen' or not complete and 'Erholungsrate fehlt' or 'Einzelziel-Modell inkl. Erholung',
  caveat=opts.incomingDamage and 'Gegnerschaden konstant aus Beobachtung/Angabe; Kontrolle und Rüstungsänderungen nur teilweise modelliert.' or 'Gegnerschaden fehlt; keine Aussage zur Überlebensfähigkeit.'}
end
L.cache={};L.order={}
function L.Evaluate(data,profile,gear,choice,opts)
 opts=opts or L.Context(profile)
 if profile.level<(profile.minSimLevel or P.minSimLevel()) or not usableHealth(opts.targetHealth) then return evaluate(data,profile,gear,choice,opts)end
 local key=tostring(P.revision)..':'..P.key(data,profile,gear)..':'..P.canonical({choice=choice,context=opts})
 if L.cache[key]then return P.copy(L.cache[key])end
 local r=evaluate(data,profile,gear,choice,opts)
 if #L.order>=64 then local old=table.remove(L.order,1);L.cache[old]=nil end
 L.order[#L.order+1]=key;L.cache[key]=P.copy(r)
 return r
end
function L.Compare(data,p,before,oldChoice,after,newChoice,opts,newProfile)
 opts=opts or L.Context(p)
 local a=L.Evaluate(data,p,before,oldChoice,opts);local b=L.Evaluate(data,newProfile or p,after,newChoice,opts)
 return {baseline=a,candidate=b,percent=a.killsPerMinute and b.killsPerMinute and 100*(b.killsPerMinute/a.killsPerMinute-1) or nil}
end
function L.Text(r)
 if not r or not r.available then return r and r.reason or 'Leveltempo noch nicht berechnet'end
 local source=r.context and r.context.source or 'Quelle nicht angegeben'
 if r.killsPerMinute then return string.format('Modell: %.2f Gegner/min · %.1f s Kampf · %.1f s Erholung · HP: %s',r.killsPerMinute,r.killSeconds,r.recoverySeconds,source)end
 return (r.killSeconds and string.format('Modell: %.1f s bis Kill · ',r.killSeconds)or '')..r.reason..' · HP: '..source
end
function L.Optimize(autoApply)
 if InCombatLockdown and InCombatLockdown()then print('Forever SIM: Levelvergleich außerhalb des Kampfes.');return end
 local snap=P.capture(true);local p=P.normalizeSnapshot(snap);local data=FUSLiveData[p.class]
 if not data then print('Forever SIM: Klassenmodul fehlt.');return end
 local issue=P.coverage(data,p);if issue then print('Forever SIM: '..issue);return end
 local context=L.Context(p);if not context.targetHealth then print('Forever SIM: '..L.Evaluate(data,p,{},nil,context).reason);return end
 local gear,gearIssue=P.tryCombine(p.equipped)
 if not gear then P.lastItemError=gearIssue;print('Forever SIM: '..gearIssue.message..'; Levelvergleich nicht verfügbar.');return end
 local start=P.lastRotation and not P.stale and P.lastRotation.choice or P.candidates(data,p)[1]
 if not start then print('Forever SIM: Keine gelernte Rotation.');return end
 P.enqueue(function()
  local baseline=L.Evaluate(data,p,gear,start,context);local best={choice=start,result=baseline};local seen={}
  local choices={start};for _,c in ipairs(P.candidates(data,p))do choices[#choices+1]=c end
  for _,c in ipairs(choices)do local key=P.canonical(c)
   if not seen[key]then
    seen[key]=true;local r=L.Evaluate(data,p,gear,c,context)
    if r.killsPerMinute and (not best.result.killsPerMinute or r.killsPerMinute>best.result.killsPerMinute)then best={choice=P.copy(c),result=r}end
   end
  end
  return {baseline=baseline,choice=best.choice,result=best.result,signature=P.combatAudit and P.combatAudit.Signature(p),revision=P.revision}
 end,function(result,err)
  if err then P.lastLiveError=tostring(err);print('Forever SIM: Levelvergleich derzeit nicht verfügbar.');return end
  P.lastLeveling=result;settings().result=P.copy(result)
  print('Forever SIM: '..L.Text(result.result));print('Forever SIM: '..result.result.caveat)
  if autoApply then L.Apply()elseif P.analysisUI then P.analysisUI.Show('leveling')end
 end)
end
function L.Apply()
 local result=P.lastLeveling
 if not result or not result.result.killsPerMinute or not result.baseline.killsPerMinute then print('Forever SIM: Zuerst einen vollständigen Levelvergleich berechnen.');return end
 if InCombatLockdown and InCombatLockdown()then return end
 local p=P.normalizeSnapshot(P.capture(true));local data=FUSLiveData[p.class]
 if result.revision~=P.revision or P.combatAudit and result.signature~=P.combatAudit.Signature(p)then print('Forever SIM: Charakter verändert; Levelvergleich neu starten.');return end
 local gear,gearIssue=P.tryCombine(p.equipped)
 if not gear then P.lastItemError=gearIssue;print('Forever SIM: '..gearIssue.message..'; Levelrotation nicht verfügbar.');return end
 P.enqueue(function()
  local dps=P.score(data,p,gear,result.choice,4,21)
  local base=result.baseline.killsPerMinute;local chosen=result.result.killsPerMinute
  return {purpose='leveling',choice=P.copy(result.choice),dps=dps,baselineDps=dps,
   percentOfStart=100*chosen/base,improvementPercent=100*(chosen/base-1),accepted=chosen>base,
   killsPerMinute=chosen,baselineKillsPerMinute=base,candidatesTested=0}
 end,function(r,err)
  if not r then P.lastLiveError=tostring(err);print('Forever SIM: Levelrotation derzeit nicht verfügbar.');return end
  P.lastRotation=r;P.stale=false;ForeverSimBridgeDB.rotationGoal='leveling'
  if P.rotationHUD then P.rotationHUD.configure(data,p,r)end
  print('Forever SIM: Levelrotation aktiv · '..string.format('%.2f Modell-Gegner/min',r.killsPerMinute)..'. /fus optimize wechselt zu Boss-DPS.')
 end)
end
function L.Command(msg)
 if msg=='leveling' then L.Optimize();return true end
 if msg=='leveling apply' then L.Apply();return true end
 local key,v=msg:match('^leveling%s+(%w+)%s+([%d.]+)$');v=tonumber(v)
 local keys={health='targetHealth',level='targetLevel',mana='manaPerSecond',heal='healthPerSecond',move='moveSeconds',damage='incomingDamage',hit='hitEvery'}
 if keys[key] and v and v>=0 and v<10000000 and (key~='health' or v>0) and (key~='level' or v>=1)then
  settings()[keys[key]]=v;P.invalidate();print('Forever SIM: Levelvergleich '..key..' = '..v);return true
 end
 if msg=='leveling reset' then ForeverSimBridgeDB.leveling={};P.invalidate();return true end
end

