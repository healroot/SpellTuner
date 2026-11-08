-- tools/run.sh [--flavour tbc|forever] tools/clockwordscheck.lua
--
-- T145a (docs/SPEC-clock-v3.md 4.1; docs/tasks/T145a-clock-words.md): the
-- clock's words, Engine/ClockWords.lua, pure. What is held, on both flavours:
--   1. the file loads beside Engine/ClockFace.lua in an environment holding
--      nothing but Lua's own library (no frame, no client call, no ST.db);
--   2. the FULL rule as a table (1.2): fullnow, bug 2's in-fight full at
--      ttf 0, a refill under 5 s, a refill with a time, pct >= 0.995, an OOM
--      time in both formats with its Warn tone, warm-up, hold, >10m, TBC's
--      bound and arrow, the quiet-pool signal;
--   3. no time ever reads "0s" or "0:00": every mode x value 0..12 x format;
--   4. the Steady sequences (T144's, moved here; ManaModel.Steady its alias),
--      and entering FULL snaps;
--   5. QuietFull at every boundary, nil inputs false (E7's rule, pure);
--   6. Build with `out` passed allocates nothing over 1000 calls;
--   7. the other kinds' words (no "~"), the modelled marks.
-- Forever only:
--   8. the bug-2 face made by the real model (in a fight, regen outrunning
--      the spend, the model at max) reads FULL, and so does a refill under
--      2.5 s out of combat;
--   9. the pool's quiet-full anchor through the real events and ticks (E7):
--      events every 0.2 s no anchor; quiet outside the rule anchors at max and
--      the words read FULL; quiet inside the rule no anchor; a slow base no
--      anchor; the dump line counts both.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
local check = T.check

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local FLAVOUR = S.flavour

local W = ST.ClockWords
local CF = ST.ClockFace

--------------------------------------------------------------------------------
T.section("1. pure, and in every main TOC")
--------------------------------------------------------------------------------
do
    local env = {
        string = string, table = table, math = math, pairs = pairs, ipairs = ipairs, type = type,
        tostring = tostring, tonumber = tonumber, next = next, select = select, error = error,
        setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
        pcall = pcall, unpack = unpack,
    }
    local fake = {}
    local okAll, err = true, nil
    for _, rel in ipairs({ "Engine/ClockFace.lua", "Engine/ClockWords.lua" }) do
        local chunk, lerr = loadfile(S.root .. "/" .. rel)
        if not chunk then okAll, err = false, lerr break end
        setfenv(chunk, setmetatable({}, { __index = function(_, k)
            local v = env[k]
            if v == nil then error("ClockWords is not pure: reads global " .. tostring(k), 2) end
            return v
        end }))
        local ok, rerr = pcall(chunk, "SpellTuner", fake)
        if not ok then okAll, err = false, rerr break end
    end
    local built
    if okAll then
        local ok2, out = pcall(fake.ClockWords.Build,
            { mode = "oom", label = "OOM", value = 80, known = "point", tone = "normal", timeFmt = "mss",
              mana = 400, manaMax = 1000, pct = 0.4, mp5 = 30, fsr = 2.5,
              second = { kind = "rest", label = "rest", value = 130 } },
            { timeFmt = "mss", warn = true }, {}, 10, nil, false)
        built = ok2 and out.time.text == "1:20" and out.rest.text == "rest 2:10"
    end
    check("ClockWords loads and builds with Lua's library only (no frame, no client, no db)",
        okAll and built == true, tostring(err))

    local inToc = {}
    for _, toc in ipairs({ "SpellTuner_Mainline.toc", "SpellTuner.toc", "SpellTuner_TBC.toc" }) do
        local files = S.TocFiles(toc)
        local face, words
        for i, rel in ipairs(files) do
            if rel == "Engine/ClockFace.lua" then face = i end
            if rel == "Engine/ClockWords.lua" then words = i end
        end
        inToc[#inToc + 1] = (face and words and words == face + 1) and true or false
    end
    check("every main TOC lists Engine/ClockWords.lua right after Engine/ClockFace.lua",
        inToc[1] and inToc[2] and inToc[3], table.concat({ tostring(inToc[1]), tostring(inToc[2]), tostring(inToc[3]) }, " "))
    check("the harness loaded it (ST.ClockWords with Build, IsFull, QuietFull, Steady)",
        type(W) == "table" and type(W.Build) == "function" and type(W.IsFull) == "function"
        and type(W.QuietFull) == "function" and type(W.Steady) == "function")
end

-- A face as a line makes one. fmt: the face's own ("mss" Forever, "auto" TBC).
local function F(mode, value, known, extra)
    local label = (mode == "oom" or mode == "hold" or mode == "warmup") and "OOM" or "FULL"
    local f = { mode = mode, label = label, value = value, known = known or "point", timeFmt = "mss",
        tone = "normal", combat = mode ~= "ooc" and mode ~= "fullnow" }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end
local function Words(face, look, quiet, latch, now)
    return W.Build(face, look or { timeFmt = "mss", warn = true }, latch, now or 0, nil, quiet)
end
local SEC = { timeFmt = "sec", warn = true }

--------------------------------------------------------------------------------
T.section("2. the FULL rule (1.2)")
--------------------------------------------------------------------------------
do
    local rows = {
        { "fullnow -> FULL", F("fullnow", nil, "none"), nil, "FULL", true },
        { "in a fight, mode full, ttf 0 -> FULL (bug 2)", F("full", 0), nil, "FULL", true },
        { "ooc ttf 2.4 -> FULL", F("ooc", 2.4), nil, "FULL", true },
        { "ooc ttf 0 (Forever's shown 2.4) -> FULL", F("ooc", 0), nil, "FULL", true },
        { "ooc 10 -> FULL 0:10", F("ooc", 10), nil, "FULL 0:10", false },
        { "ooc 10, sec -> FULL 10s", F("ooc", 10), SEC, "FULL 10s", false },
        { "full 45 in a fight -> FULL 0:45", F("full", 45), nil, "FULL 0:45", false },
        { "pct 0.996, mode full, ttf 20 -> FULL", F("full", 20, "point", { pct = 0.996 }), nil, "FULL", true },
        { "pct 0.994, mode full, ttf 20 -> FULL 0:20", F("full", 20, "point", { pct = 0.994 }), nil, "FULL 0:20", false },
        { "oom 80 -> 1:20", F("oom", 80), nil, "1:20", false },
        { "oom 80, sec -> 80s", F("oom", 80), SEC, "80s", false },
        { "warmup -> ...", F("warmup", nil, "pending"), nil, "...", false },
        { "hold -> --", F("hold", nil, "none"), nil, "--", false },
        { "oom with no value -> --", F("oom", nil, "none"), nil, "--", false },
        { "oom over 600 -> >10m", F("oom", 900), nil, ">10m", false },
        { "ooc over 600 -> FULL >10m", F("ooc", 900), nil, "FULL >10m", false },
        { "TBC bound 110 -> >1:50 =", F("oom", 110, "bound", { timeFmt = "auto", arrow = "=" }), nil, ">1:50 =", false },
        { "TBC oom 80 with its arrow -> 1:20 v", F("oom", 80, "point", { timeFmt = "auto", arrow = "v" }), nil, "1:20 v", false },
        { "TBC oom 15 -> 15s vv", F("oom", 15, "point", { timeFmt = "auto", arrow = "vv" }), nil, "15s vv", false },
        { "nodata (TBC) -> FULL --", F("nodata", nil, "none"), nil, "FULL --", false },
        { "the quiet pool, a face at oom 80 -> FULL", F("oom", 80), nil, "FULL", true, true },
        { "no face, the quiet pool -> FULL", nil, nil, "FULL", true, true },
        { "no face -> --", nil, nil, "--", false },
    }
    for _, r in ipairs(rows) do
        local out = Words(r[2], r[3], r[6])
        check("2. " .. r[1], out.time.text == r[4] and out.full == r[5],
            "time=" .. tostring(out.time.text) .. " full=" .. tostring(out.full))
    end

    local function Tone(face, look) return Words(face, look).time.tone end
    check("2. oom 15 with Warn colours -> tone crit; 45 -> warn; 80 -> the text's colour",
        Tone(F("oom", 15)) == "crit" and Tone(F("oom", 45)) == "warn" and Tone(F("oom", 80)) == "text")
    check("2. Warn colours off -> the text's colour at 15 s",
        Tone(F("oom", 15), { timeFmt = "mss", warn = false }) == "text")
    check("2. a refill time and FULL in the text's colour; warm-up, hold and a bound muted",
        Tone(F("ooc", 45)) == "text" and Tone(F("fullnow", nil, "none")) == "text"
        and Tone(F("warmup", nil, "pending")) == "muted" and Tone(F("hold", nil, "none")) == "muted"
        and Tone(F("oom", 110, "bound", { timeFmt = "auto" })) == "muted")
    check("2. FULL_PCT is the named 0.995, FULL_UNDER 5", W.FULL_PCT == 0.995 and W.FULL_UNDER == 5)
end

--------------------------------------------------------------------------------
T.section("3. a time is never 0s or 0:00")
--------------------------------------------------------------------------------
do
    local function Zero(s)
        if type(s) ~= "string" then return false end
        return s:find("%f[%w]0s%f[%W]") ~= nil or s:find("^0s") ~= nil or s:find("%f[%d]0:00") ~= nil
    end
    local modes = {
        { "oom", "point" }, { "oom", "bound" }, { "full", "point" }, { "ooc", "point" }, { "hold", "bound" },
        { "warmup", "pending" }, { "hold", "none" }, { "fullnow", "none" }, { "nodata", "none" },
    }
    local bad, n = {}, 0
    for _, m in ipairs(modes) do
        for v = 0, 12, 0.5 do
            for _, fmt in ipairs({ "mss", "sec", "auto" }) do
                for _, look in ipairs({ { timeFmt = "mss", warn = true }, { timeFmt = "sec", warn = false } }) do
                    for _, latch in ipairs({ false, true }) do
                        local face = F(m[1], v, m[2], { timeFmt = fmt, second = { kind = "rest", label = "rest", value = v } })
                        local out = W.Build(face, look, latch and {} or nil, 0, nil, false)
                        n = n + 1
                        if Zero(out.time.text) or Zero(out.rest.text) then
                            bad[#bad + 1] = m[1] .. "/" .. m[2] .. " " .. v .. " " .. fmt .. ": " .. tostring(out.time.text)
                                .. " | " .. tostring(out.rest.text)
                        end
                    end
                end
            end
        end
    end
    check("3. every mode x value 0..12 x format: no 0s / 0:00 in the time or the rest (" .. n .. " cases)",
        #bad == 0, bad[1])
    check("3. a running-out value shown as 0 reads OOM, in the crit tone",
        Words(F("oom", 0)).time.text == "OOM" and Words(F("oom", 0)).time.tone == "crit")
end

--------------------------------------------------------------------------------
T.section("4. Steady (T144's rules, moved), and entering FULL snaps")
--------------------------------------------------------------------------------
do
    local function V(latch, v, now, mode, known)
        return W.Build(F(mode or "oom", v, known), SEC, latch, now, nil, false).time.text
    end
    local L = {}
    local s0 = V(L, 25, 0)
    local same = V(L, 15, 0)
    local half = V(L, 15, 0.5)
    local one = V(L, 15, 1.0)
    local oneHalf = V(L, 15, 1.5)
    local two = V(L, 15, 2.0)
    check("4. 25 -> 15 at t = 0: 25 at 0 and 0.5, 20 at 1.0 and 1.5, 15 at 2.0",
        s0 == "25s" and same == "25s" and half == "25s" and one == "20s" and oneHalf == "20s" and two == "15s",
        table.concat({ s0, same, half, one, oneHalf, two }, ","))

    local A = {}
    V(A, 40, 0)
    local label = V(A, 20, 0.1, "full") == "FULL 20s"
    local A2 = {}
    V(A2, 40, 0)
    local gone = V(A2, nil, 0.3, "oom", "none") == "--"
    local back = V(A2, 10, 0.4) == "10s"
    local A3 = {}
    V(A3, 30, 0)
    local far = V(A3, 90, 5) == "90s"
    check("4. a label change snaps; a nil snaps and the next value snaps; a 60 s gap snaps",
        label and gone and back and far)

    local B = {}
    V(B, 30, 0, "ooc")
    local stepped = V(B, 20, 1.0, "ooc")       -- one step toward 20: 25
    local full = V(B, 0, 1.1, "ooc")           -- the face reaches 0: FULL at once
    local after = V(B, 15, 1.2, "ooc")         -- leaving FULL snaps to the face's value
    check("4. entering FULL snaps (no steps down to it), and leaving it starts afresh",
        stepped == "FULL 25s" and full == "FULL" and after == "FULL 15s",
        tostring(stepped) .. "," .. tostring(full) .. "," .. tostring(after))

    local Q = {}
    V(Q, 40, 0)
    local quiet = W.Build(F("oom", 20), SEC, Q, 0.2, nil, true).time.text
    check("4. the quiet-pool FULL snaps the latch too", quiet == "FULL" and Q.shown == nil)

    -- the alias: ManaModel.Steady is ClockWords.Steady (Forever has the model)
    if ST.ManaModel then
        local face = F("oom", 15)
        local L1, L2 = {}, {}
        W.Steady(L1, F("oom", 25), 0); ST.ManaModel.Steady(L2, F("oom", 25), 0)
        local a = W.Steady(L1, face, 1.0)
        local b = ST.ManaModel.Steady(L2, face, 1.0)
        check("4. ManaModel.Steady and its constants are ClockWords' (the alias)",
            a.value == 20 and b.value == 20 and ST.ManaModel.STEADY_SNAP == W.STEADY_SNAP
            and ST.ManaModel.STEADY_STEP == W.STEADY_STEP and ST.ManaModel.STEADY_EVERY == W.STEADY_EVERY
            and face.value == 15)
    end
end

--------------------------------------------------------------------------------
T.section("5. QuietFull (E7's rule, pure)")
--------------------------------------------------------------------------------
do
    local Q = W.QUIET
    local now, spend, base = 100, 50, 10
    check("5. QUIET is 3.0 s (VERIFY) and the points 2", Q == 3.0 and W.QUIET_POINTS == 2)
    check("5. quiet for QUIET, outside the rule, a base that moves the pool: true",
        W.QuietFull(now, now - Q, spend, base) == true)
    check("5. quiet for just under QUIET: false", W.QuietFull(now, now - Q + 0.01, spend, base) == false)
    check("5. the rule's end plus QUIET exactly: true; just inside: false",
        W.QuietFull(now, 90, now - 5 - Q, base) == true and W.QuietFull(now, 90, now - 5 - Q + 0.01, base) == false)
    check("5. inside the five-second rule: false", W.QuietFull(now, 90, now - 2, base) == false)
    check("5. base x QUIET exactly 2: true; just under: false",
        W.QuietFull(now, 90, spend, 2 / Q) == true and W.QuietFull(now, 90, spend, 2 / Q - 0.001) == false)
    check("5. nil inputs: false (no event yet, no rate, no time)",
        W.QuietFull(now, nil, spend, base) == false and W.QuietFull(now, 90, spend, nil) == false
        and W.QuietFull(nil, 90, spend, base) == false and W.QuietFull(now, 90, nil, base) == false
        and W.QuietFull(0 / 0, 90, spend, base) == false)
end

--------------------------------------------------------------------------------
T.section("6. Build with out passed allocates nothing")
--------------------------------------------------------------------------------
do
    local face = F("oom", 80, "point", { mana = 4210, manaMax = 6800, pct = 0.62, mp5 = 92, fsr = 3.2,
        manaModelled = true, pctModelled = true, second = { kind = "rest", label = "rest", value = 130 } })
    local look = { timeFmt = "mss", warn = true }
    local latch, out = {}, {}
    for i = 1, 50 do W.Build(face, look, latch, i * 0.5, out, false) end
    local first = out
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, 1000 do W.Build(face, look, latch, 25 + i * 0.5, out, false) end
    local grew = collectgarbage("count") - before
    collectgarbage("restart")
    check("6. 1000 calls with one out: the heap steady (< 1 KB)", grew < 1, string.format("%.2f KB", grew))
    check("6. the same out table comes back", W.Build(face, look, latch, 600, out, false) == first)
end

--------------------------------------------------------------------------------
T.section("7. the other kinds' words")
--------------------------------------------------------------------------------
do
    local face = F("oom", 80, "point", { mana = 4210.4, manaMax = 6800, pct = 0.619, mp5 = 92.4, fsr = 3.24,
        manaModelled = true, pctModelled = true, second = { kind = "rest", label = "rest", value = 130 } })
    local out = Words(face)
    check("7. mana 4210, mana / max 4210/6800, 62%, 92 mp5, 5SR 3.2, rest 2:10 -- no ~",
        out.mana.text == "4210" and out.manaMax.text == "4210/6800" and out.pct.text == "62%"
        and out.mp5.text == "92 mp5" and out.fsr.text == "5SR 3.2" and out.rest.text == "rest 2:10",
        table.concat({ tostring(out.mana.text), tostring(out.manaMax.text), tostring(out.pct.text),
            tostring(out.mp5.text), tostring(out.fsr.text), tostring(out.rest.text) }, ","))
    check("7. the modelled marks name the power kinds the model made",
        out.modelled.mana == true and out.modelled.manaMax == true and out.modelled.pct == true)
    local tbc = Words(F("oom", 80, "point", { mana = 100, manaMax = 200, pct = 0.5, manaModelled = false,
        pctModelled = false, timeFmt = "auto" }))
    check("7. TBC's plain reads are not modelled", tbc.modelled.mana == false and tbc.modelled.pct == false)
    local none = Words(F("oom", 80))
    check("7. no numbers: --, --/--, --%, -- mp5; no rule and no rest draw nothing",
        none.mana.text == "--" and none.manaMax.text == "--/--" and none.pct.text == "--%"
        and none.mp5.text == "-- mp5" and none.fsr.text == nil and none.rest.text == nil)
    local cd = Words(F("oom", 75, "point", { timeFmt = "auto", second = { kind = "cd", label = "inn", value = 135 } }))
    check("7. TBC's cooldown secondary in the rest text (inn 2:15)", cd.rest.text == "inn 2:15", tostring(cd.rest.text))
    local ok = true
    for _, k in ipairs(W.KINDS) do
        local p = out[k]
        local good = T.TextOK and T.TextOK(p.text or "") or (p.text or ""):match("^[\32-\123\125\126]*$") ~= nil
        if not good or (p.text or ""):find("~", 1, true) then ok = false end
    end
    check("7. every word is ASCII with no pipe and no ~", ok)
end

--------------------------------------------------------------------------------
-- Forever: the real model and the real pool
--------------------------------------------------------------------------------
if FLAVOUR == "forever" then
    local MM, Pool = ST.ManaModel, ST.Pool

    T.section("8. bug 2 from the real model")
    do
        local m = MM.New()
        m:SetMax(1000)
        m:SetRegen(20, 10)
        m:Anchor(0, 1000, "test")
        m:StartFight(0)
        m:Spend(300, 0); m:Spend(10, 1); m:Spend(10, 2)
        local t, words = 2, nil
        local latch, out = {}, {}
        local everZero, fullAt, reachedMax = false, nil, nil
        while t < 120 do
            t = t + 0.5
            local state = m:Project(t)
            local face = MM.Face(state, t)
            words = W.Build(face, SEC, latch, t, out, false).time.text
            if words == "0s" or words == "0:00" then everZero = true end
            if reachedMax == nil and state.mana >= state.max then reachedMax = t end
            if reachedMax and fullAt == nil and words == "FULL" then fullAt = t end
        end
        check("8. in a fight, regen outrunning the spend, the model at max: FULL within one tick, never 0s",
            reachedMax ~= nil and fullAt ~= nil and fullAt - reachedMax <= 0.5 and not everZero and words == "FULL",
            "max at " .. tostring(reachedMax) .. " FULL at " .. tostring(fullAt) .. " last " .. tostring(words))
        local face = MM.Face(m:Project(120), 120)
        check("8. that face is mode full, ttf 0 (the bug's face) and reads FULL",
            face.mode == "full" and face.value == 0 and W.Build(face, SEC, nil, 120).time.text == "FULL")

        local m2 = MM.New()
        m2:SetMax(1000); m2:SetRegen(20, 10); m2:Anchor(0, 1000 - 40, "test")
        local f2 = MM.Face(m2:Project(0), 0) -- out of combat, ttf 2.0
        check("8. out of combat, a refill of 2 s (shown 0) reads FULL", f2.mode == "ooc"
            and W.Build(f2, SEC, {}, 0).time.text == "FULL", tostring(f2.mode) .. " " .. tostring(f2.value))
    end

    T.section("9. the quiet pool through the real events (E7)")
    do
        local model = Pool.model
        check("9. the pool has its model, the flag ships on", model ~= nil and Pool.QUIET_FULL == true)
        if model then
            -- in a fight, so the base rate is the one set here (out of combat
            -- the pool reads the client's every tick) and the assume-full
            -- rule (out of combat only) stays out of the way
            S.inCombat = true
            S.Fire("PLAYER_REGEN_DISABLED")
            local function Reset(manaPct, base)
                model:SetRegen(base, base / 2)
                model.lastSpend = S.now - 20
                model:Anchor(S.now, model.max * manaPct, "test")
            end

            Reset(0.8, 10)
            local anchors0 = Pool.quietAnchors
            local events0 = Pool.powerEvents
            for _ = 1, 40 do -- 8 s of events every 0.2 s
                S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
                S.Tick(0.2)
            end
            check("9. events every 0.2 s: no anchor", Pool.quietAnchors == anchors0
                and model.anchor.why == "test" and Pool.powerEvents == events0 + 40,
                "anchors " .. (Pool.quietAnchors - anchors0) .. " events " .. (Pool.powerEvents - events0))

            for _ = 1, 8 do S.Tick(0.5) end -- 4 s of silence, outside the rule
            local face = ST.ManaModel.Face(Pool:Project(S.now), S.now)
            local words = W.Build(face, SEC, {}, S.now, nil, Pool:QuietFull(S.now)).time.text
            check("9. silent for QUIET outside the rule: anchored at max, the words FULL",
                Pool.quietAnchors == anchors0 + 1 and model.mana == model.max
                and model.anchor.why == "the game's pool stopped moving" and words == "FULL",
                "anchors " .. (Pool.quietAnchors - anchors0) .. " mana " .. tostring(model.mana) .. " words "
                .. tostring(words) .. " why " .. tostring(model.anchor.why))

            -- inside the rule: a spend, then silence
            Reset(0.8, 10)
            S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
            local a1 = Pool.quietAnchors
            model.lastSpend = S.now
            for _ = 1, 8 do S.Tick(0.5) end -- 4 s: still inside 5 + QUIET
            check("9. silent inside the five-second rule: no anchor", Pool.quietAnchors == a1 and model.mana < model.max)

            -- a slow base: 0.5 mana/s x 3 s < 2
            Reset(0.8, 0.5)
            S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
            local a2 = Pool.quietAnchors
            for _ = 1, 10 do S.Tick(0.5) end
            check("9. base x QUIET under 2: no anchor", Pool.quietAnchors == a2 and model.mana < model.max)

            -- the flag off
            Reset(0.8, 10)
            S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
            Pool.QUIET_FULL = false
            local a3 = Pool.quietAnchors
            for _ = 1, 10 do S.Tick(0.5) end
            local off = Pool.quietAnchors == a3 and Pool:QuietFull(S.now) == false
            Pool.QUIET_FULL = true
            check("9. with Pool.QUIET_FULL off: no anchor and no quiet answer", off)

            S.Fire("PLAYER_REGEN_ENABLED")
            S.inCombat = false
            local line
            for _, d in ipairs(ST:DumpLines()) do if d.key == "pool" then line = d.fn() end end
            check("9. the dump line counts the events and the anchors", type(line) == "string"
                and line == string.format("pool: power events %d, quiet-full anchors %d", Pool.powerEvents, Pool.quietAnchors)
                and Pool.quietAnchors >= 1, tostring(line))
        end
    end
end

T.done()
