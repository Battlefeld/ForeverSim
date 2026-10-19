-- The only Lua rotation search and gear comparison. Damage is exclusively P.run.
local P=FUSLive
P.durations={60,90,120};P.weights={.25,.5,.25};P.cache={};P.cacheOrder={};P.revision=0
local statKeys={'sp','shadowSp','fireSp','frostSp','natureSp','arcaneSp','int','spi','sta','mp5','hitPct','critPct','hastePct','pierce','agi','str','ap','rap','holySp','expertise'}
local ignored={ITEM_MOD_ARMOR_SHORT=true,ITEM_MOD_HEALTH_REGEN_SHORT=true,ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=true,ITEM_MOD_DODGE_RATING_SHORT=true,ITEM_MOD_PARRY_RATING_SHORT=true,RESISTANCE0_NAME=true}
local rawAlias={ITEM_MOD_STRENGTH_SHORT='str',ITEM_MOD_ATTACK_POWER_SHORT='ap',ITEM_MOD_RANGED_ATTACK_POWER_SHORT='rap',ITEM_MOD_HOLY_DAMAGE_SHORT='holySp',ITEM_MOD_EXPERTISE_RATING_SHORT='expertise',ITEM_MOD_SPELL_PENETRATION_SHORT='pierce',ITEM_MOD_AGILITY_SHORT='agi',ITEM_MOD_INTELLECT_SHORT='int',ITEM_MOD_SPIRIT_SHORT='spi',ITEM_MOD_STAMINA_SHORT='sta',ITEM_MOD_SPELL_POWER_SHORT='sp',ITEM_MOD_SPELL_DAMAGE_DONE_SHORT='sp',ITEM_MOD_MANA_REGENERATION_SHORT='mp5',ITEM_MOD_SHADOW_DAMAGE_SHORT='shadowSp',ITEM_MOD_FIRE_DAMAGE_SHORT='fireSp',ITEM_MOD_FROST_DAMAGE_SHORT='frostSp',ITEM_MOD_NATURE_DAMAGE_SHORT='natureSp',ITEM_MOD_ARCANE_DAMAGE_SHORT='arcaneSp'}
-- Tooltip DPS describes the weapon; its min/max/speed already determine damage.
-- It must never be added again as AP, RAP or spell power.
local metadataStats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=true}
for k,v in pairs({ITEM_MOD_HIT_RATING_SHORT='hitPct',ITEM_MOD_SPELL_HIT_RATING_SHORT='hitPct',ITEM_MOD_CRIT_RATING_SHORT='critPct',ITEM_MOD_SPELL_CRIT_RATING_SHORT='critPct',ITEM_MOD_HASTE_RATING_SHORT='hastePct',ITEM_MOD_SPELL_HASTE_RATING_SHORT='hastePct'})do rawAlias[k]=v end
local invSlots={HeadSlot='head',NeckSlot='neck',ShoulderSlot='shoulder',BackSlot='back',ChestSlot='chest',WristSlot='wrist',HandsSlot='hands',WaistSlot='waist',LegsSlot='legs',FeetSlot='feet',Finger0Slot='finger1',Finger1Slot='finger2',Trinket0Slot='trinket1',Trinket1Slot='trinket2',MainHandSlot='mainhand',SecondaryHandSlot='offhand',RangedSlot='ranged'}
local aliases={shadowBolt={'shadow bolt','schattenblitz'},corruption={'corruption','verderbnis'},immolate={'immolate','feuerbrand'},baneOfAgony={'bane of agony','curse of agony','fluch der pein'},lifeTap={'life tap','aderlass'},frostbolt={'frostbolt','frostblitz'},fireball={'fireball','feuerball'},fireBlast={'fire blast','feuerschlag'},lightningBolt={'lightning bolt','blitzschlag'},flameShock={'flame shock','flammenschock'},searingTotem={'searing totem','verbrennungstotem'}}
local spellIds={[686]={'shadowBolt',1},[695]={'shadowBolt',2},[705]={'shadowBolt',3},[1088]={'shadowBolt',4},[1106]={'shadowBolt',5},[7641]={'shadowBolt',6},[11659]={'shadowBolt',7},[11660]={'shadowBolt',8},[11661]={'shadowBolt',9},[25307]={'shadowBolt',10},[172]={'corruption',1},[6222]={'corruption',2},[6223]={'corruption',3},[7648]={'corruption',4},[11671]={'corruption',5},[11672]={'corruption',6},[25311]={'corruption',7},[348]={'immolate',1},[707]={'immolate',2},[1094]={'immolate',3},[2941]={'immolate',4},[11665]={'immolate',5},[11667]={'immolate',6},[11668]={'immolate',7},[980]={'baneOfAgony',1},[1014]={'baneOfAgony',2},[6217]={'baneOfAgony',3},[11711]={'baneOfAgony',4},[11712]={'baneOfAgony',5},[11713]={'baneOfAgony',6},[1454]={'lifeTap',1},[1455]={'lifeTap',2},[1456]={'lifeTap',3},[11687]={'lifeTap',4},[11688]={'lifeTap',5},[11689]={'lifeTap',6}}
P.spellAliases=aliases
function P.normalizeSnapshot(snap)
 local p={class=string.lower(snap.class),level=snap.level,race=snap.race,faction=snap.faction,talents=snap.talents or {},hasSpellbook=true,knownSpellRanks={},petActive=snap.petActive==true,pet=snap.pet,petType=snap.petType,stats=snap.stats or {},soulShards=snap.soulShards or 0,sacrifice=snap.sacrifice,armor=snap.armor,shield=snap.shield,weaponEnhancement=snap.weaponEnhancement,inventory=snap.inventory or {},activeAuras=snap.activeAuras,baseMana=snap.baseMana,targetHealthPct=snap.targetHealthPct,equipped={},bossPlus=snap.bossPlus or(snap.encounter or {}).levelDifference or(snap.level==60 and 3 or 2),encounter=snap.encounter or {},spec=snap.spec,form=snap.form,dualWield=snap.dualWield,weaponEnchants=snap.weaponEnchants,stealthed=snap.stealthed}
 local data=FUSLiveData and FUSLiveData[p.class];local classIds={};local spellData=data;if data and data.combatModes then spellData=P.copy(data);for _,mode in pairs(data.combatModes)do for key,ranks in pairs(mode.abilityOverrides or {})do spellData.abilities[key]=ranks end end end;for k,rs in pairs(spellData and spellData.abilities or {})do for _,r in ipairs(rs)do if r.id then classIds[r.id]={k,r.rank}end end end
 for _,s in ipairs(snap.spells or {})do local key,rank=nil,s.rank or tonumber((s.rankText or ''):match('%d+'));local id=classIds[s.id]or spellIds[s.id]if id then key=id[1];rank=rank or id[2]end
  if not key then for k,names in pairs(data and data.spellAliases or aliases)do for _,n in ipairs(names)do if string.lower(s.name or '')==n then key=k end end end end
  if key and rank then p.knownSpellRanks[key]=p.knownSpellRanks[key]or {};table.insert(p.knownSpellRanks[key],rank)end
 end
 if data and(data.typedCombat or data.specs)and not p.spec then local largest=-1;for index,tree in ipairs(p.talents)do if(tree.points or 0)>largest then largest=tree.points or 0;p.spec=(data.specs or {})[index]end end end
 for _,rs in pairs(p.knownSpellRanks)do table.sort(rs)end
 for _,i in ipairs(snap.equipped or {})do local slot=invSlots[i.slot]or i.slot;p.equipped[slot]=P.copy(i);p.equipped[slot].slot=slot end
 if p.class=='mage'and not p.spec then local biggest=-1;p.spec='frost'for _,tree in ipairs(p.talents)do if(tree.points or 0)>biggest then biggest=tree.points or 0;local n=string.lower(tree.name or '')if n:find('fire')or n:find('feuer')then p.spec='fire'elseif n:find('arcane')or n:find('arkan')then p.spec='arcane'else p.spec='frost'end end end end
 if P.encounters and P.encounters.Apply then
  local resolved,encounterError=P.encounters.Apply(p)
  if not resolved then error(encounterError or 'Encounter ungültig')end
  p=resolved
 end
 return p
end
local function publicNumber(value)
 if P.publicNumber then return P.publicNumber(value)end
 if P.isProtected and P.isProtected(value)then return nil end
 if type(value)~='number' or value~=value or value==math.huge or value==-math.huge then return nil end
 return value
end
local function itemProblem(item,code,message,key,value)
 local info=type(item)=='table' and item or {}
 return message,{code=code,message=message,item=info.name,itemId=info.id,key=key,
  value=publicNumber(value),evaluable=false,bewertbar=false}
end
function P.validateWeaponDps(item)
 local shown=item and(item.displayWeaponDps or(item.rawStats or {}).ITEM_MOD_DAMAGE_PER_SECOND_SHORT)
 if shown==nil then return true end
 shown=publicNumber(shown)
 if not shown or shown<0 then return false,'WEAPON_DPS_INVALID','Waffen-DPS nicht öffentlich verfügbar'end
 local w=item.weapon
 if shown==0 and not w and item.weaponClass~=2 then return true end
 local low,high,speed=w and publicNumber(w.min),w and publicNumber(w.max),w and publicNumber(w.speed)
 if not low or not high or not speed or speed<=0 or low<0 or high<low then
  return false,'WEAPON_DATA_INCOMPLETE','Waffenschaden oder Geschwindigkeit fehlt'
 end
 local calculated=(low+high)*.5/speed
 if math.abs(calculated-shown)>.15 then
  return false,'WEAPON_DPS_MISMATCH','Waffen-DPS und Schadensbereich widersprechen sich',calculated
 end
 return true,nil,nil,calculated
end
function P.itemIssue(item)
 if type(item)~='table' or type(item.stats)~='table' then return itemProblem(item,'ITEM_STATS_MISSING','Itemwerte fehlen')end
 if item.statsComplete==false then return itemProblem(item,'ITEM_STATS_INCOMPLETE','Itemwerte unvollständig')end
 if item.hasUnmodeledEffects then return itemProblem(item,'ITEM_EFFECT_UNMODELED','Nicht modellierter Itemeffekt')end
 for k,v in pairs(item.rawStats or {})do
  local value=publicNumber(v)
  if value==nil then return itemProblem(item,'ITEM_STAT_INVALID','Itemwert nicht öffentlich verfügbar: '..tostring(k),k,v)end
  if value~=0 and not rawAlias[k]and not ignored[k]and not metadataStats[k]then
   return itemProblem(item,'ITEM_STAT_UNMODELED','Nicht modellierter Itemwert: '..tostring(k),k,value)
  end
 end
 for k,v in pairs(item.stats)do
  local value=publicNumber(v)
  if value==nil then return itemProblem(item,'ITEM_STAT_INVALID','Itemwert nicht öffentlich verfügbar: '..tostring(k),k,v)end
  local known=false for _,x in ipairs(statKeys)do if k==x then known=true end end
  if not known and value~=0 then return itemProblem(item,'ITEM_STAT_UNMODELED','Unbekannter Itemwert: '..tostring(k),k,value)end
 end
 local valid,code,message=P.validateWeaponDps(item)
 if not valid then return itemProblem(item,code,message,'ITEM_MOD_DAMAGE_PER_SECOND_SHORT',item.displayWeaponDps)end
end
-- Invalid gear returns a structured problem before any arithmetic or simulation.
function P.tryCombine(equipped)
 local out={}for _,k in ipairs(statKeys)do out[k]=0 end
 for _,item in pairs(equipped or {})do
  local reason,issue=P.itemIssue(item)
  if reason then return nil,issue end
  for _,k in ipairs(statKeys)do out[k]=out[k]+(item.stats[k]or 0)end
  out.itemIds=out.itemIds or {};out.itemIds[#out.itemIds+1]=item.id
 end
 for hand,item in pairs(equipped or {})do
  if hand=='mainhand'or hand=='offhand'or hand=='ranged'then
   if item.weaponClass==2 or item.weapon or item.weaponType then out.weaponItems=out.weaponItems or {};out.weaponItems[hand]=P.copy(item)end
  end
 end
 return out
end
-- Preserve the engine's established contract. User actions use tryCombine for
-- a non-throwing preflight; older protected callers still get a readable reason.
function P.combine(equipped)
 local stats,issue=P.tryCombine(equipped)
 if not stats then error(issue.message..(issue.item and ': '..issue.item or ''),0)end
 return stats
end
function P.score(data,p,stats,choice,runs,stage)
 local value=0
 for i,duration in ipairs(P.durations)do local total=0 for n=0,runs-1 do local seed=(7331+stage*1000003+n*7919+(i-1)*104729)%4294967296;total=total+P.run(P.compile(data,p,stats,choice,duration,seed)).dps end value=value+P.weights[i]*total/runs end return value
end
function P.key(data,p,stats)return P.version..':'..data.revision..':'..P.canonical({class=p.class,form=p.form,stealthed=p.stealthed,weaponEnchants=p.weaponEnchants,level=p.level,race=p.race,faction=p.faction,spec=p.spec,bossPlus=p.bossPlus,encounter=p.encounter,talents=p.talents,knownSpellRanks=p.knownSpellRanks,hasSpellbook=p.hasSpellbook,petActive=p.petActive,pet=p.pet,petType=p.petType,sheet=p.stats,soulShards=p.soulShards,sacrifice=p.sacrifice,baseMana=p.baseMana,targetHealthPct=p.targetHealthPct,armor=p.armor,shield=p.shield,weaponEnhancement=p.weaponEnhancement,inventory=p.inventory,activeAuras=p.activeAuras,equipped=p.equipped,comparisonGear=p.comparisonGear,stats=stats})end
-- A candidate never becomes a recommendation just because it won the search.
-- The incoming starting priority (or the first generated priority) is 100%.
function P.legalChoice(data,p,choice)
 if not choice or not choice.policies then return false end
 for _,policy in ipairs(choice.policies)do if #P.ranks(data,p,policy.key)==0 then return false end end
 return true
end
function P.best(data,p,stats,startChoice)
 local choices=P.candidates(data,p)
 if startChoice and not P.legalChoice(data,p,startChoice)then
  if p.hypotheticalBuild or p.comparisonGear then startChoice=nil else error('Startrotation enthält nicht verfügbare Fähigkeiten.')end
 end
 if #choices==0 and not startChoice then error('Keine erlernte Rotation') end
 local baseline=P.copy(startChoice or choices[1])
 local baselineId=P.canonical(baseline)
 local key=P.key(data,p,stats)..':start:'..baselineId
 if P.cache[key] then return P.copy(P.cache[key]) end
 local ranked,seen={},{}
 local function add(choice,order)
  local id=P.canonical(choice)
  if seen[id] then return end
  seen[id]=true
  ranked[#ranked+1]={choice=P.copy(choice),dps=P.score(data,p,stats,choice,2,1),order=order}
 end
 add(baseline,0)
 for i,c in ipairs(choices)do add(c,i)end
 local function sort(a,b)if a.dps~=b.dps then return a.dps>b.dps end return a.order<b.order end
 table.sort(ranked,sort)
 local finalists={{choice=baseline,order=0}}
 local finalistIds={[baselineId]=true}
 for _,e in ipairs(ranked)do
  if #finalists>=8 then break end
  local id=P.canonical(e.choice)
  if not finalistIds[id] then finalists[#finalists+1]=e;finalistIds[id]=true end
 end
 -- EVERY finalist is rescored on exactly the same final seeds, including 100% baseline.
 for _,e in ipairs(finalists)do e.dps=P.score(data,p,stats,e.choice,7,3)end
 table.sort(finalists,sort)
 local baselineScore
 for _,e in ipairs(finalists)do if P.canonical(e.choice)==baselineId then baselineScore=e.dps;break end end
 local chosen=baseline
 local dps=baselineScore
 local verification=nil
 -- Compare every finalist against the same 100% start on independent seeds.
 -- User rule: ANY measured gain above 0 wins; confidence bands are diagnostic only.
 local bestDiff=0
 for _,candidate in ipairs(finalists)do
  if P.canonical(candidate.choice)~=baselineId then
   local trial=P.paired(data,p,stats,baseline,stats,candidate.choice,12,4)
   if trial.difference>bestDiff then
    bestDiff=trial.difference;chosen=P.copy(candidate.choice);verification=trial
   end
  end
 end
 if verification then baselineScore=verification.baselineDps;dps=verification.candidateDps else dps=baselineScore end
 local accepted=P.canonical(chosen)~=baselineId
 local winner={choice=chosen,dps=dps,baselineDps=baselineScore,percentOfStart=baselineScore>0 and (100*dps/baselineScore) or 100,
               improvementPercent=baselineScore>0 and (100*(dps-baselineScore)/baselineScore) or 0,
               accepted=accepted,status=accepted and 'confirmed_improvement' or 'start_preserved',
               verification=verification,candidatesTested=#ranked,finalistsTested=#finalists}
 if #P.cacheOrder>=64 then local oldest=table.remove(P.cacheOrder,1);P.cache[oldest]=nil end
 P.cache[key]=P.copy(winner);P.cacheOrder[#P.cacheOrder+1]=key
 return winner
end
function P.paired(data,p,oldStats,oldChoice,newStats,newChoice,runs,stage,newProfile)
 local diff,variance,fromDps,toDps=0,0,0,0
 for i,duration in ipairs(P.durations)do
  local samples,total,oldTotal,newTotal={},0,0,0
  for n=0,runs-1 do
   local seed=(7331+stage*1000003+n*7919+(i-1)*104729)%4294967296
   local a=P.run(P.compile(data,p,oldStats,oldChoice,duration,seed)).dps
   local b=P.run(P.compile(data,newProfile or p,newStats,newChoice,duration,seed)).dps
   local d=b-a;samples[#samples+1]=d;total=total+d;oldTotal=oldTotal+a;newTotal=newTotal+b
  end
  local mean=total/runs;local sv=0
  for _,v in ipairs(samples)do sv=sv+(v-mean)^2 end
  sv=sv/math.max(1,runs-1)
  diff=diff+P.weights[i]*mean
  fromDps=fromDps+P.weights[i]*oldTotal/runs
  toDps=toDps+P.weights[i]*newTotal/runs
  variance=variance+P.weights[i]^2*sv/runs
 end
 local margin=1.96*math.sqrt(variance)
 return {difference=diff,baselineDps=fromDps,candidateDps=toDps,margin=margin,lower95=diff-margin,upper95=diff+margin,confirmed=math.abs(diff)>margin}
end

local function eligibility(data,p,item,equipped)
 local issue=P.itemIssue(item)if issue then return issue end
 if(item.minLevel or 1)>p.level then return 'Benötigt Level '..item.minLevel end
 if item.faction and item.faction~=p.faction then return 'Falsche Fraktion'end
 local rules=data.equipmentRules;if not rules then return 'Tragbarkeitsregeln fehlen'end
 local maxArmor=0 for _,tier in ipairs(rules.armorTiers or {})do if p.level>=tier.minLevel then maxArmor=tier.maxSubclass end end
 local armor=item.itemSubclass or ({cloth=1,leather=2,mail=3,plate=4})[string.lower(item.armorType or '')]
 if item.slot~='back'and item.slot~='offhand'and armor and armor>=1 and armor<=4 and(not item.itemClass or item.itemClass==4)and armor>maxArmor then return 'Rüstung nicht tragbar'end
 if item.slot=='offhand'and equipped.mainhand and equipped.mainhand.twoHanded then return 'Zweihandwaffe angelegt'end
 if item.slot=='mainhand'or item.slot=='offhand'or item.slot=='ranged'then
  local wc,ws=item.weaponClass or item.itemClass,item.weaponSubclass or item.itemSubclass
  if wc==nil or ws==nil then return 'Waffentyp nicht erkannt'end
  local function contains(a,v)for _,x in ipairs(a or {})do if x==v then return true end end return false end
  local permitted=wc==2 and contains(rules.weaponSubclasses,ws)
  if item.slot=='ranged'then permitted=wc==2 and contains(rules.rangedSubclasses,ws)end
  if item.slot=='offhand'then permitted=(wc==2 and rules.dualWield and p.dualWield==true and contains(rules.weaponSubclasses,ws))or wc==4 and(item.equipLoc=='INVTYPE_HOLDABLE'or(rules.shield and ws==6))end
  if not permitted then return 'Waffe oder Nebenhand nicht tragbar'end
  if item.twoHanded and not contains(rules.twoHandSubclasses,ws)then return 'Zweihand-Regeln fehlen'end
 end
 for slot,other in pairs(equipped)do if slot~=item.slot and(item.uniqueEquip or item.unique)and item.id==other.id then return 'Einzigartig anlegbar'end end
end
-- Fast eligibility gate shared by live loot prefetch and the regular item comparison.
function P.checkEligibility(data,p,item,equipped)return eligibility(data,p,item,equipped)end
function P.compareSlot(data,p,equipped,item,base)
 local issue=eligibility(data,p,item,equipped)
 if issue then local _,problem=P.itemIssue(item);return {item=item,eligible=false,evaluable=false,bewertbar=false,reason=issue,error=problem}end
 local nextGear=P.copy(equipped);nextGear[item.slot]=item;if item.slot=='mainhand'and item.twoHanded then nextGear.offhand=nil end
 local before,beforeIssue=P.tryCombine(equipped);local after,afterIssue=P.tryCombine(nextGear)
 local problem=beforeIssue or afterIssue
 if problem then return {item=item,eligible=false,evaluable=false,bewertbar=false,reason=problem.message,error=problem}end
 local candidateProfile=P.copy(p);candidateProfile.comparisonGear=nextGear
 base=base or P.best(data,p,before);local trial=P.best(data,candidateProfile,after)
 -- The item preview must use the exact same >100% rule as the rotation optimizer:
 -- test new gear with original AND searched rotations on identical holdout seeds.
 -- Confidence intervals are diagnostic for the item recommendation, not a veto
 -- against a measured positive DPS rotation improvement.
 local old=P.score(data,p,before,base.choice,32,7)
 local legal=true;for _,policy in ipairs(base.choice.policies or {})do if #P.ranks(data,candidateProfile,policy.key)==0 then legal=false;break end end
 local same=legal and P.score(data,candidateProfile,after,base.choice,32,7)or nil
 local new=P.score(data,candidateProfile,after,trial.choice,32,7)
 local wins=not same or new>same
 local choice=wins and trial.choice or base.choice
 if not wins then new=same end
 local holdout=P.paired(data,p,before,base.choice,after,choice,32,7,candidateProfile)
 local result={item=item,eligible=true,evaluable=true,bewertbar=true,baseDps=old,newDps=new,percent=old>0 and 100*(new-old)/old or nil,delta=new-old,newChoice=choice,status=holdout.lower95>0 and 'upgrade'or(holdout.upper95<0 and 'downgrade'or 'uncertain'),confidence95={holdout.lower95,holdout.upper95},rotationChangedRequired=not legal,rotationRules=P.compile(data,candidateProfile,after,choice,90,1).rotationRules,preview=not data.validated}
 if P.leveling then local context=P.leveling.Context(p);if context.targetHealth then result.leveling=P.leveling.Compare(data,p,before,base.choice,after,choice,context,candidateProfile)end end
 return result
end
function P.compare(data,p,equipped,item,base)
 local a=P.compareSlot(data,p,equipped,item,base);local other=({finger1='finger2',finger2='finger1',trinket1='trinket2',trinket2='trinket1'})[item.slot]
 if not other then return a end local alternate=P.copy(item);alternate.slot=other;local b=P.compareSlot(data,p,equipped,alternate,base)if b.eligible and(not a.eligible or b.delta>a.delta)then return b end return a
end
function P.invalidate()P.revision=P.revision+1;P.stale=true;P.lastLeveling=nil end
-- Buffs, auras, pets, forms, zoning and bag changes do NOT change item comparisons.
-- Only level, worn gear and talent ranks do; everything else must keep the caches.
function P.stateSignature()
 local parts={tostring(UnitLevel and UnitLevel('player') or 0)}
 if GetInventoryItemLink then for slot=1,19 do local ok,link=pcall(GetInventoryItemLink,'player',slot);parts[#parts+1]=ok and type(link)=='string' and link or '' end end
 if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
  local ok=pcall(function()
   for tab=1,(GetNumTalentTabs() or 0) do for i=1,(GetNumTalents(tab) or 0) do local _,_,_,_,rank=GetTalentInfo(tab,i);parts[#parts+1]=tostring(rank or 0) end end
  end)
 end
 return table.concat(parts,'|')
end
-- True (and invalidates) only when the signature differs from the last one this caller saw.
function P.stateChanged(owner)
 local sig=P.stateSignature()
 if owner.sig==sig then return false end
 owner.sig=sig
 return true
end

-- Local, class-neutral priority tuner. Begins with a supplied, explicit policy
-- (e.g. a faithfully imported XN build) instead of substituting a generic preset.
-- Optimizes only with our Lua combat engine; XN results are never fed to scoring.
function P.rotationNeighbors(choice)
 local out,seen={},{}
 local function add(c,reason)
  if #c.policies==0 then return end
  local id=P.canonical(c);if not seen[id]then seen[id]=true;out[#out+1]={choice=c,reason=reason}end
 end
 add(P.copy(choice),'original')
 for i,policy in ipairs(choice.policies or {})do
  if i<#choice.policies-1 then
   local c=P.copy(choice);c.policies[i],c.policies[i+1]=c.policies[i+1],c.policies[i]
   add(c,'Priorität '..policy.key..' / '..choice.policies[i+1].key..' tauschen')
  end
  -- Final (non-maintained) filler cannot be removed.
  if i<#choice.policies then local c=P.copy(choice);table.remove(c.policies,i);add(c,policy.key..' weglassen')end
  if policy.maintain and i<#choice.policies then
   local refresh=P.copy(choice);refresh.policies[i].refreshAtCastTime=not policy.refreshAtCastTime;add(refresh,'Erneuerung zum Ende der Wirkzeit: '..policy.key)
   for _,threshold in ipairs({0,8,15,25,40,60})do
    if (policy.minRemaining or 0)~=threshold then
     local c=P.copy(choice);c.policies[i].minRemaining=threshold>0 and threshold or nil
     add(c,policy.key..' nicht erneuern bei < '..threshold..' Sekunden')
    end
   end
  end
 end
 for _,tap in ipairs({.2,.35,.5,.65,.8})do
  if math.abs((choice.tapAtPct or 0)-tap)>.001 then local c=P.copy(choice);c.tapAtPct=tap;add(c,'Life Tap unter '..math.floor(tap*100)..'% Mana')end
 end
 if choice.channelClip~=nil then local c=P.copy(choice);c.channelClip=not c.channelClip;add(c,'Kanal abbrechen '..tostring(c.channelClip))end
 return out
end
function P.rotationTrial(data,p,gear,choice,durations,seeds)
 local dps=0
 for _,duration in ipairs(durations)do
  for _,seed in ipairs(seeds)do
   local spec=P.compile(data,p,gear,choice,duration,seed)
   if p.rotationTrialOverrides then p.rotationTrialOverrides(spec) end
   dps=dps+P.run(spec).dps
  end
 end
 return dps/(#durations*#seeds)
end
-- Paired samples, using identical durations and seeds for start and candidate.
-- Used only on unseen validation seeds, never on seeds used to tune a choice.
function P.rotationPairTrial(data,p,gear,startChoice,otherChoice,durations,seeds,z)
 local changes,total={},0
 local startSum,candidateSum=0,0
 for _,duration in ipairs(durations)do
  for _,seed in ipairs(seeds)do
   local a=P.compile(data,p,gear,startChoice,duration,seed)
   local b=P.compile(data,p,gear,otherChoice,duration,seed)
   if p.rotationTrialOverrides then p.rotationTrialOverrides(a);p.rotationTrialOverrides(b)end
   local aDps=P.run(a).dps;local bDps=P.run(b).dps
   startSum=startSum+aDps;candidateSum=candidateSum+bDps
   local delta=bDps-aDps;changes[#changes+1]=delta;total=total+delta
  end
 end
 local n=#changes;local mean=total/n
 local variance=0
 for _,v in ipairs(changes)do variance=variance+(v-mean)^2 end
 variance=variance/math.max(1,n-1)
 local margin=(z or 2.58)*math.sqrt(variance/n)
 return {baselineDps=startSum/n,candidateDps=candidateSum/n,difference=mean,
         margin=margin,lower=mean-margin,upper=mean+margin,samples=n,
         relativePercent=startSum>0 and (100*candidateSum/startSum) or 100}
end

-- Guaranteed starting rotation: 100%, always preserved on equal, negative or
-- unverified gains. Search only proposes alternatives; validation alone accepts.
-- No class module, learned rotation or live addon default is modified here.
function P.tuneRotation(data,p,gear,base,opts)
 opts=opts or {}
 assert(base and base.policies and #base.policies>0,'Startrotation fehlt')
 local durations=opts.durations or {108,120,132}
 local seeds=opts.seeds or {31211,48817,81721}
 local validationSeeds=opts.validationSeeds or {178651,191789,205279,219103,232369,247301,260849,274073,289157,302147,316241,330431,344219,358633,370873,386017,399911,413921}
 assert(#durations>0 and #seeds>0 and #validationSeeds>=2,'Leere Seed- oder Kampfdauerliste')
 local used={}
 for _,seed in ipairs(seeds)do used[seed]=true end
 for _,seed in ipairs(validationSeeds)do assert(not used[seed],'Validierungs-Seeds müssen neu sein')end
 local startChoice=P.copy(base);local startId=P.canonical(startChoice)
 local current=P.copy(startChoice);local tested,history=0,{}
 local function trial(choice,ds,ss)
  tested=tested+1;return P.rotationTrial(data,p,gear,choice,ds,ss)
 end
 local baseTraining=trial(startChoice,durations,seeds)
 local currentTraining=baseTraining
 local discovered={[startId]={choice=P.copy(startChoice),reason='Startrotation',score=baseTraining}}
 for round=1,(opts.rounds or 2)do
  local neighbors=P.rotationNeighbors(current)
  local shortlist={}
  for _,neighbor in ipairs(neighbors)do
   local id=P.canonical(neighbor.choice)
   local quick=trial(neighbor.choice,{durations[math.min(2,#durations)]},{seeds[1]})
   shortlist[#shortlist+1]={choice=neighbor.choice,reason=neighbor.reason,quick=quick,id=id}
  end
  table.sort(shortlist,function(a,b)if a.quick~=b.quick then return a.quick>b.quick end return a.id<b.id end)
  local top=math.min(opts.finalists or 6,#shortlist)
  local best={choice=current,score=currentTraining,reason='Beibehalten',id=P.canonical(current)}
  for j=1,top do
   local candidate=shortlist[j]
   candidate.score=trial(candidate.choice,durations,seeds)
   local old=discovered[candidate.id]
   if not old or candidate.score>old.score then discovered[candidate.id]={choice=P.copy(candidate.choice),reason=candidate.reason,score=candidate.score}end
   if candidate.score>best.score or (candidate.score==best.score and candidate.id<best.id)then best=candidate end
  end
  history[#history+1]={round=round,neighbors=#neighbors,leading=best.reason,leadingDps=best.score,baselineDps=baseTraining}
  if best.score<=currentTraining+(opts.minGain or 0.05) or best.id==P.canonical(current) then break end
  current=P.copy(best.choice);currentTraining=best.score
 end
 -- The holdout does not direct exploration. It only decides the recommendation.
 local candidates={}
 for id,entry in pairs(discovered)do if id~=startId then candidates[#candidates+1]={id=id,choice=entry.choice,reason=entry.reason,score=entry.score}end end
 table.sort(candidates,function(a,b)if a.score~=b.score then return a.score>b.score end return a.id<b.id end)
 local maxChecks=math.min(opts.validationFinalists or 5,#candidates)
 local winner=nil;local comparisons={}
 local referenceScore=trial(startChoice,durations,validationSeeds)
 local minPercent=opts.minGainPercent or 0
 local minDps=opts.minGainDps or 0
 for j=1,maxChecks do
  local candidate=candidates[j]
  local result=P.rotationPairTrial(data,p,gear,startChoice,candidate.choice,durations,validationSeeds,opts.validationZ or 2.58)
  tested=tested+2
  result.reason=candidate.reason;result.choiceId=candidate.id;result.trainingDps=candidate.score
  result.confirmed=result.difference>0 and result.relativePercent>100
  comparisons[#comparisons+1]=result
  if result.confirmed and (not winner or result.candidateDps>winner.result.candidateDps)then winner={choice=candidate.choice,result=result,reason=candidate.reason}end
 end
 local accepted=winner~=nil
 local selected=accepted and P.copy(winner.choice) or P.copy(startChoice)
 local result=accepted and winner.result or nil
 return {baseline=referenceScore,optimized=accepted and result.candidateDps or referenceScore,
         percentOfStart=accepted and result.relativePercent or 100,
         improvementPercent=accepted and (result.relativePercent-100) or 0,
         accepted=accepted,status=accepted and 'confirmed_improvement' or 'start_preserved',
         choice=selected,startChoice=startChoice,history=history,comparisons=comparisons,
         chosenReason=accepted and winner.reason or 'Startrotation beibehalten',
         tested=tested,validationSamples=#durations*#validationSeeds,
         confidenceLowerDps=accepted and result.lower or 0,
         searchedCandidates=#candidates}
end

