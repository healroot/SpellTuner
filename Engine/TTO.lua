-- Time-to-OOM / time-to-full. Model (docs/DECISIONS.md, feedback round 3):
--   spend = EWMA rate + K_SIGMA * sigma          (pessimistic edge, calibrated)
--   regen = FSR-duty-weighted GetManaRegen()     (no regime flip at the 5s edge)
--   net   = spend - regen
--   mode  = oom   (net >  sigma): tto   = mana / net
--           full  (net < -sigma): ttf   = deficit / -net
--           hold  (|net| <= sigma): one-sided bound mana / (net + sigma)
--   rest  = time to full if casting stopped NOW (exact inputs, ~zero variance)
-- Out of combat the clock is deterministic: max(observed mana gain, FSR-aware
-- GetManaRegen) so drinking reads correctly.
--
-- Display layer (tick-accumulated, render-only; the raw state above is what
-- every other module reads): digits are quantized to the model's own sigma,
-- the shown value and mode are latched (bad news instant, good news needs two
-- consecutive ticks), and the trend arrow is derived from the SHOWN value so
-- arrow and number can never contradict each other.
local _, MD = ...

local RM, ST -- bound at MD_READY (load order guarantees they exist by then)
MD:RegisterCallback("MD_READY", function()
    RM, ST = MD.Regen, MD.Spend
end)

local K_SIGMA = 1.0        -- pessimistic edge, in standard deviations
local CV_STABLE = 0.35     -- sigma/rate above this -> "~" (chain-casting sits ~0.24)
local WARMUP_CASTS = 3     -- sigma is meaningless below this many priced casts
local CAP = 600            -- seconds; beyond this the clock reads ">10m"
local FULL_PCT = 0.98

local state -- raw state, refreshed every master tick

--------------------------------------------------------------------------------
-- Raw model
--------------------------------------------------------------------------------
-- FSR-aware time to full at the current GetManaRegen rates with zero spend.
local function RestTime(mana, manaMax)
    local deficit = manaMax - mana
    if deficit <= 0 then return 0 end
    local fsr = RM:FSRRemaining()
    if fsr > 0 then
        local gained = RM.casting * fsr
        if gained >= deficit then
            return RM.casting > 0 and deficit / RM.casting or nil
        end
        if RM.base <= 0 then return nil end
        return fsr + (deficit - gained) / RM.base
    end
    if RM.base <= 0 then return nil end
    return deficit / RM.base
end

local function Compute()
    if not RM or not MD.player.usesMana then return nil end
    local mana = UnitPower("player", 0)
    local manaMax = UnitPowerMax("player", 0)
    local rate, sigma, n = ST:Estimate()
    local regen = RM:Effective()
    local pess = rate + K_SIGMA * sigma
    local net = pess - regen
    local cv = rate > 0 and sigma / rate or 0
    local s = {
        mana = mana, manaMax = manaMax,
        pct = manaMax > 0 and mana / manaMax or 1,
        regen = regen, regenNow = RM:Current(), duty = RM:Duty(),
        spend = rate, sigma = sigma, pessimistic = pess, net = net,
        casts = n, cv = cv,
        stable = n >= 5 and cv <= CV_STABLE,
        -- T58 (P14, review A28): the kernel's flag (Core.lua), set by the two
        -- regen events and seeded at MD_READY -- so a /reload mid-fight
        -- projects in combat at once, as the Forever clock already did (R36).
        inCombat = MD.inCombat == true,
        rest = RestTime(mana, manaMax),
    }
    if not s.inCombat then
        local deficit = manaMax - mana
        local ttf = s.rest
        local fill = RM:ObservedFill()
        if fill > 0 and deficit > 0 then
            local t = deficit / fill
            if not ttf or t < ttf then ttf = t end
        end
        s.ttf = ttf
        if s.pct >= FULL_PCT then
            s.mode = "fullnow"
        else
            s.mode = ttf and "ooc" or "nodata"
        end
    elseif n < WARMUP_CASTS and not ST:Seeded() then
        s.mode = "warmup"
    elseif net > sigma then
        s.mode = "oom"
        s.tto = mana / net
        -- How much to trust that number: sigma/net is the relative error of
        -- the projection. In the first dungeon log the one hard pull sat at
        -- 0.34-0.66 and every quiet pull at a median 0.73 -- the digits on the
        -- quiet ones were +-90% and changed on 79% of consecutive samples.
        -- Above db.oomConfidence the display falls back to the one-sided bound
        -- (mana / (net + sigma), "no sooner than") that hold already uses.
        -- The mode logic is untouched; only whether digits get printed changes.
        s.rel = sigma / net
        s.confident = s.rel <= ((MD.db and MD.db.oomConfidence) or 0.7)
        s.bound = mana / (net + sigma)
    elseif net < -sigma then
        s.mode = "full"
        s.ttf = (manaMax - mana) / -net
    else
        s.mode = "hold"
        if net + sigma > 0 then s.bound = mana / (net + sigma) end
    end
    -- Big mana cooldown: what the clock becomes if you press it now. The
    -- delta is already marginal over RM:Effective() (Engine/ManaCooldowns.lua),
    -- so it is simply added to the pool.
    if s.inCombat and MD.ManaCooldowns then
        local best = MD.ManaCooldowns:Best()
        if best and best.delta > 0 then
            best.tto = nil -- MC:All() caches its entries; never show a stale projection
            if s.mode == "oom" and net > 0 then
                best.tto = (mana + best.delta) / net
            elseif s.mode == "hold" and net + sigma > 0 then
                best.tto = (mana + best.delta) / (net + sigma)
            end
            s.cd = best
        end
    end

    -- sigma of the projected horizon (delta method): T * sigma / |net|
    local T = s.tto or s.ttf
    if T and s.inCombat and net ~= 0 then
        s.sigmaT = T * sigma / math.abs(net)
    end
    return s
end

-- Raw state for every consumer except the display string. Fields:
-- mana, manaMax, pct, regen (projection), regenNow, duty, spend, sigma,
-- pessimistic, net, casts, cv, stable, inCombat, rest, mode, and one of
-- tto (oom) / ttf (full, ooc) / bound (hold); sigmaT when a horizon exists;
-- cd = the richest ready mana cooldown { name, short, delta, tto, ... } or nil.
function MD:GetManaState()
    return state
end

--------------------------------------------------------------------------------
-- Display layer
--------------------------------------------------------------------------------
local LADDER = { 1, 5, 10, 15, 30, 60 }
local BETTER = { oom = 1, hold = 2, full = 3 } -- in-combat modes, worst first
local disp = { history = {} }

local function ResetDisplay(mode)
    disp.mode = mode
    disp.modeCand, disp.modeTicks = nil, 0
    disp.value, disp.cand, disp.candTicks = nil, nil, 0
    disp.step, disp.finer, disp.finerSince = nil, nil, nil
    disp.bounded, disp.confTicks, disp.stale = false, 0, false
    wipe(disp.history)
end

-- Worse news switches immediately; better news needs two consecutive ticks.
local function LatchMode(m)
    local cur = disp.mode
    if cur == m then
        disp.modeCand, disp.modeTicks = nil, 0
        return
    end
    local immediate = not (BETTER[cur] and BETTER[m]) or BETTER[m] < BETTER[cur]
    if immediate then
        ResetDisplay(m)
        return
    end
    if disp.modeCand == m then
        disp.modeTicks = disp.modeTicks + 1
    else
        disp.modeCand, disp.modeTicks = m, 1
    end
    if disp.modeTicks >= 2 then ResetDisplay(m) end
end

-- Display step = smallest ladder value >= 0.5 * sigma of the horizon, floored
-- at 1s (under a minute) / 5s, capped at 60s: the digit that moves is a digit
-- that means something. The step may coarsen at once but refines only after
-- the finer step has held for 5s, so granularity itself does not flicker.
local function ChooseStep(v, sigmaT, now)
    local floorStep = v < 60 and 1 or 5
    local want = 0.5 * (sigmaT or 0)
    local step = 60
    for _, s in ipairs(LADDER) do
        if s >= want then
            step = s
            break
        end
    end
    step = math.max(step, floorStep)
    if not disp.step or step > disp.step then
        disp.step, disp.finer, disp.finerSince = step, nil, nil
    elseif step < disp.step then
        if disp.finer ~= step then disp.finer, disp.finerSince = step, now end
        if now - disp.finerSince >= 5 then
            disp.step, disp.finer, disp.finerSince = step, nil, nil
        end
    else
        disp.finer, disp.finerSince = nil, nil
    end
    return disp.step
end

local function Quantize(v, step)
    return step * math.floor(v / step + 0.5)
end

-- The shown value changes only after a consistent quantized value is seen on
-- two consecutive ticks — except when it worsens by more than two steps or
-- crosses the 60s / 20s severity boundaries downward, which apply at once.
local function LatchValue(q, worseIsLower, step)
    local cur = disp.value
    if cur == nil or q == cur then
        disp.value, disp.cand, disp.candTicks = q, nil, 0
        return
    end
    local worse = (worseIsLower and q < cur) or (not worseIsLower and q > cur)
    if worse then
        local big = math.abs(q - cur) > 2 * step
        local crossed = worseIsLower and ((cur >= 60 and q < 60) or (cur >= 20 and q < 20))
        if big or crossed then
            disp.value, disp.cand, disp.candTicks = q, nil, 0
            return
        end
    end
    -- A candidate counts as "the same" when it lands within one step of the
    -- previous candidate: the raw horizon jitters a few % tick to tick, and
    -- demanding bit-identical quantized values could keep the shown number
    -- from ever moving (seen 2026-09-03: "FULL 2:05" stuck at a true 94s).
    if disp.cand and math.abs(q - disp.cand) <= step then
        disp.cand, disp.candTicks = q, disp.candTicks + 1
    else
        disp.cand, disp.candTicks = q, 1
    end
    if disp.candTicks >= 2 then
        disp.value, disp.cand, disp.candTicks = q, nil, 0
    end
end

MD:OnTick(function()
    state = Compute()
    if not state then
        disp.mode = nil
        return
    end
    local now = GetTime()
    LatchMode(state.mode)

    local m = disp.mode

    -- Confidence latch for the oom point estimate: drop to the bound at once
    -- (bad news), but need two confident ticks to bring the digits back, so
    -- rel hovering around the threshold does not flip the shape every tick.
    if m == "oom" and state.mode == "oom" then
        if not state.confident then
            if not disp.bounded then
                disp.bounded = true
                disp.value, disp.cand, disp.candTicks = nil, nil, 0 -- a bound is not a tto
            end
            disp.confTicks = 0
        elseif disp.bounded then
            disp.confTicks = disp.confTicks + 1
            if disp.confTicks >= 2 then
                disp.bounded = false
                disp.value, disp.cand, disp.candTicks = nil, nil, 0
            end
        end
    end

    local v, worseIsLower, sigmaT
    if m == "oom" then
        if disp.bounded then
            v, worseIsLower, sigmaT = state.bound, true, 60 -- bound: coarse by design
        else
            v, worseIsLower, sigmaT = state.tto, true, state.sigmaT
        end
    elseif m == "hold" then
        v, worseIsLower, sigmaT = state.bound, true, 60 -- bound: coarse by design
    elseif m == "full" then
        v, worseIsLower, sigmaT = state.ttf, false, state.sigmaT
    elseif m == "ooc" then
        v, worseIsLower, sigmaT = state.ttf, false, 0     -- deterministic
    end
    if v then
        local step = ChooseStep(v, sigmaT, now)
        LatchValue(Quantize(v, step), worseIsLower, step)
        disp.stale = false
    else
        -- No value for the LATCHED mode in the current state: this is the
        -- window where the mode latch is holding "oom" while the state has
        -- already moved to "hold" (which sets bound, not tto). Keep the last
        -- shown value for those two ticks instead of nil-ing it -- nil used to
        -- fall through "v or 0" into a red "OOM 0s vv" at 79% mana.
        disp.stale = true
    end

    -- shown-value history for the arrow: keep ~10s
    local h = disp.history
    h[#h + 1] = { now, disp.value }
    while h[2] and now - h[2][1] >= 10 do
        table.remove(h, 1)
    end
end)

-- Arrow from the SHOWN value over the last ~10s. A clock counting down at
-- 1s/s is "=" (steady drain); "v" = losing ground faster than that;
-- "^" = the clock went up (recovering). Dead band = one display step.
local function Arrow(now)
    local old = disp.history[1]
    if not old or old[2] == nil or disp.value == nil then return "=" end
    local elapsed = now - old[1]
    if elapsed < 8 then return "=" end
    local step = disp.step or 5
    local change = disp.value - old[2] + elapsed
    if change < -step then return "v" end
    if change > step then return "^" end
    return "="
end

--------------------------------------------------------------------------------
-- The clock's face (T88, docs/SPEC-next.md 2.4): what the display layer above
-- decided, as the pure record Engine/ClockFace.lua words. Built from `disp`
-- and `state` exactly as the display string branched before T88 (the branches
-- and their order are the old ones; only the words moved out); the string is
-- now ClockFace.LineString of this face -- the ElvUI datatext, the floating
-- widget and the minimap tooltip all render exactly that. ASCII only (WoW
-- fonts have no arrow/infinity glyphs) and NO bare "|" (it opens a colour
-- escape). tools/clockfacecheck.lua holds every string byte for byte.
--------------------------------------------------------------------------------
MD.ClockFace = MD.ClockFace or {} -- Engine/ClockFace.lua, listed first, keeps a table it finds
local CF = MD.ClockFace             -- LineString / Tone looked up at call time

-- now: the caller's GetTime(), for the arrow (the clock's own when omitted).
function MD:GetClockFace(now)
    local s = state
    local m = disp.mode
    if not s or not m then return nil end
    local v = disp.value
    -- T114: mp5 is the regen feed's number (UI/Feeds.lua RegenReading reads
    -- RM:Current() live); the state's regenNow is the last tick's and could
    -- sit up to 0.5 s on the wrong side of the rule, so it is read live too.
    local regenNow = RM and RM:Current()
    if type(regenNow) ~= "number" then regenNow = s.regenNow end
    local face = {
        mode = m, value = v, combat = s.inCombat, modelled = false, mono = false,
        unstable = false, timeFmt = "auto", pct = s.pct, pctModelled = false,
        mp5 = regenNow and regenNow * 5, mp5Modelled = false,
        fsr = RM and RM:FSRRemaining() or nil,
        mana = s.mana, manaMax = s.manaMax, manaModelled = false, -- T114: read plain
    }

    if m == "fullnow" then
        face.label, face.known, face.tone = "FULL", "none", "good"
    elseif m == "nodata" then
        face.label, face.known, face.tone = "FULL", "none", "muted"
    elseif m == "ooc" or m == "full" then
        face.label = "FULL"
        if v == nil then
            -- not reached: the latch resets the value only on a mode the raw
            -- state already holds, and ooc / full always carry ttf. Was
            -- "FULL 0s" (v or 0); a missing number is "--", never a 0.
            face.known, face.tone = "none", "muted"
        else
            face.known, face.tone = "point", "good"
        end
    elseif m == "warmup" then
        face.label, face.known, face.tone = "OOM", "pending", "muted"
    elseif m == "hold" then
        -- the one-sided bound; nil or past the cap reads ">10m"
        face.label, face.known, face.tone, face.arrow = "OOM", "bound", "muted", "="
    else -- oom
        face.label = "OOM"
        if v == nil then
            face.known, face.tone = "none", "muted"              -- never fabricate a number
        elseif disp.bounded then
            face.known, face.tone, face.arrow = "bound", "muted", "=" -- digits not trusted: the bound
        elseif v < 20 then
            face.known, face.tone, face.arrow = "point", "crit", "vv"
        else
            face.known, face.tone = "point", CF.Tone(v)
            face.unstable = not s.stable
            face.arrow = Arrow(now or GetTime())
        end
    end

    -- Secondary segment: AT MOST ONE, and never next to a FULL clock.
    --   "inn 2:10"  what the clock becomes if you press the cooldown now.
    --               Takes the slot when the clock is short (<= 90s), the
    --               cooldown is ready and it is worth at least 10% of the
    --               pool: at that point it is the only decision left, and
    --               "stop casting entirely" is the one you are least likely
    --               to take. Suppressed while the buff is already up, because
    --               GetManaRegen reports the boosted rate and the clock is
    --               then already right.
    --   "rest 2:10" time to full if you stop casting now. Hidden when it is
    --               within 25% of the primary (no decision content).
    if s.inCombat and (m == "oom" or m == "hold" or m == "warmup") then
        local cd = s.cd
        if cd and cd.tto and m == "oom" and not disp.bounded and v and v <= 90
            and cd.delta >= 0.10 * math.max(s.manaMax, 1)
            and not (MD.db and MD.db.showCooldown == false) then
            face.second = { kind = "cd", label = cd.short, value = Quantize(cd.tto, cd.tto < 60 and 5 or 15) }
        elseif s.rest and not (MD.db and MD.db.showRest == false) then
            local r = s.rest
            -- always when the primary is a bound or missing: nothing to compare against
            local show = disp.bounded or (v == nil) or (v > CAP) or (math.abs(r - v) / math.max(v, 1) >= 0.25)
            if show then
                face.second = { kind = "rest", label = "rest", value = Quantize(r, r < 30 and 1 or 5) }
            end
        end
    end
    return face
end
MD:Provide("ClockFace.Current", function(now) return MD:GetClockFace(now) end)

-- The one display string (valueHex: see ClockFace.LineString). "" before the
-- first state, as always.
function MD:GetDisplayString(valueHex)
    local face = MD:GetClockFace()
    if not face then return "" end
    return CF.LineString(face, valueHex)
end

--------------------------------------------------------------------------------
-- Debug log: mode transitions at once, a state summary every 5s in combat
-- (15s out), first summary immediately after a transition.
--------------------------------------------------------------------------------
local dbgMode, dbgAcc = nil, 0
local dbgShown, dbgShownAt = nil, nil
local function Plain(str)
    return (str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

MD:OnTick(function(dt)
    if not state or not (MD.db and MD.db.debug and MD.db.debug.enabled) then return end
    local s = state
    if s.mode ~= dbgMode then
        MD:Debug("tto", "mode %s -> %s (shown: %s)", tostring(dbgMode), s.mode, Plain(MD:GetDisplayString()))
        dbgMode = s.mode
        dbgAcc = math.huge
    end
    -- Every change of the SHOWN string, so jumpiness can be measured rather
    -- than estimated from 5s samples (79% of consecutive samples differed in
    -- the first dungeon log; how many of those were real changes is unknown).
    local shown = Plain(MD:GetDisplayString())
    if shown ~= dbgShown then
        local now = GetTime()
        if dbgShown ~= nil then
            MD:Debug("tto", "shown: '%s' (was '%s', %.1fs)", shown, dbgShown, now - (dbgShownAt or now))
        end
        dbgShown, dbgShownAt = shown, now
    end
    dbgAcc = dbgAcc + dt
    if dbgAcc >= (s.inCombat and 5 or 15) then
        dbgAcc = 0
        local T = s.tto or s.ttf or s.bound
        -- "||" draws one pipe in the console; a bare "|" is an escape (T47, B11)
        MD:Debug("tto", "%s '%s' || T %s rest %s || spend %.2f +- %.2f/s n=%d cv=%.2f || regen %.2f/s (duty %d%%, now %.2f) || net %+.2f/s%s || mana %d/%d",
            s.mode, Plain(MD:GetDisplayString()),
            T and string.format("%.0fs", T) or "-", s.rest and string.format("%.0fs", s.rest) or "-",
            s.spend, s.sigma, s.casts, s.cv, s.regen, s.duty * 100, s.regenNow, s.net,
            s.rel and string.format(" rel %.2f%s", s.rel, s.confident and "" or " BOUND") or "",
            s.mana, s.manaMax)
        if s.cd then
            MD:Debug("tto", "  cooldown ready: %s worth %d mana -> OOM %s",
                s.cd.name, s.cd.delta, s.cd.tto and string.format("%.0fs", s.cd.tto) or "-")
        end
    end
end)
