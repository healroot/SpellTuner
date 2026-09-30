-- T16a (docs/tasks/T16a-replay-window.md): the replay window's three
-- commands -- TBC's own syntax and help text (Core_TBC.lua), reimplemented
-- here rather than pulled from Verify.lua (TBC-only, not on this TOC) --
-- plus the settings the window and the engine read that Core_Forever.lua's
-- own MD.DEFAULTS never carried (InitDB already ran once by the time this
-- LoadOnDemand module loads, so FillDefaults never sees these keys). Set
-- only when absent, so an existing value or a later /st change is never
-- overwritten. Runs only once this module is on -- this file is that
-- module's own TOC entry.
local _, MD = ...

local REPLAY_DEFAULTS = {
    replaySpeed = 1, replayTicks = true, replayNextPull = true, replayAutoCoach = true,
    -- The sim* values Engine/SimModel.lua, Engine/SimPlanner.lua and
    -- Gates_Forever.lua already read with an inline `or default` fallback
    -- (Core_TBC.lua's own DEFAULTS, matched here for the settings pane, which
    -- reads MD.db directly with no such fallback of its own).
    simFullHp = 0.85, simFloor = 0.30, simDangerHits = 1, simReaction = 0.5, simMinActivity = 0,
    simGateManaMean = 0.02, simGateManaMax = 0.05, simGateHpMean = 0.05, simGateHpMax = 0.15,
    simForeignShare = 0.25, simAllowRebinds = false, simBigHit = 0.15,
}
for k, v in pairs(REPLAY_DEFAULTS) do
    if MD.db and MD.db[k] == nil then MD.db[k] = v end
end

-- The probe's own escaping (Client/Probe.lua's Esc, duplicated -- Rules): a
-- literal backslash doubled first, then a pipe as "||", then any non-ASCII/
-- control byte as "\ddd", so a printed line stays ASCII with no bare pipe
-- even when it carries a target or spell name straight from the client.
local function Esc(s)
    if type(s) ~= "string" then return s end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

local function Print(line)
    MD:Print(Esc(line))
end

-- review-replay R26: the coach card (Engine/SimPlanner.lua's SP.Card, shared
-- with TBC) carries its own colour codes ("|cff888888...|r"). Esc alone
-- doubles their pipes and chat shows them as literal text, so a card line is
-- split around each well-formed colour start ("|c" + eight hex digits) and
-- reset ("|r"), those are kept as they are, and everything between them is
-- escaped as before -- a name's own pipe still never reaches chat bare.
local function EscKeepColours(s)
    if type(s) ~= "string" then return s end
    local out, i = {}, 1
    while i <= #s do
        local a, b = s:find("|c%x%x%x%x%x%x%x%x", i)
        local c, d = s:find("|r", i, true)
        if c and (not a or c < a) then a, b = c, d end
        if not a then
            out[#out + 1] = Esc(s:sub(i))
            break
        end
        out[#out + 1] = Esc(s:sub(i, a - 1))
        out[#out + 1] = s:sub(a, b)
        i = b + 1
    end
    return table.concat(out)
end

local function PrintCard(line)
    MD:Print(EscKeepColours(line))
end

-- The v3 stream's own OWNCAST kind (Modules/SpellTuner_Recorder/
-- Recorder_Forever.lua's local K, Scenario_Forever.lua's local V3) --
-- duplicated here for the same reason those files give: nothing guarantees
-- one module can read another's locals.
local V3_OWNCAST = 3

local function CastsAndMana(rec)
    local casts, mana = 0, 0
    local ev, n = rec.ev or {}, rec.n or 0
    for i = 1, n do
        if ev.kind[i] == V3_OWNCAST then
            casts = casts + 1
            if (ev.amt[i] or 0) > 0 then mana = mana + ev.amt[i] end
        end
    end
    return casts, mana
end

--------------------------------------------------------------------------------
-- The validation report for one recording (Verify.lua's MD:ValidationReport,
-- reimplemented for Forever's own eight gates, SM:Validate already
-- dispatching a v3 stream to Gates_Forever.lua's SM:ValidateV3).
--------------------------------------------------------------------------------
local function ValidationReport(rec, n)
    local v = MD.SimModel:Validate(rec)
    if not v then return { "validate: nothing to validate." } end
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
MD.ValidationReportForever = ValidationReport -- read by tools/replayforever.lua
-- T16b: the Review tab's own Validate button (UI/Dashboard_Review.lua, shared
-- with TBC) calls `MD:ValidationReport(rec, n)` -- a COLON call, same as
-- Verify.lua's TBC one (Verify.lua:1299) -- so this has to be a method too:
-- `MD.ValidationReport = ValidationReport` (the plain, 2-argument local
-- above) would have taken the implicit `self` as `rec` and shifted `rec`
-- into `n`, and the misfed table sailed straight through as far as
-- `SM:Run` before it broke on a field only a real recording has. Not
-- wrapped in Esc here, same as the TBC one it mirrors: MD:Print goes
-- straight to chat on both clients, unescaped, on this call path today.
function MD:ValidationReport(rec, n)
    return ValidationReport(rec, n)
end

MD:AddCommand("replay", function(arg)
    if MD.ToggleReplay then MD:ToggleReplay(arg) end
end, "/st replay [n] [force]",
    "play recorded fight n as unit frames; force: draw the suggested column on a fight that does not replay")

MD:AddCommand("validate", function(arg)
    if not MD.SimModel then Print("validate: not loaded.") return end
    local n = (arg ~= "" and arg) or "1"
    local rec, label = MD:GetRecording(n)
    if not rec then Print("validate: no recording " .. tostring(n) .. ".") return end
    for _, line in ipairs(ValidationReport(rec, label)) do Print(line) end
end, "/st validate [n]", "check whether recording n replays through the engine, gate by gate")

-- T16b (UI/Dashboard_Review.lua, shared with TBC): the Review tab's Coach and
-- Coach pull buttons call `MD:RunCoach(arg)` the same way Core_TBC.lua's own
-- "coach" slash command does (`if MD.RunCoach then MD:RunCoach(arg) end`,
-- Core_TBC.lua:390) -- named the same on both clients so the shared pane
-- never needs to know which one it is on. `/st coach` is now this function;
-- Verify.lua's own `MD:RunCoach` (TBC, printing through a different Print)
-- is untouched.
function MD:RunCoach(arg)
    if not (MD.SimPlanner and MD.FightRecorder) then Print("coach: not loaded.") return end
    arg = arg or ""
    if arg == "cancel" then
        if MD.coachSearch then MD.coachSearch:Cancel(); MD.coachSearch = nil
        else Print("coach: nothing running.") end
        return
    end
    -- "3" is a single fight, "3 force" coaches one that failed its gates
    -- (Coach itself refuses without it), "3 health" picks a strategy.
    -- T49 (P5), B16: "2:7" (a run's pull) is an address too, and an argument
    -- the pattern cannot read is refused as /st validate refuses one -- it
    -- used to fall through to recording 1 and print that fight's card.
    local n, rest = arg:match("^([pP]?[%d:]*)%s*(%a*)$")
    if not n then Print("coach: no recording " .. arg .. ".") return end
    if n == "" then n = "1" end
    local rec, label = MD:GetRecording(n)
    if not rec then Print("coach: no recording " .. tostring(n) .. ".") return end
    n = label

    -- review-replay R12: "/st coach 3 health" picks one of the strategies the
    -- last search on this fight produced (the card's own hint), without
    -- searching again -- Verify.lua's TBC branch, ported (v0.10.4).
    local SP = MD.SimPlanner
    for _, obj in ipairs(SP.OBJECTIVES or {}) do
        if rest == obj.key then
            local w = SP.strategies and SP.strategies[rec.id] and SP.strategies[rec.id][obj.key]
            if not w then
                PrintCard(string.format("coach: no strategies for recording %s yet - run |cffffff00/st coach %s|r first.",
                    Esc(tostring(n)), Esc(tostring(n))))
                return
            end
            SP.plans[rec.id] = w.plan
            PrintCard(string.format("coach: |cff33ff66%s|r is now the plan the replay draws for recording %s - %s.",
                Esc(obj.name), Esc(tostring(n)), Esc(obj.what)))
            local r = w.result or {}
            Print(string.format("  %d mana used (and owed), floor %d%%, %.1fs in danger.",
                math.floor(SP.ManaUsed(r) + SP.ManaOwed(r, w.plan) + 0.5),
                math.floor((r.lowest and r.lowest.hp or 1) * 100 + 0.5), r.floorSeconds or 0))
            return
        end
    end

    if MD.coachSearch and MD.replayCoaching then
        MD.coachSearch:Cancel()
        MD.coachSearch, MD.replayCoaching = nil, nil
    end
    if MD.coachSearch then Print("coach: already searching (/st coach cancel).") return end

    local function Show(lines)
        MD.coachSearch = nil
        for _, line in ipairs(lines) do PrintCard(line) end
    end
    MD.coachSearch = MD.SimPlanner.CoachAsync(rec, { n = n, force = (rest == "force") }, Show)
end

MD:AddCommand("coach", function(arg) MD:RunCoach(arg) end,
    "/st coach [n] [force, or safe / health / cheap / regen]",
    "search for a better plan on recorded fight n and show the card (cancel stops it); a strategy name plays that one")
