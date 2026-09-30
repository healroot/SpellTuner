-- The review commands: the validation report for one recording
-- (MD:ValidationReport), /md coachrun (MD:RunCoachRun) and /md coach
-- (MD:RunCoach).
--
-- T56 (P12, review A2): moved out of Verify.lua unchanged, into their final
-- home. On the TBC TOC only for now; P21 (docs/PLAN-refactor-ux.md) lists this
-- file on the Replay module too and retires the Forever copies in
-- Modules/SpellTuner_Replay/Commands_Forever.lua.
local _, MD = ...

--------------------------------------------------------------------------------
-- The validation report for one recording: whether the engine can reproduce the
-- fight, gate by gate, with each threshold's provenance. This is what the
-- Review tab's tooltip shows and what decides whether the Coach is allowed to
-- say anything at all about this pull.
--------------------------------------------------------------------------------
function MD:ValidationReport(rec, n)
    local v = MD.SimModel:Validate(rec)
    if not v then return { "simreplay: nothing to validate." } end
    local out = {
        string.format("recording %s: %s, %.0fs, %d casts, %d mana%s", tostring(n or 1),
            rec.zone or "?", rec.dur or 0, rec.ownCasts or 0, rec.spent or 0,
            rec.truncated and " (stream truncated)" or ""),
        string.format("  verdict: %s", v.ok and "REPLAYS - safe to coach from"
            or "does NOT replay - nothing will be suggested from this fight"),
    }
    for _, g in ipairs(v.gates) do
        out[#out + 1] = string.format("  %-18s %-4s %s", g.name, g.ok and "ok" or "FAIL", g.text)
    end
    if (v.energize or 0) > 0 then
        out[#out + 1] = string.format("  energize: %.2f/s (%d mp5) the API does not report%s",
            v.energize, v.energize * 5 + 0.5,
            v.energizeAssumed and " - ASSUMED: this recording predates the measurement, so the current one was applied"
                or " - recorded with the fight")
    end
    for i, why in pairs(v.excluded) do
        local name = rec.roster[i] and rec.roster[i].name or ("target " .. i)
        out[#out + 1] = string.format("  excluded: %s - %s", name, why)
    end
    for _, g in ipairs(v.gates) do
        if not g.ok and g.why then
            out[#out + 1] = string.format("  why %s is %s: %s", g.name,
                g.limit and string.format("%.2f", g.limit) or "set where it is", g.why)
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- /md coachrun [n]: the whole run through the engine (docs/SPEC-v0.9.md 5).
-- The same search as /md coach, one plan for the dungeon, scored on time before
-- mana -- because in a five-man mana is only worth the time it saves.
--------------------------------------------------------------------------------
function MD:RunCoachRun(arg)
    if not (MD.SimPlanner and MD.RunRecorder) then MD:Print("coachrun: not loaded.") return end
    arg = tostring(arg or ""):gsub("%s+", "")
    if arg == "cancel" then
        if MD.runSearch then MD.runSearch:Cancel(); MD.runSearch = nil
        else MD:Print("coachrun: nothing running.") end
        return
    end
    -- "/md coachrun 2 force": coach every pull, the ones that do not replay
    -- included. Same escape hatch a single fight has had since v0.9.6.
    local force = arg:find("force") ~= nil
    arg = arg:gsub("force", "")
    local n = tonumber(arg) or 1
    local run = MD.RunRecorder:Get(n)
    if not run then
        MD:Print("coachrun: no run " .. n .. " (/md run status lists them).")
        return
    end
    if MD.runSearch then MD:Print("coachrun: already searching (/md coachrun cancel).") return end
    if not MD.player.isDruid then MD:Print("coachrun: coaching is Druid-only in v1.") return end
    MD:Print(string.format("coachrun: %s - %d pull(s) through the engine, this may take a moment.",
        run.name or "?", #(run.pulls or {})))
    if force then MD:Print("coachrun: FORCED - pulls that do not replay are coached too.") end
    MD.runSearch = MD.SimPlanner.CoachRun(run, { force = force }, function(lines)
        MD.runSearch = nil
        if MD.ShowCopyPopup and #lines > 6 then
            MD:ShowCopyPopup("SpellTuner coach: " .. (run.name or "run"), table.concat(lines, "\n"))
        end
        for _, line in ipairs(lines) do
            MD:Print(line)
            MD:Debug("sim", "coachrun %s", line)
        end
    end)
end

--------------------------------------------------------------------------------
-- /md coach [n] [force]
--------------------------------------------------------------------------------
function MD:RunCoach(arg)
    if not (MD.SimPlanner and MD.FightRecorder) then MD:Print("coach: not loaded.") return end
    arg = arg or ""
    if arg == "cancel" then
        if MD.coachSearch then MD.coachSearch:Cancel(); MD.coachSearch = nil
        else MD:Print("coach: nothing running.") end
        return
    end
    -- "2" is a single fight, "2:7" the seventh pull of the second run
    -- "p2" is the second practice fight (v0.15.0)
    local n, rest = arg:match("^([pP]?[%d:]*)%s*(%a*)$")   -- "3", "3 force", "3 health", "p1"
    if not n or n == "" then n = "1" end
    local rec, label = MD:GetRecording(n)
    if not rec then MD:Print("coach: no recording " .. tostring(n) .. ".") return end
    n = label

    -- /md coach 3 health: pick one of the strategies the last search on this
    -- fight produced, without searching again (v0.10.4)
    local SP = MD.SimPlanner
    for _, obj in ipairs(SP.OBJECTIVES or {}) do
        if rest == obj.key then
            local w = SP.strategies[rec.id] and SP.strategies[rec.id][obj.key]
            if not w then
                MD:Print(string.format("coach: no strategies for recording %s yet - run |cffffff00/md coach %s|r first.",
                    tostring(n), tostring(n)))
                return
            end
            SP.plans[rec.id] = w.plan
            MD:Print(string.format("coach: |cff33ff66%s|r is now the plan the replay draws for recording %s - %s.",
                obj.name, tostring(n), obj.what))
            MD:Print(string.format("  %d mana used (and owed), floor %d%%, %.1fs in danger.",
                SP.ManaUsed(w.result) + SP.ManaOwed(w.result, w.plan) + 0.5,
                (w.result.lowest and w.result.lowest.hp or 1) * 100 + 0.5, w.result.floorSeconds or 0))
            return
        end
    end
    -- v0.13.9: an auto-coach kicked off by opening the replay must not block the
    -- author asking for one. Theirs wins: cancel ours and run it.
    if MD.coachSearch and MD.replayCoaching then
        MD.coachSearch:Cancel()
        MD.coachSearch, MD.replayCoaching = nil, nil
    end
    if MD.coachSearch then MD:Print("coach: already searching (/md coach cancel).") return end

    local function Show(lines)
        MD.coachSearch = nil
        if MD.ShowCopyPopup and #lines > 6 then
            MD:ShowCopyPopup("SpellTuner coach: recording " .. tostring(n), table.concat(lines, "\n"))
        end
        for _, line in ipairs(lines) do
            MD:Print(line)
            MD:Debug("sim", "coach %s", line)
        end
    end
    MD.coachSearch = MD.SimPlanner.CoachAsync(rec, { n = n, force = (rest == "force") }, Show)
end
