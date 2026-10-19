-- ForeverSimBridge: source-based, graphical talent planning drafts.
-- No character talent changes; no implicit modification of Combat Engine inputs.
local P=_G.FUSLive
if not P then return end
local T={};P.talentPlannerUI=T
local classes={'warlock','mage','shaman','warrior','paladin','rogue','druid','priest','hunter'}
local classLabel={warlock='Hexenmeister',mage='Magier',shaman='Schamane',warrior='Krieger',paladin='Paladin',rogue='Schurke',druid='Druide',priest='Priester',hunter='Jaeger'}
local C={gold={.94,.76,.44},white={.92,.93,.94},pale={.70,.75,.80},blue={.43,.73,1},green={.38,.86,.58},purple={.78,.55,.98},warn={1,.57,.40}}
local root='Interface\\AddOns\\ForeverSimBridge\\Media\\'
local frame
local columns,sideButtons={},{}
local caption,description,liveCaption,closeButton
local embeddedParent=nil
local liveRecords,liveRanks,liveStatus={}, {}, {state='incomplete',message='Live-Talente noch nicht gelesen'}
local liveClass,liveLevel=nil,nil
local plannerMessage=nil;local previewStatus=nil;local previewToken=0;local previewBusy=false
local chosen='warlock';local chosenTalent=nil;local lastSource=nil;local fOpened=false
local function isCombat()return InCombatLockdown and InCombatLockdown()end
local function text(parent,x,y,w,font,s,color)
 local f=parent:CreateFontString(nil,'OVERLAY',font>=18 and 'GameFontNormalLarge' or 'GameFontNormal')
 f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetJustifyV('TOP');f:SetWordWrap(true)
 f:SetTextColor(unpack(color or C.white));f:SetText(s or '');return f
end
local function box(parent,x,y,w,h,heading)
 local b=CreateFrame('Frame',nil,parent,'BackdropTemplate');b:SetSize(w,h);b:SetPoint('TOPLEFT',x,y)
 b:SetBackdrop({bgFile=root..'FQDark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 b:SetBackdropColor(.035,.049,.082,.98);b:SetBackdropBorderColor(.52,.41,.26,.88)
 if heading then text(b,14,-11,w-28,16,heading,C.gold)end
 return b
end
local function button(parent,x,y,w,h,title,fn)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,h);b:SetPoint('TOPLEFT',x,y);b:SetText(title)
 b:SetScript('OnClick',function()if not isCombat()then fn()end end);return b
end
local function model()return FUSLiveData and FUSLiveData[chosen]end
local function classKey()
 local _,key
 if type(UnitClass)=='function' then _,key=UnitClass('player') end
 return type(key)=='string' and string.lower(key) or nil
end
function T.ReadLive()
 if isCombat()then return end
 liveClass=classKey();liveLevel=UnitLevel and UnitLevel('player') or nil
 if P.talentSnapshotAdapter then
  local ok,records,status=pcall(P.talentSnapshotAdapter.Capture,liveClass,liveLevel)
  if ok and type(records)=='table' and type(status)=='table' then liveRecords=records;liveStatus=status
  else liveRecords={};liveStatus={state='incomplete',message='Live-Talentprofil konnte nicht gelesen werden'}end
 else liveRecords={};liveStatus={state='incomplete',message='Talent-Snapshot-Adapter fehlt'}end
 liveRanks={}
 for _,tree in ipairs(liveRecords)do for _,entry in ipairs(tree.entries or {})do
  if entry.classKey then liveRanks[entry.classKey]=entry.rank end
 end end
 T.Refresh()
end
local function config()
 ForeverSimBridgeDB=ForeverSimBridgeDB or {}
 ForeverSimBridgeDB.talentPlannerDrafts=ForeverSimBridgeDB.talentPlannerDrafts or {}
 local drafts=ForeverSimBridgeDB.talentPlannerDrafts
 if type(drafts[chosen])~='table' then drafts[chosen]={ranks={}}end
 if type(drafts[chosen].ranks)~='table' then drafts[chosen].ranks={}end
 return drafts[chosen]
end
local function treeGroups()
 local data=model()
 local defs=data and data.talentDefinitions or {}
 local byKey={}
 for _,def in ipairs(defs) do if def.key then byKey[def.key]=def end end
 local all=data and data.talentTrees or nil
 local groups={}
 for _,tree in ipairs(all or {})do
  local g={name=tree.name,positioned=true,defs={}}
  for _,position in ipairs(tree.talents or {}) do
   local source=byKey[position.key]
   -- Read canonical geometry from the class module; only the draft is writable.
   local d={}
   if source then for k,v in pairs(source)do d[k]=v end end
   d.key=position.key;d.name=position.name or d.name or d.key
   d.tree=tree.name;d.row=position.row;d.column=position.column
   d.id=position.spellId or d.id;d.maxRank=position.maxRank or d.maxRank
   d.prereqKey=position.prereqKey
   d.source=source and source.source or position.source or data.talentTreeSource
   d.supported=source and source.supported
   d.modelAvailable=(source~=nil) and position.modelAvailable~=false
   g.defs[#g.defs+1]=d
  end
  groups[#groups+1]=g
 end
 return groups,(#groups==3)
end
local function draftPoints()
 local groups=treeGroups();local total=0
 for _,g in ipairs(groups)do for _,d in ipairs(g.defs)do
  local n=tonumber(config().ranks[d.key]) or 0
  total=total+math.max(0,math.min(tonumber(d.maxRank) or 1,n))
 end end
 return total
end
local function isValidDraft()
 local data=model()
 if P.talentBuild and data then
  return P.talentBuild.validate(data,config().ranks)
 end
 return false,'Talentpruefung nicht geladen'
end
local function resetPreview()
 previewToken=previewToken+1;previewStatus=nil;previewBusy=false
end
local function tentativeCoverage(d)
 local data=model()
 if not d or not data then return '' end
 local reference=P.talentBuild and P.talentBuild.ruleReferences(data)
 if reference and reference[d.key] then return 'Kampfregel im Modul referenziert; einzelner Effekt nicht vollstaendig validiert' end
 return 'Kein direkter deklarativer Effektbeleg; ggf. nur passiv oder nicht modelliert'
end

local function iconFor(d)
 local id=d and ((type(d.spellIds)=='table' and d.spellIds[1])or d.id)
 if type(id)~='number' then return 'Interface\\Icons\\INV_Misc_QuestionMark' end
 if C_Spell and type(C_Spell.GetSpellTexture)=='function' then
  local ok,ret=pcall(C_Spell.GetSpellTexture,id)
  if ok and ret then return ret end
 end
 if C_Spell and type(C_Spell.GetSpellInfo)=='function' then
  local ok,ret=pcall(C_Spell.GetSpellInfo,id)
  if ok and type(ret)=='table' and ret.iconID then return ret.iconID end
 end
 return 'Interface\\Icons\\INV_Misc_QuestionMark'
end
local function detailText(d)
 if not d then return 'Talent auswählen, um Quelle, Modellabdeckung und Planung zu sehen.'end
 local draft=config();local n=tonumber(draft.ranks[d.key] or 0)or 0
 local refs=P.talentBuild and P.talentBuild.ruleReferences(model())
 local covered=d.modelAvailable==false and 'keine Talentdefinition' or (refs and refs[d.key]and 'Direktregel referenziert (Teilmodell)' or 'keine direkte Effektregel belegt')
 local source=tostring(d.source or 'keine Einzelquelle im Modul'):gsub('^https?://','')
 if #source>50 then source=source:sub(1,47)..'...' end
 return tostring(d.name or d.key)..'  ·  Entwurf '..n..'/'..tostring(d.maxRank or '?')..'\n'
 ..(chosen==liveClass and ('Live: '..tostring(liveStatus.state=='valid' and (liveRanks[d.key]or 0) or '?')..'/'..tostring(d.maxRank or '?')..'  ·  ')or '')
 ..tostring(d.tree)..' · Reihe '..tostring((d.row or 0)+1)..', Spalte '..tostring((d.column or 0)+1)..'\n'
 ..'Modell: '..covered..'\nQuelle: '..source
end
local function selectedRank(d)
 local n=tonumber(config().ranks[d.key]) or 0
 return math.max(0,math.min(tonumber(d.maxRank)or 1,n))
end
local function mutate(d,delta)
 local draft=config();local key=d.key
 if type(key)~='string' then return end
 local previous=tonumber(draft.ranks[key]) or 0
 local limit=tonumber(d.maxRank) or 1
 local nextRank=math.min(limit,math.max(0,previous+delta))
 if nextRank==previous then return end
 draft.ranks[key]=nextRank
 local valid,reason=isValidDraft()
 if not valid then draft.ranks[key]=previous;plannerMessage=reason
 else plannerMessage=nil;chosenTalent=d;resetPreview() end
 T.Refresh()
end
local function tooltipFor(btn)
 local d=btn.data
 if not d or not GameTooltip then return end
 GameTooltip:SetOwner(btn,'ANCHOR_RIGHT')
 GameTooltip:SetText(tostring(d.name or d.key),.95,.79,.48)
 GameTooltip:AddLine('Entwurf '..selectedRank(d)..'/'..tostring(d.maxRank or '?'),.55,.85,.99)
 if chosen==liveClass then GameTooltip:AddLine('Live '..tostring(liveStatus.state=='valid' and (liveRanks[d.key]or 0)or '?')..'/'..tostring(d.maxRank or '?'),.55,.9,.65)end
 GameTooltip:AddLine('Links +1, Rechts -1 (nur Planung)',.64,.82,.92)
 GameTooltip:AddLine('Reihe '..tostring(d.row+1)..', Spalte '..tostring(d.column+1),.7,.8,.88)
 if d.prereqKey then GameTooltip:AddLine('Voraussetzung: '..tostring(d.prereqKey)..' (voller Rang)',.9,.72,.52,true)end
 GameTooltip:AddLine('Quelle: '..tostring(d.source or 'keine Einzelquelle'),.73,.73,.68,true)
 GameTooltip:Show()
end
local function build(parent)
 if frame then return end
 local f=CreateFrame('Frame','ForeverSimTalentPlanner',parent or UIParent,'BackdropTemplate');frame=f;T.frame=f
 f:SetSize(1155,796);f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true);f:SetMovable(true);f:EnableMouse(true)
 f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',function(self)if not isCombat()then self:StartMoving()end end)
 f:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
 f:SetBackdrop({bgFile=root..'FQDark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
 f:SetBackdropColor(.025,.034,.060,.985);f:SetBackdropBorderColor(.78,.55,.28,.98)
 text(f,20,-14,985,25,'FOREVER SIM  /  TALENT-STUDIO',C.gold)
 liveCaption=text(f,22,-51,1085,14,'LIVE & ENTWURF  ·  L = Live-Rang, E = Entwurfsrang  ·  nur lokale Planung',C.blue)
 local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');closeButton=close;close:SetPoint('TOPRIGHT',-10,-10);close:SetScript('OnClick',function()f:Hide()end)
 local side=box(f,13,-87,173,601,'KLASSE')
 for i,key in ipairs(classes)do
  sideButtons[key]=button(side,9,-44-(i-1)*55,153,42,classLabel[key],function()chosen=key;chosenTalent=nil;resetPreview();T.Refresh()end)
 end
 button(side,9,-551,153,33,'Live erneut lesen',function()T.ReadLive()end)
 for ci=1,3 do
  local p=box(f,196+(ci-1)*315,-87,305,493,'TALENTBAUM '..ci)
  columns[ci]={frame=p,title=text(p,15,-41,276,15,'',C.blue),info=text(p,65,-443,170,12,'',C.pale),pool={},page=1,links={}}
  for j=1,24 do local t=p:CreateTexture(nil,'BACKGROUND');t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(.80,.62,.32,.7);t:Hide();columns[ci].links[j]=t end
  for i=1,28 do
   local b=CreateFrame('Button',nil,p,'BackdropTemplate');b:SetSize(55,51)
   b:RegisterForClicks('LeftButtonUp','RightButtonUp')
   b:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=9,insets={left=3,right=3,top=3,bottom=3}})
   b:SetBackdropColor(.08,.11,.16,.85);b:SetBackdropBorderColor(.44,.36,.23,.83)
   local t=b:CreateTexture(nil,'ARTWORK');t:SetSize(36,36);t:SetPoint('TOP',0,-3);b.icon=t
   local rank=text(b,2,-33,51,12,'',C.gold);rank:SetJustifyH('CENTER');b.rank=rank
   b:SetScript('OnEnter',tooltipFor)
   b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
   b:SetScript('OnClick',function(self,mouse)
    if isCombat()then return end
    if self.data then mutate(self.data,mouse=='RightButton' and -1 or 1)end
   end)
   columns[ci].pool[i]=b
  end
  button(p,15,-441,40,24,'<',function()local col=columns[ci];col.page=math.max(1,col.page-1);T.Refresh()end)
  button(p,248,-441,40,24,'>',function()local col=columns[ci];col.page=col.page+1;T.Refresh()end)
 end
 local bottom=box(f,196,-591,935,187,'AUSWAHL & PLANENTWURF')
 description=text(bottom,15,-43,445,14,'',C.white)
 caption=text(f,204,-770,890,13,'',C.pale)
 button(bottom,15,-132,220,32,'Entwurf zurücksetzen',function()config().ranks={};chosenTalent=nil;resetPreview();T.Refresh()end)
 button(bottom,250,-132,215,32,'Entwurf als Text',function()T.Export()end)
 button(bottom,480,-97,436,31,'Entwurf mit Universal SIM vergleichen',function()T.Compare()end)
 button(bottom,480,-132,436,32,'Live-Build als Entwurf uebernehmen',function()T.UseLive()end)
 f:Hide();-- No writes to Blizzard UISpecialFrames (taint isolation).
end
local function ordered(g)
 local all={};for _,d in ipairs(g and g.defs or {})do all[#all+1]=d end
 if g and g.positioned then
  table.sort(all,function(a,b)
   if a.row~=b.row then return a.row<b.row end
   if a.column~=b.column then return a.column<b.column end
   return tostring(a.key)<tostring(b.key)
  end)
 end
 return all
end
function T.Refresh()
 if not frame or not frame:IsShown()then return end
 if embeddedParent then
  local w,h=embeddedParent:GetWidth(),embeddedParent:GetHeight()
  if w and h and w>0 and h>0 then frame:SetScale(math.max(.35,math.min(1,w/1155,h/796)))end
 end
 local groups,positioned=treeGroups()
 local draft=config();local count,total=draftPoints(),0
 for _,g in ipairs(groups)do total=total+#g.defs end
 for _,key in ipairs(classes)do
  if sideButtons[key] and sideButtons[key].SetText then sideButtons[key]:SetText((key==chosen and '» 'or'')..classLabel[key])end
 end
 for i,col in ipairs(columns)do
  local group=groups[i];local arr=ordered(group)
  local maxPages=math.max(1,math.ceil(#arr/28));col.page=math.min(col.page,maxPages)
  col.title:SetText(group and (group.name..'  ·  '..#arr..' Talente') or 'Keine Gruppendaten')
  for _,line in ipairs(col.links or {})do line:Hide()end
  local linkIndex=1
  if group then
   for _,d in ipairs(group.defs)do
    if d.prereqKey and linkIndex<=#col.links then
     local prev=nil
     for _,a in ipairs(group.defs)do if a.key==d.prereqKey then prev=a;break end end
     if prev and d.row>prev.row then
      local line=col.links[linkIndex];linkIndex=linkIndex+1
      local x=14+d.column*69+27
      local height=math.max(2,(d.row-prev.row)*51-51)
      line:ClearAllPoints();line:SetPoint('TOPLEFT',x-1,-81-prev.row*51-51)
      line:SetSize(3,height);line:Show()
     end
    end
   end
  end
  col.info:SetText('Seite '..col.page..'/'..maxPages..'  |  '..(group and group.positioned and 'Quellposition' or 'Alphabetisch gruppiert'))
  for j,cell in ipairs(col.pool)do
   local d=arr[(col.page-1)*28+j];cell.data=d;cell:SetShown(d~=nil)
   if d then
    local x,y
    if group.positioned and (tonumber(d.column)or 0)>=0 and (tonumber(d.column)or 0)<4 and (tonumber(d.row)or 0)>=0 and (tonumber(d.row)or 0)<7 then
     x=14+d.column*69;y=-81-d.row*51
    else
     local n=(j-1);x=14+(n%4)*69;y=-81-math.floor(n/4)*51
    end
    cell:ClearAllPoints();cell:SetPoint('TOPLEFT',x,y)
    local rank=chosen==liveClass and liveStatus.state=='valid' and tostring(liveRanks[d.key]or 0)or '?'
    cell.icon:SetTexture(iconFor(d));cell.rank:SetText('L'..rank..' E'..selectedRank(d))
    if cell.SetBackdropBorderColor then
     if selectedRank(d)>0 then cell:SetBackdropBorderColor(.34,.75,.42,1)
     elseif chosenTalent==d then cell:SetBackdropBorderColor(.96,.74,.39,1)
     else cell:SetBackdropBorderColor(.44,.36,.23,.83)end
    end
   end
  end
 end
 description:SetText(detailText(chosenTalent)..'\nGeplante Punkte: '..count..'/51  ·  Baumpositionen: '..total)
 local state='Aktuell';local valid,reason=isValidDraft()
 if not valid then state='Entwurf nicht vollstaendig simulierbar'
 elseif liveStatus.state~='valid' and chosen==liveClass then state='Entwurf nicht vollstaendig simulierbar'
 else
  if chosen~=liveClass then state='Entwurf fuer '..(classLabel[chosen]or chosen)
  else for _,group in ipairs(groups)do for _,d in ipairs(group.defs)do if selectedRank(d)~=(liveRanks[d.key]or 0)then state='Entwurf geaendert' end end end end
 end
 liveCaption:SetText('LIVE: '..(classLabel[liveClass]or liveClass or '?')..' · '..(liveStatus.state=='valid' and (tostring(liveStatus.points or 0)..' Punkte · '..tostring(liveStatus.source or 'Client'))or 'unvollstaendig')..'\n'..state..'  ·  L = Live, E = Entwurf')
 caption:SetText(previewStatus or plannerMessage or (not valid and tostring(reason))or (chosen==liveClass and liveStatus.state~='valid' and liveStatus.message)or (positioned and 'Forever-Beta-Talentbaeume · lokale Planung · Effektwerte koennen noch unvollstaendig sein.' or 'Baumpositionen fehlen; Quelle pruefen.'))
end
function T.UseLive()
 if isCombat()then return end
 if chosen~=liveClass then plannerMessage='Live-Build nur fuer die aktuell gespielte Klasse verfuegbar';T.Refresh();return end
 if liveStatus.state~='valid' then plannerMessage=liveStatus.message or 'Live-Talentprofil unvollstaendig';T.Refresh();return end
 local data=model()
 local ok,reason
 if P.talentBuild then ok,reason=P.talentBuild.validate(data,liveRanks,liveLevel)end
 if not ok then plannerMessage=reason or 'Live-Talente koennen nicht in den Entwurf uebernommen werden';T.Refresh();return end
 local ranks={};for key,rank in pairs(liveRanks)do ranks[key]=rank end
 config().ranks=ranks;plannerMessage=nil;resetPreview();T.Refresh()
end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
function T.Compare()
 if isCombat() then return end
 if previewBusy and T.previewRevision~=P.revision then previewBusy=false end
 if previewBusy then return end
 local current=classKey()
 if chosen~=current then previewStatus='Vorschau nur fuer die aktuell gespielte Klasse ('..tostring(current or '?')..').';T.Refresh();return end
 local required={'capture','normalizeSnapshot','combine','coverage','candidates','score','enqueue','copy'}
 for _,key in ipairs(required)do if type(P[key])~='function' then previewStatus='SIM-Funktion fehlt: '..key;T.Refresh();return end end
 if not P.talentBuild then previewStatus='Talent-Pruefmodul fehlt';T.Refresh();return end
 local okSnap,snap=pcall(P.capture,true)
 if not okSnap or not snap or (P.isProtected and P.isProtected(snap)) then previewStatus='Charakterprofil nicht auslesbar';T.Refresh();return end
 local okProfile,live=pcall(P.normalizeSnapshot,snap)
 if not okProfile or type(live)~='table' then previewStatus='Charakterprofil unvollstaendig';T.Refresh();return end
 local snapshotIssue=P.simulationIssue and P.simulationIssue(live)
 if not snapshotIssue and snap.talentSnapshotStatus and snap.talentSnapshotStatus.state~='valid' then snapshotIssue=snap.talentSnapshotStatus.message or 'Live-Talentprofil unvollstaendig' end
 if snapshotIssue then previewStatus='Entwurf nicht vollstaendig simulierbar: '..tostring(snapshotIssue);T.Refresh();return end
 local data=model();if not data then return end
 local draft,reason=P.talentBuild.profile(data,live,config().ranks)
 if not draft then previewStatus=tostring(reason);T.Refresh();return end
 local bookIssue=P.talentBuild.spellbookIssue(data,live,draft)
 if bookIssue then previewStatus=bookIssue;T.Refresh();return end
 local issue=P.coverage(data,live)or P.coverage(data,draft)
 if issue then previewStatus='SIM-Abdeckung: '..tostring(issue);T.Refresh();return end
 -- Compare on the SAME deliberately normalized base: the current client character sheet
 -- already contains live-talent effects and cannot simply be reused for a hypothetical build.
 local original=P.copy(live)
 if not data.typedCombat then
  -- Legacy classes can be evaluated from their neutral attribute template.
  original.stats={};draft.stats={}
 else
  -- Typed classes require the observed character sheet. Hold it identical on both
  -- sides; this is a directional model comparison, not a verified respec DPS.
  original.stats=P.copy(live.stats or {});draft.stats=P.copy(live.stats or {})
 end
 local okGear,stats=pcall(P.combine,original.equipped or {})
 if not okGear then previewStatus='Itemdaten: '..tostring(stats);T.Refresh();return end
 local okChoices,choices=pcall(P.candidates,data,original)
 if not okChoices or type(choices)~='table' or not choices[1] then previewStatus='Keine gemeinsame Startrotation verfuegbar';T.Refresh();return end
 local chosenRotation=P.copy(choices[1]);local token=previewToken+1
 previewToken=token;previewBusy=true;T.previewRevision=P.revision
 previewStatus='Talentvergleich laeuft in der SIM-Jobwarteschlange ...';T.Refresh()
 local ref=P.talentBuild.ruleReferences(data);local unknown=0
 for key,v in pairs(config().ranks)do if v>0 and not ref[key]then unknown=unknown+1 end end
 local snapshotRanks=P.copy(config().ranks)
 P.enqueue(function()
  local baseline=P.score(data,original,stats,chosenRotation,2,411)
  if P.checkpoint then P.checkpoint()end
  local candidate=P.score(data,draft,stats,chosenRotation,2,411)
  return {baseline=baseline,candidate=candidate,unreferenced=unknown,points=P.talentBuild.validate(data,snapshotRanks,live.level)}
 end,function(result,err)
  if token~=previewToken then return end
  previewBusy=false
  if err or not result or not finite(result.baseline)or not finite(result.candidate)or result.baseline<=0 then
   previewStatus='Talentvergleich nicht berechenbar: '..tostring(err or 'unvollstaendiges SIM-Ergebnis')
  else
   local pct=100*result.candidate/result.baseline
   previewStatus=string.format('SIM-VERGLEICH: %.1f%% zu aktuell (100%%), %.1f / %.1f DPS | %d Talente ohne Direktregel | Teilmodell; gleiche Rotation/%s',pct,result.candidate,result.baseline,result.unreferenced,data.typedCombat and 'fixer Charakterbogen' or 'neutrale Basis')
  end
  T.Refresh()
 end,function()return token==previewToken and T.previewRevision==P.revision end)
end
function T.Mount(parent)
 if isCombat()or not parent then return end
 local current=classKey();if not liveClass and current and classLabel[current]then chosen=current end
 build(parent);embeddedParent=parent
 frame:SetParent(parent);frame:SetFrameStrata('DIALOG');frame:SetFrameLevel(parent:GetFrameLevel()+1);frame:SetMovable(false)
 frame:SetScript('OnDragStart',nil);frame:SetScript('OnDragStop',nil)
 frame:ClearAllPoints();frame:SetPoint('TOPLEFT',parent,'TOPLEFT',0,0)
 if closeButton then closeButton:Hide()end
 frame:Show();T.ReadLive();T.Refresh();return frame
end
function T.Show(key)
 if isCombat() then return end
 if key and classLabel[key] then chosen=key end
 if P.app and type(P.app.Open)=='function' then P.app.Open('talents');T.Refresh();return end
 build();local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 frame:SetScale(math.max(.43,math.min(1,w*.96/1155,h*.91/796)))
 frame:ClearAllPoints();frame:SetPoint('CENTER',UIParent,'CENTER',0,0);frame:Show();T.ReadLive();T.Refresh()
end
function T.Export()
 if isCombat()then return end
 local draft=config();local lines={'FOREVER SIM · TALENTENTWURF','Klasse: '..(classLabel[chosen]or chosen),'Status: UNGEPRUEFTER PLAN · keine Talentpunkte im Spiel geaendert'}
 local groups=treeGroups()
 for _,g in ipairs(groups)do
  for _,d in ipairs(g.defs)do local n=selectedRank(d);if n>0 then lines[#lines+1]=tostring(g.name)..' / '..tostring(d.name or d.key)..': '..n..'/'..tostring(d.maxRank or '?')end end
 end
 if #lines==3 then lines[#lines+1]='(Keine geplanten Punkte)'end
 if not T.exportFrame then
  local holder=box(frame or UIParent,0,0,575,415,'ENTWURF ZUM KOPIEREN');holder:ClearAllPoints();holder:SetPoint('CENTER',frame or UIParent,'CENTER',0,0);holder:SetFrameStrata('FULLSCREEN_DIALOG')
  local close=CreateFrame('Button',nil,holder,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-3,-4);close:SetScript('OnClick',function()holder:Hide()end)
  local edit=CreateFrame('EditBox',nil,holder,'InputBoxTemplate');edit:SetSize(535,329);edit:SetPoint('TOPLEFT',18,-53);edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject('ChatFontNormal')
  edit:SetScript('OnEscapePressed',function(self)self:ClearFocus();holder:Hide()end)
  T.exportFrame=holder;T.exportEdit=edit
 end
 T.exportEdit:SetText(table.concat(lines,'\n'));T.exportFrame:Show();T.exportEdit:SetFocus();T.exportEdit:HighlightText()
end
-- Legacy command opens the same canonical talent tree used by /fc.
SLASH_FOREVERSIMTALENTPLAN1='/fsimtalents'
SlashCmdList.FOREVERSIMTALENTPLAN=function()
 if FUSLive and FUSLive.app and FUSLive.app.Open then FUSLive.app.Open('talents')
 else T.Show(classKey()) end
end
