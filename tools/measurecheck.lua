-- tools/run.sh tools/measurecheck.lua
--
-- T12 (docs/tasks/T12-measure.md) / T12b (docs/tasks/T12b-measure-attribution.md):
-- the measuring session (Spells/Measure.lua) -- a cast matched to what
-- landed, judged against its own text, several watches open at once, never a
-- BELOW verdict on an amount it cannot pin to one cast. Forever only: it
-- needs UNIT_COMBAT (Facts) and MD.Book (T7), both Forever-only.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local Measure = MD.Measure

-- The fixed spellbook slots every forever suite already relies on (from
-- tools/wowstub.lua's S.UseProfile("forever")):
--   5185 Healing Touch R1: "Heals a friendly target for 40 to 55." (direct only)
--   774  Rejuvenation R1:  "Heals the target for 32 over 12 sec."  (over only)
--   5176 Wrath R1:         "Causes 13 to 16 Nature damage..."      (direct, damage)

local function LastLine()
    local list = SpellTunerDB and SpellTunerDB.measures
    return list and list[#list]
end

-- T12b: several watches can close minutes apart now (a deadline, not the
-- next amount, ends one), so a multi-watch item reads every line printed
-- since it started rather than just the last one.
local function Mark()
    return #(SpellTunerDB and SpellTunerDB.measures or {})
end
local function LinesSince(mark)
    local list = SpellTunerDB and SpellTunerDB.measures or {}
    local out = {}
    for i = mark + 1, #list do out[#out + 1] = list[i] end
    return out
end
local function FindContaining(lines, substr)
    for _, l in ipairs(lines) do
        if l:find(substr, 1, true) then return l end
    end
    return nil
end
-- Anchored at the line's own start -- "Moonfire" alone would also match a
-- Wrath line that says "ambiguous ... also fit Moonfire".
local function FindStarting(lines, prefix)
    for _, l in ipairs(lines) do
        if l:sub(1, #prefix) == prefix then return l end
    end
    return nil
end

local function AsciiCleanMultiline(s)
    if type(s) ~= "string" then return false end
    if s:find("|", 1, true) then return false end
    for line in (s .. "\n"):gmatch("(.-)\n") do
        if not line:match("^[\32-\126]*$") then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- item 1: off until asked, registers nothing until then.
--------------------------------------------------------------------------------
do
    local before = SpellTunerDB and SpellTunerDB.measures
    S.Cast(5185)
    S.Combat("player", "HEAL", 48)
    check("measuring is off until asked and registers nothing until then",
        Measure.on == false and Measure.registered == false
        and (SpellTunerDB.measures == nil or #SpellTunerDB.measures == (before and #before or 0)),
        string.format("on=%s registered=%s", tostring(Measure.on), tostring(Measure.registered)))
end

Measure:Toggle() -- switches on; this is also the first registration.

--------------------------------------------------------------------------------
-- item 2: a direct heal on yourself, in range. T12b: a watch now closes at
-- its window's end (+0.4 s grace), not on the first amount -- S.Tick past it.
--------------------------------------------------------------------------------
do
    S.Cast(5185) -- Healing Touch R1, 40-55
    S.Combat("player", "HEAL", 48)
    S.Tick(2) -- past castTime + 1.0 + 0.4 grace
    local line = LastLine()
    check("a direct heal on yourself is matched to what landed and judged against its text",
        line == "Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range",
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 3: a landed amount above the text's top -- crit range (<= max*1.5).
--------------------------------------------------------------------------------
do
    S.Cast(5185)
    S.Combat("player", "HEAL", 70) -- 55 < 70 <= 55*1.5=82.5
    S.Tick(2)
    local line = LastLine()
    check("a landed amount above the text's top is judged against the crit range",
        line ~= nil and line:find("crit range", 1, true) ~= nil, tostring(line))
end

--------------------------------------------------------------------------------
-- item 4: below the text's own minimum, with the target genuinely missing
-- that much health -- BELOW range. T12b: a heal below range is BELOW only
-- when the known deficit backs it up, so this fixture wounds the player
-- first (Facts: "+ WOUND ... on player" grows the deficit).
--------------------------------------------------------------------------------
do
    S.Combat("player", "WOUND", 100)
    S.Cast(5185)
    S.Combat("player", "HEAL", 30) -- < 40, and deficitBefore (100) >= min (40)
    S.Tick(2)
    local line = LastLine()
    check("a heal below its text's range, with the deficit to back it up, is called out",
        line ~= nil and line:find("BELOW range", 1, true) ~= nil, tostring(line))
end

--------------------------------------------------------------------------------
-- item 5: a HoT's ticks -- counted, summed, timed. Rejuvenation R1: over 32,
-- dur 12 -- four ticks of 8 sum to the whole text total. T12b: the client's
-- first tick is one period after the application, so the ticks fire at
-- 3, 6, 9, 12 s after the cast, not 0, 3, 6, 9.
--------------------------------------------------------------------------------
do
    S.Cast(774)
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=3
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=6
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=9
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=12, sum 32
    S.Tick(2) -- past castTime + dur(12) + 0.4*2 grace -> the ticker closes it
    local line = LastLine()
    check("a HoT's ticks are counted, summed and timed",
        line ~= nil and line:find("4 ticks", 1, true) ~= nil
        and line:find("8+8+8+8", 1, true) ~= nil
        and line:find("= 32", 1, true) ~= nil
        and line:find("every 3.0 s", 1, true) ~= nil
        and line:find("matches", 1, true) ~= nil,
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 6: a damage spell, matched on the target.
--------------------------------------------------------------------------------
do
    S.Cast(5176) -- Wrath R1, 13-16, cast by "player" at a target
    S.Combat("target", "WOUND", 15)
    S.Tick(4) -- past castTime + 2.5 + 0.4 grace
    local line = LastLine()
    check("a damage spell is matched on the target",
        line == "Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range",
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 7: another unit's event is not counted. T12b: the watch is no longer
-- closed by a second real amount -- it is read open, then ticked past its
-- own window, and closes on its own with nothing landed.
--------------------------------------------------------------------------------
do
    S.Cast(5185) -- opens a watch on "player"
    S.Combat("party1", "HEAL", 48) -- wrong unit, ignored
    local w = Measure:Watch()
    local stillWaiting = w ~= nil
    S.Tick(2) -- past its own window -- closes with nothing landed
    local line = LastLine()
    check("events on another unit are not counted",
        stillWaiting and line ~= nil and line:find("nothing landed", 1, true) ~= nil,
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 8: the lines are kept and dumped as one copy block, ASCII, no bare pipe.
--------------------------------------------------------------------------------
do
    local text = Measure:Dump()
    check("the lines are kept and dumped as one copy block, ASCII, no bare pipe",
        type(text) == "string" and text:find("SpellTuner", 1, true) ~= nil
        and AsciiCleanMultiline(text) and SpellTunerDB.measures and #SpellTunerDB.measures > 0,
        tostring(text and #text))
end

--------------------------------------------------------------------------------
-- item 9: a secret amount or id is counted unreadable, never judged. T12b:
-- same shape as item 7 -- read open, then ticked past the window.
--------------------------------------------------------------------------------
do
    local before = Measure.unreadable
    S.Cast(S.Secret()) -- secret id: counted, no watch opened
    S.Cast(5185) -- a normal cast, opens a watch
    S.Combat("player", "HEAL", S.Secret()) -- secret amount: counted, watch left open
    local w = Measure:Watch()
    local stillOpen = w ~= nil
    S.Tick(2) -- past its own window -- closes with nothing landed
    local line = LastLine()
    check("a secret amount or id is counted unreadable, never judged",
        Measure.unreadable == before + 2 and stillOpen
        and line ~= nil and line:find("nothing landed", 1, true) ~= nil,
        string.format("unreadable %s->%s stillOpen=%s line=%s",
            tostring(before), tostring(Measure.unreadable), tostring(stillOpen), tostring(line)))
end

-- T12b acceptance: Moonfire, a hybrid direct+over damage spell, for the
-- multi-watch items below.
S.AddSpell(8924, "Moonfire", "Rank 2",
    function() return "Burns the enemy for 11 to 15 Arcane damage and then an additional 24 Arcane damage over 12 sec." end,
    { cost = 50, level = 10 })

--------------------------------------------------------------------------------
-- item 10: a direct heal landing just before its own cast event is paired
-- with it (m2 field failure: a Healing Touch's own HEAL can arrive before or
-- in the same frame as its own UNIT_SPELLCAST_SUCCEEDED).
--------------------------------------------------------------------------------
do
    S.Combat("player", "HEAL", 48) -- at t
    S.Tick(0.1)
    S.Cast(5185) -- SUCCEEDED at t + 0.1
    S.Tick(2)
    local line = LastLine()
    check("a direct heal landing just before its own cast event is paired with it",
        line ~= nil and line:find("landed 48", 1, true) ~= nil and line:find("in range", 1, true) ~= nil,
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 11: a HoT keeps its ticks while another heal is cast, and that heal
-- is not a tick.
--------------------------------------------------------------------------------
do
    local mark = Mark()
    S.Combat("player", "WOUND", 200)
    S.Cast(774) -- Rejuvenation, t=0
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=3
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=6
    S.Tick(0.8)
    S.Cast(5185) -- Healing Touch SUCCEEDED at t=6.8
    S.Combat("player", "HEAL", 50) -- t=6.8, direct
    S.Tick(2.2)
    S.Combat("player", "HEAL", 8) -- t=9
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=12
    S.Tick(3) -- past both watches' windows
    local lines = LinesSince(mark)
    local htLine = FindContaining(lines, "Healing Touch")
    local rejLine = FindContaining(lines, "Rejuvenation")
    check("a HoT keeps its ticks while another heal is cast, and that heal is not a tick",
        htLine ~= nil and htLine:find("landed 50", 1, true) ~= nil and htLine:find("in range", 1, true) ~= nil
        and rejLine ~= nil and rejLine:find("4 ticks", 1, true) ~= nil and rejLine:find("8+8+8+8", 1, true) ~= nil
        and rejLine:find("= 32", 1, true) ~= nil and rejLine:find("every 3.0 s", 1, true) ~= nil
        and rejLine:find("matches", 1, true) ~= nil,
        string.format("ht=%s rej=%s", tostring(htLine), tostring(rejLine)))
end

--------------------------------------------------------------------------------
-- item 12: a DoT's ticks on the target are captured through the next casts.
-- The tick at t=6 lies inside Wrath's own direct window; Wrath resolves
-- first (its deadline is earlier) and claims its own hit at 4.6, so by the
-- time Moonfire closes, the 6 at t=6 is uncontested again and goes back to it.
--------------------------------------------------------------------------------
do
    local mark = Mark()
    S.Cast(8924) -- Moonfire, t=0
    S.Combat("target", "WOUND", 13) -- t=0, direct
    S.Tick(3)
    S.Combat("target", "WOUND", 6) -- t=3, tick 1
    S.Tick(1.5)
    S.Cast(5176) -- Wrath SUCCEEDED at t=4.5
    S.Tick(0.1)
    S.Combat("target", "WOUND", 15) -- t=4.6, Wrath's own direct hit
    S.Tick(1.4)
    S.Combat("target", "WOUND", 6) -- t=6, tick 2 -- inside Wrath's direct window
    S.Tick(3)
    S.Combat("target", "WOUND", 6) -- t=9, tick 3
    S.Tick(3)
    S.Combat("target", "WOUND", 6) -- t=12, tick 4
    S.Tick(3) -- past both watches' windows
    local lines = LinesSince(mark)
    local moonfireLine = FindStarting(lines, "Moonfire R2")
    local wrathLine = FindStarting(lines, "Wrath R1")
    check("a DoT's ticks on the target are captured through the next casts",
        moonfireLine ~= nil and moonfireLine:find("landed 13", 1, true) ~= nil
        and moonfireLine:find("in range", 1, true) ~= nil
        and moonfireLine:find("4 ticks", 1, true) ~= nil and moonfireLine:find("6+6+6+6", 1, true) ~= nil
        and moonfireLine:find("= 24", 1, true) ~= nil and moonfireLine:find("every 3.0 s", 1, true) ~= nil
        and moonfireLine:find("matches", 1, true) ~= nil
        and wrathLine ~= nil and wrathLine:find("landed 15", 1, true) ~= nil,
        string.format("moonfire=%s wrath=%s", tostring(moonfireLine), tostring(wrathLine)))
end

--------------------------------------------------------------------------------
-- item 13: an amount that fits two casts is ambiguous, never BELOW.
--------------------------------------------------------------------------------
do
    local mark = Mark()
    S.Cast(8924) -- Moonfire, t=0
    S.Combat("target", "WOUND", 13) -- t=0, direct
    S.Tick(2.9)
    S.Cast(5176) -- Wrath SUCCEEDED at t=2.9
    S.Tick(0.1)
    S.Combat("target", "WOUND", 6) -- t=3.0, fits both Wrath's direct window and Moonfire's tick window
    S.Tick(6) -- past Wrath's window
    S.Tick(5) -- past Moonfire's window too
    local lines = LinesSince(mark)
    local moonfireLine = FindStarting(lines, "Moonfire R2")
    local wrathLine = FindStarting(lines, "Wrath R1")
    check("an amount that fits two casts is ambiguous, never BELOW",
        wrathLine ~= nil and wrathLine:find("ambiguous", 1, true) ~= nil
        and not wrathLine:find("BELOW", 1, true)
        and moonfireLine ~= nil and not moonfireLine:find("BELOW", 1, true),
        string.format("moonfire=%s wrath=%s", tostring(moonfireLine), tostring(wrathLine)))
end

--------------------------------------------------------------------------------
-- item 14: a damage spell below its range is a possible resist, never BELOW.
--------------------------------------------------------------------------------
do
    S.Cast(5176)
    S.Combat("target", "WOUND", 7) -- ~50% of the text range
    S.Tick(4)
    local line1 = LastLine()

    S.Cast(5176)
    S.Combat("target", "WOUND", 3) -- fits no resist step within tolerance
    S.Tick(4)
    local line2 = LastLine()

    check("a damage spell below its range is a possible resist, never BELOW",
        line1 ~= nil and line1:find("below range: partial resist 50%?", 1, true) ~= nil
        and line2 ~= nil and line2:find("below range (resist?)", 1, true) ~= nil
        and not line1:find("BELOW", 1, true) and not line2:find("BELOW", 1, true),
        string.format("line1=%s line2=%s", tostring(line1), tostring(line2)))
end

--------------------------------------------------------------------------------
-- item 15: a heal below range on a target not known to be missing that much
-- is not BELOW. A fresh toggle off/on resets the known deficit to 0.
--------------------------------------------------------------------------------
do
    Measure:Toggle() -- off
    Measure:Toggle() -- on: fresh session, deficit 0
    S.Cast(5185)
    S.Combat("player", "HEAL", 30) -- < 40, deficitBefore 0
    S.Tick(2)
    local line = LastLine()
    check("a heal below range on a target not known to be missing that much is not BELOW",
        line ~= nil and line:find("below range, missing health not known (0 known)", 1, true) ~= nil
        and not line:find("BELOW", 1, true),
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 16: a heal equal to the known missing health reads as capped.
--------------------------------------------------------------------------------
do
    S.Combat("player", "WOUND", 20)
    S.Cast(5185)
    S.Combat("player", "HEAL", 20) -- amount == deficitBefore
    S.Tick(2)
    local line = LastLine()
    check("a heal equal to the known missing health reads as capped",
        line ~= nil and line:find("capped at missing health 20 (amount looks effective)", 1, true) ~= nil,
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 17: bonus healing in combat is the last reading from before combat,
-- and says so. Read out of combat by an ordinary cast (Behaviour: "the last
-- plain reading taken out of combat" -- a PLAYER_REGEN_DISABLED handler would
-- do just as well; this file reads it the simpler way, at the next cast).
--------------------------------------------------------------------------------
do
    S.bonusHealing = 12
    S.Cast(5185) -- out of combat -- primes Measure.lastBonus = 12
    S.Combat("player", "HEAL", 48)
    S.Tick(2)

    S.bonusHealingSecretInCombat = true
    S.inCombat = true
    S.Cast(5185) -- in combat -- GetSpellBonusHealing() now secret
    S.Combat("player", "HEAL", 45)
    S.Tick(2)
    local line = LastLine()
    S.inCombat = false
    S.bonusHealingSecretInCombat = false

    check("bonus healing in combat is the last reading from before combat, and says so",
        line ~= nil and line:find("+heal 12 before combat", 1, true) ~= nil, tostring(line))
end

--------------------------------------------------------------------------------
-- item 18: a HoT recast on itself ends the first watch as refreshed.
--------------------------------------------------------------------------------
do
    S.Cast(774) -- Rejuvenation, t=0
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- t=3, one tick
    S.Tick(1)
    S.Cast(774) -- recast at t=4 -- closes the first watch at once
    local line = LastLine()
    check("a HoT recast on itself ends the first watch as refreshed",
        line ~= nil and line:find("refreshed after 1 ticks", 1, true) ~= nil
        and not line:find("matches", 1, true) and not line:find("partial", 1, true)
        and not line:find("BELOW", 1, true) and not line:find("above", 1, true),
        tostring(line))
    S.Tick(15) -- close the second watch so nothing leaks past this file
end

--------------------------------------------------------------------------------
-- demonstration: the lines a scripted session printed (already echoed to
-- stdout above by MD:Print, which the stub's DEFAULT_CHAT_FRAME.AddMessage
-- forwards to print()) -- restated here from the stored copy for the Report.
--------------------------------------------------------------------------------
print("\n-- demonstration: the stored measure lines --")
for _, l in ipairs(SpellTunerDB.measures or {}) do print("  " .. l) end

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
