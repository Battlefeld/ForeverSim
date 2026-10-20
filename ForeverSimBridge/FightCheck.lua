-- Fight check: after a boss fight a small panel says how the rotation went. Only what the game lets an addon read is used:
-- our own casts, the glow events of procs and the clock. How much damage was done is shown only when the game's own
-- damage meter hands it over (C_DamageMeter); the combat log is not needed and not used.
ForeverSimFight=ForeverSimFight or{}
local FC=ForeverSimFight
local HUD=ForeverSimHUD
local UI=ForeverSimUI or{}
local COLOR=UI.COLOR or{gold={.953,.78,.357},text={1,1,1},muted={.6,.65,.75},good={.3,.9,.4},bad={1,.42,.35}}
local function now()return GetTime and GetTime()or 0 end
local GCD=1.5
local fight

-- Summary ------------------------------------------------------------------------------------------------------------------
-- fight: {name,start,finish,success,counted,followed,idle,procs={{id,at,hideAt,casts={...}}}} -> numbers for the panel
function FC.Summarize(f)
 local duration=math.max(0,(f.finish or now())-f.start)
 local out={name=f.name,duration=duration,success=f.success,counted=f.counted,followed=f.followed,idle=f.idle}
 out.followedPct=f.counted>0 and math.floor(100*f.followed/f.counted+.5)or nil
 local total,used,missed=0,0,{}
 for _,p in ipairs(f.procs)do
  total=total+1
  local hideAt=p.hideAt or f.finish or now()
  local hit=false
  for _,t in ipairs(p.casts)do if t>=p.at-.2 and t<=hideAt+1.0 then hit=true;break end end
  if hit then used=used+1 else missed[#missed+1]={id=p.id,at=p.at-f.start}end
 end
 out.procTotal,out.procUsed,out.missed=total,used,missed
 return out
end
local function clock(sec)sec=math.max(0,math.floor(sec+.5));return string.format('%d:%02d',math.floor(sec/60),sec%60)end
FC.Clock=clock

-- the damage per second of the player in the game's damage meter, when it can be read
function FC.ReadDps()
 local dm=C_DamageMeter;if not dm or not dm.GetCombatSessionFromType or not Enum or not Enum.DamageMeterSessionType or not Enum.DamageMeterType then return nil end
 local ok,session=pcall(dm.GetCombatSessionFromType,Enum.DamageMeterSessionType.Current,Enum.DamageMeterType.Dps)
 if not ok or type(session)~='table'or(FUSLive and FUSLive.isProtected and FUSLive.isProtected(session))then return nil end
 local function protected(v)return FUSLive and FUSLive.isProtected and FUSLive.isProtected(v)or false end
 local function read()
  local sources=session.combatSources
  if protected(sources)or type(sources)~='table'then return nil end
  for _,src in ipairs(sources)do
   if not protected(src)and type(src)=='table'then
    local mine=src.isLocalPlayer
    if not protected(mine)and mine==true then
     local raw=src.amountPerSecond;local v
     if FUSLive and FUSLive.publicNumber then v=FUSLive.publicNumber(raw)
     elseif not protected(raw)and type(raw)=='number'then v=raw end
     if v and v>0 then return v end
    end
   end
  end
 end
 local readable,value=pcall(read);return readable and value or nil
end

-- Collecting ------------------------------------------------------------------------------------------------------------------
local rowIds
local function rebuildRows()rowIds={};for _,r in ipairs((HUD.Rows()))do if r.spellId then rowIds[r.spellId]=true end end end
function FC.Start(name)
 rebuildRows()
 fight={name=name or'Boss',start=now(),counted=0,followed=0,idle=0,procs={},open={}}
end
function FC.Active()return fight~=nil end
local function suggestion()
 local items=HUD.lastItems;return items and items[1],items and items[2]
end
function FC.OnCastStart(id)
 if not fight then return end
 local top,second=suggestion();fight.startSnap={id=id,top=top,second=second,at=now()}
end
function FC.OnCast(id)
 if not fight then return end
 local t=now()
 for _,p in ipairs(fight.procs)do if p.id==id then p.casts[#p.casts+1]=t end end
 if rowIds and rowIds[id]then
  local snap=fight.startSnap;local top,second
  if snap and snap.id==id and t-snap.at<12 then top,second=snap.top,snap.second else top,second=suggestion()end
  fight.startSnap=nil
  if top then
   fight.counted=fight.counted+1
   if top.id==id or(top.state=='wait'and second and second.id==id)then fight.followed=fight.followed+1 end
  end
 end
 if fight.lastCast then
  local gap=t-fight.lastCast;local expected=math.max(GCD,HUD.CastSeconds and HUD.CastSeconds(id)or 0)
  if gap>expected+.6 then fight.idle=fight.idle+(gap-expected)end
 end
 fight.lastCast=t
end
function FC.OnGlow(id,on)
 if not fight or not id then return end
 if on then
  if fight.open[id]then return end
  local p={id=id,at=now(),casts={}};fight.procs[#fight.procs+1]=p;fight.open[id]=p
 else
  local p=fight.open[id];if p then p.hideAt=now();fight.open[id]=nil end
 end
end

-- The panel ----------------------------------------------------------------------------------------------------------------------
local panel
local function build()
 local f=CreateFrame('Frame','ForeverSimFightCheck',UIParent);f:SetSize(430,300);f:SetFrameStrata('HIGH');f:SetPoint('RIGHT',UIParent,'RIGHT',-50,120)
 f:EnableMouse(true);f:Hide()
 if UI.Style then UI.Style(f,'panel','BACKGROUND')end
 f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetSize(34,34);f.icon:SetPoint('TOPLEFT',f,'TOPLEFT',30,-38)
 if UI.SetArt then UI.SetArt(f.icon,'crystal_on')end
 f.title=UI.Text(f,17,COLOR.gold,'title','LEFT');f.title:SetPoint('TOPLEFT',f.icon,'TOPRIGHT',10,2)
 f.sub=UI.Text(f,12,COLOR.muted,'body','LEFT');f.sub:SetPoint('TOPLEFT',f.title,'BOTTOMLEFT',0,-2)
 f.big=UI.Text(f,30,{1,1,1},'title','LEFT');f.big:SetPoint('TOPLEFT',f,'TOPLEFT',32,-88)
 f.bigNote=UI.Text(f,13,COLOR.muted,'body','LEFT');f.bigNote:SetPoint('LEFT',f.big,'RIGHT',10,-3)
 f.bar=UI.Bar and UI.Bar(f,360,10)or nil
 if f.bar then f.bar:SetPoint('TOPLEFT',f,'TOPLEFT',32,-128)end
 f.rows={}
 for i=1,4 do
  local l=UI.Text(f,13,COLOR.text,'body','LEFT');l:SetPoint('TOPLEFT',f,'TOPLEFT',32,-150-(i-1)*24)
  local v=UI.Text(f,13,COLOR.text,'num','RIGHT');v:SetPoint('TOPRIGHT',f,'TOPRIGHT',-34,-150-(i-1)*24)
  f.rows[i]={label=l,value=v}
 end
 f.note=UI.Text(f,12.5,COLOR.bad,'body','LEFT');f.note:SetPoint('TOPLEFT',f,'TOPLEFT',32,-252);f.note:SetWidth(360)
 f.foot=UI.Text(f,11,COLOR.muted,'body','LEFT');f.foot:SetPoint('BOTTOMLEFT',f,'BOTTOMLEFT',32,22);f.foot:SetText('blendet nach 10 s aus')
 f.close=UI.Button and UI.Button(f,'Schließen',{w=110,h=34,size=12,style='buttonActive',color=COLOR.gold})or nil
 if f.close then f.close:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-26,16);f.close:SetScript('OnClick',function()f:Hide()end)end
 f:SetScript('OnUpdate',function(self,dt)
  if MouseIsOver and MouseIsOver(self)then self.shownAt=self.shownAt and(self.shownAt+dt)or now();return end
  if now()-(self.shownAt or now())>10 then self:Hide()end
 end)
 return f
end
local function pct(x)return string.format('%d %%',math.floor(x+.5))end
function FC.Show(s)
 panel=panel or build()
 panel.shownAt=now()
 panel.title:SetText(s.success and'Kampf vorbei'or'Kampf nicht geschafft')
 panel.sub:SetText(tostring(s.name or'')..' · '..clock(s.duration))
 local dps=s.dps;local sim=s.simDps
 local rows={}
 if dps then
  panel.big:SetText(UI.FormatDps and UI.FormatDps(dps)or tostring(math.floor(dps)))
  panel.bigNote:SetText(sim and('DPS · Sim für deinen Build '..(UI.FormatDps and UI.FormatDps(sim)or tostring(math.floor(sim))))or'DPS')
  if sim and sim>0 then rows[#rows+1]={'Erreicht',pct(100*dps/sim),dps>=sim*.9 and COLOR.good or COLOR.bad}end
  if panel.bar then panel.bar:SetFraction(sim and sim>0 and math.min(1,dps/sim)or 0,COLOR.gold);panel.bar:Show()end
 else
  panel.big:SetText(s.followedPct and pct(s.followedPct)or'–')
  panel.bigNote:SetText('Rotation gefolgt')
  if panel.bar then panel.bar:SetFraction((s.followedPct or 0)/100,COLOR.gold);panel.bar:Show()end
 end
 if dps and s.followedPct then rows[#rows+1]={'Rotation gefolgt',pct(s.followedPct),COLOR.text}end
 if s.procTotal>0 then rows[#rows+1]={'Procc genutzt',s.procUsed..' / '..s.procTotal,s.procUsed<s.procTotal and COLOR.bad or COLOR.good}end
 rows[#rows+1]={'Ohne Zauber',string.format('%.1f',s.idle):gsub('%.',',')..' s',s.idle>6 and COLOR.bad or COLOR.text}
 for i,r in ipairs(panel.rows)do
  local d=rows[i]
  if d then r.label:SetText(d[1]);r.value:SetText(d[2]);r.value:SetTextColor(d[3][1],d[3][2],d[3][3],1);r.label:Show();r.value:Show()
  else r.label:Hide();r.value:Hide()end
 end
 local m=s.missed and s.missed[1]
 if m then
  local name=FUSLive and FUSLive.spellDisplay and FUSLive.spellDisplay(m.id)
  panel.note:SetText((name or('Zauber '..m.id))..'-Procc verpasst · '..clock(m.at))
 else panel.note:SetText('')end
 panel:Show()
end
function FC.Hide()if panel then panel:Hide()end end

function FC.Finish(name,success)
 local f=fight;fight=nil
 if not f then return nil end
 f.finish=now();f.success=success
 local s=FC.Summarize(f)
 if s.duration<10 or(s.counted<3 and s.procTotal==0)then return s end   -- too short to say anything
 local dps=FC.ReadDps();s.dps=dps
 local C=ForeverCoreClient;local live=C and C.Sim and C.Sim.Result('live');s.simDps=live and not(C.Sim.IsStale and C.Sim.IsStale(live))and tonumber(live.dps)or nil
 if not(HUD.Config().fightCheck==false)then FC.Show(s)end
 FC.last=s
 return s
end

HUD.On('encounterStart',function(_,name)FC.Start(name)end)
HUD.On('encounterEnd',function(_,name,success)FC.Finish(name,success)end)
HUD.On('castStart',FC.OnCastStart)
HUD.On('cast',FC.OnCast)
HUD.On('glow',FC.OnGlow)
