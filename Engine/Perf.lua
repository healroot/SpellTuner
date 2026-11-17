local _, ST = ...

--------------------------------------------------------------------------------
-- Engine/Perf.lua -- /st perf, the profiler (2026-11-16, both lines).
--
-- Players reported a freeze every few seconds (docs/review/perf-0.18.1.md).
-- 0.18.2 removed the cause found in the code; this file is how a player's
-- session shows whether anything of ours is still slow. Off by default and
-- costs nothing off: Core.lua reads ST.Prof.on once per dispatch.
--
-- On (`/st perf on`, kept across /reload until `/st perf off`):
--   * every handler Core.lua dispatches (events, unit events, callbacks, the
--     0.5 s tick) timed by debugprofilestop: calls, SELF time (a handler that
--     fires a callback is not charged for the callback's handlers), worst
--     call, calls over SLOW_MS, and the Lua memory it allocated
--     (collectgarbage("count") before / after, a GC step in between counted
--     as nothing). Named by what fired and where the handler registered;
--   * ST.Prof.Time(label, fn, ...) for code outside the dispatcher (the
--     clock's per-frame line, the TBC widget's paint, the spell tooltip);
--   * ST.Prof.Note(kind, key, ms) for a cost with a cause (a book scan and
--     what marked it, Spells/Book.lua);
--   * every frame (an OnUpdate here): the frame's own length and our share
--     since the last one. A frame over HITCH_MS, or ours over SPIKE_MS, is
--     kept (the last KEEP_EVENTS) with the time, combat, and our biggest
--     handler in it -- so a hitch that is not ours shows as "ours 0.3 ms";
--   * the Lua heap each second (every addon's): a drop over GC_DROP_KB is a
--     garbage collection, counted and timed;
--   * the addon's own memory when profiling starts and at each report only
--     (UpdateAddOnMemoryUsage walks every addon: 75 ms a read in the
--     author's game, 2026-11-16);
--   * from the first `on`, the Spells pane's, the talent planner's and the
--     What if's functions are timed too (Perf.WrapUI), so a click, a hover
--     or a view shown outside the dispatcher is named, not "?".
--
-- `/st perf report` shows the report in a copy box and keeps it in
-- SpellTunerDB.perf.report; logging out keeps the latest as well, so it can
-- be read from WTF/.../SavedVariables/SpellTuner.lua.
--------------------------------------------------------------------------------

local Perf = {}
ST.Perf = Perf
local PROF = ST.Prof

Perf.SLOW_MS = 5
Perf.SPIKE_MS = 16
Perf.HITCH_MS = 100
Perf.GC_DROP_KB = 256
Perf.KEEP_EVENTS = 60
Perf.TOP = 20

local Clock = function() return ST.API.ProfileMs() end
local Heap = function() return collectgarbage("count") end
local Now = function() return GetTime() end

-- the session's data; Reset() makes a fresh one
local D

function Perf.Reset()
    D = {
        startedAt = Now(),
        stats = {},      -- key -> { label, site, calls, ms, max, slow, kb }
        notes = {},      -- kind -> key -> { n, ms, max }
        events = {},     -- ring of hitches / spikes
        eventN = 0,
        frames = 0, framesCombat = 0,
        frameHist = { [50] = 0, [100] = 0, [250] = 0, [1000] = 0 },
        worstFrame = 0,
        combatSec = 0,
        fightsIn = 0, fightsOut = 0,  -- PLAYER_REGEN_DISABLED / _ENABLED inside the window
        framesLockdown = 0,           -- frames InCombatLockdown() answered true
        inCombatAtStart = ST.inCombat and true or false,
        ourMs = 0, ourMsCombat = 0,
        gcN = 0, gcKB = 0, gcCombat = 0,
        heapMin = nil, heapMax = nil,
        mem = {},        -- { t, kb } samples of the addon's own memory
        memMs = 0,       -- what reading it cost
    }
    Perf.data = D
end

--------------------------------------------------------------------------------
-- Timing: a stack of the handlers running, so each is charged its self time.
--------------------------------------------------------------------------------
local depth = 0
local childMs = {}  -- [depth] = ms its children took
local childKB = {}
local heapAt = {}
local current = {}  -- [depth] = label of the running handler
local acc, accTop, accTopMs = 0, nil, 0  -- this frame: our ms, the biggest

local function Stat(key, label, site)
    local s = D.stats[key]
    if not s then
        s = { label = label, site = site, calls = 0, ms = 0, max = 0, slow = 0, kb = 0 }
        D.stats[key] = s
    end
    return s
end

local function Begin(name)
    depth = depth + 1
    childMs[depth], childKB[depth] = 0, 0
    current[depth] = name
    heapAt[depth] = Heap()
    return Clock(), depth
end

local function Finish(key, label, site, t0, d)
    local dt = Clock() - t0
    if d < depth then depth = d end           -- a raising frame above us: drop it
    local kb = Heap() - (heapAt[d] or 0)
    if kb < 0 then kb = 0 end                 -- a GC step ran in between
    local selfMs = dt - (childMs[d] or 0)
    local selfKB = kb - (childKB[d] or 0)
    if selfMs < 0 then selfMs = 0 end
    if selfKB < 0 then selfKB = 0 end
    depth = d - 1
    if depth > 0 then
        childMs[depth] = (childMs[depth] or 0) + dt
        childKB[depth] = (childKB[depth] or 0) + kb
    else
        acc = acc + dt
        if dt > accTopMs then accTop, accTopMs = site and (label .. " " .. site) or label, dt end
        D.ourMs = D.ourMs + dt
        if ST.inCombat then D.ourMsCombat = D.ourMsCombat + dt end
    end
    local s = Stat(key, label, site)
    s.calls = s.calls + 1
    s.ms = s.ms + selfMs
    s.kb = s.kb + selfKB
    if dt > s.max then s.max = dt end
    if dt >= Perf.SLOW_MS then s.slow = s.slow + 1 end
end

-- Core.lua's two hooks: list is a handler list (label, sites), i the handler
function PROF.Enter(list, i)
    return Begin(list.label)
end
function PROF.Took(list, i, t0, d)
    local site = list.sites and list.sites[i]
    Finish(list.label .. "#" .. i, list.label, site, t0, d)
end

-- Code outside the dispatcher: PROF.Time(label, fn, ...) runs fn(...) timed
-- and hands its returns back. A raise propagates as before (the next Finish
-- at a lower depth drops the frame it left).
local function After(label, t0, d, ...)
    Finish(label, label, nil, t0, d)
    return ...
end
function PROF.Time(label, fn, ...)
    local t0, d = Begin(label)
    return After(label, t0, d, fn(...))
end

-- The label of the handler running now ("UNIT_AURA", "tick", ...), or nil.
function PROF.Current()
    return current[depth]
end

-- A cost with a cause: kind "book scan", key "hard by SPELLS_CHANGED", ms.
function PROF.Note(kind, key, ms)
    if not D then return end
    local k = D.notes[kind]
    if not k then k = {}; D.notes[kind] = k end
    local n = k[key]
    if not n then n = { n = 0, ms = 0, max = 0 }; k[key] = n end
    n.n = n.n + 1
    n.ms = n.ms + (ms or 0)
    if (ms or 0) > n.max then n.max = ms end
end

--------------------------------------------------------------------------------
-- Frames, the heap, the addon's memory
--------------------------------------------------------------------------------
local frame
local secAcc, lastHeap = 0, nil
local pending -- a spike of ours: the frame it delays is the next one

local function Keep(ev)
    D.eventN = D.eventN + 1
    D.events[(D.eventN - 1) % Perf.KEEP_EVENTS + 1] = ev
end

local function ReadMem()
    if not (ST.API.UpdateAddOnMemory and ST.API.AddOnMemory) then return end
    local t0 = Clock()
    ST.API.UpdateAddOnMemory()
    local kb = ST.API.AddOnMemory("SpellTuner")
    D.memMs = D.memMs + (Clock() - t0)
    if type(kb) == "number" then D.mem[#D.mem + 1] = { t = Now() - D.startedAt, kb = kb } end
end

function Perf.OnFrame(elapsed)
    local ms = (elapsed or 0) * 1000
    D.frames = D.frames + 1
    if ST.inCombat then
        D.framesCombat = D.framesCombat + 1
        D.combatSec = D.combatSec + (elapsed or 0)
    end
    -- 2026-11-17: the client's own answer beside the flag, so a report says
    -- plainly whether its window saw a fight
    local lock = ST.API.InCombatLockdown and ST.API.InCombatLockdown()
    if lock == true or lock == 1 then D.framesLockdown = D.framesLockdown + 1 end
    if ms > D.worstFrame then D.worstFrame = ms end
    for _, b in ipairs({ 1000, 250, 100, 50 }) do
        if ms >= b then D.frameHist[b] = D.frameHist[b] + 1 break end
    end
    -- our work between two OnUpdates can land after this frame's own (a
    -- tooltip, a click): the frame it lengthens is the next, so a spike is
    -- kept with both lengths
    if pending then
        pending.next = ms
        Keep(pending)
        pending = nil
    end
    if acc >= Perf.SPIKE_MS then
        pending = { t = Now() - D.startedAt, frame = ms, ours = acc, top = accTop, topMs = accTopMs,
            combat = ST.inCombat and true or false }
    elseif ms >= Perf.HITCH_MS then
        Keep({ t = Now() - D.startedAt, frame = ms, ours = acc, top = accTop, topMs = accTopMs,
            combat = ST.inCombat and true or false })
    end
    acc, accTop, accTopMs = 0, nil, 0

    secAcc = secAcc + (elapsed or 0)
    if secAcc >= 1 then
        secAcc = 0
        local h = Heap()
        if lastHeap and h < lastHeap - Perf.GC_DROP_KB then
            D.gcN = D.gcN + 1
            D.gcKB = D.gcKB + (lastHeap - h)
            if ST.inCombat then D.gcCombat = D.gcCombat + 1 end
        end
        lastHeap = h
        if not D.heapMin or h < D.heapMin then D.heapMin = h end
        if not D.heapMax or h > D.heapMax then D.heapMax = h end
    end
end

--------------------------------------------------------------------------------
-- On / off
--------------------------------------------------------------------------------
local function Saved()
    -- SpellTunerDB.perf, like /st measure's SpellTunerDB.measures: written only
    -- once the profiler is used, never a setting
    if type(SpellTunerDB) ~= "table" then return nil end
    if type(SpellTunerDB.perf) ~= "table" then SpellTunerDB.perf = {} end
    return SpellTunerDB.perf
end

function Perf.Start(keepData)
    if type(ST.API.ProfileMs) ~= "function" then return false end
    if not D or not keepData then Perf.Reset() end
    depth, acc, accTop, accTopMs = 0, 0, nil, 0
    secAcc, lastHeap, pending = 0, nil, nil
    Perf.WrapUI()
    if not frame then frame = CreateFrame("Frame") end
    frame:SetScript("OnUpdate", function(_, elapsed) Perf.OnFrame(elapsed) end)
    PROF.on = true
    ReadMem()
    local sv = Saved()
    if sv then sv.on = true end
    return true
end

function Perf.Stop()
    PROF.on = false
    depth = 0
    if frame then frame:SetScript("OnUpdate", nil) end
    local sv = Saved()
    if sv then sv.on = nil end
end

--------------------------------------------------------------------------------
-- The report: plain ASCII lines, one block to paste back.
--------------------------------------------------------------------------------
local function F(n, p) return string.format("%." .. (p or 1) .. "f", n or 0) end
local function Where(s) return s.site and (" (" .. s.site .. ")") or "" end

local function Sorted(t, by)
    local list = {}
    for _, v in pairs(t) do list[#list + 1] = v end
    table.sort(list, function(a, b) return (a[by] or 0) > (b[by] or 0) end)
    return list
end

function Perf.Report()
    if not D then return "SpellTuner perf: no data (/st perf on, play, /st perf report)" end
    if PROF.on then ReadMem() end
    local L = {}
    local function A(s) L[#L + 1] = s end
    local dur = Now() - D.startedAt
    A(string.format("SpellTuner perf report -- %s, %s", tostring(ST.API.AddonVersion and ST.API.AddonVersion() or "?"),
        PROF.on and "running" or "stopped"))
    A(string.format("session %ss (combat %ss), frames %d (combat %d), avg fps %s",
        F(dur, 0), F(D.combatSec, 0), D.frames, D.framesCombat, F(dur > 0 and D.frames / dur or 0)))
    A(string.format("combat in this window: %s at start, %d entered, %d left; client lockdown %d frames",
        D.inCombatAtStart and "in combat" or "out of combat", D.fightsIn, D.fightsOut, D.framesLockdown))
    A(string.format("ours: %s ms total (%s ms/s), in combat %s ms (%s ms/s)",
        F(D.ourMs), F(dur > 0 and D.ourMs / dur or 0, 2), F(D.ourMsCombat),
        F(D.combatSec > 0 and D.ourMsCombat / D.combatSec or 0, 2)))
    A(string.format("frames 50-99 ms %d, 100-249 ms %d, 250-999 ms %d, 1 s+ %d; worst %s ms",
        D.frameHist[50], D.frameHist[100], D.frameHist[250], D.frameHist[1000], F(D.worstFrame, 0)))
    A(string.format("lua heap (all addons) %s..%s KB, GC drops %d (%d in combat, %s KB freed)",
        F(D.heapMin, 0), F(D.heapMax, 0), D.gcN, D.gcCombat, F(D.gcKB, 0)))
    if #D.mem > 0 then
        local first, last = D.mem[1], D.mem[#D.mem]
        local lo, hi = first.kb, first.kb
        for _, m in ipairs(D.mem) do
            if m.kb < lo then lo = m.kb end
            if m.kb > hi then hi = m.kb end
        end
        A(string.format("SpellTuner memory %s -> %s KB (min %s, max %s, %d reads, %s ms reading)",
            F(first.kb, 0), F(last.kb, 0), F(lo, 0), F(hi, 0), #D.mem, F(D.memMs)))
    end

    A("")
    A("by self time:  calls  self ms  max ms  >5ms  KB alloc  what (where it registered)")
    local byMs = Sorted(D.stats, "ms")
    for i = 1, math.min(Perf.TOP, #byMs) do
        local s = byMs[i]
        A(string.format("  %6d %8s %7s %5d %9s  %s%s", s.calls, F(s.ms), F(s.max), s.slow, F(s.kb, 0),
            s.label, Where(s)))
    end
    A("by worst call:")
    local byMax = Sorted(D.stats, "max")
    for i = 1, math.min(10, #byMax) do
        local s = byMax[i]
        if s.max < 1 then break end
        A(string.format("  %7s ms  %s%s, %d calls", F(s.max), s.label, Where(s), s.calls))
    end
    A("by allocation:")
    local byKB = Sorted(D.stats, "kb")
    for i = 1, math.min(10, #byKB) do
        local s = byKB[i]
        if s.kb < 1 then break end
        A(string.format("  %8s KB  %s%s, %d calls", F(s.kb, 0), s.label, Where(s), s.calls))
    end

    for kind, keys in pairs(D.notes) do
        A(kind .. ":")
        local list = {}
        for key, n in pairs(keys) do list[#list + 1] = { key = key, n = n.n, ms = n.ms, max = n.max } end
        table.sort(list, function(a, b) return a.ms > b.ms end)
        for _, n in ipairs(list) do
            A(string.format("  %4d x  %8s ms  max %7s  %s", n.n, F(n.ms), F(n.max), n.key))
        end
    end

    A("")
    A(string.format("hitches (frame >= %d ms) and spikes (ours >= %d ms), last %d of %d:",
        Perf.HITCH_MS, Perf.SPIKE_MS, math.min(D.eventN, Perf.KEEP_EVENTS), D.eventN))
    local first = math.max(1, D.eventN - Perf.KEEP_EVENTS + 1)
    for k = first, D.eventN do
        local e = D.events[(k - 1) % Perf.KEEP_EVENTS + 1]
        A(string.format("  t=%7s frame %6s ms%s  ours %6s ms%s  %s", F(e.t), F(e.frame, 0),
            e.next and (" next " .. F(e.next, 0) .. " ms") or "", F(e.ours),
            e.combat and " C" or "  ", e.top and (e.top .. " " .. F(e.topMs) .. " ms") or "-"))
    end
    -- every piece is ours and ASCII (labels, file names, numbers): no escape
    local text = table.concat(L, "\n")
    local sv = Saved()
    if sv then sv.report = text end
    return text
end

--------------------------------------------------------------------------------
-- E (2026-11-16): the UI's own functions, timed from the first `on` (never
-- wrapped while the profiler was never used). A wrapper reads ST.Prof.on
-- and calls straight through while off; returns are kept.
--------------------------------------------------------------------------------
local wrapped = false
local UI_TABLES = {
    { "SpellsPane", "Spells pane" },
    { "TalentPlanner", "talent plan" },
    { "WhatIf", "What if" },
}
local SKIP = { Get = true, Active = true, Values = true } -- WI's per-cell reads: noise
function Perf.WrapUI()
    if wrapped then return end
    wrapped = true
    for _, t in ipairs(UI_TABLES) do
        local tbl = ST[t[1]]
        if type(tbl) == "table" then
            for name, fn in pairs(tbl) do
                if type(fn) == "function" and not SKIP[name] then
                    local label = t[2] .. " " .. name
                    tbl[name] = function(...)
                        if PROF.on then return PROF.Time(label, fn, ...) end
                        return fn(...)
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Command, login, logout
--------------------------------------------------------------------------------
local function Status()
    if not D then return "off, no data" end
    return string.format("%s, %ss, %d handlers seen, %d hitches", PROF.on and "on" or "off",
        F(Now() - D.startedAt, 0), (function() local n = 0 for _ in pairs(D.stats) do n = n + 1 end return n end)(),
        D.eventN)
end

function Perf.Command(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "on" then
        if Perf.Start(false) then
            ST:Print("perf: profiling on (kept across /reload). Play a while, then /st perf report.")
        else
            ST:Print("perf: this client has no millisecond clock (debugprofilestop); nothing to time with.")
        end
    elseif arg == "off" then
        Perf.Stop()
        ST:Print("perf: profiling off; the data stays for /st perf report.")
    elseif arg == "reset" then
        if PROF.on then Perf.Start(false) else D = nil; Perf.data = nil end
        ST:Print("perf: data cleared.")
    elseif arg == "report" then
        local text = Perf.Report()
        if ST.ShowCopyPopup then ST:ShowCopyPopup("SpellTuner perf", text) else ST:Print(text) end
    else
        ST:Print("perf: " .. Status() .. ". /st perf on, off, report, reset")
    end
end

-- hidden from /st help (a diagnostic, like the probe's tools); /st perf
-- alone prints its own usage
ST:AddCommand("perf", function(arg) Perf.Command(arg) end, "/st perf on, off, report, reset",
    "time SpellTuner's own code, for a slowness report", true)

ST:RegisterCallback("CORE_LOGIN", function()
    local sv = type(SpellTunerDB) == "table" and type(SpellTunerDB.perf) == "table" and SpellTunerDB.perf
    if sv and sv.on then
        Perf.Start(false)
        ST:Print("perf: profiling is on (/st perf report, /st perf off).")
    end
end)

ST:On("PLAYER_REGEN_DISABLED", function() if D and PROF.on then D.fightsIn = D.fightsIn + 1 end end)
ST:On("PLAYER_REGEN_ENABLED", function() if D and PROF.on then D.fightsOut = D.fightsOut + 1 end end)

ST:On("PLAYER_LOGOUT", function()
    if D then pcall(Perf.Report) end
end)
