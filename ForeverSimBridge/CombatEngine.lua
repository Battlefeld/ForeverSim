-- Single class-neutral timeline. Class modules are generated data only.
FUSLive=FUSLive or {};local P=FUSLive
P.version='1.16.0'
-- Forever Legacy perk "Talented" (0-5 ranks) moves the first talent point from level
-- 10 down to level 10-rank. Read it from the client's spent+unspent points; fall back
-- to the rank chosen in the dashboard when the client does not expose talent points.
function P.talentBonus()
 local function n(v)if type(v)=='number' and v==v and not(type(issecretvalue)=='function' and issecretvalue(v))then return v end end
 local ok,level=pcall(UnitLevel,'player');level=ok and n(level)
 local manual=ForeverSimBridgeDB and ForeverSimBridgeDB.talentedRank
 if type(manual)=='number' then return math.max(0,math.min(5,manual)),'manual' end
 if not level then return 0,'unknown' end
 local unspent=nil
 if type(GetUnspentTalentPoints)=='function' then local okU,v=pcall(GetUnspentTalentPoints);unspent=okU and n(v) end
 if not unspent and type(UnitCharacterPoints)=='function' then local okU,v=pcall(UnitCharacterPoints,'player');unspent=okU and n(v) end
 local spent=0
 if type(GetNumTalentTabs)=='function' and type(GetTalentTabInfo)=='function' then
  local okT,tabs=pcall(GetNumTalentTabs);tabs=okT and n(tabs) or 0
  for i=1,tabs do local okI,_,_,pts=pcall(GetTalentTabInfo,i);pts=okI and n(pts);if pts then spent=spent+pts end end
 end
 if not unspent then return 0,'unknown' end
 -- Points = level-9+rank (first point at level 10-rank). Solve for rank; level-9 may be negative.
 local total=spent+unspent
 if total<=0 or total>=51 then return 0,'client' end
 local bonus=math.max(0,math.min(5,total-(level-9)))
 return bonus,'client'
end
-- Product rule (changed on the user's request, 2026-10-19): the SIM is usable from level 5, because talents can be
-- spent from level 5 with legacy points. Levels 5-9 are calculated as level 10 by ForeverCore.exe and marked as an
-- approximation in the result.
function P.minSimLevel()return 5 end
local function copy(x) if type(x)~='table' then return x end local o={} for k,v in pairs(x) do o[k]=copy(v) end return o end
local function clamp(x,l,h)return math.max(l,math.min(h,x))end
local function has(a,k)if not a then return true end for _,x in ipairs(a)do if x==k then return true end end return false end
local function sortedKeys(t)local o={} for k in pairs(t)do o[#o+1]=k end table.sort(o)return o end
local function value(rule,t,field)if rule.constant~=nil then return rule.constant end;field=field or 'values';local rank=t[rule.talent]or 0;if rule[field]then return rule[field][rank]or 0 end return rank*(rule.perRank or 0)end
local function scaleRank(b,level)local g=b.levelScaling;if g then local delta=math.max(0,math.min(level,g.cap)-g.start)*g.perLevel;local spread=(g.base or 0)*(g.variance or 0)/2;local low=(g.low or g.base-spread)+delta;local high=(g.high or g.base+spread)+delta;if g.field=='periodic'then b.tickBase=low;b.tickMax=high elseif g.field=='resource'then b.manaBase=low else b.base=low;b.max=high end end;for _,child in pairs(b.triggeredDamage or {})do scaleRank(child,level)end;return b end
local function schoolMatches(schools,b)if not schools then return true end for _,k in ipairs(b.schools or {b.school})do if has(schools,k)then return true end end return false end
local function matches(rule,key,b)if not(has(rule.targets,key)and schoolMatches(rule.schools,b)and has(rule.trees,b.tree))then return false end for _,k in ipairs(rule.excludeFlags or {})do if b[k]then return false end end return true end
P.copy=copy;P.sortedKeys=sortedKeys
-- A single generic resistance model, matching the independent XN rule contract.
-- This is a reference rule, including XN's negative-resistance vulnerability assumption.
function P.resistanceDistribution(mean,step,width,count,positive)
 if mean<=1e-12 then return {{pct=0,p=1}}end
 local function weights(center)
  local values,sum,actual={},0,0
  for k=0,count do local w=math.max(0,width-math.abs(k*step-center));values[k+1]=w;sum=sum+w;actual=actual+w*k*step end
  return values,sum,actual/sum
 end
 local lo,hi=-width+1e-9,positive and mean+width or 1+width
 for _=1,(positive and 80 or 100)do local mid=(lo+hi)/2;local _,_,actual=weights(mid);if actual<mean then lo=mid else hi=mid end end
 local weights,sum=weights((lo+hi)/2);local dist={}
 for k=0,count do local probability=weights[k+1]/sum;if probability>1e-12 then dist[#dist+1]={pct=(positive and 1 or -1)*k*step*100,p=probability}end end
 return dist
end
function P.resistanceProfile(rules,school,reduction)
 local resist=math.max(0,((rules.targetResist or {})[school]or 0)+(rules.levelResistance or 0)-(reduction or 0))-(rules.pierce or 0)
 local rate=rules.perPoint or .75/(5*(rules.level or 60))
 if resist>0 then return {R=resist,mean=-math.min(.75,rate*resist),dist=P.resistanceDistribution(math.min(.75,rate*resist),.25,.5,4,false)}end
 local mean=-resist*rate;local step,width=rules.vulnerableStep or .1,rules.vulnerableSpread or .2
 return {R=resist,mean=mean,dist=P.resistanceDistribution(mean,step,width,math.ceil((mean+2*width)/step)+1,true)}
end
local function baseHit(levelDifference)
 if levelDifference<=0 then return math.min(100,96-levelDifference)end
 if levelDifference<=2 then return 96-levelDifference end
 return math.max(1,83-(levelDifference-3)*11)
end
P.baseHit=baseHit
function P.ranks(data,p,key)local rs={};local t=P.talents(data,p);for _,r in ipairs(data.abilities[key]or {})do if(r.alwaysKnown or not r.requiredTalent or(t[r.requiredTalent]or 0)>0)and r.level<=p.level and(r.requiredItem and((p.inventory or {})[tostring(r.requiredItem)]or(p.inventory or {})[r.requiredItem]or 0)>0 or not r.requiredItem and(r.alwaysKnown or not p.hasSpellbook or has((p.knownSpellRanks or {})[key]or {},r.rank)))then rs[#rs+1]=r end end return rs end
function P.talents(data,p)local t={}for k,names in pairs(data.talents or {})do t[k]=0 for _,tree in ipairs(p.talents or {})do for _,e in ipairs(tree.entries or {})do if e.classKey==k or has(names,string.lower(e.name or ''))then t[k]=tonumber(e.rank)or 0 end end end end return t end
function P.levelMessage(level)
 return 'Die DPS- und Rotationsoptimierung ist erst ab Level '..P.minSimLevel()..' verfügbar (aktuell Level '..tostring(level or '?')..').'
end
function P.coverage(data,p)
 if p.level<(p.minSimLevel or P.minSimLevel()) then return P.levelMessage(p.level) end
 if p.level>data.maxLevel then return 'Die DPS- und Rotationsoptimierung wird aktuell nur bis Level '..data.maxLevel..' unterstützt (aktuell Level '..p.level..').' end
 if p.petActive and not(data.actors and data.actors[(p.pet or {}).type or p.petType])then return 'Begleiterart konnte nicht gelesen werden'end
 for _,tree in ipairs(p.talents or {})do for _,e in ipairs(tree.entries or {})do if e.rank>0 then local found=e.classKey and data.talents[e.classKey]~=nil;for _,names in pairs(data.talents or {})do if has(names,string.lower(e.name or ''))then found=true end end if not found then return 'Talentregel fehlt: '..e.name end end end end
 local t=P.talents(data,p);for _,rule in ipairs(data.talentDefinitions or {})do if(t[rule.key]or 0)>rule.maxRank then return 'Ungültiger Talentrang: '..rule.name end end
 for _,name in ipairs(data.unsupportedSpecs or {})do if p.spec==name then return 'Spezialisierungsregeln fehlen: '..name end end
end
function P.compile(data,p,s,choice,duration,seed)
 local issue=P.coverage(data,p)if issue then error(issue)end
 local t=P.talents(data,p);local stats=(data.levelStats or {})[tostring(p.level)]
 -- Level tables start at 10; below that (Talented) the level-10 row is the closest documented value.
 if not stats and p.level<10 then stats=(data.levelStats or {})['10'] end
 local a=copy(data.attributes);for k,v in pairs(stats or {})do a[k]=v end;s=s or {}
 local old=P.combine(p.equipped or {});local sheet=p.stats or {}
 local encounter=p.encounter or {};local bossPlus=p.bossPlus or encounter.levelDifference or(p.level==60 and 3 or 2)
 local hitBase=encounter.baseHitPct or baseHit(bossPlus)
 local resistance={level=p.level,targetResist=copy(encounter.targetResist or {}),levelResistance=encounter.levelResistance==false and 0 or bossPlus*(encounter.resistancePerLevel or 8),pierce=(sheet.pierce or old.pierce or 0)+(s.pierce or 0)-(old.pierce or 0),vulnerableStep=.1,vulnerableSpread=.2}
 if sheet.pierce==nil then for _,m in ipairs(data.penetrationModifiers or {})do resistance.pierce=resistance.pierce+value(m,t)end end
 local genericPower=sheet.spellPower and sheet.spellPower+(s.sp or 0)-old.sp or(s.sp or 0)
 local genericCrit=sheet.critPct and(sheet.critPct+(s.critPct or 0)-old.critPct)/100 or nil

 local intMult=1;for _,m in ipairs(data.attributeModifiers or {})do if m.field=='intellect'then intMult=intMult*(1+value(m,t))end end
 local intellect=sheet.intellect and sheet.intellect+((s.int or 0)-old.int)*intMult or(a.intBase+math.floor(p.level*a.intPerLevel+.5)+(s.int or 0))*intMult
 local oldIntellect=sheet.intellect or(a.intBase+math.floor(p.level*a.intPerLevel+.5)+old.int)*intMult
 local function intMana(x)return math.min(20,x)+math.max(0,x-20)*a.manaPerInt end
 local spirit=sheet.spirit and sheet.spirit+(s.spi or 0)-old.spi or a.spiBase+math.floor(p.level*a.spiPerLevel+.5)+(s.spi or 0)
 local manaMult,staMult=1,1;for _,m in ipairs(data.attributeModifiers or {})do if m.field=='mana'then manaMult=manaMult*(1+value(m,t))elseif m.field=='stamina'then staMult=staMult*(1+value(m,t))end end
 local initial={mana=sheet.mana and sheet.mana+(intMana(intellect)-intMana(oldIntellect))*manaMult or (a.baseMana or a.manaBase+p.level*a.manaPerLevel)+intMana(intellect),health=sheet.health and sheet.health+((s.sta or 0)-old.sta)*a.healthPerSta*staMult or a.healthBase+p.level*a.healthPerLevel+(s.sta or 0)*a.healthPerSta}
 if not sheet.mana then initial.mana=initial.mana*manaMult end;if not sheet.health then initial.health=initial.health+(s.sta or 0)*a.healthPerSta*(staMult-1)end
 local baseMana=sheet.baseMana or p.baseMana or a.baseMana or math.max(0,initial.mana/manaMult-intMana(intellect)-(sheet.flatMana or 0));local regenFraction=0;for _,m in ipairs(data.regenerationModifiers or {})do if not m.profileField or has(m.profileValues,p[m.profileField])then regenFraction=regenFraction+value(m,t)end end
 local function activeRule(m)return(not m.actorActive or p.petActive)and(not m.actorTypes or has(m.actorTypes,(p.pet or {}).type or p.petType))and(not m.profileField or has(m.profileValues,p[m.profileField]))and(not m.requiresTalent or(t[m.requiresTalent]or 0)>0)and(not m.sacrificeEffect or not p.petActive or((t[m.retentionTalent]or 0)>0 and((p.pet or {}).type or p.petType)~=p[m.profileField]))end
 local abilities={}
 for _,key in ipairs(sortedKeys(data.abilities))do
  local rs=P.ranks(data,p,key);local wanted=(choice.ranks or {})[key];local r=rs[#rs]
  if wanted then r=nil for _,v in ipairs(rs)do if v.rank==wanted then r=v end end end
  if r then local b=scaleRank(copy(r),p.level);if encounter.damageModel=='mean' and b.max then b.base=(b.base+b.max)/2;b.max=b.base end;b.mult=1;b.directBonus=0;b.periodicBonus=0;b.directFactor=1;b.periodicFactor=1;b.critBonus=0;b.cost=b.baseManaCost and baseMana*b.baseManaCost or(b.cost or 0);b.baseCost=b.cost;b.hit=clamp((hitBase+(s.hitPct or 0))/100,0,1);b.crit=clamp((sheet[b.school..'Crit']and sheet[b.school..'Crit']+(intellect-oldIntellect)/a.intPerCrit+(s.critPct or 0)-old.critPct or a.critBase+intellect/a.intPerCrit+(s.critPct or 0))/100,0,.95);b.sp=sheet[b.school..'Power']and sheet[b.school..'Power']+(s.sp or 0)-old.sp+(s[b.school..'Sp']or 0)-(old[b.school..'Sp']or 0)or(s.sp or 0)+(s[b.school..'Sp']or 0);b.critMult=1.5;if b.schools then b.sp=0 for _,k in ipairs(b.schools)do local power=sheet[k..'Power']and sheet[k..'Power']+(s.sp or 0)-old.sp+(s[k..'Sp']or 0)-(old[k..'Sp']or 0)or(s.sp or 0)+(s[k..'Sp']or 0);b.sp=math.max(b.sp,power)end end
   for _,m in ipairs(data.modifiers or {})do if matches(m,key,b)and activeRule(m)and not(m.field=='crit'and not m.targets and sheet[b.school..'Crit'])and not(m.skipIfCapturedPower and sheet[b.school..'Power'])then local v=value(m,t)*(m.perLevel and p.level or(m.perIntellect and(sheet[b.school..'Power']and intellect-oldIntellect or intellect)or 1)) if m.op=='multiply'then b[m.field]=(b[m.field]or 1)*(1+v)else b[m.field]=(b[m.field]or 0)+v end end end
   b.directMult=b.mult*(1+b.directBonus)*b.directFactor;b.periodicMult=b.mult*(1+b.periodicBonus)*b.periodicFactor;b.critMult=1+.5*(1+b.critBonus);b.hit=clamp(b.hit,0,1);b.crit=clamp(b.crit,0,1);b.cast=math.max(0,b.cast);b.cost=math.max(0,b.cost)
   if b.kind=='resource'then local mult=1 for _,m in ipairs(b.gainModifiers or {})do mult=mult*(1+m.perRank*(t[m.talent]or 0))end b.manaGain=(b.manaBase+(b.withSpirit and spirit or 0))*mult;b.maxManaGain=(b.manaMax or b.manaBase)*mult;b.healthCost=b.healthMatchesManaGain and b.manaGain or(b.healthBase~=nil and b.healthBase or b.manaBase) end
   abilities[key]=b
  end
 end
 local actors={}if p.petActive then
  local info=p.pet or {};local def=data.actors[info.type or p.petType];local r=nil
  for _,v in ipairs((data.petSpellRanks or {})[def.spell]or {})do if v.level<=(info.level or p.level)and(not info.hasSpellbook or has((info.knownSpellRanks or {})[def.spell]or {},v.rank))then r=v end end
  local owner=nil;for _,key in ipairs(sortedKeys(abilities))do if abilities[key].kind~='resource'then owner=abilities[key];break end end
  local actor={key='pet',mana=info.mana or def.mana*manaMult,manaRegen=info.manaRegen or def.manaRegen}
  if r then local b=copy(r);b.mult=1;b.sp=info.spellPower and info.spellPower+((s.sp or 0)-old.sp)*def.spInheritance or genericPower*def.spInheritance;b.actor=true;b.hit=clamp((hitBase+(s.hitPct or 0)+(t.suppression or 0))/100,0,1);b.crit=clamp((sheet[b.school..'Crit']and sheet[b.school..'Crit']+(intellect-oldIntellect)/a.intPerCrit+(s.critPct or 0)-old.critPct or a.critBase+intellect/a.intPerCrit+(s.critPct or 0))/100,0,.95);b.critMult=1.5;if b.schools then b.sp=0 for _,k in ipairs(b.schools)do local power=sheet[k..'Power']and sheet[k..'Power']+(s.sp or 0)-old.sp+(s[k..'Sp']or 0)-(old[k..'Sp']or 0)or(s.sp or 0)+(s[k..'Sp']or 0);b.sp=math.max(b.sp,power)end end
   for _,m in ipairs(data.actorModifiers or {})do if matches(m,b.key,b)and activeRule(m)and not(m.skipIfCapturedPower and info.spellPower)then local v=value(m,t)*(m.perLevel and p.level or 1);b[m.field]=m.op=='multiply'and(b[m.field]or 1)*(1+v)or(b[m.field]or 0)+v end end
   b.crit=genericCrit or b.crit;b.directMult=b.mult;actor.spell=b
  end
  if def.melee then local m,b=def.melee,info.melee;local raw=b and b.baseDps or m.baseDps;local swing=b and b.swing or m.swing;local armor=encounter.armor or 3731;local groups={};for _,d in ipairs(encounter.armorDebuffs or {})do if d.group then groups[d.group]=math.max(groups[d.group]or 0,d.amount)else armor=armor-d.amount end end;for _,amount in pairs(groups)do armor=armor-amount end;armor=math.max(0,armor);local ownerMeleeCrit=sheet.meleeCritPct or(2+(sheet.agility or 0)/20);local hitBonus=math.max(0,(s.hitPct or 0)+(t.suppression or 0)-1)
   actor.melee={key='melee',base=raw*swing,swing=swing,sp=(b and((s.sp or 0)-old.sp)or genericPower)*m.apPerSp/m.apPerDps*swing,mult=1,miss=math.max(0,.08-hitBonus/100),dodge=.065,glance=.4,glanceMult=.65,crit=math.max(0,(m.critPct+(m.inheritMeleeCrit and ownerMeleeCrit or 0)-4.8)/100),critMult=2,armorMultiplier=p.targetArmorMultiplier or(1-armor/(armor+400+85*p.level))}
   if not(b and b.includesModifiers)then for _,rule in ipairs(data.actorModifiers or {})do if matches(rule,'melee',{school='physical'})and activeRule(rule)and rule.field=='mult'then actor.melee.mult=actor.melee.mult*(1+value(rule,t))end end end
  end actor.resourceTransfers={};for _,x in ipairs(data.actorResourceTransfers or {})do actor.resourceTransfers[#actor.resourceTransfers+1]={ability=x.ability,fraction=value(x,t)}end;actor.hitBonuses={};for _,x in ipairs(data.actorHitBonuses or {})do local b=copy(x);local growth=(p.level-b.baseLevel)*b.basePerLevel;b.base=b.base+growth;if b.max~=nil then b.max=b.max+growth end;b.actor=true;b.school=def.spell=='firebolt'and'fire'or'shadow';b.sp=0;for _,key in ipairs(sortedKeys(abilities))do if abilities[key].school==b.school then b.sp=abilities[key].sp;break end end;b.crit=actor.spell and actor.spell.crit or actor.melee and actor.melee.crit or 0;b.critMult=actor.spell and actor.spell.critMult or 1.5;b.mult=1;for _,m in ipairs(data.actorModifiers or {})do if matches(m,b.key,b)and activeRule(m)and m.field=='mult'then b.mult=b.mult*(1+value(m,t))end end;actor.hitBonuses[#actor.hitBonuses+1]=b end;actors[#actors+1]=actor
 end
 for _,policy in ipairs(choice.policies)do if not abilities[policy.key]then error('Nicht erlernter Zauber: '..policy.key)end end
 local periodicResources={};for _,v in ipairs(data.periodicResources or {})do if activeRule(v)then periodicResources[#periodicResources+1]=copy(v)end end;local procs,rules={},{}for _,x in ipairs(data.procs or {})do local v=copy(x);v.livePeriodic=x.livePeriodic==true;v.chance=x.chanceValues and value(x,t,'chanceValues')or(x.chancePerRank or 0)*(t[x.talent]or 0);v.damageFraction=x.damageFractionValues and value(x,t,'damageFractionValues')or x.damageFraction;v.manaRefund=value(x,t,'manaRefundValues');v.maxStacks=x.maxStacksValues and value(x,t,'maxStacksValues')or x.maxStacks;v.damagePerStack=x.damagePerStackValues and value(x,t,'damagePerStackValues')or x.damagePerStack;v.castMultiplierPerStack=x.castMultiplierValues and value(x,t,'castMultiplierValues')or x.castMultiplierPerStack;v.charges=x.chargesValues and value(x,t,'chargesValues')or x.charges;v.damageMultiplierPerStack=x.damageMultiplierValues and value(x,t,'damageMultiplierValues')or x.damageMultiplierPerStack;v.afflictionMultiplier=x.afflictionMultiplierValues and value(x,t,'afflictionMultiplierValues')or x.afflictionMultiplier;v.maxAfflictionMultiplier=x.maxAfflictionMultiplierValues and value(x,t,'maxAfflictionMultiplierValues')or x.maxAfflictionMultiplier;if v.chance>0 and(not x.requiresTalent or(t[x.requiresTalent]or 0)>0)then procs[#procs+1]=v;if v.buff then rules[#rules+1]={buff=v.buff,spells=v.consumeOn,condition='when active',text=v.priorityText or v.buff}end end end
 local initialBuffs={};for key,b in pairs(abilities)do if b.grantsBuff and(has(p.activeAuras or {},b.id)or p.shield==key)then local buff=copy(b.grantsBuff);buff.source=key;buff.expires=buff.duration;buff.stacks=1;initialBuffs[buff.key]=buff end end
 local autoResources={};for _,key in ipairs(data.autoResourceKeys or {})do if abilities[key]then autoResources[#autoResources+1]=key end end
 local regen=data.spiritRegeneration or {base=0,perSpirit=0};local regenDelta=((s.spi or 0)-old.spi)*(regen.perSpirit or 0);local naturalRegen=sheet.manaRegen and sheet.manaRegen+regenDelta or(regen.base or 0)+(regen.perSpirit or 0)*spirit;local castingRegen=sheet.castingManaRegen and sheet.castingManaRegen+regenDelta*math.min(1,regenFraction)or naturalRegen*math.min(1,regenFraction)
 return {schema=1,duration=duration,seed=seed,initial=initial,initialBuffs=initialBuffs,autoResources=autoResources,resistance=resistance,encounter=encounter,periodicResources=periodicResources,initialShards=p.soulShards or 0,targetHealthPct=p.targetHealthPct,abilities=abilities,actors=actors,policies=copy(choice.policies),procs=procs,haste=1+((sheet.hastePct or old.hastePct)+(s.hastePct or 0)-old.hastePct)/100,mp5=sheet.manaRegen and((s.mp5 or 0)-old.mp5)or(s.mp5 or 0),naturalRegen=naturalRegen,castingRegen=castingRegen,tapKey=data.recoveryKey and abilities[data.recoveryKey]and data.recoveryKey or nil,tapAtPct=choice.tapAtPct or 0,channelClip=choice.channelClip==true,trace=p.trace==true,rotationRules=rules}
end
function P.rng(seed)local x=((seed%2147483646)+2147483646)%2147483646+1 return function()x=(x*16807)%2147483647 return(x-1)/2147483646 end end
-- Exact 32-bit operations using 16-bit limbs; safe with Lua 5.1 doubles.
local bitlib=bit or bit32
local function bxor(a,b)
 if bitlib then return bitlib.bxor(a,b)%4294967296 end
 local out,power=0,1;a=a%4294967296;b=b%4294967296
 for _=1,32 do local aa,bb=a%2,b%2;if aa~=bb then out=out+power end;a=math.floor(a/2);b=math.floor(b/2);power=power*2 end return out
end
local function bor(a,b)return (a+b-bxor(a,b))/2+bxor(a,b)end
local function shr(a,n)return math.floor(a/2^n)end
local function imul(a,b)local al,ah=a%65536,math.floor(a/65536);local bl,bh=b%65536,math.floor(b/65536);return(al*bl+((ah*bl+al*bh)%65536)*65536)%4294967296 end
function P.mulberry32(seed)local x=seed%4294967296 return function()
 x=(x+1831565813)%4294967296;local t=imul(bxor(x,shr(x,15)),bor(x,1));t=bxor(t,(t+imul(bxor(t,shr(t,7)),bor(t,61)))%4294967296);return bxor(t,shr(t,14))/4294967296
end end
function P.streams(seed)return {hit=P.mulberry32(bxor(seed,461845907)),crit=P.mulberry32(bxor(seed,2246822507)),proc=P.mulberry32(bxor(seed,3266489909)),damage=P.mulberry32(bxor(seed,668265263)),actor=P.mulberry32(bxor(seed,374761393)),resist=P.mulberry32(bxor(seed,668265263)),jow=P.mulberry32(bxor(seed,1013904226)),push=P.mulberry32(bxor(seed,1640531527))}end
function P.run(spec)
 if spec.schema~=1 or spec.duration<=0 or spec.haste<=0 then error('Invalid combat spec')end
 local duration,R=spec.duration,P.streams(spec.seed);local log,rows,actions,q,cds,auras,buffs={},{},{},{},{},{},{}
 buffs=copy(spec.initialBuffs or {});local procDots,debuffs={},{};local channelLanded=nil;local shards=spec.initialShards or 0
  local seq,time,total,mana,health,lastSpend,oom,steps=0,0,0,spec.initial.mana,spec.initial.health,-1e9,0,0
 local energy,rage,combo=(spec.resources or {}).energy or 0,(spec.resources or {}).rage or 0,(spec.resources or {}).combo or 0
 local queuedSwing=nil;local swingStates={};local syncSwingHaste;local actorHit;local actorStates={};local temporaryAttackers={}
 local function available(a)if a.resource=='energy'then return energy elseif a.resource=='rage'then return rage else return mana end end
 local function gainResource(currency,amount,key)if currency=='energy'then energy=math.min((spec.resources or {}).maxEnergy or 100,energy+amount)elseif currency=='rage'then rage=math.min((spec.resources or {}).maxRage or 100,rage+amount)elseif currency=='combo'then combo=math.min((spec.resources or {}).maxCombo or 5,combo+amount)else mana=math.min(spec.initial.mana,mana+amount)end end
 local function spendResource(a,amount)if a.resource=='energy'then energy=energy-amount elseif a.resource=='rage'then rage=rage-amount else mana=mana-amount end end
 local killTime,deathTime
 if spec.targetHP~=nil and(type(spec.targetHP)~='number' or spec.targetHP<=0)then error('Invalid target health')end
 local function ended()return killTime~=nil or deathTime~=nil end
 local function targetHealth(t)return spec.targetHP and math.max(0,100*(spec.targetHP-total)/spec.targetHP) or spec.targetHealthPct or 100*(1-t/duration)end
 local function record(kind,key,amount,extra)if spec.trace then local e={t=time,kind=kind,key=key,amount=amount or 0,mana=mana,health=health,energy=energy,rage=rage,combo=combo}for k,v in pairs(extra or {})do e[k]=v end log[#log+1]=e end end
 local function row(k)if not rows[k]then rows[k]={casts=0,hits=0,misses=0,crits=0,ticks=0,damage=0}end return rows[k]end
 local function wisdom(actor) local j=spec.encounter and spec.encounter.judgementOfWisdom;if not j or R.jow()>=(j.chance or 0) then return end;local amt=j.mana or 0;if actor then local old=actor.remainingMana;actor.remainingMana=math.min(actor.mana,old+amt);record('resource','judgementOfWisdom:pet',actor.remainingMana-old)else local old=mana;mana=math.min(spec.initial.mana,old+amt);record('resource','judgementOfWisdom',mana-old)end end
 local function schedule(t,o,kind,key,extra)if t<=duration+1e-9 then local e={t=t,o=o,kind=kind,key=key,seq=seq};seq=seq+1 for k,v in pairs(extra or {})do e[k]=v end q[#q+1]=e end end
 local function less(a,b)if a.t~=b.t then return a.t<b.t end if a.o~=b.o then return a.o<b.o end return a.seq<b.seq end
 local activeCast,activeChannel=nil,nil;local channelSequence=0
 local resistanceCache={}
 local function mitigation(a,key)
  if a.school=='physical'then if a.bleed or a.ignoreArmor then return 1 end;local dynamic=false;local groups=copy(spec.armorGroups or {});for _,d in pairs(debuffs)do if d.expires>time and d.armorReduction then groups[d.armorGroup]=math.max(groups[d.armorGroup]or 0,d.armorReduction);dynamic=true end end;if dynamic then local armor=spec.armorBeforeGroups;for _,amount in pairs(groups)do armor=armor-amount end;armor=math.max(0,armor)*(1-math.min(1,spec.armorIgnoreFactor or 0));return 1-armor/(armor+400+85*spec.armorLevel)end;return spec.armorMultiplier or 1 end
  if not spec.resistance or a.actor or a.ignoreResistance or a.binary then return 1 end
  local reduction=0;for k,b in pairs(auras)do if b.expires>time and spec.abilities[k].resistReduction then reduction=math.max(reduction,spec.abilities[k].resistReduction)end end
  local cacheKey=a.school..':'..reduction;local profile=resistanceCache[cacheKey]
  if not profile then profile=P.resistanceProfile(spec.resistance,a.school,reduction);resistanceCache[cacheKey]=profile end
  if #profile.dist==1 then return 1+profile.dist[1].pct/100 end
  local roll=R.resist();local cumulative=0
  for i,entry in ipairs(profile.dist)do cumulative=cumulative+entry.p;if roll<cumulative or i==#profile.dist then record('resistance',key,entry.pct,{roll=roll,effectiveResistance=profile.R});return 1+entry.pct/100 end end
 end
 local procReady={}
 local targetModifiers
 local function proc(trigger,key,amount)for _,p in ipairs(spec.procs or {})do if(procReady[p.cooldownKey or p.buff or p.key or p.talent]or 0)<=time+1e-9 and(not p.requiresBuff or(buffs[p.requiresBuff]and buffs[p.requiresBuff].charges>0 and buffs[p.requiresBuff].expires>time))and(not p.targetBelow or targetHealth(time)<p.targetBelow)and p.trigger==trigger and(not p.encounterFlag or spec.encounter[p.encounterFlag]==true)and(not p.requiresAura or(auras[p.requiresAura]and auras[p.requiresAura].expires or 0)>time)and(not p.sourceHand or(spec.abilities[key]and spec.abilities[key].weaponDamage and spec.abilities[key].weaponDamage.hand==p.sourceHand))and(not p.sourceAttackTypes or has(p.sourceAttackTypes,(spec.abilities[key]or {}).attackType))and has(p.sources,key)and schoolMatches(p.sourceSchools,spec.abilities[key]or {})then local roll=R.proc();record('procRoll',p.key or p.buff or p.talent,roll,{trigger=trigger,source=key})if roll<((p.sourceChances or {})[key]or p.chance)then if p.cooldown then procReady[p.cooldownKey or p.buff or p.key or p.talent]=time+p.cooldown end
 if p.debuff then local old=debuffs[p.debuff];debuffs[p.debuff]={expires=time+p.duration,stacks=math.min(p.maxStacks or 1,(old and old.expires>time and old.stacks or 0)+1)};record('debuff',p.debuff,debuffs[p.debuff].stacks)end
 if p.spendBuff then buffs[p.spendBuff].charges=buffs[p.spendBuff].charges-1;record('consume',p.spendBuff)end;if p.buff then local old=buffs[p.buff];buffs[p.buff]={expires=time+p.duration,charges=p.keepCharges and old and old.charges or p.charges or 1,stacks=p.initialStacks or math.min(p.maxStacks or 1,(old and old.expires>time and old.charges>0 and old.stacks or 0)+(p.stackGain or 1))};local bf=buffs[p.buff];bf.charges=p.maxStacks and bf.stacks or bf.charges;bf.damageBonus=p.buffDamagePerStack and p.buffDamagePerStack*bf.stacks;bf.schools=p.buffDamageSchools;bf.castingRegen=p.buffCastingRegen;bf.apMultiplier=p.buffAPMultiplier;bf.castHaste=p.buffCastHaste;bf.gcdFactor=p.buffGCDFactor;bf.gcdSpells=p.buffGCDSpells;record('buff',p.buff,bf.stacks)end
 if p.manaRefund and p.manaRefund~=0 then local before=mana;mana=math.min(spec.initial.mana,mana+spec.abilities[key].baseCost*p.manaRefund);record('resource',p.talent,mana-before)end
 if p.comboGain then gainResource('combo',p.comboGain,p.key);record('combo',p.key,p.comboGain)end
 if p.extraSpell then local a=copy(spec.abilities[key]);for k,v in pairs((a.triggeredDamage or {})[p.key]or {})do a[k]=v end;local k=p.key;local r=row(k);r.casts=r.casts+1;local hit=R.hit();record('hitRoll',k,hit);if hit>=a.hit then r.misses=r.misses+1;record('miss',k)else local bonus,mult=targetModifiers(k,a);local critical=R.crit()<math.min(1,a.crit+bonus);local d=((a.base or 0)+(a.max~=nil and R.damage()*(a.max-a.base)or 0)+(a.coef or 0)*a.sp)*a.directMult*mult*p.damageFraction*mitigation(a,k)*(critical and a.critMult or 1);r.hits=r.hits+1;wisdom(nil);if critical then r.crits=r.crits+1 end;r.damage=r.damage+d;total=total+d;record('damage',k,d,{crit=critical})end
 elseif p.damageFraction and p.damageFraction~=0 then local d=amount*p.damageFraction;if p.tickEvery then local count=math.floor(p.duration/p.tickEvery);if p.rolling then local old=procDots[p.key];local nextTick=old and old.left>0 and old.next or time+p.tickEvery;local dot={pool=(old and old.pool or 0)+d,left=count,next=nextTick,version=(old and old.version or 0)+1,every=p.tickEvery};procDots[p.key]=dot;schedule(nextTick,0,'rollingTick',p.key,{version=dot.version})else for i=1,count do schedule(time+i*p.tickEvery,0,'procTick',p.key,{amount=d/count})end end else row(p.key).damage=row(p.key).damage+d;total=total+d;record('damage',p.key,d)end end
 end end end end
 targetModifiers=function(key,a)local crit,mult=0,1;for _,b in pairs(buffs)do if b.expires>time and b.charges>0 and b.damageBonus and schoolMatches(b.schools,a)then mult=mult*(1+b.damageBonus)end;if a.actor and b.expires>time and b.charges>0 and b.actorDamageBonus then mult=mult*(1+b.actorDamageBonus)end end;for _,b in pairs(debuffs)do if b.expires>time and(b.charges or 0)>0 and b.damageBonus and has(b.affectedSpells,key)and schoolMatches(b.affectedSchools,a)then mult=mult*(1+b.damageBonus)end end;
 for _,rule in ipairs(spec.conditionalModifiers or {})do local bleeding=not rule.requiresBleed;for k,b in pairs(auras)do if b.expires>time and spec.abilities[k].bleed then bleeding=true end end;if has(rule.targets,key)and has(rule.attackTypes,a.attackType)and(not rule.excludeWhite or not a.white)and(not rule.targetBelow or targetHealth(time)<=rule.targetBelow)and bleeding then if rule.field=='crit'then crit=crit+rule.value elseif rule.field=='damage'then mult=mult*(1+rule.value)end end end
 if activeChannel and activeChannel.ends>time-1e-9 then
  local ch=spec.abilities[activeChannel.key]
  if ch and ch.channelDamageBonus and has(ch.channelAffectedSpells,key)then
   mult=mult*(1+ch.channelDamageBonus)
  end
 end;
for _,p in ipairs(spec.procs or {})do local b=p.buff and buffs[p.buff];if b and b.charges>0 and b.expires>time and p.buffCritPerStack and not p.snapshotCrit and not has(p.critExcluded or {},key)and has(p.damageOn,key)and has(p.damageAttackTypes,a.attackType)and schoolMatches(p.damageSchools,a)then crit=crit+p.buffCritPerStack*b.stacks end end;for k,b in pairs(auras)do if b.expires>time and spec.abilities[k].damageTakenBonus and a.school~='physical'then mult=mult*(1+spec.abilities[k].damageTakenBonus)end end;for _,p in ipairs(spec.procs or {})do local b=p.debuff and debuffs[p.debuff];if b and b.expires>time and not(a.actor and p.ownerOnly)and has(p.affectedSpells,key)and schoolMatches(p.affectedSchools,a)then crit=crit+(p.critPerStack or 0)*b.stacks;mult=mult*(1+(p.damagePerStack or 0)*b.stacks)end end for _,p in ipairs(spec.procs or {})do if p.afflictionMultiplier and has(p.affectedSpells,key)then local count=0;for k,b in pairs(auras)do if k~=key and b.expires>time and spec.abilities[k]and spec.abilities[k].tree=='affliction'then count=count+1 end end;mult=mult*(1+math.min(p.maxAfflictionMultiplier,count*p.afflictionMultiplier))end end if a.poison then for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time and bf.poisonDamageBonus then mult=mult*(1+bf.poisonDamageBonus)end end end;if a.actor then for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time then crit=crit+(bf.actorCritBonus or 0)end end end;return crit,mult end
 local function damage(key,amount,tick,crit,asDirect)if amount<0 or amount~=amount then error('Invalid damage')end total=total+amount local r=row(key);r.damage=r.damage+amount if tick then r.ticks=r.ticks+1 end if crit then r.crits=r.crits+1 end record(tick and 'tick'or 'damage',key,amount,{crit=crit==true});for _,b in pairs(debuffs)do if b.expires>time and(b.charges or 0)>0 and b.damageBonus and has(b.affectedSpells,key)and schoolMatches(b.affectedSchools,spec.abilities[key]or {})then b.charges=b.charges-1 end end;proc(tick and not asDirect and 'tick'or 'hit',key,amount);if crit and(not tick or asDirect)then proc('crit',key,amount)end end
 local function weaponRoll(a)
  if not a.weapon then return 0 end
  local w=a.weapon;local rolled=w.min+R.damage()*(w.max-w.min);local speed=a.weaponDamage.normalized and(w.normalizedSpeed or w.speed)or w.speed
  -- Live UnitDamage includes AP and its damage multiplier. Parsed item damage does not.
  local liveAP=a.ap or 0;for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time and bf.apMultiplier then liveAP=liveAP*(1+bf.apMultiplier)end end
  local captured=w.includesAttackPower and(w.attackPower or a.ap or 0)*w.speed/14*(w.handMultiplier or 1)or 0
  local mult=w.damageMultiplier or 1
  return (rolled-captured*mult+liveAP*speed/14*mult*(w.includesAttackPower and(w.handMultiplier or 1)or 1))/(w.modelledDamageFactor or 1)*(w.offhandMultiplier or 1)
 end
 local direct
 direct=function(a,key,event)
  event=event or {};local hit=R.hit();record('hitRoll',key,hit);local table=a.attackTable;local glancing,blocked=false,false;local hitCritical=false
  local miss=false
  if table then
   local gate=table.miss+(a.noActiveDefense and 0 or table.dodge+table.parry);miss=hit<gate
   if not miss and a.white then glancing=hit<gate+table.glance;blocked=not glancing and hit<gate+table.glance+table.block end
  else
   local chance=a.hit
   if a.binary and spec.resistance then local rp=P.resistanceProfile(spec.resistance,a.school,0);chance=chance*(1+math.min(0,rp.mean))end
   miss=hit>=chance
  end
  if miss then
   if table and hit>=table.miss and hit<table.miss+table.dodge then proc('targetDodge',key,0)end
   row(key).misses=row(key).misses+1;record('miss',key)
   if event.paidCost and(a.refundFraction or 0)>0 then local refund=event.paidCost*a.refundFraction;gainResource(a.resource,refund,key);record('refund',key,refund)end
   return false
  end
  if a.applicationAttackGate and table then local gate=table.miss+table.dodge+table.parry;if R.hit()<gate then row(key).misses=row(key).misses+1;record('miss',key);return false end end
  row(key).hits=row(key).hits+1;wisdom(nil)
  local cp=event.comboPoints or 0
  local raw=(a.base or 0)+(a.max~=nil and R.damage()*(a.max-a.base)or 0)+weaponRoll(a)+(a.comboDamage or 0)*cp+(a.comboAPCoef or 0)*cp*(a.ap or 0)+(a.extraResourceDamage or 0)*(event.extraResource or 0)+(a.apCoef or 0)*(a.ap or 0)+(a.blockValueCoef or 0)*(a.blockValue or 0)
  if a.weaponDamage then raw=raw*(a.weaponDamage.multiplier or 1)end
  local amount=(raw+(a.coef or 0)*a.sp)*(a.directMult or a.mult)
  if a.damageIfAura and(auras[a.damageIfAura.key]and auras[a.damageIfAura.key].expires or 0)>time then amount=amount*a.damageIfAura.multiplier end
  if a.mobDamageBonus and has(a.mobDamageBonus.types,spec.encounter.mobType)then amount=amount*a.mobDamageBonus.multiplier end;if a.damageIfPoison then for k,bf in pairs(auras)do if bf.expires>time and spec.abilities[k]and spec.abilities[k].poison then amount=amount*a.damageIfPoison;break end end end
  if event.frozen and a.frozenMultiplier then amount=amount*a.frozenMultiplier end
  if a.executeBelow and targetHealth(time)<a.executeBelow then amount=amount*(1+(a.executeBonus or 0))end
  if a.base~=nil and a.kind~='actor'then
   local roll=R.crit();record('critRoll',key,roll);local bonus,mult=targetModifiers(key,a)
   local critical=not a.cannotCrit and roll<math.min(1,(table and table.crit or a.crit)+bonus+(event.bonusCrit or 0)+(event.frozen and(a.frozenCrit or 0)or 0))
   if a.white and table then local gate=table.miss+table.dodge+table.parry+table.glance+table.block;critical=not glancing and not blocked and hit<gate+table.crit+bonus end
   local dealt=amount*mult*(event.damageMultiplier or 1)*mitigation(a,key)*(critical and a.critMult or 1)
   if glancing then dealt=dealt*(table.glanceMultiplier+table.glanceSpread*(2*R.damage()-1));record('glance',key,dealt)end
   if blocked then dealt=math.max(0,dealt-((spec.encounter or {}).blockValue or 0))end
   hitCritical=critical;damage(key,dealt,false,critical)
   if a.white and a.attackType=='melee'then for _,bf in pairs(buffs)do if bf.group=='seal'and bf.expires>time then local seal=spec.abilities[bf.source];local pr=seal and seal.sealProc;if pr then if pr.spellKey then local ready='seal:'..bf.source;if(procReady[ready]or 0)<=time and R.proc()<math.min(1,pr.ppm*a.weapon.speed/60)then procReady[ready]=time+pr.icd;local child=spec.abilities[pr.spellKey];row(pr.spellKey).casts=row(pr.spellKey).casts+1;direct(child,pr.spellKey,{weaponProc=true})end else local two=a.weapon.normalizedSpeed==3.3;local raw=pr.basePerSpeed*a.weapon.speed*(two and pr.twoHand or pr.oneHand)+pr.coef*seal.sp*(two and pr.twoHandSP or 1);local bonus,mult=targetModifiers(bf.source..':proc',seal);local crit=R.crit()<math.min(1,(a.attackTable and a.attackTable.crit or a.crit)+bonus);damage(bf.source..':proc',raw*seal.directMult*mult*mitigation(seal,key)*(crit and a.critMult or 1),false,crit)end end end end end
   if a.damageDot then local d=a.damageDot;local count=math.floor(d.duration/d.tickEvery);local old=procDots[d.key];local dot={pool=dealt*d.fraction,left=count,next=time+d.tickEvery,version=(old and old.version or 0)+1,every=d.tickEvery,crit=d.periodicCrit and d.crit or 0,critMult=d.critMult};procDots[d.key]=dot;schedule(dot.next,0,'rollingTick',d.key,{version=dot.version})end
   if a.temporaryAttacker then local rule=a.temporaryAttacker;local slots=temporaryAttackers[rule.key]or {};temporaryAttackers[rule.key]=slots;local index=1;for i=1,rule.maxSlots do if not slots[i]or slots[i].expires<=time then index=i;break elseif slots[i].expires<slots[index].expires then index=i end end;local version=(slots[index]and slots[index].version or 0)+1;slots[index]={expires=time+rule.duration,version=version,rule=rule};schedule(time,0,'temporaryAttack',rule.key,{slot=index,version=version})end
   if a.white and a.resource=='rage'then local factor=a.weapon.normalizedSpeed==3.3 and 4.5 or 3.46;local gain=factor*a.weapon.speed*(a.weapon.offhandMultiplier and a.weaponDamage.hand=='offhand'and .5 or 1)*(critical and 1.75 or 1);if a.weaponDamage.hand=='offhand'then gain=gain*(spec.offhandRageMultiplier or 1)end;gainResource('rage',gain,key);record('resource','rage',gain)end
   if a.leechFraction then local before=health;health=math.min(spec.initial.health,health+dealt*a.leechFraction);record('heal',key,health-before)end
   if a.selfHealthFraction and(not spec.targetHP or total<spec.targetHP)then local loss=spec.initial.health*a.selfHealthFraction;health=math.max(0,health-loss);record('selfDamage',key,loss);if health==0 then deathTime=time end end
   if a.selfDamageFromHit then health=math.max(0,health-dealt*a.selfDamageFromHit);record('selfDamage',key,dealt*a.selfDamageFromHit);if health==0 then deathTime=time end end
   for _,rule in ipairs(spec.genericProcs or {})do
    local buff=rule.key and buffs[rule.key]
    if a.white and rule.consumeOnWhite and buff and buff.expires>time and not critical then buff.charges=math.max(0,buff.charges-1);record('consume',rule.key)end
    local allowed=has(rule.sources,key)and(not rule.meleeOnly or a.attackType=='melee')and(not rule.weaponSubclasses or a.weapon and has(rule.weaponSubclasses,a.weapon.subclass))and(not rule.hand or a.weaponDamage and a.weaponDamage.hand==rule.hand)and(not rule.onCrit or critical)and(not rule.extraAttacks or not event.weaponProc)and(not rule.spellKey or a.weaponDamage~=nil)and(procReady[rule.key]or 0)<=time
    local poisonBonus=0;if rule.spellKey and spec.abilities[rule.spellKey].poison then for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time then poisonBonus=poisonBonus+(bf.poisonChanceBonus or 0)end end end
    local chance=rule.ppm and math.min(1,rule.ppm*(a.weapon and a.weapon.speed or 0)/60)or(rule.chance+poisonBonus)
    if allowed and R.proc()<chance then
     if rule.icd then procReady[rule.key]=time+rule.icd end
     if rule.comboGain then combo=math.min((spec.resources or {}).maxCombo or 5,combo+rule.comboGain)end
     if rule.resourceGain then gainResource(rule.resource,rule.resourceGain,key);record('resource',rule.key,rule.resourceGain)end
     if rule.attackHaste or rule.rangedHaste or rule.castMultiplier then local old=buffs[rule.key];buffs[rule.key]={expires=time+rule.duration,charges=rule.charges or 1,stacks=math.min(rule.maxStacks or 1,(old and old.expires>time and old.charges>0 and old.stacks or 0)+1),attackHaste=rule.attackHaste,rangedHaste=rule.rangedHaste};record('buff',rule.key,buffs[rule.key].stacks);if rule.attackHaste or rule.rangedHaste then schedule(time+rule.duration,0,'refreshAttackHaste',rule.key)end end
     if rule.weaponPoolDamage then local old=procDots[rule.key];local nextTick=old and old.left>0 and old.next or time+rule.tickEvery;local dot={pool=(old and old.pool or 0)+rule.weaponPoolDamage,left=math.floor(rule.duration/rule.tickEvery),next=nextTick,version=(old and old.version or 0)+1,every=rule.tickEvery};procDots[rule.key]=dot;schedule(nextTick,0,'rollingTick',rule.key,{version=dot.version})end
     if rule.spellKey and a.weaponDamage then local child=spec.abilities[rule.spellKey];row(child.key).casts=row(child.key).casts+1;if direct(child,child.key,{weaponProc=true})and child.stackingDot then local old=auras[child.key];local active=old and old.expires>time;local nextTick=active and old.nextTick or(time+(child.tickEvery or child.duration));local version=(old and old.version or 0)+1;local stacks=math.min(child.maxStacks,(active and old.stacks or 0)+1);auras[child.key]={expires=time+child.duration,version=version,stacks=stacks,nextTick=nextTick};record('debuff',child.key,stacks);if child.tickEvery then schedule(nextTick,0,'stackingTick',child.key,{version=version})end end end
     if rule.extraAttacks then
      local child=copy(rule.extraMainhand and spec.abilities['auto:mainhand']or a);child.key=rule.key;child.white=rule.whiteExtra==true;child.nextSwing=false;child.base=0;child.max=0;child.comboGain=nil;child.ap=(a.ap or 0)+(rule.attackPowerBonus or 0);child.weaponDamage.normalized=false;child.weaponDamage.multiplier=1
      local ctx=spec.physicalContext;child.attackTable=P.physicalTable(ctx.levelDifference,ctx.hit,child.crit,ctx.expertise,child.white,spec.abilities['auto:offhand']~=nil,ctx.front);child.cost=0;if not child.white then child.resource='mana'end
      for i=1,rule.extraAttacks do row(child.key).casts=row(child.key).casts+1;direct(child,child.key,{weaponProc=true})end
     end
    end
   end
  end
  if spec.typedCombat and a.base==nil then proc('applicationHit',key,0)end
  if a.comboGain then combo=math.min((spec.resources or {}).maxCombo or 5,combo+a.comboGain);record('combo',key,a.comboGain)end
  if a.actor and actorHit then actorHit(key,hitCritical)end
  if a.spendCombo then combo=0;record('combo',key,-cp);for _,rule in ipairs(spec.finisherProcs or {})do if R.proc()<math.min(1,rule.chance*(rule.perCombo and cp or 1))then if rule.comboGain then combo=math.min((spec.resources or {}).maxCombo or 5,combo+rule.comboGain);record('combo',rule.key,rule.comboGain)end;if rule.resourceGain then gainResource(rule.resource,rule.resourceGain,rule.key);record('resource',rule.key,rule.resourceGain)end end end;if a.fullComboRefund and cp==5 then gainResource('combo',a.fullComboRefund.amount,key);record('combo',key,a.fullComboRefund.amount)end end
  if syncSwingHaste then syncSwingHaste()end
  return true
 end
 actorStates={}for _,x in ipairs(spec.actors or {})do local a=copy(x);a.remainingMana=x.mana;a.lastRegen=0;actorStates[#actorStates+1]=a end
 actorHit=function(key,critical)
  for _,bf in pairs(buffs)do if bf.consumeOnActorHit and bf.charges>0 and bf.expires>time then bf.charges=0;record('consume',bf.key or bf.source)end end
  if critical and spec.petFrenzy and R.actor()<spec.petFrenzy.chance then for index,actor in ipairs(actorStates)do if actor.generic then local active=actor.frenzyUntil and actor.frenzyUntil>time;actor.frenzyUntil=time+spec.petFrenzy.duration;if not active and actor.nextSwing and actor.nextSwing.t>time then actor.nextSwing.t=time+(actor.nextSwing.t-time)/(1+spec.petFrenzy.attackHaste)end;schedule(actor.frenzyUntil,0,'actorHasteExpire','petFrenzy',{actor=index,expires=actor.frenzyUntil});record('buff','petFrenzy')end end end
 end
 local function actorDamage(a,key,melee,actor)local roll=R.actor();local r=row(key);r.casts=r.casts+1
  if melee then if roll<a.miss+a.dodge then r.misses=r.misses+1;record('miss',key);return end
   local _,targetMult=targetModifiers(key,{actor=true,school='physical'});local critBonus=0;for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time then critBonus=critBonus+(bf.actorCritBonus or 0)end end
   local amount=(a.base+a.sp)*a.mult*a.armorMultiplier*targetMult;local critical=false
   if roll<a.miss+a.dodge+a.glance then amount=amount*a.glanceMult elseif roll<a.miss+a.dodge+a.glance+a.crit+critBonus then amount=amount*a.critMult;critical=true end
   r.hits=r.hits+1;wisdom(actor);if critical then r.crits=r.crits+1 end;r.damage=r.damage+amount;total=total+amount;record('damage',key,amount,{crit=critical});if actor.generic then actorHit(key,critical)end
  else if roll>=a.hit then r.misses=r.misses+1;record('miss',key);return end;wisdom(actor);local critical=R.actor()<a.crit;local _,targetMult=targetModifiers(key,a);local amount=(a.base+(a.max and R.damage()*(a.max-a.base)or 0)+a.coef*a.sp)*a.directMult*targetMult*(critical and a.critMult or 1);r.hits=r.hits+1;wisdom(actor);if critical then r.crits=r.crits+1 end;r.damage=r.damage+amount;total=total+amount;record('damage',key,amount,{crit=critical})end
  for _,bonus in ipairs(actor and actor.hitBonuses or {})do local b=buffs[bonus.buff];if b and b.expires>time and b.charges>0 then b.charges=b.charges-1;record('consume',bonus.buff);local _,mult=targetModifiers(bonus.key,bonus);local critical=bonus.canCrit and R.actor()<bonus.crit or false;local base=bonus.base+(bonus.max~=nil and R.actor()*(bonus.max-bonus.base)or 0);local d=(base+bonus.coef*bonus.sp)*bonus.mult*mult*(critical and bonus.critMult or 1);local br=row(bonus.key);br.casts=br.casts+1;br.hits=br.hits+1;if critical then br.crits=br.crits+1 end;br.damage=br.damage+d;total=total+d;record('damage',bonus.key,d,{crit=critical})end end
 end
 local function setTime(to)local dt=to-time;if dt>0 then if spec.resources then local ticks=math.floor((to+1e-9)/spec.resources.energyTick)-math.floor((time+1e-9)/spec.resources.energyTick);local extra=0;for _,bf in pairs(buffs)do if bf.energyRegenBonus and bf.expires>time then local activeTicks=math.floor((math.min(to,bf.expires)+1e-9)/spec.resources.energyTick)-math.floor((time+1e-9)/spec.resources.energyTick);extra=extra+activeTicks*spec.resources.energyPerTick*bf.energyRegenBonus end end;energy=math.min(spec.resources.maxEnergy,energy+ticks*spec.resources.energyPerTick+extra)end; local extraRegen=0;for _,b in pairs(buffs)do if b.regenMultiplier and b.expires>time then extraRegen=extraRegen+(math.min(to,b.expires)-time)*((1+b.regenMultiplier)*spec.naturalRegen-(spec.castingRegen or 0))-math.max(0,math.min(to,b.expires)-math.max(time,lastSpend+5))*(spec.naturalRegen-(spec.castingRegen or 0))end end;local outside=channelLanded and 0 or math.max(0,to-math.max(time,lastSpend+5));local bonusCasting=0;for _,bf in pairs(buffs)do if bf.castingRegen and bf.expires>time and bf.charges>0 then local active=math.max(0,math.min(to,bf.expires,lastSpend+5)-time);bonusCasting=bonusCasting+active*spec.naturalRegen*bf.castingRegen end end;local gain=bonusCasting+extraRegen+spec.mp5/5*dt+(spec.castingRegen or 0)*(dt-outside)+spec.naturalRegen*outside;local before=mana;mana=math.min(spec.initial.mana,mana+gain);time=to;if mana>before then record('regen','mana',mana-before)end else time=to end end
 local function adjustedCost(a,key)
  local cost=a.cost;for _,p in ipairs(spec.procs or {})do local b=p.buff and buffs[p.buff];if b and b.charges>0 and b.expires>time then if has(p.costOn or p.consumeOn,key)and p.costMultiplierPerStack then cost=cost*(1+p.costMultiplierPerStack*b.stacks)end;if has(p.consumeOn,key)and p.costFlatPerStack then cost=cost+p.costFlatPerStack*b.stacks end;if has(p.consumeOn,key)and p.costOverride~=nil then cost=p.costOverride end end end;return math.max(0,cost)
 end
 local function attackHaste(hand)
  local h=hand=='ranged'and(spec.rangedHaste or spec.haste)or(spec.meleeHaste or spec.haste)
  for _,b in pairs(buffs)do if b.expires>time and b.charges>0 and b.attackHaste and hand~='ranged'then h=h*(1+b.attackHaste)end;if b.expires>time and b.charges>0 and b.rangedHaste and hand=='ranged'then h=h*(1+b.rangedHaste)end end
  return h
 end
 syncSwingHaste=function()
  for hand,state in pairs(swingStates)do local h=attackHaste(hand);local old=state.haste or(hand=='ranged'and(spec.rangedHaste or spec.haste)or(spec.meleeHaste or spec.haste));if state.event and state.event.t>time and h~=old then state.event.t=time+(state.event.t-time)*old/h end;state.haste=h end
 end
 local function process(e)setTime(e.t)
  if e.kind=='temporaryAttack'then local slot=(temporaryAttackers[e.key]or {})[e.slot];if not slot or slot.version~=e.version or time>=slot.expires then return end;local rule=slot.rule;local hit=R.hit();local table=rule.hit;if hit>=table.miss+table.dodge+table.parry then local amount=rule.damage*(spec.abilities[e.key].directMult or 1)*mitigation({school='physical'},e.key);row(e.key..':swings').casts=row(e.key..':swings').casts+1;row(e.key..':swings').hits=row(e.key..':swings').hits+1;row(e.key..':swings').damage=row(e.key..':swings').damage+amount;total=total+amount;record('damage',e.key..':swings',amount)end;local haste=rule.realRangedHaste and attackHaste('ranged')or 1;local every=math.floor(rule.every/haste*1000+.5)/1000;schedule(time+every,0,'temporaryAttack',e.key,{slot=e.slot,version=e.version});return end
  if e.kind=='actorHasteExpire'then local actor=actorStates[e.actor];if actor.frenzyUntil==e.expires then actor.frenzyUntil=nil;if actor.nextSwing and actor.nextSwing.t>time then actor.nextSwing.t=time+(actor.nextSwing.t-time)*(1+spec.petFrenzy.attackHaste)end end;return end
  if e.kind=='refreshAttackHaste'then syncSwingHaste();return end
  if e.kind=='periodicCurrency'then local rule=spec.periodicCurrency[e.rule];gainResource(rule.resource,rule.amount,rule.key);record('resource',rule.key,rule.amount);schedule(time+rule.every,0,'periodicCurrency',rule.key,{rule=e.rule});return end
  if e.kind=='ownerSwing'then
   if time>=duration-1e-9 then return end
   local state=swingStates[e.hand];local a=spec.abilities[e.key]
   if state and state.event~=e then return end;local stealth=buffs.stealth;if stealth and stealth.charges>0 and stealth.expires>time then e.t=time+.1;q[#q+1]=e;return end
   if a.attackType=='ranged'and activeCast and spec.abilities[activeCast.key].pausesAutoAttack and activeCast.ends>time then e.t=activeCast.ends;q[#q+1]=e;return end
   local key=e.key;local paid=0
   if e.hand=='mainhand'and queuedSwing then local queued=spec.abilities[queuedSwing];if available(queued)>=queued.cost then a=queued;key=queuedSwing;paid=queued.cost;spendResource(a,paid)end;queuedSwing=nil end
   row(key).casts=row(key).casts+1;direct(a,key,{paidCost=paid});schedule(math.max(time,state.resetAfter or 0)+state.speed/attackHaste(e.hand),0,'ownerSwing',e.key,{hand=e.hand});state.event=q[#q];return
  end

  if e.kind=='incomingHit'then
   if spec.encounter.incomingDamage then local loss=math.max(0,spec.encounter.incomingDamage);health=math.max(0,health-loss);if spec.resource=='rage'then gainResource('rage',loss*10/spec.initial.health,'incoming')end;record('incoming','target',loss);if loss>0 then proc('incomingHit','target',loss)end;if health==0 then deathTime=time;return end end
   for _,b in pairs(buffs)do if b.source and b.charges>0 and b.expires>time and(procReady['reactive:'..(b.group or b.source)]or 0)<=time then local a=spec.abilities[b.source];if b.reactiveManaFraction or b.reactiveDamage then b.charges=b.charges-1;procReady['reactive:'..(b.group or b.source)]=time+b.reactiveCooldown;if b.reactiveManaFraction then local before=mana;mana=math.min(spec.initial.mana,mana+spec.initial.mana*b.reactiveManaFraction);record('resource',b.source,mana-before)end;if b.reactiveDamage then damage(b.source,(a.reactiveBase+a.reactiveCoef*a.sp)*a.directMult*mitigation(a,b.source),false,false)end;record('consume',b.source)end end end
   local c=activeChannel or activeCast
   if c and c.ends>time+1e-9 then
    local a=spec.abilities[c.key];local protection=math.min(1,(a.pushbackAvoidance or 0)+((spec.encounter or {}).pushbackAvoidance or 0))
    if protection>0 and R.push()<protection then record('pushResist',c.key,protection)
    elseif activeChannel then local old=c.ends;c.ends=math.max(time,c.ends-c.full*.25);record('pushback',c.key,old-c.ends,{channel=true})
    else local old=c.ends;c.ends=math.min(old+math.max(.2,1-.2*c.hits)*(1-math.min(1,a.pushbackReduction or 0)),time+c.full);c.hits=c.hits+1;local delay=c.ends-old
     if delay>1e-9 then c.event.t=c.event.t+delay;lastSpend=lastSpend+delay;cds[a.cooldownGroup or c.key]=cds[a.cooldownGroup or c.key]+delay;record('pushback',c.key,delay,{channel=false})end
    end
   end
   schedule(time+spec.encounter.hitEvery,1,'incomingHit','target');return
  end
  if e.kind=='actorAct'then local actor=actorStates[e.actor];local a=actor.spell;if actor.generic then
   local ticks=math.floor((time+1e-9)/actor.focusTick)-math.floor((actor.lastRegen+1e-9)/actor.focusTick);actor.remainingMana=math.min(actor.mana,actor.remainingMana+ticks*actor.focusTick*actor.manaRegen);actor.lastRegen=time;actor.cooldowns=actor.cooldowns or {};a=nil;for _,ability in ipairs(actor.spells or {})do if actor.remainingMana>=ability.cost and(actor.cooldowns[ability.key]or 0)<=time then a=ability;break end end
   if not a then schedule(time+.25,2,'actorAct','pet',{actor=e.actor});return end;actor.remainingMana=actor.remainingMana-a.cost;actor.cooldowns[a.key]=time+a.cooldown;record('actorStart',a.key,a.cost);row(a.key).casts=row(a.key).casts+1;direct(a,a.key);schedule(time+a.gcd,2,'actorAct','pet',{actor=e.actor});return
  end;if time>=duration-1e-9 then return end;actor.remainingMana=math.min(actor.mana,actor.remainingMana+actor.manaRegen*(time-actor.lastRegen));actor.lastRegen=time
   if actor.remainingMana<a.cost then if actor.manaRegen>0 then schedule(time+math.max(.1,(a.cost-actor.remainingMana)/actor.manaRegen),2,'actorAct',a.key,{actor=e.actor})end;return end
   actor.remainingMana=actor.remainingMana-a.cost;record('actorStart','pet:'..a.key,a.cost);schedule(time+a.cast,1,'actorLand','pet:'..a.key,{actor=e.actor});schedule(time+math.max(a.cast,a.cooldown or a.gcd or 1.5),2,'actorAct',a.key,{actor=e.actor});return
  elseif e.kind=='actorLand'then actorDamage(actorStates[e.actor].spell,e.key,false,actorStates[e.actor]);return
  elseif e.kind=='actorSwing'then local a=actorStates[e.actor].melee;if time>=duration-1e-9 then return end;actorDamage(a,e.key,true,actorStates[e.actor]);local actor=actorStates[e.actor];schedule(time+a.swing/(actor.frenzyUntil and actor.frenzyUntil>time and(1+spec.petFrenzy.attackHaste)or 1),0,'actorSwing',e.key,{actor=e.actor});actor.nextSwing=q[#q];return end

  if e.kind=='periodicResource'then local x=spec.periodicResources[e.rule];local beforeMana,beforeHealth=mana,health;mana=math.min(spec.initial.mana,mana+spec.initial.mana*(x.manaFraction or 0));health=math.min(spec.initial.health,health+spec.initial.health*(x.healthFraction or 0));if mana>beforeMana then record('resource',x.key,mana-beforeMana)end;if health>beforeHealth then record('heal',x.key,health-beforeHealth)end;schedule(time+x.every,0,'periodicResource',x.key,{rule=e.rule})
  elseif e.kind=='rollingTick'then local dot=procDots[e.key];if not dot or dot.version~=e.version or dot.left<1 then return end;local amount=dot.pool/dot.left;local critical=dot.crit and R.crit()<dot.crit or false;local uncritical=amount;dot.pool=dot.pool-uncritical;if critical then amount=amount*dot.critMult;row(e.key).crits=row(e.key).crits+1 end;dot.left=dot.left-1;dot.next=time+dot.every;row(e.key).damage=row(e.key).damage+amount;row(e.key).ticks=row(e.key).ticks+1;total=total+amount;record('tick',e.key,amount,{crit=critical});if dot.left>0 then schedule(dot.next,0,'rollingTick',e.key,{version=dot.version})end
  elseif e.kind=='stackingTick'then local dot=auras[e.key];local a=spec.abilities[e.key];if not dot or dot.version~=e.version or time>dot.expires+1e-9 then return end;local bonus,mult=targetModifiers(e.key,a);local critical=a.periodicCrit and R.crit()<math.min(1,a.crit+bonus)or false;local amount=a.tickBase*dot.stacks*a.periodicMult*mult*mitigation(a,e.key)*(critical and a.critMult or 1);damage(e.key,amount,true,critical);dot.nextTick=time+a.tickEvery;if dot.nextTick<=dot.expires+1e-9 then schedule(dot.nextTick,0,'stackingTick',e.key,{version=dot.version})end
  elseif e.kind=='procTick'then row(e.key).damage=row(e.key).damage+e.amount;row(e.key).ticks=row(e.key).ticks+1;total=total+e.amount;record('tick',e.key,e.amount,{crit=false})
  elseif e.kind=='channelStart'then local a=spec.abilities[e.key];row(e.key).casts=row(e.key).casts+1;record('channel',e.key);if a.regenMultiplier then buffs[e.key]={expires=time+e.castDuration/spec.haste,charges=1,stacks=1,regenMultiplier=a.regenMultiplier};record('buff',e.key,1)end;channelLanded=not a.applicationHit or direct(a,e.key,e);if a.procApplication and R.hit()<a.hit then proc('applicationHit',e.key,0)end;if channelLanded then wisdom(nil)end;if channelLanded and a.tickEvery then for i=(a.tickAtStart and 0 or 1),math.floor(a.duration/a.tickEvery)do schedule(time+i*a.tickEvery*(e.castDuration/a.duration)/spec.haste,0,'channelTick',e.key,{channelId=activeChannel and activeChannel.id,index=i,damageMultiplier=e.damageMultiplier,periodicDamageMultiplier=e.periodicDamageMultiplier,periodicBaseMultiplier=e.periodicBaseMultiplier,frozen=e.frozen,bonusCrit=e.bonusCrit})end end;if channelLanded then proc('channelApplied',e.key,0)end;proc('cast',e.key,0)
  elseif e.kind=='channelTick'and(not activeChannel or e.channelId~=activeChannel.id or time>activeChannel.ends+1e-9)then return end
   if e.kind=='tick'or e.kind=='channelTick'then
   if e.kind=='tick'and(not auras[e.key]or auras[e.key].version~=e.version)then return end local a=spec.abilities[e.key];if a.beforeTickDebuff then local d=copy(a.beforeTickDebuff);d.expires=time+d.duration;debuffs[d.key]=d end;if e.kind=='channelTick'and a.selfTickDamage and health<=a.selfTickDamage then return end;if a.manaTick then local before=mana;mana=math.min(spec.initial.mana,mana+a.manaTick*(a.resourceMult or 1));record('resource',e.key,mana-before);return end;local amount=(a.tickBase*(e.periodicBaseMultiplier or 1)+(a.tickCoef or 0)*a.sp+(a.tickAPCoef or 0)*(a.ap or 0)+(a.comboTickDamage or 0)*(e.comboPoints or 0)+(a.comboTickAPCoef or 0)*math.min(e.comboPoints or 0,a.comboTickAPCap or 5)*(a.ap or 0))*(a.periodicMult or a.mult)*(a.ramp and a.ramp[e.index]or 1)
   if a.tickRolls then if R.hit()>=a.hit then row(e.key).misses=row(e.key).misses+1;record('miss',e.key)return end if a.tickMax and a.tickMax~=a.tickBase then amount=amount+(a.tickMax-a.tickBase)*R.damage()*(a.periodicMult or a.mult)end end local critical=false;if a.periodicCrit or a.tickRolls then local roll=R.crit();record('critRoll',e.key,roll);local bonus=targetModifiers(e.key,a);critical=roll<math.min(1,a.crit+bonus+(e.bonusCrit or 0)+(e.frozen and(a.frozenCrit or 0)or 0))end local _,mult=targetModifiers(e.key,a);local livePeriodic=1
    for _,pr in ipairs(spec.procs or {})do
     if pr.livePeriodic and pr.buff and pr.damageMultiplierPerStack then
      local live=buffs[pr.buff]
      if live and live.charges>0 and live.expires>time and
       has(pr.damageOn or pr.consumeOn,e.key) and schoolMatches(pr.damageSchools,a) and
       not has(a.periodicExcludedBuffs or {},pr.buff) then
       livePeriodic=livePeriodic*(1+pr.damageMultiplierPerStack*live.stacks)
      end
     end
    end
    local dealt=amount*mult*livePeriodic*(e.periodicDamageMultiplier or e.damageMultiplier or 1)*mitigation(a,e.key)*(critical and a.critMult or 1);damage(e.key,dealt,true,critical,a.tickAsDirect);
    -- Optional priority-channel clipping: reconsider higher-priority maintenance at each completed tick.
    -- This is only active for opt-in rotations, and never clips before the channel GCD finishes.
    if e.kind=='channelTick' and activeChannel and spec.channelClip and activeChannel.policyIndex and time>=activeChannel.started+math.max(1,1.5/spec.haste)-1e-9 then
     for pi=1,activeChannel.policyIndex-1 do
      local policy=spec.policies[pi];local check=spec.abilities[policy.key]
      if check and mana>=check.cost and (cds[check.cooldownGroup or policy.key]or 0)<=time then
       local due=false
       if policy.maintain then
        local expires=auras[policy.key] and auras[policy.key].expires or 0
        due=expires<=time+math.max(0,check.cast/spec.haste)+1e-9
        if check.exclusiveGroup then for ak,b in pairs(auras)do if b.expires>time and spec.abilities[ak].exclusiveGroup==check.exclusiveGroup then due=false end end end
       elseif policy.maintainDebuff then
        local d=debuffs[policy.maintainDebuff];due=not d or d.expires<=time+math.max(0,check.cast/spec.haste)+1e-9
       end
       if due then activeChannel.ends=time;record('clip',activeChannel.key,0,{forSpell=policy.key});break end
      end
     end
    end
    if a.selfTickDamage and a.selfTickDamage>0 then health=health-a.selfTickDamage;record('selfDamage',e.key,a.selfTickDamage);if activeChannel and health<=a.selfTickDamage then activeChannel.ends=time;record('clip',e.key,0,{reason='health'})end end;if a.leechFraction then local before=health;health=math.min(spec.initial.health,health+dealt*a.leechFraction);record('heal',e.key,health-before)end
  elseif e.kind=='complete'then
   local a=spec.abilities[e.key];if a.resetCooldownKeys then for _,key in ipairs(a.resetCooldownKeys)do cds[key]=time end end;if a.resetClassCooldowns then for key in pairs(spec.abilities)do if key~=e.key then cds[key]=time end end end;if a.completeResource then gainResource(a.completeResource.resource,a.completeResource.amount or 0,e.key);record('resource',e.key,a.completeResource.amount)end;if a.consumeBuff and buffs[a.consumeBuff]then buffs[a.consumeBuff].charges=0 end;if a.kind=='judgement'then for _,bf in pairs(buffs)do if bf.group=='seal'and bf.expires>time then local seal=spec.abilities[bf.source];if seal and seal.judgement then local j=copy(a);for k,v in pairs(seal.judgement)do j[k]=v end;j.kind='direct';j.sp=seal.sp;j.attackTable=copy(seal.attackTable or P.physicalTable(0,0,a.crit));j.attackTable.dodge=0;j.attackTable.parry=0;j.attackTable.block=0;row(e.key).casts=row(e.key).casts+1;direct(j,e.key,e);if spec.sealRefund and R.proc()<spec.sealRefund.chance then local gain=seal.cost*spec.sealRefund.refund;gainResource('mana',gain,'sanctifiedJudgement');record('resource','sanctifiedJudgement',gain)end;proc('cast',e.key,0);bf.expires=time;break end end end;return end;row(e.key).casts=row(e.key).casts+1;record('complete',e.key);if a.resetCooldownSchools then for k,b in pairs(spec.abilities)do if k~=e.key and schoolMatches(a.resetCooldownSchools,b)then cds[b.cooldownGroup or k]=time end end end
   if a.grantsBuff then local b=copy(a.grantsBuff);b.duration=(a.duration or b.duration)+(a.durationPerCombo or 0)*(e.comboPoints or 0);b.expires=time+b.duration;b.source=e.key;b.stacks=1;b.paidCost=e.paidCost;for key,old in pairs(buffs)do if b.group and old.group==b.group then buffs[key]=nil end end;buffs[b.key]=b;record('buff',b.key,b.charges);if b.attackHaste or b.rangedHaste then syncSwingHaste();schedule(b.expires,0,'refreshAttackHaste',b.key)end end
   if a.kind=='resource'then health=health-a.healthCost local before=mana;local gain=a.manaGain+(a.manaMax and R.damage()*(a.maxManaGain-a.manaGain)or 0);mana=math.min(spec.initial.mana,mana+gain);local gained=mana-before;record('resource',e.key,gained);for _,actor in ipairs(actorStates)do for _,rule in ipairs(actor.resourceTransfers or {})do if rule.ability==e.key then actor.remainingMana=math.min(actor.mana,actor.remainingMana+actor.manaRegen*(time-actor.lastRegen));actor.lastRegen=time;local previous=actor.remainingMana;actor.remainingMana=math.min(actor.mana,actor.remainingMana+gained*rule.fraction);record('actorResource',actor.key,actor.remainingMana-previous)end end end;return end
   local replaced=false;for _,bf in pairs(buffs)do if bf.triggerSpell==e.key and bf.charges>0 and bf.expires>time then bf.charges=0;local child=spec.abilities[bf.strikeKey];row(child.key).casts=row(child.key).casts+1;direct(child,child.key,e);local gain=(bf.paidCost or 0)*(bf.refundShare or 0);gainResource('mana',gain,bf.source);record('resource',bf.source,gain);if bf.resetTriggerCooldown then cds[e.key]=time end;replaced=true;break end end
   local landed=replaced or a.kind=='actor'or a.kind=='buff'or direct(a,e.key,e);if a.applyRegardlessOfHit then landed=true end;if a.kind=='buff'and a.spendCombo then combo=0;record('combo',e.key,-(e.comboPoints or 0))end
   if a.resetCooldownIfBuff and buffs[a.resetCooldownIfBuff]and buffs[a.resetCooldownIfBuff].expires>time then cds[e.key]=time end
   if landed and a.grantsDebuff then local d=copy(a.grantsDebuff);d.expires=time+d.duration;if d.armorPerCombo then d.armorReduction=d.armorPerCombo*(e.comboPoints or 0)end;debuffs[d.key]=d;record('debuff',d.key,d.charges)end
   if landed then for _,child in ipairs(a.secondaryWeapons or {})do direct(child,child.key or(e.key..':offhand'),e)end end
   if landed and a.refundShardChance then local roll=R.proc();record('procRoll','shardRefund',roll);if roll<a.refundShardChance then shards=shards+1;record('shards',e.key,1)end end
   if landed and a.consumeAura and auras[a.consumeAura]and(not a.preserveAuraChance or R.proc()>=a.preserveAuraChance)then auras[a.consumeAura].expires=time;auras[a.consumeAura].version=auras[a.consumeAura].version+1;record('expire',a.consumeAura)end
   if landed and a.duration then if a.exclusiveGroup then for key,b in pairs(auras)do if key~=e.key and spec.abilities[key].exclusiveGroup==a.exclusiveGroup then b.expires=time;b.version=b.version+1;record('expire',key)end end end;local v=(auras[e.key]and auras[e.key].version or 0)+1;local auraDuration=a.duration+(a.durationPerCombo or 0)*(e.comboPoints or 0);auras[e.key]={expires=time+auraDuration,version=v}if a.tickEvery then for i=1,math.floor(auraDuration/a.tickEvery)do schedule(time+i*a.tickEvery,0,'tick',e.key,{version=v,index=i,comboPoints=e.comboPoints,damageMultiplier=e.damageMultiplier,periodicDamageMultiplier=e.periodicDamageMultiplier,periodicBaseMultiplier=e.periodicBaseMultiplier,frozen=e.frozen})end end end proc('cast',e.key,0)
  end
 end
 local function advance(to)if ended()then return end;while #q>0 do table.sort(q,less)if q[1].t>to+1e-9 then break end process(table.remove(q,1));if spec.targetHP and total>=spec.targetHP then killTime=time end;if ended()then return end end setTime(to)end
 if spec.encounter and(spec.encounter.hitEvery or 0)>0 then schedule(R.push()*spec.encounter.hitEvery,1,'incomingHit','target')end
 for i,x in ipairs(spec.periodicResources or {})do schedule(x.every,0,'periodicResource',x.key,{rule=i})end
 for i,a in ipairs(actorStates)do if a.generic then schedule(0,2,'actorAct','pet',{actor=i})end;if a.spell then schedule(0,2,'actorAct',a.spell.key,{actor=i})end;if a.melee then schedule(0,0,'actorSwing','pet:melee',{actor=i});a.nextSwing=q[#q]end end

 for i,rule in ipairs(spec.periodicCurrency or {})do schedule(rule.every,0,'periodicCurrency',rule.key,{rule=i})end
 for _,a in ipairs(spec.autoAttacks or {})do swingStates[a.hand]={speed=a.speed};schedule(0,0,'ownerSwing',a.key,{hand=a.hand});swingStates[a.hand].event=q[#q]end

 -- Refresh at landing time: do not discard the final periodic tick just to
 -- start a cast early. This is an explicit optimizer policy, preserving starts.
 local function refreshLead(a,policy)
  if not policy.refreshAtCastTime then return policy.refreshLead or 0 end
  local cast=a.cast or 0
  for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time and bf.castHaste and not a.ignoreHaste then cast=cast/(1+bf.castHaste)end end
  for _,pr in ipairs(spec.procs or {})do local b=pr.buff and buffs[pr.buff]
   if b and b.charges>0 and b.expires>time and has(pr.consumeOn,policy.key)then
    if pr.castOverride~=nil then cast=pr.castOverride end
    if pr.castFlat then cast=math.max(0,cast+pr.castFlat)end
    if pr.castMultiplierPerStack then cast=cast*math.max(0,1+pr.castMultiplierPerStack*b.stacks)end
   end
  end
  return math.max(policy.refreshLead or 0,cast/(a.ignoreHaste and 1 or spec.haste))
 end
 while time<duration-1e-9 and not ended() do steps=steps+1 if steps>20000 then error('Combat step limit')end
  local key,keyPolicy=nil,nil;local remaining=duration-time
  for _,k in ipairs(spec.autoResources or {})do local a=spec.abilities[k];if(not rows[k]or rows[k].casts<(a.maxUses or math.huge))and(cds[a.cooldownGroup or k]or 0)<=time and spec.initial.mana-mana>=(a.maxManaGain or a.manaGain)then key=k;break end end
  for _,p in ipairs(spec.procs or {})do local b=p.buff and buffs[p.buff]if not key and p.autoPriority~=false and b and b.charges>0 and b.expires>time and(p.castOverride==0 or(p.priorityAtStacks and b.stacks>=p.priorityAtStacks))and spec.abilities[(p.consumeOn or {})[1]]then key=p.consumeOn[1];break end end
  if not key then for pi,p in ipairs(spec.policies)do local a=spec.abilities[p.key];local slotActive=false;for k,b in pairs(auras)do if k~=p.key and a.exclusiveGroup and spec.abilities[k].exclusiveGroup==a.exclusiveGroup and b.expires>time+1e-9 then slotActive=true end end;local maintainedBuff=p.maintainBuff and buffs[p.maintainBuff];local maintain=not(maintainedBuff and maintainedBuff.charges>0 and maintainedBuff.expires>time+(p.refreshWindow or 0));local requiredGroup=not a.requiresAuraGroup;for k,b in pairs(auras)do if b.expires>time+1e-9 and spec.abilities[k].exclusiveGroup==a.requiresAuraGroup then requiredGroup=true end end;local stacks=p.buffStacks and buffs[p.buffStacks.key];local belowStacks=not p.buffStacks or((stacks and stacks.expires>time and stacks.stacks or 0)<(p.buffStacks.below or 1));if p.maintainDebuff then local rule=a.grantsDebuff and a.grantsDebuff.key==p.maintainDebuff and{maxStacks=1}or nil;for _,v in ipairs(spec.procs)do if v.debuff==p.maintainDebuff then rule=v end end;local b=debuffs[p.maintainDebuff];maintain=maintain and rule~=nil and not(b and b.stacks>=rule.maxStacks and b.expires>time+(p.refreshWindow or 0))end;local cooldownActive=not p.cooldownsActiveOn;for _,k in ipairs(p.cooldownsActiveOn or {})do if(cds[k]or 0)>time then cooldownActive=true end end;local requiredGroupBuff=not(p.requiresBuffGroup or a.requiresBuffGroup);for _,bf in pairs(buffs)do if bf.group==(p.requiresBuffGroup or a.requiresBuffGroup)and bf.expires>time and bf.charges>0 then requiredGroupBuff=true end end;local stealthActive=buffs.stealth and buffs.stealth.expires>time and buffs.stealth.charges>0;local permittedStealth=not a.requiresStealth and not a.requiresStealthOrBuff or stealthActive or a.requiresStealthOrBuff and buffs[a.requiresStealthOrBuff]and buffs[a.requiresStealthOrBuff].expires>time and buffs[a.requiresStealthOrBuff].charges>0;local requiredBuff=not p.requiresBuff or(buffs[p.requiresBuff]and buffs[p.requiresBuff].charges>0 and buffs[p.requiresBuff].expires>time);local shardFree=false;for _,v in ipairs(spec.procs or {})do local b=v.buff and buffs[v.buff];if b and b.charges>0 and b.expires>time and v.shardCostOverride==0 and has(v.consumeOn,p.key)then shardFree=true end end;if (not spec.typedCombat or available(a)>=adjustedCost(a,p.key))and permittedStealth and requiredGroupBuff and(not a.requiresCooldownActive or(cds[a.requiresCooldownActive]or 0)>time)and(not a.requiresCooldownKeys or(function()for _,key in ipairs(a.requiresCooldownKeys)do if(cds[key]or 0)>time then return true end end return false end)())and(not a.maxResourceFraction or energy<=(spec.resources.maxEnergy*a.maxResourceFraction))and(not a.requiresMeleeRange or spec.encounter.inMeleeRange==true)and(not a.requiresPet or #actorStates>0)and(not a.nextSwing or not queuedSwing)and combo>=math.max(a.minCombo or 0,p.minCombo or 0)and(not p.maxCombo or combo<p.maxCombo)and(not p.minResource or available(a)>=p.minResource)and(not p.minBuffStacks or p.requiresBuff and buffs[p.requiresBuff]and buffs[p.requiresBuff].stacks>=p.minBuffStacks)and(not a.maxTargetHealth or targetHealth(time)<=a.maxTargetHealth)and(not a.mobTypes or has(a.mobTypes,(spec.encounter or {}).mobType))and (not(p.maxUses or a.maxUses)or not rows[p.key]or rows[p.key].casts<(p.maxUses or a.maxUses))and(not a.selfTickDamage or health>a.selfTickDamage)and maintain and cooldownActive and requiredBuff and(shardFree or shards>=(a.shardCost or 0))and requiredGroup and belowStacks and(not p.manaBelow or mana<=spec.initial.mana*p.manaBelow)and (cds[a.cooldownGroup or p.key]or 0)<=time+1e-9 and(not a.requiresAura or(auras[a.requiresAura]and auras[a.requiresAura].expires or 0)>time+1e-9)and(not p.minRemaining or remaining>=p.minRemaining)and(not p.maxRemaining or remaining<=p.maxRemaining)and(not p.openerOnly or time<3)and(not p.maintain or not slotActive and(auras[p.key]and auras[p.key].expires or 0)<=time+refreshLead(a,p)+1e-9)and(not p.reserve or mana>=a.cost+p.reserve*spec.initial.mana)then key=p.key;keyPolicy=pi;break end end end
  local tap=spec.tapKey and spec.abilities[spec.tapKey]
  if tap and health>tap.healthCost+20 and mana<spec.initial.mana-tap.manaGain*.65 and((mana<spec.initial.mana*spec.tapAtPct and remaining>8)or(key and mana<spec.abilities[key].cost))then key=spec.tapKey end
  if not key then local wait=spec.typedCombat and .1 or .5;if not spec.typedCombat or spec.resource=='mana'then oom=oom+math.min(wait,remaining)end;advance(math.min(duration,time+wait))
  else channelLanded=nil;local a=spec.abilities[key];local shardCost=a.shardCost or 0;local cost,cast=a.cost,a.kind=='channel'and a.duration or a.cast;if a.ignoreHaste or a.ignoreChannelHaste and a.kind=='channel'then cast=cast*spec.haste end;local consumed={};local damageMultiplier,periodicDamageMultiplier,periodicBaseMultiplier,frozen=1,1,1,false;local directAdd,periodicAdd,bonusCrit=0,0,0;local dynamicGCD=a.gcd or 1.5;for _,bf in pairs(buffs)do if bf.charges>0 and bf.expires>time then if bf.castHaste and not a.ignoreHaste then cast=cast/(1+bf.castHaste)end;if bf.gcdFactor and has(bf.gcdSpells,key)then dynamicGCD=dynamicGCD*bf.gcdFactor end end end
   for _,p in ipairs(spec.procs or {})do local b=p.buff and buffs[p.buff]if b and b.charges>0 and b.expires>time then if has(p.costOn or p.consumeOn,key)and p.costMultiplierPerStack then cost=cost*(1+p.costMultiplierPerStack*b.stacks)end;if has(p.damageOn or p.consumeOn,key)and schoolMatches(p.damageSchools,a)and p.damageMultiplierPerStack then damageMultiplier=damageMultiplier*(1+p.damageMultiplierPerStack*b.stacks);if not p.livePeriodic and not has(a.periodicExcludedBuffs or {},p.buff)then periodicDamageMultiplier=periodicDamageMultiplier*(1+p.damageMultiplierPerStack*b.stacks)end end;if has(p.damageOn or p.consumeOn,key)and schoolMatches(p.damageSchools,a)and p.damageAdditivePerStack then directAdd=directAdd+p.damageAdditivePerStack*b.stacks;if not has(a.periodicExcludedBuffs or {},p.buff)then periodicAdd=periodicAdd+p.damageAdditivePerStack*b.stacks end end;if has(p.consumeOn,key)and p.costFlatPerStack then cost=cost+p.costFlatPerStack*b.stacks end;if p.snapshotCrit and p.buffCritPerStack and has(p.consumeOn,key)and not has(p.critExcluded or {},key)then bonusCrit=bonusCrit+p.buffCritPerStack*b.stacks end;if has(p.consumeOn,key)then if p.periodicBaseMultiplierPerStack then periodicBaseMultiplier=periodicBaseMultiplier*(1+p.periodicBaseMultiplierPerStack*b.stacks)end;if p.shardCostOverride~=nil then shardCost=p.shardCostOverride end;if p.costOverride~=nil then cost=p.costOverride end if p.castOverride~=nil then cast=p.castOverride end;if p.castFlat then cast=math.max(0,cast+p.castFlat)end;if p.castMultiplierPerStack then cast=cast*math.max(0,1+p.castMultiplierPerStack*b.stacks)end if p.frozen then frozen=true end;if p.consumeCharges~=false then consumed[#consumed+1]=p.buff end end end end
   cost=math.max(0,cost);damageMultiplier=damageMultiplier*(1+directAdd/(1+a.directBonus));periodicDamageMultiplier=periodicDamageMultiplier*(1+periodicAdd/(1+a.periodicBonus));if available(a)<cost or shards<shardCost then oom=oom+math.min(.5,remaining);advance(math.min(duration,time+.5))
   elseif a.kind=='wait'then advance(math.min(duration,time+.1))
   elseif a.nextSwing then queuedSwing=key;record('queue',key);advance(math.min(duration,time+.1))
   else local castEnd,gcdEnd=time+cast/spec.haste,time+math.max(a.gcd==0 and 0 or 1,dynamicGCD/(a.ignoreHaste and 1 or spec.haste))
    -- A cast may start before the boss dies even if it cannot finish; its cost is still paid.
    if a.breakStealth and buffs.stealth then buffs.stealth.charges=0 end
    if a.pausesMelee and cast>0 then for hand,state in pairs(swingStates)do if hand~='ranged'then state.resetAfter=castEnd;if state.event and state.event.t>time+1e-9 then state.event.t=castEnd+state.speed/attackHaste(hand)end end end end
    local comboPoints=combo;spendResource(a,cost);local extraResource=0;if a.consumeExtraResource then extraResource=available(a);spendResource(a,extraResource)end;shards=shards-shardCost;if shardCost>0 then record('shards',key,-shardCost)end;if cost>0 then lastSpend=a.kind=='channel'and time or castEnd end for _,b in ipairs(consumed)do buffs[b].charges=buffs[b].charges-1;for _,pr in ipairs(spec.procs or {})do if pr.buff==b and pr.consumeAllStacks then buffs[b].charges=0;buffs[b].stacks=0 end;if pr.buff==b and pr.consumeStacks then buffs[b].stacks=math.max(0,buffs[b].stacks-1)end;if pr.buff==b and pr.cooldownOnConsume then cds[b]=castEnd+pr.cooldownOnConsume end end;record('consume',b)end
    record('start',key,cost);actions[#actions+1]=key;cds[a.cooldownGroup or key]=(a.kind=='channel'and time or castEnd)+(a.cooldown or 0);if a.kind=='channel'then
     channelSequence=channelSequence+1;activeChannel={key=key,ends=castEnd,started=time,full=cast/spec.haste,id=channelSequence,policyIndex=keyPolicy}
     schedule(time,1,'channelStart',key,{castDuration=cast,damageMultiplier=damageMultiplier,periodicDamageMultiplier=periodicDamageMultiplier,periodicBaseMultiplier=periodicBaseMultiplier,frozen=frozen,bonusCrit=bonusCrit});advance(time)
     if not channelLanded then activeChannel.ends=time end
     while time<math.min(duration,math.max(activeChannel.ends,gcdEnd))-1e-9 and not ended() do table.sort(q,less);advance(math.min(duration,math.max(activeChannel.ends,gcdEnd),q[1]and q[1].t or duration))end
     activeChannel=nil;channelLanded=nil
    else
     local ev={bonusCrit=bonusCrit,paidCost=cost,comboPoints=comboPoints,extraResource=extraResource,damageMultiplier=damageMultiplier,periodicDamageMultiplier=periodicDamageMultiplier,periodicBaseMultiplier=periodicBaseMultiplier,frozen=frozen}
     schedule(castEnd,1,'complete',key,ev);local completion=castEnd<=duration+1e-9 and q[#q]or{t=castEnd};activeCast=cast>0 and{key=key,ends=castEnd,full=cast/spec.haste,event=completion,hits=0}or nil
     advance(math.min(duration,math.max(castEnd,gcdEnd)))
     while activeCast and time<math.min(duration,activeCast.ends)-1e-9 and not ended() do advance(math.min(duration,activeCast.ends))end
     activeCast=nil
    end
   end
  end
  -- Yield within a fight so a long event timeline never monopolizes a frame.
  if P.checkpoint then P.checkpoint()end
 end
 if not ended()then advance(duration)end;local first={}for i=1,math.min(20,#actions)do first[i]=actions[i]end
 return {dps=total/(killTime and math.max(.001,killTime)or duration),total=total,damage=total,killTime=killTime,deathTime=deathTime,killed=killTime~=nil,manaEnd=mana,energyEnd=energy,rageEnd=rage,comboEnd=combo,shardsEnd=shards,healthEnd=health,oomTime=oom,bySpell=rows,actions=first,events=log,duration=duration,steps=steps,rotationRules=spec.rotationRules}
end
function P.candidates(data,p)
 local search=data.search
 local function learned(k)return #P.ranks(data,p,k)>0 end
 local primary=(search.filler.values or {})[p[search.filler.field or '']]or search.filler.default
 local out={};local fillers={primary};for _,v in ipairs(search.filler.alternatives or {})do if not has(fillers,v)then fillers[#fillers+1]=v end end
 for _,filler in ipairs(fillers)do local ranks=P.ranks(data,p,filler)if #ranks>0 then
 if not search.allFillerRanks then ranks={ranks[#ranks]}end
 local optional={}for _,v in ipairs(search.optionalAbilities or {})do if learned(v.key)then optional[#optional+1]=v end end
 local function permutations(prefix,left,orders)if #left==0 then orders[#orders+1]=prefix;return end for i,k in ipairs(left)do local a,b=copy(prefix),copy(left);a[#a+1]=k;table.remove(b,i);permutations(a,b,orders)end end
 for mask=0,2^#optional-1 do
  local subset={}for i,k in ipairs(optional)do if math.floor(mask/2^(i-1))%2==1 then subset[#subset+1]=k end end
  local orders={}if search.permute then permutations({},subset,orders)else orders={subset}end
  for _,order in ipairs(orders)do for _,minimum in ipairs(search.minRemainingValues or {false})do
   for _,variant in ipairs(search.policyVariants or {{}})do for _,r in ipairs(ranks)do for _,threshold in ipairs(search.tapThresholds or {0})do
    local policies={}for _,x in ipairs(variant)do if learned(x.key)then policies[#policies+1]=copy(x)end end
    for _,x in ipairs(order)do local v=copy(x);v.maintain=true;if minimum then v.minRemaining=minimum end policies[#policies+1]=v end
    policies[#policies+1]={key=filler};local groups,legal={},true;for _,x in ipairs(policies)do local group=data.abilities[x.key][1].exclusiveGroup;if group and x.maintain then if groups[group]then legal=false end;groups[group]=true end end;local choice={policies=policies}if search.allFillerRanks then choice.ranks={[filler]=r.rank}end if search.tapThresholds then choice.tapAtPct=threshold end if legal then out[#out+1]=choice end
   end end end
  end end
 end
 end end
 local seen,unique={},{}for _,v in ipairs(out)do local k=P.canonical(v)if not seen[k]then unique[#unique+1]=v;seen[k]=true end end local limit=search.candidateLimit;if not limit or #unique<=limit then return unique end;local bounded={};for i=0,limit-1 do bounded[#bounded+1]=unique[math.floor(i*(#unique-1)/(limit-1))+1]end;return bounded
end
function P.canonical(v)
 if type(v)=='table'then local parts={}for _,k in ipairs(sortedKeys(v))do parts[#parts+1]=tostring(k)..'='..P.canonical(v[k])end return '{'..table.concat(parts,';')..'}'end return type(v)..':'..tostring(v)
end

