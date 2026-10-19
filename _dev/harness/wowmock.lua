-- Minimal WoW client emulation for load/UI smoke tests (Lua 5.1).
-- Records: errors (with traceback), unknown globals, unknown widget methods, prints.
local M = {errors = {}, unknownGlobals = {}, unknownMethods = {}, prints = {}, frames = {}, events = {}, timers = {}, now = 1000}
_G.MOCK = M

local function record(kind, msg)
    M.errors[#M.errors + 1] = {kind = kind, msg = msg}
end
M.record = record
function M.pcall(label, fn, ...)
    local args = {...}
    local n = select('#', ...)
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, function(e) return debug.traceback(tostring(e), 2) end)
    if not ok then record(label, err) end
    return ok, err
end

-- Lua/WoW library extras ------------------------------------------------------
date = os.date; time = os.time
M.clockDivisor = 1
function debugprofilestop() return os.clock() * 1000 / M.clockDivisor end
function GetTime() return M.now end
function GetTimePreciseSec() return M.now end
strlower, strupper, strsub, strlen, strfind, strmatch, strrep, strbyte, strchar = string.lower, string.upper, string.sub, string.len, string.find, string.match, string.rep, string.byte, string.char
format, gsub, gmatch = string.format, string.gsub, string.gmatch
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
floor, ceil, abs, min, max, sqrt, mod = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.fmod
function strtrim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
function strsplit(sep, s, limit)
    local out = {}
    s = tostring(s or '')
    local pattern = '([^' .. sep:gsub('%p', '%%%0') .. ']*)'
    for part in (s .. sep):gmatch(pattern .. sep:gsub('%p', '%%%0')) do out[#out + 1] = part end
    return unpack(out)
end
function strjoin(sep, ...) return table.concat({...}, sep) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == 'table' and CopyTable(v) or v end return o end
function Mixin(o, ...) for _, m in ipairs({...}) do for k, v in pairs(m) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function issecretvalue() return false end
function canaccessvalue() return true end
function securecall(fn, ...) if type(fn) == 'string' then fn = _G[fn] end return fn(...) end
function hooksecurefunc(a, b, c)
    local tbl, name, fn = _G, a, b
    if type(a) == 'table' then tbl, name, fn = a, b, c end
    local old = tbl[name]
    if type(old) ~= 'function' then return end
    tbl[name] = function(...) local r = {old(...)}; fn(...); return unpack(r) end
end
function print(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    M.prints[#M.prints + 1] = table.concat(parts, ' ')
end
function geterrorhandler() return function(e) record('errorhandler', debug.traceback(tostring(e), 2)) end end
function seterrorhandler() end
function CreateColor(r, g, b, a) return {r = r, g = g, b = b, a = a, GetRGB = function(s) return s.r, s.g, s.b end, GetRGBA = function(s) return s.r, s.g, s.b, s.a end} end
function CreateVector2D(x, y) return {x = x, y = y, GetXY = function(s) return s.x, s.y end} end
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
UNKNOWNOBJECT = 'Unknown'
CLASS_ICON_TCOORDS = {WARLOCK = {.75, 1, .25, .5}}
RAID_CLASS_COLORS = setmetatable({}, {__index = function() return {r = 1, g = 1, b = 1, colorStr = 'ffffffff'} end})
BOOKTYPE_SPELL, BOOKTYPE_PET = 'spell', 'pet'
NUM_BAG_SLOTS = 4
Enum = {SpellBookSpellBank = {Player = 0, Pet = 1}, SpellBookItemType = {Spell = 1}, ItemClass = {Weapon = 2, Armor = 4}}
UISpecialFrames = {}
SlashCmdList = {}
hash_SlashCmdList = {}

-- Widgets -------------------------------------------------------------------------
local Widget = {}
local widgetMT = {__index = function(self, key)
    local m = Widget[key]
    if m then return m end
    local raw = rawget(self, '__fields') and self.__fields[key]
    if raw ~= nil then return raw end
    if type(key) == 'string' and key:match('^[A-Z]') then
        local tag = (rawget(self, '__type') or '?') .. ':' .. key
        M.unknownMethods[tag] = (M.unknownMethods[tag] or 0) + 1
        return function() end
    end
    return nil
end}
local nameless = 0
local function newObject(kind, name, parent)
    local o = setmetatable({__type = kind, __shown = true, __scripts = {}, __events = {}, __points = {}, __children = {}, __regions = {},
                            __w = 0, __h = 0, __scale = 1, __alpha = 1, __text = nil, __enabled = true, __attrs = {}, __parent = parent,
                            __level = 1, __strata = 'MEDIUM'}, widgetMT)
    if name then
        name = name:gsub('%$parent', parent and parent.__name or '')
        o.__name = name; _G[name] = o
    end
    if parent and parent.__children then
        if kind == 'Texture' or kind == 'FontString' or kind == 'Line' then table.insert(parent.__regions, o) else table.insert(parent.__children, o) end
    end
    M.frames[#M.frames + 1] = o
    return o
end
M.newObject = newObject
local function script(self, name, ...)
    local fn = self.__scripts[name]
    if fn then return M.pcall('script ' .. name .. ' ' .. tostring(self.__name or self.__type), fn, self, ...) end
end
M.script = script
function Widget:GetObjectType() return self.__type end
function Widget:IsObjectType(t) return self.__type == t or t == 'Frame' or t == 'Region' end
function Widget:GetName() return self.__name end
function Widget:SetSize(w, h) self.__w, self.__h = w or 0, h or 0 end
function Widget:SetWidth(w) self.__w = w or 0 end
function Widget:SetHeight(h) self.__h = h or 0 end
-- Derive extents from anchors like the client layout engine (two opposite anchors).
local function relOf(self, p) local r = p[2]; if type(r) == 'string' then r = _G[r] end; if type(r) ~= 'table' then r = nil end; return r or self.__parent end
local function extent(self, horizontal)
    local a, b
    for _, p in ipairs(self.__points) do
        local pt = p[1]
        local rp = type(p[3]) == 'string' and p[3] or pt
        local off = horizontal and (tonumber(p[4]) or (type(p[2]) == 'number' and p[2]) or 0) or (tonumber(p[5]) or (type(p[3]) == 'number' and p[3]) or 0)
        if horizontal then
            if pt:find('LEFT') then a = {rel = relOf(self, p), rp = rp, off = off} elseif pt:find('RIGHT') then b = {rel = relOf(self, p), rp = rp, off = off} end
        else
            if pt:find('TOP') then a = {rel = relOf(self, p), rp = rp, off = off} elseif pt:find('BOTTOM') then b = {rel = relOf(self, p), rp = rp, off = off} end
        end
    end
    if not a or not b or not a.rel or a.rel ~= b.rel or not a.rel.GetWidth then return 0 end
    local size = horizontal and a.rel:GetWidth() or a.rel:GetHeight()
    local function pos(x) if horizontal then return x.rp:find('RIGHT') and size or x.rp:find('LEFT') and 0 or size / 2 end
                          return x.rp:find('BOTTOM') and size or x.rp:find('TOP') and 0 or size / 2 end
    if horizontal then return math.max(0, (pos(b) + b.off) - (pos(a) + a.off)) end
    return math.max(0, (pos(b) - b.off) - (pos(a) - a.off))
end
function Widget:GetWidth()
    if self.__w == 0 and self.__allpoints and self.__parent then local r = self.__allpoints; return (type(r) == 'table' and r or self.__parent):GetWidth() end
    if self.__w == 0 then return extent(self, true) end
    return self.__w
end
function Widget:GetHeight()
    if self.__h == 0 and self.__allpoints and self.__parent then local r = self.__allpoints; return (type(r) == 'table' and r or self.__parent):GetHeight() end
    if self.__h == 0 then return extent(self, false) end
    return self.__h
end
function Widget:GetSize() return self:GetWidth(), self:GetHeight() end
function Widget:GetRect() return 0, 0, self:GetWidth(), self:GetHeight() end
function Widget:GetCenter() return 600, 400 end
function Widget:GetLeft() return 100 end
function Widget:GetRight() return 100 + self:GetWidth() end
function Widget:GetTop() return 700 end
function Widget:GetBottom() return 700 - self:GetHeight() end
function Widget:SetPoint(point, rel, relPoint, x, y)
    if type(point) ~= 'string' then error('SetPoint: invalid point ' .. tostring(point), 2) end
    if rel ~= nil and type(rel) ~= 'table' and type(rel) ~= 'string' and type(rel) ~= 'number' then error('SetPoint: bad relativeTo', 2) end
    table.insert(self.__points, {point, rel, relPoint, x, y})
end
function Widget:ClearAllPoints() self.__points = {}; self.__allpoints = nil end
function Widget:SetAllPoints(rel) self.__allpoints = rel or true end
function Widget:GetNumPoints() return #self.__points end
function Widget:GetPoint(i) local p = self.__points[i or 1]; if p then return unpack(p) end end
function Widget:Show() if not self.__shown then self.__shown = true; script(self, 'OnShow') end end
function Widget:Hide() if self.__shown then self.__shown = false; script(self, 'OnHide') end end
function Widget:SetShown(on) if on then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible()
    if not self.__shown then return false end
    local p = self.__parent
    if p and p.IsVisible then return p:IsVisible() end
    return true
end
function Widget:SetParent(p)
    if type(p) == 'string' then p = _G[p] end
    if self.__parent and self.__parent.__children then
        for i, c in ipairs(self.__parent.__children) do if c == self then table.remove(self.__parent.__children, i) break end end
    end
    self.__parent = p
    if p and p.__children then table.insert(p.__children, self) end
end
function Widget:GetParent() return self.__parent end
function Widget:GetChildren() return unpack(self.__children) end
function Widget:GetNumChildren() return #self.__children end
function Widget:GetRegions() return unpack(self.__regions) end
function Widget:SetScript(name, fn)
    if fn ~= nil and type(fn) ~= 'function' then error('SetScript: handler must be a function', 2) end
    self.__scripts[name] = fn
end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HasScript() return true end
function Widget:HookScript(name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Widget:RegisterEvent(e)
    if type(e) ~= 'string' then error('RegisterEvent: event must be string', 2) end
    if M.knownEvents and not M.knownEvents[e] then M.unknownEvents = M.unknownEvents or {}; M.unknownEvents[e] = true end
    self.__events[e] = true
end
function Widget:RegisterUnitEvent(e) self.__events[e] = true end
function Widget:UnregisterEvent(e) self.__events[e] = nil end
function Widget:UnregisterAllEvents() self.__events = {} end
function Widget:IsEventRegistered(e) return self.__events[e] == true end
function Widget:RegisterAllEvents() self.__all = true end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetFrameStrata() return self.__strata end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameLevel() return self.__level end
function Widget:SetScale(s) if type(s) ~= 'number' or s <= 0 then error('SetScale: invalid scale ' .. tostring(s), 2) end self.__scale = s end
function Widget:GetScale() return self.__scale end
function Widget:GetEffectiveScale() local p = self.__parent; return self.__scale * (p and p.GetEffectiveScale and p:GetEffectiveScale() or 1) end
function Widget:SetAlpha(a) self.__alpha = a end
function Widget:GetAlpha() return self.__alpha end
function Widget:GetEffectiveAlpha() return self.__alpha end
function Widget:EnableMouse() end
function Widget:IsMouseOver() return false end
function Widget:SetEnabled(on) self.__enabled = on and true or false end
function Widget:Enable() self.__enabled = true end
function Widget:Disable() self.__enabled = false end
function Widget:IsEnabled() return self.__enabled end
function Widget:SetText(t) if t ~= nil and type(t) ~= 'string' and type(t) ~= 'number' then error('SetText: bad argument #1 (' .. type(t) .. ')', 2) end
    if self.__type == 'FontString' and not self.__font then error('FontString:SetText(): Font not set', 2) end
    self.__text = t and tostring(t) or nil end
function Widget:SetFormattedText(f, ...) self:SetText(string.format(f, ...)) end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return #(self.__text or '') * 6 end
function Widget:GetUnboundedStringWidth() return #(self.__text or '') * 6 end
function Widget:GetStringHeight() return 14 end
function Widget:GetNumLines() return 1 end
function Widget:SetFont(path, size, flags)
    if type(path) ~= 'string' or type(size) ~= 'number' then error('SetFont: invalid arguments', 2) end
    self.__font = {path, size, flags}; return true
end
function Widget:GetFont() if self.__font then return unpack(self.__font) end return STANDARD_TEXT_FONT, 12, '' end
function Widget:SetFontObject(obj)
    if type(obj) == 'string' then obj = _G[obj] end
    if obj == nil then error('SetFontObject: nil font object', 2) end
    self.__font = {STANDARD_TEXT_FONT, 12, ''}
end
function Widget:GetFontObject() return GameFontNormal end
function Widget:SetTextColor(...) self.__color = {...} end
function Widget:GetTextColor() return unpack(self.__color or {1, 1, 1, 1}) end
function Widget:SetTexture(t) self.__texture = t; return true end
function Widget:GetTexture() return self.__texture end
function Widget:SetAtlas(a) self.__texture = a; return true end
function Widget:SetColorTexture(...) self.__texture = 'color' end
function Widget:SetVertexColor() end
function Widget:SetTexCoord() end
function Widget:SetRotation(r) if type(r) ~= 'number' then error('SetRotation: number expected', 2) end end
function Widget:SetDesaturated() end
function Widget:SetBlendMode() end
function Widget:SetDrawLayer() end
function Widget:SetGradient(o, a, b) if type(o) ~= 'string' or type(a) ~= 'table' or type(b) ~= 'table' then error('SetGradient: bad args', 2) end end
function Widget:SetBackdrop(b) self.__backdrop = b end
function Widget:SetBackdropColor() end
function Widget:SetBackdropBorderColor() end
function Widget:SetMovable() end
function Widget:IsMovable() return true end
function Widget:SetResizable() end
function Widget:SetClampedToScreen() end
function Widget:SetClipsChildren() end
function Widget:SetUserPlaced() end
function Widget:SetToplevel() end
function Widget:SetDontSavePosition() end
function Widget:StartMoving() end
function Widget:StopMovingOrSizing() end
function Widget:RegisterForDrag() end
function Widget:RegisterForClicks() end
function Widget:SetJustifyH() end
function Widget:SetJustifyV() end
function Widget:SetWordWrap(v) self.__wrap = v end
function Widget:SetNonSpaceWrap() end
function Widget:SetMaxLines() end
function Widget:SetSpacing() end
function Widget:SetShadowColor() end
function Widget:SetShadowOffset() end
function Widget:SetHitRectInsets() end
function Widget:SetIgnoreParentScale() end
function Widget:SetFixedFrameStrata() end
function Widget:SetFixedFrameLevel() end
function Widget:Raise() end
function Widget:Lower() end
function Widget:SetID(i) self.__id = i end
function Widget:GetID() return self.__id or 0 end
function Widget:SetAttribute(k, v) self.__attrs[k] = v end
function Widget:GetAttribute(k) return self.__attrs[k] end
function Widget:SetChecked(v) self.__checked = v and true or false end
function Widget:GetChecked() return self.__checked or false end
function Widget:SetHighlightTexture(t) self.__hl = self.__hl or newObject('Texture', nil, self); self.__hl.__texture = t end
function Widget:GetHighlightTexture() self.__hl = self.__hl or newObject('Texture', nil, self); return self.__hl end
function Widget:SetNormalTexture(t) self.__nt = self.__nt or newObject('Texture', nil, self); self.__nt.__texture = t end
function Widget:GetNormalTexture() self.__nt = self.__nt or newObject('Texture', nil, self); return self.__nt end
function Widget:SetPushedTexture() end
function Widget:SetDisabledTexture() end
function Widget:SetCheckedTexture() end
function Widget:GetPushedTexture() return newObject('Texture', nil, self) end
function Widget:LockHighlight() end
function Widget:UnlockHighlight() end
function Widget:SetButtonState() end
function Widget:SetMotionScriptsWhileDisabled() end
function Widget:SetNormalFontObject() end
function Widget:SetHighlightFontObject() end
function Widget:SetDisabledFontObject() end
function Widget:SetPushedTextOffset() end
function Widget:GetFontString() self.__fs = self.__fs or Widget.CreateFontString(self); return self.__fs end
function Widget:Click(button) script(self, 'OnClick', button or 'LeftButton', false) end
function Widget:SetFocus() self.__focus = true end
function Widget:ClearFocus() self.__focus = false end
function Widget:HasFocus() return self.__focus == true end
function Widget:SetAutoFocus() end
function Widget:SetNumeric() end
function Widget:SetMultiLine() end
function Widget:SetMaxLetters() end
function Widget:HighlightText() end
function Widget:SetCursorPosition() end
function Widget:SetTextInsets() end
function Widget:GetNumber() return tonumber(self.__text) or 0 end
function Widget:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Widget:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function Widget:SetValue(v) self.__value = v end
function Widget:GetValue() return self.__value or 0 end
function Widget:SetValueStep() end
function Widget:SetObeyStepOnDrag() end
function Widget:SetOrientation() end
function Widget:SetStatusBarTexture() end
function Widget:SetStatusBarColor() end
function Widget:GetStatusBarTexture() return newObject('Texture', nil, self) end
function Widget:SetScrollChild(c) self.__scrollChild = c end
function Widget:GetScrollChild() return self.__scrollChild end
function Widget:SetVerticalScroll() end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:UpdateScrollChildRect() end
function Widget:SetThickness() end
function Widget:SetStartPoint(rp, rel, x, y) if type(rp) ~= 'string' then error('SetStartPoint: relativePoint string expected', 2) end end
function Widget:SetEndPoint(rp, rel, x, y) if type(rp) ~= 'string' then error('SetEndPoint: relativePoint string expected', 2) end end
function Widget:SetCooldown() end
function Widget:SetUnit() end
function Widget:SetPortraitZoom() end
function Widget:SetCreature() end
function Widget:SetDisplayInfo() end
function Widget:SetCamDistanceScale() end
function Widget:SetModel() end
function Widget:ClearModel() end
function Widget:SetFacing() end
function Widget:SetPosition() end
function Widget:SetKeepModelOnHide() end
function Widget:RefreshUnit() end
function Widget:SetMask() end
function Widget:AddMaskTexture() end
function Widget:SetSnapToPixelGrid() end
function Widget:SetTexelSnappingBias() end
function Widget:SetHorizTile() end
function Widget:SetVertTile() end
function Widget:EnableKeyboard() end
function Widget:SetPropagateKeyboardInput() end
function Widget:SetHyperlinksEnabled() end
function Widget:EnableMouseWheel() end
function Widget:SetResizeBounds() end
function Widget:SetMinResize() end
function Widget:SetMaxResize() end
function Widget:StartSizing() end
function Widget:IsDragging() return false end
function Widget:SetFlattensRenderLayers() end
function Widget:SetFrameRef() end
function Widget:CreateTexture(name, layer, template, sub)
    local t = newObject('Texture', name, self); return t
end
function Widget:CreateMaskTexture(name) return newObject('Texture', name, self) end
function Widget:CreateFontString(name, layer, template)
    local f = newObject('FontString', name, self)
    if template then
        local tpl = type(template) == 'string' and _G[template]
        if not tpl then record('template', 'CreateFontString: unknown font template ' .. tostring(template)) end
        f.__font = {STANDARD_TEXT_FONT, 12, ''}
    end
    return f
end
function Widget:CreateLine(name) return newObject('Line', name, self) end
function Widget:CreateAnimationGroup()
    local g = newObject('AnimationGroup', nil, nil)
    function g:CreateAnimation() return newObject('Animation', nil, nil) end
    return g
end
-- Tooltip lines
function Widget:SetOwner(o) self.__lines = {}; self.__owner = o; self.__shown = true end
function Widget:GetOwner() return self.__owner end
function Widget:ClearLines() self.__lines = {} end
function Widget:AddLine(text) self.__lines = self.__lines or {}; self.__lines[#self.__lines + 1] = text end
function Widget:AddDoubleLine(a, b) self:AddLine(a) end
function Widget:NumLines() return #(self.__lines or {}) end
function Widget:SetHyperlink(link)
    self.__lines = {}
    local id = tonumber(tostring(link):match('item:(%d+)'))
    local item = id and M.items[id]
    local name = self.__name
    local lines = item and item.tooltip or {}
    for i, pair in ipairs(lines) do
        self.__lines[i] = pair[1]
        if name then
            local l = _G[name .. 'TextLeft' .. i] or newObject('FontString', name .. 'TextLeft' .. i, self)
            local r = _G[name .. 'TextRight' .. i] or newObject('FontString', name .. 'TextRight' .. i, self)
            l.__font = {STANDARD_TEXT_FONT, 12, ''}; r.__font = l.__font
            l.__text = pair[1]; r.__text = pair[2]
        end
    end
    if name then for i = #lines + 1, 30 do local l = _G[name .. 'TextLeft' .. i]; if l then l.__text = nil end; local r = _G[name .. 'TextRight' .. i]; if r then r.__text = nil end end end
end
function Widget:SetSpellByID() end
function Widget:SetUnitBuff() end
function Widget:SetItemByID() end
function Widget:SetBagItem() end
function Widget:SetInventoryItem() end
function Widget:SetQuestLogItem() end
function Widget:FadeOut() end
function Widget:SetMinimumWidth() end
function Widget:SetPadding() end
function Widget:AddTexture() end
-- Map canvas (WorldMapFrame)
function Widget:AddDataProvider() end
function Widget:RemoveDataProvider() end
function Widget:GetMapID() return M.mapID end
function Widget:SetMapID(id) M.mapID = id end
function Widget:GetCanvas() self.__canvas = self.__canvas or newObject('Frame', nil, self); self.__canvas.__w, self.__canvas.__h = 1002, 668; return self.__canvas end
function Widget:GetCanvasScale() return 1 end
function Widget:AcquirePin() return newObject('Frame', nil, self) end
function Widget:RemoveAllPinsByTemplate() end
function Widget:EnumeratePinsByTemplate() return function() end end
function Widget:RefreshAllDataProviders() end

local templateHooks = {}
function M.CreateFrame(kind, name, parent, template)
    if type(kind) ~= 'string' then error('CreateFrame: frameType must be a string', 2) end
    if type(parent) == 'string' then parent = _G[parent] end
    if parent ~= nil and type(parent) ~= 'table' then error('CreateFrame: invalid parent', 2) end
    local f = newObject(kind, name, parent)
    if kind == 'GameTooltip' then f.__shown = false end
    for tpl in tostring(template or ''):gmatch('[^,%s]+') do
        if tpl == 'UICheckButtonTemplate' or tpl == 'ChatConfigCheckButtonTemplate' then f.text = f:CreateFontString(nil, nil, 'GameFontNormal'); f.Text = f.text
        elseif tpl == 'UIPanelButtonTemplate' then f.Text = f:CreateFontString(nil, nil, 'GameFontNormal'); f.SetText = function(s, t) s.__text = t; s.Text.__text = t end
        elseif tpl == 'InputBoxTemplate' then f.__text = ''
        elseif tpl == 'UIPanelScrollFrameTemplate' or tpl == 'ScrollFrameTemplate' then
            local bar = newObject('Slider', name and (name .. 'ScrollBar') or nil, f); f.ScrollBar = bar
            bar.ScrollUpButton = newObject('Button', name and (name .. 'ScrollBarScrollUpButton') or nil, bar)
            bar.ScrollDownButton = newObject('Button', name and (name .. 'ScrollBarScrollDownButton') or nil, bar)
            bar.ThumbTexture = newObject('Texture', name and (name .. 'ScrollBarThumbTexture') or nil, bar)
        elseif tpl == 'BackdropTemplate' then
        elseif tpl == 'UIPanelCloseButton' or tpl == 'GameTooltipTemplate' or tpl == 'InsecureActionButtonTemplate' or tpl == 'SecureActionButtonTemplate'
            or tpl == 'OptionsSliderTemplate' or tpl == 'UIDropDownMenuTemplate' or tpl == 'TooltipBorderedFrameTemplate' then
        else
            M.unknownTemplates = M.unknownTemplates or {}; M.unknownTemplates[tpl] = true
        end
    end
    return f
end
CreateFrame = M.CreateFrame

UIParent = newObject('Frame', 'UIParent', nil); UIParent.__w, UIParent.__h = 1365, 768
WorldFrame = newObject('Frame', 'WorldFrame', nil)
Minimap = newObject('Minimap', 'Minimap', UIParent); Minimap.__w, Minimap.__h = 140, 140
function Minimap:GetZoom() return 0 end
function Minimap:GetZoomLevels() return 6 end
MinimapCluster = newObject('Frame', 'MinimapCluster', UIParent)
WorldMapFrame = newObject('Frame', 'WorldMapFrame', UIParent); WorldMapFrame.__shown = false
WorldMapFrame.ScrollContainer = newObject('ScrollFrame', nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = newObject('Frame', nil, WorldMapFrame.ScrollContainer)
function WorldMapFrame:GetMapID() return M.mapID end
GameTooltip = M.CreateFrame('GameTooltip', 'GameTooltip', UIParent, 'GameTooltipTemplate')
ItemRefTooltip = M.CreateFrame('GameTooltip', 'ItemRefTooltip', UIParent, 'GameTooltipTemplate')
DEFAULT_CHAT_FRAME = newObject('Frame', 'ChatFrame1', UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(msg) M.prints[#M.prints + 1] = tostring(msg) end
ChatFrame1 = DEFAULT_CHAT_FRAME
for _, n in ipairs({'GameFontNormal', 'GameFontNormalSmall', 'GameFontNormalLarge', 'GameFontHighlight', 'GameFontHighlightSmall', 'GameFontHighlightLarge',
                   'GameFontDisable', 'GameFontDisableSmall', 'GameFontGreen', 'GameFontRed', 'GameFontWhite', 'ChatFontNormal', 'NumberFontNormal',
                   'GameFontNormalHuge', 'GameFontHighlightHuge', 'SystemFont_Med1', 'QuestFont', 'GameFontBlack', 'GameFontNormalMed3', 'GameFontHighlightMedium', 'GameFontNormalMed1', 'Fancy22Font', 'GameFontHighlightLeft', 'GameFontNormalLeft'}) do
    local f = newObject('Font', n, nil); f.__font = {STANDARD_TEXT_FONT, 12, ''}
end
function CreateFont(name) local f = newObject('Font', name, nil); f.__font = {STANDARD_TEXT_FONT, 12, ''}; return f end

-- Events & timers -------------------------------------------------------------
function M.Fire(event, ...)
    for _, f in ipairs(M.frames) do
        if (f.__events and f.__events[event]) or f.__all then
            local fn = f.__scripts.OnEvent
            if fn then M.pcall('event ' .. event .. ' @' .. tostring(f.__name or f.__type), fn, f, event, ...) end
        end
    end
end
C_Timer = {}
function C_Timer.After(sec, fn)
    if type(fn) ~= 'function' then error('C_Timer.After: function expected', 2) end
    M.timers[#M.timers + 1] = {at = M.now + (sec or 0), fn = fn}
end
function C_Timer.NewTimer(sec, fn) local t = {Cancel = function(s) s.cancelled = true end}; C_Timer.After(sec, function() if not t.cancelled then fn(t) end end); return t end
function C_Timer.NewTicker(sec, fn, n)
    local t = {Cancel = function(s) s.cancelled = true end, IsCancelled = function(s) return s.cancelled end}
    local count = 0
    local function tick() if t.cancelled then return end; count = count + 1; fn(t); if not n or count < n then C_Timer.After(sec, tick) end end
    C_Timer.After(sec, tick)
    return t
end
function M.Advance(seconds, step)
    step = step or 0.2
    local target = M.now + seconds
    while M.now < target do
        M.now = M.now + step
        local due = {}
        for i = #M.timers, 1, -1 do if M.timers[i].at <= M.now then table.insert(due, 1, table.remove(M.timers, i)) end end
        for _, t in ipairs(due) do M.pcall('timer', t.fn) end
        local snapshot = {}
        for _, f in ipairs(M.frames) do if f.__scripts and f.__scripts.OnUpdate and f:IsVisible() then snapshot[#snapshot + 1] = f end end
        for _, f in ipairs(snapshot) do script(f, 'OnUpdate', step) end
    end
end

-- Unknown global tracking (installed after harness setup) -------------------------
function M.TrackGlobals(ignore)
    setmetatable(_G, {__index = function(_, k)
        if not ignore[k] then M.unknownGlobals[k] = (M.unknownGlobals[k] or 0) + 1 end
        return nil
    end})
end
return M
