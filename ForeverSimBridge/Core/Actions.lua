-- User actions share one preflight, queue and result state with slash commands.
local P = FUSLive
local A = {}
P.actions = A

local function errorResult(code, message)
    local detail = tostring(message or 'Daten nicht verfügbar')
    local display = detail
    if detail:find('%.lua:%d+:') or detail:find('Interface/AddOns', 1, true) or detail:find('stack traceback', 1, true) then
        display = 'Berechnung fehlgeschlagen. Technische Details stehen in der Diagnose.'
        if P.app then P.app.state.lastTechnicalError = detail end
    end
    return {code = code, message = display, detail = detail}
end

function A.Context()
    if InCombatLockdown and InCombatLockdown() then
        return nil, errorResult('IN_COMBAT', 'Nach dem Kampf erneut berechnen.')
    end
    local ok, snapshot = pcall(P.capture, true)
    if not ok or not snapshot then
        return nil, errorResult('SNAPSHOT_UNAVAILABLE', ok and 'Charakterdaten fehlen.' or snapshot)
    end
    local normalized, profile = pcall(P.normalizeSnapshot, snapshot)
    if not normalized or not profile then
        return nil, errorResult('PROFILE_INVALID', profile)
    end
    local issue = P.simulationIssue and P.simulationIssue(profile)
    if issue then return nil, errorResult('TALENTS_INCOMPLETE', issue) end
    local model = FUSLiveData and FUSLiveData[profile.class]
    if not model then return nil, errorResult('CLASS_UNAVAILABLE', 'Klassenmodell fehlt.') end
    issue = P.coverage(model, profile)
    if issue then return nil, errorResult('MODEL_INCOMPLETE', issue) end
    local stats, gearIssue
    if P.tryCombine then
        stats, gearIssue = P.tryCombine(profile.equipped or {})
    else
        local success, result = pcall(P.combine, profile.equipped or {})
        if success then stats = result else gearIssue = errorResult('GEAR_INCOMPLETE', result) end
    end
    if not stats then return nil, gearIssue end
    if P.app then
        P.app.state.character = {snapshot = snapshot, profile = profile, status = 'ready'}
    end
    return {model = model, profile = profile, stats = stats, revision = P.revision}
end

local function begin(route, kind)
    local app = P.app
    if not app then return end
    app.Open(route, kind == 'leveling' and 'leveling' or nil)
    if app.state.simulation.status == 'running' and app.state.simulation.revision ~= P.revision then
        app.state.simulation.status = 'cancelled'
    end
    if app.state.simulation.status == 'running' then
        app.state.notice = 'Eine Berechnung läuft bereits. Ergebnis abwarten oder abbrechen.'
        app.Refresh()
        return
    end
    local context, issue = A.Context()
    if not context then
        app.state.simulation = {status = 'error', kind = kind, error = issue}
        app.Refresh()
        return
    end
    app.state.nextRun = app.state.nextRun + 1
    local run = {status = 'running', kind = kind, runId = app.state.nextRun,
                 revision = context.revision, phase = 'Vorbereitung'}
    app.state.simulation = run
    app.state.notice = nil
    app.Refresh()
    return context, run
end

local function valid(run)
    return P.app.state.simulation == run and run.status == 'running' and run.revision == P.revision
end

local function finish(run, result, issue)
    if not valid(run) then
        if P.app.state.simulation==run and run.status=='running' then run.status='cancelled';run.phase='Kontext geändert – erneut berechnen.';P.app.Refresh()end
        return
    end
    if issue or not result then
        run.status = 'error'
        run.error = type(issue) == 'table' and issue or errorResult('SIM_FAILED', issue or 'Kein Ergebnis.')
    else
        run.status = 'complete'
        run.result = result
        run.completed = date and date('%H:%M') or ''
        P.app.state[run.kind] = {result = result, revision = run.revision}
    end
    P.app.Refresh()
end

function A.RunRotation()
    local context, run = begin('rotation', 'rotation')
    if not context then return end
    ForeverSimBridgeDB.rotationGoal = 'dps'
    P.enqueue(function()
        local data, profile, stats = context.model, context.profile, context.stats
        run.phase = 'Startrotation und Kandidaten'
        local start = P.candidates(data, profile)[1]
        if not start then error('Keine gelernte Startrotation verfügbar.') end
        local searched = P.best(data, profile, stats, start)
        local candidates = {searched.choice}
        -- Order matters at every level (e.g. DoT before nuke); tune from the first sim level on.
        if profile.level >= P.minSimLevel() and P.tuneRotation then
            run.phase = 'Rotation verfeinern'
            local tuned = P.tuneRotation(data, profile, stats, searched.choice, {
                rounds = 1, finalists = 4, seeds = {31211, 48817, 81721},
                validationSeeds = {178651, 191789, 205279, 219103, 232369, 247301, 260849, 274073}
            })
            if tuned.accepted then candidates[#candidates + 1] = tuned.choice end
        end
        run.phase = 'Vergleich mit identischen Seeds'
        local difference, selected, baseline, seen = 0, P.copy(start), 0, {}
        for _, choice in ipairs(candidates) do
            local key = P.canonical(choice)
            if not seen[key] then
                seen[key] = true
                local comparison = P.paired(data, profile, stats, start, stats, choice, 12, 13)
                baseline = comparison.baselineDps
                if comparison.difference > difference then
                    difference, selected = comparison.difference, P.copy(choice)
                end
            end
        end
        if baseline == 0 then baseline = P.score(data, profile, stats, start, 12, 13) end
        return {choice = selected, baselineChoice = P.copy(start), dps = baseline + difference,
                baselineDps = baseline, percentOfStart = baseline > 0 and 100 * (baseline + difference) / baseline or 100,
                improvementPercent = baseline > 0 and 100 * difference / baseline or 0,
                accepted = difference > 0, candidatesTested = searched.candidatesTested,
                rotationRules = searched.rotationRules, profile = profile, class = profile.class, level = profile.level}
    end, function(result, issue)
        if not valid(run) then finish(run,nil,issue);return end
        finish(run, result, issue)
        if result and not issue then A.ApplyRotation() end
    end, function() return valid(run) end)
end

function A.ApplyRotation(baseline)
    local saved = P.app.state.rotation
    if not saved or saved.revision ~= P.revision then
        P.app.state.notice = 'Rotation zuerst mit dem aktuellen Charakter und Benchmark berechnen.'
        P.app.Refresh()
        return
    end
    local result = P.copy(saved.result)
    if baseline then
        result.choice, result.dps, result.percentOfStart = result.baselineChoice, result.baselineDps, 100
        result.accepted, result.improvementPercent = false, 0
    end
    P.lastRotation, P.stale = result, false
    ForeverSimBridgeDB.rotationResult = {choice = P.copy(result.choice), dps = result.dps,
        baselineDps = result.baselineDps, percentOfStart = result.percentOfStart, accepted = result.accepted}
    if P.rotationHUD then
        if P.rotationHUD.EnableSavedDisplay then P.rotationHUD.EnableSavedDisplay() end
        P.rotationHUD.configure(FUSLiveData[result.class], result.profile, result)
    end
    P.app.state.notice = baseline and 'Bisherige Rotation aktiv.' or 'Rotation bereit. Beim Angreifen erscheint dein Rotationsfeld automatisch.'
    P.app.Refresh()
end

function A.CompareItem(reference)
    local context, run = begin('gear', 'gear')
    if not context then return end
    if not reference or reference == '' then
        finish(run, nil, errorResult('ITEM_REQUIRED', 'Item-ID oder Gegenstandslink eingeben.'))
        return
    end
    local ref = tonumber(reference) or reference
    local ok, item = pcall(P.readItem, ref, 'Manueller Vergleich')
    if not ok or not item then
        if type(ref) == 'number' and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, ref)
        end
        finish(run, nil, errorResult('ITEM_UNAVAILABLE', ok and 'Itemdaten fehlen oder der Slot ist nicht bewertbar. Nach dem Laden erneut vergleichen.' or item))
        return
    end
    run.phase = 'Ausrüstung vergleichen'
    P.enqueue(function()
        local data, profile = context.model, context.profile
        return P.compare(data, profile, profile.equipped, item)
    end, function(result, issue) finish(run, result, issue) end, function() return valid(run) end)
end

function A.Cancel()
    local run = P.app.state.simulation
    if run.status == 'running' then
        run.status = 'cancelled'
        run.phase = 'Berechnung abgebrochen'
    end
    if P.cancelJobs then P.cancelJobs('Berechnung abgebrochen.') end
    P.app.state.notice = 'Berechnung abgebrochen.'
    P.app.Refresh()
end

function A.RunLeveling(autoApply)
    local context, run = begin('benchmark', 'leveling')
    if not context then return end
    local model, profile, gear = context.model, context.profile, context.stats
    local options = P.leveling.Context(profile)
    if not options.targetHealth then
        finish(run, nil, options.healthError or errorResult('TARGET_HEALTH_INVALID', 'HP-Modell oder manuelle Gegner-HP festlegen.'))
        return
    end
    P.enqueue(function()
        local start = P.lastRotation and not P.stale and P.lastRotation.choice or P.candidates(model, profile)[1]
        if not start then error('Keine gelernte Startrotation verfügbar.') end
        run.phase = 'Levelrotationen · ' .. tostring(options.source)
        local baseline = P.leveling.Evaluate(model, profile, gear, start, options)
        if not baseline.available then error(baseline.reason or 'Leveling-Kontext unvollständig.') end
        local best, seen = {choice = start, result = baseline}, {}
        local choices = {start}
        for _, choice in ipairs(P.candidates(model, profile)) do choices[#choices + 1] = choice end
        for _, choice in ipairs(choices) do
            local key = P.canonical(choice)
            if not seen[key] then
                seen[key] = true
                local result = P.leveling.Evaluate(model, profile, gear, choice, options)
                if result.killsPerMinute and (not best.result.killsPerMinute or result.killsPerMinute > best.result.killsPerMinute) then
                    best = {choice = P.copy(choice), result = result}
                end
            end
        end
        return {baseline = baseline, choice = best.choice, result = best.result,
                signature = P.combatAudit and P.combatAudit.Signature(profile), revision = context.revision}
    end, function(result, issue)
        if not valid(run) then return end
        if result and not issue then
            P.lastLeveling = result
            ForeverSimBridgeDB.leveling = ForeverSimBridgeDB.leveling or {}
            ForeverSimBridgeDB.leveling.result = P.copy(result)
        end
        finish(run, result, issue)
        if result and autoApply then P.leveling.Apply() end
    end, function() return valid(run) end)
end

