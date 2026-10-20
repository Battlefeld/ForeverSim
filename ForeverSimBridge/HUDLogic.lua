-- Combat HUD, part 1: what to press now and next. Read-only: this file never casts, never touches secure frames and
-- never calls the optimizer. The order of spells comes from the rotation ForeverCore worked out for the build the
-- character plays (ForeverCoreClient.Sim.Rotation().priority); below level 50 (no simulation yet) a short list per class
-- is used. HUDView.lua draws the queue; the numbers here are only cooldowns, auras and the glow events of the game.
ForeverSimHUD=ForeverSimHUD or{}
local HUD=ForeverSimHUD
local P=FUSLive or{}
local function now()return GetTime and GetTime()or 0 end
local function protected(v)if P.isProtected then return P.isProtected(v)end;return false end
local function num(v)if P.publicNumber then return P.publicNumber(v)end;return type(v)=='number'and v or nil end
local function str(v)if P.publicString then return P.publicString(v)end;return type(v)=='string'and v or nil end
local function bool(v)if protected(v)or type(v)~='boolean'then return nil end;return v end
-- {a,b} with a missing first function would end ipairs early; this walks every argument
local function each(...)
 local list,n={...},select('#',...)
 local i=0
 return function()
  while i<n do i=i+1;if list[i]~=nil then return i,list[i]end end
 end
end

-- Settings (saved in ForeverSimBridgeDB.hud) ---------------------------------------------------------------------
local DEFAULTS={enabled=true,locked=true,scale=1,alpha=1,queue=4,showKeys=true,showNames=true,procs=true,showDelay=true,fightCheck=true,barHighlight=true,procSound=false,procColor={1,.82,.2}}
function HUD.Config()
 ForeverSimBridgeDB=ForeverSimBridgeDB or{}
 local db=ForeverSimBridgeDB;if type(db.hud)~='table'then db.hud={}end
 local c=db.hud
 for k,v in pairs(DEFAULTS)do if c[k]==nil then c[k]=type(v)=='table'and{v[1],v[2],v[3]}or v end end
 c.queue=math.max(1,math.min(5,math.floor(tonumber(c.queue)or 4)))
 return c
end

local function inCombat()
 if InCombatLockdown and bool(InCombatLockdown())then return true end
 return UnitAffectingCombat and bool(UnitAffectingCombat('player'))==true or false
end
HUD.InCombat=inCombat
local function haveTarget()
 local present=UnitExists and bool(UnitExists('target'))
 if not present then return false end
 if not UnitCanAttack then return true end
 return bool(UnitCanAttack('player','target'))==true
end

-- Game reads ---------------------------------------------------------------------------------------------------------
local function power(unit)
 local n=UnitPower and num(UnitPower(unit,0));local max=UnitPowerMax and num(UnitPowerMax(unit,0))
 return n or 0,max or 0,n~=nil and max~=nil
end
-- remaining seconds, can use now, only the global cooldown. math.huge when the game does not tell.
local function cooldown(id)
 if C_Spell and C_Spell.GetSpellCooldown then
  local ok,info=pcall(C_Spell.GetSpellCooldown,id)
  if ok then
   if protected(info)then return math.huge,false,false end
   if type(info)=='table'then
    local st,du=num(info.startTime),num(info.duration)
    if not st or not du or protected(info.isEnabled)then return math.huge,false,false end
    return math.max(0,st+du-now()),info.isEnabled~=false,du<=1.6,du
   end
  end
 end
 if GetSpellCooldown then
  local ok,a,b,enabled=pcall(GetSpellCooldown,id)
  if ok then
   a,b=num(a),num(b)
   if a and b and not protected(enabled)then return math.max(0,a+b-now()),enabled~=0,b<=1.6,b end
  end
  return math.huge,false,false
 end
 return 0,true,true,0
end
HUD.Cooldown=cooldown
local function usable(id)
 local f=(C_Spell and C_Spell.IsSpellUsable)or IsUsableSpell
 if not f then return true end
 local ok,u,noMana=pcall(f,id)
 if not ok or protected(u)or protected(noMana)then return false end
 return u==true
end
local function spellName(id)
 if P.spellDisplay then local n=P.spellDisplay(id);return n end
end
local function spellIcon(id)
 if P.spellDisplay then local _,i=P.spellDisplay(id);return i end
end
local function castSeconds(id)
 if C_Spell and C_Spell.GetSpellInfo then
  local ok,info=pcall(C_Spell.GetSpellInfo,id)
  if ok and type(info)=='table'then local ms=num(info.castTime);if ms then return ms/1000 end end
 elseif GetSpellInfo then
  local ok,_,_,_,cast=pcall(GetSpellInfo,id);if ok and num(cast)then return cast/1000 end
 end
 return 0
end
-- the cooldown a spell has of its own (seconds), 0 when it only has the global one
local function baseCooldown(id)
 for _,f in each(C_Spell and C_Spell.GetSpellBaseCooldown,GetSpellBaseCooldown)do
  local ok,ms=pcall(f,id);ms=ok and num(ms)or nil;if ms then return ms/1000 end
 end
 local _,_,_,du=cooldown(id)
 return num(du)and du or 0
end
-- the spell being cast or channelled right now and the seconds that are left of it
local function castingNow()
 if UnitCastingInfo then
  local ok,name,_,_,_,endMs,_,_,_,spellId=pcall(UnitCastingInfo,'player')
  if ok and str(name)and num(endMs)and num(spellId)then return spellId,math.max(0,endMs/1000-now())end
 end
 if UnitChannelInfo then
  local ok,name,_,_,_,endMs,_,_,spellId=pcall(UnitChannelInfo,'player')
  if ok and str(name)and num(endMs)and num(spellId)then return spellId,math.max(0,endMs/1000-now())end
 end
end
HUD.CastSeconds=castSeconds
local function known(id)
 for _,f in each(C_SpellBook and C_SpellBook.IsSpellKnown,IsPlayerSpell,IsSpellKnown)do
  local ok,v=pcall(f,id)
  if ok and not protected(v)and v~=nil then return v==true end
 end
 return true
end
-- remaining seconds of an aura of ours (target debuffs only when they are ours); 3600 when it is there but its end is
-- hidden (so a hidden DoT is never "refreshed blindly"), 0 when it is not there.
local function auraRemaining(unit,id,name,harmful)
 local present=UnitExists and bool(UnitExists(unit))
 if not present then return 0 end
 local t=now()
 for i=1,40 do
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
   local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,i,harmful and'HARMFUL'or'HELPFUL')
   if not ok then return 0 end
   if protected(aura)then return 3600,true end
   if not aura then break end
   local spell,auraName,source=num(aura.spellId),str(aura.name),str(aura.sourceUnit)
   if((id and spell and spell==id)or(name and auraName and auraName==name))and(not harmful or source=='player'or source=='pet')then
    local expires=num(aura.expirationTime)
    if not expires then return 3600,true end
    return expires>0 and math.max(0,expires-t)or 3600,true
   end
  else
   local f=harmful and UnitDebuff or UnitBuff;if not f then break end
   local ok,n,_,_,_,_,expires,source,_,_,spellId=pcall(f,unit,i)
   if not ok then break end
   if protected(n)or protected(source)or protected(spellId)then return 3600,true end
   if not n then break end
   if((id and spellId==id)or(name and n==name))and(not harmful or source=='player'or source=='pet')then
    expires=num(expires);if not expires then return 3600,true end
    return expires>0 and math.max(0,expires-t)or 3600,true
   end
  end
 end
 return 0,false
end

-- The rotation's conditions (the engine's own APL) ---------------------------------------------------------------------
-- E = {vt=seconds into the future, ready={[id]=virtual time the cooldown ends}, dot={[id]=virtual time the effect ends}}
local function aplID(node)
 if type(node)~='table'then return num(node)end
 local id=node.spellId;if type(id)=='table'then return num(id.spellId)end;return num(id)
end
local function remainingOf(unit,id,harmful,E)
 if harmful and E.dot[id]then return math.max(0,E.dot[id]-E.vt)end
 local r=auraRemaining(unit,id,spellName(id),harmful)
 return r>=3599 and r or math.max(0,r-E.vt)
end
local function aplValue(node,E)
 if type(node)~='table'then return nil end
 if node.const then
  local v=node.const.val
  if type(v)=='number'then return v end
  if type(v)=='string'then return tonumber(v:match('([%d%.]+)'))end
  return nil
 end
 if node.currentManaPercent then local v,m,ok=power('player');return ok and m>0 and v*100/m or nil end
 if node.spellTimeToReady then
  local id=aplID(node.spellTimeToReady);if not id then return nil end
  if E.ready[id]then return math.max(0,E.ready[id]-E.vt)end
  local s,enabled=cooldown(id);if not enabled then return nil end
  return math.max(0,s-E.vt)
 end
 if node.dotRemainingTime then
  local id=aplID(node.dotRemainingTime);if not id then return nil end
  return remainingOf('target',id,true,E)
 end
 if node.auraIsActive then
  local a=node.auraIsActive;local id=aplID(a.auraId);if not id then return nil end
  local onTarget=type(a.sourceUnit)=='table'and a.sourceUnit.type=='CurrentTarget'
  return remainingOf(onTarget and'target'or'player',id,onTarget,E)>0
 end
 if node.numberTargets then return haveTarget()and 1 or 0 end
 if node.spellCastTime then local id=aplID(node.spellCastTime);return id and castSeconds(id)or nil end
 return nil
end
local function aplCondition(node,E)
 if type(node)~='table'then return nil end
 if node['and']then
  local values=node['and'].vals or{}
  for _,x in ipairs(values)do if aplCondition(x,E)~=true then return false end end
  return #values>0
 end
 if node['or']then
  for _,x in ipairs(node['or'].vals or{})do if aplCondition(x,E)==true then return true end end
  return false
 end
 if node['not']then local v=aplCondition(node['not'].val,E);if v==nil then return nil end;return not v end
 if node.cmp then
  local x,y=aplValue(node.cmp.lhs,E),aplValue(node.cmp.rhs,E)
  if type(x)~='number'or type(y)~='number'then return nil end
  local op=node.cmp.op
  if op=='OpLt'then return x<y elseif op=='OpLe'then return x<=y elseif op=='OpGt'then return x>y
  elseif op=='OpGe'then return x>=y elseif op=='OpEq'then return x==y elseif op=='OpNe'then return x~=y end
  return nil
 end
 if node.auraIsActive then return aplValue(node,E)end
 return nil
end
HUD.Condition=function(node,E)return aplCondition(node,E or{vt=0,ready={},dot={}})end
-- the seconds an effect cast with this row lasts, when its own condition watches it (a DoT or buff to keep up)
local function watchedDuration(row)
 local found
 local function walk(n)
  if type(n)~='table'or found then return end
  local w=n.dotRemainingTime or(n.auraIsActive and n.auraIsActive.auraId)
  if w and aplID(w)==row.spellId then found=true;return end
  for _,v in pairs(n)do if type(v)=='table'then walk(v)end end
 end
 walk(row.condition)
 return found and 12 or nil
end

-- Spells for the levels without a simulated rotation ----------------------------------------------------------------------
-- keys of the class files (Classes/*.lua); dot=true: not offered again while the effect is on the target
local BASIC={
 warrior={{'bloodthirst'},{'mortalStrike'},{'whirlwind'},{'overpower'},{'execute'},{'slam'},{'heroicStrike'}},
 paladin={{'judgement'},{'holyStrike'},{'consecration'},{'exorcism'},{'hammerOfWrath'}},
 hunter={{'serpentSting',dot=true},{'aimedShot'},{'multiShot'},{'arcaneShot'}},
 rogue={{'hemorrhage'},{'mutilate'},{'ambush'},{'eviscerate'}},
 priest={{'shadowWordPain',dot=true},{'mindBlast'},{'shadowWordDeath'},{'mindFlay'},{'holyFire'},{'smite'}},
 shaman={{'flameShock',dot=true},{'lavaBurst'},{'stormstrike'},{'earthShock'},{'lightningBolt'}},
 mage={{'fireBlast'},{'pyroblast'},{'fireball'},{'frostbolt'},{'scorch'}},
 warlock={{'corruption',dot=true},{'immolate',dot=true},{'conflagrate'},{'shadowBolt'},{'incinerate'}},
 druid={{'moonfire',dot=true},{'insectSwarm',dot=true},{'rake',dot=true},{'starfire'},{'wrath'}},
}
local function playerLevel()local ok,l=pcall(UnitLevel,'player');return ok and num(l)or 1 end
local function classToken()local ok,_,c=pcall(UnitClass,'player');return ok and str(c)and c:lower()or nil end
function HUD.BasicRows()
 local class=classToken();local list=class and BASIC[class];local data=class and FUSLiveData and FUSLiveData[class]
 if not list or not data or not data.abilities then return{}end
 local level=playerLevel();local rows={}
 for _,entry in ipairs(list)do
  local ranks=data.abilities[entry[1]];local pick
  for _,r in ipairs(ranks or{})do
   if(tonumber(r.level)or 0)<=level and r.id and known(r.id)then pick=r end
  end
  if pick then
   local row={spellId=pick.id}
   if entry.dot then row.condition={['not']={val={auraIsActive={auraId={spellId=pick.id},sourceUnit={type='CurrentTarget'}}}}}end
   rows[#rows+1]=row
  end
 end
 return rows
end
-- The priority list the HUD follows, and where it comes from ('engine' | 'basic').
function HUD.Rows()
 local C=ForeverCoreClient;local Sim=C and C.Sim
 local rot=Sim and Sim.Rotation and Sim.Rotation()
 if rot and type(rot.priority)=='table'and #rot.priority>0 then return rot.priority,'engine'end
 return HUD.BasicRows(),'basic'
end

-- Procs ------------------------------------------------------------------------------------------------------------------
-- The game lights an ability up when it can be used in a special way (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE); that
-- works for every proc without reading auras, which are hidden in combat. IsSpellOverlayed is asked as well when the
-- client has it. A value the game keeps secret is simply not used.
local glow={}
HUD.glow=glow
function HUD.SetGlow(id,on)
 id=num(id);if not id then return end
 if on then if not glow[id]then glow[id]=now()end else glow[id]=nil end
end
local function baseOf(id)
 for _,f in each(C_Spell and C_Spell.GetBaseSpell,FindBaseSpellByID)do
  local ok,v=pcall(f,id);v=ok and num(v)or nil;if v and v~=id then return v end
 end
end
local function overlayed(id)
 for _,f in each(C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed,IsSpellOverlayed)do
  local ok,v=pcall(f,id);if ok and not protected(v)and v~=nil then return v==true end
 end
 return nil
end
-- is this spell (or the spell it replaces) lit up right now? Returns the time it lit up.
function HUD.ProcSince(id)
 if glow[id]then return glow[id]end
 local b=baseOf(id);if b and glow[b]then return glow[b]end
 local o=overlayed(id);if o==nil and b then o=overlayed(b)end
 if o then glow[id]=glow[id]or now();return glow[id]end
 return nil
end

-- The queue ----------------------------------------------------------------------------------------------------------------
local recentCasts={}
function HUD.OnCast(id)id=num(id);if id then recentCasts[id]=now()end end
function HUD.ClearCasts()recentCasts={}end
local GCD=1.5
-- Items: {id,icon,name,state='ready'|'wait',delay,proc}. The first is the one to press now; the following are what the
-- same rotation asks for next, with the effect of each cast taken into account (cooldown, DoT). A spell that is only a
-- moment away is offered as 'wait' with the seconds that are left.
function HUD.Build(rows,maxItems,noWait)
 maxItems=maxItems or 6;rows=rows or HUD.Rows()
 local E={vt=0,ready={},dot={}};local items={};local vt=0
 -- seconds until the spell can be cast (0 = now); nil when it cannot be used soon
 local function ready(row,steps)
  local id=row.spellId
  local remaining,enabled,gcdOnly=cooldown(id)
  if not enabled then return nil end
  if steps==0 then
   if now()-(recentCasts[id]or-100)<=.65 then return nil end
   if not usable(id)then return nil end
  end
  local left=E.ready[id]and math.max(0,E.ready[id]-vt)or math.max(0,remaining-vt)
  if left<=.15 or(steps==0 and gcdOnly and left<=GCD+.1)then return 0 end
  if left<=2.5 and not noWait then return left end
  return nil
 end
 -- what is being cast now counts as done by the time it lands; the queue is what to press after it
 local castId,castLeft=castingNow()
 if castId then
  vt=castLeft;E.vt=vt
  local own=baseCooldown(castId);E.ready[castId]=vt+(own>1.6 and own or GCD)
  for _,row in ipairs(rows)do if row.spellId==castId then local w=watchedDuration(row);if w then E.dot[castId]=vt+w end end end
 end
 for step=0,maxItems-1 do
  E.vt=vt
  local best,bestWait
  for _,row in ipairs(rows)do
   if not row.automatic and(not row.condition or aplCondition(row.condition,E)==true)then
    local wait=ready(row,step)
    if wait==0 then best,bestWait=row,0;break end
    if wait and(not bestWait or wait<bestWait)then best,bestWait=row,wait end
   end
  end
  if not best then break end
  local id=best.spellId
  local delay=bestWait or 0
  local name,icon=spellName(id),spellIcon(id)
  items[#items+1]={id=id,icon=icon or'Interface\\Icons\\INV_Misc_QuestionMark',name=name or('Zauber '..id),state=delay>0 and'wait'or'ready',delay=delay,
   since=HUD.ProcSince(id)}
  vt=vt+delay
  -- what the cast changes for the next picks
  local cast=math.max(GCD,castSeconds(id))
  local own=baseCooldown(id)
  if own>1.6 then E.ready[id]=vt+own else E.ready[id]=vt+GCD end
  local w=watchedDuration(best);if w then E.dot[id]=vt+w end
  vt=vt+cast
 end
 if #items==0 then
  -- nothing is ready: an automatic action (Auto Shot) is better than an empty HUD
  for _,row in ipairs(rows)do
   if row.automatic then
    items[1]={id=row.spellId,icon=spellIcon(row.spellId)or'Interface\\Icons\\INV_Misc_QuestionMark',name=spellName(row.spellId)or'Automatisch',state='ready',delay=0,auto=true,since=nil}
    break
   end
  end
 end
 return items
end

-- A lit-up spell that the rotation did not offer is added in front (the game says it is worth pressing).
function HUD.WithProcs(items,rows)
 local first
 for i,it in ipairs(items)do if it.since then first=i;break end end
 if first and first>1 then local it=table.remove(items,first);table.insert(items,1,it)end
 if first then items[1].proc=true;return items end
 -- a proc of a spell the list has not reached yet
 for _,row in ipairs(rows or{})do
  local id=row.spellId;local since=id and HUD.ProcSince(id)
  if since and not row.automatic and usable(id)then
   local name,icon=spellName(id),spellIcon(id)
   table.insert(items,1,{id=id,icon=icon or'Interface\\Icons\\INV_Misc_QuestionMark',name=name or('Zauber '..id),state='ready',delay=0,since=since,proc=true})
   return items
  end
 end
 return items
end
-- What the HUD shows right now: {items, source, proc=bool}
function HUD.Current()
 local cfg=HUD.Config();local rows,source=HUD.Rows()
 local items=HUD.Build(rows,cfg.queue+1,cfg.showDelay==false)
 if cfg.procs~=false then items=HUD.WithProcs(items,rows)end
 while #items>cfg.queue+1 do items[#items]=nil end
 return{items=items,source=source,proc=items[1]~=nil and items[1].proc==true}
end

-- Key bindings (read outside combat, cached) --------------------------------------------------------------------------------
local BARS={{1,'ACTIONBUTTON'},{61,'MULTIACTIONBAR1BUTTON'},{49,'MULTIACTIONBAR2BUTTON'},{25,'MULTIACTIONBAR3BUTTON'},{37,'MULTIACTIONBAR4BUTTON'}}
local keyCache={}
local function shortKey(k)return(k:gsub('SHIFT%-','S'):gsub('CTRL%-','C'):gsub('ALT%-','A'):gsub('NUMPAD','N'):gsub('BUTTON','M'))end
function HUD.RebuildKeys()
 if inCombat()or type(GetActionInfo)~='function'or type(GetBindingKey)~='function'then return end
 local out={}
 for _,bar in ipairs(BARS)do for i=0,11 do
  local ok,kind,id=pcall(GetActionInfo,bar[1]+i)
  if ok and kind=='spell'and num(id)then
   local okKey,key=pcall(GetBindingKey,bar[2]..(i+1))
   if okKey and str(key)and key~=''then
    key=shortKey(key);if not out[id]then out[id]=key end
    local name=spellName(id);if name and not out[name]then out[name]=key end
   end
  end
 end end
 keyCache=out
 if HUD.OnKeysChanged then HUD.OnKeysChanged()end
end
function HUD.KeyFor(item)return item and(keyCache[item.id]or(item.name and keyCache[item.name]))or nil end
HUD.keyCache=function()return keyCache end

-- Hooks: other parts (the fight check) listen to what the HUD sees. fire() never lets a listener break the HUD.
local hooks={}
function HUD.On(name,fn)hooks[name]=hooks[name]or{};table.insert(hooks[name],fn)end
local function fire(name,...)for _,fn in ipairs(hooks[name]or{})do pcall(fn,...)end end
HUD.Fire=fire

-- Events -----------------------------------------------------------------------------------------------------------------------
local ev=CreateFrame('Frame')
for _,e in ipairs({'UNIT_SPELLCAST_START','UNIT_SPELLCAST_CHANNEL_START','ENCOUNTER_START','ENCOUNTER_END','SPELL_ACTIVATION_OVERLAY_GLOW_SHOW','SPELL_ACTIVATION_OVERLAY_GLOW_HIDE','UNIT_SPELLCAST_SUCCEEDED','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','PLAYER_ENTERING_WORLD','PLAYER_DEAD','UPDATE_BINDINGS','ACTIONBAR_SLOT_CHANGED','ACTIONBAR_PAGE_CHANGED','UPDATE_BONUS_ACTIONBAR','UPDATE_SHAPESHIFT_FORM','SPELLS_CHANGED'})do
 pcall(ev.RegisterEvent,ev,e)
end
ev:SetScript('OnEvent',function(_,event,a,b,c,d,e)
 if event=='SPELL_ACTIVATION_OVERLAY_GLOW_SHOW'then fire('glow',num(a),true);HUD.SetGlow(a,true);if HUD.OnProc then HUD.OnProc(num(a))end
 elseif event=='SPELL_ACTIVATION_OVERLAY_GLOW_HIDE'then fire('glow',num(a),false);HUD.SetGlow(a,false)
 elseif event=='UNIT_SPELLCAST_START'or event=='UNIT_SPELLCAST_CHANNEL_START'then
  if a=='player'then local id=num(c)or num(b);if id then fire('castStart',id)end end
 elseif event=='ENCOUNTER_START'then fire('encounterStart',num(a),str(b))
 elseif event=='ENCOUNTER_END'then fire('encounterEnd',num(a),str(b),e==1 or e==true)
 elseif event=='UNIT_SPELLCAST_SUCCEEDED'then
  if a=='player'then
   -- some builds report (unit, castGUID, spellID), others the spell id in second place
   local id=num(c)or num(b);if id then fire('cast',id);HUD.OnCast(id);if HUD.OnCasted then HUD.OnCasted(id)end end
  end
 elseif event=='PLAYER_REGEN_DISABLED'then HUD.ClearCasts();if HUD.OnCombat then HUD.OnCombat(true)end
 elseif event=='PLAYER_REGEN_ENABLED'then HUD.ClearCasts();if HUD.OnCombat then HUD.OnCombat(false)end;HUD.RebuildKeys()
 elseif event=='PLAYER_DEAD'then for k in pairs(glow)do glow[k]=nil end
 elseif event=='PLAYER_ENTERING_WORLD'or event=='SPELLS_CHANGED'then for k in pairs(glow)do glow[k]=nil end;HUD.RebuildKeys()
 else HUD.RebuildKeys()end
end)
HUD.events=ev

-- A short German explanation of when a row of the rotation applies, for the priority list in the window.
function HUD.Describe(row)
 if row.automatic then return'Läuft automatisch'end
 local c=row.condition
 if not c then return'sonst immer'end
 local text
 local function walk(n)
  if type(n)~='table'or text then return end
  if n.dotRemainingTime or n.auraIsActive then text='Erneuern, wenn der Effekt fehlt';return end
  if n.spellTimeToReady then text='wenn bereit';return end
  if n.currentManaPercent then text='abhängig vom Mana';return end
  if n.numberTargets then text='je nach Zielanzahl';return end
  for _,v in pairs(n)do if type(v)=='table'then walk(v)end end
 end
 walk(c)
 return text or'unter Bedingungen'
end
-- Whether the game lights this spell up in some situation (a proc the class model knows about).
function HUD.IsProcSpell(id)
 local class=classToken();local data=class and FUSLiveData and FUSLiveData[class];if not data or not data.procs then return false end
 for _,p in ipairs(data.procs)do
  for _,key in ipairs(p.consumeOn or{})do
   for _,r in ipairs(data.abilities and data.abilities[key]or{})do if r.id==id then return true end end
  end
 end
 return false
end
