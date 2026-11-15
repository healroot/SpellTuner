-- tools/run.sh [--flavour f] tools/perf/<this>.lua -- not a suite (make check skips tools/perf/). resident memory after login, data tables by class, garbage per tick / per event
HARNESS_FLAVOUR = HARNESS_FLAVOUR or "forever"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", "")) -- tools/, from tools/perf/
collectgarbage("collect")
local base = collectgarbage("count")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
collectgarbage("collect")
local loaded = collectgarbage("count")
print(string.format("after load+login: %.0f KB (harness+stub+addon; base before %.0f KB)", loaded, base))

local function SizeOf(t, seen)
    -- rough: count tables and string bytes reachable
    seen = seen or {}
    if type(t) == "string" then return #t + 24 end
    if type(t) ~= "table" or seen[t] then return 0 end
    seen[t] = true
    local n = 40
    for k, v in pairs(t) do n = n + 16 + SizeOf(k, seen) + SizeOf(v, seen) end
    return n
end
for _, key in ipairs({ "TalentTree", "FutureRanks", "CoefRules", "TalentRules", "TalentMults", "Profiles" }) do
    local t = ST[key]
    if type(t) == "table" then
        local own = ST.player and ST.player.class
        local mine = (type(t[own]) == "table") and SizeOf(t[own]) or 0
        print(string.format("ST.%-12s ~%6.0f KB total, player's class (%s) ~%5.0f KB", key, SizeOf(t) / 1024,
            tostring(own), mine / 1024))
    end
end

-- garbage per tick, out of combat and in combat
local function Garbage(label, n, fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local m0 = collectgarbage("count")
    for i = 1, n do fn(i) end
    local m1 = collectgarbage("count")
    collectgarbage("restart")
    print(string.format("%-40s %7.2f KB per call (%d calls)", label, (m1 - m0) / n, n))
end
Garbage("tick 0.5 s, out of combat", 200, function() S.Tick(0.5) end)
S.inCombat = true
if S.Fire then S.Fire("PLAYER_REGEN_DISABLED") end
Garbage("tick 0.5 s, in combat", 200, function() S.Tick(0.5) end)
Garbage("UNIT_AURA player", 200, function() S.Fire("UNIT_AURA", "player") end)
Garbage("UNIT_POWER_FREQUENT player", 200, function() S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end)
Garbage("UNIT_SPELLCAST_SUCCEEDED (HT r1)", 50, function(i) S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g" .. i, 5185) end)
Garbage("UNIT_HEALTH party1", 200, function() S.Fire("UNIT_HEALTH", "party1") end)
S.inCombat = false
if S.Fire then S.Fire("PLAYER_REGEN_ENABLED") end
if ST.Book and ST.Book.MarkDirty then
    Garbage("Book scan (forced)", 50, function() ST.Book:MarkDirty(); ST.Book:Get() end)
end
