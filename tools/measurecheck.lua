-- tools/run.sh tools/measurecheck.lua
--
-- T12 (docs/tasks/T12-measure.md): the measuring session (Spells/Measure.lua)
-- -- a cast matched to what landed, judged against its own text. Forever
-- only: it needs UNIT_COMBAT (Facts) and MD.Book (T7), both Forever-only.
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
-- item 2: a direct heal on yourself, in range.
--------------------------------------------------------------------------------
do
    S.Cast(5185) -- Healing Touch R1, 40-55
    S.Combat("player", "HEAL", 48) -- closes at once: no over-time part
    local line = LastLine()
    -- Re-issue 1: the parenthesis carries both the rank's learn level and the
    -- caster's own level (S.level, the stub's default, is 64).
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
    local line = LastLine()
    check("a landed amount above the text's top is judged against the crit range",
        line ~= nil and line:find("crit range", 1, true) ~= nil, tostring(line))
end

--------------------------------------------------------------------------------
-- item 4: below the text's own minimum -- BELOW range.
--------------------------------------------------------------------------------
do
    S.Cast(5185)
    S.Combat("player", "HEAL", 30) -- < 40
    local line = LastLine()
    check("a heal below its text's range is called out",
        line ~= nil and line:find("BELOW range", 1, true) ~= nil, tostring(line))
end

--------------------------------------------------------------------------------
-- item 5: a HoT's ticks -- counted, summed, timed. Rejuvenation R1: over 32,
-- dur 12 -- four ticks of 8 sum to the whole text total.
--------------------------------------------------------------------------------
do
    S.Cast(774)
    S.Combat("player", "HEAL", 8)
    S.Tick(3)
    S.Combat("player", "HEAL", 8)
    S.Tick(3)
    S.Combat("player", "HEAL", 8)
    S.Tick(3)
    S.Combat("player", "HEAL", 8) -- sum 32 at t=9
    S.Tick(5) -- past castTime + dur(12) + 1.5s grace -> the ticker closes it
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
    local line = LastLine()
    -- Re-issue 1: a damage spell's parenthesis carries no +heal.
    check("a damage spell is matched on the target",
        line == "Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range",
        tostring(line))
end

--------------------------------------------------------------------------------
-- item 7: another unit's event is not counted.
--------------------------------------------------------------------------------
do
    S.Cast(5185) -- opens a watch on "player"
    S.Combat("party1", "HEAL", 48) -- wrong unit, ignored
    local w = Measure:Watch()
    local stillWaiting = w ~= nil and w.direct == nil
    S.Combat("player", "HEAL", 48) -- close it properly, do not leak into later items
    check("events on another unit are not counted", stillWaiting, tostring(w))
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
-- item 9: a secret amount or id is counted unreadable, never judged.
--------------------------------------------------------------------------------
do
    local before = Measure.unreadable
    S.Cast(S.Secret()) -- secret id: counted, no watch opened
    S.Cast(5185) -- a normal cast, opens a watch
    S.Combat("player", "HEAL", S.Secret()) -- secret amount: counted, watch left open
    local w = Measure:Watch()
    local untouched = w ~= nil and w.direct == nil
    S.Combat("player", "HEAL", 48) -- close it, do not leak
    check("a secret amount or id is counted unreadable, never judged",
        Measure.unreadable == before + 2 and untouched,
        string.format("unreadable %s->%s untouched=%s", tostring(before), tostring(Measure.unreadable), tostring(untouched)))
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
