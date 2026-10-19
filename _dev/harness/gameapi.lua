-- Test character: enUS Gnome Warlock, level 20, Westfall, out of combat.
local M = MOCK
local CK = os.getenv('MOCK_CLASS') or 'warlock'
local P = {class = CK:sub(1,1):upper()..CK:sub(2), token = CK:upper(), level = tonumber(os.getenv('MOCK_LEVEL') or '20'), race = CK == 'hunter' and 'Dwarf' or 'Gnome', faction = 'Alliance', name = 'Test'}
M.player = P
M.mapID = 1436
M.items = {
    [57] = {name = "Acolyte's Robe", quality = 0, ilvl = 1, req = 1, class = 'Armor', sub = 'Cloth', loc = 'INVTYPE_ROBE', classID = 4, subID = 1, stats = {RESISTANCE0_NAME = 3}, tooltip = {{"Acolyte's Robe"}, {'Chest', 'Cloth'}, {'3 Armor'}}},
    [2092] = {name = 'Worn Dagger', quality = 1, ilvl = 2, req = 1, class = 'Weapon', sub = 'Daggers', loc = 'INVTYPE_WEAPON', classID = 2, subID = 15,
              stats = {ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 0.9375}, tooltip = {{'Worn Dagger'}, {'One-Hand', 'Dagger'}, {'1 - 2 Damage', 'Speed 1.60'}, {'(0.9 damage per second)'}}},
    [9001] = {name = 'Robe of Testing', quality = 2, ilvl = 20, req = 15, class = 'Armor', sub = 'Cloth', loc = 'INVTYPE_ROBE', classID = 4, subID = 1,
              stats = {RESISTANCE0_NAME = 30, ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3}, tooltip = {{'Robe of Testing'}, {'Chest', 'Cloth'}, {'30 Armor'}, {'+6 Intellect'}}},
    [9002] = {name = 'Band of Shadows', quality = 2, ilvl = 18, req = 14, class = 'Armor', sub = 'Miscellaneous', loc = 'INVTYPE_FINGER', classID = 4, subID = 0,
              stats = {ITEM_MOD_SPELL_POWER_SHORT = 5}, tooltip = {{'Band of Shadows'}, {'Finger'}, {'Equip: Increases damage and healing done by magical spells and effects by up to 5.'}}},
}
M.items[2504] = {name = 'Worn Shortbow', quality = 1, ilvl = 2, req = 1, class = 'Weapon', sub = 'Bows', loc = 'INVTYPE_RANGED', classID = 2, subID = 2, stats = {ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.5}, tooltip = {{'Worn Shortbow'}, {'Ranged', 'Bow'}, {'2 - 4 Damage', 'Speed 2.00'}, {'(1.5 damage per second)'}}}
local equipped = {[5] = 57, [16] = 2092}
if CK == 'hunter' then equipped[18] = 2504 end
local bag = {[1] = 9001, [2] = 9002}
local function link(id) local i = M.items[id]; return i and ('|cffffffff|Hitem:' .. id .. '::::::::20:::::::|h[' .. i.name .. ']|h|r') end
M.link = link

function UnitClass(u) if u == 'player' then return P.class, P.token, 9 end end
function UnitClassBase(u) if u == 'player' then return P.token, 9 end end
function UnitLevel(u) if u == 'player' then return P.level end if u == 'pet' then return P.level end return 0 end
function UnitRace(u) if u == 'player' then return P.race, P.race, 7 end end
function UnitFactionGroup(u) if u == 'player' then return P.faction, P.faction end end
function UnitName(u) if u == 'player' then return P.name, nil end end
function UnitGUID(u) if u == 'player' then return 'Player-1-0000001' end end
function UnitExists(u) return u == 'player' or (u == 'pet' and CK == 'hunter') end
function UnitIsDeadOrGhost() return false end
function UnitIsDead() return false end
function UnitIsGhost() return false end
function UnitAffectingCombat() return false end
function UnitOnTaxi() return false end
function UnitXP() return 5000 end
function UnitXPMax() return 14000 end
function UnitHealth() return 400 end
function UnitHealthMax() return 400 end
function UnitPower() return 600 end
function UnitPowerMax(u, t) if t == 0 or t == nil then return 600 end return 100 end
function UnitPowerType() return 0, 'MANA' end
function UnitStat(u, i) local v = ({20, 25, 30, 60, 55})[i] or 0; return v, v, 0, 0 end
function UnitCreatureFamily(u) if u == 'pet' and CK == 'hunter' then return 'Cat' end end
function UnitCreatureType() return nil end
function UnitClassification() return 'normal' end
function UnitIsPlayer(u) return u == 'player' end
function UnitIsFriend() return false end
function UnitCanAttack() return false end
function UnitReaction() return nil end
function UnitAttackPower() return 20, 0, 0 end
function UnitRangedAttackPower() return 0, 0, 0 end
function UnitDamage(u) if u == 'pet' then return 8, 12, nil, nil, 0, 0, 1 end return 1, 2, nil, nil, 0, 0, 1 end
function UnitAttackSpeed(u) if u == 'pet' then return 2.0 end return 1.6, nil end
function UnitRangedDamage() return 2, 1, 2, 0, 0, 1 end
function UnitPosition(u) if u == 'player' then return -9000, 900, 0, 0 end end
function UnitInParty() return false end
function UnitInRaid() return nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsGroupLeader() return false end
function GetPlayerFacing() return 0 end
function GetCritChance() return 5 end
function GetRangedCritChance() return 5 end
function GetSpellCritChance() return 6 end
function GetSpellBonusDamage() return 10 end
function GetSpellBonusHealing() return 10 end
function GetManaRegen() return 6, 1 end
function GetHaste() return 0 end
function GetMeleeHaste() return 0 end
function GetRangedHaste() return 0 end
function GetSpellPenetration() return 0 end
function GetHitModifier() return 0 end
function GetSpellHitModifier() return 0 end
function GetCombatRating() return 0 end
function GetCombatRatingBonus() return 0 end
function GetShieldBlock() return 0 end
function GetExpertise() return 0 end
if os.getenv('MOCK_NOCONV') then GetCritChanceFromAgility = nil else function GetCritChanceFromAgility() return 1 end end
if os.getenv('MOCK_NOCONV') then GetSpellCritChanceFromIntellect = nil else function GetSpellCritChanceFromIntellect() return 2 end end
function GetPetSpellBonusDamage() return 0 end
function GetShapeshiftFormID() return nil end
function GetShapeshiftForm() return 0 end
function GetWeaponEnchantInfo() return false end
function IsStealthed() return false end
function InCombatLockdown() return M.inCombat == true end
function IsLoggedIn() return true end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function IsResting() return false end
function GetXPExhaustion() return nil end
function GetRestState() return 2, 'Normal', 1 end
function GetMoney() return 123456 end
function GetBindLocation() return 'Sentinel Hill' end
function GetZoneText() return 'Westfall' end
function GetRealZoneText() return 'Westfall' end
function GetSubZoneText() return 'Sentinel Hill' end
function GetMinimapZoneText() return 'Sentinel Hill' end
function GetLocale() return 'enUS' end
function GetRealmName() return 'Forever' end
function GetBuildInfo() return '1.60.1', '70338', 'Oct 1 2026', 16001 end
function GetGameTime() return 10, 24 end
function GetServerTime() return os.time() end
function GetCVar() return '1' end
function SetCVar() end
function GetCVarBool() return true end
function PlaySound() end
function PlaySoundFile() end
function GetFramerate() return 60 end
function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsModifierKeyDown() return false end
function ToggleAllBags() end
function OpenAllBags() end
function CloseAllBags() end
function ToggleWorldMap() end
function OpenWorldMap(id) M.mapID = id or M.mapID end
function ShowUIPanel(f) if f and f.Show then f:Show() end end
function HideUIPanel(f) if f and f.Hide then f:Hide() end end
function RequestTimePlayed() end
function GetAddOnMetadata(addon, field) return field == 'Version' and 'test' or nil end
function IsAddOnLoaded() return true end
C_AddOns = {GetAddOnMetadata = GetAddOnMetadata, IsAddOnLoaded = function() return true end, LoadAddOn = function() return true end, GetNumAddOns = function() return 3 end}
function GetNumAddOns() return 3 end
function LoadAddOn() return true end
function EnableAddOn() end
function GetItemCount(id) if id == 6948 then return 1 end return 0 end
function IsPlayerSpell(id) return M.knownSpellIDs and M.knownSpellIDs[id] or false end
function IsSpellKnown(id) return M.knownSpellIDs and M.knownSpellIDs[id] or false end
function GetSpellCooldown() return 0, 0, 1 end
function GetInventorySlotInfo(name)
    local ids = {HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
                 Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18, TabardSlot = 19}
    return ids[name]
end
function GetInventoryItemLink(u, slot) return u == 'player' and equipped[slot] and link(equipped[slot]) or nil end
function GetInventoryItemID(u, slot) return u == 'player' and equipped[slot] or nil end
function GetInventoryItemTexture() return 134400 end
local function itemInfo(ref)
    local id = type(ref) == 'number' and ref or tonumber(tostring(ref):match('item:(%d+)'))
    local i = id and M.items[id]
    if not i then return nil end
    return i.name, link(id), i.quality, i.ilvl, i.req, i.class, i.sub, 1, i.loc, 134400, 10, i.classID, i.subID
end
GetItemInfo = itemInfo
function GetItemInfoInstant(ref) local n, _, _, _, _, c, s, _, loc, icon, _, cid, sid = itemInfo(ref); if n then return tonumber(tostring(ref):match('(%d+)')), c, s, loc, icon, cid, sid end end
function GetItemStats(ref) local id = tonumber(tostring(ref):match('item:(%d+)')) or ref; local i = M.items[id]; if not i then return nil end; local o = {}; for k, v in pairs(i.stats) do o[k] = v end; return o end
function GetItemSpell() return nil end
function GetItemIcon() return 134400 end
function GetItemCooldown() return 0, 0, 1 end
C_Item = {GetItemInfo = itemInfo, GetItemStats = GetItemStats, GetItemSpell = GetItemSpell, GetItemIconByID = function() return 134400 end,
          GetItemNameByID = function(id) return M.items[id] and M.items[id].name end, GetItemCount = GetItemCount, GetItemCooldown = GetItemCooldown,
          RequestLoadItemDataByID = function() end, GetItemInfoInstant = GetItemInfoInstant, IsEquippableItem = function() return true end,
          GetItemQualityByID = function() return 1 end, DoesItemExistByID = function() return true end, GetItemLink = function() end}
C_Container = {}
function C_Container.GetContainerNumSlots(b) return b == 0 and 16 or 0 end
function C_Container.GetContainerNumFreeSlots(b) return b == 0 and 14 or 0, 0 end
function C_Container.GetContainerItemLink(b, s) return b == 0 and bag[s] and link(bag[s]) or nil end
function C_Container.GetContainerItemInfo(b, s)
    local id = b == 0 and bag[s]
    if not id then return nil end
    return {itemID = id, stackCount = 1, hyperlink = link(id), quality = M.items[id].quality, iconFileID = 134400, isLocked = false}
end
function C_Container.GetContainerItemID(b, s) return b == 0 and bag[s] or nil end
function C_Container.UseContainerItem() end
GetContainerNumSlots = C_Container.GetContainerNumSlots
GetContainerItemLink = C_Container.GetContainerItemLink
GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots

-- Spells & spellbook from the class model (lazy, after FUSLiveData exists).
local book
local function buildBook()
    if book then return book end
    book = {}
    M.knownSpellIDs = {}
    local data = FUSLiveData and FUSLiveData[CK]
    for key, ranks in pairs(data and data.abilities or {}) do
        for _, r in ipairs(ranks) do
            if r.id and (r.level or 1) <= P.level and not r.requiredTalent and not r.requiredItem then
                book[#book + 1] = {id = r.id, name = key:gsub('(%l)(%u)', '%1 %2'), rank = r.rank}
                M.knownSpellIDs[r.id] = true
            end
        end
    end
    table.sort(book, function(a, b) return a.id < b.id end)
    return book
end
M.buildBook = buildBook
local function spellName(id)
    for _, s in ipairs(buildBook()) do if s.id == id then return s.name end end
    return 'Spell ' .. tostring(id)
end
function GetSpellInfo(id) if id == nil then return nil end return spellName(id), nil, 136197, 1500, 0, 30, id end
function GetSpellTexture() return 136197 end
function GetSpellLink(id) return '|Hspell:' .. tostring(id) .. '|h[' .. spellName(id) .. ']|h' end
function GetSpellDescription() return '' end
C_Spell = {GetSpellInfo = function(id) if id == nil then return nil end return {name = spellName(id), iconID = 136197, spellID = id, castTime = 1500} end,
           GetSpellTexture = function() return 136197 end, GetSpellName = function(id) return spellName(id) end, GetSpellLink = GetSpellLink,
           GetSpellCooldown = function() return {startTime = 0, duration = 0, isEnabled = true} end, IsSpellUsable = function() return true end,
           DoesSpellExist = function() return true end, GetSpellDescription = function() return '' end}
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo(t) if t == 1 then return P.class, 136197, 0, #buildBook() end end
function GetSpellBookItemInfo(i) local s = buildBook()[i]; if s then return 'SPELL', s.id end end
function GetSpellBookItemName(i) local s = buildBook()[i]; if s then return s.name, 'Rank ' .. s.rank end end
function HasPetSpells() if CK == 'hunter' then return 0 end return nil end
C_SpellBook = nil
-- Talents: 11 points in Affliction through the legacy API.
local talentRanks = CK == 'warlock' and {tap = 2, suppression = 4, corruption = 5} or {}
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(t) local tree = FUSLiveData[CK].talentTrees[t]; local pts = 0; if t == 1 and CK == 'warlock' then pts = 11 end; return tree.name, 136197, pts, tree.id end
function GetNumTalents(t) return #FUSLiveData[CK].talentTrees[t].talents end
function GetTalentInfo(t, i)
    local node = FUSLiveData[CK].talentTrees[t].talents[i]
    if not node then return nil end
    return node.name, 136197, (node.row or 0) + 1, (node.column or 0) + 1, t == 1 and talentRanks[node.key] or 0, node.maxRank
end
function GetUnspentTalentPoints() local t=tonumber(os.getenv('MOCK_TALENTED') or '0'); local spent = (CK == 'warlock') and 11 or 0; return math.max(0, P.level-9+t-spent) end

-- Auras: none.
C_UnitAuras = {GetAuraDataByIndex = function() return nil end, GetPlayerAuraBySpellID = function() return nil end, GetAuraDataBySpellName = function() return nil end}
function UnitBuff() return nil end
function UnitDebuff() return nil end
function UnitAura() return nil end

-- Quests: empty quest log, nothing completed.
C_QuestLog = {GetNumQuestLogEntries = function() return 0, 0 end, GetInfo = function() return nil end, IsQuestFlaggedCompleted = function() return false end,
              GetLogIndexForQuestID = function() return nil end, IsComplete = function() return false end, GetTitleForQuestID = function() return nil end,
              GetQuestInfo = function() return nil end, RequestLoadQuestByID = function() end, GetQuestObjectives = function() return {} end,
              GetAllCompletedQuestIDs = function() return {} end, GetQuestIDForLogIndex = function() return nil end, IsOnQuest = function() return false end,
              GetSelectedQuest = function() return nil end, SetSelectedQuest = function() end, GetQuestWatchType = function() return nil end,
              AddQuestWatch = function() end, RemoveQuestWatch = function() end, GetNumQuestWatches = function() return 0 end, ShouldShowQuestRewards = function() return true end,
              GetQuestTagInfo = function() return nil end, IsQuestTask = function() return false end, GetMaxNumQuestsCanAccept = function() return 25 end}
function GetNumQuestLogEntries() return 0, 0 end
function GetQuestLogTitle() return nil end
function GetQuestsCompleted() return {} end
function IsQuestComplete() return false end
function GetNumQuestChoices() return 0 end
function GetNumQuestRewards() return 0 end
function GetQuestItemLink() return nil end
function GetTitleText() return 'Test Quest' end
function GetQuestID() return 0 end
function GetNumActiveQuests() return 0 end
function GetNumAvailableQuests() return 0 end
function GetNumGossipActiveQuests() return 0 end
function GetNumGossipAvailableQuests() return 0 end
C_GossipInfo = {GetActiveQuests = function() return {} end, GetAvailableQuests = function() return {} end, GetNumActiveQuests = function() return 0 end, GetNumAvailableQuests = function() return 0 end, GetOptions = function() return {} end}
function AcceptQuest() end
function CompleteQuest() end
function GetQuestReward() end
function IsQuestCompletable() return false end
function SelectGossipActiveQuest() end
function SelectGossipAvailableQuest() end
function GetProfessions() return nil end
function GetProfessionInfo() return nil end
function GetNumSkillLines() return 0 end
function GetSkillLineInfo() return nil end
function GetNumTrainerServices() return 0 end
function NumTaxiNodes() return 0 end
function TaxiNodeName() return nil end
function TaxiNodeGetType() return nil end
function TakeTaxiNode() end

-- Map
local mapNames = {[1436] = 'Westfall', [1429] = 'Elwynn Forest', [1415] = 'Eastern Kingdoms', [1414] = 'Kalimdor', [1453] = 'Stormwind City', [1426] = 'Dun Morogh', [1433] = 'Redridge Mountains'}
C_Map = {}
function C_Map.GetBestMapForUnit(u) if u == 'player' then return M.mapID end end
function C_Map.GetPlayerMapPosition(map, u) if u == 'player' and map == M.mapID then return CreateVector2D(.52, .48) end end
function C_Map.GetMapInfo(id) if not id then return nil end return {mapID = id, name = mapNames[id] or ('Map ' .. id), parentMapID = id == 1415 and 947 or 1415, mapType = id == 1415 and 2 or 3} end
function C_Map.GetMapArtLayers() return {{layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1}} end
function C_Map.GetMapArtLayerTextures() local t = {}; for i = 1, 12 do t[i] = 100000 + i end; return t end
function C_Map.GetMapArtID(id) return id end
function C_Map.GetWorldPosFromMapPos(id, v) return 0, CreateVector2D((v.x or 0) * 1000, (v.y or 0) * 1000) end
function C_Map.GetMapPosFromWorldPos() return 1436, CreateVector2D(.5, .5) end
function C_Map.GetMapChildrenInfo() return {} end
function C_Map.GetAreaInfo() return 'Area' end
function C_Map.GetMapGroupID() return nil end
function C_Map.GetMapLevels() return 0, 0, 0 end
function C_Map.GetMapRectOnMap() return 0, 1, 0, 1 end
function C_Map.GetMapDisplayInfo() return false end
function C_Map.SetUserWaypoint() end
function C_Map.ClearUserWaypoint() end
function C_Map.HasUserWaypoint() return false end
function C_Map.CanSetUserWaypointOnMap() return true end
function C_Map.GetUserWaypoint() return nil end
function C_Map.GetMapWorldSize() return 3000, 2000 end
UiMapPoint = {CreateFromCoordinates = function(m, x, y) return {uiMapID = m, position = CreateVector2D(x, y)} end, CreateFromVector2D = function(m, v) return {uiMapID = m, position = v} end}
C_SuperTrack = {SetSuperTrackedUserWaypoint = function() end, IsSuperTrackingUserWaypoint = function() return false end}
C_MapExplorationInfo = {GetExploredMapTextures = function() return {} end, GetExploredAreaIDsAtPosition = function() return {} end}
function GetInstanceInfo() return 'Eastern Kingdoms', 'none', 0, '', 5, 0, false, 0, 0, nil end
function IsInInstance() return false, 'none' end
function GetNumMapLandmarks() return 0 end
C_Minimap = {GetViewRadius = function() return 200 end}
C_DateAndTime = {GetCurrentCalendarTime = function() return {hour = 10, minute = 24, monthDay = 13, month = 10, year = 2026} end}
C_ChatInfo = {SendAddonMessage = function() end, RegisterAddonMessagePrefix = function() return true end}
function SendChatMessage() end
function RegisterAddonMessagePrefix() return true end
C_Secrets = nil
C_TooltipInfo = nil
C_ClassTalents = nil
C_Traits = nil
C_CVar = {GetCVar = function() return '1' end, SetCVar = function() end, GetCVarBool = function() return true end}
C_EncounterJournal = nil
C_PlayerInfo = {GetClass = function() return {classFile = P.token} end}
function GetClassInfo(i) return P.class, P.token, 9 end
function GetNumClasses() return 9 end
function EasyMenu() end
function CloseDropDownMenus() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function GetMouseFocus() return nil end
function GetMouseFoci() return {} end
function InterfaceOptions_AddCategory() end
Settings = {RegisterCanvasLayoutCategory = function() return {ID = 1, GetID = function() return 1 end} end, RegisterAddOnCategory = function() end,
            RegisterVerticalLayoutCategory = function() return {ID = 1, GetID = function() return 1 end} end, OpenToCategory = function() end}
function GameTooltip_SetDefaultAnchor(t) end
function GameTooltip_Hide() GameTooltip:Hide() end
