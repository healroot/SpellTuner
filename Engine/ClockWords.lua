-- T145a (docs/SPEC-clock-v3.md 1.2, 2.2, 2.4; docs/tasks/T145a-clock-words.md):
-- the WORDS each of the clock's texts draws, from a face (Engine/ClockFace.lua's
-- record), on both lines. One pure function, ClockWords.Build, so the renderer
-- only paints strings and the words are tested apart from any frame.
--
--   ClockWords.Build(face, look, latch, now, out, quietFull) -> out
--     out.time / mana / manaMax / pct / mp5 / fsr / rest = { text, tone }
--         text nil: nothing to draw; tone "text" (the text's own colour),
--         "crit" / "warn" (the time with Warn colours), "muted"
--     out.full      true when the FULL rule held
--     out.modelled  { mana, manaMax, pct } = true where the number came from
--                   the model (the hover says so; the Bar's words carry no "~")
--   look.timeFmt "sec" ("80s") or "mss" (the face's own: Forever "1:20", TBC
--   its "auto"); look.warn false turns the time's urgency tones off. `latch`
--   (a table, Forever's) runs the T144 Steady rules; nil (TBC) shows the face's
--   own value. With `out` passed nothing is allocated: the host keeps one.
--
-- The FULL rule (P3, "at full mana the clock says FULL"): ClockWords.IsFull.
-- A refill time always carries FULL ("FULL 0:45"); an OOM time carries no word
-- (a bare number on a mana bar is the time to OOM); a time is never "0s" or
-- "0:00" -- a running-out value shown as 0 reads "OOM", a bound of 0 "--".
--
-- The quiet pool (2.4): ClockWords.QuietFull -- the client fires
-- UNIT_POWER_FREQUENT while the pool changes and stops when it is full, so a
-- silence outside the five-second rule, at a base rate that would have moved
-- the pool, means full. QUIET is VERIFY (docs/TESTING.md section 66 step 1).
--
-- PURE: Lua's library and Engine/ClockFace.lua (Time, Tone, CAP) only -- no
-- frame, no client call, no ST.db, no GetTime (every time is an argument).
-- Listed by every main TOC right after Engine/ClockFace.lua.
local _, ST = ...

ST.ClockWords = ST.ClockWords or {}
local W = ST.ClockWords

-- A face's pct at or above this is full (TBC reads its real pool; on Forever
-- the model's). A named constant, 2.2.
W.FULL_PCT = 0.995
-- A refill time under this many seconds (a shown 0 after Forever's 5 s
-- rounding) is FULL, never a countdown to zero.
W.FULL_UNDER = 5
-- The quiet pool. QUIET: seconds of no UNIT_POWER_FREQUENT that mean the
-- pool stopped moving. VERIFY (SPEC-clock-v3 2.4, R1): EllesmereUI's smooth
-- bar relies on the event firing while the pool regenerates; if the client
-- batches regen in gaps longer than this, QUIET is raised to the measured gap,
-- never guessed. QUIET_POINTS: the base rate must have brought at least this
-- much mana over QUIET, so a silence is not a slow trickle.
W.QUIET = 3.0
W.QUIET_POINTS = 2
-- T144's Steady (moved here from Engine/ManaModel.lua, which keeps aliases).
W.STEADY_SNAP = 60    -- seconds: a gap this big is a new situation
W.STEADY_STEP = 5     -- the face's own rounding
W.STEADY_EVERY = 1.0  -- seconds between two changes, at least

-- The kinds, in drawing order (UI/ClockStore.lua's texts), and the ones the
-- game can draw itself (the power path; the model's words otherwise).
W.KINDS = { "time", "mana", "manaMax", "pct", "mp5", "fsr", "rest" }
W.POWER_KINDS = { mana = true, manaMax = true, pct = true }

local function Plain(x) return type(x) == "number" and x == x end
local function Round(x) return math.floor(x + 0.5) end

-- The modes whose label is FULL: a time there is a refill time.
local FILLING = { full = true, ooc = true, fullnow = true, nodata = true }

--------------------------------------------------------------------------------
-- The FULL rule
--------------------------------------------------------------------------------
-- IsFull(face, quietFull) -> true when the clock should say FULL:
--   the pool's quiet-full signal (Forever, 2.4);
--   mode "fullnow";
--   a plain pct >= FULL_PCT;
--   mode "full" or "ooc" with a point value under FULL_UNDER (bug 2: the model
--   at max in a fight has ttf 0, and Forever's rounding shows 0 under 2.5 s).
function W.IsFull(face, quietFull)
    if quietFull == true then return true end
    if type(face) ~= "table" then return false end
    if face.mode == "fullnow" then return true end
    local p = face.pct
    if Plain(p) and p >= W.FULL_PCT then return true end
    local m, v = face.mode, face.value
    if (m == "full" or m == "ooc") and face.known == "point" and Plain(v) and v < W.FULL_UNDER then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- The quiet pool
--------------------------------------------------------------------------------
-- QuietFull(now, lastPowerEvent, lastSpend, base) -> bool. All plain numbers;
-- any one missing answers false (no event seen yet is not a silence).
function W.QuietFull(now, lastPowerEvent, lastSpend, base)
    if not (Plain(now) and Plain(lastPowerEvent) and Plain(lastSpend) and Plain(base)) then return false end
    if now - lastPowerEvent < W.QUIET then return false end
    if now - (lastSpend + 5) < W.QUIET then return false end
    if base * W.QUIET < W.QUIET_POINTS then return false end
    return true
end

--------------------------------------------------------------------------------
-- Steady (T144, docs/tasks/T144-bar-fixes-real-mana.md item 5): the shown
-- time. Within one label and mode, with a point value (known "point", a
-- number, not past 600 s), the shown value changes at most once per
-- STEADY_EVERY seconds, each change one STEADY_STEP toward the face's own
-- value. It snaps to the face's value when the label or the mode changes,
-- when the value is nil / bound / pending (or comes back from one), and when
-- the gap is STEADY_SNAP seconds or more. `latch` is the caller's table.
--------------------------------------------------------------------------------

-- SteadyValue(latch, face, now) -> the value to show (no table made).
function W.SteadyValue(latch, face, now)
    local v = face.value
    if type(latch) ~= "table" then return v end
    local point = face.known == "point" and Plain(v) and v <= 600 and Plain(now)
    if not point then
        latch.label, latch.mode, latch.shown, latch.at = face.label, face.mode, nil, nil
        return v
    end
    if latch.shown == nil or latch.label ~= face.label or latch.mode ~= face.mode
        or math.abs(v - latch.shown) >= W.STEADY_SNAP then
        latch.label, latch.mode, latch.shown, latch.at = face.label, face.mode, v, now
        return v
    end
    if v ~= latch.shown and now - latch.at >= W.STEADY_EVERY - 1e-6 then
        local step = W.STEADY_STEP
        local nextV
        if v > latch.shown then
            nextV = math.min(v, latch.shown + step)
        else
            nextV = math.max(v, latch.shown - step)
        end
        latch.shown, latch.at = nextV, now
    end
    return latch.shown
end

-- Steady(latch, face, now) -> face: T144's API (ManaModel.Steady is this). The
-- face is never changed in place: a held value comes back in a copy with its
-- tone band (OOM) re-read.
function W.Steady(latch, face, now)
    if type(latch) ~= "table" or type(face) ~= "table" then return face end
    local shown = W.SteadyValue(latch, face, now)
    if shown == face.value then return face end
    local held = {}
    for k, x in pairs(face) do held[k] = x end
    held.value = shown
    if face.mode == "oom" and face.tone ~= "muted" then held.tone = ST.ClockFace.Tone(shown) end
    return held
end

-- Entering FULL snaps: no steps down to it, and the next time starts afresh.
local function SnapFull(latch)
    if type(latch) ~= "table" then return end
    latch.label, latch.mode, latch.shown, latch.at = "FULL", "full", nil, nil
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local function Slot(out, k)
    local s = out[k]
    if type(s) ~= "table" then
        s = {}
        out[k] = s
    end
    return s
end

local function Put(s, text, tone)
    s.text, s.tone = text, tone
end

-- The time's words and tone (1.2's table, in order).
local function TimeWords(face, fmt, warn, latch, now)
    local CF = ST.ClockFace
    W.SteadyValue(latch, face, now) -- a non-point face resets the latch here
    local known = face.known
    local filling = FILLING[face.mode] == true or face.label == "FULL"
    if known == "pending" then return "...", "muted" end
    if known == "bound" then
        local v = face.value
        if not Plain(v) or v < 1 then return "--", "muted" end
        local bound
        if v <= CF.CAP then bound = CF.Time(v, fmt) else bound = "10m" end
        return ">" .. bound .. " " .. (face.arrow or "="), "muted"
    end
    if known == "point" and Plain(face.value) then
        local v = face.value
        if type(latch) == "table" and Plain(latch.shown) then v = latch.shown end
        if filling then return "FULL " .. CF.Time(v, fmt), "text" end
        local tone = "text"
        if face.unstable then
            tone = "muted"
        elseif warn then
            local band = CF.Tone(v)
            if band == "crit" or band == "warn" then tone = band end
        end
        if v < 1 then return "OOM", tone end -- out of mana now: never "0s"
        local words = CF.Time(v, fmt)
        if face.arrow then words = words .. " " .. face.arrow end
        return words, tone
    end
    if filling then return "FULL --", "muted" end
    return "--", "muted"
end

function W.Build(face, look, latch, now, out, quietFull)
    if type(out) ~= "table" then out = {} end
    for i = 1, #W.KINDS do Slot(out, W.KINDS[i]) end
    local modelled = Slot(out, "modelled")
    local hasFace = type(face) == "table"

    local fmt = "mss"
    if hasFace and type(face.timeFmt) == "string" then fmt = face.timeFmt end
    local warn = true
    if type(look) == "table" then
        if look.timeFmt == "sec" then fmt = "sec" end
        if look.warn == false then warn = false end
    end

    -- the time
    local t = out.time
    if W.IsFull(face, quietFull) then
        out.full = true
        Put(t, "FULL", "text")
        SnapFull(latch)
    elseif not hasFace then
        out.full = false
        Put(t, "--", "muted")
    else
        out.full = false
        Put(t, TimeWords(face, fmt, warn, latch, now))
    end

    if not hasFace then
        for i = 2, #W.KINDS do Put(out[W.KINDS[i]], nil, "text") end
        modelled.mana, modelled.manaMax, modelled.pct = false, false, false
        return out
    end

    -- the power kinds: the model's words (Forever) or the plain reads (TBC);
    -- the renderer draws the game's own over them where it can
    local m, mx = face.mana, face.manaMax
    if Plain(m) then Put(out.mana, tostring(Round(m)), "text") else Put(out.mana, "--", "text") end
    if Plain(m) then
        if Plain(mx) then
            Put(out.manaMax, Round(m) .. "/" .. Round(mx), "text")
        else
            Put(out.manaMax, Round(m) .. "/--", "text")
        end
    else
        Put(out.manaMax, "--/--", "text")
    end
    local p = face.pct
    if Plain(p) then Put(out.pct, Round(p * 100) .. "%", "text") else Put(out.pct, "--%", "text") end
    modelled.mana = face.manaModelled == true
    modelled.manaMax = face.manaModelled == true
    modelled.pct = face.pctModelled == true

    -- regen, the rule, the rest
    local r = face.mp5
    if Plain(r) then Put(out.mp5, Round(r) .. " mp5", "text") else Put(out.mp5, "-- mp5", "text") end
    local f = face.fsr
    if Plain(f) and f > 0 then Put(out.fsr, string.format("5SR %.1f", f), "text") else Put(out.fsr, nil, "text") end
    local sec = face.second
    if type(sec) == "table" and Plain(sec.value) and sec.value >= 1 then
        Put(out.rest, (sec.label or sec.kind or "rest") .. " " .. ST.ClockFace.Time(sec.value, fmt), "text")
    else
        Put(out.rest, nil, "text")
    end
    return out
end
