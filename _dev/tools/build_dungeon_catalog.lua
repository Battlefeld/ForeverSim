-- Generates ForeverSimBridge/DungeonCatalogData.lua: the dungeon list, bosses, loot and drop chances the
-- simulator needs (dungeon picker, boss benchmarks, pre-calculation when entering a dungeon).
--
-- Usage:
--   lua5.1 _dev/tools/build_dungeon_catalog.lua "<NorgannonDB folder>" > ForeverSimBridge/DungeonCatalogData.lua
--
-- Source: NorgannonDB (https://github.com/zmarotrix/NorgannonDB, GPL-3.0), read only, no code of it is run but its
-- data files: the instances (level range, bosses with their loot, trash loot; collected from DungeonJournal by Exehn),
-- the creatures (name, level, drop chances) and the items (name, class, required level).
local root = assert(arg[1], "NorgannonDB folder")
if not root:find("[/\\]$") then root = root .. "/" end

-- NorgannonDB's data files call NorgannonDB:_PackedLoader(kind) for a function R(id, name, fields) and fill
-- NorgannonDB.instances; the fields are a Lua table literal.
local store = {}
NorgannonDB = {}
function NorgannonDB:_PackedLoader(kind)
  store[kind] = store[kind] or {}
  local t = store[kind]
  return function(id, name, body) t[id] = { name = name, body = body } end
end
for _, f in ipairs({ "items", "npcs", "world" }) do assert(loadfile(root .. "data/" .. f .. ".lua"))() end
local function fields(kind, id)
  local r = store[kind] and store[kind][id]
  if not r then return nil end
  if not r.f then r.f = assert(loadstring("return {" .. (r.body or "") .. "}"))() end
  return r.f, r.name
end
local version = "unknown"
for line in io.lines(root .. "NorgannonDB.toc") do local v = line:match("^## Version:%s*(.-)%s*$") if v then version = v end end

-- NorgannonDB's instances under the keys the simulator has always used, with the client's instance ids
-- (Forever keeps the Classic ids for Classic dungeons) and the map of a Scarlet Monastery wing.
local DUNGEONS = {
  { "ragefire-chasm", "rfc", { 389 } }, { "hall-of-thanes", "thanes", { 3065 } }, { "ruins-of-lordaeron", "lordaeron", { 2999 } },
  { "wailing-caverns", "wc", { 43 } }, { "deadmines", "dm", { 36 } }, { "shadowfang-keep", "sfk", { 33 } },
  { "excavation-site-wetlands", "excavation", { 2998 } }, { "blackfathom-deeps", "bfd", { 48 } }, { "stockade", "stocks", { 34 } },
  { "city-of-dalaran", "dalaran", { 2959 } }, { "gnomeregan", "gnomer", { 90 } }, { "razorfen-kraul", "rfk", { 47 } },
  { "sm-graveyard", "smgy", { 189 }, 302 }, { "sm-library", "smlib", { 189 }, 303 }, { "sm-armory", "smarm", { 189 } },
  { "sm-cathedral", "smcath", { 189 } }, { "razorfen-downs", "rfd", { 129 } }, { "uldaman", "ulda", { 70 } },
  { "zulfarrak", "zf", { 209 } }, { "maraudon", "mara", { 349 } }, { "sunken-temple", "st", { 109 } },
  { "blackrock-depths", "brd", { 230 } }, { "lbrs", "lbrs", { 229 } }, { "ubrs", "ubrs", { 229 } },
  { "scholomance", "scholo", { 289 } }, { "stratholme", "strat", { 329 } }, { "dm-east", "dme", { 429 } },
  { "dm-north", "dmn", { 429 } }, { "dm-west", "dmw", { 429 } },
}
-- English names where NorgannonDB keeps only the key (the client's names, as the instance reports them)
local NAMES = {
  ["ragefire-chasm"] = "Ragefire Chasm", ["wailing-caverns"] = "Wailing Caverns", deadmines = "The Deadmines",
  ["shadowfang-keep"] = "Shadowfang Keep", ["blackfathom-deeps"] = "Blackfathom Deeps", stockade = "The Stockade",
  gnomeregan = "Gnomeregan", ["razorfen-kraul"] = "Razorfen Kraul", ["sm-graveyard"] = "Scarlet Monastery: Graveyard",
  ["sm-library"] = "Scarlet Monastery: Library", ["sm-armory"] = "Scarlet Monastery: Armory",
  ["sm-cathedral"] = "Scarlet Monastery: Cathedral", ["razorfen-downs"] = "Razorfen Downs", uldaman = "Uldaman",
  zulfarrak = "Zul'Farrak", maraudon = "Maraudon", ["sunken-temple"] = "The Temple of Atal'Hakkar", ["blackrock-depths"] = "Blackrock Depths",
  lbrs = "Lower Blackrock Spire", ubrs = "Upper Blackrock Spire", scholomance = "Scholomance", stratholme = "Stratholme",
  ["dm-east"] = "Dire Maul: East", ["dm-north"] = "Dire Maul: North", ["dm-west"] = "Dire Maul: West",
  ["excavation-site-wetlands"] = "Excavation Site: Wetlands", ["city-of-dalaran"] = "City of Dalaran",
  ["hall-of-thanes"] = "Hall of Thanes", ["ruins-of-lordaeron"] = "Ruins of Lordaeron",
}
-- What an item is (the first word is the slot the loot list sorts by when the client cannot say)
local WEAPON = { [0] = "One-Hand, Axe", [1] = "Two-Hand, Axe", [2] = "Ranged, Bow", [3] = "Ranged, Gun", [4] = "One-Hand, Mace",
  [5] = "Two-Hand, Mace", [6] = "Two-Hand, Polearm", [7] = "One-Hand, Sword", [8] = "Two-Hand, Sword", [10] = "Two-Hand, Staff",
  [13] = "One-Hand, Fist Weapon", [15] = "One-Hand, Dagger", [16] = "Thrown", [18] = "Ranged, Crossbow", [19] = "Wand" }
local ARMOR = { [0] = "Armor, Miscellaneous", [1] = "Armor, Cloth", [2] = "Armor, Leather", [3] = "Armor, Mail", [4] = "Armor, Plate",
  [6] = "Shield", [7] = "Relic", [8] = "Relic", [9] = "Relic" }
local function kindOf(f)
  if not f then return nil end
  if f.class == 2 then return WEAPON[f.subClass] or "Weapon" end
  if f.class == 4 then return ARMOR[f.subClass] or "Armor" end
  if f.class == 9 then return "Recipe" end
  return nil
end
-- The drop chance of an item from a creature in percent (0 in NorgannonDB means seen, chance unknown: nil)
local function chance(npc, item)
  local nf = fields("npcs", npc)
  local c = nf and nf.drops and nf.drops[item]
  if not c or c == 0 then
    local itf = fields("items", item)
    c = itf and itf.drops and itf.drops.npcs and itf.drops.npcs[npc]
  end
  if c and c > 0 then return c end
end

local function q(s) return string.format("%q", tostring(s or "")) end
local function num(v) return v and string.format("%.4g", v) or "nil" end
local out = {}
local function w(s) out[#out + 1] = s end
w("-- GENERATED by _dev/tools/build_dungeon_catalog.lua. Do not edit by hand.")
w("-- Source: NorgannonDB " .. version .. " (github.com/zmarotrix/NorgannonDB, GPL-3.0; instances from DungeonJournal by Exehn).")
w("-- Drop chances are percent values (nil: the drop is known, its chance is not); boss=false marks the trash loot.")
w("FUSLiveDungeonData = {")
w("  source = " .. q("NorgannonDB " .. version) .. ",")
w("  dungeons = {")
local nDungeons, totalItems, withChance = 0, 0, 0
local inst = assert(NorgannonDB.instances, "NorgannonDB.instances missing")
for _, row in ipairs(DUNGEONS) do
  local nkey, key, ids, smap = row[1], row[2], row[3], row[4]
  local d = inst[nkey]
  if d and d.levels and d.levels.min and d.levels.max then
    nDungeons = nDungeons + 1
    local name = NAMES[nkey] or d.name or nkey
    w(string.format("    { key = %s, name = %s, journal = %s, min = %d, max = %d, new = %s, instanceIDs = {%s}, scarletMap = %s,",
      q(key), q(name), q(nkey == "sunken-temple" and "Sunken Temple" or name), d.levels.min, d.levels.max, tostring(d.forever == true), table.concat(ids, ","), smap and tostring(smap) or "nil"))
    w("      groups = {")
    local function item(id, npc)
      local f, iname = fields("items", id)
      local c = npc and chance(npc, id)
      totalItems = totalItems + 1
      if c then withChance = withChance + 1 end
      return string.format("{%d,%s,%s,%s,%s}", id, q(iname or ("Item " .. id)), kindOf(f) and q(kindOf(f)) or "nil", num(c), f and f.requiredLevel and tostring(f.requiredLevel) or "nil")
    end
    for _, b in ipairs(d.bosses or {}) do
      local nf, bname = fields("npcs", b.id)
      local items = {}
      for _, id in ipairs(b.loot or {}) do items[#items + 1] = item(id, b.id) end
      local level = nf and (nf.maxLevel or nf.minLevel)
      w(string.format("        { name = %s, npcID = %d, level = %s, boss = true, items = { %s } },", q(bname or ("NPC " .. b.id)), b.id,
        level and tostring(level) or "nil", table.concat(items, ", ")))
    end
    if d.trash and #d.trash > 0 then
      local items = {}
      for _, id in ipairs(d.trash) do items[#items + 1] = item(id, nil) end
      w(string.format("        { name = %s, npcID = nil, level = nil, boss = false, items = { %s } },", q("Trash"), table.concat(items, ", ")))
    end
    w("      } },")
  end
end
w("  },")
w("}")
io.write(table.concat(out, "\n"), "\n")
io.stderr:write(string.format("%d dungeons, %d items, %d with a drop chance\n", nDungeons, totalItems, withChance))
