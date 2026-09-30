-- The regen instruments (TBC TOC only): /md fsrtest logs mana ticks for 15s to
-- pin down the five-second-rule anchor, /md regentest measures idle regen
-- against GetManaRegen (Dreamstate check, the tick histogram) and /md spamtest
-- checks the dashboard's To OOM column. /md regentest is the ONLY writer of
-- `cdb.mp5` (the measured leftover Engine/RegenModel.lua's RM:MeasuredMp5()
-- reads); its shape and the "leftover <= what the client reports" bound are
-- below. RegenModel keeps its own copy of that bound and its once-only refusal
-- message (docs/PLAN-refactor-ux.md section 6: sharing it is a later change).
--
-- T56 (P12, review A2): moved out of Verify.lua unchanged.
local _, MD = ...

--------------------------------------------------------------------------------
-- FSR anchor test: log every player mana change with a timestamp for 15s.
--------------------------------------------------------------------------------
local fsrLogging = false
local fsrT0, fsrLast = 0, 0

-- Registered once; inert unless a test is running.
MD:On("UNIT_POWER_UPDATE", function(unit, powerType)
    if not fsrLogging or unit ~= "player" or powerType ~= "MANA" then return end
    local cur = UnitPower("player", 0)
    if cur ~= fsrLast then
        MD:Print(string.format("  t+%5.2fs  %+d  (-> %d)", GetTime() - fsrT0, cur - fsrLast, cur))
        fsrLast = cur
    end
end)

function MD:RunFSRTest()
    if fsrLogging then return end
    fsrLogging = true
    fsrT0 = GetTime()
    fsrLast = UnitPower("player", 0)
    MD:Print("fsrtest: logging mana changes for 15s - cast one spell now.")
    C_Timer.After(15, function()
        fsrLogging = false
        MD:Print("fsrtest: done.")
    end)
end

--------------------------------------------------------------------------------
-- Idle regen test (/md regentest [seconds]): does the RAW GetManaRegen()
-- include Dreamstate? Stand idle at partial mana, no drink, no casting. The
-- window starts once the five-second rule has ended (so the API side is a
-- single rate), observed mana gain is compared with the raw API base rate
-- and with the model rate (API + whatever RegenModel adds), and the raw
-- difference is matched against the talent's expected contribution
-- (4/7/10% of Intellect per 5s). Mana spent or a drink buff during the
-- window invalidates the result (reported, not hidden).
--
-- It also prints a TICK HISTOGRAM: every distinct gain size with its count and
-- median spacing. That is what identifies an energize the API is blind to --
-- the BF-1 log carried a constant 17 every 2.00s next to the spirit tick
-- (42 mp5, all 28 minutes, in and out of combat) that GetManaRegen never
-- reported. A size is what a source is; a cadence is which source it is.
-- See docs/TESTING.md 16.
--------------------------------------------------------------------------------
local DREAMSTATE_PCT = { 0.04, 0.07, 0.10 }
local regenTest = nil

local function IsDrinking()
    return MD:HasBuff("Drink") or MD:HasBuff("Refreshment") or MD:HasBuff("Food & Drink")
end

--------------------------------------------------------------------------------
-- Storing the measurement (v0.9.0, corrected in v0.9.5). What is stored is the
-- RESIDUAL: the observed regen rate minus what the client reports, minus what
-- the model already adds for Dreamstate, minus anything the histogram
-- identified as somebody else's 3s party energize.
--
--   unreported = observed - GetManaRegen - Dreamstate - party
--
-- The first version stored the SIZE OF THE TICK instead, off a cluster the
-- histogram had labelled "a 2s beat the API does not report". On a druid with
-- Dreamstate that label is wrong: Dreamstate rides inside the same server tick,
-- so the one and only tick reads ~14% above the raw API rate, gets called a
-- separate stream, and its whole size is stored. The author's character ended
-- up with 279 mp5 of "unreported" regen on top of a 244 mp5 API rate -- a 556
-- mp5 datatext for a druid regenerating 279. A term the API does not report can
-- only ever be what is LEFT OVER after everything that is reported; anything
-- else double counts by construction.
--
-- Stored only from a clean window: nothing spent, no drink, out of the
-- five-second rule throughout, enough ticks to average, and SOLO -- in a group
-- somebody's blessing lands in the same bucket. Below MP5_FLOOR the residual is
-- indistinguishable from the test's own precision, so nothing is stored and any
-- previous measurement is CLEARED: "the model already accounts for everything"
-- is a result, and leaving a stale number in place would hide it.
--------------------------------------------------------------------------------
local MP5_MIN_TICKS = 6
local MP5_FLOOR = 1.0     -- mana/s (5 mp5). The tick sizes vary by +-1 and a 30s
                          -- window holds ~15 of them, so the test itself is good
                          -- to about 0.5/s; half of that again is noise.

local function ClearMeasured(reason)
    if not (MD.cdb and MD.cdb.mp5) then return false end
    local prev = MD.cdb.mp5
    MD.cdb.mp5 = nil
    if MD.Regen then MD.Regen:Refresh() end
    MD:Print(string.format("regentest: |cffffcc00cleared|r the stored %d mp5 (measured %s) - %s.",
        prev.mp5 or 0, date("%Y-%m-%d", prev.at or 0), reason))
    return true
end

function MD:ClearMeasuredMp5()
    if not ClearMeasured("you asked") then
        MD:Print("regentest: nothing stored to clear.")
    end
end

-- t: the finished test. observed/api/ds/party are all mana per second.
local function StoreMeasuredMp5(t, elapsed, observed, api, ds, party)
    local solo = (GetNumGroupMembers and GetNumGroupMembers() or 1) <= 1
    local why = nil
    if not MD.cdb then why = "no character database yet"
    elseif t.spent > 0 then why = string.format("%d mana was spent during the window", t.spent)
    elseif t.drank then why = "a drink/food buff was up"
    elseif t.fsrTime > 0.5 then why = string.format("%.1fs of the window were inside the 5SR", t.fsrTime)
    elseif t.ticks < MP5_MIN_TICKS then why = string.format("%d regen tick(s) seen, needs %d", t.ticks, MP5_MIN_TICKS)
    elseif not solo then why = "you are in a group - somebody else's blessing would be measured in"
    end
    if why then
        MD:Print("regentest: not stored - " .. why .. ". Nothing was changed.")
        return
    end

    local unreported = observed - api - ds - party
    MD:Print(string.format("regentest: observed %.2f/s = API %.2f + Dreamstate %.2f%s + unreported %+.2f (%+d mp5)",
        observed, api, ds, party > 0 and string.format(" + party %.2f", party) or "",
        unreported, unreported * 5 + (unreported >= 0 and 0.5 or -0.5)))

    if unreported > api and api > 0 then
        MD:Print(string.format("regentest: |cffff4444not stored|r - the leftover (%d mp5) is larger than everything " ..
            "the client reports (%d mp5). That is a broken measurement, not a discovery.",
            unreported * 5 + 0.5, api * 5 + 0.5))
        return
    end
    if unreported < MP5_FLOOR then
        MD:Print(string.format("regentest: nothing to store - the model already accounts for everything the client " ..
            "regenerates (leftover %+d mp5, under the %d mp5 floor this test can resolve).",
            unreported * 5 + (unreported >= 0 and 0.5 or -0.5), MP5_FLOOR * 5))
        ClearMeasured("the leftover is now inside the noise floor")
        return
    end

    local prev = MD.cdb.mp5
    MD.cdb.mp5 = {
        perSec = unreported, mp5 = math.floor(unreported * 5 + 0.5), at = time(),
        source = "regentest", ticks = t.ticks, level = UnitLevel("player") or 0,
        hint = GetRealZoneText and GetRealZoneText() or nil,
        window = elapsed, solo = solo,
        observed = observed, api = api, dreamstate = ds, party = party,
    }
    if MD.Regen then MD.Regen:Refresh() end
    MD:Print(string.format("regentest: |cff33ff66stored %d mp5|r (%.2f/s left over after the API and Dreamstate, " ..
        "%d ticks over %.0fs) - was: %s.", MD.cdb.mp5.mp5, unreported, t.ticks, elapsed,
        prev and string.format("%d mp5 measured %s", prev.mp5 or 0, date("%Y-%m-%d", prev.at or 0)) or "none"))
end

local function FinishRegenTest(reason)
    local t = regenTest
    regenTest = nil
    if not t then return end
    if not t.t0 then
        MD:Print("regentest: stopped while waiting for the 5SR to end (" .. reason .. ") - nothing measured.")
        return
    end
    local elapsed = GetTime() - t.t0
    if elapsed < 4 then
        MD:Print(string.format("regentest: stopped after %.1fs (%s) - too short, nothing measured.", elapsed, reason))
        return
    end
    local observed = t.gained / elapsed
    local api = t.apiSum / elapsed        -- time-weighted raw GetManaRegen base
    local model = t.modelSum / elapsed    -- time-weighted RM.base (API + unreported)
    local diff = observed - api
    local intellect = UnitStat("player", 4) or 0
    local dsRank = MD:TalentRank("Dreamstate")
    local dsRate = (DREAMSTATE_PCT[dsRank] or 0) * intellect / 5

    MD:Print(string.format("regentest: %.0fs (%s), %d mana in %d ticks -> observed %.2f/s (%d mp5); " ..
        "raw API %.2f/s (%d mp5); diff %+.2f/s (%+d mp5); model %.2f/s (%d mp5), observed - model %+.2f/s",
        elapsed, reason, t.gained, t.ticks, observed, observed * 5 + 0.5, api, api * 5 + 0.5, diff, diff * 5,
        model, model * 5 + 0.5, observed - model))
    if t.spent > 0 then
        MD:Print(string.format("|cffff4444WARNING|r %d mana was spent during the test (5SR reset) - result unreliable.", t.spent))
    end
    if t.fsrTime > 0.5 then
        MD:Print(string.format("|cffff4444WARNING|r %.1fs of the window were inside the 5SR - result unreliable.", t.fsrTime))
    end
    if t.drank then
        MD:Print("|cffff4444WARNING|r a drink/food buff was up during the test - result unreliable.")
    end
    if t.ticks < 3 then
        MD:Print("|cffff4444WARNING|r fewer than 3 regen ticks observed - were you at full mana?")
    end
    -- Tick histogram. The whole point of a size/cadence table is that a
    -- periodic energize the API does not report (item mp5, Blessing of Wisdom,
    -- a party effect) shows up as its OWN constant next to the spirit tick.
    -- Sizes are clustered within +-1, because an energize proportional to
    -- somebody else's damage jitters by a point or two while a mana tick does
    -- not, and each cluster is tested for a beat the way the BF-1 log was
    -- decomposed by hand: the share of its events that have a partner exactly
    -- one period later. Interleaved phases of the same source ruin a median
    -- spacing (four overlapping 3s streams read as ~1s) but not this.
    local sizes = {}
    for size in pairs(t.sizes) do sizes[#sizes + 1] = size end
    table.sort(sizes)
    local clusters = {}
    for _, size in ipairs(sizes) do
        local b = t.sizes[size]
        local c = clusters[#clusters]
        if not (c and size - c.hi <= 1) then
            c = { lo = size, hi = size, n = 0, sum = 0, ts = {} }
            clusters[#clusters + 1] = c
        end
        c.hi, c.n, c.sum = size, c.n + b.n, c.sum + size * b.n
        for _, ts in ipairs(b.ts) do c.ts[#c.ts + 1] = ts end
    end
    table.sort(clusters, function(a, b) return a.n > b.n end)

    -- The rate one stream of ticks actually carries, without the window's edges
    -- in it. Dividing a cluster's whole mana by the whole window is biased by up
    -- to one tick -- 111 mana over 30s is 3.7/s, which is bigger than the
    -- leftover this test is trying to resolve. Between the FIRST and LAST tick
    -- of a stream there are exactly n-1 intervals, so dropping one tick's worth
    -- of mana and dividing by that span is unbiased.
    --
    -- Interleaved phases of one source (four overlapping 3s streams in the BF-1
    -- log) need p ticks dropped, not one: p is how many the cluster has more
    -- than a single phase could fit in its own span.
    local function ClusterRate(c, period)
        if c.n < 2 then return 0 end
        local span = c.ts[#c.ts] - c.ts[1]
        if span <= 0 then return 0 end
        local mean = c.sum / c.n
        local phases = 1
        if period and period > 0 then
            local perPhase = span / period + 1
            if perPhase > 0.5 then phases = math.max(1, math.floor(c.n / perPhase + 0.5)) end
        end
        return (c.sum - phases * mean) / span
    end

    -- share of events with a partner at +period (+-0.15s)
    local function beat(ts, period)
        local hits = 0
        for i = 1, #ts do
            for j = i + 1, #ts do
                local d = ts[j] - ts[i]
                if d > period + 0.15 then break end
                if d >= period - 0.15 then hits = hits + 1; break end
            end
        end
        return hits / #ts
    end

    -- Mana per second that belongs to somebody else: a cluster on a 3s beat is
    -- a party energize (the BF-1 log's second stream), and it must not end up
    -- in this character's own bucket.
    local party, ticked = 0, 0
    if #clusters > 0 then
        -- What a 2s tick of everything the model ALREADY knows about weighs.
        -- Dreamstate is not a separate stream: the server folds it into the
        -- same regen tick, so comparing against the raw API rate alone reads the
        -- one true tick as an unexplained beat -- which is the bug that stored
        -- 279 mp5 on a character regenerating 279 in total (v0.9.5).
        local expected = (t.apiSum / elapsed + dsRate) * 2
        MD:Print("regentest: tick histogram (size x count, cadence) -")
        for i = 1, math.min(#clusters, 6) do
            local c = clusters[i]
            table.sort(c.ts)
            local mean = c.sum / c.n
            local label = c.lo == c.hi and tostring(c.lo) or string.format("%d-%d", c.lo, c.hi)
            local b2, b3 = beat(c.ts, 2.0), beat(c.ts, 3.0)
            local period = (b3 >= 0.4 and b3 > b2) and 3.0 or (b2 >= 0.4 and 2.0 or nil)
            local rate = ClusterRate(c, period)
            ticked = ticked + rate
            local note
            if expected > 0 and math.abs(mean - expected) <= 0.12 * expected then
                note = dsRate > 0 and "the regen tick the model expects (spirit + gear + Dreamstate)"
                    or "the reported spirit tick"
            elseif b3 >= 0.4 and b3 > b2 then
                note = string.format("a 3s beat - a party energize, not yours (%d mp5)", rate * 5 + 0.5)
                party = party + rate
            elseif b2 >= 0.4 then
                note = string.format("a 2s beat of %d mana - a stream of its own (%d mp5)", mean + 0.5, rate * 5 + 0.5)
            elseif c.n > 2 then
                note = string.format("no clean beat (2s %d%%, 3s %d%%)", b2 * 100, b3 * 100)
            else
                note = "seen too few times to read a cadence"
            end
            MD:Print(string.format("    %7s x %-3d  %s", label, c.n, note))
        end
    end
    -- the rate the TICKS carry (edge-free), not the window's endpoints
    StoreMeasuredMp5(t, elapsed, ticked > 0 and ticked or observed, api, dsRate, party)

    if dsRank == 0 then
        MD:Print(string.format("no Dreamstate talent: diff should be ~0 (it is %+.2f/s). A large positive diff means " ..
            "GetManaRegen misses some regen source.", diff))
    elseif diff >= 0.5 * dsRate then
        MD:Print(string.format("|cffffcc00VERDICT|r raw GetManaRegen EXCLUDES Dreamstate: diff %.2f/s vs expected %.2f/s " ..
            "(Dreamstate %d = %d%% of %d int / 5s). The model adds %.2f/s for it.", diff, dsRate, dsRank,
            DREAMSTATE_PCT[dsRank] * 100, intellect, MD.Regen.unreported))
    else
        MD:Print(string.format("|cffffcc00VERDICT|r raw GetManaRegen INCLUDES Dreamstate: diff %.2f/s, it would be ~%.2f/s " ..
            "if excluded (Dreamstate %d, %d int). The model's %.2f/s Dreamstate term would then double count!",
            diff, dsRate, dsRank, intellect, MD.Regen.unreported))
    end
end

-- Registered once; inert unless a test is measuring.
MD:On("UNIT_POWER_UPDATE", function(unit, powerType)
    if not regenTest or not regenTest.t0 or unit ~= "player" or powerType ~= "MANA" then return end
    local cur = UnitPower("player", 0)
    local delta = cur - regenTest.last
    regenTest.last = cur
    if delta > 0 then
        regenTest.gained = regenTest.gained + delta
        regenTest.ticks = regenTest.ticks + 1
        local b = regenTest.sizes[delta]
        if not b then b = { n = 0, ts = {} }; regenTest.sizes[delta] = b end
        b.n = b.n + 1
        b.ts[#b.ts + 1] = GetTime()
        if cur >= UnitPowerMax("player", 0) then
            FinishRegenTest("mana full")
        end
    elseif delta < 0 then
        regenTest.spent = regenTest.spent + (-delta)
    end
end)

MD:OnTick(function(dt)
    if not regenTest then return end
    local RM = MD.Regen
    if UnitAffectingCombat("player") then
        FinishRegenTest("entered combat")
        return
    end
    if not regenTest.t0 then
        if RM:InFSR() then return end
        regenTest.t0 = GetTime()
        regenTest.last = UnitPower("player", 0)
        MD:Print(string.format("regentest: 5SR over, measuring for %ds now - stand still.", regenTest.duration))
        return
    end
    regenTest.apiSum = regenTest.apiSum + RM.apiBase * dt
    regenTest.modelSum = regenTest.modelSum + RM.base * dt
    if RM:InFSR() then regenTest.fsrTime = regenTest.fsrTime + dt end
    if IsDrinking() then regenTest.drank = true end
    if GetTime() - regenTest.t0 >= regenTest.duration then
        FinishRegenTest("done")
    end
end)

function MD:RunRegenTest(seconds)
    if tostring(seconds or ""):lower():match("^clear") then
        MD:ClearMeasuredMp5()
        return
    end
    if regenTest then
        MD:Print("regentest: already running.")
        return
    end
    seconds = tonumber(seconds) or 30
    if seconds < 10 then seconds = 10 end
    if UnitAffectingCombat("player") then
        MD:Print("regentest: leave combat first.")
        return
    end
    local mana, manaMax = UnitPower("player", 0), UnitPowerMax("player", 0)
    if mana >= manaMax then
        MD:Print("regentest: you are at full mana - spend some first (a few casts), then run it again.")
        return
    end
    local RM = MD.Regen
    regenTest = {
        t0 = nil, duration = seconds, last = mana,
        gained = 0, ticks = 0, spent = 0, apiSum = 0, modelSum = 0, fsrTime = 0, drank = IsDrinking(),
        sizes = {}, -- [gain] = { n, ts = {} }
    }
    MD:Print(string.format("regentest: %ds - do not cast or drink. Mana %d/%d, raw API base %.2f/s, model %.2f/s, " ..
        "Dreamstate %d, int %d, %s%s.", seconds, mana, manaMax, RM.apiBase, RM.base,
        MD:TalentRank("Dreamstate"), UnitStat("player", 4) or 0,
        MD.db.debug.enabled and "debug log on" or "debug log OFF (enable it in the Debug Console to keep the ticks)",
        RM:InFSR() and string.format("; waiting %.1fs for the 5SR to end", RM:FSRRemaining()) or ""))
end

--------------------------------------------------------------------------------
-- Spam test (/md spamtest): validates the dashboard's "To OOM" column. Arm
-- it, then chain-cast ONE spell until you are out of mana (or stop for 10s).
-- Counts the casts, the real per-cast drops and the regen that landed, and
-- compares with the prediction made from the mana you had when you armed it.
--------------------------------------------------------------------------------
local spamTest = nil

local function FinishSpamTest(reason)
    local t = spamTest
    spamTest = nil
    if not t then return end
    if t.casts == 0 then
        MD:Print("spamtest: no cast seen (" .. reason .. ").")
        return
    end
    local name = GetSpellInfo(t.spellID) or "?"
    local duration = (t.lastCastT or t.firstCastT) - t.firstCastT
    local interval = t.casts > 1 and duration / (t.casts - 1) or t.interval
    local avgDrop = t.spent / math.max(t.casts, 1)
    local mana = UnitPower("player", 0)
    MD:Print(string.format("spamtest (%s): %d casts of %s (%d) in %.1fs (%.2fs apart) - %d mana spent (%.1f per cast, live cost %d), " ..
        "%d regained; mana %d -> %d.", reason, t.casts, name, t.spellID, duration, interval, t.spent, avgDrop, t.liveCost, t.gained,
        t.armMana, mana))
    local predicted = MD.RankMath:CastsToOOM(t.liveCost, t.interval, t.armMana, t.castingRegen)
    local predictedReal = MD.RankMath:CastsToOOM(avgDrop, interval, t.armMana, t.gained / math.max(duration, 1))
    MD:Print(string.format("prediction from %d mana: %s casts (live cost %d, %.1fs interval, casting regen %.2f/s); " ..
        "with the MEASURED drop and regen it would be %s. Observed regen during the spam: %.2f/s.",
        t.armMana, predicted == math.huge and "inf" or tostring(predicted), t.liveCost, t.interval, t.castingRegen,
        predictedReal == math.huge and "inf" or tostring(predictedReal), t.gained / math.max(duration, 1)))
    if math.abs(avgDrop - t.liveCost) > 1 then
        MD:Print(string.format("|cffffaa33NOTE|r the real drop per cast (%.1f) differs from the live cost (%d) - that is the column's error source.",
            avgDrop, t.liveCost))
    end
    if t.otherCasts > 0 then
        MD:Print(string.format("|cffffaa33NOTE|r %d cast(s) of other spells were mixed in and counted in the mana spent.", t.otherCasts))
    end
end

MD:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if not spamTest or unit ~= "player" or type(spellID) ~= "number" then return end
    local now = GetTime()
    if not spamTest.spellID then
        local cost = MD.SpellData:GetCost(spellID)
        if not cost or cost <= 0 then return end -- ignore free/unknown (form shift etc.)
        spamTest.spellID = spellID
        spamTest.liveCost = cost
        local _, _, _, castMs = GetSpellInfo(spellID)
        spamTest.interval = math.max((castMs or 0) / 1000, 1.5)
        spamTest.firstCastT = now
        MD:Print(string.format("spamtest: counting %s (live cost %d, %.1fs interval) - keep casting until OOM.",
            GetSpellInfo(spellID) or "?", cost, spamTest.interval))
    end
    if spellID == spamTest.spellID then
        spamTest.casts = spamTest.casts + 1
        spamTest.lastCastT = now
    else
        spamTest.otherCasts = spamTest.otherCasts + 1
    end
end)

MD:On("UNIT_POWER_UPDATE", function(unit, powerType)
    if not spamTest or unit ~= "player" or powerType ~= "MANA" then return end
    local cur = UnitPower("player", 0)
    local delta = cur - spamTest.last
    spamTest.last = cur
    if delta < 0 then
        spamTest.spent = spamTest.spent - delta
    elseif delta > 0 then
        spamTest.gained = spamTest.gained + delta
    end
end)

MD:OnTick(function()
    if not spamTest then return end
    local now = GetTime()
    if spamTest.spellID then
        if UnitPower("player", 0) < spamTest.liveCost then
            FinishSpamTest("OOM")
        elseif now - spamTest.lastCastT > 10 then
            FinishSpamTest("stopped")
        end
    elseif now - spamTest.armT > 30 then
        FinishSpamTest("timed out waiting for the first cast")
    end
end)

function MD:RunSpamTest()
    if spamTest then
        MD:Print("spamtest: already armed.")
        return
    end
    local mana = UnitPower("player", 0)
    spamTest = {
        armT = GetTime(), armMana = mana, last = mana,
        castingRegen = MD.Regen.casting,
        casts = 0, otherCasts = 0, spent = 0, gained = 0,
    }
    MD:Print(string.format("spamtest: armed at %d mana (casting regen %.2f/s). Chain-cast ONE spell now until OOM; " ..
        "the dashboard's To OOM column for it should match.", mana, MD.Regen.casting))
end
