-- ForeverSim single-page dashboard. Widget helpers first, then state, layout and refresh.
local P = FUSLive
local D = {}
P.dashboard = D
local UI = {}
P.ui = UI

local WHITE = 'Interface\\Buttons\\WHITE8X8'
local SERIF = 'Interface\\AddOns\\ForeverDungeonQuest\\Media\\FQSerif.ttf'
local C = {gold = {.96, .79, .43}, text = {.90, .92, .96}, muted = {.56, .62, .72}, blue = {.38, .68, 1},
           purple = {.70, .50, 1}, green = {.40, .88, .55}, red = {1, .42, .40}, cyan = {.36, .84, .96},
           orange = {1, .60, .24}, yellow = {.95, .82, .30}, dim = {.30, .35, .45}}
UI.colors = C
local SERIES = {{.64, .40, 1}, {.30, .74, 1}, {.86, .38, .95}, {.36, .86, .55}, {.98, .64, .26}, {.55, .58, .68}, {.95, .82, .30}, {1, .42, .40}}
UI.series = SERIES
local CLASSES = {'warlock', 'mage', 'shaman', 'warrior', 'paladin', 'rogue', 'druid', 'priest', 'hunter'}
local CLASS_NAMES = {warlock = 'Hexenmeister', mage = 'Magier', shaman = 'Schamane', warrior = 'Krieger', paladin = 'Paladin',
                     rogue = 'Schurke', druid = 'Druide', priest = 'Priester', hunter = 'Jäger'}
UI.classNames = CLASS_NAMES
local CLASS_COORDS = {warrior = {0, .25, 0, .25}, mage = {.25, .49609375, 0, .25}, rogue = {.49609375, .7421875, 0, .25},
                      druid = {.7421875, .98828125, 0, .25}, hunter = {0, .25, .25, .5}, shaman = {.25, .49609375, .25, .5},
                      priest = {.49609375, .7421875, .25, .5}, warlock = {.7421875, .98828125, .25, .5}, paladin = {0, .25, .5, .75}}

local function combat() return InCombatLockdown and InCombatLockdown() end
local function num(v)
    if P.publicNumber then return P.publicNumber(v) end
    if type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge then return v end
end
local function safe(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok and not (P.isProtected and P.isProtected(a)) then return a, b, c, d end
end
local function fmt(v, pattern, fallback)
    v = num(v)
    return v and string.format(pattern or '%.1f', v) or (fallback or '–')
end
local function thousands(v)
    v = num(v)
    if not v then return '–' end
    local s = string.format('%d', math.floor(v + .5))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (out:gsub('^%.', ''))
end
UI.fmt, UI.thousands, UI.num = fmt, thousands, num

-- Widgets ------------------------------------------------------------------
local function rgb(color) return type(color) == 'table' and color or C[color or 'text'] or C.text end
function UI.Text(parent, x, y, w, h, size, value, color, justify, serif)
    local f = parent:CreateFontString(nil, 'OVERLAY')
    local base = GameFontNormal and select(1, GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
    if GameFontNormal then f:SetFontObject(GameFontNormal) end
    -- Blizzard's Friz Quadrata everywhere (matches the character frame); no decorative serif.
    f:SetFont(base, size or 12, '')
    f:SetShadowColor(0, 0, 0, .95); f:SetShadowOffset(1, -1)
    if x then f:SetPoint('TOPLEFT', x, y) end
    if w then f:SetWidth(w) end
    if h then f:SetHeight(h) end
    f:SetJustifyH(justify or 'LEFT'); f:SetJustifyV('TOP')
    f:SetWordWrap(h ~= nil and h > (size or 12) * 1.7)
    local c = rgb(color); f:SetTextColor(c[1], c[2], c[3], 1)
    f:SetText(value or '')
    function f:SetColor(name) local cc = rgb(name); self:SetTextColor(cc[1], cc[2], cc[3], 1) end
    return f
end
local function gradient(t, a1, a2)
    if CreateColor and t.SetGradient then
        if pcall(t.SetGradient, t, 'VERTICAL', CreateColor(a1[1], a1[2], a1[3], a1[4]), CreateColor(a2[1], a2[2], a2[3], a2[4])) then return end
    end
    if t.SetGradientAlpha then pcall(t.SetGradientAlpha, t, 'VERTICAL', a1[1], a1[2], a1[3], a1[4], a2[1], a2[2], a2[3], a2[4]) end
end
UI.Gradient = gradient
function UI.Box(parent, x, y, w, h, bg, border)
    local p = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
    p:SetSize(w, h)
    if x then p:SetPoint('TOPLEFT', x, y) end
    p:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    local b, e = bg or {.035, .045, .080, .97}, border or {.50, .39, .21, .95}
    p:SetBackdropColor(b[1], b[2], b[3], b[4] or 1); p:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
    return p
end
local function corner(p, point, dx, dy)
    local t = p:CreateTexture(nil, 'OVERLAY'); t:SetTexture(WHITE); t:SetVertexColor(.95, .76, .38, 1)
    t:SetSize(5, 5); t:SetPoint('CENTER', p, point, dx, dy); t:SetRotation(math.pi / 4)
end
function UI.Panel(parent, x, y, w, h, title, number)
    local p = UI.Box(parent, x, y, w, h)
    local g = p:CreateTexture(nil, 'BACKGROUND', nil, 1); g:SetTexture(WHITE)
    g:SetPoint('TOPLEFT', 1, -1); g:SetPoint('BOTTOMRIGHT', -1, 1)
    gradient(g, {.018, .024, .050, .96}, {.060, .078, .140, .96})
    corner(p, 'TOPLEFT', 0, 0); corner(p, 'TOPRIGHT', 0, 0); corner(p, 'BOTTOMLEFT', 0, 0); corner(p, 'BOTTOMRIGHT', 0, 0)
    if title then
        local x0 = 10
        if number then
            local badge = UI.Box(p, 8, -7, 16, 16, {.12, .09, .03, 1}, {.92, .73, .36, 1})
            local n = UI.Text(badge, 0, -2, 16, nil, 10, tostring(number), 'gold', 'CENTER')
            n:SetPoint('TOPLEFT', 0, -2)
            x0 = 30
        end
        p.title = UI.Text(p, x0, -9, w - x0 - 10, nil, 12, title, 'gold')
        local line = p:CreateTexture(nil, 'ARTWORK'); line:SetTexture(WHITE); line:SetVertexColor(.62, .47, .24, .55)
        line:SetPoint('TOPLEFT', 8, -27); line:SetPoint('TOPRIGHT', -8, -27); line:SetHeight(1)
    end
    return p
end
local STYLE = {primary = {{.08, .26, .62, 1}, {.36, .62, 1, 1}, 'text'}, gold = {{.24, .16, .05, 1}, {.92, .73, .36, 1}, 'gold'},
               purple = {{.25, .12, .45, 1}, {.66, .46, 1, 1}, 'text'}, default = {{.06, .08, .14, 1}, {.28, .34, .48, 1}, 'text'},
               active = {{.16, .12, .30, 1}, {.70, .52, 1, 1}, 'gold'}}
function UI.Button(parent, x, y, w, h, label, onClick, style)
    local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
    b:SetSize(w, h)
    if x then b:SetPoint('TOPLEFT', x, y) end
    b:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    b.label = UI.Text(b, nil, nil, w - 8, nil, h >= 26 and 12 or 11, label, 'text', 'CENTER')
    b.label:SetPoint('CENTER', 0, 0)
    local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, .08)
    function b:SetStyle(name)
        local s = STYLE[name or 'default'] or STYLE.default
        self:SetBackdropColor(unpack(s[1])); self:SetBackdropBorderColor(unpack(s[2])); self.label:SetColor(s[3])
        self.style = name
    end
    function b:SetLabel(text) self.label:SetText(text or '') end
    function b:SetUsable(on) self:SetEnabled(on); self:SetAlpha(on and 1 or .45) end
    b:SetStyle(style)
    b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    b:SetScript('OnClick', function(self, mouse) if not combat() and onClick then onClick(self, mouse) end end)
    return b
end
function UI.Tooltip(frame, title, lines)
    frame:HookScript('OnEnter', function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:SetText(type(title) == 'function' and title() or title, .96, .79, .43)
        local body = type(lines) == 'function' and lines() or lines
        for _, line in ipairs(type(body) == 'table' and body or {body}) do GameTooltip:AddLine(line, .85, .88, .95, true) end
        GameTooltip:Show()
    end)
    frame:HookScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end
function UI.Check(parent, x, y, label, get, set, tip)
    local b = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
    b:SetSize(20, 20); b:SetPoint('TOPLEFT', x, y)
    b.caption = UI.Text(parent, x + 21, y - 4, nil, nil, 11, label, 'text')
    b:SetScript('OnClick', function(self)
        if combat() then self:SetChecked(get() and true or false); return end
        set(self:GetChecked() and true or false)
    end)
    function b:Sync() self:SetChecked(get() and true or false) end
    if tip then UI.Tooltip(b, label, tip) end
    return b
end
local menu
local function closeMenu() if menu then menu:Hide(); menu.owner = nil end end
UI.CloseMenu = closeMenu
function UI.Dropdown(parent, x, y, w, options, get, set)
    local b
    b = UI.Button(parent, x, y, w, 20, '', function()
        if menu and menu:IsShown() and menu.owner == b then closeMenu(); return end
        if not menu then
            menu = UI.Box(UIParent, nil, nil, 10, 10, {.03, .04, .08, .98}, {.62, .48, .26, 1})
            menu:SetFrameStrata('FULLSCREEN_DIALOG'); menu:SetClampedToScreen(true); menu.rows = {}
            menu:SetScript('OnUpdate', function(self) if not self.owner or not self.owner:IsVisible() then closeMenu() end end)
        end
        local list = type(options) == 'function' and options() or options
        menu:SetScale(b:GetEffectiveScale() / UIParent:GetEffectiveScale())
        menu:SetSize(w, 4 + #list * 18); menu:ClearAllPoints(); menu:SetPoint('TOPLEFT', b, 'BOTTOMLEFT', 0, -1)
        for _, row in ipairs(menu.rows) do row:Hide() end
        for i, option in ipairs(list) do
            local row = menu.rows[i]
            if not row then
                row = UI.Button(menu, 2, 0, w - 4, 17, '', nil); row:SetBackdropBorderColor(0, 0, 0, 0)
                row.label:ClearAllPoints(); row.label:SetPoint('LEFT', 6, 0); row.label:SetJustifyH('LEFT')
                menu.rows[i] = row
            end
            row:SetWidth(w - 4); row.label:SetWidth(w - 12)
            row:ClearAllPoints(); row:SetPoint('TOPLEFT', 2, -2 - (i - 1) * 18)
            row:SetLabel(option.text); row:SetScript('OnClick', function() closeMenu(); set(option.value) end)
            row:SetBackdropColor(option.value == get() and .16 or .03, option.value == get() and .12 or .04, option.value == get() and .30 or .08, 1)
            row:Show()
        end
        menu.owner = b; menu:Show()
    end)
    b.label:ClearAllPoints(); b.label:SetPoint('LEFT', 6, 0); b.label:SetWidth(w - 22); b.label:SetJustifyH('LEFT')
    local arrow = b:CreateTexture(nil, 'OVERLAY'); arrow:SetTexture('Interface\\ChatFrame\\ChatFrameExpandArrow')
    arrow:SetSize(10, 10); arrow:SetPoint('RIGHT', -5, 0); arrow:SetRotation(-math.pi / 2)
    function b:Sync()
        local list, value = type(options) == 'function' and options() or options, get()
        local text = '–'
        for _, option in ipairs(list) do if option.value == value then text = option.text end end
        self:SetLabel(text)
    end
    return b
end
function UI.Bar(parent, x, y, w, h, color)
    local bg = parent:CreateTexture(nil, 'ARTWORK'); bg:SetTexture(WHITE); bg:SetVertexColor(.14, .17, .25, .95)
    bg:SetPoint('TOPLEFT', x, y); bg:SetSize(w, h)
    local fill = parent:CreateTexture(nil, 'OVERLAY'); fill:SetTexture(WHITE); fill:SetPoint('TOPLEFT', x, y); fill:SetSize(1, h)
    local bar = {bg = bg, fill = fill}
    function bar:Set(frac, c)
        local cc = rgb(c or color)
        frac = num(frac) and math.max(0, math.min(1, frac)) or 0
        fill:SetVertexColor(cc[1], cc[2], cc[3], 1); fill:SetWidth(math.max(1, w * frac)); fill:SetAlpha(frac > 0 and 1 or .25)
    end
    bar:Set(0)
    return bar
end
function UI.Icon(parent, size, x, y, border)
    local holder = CreateFrame('Frame', nil, parent, 'BackdropTemplate'); holder:SetSize(size, size)
    if x then holder:SetPoint('TOPLEFT', x, y) end
    holder:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    holder:SetBackdropColor(0, 0, 0, .8)
    local e = border or {.45, .36, .22, 1}; holder:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
    local t = holder:CreateTexture(nil, 'ARTWORK'); t:SetPoint('TOPLEFT', 1, -1); t:SetPoint('BOTTOMRIGHT', -1, 1)
    t:SetTexCoord(.07, .93, .07, .93); holder.icon = t
    function holder:SetIcon(path) self.icon:SetTexture(path or 'Interface\\Icons\\INV_Misc_QuestionMark') end
    return holder
end
function UI.ClassIcon(texture, class)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[string.upper(class or '')] or CLASS_COORDS[class or '']
    texture:SetTexture('Interface\\TargetingFrame\\UI-Classes-Circles')
    if coords then texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end
function UI.LineChart(parent, x, y, w, h, color, fillAlpha)
    local c = CreateFrame('Frame', nil, parent); c:SetSize(w, h); c:SetPoint('TOPLEFT', x, y)
    for i = 0, 3 do
        local g = c:CreateTexture(nil, 'BACKGROUND'); g:SetTexture(WHITE); g:SetVertexColor(.30, .36, .50, i == 0 and .7 or .25)
        g:SetPoint('BOTTOMLEFT', 0, h * i / 3); g:SetSize(w, 1)
    end
    c.lines, c.fills, c.yLabels, c.xLabels = {}, {}, {}, {}
    for i = 1, 3 do c.yLabels[i] = UI.Text(parent, x - 34, y - h + h * i / 3 + 5, 30, nil, 9, '', 'muted', 'RIGHT') end
    for i = 1, 6 do c.xLabels[i] = UI.Text(parent, x + w * (i - 1) / 5 - 15, y - h - 3, 30, nil, 9, '', 'muted', 'CENTER') end
    c.empty = UI.Text(c, 0, -h / 2 + 6, w, nil, 11, '', 'muted', 'CENTER')
    function c:SetData(values, maxValue, duration, labelFn)
        for _, l in ipairs(self.lines) do l:Hide() end
        for _, f in ipairs(self.fills) do f:Hide() end
        local n = #(values or {})
        self.empty:SetText(n < 2 and 'Keine Trace-Daten' or '')
        local top = num(maxValue) or 0
        for _, v in ipairs(values or {}) do top = math.max(top, num(v) or 0) end
        if top <= 0 then top = 1 end
        for i = 1, 3 do self.yLabels[i]:SetText(n >= 2 and (labelFn and labelFn(top * i / 3) or thousands(top * i / 3)) or '') end
        for i = 1, 6 do self.xLabels[i]:SetText(n >= 2 and duration and string.format('%d', duration * (i - 1) / 5) or '') end
        if n < 2 then return end
        local cc = rgb(color)
        for i = 1, n do
            local px = (i - 1) / (n - 1) * w
            local py = math.max(0, math.min(1, (num(values[i]) or 0) / top)) * h
            local f = self.fills[i]
            if not f then f = self:CreateTexture(nil, 'BORDER'); f:SetTexture(WHITE); self.fills[i] = f end
            f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', math.max(0, px - w / (2 * (n - 1))), 0)
            f:SetSize(math.max(1, w / (n - 1)), math.max(1, py)); f:SetVertexColor(cc[1], cc[2], cc[3], fillAlpha or .16); f:Show()
            if i < n then
                local qx = i / (n - 1) * w
                local qy = math.max(0, math.min(1, (num(values[i + 1]) or 0) / top)) * h
                local l = self.lines[i]
                if self.CreateLine then
                    if not l then l = self:CreateLine(nil, 'ARTWORK'); l:SetThickness(2); self.lines[i] = l end
                    l:SetColorTexture(cc[1], cc[2], cc[3], 1)
                    l:SetStartPoint('BOTTOMLEFT', self, px, py); l:SetEndPoint('BOTTOMLEFT', self, qx, qy); l:Show()
                else
                    if not l then l = self:CreateTexture(nil, 'ARTWORK'); l:SetTexture(WHITE); self.lines[i] = l end
                    l:ClearAllPoints(); l:SetPoint('BOTTOMLEFT', px, math.min(py, qy)); l:SetSize(math.max(1, qx - px), math.max(2, math.abs(qy - py)))
                    l:SetVertexColor(cc[1], cc[2], cc[3], 1); l:Show()
                end
            end
        end
    end
    return c
end
function UI.Donut(parent, x, y, size, thickness)
    local d = CreateFrame('Frame', nil, parent); d:SetSize(size, size); d:SetPoint('TOPLEFT', x, y)
    local N, radius = 72, (size - thickness) / 2
    d.segments = {}
    for i = 1, N do
        local a = (i - .5) / N * 2 * math.pi
        local t = d:CreateTexture(nil, 'ARTWORK'); t:SetTexture(WHITE)
        t:SetSize(math.pi * size / N + 1.2, thickness)
        t:SetPoint('CENTER', d, 'CENTER', math.sin(a) * radius, math.cos(a) * radius); t:SetRotation(-a)
        d.segments[i] = t
    end
    function d:SetSlices(slices)
        local total = 0
        for _, s in ipairs(slices or {}) do total = total + (num(s.value) or 0) end
        for i, t in ipairs(self.segments) do
            local at, acc, color = (i - .5) / N, 0, {.18, .21, .30}
            if total > 0 then
                for _, s in ipairs(slices) do
                    acc = acc + (num(s.value) or 0) / total
                    if at <= acc then color = s.color; break end
                end
            end
            t:SetVertexColor(color[1], color[2], color[3], 1)
        end
    end
    d:SetSlices({})
    return d
end
function UI.ItemIcon(id)
    if not id then return nil end
    local icon = safe(C_Item and C_Item.GetItemIconByID, id) or safe(GetItemIcon, id)
    return icon
end
local function spellInfo(id)
    if not id or not P.spellDisplay then return nil, nil end
    return safe(P.spellDisplay, id)
end
UI.SpellInfo = spellInfo

-- State ---------------------------------------------------------------------
-- One page, one window. Everything is controlled from here; values come from the
-- Combat Engine, the live character and SavedVariables only.
local function settings()
    ForeverSimBridgeDB = ForeverSimBridgeDB or {}
    local db = ForeverSimBridgeDB
    db.dashboard = db.dashboard or {}
    local s = db.dashboard
    if s.autoEnemy == nil then s.autoEnemy = true end
    if s.duration ~= 60 then s.duration = 60 end
    return s
end
local S = {trace = nil, gear = {rows = {}}, questItems = {}, weights = nil}
D.state = S
local function app() return P.app end
local function profile() return app() and app().state.character.profile end
local function snapshot() return app() and app().state.character.snapshot end
local function liveClass()
    local _, token = safe(UnitClass, 'player')
    return type(token) == 'string' and string.lower(token) or nil
end
local function liveLevel() return num(safe(UnitLevel, 'player')) or 1 end
local function message(text) S.notice = text; if D.Refresh then D.Refresh() end end
local function rotation()
    local saved = app() and app().state.rotation
    if saved and saved.revision == P.revision then return saved.result, false end
    local old = P.lastRotation or (ForeverSimBridgeDB and ForeverSimBridgeDB.rotationResult)
    if old and num(old.dps) then return old, true end
end
local function abilityFor(model, key)
    local ranks = model and model.abilities and model.abilities[key]
    return ranks and ranks[#ranks]
end
local function displayKey(model, key)
    local base = type(key) == 'string' and key:gsub(':swings$', '') or key
    local ability = abilityFor(model, base)
    local name, icon = spellInfo(ability and ability.id)
    if not name and model and model.petSpellRanks and model.petSpellRanks[base] then
        local r = model.petSpellRanks[base][1]; name, icon = spellInfo(r and r.id)
    end
    if not name then
        if base == 'melee' then name = 'Begleiter (Nahkampf)'
        elseif base == 'autoAttack' or base == 'autoShot' then name = 'Automatischer Schuss'
        else name = tostring(base or '?'):gsub('(%l)(%u)', '%1 %2'); name = name:sub(1, 1):upper() .. name:sub(2) end
    end
    return name, icon
end
D.DisplayKey = displayKey

-- Benchmark enemy by level (ZIELE.md, Ziel 4): 1-30 quest mobs, 31-49 dungeon bosses, 50-60 raid bosses.
-- Elite stays available as a manual choice under "Mehr".
local ENEMY = {{value = 'auto', text = 'Levelgegner (automatisch)'}, {value = 'quest', text = 'Questgegner'}, {value = 'elite', text = 'Elitegegner'},
               {value = 'dungeon', text = 'Dungeonboss'}, {value = 'standard', text = 'Raidboss'}}
local ENEMY_NAME = {quest = 'Questgegner', elite = 'Elitegegner', dungeon = 'Dungeonboss', standard = 'Raidboss'}
local function enemyForLevel(level)
    if level <= 30 then return 'quest' elseif level <= 49 then return 'dungeon' end
    return 'standard'
end
local function request() return ForeverSimBridgeDB and ForeverSimBridgeDB.encounter or {} end
local function resolved()
    return P.encounters and P.encounters.Resolve(liveLevel(), request())
end
local function applyAutoEnemy()
    if not settings().autoEnemy or combat() or not P.encounters then return end
    local want = enemyForLevel(liveLevel())
    local req = request()
    if req.mode ~= want or req.dungeon or req.boss then
        P.encounters.Configure({mode = want, offset = 0})
    end
end

-- Stats the client can actually convert; missing conversions are skipped, not guessed.
local CASTER_STATS = {{'sp', 'Zaubermacht', 10}, {'hitPct', 'Trefferchance', 1}, {'critPct', 'Kritisch', 1}, {'hastePct', 'Tempo', 1}, {'int', 'Intelligenz', 10}}
local PHYSICAL_STATS = {{'agi', 'Beweglichkeit', 10}, {'ap', 'Angriffskraft', 20}, {'critPct', 'Kritisch', 1}, {'hitPct', 'Trefferchance', 1}, {'str', 'Stärke', 10}, {'int', 'Intelligenz', 10}}
local function intConvertible(model, p)
    local data = P.classModel and P.classModel(model, p) or model
    if not data.typedCombat then return true end
    local rate = (p.stats or {}).critPerIntellect or (p.level == 60 and data.critPerIntellect60)
    return rate and rate > 0
end
local AGI60 = {warrior = true, paladin = true, hunter = true, rogue = true, druid = true}
local function agiConvertible(model, p)
    local data = P.classModel and P.classModel(model, p) or model
    if not data.typedCombat then return true end
    return (p.stats or {}).critPerAgility ~= nil or (p.level == 60 and AGI60[data.id])
end
local function statList(model, p)
    local data = P.classModel and P.classModel(model, p) or model
    local list = {}
    for _, s in ipairs(data.typedCombat and PHYSICAL_STATS or CASTER_STATS) do
        if (s[1] ~= 'int' or intConvertible(model, p)) and (s[1] ~= 'agi' or agiConvertible(model, p)) then list[#list + 1] = s end
    end
    return list
end
local function itemBlocked(model, p, item)
    local stats = item.stats or {}
    if (stats.int or 0) ~= 0 and not intConvertible(model, p) then return 'Intelligenz-Umrechnung liefert der Client auf diesem Level nicht' end
    if (stats.agi or 0) ~= 0 and not agiConvertible(model, p) then return 'Beweglichkeit-Umrechnung liefert der Client auf diesem Level nicht' end
end

-- Calculations ----------------------------------------------------------------
local function levelingMode()
    local e = resolved()
    return e and (e.mode == 'quest' or e.mode == 'elite')
end
local function currentLeveling()
    local l = S.leveling
    if l and l.revision == P.revision then return l end
end
local function currentChoice(ctx)
    local l = currentLeveling()
    if l then return l.choice, l.baselineChoice end
    local r = rotation()
    local fresh = r and app().state.rotation and app().state.rotation.result == r
    return fresh and r.choice or (not P.stale and P.lastRotation and P.lastRotation.choice) or P.candidates(ctx.model, ctx.profile)[1], fresh and r.baselineChoice
end
function D.RunTrace()
    if combat() then return end
    if S.traceBusy and S.traceRevision == P.revision then return end
    local ctx, issue = P.actions.Context()
    if not ctx then S.traceError = issue and issue.message; D.Refresh(); return end
    local choice = currentChoice(ctx)
    if not choice then S.traceError = 'Keine erlernte Rotation verfügbar.'; D.Refresh(); return end
    local rev = P.revision
    S.traceBusy, S.traceRevision, S.traceError = true, rev, nil
    P.enqueue(function()
        local test = P.copy(ctx.profile); test.trace = true
        local spec = P.compile(ctx.model, test, ctx.stats, choice, 60, 7331)
        spec.resourceKind = ctx.profile.form == 'cat' and 'energy' or ctx.profile.form == 'bear' and 'rage' or ctx.model.resource
        local out = P.run(spec)
        local summary = P.scenarioStudio and P.scenarioStudio.SummarizeTrace(out, spec, 30)
        if not summary then error('Trace-Auswertung fehlgeschlagen') end
        local actorKeys = {}
        for _, actor in ipairs(spec.actors or {}) do
            if actor.spell then actorKeys[actor.spell.key or ''] = true end
            if actor.melee then actorKeys[actor.melee.key or 'melee'] = true end
            for _, bonus in ipairs(actor.hitBonuses or {}) do actorKeys[bonus.key or ''] = true end
        end
        local ability, pet, misc, casts = 0, 0, 0, {}
        for key, row in pairs(out.bySpell or {}) do
            local dmg = num(row.damage) or 0
            if actorKeys[key] then pet = pet + dmg elseif spec.abilities[key] then ability = ability + dmg else misc = misc + dmg end
        end
        for _, e in ipairs(out.events or {}) do
            if e.kind == 'start' and type(e.key) == 'string' and not actorKeys[e.key] then casts[e.key] = (casts[e.key] or 0) + 1 end
        end
        -- Damage per own ability for "Woher dein Schaden kommt"; pet damage stays one bucket.
        local spells = {}
        for key, row in pairs(out.bySpell or {}) do
            local dmg = num(row.damage) or 0
            if dmg > 0 and not actorKeys[key] and spec.abilities[key] then spells[#spells + 1] = {key = key, damage = dmg} end
        end
        table.sort(spells, function(a, b) return a.damage > b.damage end)
        return {dps = num(out.dps), total = num(out.total), summary = summary, ability = ability, pet = pet, misc = misc, casts = casts, spells = spells, class = ctx.profile.class}
    end, function(result, err)
        S.traceBusy = false; if S.run then S.run.done.trace = true end
        if err or not result then S.traceError = 'Verlauf nicht berechenbar: ' .. tostring(err or 'kein Ergebnis')
        else result.revision = rev; S.trace = result end
        D.Refresh()
    end, function() return rev == P.revision end)
end
function D.RunWeights()
    if combat() then return end
    if S.weightsBusy and S.weightsRevision == P.revision then return end
    local ctx, issue = P.actions.Context()
    if not ctx then S.weightsError = issue and issue.message; D.Refresh(); return end
    local choice = currentChoice(ctx)
    if not choice then return end
    local list, rev = statList(ctx.model, ctx.profile), P.revision
    S.weightsBusy, S.weightsRevision, S.weightsError = true, rev, nil
    P.enqueue(function()
        local base = P.score(ctx.model, ctx.profile, ctx.stats, choice, 2, 153)
        local rows = {}
        for _, stat in ipairs(list) do
            local modified = P.copy(ctx.stats); modified[stat[1]] = (modified[stat[1]] or 0) + stat[3]
            local trial = P.score(ctx.model, ctx.profile, modified, choice, 2, 153)
            rows[#rows + 1] = {key = stat[1], name = stat[2], perPoint = (trial - base) / stat[3]}
            if P.checkpoint then P.checkpoint() end
        end
        return {base = base, rows = rows}
    end, function(result, err)
        S.weightsBusy = false; if S.run then S.run.done.weights = true end
        if err or not result then S.weightsError = 'Stat-Gewichte nicht berechenbar: ' .. tostring(err or '')
        else result.revision = rev; S.weights = result end
        D.Refresh()
    end, function() return rev == P.revision end)
end
local function candidateItems()
    local snap = safe(P.capture, false)
    local list, seen = {}, {}
    local function add(item, origin)
        if type(item) == 'table' and item.id and not seen[item.id] then seen[item.id] = true; item.origin = origin; list[#list + 1] = item end
    end
    for _, item in ipairs(snap and snap.bagItems or {}) do add(item, 'Tasche') end
    for _, item in ipairs(S.questItems) do add(item, 'Questbelohnung') end
    -- Bank (remembered while it was open) and dungeon loot of the journal for this level (ZIELE.md, Ziel 1).
    local score = P.itemScore
    for _, link in ipairs(score and score.BankLinks and score.BankLinks() or {}) do
        local item = P.readItem and P.readItem(link, 'Bank')
        if item then add(item, 'Bank') end
    end
    local api = _G.ForeverSimDungeonAPI
    if api and api.LootCandidates and P.readItem then
        for _, c in ipairs(api.LootCandidates(liveLevel(), 30)) do
            local item = P.readItem('item:' .. c.id, 'Dungeon Journal')
            if item then item.boss, item.dungeon, item.dungeonKey = c.boss, c.dungeon, c.dungeonKey; add(item, 'Dungeon Journal') end
        end
    end
    return list
end
function D.CheckGear()
    if combat() then return end
    local g = S.gear
    if g.busy and g.revision == P.revision then return end
    local ctx, issue = P.actions.Context()
    if not ctx then g.error = issue and issue.message; D.Refresh(); return end
    local items, rev = candidateItems(), P.revision
    -- Fixed per-spec weights only order the candidates (likely upgrades first). The shown number is always the simulation.
    local weights = P.statWeights60
    local spec = weights and weights.SpecOf(ctx.profile)
    if weights and spec and weights.Get(ctx.profile.class, spec) then
        local score = {}
        for _, item in ipairs(items) do score[item] = weights.Score(ctx.profile.class, spec, item.stats) or 0 end
        table.sort(items, function(a, b) return score[a] > score[b] end)
    end
    g.rows, g.error, g.busy, g.revision, g.done, g.total = {}, nil, true, rev, 0, #items
    if #items == 0 then g.busy = false; g.error = 'Keine Ausrüstung in Taschen oder Questbelohnungen gefunden.'; D.Refresh(); return end
    local start = not P.stale and P.lastRotation and P.lastRotation.choice or nil
    P.enqueue(function()
        local base = P.best(ctx.model, ctx.profile, ctx.stats, start)
        local rows = {}
        for _, item in ipairs(items) do
            -- No pcall: P.compare yields between slices (Lua 5.1 cannot yield across pcall).
            local reason = P.checkEligibility(ctx.model, ctx.profile, item, ctx.profile.equipped) or itemBlocked(ctx.model, ctx.profile, item)
            if reason then rows[#rows + 1] = {item = item, reason = reason}
            else
                local result = P.compare(ctx.model, ctx.profile, ctx.profile.equipped, item, base)
                rows[#rows + 1] = {item = item, result = result.eligible and result or nil, reason = result.reason}
            end
            g.done = #rows
            if P.checkpoint then P.checkpoint() end
        end
        return rows
    end, function(rows, err)
        if g.revision~=rev then return end
        g.busy = false; if S.run then S.run.done.gear = true end
        if err or not rows then g.error = 'Gear-Vergleich nicht möglich: ' .. tostring(err or '')
        else
            table.sort(rows, function(a, b) return (a.result and num(a.result.delta) or -1e9) > (b.result and num(b.result.delta) or -1e9) end)
            g.rows = rows
        end
        D.Refresh()
    end, function() return rev == P.revision end)
end
-- Rotation first; the other calculations follow once it is finished.
function D.RunAll()
    if combat() then return end
    applyAutoEnemy()
    S.run = {start = GetTime and GetTime() or 0, leveling = levelingMode(), done = {}}
    S.chain = {revision = P.revision}
    local a = app()
    local open = a.Open
    a.Open = function() end
    local ok, err = pcall(P.actions.RunRotation)
    a.Open = open
    if not ok then S.chain = nil; message(tostring(err)) end
    D.Refresh()
end
-- Leveling (quest/elite enemies): rank rotations by kill time against the modelled
-- enemy HP instead of long-fight DPS. DoT ordering is tested both ways.
local function variants(choice)
    local out = {choice}
    local pols = choice.policies or {}
    local front, back, rest, auto = {}, {}, {}, {}
    for _, pol in ipairs(pols) do
        if pol.key == 'autoAttack' or pol.key == 'autoShot' then auto[#auto + 1] = pol
        elseif pol.maintain then front[#front + 1] = pol else rest[#rest + 1] = pol end
    end
    if #front > 0 and #rest > 0 then
        local a, b = P.copy(choice), P.copy(choice)
        a.policies, b.policies = {}, {}
        for _, x in ipairs(front) do a.policies[#a.policies + 1] = P.copy(x) end
        for _, x in ipairs(rest) do a.policies[#a.policies + 1] = P.copy(x); b.policies[#b.policies + 1] = P.copy(x) end
        for _, x in ipairs(front) do b.policies[#b.policies + 1] = P.copy(x) end
        for _, x in ipairs(auto) do a.policies[#a.policies + 1] = P.copy(x); b.policies[#b.policies + 1] = P.copy(x) end
        out[#out + 1] = a; out[#out + 1] = b
    end
    return out
end
function D.RunLeveling(after)
    local ctx = P.actions.Context()
    if not ctx or not P.leveling then if after then after() end return end
    local opts = P.leveling.Context(ctx.profile)
    if not opts.targetHealth then S.levelingError = 'Gegner-HP unbekannt'; if after then after() end return end
    opts.runs = 12
    local r = app().state.rotation and app().state.rotation.result
    local list = {}
    if r then list[#list + 1] = r.choice; list[#list + 1] = r.baselineChoice end
    for _, c in ipairs(P.candidates(ctx.model, ctx.profile)) do list[#list + 1] = c end
    local rev = P.revision
    S.levelingBusy = true
    P.enqueue(function()
        local seen, results = {}, {}
        for _, base in ipairs(list) do
            for _, c in ipairs(variants(base)) do
                local key = P.canonical(c)
                if not seen[key] then
                    seen[key] = true
                    local e = P.leveling.Evaluate(ctx.model, ctx.profile, ctx.stats, c, opts)
                    if e.available and e.killSeconds and (e.failures or 0) == 0 then results[#results + 1] = {choice = P.copy(c), eval = e} end
                end
            end
        end
        table.sort(results, function(a, b) return a.eval.killSeconds < b.eval.killSeconds end)
        local start = r and r.baselineChoice and P.canonical(r.baselineChoice)
        local startKill
        for _, x in ipairs(results) do if P.canonical(x.choice) == start then startKill = x.eval.killSeconds end end
        local best = results[1]
        if not best then error('Kein Modellkampf gewonnen') end
        local dps = P.score(ctx.model, ctx.profile, ctx.stats, best.choice, 2, 21)
        return {choice = best.choice, baselineChoice = r and r.baselineChoice, killSeconds = best.eval.killSeconds,
                startKill = startKill, hp = opts.targetHealth,hpSource=opts.source,hpEstimated=opts.estimated, dps = dps, tested = #results, killsPerMinute = best.eval.killsPerMinute}
    end, function(res, err)
        S.levelingBusy = false; if S.run then S.run.done.leveling = true end
        if err or not res then S.levelingError = 'Kill-Zeit nicht berechenbar: ' .. tostring(err or '')
        else
            res.revision = rev; S.leveling = res; S.levelingError = nil
            -- The combat rotation field shows exactly what the dashboard shows.
            local result = {purpose = 'leveling', choice = P.copy(res.choice), dps = res.dps, baselineDps = res.dps, percentOfStart = 100, accepted = true}
            P.lastRotation, P.stale = result, false
            ForeverSimBridgeDB.rotationResult = P.copy(result)
            if P.rotationHUD and P.rotationHUD.configure then pcall(P.rotationHUD.configure, ctx.model, ctx.profile, result) end
        end
        if after then after() end
        D.Refresh()
    end, function() return rev == P.revision end)
end
local function advanceChain()
    local chain = S.chain
    if not chain then return end
    local run = app() and app().state.simulation
    if not run or run.status == 'running' then return end
    S.chain = nil
    if run.status == 'complete' and app().state.rotation and app().state.rotation.revision == P.revision then
        local rest = function() D.RunTrace(); D.RunWeights(); D.CheckGear() end
        if levelingMode() then D.RunLeveling(rest)
        else
            S.leveling = nil
            pcall(P.actions.ApplyRotation)
            rest()
        end
    end
end
local questEvents = CreateFrame('Frame')
for _, name in ipairs({'QUEST_DETAIL', 'QUEST_COMPLETE'}) do pcall(questEvents.RegisterEvent, questEvents, name) end
questEvents:SetScript('OnEvent', function()
    if not (GetQuestItemLink and P.readItem) then return end
    local out = {}
    for kind, count in pairs({choice = safe(GetNumQuestChoices) or 0, reward = safe(GetNumQuestRewards) or 0}) do
        for i = 1, count do
            local link = safe(GetQuestItemLink, kind, i)
            local item = link and safe(P.readItem, link, 'Questbelohnung')
            if item then out[#out + 1] = item end
        end
    end
    if #out > 0 then S.questItems = out end
end)

-- Trait entry per talent spell (C_Traits), used to show a tooltip for a chosen rank.
local traitEntries
function D.TraitEntry(spellId)
    if not spellId then return nil end
    if not traitEntries then
        if combat() or not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return nil end
        local map = {}
        local config = safe(C_ClassTalents.GetActiveConfigID)
        local info = config and safe(C_Traits.GetConfigInfo, config)
        for _, treeID in ipairs(info and info.treeIDs or {}) do
            for _, nodeID in ipairs(safe(C_Traits.GetTreeNodes, treeID) or {}) do
                local node = safe(C_Traits.GetNodeInfo, config, nodeID)
                for _, entryID in ipairs(node and node.entryIDs or {}) do
                    local entry = safe(C_Traits.GetEntryInfo, config, entryID)
                    local def = entry and entry.definitionID and safe(C_Traits.GetDefinitionInfo, entry.definitionID)
                    if def and def.spellID then map[def.spellID] = entryID end
                end
            end
        end
        if next(map) then traitEntries = map else return nil end
    end
    return traitEntries[spellId]
end

-- Talent draft (stored with the existing planner drafts) ------------------------
local function draftStore(class)
    ForeverSimBridgeDB.talentPlannerDrafts = ForeverSimBridgeDB.talentPlannerDrafts or {}
    local d = ForeverSimBridgeDB.talentPlannerDrafts
    if type(d[class]) ~= 'table' then d[class] = {ranks = {}} end
    if type(d[class].ranks) ~= 'table' then d[class].ranks = {} end
    return d[class]
end
local function liveRanks()
    local ranks, points = {}, {}
    for i, tree in ipairs(snapshot() and snapshot().talents or {}) do
        points[i] = tree.points or 0
        for _, e in ipairs(tree.entries or {}) do if e.classKey then ranks[e.classKey] = e.rank end end
    end
    return ranks, points
end
local function draftRanks(class)
    local store = draftStore(class)
    if not store.touched then
        local live = liveRanks()
        store.ranks = {}
        for k, v in pairs(live) do store.ranks[k] = v end
    end
    return store.ranks
end
local function changeTalent(class, node, delta)
    local data = FUSLiveData and FUSLiveData[class]
    local store = draftStore(class)
    local ranks = draftRanks(class)
    local old = ranks[node.key] or 0
    local new = math.max(0, math.min(node.maxRank or 1, old + delta))
    if new == old then return end
    ranks[node.key] = new
    local ok, reason = true, nil
    if P.talentBuild and data then ok, reason = P.talentBuild.validate(data, ranks, liveLevel()) end
    -- Removing a point may orphan deeper talents: remove those (deepest rows first) instead of refusing.
    if not ok and delta < 0 and data then
        local tree
        for _, t in ipairs(data.talentTrees or {}) do for _, n in ipairs(t.talents or {}) do if n.key == node.key then tree = t end end end
        for row = 6, (node.row or 0) + 1, -1 do
            if ok then break end
            for _, n in ipairs(tree and tree.talents or {}) do if n.row == row then ranks[n.key] = nil end end
            ok, reason = P.talentBuild.validate(data, ranks, liveLevel())
        end
    end
    if not ok then ranks[node.key] = old; S.talentMessage = tostring(reason or 'Ungültiger Talentpunkt'); S.talentError = true
    else store.touched = true; S.talentMessage = nil; S.talentError = nil; S.talentCompare = nil end
    D.Refresh()
end
-- Reset clears the plan; "Live übernehmen" copies the talents you actually have.
function D.ResetTalents()
    local store = draftStore(liveClass() or 'warlock')
    store.touched = true; store.ranks = {}
    S.talentMessage, S.talentError, S.talentCompare = 'Entwurf geleert. „Live übernehmen“ holt deine echten Talente zurück.', nil, nil
    D.Refresh()
end
function D.UseLiveTalents()
    local store = draftStore(liveClass() or 'warlock')
    store.touched = nil; store.ranks = {}
    S.talentMessage, S.talentError, S.talentCompare = 'Deine aktuellen Talente übernommen.', nil, nil
    D.Refresh()
end
function D.CompareTalents()
    if combat() or S.talentBusy then return end
    local class = liveClass()
    local data = class and FUSLiveData and FUSLiveData[class]
    local ctx, issue = P.actions.Context()
    if not data or not ctx then S.talentMessage = issue and issue.message or 'Klassenmodell fehlt'; D.Refresh(); return end
    local live = ctx.profile
    local draft, reason = P.talentBuild.profile(data, live, draftRanks(class))
    if not draft then S.talentMessage = tostring(reason); D.Refresh(); return end
    local bookIssue = P.talentBuild.spellbookIssue(data, live, draft)
    local coverage = bookIssue or P.coverage(data, draft)
    if coverage then S.talentMessage = tostring(coverage); D.Refresh(); return end
    local original = P.copy(live)
    draft.stats = P.copy(live.stats or {})
    -- Stat talents are applied by the engine as draft-minus-live delta (P.applyTalentStatDeltas).
    -- List chosen talents that have no damage rule at all, so "0 %" is explainable.
    local refs = P.talentBuild.ruleReferences(data)
    if data.petCritValues then refs.ferocity = true end
    local draftR = P.talents(data, draft)
    local unmodeled = {}
    for _, tree in ipairs(data.talentTrees or {}) do for _, n in ipairs(tree.talents or {}) do
        if (draftR[n.key] or 0) > 0 and not refs[n.key] then unmodeled[#unmodeled + 1] = n.name or n.key end
    end end
    local start = currentChoice(ctx)
    if not start then S.talentMessage = 'Keine Startrotation'; D.Refresh(); return end
    local ranksAtClick = P.copy(draftRanks(class))
    local rev = P.revision
    S.talentBusy = rev; S.talentMessage = 'Build wird verglichen (geprüfte Rotationen je Build) ...'; D.Refresh()
    P.enqueue(function()
        -- Each build is scored with its own best rotation; identical seeds for both.
        local liveChoice = P.best(data, original, ctx.stats, start).choice
        local draftChoice = P.best(data, draft, ctx.stats, start).choice
        local base = P.score(data, original, ctx.stats, liveChoice, 6, 411)
        if P.checkpoint then P.checkpoint() end
        local cand = P.score(data, draft, ctx.stats, draftChoice, 6, 411)
        -- DPS share per changed talent (ZIELE.md: values at the talents): the draft without that one change,
        -- same rotation, same seeds. Up to 8 changes; deeper talents that depend on it make "without" invalid -> no value.
        local liveR, ranksNow = liveRanks(), ranksAtClick
        local changed = {}
        for key, rank in pairs(ranksNow) do if rank ~= (liveR[key] or 0) then changed[#changed + 1] = key end end
        for key, rank in pairs(liveR) do if ranksNow[key] == nil and rank ~= 0 then changed[#changed + 1] = key end end
        table.sort(changed)
        local per = {}
        if #changed <= 8 then
            for _, key in ipairs(changed) do
                local without = P.copy(ranksNow); without[key] = liveR[key]
                local wp = P.talentBuild.profile(data, live, without)
                if wp then
                    P.talentBuild.grantAbilities(data,wp);wp.stats=P.copy(live.stats or {})
                    local sc = P.score(data, wp, ctx.stats, draftChoice, 6, 411)
                    if cand > 0 then per[key] = 100 * (cand - sc) / cand end
                end
                if P.checkpoint then P.checkpoint() end
            end
        end
        return {base = base, cand = cand, per = per}
    end, function(r, err)
        if S.talentBusy~=rev then return end
        S.talentBusy = false
        if err or not r or not num(r.base) or r.base <= 0 then S.talentMessage = 'Vergleich nicht berechenbar: ' .. tostring(err or '')
        else
            S.talentMessage = nil
            S.talentCompare = {pct = 100 * (r.cand - r.base) / r.base, base = r.base, cand = r.cand, unmodeled = unmodeled, per = r.per or {}}
        end
        D.Refresh()
    end, function() return rev == P.revision end)
end

-- Level paths (ZIELE.md, Ziel 2, level 10-49: Baum gegen Baum) ------------------------
-- Every tree gets the same path: all available points into that tree, talents with a SIM rule first,
-- rows and prerequisites respected. The result is a real, valid build per tree.
local function availablePoints()
    local bonus = P.talentBonus and P.talentBonus() or 0
    return math.max(0, math.min(51, liveLevel() - 9 + bonus))
end
local function treePath(data, tree, points, refs,variant)
    local ranks, spent = {}, 0
    local nodes = tree.talents or {}
    local byKey = {}
    for _, n in ipairs(nodes) do byKey[n.key] = n end
    local rowPoints = data.talentTreeRowPoints or 5
    while spent < points do
        local pick, pickScore
        for _, n in ipairs(nodes) do
            local cur = ranks[n.key] or 0
            if cur < (n.maxRank or 1) then
                local earlier = 0
                for _, o in ipairs(nodes) do if (o.row or 0) < (n.row or 0) then earlier = earlier + (ranks[o.key] or 0) end end
                local pre = n.prereqKey and byKey[n.prereqKey]
                if earlier >= (n.row or 0) * rowPoints and (not pre or (ranks[pre.key] or 0) >= (pre.maxRank or 1)) then
                    local score = (refs[n.key] and 0 or 1000) + (variant=='deep' and -(n.row or 0)or(n.row or 0))*10 + (variant=='reverse' and -(n.column or 0)or(n.column or 0))
                    if not pickScore or score < pickScore then pick, pickScore = n, score end
                end
            end
        end
        if not pick then break end
        ranks[pick.key] = (ranks[pick.key] or 0) + 1; spent = spent + 1
    end
    return ranks, spent
end
function D.LevelPaths()
    local class = liveClass()
    local data = class and FUSLiveData and FUSLiveData[class]
    if not data or not data.talentTrees or not P.talentBuild then return nil end
    local level, revision = liveLevel(), P.revision
    local c = S.levelPaths
    if c and c.class == class and c.level == level and c.revision == revision then return c end
    local refs = P.talentBuild.ruleReferences(data)
    if data.petCritValues then refs.ferocity = true end
    local points = availablePoints()
    c = {class = class, level = level, revision = revision, trees = {}}
    for t, tree in ipairs(data.talentTrees) do
        local ranks, spent = treePath(data, tree, points, refs)
        local unmodeled = {}
        for _, n in ipairs(tree.talents or {}) do if (ranks[n.key] or 0) > 0 and not refs[n.key] then unmodeled[#unmodeled + 1] = n.name or n.key end end
        local alternatives={ranks};local seen={[P.canonical(ranks)]=true}
        for _,variant in ipairs({'reverse','deep'})do local other=treePath(data,tree,points,refs,variant);local key=P.canonical(other);if not seen[key]then seen[key]=true;alternatives[#alternatives+1]=other end end
        c.trees[t] = {ranks = ranks, points = spent, unmodeled = unmodeled,alternatives=alternatives}
    end
    S.levelPaths = c
    return c
end
-- Talent abilities a path would teach (e.g. a talent that grants a spell) count as known for that path.
function D.CompareTrees()
    if combat() or S.treeBusy then return end
    local paths = D.LevelPaths()
    local ctx, issue = P.actions.Context()
    local class = liveClass()
    local data = class and FUSLiveData and FUSLiveData[class]
    if not paths or not data or not ctx then S.talentMessage = issue and issue.message or 'Klassenmodell fehlt'; D.Refresh(); return end
    local opts = P.leveling and P.leveling.Context(ctx.profile) or {}
    opts.runs = 8
    local byKill = opts.targetHealth ~= nil
    local start = currentChoice(ctx)
    if not start then S.talentMessage = 'Keine Startrotation'; D.Refresh(); return end
    local profiles = {}
    for t = 1, #paths.trees do
        profiles[t]={}
        for _,ranks in ipairs(paths.trees[t].alternatives or {paths.trees[t].ranks})do
            local profile = P.talentBuild.profile(data, ctx.profile,ranks)
            if profile then P.talentBuild.grantAbilities(data,profile);profiles[t][#profiles[t]+1]={profile=profile,ranks=ranks}end
        end
    end
    local rev = P.revision
    S.treeBusy = rev; S.talentMessage = 'Die drei Levelwege werden verglichen ...'; D.Refresh()
    P.enqueue(function()
        local rows = {}
        for t, builds in ipairs(profiles) do
            local winning,tested=nil,0
            for _,build in ipairs(builds)do
                local profile=build.profile
                -- Select a rotation legal for this hypothetical build, retaining
                -- the same captured stats, target and evaluation seeds.
                local best=P.best(data,profile,ctx.stats,P.legalChoice(data,profile,start)and start or nil).choice
                local result
                if byKill then
                    local fastest
                    for _,choice in ipairs(variants(best))do
                        local e=P.leveling.Evaluate(data,profile,ctx.stats,choice,opts)
                        if e.available and e.killSeconds and (e.failures or 0)==0 and(not fastest or e.killSeconds<fastest)then fastest=e.killSeconds end
                    end
                    result=fastest and {kill=fastest,ranks=build.ranks}
                else result={dps=P.score(data,profile,ctx.stats,best,8,411),ranks=build.ranks}end
                tested=tested+1
                if result then local value=result.kill and -result.kill or result.dps;if not winning or value>(winning.kill and -winning.kill or winning.dps)then winning=result end end
                if P.checkpoint then P.checkpoint()end
            end
            rows[t]=winning or {error='Kein gültiger Modellkampf'};rows[t].buildsTested=tested
        end
        return rows
    end, function(rows, err)
        if S.treeBusy~=rev then return end
        S.treeBusy = false
        if err or not rows then S.talentMessage = 'Baumvergleich nicht berechenbar: ' .. tostring(err or '')
        else
            S.talentMessage = nil
            local best
            for t, r in ipairs(rows) do
                local v = r.kill and -r.kill or r.dps
                if v and (not best or v > best.v) then best = {t = t, v = v} end
            end
            for t,row in ipairs(rows)do if row.ranks then paths.trees[t].ranks=row.ranks;local missing={};for _,node in ipairs(data.talentTrees[t].talents or {})do if(row.ranks[node.key]or 0)>0 and not(P.talentBuild.ruleReferences(data))[node.key]then missing[#missing+1]=node.name end end;paths.trees[t].unmodeled=missing end end
            S.treeCompare = {revision = rev, byKill = byKill, rows = rows, best = best and best.t, enemy = opts.targetLevel}
        end
        D.Refresh()
    end, function() return rev == P.revision end)
end

-- Layout ----------------------------------------------------------------------
-- One window, three pages (Übersicht, Talente, Rotation Style), page tabs below the
-- frame like the character frame. Look follows the design renders; every value is
-- live. Element-by-element mapping: UI-BAUPLAN.md.
local W = {}
D.widgets = W
local FW, FH = 1180, 770
local frame
local MEDIA = 'Interface\\AddOns\\ForeverSimBridge\\Media\\'
local GOLD = {1, .82, 0}
local PALE = {.93, .91, .85}
local DARKTEXT = {.13, .08, .02}
local GREEN = {.12, 1, .12}
local RED = {1, .32, .28}
local ORANGE = {1, .62, .25}
local RIM = {.58, .45, .22, 1}
local QUALITY = {[0] = {.62, .62, .62}, [1] = {1, 1, 1}, [2] = {.12, 1, 0}, [3] = {0, .44, .87}, [4] = {.64, .21, .93}, [5] = {1, .5, 0}}
local TREE_TINT = {{.10, .55, .55}, {.80, .46, .10}, {.25, .62, .18}}
local SLOT_ID = {head = 1, neck = 2, shoulder = 3, chest = 5, waist = 6, legs = 7, feet = 8, wrist = 9, hands = 10,
                 finger1 = 11, finger2 = 12, trinket1 = 13, trinket2 = 14, back = 15, mainhand = 16, offhand = 17, ranged = 18}
local SLOT_LEFT = {{'HeadSlot', 'head'}, {'NeckSlot', 'neck'}, {'ShoulderSlot', 'shoulder'}, {'BackSlot', 'back'},
                   {'ChestSlot', 'chest'}, {'ShirtSlot'}, {'TabardSlot'}, {'WristSlot', 'wrist'}}
local SLOT_RIGHT = {{'HandsSlot', 'hands'}, {'WaistSlot', 'waist'}, {'LegsSlot', 'legs'}, {'FeetSlot', 'feet'},
                    {'Finger0Slot', 'finger1'}, {'Finger1Slot', 'finger2'}, {'Trinket0Slot', 'trinket1'}, {'Trinket1Slot', 'trinket2'}}
local SLOT_WEAPON = {{'MainHandSlot', 'mainhand'}, {'SecondaryHandSlot', 'offhand'}, {'RangedSlot', 'ranged'}}
local PAGE_TITLE = {overview = 'Übersicht', talents = 'Talente', style = 'Rotation', quests = 'Quests', more = 'Erweitert'}
local TABBED = {overview = true, talents = true, style = true}

local function pct(v)
 v=v or 0;if v~=0 and math.abs(v)<.01 then return(v>0 and '+'or '-')..'<0,01 %'end
 return(string.format(math.abs(v)<.1 and '%+.2f %%'or'%+.1f %%',v):gsub('%.',',',1))
end
local function hudCfg()
    local hud = P.rotationHUD
    return hud and hud.Config and hud.Config() or (ForeverSimBridgeDB and ForeverSimBridgeDB.hud) or {}
end
local function applyHud() if P.rotationHUD and P.rotationHUD.ApplyStyle then pcall(P.rotationHUD.ApplyStyle) end end
local function itemQuality(item)
    if not item then return 1 end
    local q = num(item.quality)
    if not q and item.id then q = num(safe(C_Item and C_Item.GetItemQualityByID, item.id)) end
    if not q and item.id and GetItemInfo then q = num(select(3, safe(GetItemInfo, item.id))) end
    return q or 1
end
local function tex(parent, layer, path, w, h)
    local t = parent:CreateTexture(nil, layer or 'ARTWORK')
    if path then t:SetTexture(path) end
    if w then t:SetSize(w, h or w) end
    return t
end

-- Buttons with the render textures. kind: gold, dark, red, blue.
local KIND = {gold = 'FSButtonGold', dark = 'FSButtonDark', red = 'FSButtonRed', blue = 'FSButtonBlue'}
local function Btn(parent, x, y, w, h, label, onClick, kind, icon, lightText)
    local b = CreateFrame('Button', nil, parent)
    b:SetSize(w, h)
    if x then b:SetPoint('TOPLEFT', x, y) end
    b.bg = tex(b, 'BACKGROUND'); b.bg:SetAllPoints()
    local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, .08)
    b.label = UI.Text(b, nil, nil, nil, nil, h >= 34 and 14 or h >= 28 and 13 or 12, label, 'text', 'CENTER')
    if icon then
        b.icon = tex(b, 'ARTWORK', icon, h - 14)
        b.label:SetPoint('CENTER', (h - 14) / 2 + 3, 0)
        b.icon:SetPoint('RIGHT', b.label, 'LEFT', -6, 0)
    else
        b.label:SetPoint('CENTER', 0, 0)
    end
    function b:SetKind(k)
        self.style = k or 'dark'
        self.bg:SetTexture(MEDIA .. (KIND[self.style] or KIND.dark))
        local dark = self.style == 'gold' and not lightText
        self.label:SetColor(dark and DARKTEXT or PALE)
        self.label:SetShadowOffset(dark and 0 or 1, dark and 0 or -1)
    end
    function b:SetLabel(t) self.label:SetText(t or '') end
    function b:SetUsable(on) self:SetEnabled(on); self:SetAlpha(on and 1 or .55) end
    b:SetKind(kind)
    b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    b:SetScript('OnClick', function(self, mouse) if not combat() and onClick then onClick(self, mouse) end end)
    return b
end
-- Dark panel with the double gold rim of the renders.
local function Panel(parent, x, y, w, h, title, size)
    local p = UI.Box(parent, x, y, w, h, {.016, .018, .024, .92}, RIM)
    local inner = CreateFrame('Frame', nil, p, 'BackdropTemplate')
    inner:SetPoint('TOPLEFT', 3, -3); inner:SetPoint('BOTTOMRIGHT', -3, 3)
    inner:SetBackdrop({edgeFile = WHITE, edgeSize = 1}); inner:SetBackdropBorderColor(.30, .23, .11, .9)
    if title then p.title = UI.Text(p, 16, -14, w - 32, nil, size or 17, title, GOLD) end
    return p
end
local function Rule(parent, x, y, w)
    local l = tex(parent, 'ARTWORK', WHITE); l:SetVertexColor(.45, .36, .18, .7)
    l:SetPoint('TOPLEFT', x, y); l:SetSize(w, 1)
    return l
end
-- Percent plate on an icon (bottom left, stack count stays readable bottom right).
local function Plate(parent)
    local b = UI.Box(parent, nil, nil, 40, 14, {0, 0, 0, .9}, {.30, .60, .22, 1})
    b:SetPoint('BOTTOMLEFT', parent, 'BOTTOMLEFT', -4, -5)
    b:SetFrameLevel(parent:GetFrameLevel() + 3)
    b.text = UI.Text(b, 0, -2, 40, nil, 10, '', GREEN, 'CENTER')
    function b:Set(value, kind)
        if not value then self:Hide(); return end
        local color = kind == 'down' and RED or kind == 'unknown' and ORANGE or GREEN
        self.text:SetText(value); self.text:SetColor(color)
        self:SetBackdropBorderColor(color[1] * .55, color[2] * .55, color[3] * .55, 1)
        self:SetWidth(math.max(26, (self.text:GetStringWidth() or 30) + 8)); self.text:SetWidth(self:GetWidth())
        self:Show()
    end
    b:Hide()
    return b
end
local function tooltip(frameRef, fn)
    frameRef:EnableMouse(true)
    frameRef:SetScript('OnEnter', function(self)
        if not GameTooltip then return end
        local lines = fn(self)
        if lines == true then GameTooltip:Show() return end
        if not lines then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(lines[1], 1, .82, 0)
        for i = 2, #lines do GameTooltip:AddLine(lines[i], .9, .9, .9, true) end
        GameTooltip:Show()
    end)
    frameRef:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Window ---------------------------------------------------------------------
local pages = {}
local function setPage(name)
    S.page = PAGE_TITLE[name] and name or 'overview'
    for key, p in pairs(pages) do p:SetShown(key == S.page) end
    for _, t in ipairs(W.tabs or {}) do t:SetKind((t.page == S.page or (t.page == 'gear' and S.page == 'more' and app().state.ui and app().state.ui.tab == 'gear')) and 'gold' or 'dark') end
    if W.more then W.more:SetKind(S.page == 'more' and 'gold' or 'dark') end
    if S.page == 'quests' then
        local fdq = _G.ForeverCoreFDQ
        if fdq and fdq.OverviewUI and fdq.OverviewUI.Mount then fdq.OverviewUI.Mount(pages.quests) end
    end
    if UI.CloseMenu then UI.CloseMenu() end
    D.Refresh()
end
D.SetPage = setPage
local menu
local function toggleMenu(owner)
    if menu and menu:IsShown() then menu:Hide(); return end
    if not menu then
        local entries = {{'Gegner & Benchmark', 'benchmark'}, {'Kampfverlauf', 'analysis', 'trace'},
                         {'Kampfaudit', 'analysis', 'audit'}, {'Dungeons & Bosse', 'dungeons'}, {'Diagnose & Hilfe', 'diagnostics'}}
        menu = UI.Box(frame, nil, nil, 200, 8 + #entries * 30, {.02, .02, .03, .98}, RIM)
        menu:SetFrameStrata('FULLSCREEN_DIALOG')
        for i, e in ipairs(entries) do
            Btn(menu, 4, -4 - (i - 1) * 30, 192, 28, e[1], function() menu:Hide(); app().Open(e[2], e[3]) end, 'dark')
        end
    end
    menu:ClearAllPoints(); menu:SetPoint('TOPRIGHT', owner, 'BOTTOMRIGHT', 0, -2); menu:Show()
end
local function buildWindow()
    frame = UI.Box(UIParent, nil, nil, FW, FH, {.012, .013, .016, .95}, {.66, .51, .25, 1})
    frame:SetPoint('CENTER'); frame:SetFrameStrata('DIALOG'); frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    local dark = tex(frame, 'BACKGROUND', MEDIA .. 'FQDark'); dark:SetPoint('TOPLEFT', 2, -2); dark:SetPoint('BOTTOMRIGHT', -2, 2); dark:SetAlpha(.6)
    local inner = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
    inner:SetPoint('TOPLEFT', 4, -4); inner:SetPoint('BOTTOMRIGHT', -4, 4)
    inner:SetBackdrop({edgeFile = WHITE, edgeSize = 1}); inner:SetBackdropBorderColor(.36, .28, .13, 1)
    -- Header (drag handle)
    local h = CreateFrame('Frame', nil, frame); h:SetSize(FW - 120, 64); h:SetPoint('TOPLEFT', 0, 0)
    h:EnableMouse(true); h:RegisterForDrag('LeftButton')
    h:SetScript('OnDragStart', function() if not combat() then frame:StartMoving() end end)
    h:SetScript('OnDragStop', function() frame:StopMovingOrSizing() end)
    local emblem = tex(frame, 'ARTWORK', MEDIA .. 'ArtEmblem', 50); emblem:SetPoint('TOPLEFT', 14, -8)
    W.title = UI.Text(frame, 74, -12, 600, nil, 22, 'ForeverSim', GOLD)
    W.who = UI.Text(frame, 74, -40, 700, nil, 14, '', PALE)
    W.extra = CreateFrame('Frame', nil, frame); W.extra:SetSize(420, 34); W.extra:SetPoint('TOPRIGHT', -180, -16)
    W.more = Btn(frame, nil, nil, 116, 32, 'Erweitert', function(self) toggleMenu(self) end, 'dark', MEDIA .. 'ArtDown')
    W.more:SetPoint('TOPRIGHT', -58, -16)
    local close = CreateFrame('Button', nil, frame); close:SetSize(32, 32); close:SetPoint('TOPRIGHT', -14, -16)
    close:SetNormalTexture(MEDIA .. 'ArtClose'); close:SetHighlightTexture(MEDIA .. 'ArtClose', 'ADD')
    close:SetScript('OnClick', function() D.Hide() end)
    Rule(frame, 8, -66, FW - 16)
    -- Page tabs below the frame (character frame style). Switching never opens a window.
    W.tabs = {}
    local defs = {{'overview', 'Übersicht', MEDIA .. 'ArtEmblem', 158},
                  {'gear', 'Ausrüstung', MEDIA .. 'ArtGear', 158},
                  {'style', 'Rotation', MEDIA .. 'ArtGear', 158},
                  {'talents', 'Talente', MEDIA .. 'ArtJournal', 158},
                  {'quests', 'Quests', MEDIA .. 'ArtEmblem', 158}}
    local x = 14
    for _, d in ipairs(defs) do
        local t = Btn(frame, nil, nil, d[4], 36, d[2], function()
            if d[1] == 'gear' then app().Open('gear', 'compare')
            else setPage(d[1]) end
        end, 'dark', d[3], true)
        t:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', x, 2); t.page = d[1]
        W.tabs[#W.tabs + 1] = t; x = x + d[4] + 6
    end
    for name in pairs(PAGE_TITLE) do
        local p = CreateFrame('Frame', nil, frame); p:SetPoint('TOPLEFT', 0, -68); p:SetPoint('BOTTOMRIGHT', 0, 0); p:Hide()
        pages[name] = p
    end
    UI.Text(pages.quests, 30, -25, 980, 35, 15, 'ForeverDungeonQuest ist nicht geladen.', 'muted')
    -- Erweitert: Fachansichten (Gegner, Kampfverlauf, Gewichte, Szenarien, Dungeons, Diagnose) are drawn
    -- into this host by UI/Shell.lua. They never get a window or a tab of their own.
    W.moreHost = CreateFrame('Frame', nil, pages.more); W.moreHost:SetSize(FW - 28, 690); W.moreHost:SetPoint('TOPLEFT', 14, -6)
end

-- Page: Übersicht ------------------------------------------------------------------
local function slotWidget(parent, size, x, y, def)
    local s = UI.Icon(parent, size, x, y, {.35, .35, .35, 1})
    s.slotName, s.slotKey = def[1], def[2]
    s.plate = Plate(s)
    tooltip(s, function(self)
        local id = self.slotName and safe(GetInventorySlotInfo, self.slotName)
        if id and GameTooltip and safe(GetInventoryItemLink, 'player', id) then
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); pcall(GameTooltip.SetInventoryItem, GameTooltip, 'player', id)
            if self.upgrade then GameTooltip:AddLine(' '); GameTooltip:AddLine('ForeverSim: Upgrade ' .. self.upgrade, .12, 1, .12) end
            return true
        end
    end)
    return s
end
local function buildOverview()
    local page = pages.overview
    -- Equipment and damage
    local left = Panel(page, 14, -8, 650, 520)
    W.slots = {}
    for i, def in ipairs(SLOT_LEFT) do W.slots[#W.slots + 1] = slotWidget(left, 50, 14, -14 - (i - 1) * 61, def) end
    for i, def in ipairs(SLOT_RIGHT) do W.slots[#W.slots + 1] = slotWidget(left, 50, 586, -14 - (i - 1) * 61, def) end
    for i, def in ipairs(SLOT_WEAPON) do W.slots[#W.slots + 1] = slotWidget(left, 56, 232 + (i - 1) * 68, -444, def) end
    W.enemyLine = UI.Text(left, 80, -18, 490, nil, 14, '', PALE, 'CENTER')
    W.dps = UI.Text(left, 80, -40, 490, nil, 38, '–', GOLD, 'CENTER')
    W.delta = UI.Text(left, 80, -88, 490, nil, 13, '', PALE, 'CENTER')
    W.context = UI.Text(left, 80, -108, 490, nil, 13, '', GREEN, 'CENTER')
    Rule(left, 90, -132, 470)
    UI.Text(left, 90, -144, 470, nil, 16, 'Woher dein Schaden kommt', GOLD)
    W.split = {}
    for i = 1, 6 do
        local y = -174 - (i - 1) * 40
        local icon = UI.Icon(left, 30, 90, y, {.4, .32, .18, 1})
        local name = UI.Text(left, 128, y - 8, 136, nil, 13, '', PALE)
        local bar = UI.Bar(left, 270, y - 9, 214, 14, GOLD)
        local value = UI.Text(left, 494, y - 8, 60, nil, 13, '', PALE, 'RIGHT')
        W.split[i] = {icon = icon, name = name, bar = bar, value = value}
    end
    W.splitEmpty = UI.Text(left, 90, -200, 470, nil, 13, '', 'muted', 'CENTER')
    -- More damage: suggestions
    local right = Panel(page, 676, -8, 490, 520)
    local status = UI.Box(right, 14, -14, 462, 36, {.03, .035, .045, .95}, {.25, .22, .16, 1})
    W.statusIcon = tex(status, 'ARTWORK', MEDIA .. 'ArtCheck', 20); W.statusIcon:SetPoint('LEFT', 10, 0)
    W.status = UI.Text(status, 40, -11, 410, nil, 13, '', PALE)
    UI.Text(right, 16, -64, 460, nil, 18, 'So holst du mehr Schaden raus', GOLD)
    W.rows = {}
    for i = 1, 5 do
        local y = -94 - (i - 1) * 76
        local row = CreateFrame('Frame', nil, right); row:SetSize(462, 72); row:SetPoint('TOPLEFT', 14, y)
        row.bg = tex(row, 'BACKGROUND', MEDIA .. 'FSRowGold'); row.bg:SetAllPoints()
        row.rule = Rule(row, 0, -72, 462)
        row.n = UI.Text(row, 6, -24, 20, nil, 20, tostring(i), GOLD)
        row.icon = UI.Icon(row, 44, 32, -14, {.4, .4, .4, 1})
        row.title = UI.Text(row, 86, -16, 220, nil, 14, '', PALE)
        row.sub = UI.Text(row, 86, -38, 220, nil, 12, '', 'muted')
        row.gain = UI.Text(row, 296, -24, 66, nil, 18, '', GREEN, 'RIGHT')
        row.button = Btn(row, 370, -20, 92, 32, '', nil, 'dark')
        W.rows[i] = row
    end
    W.rowsEmpty = UI.Text(right, 20, -120, 450, 120, 13, '', 'muted')
    W.unmodeled = UI.Text(right, 16, -488, 460, nil, 12, '', ORANGE)
    -- Rotation strip
    local rota = Panel(page, 14, -540, 1152, 150)
    UI.Text(rota, 20, -36, 200, nil, 20, 'Deine Rotation', GOLD)
    W.rotaStatus = UI.Text(rota, 20, -66, 200, 40, 13, '', GREEN)
    W.rotaSlots = {}
    for i = 1, 6 do
        local x = 240 + (i - 1) * 118
        local icon = UI.Icon(rota, 52, x + 30, -26, {.55, .43, .22, 1})
        local num = UI.Box(icon, nil, nil, 18, 18, {.10, .07, .02, 1}, {.85, .66, .28, 1}); num:SetPoint('TOPLEFT', -6, 6)
        num:SetFrameLevel(icon:GetFrameLevel() + 2)
        UI.Text(num, 0, -3, 18, nil, 11, tostring(i), GOLD, 'CENTER')
        local name = UI.Text(rota, x, -86, 112, nil, 12, '', PALE, 'CENTER')
        tooltip(icon, function(self)
            if self.spellId and GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); if pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellId) then return true end end
            return self.info
        end)
        W.rotaSlots[i] = {icon = icon, num = num, name = name}
    end
    W.rotaEmpty = UI.Text(rota, 240, -60, 700, nil, 13, '', 'muted', 'CENTER')
    W.calc = Btn(rota, 952, -26, 186, 40, 'Beste Rotation berechnen', function() D.RunAll() end, 'gold')
    W.toStyle = Btn(rota, 952, -78, 186, 36, 'Rotation Style', function() setPage('style') end, 'dark')
end
local function suggestions()
    local list, unknown = {}, {}
    local g = S.gear
    if g.revision == P.revision then
        for _, row in ipairs(g.rows or {}) do
            local r = row.result
            if r and num(r.percent) and (num(r.delta) or 0) > 0 then
                list[#list + 1] = {kind = 'item', item = r.item or row.item, origin = row.item and row.item.origin, gain = r.percent}
            elseif not r and row.reason and row.item and tostring(row.reason):lower():find('modell') then
                unknown[#unknown + 1] = {kind = 'unknown', item = row.item, origin = row.item.origin}
            end
        end
    end
    local c = S.talentCompare
    if c and num(c.pct) and c.pct > .05 then list[#list + 1] = {kind = 'talent', gain = c.pct} end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    for _, u in ipairs(unknown) do list[#list + 1] = u end
    return list, #unknown
end
local function refreshOverview()
    -- Equipment from the client; upgrade plate on the slot where a better item exists.
    local best = {}
    local g = S.gear
    if g.revision == P.revision then
        for _, row in ipairs(g.rows or {}) do
            local r = row.result
            local slot = r and r.item and r.item.slot
            if slot and num(r.percent) and (num(r.delta) or 0) > 0 and (not best[slot] or r.percent > best[slot]) then best[slot] = r.percent end
        end
    end
    for _, s in ipairs(W.slots) do
        local id, empty = safe(GetInventorySlotInfo, s.slotName)
        local icon = id and safe(GetInventoryItemTexture, 'player', id)
        s:SetIcon(icon or empty)
        s.icon:SetDesaturated(icon == nil); s.icon:SetAlpha(icon and 1 or .5)
        local q = icon and num(safe(GetInventoryItemQuality, 'player', id)) or nil
        local c = q and QUALITY[q] or {.30, .30, .30}
        s:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        local up = s.slotKey and best[s.slotKey]
        s.upgrade = up and pct(up)
        s.plate:Set(up and ('▲' .. (string.format('%.1f', up):gsub('%.', ','))) or nil)
    end
    -- Damage
    local r, stale = rotation()
    local l = currentLeveling()
    local run = app().state.simulation
    local e = resolved()
    W.enemyLine:SetText('Dein Schaden gegen ' .. (ENEMY_NAME[e and e.mode or ''] or 'Gegner')..(e and e.armorAssumed and ' (Modell)'or''))
    if run.status == 'running' then
        W.dps:SetText('…'); W.delta:SetText('wird berechnet'); W.context:SetText('')
    elseif l then
        W.dps:SetText((string.format('%.1f s pro Kill', l.killSeconds):gsub('%.', ',', 1)))
        local faster = l.startKill and l.startKill > 0 and (1 - l.killSeconds / l.startKill) * 100
        W.delta:SetText(faster and faster > .5 and string.format('%d %% schneller als vorher', math.floor(faster + .5)) or 'schnellste geprüfte Variante')
        W.context:SetText(string.format('%s %s · %d Varianten geprüft',thousands(l.hp),l.hpEstimated and 'Modell-HP'or'HP',l.tested or 0))
    elseif r then
        W.dps:SetText(thousands(r.dps) .. ' DPS'); W.dps:SetColor(stale and 'muted' or GOLD)
        local gain = num(r.improvementPercent) or (num(r.percentOfStart) and r.percentOfStart - 100) or 0
        W.delta:SetText(stale and 'Altes Ergebnis – bitte neu berechnen' or gain > 0 and (pct(gain) .. ' gegenüber deiner bisherigen Rotation') or 'Keine bessere geprüfte Rotation gefunden')
        local buffs = snapshot() and snapshot().activeAuras and #snapshot().activeAuras or 0
        W.context:SetText(buffs>0 and ('Mit erfassten aktiven Buffs ('..buffs..')') or 'Mit erfasstem Charakter, ohne aktive Buffs')
    else
        W.dps:SetText('–'); W.dps:SetColor('muted'); W.delta:SetText('Noch nicht berechnet'); W.context:SetText('')
    end
    local t = S.trace and S.trace.revision == P.revision and S.trace or nil
    local rows, total = {}, 0
    if t then
        for _, s in ipairs(t.spells or {}) do rows[#rows + 1] = s end
        if (t.pet or 0) > 0 then rows[#rows + 1] = {key = 'pet', damage = t.pet} end
        table.sort(rows, function(a, b) return a.damage > b.damage end)
        for _, s in ipairs(rows) do total = total + s.damage end
    end
    local model = FUSLiveData and FUSLiveData[liveClass() or '']
    local top = rows[1] and rows[1].damage or 0
    for i, w in ipairs(W.split) do
        local s = rows[i]
        w.icon:SetShown(s ~= nil); w.name:SetShown(s ~= nil); w.value:SetShown(s ~= nil); w.bar.bg:SetShown(s ~= nil); w.bar.fill:SetShown(s ~= nil)
        if s then
            local name, icon
            if s.key == 'pet' then name, icon = 'Begleiter', 'Interface\\Icons\\Ability_Hunter_BeastCall' else name, icon = displayKey(model, s.key) end
            w.icon:SetIcon(icon); w.name:SetText(name)
            w.bar:Set(top > 0 and s.damage / top or 0, ({GOLD, {.45, .70, 1}, {.45, .70, 1}, {.40, .85, .35}, {.75, .55, 1}, {.65, .63, .58}})[i])
            w.value:SetText(string.format('%d %%', math.floor(100 * s.damage / total + .5)))
        end
    end
    W.splitEmpty:SetText(#rows == 0 and (S.traceBusy and 'Kampfverlauf wird berechnet …' or 'Erscheint nach „Beste Rotation berechnen“.') or '')
    -- Status and suggestions
    local ch = app().state.character
    W.status:SetText(ch.status == 'ready' and 'Ausrüstung, Talente und Buffs erfasst.' or 'Charakterdaten unvollständig – nach dem Kampf erneut öffnen.')
    W.statusIcon:SetTexture(MEDIA .. (ch.status == 'ready' and 'ArtCheck' or 'ArtLight'))
    local list, unknownCount = suggestions()
    for i, row in ipairs(W.rows) do
        local s = list[i]
        row:SetShown(s ~= nil)
        if s then
            row.bg:SetShown(i == 1 and s.kind ~= 'unknown')
            if s.kind == 'talent' then
                row.icon:SetIcon(MEDIA .. 'ArtJournal'); row.icon:SetBackdropBorderColor(.85, .66, .28, 1)
                row.title:SetText('Talent-Entwurf übernehmen'); row.title:SetColor(i == 1 and GOLD or PALE)
                row.sub:SetText('Entwurf liegt vorn – im Spiel umskillen')
                row.gain:SetText(pct(s.gain)); row.gain:SetColor(GREEN)
                row.button:SetLabel('Talente'); row.button:SetScript('OnClick', function() setPage('talents') end); row.button:Show()
            else
                local item = s.item or {}
                local q = QUALITY[itemQuality(item)] or QUALITY[1]
                row.icon:SetIcon(UI.ItemIcon(item.id)); row.icon:SetBackdropBorderColor(q[1], q[2], q[3], 1)
                row.icon.link = item.link
                local verb = s.kind == 'unknown' and 'prüfen' or s.origin == 'Questbelohnung' and 'wählen' or s.origin == 'Dungeon Journal' and 'holen' or 'anlegen'
                row.title:SetText('[' .. tostring(item.name or '?') .. '] ' .. verb); row.title:SetColor(q)
                local from = s.kind == 'unknown' and 'Effekt nicht modelliert' or s.origin == 'Tasche' and 'liegt in deiner Tasche'
                    or s.origin == 'Bank' and 'liegt in deiner Bank'
                    or s.origin == 'Dungeon Journal' and ('Dungeon Journal · ' .. tostring(item.boss or item.dungeon or '?'))
                    or tostring(s.origin or '')
                row.sub:SetText(from)
                row.gain:SetText(s.kind == 'unknown' and '?' or pct(s.gain)); row.gain:SetColor(s.kind == 'unknown' and ORANGE or GREEN)
                if s.origin == 'Tasche' then
                    row.button:SetLabel('Zeigen'); row.button:SetScript('OnClick', function() if not combat() then safe(OpenAllBags) end end); row.button:Show()
                elseif s.origin == 'Dungeon Journal' then
                    row.button:SetLabel('Im Journal')
                    row.button:SetScript('OnClick', function()
                        local fdq = _G.ForeverSimDungeonAPI
                        if not combat() and fdq and fdq.OpenDungeon then fdq.OpenDungeon(item.dungeonKey) end
                    end)
                    row.button:Show()
                else row.button:Hide() end
            end
        end
    end
    W.rowsEmpty:SetText(#list == 0 and (S.gear.busy and string.format('Prüfe Gegenstände %d von %d …', S.gear.done or 0, S.gear.total or 0)
        or 'Noch keine Vorschläge. „Beste Rotation berechnen“ prüft auch Taschen und Questbelohnungen.') or '')
    W.unmodeled:SetText(unknownCount > 0 and string.format('Nicht modelliert: %d Item-Effekt%s. Diese Werte fehlen in den Zahlen.', unknownCount, unknownCount == 1 and '' or 'e') or '')
    -- Rotation strip
    local choice = l and l.choice or r and r.choice
    local policies = choice and choice.policies or {}
    for i, slot in ipairs(W.rotaSlots) do
        local pol = policies[i]
        slot.icon:SetShown(pol ~= nil); slot.name:SetShown(pol ~= nil)
        if pol then
            local name, icon, hint
            if P.rotationHUD and P.rotationHUD.PolicyInfo then name, icon, hint = P.rotationHUD.PolicyInfo(pol) end
            if not name or name == pol.key then name, icon = displayKey(model, pol.key) end
            local ability = abilityFor(model, pol.key)
            slot.icon.spellId = ability and ability.id
            slot.icon:SetIcon(icon); slot.name:SetText(name or pol.key)
            slot.icon.info = {name or pol.key, hint or (pol.maintain and 'aktiv halten' or 'wenn bereit')}
        end
    end
    W.rotaEmpty:SetText(#policies == 0 and (run.status == 'error' and tostring(run.error and run.error.message or '') or 'Noch keine Rotation berechnet.') or '')
    local busy = run.status == 'running' or S.levelingBusy or S.traceBusy or S.weightsBusy or (S.gear.busy and S.gear.revision == P.revision) or P.pendingJobs() > 0
    W.calc:SetLabel(busy and 'Berechnung läuft …' or 'Beste Rotation berechnen'); W.calc:SetUsable(not busy)
    if run.status == 'running' then W.rotaStatus:SetText('Rotation wird gesucht …'); W.rotaStatus:SetColor(GOLD)
    elseif busy then W.rotaStatus:SetText('Weitere Berechnungen laufen …'); W.rotaStatus:SetColor(GOLD)
    elseif r and not stale then W.rotaStatus:SetText('Beste Rotation · aktuell'); W.rotaStatus:SetColor(GREEN)
    elseif r then W.rotaStatus:SetText('Altes Ergebnis · neu berechnen'); W.rotaStatus:SetColor(ORANGE)
    else W.rotaStatus:SetText('Noch nicht berechnet'); W.rotaStatus:SetColor('muted') end
    -- Minimum level 10 (ZIELE.md, Grundsatz 5): below it the SIM stays off, as before.
    if liveLevel() < P.minSimLevel() then
        W.calc:SetUsable(false)
        W.dps:SetText('–'); W.dps:SetColor('muted')
        W.delta:SetText(P.levelMessage(liveLevel())); W.context:SetText('')
        W.rotaStatus:SetText('Ab Level ' .. P.minSimLevel() .. ' verfügbar'); W.rotaStatus:SetColor('muted')
    end
end

-- Page: Talente -------------------------------------------------------------------
local CELL, DX, DY = 44, 60, 72
-- The question changes with the level (ZIELE.md, Ziel 2): below 50 tree against tree, from 50 draft against the real build.
-- The header buttons still allow switching by hand.
local function talentLevelMode() return (S.talentMode or (liveLevel() < 50 and 'level' or 'draft')) == 'level' end
local function buildTalents()
    local page = pages.talents
    W.trees = {}
    for t = 1, 3 do
        local p = Panel(page, 14 + (t - 1) * 282, -8, 272, 606)
        local glow = tex(p, 'BACKGROUND', MEDIA .. 'FSTreeGlow'); glow:SetPoint('TOPLEFT', 4, -50); glow:SetPoint('BOTTOMRIGHT', -4, 4)
        local c = TREE_TINT[t]; glow:SetVertexColor(c[1], c[2], c[3], .75)
        p.headIcon = UI.Icon(p, 34, 12, -9, {.6, .48, .24, 1})
        p.head = UI.Text(p, 54, -14, 210, nil, 17, '', GOLD)
        p.sub = UI.Text(p, 54, -34, 210, nil, 11, '', PALE)
        Rule(p, 6, -50, 260)
        p.links, p.cells = {}, {}
        for i = 1, 8 do local l = tex(p, 'BORDER', WHITE); l:Hide(); p.links[i] = l end
        local x0 = math.floor((272 - (3 * DX + CELL)) / 2)
        for row = 0, 6 do
            for col = 0, 3 do
                local b = CreateFrame('Button', nil, p, 'BackdropTemplate')
                b:SetSize(CELL, CELL); b:SetPoint('TOPLEFT', x0 + col * DX, -64 - row * DY)
                b:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 2}); b:SetBackdropColor(0, 0, 0, .85)
                b.icon = tex(b, 'ARTWORK'); b.icon:SetPoint('TOPLEFT', 2, -2); b.icon:SetPoint('BOTTOMRIGHT', -2, 2); b.icon:SetTexCoord(.07, .93, .07, .93)
                local rb = UI.Box(b, nil, nil, 30, 15, {0, 0, 0, .92}, {.45, .45, .45, 1}); rb:SetPoint('BOTTOMRIGHT', 7, -7)
                rb:SetFrameLevel(b:GetFrameLevel() + 2)
                b.rank = UI.Text(rb, 0, -2, 30, nil, 10, '', PALE, 'CENTER'); b.rankBg = rb
                local db = UI.Box(b, nil, nil, 24, 16, {.10, .35, .08, 1}, {.30, .75, .22, 1}); db:SetPoint('TOPLEFT', -7, 7)
                db:SetFrameLevel(b:GetFrameLevel() + 2)
                b.diff = UI.Text(db, 0, -2, 24, nil, 11, '', {1, 1, 1}, 'CENTER'); b.diffBg = db
                b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
                b:SetScript('OnClick', function(self, mouse)
                    if not self.node or combat() then return end
                    S.selTalent = self.node
                    if not talentLevelMode() then changeTalent(liveClass(), self.node, mouse == 'RightButton' and -1 or 1) else D.Refresh() end
                end)
                b:SetScript('OnEnter', function(self) if self.node then S.selTalent = self.node; D.Refresh() end end)
                p.cells[row * 4 + col + 1] = b
            end
        end
        p.x0 = x0
        W.trees[t] = p
    end
    W.talentHint = UI.Text(page, 14, -620, 840, nil, 11, 'Linksklick: Punkt im Entwurf setzen  ·  Rechtsklick: entfernen  ·  deine echten Talente bleiben unverändert', 'muted')
    -- Details and comparison
    local side = Panel(page, 862, -8, 304, 630)
    UI.Text(side, 16, -14, 272, nil, 17, 'Talentdetails', GOLD)
    W.selIcon = UI.Icon(side, 44, 16, -44, {.6, .48, .24, 1})
    W.selName = UI.Text(side, 68, -44, 224, 32, 13, '', PALE)
    W.selRanks = UI.Text(side, 68, -78, 224, nil, 12, '', PALE)
    local box = UI.Box(side, 14, -100, 276, 104, {.03, .035, .045, .95}, {.25, .22, .16, 1})
    W.selDesc = UI.Text(box, 8, -8, 260, 88, 11, '', PALE)
    W.sideTitle = UI.Text(side, 16, -216, 272, nil, 17, 'Entwurf gegen Im Spiel', GOLD)
    Rule(side, 14, -240, 276)
    W.diffs = {}
    for i = 1, 4 do
        local y = -248 - (i - 1) * 32
        W.diffs[i] = {icon = UI.Icon(side, 26, 16, y, {.4, .32, .18, 1}), name = UI.Text(side, 50, y - 7, 190, nil, 12, '', PALE),
                      value = UI.Text(side, 240, y - 7, 48, nil, 13, '', GREEN, 'RIGHT')}
    end
    W.diffMore = UI.Text(side, 16, -378, 272, nil, 11, '', 'muted')
    Rule(side, 14, -394, 276)
    W.result = UI.Text(side, 14, -404, 276, nil, 24, '', GREEN, 'CENTER')
    W.resultNote = UI.Text(side, 14, -434, 276, 30, 11, '', 'muted', 'CENTER')
    W.compare = Btn(side, 14, -466, 276, 32, 'Kombination neu berechnen', function()
        local core=_G.ForeverCoreClient
        if core and core.RecommendTalents then
            core.RecommendTalents(true)
        else
            S.talentMessage='ForeverCoreBridge fehlt; Addon aktivieren und /reload eingeben.'
        end
        D.Refresh() -- Display queued, running and error states immediately after the click.
    end, 'blue')
    W.useLive = Btn(side, 14, -502, 276, 44, 'Aktuelle Skillung kopieren', function() D.UseLiveTalents() end, 'red')
    W.useLive.label:ClearAllPoints(); W.useLive.label:SetPoint('CENTER', 0, 8)
    W.useLiveNote = UI.Text(W.useLive, 0, -26, 276, nil, 10, 'Kopiert deine aktuellen Spiel-Talente in den Entwurf.', PALE, 'CENTER')
    W.clear = Btn(side, 14, -550, 276, 32, 'Entwurf leeren', function() D.ResetTalents() end, 'red')
    W.clearNote = UI.Text(side, 14, -586, 276, nil, 10, 'Ändert nur den Entwurf.', 'muted', 'CENTER')
    W.points = UI.Text(side, 14, -606, 276, nil, 13, '', PALE, 'CENTER')
    -- Mode toggle lives in the header while this page is open.
    W.modeDraft = Btn(W.extra, 0, 0, 200, 32, 'Eigener Entwurf', function() S.talentMode = 'draft'; D.Refresh() end, 'gold', nil, true)
    W.modeLevel = Btn(W.extra, 210, 0, 200, 32, 'Leveln (1–49)', function() S.talentMode = 'level'; D.Refresh() end, 'dark')
    -- The normal player workflow is a whole-build result, not separate tree paths.
    W.modeLevel:Hide();W.modeDraft:Hide()
end
local function refreshTalents()
    local class = liveClass()
    local data = class and FUSLiveData and FUSLiveData[class]
    local trees = data and data.talentTrees or {}
    local level = false  -- no independent one-tree leveling path in the normal UI
    local ranks = class and draftRanks(class) or {}
    local live = liveRanks()
    local paths,cmp=nil,nil
    local core=_G.ForeverCoreClient
    local advice=core and core.lastTalentAdvice
    local recommendation=advice and advice.state=='ok' and advice.build or nil
    local recommendedRanks={}
    for _,talent in ipairs(recommendation or{})do
        if talent.key then recommendedRanks[talent.key]=tonumber(talent.rank)or 0 end
    end
    if W.talentHint then
        if recommendation then
            W.talentHint:SetText(string.format('Beste gefundene Kombination: %d Punkte · %+.2f DPS (%+.2f %%)',
                tonumber(advice.points)or 0,tonumber(advice.delta)or 0,tonumber(advice.percent)or 0))
            W.talentHint:SetColor('green')
        elseif advice and advice.state=='busy' then
            W.talentHint:SetText('MythicSim sucht die beste Kombination über alle drei Talentbäume ...')
            W.talentHint:SetColor('muted')
        elseif advice and advice.state=='unsupported' then
            W.talentHint:SetText('Kombination nicht berechenbar: '..tostring(advice.reason or 'Keine Daten'))
            W.talentHint:SetColor('muted')
        else W.talentHint:SetText('MythicSim bewertet die gesamte Verteilung deiner Talentpunkte.');W.talentHint:SetColor('muted') end
    end
    local spent = 0
    local byKey = {}
    for t, p in ipairs(W.trees) do
        local tree = trees[t]
        p:SetShown(tree ~= nil)
        if tree then
            local ranks = recommendation and recommendedRanks or ranks
            local points = 0
            local byPos = {}
            for _, n in ipairs(tree.talents or {}) do
                points = points + (ranks[n.key] or 0); byKey[n.key] = n
                local r, c = tonumber(n.row) or 0, tonumber(n.column) or 0
                if r >= 0 and r < 7 and c >= 0 and c < 4 then byPos[r * 4 + c + 1] = n end
            end
            if level then spent = math.max(spent, points) else spent = spent + points end
            local clientTree = snapshot() and snapshot().talents and snapshot().talents[t]
            p.head:SetText(tostring(clientTree and clientTree.name or tree.name or '?') .. '  ·  ' .. points)
            local row = cmp and cmp.rows[t]
            local best = cmp and cmp.best == t
            if level and row then
                if row.kill then p.sub:SetText(string.format('%s s pro Kill', (string.format('%.1f', row.kill):gsub('%.', ',', 1))))
                elseif row.dps then p.sub:SetText(thousands(row.dps) .. ' DPS')
                else p.sub:SetText(tostring(row.error or '?')) end
                p.sub:SetColor(best and GOLD or PALE)
            elseif level and paths and paths.trees[t] and #paths.trees[t].unmodeled > 0 then
                p.sub:SetText(#paths.trees[t].unmodeled .. ' Talente ohne SIM-Regel'); p.sub:SetColor(ORANGE)
            else p.sub:SetText(recommendation and 'Empfohlene Punkte' or '') end
            p:SetBackdropBorderColor(best and 1 or RIM[1], best and .82 or RIM[2], best and 0 or RIM[3], 1)
            local first = tree.talents and tree.talents[1]
            local _, icon = spellInfo(first and first.spellId); p.headIcon:SetIcon(icon)
            for i, cell in ipairs(p.cells) do
                local n = byPos[i]
                cell:SetShown(n ~= nil); cell.node = n
                if n then
                    local _, ticon = spellInfo(n.spellId)
                    local cur, maxRank = ranks[n.key] or 0, n.maxRank or 1
                    local diff = level and 0 or cur - (live[n.key] or 0)
                    local open = (n.row or 0) * 5 <= points
                    cell.icon:SetTexture(ticon or 'Interface\\Icons\\INV_Misc_QuestionMark')
                    cell.icon:SetDesaturated(cur == 0); cell.icon:SetAlpha(cur > 0 and 1 or open and .75 or .4)
                    local full = cur >= maxRank
                    if recommendation and cur>0 then cell:SetBackdropBorderColor(.12,1,.12,1) elseif full then cell:SetBackdropBorderColor(1, .82, 0, 1) elseif cur > 0 then cell:SetBackdropBorderColor(.30, .85, .25, 1) else cell:SetBackdropBorderColor(.30, .30, .30, 1) end
                    cell.rank:SetText(cur .. '/' .. maxRank); cell.rank:SetColor(full and GOLD or cur > 0 and GREEN or PALE)
                    cell.diffBg:SetShown(diff ~= 0 and not level)
                    if diff ~= 0 then
                        cell.diff:SetText((diff > 0 and '+' or '−') .. math.abs(diff))
                        cell.diffBg:SetBackdropColor(diff > 0 and .10 or .40, diff > 0 and .35 or .08, diff > 0 and .08 or .06, 1)
                        cell.diffBg:SetBackdropBorderColor(diff > 0 and .30 or .85, diff > 0 and .75 or .25, diff > 0 and .22 or .20, 1)
                    end
                end
            end
            for _, l in ipairs(p.links) do l:Hide() end
            local li = 0
            for _, n in ipairs(tree.talents or {}) do
                local pre = n.prereqKey and byKey[n.prereqKey]
                if pre and li < #p.links and n.column == pre.column and (n.row or 0) > (pre.row or 0) then
                    li = li + 1
                    local l = p.links[li]
                    l:ClearAllPoints(); l:SetPoint('TOPLEFT', p.x0 + n.column * DX + CELL / 2 - 2, -64 - pre.row * DY - CELL - 2)
                    l:SetSize(4, math.max(2, (n.row - pre.row) * DY - CELL - 2))
                    local on = (ranks[n.key] or 0) > 0 or (ranks[pre.key] or 0) >= (pre.maxRank or 1)
                    l:SetVertexColor(on and 1 or .40, on and .78 or .40, on and .25 or .40, on and 1 or .8); l:Show()
                end
            end
        end
    end
    -- Details
    local n = S.selTalent
    W.selIcon:SetShown(n ~= nil)
    if n then
        local name, icon = spellInfo(n.spellId)
        W.selIcon:SetIcon(icon); W.selName:SetText(name or n.name or n.key)
        local lr, dr, m = live[n.key] or 0, (recommendation and recommendedRanks or ranks)[n.key] or 0, n.maxRank or 1
        W.selRanks:SetText(string.format('Im Spiel |cff%s%d/%d|r · Empfohlen |cff%s%d/%d|r', lr > 0 and 'ffd100' or 'ff5548', lr, m, dr > 0 and '20ff20' or 'aaaaaa', dr, m))
        local desc = n.spellId and (safe(C_Spell and C_Spell.GetSpellDescription, n.spellId) or safe(GetSpellDescription, n.spellId))
        local share = S.talentCompare and S.talentCompare.per and S.talentCompare.per[n.key]
        W.selDesc:SetText((type(desc) == 'string' and desc ~= '' and desc or 'Beschreibung im Talent-Tooltip (Maus über das Talent).')
            .. (share and ('\n\nDPS-Beitrag dieser Änderung: |cff20ff20' .. pct(share) .. '|r') or ''))
    else
        W.selName:SetText('Talent anklicken'); W.selRanks:SetText(''); W.selDesc:SetText('Fahre über ein Talent, um Rang und Beschreibung zu sehen.')
    end
    W.sideTitle:SetText('Beste Kombination gegen Im Spiel')
    W.compare:SetLabel('Kombination neu berechnen')
    if level then
        -- Fastest level path first; the unit is the time until a typical enemy of this level dies.
        local order = {}
        for t, r in ipairs(cmp and cmp.rows or {}) do order[#order + 1] = {t = t, r = r} end
        table.sort(order, function(a, b)
            local av, bv = a.r.kill and -a.r.kill or a.r.dps or -1e9, b.r.kill and -b.r.kill or b.r.dps or -1e9
            return av > bv
        end)
        for i, w in ipairs(W.diffs) do
            local o = order[i]
            w.icon:SetShown(o ~= nil)
            if o then
                local tree = trees[o.t]
                local first = tree and tree.talents and tree.talents[1]
                local _, icon = spellInfo(first and first.spellId); w.icon:SetIcon(icon)
                w.name:SetText(tostring(tree and tree.name or '?'))
                w.value:SetText(o.r.kill and ((string.format('%.1f', o.r.kill):gsub('%.', ',', 1)) .. ' s') or o.r.dps and thousands(o.r.dps) or '?')
                w.value:SetColor(o.t == cmp.best and GOLD or PALE)
            else w.name:SetText(''); w.value:SetText('') end
        end
        W.diffMore:SetText('')
        if S.treeBusy then W.result:SetText('…'); W.result:SetColor(GOLD)
        elseif cmp and cmp.best and order[1] and order[2] and order[1].r.kill and order[2].r.kill then
            local gain = (1 - order[1].r.kill / order[2].r.kill) * 100
            W.result:SetText(string.format('%s  %s schneller', tostring(trees[cmp.best] and trees[cmp.best].name or '?'), (string.format('%.0f %%', gain))))
            W.result:SetColor(GREEN)
        elseif cmp and cmp.best then W.result:SetText(tostring(trees[cmp.best] and trees[cmp.best].name or '?')); W.result:SetColor(GREEN)
        else W.result:SetText('') end
        local unm = 0
        for _, t in ipairs(paths and paths.trees or {}) do unm = math.max(unm, #t.unmodeled) end
        W.resultNote:SetText(S.talentMessage or (cmp and ('Bis zu drei gültige Builds je Baum geprüft, gleiche Ausrüstung und aktuelle Form. Maßstab: ' .. (cmp.byKill and 'Zeit bis ein Gegner dieser Stufe stirbt.' or 'DPS gegen den Benchmark-Gegner.') .. (unm > 0 and ' Talente ohne SIM-Regel sind nicht eingerechnet.' or ''))
            or '„Bäume vergleichen“ prüft mehrere gültige Levelwege je Baum und deren Rotationen.'))
        W.resultNote:SetColor(S.talentError and ORANGE or 'muted')
        W.compare:Show(); W.useLive:Hide(); W.clear:Hide(); W.clearNote:Hide()
        W.compare:SetUsable(not S.treeBusy and not S.talentBusy)
    else
        W.compare:Show(); W.useLive:Show(); W.clear:Show(); W.clearNote:Show()
        local diffs = {}
        for key, node in pairs(byKey) do
            local d = ((recommendation and recommendedRanks or ranks)[key] or 0) - (live[key] or 0)
            if d ~= 0 then diffs[#diffs + 1] = {node = node, d = d} end
        end
        table.sort(diffs, function(a, b) return math.abs(a.d) > math.abs(b.d) end)
        for i, w in ipairs(W.diffs) do
            local d = diffs[i]
            w.icon:SetShown(d ~= nil)
            if d then
                local name, icon = spellInfo(d.node.spellId)
                w.icon:SetIcon(icon); w.name:SetText(name or d.node.name or d.node.key)
                local share = S.talentCompare and S.talentCompare.per and S.talentCompare.per[d.node.key]
                w.value:SetText((d.d > 0 and '+' or '−') .. math.abs(d.d) .. (share and ('  ' .. pct(share)) or '')); w.value:SetColor(d.d > 0 and GREEN or RED)
            else w.name:SetText(''); w.value:SetText('') end
        end
        W.diffMore:SetText(#diffs == 0 and 'Entwurf entspricht deinen Talenten.' or #diffs > #W.diffs and ('+' .. (#diffs - #W.diffs) .. ' weitere Änderungen') or '')
        if recommendation then
            W.result:SetText(string.format('%+.2f DPS',tonumber(advice.delta)or 0))
            W.result:SetColor((tonumber(advice.delta)or 0)>0 and GREEN or PALE)
            W.resultNote:SetText((advice.requiresRespec and 'Nur mit Talent-Reset umsetzbar. ' or 'Mit deinen aktuellen Talenten vereinbar. ')
                .. tostring(advice.tested or '?')..' Builds geprüft; beste gefundene Variante, nicht mathematisch bewiesen.')
            W.resultNote:SetColor(advice.requiresRespec and ORANGE or PALE)
        elseif advice and advice.state=='busy' then
            W.result:SetText('…'); W.result:SetColor(GOLD)
            W.resultNote:SetText('Auftrag an MythicSim übermittelt; vollständige Misch-Builds werden verglichen.')
        elseif advice and advice.state=='unsupported' then
            W.result:SetText('Fehler'); W.result:SetColor(ORANGE)
            W.resultNote:SetText(tostring(advice.reason or 'Keine Rückmeldung von MythicSim'))
        elseif advice and advice.state=='no-points' then
            W.result:SetText('Keine Punkte'); W.result:SetColor(PALE)
            W.resultNote:SetText('Auf diesem Charakter sind noch keine Talentpunkte verfügbar.')
        else
            W.result:SetText('')
            W.resultNote:SetText(S.talentMessage or 'Es werden vollständige Misch-Builds verglichen, keine isolierten Talentbäume.')
        end
        W.useLive:Hide();W.clear:Hide();W.clearNote:Hide()
        W.compare:SetUsable(not (advice and advice.state=='busy'))
    end
    local bonus = 0
    if P.talentBonus then bonus = P.talentBonus() or 0 end
    local available = math.max(0, math.min(51, liveLevel() - 9 + bonus))
    W.points:SetText(string.format('%s: |cff%s%d|r von %d Punkten', recommendation and 'Beste Kombination' or 'Aktuell', spent > available and 'ff5548' or '20ff20', spent, available))
end

-- Page: Rotation Style --------------------------------------------------------------
local SWATCH = {{1, .82, .2}, {.30, .85, .25}, {.25, .55, 1}, {.66, .35, 1}, {1, .28, .25}, {1, .55, .12}}
local function previewIcons()
    local r = rotation()
    local l = currentLeveling()
    local choice = l and l.choice or r and r.choice
    local model = FUSLiveData and FUSLiveData[liveClass() or '']
    local out = {}
    for i, pol in ipairs(choice and choice.policies or {}) do
        if i > 3 then break end
        local name, icon
        if P.rotationHUD and P.rotationHUD.PolicyInfo then name, icon = P.rotationHUD.PolicyInfo(pol) end
        if not name or name == pol.key then name, icon = displayKey(model, pol.key) end
        out[i] = {name = name or pol.key, icon = icon}
    end
    return out
end
-- A static copy of the combat display, drawn with the same settings.
local function hudPreview(parent, x, y)
    local f = CreateFrame('Frame', nil, parent); f:SetSize(300, 150); f:SetPoint('TOPLEFT', x, y)
    f.proc = UI.Text(f, 0, -2, 300, nil, 15, '', GOLD, 'LEFT')
    f.main = CreateFrame('Frame', nil, f); f.main:SetSize(64, 64)
    f.glow = tex(f.main, 'OVERLAY', MEDIA .. 'FSGlow'); f.glow:SetPoint('TOPLEFT', -14, 14); f.glow:SetPoint('BOTTOMRIGHT', 14, -14)
    f.mainIcon = tex(f.main, 'ARTWORK'); f.mainIcon:SetAllPoints(); f.mainIcon:SetTexCoord(.07, .93, .07, .93)
    f.cd = UI.Text(f.main, 0, -22, 64, nil, 20, '', GOLD, 'CENTER')
    f.key = UI.Text(f.main, 0, 0, 60, nil, 16, '', PALE, 'RIGHT'); f.key:ClearAllPoints(); f.key:SetPoint('BOTTOMRIGHT', -3, 3)
    f.name = UI.Text(f, 0, 0, 200, nil, 16, '', PALE, 'LEFT')
    f.next = {}
    for i = 1, 2 do
        local n = CreateFrame('Frame', nil, f); n:SetSize(40, 40)
        n.icon = tex(n, 'ARTWORK'); n.icon:SetAllPoints(); n.icon:SetTexCoord(.07, .93, .07, .93)
        n.key = UI.Text(n, 0, 0, 36, nil, 12, '', PALE, 'RIGHT'); n.key:ClearAllPoints(); n.key:SetPoint('BOTTOMRIGHT', -2, 2)
        f.next[i] = n
    end
    function f:Paint(state, cfg, icons)
        local s = math.max(.6, math.min(1.6, cfg.scale or 1))
        local main = math.floor(64 * s + .5)
        local small = math.floor(40 * s + .5)
        local color = cfg.procColor or SWATCH[1]
        self:SetAlpha(cfg.alpha or 1)
        local top = (cfg.procText ~= false and state == 'proc') and 24 or 4
        self.proc:SetShown(cfg.procText ~= false and state == 'proc')
        self.proc:SetText('Proc aktiv – jetzt nutzen'); self.proc:SetTextColor(color[1], color[2], color[3], 1)
        self.main:SetSize(main, main); self.main:ClearAllPoints(); self.main:SetPoint('TOPLEFT', 14, -top)
        self.mainIcon:SetTexture(icons[1] and icons[1].icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
        self.mainIcon:SetDesaturated(state == 'cd'); self.mainIcon:SetVertexColor(state == 'range' and 1 or 1, state == 'range' and .35 or 1, state == 'range' and .35 or 1)
        self.mainIcon:SetAlpha(state == 'cd' and .6 or 1)
        self.glow:SetShown(state == 'proc'); self.glow:SetVertexColor(color[1], color[2], color[3], 1)
        self.cd:SetShown(state == 'cd'); self.cd:SetText('1,2'); self.cd:SetWidth(main); self.cd:ClearAllPoints(); self.cd:SetPoint('CENTER')
        self.key:SetShown(cfg.showKeys ~= false); self.key:SetText('3')
        self.name:SetShown(cfg.showName ~= false); self.name:SetText(icons[1] and icons[1].name or 'Zauber')
        self.name:ClearAllPoints(); self.name:SetPoint('TOPLEFT', self.main, 'BOTTOMLEFT', 0, -6)
        for i, n in ipairs(self.next) do
            local show = i <= (cfg.queue or 2)
            n:SetShown(show)
            n:SetSize(small, small); n:ClearAllPoints(); n:SetPoint('BOTTOMLEFT', self.main, 'BOTTOMRIGHT', 10 + (i - 1) * (small + 8), 0)
            n:SetAlpha(i == 1 and .85 or .65)
            n.icon:SetTexture(icons[i + 1] and icons[i + 1].icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
            n.key:SetShown(cfg.showKeys ~= false); n.key:SetText(tostring(3 + i))
        end
    end
    return f
end
local function slider(parent, x, y, w, minV, maxV, step, get, set)
    local s = CreateFrame('Slider', nil, parent, 'BackdropTemplate')
    s:SetOrientation('HORIZONTAL'); s:SetSize(w, 16); s:SetPoint('TOPLEFT', x, y)
    s:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1}); s:SetBackdropColor(.06, .06, .08, 1); s:SetBackdropBorderColor(.45, .36, .18, 1)
    local thumb = s:CreateTexture(nil, 'OVERLAY'); thumb:SetTexture(MEDIA .. 'FSButtonGold'); thumb:SetSize(12, 22)
    s:SetThumbTexture(thumb)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetScript('OnValueChanged', function(_, v)
        if s.syncing then return end
        set(math.floor(v / step + .5) * step); applyHud(); D.Refresh()
    end)
    function s:Sync() self.syncing = true; self:SetValue(get()); self.syncing = nil end
    return s
end
local function buildStyle()
    local page = pages.style
    local prev = Panel(page, 14, -8, 700, 380, 'Live-Vorschau', 20)
    UI.Text(prev, 16, -42, 660, nil, 13, 'Gespeicherte Priorität; Bedingungen selbst prüfen.', PALE)
    W.previewState = 'proc'
    W.previewTabs = {}
    for i, d in ipairs({{'normal', 'Normal'}, {'proc', 'Proc'}, {'cd', 'Abklingzeit'}}) do
        local b = Btn(prev, 16 + (i - 1) * 140, -68, 132, 32, d[2], function() W.previewState = d[1]; D.Refresh() end, 'dark')
        b.state = d[1]; W.previewTabs[i] = b
    end
    local stage = UI.Box(prev, 16, -110, 668, 254, {.05, .06, .07, .95}, {.22, .20, .15, 1})
    W.preview = hudPreview(stage, 220, -50)
    -- Settings
    local set = Panel(page, 726, -8, 440, 380, 'Anzeige-Einstellungen', 20)
    local cfg = hudCfg
    UI.Text(set, 16, -52, 120, nil, 14, 'Größe', PALE)
    W.scale = slider(set, 130, -52, 220, .6, 1.6, .1, function() return cfg().scale or 1 end, function(v) cfg().scale = v end)
    W.scaleText = UI.Text(set, 362, -52, 64, nil, 14, '', PALE, 'RIGHT')
    UI.Text(set, 16, -88, 120, nil, 14, 'Deckkraft', PALE)
    W.alpha = slider(set, 130, -88, 220, .3, 1, .1, function() return cfg().alpha or 1 end, function(v) cfg().alpha = v end)
    W.alphaText = UI.Text(set, 362, -88, 64, nil, 14, '', PALE, 'RIGHT')
    UI.Text(set, 16, -126, 120, nil, 14, 'Proc-Farbe', PALE)
    W.swatches = {}
    for i, c in ipairs(SWATCH) do
        local b = CreateFrame('Button', nil, set, 'BackdropTemplate'); b:SetSize(32, 32); b:SetPoint('TOPLEFT', 130 + (i - 1) * 40, -118)
        b:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 2}); b:SetBackdropColor(c[1], c[2], c[3], 1)
        b:SetScript('OnClick', function() if combat() then return end cfg().procColor = {c[1], c[2], c[3]}; applyHud(); D.Refresh() end)
        b.color = c; W.swatches[i] = b
    end
    UI.Text(set, 16, -170, 120, nil, 14, 'Nächste Zauber', PALE)
    W.queue = {}
    for i, d in ipairs({{0, 'Keine'}, {1, 'Eine'}, {2, 'Zwei'}}) do
        local b = Btn(set, 130 + (i - 1) * 98, -162, 92, 30, d[2], function() cfg().queue = d[1]; applyHud(); D.Refresh() end, 'dark')
        b.value = d[1]; W.queue[i] = b
    end
    local checks = {{'showKeys', 'Tastenbelegung'}, {'showName', 'Zaubername'}, {'procText', 'Proc-Text'}, {'procSound', 'Ton bei Proc', true},
                    {'combatOnly', 'Nur im Kampf'}, {'locked', 'Position sperren'}, {'barHighlight', 'Aktionsleiste markieren'}}
    W.checks = {}
    for i, d in ipairs(checks) do
        local col, row = (i - 1) > 3 and 1 or 0, (i - 1) % 4
        if i > 4 then row = i - 5 end
        local key, offDefault = d[1], d[3]
        local c = UI.Check(set, 16 + col * 210, -206 - row * 30, d[2], function()
            local v = cfg()[key]
            if v == nil then return not offDefault end
            return v
        end, function(on) cfg()[key] = on; applyHud(); D.Refresh() end)
        c:SetSize(24, 24)
        c.caption:SetFont((GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT, 14, '')
        c.caption:ClearAllPoints(); c.caption:SetPoint('LEFT', c, 'RIGHT', 4, 0)
        W.checks[i] = c
    end
    W.move = Btn(set, 16, -330, 260, 34, 'Position verschieben', function()
        local c = cfg(); c.locked = false; c.preview = true; applyHud(); D.Refresh()
    end, 'red')
    W.reset = Btn(set, 286, -330, 138, 34, 'Standard', function()
        local c = cfg()
        c.scale, c.alpha, c.procColor, c.queue, c.showKeys, c.showName, c.procText, c.procSound, c.combatOnly, c.locked, c.preview, c.barHighlight =
            1, 1, nil, 2, true, true, true, false, true, true, nil, true
        applyHud(); D.Refresh()
    end, 'red')
    -- Examples
    local ex = Panel(page, 14, -400, 1152, 290, 'Darstellungsbeispiele', 20)
    UI.Text(ex, 16, -44, 300, 60, 13, 'So sieht die Anzeige in den verschiedenen Situationen aus.', PALE)
    W.examples = {}
    for i, d in ipairs({{'normal', 'Normal'}, {'proc', 'Proc'}, {'cd', 'Abklingzeit'}, {'range', 'Außer Reichweite'}}) do
        local x = 330 + (i - 1) * 205
        local cell = UI.Box(ex, x, -40, 190, 200, {.03, .035, .045, .95}, {.22, .20, .15, 1})
        local f = CreateFrame('Frame', nil, cell); f:SetSize(80, 80); f:SetPoint('TOP', 0, -30)
        f.glow = tex(f, 'OVERLAY', MEDIA .. 'FSGlow'); f.glow:SetPoint('TOPLEFT', -16, 16); f.glow:SetPoint('BOTTOMRIGHT', 16, -16)
        f.icon = tex(f, 'ARTWORK'); f.icon:SetAllPoints(); f.icon:SetTexCoord(.07, .93, .07, .93)
        f.text = UI.Text(f, 0, -28, 80, nil, 22, d[1] == 'cd' and '1,2' or '', GOLD, 'CENTER')
        UI.Text(cell, 0, -150, 190, nil, 15, d[2], PALE, 'CENTER')
        f.state = d[1]; W.examples[i] = f
    end
end
local function refreshStyle()
    local cfg = hudCfg()
    local icons = previewIcons()
    for _, b in ipairs(W.previewTabs) do b:SetKind(b.state == W.previewState and 'gold' or 'dark') end
    W.preview:Paint(W.previewState, cfg, icons)
    W.scale:Sync(); W.alpha:Sync()
    W.scaleText:SetText((string.format('%.1f ×', cfg.scale or 1):gsub('%.', ',', 1)))
    W.alphaText:SetText(string.format('%d %%', math.floor((cfg.alpha or 1) * 100 + .5)))
    local pc = cfg.procColor or SWATCH[1]
    for _, s in ipairs(W.swatches) do
        local on = math.abs(s.color[1] - pc[1]) + math.abs(s.color[2] - pc[2]) + math.abs(s.color[3] - pc[3]) < .05
        s:SetBackdropBorderColor(on and 1 or .2, on and 1 or .2, on and 1 or .2, 1)
    end
    for _, b in ipairs(W.queue) do b:SetKind(b.value == (cfg.queue or 2) and 'blue' or 'dark') end
    for _, c in ipairs(W.checks) do c:Sync() end
    local icon = icons[1] and icons[1].icon or 'Interface\\Icons\\INV_Misc_QuestionMark'
    for _, f in ipairs(W.examples) do
        f.icon:SetTexture(icon)
        f.icon:SetDesaturated(f.state == 'cd'); f.icon:SetAlpha(f.state == 'cd' and .6 or 1)
        f.icon:SetVertexColor(1, f.state == 'range' and .35 or 1, f.state == 'range' and .35 or 1)
        f.glow:SetShown(f.state == 'proc'); f.glow:SetVertexColor(pc[1], pc[2], pc[3], 1)
    end
end

local function build()
    if frame then return end
    buildWindow(); buildOverview(); buildTalents(); buildStyle()
    frame:SetScript('OnUpdate', function(_, e)
        D.elapsed = (D.elapsed or 0) + e
        if D.elapsed >= .5 then D.elapsed = 0; D.Refresh() end
    end)
    frame:SetScript('OnShow', function() P.jobBudgetMs = 6 end)
    frame:SetScript('OnHide', function() P.jobBudgetMs = nil; if menu then menu:Hide() end end)
    frame:Hide()
    W.host = frame
    setPage(S.page or 'overview')
end

-- Refresh ---------------------------------------------------------------------
function D.Refresh()
    if not frame or not frame:IsShown() or not app() then return end
    advanceChain()
    P.jobBudgetMs = not combat() and 6 or nil
    local page = S.page or 'overview'
    local snap = snapshot()
    local spec, most = nil, 0
    for _, tree in ipairs(snap and snap.talents or {}) do if (tree.points or 0) > most then most = tree.points; spec = tree.name end end
    local class = liveClass()
    local currentTab = app().state.ui and app().state.ui.tab
    for _, tab in ipairs(W.tabs or {}) do
        tab:SetKind((tab.page == page or (tab.page == 'gear' and page == 'more' and currentTab == 'gear')) and 'gold' or 'dark')
    end
    W.title:SetText('ForeverCore  ·  ' .. (page == 'more' and currentTab == 'gear' and 'Ausrüstung' or PAGE_TITLE[page]))
    W.who:SetText((CLASS_NAMES[class] or class or '?') .. '  ·  Stufe ' .. liveLevel() .. (spec and ('  ·  ' .. spec) or ''))
    W.extra:SetShown(page == 'talents')
    if page == 'talents' and _G.ForeverCoreClient and ForeverCoreClient.RecommendTalents and not combat() then
        ForeverCoreClient.RecommendTalents()
    end
    if page == 'overview' then refreshOverview() elseif page == 'talents' then refreshTalents() elseif page == 'style' then refreshStyle()
    elseif P.shell and P.shell.Refresh then P.shell.Refresh() end
end
function D.Show(pageName)
    if combat() then return end
    build()
    local api = _G.ForeverSimDungeonAPI
    if api and api.Hide then api.Hide() end
    if app() and (not app().state.character.snapshot or app().state.dirty) then app().Capture() end
    applyAutoEnemy()
    -- Same visual scale as Blizzard frames; shrink only if the screen is too small (tabs hang below).
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    frame:SetScale(math.min(1, w * .97 / FW, h * .92 / (FH + 44)))
    frame:Show()
    -- Opening without a page (toggle, /fsim) never lands on an empty "Mehr" page.
    if not pageName and S.page == 'more' then pageName = 'overview' end
    if PAGE_TITLE[pageName or ''] then setPage(pageName) else D.Refresh() end
end
function D.Hide() if frame then frame:Hide() end; if UI.CloseMenu then UI.CloseMenu() end; if P.shell and P.shell.Hide then P.shell.Hide() end end
function D.MoreHost() build(); return W.moreHost end
function D.Toggle() if frame and frame:IsShown() then D.Hide() else D.Show() end end
function D.IsShown() return frame and frame:IsShown() or false end
function D.Notice() local n = S.notice; S.notice = nil; return n end
function D.TraceBusy() return S.traceBusy and S.traceRevision == P.revision end
-- Shell compatibility: the old overview route now opens this window.
function D.Mount(view) D.Show(); return frame end
