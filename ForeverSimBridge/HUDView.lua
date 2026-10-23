-- Combat HUD, part 2: the picture. The spells to press flow from right to left: the one to press now is the biggest, the
-- next ones follow smaller and fainter, the one just cast slides out on the left. No panel behind them. When a spell
-- lights up (proc) it takes over: it grows, glows and everything else shrinks away until it is used.
-- Pure display: it never casts, never touches secure frames and only reads through HUDLogic.lua.
local HUD=ForeverSimHUD
local UI=ForeverSimUI or{}
local COLOR=UI.COLOR or{gold={.953,.78,.357},text={1,1,1},muted={.6,.65,.75}}
local function now()return GetTime and GetTime()or 0 end

-- Where each item rests ---------------------------------------------------------------------------------------------------
local NEXT_X={170,300,410,505,590}
local NEXT_SIZE={64,56,50,46,42}
local NEXT_ALPHA={.85,.6,.38,.22,.12}
local HERO_X={215,300,375,440,495}
local HERO_SIZE={44,40,36,32,30}
local HERO_ALPHA={.45,.32,.2,.12,.08}
local PAST={{x=-150,size=56,alpha=.35},{x=-250,size=46,alpha=.15}}
local HERO_PAST={{x=-190,size=38,alpha=.25},{x=-260,size=32,alpha=.1}}
-- Position, size and opacity of the queue item `index` (1 = press now). hero: a proc is lit up.
function HUD.Layout(index,hero)
 if index==1 then return hero and{x=0,size=150,alpha=1}or{x=0,size=104,alpha=1}end
 local k=math.min(index-1,#NEXT_X)
 if hero then return{x=HERO_X[k],size=HERO_SIZE[k],alpha=HERO_ALPHA[k]}end
 return{x=NEXT_X[k],size=NEXT_SIZE[k],alpha=NEXT_ALPHA[k]}
end
function HUD.PastLayout(index,hero)
 local t=(hero and HERO_PAST or PAST)[index];return t and{x=t.x,size=t.size,alpha=t.alpha}or nil
end

-- Frames -------------------------------------------------------------------------------------------------------------------
local root=CreateFrame('Frame','ForeverSimCombatHUD',UIParent)
HUD.frame=root
root:SetSize(1000,230);root:SetPoint('BOTTOM',UIParent,'BOTTOM',0,167);root:SetFrameStrata('MEDIUM')
root:SetMovable(true);root:EnableMouse(false);root:Hide()
local MAX_CELLS=12
local cells={}
local function newCell(i)
 local c=CreateFrame('Frame',nil,root);c:SetSize(64,64);c:SetFrameLevel(root:GetFrameLevel()+2)
 c.rays=c:CreateTexture(nil,'BACKGROUND',nil,-2);c.glow=c:CreateTexture(nil,'BACKGROUND',nil,-1)
 if UI.SetArt then UI.SetArt(c.rays,'rays');UI.SetArt(c.glow,'glow')end
 c.rays:SetBlendMode('ADD');c.glow:SetBlendMode('ADD');c.rays:Hide();c.glow:Hide()
 c.edge=c:CreateTexture(nil,'BORDER');c.edge:SetColorTexture(COLOR.gold[1],COLOR.gold[2],COLOR.gold[3],.9)
 c.icon=c:CreateTexture(nil,'ARTWORK');c.icon:SetPoint('TOPLEFT',c,'TOPLEFT',1,-1);c.icon:SetPoint('BOTTOMRIGHT',c,'BOTTOMRIGHT',-1,1);c.icon:SetTexCoord(.07,.93,.07,.93)
 c.edge:SetPoint('TOPLEFT',c,'TOPLEFT',-1,1);c.edge:SetPoint('BOTTOMRIGHT',c,'BOTTOMRIGHT',1,-1)
 c.key=UI.Text and UI.Text(c,13,{1,1,1},'num','RIGHT')or c:CreateFontString(nil,'OVERLAY')
 c.key:SetPoint('BOTTOMRIGHT',c,'BOTTOMRIGHT',-4,3)
 c.name=UI.Text and UI.Text(c,15,COLOR.gold,'title','CENTER')or c:CreateFontString(nil,'OVERLAY')
 c.name:SetPoint('TOP',c,'BOTTOM',0,-10);c.name:SetWidth(300)
 c.delay=UI.Text and UI.Text(c,13,{1,.82,.2},'num','CENTER')or c:CreateFontString(nil,'OVERLAY')
 c.delay:SetPoint('BOTTOM',c,'TOP',0,6)
 c:Hide();return c
end
for i=1,MAX_CELLS do cells[i]=newCell(i)end

-- the handle to place the HUD (only while it is unlocked)
local handle=root:CreateTexture(nil,'BACKGROUND');handle:SetAllPoints();handle:SetColorTexture(.95,.78,.36,.08);handle:Hide()
local handleText=UI.Text and UI.Text(root,12,COLOR.gold,'body','CENTER')or root:CreateFontString(nil,'OVERLAY')
handleText:SetPoint('TOP',root,'TOP',0,-6);handleText:SetText('ForeverSim · Kampf-HUD · ziehen zum Verschieben');handleText:Hide()

-- Slots: one per spell on the way through the queue ----------------------------------------------------------------------------
local slots={}      -- queue order
local past={}       -- the spells just cast, newest first
local dying={}      -- fading out
local lastCastAt=-10
local function freeCell()
 for _,c in ipairs(cells)do if not c.used then c.used=true;return c end end
end
local function release(slot)if slot.cell then slot.cell.used=false;slot.cell:Hide();slot.cell.rays:Hide();slot.cell.glow:Hide()end end
local function targetOf(slot,t)slot.tx,slot.tsize,slot.talpha=t.x,t.size,t.alpha end
local function startSlot(it)
 local cell=freeCell();if not cell then return nil end
 local s={id=it.id,cell=cell,x=640,size=40,alpha=0,tx=640,tsize=40,talpha=0}
 cell:Show();return s
end
-- Matches the new queue with the slots on screen so a spell that stays in the queue glides instead of jumping.
local function assign(items)
 local old=slots;local taken={};local out={};local last=0
 for i,it in ipairs(items)do
  local found
  for j=last+1,#old do if not taken[j]and old[j].id==it.id then found=j;break end end
  if found then taken[found]=true;last=found;out[#out+1]=old[found]
  else
   local fresh=startSlot(it)
   -- no free cell: the queue ends here (the slots stay dense, so every loop sees all of them)
   if not fresh then for k=#items,i,-1 do items[k]=nil end;break end
   out[#out+1]=fresh
  end
 end
 -- the spell that was first in the queue and is gone because it was cast: it slides out to the left
 for j,s in ipairs(old)do
  if not taken[j]then
   if j==1 and now()-lastCastAt<1.5 then
    table.insert(past,1,s)
    while #past>2 do local drop=table.remove(past);drop.dead=true;dying[#dying+1]=drop end
   else s.dead=true;dying[#dying+1]=s end
  end
 end
 slots=out
end

-- Painting ----------------------------------------------------------------------------------------------------------------------
local pulseT=0
local function paintSlot(slot,it,hero,index)
 local c=slot.cell
 slot.it=it
 c.icon:SetTexture(it.icon)
 local isNow=index==1
 local waiting=it.state=='wait'
 c.icon:SetVertexColor(waiting and .7 or 1,waiting and .7 or 1,waiting and .7 or 1)
 local cfg=HUD.Config()
 local key=cfg.showKeys and HUD.KeyFor(it)or nil
 c.key:SetText(key or'')
 if c.key.SetFont and UI.FONT then pcall(c.key.SetFont,c.key,UI.FONT.num,isNow and(hero and 24 or 17)or 12,'')end
 if isNow and cfg.showNames then c.name:SetText(hero and(it.name or'')or'');c.name:Show()else c.name:SetText('');c.name:Hide()end
 if waiting and it.delay and it.delay>0 then c.delay:SetText('in '..string.format('%.1f',it.delay):gsub('%.',',')..' s');c.delay:Show()else c.delay:SetText('');c.delay:Hide()end
 local proc=hero and isNow
 local pc=cfg.procColor or COLOR.gold
 if proc then c.edge:SetColorTexture(1,.95,.62,1)
 elseif isNow then c.edge:SetColorTexture(pc[1],pc[2],pc[3],.95)
 else c.edge:SetColorTexture(COLOR.gold[1],COLOR.gold[2],COLOR.gold[3],.55)end
 UI.Show(c.glow,proc);UI.Show(c.rays,proc)
 c.proc=proc
end

local function stepSlot(slot,dt)
 local k=math.min(1,dt*13)
 slot.x=slot.x+(slot.tx-slot.x)*k;slot.size=slot.size+(slot.tsize-slot.size)*k;slot.alpha=slot.alpha+(slot.talpha-slot.alpha)*k
 local c=slot.cell;if not c then return end
 c:ClearAllPoints();c:SetPoint('CENTER',root,'CENTER',slot.x,10)
 local s=math.max(8,slot.size);c:SetSize(s,s);c:SetAlpha(math.max(0,math.min(1,slot.alpha)))
 if c.proc then
  local g=s*2.1;c.glow:ClearAllPoints();c.glow:SetPoint('CENTER',c,'CENTER',0,0);c.glow:SetSize(g,g)
  c.glow:SetVertexColor(1,.62,.15,.65+.35*math.sin(pulseT*9))
  local r=s*2.5;c.rays:ClearAllPoints();c.rays:SetPoint('CENTER',c,'CENTER',0,0);c.rays:SetSize(r,r)
  c.rays:SetVertexColor(1,.7,.2,.6)
  if c.rays.SetRotation then pcall(c.rays.SetRotation,c.rays,pulseT*.35)end
 end
end

-- The bar highlight (gold frame around the button of the spell to press) --------------------------------------------------------
local BAR_FRAMES={'ActionButton','MultiBarBottomLeftButton','MultiBarBottomRightButton','MultiBarRightButton','MultiBarLeftButton'}
local overlays,overlayFor={}, {}
local function overlayOn(button)
 for _,o in ipairs(overlays)do if o.anchor==button then return o end end
 local o=CreateFrame('Frame',nil,UIParent);o:SetFrameStrata('FULLSCREEN');o.anchor=button
 o.tex=o:CreateTexture(nil,'OVERLAY');o.tex:SetAllPoints();o.tex:SetTexture('Interface\\AddOns\\ForeverSimBridge\\Media\\FQGoldBorder')
 o:SetPoint('TOPLEFT',button,'TOPLEFT',-4,4);o:SetPoint('BOTTOMRIGHT',button,'BOTTOMRIGHT',4,-4);o:Hide()
 overlays[#overlays+1]=o;return o
end
HUD.OnKeysChanged=function()
 overlayFor={}
 if HUD.InCombat()then return end
 for _,frameName in ipairs(BAR_FRAMES)do for i=1,12 do
  local button=_G[frameName..i];local slot=button and type(button.action)=='number'and button.action or nil
  if slot and GetActionInfo then
   local ok,kind,id=pcall(GetActionInfo,slot)
   if ok and kind=='spell'and id and not overlayFor[id]then
    overlayFor[id]=overlayOn(button)
    local name=FUSLive and FUSLive.spellDisplay and FUSLive.spellDisplay(id)
    if type(name)=='string'and not overlayFor[name]then overlayFor[name]=overlayFor[id]end
   end
  end
 end end
end
local function highlight(it)
 for _,o in ipairs(overlays)do if o:IsShown()then o:Hide()end end
 if not it or not HUD.Config().barHighlight then return end
 local o=overlayFor[it.id]or(it.name and overlayFor[it.name])
 if o and o.anchor and(not o.anchor.IsVisible or o.anchor:IsVisible())then o:Show()end
end

-- State ------------------------------------------------------------------------------------------------------------------------
local fade={value=0,target=0}
local demo
-- A short demonstration (also to place and judge the HUD without a fight): kind 'normal' or 'proc'.
function HUD.Demo(kind,seconds)
 demo={kind=kind or'normal',until_=now()+(seconds or 6)}
 HUD.Refresh(true)
end
local function previewItems(n)
 local rows=HUD.Rows();local items={}
 local fallback={133,116,2136,2948,12051,5143}
 for i=1,n do
  local id=rows[i]and rows[i].spellId or fallback[i]
  local name,icon;if FUSLive and FUSLive.spellDisplay then name,icon=FUSLive.spellDisplay(id)end
  items[i]={id=id,icon=icon or'Interface\\Icons\\INV_Misc_QuestionMark',name=name or('Zauber '..id),state='ready',delay=0}
 end
 if n>=3 then items[3].state='wait';items[3].delay=1.8 end
 return items
end
-- What is shown now; nil when nothing is to be shown.
local function current(cfg)
 if demo then
  if now()>demo.until_ then demo=nil
  else
   local items=previewItems(cfg.queue+1);if demo.kind=='proc'then items[1].proc=true;items[1].since=now()end
   return{items=items,proc=demo.kind=='proc',demo=true}
  end
 end
 if not cfg.enabled then return nil end
 if HUD.InCombat()then
  local cur=HUD.Current();if #cur.items>0 then return cur end
  return nil
 end
 if not cfg.locked then return{items=previewItems(cfg.queue+1),proc=false,preview=true}end
 return nil
end

local lastProc=false
function HUD.Refresh(force)
 local cfg=HUD.Config();local cur=current(cfg)
 if not cur then
  fade.target=0;highlight(nil)
  if fade.value<=0.01 then
   for _,s in ipairs(slots)do release(s)end;slots={};for _,s in ipairs(past)do release(s)end;past={}
   for _,s in ipairs(dying)do release(s)end;dying={};lastProc=false
  end
  return
 end
 fade.target=1;if not root:IsShown()then root:Show()end
 local items,hero=cur.items,cur.proc==true
 if not cur.demo and not cur.preview then HUD.lastItems=items end
 assign(items)
 for i,it in ipairs(items)do
  local slot=slots[i]
  if slot then paintSlot(slot,it,hero,i);targetOf(slot,HUD.Layout(i,hero))end
 end
 for k,slot in ipairs(past)do
  local t=HUD.PastLayout(k,hero)
  if t then targetOf(slot,t);slot.cell.proc=false;slot.cell.glow:Hide();slot.cell.rays:Hide();slot.cell.name:Hide();slot.cell.key:SetText('');slot.cell.delay:Hide()
  else slot.dead=true;dying[#dying+1]=slot end
 end
 for k=#past,1,-1 do if past[k].dead then table.remove(past,k)end end
 highlight(items[1])
 if hero and not lastProc then
  if cfg.procSound and PlaySound then pcall(PlaySound,SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)end
 end
 lastProc=hero
end

HUD.OnCasted=function(id)lastCastAt=now();if HUD.frame:IsShown()then HUD.Refresh()end end
HUD.OnProc=function()if HUD.frame:IsShown()then HUD.Refresh()end end
HUD.OnCombat=function(entering)
 -- an unlocked HUD must never take clicks away from the world during a fight
 if entering then root:EnableMouse(false);handle:Hide();handleText:Hide()else HUD.Apply()end
 HUD.Refresh()
end

-- Placement and settings ---------------------------------------------------------------------------------------------------------
function HUD.Apply()
 local cfg=HUD.Config()
 root:SetScale(math.max(.5,math.min(1.8,tonumber(cfg.scale)or 1)))
 if cfg.x and cfg.y then root:ClearAllPoints();root:SetPoint('CENTER',UIParent,'CENTER',cfg.x,cfg.y)end
 local free=not cfg.locked
 root:EnableMouse(free);UI.Show(handle,free);UI.Show(handleText,free)
 HUD.Refresh()
end
function HUD.SetLocked(on)
 if HUD.InCombat()then return false end
 HUD.Config().locked=on and true or false;HUD.Apply();return true
end
function HUD.ResetPosition()
 if HUD.InCombat()then return false end
 local cfg=HUD.Config();cfg.x,cfg.y=nil,nil;root:ClearAllPoints();root:SetPoint('BOTTOM',UIParent,'BOTTOM',0,167);return true
end
root:RegisterForDrag('LeftButton')
root:SetScript('OnDragStart',function(self)if not HUD.Config().locked and not HUD.InCombat()then self:StartMoving()end end)
root:SetScript('OnDragStop',function(self)
 self:StopMovingOrSizing()
 local x,y=self:GetCenter();local ux,uy=UIParent:GetCenter()
 if x and ux then local cfg=HUD.Config();local s=self:GetScale();if not s or s<=0 then s=1 end;cfg.x,cfg.y=(x*s-ux)/s,(y*s-uy)/s end
end)

-- a frame that is always shown drives the HUD (the HUD frame itself is hidden between fights)
local driver=CreateFrame('Frame')
local tick=0
driver:SetScript('OnUpdate',function(_,dt)
 pulseT=pulseT+dt
 -- fade of the whole HUD
 local speed=fade.target>fade.value and 1/.18 or 1/.22
 if fade.value<fade.target then fade.value=math.min(fade.target,fade.value+dt*speed)else fade.value=math.max(fade.target,fade.value-dt*speed)end
 root:SetAlpha(math.max(0,math.min(1,HUD.Config().alpha or 1))*fade.value)
 tick=tick+dt
 if tick>=.1 then tick=0;HUD.Refresh()end
 for _,s in ipairs(slots)do stepSlot(s,dt)end
 for _,s in ipairs(past)do stepSlot(s,dt)end
 for i=#dying,1,-1 do
  local s=dying[i];s.talpha=0;stepSlot(s,dt)
  if s.alpha<=.02 then release(s);table.remove(dying,i)end
 end
 if fade.value<=0 and fade.target==0 and root:IsShown()and not(HUD.Config().locked==false)then root:Hide()end
end)

local boot=CreateFrame('Frame')
boot:RegisterEvent('PLAYER_LOGIN');boot:RegisterEvent('ADDON_LOADED')
boot:SetScript('OnEvent',function(self,event,name)
 if event=='ADDON_LOADED'and name~='ForeverSimBridge'then return end
 HUD.Apply();if event=='PLAYER_LOGIN'then HUD.RebuildKeys()end
end)
HUD.Apply()
