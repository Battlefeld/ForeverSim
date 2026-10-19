"""Smoke test for the one-window UI (Übersicht, Talente, Rotation Style) and the combat display.

Loads every file from ForeverSimBridge.toc with a permissive WoW mock, opens the window,
switches all pages, clicks the main buttons and paints the combat display in all states.
It checks for Lua errors and a few layout invariants, not for pixel output.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wowmock_ui import load_addon

lua = load_addon()
lua.execute(r'''
local P = FUSLive
local D = P.dashboard
assert(D and D.Show and P.rotationHUD and P.rotationHUD.ApplyStyle, 'Module fehlen')
-- Open the window through the normal routes.
P.app.Open('overview'); assert(D.IsShown(), 'Fenster nicht offen')
for _, page in ipairs({'talents', 'style', 'overview', 'talents'}) do D.SetPage(page); D.Refresh() end
P.app.Open('talents'); assert(D.IsShown())
-- Click every button that exists in the window (actions may legitimately refuse without data).
local clicked = 0
for _, f in ipairs(frames) do
    local h = f.scripts.OnClick
    if f.kind == 'Button' and h then
        local ok, err = pcall(h, f, 'LeftButton')
        assert(ok, tostring(err))
        if ok then clicked = clicked + 1 end
    end
end
assert(clicked > 40, 'zu wenige Knöpfe: ' .. clicked)
D.Show('style'); D.Refresh()
-- Ziele.md Grundsatz 3: every route lives in the one window. No second big top-level frame is ever shown.
local function bigWindows()
    local n = 0
    for _, f in ipairs(frames) do
        if f.parent == UIParent and f.shown and (f.width or 0) >= 800 and (f.height or 0) >= 500 and f.kind ~= 'Anim' then n = n + 1 end
    end
    return n
end
for _, route in ipairs({{'benchmark', 'encounter'}, {'benchmark', 'leveling'}, {'gear', 'weights'}, {'analysis', 'scenario'},
                        {'analysis', 'trace'}, {'analysis', 'history'}, {'diagnostics'}, {'dungeons'}, {'overview'}, {'talents'}, {'rotation'}}) do
    local ok, err = pcall(P.app.Open, route[1], route[2])
    assert(ok, tostring(route[1]) .. ': ' .. tostring(err))
    assert(D.IsShown() and bigWindows() == 1, 'mehr als ein Fenster bei Route ' .. route[1] .. ': ' .. bigWindows())
end
P.app.Open('diagnostics'); assert(D.widgets.moreHost.shown and D.state.page == 'more')
-- Grundsatz 4: no second calculation button.
local starts = 0
for _, f in ipairs(frames) do
    if f.kind == 'FontString' and f.text == 'Simulation starten' then starts = starts + 1 end
end
assert(starts == 0, 'doppelter Rechenknopf')
-- Grundsatz 5: minimum level is fixed at 10.
assert(P.minSimLevel() == 10)
-- Filled data: rotation result, damage split, gear upgrade, unmodeled item, talent comparison.
local S, W = D.state, D.widgets
P.app.state.rotation = {revision = P.revision, result = {dps = 1248.4, baselineDps = 1200, improvementPercent = 4,
    choice = {policies = {{key = 'aimedShot'}, {key = 'multiShot', maintain = true}, {key = 'autoShot'}}}}}
S.trace = {revision = P.revision, spells = {{key = 'aimedShot', damage = 600}, {key = 'multiShot', damage = 300}}, pet = 100, ability = 900, misc = 0, casts = {}}
S.gear = {revision = P.revision, rows = {
    {item = {id = 1, name = 'Armbrust', origin = 'Tasche'}, result = {item = {id = 1, name = 'Armbrust', slot = 'ranged'}, percent = 5.2, delta = 60}},
    {item = {id = 2, name = 'Schmuck', origin = 'Tasche'}, reason = 'Effekt nicht modelliert'}}}
S.talentCompare = {pct = 1.7, unmodeled = {}}
D.Show("overview"); assert(D.IsShown())
assert(W.dps.text:find('DPS'), 'DPS fehlt: ' .. tostring(W.dps.text))
assert(W.rows[1].shown and W.rows[1].title.text:find('Armbrust'), 'Upgrade-Zeile fehlt')
assert(W.rows[2].shown and W.rows[2].title.text:find('Talent'), 'Talentzeile fehlt')
assert(W.rows[3].shown and W.rows[3].gain.text == '?', 'Unbekannt-Zeile fehlt')
assert(W.split[1].icon.shown and W.split[1].value.text == '60 %', 'Schadensanteil falsch: ' .. tostring(W.split[1].value.text))
local plated = false
for _, s in ipairs(W.slots) do if s.slotKey == 'ranged' and s.plate.shown then plated = true end end
assert(plated, 'Upgrade-Schild am Distanzplatz fehlt')
level = 9; P.app.Open('overview'); D.Refresh()
assert(not D.widgets.calc.enabled, 'Rechenknopf unter Level 10 aktiv')
level = 60; D.Refresh()
S.talentMode = 'draft'; D.SetPage('talents'); D.Refresh(); assert(W.result.text:find('1,7'), 'Talentergebnis fehlt')
D.SetPage('style'); D.Refresh()
-- Combat display: style settings and all paint states.
local cfg = P.rotationHUD.Config()
cfg.scale, cfg.alpha, cfg.queue, cfg.procColor = 1.3, .8, 1, {.3, .85, .25}
P.rotationHUD.ApplyStyle()
P.rotationHUD.RebuildKeys()
local a = {id = 19434, name = 'Aimed Shot', icon = 'Interface\\Icons\\INV_Spear_07'}
P.rotationHUD.inCombat = true
P.rotationHUD.paint(1, a, 'proc'); P.rotationHUD.paint(2, a); P.rotationHUD.paint(3, nil)
P.rotationHUD.inCombat = false
cfg.locked = false; cfg.preview = true; P.rotationHUD.ApplyStyle()
cfg.locked = true; P.rotationHUD.ApplyStyle(); assert(cfg.preview == nil)
D.Hide(); assert(not D.IsShown())
print('PASS: ein Fenster mit drei Seiten, Knöpfe, Talent-Entwurf und Kampfanzeige ohne Lua-Fehler (' .. clicked .. ' Klicks).')
''')

