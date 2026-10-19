-- ForeverSim item scores (ZIELE.md, Ziel 1): "Ist dieses Item wirklich besser?" as a DPS percentage,
-- wherever an item shows up: tooltip, quest reward, loot roll, bags, bank and the FDQ dungeon journal.
--
-- One cache, one calculation path: every number is a full P.compare simulation against the worn slot
-- (never a sum of stat points). Effects the engine does not model show "?" instead of a guess.
--
-- Taint rules (see LiveUI.lua, TAINT-FIX-1.12.4.md): nothing is attached to Blizzard frames. All marks
-- are our own frames on UIParent that merely anchor to the Blizzard frame. Nothing is computed or
-- shown while in combat. The switch ForeverSimBridgeDB.itemScores (default on) turns all of it off.
local P = FUSLive
local M = {}
P.itemScore = M

local MEDIA = 'Interface\\AddOns\\ForeverSimBridge\\Media\\'
local ENEMY = {quest = 'Questgegner', elite = 'Elitegegner', dungeon = 'Dungeonboss', standard = 'Raidboss'}
local cache, cacheRevision = {}, nil
local context, base
local listeners = {}
local marks = {}

local function inCombat() return InCombatLockdown and InCombatLockdown() == true end
function M.Enabled() return not (ForeverSimBridgeDB and ForeverSimBridgeDB.itemScores == false) end
local function playerLevel()
    local level = UnitLevel and UnitLevel('player')
    if P.publicNumber then level = P.publicNumber(level) end
    return type(level) == 'number' and level or nil
end
local function belowMinimum()
    local level = playerLevel()
    return not level or level < P.minSimLevel()
end
local function sync()
    if cacheRevision ~= P.revision then cache, context, base, cacheRevision = {}, nil, nil, P.revision end
end
local function comma(v, digits) return (string.format('%.' .. (digits or 1) .. 'f', v):gsub('%.', ',', 1)) end

-- Character context: captured once per revision.
local function ctx()
    sync()
    if context then return context end
    local snap = P.capture and P.capture(true)
    if not snap then error('Charakterdaten fehlen', 0) end
    local profile = P.normalizeSnapshot(snap); profile.spells = snap.spells
    local data = FUSLiveData and FUSLiveData[profile.class]
    if not data then error('Klassenmodul fehlt', 0) end
    local issue = P.coverage(data, profile)
    if issue then error(issue, 0) end
    context = {data = data, profile = profile}
    return context
end
M.Context = ctx

local function enemyName()
    local level = playerLevel()
    local request = ForeverSimBridgeDB and ForeverSimBridgeDB.encounter or {}
    local e = level and P.encounters and P.encounters.Resolve(level, request)
    return e and ENEMY[e.mode] or nil
end

-- Result record shown by every surface.
-- state: busy | ok | unmodeled | blocked | none
local function describe(result, profile)
    if not result then return {state = 'unmodeled', reason = 'SIM derzeit nicht verfügbar'} end
    if not result.eligible then
        -- Only real wearability rules count as "nicht anlegbar". Missing data or model gaps are "?".
        local reason = tostring(result.reason or 'Nicht bewertbar')
        local wearable = reason:find('Benötigt', 1, true) or reason:find('nicht tragbar', 1, true) or reason:find('Falsche Fraktion', 1, true)
            or reason:find('Zweihand', 1, true) or reason:find('Einzigartig', 1, true)
        return {state = wearable and 'blocked' or 'unmodeled', reason = reason}
    end
    local slot = result.item and result.item.slot
    local worn = slot and profile and profile.equipped and profile.equipped[slot]
    return {state = 'ok', pct = result.percent, delta = result.delta, status = result.status, replaces = worn and worn.name or nil,
            slot = slot, preview=result.preview,result = result}
end

local function notify(link, entry)
    for _, fn in ipairs(listeners) do pcall(fn, link, entry) end
end
function M.OnChange(fn) listeners[#listeners + 1] = fn end
-- A new revision (gear, talents, level) or leaving combat: surfaces re-read and recompute.
function M.Changed() sync(); notify(nil, nil) end

-- Cached entry without starting a calculation.
function M.Peek(link) sync(); return link and cache[link] or nil end

-- Cached entry; starts the simulation when missing. Returns nil while the SIM is not allowed to run
-- (disabled, combat, level below minimum, item not equippable).
function M.Get(link)
    if not link or not M.Enabled() then return nil end
    sync()
    local entry = cache[link]
    if entry then return entry end
    if inCombat() or belowMinimum() or not P.readItem then return nil end
    local item = P.readItem(link, 'ForeverSim')
    if not item then return nil end                       -- item data not cached yet: retry on the next pass
    if not item.slot then entry = {state = 'none'}; cache[link] = entry; return entry end
    local ok, c = pcall(ctx)
    if not ok then return {state = 'unmodeled', reason = 'SIM derzeit nicht verfügbar', transient = true} end
    entry = {state = 'busy'}; cache[link] = entry
    local revision = P.revision
    P.enqueue(function()
        local stats = P.combine(c.profile.equipped)
        if not base or base.revision ~= revision then
            local chosen = (not P.stale and P.lastRotation and P.lastRotation.choice) or nil
            base = {revision = revision, value = P.best(c.data, c.profile, stats, chosen)}
        end
        local issue = P.checkEligibility(c.data, c.profile, item, c.profile.equipped)
        if issue then return {item = item, eligible = false, reason = issue} end
        return P.compare(c.data, c.profile, c.profile.equipped, item, base.value)
    end, function(result, err)
        if revision ~= P.revision or cache[link] ~= entry then return end
        local done = err and {state = 'unmodeled', reason = 'SIM derzeit nicht verfügbar'} or describe(result, c.profile)
        for k in pairs(entry) do entry[k] = nil end
        for k, v in pairs(done) do entry[k] = v end
        entry.enemy = enemyName()
        notify(link, entry)
    end, function() return revision == P.revision and not inCombat() end)
    return entry
end

-- Text pieces ------------------------------------------------------------------
local GREEN, RED, ORANGE, GREY = {.12, 1, .12}, {1, .32, .28}, {1, .62, .25}, {.7, .7, .7}
-- Short label for plates and reward lines: "+4,8 %", "-0,6 %", "?", "kein Nutzen", "nicht anlegbar", "…".
function M.Label(entry, withPercent)
    if not entry then return nil end
    local unit = withPercent == false and '' or ' %'
    if entry.state == 'busy' then return '…', GREY end
    if entry.state == 'unmodeled' then return '?', ORANGE end
    if entry.state == 'blocked' then return 'nicht anlegbar', GREY end
    if entry.state ~= 'ok' or type(entry.pct) ~= 'number' then return nil end
    if entry.pct==0 then return 'kein Nutzen', GREY end
    if math.abs(entry.pct)<.01 then return(entry.pct>0 and '+'or '-')..'<0,01'..unit,entry.pct>0 and GREEN or RED end
    return (entry.pct > 0 and '+' or '-') .. comma(math.abs(entry.pct),math.abs(entry.pct)<.1 and 2 or 1) .. unit, entry.pct > 0 and GREEN or RED
end
-- Best positive entry among several (quest rewards, bag scan): index or nil.
function M.Best(entries)
    local best, index = 0, nil
    for i, e in pairs(entries) do
        if e and e.state == 'ok' and e.status == 'upgrade' and type(e.pct) == 'number' and e.pct > best then best, index = e.pct, i end
    end
    return index
end

-- Tooltip ----------------------------------------------------------------------
-- One line with an arrow and the gain; warnings, the replaced item and the enemy only with Shift (or when the
-- player wants them always: ForeverCoreBridgeDB.tooltipDetails). With ForeverCore the arrows come from its media.
local CORE_MEDIA = 'Interface\\AddOns\\ForeverCoreBridge\\Media\\'
local function core() return _G.ForeverCoreClient ~= nil end
local function details()
    if IsShiftKeyDown and IsShiftKeyDown() then return true end
    return ForeverCoreBridgeDB ~= nil and ForeverCoreBridgeDB.tooltipDetails == true
end
local function arrowTag(up)
    if not core() then return '' end
    return '|T' .. CORE_MEDIA .. (up and 'FCArrowUp' or 'FCArrowDown') .. ':14:14:0:0|t '
end
local function addTooltip(tt, link)
    if not tt or not link or inCombat() or not M.Enabled() then return end
    if tt.fsAdded == link and tt.fsAddedSeq == (tt.fsSeq or 0) then return end
    local entry = M.Get(link)
    if not entry or entry.state == 'none' then return end
    local name = core() and 'ForeverCore' or 'ForeverSim'
    local more, hidden = details(), false
    if entry.state == 'busy' then tt:AddLine(name .. ': wird berechnet …', .7, .7, .7)
    elseif entry.state == 'unmodeled' then
        tt:AddLine(name .. ': nicht berechenbar (Spezialeffekt)', 1, .62, .25)
        if more then tt:AddLine(tostring(entry.reason or ''), .7, .7, .7, true) else hidden = entry.reason ~= nil end
    elseif entry.state == 'blocked' then tt:AddLine(name .. ': ' .. tostring(entry.reason or 'nicht anlegbar'), .7, .7, .7, true)
    else
        local text, color = M.Label(entry)
        if not text or text == 'kein Nutzen' then
            tt:AddLine(name .. ': kein Schadensgewinn', .7, .7, .7)
        else
            local up = type(entry.pct) == 'number' and entry.pct > 0
            local delta = type(entry.delta) == 'number' and (string.format('%+.1f DPS', entry.delta):gsub('%.', ',', 1)) or ''
            tt:AddDoubleLine(arrowTag(up) .. text .. ' DPS', delta, color[1], color[2], color[3], .7, .7, .7)
        end
        local extra = {}
        for _, warning in ipairs(entry.result and entry.result.warnings or {}) do extra[#extra + 1] = {warning, 1, .62, .25} end
        if entry.preview then extra[#extra + 1] = {'Dungeon-Vorschau: Stufe nicht beruecksichtigt', .7, .7, .7} end
        if entry.status == 'uncertain' then extra[#extra + 1] = {'Differenz innerhalb der Simulationsstreuung', 1, .62, .25} end
        if entry.replaces then extra[#extra + 1] = {'ersetzt: ' .. entry.replaces, .9, .9, .9} end
        local enemy = entry.enemy or enemyName()
        if enemy then extra[#extra + 1] = {'Gegner: ' .. enemy, .9, .9, .9} end
        if more then for _, e in ipairs(extra) do tt:AddLine(e[1], e[2], e[3], e[4], true) end
        else hidden = #extra > 0 end
    end
    -- Drop chance from the dungeon catalog (Dungeon Journal + Forever Guide), if the item drops in a known dungeon.
    local api = _G.ForeverSimDungeonAPI
    local itemId = tonumber(tostring(link):match('item:(%d+)'))
    local chance = api and api.ChanceText and itemId and api.ChanceText(itemId)
    if chance then tt:AddLine(chance, .7, .85, 1, true) end
    if hidden then tt:AddLine('Shift: Details', .5, .5, .5) end
end
local function installTooltip()
    local added = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        added = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
            local link = data and data.hyperlink
            if not link and tt.GetItem then local _; _, link = tt:GetItem() end
            addTooltip(tt, link)
        end)
    end
    if not added and GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, 'OnTooltipSetItem', function(tt)
            local _, link = tt:GetItem()
            addTooltip(tt, link)
        end)
    end
end

-- Marks: our own frames that sit on a Blizzard frame --------------------------------
local pool = {}
local function newMark()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame('Frame', nil, UIParent)
    f:SetFrameStrata('FULLSCREEN')
    f.bg = f:CreateTexture(nil, 'BACKGROUND'); f.bg:SetAllPoints(); f.bg:SetColorTexture(0, 0, 0, .82)
    f.border = f:CreateTexture(nil, 'ARTWORK'); f.border:SetAllPoints()
    f.text = f:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    f.text:SetPoint('CENTER', 0, 0)
    return f
end
local function release(f) f:Hide(); f.anchor = nil; pool[#pool + 1] = f end
function M.ClearMarks(group)
    local kept = {}
    for _, m in ipairs(marks) do
        if m.group == group or (group == 'roll' and tostring(m.group):find('^roll')) then release(m) else kept[#kept + 1] = m end
    end
    marks = kept
end
-- Percent plate (bags, bank): small, bottom left of the icon, so the stack count stays readable.
function M.Plate(group, anchor, entry)
    local text, color = M.Label(entry, false)
    if not text or not anchor then return end
    if core() then
        if ForeverCoreBridgeDB and ForeverCoreBridgeDB.arrows == false then return end
        if not (entry and entry.state == 'ok' and type(entry.pct) == 'number' and entry.pct > 0.005) then return end
        local f = newMark(); f.group = group; f.anchor = anchor; f.kind = 'arrow'
        f:SetSize(14, 14)
        f.bg:SetColorTexture(0, 0, 0, 0); f.border:SetTexture(CORE_MEDIA .. 'FCArrowUp'); f.border:SetAllPoints()
        f.text:SetText('')
        f:ClearAllPoints(); f:SetPoint('TOPLEFT', anchor, 'TOPLEFT', 1, -1)
        f:Show(); marks[#marks + 1] = f
        return f
    end
    if text == 'kein Nutzen' or text == 'nicht anlegbar' or text == '…' then return end
    local f = newMark(); f.group = group; f.anchor = anchor; f.kind = 'plate'
    f:SetSize(1, 14)
    f.bg:SetColorTexture(0, 0, 0, .82); f.border:SetColorTexture(0, 0, 0, 0)
    f.text:SetText(text); f.text:SetTextColor(color[1], color[2], color[3], 1)
    f:SetWidth(math.max(22, (f.text:GetStringWidth() or 24) + 6))
    f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 1, 1)
    f:Show(); marks[#marks + 1] = f
    return f
end
-- Result line beside an icon (quest reward): "+4,8 %" without a plate background.
function M.Line(group, anchor, entry, dx, dy)
    local text, color = M.Label(entry)
    if not text or not anchor then return end
    if entry.state=='ok' and type(entry.delta)=='number' then
        text=string.format('%+.1f DPS (%s)',entry.delta,text)
    end
    local f = newMark(); f.group = group; f.anchor = anchor; f.kind = 'line'
    f:SetSize(190, 14)
    f.bg:SetColorTexture(0, 0, 0, 0); f.border:SetColorTexture(0, 0, 0, 0)
    f.text:SetText(text); f.text:SetTextColor(color[1], color[2], color[3], 1)
    f.text:ClearAllPoints(); f.text:SetPoint('LEFT', 0, 0)
    f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', dx or 44, dy or 3)
    f:Show(); marks[#marks + 1] = f
    return f
end
-- Gold frame around the best choice.
function M.GoldBorder(group, anchor, pad)
    if not anchor then return end
    local f = newMark(); f.group = group; f.anchor = anchor; f.kind = 'border'
    f.bg:SetColorTexture(0, 0, 0, 0); f.border:SetTexture(MEDIA .. 'FQGoldBorder'); f.border:SetAllPoints()
    f.text:SetText('')
    f:ClearAllPoints(); pad = pad or 5
    f:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -pad, pad); f:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', pad, -pad)
    f:Show(); marks[#marks + 1] = f
    return f
end
-- Marks follow their Blizzard frame: hidden bag or reward window, hidden mark.
local ticker, elapsed = CreateFrame('Frame'), 0
ticker:SetScript('OnUpdate', function(_, dt)
    elapsed = elapsed + dt
    if elapsed < .25 then return end
    elapsed = 0
    for _, m in ipairs(marks) do
        local a = m.anchor
        local visible = a ~= nil and (not a.IsVisible or a:IsVisible())
        if m:IsShown() ~= visible then m:SetShown(visible) end
    end
end)

-- Bags and bank -----------------------------------------------------------------
local function containerLink(bag, slot)
    local api = C_Container and C_Container.GetContainerItemLink
    if api then local ok, link = pcall(api, bag, slot); if ok then return link end end
    if GetContainerItemLink then local ok, link = pcall(GetContainerItemLink, bag, slot); if ok then return link end end
end
local function equippable(link)
    if IsEquippableItem then local ok, yes = pcall(IsEquippableItem, link); return ok and yes end
    return true
end
local function eachBagButton(fn)
    for i = 1, 13 do
        local cf = _G['ContainerFrame' .. i]
        if cf and cf.IsShown and cf:IsShown() then
            local bag = cf.GetID and cf:GetID()
            if cf.EnumerateValidItems then
                local ok = pcall(function() for _, b in cf:EnumerateValidItems() do fn(b, b.GetBagID and b:GetBagID() or bag, b:GetID()) end end)
            else
                local size = cf.size or (bag and C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
                for j = 1, size do
                    local b = _G['ContainerFrame' .. i .. 'Item' .. j]
                    if b and (not b.IsShown or b:IsShown()) then fn(b, bag, b:GetID()) end
                end
            end
        end
    end
    if BankFrame and BankFrame.IsShown and BankFrame:IsShown() then
        for j = 1, 28 do
            local b = _G['BankFrameItem' .. j]
            if b and (not b.IsShown or b:IsShown()) then fn(b, -1, b:GetID()) end
        end
    end
end
-- Scan items found in the last bag pass (also used by the overview suggestions).
M.bagItems = {}
local function refreshBags()
    M.ClearMarks('bags')
    if inCombat() or not M.Enabled() or belowMinimum() then return end
    local found, entries = {}, {}
    eachBagButton(function(button, bag, slot)
        local link = bag and slot and containerLink(bag, slot)
        if link and equippable(link) then
            local entry = M.Get(link)
            found[#found + 1] = {link = link, bag = bag, slot = slot}
            if entry then entries[link] = entry; M.Plate('bags', button, entry) end
        end
    end)
    local best = M.Best(entries)
    if best then
        eachBagButton(function(button, bag, slot)
            if bag and slot and containerLink(bag, slot) == best then M.GoldBorder('bags', button, 3) end
        end)
    end
    M.bagItems = found
end
M.RefreshBags = refreshBags

-- Bank contents are only readable while the bank is open (Classic); remember the equippable links per character.
local function charKey()
    local name = UnitName and UnitName('player') or '?'
    local realm = GetRealmName and GetRealmName() or ''
    return tostring(name) .. '-' .. tostring(realm)
end
local function scanBank()
    if inCombat() or not (BankFrame and BankFrame.IsShown and BankFrame:IsShown()) then return end
    local links, seen = {}, {}
    local bags = {-1, 5, 6, 7, 8, 9, 10, 11}
    for _, bag in ipairs(bags) do
        local n = 0
        if C_Container and C_Container.GetContainerNumSlots then local ok, v = pcall(C_Container.GetContainerNumSlots, bag); n = ok and tonumber(v) or 0
        elseif GetContainerNumSlots then local ok, v = pcall(GetContainerNumSlots, bag); n = ok and tonumber(v) or 0 end
        for slot = 1, n do
            local link = containerLink(bag, slot)
            if link and not seen[link] and equippable(link) then seen[link] = true; links[#links + 1] = link end
        end
    end
    -- The bank belongs to one character; the saved variables are account wide.
    if ForeverSimBridgeDB then
        ForeverSimBridgeDB.bank = ForeverSimBridgeDB.bank or {}
        ForeverSimBridgeDB.bank[charKey()] = links
    end
end
function M.BankLinks()
    local bank = ForeverSimBridgeDB and ForeverSimBridgeDB.bank
    return bank and bank[charKey()] or {}
end
M.ScanBank = scanBank

-- Quest rewards -------------------------------------------------------------------
local function rewardButton(i)
    local b = _G['QuestInfoItem' .. i]
    if b then return b end
    local frame = QuestInfoRewardsFrame
    return frame and frame.RewardButtons and frame.RewardButtons[i]
end
local questToken = 0
local function refreshQuest()
    M.ClearMarks('quest')
    if inCombat() or not M.Enabled() or belowMinimum() then return end
    if QuestFrame and QuestFrame.IsShown and not QuestFrame:IsShown() then return end
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    local count = choices > 0 and choices or (GetNumQuestRewards and GetNumQuestRewards() or 0)
    if count == 0 then return end
    local entries = {}
    for i = 1, count do
        local link = GetQuestItemLink and GetQuestItemLink(choices > 0 and 'choice' or 'reward', i)
        local entry = link and M.Get(link)
        if entry then entries[i] = entry end
    end
    local best = M.Best(entries)
    for i, entry in pairs(entries) do
        local button = rewardButton(i)
        if button then
            M.Line('quest', button, entry, 44, 3)
            if i == best then M.GoldBorder('quest', button.Icon or button, 5) end
        end
    end
end
M.RefreshQuest = refreshQuest

-- Loot roll: a mark under the roll frame (GroupLootFrameN) and a gold frame on the need button.
local function rollFrame(rollID)
    for i = 1, 4 do
        local f = _G['GroupLootFrame' .. i]
        if f and f.rollID == rollID then return f, i end
    end
end
M.RollFrame = rollFrame
function M.RollNeedButton(f, i)
    return f and (f.NeedButton or _G['GroupLootFrame' .. i .. 'NeedButton'])
end

-- Public API for other addons (ForeverQuests dungeon journal): ForeverSimAPI.ItemScore(link) -> entry.
-- Pending entries complete later; poll again or register through ForeverSimAPI.OnItemScore.
_G.ForeverSimAPI = _G.ForeverSimAPI or {}
_G.ForeverSimAPI.schema = 1
function _G.ForeverSimAPI.ItemScore(link)
    local e = M.Get(link)
    if not e then return nil end
    local text, color = M.Label(e)
    return {state = e.state, percent = e.pct, label = text, color = color, reason = e.reason, replaces = e.replaces}
end
function _G.ForeverSimAPI.OnItemScore(fn) if type(fn) == 'function' then M.OnChange(fn) end end
function _G.ForeverSimAPI.IsEnabled() return M.Enabled() and not belowMinimum() end

-- Events ------------------------------------------------------------------------------
local dirty, signature = true, ''
local function bagSignature()
    local n = 0
    for i = 1, 13 do local cf = _G['ContainerFrame' .. i]; if cf and cf.IsShown and cf:IsShown() then n = n + 1 end end
    return n .. (BankFrame and BankFrame.IsShown and BankFrame:IsShown() and 'b' or '')
end
local events = CreateFrame('Frame')
for _, e in ipairs({'BAG_UPDATE_DELAYED', 'BANKFRAME_OPENED', 'BANKFRAME_CLOSED', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED',
                    'QUEST_COMPLETE', 'QUEST_FINISHED', 'GET_ITEM_INFO_RECEIVED', 'PLAYER_LEVEL_UP', 'PLAYER_ENTERING_WORLD'}) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript('OnEvent', function(_, e)
    if e == 'PLAYER_REGEN_DISABLED' then
        -- Nothing is computed in combat; running jobs are dropped by their validity check. Forget their busy entries.
        for link, entry in pairs(cache) do if entry.state == 'busy' then cache[link] = nil end end
        return
    end
    if e == 'QUEST_FINISHED' then M.ClearMarks('quest'); return end
    if e == 'QUEST_COMPLETE' then
        questToken = questToken + 1
        if C_Timer and C_Timer.After then C_Timer.After(.1, refreshQuest) else refreshQuest() end
        return
    end
    dirty = true
    if e == 'GET_ITEM_INFO_RECEIVED' and QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then refreshQuest() end
end)
M.OnChange(function()
    dirty = true
    if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then refreshQuest() end
end)
local pass = CreateFrame('Frame')
local acc = 0
pass:SetScript('OnUpdate', function(_, dt)
    acc = acc + dt
    if acc < .4 then return end
    acc = 0
    local sig = bagSignature()
    if sig ~= signature then signature = sig; dirty = true end
    if dirty and not inCombat() then dirty = false; scanBank(); refreshBags() end
end)

local modifier = CreateFrame('Frame')
pcall(modifier.RegisterEvent, modifier, 'MODIFIER_STATE_CHANGED')
modifier:SetScript('OnEvent', function(_, _, key)
    if key ~= 'LSHIFT' and key ~= 'RSHIFT' then return end
    if inCombat() or not (GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown()) then return end
    if GameTooltip.RefreshData then pcall(GameTooltip.RefreshData, GameTooltip) end
end)
local login = CreateFrame('Frame')
login:RegisterEvent('PLAYER_LOGIN')
login:SetScript('OnEvent', function() installTooltip() end)
if IsLoggedIn and IsLoggedIn() then installTooltip() end

