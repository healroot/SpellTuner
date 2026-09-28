-- Shared v3 fixture (T13d, docs/tasks/T13d-scenario-v3.md): a hand-built v3
-- stream shaped per T13's field list (docs/tasks/T13-recorder-v3.md) --
-- player (Healroot, plain max 375) + party1 (Tank, WARRIOR/TANK, secret max),
-- 30s, the stub book's fixed Healing Touch R1 (5185, "Heals a friendly
-- target for 40 to 55" -> direct 47.5) and Rejuvenation R1/R2 (774 "...32...
-- over 12 sec" -> tick 8; 1058 "...56... over 12 sec" -> tick 14, both
-- tickPeriod 3), one untracked-kit cast (Wrath, 5176 -- a damage spell, not
-- in the healing kit at all). tools/kitcheck.lua's own comment names these
-- as "T7a's fixed five", always present in the forever stub's default book.
--
-- The own-heal events below are placed at the EXACT times/amounts
-- Engine/SimModel.lua's own HoT model produces when it replays the same own
-- casts with crit forced to 0 (assertion 9 needs the two to agree):
--  * a fresh Rejuvenation ticks starting one tickPeriod after its own cast;
--  * a recast landing while the previous application is still active does
--    NOT restart the tick timer (Engine/SimModel.lua's ApplyHot, "a refresh
--    extends a HoT; it does NOT restart its tick timer") -- so a recast (cast
--    C, 1058) lands OFF the previous application's tick boundary (1.5s after
--    its t=16 tick) and its own recorded ticks follow the OLD application's
--    continuing cadence (t=19, 22, 25, 28 -- 7 + 3k for k=4..7), at the NEW
--    rank's tick value. A foreign heal lands at the recast's own instant
--    (17.5), which is never a tick of either cadence.
--
-- A fresh table every call -- T14, T16 and T17 reuse this fixture, and none
-- may see another caller's edits. `opts.death` appends a DIED event on
-- party1; `opts.foreign` appends extra sourceless heals; `opts.meter`
-- overrides the meter table (nil is a valid override, left as `own`/`others`
-- defaults below only when the key is entirely absent from opts). `opts.
-- recastCadence` ("old", the default, or "new") picks which of the two
-- cadences Lead review 1 requires SM.AttributeHeals to accept the recast's
-- recorded ticks lands its heal events at -- "old" is what
-- Engine/SimModel.lua actually does (kept cadence); "new" is what Planner
-- ruling 2's own words describe (cast + 3k from the recast) -- a second,
-- separate stream (T13d Lead review 1 item 3) proves the ruling's own
-- cadence is also accepted, even though it never happens in the fixture used
-- for assertion 9's reproduction. `opts.chain` (Lead review 2 item 2)
-- replaces the whole event stream with THREE Rejuvenation applications on
-- the tank, each refreshed 1.5s off a tick boundary, whose recorded ticks
-- follow the engine's own kept cadence throughout -- see the branch below
-- for the arithmetic.
return function(opts)
    opts = opts or {}

    local K = { DMG = 1, HEAL = 15, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9 }

    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    local n = 0
    local function push(t, kind, tgt, amt, x)
        n = n + 1
        ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = t, kind, tgt, amt, x
    end

    if opts.chain then
        -- Lead review 2: a chain of THREE Rejuvenation applications on the
        -- tank (spell 774 throughout, tick 8, tickPeriod 3, 4 ticks), each
        -- recast 1.5s off the previous cadence's own tick boundary, so the
        -- inherited cadence must be traced back through two recasts, not
        -- one. Worked out by hand against Engine/SimModel.lua's own kept
        -- (never-reset) tick timer:
        --  * X1 at t=7 (fresh): its own cadence anchors at 10, period 3.
        --    Own ticks before the t=17.5 recast: 10, 13, 16.
        --  * X2 (recast) at t=17.5 -- OFF cast X1's own next boundary (19).
        --    Inherits X1's cadence (anchor 10): continuing ticks before the
        --    t=23.5 recast: 19, 22. X2's own fresh cadence (anchor 20.5):
        --    one tick before 23.5: 20.5.
        --  * X3 (recast) at t=23.5 -- OFF cast X2's own boundary (23.5 is
        --    itself a boundary of the ORIGINAL X1 cadence, chosen so X3
        --    lands off X2's own fresh cadence at 20.5, 23.5, 26.5, ... --
        --    23.5 IS one of those, which is the point: review 2's bug reads
        --    X2's own cadence here and gets it wrong; the fix must still
        --    inherit X1's original cadence, not X2's fresh one). Inherits
        --    X1's cadence (anchor 10, NOT X2's anchor 20.5): continuing
        --    ticks within the stream's 30s: 25, 28. X3's own fresh cadence
        --    (anchor 26.5): ticks within 30s: 26.5, 29.5.
        -- Every one of these ten heal events is own.
        push(7, K.CASTSTART, 2, 0, 774)
        push(7, K.OWNCAST, 2, 25, 774)
        push(10, K.HEAL, 2, 8, 0)
        push(13, K.HEAL, 2, 8, 0)
        push(16, K.HEAL, 2, 8, 0)

        push(17.5, K.CASTSTART, 2, 0, 774)
        push(17.5, K.OWNCAST, 2, 25, 774)
        push(19, K.HEAL, 2, 8, 0)   -- inherited from X1's cadence
        push(20.5, K.HEAL, 2, 8, 0) -- X2's own fresh cadence
        push(22, K.HEAL, 2, 8, 0)   -- inherited from X1's cadence

        push(23.5, K.CASTSTART, 2, 0, 774)
        push(23.5, K.OWNCAST, 2, 25, 774)
        push(25, K.HEAL, 2, 8, 0)   -- inherited from X1's cadence (not X2's)
        push(26.5, K.HEAL, 2, 8, 0) -- X3's own fresh cadence
        push(28, K.HEAL, 2, 8, 0)   -- inherited from X1's cadence (not X2's)
        push(29.5, K.HEAL, 2, 8, 0) -- X3's own fresh cadence

        local mana = { t = {}, v = {}, base = {}, cast = {} }
        for t = 2, 30, 2 do
            local i = #mana.t + 1
            mana.t[i], mana.v[i], mana.base[i], mana.cast[i] = t, 1000, 69.24, 28.33
        end

        return {
            v = 3, client = "forever", id = 1757000001, zone = "Blood Furnace",
            t0 = 0, dur = 30, pool = 1000,
            roster = {
                { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
                  level = 64, maxHP = 375, maxSecret = false },
                { name = "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
                  level = 64, maxHP = -1, maxSecret = true },
            },
            tracked = { 1, 2 },
            ev = ev, n = n,
            mana = mana, manaModelled = true,
            deaths = {}, restriction = {}, names = {},
            initial = {
                mana = 1000, form = "caster",
                known = { HealingTouch = 5185, Rejuvenation = 1058 },
                auras = {},
            },
            meter = { own = 200, others = 0, bySource = {}, bySpell = {}, read = "current" },
            unreadable = 0, truncated = false, raid = false, pinned = false,
        }
    end

    push(1, K.DMG, 2, 500, 0)

    -- Cast A: Healing Touch on the player (self). Direct heal lands the same
    -- instant UNIT_SPELLCAST_SUCCEEDED does (own).
    push(2, K.CASTSTART, 1, 0, 5185)
    push(2, K.OWNCAST, 1, 25, 5185)
    push(2, K.HEAL, 1, 47.5, 0)

    push(2.5, K.HEAL, 2, 100, 0) -- foreign: right time, wrong target (cast A was on the player)

    push(3, K.HEAL, 2, 8, 0) -- pre-pull Rejuvenation, tick 1 of 2 (own)

    push(4, K.DMG, 2, 300, 0)

    push(6, K.HEAL, 2, 8, 0) -- pre-pull Rejuvenation, tick 2 of 2 (own) -- it expires here

    -- Cast B: Rejuvenation R1 on the tank -- fresh (the pre-pull HoT already
    -- expired at t=6), so its ticks start at t+3.
    push(7, K.CASTSTART, 2, 0, 774)
    push(7, K.OWNCAST, 2, 25, 774)
    push(10, K.HEAL, 2, 8, 0) -- cast B tick 1 (own)

    push(11.5, K.HEAL, 2, 30, 0) -- foreign: lands between two ticks

    push(13, K.HEAL, 2, 8, 0) -- cast B tick 2 (own)
    push(16, K.HEAL, 2, 8, 0) -- cast B tick 3 (own) -- still before the recast

    -- Cast C: Rejuvenation R2 on the tank, timed to land 1.5s OFF cast B's
    -- own next tick boundary (7 + 3*4 = 19) -- a recast that does not land on
    -- a tick, so the two cadences (old/continuing vs new/from-the-recast)
    -- disagree and only one is what actually happened.
    local recastCadence = opts.recastCadence or "old"
    push(17.5, K.CASTSTART, 2, 0, 1058)
    push(17.5, K.OWNCAST, 2, 40, 1058)
    push(17.5, K.HEAL, 2, 5, 0) -- foreign: lands at the recast's own instant, not a tick of either cadence

    -- Wrath: a damage spell the healing kit has no slot for -- a fixed point
    -- (kind "damage" from the book), not a healing script entry.
    push(20, K.CASTSTART, 2, 0, 5176)
    push(20, K.OWNCAST, 2, 20, 5176)

    if recastCadence == "new" then
        -- Planner ruling 2's own words: cast + 3k from the recast.
        push(20.5, K.HEAL, 2, 14, 0) -- cast C tick 1 (own, new cadence)
        push(23.5, K.HEAL, 2, 14, 0) -- cast C tick 2 (own, new cadence)
        push(26.5, K.HEAL, 2, 14, 0) -- cast C tick 3 (own, new cadence)
        push(29.5, K.HEAL, 2, 14, 0) -- cast C tick 4 (own, new cadence)
    else
        -- Engine/SimModel.lua's actual behaviour: cast B's own cadence keeps
        -- ticking (7 + 3k for k=4..7), at the NEW rank's tick value.
        push(19, K.HEAL, 2, 14, 0) -- cast C tick 1 (own, old/continuing cadence)
        push(22, K.HEAL, 2, 14, 0) -- cast C tick 2 (own, old/continuing cadence)
        push(25, K.HEAL, 2, 14, 0) -- cast C tick 3 (own, old/continuing cadence)
        push(28, K.HEAL, 2, 14, 0) -- cast C tick 4 (own, old/continuing cadence)
    end

    if opts.death then
        push(opts.death, K.DIED, 2, 0, 0)
    end
    for _, extra in ipairs(opts.foreign or {}) do
        push(extra.t, K.HEAL, extra.tgt, extra.amt, 0)
    end

    local mana = { t = {}, v = {}, base = {}, cast = {} }
    for t = 2, 30, 2 do
        local i = #mana.t + 1
        mana.t[i], mana.v[i], mana.base[i], mana.cast[i] = t, 1000, 69.24, 28.33
    end

    local meter = opts.meter
    if opts.meter == nil and opts.meterOverridden ~= true then
        meter = { own = 400, others = 0, bySource = {}, bySpell = {}, read = "current" }
    end

    return {
        v = 3, client = "forever", id = 1757000000, zone = "Blood Furnace",
        t0 = 0, dur = 30, pool = 1000,
        roster = {
            { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
              level = 64, maxHP = 375, maxSecret = false },
            { name = "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
              level = 64, maxHP = -1, maxSecret = true },
        },
        tracked = { 1, 2 },
        ev = ev, n = n,
        mana = mana, manaModelled = true,
        deaths = {}, restriction = {}, names = {},
        initial = {
            mana = 1000, form = "caster",
            known = { HealingTouch = 5185, Rejuvenation = 1058 },
            -- T13d's lead hand-out amendment: `tgt` is the roster index (2, the tank).
            auras = { { token = "party1", spellId = 774, remaining = 6, stacks = 1, tgt = 2 } },
        },
        meter = meter, unreadable = 0, truncated = false, raid = false, pinned = false,
    }
end
