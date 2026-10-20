-- What the "Beute" tab knows: every wearable item from the sources the addon has data for (dungeon drops with their chances,
-- the items in the bags, the MythicSim top gear), what each would change in the damage (the same values as the tooltips
-- and the dungeon list: C.ItemResult), the best item per slot and where to get the upgrades. No frames here.
local C=ForeverCoreClient
local Loot={};C.Loot=Loot
local function Sim()return C.Sim end
local function now()return GetTime and GetTime()or 0 end

-- Slots as drawn on the paper doll. inv = the game's inventory slot id, pool = the group of slots that share items
-- (two rings, two trinkets).
Loot.SLOTS={
 {key='head',label='Kopf',inv=1,pool='head',side='L'},
 {key='neck',label='Hals',inv=2,pool='neck',side='L'},
 {key='shoulder',label='Schulter',inv=3,pool='shoulder',side='L'},
 {key='back',label='Rücken',inv=15,pool='back',side='L'},
 {key='chest',label='Brust',inv=5,pool='chest',side='L'},
 {key='wrist',label='Handgelenk',inv=9,pool='wrist',side='L'},
 {key='hands',label='Hände',inv=10,pool='hands',side='L'},
 {key='waist',label='Taille',inv=6,pool='waist',side='R'},
 {key='legs',label='Beine',inv=7,pool='legs',side='R'},
 {key='feet',label='Füße',inv=8,pool='feet',side='R'},
 {key='finger1',label='Ring',inv=11,pool='finger',side='R'},
 {key='finger2',label='Ring',inv=12,pool='finger',side='R'},
 {key='trinket1',label='Schmuck',inv=13,pool='trinket',side='R'},
 {key='trinket2',label='Schmuck',inv=14,pool='trinket',side='R'},
 {key='mainhand',label='Waffe',inv=16,pool='mainhand',side='B'},
 {key='offhand',label='Nebenhand',inv=17,pool='offhand',side='B'},
 {key='ranged',label='Fernkampf',inv=18,pool='ranged',side='B'},
}
local BY_KEY={};for _,s in ipairs(Loot.SLOTS)do BY_KEY[s.key]=s end
function Loot.Slot(key)return BY_KEY[key]end
-- the engine's equipment slot index of an inventory slot (preset gear lists use it)
local ENGINE_INDEX={head=0,neck=1,shoulder=2,back=3,chest=4,wrist=5,hands=6,waist=7,legs=8,feet=9,finger1=10,finger2=11,trinket1=12,trinket2=13,mainhand=14,offhand=15,ranged=16}
local POOL_BY_INDEX={};for key,i in pairs(ENGINE_INDEX)do POOL_BY_INDEX[i]=BY_KEY[key].pool end

local LOC_POOL={INVTYPE_HEAD='head',INVTYPE_NECK='neck',INVTYPE_SHOULDER='shoulder',INVTYPE_CLOAK='back',INVTYPE_CHEST='chest',INVTYPE_ROBE='chest',
 INVTYPE_WRIST='wrist',INVTYPE_HAND='hands',INVTYPE_WAIST='waist',INVTYPE_LEGS='legs',INVTYPE_FEET='feet',INVTYPE_FINGER='finger',INVTYPE_TRINKET='trinket',
 INVTYPE_WEAPON='mainhand',INVTYPE_2HWEAPON='mainhand',INVTYPE_WEAPONMAINHAND='mainhand',INVTYPE_SHIELD='offhand',INVTYPE_HOLDABLE='offhand',INVTYPE_WEAPONOFFHAND='offhand',
 INVTYPE_RANGED='ranged',INVTYPE_RANGEDRIGHT='ranged',INVTYPE_THROWN='ranged',INVTYPE_RELIC='ranged'}
-- the first word of the catalog's slot text ("Back, Cloth")
local TEXT_POOL={Head='head',Neck='neck',Shoulder='shoulder',Back='back',Chest='chest',Wrist='wrist',Hands='hands',Waist='waist',Legs='legs',Feet='feet',Finger='finger',
 Trinket='trinket',['Main Hand']='mainhand',['One-Hand']='mainhand',['Two-Hand']='mainhand',['Off Hand']='offhand',['Held In Off-hand']='offhand',Shield='offhand',
 Ranged='ranged',Wand='ranged',Thrown='ranged',Relic='ranged'}
local function equipLoc(id)
 local inst=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 if type(inst)~='function'then return nil end
 local ok,_,_,_,loc=pcall(inst,id)
 return ok and type(loc)=='string'and loc~=''and loc or nil
end
function Loot.PoolOf(id,text)
 local loc=equipLoc(id);if loc and LOC_POOL[loc]then return LOC_POOL[loc]end
 if type(text)=='string'then local first=text:match('^([^,]+)');if first and TEXT_POOL[first]then return TEXT_POOL[first]end end
 return nil
end

-- Settings (what counts as a source) -----------------------------------------------------------------------------------
local function store()
 local s=Sim().Store();if type(s.loot)~='table'then s.loot={}end
 local l=s.loot;if type(l.filter)~='table'then l.filter={dungeon=true,bag=true,star=true,onlyStar=false}end
 return l
end
function Loot.Filter()return store().filter end
function Loot.SetFilter(key,on)store().filter[key]=on and true or false;Loot.cands=nil;Sim().Changed()end
Loot.LEVEL_FROM=50       -- dungeons that still have something for level 50 and up

-- Candidates ------------------------------------------------------------------------------------------------------------------
-- {id,name,pool,sources={{kind='dungeon'|'bag'|'star',...}},star=bool,owned=bool,requiredLevel}
function Loot.Candidates()
 if Loot.cands then return Loot.cands end
 local filter=Loot.Filter();local list,byId={}, {}
 local function get(id,name,pool)
  local c=byId[id];if c then return c end
  c={id=id,name=name,pool=pool,sources={}};byId[id]=c;list[#list+1]=c;return c
 end
 if filter.dungeon and not filter.onlyStar then
  local D=_G.FUSLiveDungeonData
  for _,d in ipairs(D and D.dungeons or{})do
   if(tonumber(d.max)or 0)>=Loot.LEVEL_FROM then
    for _,g in ipairs(d.groups or{})do
     for _,it in ipairs(g.items or{})do
      local id,name,text,chance,need=it[1],it[2],it[3],it[4],it[5]
      local pool=id and Loot.PoolOf(id,text)
      if pool and(need==nil or need<=60)then
       local c=get(id,name,pool);c.requiredLevel=need
       c.sources[#c.sources+1]={kind='dungeon',dungeon=d.name,key=d.key,boss=g.name,chance=chance}
      end
     end
    end
   end
  end
 end
 if filter.bag and not filter.onlyStar then
  for id in pairs(Sim().ScanBags())do
   local pool=Loot.PoolOf(id)
   if pool then local c=get(id,nil,pool);c.owned=true;c.sources[#c.sources+1]={kind='bag'}end
  end
 end
 if filter.star then
  local presets=Sim().Presets()
  local function addSet(set)
   for _,it in ipairs(set.items or{})do
    local id=tonumber(it.id)
    local pool=id and(POOL_BY_INDEX[tonumber(it.slot)]or Loot.PoolOf(id))
    if pool then local c=get(id,nil,pool);c.star=true;c.sources[#c.sources+1]={kind='star',set=set.name}end
   end
  end
  local any=false
  for _,set in ipairs(presets and presets.gear or{})do if tostring(set.name):lower():find('bis',1,true)then addSet(set);any=true end end
  if not any then for _,set in ipairs(presets and presets.gear or{})do addSet(set)end end
 end
 table.sort(list,function(a,b)return a.id<b.id end)
 Loot.cands=list;Loot.byId=byId
 return list
end
function Loot.Reset()Loot.cands=nil;Loot.byId=nil end

-- Worn items ------------------------------------------------------------------------------------------------------------------
function Loot.Worn(slotKey)
 local s=BY_KEY[slotKey];if not s then return nil end
 local ok,id=pcall(GetInventoryItemID,'player',s.inv)
 if not ok or type(id)~='number'then return nil end
 local link;local okl,l=pcall(GetInventoryItemLink,'player',s.inv);if okl and type(l)=='string'then link=l end
 local name;local f=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 if f then local okn,n=pcall(f,link or id);if okn and type(n)=='string'then name=n end end
 return{id=id,link=link,name=name}
end
-- the enchant id inside an item link (0 = none)
function Loot.EnchantOf(link)
 if type(link)~='string'then return 0 end
 local enchant=link:match('item:%d+:(%-?%d*)')
 return tonumber(enchant)or 0
end

-- Values ----------------------------------------------------------------------------------------------------------------------
-- Asks for the value of the candidates that have none yet (the same pipeline as every tooltip) and counts where things stand.
function Loot.Poll(budget)
 local list=Loot.Candidates();local p={total=#list,ready=0,busy=0,failed=0,blocked=0,unread=0}
 budget=budget or 80;local asked=0
 for _,c in ipairs(list)do
  local e=c.entry
  if not e or e.state=='busy'or e.state==nil then
   if asked<budget then
    asked=asked+1
    e=C.ItemResult and C.ItemResult('item:'..c.id,true)
    c.entry=e
    if e==nil then
     c.tries=(c.tries or 0)+1
     if c.tries<=6 and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,c.id)end
    end
   end
  end
  e=c.entry
  if not e then if(c.tries or 0)>6 then p.failed=p.failed+1 else p.unread=p.unread+1 end
  elseif e.state=='ok'then p.ready=p.ready+1
  elseif e.state=='busy'then p.busy=p.busy+1
  elseif e.state=='blocked'then p.blocked=p.blocked+1
  else p.failed=p.failed+1 end
 end
 Loot.progress=p
 return p
end
function Loot.Value(c)local e=c.entry;if e and e.state=='ok'then return tonumber(e.pct)or 0,tonumber(e.delta)or 0 end end

-- "Alle Items simmen": polls until nothing is open any more (or gives up after a while).
Loot.running=false
function Loot.Run(done)
 if Loot.running then return false end
 Loot.running=true;Loot.startedAt=now();Loot.Reset()
 local function tick()
  local p=Loot.Poll(80);Sim().Changed()
  local open=p.busy+p.unread
  if open==0 or now()-Loot.startedAt>20*60 then
   Loot.running=false
   local s=store();s.lastRun={at=time and time()or 0,total=p.total,ready=p.ready}
   Sim().Changed();if done then done(p)end
   return
  end
  if C_Timer and C_Timer.After then C_Timer.After(3,tick)else Loot.running=false end
 end
 tick()
 return true
end

-- Tables ----------------------------------------------------------------------------------------------------------------------
local THRESHOLD=0.05   -- percent a drop has to bring to count as an upgrade
Loot.THRESHOLD=THRESHOLD
-- per pool: items with a value, best first
function Loot.Pools()
 local pools={}
 for _,c in ipairs(Loot.Candidates())do
  local pct,delta=Loot.Value(c)
  if pct then local list=pools[c.pool];if not list then list={};pools[c.pool]=list end;list[#list+1]={c=c,id=c.id,pct=pct,delta=delta}end
 end
 for _,list in pairs(pools)do table.sort(list,function(a,b)if a.pct~=b.pct then return a.pct>b.pct end;return a.id<b.id end)end
 return pools
end
-- The best item for each slot: {slot=key, worn=info|nil, best={id,pct,c}|nil, better=bool}
function Loot.PreBis()
 local pools=Loot.Pools();local out={};local taken={}
 for _,s in ipairs(Loot.SLOTS)do
  local row={slot=s.key,worn=Loot.Worn(s.key)}
  local list=pools[s.pool]or{}
  for _,e in ipairs(list)do
   if e.pct>THRESHOLD and not taken[e.id]and not(row.worn and row.worn.id==e.id)then
    -- an item already worn in the twin slot is not an upgrade either
    local twin=false
    if s.pool=='finger'or s.pool=='trinket'then
     for _,o in ipairs(Loot.SLOTS)do if o.pool==s.pool and o.key~=s.key then local w=Loot.Worn(o.key);if w and w.id==e.id then twin=true end end end
    end
    if not twin then row.best=e;taken[e.id]=true;row.better=true;break end
   end
  end
  out[#out+1]=row
 end
 return out
end
-- the total gain if all the best items were worn (sum of the single values: an approximation)
function Loot.Total(prebis)
 local sum,n=0,0
 for _,r in ipairs(prebis or Loot.PreBis())do if r.best then sum=sum+r.best.pct;n=n+1 end end
 return sum,n
end
-- Alternatives for one slot: the next best items with a value.
function Loot.Alternatives(slotKey,skipId,limit)
 local s=BY_KEY[slotKey];local list=Loot.Pools()[s and s.pool]or{};local out={}
 for _,e in ipairs(list)do if e.id~=skipId and #out<(limit or 3)then out[#out+1]=e end end
 return out
end
-- Where to go: the dungeons that drop the most of the upgrades; gain per run = sum of chance x value.
function Loot.Farm(prebis,limit)
 local byDungeon={}
 for _,r in ipairs(prebis or Loot.PreBis())do
  if r.best then
   for _,src in ipairs(r.best.c.sources)do
    if src.kind=='dungeon'then
     local d=byDungeon[src.dungeon];if not d then d={dungeon=src.dungeon,key=src.key,upgrades=0,perRun=0,items={}};byDungeon[src.dungeon]=d end
     d.upgrades=d.upgrades+1;d.perRun=d.perRun+(tonumber(src.chance)or 0)/100*r.best.pct;d.items[#d.items+1]=r.best.id
    end
   end
  end
 end
 local out={};for _,d in pairs(byDungeon)do out[#out+1]=d end
 table.sort(out,function(a,b)if a.perRun~=b.perRun then return a.perRun>b.perRun end;return a.dungeon<b.dungeon end)
 while #out>(limit or 3)do out[#out]=nil end
 return out
end

-- Stat weights (the engine's own sensitivity of the damage to each stat) ----------------------------------------------------------
local STAT_LABEL={StatSpellDamage='Zauberschaden',StatSpellHitRating='Trefferwertung',StatSpellCritRating='Kritische Zauberwertung',StatSpellHasteRating='Zaubertempo',
 StatIntellect='Intelligenz',StatAgility='Beweglichkeit',StatStrength='Stärke',StatAttackPower='Angriffskraft'}
function Loot.LoadWeights(cb,force)
 local s=store();local ctx=C.SimCacheContext and C.SimCacheContext()
 if s.weights and s.weights.context==ctx and not force then if cb then cb(s.weights)end;return true end
 local ok=C.Request('weights',{},function(result,issue)
  if type(result)~='table'or type(result.rows)~='table'then if cb then cb(nil,issue or'Keine Antwort')end;return end
  local rows,top={},0
  for _,r in ipairs(result.rows)do local v=tonumber(r.perPoint)or 0;if v>top then top=v end;rows[#rows+1]={key=r.key,perPoint=v}end
  for _,r in ipairs(rows)do r.weight=top>0 and math.max(0,r.perPoint)/top or 0;r.label=STAT_LABEL[r.key]or tostring(r.key):gsub('^Stat','')end
  table.sort(rows,function(a,b)return a.weight>b.weight end)
  s.weights={context=ctx,rows=C.clean(rows),at=time and time()or 0}
  Sim().Changed();if cb then cb(s.weights)end
 end,{timeout=300})
 if not ok and cb then cb(nil,'Anfrage nicht moeglich')end
 return ok
end
function Loot.Weights()local s=store();return s.weights end
function Loot.LastRun()return store().lastRun end
