-- Class-neutral compiler extensions. No alternative damage simulator.
local P=FUSLive
local copy=P.copy
local function contains(xs,k)if not xs then return true end for _,v in ipairs(xs)do if v==k then return true end end return false end
-- True when one of the profile's active auras has one of the given (lower-case) names.
-- Auras are stored as spell IDs; names are resolved through the client (enUS/deDE lists).
function P.hasAuraNamed(p,names)
 for _,id in ipairs(p and p.activeAuras or {})do
  local name=type(id)=='string' and id or (P.spellDisplay and P.spellDisplay(id))
  if type(name)=='string' then name=string.lower(name);for _,n in ipairs(names)do if name==n then return true end end end
 end
 return false
end
local function clamp(n,lo,hi)return math.max(lo,math.min(hi,n))end
function P.float32(n)
 if n==0 then return 0 end
 local sign=n<0 and -1 or 1;n=math.abs(n)
 local _,exp=math.frexp(n);local step=2^math.max(-149,exp-24);local q=n/step;local base=math.floor(q);local f=q-base
 if f>.5 or(f==.5 and base%2==1)then base=base+1 end
 return sign*base*step
end
function P.clientAverage(effect,level)
 local base=effect.base or effect.BasePoints or 0;local start=effect.start or effect.SpellLevel or 0;local cap=effect.cap or effect.MaxLevel or 0
 local delta=math.max(0,(cap>0 and math.min(level,cap)or level)-start)
 return math.floor(P.float32(P.float32(base)+P.float32(P.float32(delta)*P.float32(effect.perLevel or effect.PPL or 0))))
end
function P.physicalTable(levelDifference,hit,crit,expertise,white,dual,front)
 local d=math.min(3,math.max(-1,levelDifference));local idx=d+2
 local miss=({.04,.05,.055,.06,.08})[idx];local dodge=({.04,.05,.055,.06,.065})[idx]
 local parry=front and({.04,.05,.055,.06,.14})[idx]or 0
 return {miss=math.max(0,miss+(white and dual and .19 or 0)-(hit or 0)+ (d==3 and(hit or 0)>0 and .01 or 0)),dodge=math.max(0,dodge-(expertise or 0)*.0025),parry=math.max(0,parry-(expertise or 0)*.0025),block=front and .05 or 0,glance=white and({0,.1,.2,.3,.4})[idx]or 0,glanceMultiplier=({.95,.95,.95,.85,.65})[idx],glanceSpread=({.04,.04,.04,.05,.1})[idx],crit=math.max(0,(crit or 0)-({0,0,.01,.02,.048})[idx])}
end
local modeCache=setmetatable({}, {__mode='k'})
function P.classModel(data,p)
 local mode=data.combatModes and data.combatModes[p.spec]
 if not mode then return data end
 local cache=modeCache[data];if cache and cache[p.spec]then return cache[p.spec]end
 local model=copy(data);model.combatModes=nil
 for key,value in pairs(mode)do if key~='abilityOverrides'then model[key]=copy(value)end end
 for key,ranks in pairs(mode.abilityOverrides or {})do model.abilities[key]=copy(ranks)end
 modeCache[data]=modeCache[data]or {};modeCache[data][p.spec]=model
 return model
end
local legacyRanks=P.ranks
function P.ranks(data,p,key)
 data=P.classModel(data,p)
 local rs=legacyRanks(data,p,key)
 local allowed={};local gear=p.comparisonGear or p.equipped or {};local talents=P.talents(data,p);local form=p.form or(data.id=='warrior'and'battle'or'caster')
 local ws=copy((p.stats or {}).weapons or {})
 if p.comparisonGear then
  for _,hand in ipairs({'mainhand','offhand','ranged'})do
   local item=gear[hand];local old=(p.equipped or {})[hand]
   if not item then ws[hand]=nil
   elseif not old or(item.link or item.id)~=(old.link or old.id)then
    ws[hand]=item.weaponClass==2 and copy(item.weapon or {subclass=item.weaponSubclass})or nil
   end
  end
 end
 for _,r in ipairs(rs)do if(not r.requiresSpellbook or p.hasSpellbook)and contains(r.forms,form)and(not r.weaponSubclasses or ws.mainhand and contains(r.weaponSubclasses,ws.mainhand.subclass))and(not r.requiredOffhandSubclass or ws.offhand and ws.offhand.subclass==r.requiredOffhandSubclass)and(not r.behindUnlessTalent or(talents[r.behindUnlessTalent]or 0)>0 or(p.encounter or {}).inFront~=true)and(not r.behindRequired or(p.encounter or {}).inFront~=true)and(not r.shieldRequired or gear.offhand and gear.offhand.equipLoc=='INVTYPE_SHIELD')then allowed[#allowed+1]=r end end
 if data.typedCombat and data.abilities[key]and data.abilities[key][1].alwaysKnown then allowed={data.abilities[key][1]}end
 return allowed
end
local legacyCoverage=P.coverage
function P.coverage(data,p)
 data=P.classModel(data,p)
 local issue=legacyCoverage(data,p);if issue then return issue end
 if not data.typedCombat then return end
 local t=P.talents(data,p)
 if(p.encounter or {}).targetCount and p.encounter.targetCount~=1 then return 'Dieses Klassenmodell unterstützt derzeit Einzelzielkämpfe.'end
 if type((p.encounter or {}).hitEvery)=='number' and p.encounter.hitEvery>0 and (p.encounter.incomingDamage or 0)>0 then for _,k in ipairs(data.encounterUnsupportedTalents or {})do if(t[k]or 0)>0 then return 'Talentregel für eingehenden Schaden fehlt: '..k end end end
 for _,k in ipairs(P.sortedKeys(data.unsupportedTalents or {}))do if(t[k]or 0)>0 then return 'Talentregel noch nicht vollständig: '..data.unsupportedTalents[k]end end
 if data.id=='rogue'and p.weaponEnchants then local mh=data.weaponEnchantRules[tostring(p.weaponEnchants.mainhand)];local oh=data.weaponEnchantRules[tostring(p.weaponEnchants.offhand)];if mh and oh and mh.spellKey=='deadlyPoison'and oh.spellKey=='deadlyPoison'and p.weaponEnchants.mainhand~=p.weaponEnchants.offhand then return 'Unterschiedliche Ränge von Deadly Poison auf beiden Waffen sind noch nicht modelliert.'end end
 if data.weaponEnchantRules then if not p.weaponEnchants then return 'Waffenverzauberungen konnten nicht gelesen werden.'end;for _,id in pairs(p.weaponEnchants)do if id~=0 and not data.weaponEnchantRules[tostring(id)]then return 'Waffenverzauberungsregel fehlt: '..tostring(id)end end end
 local s=p.stats or {}
 for _,k in ipairs({'health','intellect','spirit','mana'})do if type(s[k])~='number'or s[k]<0 then return 'Charakterwert fehlt: '..k end end
 if p.petActive then for _,k in ipairs(P.sortedKeys(data.unsupportedPetTalents or {}))do if(t[k]or 0)>0 then return 'Begleiterregel noch nicht vollständig: '..data.unsupportedPetTalents[k]end end;local pet=p.pet or {};if not data.genericPet or not pet.melee or not pet.critPct or not pet.hasSpellbook then return 'Begleiterwerte oder Begleiter-Zauberbuch fehlen.'end end
 local mode=data.autoAttack or(p.form=='cat'or p.form=='bear')and'mainhand'
 if mode then
  if type(mode=='ranged'and s.rangedCritPct or s.meleeCritPct)~='number'then return 'Kritischer Trefferwert fehlt: '..mode end
  local weapon=(s.weapons or {})[mode]
  if not weapon or type(weapon.min)~='number'or type(weapon.max)~='number'or not weapon.speed or weapon.speed<=0 then return 'Waffenwerte fehlen: '..mode end
  if type(s.attackPower)~='number'and mode~='ranged'or mode=='ranged'and type(s.rangedAttackPower)~='number'then return 'Angriffskraft fehlt: '..mode end
 end
end
local legacyCompile=P.compile
-- Talents whose effect is a plain character-sheet stat (crit, AP, ...). The sheet read
-- from the client already contains LIVE talents, so only the difference between the
-- profile's talents and the live talents is applied (drafts in the talent planner).
-- Values per rank are Forever beta tooltips (foreverdb.net, build 1.60.1.70338).
-- Rebase captured character-sheet values instead of replacing them with generic
-- class base stats. Rules come exclusively from the loaded class model.
local function ruleValue(rule,ranks)
 if rule.constant~=nil then return rule.constant end
 local n=ranks[rule.talent]or 0
 return rule.values and(rule.values[n]or 0)or n*(rule.perRank or 0)
end
-- MythicSim cca7ffd: sim/{hunter,rogue,warlock,...} class stat dependencies.
local function strengthAP(data)return (data.id=='rogue'or data.id=='hunter'or data.id=='warlock')and 1 or 2 end
local function agilityAP(data,p)return (data.id=='rogue'or data.id=='hunter'or p.form=='cat')and 1 or 0 end
function P.applyAttributeTalentDeltas(data,p)
 if not p.stats or not p.liveTalentRanks then return p end
 local current=P.talents(data,p);local live=p.liveTalentRanks
 if P.canonical(current)==P.canonical(live)then return p end
 local out=copy(p);local s,old=out.stats,p.stats
 local function factor(field,ranks)
  local f=1;for _,r in ipairs(data.attributeModifiers or {})do if r.field==field then f=f*(1+ruleValue(r,ranks))end end;return f
 end
 local delta={}
 for _,field in ipairs({'intellect','spirit','strength','agility','stamina'})do
  if type(old[field])=='number'then s[field]=old[field]/factor(field,live)*factor(field,current);delta[field]=s[field]-old[field]else delta[field]=0 end
 end
 local a=copy(data.attributes or {});for k,v in pairs((data.levelStats or {})[tostring(p.level)]or {})do a[k]=v end
 if old.mana then s.mana=(old.mana/factor('mana',live)+delta.intellect*(a.manaPerInt or 15))*factor('mana',current)end
 if old.health and delta.stamina~=0 then s.health=old.health+delta.stamina*(a.healthPerSta or 10)end
 local spellCrit=old.critPerIntellect or(a.intPerCrit and 1/a.intPerCrit)
 local agiCrit=old.critPerAgility or(p.level==60 and ({warrior=.05,paladin=.0506,hunter=.0189,rogue=.0345,druid=.05})[data.id])
 if delta.agility~=0 and not agiCrit then error('Krit-Umrechnung für Beweglichkeit fehlt für diesen Talententwurf.')end
 for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do
  if old[school..'Crit']and spellCrit then s[school..'Crit']=old[school..'Crit']+delta.intellect*spellCrit end
 end
 for _,key in ipairs({'meleeCritPct','critPct','rangedCritPct'})do if old[key]then s[key]=old[key]+delta.agility*(agiCrit or 0)end end
 if old.attackPower then s.attackPower=old.attackPower+delta.strength*strengthAP(data)+delta.agility*agilityAP(data,p)end
 if old.rangedAttackPower then s.rangedAttackPower=old.rangedAttackPower+delta.agility*2 end
 for _,r in ipairs(data.contextModifiers or {})do
  if r.field=='intellectAttackPower'then
   local v=(s.intellect or 0)*ruleValue(r,current)-(old.intellect or 0)*ruleValue(r,live)
   if s.attackPower then s.attackPower=s.attackPower+v end;if s.rangedAttackPower then s.rangedAttackPower=s.rangedAttackPower+v end
  end
 end
 local powerDelta=0
 for _,r in ipairs(data.staticRules or {})do
  local field=r.field=='spiritPower'and'spirit'or r.field=='strengthPower'and'strength'
  if field then powerDelta=powerDelta+(s[field]or 0)*ruleValue(r,current)-(old[field]or 0)*ruleValue(r,live)end
 end
 for _,r in ipairs(data.modifiers or {})do
  local diff=ruleValue(r,current)-ruleValue(r,live)
  local active=(not r.actorActive or p.petActive)and(not r.profileField or contains(r.profileValues,p[r.profileField]))
  if active and not r.targets and r.field=='crit'then
   for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do if s[school..'Crit']and contains(r.schools,school)then s[school..'Crit']=s[school..'Crit']+100*diff end end
  elseif active and r.skipIfCapturedPower and r.field=='sp'then
   local amount=diff*(r.perLevel and p.level or 1)
   for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do if s[school..'Power']and contains(r.schools,school)then s[school..'Power']=s[school..'Power']+amount end end
  end
 end
 for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do if s[school..'Power']then s[school..'Power']=s[school..'Power']+powerDelta end end
 if old.pierce then for _,r in ipairs(data.penetrationModifiers or {})do s.pierce=s.pierce+ruleValue(r,current)-ruleValue(r,live)end end
 local regen=data.spiritRegeneration or {};local regenDelta=delta.spirit*(regen.perSpirit or 0)
 if old.manaRegen then s.manaRegen=old.manaRegen+regenDelta end
 if old.castingManaRegen then
  local before,after=0,0
  for _,r in ipairs(data.regenerationModifiers or {})do if not r.profileField or contains(r.profileValues,p[r.profileField])then before=before+ruleValue(r,live);after=after+ruleValue(r,current)end end
  s.castingManaRegen=math.max(0,old.castingManaRegen+(s.manaRegen or 0)*math.min(1,after)-(old.manaRegen or 0)*math.min(1,before))
 end
 return out
end
function P.applyTalentStatDeltas(data,p)
 local rules=data and data.talentStatRules or {}
 if not p.stats then return p end
 local capturedStats=p.stats
 p=P.applyAttributeTalentDeltas(data,p)
 local t=P.talents(data,p);local live=p.liveTalentRanks or t
 local out=nil
 for _,r in ipairs(rules)do
  local d=(t[r.talent]or 0)-(live[r.talent]or 0)
  local intChanged=r.perRank and r.perRank.apPerInt and (p.stats.intellect or 0)~=(capturedStats.intellect or 0)
  if (d~=0 or intChanged)and contains(r.forms,p.form or'caster')then
   out=out or copy(p);local s=out.stats;local v=r.perRank or {}
   if v.meleeCrit then for _,k in ipairs({'meleeCritPct','critPct'})do if s[k]then s[k]=s[k]+v.meleeCrit*d end end end
   if v.rangedCrit and s.rangedCritPct then s.rangedCritPct=s.rangedCritPct+v.rangedCrit*d end
   if v.spellCrit then for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do if s[school..'Crit']then s[school..'Crit']=s[school..'Crit']+v.spellCrit*d end end end
   if v.ap and s.attackPower then s.attackPower=s.attackPower+v.ap*d end
   if v.rap and s.rangedAttackPower then s.rangedAttackPower=s.rangedAttackPower+v.rap*d end
   if v.apPerLevel and s.attackPower then s.attackPower=s.attackPower+v.apPerLevel*p.level*d end
   if v.apPerInt and s.attackPower and s.intellect then s.attackPower=s.attackPower+v.apPerInt*(s.intellect*(t[r.talent]or 0)-(capturedStats.intellect or 0)*(live[r.talent]or 0)) end
   if v.petDamage and out.pet and out.pet.melee and out.pet.melee.baseDps then
    local liveRank,newRank=live[r.talent]or 0,t[r.talent]or 0
    out.pet.melee.baseDps=out.pet.melee.baseDps*(1+v.petDamage*newRank)/(1+v.petDamage*liveRank)
   end
  end
 end
 return out or p
end
function P.compile(data,p,stats,choice,duration,seed)
 data=P.classModel(data,p)
 p=P.applyTalentStatDeltas(data,p)
 if P.encounters and not ((p.encounter or {})._profileResolved) then
  local resolved,encounterError=P.encounters.Apply(p)
  if not resolved then error(encounterError or 'Encounter ungültig') end
  p=resolved
 end
 data=P.classModel(data,p)
 if data.typedCombat and stats then local old=P.combine(p.equipped or {});if(stats.int or 0)~=(old.int or 0)then local rate=(p.stats or {}).critPerIntellect or(p.level==60 and data.critPerIntellect60);if not rate or rate<=0 then error('Krit-Umrechnung für Intelligenz fehlt auf diesem Level.')end;data=copy(data);data.attributes.intPerCrit=1/rate end end
 local legacyProfile=p;if data.genericPet and p.petActive then legacyProfile=copy(p);legacyProfile.petActive=false end
 local spec=legacyCompile(data,legacyProfile,stats,choice,duration,seed)
 if not data.typedCombat then return spec end
 local sheet=p.stats or {};local old=P.combine(p.equipped or {});stats=stats or {};local t=P.talents(data,p)
 spec.typedCombat=true;spec.resource=data.resource;spec.form=p.form;spec.resources={energy=sheet.energy or 100,rage=sheet.rage or 0,combo=0,maxEnergy=sheet.maxEnergy and sheet.maxEnergy>0 and sheet.maxEnergy or 100,maxRage=sheet.maxRage and sheet.maxRage>0 and sheet.maxRage or 100,maxCombo=5,energyTick=.1,energyPerTick=1}
 if p.form=='cat'then spec.resource='energy'elseif p.form=='bear'then spec.resource='rage'end
 local multipliers={strength=1,agility=1,spirit=1};for _,rule in ipairs(data.attributeModifiers or {})do if multipliers[rule.field]then multipliers[rule.field]=multipliers[rule.field]*(1+((rule.values or {})[t[rule.talent]or 0]or 0))end end
 local strDelta=((stats.str or 0)-(old.str or 0))*multipliers.strength;local agiDelta=((stats.agi or 0)-(old.agi or 0))*multipliers.agility;local spiDelta=((stats.spi or 0)-(old.spi or 0))*multipliers.spirit;local extraPower=0;for _,rule in ipairs(data.staticRules or {})do local rate=(rule.values or {})[t[rule.talent]or 0]or 0;if rule.field=='spiritPower'then extraPower=extraPower+spiDelta*rate elseif rule.field=='strengthPower'then extraPower=extraPower+strDelta*rate end end
 local spiritExtra=((stats.spi or 0)-(old.spi or 0))*(multipliers.spirit-1)*(data.spiritRegeneration and data.spiritRegeneration.perSpirit or 0);spec.naturalRegen=spec.naturalRegen+spiritExtra;local fraction=0;for _,rule in ipairs(data.regenerationModifiers or {})do fraction=fraction+((rule.values or {})[t[rule.talent]or 0]or 0)end;spec.castingRegen=spec.castingRegen+spiritExtra*math.min(1,fraction)
 local ap=(sheet.attackPower or 0)+(stats.ap or 0)-(old.ap or 0)+strDelta*strengthAP(data)+agiDelta*agilityAP(data,p)
 local rap=(sheet.rangedAttackPower or 0)+(stats.rap or 0)-(old.rap or 0)+(stats.ap or 0)-(old.ap or 0)+agiDelta*2
 local intMultiplier=1;for _,rule in ipairs(data.attributeModifiers or {})do if rule.field=='intellect'then intMultiplier=intMultiplier*(1+((rule.values or {})[t[rule.talent]or 0]or 0))end end
 local intDelta=((stats.int or 0)-(old.int or 0))*intMultiplier
 for _,rule in ipairs(data.contextModifiers or {})do if rule.field=='intellectAttackPower'then local bonus=intDelta*((rule.values or {})[t[rule.talent]or 0]or 0);ap=ap+bonus;rap=rap+bonus end end
 local expertise=sheet.expertise or 0;local offhandMultiplier=.5;local capturedOffhandMultiplier=.5
 for _,r in ipairs(data.staticRules or {})do if r.field=='offhandMultiplier'then capturedOffhandMultiplier=capturedOffhandMultiplier*(1+ruleValue(r,p.liveTalentRanks or t))end end
 for _,m in ipairs(data.staticRules or {})do local v=(m.values or {})[t[m.talent]or 0]or 0;if m.field=='maxEnergy'then spec.resources.maxEnergy=spec.resources.maxEnergy+v;spec.resources.energy=math.min(spec.resources.maxEnergy,sheet.energy and sheet.energy>0 and sheet.energy or spec.resources.maxEnergy)elseif m.field=='expertise'then expertise=expertise+v elseif m.field=='offhandMultiplier'then offhandMultiplier=offhandMultiplier*(1+v)end end
 local capturedTalents=p.liveTalentRanks or t
 local capturedPhysicalFactor=1;for _,m in ipairs(data.modifiers or {})do if not m.targets and m.field=='mult'and contains(m.schools,'physical')then capturedPhysicalFactor=capturedPhysicalFactor*(1+ruleValue(m,capturedTalents))end end
 local weapons=copy(sheet.weapons or {});if stats.weaponItems and(p.equipped or {}).offhand and not stats.weaponItems.offhand then weapons.offhand=nil end
 local enchants=copy(p.weaponEnchants or {})
 -- Weapons on a compared item must have parsed damage/speed. Never score a weapon swap as stats alone.
 for hand,item in pairs(stats.weaponItems or {})do
  local prev=(p.equipped or {})[hand]
  if not prev or(item.link or item.id)~=(prev.link or prev.id)then
   if not item.weapon then error('Waffenschaden oder Tempo fehlt: '..(item.name or hand))end
   weapons[hand]=copy(item.weapon);weapons[hand].includesAttackPower=false
   enchants[hand]=0
  end
 end
 if stats.weaponItems and stats.weaponItems.mainhand and stats.weaponItems.mainhand.twoHanded then weapons.offhand=nil end
 local armor=spec.encounter.armor or 3731;local groups={}
 for _,v in ipairs(spec.encounter.armorDebuffs or {})do if v.group then local group=(v.group=='majorArmor'and'major'or v.group);groups[group]=math.max(groups[group]or 0,v.amount)else armor=armor-v.amount end end
 spec.armorBeforeGroups=armor;spec.armorGroups=copy(groups);for _,amount in pairs(groups)do armor=armor-amount end
 local armorIgnore=0;for _,rule in ipairs(data.contextModifiers or {})do if rule.field=='armorIgnore'then armorIgnore=armorIgnore+((rule.values or {})[t[rule.talent]or 0]or 0)end end;for _,rule in ipairs(data.weaponTalentRules or {})do local qualified=false;for hand,w in pairs(weapons)do if hand~='ranged'and(not rule.armorMainhandOnly or hand=='mainhand')and contains(rule.armorTypes,w.subclass)then qualified=true end end;if qualified then armorIgnore=armorIgnore+((rule.armorValues or {})[t[rule.talent]or 0]or 0)end end;armor=armor*(1-math.min(1,armorIgnore))
 spec.targetArmor=armor;spec.armorIgnoreFactor=armorIgnore;spec.armorLevel=p.level
 spec.armorMultiplier=1-math.max(0,armor)/(math.max(0,armor)+400+85*p.level);spec.targetArmorAssumed=spec.encounter.armorAssumed==true or spec.encounter.armor==nil;spec.targetArmorSource=spec.encounter.armorSource
 spec.meleeHaste=1+((sheet.meleeHastePct or sheet.hastePct or 0)+(stats.hastePct or 0)-(old.hastePct or 0))/100;spec.rangedHaste=1+((sheet.rangedHastePct or sheet.hastePct or 0)+(stats.hastePct or 0)-(old.hastePct or 0))/100
 for _,rule in ipairs(data.genericProcs or {})do if rule.buffId and contains(p.activeAuras or {},rule.buffId)and rule.attackHasteValues then local bonus=rule.attackHasteValues[t[rule.talent]or 0]or 0;spec.meleeHaste=spec.meleeHaste/(1+bonus)end end
 local physicalHit=(sheet.meleeHitPct or old.hitPct or 0)/100+((stats.hitPct or 0)-(old.hitPct or 0))/100
 local meleeCrit=(sheet.meleeCritPct or sheet.critPct or 0)/100+((stats.critPct or 0)-(old.critPct or 0))/100
 if agiDelta~=0 then local coefficient=sheet.critPerAgility or(p.level==60 and ({warrior=.05,paladin=.0506,hunter=.0189,rogue=.0345,druid=.05})[data.id]);if not coefficient then error('Krit-Umrechnung für Beweglichkeit fehlt auf diesem Level.')end;meleeCrit=meleeCrit+agiDelta*coefficient/100 end
 local rangedCrit=(sheet.rangedCritPct or sheet.meleeCritPct or 0)/100+((stats.critPct or 0)-(old.critPct or 0))/100
 local function prepare(b,key,white,hand)
  b.attackType=b.attackType or'spell'
  if b.contextDamageFactor then b.directMult=b.directMult/b.contextDamageFactor;if b.periodicMult then b.periodicMult=b.periodicMult/b.contextDamageFactor end end;b.contextDamageFactor=1
  if b.attackType=='spell'and b.school~='physical'and (b.base~=nil or b.tickBase~=nil)and(type(sheet[b.school..'Power'])~='number'or type(sheet[b.school..'Crit'])~='number')then error('Zauberwert fehlt: '..b.school)end
  if b.directScaling then local g=b.directScaling;local average=P.clientAverage(g,p.level);local spread=average*(g.variance or 0)/2;b.base=average-spread;b.max=average+spread;if spec.encounter.damageModel=='mean'then b.base=average;b.max=average end end
  if b.periodicScaling then local g=b.periodicScaling;local average=P.clientAverage(g,p.level);local spread=average*(g.variance or 0)/2;b.tickBase=average-spread;b.tickMax=average+spread end
  if b.damageIfAura and b.damageIfAura.values then b.damageIfAura.multiplier=1+(b.damageIfAura.values[t[b.damageIfAura.talent]or 0]or 0)end
  if b.attackType=='spell'and b.school=='physical'then b.crit=(sheet.physicalCrit or 0)/100 end
  b.sp=(b.sp or 0)+extraPower
  b.ap=(b.apType=='ranged'or b.attackType=='ranged')and rap or ap;b.blockValue=sheet.blockValue or 0
  if b.weaponDamage then
   if b.requiredOffhandSubclass and(not weapons.offhand or weapons.offhand.subclass~=b.requiredOffhandSubclass)then error('Benötigte Nebenhandwaffe fehlt: '..key)end
   local w=weapons[hand or b.weaponDamage.hand];if not w then error('Waffenwerte fehlen: '..(hand or b.weaponDamage.hand))end
   if b.weaponSubclasses and not contains(b.weaponSubclasses,w.subclass)then error('Falscher Waffentyp für '..key)end
   b.weapon=copy(w);b.weapon.modelledDamageFactor=w.includesAttackPower and capturedPhysicalFactor or 1;local off=(hand or b.weaponDamage.hand)=='offhand';b.weapon.handMultiplier=off and(w.includesAttackPower and capturedOffhandMultiplier or offhandMultiplier)or 1;b.weapon.offhandMultiplier=off and(w.includesAttackPower and offhandMultiplier/capturedOffhandMultiplier or offhandMultiplier)or 1
   if b.weaponMultipliersBySubclass then b.weaponDamage.multiplier=b.weaponMultipliersBySubclass[tostring(w.subclass)]or b.weaponDamage.multiplier end
   if p.form=='cat'or p.form=='bear'then
    local speed=p.form=='cat'and 1 or 2.5
    if w.form~=p.form then error('Waffenwerte müssen in aktueller Druidenform aufgenommen werden.')end
    b.weapon.speed=speed;b.weapon.normalizedSpeed=speed
   end
  end
  if b.attackType~='spell'and b.attackType then
   local weaponCrit=0;for _,rule in ipairs(data.weaponTalentRules or {})do local v=(rule.critValues or {})[t[rule.talent]or 0]or 0;local w=weapons[hand or(b.weaponDamage or {}).hand or'mainhand'];if w and contains(rule.critTypes,w.subclass)then weaponCrit=weaponCrit+v end;if sheet.weaponCritIncludesTalents and contains(rule.critTypes,((sheet.weapons or {}).mainhand or {}).subclass)then weaponCrit=weaponCrit-((rule.critValues or {})[capturedTalents[rule.talent]or 0]or 0)end end
   b.crit=(b.attackType=='ranged'and rangedCrit or meleeCrit)+(b.physicalCritBonus or 0)+weaponCrit;b.critMult=2+(b.critBonus or 0)
   b.attackTable=P.physicalTable(p.bossPlus,physicalHit+(b.physicalHitBonus or 0),b.crit,expertise,white,weapons.offhand~=nil,spec.encounter.inFront==true)
   if b.attackType=='ranged'or b.noActiveDefense then b.attackTable.dodge=0;b.attackTable.parry=0;b.attackTable.block=0;b.attackTable.glance=0 end
  end
  if b.alwaysHit and b.attackTable then b.attackTable.miss=0;b.attackTable.dodge=0;b.attackTable.parry=0;b.attackTable.block=0 end
  if b.damageDot then if(t[b.damageDot.talent]or 0)==0 then b.damageDot=nil else b.damageDot.crit=b.crit;b.damageDot.critMult=b.critMult end end
  if b.temporaryAttacker then local r=b.temporaryAttacker;r.damage=P.clientAverage(b.directScaling,p.level)*r.baseFraction;r.hit=P.physicalTable(p.bossPlus,physicalHit,0,expertise,false,false,false)end
  if b.fullComboRefund then b.fullComboRefund.amount=b.fullComboRefund.values[t[b.fullComboRefund.talent]or 0]or 0 end
  if b.cannotCrit then b.crit=0;if b.attackTable then b.attackTable.crit=0 end end
  local mh=weapons.mainhand;local two=mh and(mh.twoHanded==true or mh.normalizedSpeed==3.3)or false
  local shield=(p.comparisonGear or p.equipped or {}).offhand
  for _,rule in ipairs(data.contextModifiers or {})do
   if rule.field=='damage'and(rule.twoHanded==nil or rule.twoHanded==two)and(not rule.shield or shield and shield.equipLoc=='INVTYPE_SHIELD')and(rule.petActive==nil or rule.petActive==(p.petActive==true))and contains(rule.mobTypes,(p.encounter or {}).mobType)and contains(rule.targets,key)and contains(rule.schools,b.school)and contains(rule.attackTypes,b.attackType)then local v=(rule.values or {})[t[rule.talent]or 0]or 0;b.directMult=b.directMult*(1+v);b.contextDamageFactor=b.contextDamageFactor*(1+v);if b.periodicMult then b.periodicMult=b.periodicMult*(1+v)end;if b.weapon and b.weapon.includesAttackPower and not rule.mobTypes then b.weapon.modelledDamageFactor=b.weapon.modelledDamageFactor*(1+((rule.values or {})[capturedTalents[rule.talent]or 0]or 0))end end
  end
  if b.sealProc then if b.sealProc.scaling then b.sealProc.basePerSpeed=P.clientAverage(b.sealProc.scaling,p.level)/100 end;local de=b.judgement.scaling;local average=P.clientAverage(de,p.level);local v=de.Variance or de.variance or 0;local scale=b.judgement.scale or 1;if scale==.5 and spec.encounter.stunned then scale=1 end;b.judgement.base=average*(1-v/2)*scale;b.judgement.max=average*(1+v/2)*scale;if spec.encounter.damageModel=='mean'then b.judgement.base=average*scale;b.judgement.max=average*scale end;b.judgement.crit=meleeCrit;b.judgement.critMult=2;b.judgement.hit=1;b.judgement.attackType='melee';b.judgement.noActiveDefense=true;b.judgement.attackTable=P.physicalTable(p.bossPlus,physicalHit,meleeCrit,expertise,false,false,false);b.judgement.attackTable.dodge=0;b.judgement.attackTable.parry=0;b.judgement.attackTable.block=0 end
  if b.weaponPercentBonus and b.weaponDamage then b.weaponDamage.multiplier=b.weaponDamage.multiplier*(1+b.weaponPercentBonus)end
  if b.beforeTickDebuff then local r=b.beforeTickDebuff;r.damageBonus=(r.damageBonusValues or {})[t[r.talent]or 0]or 0;if r.damageBonus==0 then b.beforeTickDebuff=nil end end
 end
 local additions={}
 for key,b in pairs(spec.abilities)do prepare(b,key,false);if b.completeResource then local r=b.completeResource;if r.values then r.amount=r.values[t[r.talent]or 0]or 0 end;if stats.itemIds then for _,id in ipairs(stats.itemIds)do r.amount=(r.amount or 0)+((r.itemBonuses or {})[tostring(id)]or 0)end else for _,item in pairs(p.equipped or {})do r.amount=(r.amount or 0)+((r.itemBonuses or {})[tostring(item.id)]or 0)end end end;if b.weaponHands then b.secondaryWeapons={};for _,hand in ipairs(b.weaponHands)do if(hand~=(b.weaponDamage or {}).hand or b.parentAttackOnly)and weapons[hand]then local child=copy(b);child.key=key..':'..hand;child.weaponHands=nil;child.secondaryWeapons=nil;child.comboGain=nil;child.parentAttackOnly=nil;child.weaponDamage.hand=hand;prepare(child,child.key,false,hand);if b.parentAttackOnly then child.attackTable.miss=0;child.attackTable.dodge=0;child.attackTable.parry=0 end;additions[child.key]=child;b.secondaryWeapons[#b.secondaryWeapons+1]=child end end;if b.parentAttackOnly then b.base=nil;b.max=nil;b.weaponDamage=nil;b.weapon=nil end end end
 for key,b in pairs(additions)do spec.abilities[key]=b end
 spec.autoAttacks={};local mode=data.autoAttack or((p.form=='cat'or p.form=='bear')and'mainhand')
 if mode then
  for _,hand in ipairs(mode=='ranged'and{'ranged'}or{'mainhand','offhand'})do if weapons[hand]then
   local b={key='auto:'..hand,school='physical',attackType=hand=='ranged'and'ranged'or'melee',resource=spec.resource,cost=0,cast=0,white=true,base=0,max=0,coef=0,sp=0,directMult=1,mult=1,critBonus=0,hit=1,weaponDamage={hand=hand,normalized=false,multiplier=1},ap=hand=='ranged'and rap or ap,baseCost=0}
   -- Auto attacks also receive generic static damage modifiers.
   for _,m in ipairs(data.modifiers or {})do if not m.targets and contains(m.schools,'physical')then local v=(m.values or {})[t[m.talent]or 0]or 0;if m.field=='mult'then b.directMult=b.directMult*(1+v)elseif m.field=='directBonus'then b.directMult=b.directMult*(1+v)elseif m.field=='physicalHitBonus'then b.physicalHitBonus=(b.physicalHitBonus or 0)+v end end end
   prepare(b,b.key,true,hand);spec.abilities[b.key]=b;spec.autoAttacks[#spec.autoAttacks+1]={key=b.key,hand=hand,speed=b.weapon.speed}
  end end
 end
 spec.sealRefund=data.sealRefund and copy(data.sealRefund);if spec.sealRefund then local r=spec.sealRefund;r.chance=r.chanceValues[t[r.talent]or 0]or 0;r.refund=r.refundValues[t[r.talent]or 0]or 0 end
 spec.petFrenzy=data.petFrenzy and copy(data.petFrenzy);if spec.petFrenzy then spec.petFrenzy.chance=spec.petFrenzy.chanceValues[t.frenzy or 0]or 0 end
 spec.finisherProcs={};for _,v in ipairs(data.finisherProcs or {})do local rule=copy(v);rule.chance=(rule.chanceValues or {})[t[rule.talent]or 0]or 0;spec.finisherProcs[#spec.finisherProcs+1]=rule end
 spec.periodicCurrency={};for _,rule in ipairs(data.periodicCurrency or {})do if(t[rule.talent]or 0)>0 then spec.periodicCurrency[#spec.periodicCurrency+1]=copy(rule)end end
 spec.genericProcs={};spec.physicalContext={levelDifference=p.bossPlus,hit=physicalHit,expertise=expertise,front=spec.encounter.inFront==true}
 for hand,id in pairs(enchants)do local enchant=(data.weaponEnchantRules or {})[tostring(id)];if enchant then local rule=copy(enchant);rule.key='weaponProc:'..hand;rule.hand=hand;if enchant.type=='extraAttacks'then rule.attackPowerBonus=P.clientAverage(enchant.attackPowerScaling,p.level)*(1+((data.windfuryAPValues or {})[t.elementalWeapons or 0]or 0))elseif enchant.type=='spellProc'then rule.chance=rule.chance+((data.poisonChanceValues or {})[t.improvedPoisons or 0]or 0);rule.meleeOnly=true;if enchant.abilityOverride then local child=copy(spec.abilities[rule.spellKey]);child.key=child.key..':'..id;for key,v in pairs(enchant.abilityOverride)do child[key]=v end;if spec.encounter.damageModel=='mean'and child.max then child.base=(child.base+child.max)/2;child.max=child.base end;spec.abilities[child.key]=child;rule.spellKey=child.key end end;spec.genericProcs[#spec.genericProcs+1]=rule end end
 for _,v in ipairs(data.genericProcs or {})do local r=copy(v);if r.talent then r.chance=(r.chanceValues or {})[t[r.talent]or 0]or 0 end;if r.weaponPoolValues then local w=weapons.mainhand;local raw=(w.min+w.max)/2/(w.damageMultiplier or 1)-(w.includesAttackPower and(w.attackPower or ap)*w.speed/14 or 0);r.weaponPoolDamage=math.max(0,raw)*(r.weaponPoolValues[t[r.talent]or 0]or 0)end;if r.attackHasteValues then r.attackHaste=r.attackHasteValues[t[r.talent]or 0]or 0 end;if r.rangedHasteValues then r.rangedHaste=r.rangedHasteValues[t[r.talent]or 0]or 0 end;if r.requiresAuraNames and not P.hasAuraNamed(p,r.requiresAuraNames)then r.chance=0 end;if r.castMultiplierValues then r.castMultiplier=r.castMultiplierValues[t[r.talent]or 0]or 0 end;if r.ppmPerRank then r.ppm=r.ppmPerRank*(t[r.talent]or 0);r.chance=r.ppm>0 and 1 or 0 end;if(r.chance or 0)>0 and contains(r.forms,p.form or'caster')then spec.genericProcs[#spec.genericProcs+1]=r end end
 spec.conditionalModifiers={};for _,rule in ipairs(data.conditionalModifiers or {})do local r=copy(rule);r.value=(r.values or {})[t[r.talent]or 0]or 0;if r.value~=0 then spec.conditionalModifiers[#spec.conditionalModifiers+1]=r end end
 for _,rule in ipairs(data.buffRules or {})do local r=copy(rule);if r.castFlatValues then r.castFlat=r.castFlatValues[t[r.talent]or 0]or 0 end;spec.procs[#spec.procs+1]=r end
 for _,rule in ipairs(spec.procs)do for _,field in ipairs({'buffDamagePerStack','buffCastingRegen','buffCritPerStack','buffAPMultiplier'})do if rule[field..'Values']then rule[field]=rule[field..'Values'][t[rule.talent]or 0]or 0 end end end
 spec.offhandRageMultiplier=1;for _,rule in ipairs(data.staticRules or {})do if rule.field=='offhandRageMultiplier'then spec.offhandRageMultiplier=spec.offhandRageMultiplier*(1+((rule.values or {})[t[rule.talent]or 0]or 0))end end
 for _,rule in ipairs(spec.genericProcs)do if rule.castMultiplier then spec.procs[#spec.procs+1]={buff=rule.key,castMultiplierPerStack=rule.castMultiplier,costMultiplierPerStack=rule.castMultiplier,consumeOn=rule.consumeOn,consumeCharges=true,autoPriority=false}end end
 if data.genericPet and p.petActive then
  local pet=p.pet;local melee=pet.melee;local actor={key='pet',mana=100,manaRegen=(data.petFocusRegen or 10)*(1+((data.petFocusValues or {})[t.bestialDiscipline or 0]or 0)),focusTick=.25,generic=true,spells={}}
  local petCrit=pet.critPct+((data.petCritValues or {})[t.ferocity or 0]or 0);local table=P.physicalTable(p.bossPlus,0,petCrit/100,0,true,false,false)
  actor.melee={key='pet:melee',base=melee.baseDps*melee.swing,swing=melee.swing,sp=0,mult=1,miss=table.miss,dodge=table.dodge,glance=table.glance,glanceMult=table.glanceMultiplier,crit=table.crit,critMult=2,armorMultiplier=spec.armorMultiplier}
  local petMultiplier=1;for _,rule in ipairs(data.contextModifiers or {})do if rule.includePet then petMultiplier=petMultiplier*(1+((rule.values or {})[t[rule.talent]or 0]or 0))end end
  -- Captured pet melee already includes static damage bonuses; only spell rows need these factors.
  for _,key in ipairs({'bite','lightningBreath','claw'})do
   local selected;for _,r in ipairs((data.petSpellRanks or {})[key]or {})do if r.level<=(pet.level or p.level)and contains((pet.knownSpellRanks or {})[key]or {},r.rank)then selected=r end end
   if selected then local b=copy(selected);b.key='pet:'..key;b.hit=(P.baseHit(p.bossPlus))/100;b.crit=petCrit/100;b.directMult=pet.melee.damageMultiplier or petMultiplier;b.actor=true;b.generic=true;b.attackType=b.school=='physical'and'melee'or'spell';b.attackTable=b.school=='physical'and P.physicalTable(p.bossPlus,0,b.crit,0,false,false,false)or nil;actor.spells[#actor.spells+1]=b;spec.abilities[b.key]=b end
  end
  spec.actors[#spec.actors+1]=actor
 end
 if p.stealthed or spec.encounter.startStealthed then spec.initialBuffs.stealth={expires=1e9,charges=1,stacks=1,pausesOwnerAutos=true}end
 return spec
end
-- Extend search with resource/form constraints; keep the established optimizer and score policy.
local legacyCandidates=P.candidates
function P.candidates(data,p)
 data=P.classModel(data,p)
 if not data.typedCombat then return legacyCandidates(data,p)end
 local d=copy(data);local profile=(d.rotationProfiles or {})[p.form or'caster']
 if profile then d.search.filler={default=profile.filler,alternatives=profile.alternatives};d.search.optionalAbilities={};for _,k in ipairs(profile.optional)do d.search.optionalAbilities[#d.search.optionalAbilities+1]={key=k}end;d.search.policyVariants={{}};for _,k in ipairs(profile.priority)do d.search.policyVariants[1][#d.search.policyVariants[1]+1]={key=k}end end
 local choices=legacyCandidates(d,p)
 if data.sealChoices then local more={};for _,c in ipairs(choices)do for _,seal in ipairs(data.sealChoices)do if seal~='sealOfRighteousness'and #P.ranks(data,p,seal)>0 then local cc=copy(c);for _,pol in ipairs(cc.policies)do if pol.key=='sealOfRighteousness'then pol.key=seal;pol.maintainBuff=seal end end;more[#more+1]=cc end end end;for _,c in ipairs(more)do choices[#choices+1]=c end end
 local talents=P.talents(data,p)
 for _,c in ipairs(choices)do if data.id=='druid'and(talents.eclipse or 0)>0 and #P.ranks(data,p,'starfire')>0 and c.policies[#c.policies].key=='wrath'then table.insert(c.policies,1,{key='starfire',requiresBuff='eclipse'})end end
 for _,c in ipairs(choices)do for i=#(data.cooldownAbilities or {}),1,-1 do local key=data.cooldownAbilities[i];local ranks=P.ranks(data,p,key);if #ranks>0 then table.insert(c.policies,1,{key=key,maintainBuff=key})end end end
 for _,c in ipairs(choices)do for _,pol in ipairs(c.policies)do
  local ranks=P.ranks(data,p,pol.key);local b=ranks[#ranks]
  if b then
   if b.spendCombo then pol.minCombo=4;if b.kind=='buff'then pol.maintainBuff=pol.key elseif b.duration then pol.maintain=true end end
   if b.comboGain then pol.maxCombo=4 end
   if b.nextSwing then pol.minResource=math.max(30,b.cost+10)end
   if b.requiresPet then pol.requiresPet=true end
   if b.requiresBuff then pol.requiresBuff=b.requiresBuff end
   if b.kind=='judgement'then pol.requiresBuffGroup='seal'end
   if b.kind=='buff'and not pol.maintainBuff then pol.maintainBuff=pol.key end
  end
 end end
 return choices
end

