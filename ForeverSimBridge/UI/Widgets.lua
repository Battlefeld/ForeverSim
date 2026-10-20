-- Controls of the ForeverSim window, all drawn with the pack's own frames: buttons, check boxes, a drop-down list,
-- cards, bars and a small bar chart. Nothing here talks to Blizzard frames or to the PC.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
local WHITE='Interface\\Buttons\\WHITE8X8'

-- A flat card: dark blue fill with a thin light border (the look of the list rows and boxes in the mock-ups).
function UI.Box(parent,fill,border)
 local f=CreateFrame('Frame',nil,parent,'BackdropTemplate')
 if f.SetBackdrop then
  f:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
  local a,b=fill or{.055,.15,.30,.62},border or{.47,.63,.9,.22}
  f:SetBackdropColor(a[1],a[2],a[3],a[4]or 1);f:SetBackdropBorderColor(b[1],b[2],b[3],b[4]or 1)
 end
 return f
end
function UI.BoxColors(f,fill,border)
 if not f.SetBackdropColor then return end
 if fill then f:SetBackdropColor(fill[1],fill[2],fill[3],fill[4]or 1)end
 if border then f:SetBackdropBorderColor(border[1],border[2],border[3],border[4]or 1)end
end

-- Tooltip on hover. text: a string or a function returning title and lines ({title,line,...}).
function UI.Tooltip(frame,text)
 frame:SetScript('OnEnter',function(self)
  if not GameTooltip then return end
  local t=type(text)=='function'and text(self)or text;if not t then return end
  GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
  if type(t)=='string'then GameTooltip:SetText(t,1,.82,0,1,true)
  else
   GameTooltip:SetText(t[1]or'',1,.82,0)
   for i=2,#t do GameTooltip:AddLine(t[i],.85,.9,1,true)end
  end
  GameTooltip:Show()
 end)
 frame:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
end

-- A button with the pack's frame. opts: w, h, style (button | buttonGlow | buttonActive | buttonBig | tab), size, color,
-- kind (font), icon (texture path), onClick. Methods: SetLabel, SetStyle, SetEnabledLook.
function UI.Button(parent,text,opts)
 opts=opts or{}
 local b=CreateFrame('Button',nil,parent)
 b:SetSize(opts.w or 120,opts.h or 40)
 b.sets={}
 local function make(name)
  local holder=CreateFrame('Frame',nil,b);holder:SetAllPoints();holder:EnableMouse(false)
  holder:SetFrameLevel(b:GetFrameLevel());b.sets[name]={holder=holder,parts=UI.Style(holder,name,'BACKGROUND')};holder:Hide()
 end
 for _,name in ipairs(opts.styles or{opts.style or'button'})do make(name)end
 b.label=UI.Text(b,opts.size or 13,opts.color or COLOR.text,opts.kind or'body','CENTER')
 b.label:SetPoint('CENTER',b,'CENTER',opts.icon and 9 or 0,0)
 if opts.icon then
  b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(opts.iconSize or 17,opts.iconSize or 17);b.icon:SetTexture(opts.icon)
  b.icon:SetTexCoord(.07,.93,.07,.93);b.icon:SetPoint('RIGHT',b.label,'LEFT',-7,0)
 end
 b.hl=b:CreateTexture(nil,'HIGHLIGHT');b.hl:SetAllPoints();b.hl:SetColorTexture(1,1,1,.08)
 function b:SetLabel(t)self.label:SetText(t or'')end
 function b:SetStyle(name)
  for n,s in pairs(self.sets)do if n==name then s.holder:Show()else s.holder:Hide()end end
  self.style=name
 end
 function b:SetEnabledLook(on)
  if on then self:Enable();self:SetAlpha(1)else self:Disable();self:SetAlpha(.45)end
 end
 b:SetLabel(text);b:SetStyle(opts.styles and opts.styles[1]or opts.style or'button')
 if opts.onClick then b:SetScript('OnClick',function(self,...)if self:IsEnabled()then opts.onClick(self,...)end end)end
 if opts.tooltip then UI.Tooltip(b,opts.tooltip)end
 return b
end

-- A check box: the pack's checkbox frame with a gold check mark. get() returns the state, set(on) stores it.
function UI.Check(parent,label,get,set,width)
 local b=CreateFrame('Button',nil,parent);b:SetSize(width or 200,22)
 b.box=UI.ArtTexture(b,'BACKGROUND','checkbox',0,20,20);b.box:SetPoint('LEFT',b,'LEFT',0,0)
 b.mark=b:CreateTexture(nil,'ARTWORK');b.mark:SetTexture('Interface\\Buttons\\UI-CheckBox-Check');b.mark:SetSize(26,26)
 b.mark:SetPoint('CENTER',b.box,'CENTER',0,0);UI.Tint(b.mark,COLOR.gold)
 b.text=UI.Text(b,12.5,COLOR.text,'body','LEFT');b.text:SetPoint('LEFT',b.box,'RIGHT',8,0);b.text:SetText(label)
 function b:Refresh()UI.Show(self.mark,get()==true)end
 b:SetScript('OnClick',function(self)if set then set(not(get()==true))end;self:Refresh()end)
 b:SetScript('OnShow',function(self)self:Refresh()end)
 b:Refresh()
 return b
end

-- The numbered gold disc that leads a step ("1 Skillung").
function UI.Step(parent,n)
 local f=CreateFrame('Frame',nil,parent);f:SetSize(22,22)
 f.bg=UI.ArtTexture(f,'ARTWORK','badge',0,22,22);f.bg:SetAllPoints()
 f.text=UI.Text(f,12,{.16,.1,0},'title','CENTER');f.text:SetPoint('CENTER',f,'CENTER',0,0);f.text:SetText(tostring(n))
 return f
end
-- A small heading in capitals ("QUELLEN"), optionally with a step disc.
function UI.Heading(parent,text,step)
 local f=CreateFrame('Frame',nil,parent);f:SetHeight(22)
 local x=0
 if step then f.step=UI.Step(f,step);f.step:SetPoint('LEFT',f,'LEFT',0,0);x=30 end
 f.text=UI.Text(f,11,COLOR.gold,'body','LEFT');f.text:SetPoint('LEFT',f,'LEFT',x,0);f.text:SetText(string.upper(text))
 return f
end

-- An icon in a thin frame (spell, talent, item). color: border colour.
function UI.IconBox(parent,size,border)
 local f=UI.Box(parent,{.02,.04,.09,1},border or COLOR.gold2)
 f:SetSize(size,size)
 f.tex=f:CreateTexture(nil,'ARTWORK');f.tex:SetPoint('TOPLEFT',2,-2);f.tex:SetPoint('BOTTOMRIGHT',-2,2)
 f.tex:SetTexCoord(.07,.93,.07,.93);f.tex:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
 function f:SetIcon(path)self.tex:SetTexture(path or'Interface\\Icons\\INV_Misc_QuestionMark')end
 function f:SetBorder(c)UI.BoxColors(self,nil,c)end
 return f
end
-- The icon of a spell by id; the question mark when the client does not know it.
function UI.SpellIcon(id)
 local tex
 if id then
  if C_Spell and C_Spell.GetSpellTexture then local ok,t=pcall(C_Spell.GetSpellTexture,id);if ok and t then tex=t end end
  if not tex and GetSpellTexture then local ok,t=pcall(GetSpellTexture,id);if ok and t then tex=t end end
 end
 return tex or'Interface\\Icons\\INV_Misc_QuestionMark'
end

-- A horizontal bar. bar:SetFraction(0..1, colour).
function UI.Bar(parent,w,h,color)
 local f=UI.Box(parent,{.01,.03,.06,1},{.47,.63,.9,.25});f:SetSize(w,h)
 f.fill=f:CreateTexture(nil,'ARTWORK');f.fill:SetPoint('TOPLEFT',1,-1);f.fill:SetPoint('BOTTOMLEFT',1,1);f.fill:SetWidth(1)
 f.max=w-2;f.fill:SetColorTexture((color or COLOR.gold)[1],(color or COLOR.gold)[2],(color or COLOR.gold)[3],1)
 function f:SetFraction(x,c)
  x=math.max(0,math.min(1,tonumber(x)or 0));self.fill:SetWidth(math.max(1,self.max*x))
  if c then self.fill:SetColorTexture(c[1],c[2],c[3],c[4]or 1)end
  self.fraction=x
 end
 return f
end

-- A bar chart: values (any count) are resampled to the available bars. chart:SetData(values, maximum, colour).
function UI.Chart(parent,w,h,color)
 local f=UI.Box(parent,{.01,.03,.06,.7},{.47,.63,.9,.18});f:SetSize(w,h)
 f.bars={};f.caps={};f.count=0
 function f:SetData(values,maximum,c)
  c=c or color or COLOR.gold
  local n=math.min(#(values or{}),60);local top=maximum or 0
  if not maximum then for i=1,n do top=math.max(top,values[i])end end
  if n==0 or top<=0 then for i=1,#self.bars do self.bars[i]:Hide();self.caps[i]:Hide()end;self.count=0;return end
  local innerW,innerH=w-6,h-8;local bw=innerW/n
  for i=1,n do
   local bar=self.bars[i];if not bar then bar=self:CreateTexture(nil,'ARTWORK');self.bars[i]=bar;self.caps[i]=self:CreateTexture(nil,'OVERLAY')end
   local cap=self.caps[i]
   local ht=math.max(1,innerH*math.max(0,values[i])/top)
   bar:ClearAllPoints();bar:SetPoint('BOTTOMLEFT',self,'BOTTOMLEFT',3+(i-1)*bw,4);bar:SetSize(math.max(1,bw-.5),ht)
   bar:SetColorTexture(c[1],c[2],c[3],.30);bar:Show()
   cap:ClearAllPoints();cap:SetPoint('BOTTOMLEFT',self,'BOTTOMLEFT',3+(i-1)*bw,4+ht-1);cap:SetSize(math.max(1,bw-.5),2)
   cap:SetColorTexture(c[1],c[2],c[3],1);cap:Show()
  end
  for i=n+1,#self.bars do self.bars[i]:Hide();self.caps[i]:Hide()end
  self.count=n
 end
 return f
end

-- A drop-down list. opts.items = {{key,text,icon}}, opts.onSelect(key,item). dd:SetValue(key|nil,text,icon).
function UI.Dropdown(parent,w,opts)
 opts=opts or{}
 local d=CreateFrame('Button',nil,parent);d:SetSize(w,40)
 UI.Style(d,'dropdown','BACKGROUND')
 d.icon=d:CreateTexture(nil,'ARTWORK');d.icon:SetSize(22,22);d.icon:SetPoint('LEFT',d,'LEFT',14,0);d.icon:SetTexCoord(.07,.93,.07,.93)
 d.text=UI.Text(d,13,COLOR.text,'body','LEFT');d.text:SetPoint('LEFT',d,'LEFT',14,0);d.text:SetPoint('RIGHT',d,'RIGHT',-34,0)
 d.text:SetWordWrap(false)
 d.items=opts.items or{}
 function d:SetValue(key,text,icon)
  self.key=key;self.text:SetText(text or'')
  if icon then self.icon:SetTexture(icon);self.icon:Show();self.text:ClearAllPoints();self.text:SetPoint('LEFT',self.icon,'RIGHT',8,0);self.text:SetPoint('RIGHT',self,'RIGHT',-34,0)
  else self.icon:Hide();self.text:ClearAllPoints();self.text:SetPoint('LEFT',self,'LEFT',14,0);self.text:SetPoint('RIGHT',self,'RIGHT',-34,0)end
 end
 function d:SetItems(items)self.items=items or{}end
 local list=UI.Box(UIParent,{.02,.05,.1,.98},{.79,.6,.24,1});list:SetFrameStrata('FULLSCREEN_DIALOG');list:Hide()
 local catcher=CreateFrame('Button',nil,UIParent);catcher:SetAllPoints(UIParent);catcher:SetFrameStrata('FULLSCREEN_DIALOG');catcher:SetFrameLevel(1);catcher:Hide()
 catcher:SetScript('OnClick',function()list:Hide();catcher:Hide()end)
 list:SetFrameLevel(5);d.list=list;d.rows={}
 local function close()list:Hide();catcher:Hide()end
 d:SetScript('OnHide',close)
 d:SetScript('OnClick',function(self)
  if list:IsShown()then close();return end
  local n=#self.items;if n==0 then return end
  list:SetSize(w,n*26+6);list:ClearAllPoints();list:SetPoint('TOPLEFT',self,'BOTTOMLEFT',0,2)
  for i,item in ipairs(self.items)do
   local row=self.rows[i]
   if not row then
    row=CreateFrame('Button',nil,list);row:SetHeight(26);row:SetPoint('TOPLEFT',list,'TOPLEFT',3,-3-(i-1)*26);row:SetPoint('TOPRIGHT',list,'TOPRIGHT',-3,-3-(i-1)*26)
    row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(20,20);row.icon:SetPoint('LEFT',6,0);row.icon:SetTexCoord(.07,.93,.07,.93)
    row.text=UI.Text(row,12.5,COLOR.text,'body','LEFT');row.text:SetPoint('RIGHT',row,'RIGHT',-6,0)
    row.hl=row:CreateTexture(nil,'HIGHLIGHT');row.hl:SetAllPoints();row.hl:SetColorTexture(.3,.5,.9,.25)
    self.rows[i]=row
   end
   row.text:ClearAllPoints();row.text:SetPoint('LEFT',row,'LEFT',item.icon and 32 or 8,0);row.text:SetPoint('RIGHT',row,'RIGHT',-6,0)
   row.text:SetText(item.text or'');if item.icon then row.icon:SetTexture(item.icon);row.icon:Show()else row.icon:Hide()end
   row:SetScript('OnClick',function()close();self:SetValue(item.key,item.text,item.icon);if opts.onSelect then opts.onSelect(item.key,item)end end)
   row:Show()
  end
  for i=n+1,#self.rows do self.rows[i]:Hide()end
  catcher:Show();list:Show()
 end)
 d:SetValue(nil,'')
 return d
end

-- A small window with one line of text to edit: renaming a build, importing or copying a shared build text.
-- UI.Prompt(title, text, onOk, {readOnly=bool, okText=str}). onOk(text) returns nothing; a nil onOk makes it a viewer.
local prompt
function UI.Prompt(title,text,onOk,opts)
 opts=opts or{}
 if not prompt then
  local f=UI.Box(UIParent,{.02,.05,.1,.98},{.79,.6,.24,1});f:SetSize(460,150);f:SetPoint('CENTER',UIParent,'CENTER',0,120)
  f:SetFrameStrata('FULLSCREEN_DIALOG');f:EnableMouse(true);f:Hide()
  f.title=UI.Text(f,14,COLOR.gold,'title','LEFT');f.title:SetPoint('TOPLEFT',f,'TOPLEFT',16,-14)
  local box=UI.Box(f,{.01,.03,.06,1},{.47,.63,.9,.4});box:SetPoint('TOPLEFT',f,'TOPLEFT',16,-44);box:SetPoint('TOPRIGHT',f,'TOPRIGHT',-16,-44);box:SetHeight(30)
  f.edit=CreateFrame('EditBox',nil,box);f.edit:SetPoint('TOPLEFT',box,'TOPLEFT',8,-4);f.edit:SetPoint('BOTTOMRIGHT',box,'BOTTOMRIGHT',-8,4)
  f.edit:SetAutoFocus(false);f.edit:SetMaxLetters(2000);pcall(f.edit.SetFont,f.edit,UI.FONT.body,13,'');f.edit:SetTextColor(1,1,1)
  f.ok=UI.Button(f,'OK',{w=120,h=40,style='buttonActive',color=COLOR.gold});f.ok:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-146,12)
  f.cancel=UI.Button(f,'Abbrechen',{w=120,h=40});f.cancel:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-16,12)
  f.note=UI.Text(f,11,COLOR.muted,'body','LEFT');f.note:SetPoint('TOPLEFT',box,'BOTTOMLEFT',2,-6);f.note:SetPoint('RIGHT',f,'RIGHT',-16,0)
  local function close()f:Hide();f.edit:ClearFocus()end
  f.cancel:SetScript('OnClick',close)
  f.edit:SetScript('OnEscapePressed',close)
  f.ok:SetScript('OnClick',function()local cb=f.onOk;local t=f.edit:GetText();close();if cb then cb(t)end end)
  f.edit:SetScript('OnEnterPressed',function()if f.onOk then f.ok:Click()else close()end end)
  prompt=f
 end
 local f=prompt
 f.title:SetText(title or'');f.edit:SetText(text or'');f.onOk=onOk;f.note:SetText(opts.note or'')
 f.ok:SetLabel(opts.okText or'OK');UI.Show(f.ok,onOk~=nil)
 f:Show();f.edit:SetFocus();if opts.readOnly then f.edit:HighlightText()end
 return f
end
