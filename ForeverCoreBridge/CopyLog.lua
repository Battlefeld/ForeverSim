-- Copyable log. The WoW chat window cannot be copied, so every ForeverCore status message is also kept here.
--   /fc log          opens a window with the text already selected: Ctrl+A is not needed, press Ctrl+C
--   /fc log clear    empties the log
-- Messages come from C.Say (connection status, jobs, auction house ...). The log is kept for the session only.
local C=ForeverCoreClient
local MAX=400
C.logLines=C.logLines or{}
local lines=C.logLines
function C.Log(text)
 text=tostring(text or'')
 local stamp=date and date('%H:%M:%S')or''
 -- identical consecutive messages (status label refreshes) are counted, not repeated
 local last=lines[#lines]
 if last and last.text==text then last.count=last.count+1;return end
 lines[#lines+1]={stamp=stamp,text=text,count=1}
 if #lines>MAX then table.remove(lines,1)end
end
function C.LogText()
 local out={}
 for i,l in ipairs(lines)do
  out[i]=l.stamp..'  '..l.text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')..(l.count>1 and('  (x'..l.count..')')or'')
 end
 return table.concat(out,'\n')
end
-- every C.Say also goes into the log
local say=C.Say
if type(say)=='function' then
 C.Say=function(text,...)
  C.Log(text)
  return say(text,...)
 end
end
local frame
local function build()
 if frame then return frame end
 local ok,err=pcall(function()
  local f=CreateFrame('Frame','ForeverCoreLogFrame',UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
  f:SetSize(640,420);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true)
  f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
  if f.SetBackdrop then
   f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}})
  end
  local title=f:CreateFontString(nil,'OVERLAY','GameFontNormal');title:SetPoint('TOPLEFT',20,-16)
  title:SetText('ForeverCore Protokoll - Text ist markiert: Strg+C zum Kopieren, Esc zum Schliessen')
  local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-4,-4)
  local scroll=CreateFrame('ScrollFrame','ForeverCoreLogScroll',f,'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT',20,-42);scroll:SetPoint('BOTTOMRIGHT',-38,18)
  local edit=CreateFrame('EditBox',nil,scroll)
  edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject('ChatFontNormal');edit:SetWidth(570)
  edit:SetScript('OnEscapePressed',function()f:Hide()end)
  scroll:SetScrollChild(edit)
  f.edit=edit
  if UISpecialFrames then table.insert(UISpecialFrames,'ForeverCoreLogFrame')end
  frame=f
 end)
 if not ok then
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r Protokollfenster konnte nicht erstellt werden: '..tostring(err))end
  return nil
 end
 return frame
end
function C.ShowLog()
 local f=build();if not f then return false end
 f.edit:SetText(#lines>0 and C.LogText() or 'Noch keine Meldungen.')
 f:Show()
 f.edit:SetFocus();f.edit:HighlightText()
 return true
end
local old=SlashCmdList and SlashCmdList.FOREVERCORE
if old then
 SlashCmdList.FOREVERCORE=function(msg)
  local head,tail=tostring(msg or''):match('^%s*(%S+)%s*(.-)%s*$')
  if head and head:lower()=='log' then
   if tail:lower()=='clear' then for i=#lines,1,-1 do lines[i]=nil end;return end
   return C.ShowLog()
  end
  return old(msg)
 end
end
