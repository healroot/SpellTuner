-- The review commands, both lines: the validation report for one recording
-- (MD:ValidationReport), /md coach (MD:RunCoach), /md coachrun
-- (MD:RunCoachRun) and, on Forever, /st validate.
--
-- T56 (P12, review A2): moved out of Verify.lua unchanged, into their final
-- home. T65 (P21, review A1): listed by the TBC TOC and by the Replay
-- module's TOCs, replacing the second implementation that lived in
-- Modules/SpellTuner_Replay/Commands_Forever.lua. Where the two differed, the
-- one below is what both lines do now:
--   * every line printed goes through MD:PrintSafe (Core.lua's
--     EscKeepColours: ASCII, no bare pipe, the card's own colour codes kept) --
--     TBC printed raw, so a zone, name or spell with a pipe, a backslash or a
--     non-ASCII byte now prints escaped there too (docs/DECISIONS.md);
--   * the energize line is printed when the validation carries one (a v3
--     validation never does);
--   * the header's casts and mana are rec.ownCasts / rec.spent, else counted
--     from a v3 stream's own casts (a recording that predates the counters);
--   * a hint names the line's own slash command (the policy's, below);
--   * an argument the coach address cannot read is refused (B16) -- on TBC too;
--   * a card over six lines opens the copy box only where the policy says so
--     (TBC), and coachrun is a verb only where runs are recorded.
-- A verb the flavour core already registered (TBC's coach and coachrun, in
-- Core_TBC.lua) keeps its row; this file registers only the ones it has not,
-- so neither line's /help moves.
local _, MD = ...

local RC = {}
MD.ReviewCommands = RC

-- The review POLICY (the T59 pattern, Engine/Practice.lua): what differs
-- between the two lines is installed by the flavour, never asked of the
-- client in this shared file.
--   copyBox     a card over six lines also opens the copy box (TBC's since
--               v0.7; Forever prints the card to chat only);
--   reportVerb  the verb that prints the validation report and names it when
--               there is nothing to validate: TBC's is /md simreplay N
--               (Engine/SimSelfTest.lua), Forever's is /st validate N,
--               registered below;
--   slash       the line's own slash command, for hints ("/md coach 1
--               force") -- MD.SLASH wins when a core sets one.
-- The TBC value below is the default. Commands_Forever.lua provides
-- MD.ReviewPolicy before this file runs (the Replay module's TOCs list it
-- first), and that replaces it.
RC.TBC_POLICY = { copyBox = true, reportVerb = "simreplay", slash = "/md" }
RC.policy = MD.ReviewPolicy or RC.TBC_POLICY

local function Slash()
    return MD.SLASH or RC.policy.slash or "/st"
end
RC.Slash = Slash

local function Say(line)
    MD:PrintSafe(line)
end

-- The v3 stream's own OWNCAST kind (Modules/SpellTuner_Recorder/
-- Recorder_Forever.lua's local K, Scenario_Forever.lua's local V3) --
-- duplicated here for the same reason those files give: nothing guarantees
-- one module can read another's locals. P22 publishes it once.
local V3_OWNCAST = 3

-- The header's casts and mana: the recorder's own counters when the
-- recording has them (TBC since v0.7, Forever since T13f), else counted from
-- a v3 stream. A v2 stream without them reads 0, as it always did.
local function CastsAndMana(rec)
    if rec.ownCasts ~= nil or rec.spent ~= nil then
        return rec.ownCasts or 0, rec.spent or 0
    end
    local casts, mana = 0, 0
    local ev = rec.ev
    if rec.v ~= 3 or type(ev) ~= "table" or type(ev.kind) ~= "table" then return casts, mana end
    for i = 1, rec.n or 0 do
        if ev.kind[i] == V3_OWNCAST then
            casts = casts + 1
            local amt = ev.amt and ev.amt[i]
            if amt and amt > 0 then mana = mana + amt end
        end
    end
    return casts, mana
end
RC.CastsAndMana = CastsAndMana

--------------------------------------------------------------------------------
-- The validation report for one recording: whether the engine can reproduce the
-- fight, gate by gate, with each threshold's provenance. This is what the
-- Review tab's tooltip shows and what decides whether the Coach is allowed to
-- say anything at all about this pull. SM:Validate dispatches a v3 stream to
-- the Replay module's own gates (Gates_Forever.lua). The lines are returned
-- raw: whoever prints them escapes them.
--------------------------------------------------------------------------------
function MD:ValidationReport(rec, n)
    local v = MD.SimModel:Validate(rec)
    if not v then return { RC.policy.reportVerb .. ": nothing to validate." } end
    local casts, mana = CastsAndMana(rec)
    local out = {
        string.format("recording %s: %s, %.0fs, %d casts, %d mana%s", tostring(n or 1),
            rec.zone or "?", rec.dur or 0, casts, mana,
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
    for i, why in pairs(v.excluded or {}) do
        local name = rec.roster and rec.roster[i] and rec.roster[i].name or ("target " .. i)
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

-- /st validate [n] (Forever's report verb; TBC's is /md simreplay n).
function MD:RunValidate(arg)
    if not MD.SimModel then Say("validate: not loaded.") return end
    local n = (arg and arg ~= "" and arg) or "1"
    local rec, label = MD:GetRecording(n)
    if not rec then Say("validate: no recording " .. tostring(n) .. ".") return end
    for _, line in ipairs(MD:ValidationReport(rec, label)) do Say(line) end
end

-- A finished card: chat, the debug log, and on TBC the copy box as well.
local function ShowCard(verb, title, lines)
    if RC.policy.copyBox and MD.ShowCopyPopup and #lines > 6 then
        MD:ShowCopyPopup(title, table.concat(lines, "\n"))
    end
    for _, line in ipairs(lines) do
        Say(line)
        MD:Debug("sim", "%s %s", verb, line)
    end
end

--------------------------------------------------------------------------------
-- /md coachrun [n]: the whole run through the engine (docs/SPEC-v0.9.md 5).
-- The same search as /md coach, one plan for the dungeon, scored on time before
-- mana -- because in a five-man mana is only worth the time it saves.
--------------------------------------------------------------------------------
function MD:RunCoachRun(arg)
    if not (MD.SimPlanner and MD.RunRecorder) then Say("coachrun: not loaded.") return end
    arg = tostring(arg or ""):gsub("%s+", "")
    if arg == "cancel" then
        if MD.runSearch then MD.runSearch:Cancel(); MD.runSearch = nil
        else Say("coachrun: nothing running.") end
        return
    end
    -- "/md coachrun 2 force": coach every pull, the ones that do not replay
    -- included. Same escape hatch a single fight has had since v0.9.6.
    local force = arg:find("force") ~= nil
    arg = arg:gsub("force", "")
    local n = tonumber(arg) or 1
    local run = MD.RunRecorder:Get(n)
    if not run then
        Say("coachrun: no run " .. n .. " (" .. Slash() .. " run status lists them).")
        return
    end
    if MD.runSearch then Say("coachrun: already searching (" .. Slash() .. " coachrun cancel).") return end
    if not MD.player.isDruid then Say("coachrun: coaching is Druid-only in v1.") return end
    Say(string.format("coachrun: %s - %d pull(s) through the engine, this may take a moment.",
        run.name or "?", #(run.pulls or {})))
    if force then Say("coachrun: FORCED - pulls that do not replay are coached too.") end
    MD.runSearch = MD.SimPlanner.CoachRun(run, { force = force }, function(lines)
        MD.runSearch = nil
        ShowCard("coachrun", "SpellTuner coach: " .. (run.name or "run"), lines)
    end)
end

--------------------------------------------------------------------------------
-- /md coach [n] [force, or safe / health / cheap / regen]
--------------------------------------------------------------------------------
function MD:RunCoach(arg)
    if not (MD.SimPlanner and MD.FightRecorder) then Say("coach: not loaded.") return end
    arg = arg or ""
    if arg == "cancel" then
        if MD.coachSearch then MD.coachSearch:Cancel(); MD.coachSearch = nil
        else Say("coach: nothing running.") end
        return
    end
    -- "2" is a single fight, "2:7" the seventh pull of the second run, "p2"
    -- the second practice fight (v0.15.0); "3 force" coaches one that failed
    -- its gates, "3 health" picks a strategy. B16 (T49 on Forever, T65 on
    -- both): an argument the pattern cannot read ("1 force now") is refused
    -- as an address the router cannot find is -- it used to mean recording 1.
    local n, rest = arg:match("^([pP]?[%d:]*)%s*(%a*)$")
    if not n then Say("coach: no recording " .. arg .. ".") return end
    if n == "" then n = "1" end
    local rec, label = MD:GetRecording(n)
    if not rec then Say("coach: no recording " .. tostring(n) .. ".") return end
    n = label

    -- /md coach 3 health: pick one of the strategies the last search on this
    -- fight produced, without searching again (v0.10.4)
    local SP = MD.SimPlanner
    for _, obj in ipairs(SP.OBJECTIVES or {}) do
        if rest == obj.key then
            local w = SP.strategies and SP.strategies[rec.id] and SP.strategies[rec.id][obj.key]
            if not w then
                Say(string.format("coach: no strategies for recording %s yet - run |cffffff00%s coach %s|r first.",
                    tostring(n), Slash(), tostring(n)))
                return
            end
            SP.plans[rec.id] = w.plan
            Say(string.format("coach: |cff33ff66%s|r is now the plan the replay draws for recording %s - %s.",
                obj.name, tostring(n), obj.what))
            local r = w.result or {}
            Say(string.format("  %d mana used (and owed), floor %d%%, %.1fs in danger.",
                math.floor(SP.ManaUsed(r) + SP.ManaOwed(r, w.plan) + 0.5),
                math.floor((r.lowest and r.lowest.hp or 1) * 100 + 0.5), r.floorSeconds or 0))
            return
        end
    end
    -- v0.13.9: an auto-coach kicked off by opening the replay must not block the
    -- author asking for one. Theirs wins: cancel ours and run it.
    if MD.coachSearch and MD.replayCoaching then
        MD.coachSearch:Cancel()
        MD.coachSearch, MD.replayCoaching = nil, nil
    end
    if MD.coachSearch then Say("coach: already searching (" .. Slash() .. " coach cancel).") return end

    MD.coachSearch = MD.SimPlanner.CoachAsync(rec, { n = n, force = (rest == "force") }, function(lines)
        MD.coachSearch = nil
        ShowCard("coach", "SpellTuner coach: recording " .. tostring(n), lines)
    end)
end

--------------------------------------------------------------------------------
-- The verbs the flavour core has not registered itself. TBC's core registers
-- coach and coachrun with its own rows (Core_TBC.lua) and names simreplay as
-- its report verb, so on TBC nothing below is added; on Forever validate and
-- coach are, with the rows Commands_Forever.lua gave them.
--------------------------------------------------------------------------------
local function Registered(name)
    for _, c in ipairs(MD:Commands()) do
        if c.name == name then return true end
        for _, a in ipairs(c.aliases or {}) do if a == name then return true end end
    end
    return false
end

if RC.policy.reportVerb == "validate" and not Registered("validate") then
    MD:AddCommand("validate", function(arg)
        if MD.RunValidate then MD:RunValidate(arg) end
    end, Slash() .. " validate [n]", "check whether recording n replays through the engine, gate by gate")
end

if not Registered("coach") then
    MD:AddCommand("coach", function(arg)
        if MD.RunCoach then MD:RunCoach(arg) end
    end, Slash() .. " coach [n] [force, or safe / health / cheap / regen]",
        "search for a better plan on recorded fight n and show the card (cancel stops it); a strategy name plays that one")
end

if MD.RunRecorder and not Registered("coachrun") then
    MD:AddCommand("coachrun", function(arg)
        if MD.RunCoachRun then MD:RunCoachRun(arg) end
    end, Slash() .. " coachrun [n]", "coach a recorded RUN: one plan and a drink policy for the whole dungeon")
end
