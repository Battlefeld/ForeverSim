-- A single app window. Views are created once and reused on navigation.
local P = FUSLive
local S = {}
P.shell = S
local views, refreshers = {}, {}
-- Same look as the other pages (UI/Dashboard.lua): gold titles, warm light text, dark panels with a gold rim.
local MEDIA = 'Interface\\AddOns\\ForeverSimBridge\\Media\\'
local palette = {gold = {1, .82, 0}, text = {.93, .91, .85}, muted = {.62, .60, .55},
                 purple = {1, .82, 0}, green = {.12, 1, .12}}

local function app() return P.app end
local function state() return app().state end
local function combat() return InCombatLockdown and InCombatLockdown() end
local function text(parent, x, y, width, height, value, color, large)
    local label = parent:CreateFontString(nil, 'OVERLAY', large and 'GameFontNormalLarge' or 'GameFontNormal')
    label:SetPoint('TOPLEFT', x, y)
    label:SetSize(width, height)
    label:SetJustifyH('LEFT')
    label:SetJustifyV('TOP')
    label:SetWordWrap(true)
    local rgb = palette[color or 'text']
    label:SetTextColor(rgb[1], rgb[2], rgb[3])
    label:SetText(value or '')
    return label
end
local function surface(parent, x, y, width, height)
    local box = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
    box:SetSize(width, height)
    box:SetPoint('TOPLEFT', x, y)
    box:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8',
        edgeSize = 1, insets = {left = 1, right = 1, top = 1, bottom = 1}})
    box:SetBackdropColor(.016, .018, .024, .92)
    box:SetBackdropBorderColor(.40, .31, .16, 1)
    return box
end
local function button(parent, x, y, width, label, callback, primary)
    local b = surface(parent, x, y, width, 36)
    -- Button textures of the render design: gold for the main action, dark otherwise.
    b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0)
    local bg = b:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetTexture(MEDIA .. (primary and 'FSButtonGold' or 'FSButtonDark'))
    local click = CreateFrame('Button', nil, b)
    click:SetAllPoints()
    b.label = text(click, 10, -10, width - 20, 22, label, 'text')
    b.label:SetJustifyH('CENTER')
    if primary then b.label:SetTextColor(.13, .08, .02) end
    click:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight', 'ADD')
    click:SetScript('OnClick', function() if not combat() then callback() end end)
    return b
end
local function input(parent, x, y, width, value)
    local box = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    box:SetSize(width, 30)
    box:SetPoint('TOPLEFT', x, y)
    box:SetAutoFocus(false)
    box:SetText(value or '')
    box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    return box
end
local function fmt(value, suffix)
    local number
    if P.publicNumber then number = P.publicNumber(value)
    elseif type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then number = value end
    return number and (string.format('%.1f%s', number, suffix or ''):gsub('%.',',')) or '–'
end
local function profile() return state().character.profile end
local function encounter()
    local p = profile()
    return P.encounters.Resolve(p and p.level or 10, ForeverSimBridgeDB.encounter or {})
end
local function currentResult(kind)
    local saved = state()[kind]
    return saved and saved.revision == P.revision and saved.result
end
local function title(parent, value, note)
    text(parent, 20, -16, 1050, 30, value, 'gold', true)
    text(parent, 20, -54, 1050, 44, note, 'muted')
end
local function healthContext()
    local p = profile()
    if p then p = P.encounters.Apply(p, ForeverSimBridgeDB.encounter or {}) end
    return p and P.leveling and P.leveling.Context(p) or nil
end


local function subnav(v, entries, active)
    for i, entry in ipairs(entries) do
        button(v, 16 + (i - 1) * 213, -10, 201, entry[1], function() app().Open(state().ui.tab, entry[2], state().ui.key) end, active == entry[2])
    end
    local content = CreateFrame('Frame', nil, v)
    content:SetSize(1073, 643)
    content:SetPoint('TOPLEFT', 16, -62)
    v.mountHost = content
    return content
end

local function benchmark(v, subtab)
    if subtab=='encounter' or subtab=='leveling' then
        local content=subnav(v,{{'Boss-Auswahl','encounter'},{'Eigene Werte','leveling'}},subtab)
        if subtab=='leveling' then P.analysisUI.Mount(content,'leveling')else P.encounterUI.Mount(content)end
        return
    end
    title(v,'Dein Gegner','Wähle einen passenden Gegner. Die Lebenspunkte werden für deinen Level geschätzt.')
    local box=surface(v,20,-112,1045,195)
    local info=text(box,20,-25,995,100,'','purple',true)
    local function choose(mode,offset)
        P.encounters.Configure({mode=mode,offset=offset});S.Refresh()
    end
    button(box,20,-140,325,'Gleiches Level',function()choose('quest',0)end,true)
    button(box,360,-140,325,'Ein Level höher',function()choose('quest',1)end)
    button(box,700,-140,325,'Elite-Gegner',function()choose('elite',0)end)
    local result=surface(v,20,-329,1045,236)
    text(result,20,-19,995,28,'WIE SCHNELL BESIEGST DU DEN GEGNER?', 'gold',true)
    local report=text(result,20,-69,995,139,'','text')
    button(v,20,-588,1045,'Leveltempo berechnen',function()P.actions.RunLeveling()end,true)
    button(v,20,-644,515,'Boss auswählen',function()app().Open('benchmark','encounter')end)
    button(v,550,-644,515,'Eigene Lebenspunkte / Erholung',function()app().Open('benchmark','leveling')end)
    refreshers[v]=function()
        local hp=healthContext()
        info:SetText(hp and ('Level '..hp.targetLevel..' · '..fmt(hp.targetHealth)..' HP\n'..(hp.estimated and 'Geschätzte Lebenspunkte' or hp.source)) or 'Charakterdaten zuerst laden')
        local r=P.lastLeveling and P.lastLeveling.revision==P.revision and P.lastLeveling.result
        report:SetText(r and P.leveling.Text(r)..'\n\n'..tostring(r.caveat or '') or 'Berechne den Vergleich, um Kampfzeit und Erholung zu sehen. Die HP-Annahme braucht kein anvisiertes Ziel.')
    end
end

local function gear(v, subtab)
    local content = subnav(v, {{'Itemvergleich', 'compare'}}, 'compare')
    title(content, 'Ausrüstung vergleichen', 'Item-ID eingeben oder einen Gegenstandslink einfügen. Es wird keine Ausrüstung angelegt.')
    local ref = input(content, 25, -114, 723, state().itemReference)
    ref:SetScript('OnTextChanged', function(self) state().itemReference = self:GetText() end)
    button(content, 775, -111, 268, 'Vergleich starten', function() P.actions.CompareItem(ref:GetText()) end, true)
    local report = surface(content, 20, -180, 1025, 335)
    text(report, 20, -18, 985, 24, 'ERGEBNIS', 'gold')
    local info = text(report, 20, -64, 981, 242, '')
    text(content, 22, -546, 1015, 65, 'Waffen-DPS beschreibt Min-/Max-Schaden und Geschwindigkeit. Dieser Wert wird nicht zusätzlich als Angriffskraft eingerechnet.', 'muted')
    refreshers[v] = function()
        local r = currentResult('gear')
        local lines = P.explainItem(r)
        if r and r.item then table.insert(lines, 1, r.item.name or 'Gegenstand') end
        info:SetText(table.concat(lines, '\n\n'))
    end
end

-- The loot of the dungeon you are in is shown by ForeverCore (dungeon window, /fc dungeon); this page lists the
-- dungeons and their bosses and sets a boss as the benchmark enemy.
local function dungeonList()
    local core = _G.ForeverCoreClient
    if core and core.DungeonReport then core.DungeonReport.Report(false, 1, false, true) end
end
local function dungeons(v)
    title(v, 'Dungeons', 'Dungeon wählen und einen Boss als Benchmark nutzen. Die Loot-Liste zeigt ForeverCore im Dungeon.')
    local selection = text(v, 24, -113, 1015, 50, '', 'purple', true)
    local function selected()
        local api = _G.ForeverSimDungeonAPI
        local list = api and api.ListDungeons and api.ListDungeons() or {}
        for _, d in ipairs(list) do if d.key == state().ui.key or d.name == state().ui.key then return d, list end end
        return list[1], list
    end
    button(v, 20, -175, 335, 'Nächster Dungeon', function()
        local d, list = selected()
        for i, record in ipairs(list) do if d and record.key == d.key then app().Open('dungeons', nil, list[i % #list + 1].key); return end end
    end)
    button(v, 372, -175, 335, 'Boss als Benchmark', function()
        local d = selected()
        if not d then state().notice = 'FDQ aktivieren, um einen Dungeon auszuwählen.'; S.Refresh(); return end
        local names = P.encounters.ListBosses(d.journalName or d.name)
        local ok, issue = P.encounters.Configure({mode = 'dungeon', dungeon = d.journalName or d.name, boss = names[1]})
        if not ok then state().notice = tostring(issue) end
        app().Open('benchmark', 'encounter')
    end, true)
    button(v, 723, -175, 342, 'Loot-Liste (im Dungeon)', dungeonList)
    local panel = surface(v, 20, -232, 1045, 352)
    text(panel, 20, -18, 1000, 24, 'BOSSE', 'gold')
    local detail = text(panel, 20, -59, 996, 275, '')
    refreshers[v] = function()
        local d = selected()
        selection:SetText(d and (d.name .. ' · Level ' .. tostring(d.min or '?') .. '–' .. tostring(d.max or '?')) or 'Kein Dungeon im Katalog.')
        local api = _G.ForeverSimDungeonAPI
        local lines = {}
        local bosses = d and api and api.ListBosses and api.ListBosses(d.key) or {}
        for i, boss in ipairs(bosses) do
            if i > 7 then break end
            lines[#lines + 1] = boss.name .. ' · Level ' .. tostring(boss.level or '?')
        end
        detail:SetText(table.concat(lines, '\n'))
    end
end

local function analysis(v, subtab)
    local key = subtab == 'audit' and 'audit' or 'trace'
    local content = subnav(v, {{'Kampftrace', 'trace'}, {'Kampfaudit', 'audit'}}, key)
    if key == 'audit' then P.analysisUI.Mount(content, 'audit') else P.traceUI.Mount(content) end
end

local function diagnostics(v, subtab)
    title(v, 'Diagnose & Hilfe', 'Technischer Status und Befehle. Normale Berechnungen starten über die jeweiligen Seiten.')
    local box = surface(v, 20, -107, 1045, 474)
    local info = text(box, 20, -20, 995, 429, '')
    button(v, 20, -604, 515, 'Cache leeren', function() P.invalidate(); state().notice = 'Cache geleert. Ergebnisse neu berechnen.'; S.Refresh() end)
    button(v, 550, -604, 515, 'Charakter aktualisieren', function() app().Capture(); S.Refresh() end)
    refreshers[v] = function()
        local db = ForeverSimBridgeDB
        local lines = {'Schutzmodus: ' .. (P.passiveSafetyMode() and 'aktiv · automatische Live-Lesungen aus' or 'Live-Diagnose aktiviert'),
            'Combat Engine: ' .. tostring(P.version) .. ' · Oberfläche: 1.16.0 Beta',
            'Blockierte Aktionen: ' .. tostring(db.blockedActionCount or 0),
            'Letzte blockierte Aktion: ' .. tostring(db.lastBlockedAction and db.lastBlockedAction.action or 'keine'),
            'Letzter interner Fehler: ' .. tostring(state().lastTechnicalError or 'keiner'),
            'Jobs: ' .. tostring(P.pendingJobs()) .. ' · max. bisheriger SIM-Slice: ' .. fmt(P.metrics.maxSliceMs, ' ms'),
            'Kampfaudit: automatische Zielerfassung deaktiviert; manuelle Daten / HP-Modell verfügbar',
            '', '/fsim oder /fus — Übersicht', '/fus optimize — Rotation berechnen',
            '/fsimtalents — Build & Talente', '/fus leveling — Leveling-Vergleich',
            '/fsimtarget — Boss-/Quest-Benchmark', '/fus audit — Kampfaudit',
            '/fus cancel — aktuelle Berechnung abbrechen', '/fus help — diese Hilfe'}
        info:SetText(table.concat(lines, '\n'))
    end
end


-- The fachansichten live on the "Mehr" page of the one ForeverSim window (UI/Dashboard.lua).
-- This module owns no window of its own: it fills the page host with the requested view.
local function host_frame() return P.dashboard and P.dashboard.MoreHost and P.dashboard.MoreHost() end
local VIEW_W, VIEW_H = 1106, 722

function S.Refresh()
    local v = S.active
    local notice = P.dashboard and P.dashboard.Notice and P.dashboard.Notice()
    if notice then state().notice = notice end
    if v and v:IsShown() and refreshers[v] then refreshers[v]() end
end

function S.Show(tab, subtab)
    if combat() then return end
    local host = host_frame()
    if not host then return end
    local key = tab .. ':' .. (subtab or '')
    local v = views[key]
    for _, old in pairs(views) do old:Hide() end
    if not v then
        v = CreateFrame('Frame', nil, host)
        v:SetSize(VIEW_W, VIEW_H); v:SetPoint('TOP', host, 'TOP', 0, 0)
        v:SetScale(math.min(1, (host:GetWidth() or VIEW_W) / VIEW_W, (host:GetHeight() or VIEW_H) / VIEW_H))
        views[key] = v
        if tab == 'benchmark' then benchmark(v, subtab)
        elseif tab == 'gear' then gear(v, subtab)
        elseif tab == 'dungeons' then dungeons(v)
        elseif tab == 'analysis' then analysis(v, subtab)
        elseif tab == 'diagnostics' then diagnostics(v, subtab) end
    end
    -- Shared legacy views move between subpages; mount on every route activation.
    if tab == 'benchmark' and v.mountHost then
        local content = v.mountHost
        if subtab == 'leveling' then P.analysisUI.Mount(content, 'leveling') else P.encounterUI.Mount(content) end
    elseif tab == 'analysis' then
        local content = v.mountHost
        if subtab == 'audit' then P.analysisUI.Mount(content, 'audit') else P.traceUI.Mount(content) end
    end
    S.active = v
    v:Show()
    S.Refresh()
end
function S.Hide() if S.active then S.active:Hide() end end
function S.IsShown() return S.active ~= nil and S.active:IsShown() and P.dashboard and P.dashboard.IsShown() or false end
function S.GetFrame() return host_frame() end

