-- Own-window routing only. Never register in Blizzard's secure panel lists.
local P = FUSLive
local App = {state = {ui = {tab = 'overview'}, character = {status = 'unknown'},
    simulation = {status = 'idle'}, nextRun = 0, revisions = {character = 0, gear = 0, talents = 0, encounter = 0}}}
P.app = App

local routes = {overview = true, talents = true, rotation = true, benchmark = true,
                gear = true, dungeons = true, analysis = true, diagnostics = true}
local aliases = {simulation = 'benchmark', database = 'diagnostics'}

function App.Refresh()
    if P.shell then P.shell.Refresh() end
end

function App.Hide()
    if P.shell then P.shell.Hide() end
end

function App.Capture()
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, snapshot = pcall(P.capture, true)
    if ok and snapshot then
        local good, profile = pcall(P.normalizeSnapshot, snapshot)
        App.state.character = {snapshot = snapshot, profile = good and profile or nil,
                               status = good and 'ready' or 'incomplete'}
        App.state.dirty = nil
    else
        App.state.character = {status = 'incomplete', error = tostring(snapshot or 'Charakterdaten fehlen')}
    end
end

function App.Open(tab, subtab, key)
    tab = aliases[tab] or tab
    if not routes[tab] then tab = 'overview' end
    if tab == 'dungeons' then key, subtab = key or subtab, nil end
    if InCombatLockdown and InCombatLockdown() then
        App.deferred = {tab, subtab, key}
        return
    end
    local api = _G.ForeverSimDungeonAPI
    if api and api.Hide then api.Hide() end
    if not App.state.character.snapshot or App.state.dirty then App.Capture() end
    App.state.ui = {tab = tab, subtab = subtab, key = key}
    if P.shell then P.shell.Show(tab, subtab, key) end
end

function App.Toggle()
    if P.shell and P.shell.IsShown() then App.Hide() else App.Open('overview') end
end

function App.Embed(frame, parent, width, height)
    if not frame then return end
    frame:SetParent(parent)
    frame:SetMovable(false)
    frame:RegisterForDrag()
    frame:SetScript('OnDragStart', nil)
    frame:SetScript('OnDragStop', nil)
    frame:SetClampedToScreen(false)
    frame:SetFrameStrata('DIALOG')
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame:ClearAllPoints()
    frame:SetScale(math.min(1, parent:GetWidth() / width, parent:GetHeight() / height))
    frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0)
    if frame.appClose then frame.appClose:Hide() end
    frame:Show()
    return frame
end

-- Existing UIs retain their data/render logic but their public entry points route here.
local function bind(module, route, default, dimensions, translate)
    if not module or not module.Show or not module.GetFrame then return end
    local show = module.Show
    module.Mount = function(parent, subtab, key)
        show(subtab or default, key)
        local view = App.Embed(module.GetFrame(), parent, dimensions[1], dimensions[2])
        if module.Refresh then module.Refresh() end
        return view
    end
    module.Show = function(subtab, key)
        if translate then return translate(subtab, key) end
        App.Open(route, subtab or default, key)
    end
    module.Toggle = function() App.Open(route, default) end
end

bind(P.encounterUI, 'benchmark', 'encounter', {800, 605})
bind(P.analysisUI, 'benchmark', 'leveling', {720, 540}, function(tab, key)
    if tab == 'dungeon' then App.Open('dungeons', nil, key)
    elseif tab == 'audit' then App.Open('analysis', 'audit')
    else App.Open('benchmark', 'leveling') end
end)
bind(P.traceUI, 'analysis', 'trace', {955, 738})
if P.talentPlannerUI then
    P.talentPlannerUI.Toggle = function() App.Open('talents') end
end
if P.rotationHUD then
    P.rotationHUD.showStats = function() App.Open('rotation') end
end
P.dashboardUI = {Show = App.Open, Toggle = App.Toggle, SetTab = App.Open, Refresh = App.Refresh,
    Export = function() App.Open('analysis', 'trace') end,
    Command = function(message) if message == 'dashboard' or message == 'ui' then App.Open('overview'); return true end end}
P.optimizeNow = function() return P.actions.RunRotation() end
P.leveling.Optimize = function(autoApply) return P.actions.RunLeveling(autoApply) end
local configureEncounter = P.encounters.Configure
P.encounters.Configure = function(patch)
    local ok, issue = configureEncounter(patch)
    if ok then
        App.state.revisions.encounter = App.state.revisions.encounter + 1
        local profile = App.state.character.profile
        if profile then App.state.character.profile = P.encounters.Apply(profile, ForeverSimBridgeDB.encounter) end
        App.Refresh()
    end
    return ok, issue
end

local legacyCommand = SlashCmdList.FOREVERSIMBRIDGE
local commands = {
    [''] = function() App.Open('overview') end,
    help = function() App.Open('diagnostics', 'commands') end,
    optimize = function() P.actions.RunRotation() end,
    talents = function() App.Open('talents') end,
    leveling = function() App.Open('benchmark', 'leveling') end,
    encounter = function() App.Open('benchmark', 'encounter') end,
    target = function() App.Open('benchmark', 'encounter') end,
    analysis = function() App.Open('analysis', 'trace') end,
    audit = function() App.Open('analysis', 'audit') end,
    stats = function() App.Open('rotation') end,
    gear = function() App.Open('gear') end,
    dungeon = function() App.Open('dungeons') end,
    recommend = function() App.Open('dungeons') end,
    safety = function() App.Open('diagnostics') end,
    safe = function() App.Open('diagnostics') end,
    taint = function() App.Open('diagnostics') end,
    diagnose = function() App.Open('diagnostics') end,
    status = function() App.Open('diagnostics') end,
    cancel = function() P.actions.Cancel() end,
    ['items on'] = function() ForeverSimBridgeDB.itemScores = nil; if P.itemScore then P.itemScore.Changed() end; print('Forever SIM: Item-Bewertung an Items ist AN.') end,
    ['items off'] = function()
        ForeverSimBridgeDB.itemScores = false
        if P.itemScore then for _, g in ipairs({'bags', 'quest', 'roll'}) do P.itemScore.ClearMarks(g) end end
        print('Forever SIM: Item-Bewertung an Items ist AUS (Tooltip, Quest, Würfeln, Taschen).')
    end,
}
function App.Command(message)
    local normalized = (message or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if commands[normalized] then return commands[normalized]() end
    local ok, issue = pcall(legacyCommand, normalized)
    if not ok then
        App.state.notice = tostring(issue)
        App.Open('diagnostics')
    end
end
SlashCmdList.FOREVERSIMBRIDGE = App.Command
SLASH_FOREVERSIMDASH1 = '/fsim'
SlashCmdList.FOREVERSIMDASH = function(message) App.Command(message) end
SlashCmdList.FOREVERSIMTRACE = function() App.Open('analysis', 'trace') end
SlashCmdList.FOREVERSIMENCOUNTER = function() App.Open('benchmark', 'encounter') end

local events = CreateFrame('Frame')
for _, name in ipairs({'PLAYER_EQUIPMENT_CHANGED', 'PLAYER_LEVEL_UP', 'SPELLS_CHANGED',
                      'PLAYER_TALENT_UPDATE', 'CHARACTER_POINTS_CHANGED', 'PLAYER_REGEN_ENABLED'}) do
    pcall(events.RegisterEvent, events, name)
end
events:SetScript('OnEvent', function(_, event, unit)
    if (event=='UNIT_PET' or event=='UNIT_AURA' or event=='UNIT_INVENTORY_CHANGED')and unit~='player'then return end
    if event=='UNIT_AURA' or event=='UNIT_INVENTORY_CHANGED'then
        if InCombatLockdown and InCombatLockdown()then App.contextDirty=true;return end
    end
    if event == 'PLAYER_REGEN_ENABLED' then
        if App.contextDirty then
            App.contextDirty=nil;App.state.dirty=true
            if P.invalidate then P.invalidate()end
            if P.rotationHUD then P.rotationHUD.invalidate()end
            if P.itemScore then P.itemScore.Changed()end
        end
        if App.deferred then local route = App.deferred; App.deferred = nil; App.Open(route[1], route[2], route[3]) end
        return
    end
    if not P.stateChanged(App) then return end
    -- Mark dirty and invalidate jobs; never read character/target APIs in this event.
    App.state.dirty = true
    local domain = event == 'PLAYER_EQUIPMENT_CHANGED' and 'gear' or event == 'PLAYER_LEVEL_UP' and 'character' or 'talents'
    App.state.revisions[domain] = App.state.revisions[domain] + 1
    if P.invalidate then P.invalidate() end
    if P.rotationHUD then P.rotationHUD.invalidate() end
    if P.itemScore then P.itemScore.Changed() end
    if App.state.simulation.status == 'running' then
        App.state.simulation.status = 'cancelled'
        App.state.simulation.phase = 'Charakter geändert – erneut berechnen'
    end
    App.Refresh()
end)

