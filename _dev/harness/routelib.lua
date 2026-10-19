-- Shared helpers for offline route analysis: loads FDQ with the WoW mocks and walks a
-- route plan chain with the addon's own RoutePlan/ModePolicy logic.
local L = {}

function L.Load(H, ROOT, race, class, faction)
    dofile(H .. '/wowmock.lua')
    dofile(H .. '/gameapi.lua')
    MOCK.player.race, MOCK.player.token, MOCK.player.faction = race or 'Orc', class or 'WARRIOR', faction or 'Horde'
    local ns = {}
    for line in io.lines(ROOT .. '/ForeverDungeonQuest/ForeverDungeonQuest.toc') do
        line = line:gsub('\r', '')
        if line ~= '' and not line:match('^#') and line:match('%.lua%s*$') then
            local f = line:gsub('\\', '/'):gsub('^%s+', ''):gsub('%s+$', '')
            if not (L.skip and L.skip[f]) then
                local ok, err = pcall(assert(loadfile(ROOT .. '/ForeverDungeonQuest/' .. f)), 'ForeverDungeonQuest', ns)
                if not ok then io.stderr:write('load ' .. f .. ': ' .. tostring(err) .. '\n') end
            end
        end
    end
    -- Load-on-demand route addon (Level 30-60): in the game ForeverQuests loads it when needed, here always.
    local routes60 = L.routes60Dir or os.getenv('RXP_ROUTES60_DIR') or (ROOT .. '/ForeverDungeonQuestRoutes60')
    local extra = routes60 .. '/ForeverDungeonQuestRoutes60.toc'
    local fh = io.open(extra)
    local dirProbe = io.open(routes60 .. '/Schnell_RXP_60.lua')
    if dirProbe then dirProbe:close() end
    if not fh and dirProbe then error('ForeverDungeonQuestRoutes60.toc fehlt, obwohl Routendateien vorhanden sind') end
    if fh then
        fh:close()
        local ns2 = {}
        for line in io.lines(extra) do
            line = line:gsub('\r', '')
            if line ~= '' and not line:match('^#') and line:match('%.lua%s*$') then
                local f = line:gsub('^%s+', ''):gsub('%s+$', '')
                if not (L.skip and L.skip[f]) then
                    local ok, err = pcall(assert(loadfile(routes60 .. '/' .. f)), 'ForeverDungeonQuestRoutes60', ns2)
                    if not ok then io.stderr:write('load ' .. f .. ': ' .. tostring(err) .. '\n') end
                end
            end
        end
    end
    if not L.lazy and ns.RoutePackages.Materialize then
        local ids={};for id in pairs(ns.RoutePackages.packages)do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids)do assert(ns.RoutePackages.Materialize(id))end
    end
    L.ns = ns
    return ns
end

-- Every valid race/class/faction profile from the addon's own profile matrix.
function L.Profiles(ns)
    local out = {}
    for race, r in pairs(ns.RaceDB) do
        for _, faction in ipairs({'Alliance', 'Horde'}) do
            for class in pairs(ns.ClassDB) do
                if ns.ValidProfile(race, class, faction) then out[#out + 1] = {race = race, class = class, faction = faction} end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.faction ~= b.faction then return a.faction < b.faction end
        if a.class ~= b.class then return a.class < b.class end
        return a.race < b.race
    end)
    return out
end

L.XPL = {400,900,1400,2100,2800,3600,4500,5400,6500,7600,8800,10100,11400,12900,14400,16000,17700,19400,21300,23200,
         25200,27300,29400,31700,34000,36400,38900,41400,44300,47400,
         -- 31-59: Classic table; Forever keeps the XP curve unchanged (Wowhead Forever, 8 Oct 2026). 60 is a placeholder.
         50800,54500,58600,62800,67100,71600,76100,80800,85700,90700,95800,101000,106300,111800,117500,123200,129100,135100,141200,
         147500,153900,160400,167100,173900,180800,187900,195000,202300,209800,217000}
-- Highest level the simulation and compiler work towards (RXP_MAX_LEVEL=60 for the 30-60 routes).
L.MAXL = tonumber(os.getenv('RXP_MAX_LEVEL')) or 30
-- Quest XP at the player's level. Forever values (ForeverQuestXP.lua, from Wowhead's Forever
-- database) win over the classic quest data: base XP and Forever's per-quest multiplier
-- (e.g. Deviate Hides 1600 × 1.95 after the dungeon-quest change of 1/2 October).
function L.QuestXP(q, level)
    local f = L.ns and L.ns.ForeverQuestXP and L.ns.ForeverQuestXP[q.id]
    local xp = (f and f.xp) or q.xp or 0
    local mult = f and f.mult or 1
    local d = level - (q.level or level)
    if d >= 10 then xp = math.floor(xp * 0.1) elseif d == 9 then xp = math.floor(xp * 0.2) elseif d == 8 then xp = math.floor(xp * 0.4)
    elseif d == 7 then xp = math.floor(xp * 0.6) elseif d == 6 then xp = math.floor(xp * 0.8) end
    return xp * mult
end
-- Incidental XP (mobs on the way, discovery) on top of quest and objective XP. Calibrated so
-- that RestedXP 1-22 needs only the little grinding RestedXP itself plans.
L.FACTOR = 1.05
function L.MobXP(level) return 45 + 5 * level end
-- Expected kills for a quest's objectives: kill objectives count directly, item objectives
-- assume a 2/3 drop chance; objectives without any count assume 8.
function L.KillsFor(q, counts)
    local total = 0
    local known = counts and counts[q.id] or {}
    for i, o in ipairs(q.objectives or {}) do
        local c = known[i] and known[i].count or (type(o.count) == 'number' and o.count) or 8
        local kill = (known[i] and known[i].kill) or o.kind == 'KILL'
        if kill then total = total + c elseif o.kind == 'LOOT' then total = total + c * 1.5 end
    end
    return total
end

-- Forever XP model (v2). Sources and assumptions: ForeverDungeonQuest/Pruefberichte/XP-Modell.md
L.MODEL = {
    dungeonMob = 0.30,        -- dungeon kill XP vs classic: about -75 % (Deadmines elite 20 instead of 80 XP), +20 % from 8 Oct
    elite = 2, groupShare = 1.4 / 5,   -- classic: elites give double XP; 5-player group bonus 1.4 split five ways
    food = 0.05, foodUptime = 0.75, foodFrom = 5,     -- Well Fed: +5 % XP from kills (not quests)
    bag = 0.03, bagUptime = 0.5, bagFrom = 20,        -- Cozy Sleeping Bag: Well-Rested up to 3 × 1 %
    tent = 0.05, tentFrom = 12,                       -- Camp Tent (Leatherworking 20): rested worth 5 % of a level, 1 h lock
    grindSeconds = 22.5,                              -- 18 s per kill + 25 % downtime (same as the compiler)
    campXP = {adventurer = 405, outdoors = 405, camping101 = 270},   -- Wowhead Forever
}
-- Elite kills of one normal dungeon run (estimate; Forever's new dungeons use the default).
L.DUNGEON_KILLS = {rfc = 50, wc = 110, dm = 90, sfk = 90, bfd = 110, stocks = 70, gnomer = 130, rfk = 90,
    thanes = 70, lordaeron = 80, excavation = 90}
local PROF_NAME = {[197] = 'Tailoring', [333] = 'Enchanting', [393] = 'Skinning', [165] = 'Leatherworking', [186] = 'Mining',
    [164] = 'Blacksmithing', [182] = 'Herbalism', [171] = 'Alchemy', [202] = 'Engineering', [185] = 'Cooking', [129] = 'First Aid', [356] = 'Fishing'}

-- What the active package actually guides the player to do (side content, buffs, dungeons).
function L.Features(ns, profile, mode, opts)
    opts = opts or {}
    local pkg = ns.RoutePackages.active or {}
    local prof = pkg.profile or {}
    local st = L.State(profile, mode)
    local pp = ns.RouteModules and ns.RouteModules.ProfessionProfile(st)
    local professions = {}
    if pp then
        if pp.starter then professions[pp.starter] = true end
        for _, id in ipairs(pp.targets or {}) do professions[id] = true end
    end
    local balancedRuns = opts.balancedDungeons ~= false
    return {
        food = prof.Cooking == true, bag = prof.SleepingBag == true,
        tent = prof.Camping == true and professions[165] == true,
        professionQuests = mode ~= 'speed', professions = professions,
        classQuests = (mode == 'balanced' or mode == 'completion') and mode or nil,
        dungeonRuns = pkg.dungeonRoute == true or (mode == 'balanced' and balancedRuns) or opts.group == true,
        skipDungeonQuests = mode == 'balanced' and not balancedRuns,
    }
end

function L.State(p, mode)
    return {race = p.race, class = p.class, faction = p.faction, level = 1, mode = mode, professions = {}, spells = {},
            active = {}, ready = {}, completed = {}, dungeonState = {}}
end

function L.Activate(ns, mode, packageId)
    ns.RoutePackages.active = nil
    local db = {settings = {mode = mode, routePackages = {}}}
    packageId = packageId or os.getenv('ROUTE_PACKAGE')
    if packageId then db.settings.routePackages[mode] = packageId end
    return ns.RoutePackages.Ensure(db)
end

-- Ordered node list of a block, as RoutePlan.Resolve sees it (nodes + module attachments).
function L.BlockNodes(block)
    local list = {}
    -- Hint nodes ("Unterwegs mitnehmen") are optional extras: neither counted nor waited for.
    for _, n in ipairs(block.nodes or {}) do if not n.hint then list[#list + 1] = n end end
    for _, n in ipairs(block.modules or {}) do list[#list + 1] = n end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

local function hasBit(mask, b) return mask and mask ~= 0 and math.floor(mask / b) % 2 == 1 end
function L.Available(ns, q, p)
    local r = ns.RaceDB[p.race]
    local rb = r.masks and r.masks[p.faction] or r.mask
    if q.raceMask and q.raceMask ~= 0 and not hasBit(q.raceMask, rb) then return false end
    if q.classMask and q.classMask ~= 0 and not hasBit(q.classMask, ns.ClassDB[p.class].mask) then return false end
    return true
end
function L.MissingPrereqs(q, s)
    local missing = {}
    for _, x in ipairs(q.preAll or {}) do if not s.completed[x] then missing[#missing + 1] = x end end
    local any = #(q.preAny or {}) == 0
    for _, x in ipairs(q.preAny or {}) do if s.completed[x] then any = true end end
    if not any then for _, x in ipairs(q.preAny) do missing[#missing + 1] = 'oder ' .. x end end
    return missing
end

-- Game-faithful simulation. Like RoutePlan.Resolve, a block offers all of its applicable
-- steps at once; the player does whichever step is possible right now (pick up, objective,
-- turn in) until nothing moves. Steps left unsatisfied stall the route in game: they are
-- reported via onIssue('STALL', ...) and then force-skipped so the walk can continue.
-- Events: onIssue(kind, node, quest, detail, ctx) and onStep(node, quest, ctx).
-- Forever's quest log holds 40 quests. Routes are planned for at most QUESTLOG_PLAN active quests (reserve for drop quests, hints, class quests).
L.QUESTLOG_LIMIT = tonumber(os.getenv('FDQ_QUESTLOG_LIMIT')) or 40
L.QUESTLOG_PLAN = tonumber(os.getenv('FDQ_QUESTLOG_PLAN')) or 32
function L.Simulate(ns, profile, mode, opts)
    opts = opts or {}
    local factor = opts.factor or L.FACTOR
    local state = L.State(profile, mode)
    -- opts.group: simulate a party of five (group quests become part of the route).
    if opts.group then state.group, state.partySize = true, 5 end
    -- opts.resume: continue a character from a previous run (route stage switch).
    local resume = opts.resume
    if resume then
        state.level = resume.level
        for _, k in ipairs({'completed', 'active', 'ready'}) do
            for id, v in pairs(resume.state[k] or {}) do state[k][id] = v end
        end
    end
    local db = {}
    local plan = ns.RoutePlan.Find(state, nil)
    if not plan then return nil end
    local xp, level = resume and resume.xp or 0, resume and resume.level or 1
    local F = opts.model ~= false and L.Features(ns, profile, mode, opts) or nil
    local Mo = L.MODEL
    local pool = 0 -- rested XP from the camp tent
    local function gain(a)
        xp = xp + a
        while level < L.MAXL and xp >= L.XPL[level] do
            xp = xp - L.XPL[level]; level = level + 1
            -- One camp per level (about an hour at 12-30): the tent only refills an empty pool.
            if F and F.tent and level >= Mo.tentFrom and pool <= 0 then pool = Mo.tent * L.XPL[level] end
        end
    end
    local function killMult()
        if not F then return 1 end
        return 1 + (F.food and level >= Mo.foodFrom and Mo.food * Mo.foodUptime or 0)
                 + (F.bag and level >= Mo.bagFrom and Mo.bag * Mo.bagUptime or 0)
    end
    local run = {chain = {}, grind = 0, planned = 0, state = state, forced = {}, grindLog = {}, counts = {},
        grindSeconds = 0, ranDungeons = {},
        sources = {quests = 0, kills = 0, dungeonRuns = 0, professionQuests = 0, classQuests = 0, buffs = 0, rested = 0}}
    -- Kill XP with food/sleeping-bag buffs; rested XP doubles kill XP until the pool is used up.
    local function gainKills(base, bucket)
        if base <= 0 then return end
        local mult = killMult()
        local rested = math.min(pool, base * mult)
        pool = pool - rested
        run.sources[bucket or 'kills'] = run.sources[bucket or 'kills'] + base
        run.sources.buffs = run.sources.buffs + base * (mult - 1)
        run.sources.rested = run.sources.rested + rested
        gain(base * mult + rested)
    end
    local function grindRate() return L.MobXP(level) * killMult() / Mo.grindSeconds end
    local function grindTo(target)
        local need = -xp
        for l = level, target - 1 do need = need + L.XPL[l] end
        if need > 0 then run.grindSeconds = run.grindSeconds + need / grindRate(); gain(need) end
        return math.max(0, need)
    end
    -- One dungeon run: elite kills, group share and Forever's lower dungeon kill XP.
    local function runDungeon(d)
        if not (F and F.dungeonRuns) or not d or run.ranDungeons[d] then return end
        run.ranDungeons[d] = level
        gainKills((L.DUNGEON_KILLS[d] or 80) * Mo.elite * Mo.groupShare * L.MobXP(level) * Mo.dungeonMob, 'dungeonRuns')
    end
    -- Objective counts from the route (RXP comments), used where the quest data has none.
    do
        local pl, seen = plan, {}
        while pl and not seen[pl] do
            seen[pl] = true
            for _, b in ipairs(pl.blocks or {}) do for _, n in ipairs(b.nodes or {}) do
                if n.count and n.objectiveIndex then
                    run.counts[n.id] = run.counts[n.id] or {}
                    run.counts[n.id][n.objectiveIndex] = {count = n.count, kill = n.kill}
                end
            end end
            pl = pl.nextPlan and ns.RoutePlan.ByID(pl.nextPlan)
        end
    end
    -- Side content the package guides to (Balanced/Vollständig): camping chain + Camping 101 for
    -- the class's professions, class quests whose giver lies on the route (ClassQuestRoute rules).
    local classCands, campDone, routeIds = {}, {}, {}
    if F and F.classQuests and ns.ClassQuestRoute then
        local pts = {}
        local pl, seen = plan, {}
        while pl and not seen[pl] do
            seen[pl] = true
            for _, b in ipairs(pl.blocks or {}) do for _, n in ipairs(L.BlockNodes(b)) do
                routeIds[n.id] = true
                local q = ns.DataProvider.GetQuest(n.id)
                for _, pt in ipairs({q and q.g or false, q and q.r or false}) do
                    if pt and pt[4] then pts[pt[4]] = pts[pt[4]] or {}; table.insert(pts[pt[4]], pt) end
                end
            end end
            pl = pl.nextPlan and ns.RoutePlan.ByID(pl.nextPlan)
        end
        for _, e in ipairs(ns.ClassQuestRoute.List(L.State(profile, mode))) do
            local ok = e.tier == 'pflicht' or e.tier == 'empfohlen' or (F.classQuests == 'completion' and e.tier == 'optional')
            local g = e.q.g
            if ok and not routeIds[e.id] and g and g[4] and pts[g[4]] then
                for _, pt in ipairs(pts[g[4]]) do
                    if math.sqrt((pt[1] - g[1]) ^ 2 + (pt[2] - g[2]) ^ 2) <= 6 then classCands[#classCands + 1] = e; break end
                end
            end
        end
        table.sort(classCands, function(a, b) return (a.q.level or 0) < (b.q.level or 0) end)
    end
    local function sideContent()
        if not F then return end
        if F.professionQuests then
            local function done(name)
                for id in pairs(state.completed) do local q = ns.DataProvider.GetQuest(id); if q and q.name == name then return true end end
            end
            local function camp(key, xp, minLevel)
                if campDone[key] or level < minLevel then return end
                campDone[key] = true
                if done(key) then return end
                local x = L.QuestXP({xp = xp, level = 6}, level) * factor
                run.sources.professionQuests = run.sources.professionQuests + x
                gain(x)
            end
            camp('The Adventurer', Mo.campXP.adventurer, 6)
            camp('The Great Outdoors', Mo.campXP.outdoors, 6)
            local profs = {[185] = true, [129] = true}
            for id in pairs(F.professions) do profs[id] = true end
            for id in pairs(profs) do if PROF_NAME[id] then camp('Camping 101: ' .. PROF_NAME[id], Mo.campXP.camping101, 9) end end
        end
        for _, e in ipairs(classCands) do
            local q = e.q
            local excluded = false
            for _, x in ipairs(q.exclusive or {}) do if state.completed[x] or state.active[x] or routeIds[x] then excluded = true end end
            if not excluded and not state.completed[e.id] and not state.active[e.id] and level >= (q.minLevel or 1) and (q.level or 1) <= level + 1
                and #L.MissingPrereqs(q, state) == 0 and L.Available(ns, q, profile) then
                state.completed[e.id] = true
                local x = L.QuestXP(q, level) * factor
                run.sources.classQuests = run.sources.classQuests + x
                gain(x)
                gainKills(L.KillsFor(q, run.counts) * L.MobXP(level) * factor, 'classQuests')
            end
        end
    end
    local issue = opts.onIssue or function() end
    if resume then ns.RoutePlan.PrepareLevelResume(plan, state, db) end
    local visited, p = {}, plan
    while p and not visited[p.id] do
        visited[p.id] = true
        run.chain[#run.chain + 1] = p
        local ctx = {plan = p, state = state}
        if p.minLevel and level < p.minLevel then
            local at = level + xp / L.XPL[level]
            local need = grindTo(p.minLevel)
            run.grind = run.grind + need
            run.grindLog[#run.grindLog + 1] = {kind = 'gap', level = math.floor(at), xp = need}
            issue('LEVEL_GAP', nil, nil, string.format('%s: L%.1f → L%d, %d XP', p.id, at, p.minLevel, need), ctx)
        end
        for bi, block in ipairs(p.blocks or {}) do
            -- opts.stopAtLevel: end the run when the character reaches that level (first route stage).
            if opts.stopAtLevel and level >= opts.stopAtLevel then run.stopped = true; break end
            ctx.block, ctx.blockIndex = block, bi
            run.blockLevel = run.blockLevel or {}
            run.blockLevel[block.id] = level
            local list = L.BlockNodes(block)
            local blocked = {}
            local progress = true
            local function repair()
                -- A turn-in whose quest is in the log but has no objective step in the route:
                -- the player does the objective in passing, the route just never points there.
                for _, n in ipairs(list) do
                    if n.id and n.phase == 'TURNIN' and not run.forced[n] and state.active[n.id] and not state.ready[n.id] then
                        local q = ns.DataProvider.GetQuest(n.id)
                        issue(ns.RoutePlan.NodeSatisfied(n,state,db)and 'SIDE_OBJECTIVE' or 'NO_OBJECTIVE_STEP', n, q, nil, ctx)
                        state.ready[n.id] = true
                        if q and q.dungeon then runDungeon(q.dungeon) end
                        return true
                    end
                end
                return false
            end
            while progress do
                progress = false
                blocked = {}
                for _, authored in ipairs(list) do
                    local n=ns.RoutePlan.EffectiveNode(authored,block,state)
                    state.level = level
                    local pending = not ns.RoutePlan.NodeSatisfied(n, state, db)
                    -- Parallel (#completewith/#optional) steps are shown and done in passing.
                    local side = not pending and n.parallel and not n.groupPart and ns.RoutePlan.Conditions(n.conditions, state)
                        and not ns.RoutePlan.PhaseDone(n, state) and not (ns.RoutePlan.Opportunistic and ns.RoutePlan.Opportunistic(n, state))
                    if n.id and not blocked[n] and not run.forced[n] and (pending or side)
                        and not (F and F.skipDungeonQuests and n.kind == 'DUNGEON_QUEST')
                        and ns.RoutePlan.PhaseMatches(n, state) then
                        local q = ns.DataProvider.GetQuest(n.id)
                        ctx.level = level
                        if not q then blocked[n] = 'Quest fehlt in den Daten'
                        elseif n.phase == 'PICKUP' then
                            local missing = L.MissingPrereqs(q, state)
                            if not L.Available(ns, q, profile) then blocked[n] = 'für dieses Profil nicht verfügbar'
                            elseif #missing > 0 then blocked[n] = 'Vorquest fehlt: ' .. table.concat(missing, ', ')
                            elseif side and (q.minLevel or 1) > level then blocked[n] = 'nebenbei, Level zu niedrig'
                            else
                                if (q.minLevel or 1) > level then
                                    local at = level
                                    local need = grindTo(q.minLevel)
                                    run.grind = run.grind + need
                                    run.grindLog[#run.grindLog + 1] = {kind = 'minlevel', level = at, xp = need, block = block.id, plan = p.id, quest = n.id, minLevel = q.minLevel}
                                    issue('TOO_LOW', n, q, string.format('Mindestlevel %d, Route bei L%d (+%d XP)', q.minLevel, ctx.level, need), ctx)
                                end
                                for _, x in ipairs(q.exclusive or {}) do
                                    if state.completed[x] or state.active[x] then issue('EXCLUSIVE', n, q, 'schließt ' .. x .. ' aus', ctx) end
                                end
                                if opts.onStep then opts.onStep(n, q, ctx) end
                                state.active[n.id] = true; progress = true
                                -- Quest log capacity (Forever: 20 quests): report the peak and every pickup above the limit.
                                local count = 0
                                for id in pairs(state.active) do if not (opts.logIgnore and opts.logIgnore[id]) then count = count + 1 end end
                                if count > (run.maxActive or 0) then run.maxActive = count end
                                if count > L.QUESTLOG_LIMIT then issue('LOG_FULL', n, q, string.format('%d aktive Quests (Limit %d)', count, L.QUESTLOG_LIMIT), ctx) end
                                -- Delivery/talk-to quests have no objectives: completable at once.
                                if #(q.objectives or {}) == 0 then state.ready[n.id] = true end
                            end
                        elseif n.phase == 'OBJECTIVE' then
                            if opts.onStep then opts.onStep(n, q, ctx) end
                            if n.recoveredObjective then issue('RECOVERED_OBJECTIVE',n,q,nil,ctx) end
                            state.ready[n.id] = true; progress = true
                            if F and F.dungeonRuns and q.dungeon then runDungeon(q.dungeon)
                            elseif F then gainKills(L.KillsFor(q, run.counts) * L.MobXP(level) * factor)
                            else gain(L.KillsFor(q, run.counts) * L.MobXP(level) * factor) end
                        else -- TURNIN or phase-less node
                            if opts.onStep then opts.onStep(n, q, ctx) end
                            local qx = L.QuestXP(q, level) * factor
                            run.sources.quests = run.sources.quests + qx
                            gain(qx)
                            state.completed[n.id] = true; state.active[n.id] = nil; state.ready[n.id] = nil; progress = true
                        end
                    end
                end
                if not progress then progress = repair() end
            end
            sideContent()
            local cp = block.checkpoint
            if cp and cp.enforceLevel and cp.expectedLevel and level < cp.expectedLevel then
                local at = level
                local need = grindTo(cp.expectedLevel)
                run.planned = (run.planned or 0) + need
                run.grindLog[#run.grindLog + 1] = {kind = 'planned', level = at, xp = need, block = block.id, plan = p.id, target = cp.expectedLevel}
            end
            for _, n in ipairs(list) do
                state.level = level
                if n.id and not run.forced[n] and not ns.RoutePlan.NodeSatisfied(n, state, db) then
                    local q = ns.DataProvider.GetQuest(n.id)
                    local why = blocked[n]
                    if not why then
                        if (n.phase == 'OBJECTIVE' or n.phase == 'TURNIN') and not state.active[n.id] then why = 'keine Annahme im Abschnitt'
                        elseif n.phase == 'PICKUP' and state.completed[n.id] then why = 'bereits abgegeben'
                        else why = 'Phase passt nicht (' .. tostring(n.phase) .. ')' end
                    end
                    issue('STALL', n, q, why, ctx)
                    -- Mimic a manual skip of this step so later steps can still be checked.
                    run.forced[n] = true
                end
            end
        end
        if run.stopped then break end
        p = p.nextPlan and ns.RoutePlan.ByID(p.nextPlan)
    end
    run.level, run.xp = level, xp
    run.endLevel = level + xp / L.XPL[level]
    local missing = -xp
    for l = level, L.MAXL - 1 do missing = missing + L.XPL[l] end
    run.toThirty = math.max(0, missing)
    run.grindSeconds = run.grindSeconds + run.toThirty / grindRate()
    return run
end

-- Walks the plan chain from level 1. visit(event) is called per applicable node with
-- {plan, block, node, quest, state, level}. Quest/kill XP advance the level with the
-- given incidental factor; plan minLevel gaps are reported through onGap.
function L.Walk(ns, profile, mode, opts)
    opts = opts or {}
    local factor = opts.factor or L.FACTOR
    local state = L.State(profile, mode)
    local plan = ns.RoutePlan.Find(state, nil)
    if not plan then return nil end
    local xp, level = 0, 1
    local function gain(a)
        xp = xp + a
        while level < L.MAXL and xp >= L.XPL[level] do xp = xp - L.XPL[level]; level = level + 1 end
    end
    local run = {chain = {}, grind = 0, state = state}
    local visited, p = {}, plan
    while p and not visited[p.id] do
        visited[p.id] = true
        run.chain[#run.chain + 1] = p
        if p.minLevel and level < p.minLevel then
            local need = -xp
            for l = level, p.minLevel - 1 do need = need + L.XPL[l] end
            run.grind = run.grind + need
            if opts.onGap then opts.onGap(p, level + xp / L.XPL[level], need) end
            gain(need)
        end
        for _, block in ipairs(p.blocks or {}) do
            for _, n in ipairs(L.BlockNodes(block)) do
                state.level = level
                if n.id and ns.RoutePlan.Conditions(n.conditions, state) and not ns.ModePolicy.Excluded(n, state) then
                    local q = ns.DataProvider.GetQuest(n.id)
                    if opts.visit then opts.visit({plan = p, block = block, node = n, quest = q, state = state, level = level}) end
                    local ph = n.phase or 'QUEST'
                    if ph == 'PICKUP' then
                        if not state.completed[n.id] then state.active[n.id] = true end
                    elseif ph == 'OBJECTIVE' then
                        if q and state.active[n.id] and not state.ready[n.id] then
                            state.ready[n.id] = true
                            for _, o in ipairs(q.objectives or {}) do
                                if o.kind == 'KILL' and type(o.count) == 'number' then gain(o.count * L.MobXP(level) * factor) end
                            end
                        end
                    elseif q and not state.completed[n.id] and (state.active[n.id] or not opts.strict) then
                        local g = L.QuestXP(q, level)
                        gain(g * factor)
                        state.completed[n.id] = true; state.active[n.id] = nil; state.ready[n.id] = nil
                    end
                end
            end
        end
        p = p.nextPlan and ns.RoutePlan.ByID(p.nextPlan)
    end
    run.endLevel = level + xp / L.XPL[level]
    local missing = -xp
    for l = level, L.MAXL - 1 do missing = missing + L.XPL[l] end
    run.grind = run.grind + math.max(0, missing)
    return run
end

return L

