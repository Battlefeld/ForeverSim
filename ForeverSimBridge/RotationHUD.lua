-- Forever SIM 1.8.6: compact combat-only, read-only rotation suggestions.
-- The optimizer runs OUTSIDE combat. This file never calls P.run/P.best or casts spells.
local P=FUSLive
local DB=ForeverSimBridgeDB or {}
ForeverSimBridgeDB=DB
DB.hud=DB.hud or {enabled=true,locked=true,scale=1}
local cfg=DB.hud
local HUD={}
P.rotationHUD=HUD
HUD.inCombat=false
local now=GetTime or function()return 0 end
local safeNumber=P.publicNumber or function(v)return type(v)=='number'and v or nil end
local safeString=P.publicString or function(v)return type(v)=='string'and v or nil end
local protected=P.isProtected or function()return false end
local function safeBoolean(v)
 if protected(v) or type(v)~='boolean' then return nil end
 return v
end
local function combat()
 if InCombatLockdown and safeBoolean(InCombatLockdown()) then return true end
 return UnitAffectingCombat and safeBoolean(UnitAffectingCombat('player'))==true or false
end
local function haveTarget()
 local present=UnitExists and safeBoolean(UnitExists('target'))
 if not present then return false end
 if not UnitCanAttack then return true end
 return safeBoolean(UnitCanAttack('player','target'))==true
end
local function power(unit,currency)
 local powerType=currency=='energy'and 3 or currency=='rage'and 1 or 0
 local n=UnitPower and safeNumber(UnitPower(unit,powerType))
 if not n and UnitMana then n=safeNumber(UnitMana(unit)) end
 local max=UnitPowerMax and safeNumber(UnitPowerMax(unit,powerType))
 if not max and UnitManaMax then max=safeNumber(UnitManaMax(unit)) end
 return n or 0,max or 0,n~=nil and max~=nil
end
local function cooldown(id,name)
 if C_Spell and C_Spell.GetSpellCooldown then
  local info=C_Spell.GetSpellCooldown(id or name)
  if protected(info) then return math.huge,false,false end
   if info then
    local st,du=safeNumber(info.startTime),safeNumber(info.duration)
    if not st or not du or protected(info.isEnabled) then return math.huge,false,false end
    return math.max(0,st+du-now()),info.isEnabled~=false,du<=1.6,st,du
   end
 end
 if GetSpellCooldown then
  local a,b,enabled=GetSpellCooldown(id or name)
  a,b=safeNumber(a),safeNumber(b)
   if a and b and not protected(enabled) then return math.max(0,a+b-now()),enabled~=0,b<=1.6,a,b end
   return math.huge,false,false
 end
 return 0,true
end
local function auraRemaining(unit,id,name,harmful)
 local present=UnitExists and safeBoolean(UnitExists(unit))
 if not present then return 0 end
 local t=now()
 -- Do not count another player's DoT as our own.
 for i=1,40 do
  local aura
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
   aura=C_UnitAuras.GetAuraDataByIndex(unit,i,harmful and 'HARMFUL' or 'HELPFUL')
   if protected(aura) then return 3600,true end
   if not aura then break end
   local spell=safeNumber(aura.spellId)
    local auraName=safeString(aura.name)
    local source=safeString(aura.sourceUnit)
    local matching=(id and spell and spell==id) or (name and auraName and auraName==name)
    if matching and (not harmful or source=='player' or source=='pet') then
     local expires=safeNumber(aura.expirationTime)
     if not expires then return 3600,true end -- do not refresh a possibly active DoT blindly
     return (expires>0 and math.max(0,expires-t) or 3600),true
    end
  else
   local spellName,_,_,_,duration,expires,source,_,_,spellId
   if harmful and UnitDebuff then
    spellName,_,_,_,duration,expires,source,_,_,spellId=UnitDebuff(unit,i)
   elseif UnitBuff then
    spellName,_,_,_,duration,expires,source,_,_,spellId=UnitBuff(unit,i)
   end
   if protected(spellName) or protected(source) or protected(spellId) then return 3600,true end
    if not spellName then break end
    local matching=(id and spellId==id) or (name and spellName==name)
    if matching and (not harmful or source=='player' or source=='pet') then
     expires=safeNumber(expires)
     if not expires then return 3600,true end
     return (expires>0 and math.max(0,expires-t) or 3600),true
    end
  end
 end
 return 0,false
end
local function isUsable(id,name)
 if not IsUsableSpell then return true end
 local usable,noMana=IsUsableSpell(id or name)
 if protected(usable) or protected(noMana) then return false,false end
 return usable==true, noMana==true
end
local function exists(id,name)
 return id or name
end
-- Combat display in the look of the design renders: one large "press now" icon with
-- key binding, up to two smaller follow-up icons, proc glow, cooldown and range tint.
-- Pure display: never casts, never touches secure frames. Settings: page "Rotation Style".
local MEDIA='Interface\\AddOns\\ForeverSimBridge\\Media\\'
local function opt(key,default)local v=cfg[key];if v==nil then return default end;return v end
local frame=CreateFrame('Frame','ForeverSimRotationHUD',UIParent)
frame:SetSize(260,132)
frame:SetPoint('BOTTOM',UIParent,'BOTTOM',0,167)
frame:SetScale(cfg.scale or 1)
frame:SetFrameStrata('MEDIUM')
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag('LeftButton')
frame:SetScript('OnDragStart',function(self)if not cfg.locked and not combat()then self:StartMoving()end end)
frame:SetScript('OnDragStop',function(self)
 self:StopMovingOrSizing()
 local x,y=self:GetCenter();local ux,uy=UIParent:GetCenter()
 if x and ux then cfg.x=x-ux;cfg.y=y-uy end
end)
-- Background and heading only while unlocked, so the frame can be found and dragged.
local back=frame:CreateTexture(nil,'BACKGROUND');back:SetAllPoints();back:SetColorTexture(.015,.013,.025,.70)
local border=frame:CreateTexture(nil,'BORDER');border:SetPoint('TOPLEFT',2,-2);border:SetPoint('TOPRIGHT',-2,-2);border:SetHeight(2);border:SetColorTexture(.85,.66,.28,.90)
local head=frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
head:SetPoint('BOTTOMLEFT',frame,'TOPLEFT',2,3);head:SetText('ForeverSim · Rotation (ziehen zum Verschieben)')
local status=frame:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
status:SetPoint('BOTTOMRIGHT',frame,'TOPRIGHT',-2,3);status:SetWidth(160);status:SetJustifyH('RIGHT')
local procLabel=frame:CreateFontString(nil,'OVERLAY','GameFontNormal')
procLabel:SetPoint('TOPLEFT',14,-4);procLabel:SetJustifyH('LEFT')
local cells={}
for i=1,3 do
 local size=i==1 and 64 or 40
 local f=CreateFrame('Frame',nil,frame);f:SetSize(size,size)
 if i==1 then f:SetPoint('TOPLEFT',14,-26) else f:SetPoint('BOTTOMLEFT',cells[i-1],'BOTTOMRIGHT',i==2 and 12 or 8,0) end
 f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetAllPoints();f.icon:SetTexCoord(.07,.93,.07,.93);f.icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
 f.tint=f:CreateTexture(nil,'OVERLAY');f.tint:SetAllPoints();f.tint:SetColorTexture(0,0,0,.0)
 local okCd,cd=pcall(CreateFrame,'Cooldown',nil,f,'CooldownFrameTemplate')
 if okCd and cd then cd:SetAllPoints();if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers,cd,true)end;f.cooldown=cd end
 f.cdText=f:CreateFontString(nil,'OVERLAY',i==1 and 'GameFontNormalLarge' or 'GameFontNormal');f.cdText:SetPoint('CENTER')
 f.key=f:CreateFontString(nil,'OVERLAY',i==1 and 'GameFontHighlightLarge' or 'GameFontHighlight');f.key:SetPoint('BOTTOMRIGHT',-3,3);f.key:SetJustifyH('RIGHT')
 f.label=f:CreateFontString(nil,'OVERLAY','GameFontHighlight');f.label:SetPoint('TOPLEFT',f,'BOTTOMLEFT',0,-5)
 f.label:SetWidth(220);f.label:SetJustifyH('LEFT');f.label:SetText('')
 if i>1 then f.label:Hide() end
 cells[i]=f
end
local glow=cells[1]:CreateTexture(nil,'OVERLAY',nil,2);glow:SetTexture(MEDIA..'FSGlow')
glow:SetPoint('TOPLEFT',-14,14);glow:SetPoint('BOTTOMRIGHT',14,-14);glow:Hide()
local pulse=glow.CreateAnimationGroup and glow:CreateAnimationGroup()
if pulse then
 local a=pulse:CreateAnimation('Alpha');a:SetFromAlpha(1);a:SetToAlpha(.45);a:SetDuration(.45);a:SetOrder(1)
 local b=pulse:CreateAnimation('Alpha');b:SetFromAlpha(.45);b:SetToAlpha(1);b:SetDuration(.45);b:SetOrder(2)
 pulse:SetLooping('REPEAT')
end
local note=frame:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');note:SetPoint('TOPLEFT',cells[1],'BOTTOMLEFT',0,-24);note:SetWidth(240);note:SetJustifyH('LEFT')
-- Hekili-like read-only icon queue: no captions, no idle panel, no automated casts.
cfg.combatOnly=true
cfg.showName=false
cfg.procText=false
head:Hide();status:Hide();note:Hide();procLabel:Hide()
for _,cell in ipairs(cells)do cell.label:Hide()end
-- Forward declaration: combat display calls this before the action-bar helper
-- is defined; without it Lua attempts a nil global and the rotation disappears.
local highlightBar
local currentIndex=1
local switchedAt=-5
-- Independent outgoing icon: previous action can shrink/fade while the new one grows.
local outgoing=CreateFrame('Frame',nil,frame)
outgoing:SetSize(64,64)
outgoing:SetPoint('CENTER',cells[1],'CENTER',0,0)
outgoing:SetFrameLevel(cells[1]:GetFrameLevel()+5)
outgoing.icon=outgoing:CreateTexture(nil,'ARTWORK')
outgoing.icon:SetAllPoints()
outgoing.icon:SetTexCoord(.07,.93,.07,.93)
outgoing:Hide()
local transitionSeconds=.27
local function smooth(x)
 x=math.max(0,math.min(1,x))
 return 1-(1-x)*(1-x)*(1-x)
end
local function animateTransition()
 if not frame:IsShown()then outgoing:Hide();return end
 local p=math.max(0,math.min(1,(now()-switchedAt)/transitionSeconds))
 local eased=smooth(p)
 local main=cells[1]
 main:SetAlpha(.24+.76*eased)
 main:SetScale(.78+.22*eased)
 if outgoing:IsShown()then
  outgoing:SetAlpha((1-p)*(1-p)*.95)
  outgoing:SetScale(1-.33*eased)
  if p>=1 then outgoing:Hide()end
 end
end
local function shiftTo(list,newIndex)
 if not list or not list[newIndex] or newIndex==currentIndex then return end
 local old=list[currentIndex]
 if old and old.icon then
  outgoing.icon:SetTexture(old.icon)
  outgoing:SetScale(1);outgoing:SetAlpha(.95);outgoing:Show()
 else outgoing:Hide()end
 currentIndex=newIndex
 switchedAt=now()
end
-- Fade the complete HUD as well as individual icons. The frame remains shown
-- until the outro completes, allowing OnUpdate to render every intermediate step.
local visibility={value=0,from=0,to=0,started=now()}
local function requestVisibility(visible)
 local target=visible and 1 or 0
 if visibility.to~=target then
  visibility.from=visibility.value
  visibility.to=target
  visibility.started=now()
 end
 if target==1 and not frame:IsShown()then frame:Show()end
end
local function animateVisibility()
 if not frame:IsShown()then return end
 local duration=visibility.to==1 and .18 or .22
 local p=math.max(0,math.min(1,(now()-visibility.started)/duration))
 local eased=p*p*(3-2*p)
 visibility.value=visibility.from+(visibility.to-visibility.from)*eased
 frame:SetAlpha(math.max(.3,math.min(1,opt('alpha',1)))*visibility.value)
 if p>=1 and visibility.to==0 then frame:Hide()end
end
local lastProcKey=nil
-- Publicly readable short-duration player buffs only. Match localized aura
-- text if no reliable buff spell ID exists; never infer a proc from RNG or combat log.
local function procAuraActive(proc)
 local buffId=HUD.buffIds and HUD.buffIds[proc.buff]
 if buffId then
  local rem=auraRemaining('player',buffId,nil,false)
  return rem>0 and rem<3599
 end
 if type(proc.buff)~='string' then return false end
 local key=proc.buff:lower():gsub('[^%w]','')
 for i=1,40 do
  local name,expiration
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
   local a=C_UnitAuras.GetAuraDataByIndex('player',i,'HELPFUL')
   if protected(a)then return false end
   if not a then break end
   name=safeString(a.name);expiration=safeNumber(a.expirationTime)
  elseif UnitBuff then
   local n,_,_,_,_,expires=UnitBuff('player',i)
   name=safeString(n);expiration=safeNumber(expires)
  else break end
  if not name then break end
  if name:lower():gsub('[^%w]','')==key and expiration and expiration>now() then return true end
 end
 return false
end
local function procIndex(list)
 for _,p in ipairs(HUD.procs or{})do
  if procAuraActive(p) then
   for i,a in ipairs(list)do
    if a.key==p.key or (HUD.abilities and HUD.abilities[p.key] and HUD.abilities[p.key].id==a.id)then
     return i,p.buff
    end
   end
  end
 end
 return nil,nil
end
-- Live APL evaluation; never propose active DoTs just because their cooldown ended.
local function aplID(node)
 if type(node)~='table' then return safeNumber(node) end
 local id=node.spellId
 if type(id)=='table' then return safeNumber(id.spellId) end
 return safeNumber(id)
end
local function aplValue(node)
 if type(node)~='table' then return nil end
 if node.const then
  local v=node.const.val
  if type(v)=='number' then return v end
  if type(v)=='string' then return tonumber(v:match('([%d%.]+)')) end
  return nil
 end
 if node.currentManaPercent then
  local v,m,ok=power('player','mana')
  return ok and m>0 and v*100/m or nil
 end
 if node.spellTimeToReady then
  local id=aplID(node.spellTimeToReady)
  if not id then return nil end
  local seconds,enabled=cooldown(id)
  return enabled and seconds or nil
 end
 if node.dotRemainingTime then
  local id=aplID(node.dotRemainingTime)
  if not id then return nil end
  return auraRemaining('target',id,nil,true)
 end
 if node.auraIsActive then
  local a=node.auraIsActive
  local id=aplID(a.auraId)
  if not id then return nil end
  local unit=type(a.sourceUnit)=='table' and a.sourceUnit.type=='CurrentTarget' and 'target' or 'player'
  local remain=auraRemaining(unit,id,nil,unit=='target')
  return remain>0
 end
 if node.numberTargets then return haveTarget() and 1 or 0 end
 if node.spellCastTime then
  local id=aplID(node.spellCastTime)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
   local ok,info=pcall(C_Spell.GetSpellInfo,id)
   if ok and type(info)=='table' and safeNumber(info.castTime) then return info.castTime/1000 end
  elseif GetSpellInfo then
   local ok,_,_,_,cast=pcall(GetSpellInfo,id)
   if ok and safeNumber(cast) then return cast/1000 end
  end
 end
 return nil
end
local function aplCondition(node)
 if type(node)~='table' then return nil end
 if node["and"] then
  local values=node["and"].vals or {}
  for _,x in ipairs(values)do if aplCondition(x)~=true then return false end end
  return #values>0
 end
 if node["or"] then
  for _,x in ipairs(node["or"].vals or {})do if aplCondition(x)==true then return true end end
  return false
 end
 if node["not"] then
  local v=aplCondition(node["not"].val)
  if v==nil then return nil end
  return not v
 end
 if node.cmp then
  local x=aplValue(node.cmp.lhs)
  local y=aplValue(node.cmp.rhs)
  if type(x)~='number' or type(y)~='number' then return nil end
  local op=node.cmp.op
  if op=='OpLt' then return x<y end
  if op=='OpLe' then return x<=y end
  if op=='OpGt' then return x>y end
  if op=='OpGe' then return x>=y end
  if op=='OpEq' then return x==y end
  if op=='OpNe' then return x~=y end
 end
 if node.auraIsActive then return aplValue(node) end
 return nil
end
local recentCasts={}
local function actionable()
 local list={}
 local passive=nil
 for _,policy in ipairs(HUD.policies or {})do
  local ability=HUD.abilities and HUD.abilities[policy.key]
  if ability then
   if ability.automatic then
    if not passive then passive=ability end
   elseif (not ability.condition or aplCondition(ability.condition)==true)
    and now()-(recentCasts[ability.id]or -100)>0.65 then
    local remaining,enabled,gcd=cooldown(ability.id,ability.name)
    local usable=isUsable(ability.id,ability.name)
    if enabled and usable and (remaining<=0.15 or (gcd and remaining<=1.6)) then list[#list+1]=ability end
   end
  end
 end
 -- At low hunter levels MythicSim can resolve only Auto Shot. Showing its icon
 -- is preferable to a broken empty UI, but it is never marked as a cast action.
 if #list==0 and passive then list[1]=passive end
 return list
end
local function displayCombatQueue()
 local list=actionable()
 if not cfg.enabled or not HUD.inCombat or #list==0 then
  requestVisibility(false)
  if highlightBar then highlightBar(nil)end
  return
 end
 local proc,procKey=procIndex(list)
 if proc and proc>1 then table.insert(list,1,table.remove(list,proc))end
 lastProcKey=procKey
 if not HUD.previousRecommended or HUD.previousRecommended.id~=list[1].id then
  if HUD.previousRecommended and HUD.previousRecommended.icon then
   outgoing.icon:SetTexture(HUD.previousRecommended.icon)
   outgoing:SetScale(1);outgoing:SetAlpha(.95);outgoing:Show()
  else outgoing:Hide()end
  switchedAt=now()
  HUD.previousRecommended=list[1]
 end
 currentIndex=1
 requestVisibility(true)
 -- A proc immediately interrupts the icon queue only if its aura is publicly readable.
 local active=procKey~=nil and proc==currentIndex
 for i,cell in ipairs(cells)do
  local ability=list[i]
  cell:SetShown(ability~=nil and (i==1 or (i==2 and opt('queue',2)>=1) or (i==3 and opt('queue',2)>=2)))
  if ability then HUD.paint(i,ability,i==1 and active and 'proc' or nil)end
  cell.label:Hide()
  if i~=1 then cell:SetAlpha(i==2 and .70 or .48);cell:SetScale(1)end
 end
 highlightBar(list[currentIndex])
 glow:SetShown(active)
 if pulse then if active then if not pulse:IsPlaying()then pulse:Play()end else pulse:Stop()end end
 if not HUD.animBroken then pcall(animateTransition)end
end
function HUD.AdvanceOnCast(spellID)
 if not HUD.inCombat or not safeNumber(spellID)then return end
 recentCasts[spellID]=now()
 displayCombatQueue()
end

function HUD.EnableSavedDisplay()cfg.enabled=true end
-- Key bindings: read outside combat only and cached by spell id and name.
local keyCache={}
-- Highlight of the next key on the action bar (ZIELE.md, Ziel 5). Our own unprotected frames, anchored once
-- outside combat to Blizzard's buttons; in combat only their visibility changes. Blizzard buttons are never touched.
local BAR_FRAMES={'ActionButton','MultiBarBottomLeftButton','MultiBarBottomRightButton','MultiBarRightButton','MultiBarLeftButton'}
local overlays,overlayFor={},{}
local function overlayOn(button)
 for _,o in ipairs(overlays)do if o.anchor==button then return o end end
 local o=CreateFrame('Frame',nil,UIParent);o:SetFrameStrata('FULLSCREEN');o.anchor=button
 o.tex=o:CreateTexture(nil,'OVERLAY');o.tex:SetAllPoints();o.tex:SetTexture(MEDIA..'FQGoldBorder')
 o:SetPoint('TOPLEFT',button,'TOPLEFT',-4,4);o:SetPoint('BOTTOMRIGHT',button,'BOTTOMRIGHT',4,-4);o:Hide()
 overlays[#overlays+1]=o;return o
end
local BARS={{1,'ACTIONBUTTON'},{61,'MULTIACTIONBAR1BUTTON'},{49,'MULTIACTIONBAR2BUTTON'},{25,'MULTIACTIONBAR3BUTTON'},{37,'MULTIACTIONBAR4BUTTON'}}
local function shortKey(k)return (k:gsub('SHIFT%-','S'):gsub('CTRL%-','C'):gsub('ALT%-','A'):gsub('NUMPAD','N'):gsub('BUTTON','M'))end
function HUD.RebuildKeys()
 if combat() or type(GetActionInfo)~='function' or type(GetBindingKey)~='function' then return end
 local out={}
 for barIndex,bar in ipairs(BARS)do for i=0,11 do
  local ok,kind,id=pcall(GetActionInfo,bar[1]+i)
  if ok and kind=='spell' and id then
   local okKey,key=pcall(GetBindingKey,bar[2]..(i+1))
   if okKey and type(key)=='string' and key~='' then
    key=shortKey(key)
    if not out[id] then out[id]=key end
    local name=P.spellDisplay and P.spellDisplay(id)
    if type(name)=='string' and not out[name] then out[name]=key end
   end
  end
 end end
 keyCache=out
 -- Overlays: the slot each Blizzard button shows is read from the button (stances, forms and bar pages change it).
 overlayFor={}
 for _,frameName in ipairs(BAR_FRAMES)do for i=1,12 do
  local button=_G[frameName..i]
  local slot=button and type(button.action)=='number' and button.action or nil
  if slot then
   local ok,kind,id=pcall(GetActionInfo,slot)
   if ok and kind=='spell' and id and not overlayFor[id] then
    local name=P.spellDisplay and P.spellDisplay(id)
    local o=overlayOn(button);overlayFor[id]=o
    if type(name)=='string' and not overlayFor[name] then overlayFor[name]=o end
   end
  end
 end end
end
local function keyFor(a)return a and (keyCache[a.id] or keyCache[a.name]) or nil end
highlightBar=function(a)
 for _,o in ipairs(overlays)do if o:IsShown()then o:Hide()end end
 if not a or not opt('barHighlight',true)then return end
 local o=overlayFor[a.id] or overlayFor[a.name]
 if o and o.anchor and (not o.anchor.IsVisible or o.anchor:IsVisible()) then o:Show()end
end
local procWasActive=false
-- Paint one cell. state: nil (normal), 'proc', 'wait' (unknown/empty).
function HUD.paint(i,a,state)
 local f=cells[i]
 f.icon:SetTexture(a and a.icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
 f.icon:SetDesaturated(false);f.icon:SetVertexColor(1,1,1)
 f.tint:SetColorTexture(0,0,0,a and 0 or .55)
 f.cdText:SetText('')
 if f.cooldown then f.cooldown:Hide() end
 local k=opt('showKeys',true) and keyFor(a)
 f.key:SetText(k or '')
 if i==1 then f.label:SetText(opt('showName',true) and a and a.name or '');highlightBar(nil) end

 if i==1 then
  local proc=state=='proc'
  local c=cfg.procColor or {1,.82,.2}
  glow:SetVertexColor(c[1],c[2],c[3],1);glow:SetShown(proc)
  if pulse then if proc then if not pulse:IsPlaying()then pulse:Play()end else if pulse:IsPlaying()then pulse:Stop()end end end
  procLabel:SetShown(proc and opt('procText',true));procLabel:SetTextColor(c[1],c[2],c[3],1)
  procLabel:SetText(proc and ('Proc: '..(a and a.name or '')..' – jetzt nutzen') or '')
  if proc and not procWasActive and opt('procSound',false) and PlaySound then pcall(PlaySound,SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
  procWasActive=proc
 end
end
function HUD.Config()return cfg end
function HUD.ApplyStyle()
 frame:SetScale(math.max(.6,math.min(1.6,cfg.scale or 1)))
 frame:SetAlpha(math.max(.3,math.min(1,opt('alpha',1))))
 local q=opt('queue',2)
 cells[2]:SetShown(q>=1);cells[3]:SetShown(q>=2)
 local unlocked=not cfg.locked
 back:SetShown(unlocked);border:SetShown(unlocked);head:Hide();status:Hide();note:Hide();procLabel:Hide()
 for _,cell in ipairs(cells)do cell.label:Hide()end
 if cfg.locked then cfg.preview=nil end
 if HUD.refreshDisplay then HUD.refreshDisplay() end
end
frame:Hide()
local stats=CreateFrame('Frame','ForeverSimRotationStats',UIParent)
stats:SetSize(370,294);stats:SetPoint('CENTER',UIParent,'CENTER',0,40)
stats:SetFrameStrata('DIALOG');stats:EnableMouse(true);stats:SetMovable(true)
stats:RegisterForDrag('LeftButton');stats:SetScript('OnDragStart',function(self)if not combat()then self:StartMoving()end end)
stats:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
local bg=stats:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.03,.03,.05,.96)
local title=stats:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',15,-13);title:SetText('|cffbd82ffFOREVER SIM|r - Rotation')
local close=CreateFrame('Button',nil,stats,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-2,-2);close:SetScript('OnClick',function()stats:Hide()end)
local lines={}
for i=1,11 do local line=stats:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');line:SetPoint('TOPLEFT',15,-44-(i-1)*21);line:SetWidth(340);line:SetJustifyH('LEFT');lines[i]=line end
local function nameFor(k)
 if not HUD.abilities then return k end
 local a=HUD.abilities[k];return a and a.name or k
end
stats:SetHeight(335)
local function paintStats()
 if combat()then stats:Hide();return end
 local level=UnitLevel and UnitLevel('player')
 if level and level<P.minSimLevel() then
  for i,line in ipairs(lines)do line:SetText('')end
  lines[1]:SetText('|cffffb970Noch nicht verfügbar|r')
  lines[2]:SetText('DPS- und Rotationsoptimierung erst ab Level 10.')
  lines[3]:SetText('Aktuelles Level: '..level)
  return
 end
 local r=P.lastRotation
 local labels={}
 labels[1]=r and (r.engine=='MythicSim Go' and '|cffddddddLetzte Optimierung (MythicSim)|r' or '|cffddddddLetzte lokale Optimierung|r') or '|cffffb970Noch keine Optimierung gestartet|r'
 labels[2]=r and string.format('Start: %.1f DPS = 100%%',r.baselineDps or r.dps or 0) or 'Mit /fus optimize außerhalb des Kampfes starten.'
 labels[3]=r and string.format('Gewählt: %.1f DPS = %.2f%%',r.dps or 0,r.percentOfStart or 100) or ''
 if r and r.purpose=='leveling' then
  labels[1]='Ziel: Leveltempo · Einzelziel-Modell'
  labels[2]=string.format('Start: %.2f Gegner/min = 100%%',r.baselineKillsPerMinute or 0)
  labels[3]=string.format('Gewählt: %.2f Gegner/min = %.2f%%',r.killsPerMinute or 0,r.percentOfStart or 100)
 end
 labels[4]=r and (r.accepted and '|cff80ff80Bessere Rotation gefunden|r' or 'Startrotation beibehalten') or ''
 labels[5]=''
 labels[6]='|cffccaaffPriorität (erste sechs Regeln):|r'
 local policies=r and r.choice and r.choice.policies or {}
 for i=1,math.min(5,#policies)do labels[6+i]=i..'. '..nameFor(policies[i].key) end
 for i,line in ipairs(lines)do line:SetText(labels[i]or '')end
end
local levelButton=CreateFrame('Button',nil,stats,'UIPanelButtonTemplate');levelButton:SetSize(155,26);levelButton:SetPoint('BOTTOMLEFT',15,10);levelButton:SetText('Leveltempo');levelButton:SetScript('OnClick',function()if P.analysisUI then P.analysisUI.Show('leveling')end end)
local auditButton=CreateFrame('Button',nil,stats,'UIPanelButtonTemplate');auditButton:SetSize(155,26);auditButton:SetPoint('BOTTOMRIGHT',-15,10);auditButton:SetText('Kampfabgleich');auditButton:SetScript('OnClick',function()if P.analysisUI then P.analysisUI.Show('audit')end end)
HUD.abilities=nil;HUD.policies=nil;HUD.ready=false;HUD.stale=true
local function buildAbilities(data,profile,choice)
 local out={}
 local keys={};for _,pol in ipairs(choice.policies or {})do keys[pol.key]=true end
 for _,k in ipairs({'lifeTap','soulFire','shadowBolt','searingPain','immolate','corruption','baneOfDoom','baneOfAgony','conflagrate','shadowburn'})do if data.abilities[k] then keys[k]=true end end
 for key in pairs(keys)do
  local rs=P.ranks(data,profile,key)
  local rank=choice.ranks and choice.ranks[key]
  local chosen=rs[#rs]
  if rank then for _,r in ipairs(rs)do if r.rank==rank then chosen=r;break end end end
  if chosen then
   local id=chosen.id
   local spellName,icon
   if P.spellDisplay then
    spellName,icon=P.spellDisplay(id)
   elseif type(GetSpellInfo)=='function' then
    local n,_,texture=GetSpellInfo(id)
    spellName,icon=n,texture
   end
   out[key]={id=id,name=spellName or key,icon=icon or 'Interface\\Icons\\INV_Misc_QuestionMark',duration=chosen.duration,
     cast=chosen.cast or 0,cost=chosen.cost or 0,cooldown=chosen.cooldown or 0,requiresAura=chosen.requiresAura,
     requiresAuraGroup=chosen.requiresAuraGroup,exclusiveGroup=chosen.exclusiveGroup}
  end
 end
 return out
end
function HUD.configure(data,profile,result)
 if P.classModel then data=P.classModel(data,profile)end
 if not result or not result.choice or not result.choice.policies then return false end
 HUD.abilities=buildAbilities(data,profile,result.choice)
 if data.typedCombat then local ok,spec=pcall(P.compile,data,profile,P.combine(profile.equipped or {}),result.choice,60,7331);if not ok then HUD.ready=false;HUD.stale=true;return false end;for key,ability in pairs(HUD.abilities)do local b=spec.abilities[key];if b then for _,field in ipairs({'resource','cost','minCombo','maxTargetHealth','kind','forms','mobTypes'})do ability[field]=b[field]end end end;HUD.resource=spec.resource;HUD.form=profile.form else HUD.resource='mana'end
 HUD.policies=P.copy(result.choice.policies)
 HUD.tapAtPct=result.choice.tapAtPct or 0
 HUD.ready=#HUD.policies>0
 HUD.stale=false
 HUD.class=profile.class
 HUD.buffIds={};for _,rule in ipairs(data.genericProcs or {})do if rule.buffId then HUD.buffIds[rule.key]=rule.buffId end end;for key,ability in pairs(HUD.abilities)do if ability.kind=='buff'then HUD.buffIds[key]=ability.id end end
 HUD.manaStart=(profile.stats and profile.stats.mana) or 0
 HUD.procs={}
 local talents=P.talents and P.talents(data,profile) or {}
 for _,proc in ipairs(data.procs or {})do
  if proc.buff and (not proc.talent or (talents[proc.talent] or 0)>0) and proc.autoPriority~=false then
   for _,key in ipairs(proc.consumeOn or {})do
    if HUD.abilities[key] then HUD.procs[#HUD.procs+1]={key=key,buff=proc.buff} end
   end
  end
 end
 paintStats()
 cfg.saved={policies=P.copy(HUD.policies),abilities={},class=profile.class,level=profile.level}
 for key,ability in pairs(HUD.abilities)do cfg.saved.abilities[key]={id=ability.id,name=ability.name,icon=ability.icon,maxTargetHealth=ability.maxTargetHealth}end
 HUD.restored=false
 return HUD.ready
end
-- Import display metadata only. Never invoke the old Lua compiler for a Core result.
-- The engine APL contains level-60 spell IDs. The live engine resolves trained
-- ranks for actual casts; the HUD must independently show only learned spells
-- and use their real spellbook IDs instead of displaying untrained APL ranks.
function HUD.SetExternalPriority(rows,learned)
 if combat()then return nil end
 local knownByID,knownByName=nil,nil
 if type(learned)=='table'then
  knownByID,knownByName={},{}
  for _,spell in ipairs(learned)do
   local id=tonumber(spell.id);local name=spell.name
   if id and type(name)=='string'and name~=''then
    knownByID[id]=spell
    local key=string.lower(name);local prior=knownByName[key]
    if not prior or (tonumber(spell.rank)or 0)>=(tonumber(prior.rank)or 0)then knownByName[key]=spell end
   end
  end
 end
 local function spellInfo(id)
  local name,icon
  if C_Spell and C_Spell.GetSpellInfo then
   local ok,v=pcall(C_Spell.GetSpellInfo,id)
   if ok and not protected(v)and type(v)=='table'then name=safeString(v.name);icon=safeNumber(v.iconID)or safeString(v.iconID)end
  elseif GetSpellInfo then
   local ok,n,_,ico=pcall(GetSpellInfo,id)
   if ok then name=safeString(n);icon=safeNumber(ico)or safeString(ico)end
  end
  return name,icon
 end
 HUD.abilities={};HUD.policies={}
 local seen={}
 for index,row in ipairs(rows or{})do
  local id=tonumber(row.spellId)
  if id then
   local name,icon=spellInfo(id)
   if knownByID then
    local known=knownByID[id]or(name and knownByName[string.lower(name)])
    if known then
     -- Use the taught rank ID to get matching action bar buttons/icons.
     id=tonumber(known.id);name=known.name
     local _,learnedIcon=spellInfo(id);icon=learnedIcon or icon
    else id=nil end
   end
   if id then
    seen[id]=true
    local key='mythicsim:'..id..':'..index
    HUD.abilities[key]={id=id,name=(name or('Zauber '..id))..(row.automatic and ' (automatisch)' or ''),icon=icon or'Interface\\Icons\\INV_Misc_QuestionMark',automatic=row.automatic==true,condition=row.condition}
    HUD.policies[#HUD.policies+1]={key=key}
   end
  end
 end
 -- Bind only procs explicitly declared by the class model and tied to a
 -- learned, displayed action. A passive buff without a consumer does not take over.
 HUD.procs={};HUD.buffIds={}
 local _,classToken=UnitClass and UnitClass('player')
 local data=classToken and FUSLiveData and FUSLiveData[string.lower(classToken)] or nil
 if data then
  for _,generic in ipairs(data.genericProcs or{})do
   if generic.key and generic.buffId then HUD.buffIds[generic.key]=generic.buffId end
  end
  for _,p in ipairs(data.procs or{})do
   if p.buff and type(p.consumeOn)=='table' and #p.consumeOn>0 then
    for _,consumer in ipairs(p.consumeOn)do
     local ranks=data.abilities and data.abilities[consumer] or{}
     for _,policy in ipairs(HUD.policies)do
      local ability=HUD.abilities[policy.key]
      if ability then
       local same=false
       for _,rank in ipairs(ranks)do
        if tonumber(rank.id)==ability.id then same=true;break end
       end
       if same then HUD.procs[#HUD.procs+1]={key=policy.key,buff=p.buff}end
      end
     end
    end
   end
  end
 end
 HUD.ready=#HUD.policies>0;HUD.stale=false;HUD.restored=false;currentIndex=1;switchedAt=-5;outgoing:Hide();lastProcKey=nil;HUD.previousRecommended=nil;recentCasts={}
 cfg.saved={policies=P.copy(HUD.policies),abilities=P.copy(HUD.abilities)}
 HUD.refreshDisplay()
 return {policies=P.copy(HUD.policies)}
end
function HUD.invalidate()
 HUD.stale=true
end
function HUD.PolicyInfo(policy)
 local a=HUD.abilities and HUD.abilities[policy.key]
 local hint=(a and a.automatic) and 'Laeuft automatisch; kein weiterer Tastendruck' or policy.maintain and 'Erneuern, wenn der Effekt fehlt' or policy.maintainBuff and 'Buff aktiv halten' or policy.minCombo and ('Ab '..policy.minCombo..' Combopunkten') or policy.manaBelow and 'Bei wenig Mana' or policy.openerOnly and 'Zum Kampfbeginn' or 'Wenn verfügbar'
 return a and a.name or policy.key,a and a.icon or 'Interface\\Icons\\INV_Misc_QuestionMark',hint
end
local function showSavedPriority()
 if not cfg.enabled or not HUD.inCombat then frame:Hide();highlightBar(nil);return end
 stats:Hide()
 frame:Show()
 local current=not HUD.stale and (not P.stale or HUD.restored and P.revision==HUD.restoredRevision)
 status:SetText(HUD.ready and current and 'Gespeicherte Rotation' or 'Neu berechnen')
 note:SetText('Zauberpriorität · Bedingungen selbst prüfen')
 for i,cell in ipairs(cells)do
  local policy=HUD.policies and HUD.policies[i]
  local a=policy and HUD.abilities and HUD.abilities[policy.key]
  HUD.paint(i,a)
  cell.tint:SetColorTexture(0,0,0,a and current and 0 or .55)
  if i==1 and not a then cell.label:SetText('Berechnen') end
 end
 if not HUD.ready or not current then note:SetText('Nach dem Kampf: /fus optimize')end
end
function HUD.showStats()
 if combat()then print('Forever SIM: Statistik erst außerhalb des Kampfes öffnen.');return end
 paintStats();if stats:IsShown()then stats:Hide()else stats:Show()end
end
function HUD.refreshDisplay()
 head:Hide();status:Hide();note:Hide();procLabel:Hide()
 if HUD.inCombat or combat() then
  stats:Hide()
  displayCombatQueue()
 else
  requestVisibility(false);highlightBar(nil);glow:Hide();outgoing:Hide()
  cells[1]:SetScale(1);cells[1]:SetAlpha(1)
 end
end
frame:SetScript('OnUpdate',function(_,elapsed)
 -- Both fades run at display refresh speed, not at the 100 ms logic cadence.
 animateVisibility()
 if not HUD.animBroken then local ok=pcall(animateTransition);if not ok then HUD.animBroken=true;outgoing:Hide()end end
 HUD.elapsed=(HUD.elapsed or 0)+elapsed
 if HUD.elapsed>=.10 then HUD.elapsed=0;HUD.refreshDisplay()end
end)
local evt=CreateFrame('Frame')
for _,e in ipairs({'UNIT_SPELLCAST_SUCCEEDED','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','PLAYER_ENTERING_WORLD','PLAYER_TARGET_CHANGED','UNIT_AURA','PLAYER_EQUIPMENT_CHANGED','PLAYER_LEVEL_UP','CHARACTER_POINTS_CHANGED','SPELLS_CHANGED','UPDATE_BINDINGS','ACTIONBAR_SLOT_CHANGED','ACTIONBAR_PAGE_CHANGED','UPDATE_BONUS_ACTIONBAR','UPDATE_SHAPESHIFT_FORM'})do pcall(evt.RegisterEvent,evt,e)end
evt:SetScript('OnEvent',function(_,event,unit,castGUID,spellID)
 if event=='UNIT_SPELLCAST_SUCCEEDED' then
  -- Forever branches report (unit, castGUID, spellID); some client builds
  -- report the spell ID in the second argument instead.
  if unit=='player' then
   local id=safeNumber(spellID) or safeNumber(castGUID)
   HUD.AdvanceOnCast(id)
  end
  return
 end
 if event=='PLAYER_REGEN_DISABLED' then currentIndex=1;switchedAt=now();outgoing:Hide();lastProcKey=nil;HUD.previousRecommended=nil;recentCasts={} end
 if event=='PLAYER_REGEN_ENABLED' then currentIndex=1;outgoing:Hide();lastProcKey=nil;HUD.previousRecommended=nil;recentCasts={} end
 if event=='PLAYER_REGEN_DISABLED'then HUD.inCombat=true end
 if event=='UPDATE_BINDINGS' or event=='ACTIONBAR_SLOT_CHANGED' or event=='ACTIONBAR_PAGE_CHANGED' or event=='UPDATE_BONUS_ACTIONBAR' then HUD.RebuildKeys();return end
 if event=='UPDATE_SHAPESHIFT_FORM' then HUD.RebuildKeys();HUD.invalidate();HUD.refreshDisplay();return end
 if event=='PLAYER_REGEN_ENABLED' or event=='PLAYER_ENTERING_WORLD' or event=='SPELLS_CHANGED' then HUD.RebuildKeys() end
 if event=='PLAYER_REGEN_ENABLED' or event=='PLAYER_ENTERING_WORLD'then HUD.inCombat=false end
 if event=='UNIT_AURA' and unit~='target' and unit~='player' then return end
 if event=='PLAYER_EQUIPMENT_CHANGED' or event=='PLAYER_LEVEL_UP' or event=='CHARACTER_POINTS_CHANGED' or event=='SPELLS_CHANGED' then HUD.invalidate()end
 HUD.refreshDisplay()
end)
function HUD.command(cmd)
 if cmd=='stats' or cmd=='ui' then HUD.showStats();return true end
 if cmd=='hud' then cfg.enabled=not cfg.enabled;HUD.refreshDisplay();print('Forever SIM: Rotationstracker '..(cfg.enabled and 'aktiv' or 'aus'));return true end
 if cmd=='unlock' then if combat()then print('Forever SIM: erst nach dem Kampf verschieben.');return true end cfg.locked=false;print('Forever SIM: HUD entsperrt, mit linker Maustaste verschieben.');return true end
 if cmd=='lock' then cfg.locked=true;print('Forever SIM: HUD gesperrt.');return true end
 if cmd=='reset' then if combat()then return true end cfg.x=nil;cfg.y=nil;frame:ClearAllPoints();frame:SetPoint('BOTTOM',UIParent,'BOTTOM',0,167);print('Forever SIM: HUD-Position zurückgesetzt.');return true end
 return false
end
local function restoreSaved()
 frame:SetScale(cfg.scale or 1)
 if cfg.x and cfg.y then frame:ClearAllPoints();frame:SetPoint('CENTER',UIParent,'CENTER',cfg.x,cfg.y)end
 -- Restore only stored display metadata. No character, spell or combat API read.
 if type(cfg.saved)=='table' and type(cfg.saved.abilities)=='table' and type(cfg.saved.policies)=='table' then
  HUD.abilities=P.copy(cfg.saved.abilities);HUD.policies=P.copy(cfg.saved.policies)
  HUD.ready=#HUD.policies>0;HUD.stale=false;HUD.restored=true;HUD.restoredRevision=P.revision
 end
 HUD.ApplyStyle()
end
stats:Hide()
restoreSaved()
-- SavedVariables are assigned after this file runs, replacing the table captured
-- above. Rebind to the saved table once it exists so HUD settings persist.
local savedVariables=CreateFrame('Frame')
savedVariables:RegisterEvent('ADDON_LOADED')
savedVariables:SetScript('OnEvent',function(self,_,name)
 if name~='ForeverSimBridge' then return end
 self:UnregisterEvent('ADDON_LOADED')
 local live=ForeverSimBridgeDB
 if type(live)~='table' or live==DB then return end
 live.hud=type(live.hud)=='table' and live.hud or cfg
 DB,cfg=live,live.hud
 if cfg.enabled==nil then cfg.enabled=true end
 if cfg.locked==nil then cfg.locked=true end
 restoreSaved()
end)
