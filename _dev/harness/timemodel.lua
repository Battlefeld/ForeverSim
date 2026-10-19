-- Time estimate of a simulated route from level `fromLevel` on: conversation, kills, walking inside a zone,
-- trips between zones and the planned/forced grinding of the simulator. A model for comparing routes under the
-- same assumptions, not a measured play time. Constants are scenario parameters (see T.scenarios).
local T = {}

T.scenarios = {
    schnell = {talk = 20, kill = 18, walk = 4, zone = 150, continent = 360},
    normal = {talk = 25, kill = 22.5, walk = 5, zone = 180, continent = 420},
    langsam = {talk = 35, kill = 30, walk = 6.5, zone = 240, continent = 540},
}

-- tripSeconds(zoneA, zoneB) -> seconds or nil (same zone); objectivePoint(q) -> {x, y, zone}
function T.collector(ns, L, tripSeconds, objectivePoint, scenario, fromLevel)
    local S = T.scenarios[scenario or 'normal']
    local c = {talk = 0, kills = 0, walk = 0, trips = 0, last = nil, zoneChanges = 0, quests = 0}
    function c.onStep(n, q, ctx)
        if (ctx.level or 0) < (fromLevel or 30) or not q then return end
        local pt
        if n.phase == 'PICKUP' then pt = q.g
        elseif n.phase == 'TURNIN' then pt = q.r
        else pt = objectivePoint(q) end
        if n.phase == 'PICKUP' then c.talk = c.talk + S.talk; c.quests = c.quests + 1
        elseif n.phase == 'TURNIN' then c.talk = c.talk + S.talk
        else
            local kills = n.count or L.KillsFor(q, {})
            c.kills = c.kills + (kills or 0) * S.kill
        end
        if pt and pt[1] and pt[4] then
            local last = c.last
            if last then
                if last[4] == pt[4] then
                    c.walk = c.walk + math.sqrt((last[1] - pt[1]) ^ 2 + (last[2] - pt[2]) ^ 2) * S.walk
                else
                    c.trips = c.trips + (tripSeconds(last[4], pt[4]) and (tripSeconds(last[4], pt[4]) == 180 and S.zone or S.continent) or S.zone)
                    c.zoneChanges = c.zoneChanges + 1
                end
            end
            c.last = pt
        end
    end
    -- Totals in minutes; grindSeconds from the simulator (only the part after fromLevel is meaningful when
    -- the 1-30 part has none, which holds for the shipped packages).
    function c.result(run)
        local grind = (run and run.grindSeconds or 0)
        local total = c.talk + c.kills + c.walk + c.trips + grind
        return {total = total / 60, talk = c.talk / 60, kills = c.kills / 60, walk = c.walk / 60, trips = c.trips / 60, grind = grind / 60,
            zoneChanges = c.zoneChanges, quests = c.quests}
    end
    return c
end

return T
