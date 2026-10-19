"""ZIELE.md checks that do not need the full window: level bands, minimum level, item scores."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wowmock_ui import load_addon

lua = load_addon()
lua.execute(r'''
local P = FUSLive
-- Ziel 4: benchmark enemy by level band.
local want = {[10] = 'quest', [30] = 'quest', [31] = 'dungeon', [49] = 'dungeon', [50] = 'standard', [60] = 'standard'}
for lvl, mode in pairs(want) do
    local r = P.encounters.Resolve(lvl, {})
    assert(r.mode == mode, 'Level ' .. lvl .. ': ' .. tostring(r.mode) .. ' statt ' .. mode)
end
-- Grundsatz 5: minimum level 10, independent of any talent bonus.
assert(P.minSimLevel() == 10)
print('PASS: Gegnerband 1-30 Quest, 31-49 Dungeonboss, 50-60 Raidboss; Mindestlevel 10.')
''')

# ---------------------------------------------------------------------------------------------
# Ziel 1: item scores at the item. Stub the simulator, drive the real ItemScore/LiveUI code.
lua.execute(r'''
local P = FUSLive
local nowLevel = level
local compareCalls = 0
local pct = {['item:1'] = 4.8, ['item:2'] = 0.9, ['item:3'] = -0.6}
local slots = {['item:1'] = 'mainhand', ['item:2'] = 'shoulder', ['item:3'] = 'waist', ['item:4'] = 'trinket1'}
P.revision = 1
P.stale = true
P.readItem = function(link) return {id = tonumber(link:match('%d+')), name = 'Item' .. link, slot = slots[link], link = link, hasUnmodeledEffects = link == 'item:4'} end
P.capture = function() return {level = level, spells = {}} end
P.normalizeSnapshot = function(s) return {class = 'hunter', level = s.level, equipped = {mainhand = {name = 'Alter Bogen'}}, spells = {}} end
FUSLiveData = FUSLiveData or {}
FUSLiveData.hunter = {}
P.coverage = function() end
P.combine = function() return {} end
P.best = function() return {choice = {policies = {}}} end
P.checkEligibility = function(_, _, item) if item.hasUnmodeledEffects then return 'Nicht modellierter Itemeffekt' end end
P.compare = function(_, _, _, item)
    compareCalls = compareCalls + 1
    return {item = item, eligible = true, percent = pct[item.link], delta = pct[item.link], status = pct[item.link] > 0 and 'upgrade' or 'downgrade', newDps = 100, newChoice = {policies = {}}, rotationRules = {}}
end
P.encounters = {Resolve = function() return {mode = 'standard'} end}
InCombatLockdown = function() return false end
ForeverSimBridgeDB = ForeverSimBridgeDB or {}
local IS = P.itemScore
assert(IS, 'ItemScore fehlt')
-- Run queued jobs the way LiveUI does: the scheduler frame has an OnUpdate script.
local scheduler
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f ~= nil then scheduler = scheduler or f end end
local function drain()
    for _, f in ipairs(frames) do
        if f.scripts.OnUpdate then for i = 1, 20 do f.scripts.OnUpdate(f, 1) end end
    end
end
-- 1. Item score is computed once, cached, and uses the full compare path.
local e = IS.Get('item:1'); assert(e.state == 'busy')
drain()
assert(IS.Peek('item:1').state == 'ok' and IS.Peek('item:1').pct == 4.8 and IS.Peek('item:1').replaces == 'Alter Bogen')
assert(compareCalls == 1)
IS.Get('item:1'); drain(); assert(compareCalls == 1, 'Cache nicht genutzt')
local label = IS.Label(IS.Peek('item:1')); assert(label == '+4,8 %', label)
-- 2. Unmodeled effects show "?" and never a number.
IS.Get('item:4'); drain()
assert(IS.Peek('item:4').state == 'unmodeled' and IS.Label(IS.Peek('item:4')) == '?')
-- 3. Negative values keep their sign.
IS.Get('item:3'); drain(); assert(IS.Label(IS.Peek('item:3')) == '-0,6 %')
-- 4. New revision (gear/talent change) invalidates the cache.
P.revision = 2; assert(IS.Peek('item:1') == nil)
-- 5. Nothing is computed in combat or below level 10.
InCombatLockdown = function() return true end
assert(IS.Get('item:2') == nil)
InCombatLockdown = function() return false end
level = 9; assert(IS.Get('item:2') == nil); level = 60
-- 6. Switch off.
ForeverSimBridgeDB.itemScores = false; assert(IS.Get('item:2') == nil); ForeverSimBridgeDB.itemScores = nil
-- 7. Best choice among several quest rewards.
IS.Get('item:1'); IS.Get('item:2'); drain()
assert(IS.Best({IS.Peek('item:1'), IS.Peek('item:2')}) == 1)
-- 8. Quest window: marks on Blizzard's reward buttons, gold frame on the best, nothing attached to Blizzard frames.
QuestFrame = CreateFrame(); QuestFrame.shown = true
QuestInfoItem1 = CreateFrame(); QuestInfoItem2 = CreateFrame(); QuestInfoItem3 = CreateFrame()
for _, b in ipairs({QuestInfoItem1, QuestInfoItem2, QuestInfoItem3}) do b.Icon = CreateFrame() end
GetNumQuestChoices = function() return 3 end
GetQuestItemLink = function(_, i) return 'item:' .. i end
IS.RefreshQuest(); drain(); IS.RefreshQuest()
local texts, borders = {}, 0
for _, f in ipairs(frames) do
    if f.group == 'quest' and f.shown ~= false then
        if f.kind == 'border' then borders = borders + 1 else texts[#texts + 1] = f.text.text end
    end
end
table.sort(texts)
assert(#texts == 3 and texts[1] == '+0,9 %' and texts[2] == '+4,8 %' and texts[3] == '-0,6 %', table.concat(texts, ','))
assert(borders == 1, 'Goldrahmen um die beste Belohnung: ' .. borders)
for _, b in ipairs({QuestInfoItem1, QuestInfoItem2, QuestInfoItem3}) do
    assert(next(b.scripts) == nil and b.fsLabel == nil and b.fusLabel == nil, 'Feld/Script am Blizzard-Knopf')
end
IS.ClearMarks('quest')
-- 9. Public API for ForeverQuests.
local api = ForeverSimAPI.ItemScore('item:1'); assert(api.label == '+4,8 %' and api.percent == 4.8)
print('PASS: Item-Bewertung: Cache, Voll-Simulation, ?, Vorzeichen, Revision, Kampf/Level/Schalter, Questbelohnung mit Goldrahmen, API.')
''')

lua.execute(r'''
local P, IS = FUSLive, FUSLive.itemScore
local function drain() for _, f in ipairs(frames) do if f.scripts.OnUpdate then for i = 1, 20 do f.scripts.OnUpdate(f, 1) end end end end
P.revision = 10
-- 10. Tooltip: lines at the item tooltip (post call), "?" for unmodeled effects, no calculation in combat.
local postCall
TooltipDataProcessor = {AddTooltipPostCall = function(_, fn) postCall = fn end}
Enum = {TooltipDataType = {Item = 1}}
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then pcall(f.scripts.OnEvent, f, 'PLAYER_LOGIN') end end
assert(postCall, 'Tooltip-Hook nicht installiert')
local function tip() local t = CreateFrame(); t.lines = {}; t.AddLine = function(self, l) self.lines[#self.lines + 1] = l end; return t end
GameTooltip = tip()
postCall(GameTooltip, {hyperlink = 'item:1'}); drain()
GameTooltip = tip(); postCall(GameTooltip, {hyperlink = 'item:1'})
local all = table.concat(GameTooltip.lines, '|')
assert(all:find('ForeverSim', 1, true) and all:find('+4,8 % DPS', 1, true) and all:find('ersetzt: Alter Bogen', 1, true) and all:find('Gegner: Raidboss', 1, true), all)
GameTooltip = tip(); postCall(GameTooltip, {hyperlink = 'item:4'}); drain(); GameTooltip = tip(); postCall(GameTooltip, {hyperlink = 'item:4'})
assert(table.concat(GameTooltip.lines, '|'):find('? Effekt nicht modelliert', 1, true))
-- 11. Bags: plate bottom left on bag items, gold frame on the best one, bank included.
local links = {[1] = 'item:1', [2] = 'item:2', [3] = 'item:3'}
C_Container = {GetContainerItemLink = function(bag, slot) return links[slot] end, GetContainerNumSlots = function() return 3 end}
IsEquippableItem = function() return true end
ContainerFrame1 = CreateFrame(); ContainerFrame1.size = 3; ContainerFrame1.GetID = function() return 0 end; ContainerFrame1.EnumerateValidItems = false
for j = 1, 3 do local b = CreateFrame(); b.GetID = function() return j end; _G['ContainerFrame1Item' .. j] = b end
for i = 1, 3 do IS.Get('item:' .. i) end drain()
IS.RefreshBags()
local plates, borders = {}, 0
for _, f in ipairs(frames) do if f.group == 'bags' and f.shown ~= false then if f.kind == 'plate' then plates[#plates + 1] = f.text.text elseif f.kind == 'border' then borders = borders + 1 end end end
table.sort(plates); assert(#plates == 3 and plates[1] == '+0,9' and plates[2] == '+4,8' and plates[3] == '-0,6', table.concat(plates, ','))
assert(borders == 1)
-- 12. Roll: the score sits under GroupLootFrame<n>, gold frame on the need button for an upgrade.
GroupLootFrame1 = CreateFrame(); GroupLootFrame1.rollID = 7; GroupLootFrame1.NeedButton = CreateFrame()
GroupLootFrame1.GetWidth = function() return 300 end
GetLootRollItemLink = function() return 'item:1' end
GetLootRollTimeLeft = function() return 10000 end
local liveEvents
for _, f in ipairs(frames) do if f.events.START_LOOT_ROLL then liveEvents = f end end
liveEvents.scripts.OnEvent(liveEvents, 'START_LOOT_ROLL', 7)
if C_Timer then C_Timer.After = nil end
drain()
local found = false
for _, l in ipairs(frames) do
    if l.kind == 'FontString' and l.text and tostring(l.text):find('ForeverSim: ', 1, true) and tostring(l.text):find('4,8 % DPS', 1, true) then
        found = true
        local pt = l.parent.points[#l.parent.points]
        assert(pt[1] == 'TOPLEFT' and pt[2] == GroupLootFrame1 and pt[3] == 'BOTTOMLEFT', 'Würfelanzeige nicht unter dem Blizzard-Fenster')
    end
end
assert(found, 'Würfelzeile fehlt')
local roll_borders = 0
for _, f in ipairs(frames) do if tostring(f.group):find('^roll') and f.kind == 'border' and f.shown ~= false then roll_borders = roll_borders + 1 end end
assert(roll_borders == 1, 'Goldrahmen am Bedarf-Knopf')
-- Roll cancelled: the gold frame goes away with it (Blizzard reuses GroupLootFrame1 for the next roll).
liveEvents.scripts.OnEvent(liveEvents, 'CANCEL_LOOT_ROLL', 7)
IS.ClearMarks('roll7')
-- Wearability vs. missing model data: only real rules say "nicht anlegbar", the rest is "?".
P.checkEligibility = function(_, _, item) if item.link == 'item:2' then return 'Benötigt Level 70' elseif item.link == 'item:3' then return 'Unbekannter Itemwert: Dornen' end end
P.revision = 11
IS.Get('item:2'); IS.Get('item:3'); drain()
assert(IS.Label(IS.Peek('item:2')) == 'nicht anlegbar', tostring(IS.Label(IS.Peek('item:2'))))
assert(IS.Label(IS.Peek('item:3')) == '?', tostring(IS.Label(IS.Peek('item:3'))))
-- The bank belongs to one character.
ForeverSimBridgeDB.bank = {['Anna-Realm'] = {'item:1'}}
UnitName = function() return 'Berta' end; GetRealmName = function() return 'Realm' end
assert(#IS.BankLinks() == 0, 'Bank eines anderen Charakters')
print('PASS: Tooltip-Block, Taschen-Schilder mit Goldrahmen, Würfelanzeige unter dem Blizzard-Fenster, nicht anlegbar gegen ?, Bank je Charakter.')
''')

# ---------------------------------------------------------------------------------------------
# Ziel 2: tree against tree below level 50 (level paths), draft against live from 50.
lua2 = load_addon()
lua2.execute(r'''
local P, D = FUSLive, FUSLive.dashboard
level = 30
P.app.Open('talents'); D.Refresh()
local paths = D.LevelPaths()
assert(paths and #paths.trees == 3, 'Levelwege fehlen')
local data = FUSLiveData.hunter
for t = 1, 3 do
    local ok, detail = P.talentBuild.validate(data, paths.trees[t].ranks, 30)
    assert(ok, 'Levelweg ' .. t .. ' ungültig: ' .. tostring(detail))
    assert(paths.trees[t].points == 21, 'Level 30 hat 21 Punkte, Baum ' .. t .. ': ' .. paths.trees[t].points)
end
-- The window opens in tree-against-tree mode at level 30 and in draft mode at 60.
assert(D.widgets.compare.label.text == 'Bäume vergleichen', tostring(D.widgets.compare.label.text))
assert(D.widgets.sideTitle.text == 'Baum gegen Baum')
level = 60; D.Refresh()
assert(D.widgets.compare.label.text == 'Mit meinen Talenten vergleichen')
print('PASS: Levelwege je Baum gültig (21 Punkte auf Level 30), Modus folgt dem Level.')
''')

lua2.execute(r'''
local P, D = FUSLive, FUSLive.dashboard
level = 30
local live = {class = 'hunter', level = 30, talents = {}, stats = {}, hasSpellbook = true, knownSpellRanks = {}, equipped = {}}
P.actions.Context = function() return {profile = live, model = FUSLiveData.hunter, stats = {}} end
P.candidates = function() return {{policies = {{key = 'autoShot'}}}} end
P.leveling.Context = function() return {targetHealth = 1000} end
local calls = 0
P.best = function() return {choice = {policies = {{key = 'autoShot'}}}} end
P.leveling.Evaluate = function(_, profile) calls = calls + 1; return {available = true, killSeconds = 10 + (profile.talents[1].points > 0 and 0 or 1) + calls * .01, failures = 0} end
P.revision = 77
D.Refresh(); D.CompareTrees()
for _, f in ipairs(frames) do if f.scripts.OnUpdate then for i = 1, 60 do f.scripts.OnUpdate(f, 1) end end end
local c = D.state.treeCompare
assert(c and c.byKill and #c.rows == 3 and c.best, 'Baumvergleich ohne Ergebnis: ' .. tostring(D.state.talentMessage))
for t = 1, 3 do assert(c.rows[t].kill, 'Baum ' .. t .. ' ohne Kill-Zeit') end
D.Refresh()
assert(D.widgets.trees[c.best].sub.text:find('pro Kill'), 'Kill-Zeit fehlt am Baumkopf')
print('PASS: Baum-gegen-Baum rechnet drei Levelwege und zeigt Kill-Zeit am Baumkopf.')
''')

# Ziel 3: fixed per-spec weights are looked up, scored and never invented.
lua3 = load_addon()
lua3.execute(r'''
local W = FUSLive.statWeights60
assert(W, 'StatWeights60 fehlt')
ForeverSimBridgeDB = ForeverSimBridgeDB or {}
assert(W.Get('hunter', 'Treffsicherheit') == nil, 'ohne Messung dürfen keine Gewichte existieren')
assert(W.Score('hunter', 'Treffsicherheit', {agi = 10}) == nil)
assert(W.Store('hunter', 'Treffsicherheit', 60, 1200, {{key = 'agi', perPoint = 1.5}, {key = 'ap', perPoint = .5}}))
local w, kind = W.Get('hunter', 'Treffsicherheit'); assert(w.agi == 1.5 and kind == 'gemessen')
assert(W.Score('hunter', 'Treffsicherheit', {agi = 10, ap = 20}) == 25)
assert(W.SpecOf({talents = {{name = 'A', points = 3}, {name = 'B', points = 30}, {name = 'C', points = 0}}}) == 'B')
assert(W.SpecOf({talents = {{name = 'A', points = 0}}}) == nil)
print('PASS: Gewichte je Skillung: keine erfundenen Werte, Messung speichern, Gewichtung berechnen.')
''')

# Ziel 5: combat display states. Cooldown sweep, red without mana, key highlighted on the action bar.
lua4 = load_addon()
lua4.execute(r'''
local P, H = FUSLive, FUSLive.rotationHUD
local cd = {}
-- mock client: spell 19434 sits on action slot 3; cooldown 8 s of a 10 s spell; not enough mana
C_Spell = {GetSpellCooldown = function() return {startTime = 92, duration = 10, isEnabled = true} end}
IsUsableSpell = function() return false, true end
ActionButton3 = CreateFrame(); ActionButton3.action = 3
P.passiveSafetyMode = function() return false end
H.RebuildKeys()
local a = {id = 19434, name = 'Aimed Shot', icon = 'Interface\\Icons\\INV_Spear_07'}
H.inCombat = true
local sweep
local cells = {}
for _, f in ipairs(frames) do if f.cooldown then cells[#cells + 1] = f end end
assert(#cells >= 1, 'keine Zellen')
H.paint(1, a, nil)
local first
for _, f in ipairs(cells) do if f.icon and f.icon.vertex then first = first or f end end
assert(first and first.icon.vertex[1] == 1 and first.icon.vertex[2] < .5, 'ohne Mana nicht rot')
assert(first.icon.desaturated == true, 'Abklingzeit nicht abgedunkelt')
assert(first.cdText.text and first.cdText.text ~= '', 'Restzeit fehlt')
local highlighted = 0
for _, f in ipairs(frames) do if f.anchor == ActionButton3 and f.shown then highlighted = highlighted + 1 end end
assert(highlighted == 1, 'Aktionsleisten-Markierung: ' .. highlighted)
-- Leaving combat removes the highlight again.
H.inCombat = false; H.paint(1, a, nil)
local still = 0
for _, f in ipairs(frames) do if f.anchor == ActionButton3 and f.shown then still = still + 1 end end
assert(still == 0, 'Markierung bleibt nach dem Kampf')
print('PASS: Kampffeld: Abklingzeit, kein Mana rot, Aktionsleisten-Markierung nur im Kampf.')
''')
