-- Forever SIM dungeon catalog: dungeon list, bosses, loot and drop chances without any other addon.
-- Data: DungeonCatalogData.lua (generated, see tools/build_dungeon_catalog.lua).
-- The API keeps the shape the simulator UI and the bridge already use (schema 2).
local P = FUSLive
local D = FUSLiveDungeonData
local API = { schema = 2 }
_G.ForeverSimDungeonAPI = API
if P then P.dungeonCatalog = API end

local function norm(s) return (tostring(s or ""):lower():gsub("^the ", ""):gsub("[^%a]", "")) end
local ALIASES = { sunkentemple = "templeofatalhakkar" }

local function dungeons() return (D and D.dungeons) or {} end

local function find(key)
  if type(key) ~= "string" then return nil end
  for _, d in ipairs(dungeons()) do
    if d.key == key or d.name == key or d.journal == key then return d end
  end
  local n = norm(key)
  for _, d in ipairs(dungeons()) do if norm(d.name) == n then return d end end
end

function API.ListDungeons()
  local out = {}
  for _, d in ipairs(dungeons()) do
    out[#out + 1] = { key = d.key, name = d.name, journalName = d.journal or d.name, min = d.min, max = d.max,
      lootIncomplete = false, source = D.source }
  end
  table.sort(out, function(a, b) return (a.min or 0) == (b.min or 0) and a.name < b.name or (a.min or 0) < (b.min or 0) end)
  return out
end

function API.ListBosses(key)
  local d = find(key)
  if not d then return {} end
  local out, seen = {}, {}
  for _, g in ipairs(d.groups) do
    if g.boss and g.name and not seen[g.name] then
      seen[g.name] = true
      out[#out + 1] = { name = g.name, level = g.level, npcID = g.npcID, dungeonKey = d.key, dungeon = d.name, source = D.source }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function itemsOf(list)
  local ids, seen = {}, {}
  for _, d in ipairs(list) do
    for _, g in ipairs(d.groups) do
      for _, it in ipairs(g.items) do
        if it[1] and not seen[it[1]] then seen[it[1]] = true; ids[#ids + 1] = it[1] end
      end
    end
  end
  return ids
end
API.ItemsOf = itemsOf

local function contextFor(list, name, key)
  local level = UnitLevel and UnitLevel("player")
  if P and P.publicNumber then level = P.publicNumber(level) end
  if type(level) ~= "number" then return nil end
  local class
  if UnitClass then local _, c = UnitClass("player"); class = c end
  local ids = itemsOf(list)
  if #ids == 0 then return nil end
  return { key = key, name = name, level = level, class = class, items = ids, lootIncomplete = false,
    prerequisites = 0, pickups = 0, accepted = 0 }
end

-- Context of a dungeon by key (for the dungeon picker); without key: the instance the player is in.
function API.Context(key)
  if not key then return API.InstanceContext() end
  local d = find(key)
  if not d then return nil end
  local ctx = contextFor({ d }, d.name, d.key)
  if ctx then ctx.min, ctx.max = d.min, d.max end
  return ctx
end
API.GetDungeonContext = API.Context

-- Dungeons matching the instance the player stands in: by instance id (language independent),
-- scarlet monastery by map, otherwise by English name. Wings of one instance are merged.
local function matchInstance()
  if not GetInstanceInfo then return nil end
  local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
  if instanceType ~= "party" and instanceType ~= "raid" then return nil end
  if IsInInstance and not IsInInstance() then return nil end
  if type(name) ~= "string" or name == "" then return nil end
  local id = tonumber(instanceID)
  local hits = {}
  if id then for _, d in ipairs(dungeons()) do for _, v in ipairs(d.instanceIDs or {}) do if v == id then hits[#hits + 1] = d end end end end
  if #hits > 1 then
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local narrowed = {}
    for _, d in ipairs(hits) do if d.scarletMap and mapID and d.scarletMap == mapID then narrowed[#narrowed + 1] = d end end
    if #narrowed > 0 then hits = narrowed end
  end
  if #hits == 0 then
    local n = norm(name); n = ALIASES[n] or n
    for _, d in ipairs(dungeons()) do
      local dn = norm(d.name); local base = norm((tostring(d.name):gsub(":.*$", "")))
      if dn == n or base == n or dn:find(n, 1, true) then hits[#hits + 1] = d end
    end
  end
  if #hits == 0 then return nil end
  return hits, name
end
API.MatchInstance = matchInstance

function API.InstanceContext()
  local hits, name = matchInstance()
  if not hits then return nil end
  local label = #hits == 1 and hits[1].name or name
  return (function(ctx) if ctx then ctx.instance = true end return ctx end)(contextFor(hits, label, "instance:" .. label))
end

-- Weapon/armor drops a character of `level` could wear (required level known from the confirmed drop audit).
function API.LootCandidates(level, limit)
  level = tonumber(level)
  if not level then return {} end
  local out, seen = {}, {}
  for _, d in ipairs(dungeons()) do
    for _, g in ipairs(d.groups) do
      for _, it in ipairs(g.items) do
        local need = tonumber(it[5])
        if need and need <= level and need >= level - 12 and not seen[it[1]] then
          seen[it[1]] = true
          out[#out + 1] = { id = it[1], name = it[2], boss = g.name, dungeonKey = d.key, dungeon = d.name, requiredLevel = need }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.requiredLevel ~= b.requiredLevel then return a.requiredLevel > b.requiredLevel end return a.id < b.id end)
  limit = tonumber(limit) or 40
  while #out > limit do out[#out] = nil end
  return out
end

-- Drop chance lines for tooltips: "12 % - Boss; 3 % - Other".
local byItem
local function build()
  byItem = {}
  for _, d in ipairs(dungeons()) do
    for _, g in ipairs(d.groups) do
      for _, it in ipairs(g.items) do
        local list = byItem[it[1]]
        if not list then list = {}; byItem[it[1]] = list end
        list[#list + 1] = { dungeon = d.name, boss = g.name, chance = it[4] }
      end
    end
  end
end
function API.Sources(itemID)
  if not byItem then build() end
  return byItem[tonumber(itemID) or -1]
end
function API.ChanceText(itemID)
  local list = API.Sources(itemID)
  if not list then return nil end
  local parts = {}
  for _, s in ipairs(list) do
    if s.chance then
      parts[#parts + 1] = string.format("%s%% - %s", (tostring(s.chance):gsub("%.", ",")), s.boss or s.dungeon)
      if #parts == 3 then break end
    end
  end
  if #parts == 0 then return nil end
  return "Drop-Chance: " .. table.concat(parts, "; ")
end

