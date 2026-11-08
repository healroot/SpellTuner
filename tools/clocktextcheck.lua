-- tools/run.sh --flavour tbc tools/clocktextcheck.lua
-- tools/run.sh --flavour forever tools/clocktextcheck.lua
--
-- T114 (docs/tasks/T114-clock-face-slots.md), cut down by T145d
-- (docs/SPEC-clock-v3.md 4.6; docs/tasks/T145d-clock-pane.md): Line's slots
-- (CF.TEXT, ResolveText, Slots) left with Line and Compact, and their checks
-- with them (T114's 2-5 and 8-11). What stays is what the faces' producers
-- owe the clock's texts, now worded by Engine/ClockWords.lua:
--    1. CF.Time's formats;
--    6. the Regen text's number is the regen feed's (RegenReading);
--    7. the 5SR text: 5SR 3.0 two seconds after a spend, nothing after five;
--   12. the matrix: every sample x every look's time format and warn switch,
--       ClockWords.Build and LineString -- ASCII, no bare pipe, never a lone 0
--       as a time;
--   13. the producers' fields (TBC ST:GetClockFace, Forever ManaModel.Face).
-- 6, 7 and 13 drive this flavour's own producer.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")
local check = T.check
local FLAVOUR = S.flavour
local FOREVER = FLAVOUR == "forever"
local CF = ST.ClockFace
local HEX = "|cff16c3f2"

-- A block that raises (on the parent: no CF.Slots) is one FAIL, not the end.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

local CW = ST.ClockWords
-- The words a look gives a face (Engine/ClockWords.lua), one kind.
local function Says(face, kind, look)
    local out = CW.Build(face, look or { timeFmt = "mss", warn = true }, nil, GetTime(), nil, false)
    return out[kind] and out[kind].text
end

local function Copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end
local function Sample(key)
    for _, s in ipairs(CF.SAMPLES) do if s.key == key then return Copy(s.face) end end
end
-- A face as the Forever line words it: modelled, one colour, M:SS, no arrow.
local function ForeverShaped(f)
    f = Copy(f)
    f.modelled, f.mono, f.timeFmt, f.unstable, f.arrow = true, true, "mss", false, nil
    f.pctModelled, f.mp5Modelled, f.manaModelled = true, true, true
    return f
end
local function LineShaped(f) return FOREVER and ForeverShaped(f) or f end

-- The words fixture: OOM 1:20 v, rest 2:10, 62 %, 4210 of 6800, 92 mp5.
local function Words(extra)
    local f = Sample("oom")
    f.pct, f.mana, f.manaMax, f.mp5 = 0.62, 4210, 6800, 92
    f.pctModelled, f.mp5Modelled, f.manaModelled = false, false, false
    f.second = { kind = "rest", label = "rest", value = 130 }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

local function Plain(s) return T.Strip(s or "") end

-- Feeds on TBC: the harness drops UI/ (but for UI/Summary.lua); load it by
-- hand, handing it the MD_READY it missed.
if not ST.Feeds then
    local ready, realReg = {}, ST.RegisterCallback
    ST.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    local okLoad, err = pcall(S.Load, { "UI/Feeds.lua" }, "SpellTuner", ST)
    ST.RegisterCallback = realReg
    if not okLoad then print("load UI/Feeds.lua: " .. tostring(err)) end
    for _, fn in ipairs(ready) do pcall(fn) end
end

local function Ticks(n) for _ = 1, n do S.Tick(0.5) end end
Ticks(4)

--------------------------------------------------------------------------------
-- 1. CF.Time
--------------------------------------------------------------------------------
T.section("1. CF.Time")
Guarded("1. CF.Time", function()
    local cases = {
        { 15, "auto", "15s" }, { 80, "auto", "1:20" }, { 15, "mss", "0:15" }, { 80, "mss", "1:20" },
        { 80, "sec", "80s" }, { 15, "sec", "15s" }, { 80, "msec", "1m20" }, { 120, "msec", "2m00" },
        { 15, "msec", "15s" },
        { 601, "auto", ">10m" }, { 601, "mss", ">10m" }, { 601, "sec", ">10m" }, { 601, "msec", ">10m" },
        { nil, "auto", "--" }, { nil, "mss", "--" }, { nil, "sec", "--" }, { nil, "msec", "--" },
    }
    local bad = {}
    for _, c in ipairs(cases) do
        local got = CF.Time(c[1], c[2])
        if got ~= c[3] then bad[#bad + 1] = tostring(c[1]) .. "/" .. c[2] .. "=" .. tostring(got) end
    end
    check("1. CF.Time: auto / mss unchanged; sec 80s; msec 1m20 / 2m00 / 15s; >10m in all; nil --",
        #bad == 0, table.concat(bad, ", "))
end)

--------------------------------------------------------------------------------
-- 6. mp5 is the regen feed's number
--------------------------------------------------------------------------------
T.section("6. mp5 = the regen feed")
local function Spend(n)
    if FOREVER then
        ST.Pool.model:Spend(n, GetTime())
    else
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        S.mana = S.mana - n
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
end
local function Face() return CF.Current(GetTime()) end
local function Mp5Words(face) return Says(face, "mp5") end
Guarded("6. mp5", function()
    local read = ST.Feeds and ST.Feeds.RegenReading
    local rows = {}
    local function Row(tag)
        local face, r = Face(), read()
        local words = Mp5Words(face)
        local n = words and tonumber(words:match("^(%d+) mp5$"))
        local mark = face.mp5Modelled == true and face.combat == true
        rows[#rows + 1] = { tag = tag, n = n, want = r and r.mp5, mark = mark, wantMark = r and r.modelled, fsr = r and r.fsr }
    end
    Ticks(14)
    Row("out")
    Spend(100)
    Row("in rule")
    if FOREVER then
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Spend(100)
        Ticks(1)
        Row("fight, rule")
        Ticks(12)
        Row("fight")
        S.Fire("PLAYER_REGEN_ENABLED")
        S.inCombat = false
    end
    Ticks(12)
    local bad, sawIn, sawOut = nil, false, false
    for _, r in ipairs(rows) do
        if r.n == nil or r.n ~= r.want or r.mark ~= (r.wantMark == true) then
            bad = string.format("%s: %s vs feed %s (mark %s/%s)", r.tag, tostring(r.n), tostring(r.want),
                tostring(r.mark), tostring(r.wantMark))
        end
        if r.fsr then sawIn = true else sawOut = true end
    end
    check("6. the Regen text's number is the regen feed's (RegenReading), in and out of the rule"
        .. (FOREVER and ", the face marks it modelled in a fight" or ""), type(read) == "function" and bad == nil
        and sawIn and sawOut and rows[1].n ~= rows[2].n, bad)
end)

--------------------------------------------------------------------------------
-- 7. fsr
--------------------------------------------------------------------------------
T.section("7. fsr")
local function FsrWords() return Says(Face(), "fsr") end
Guarded("7. fsr", function()
    Ticks(14)
    local before = FsrWords()
    Spend(100)
    Ticks(4)
    local three = FsrWords()
    Ticks(6)
    local after = FsrWords()
    local free = true
    if FOREVER then
        local model = ST.Pool.model
        local last = model.lastSpend
        local realCost = ST.Pool.CostFor
        ST.Pool.CostFor = function(id) if id == 99001 then return 0 end return realCost(id) end
        S.Cast(99001)
        Ticks(1)
        ST.Pool.CostFor = realCost
        free = model.lastSpend == last and FsrWords() == nil
    else
        -- a cast with no mana leaving the pool starts nothing
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 5185)
        Ticks(1)
        free = FsrWords() == nil
    end
    check("7. fsr: 5SR 3.0 two seconds after a spend, empty after five, a free cast starts nothing",
        before == nil and three == "5SR 3.0" and after == nil and free,
        string.format("before=%s three=%s after=%s free=%s", tostring(before), tostring(three), tostring(after),
            tostring(free)))
end)

--------------------------------------------------------------------------------
-- 12. the matrix
--------------------------------------------------------------------------------
T.section("12. matrix")
local function LoneZero(s)
    for word in Plain(s):gmatch("[^ ]+") do
        local w = word:gsub("^[~>]", "")
        if w == "0" or w == "0%" or w == "0s" or w == "0:00" or w == "0m00" or w == "0/0" or w == "0.0" then
            return true
        end
    end
    return false
end
Guarded("12. matrix", function()
    local bad, n = nil, 0
    local faces = {}
    for _, s in ipairs(CF.SAMPLES) do
        faces[#faces + 1] = { key = s.key, face = Copy(s.face) }
        faces[#faces + 1] = { key = s.key .. "~", face = ForeverShaped(s.face) }
    end
    local function See(key, what, str, timeLike)
        n = n + 1
        local okA, why = T.Ascii(str)
        if not okA then bad = bad or (key .. " " .. what .. ": " .. why) end
        if str:find("nil", 1, true) then bad = bad or (key .. ": nil in " .. str) end
        if timeLike and LoneZero(str) then bad = bad or (key .. " " .. what .. ": zero " .. str) end
    end
    for _, F in ipairs(faces) do
        for _, fmt in ipairs({ "mss", "sec" }) do
            for _, warn in ipairs({ true, false }) do
                local out = CW.Build(F.face, { timeFmt = fmt, warn = warn }, nil, 0, nil, false)
                for _, kind in ipairs(CW.KINDS) do
                    local w = out[kind] and out[kind].text
                    if w ~= nil then See(F.key, kind, w, kind == "time" or kind == "rest") end
                end
            end
        end
        local line = CF.LineString(F.face)
        See(F.key, "LineString", line, true)
        See(F.key, "LineString hex", CF.LineString(F.face, HEX), true)
        See(F.key, "Join", CF.JoinSegments(CF.Segments(F.face)), true)
        if F.face.mono and line ~= Plain(line) then bad = bad or (F.key .. ": colour on a mono face " .. line) end
    end
    check("12. every sample x the time formats x warn: ClockWords and LineString ASCII, no bare pipe, never a lone 0",
        bad == nil and n > 100, bad or (n .. " strings"))
end)

--------------------------------------------------------------------------------
-- 13. the producers
--------------------------------------------------------------------------------
T.section("13. producers")
Guarded("13. producers", function()
    local IsSecret = ST.API.IsSecret
    local function NoSecret(face)
        for k, v in pairs(face) do
            if IsSecret(v) then return k end
            if type(v) == "table" then for k2, v2 in pairs(v) do if IsSecret(v2) then return k .. "." .. k2 end end end
        end
        return nil
    end
    if FOREVER then
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Spend(200)
        Ticks(2)
        local face = Face()
        local model = ST.Pool.model
        local secretField = NoSecret(face)
        local base, casting = ST.API.ManaRegen()
        check("13. Forever ManaModel.Face: the model's mana / manaMax, manaModelled; no field a secret (in a fight)",
            face.mana == model.mana and face.manaMax == model.max and face.manaModelled == true
            and type(face.mana) == "number" and face.mana < model.max and secretField == nil
            and casting == "secret" and type(face.fsr) == "number" and face.mp5 ~= nil,
            string.format("mana=%s/%s max=%s secret=%s regen=%s/%s", tostring(face.mana), tostring(model.mana),
                tostring(face.manaMax), tostring(secretField), tostring(base), tostring(casting)))
        S.Fire("PLAYER_REGEN_ENABLED")
        S.inCombat = false
    else
        S.mana = 4210
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        Ticks(1)
        local face = ST:GetClockFace(GetTime())
        check("13. TBC ST:GetClockFace: mana / manaMax plain, manaModelled false",
            face and face.mana == 4210 and face.manaMax == S.manaMax and face.manaModelled == false
            and NoSecret(face) == nil,
            face and string.format("mana=%s max=%s modelled=%s", tostring(face.mana), tostring(face.manaMax),
                tostring(face.manaModelled)) or "no face")
    end
end)

T.done()
