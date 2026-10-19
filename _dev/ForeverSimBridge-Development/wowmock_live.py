"""Small WoW mock (frames, quest/loot stubs, FUSLive stub) used by test_universal_live_capture.py.

The former reward-panel test lived here; item scores are tested in test_goals.py.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
root=Path(__file__).resolve().parent.parent
compile_lua=lua.eval('function(s,n)local f,e=loadstring(s,n);assert(f,e);return f end')
for p in root.rglob('*.lua'):compile_lua(p.read_text(encoding='utf-8-sig'),str(p))
lua.execute('''
frames={};level=0;captureCalls=0;compareCalls=0;failCurrent=false;failJob=false
local methods={}
function methods:SetText(t)self.text=t end
function methods:SetScript(k,f)self.scripts[k]=f end
function methods:HookScript(k,f)local previous=self.scripts[k];self.scripts[k]=function(...)if previous then previous(...)end;f(...)end end
function methods:RegisterEvent(e)self.events[e]=true end
function methods:SetPoint(...)self.point={...}end
function methods:SetSize(w,h)self.width=w;self.height=h end
function methods:SetWidth(w)self.width=w end
function methods:SetHeight(h)self.height=h end
function methods:SetWordWrap(v)self.wrap=v end
function methods:Show()self.shown=true end
function methods:Hide()self.shown=false end
function methods:SetShown(v)self.shown=v end
function methods:IsShown()return self.shown end
function methods:CreateFontString()local f=CreateFrame();self.labels=self.labels or {};table.insert(self.labels,f);return f end
function methods:CreateTexture()return CreateFrame()end
local noop=function()end
function CreateFrame(_,name,parent)local f=setmetatable({scripts={},events={},shown=true,parent=parent},{__index=function(_,k)return methods[k] or (k:match("^[A-Z]") and noop or nil) end});frames[#frames+1]=f;if name then _G[name]=f end;return f end
function UnitLevel()return level end
function GetTime()return 0 end
function InCombatLockdown()return false end
function GetNumQuestChoices()return 2 end
function GetQuestItemLink(_,i)return 'item:'..i end
QuestFrame=CreateFrame()
QuestInfoItem1=CreateFrame();QuestInfoItem2=CreateFrame()
GroupLootFrame1=CreateFrame();GroupLootFrame1.rollID=7
function GetLootRollItemLink()return 'item:1' end
GameTooltip=CreateFrame();GameTooltip.lines={}
function GameTooltip:IsOwned(owner)return self.owner==owner end
function GameTooltip:SetOwner(owner)self.owner=owner;self.lines={}end
function GameTooltip:AddLine(line)table.insert(self.lines,line)end
FUSLiveData={warlock={}}
FUSLive={revision=1,stale=true,publicNumber=function(v)return v end,readItem=function(link)return {id=tonumber(link:match('%d+'))}end,
 capture=function()captureCalls=captureCalls+1;return {spells={},level=level}end,
 normalizeSnapshot=function(s)return {class='warlock',level=s.level,equipped={},spells={}}end,
 coverage=function()if failCurrent then return 'Interface/AddOns/ForeverSimBridge/LiveUI.lua:99: technical failure' end end,
 combine=function()return {}end,best=function()return {}end,
 compare=function(_,_,_,item)compareCalls=compareCalls+1;if failJob then error('Interface/AddOns/LiveUI.lua:99: job failure')end;return {eligible=true,percent=item.id,newDps=100+item.id,newChoice={policies={}},rotationRules={{text='Use spell'}}}end,
 invalidate=function()FUSLive.revision=FUSLive.revision+1 end}
''')
