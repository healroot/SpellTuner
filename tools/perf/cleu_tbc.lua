-- tools/run.sh --flavour tbc tools/perf/cleu_tbc.lua -- not a suite. The TBC combat log
-- handler's garbage per event kind (perf F3), the harness's own table per event excluded.
HARNESS_FLAVOUR = "tbc"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", ""))
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local me, p1, mob = UnitGUID("player"), "Player-1-00000002", "Creature-0-0-0-0-1234-0000000001"
local function Up(fn, name)
    for i = 1, 50 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
    end
end
local handlers = Up(ST.On, "handlers")
local cleu = handlers.COMBAT_LOG_EVENT_UNFILTERED[1]
print("recorder active:", ST.FightRecorder and ST.FightRecorder.active, "recordFights:", ST.db.recordFights)
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
print("recorder active in fight:", ST.FightRecorder and ST.FightRecorder.active)
local function Measure(label, ...)
    S.clog = { ... }
    S.clogN = select("#", ...)
    collectgarbage("collect"); collectgarbage("stop")
    local m0 = collectgarbage("count")
    for _ = 1, 1000 do cleu() end
    local kb = collectgarbage("count") - m0
    collectgarbage("restart")
    print(string.format("%-30s %7.0f bytes per event", label, kb * 1024 / 1000))
end
Measure("others' swing", 0, "SWING_DAMAGE", false, mob, "Mob", 0, 0, p1, "Tank", 0, 0, 900, 0, 1)
Measure("others' aura", 0, "SPELL_AURA_APPLIED", false, "Player-1-9", "P", 0, 0, p1, "Tank", 0, 0, 25218, "PWS", 2, "BUFF")
Measure("others' cast", 0, "SPELL_CAST_SUCCESS", false, "Player-1-9", "P", 0, 0, p1, "Tank", 0, 0, 25222, "Renew", 2)
Measure("own heal", 0, "SPELL_HEAL", false, me, "Me", 0, 0, p1, "Tank", 0, 0, 26979, "Healing Touch", 8, 2500, 300, 0, false)
Measure("own periodic heal", 0, "SPELL_PERIODIC_HEAL", false, me, "Me", 0, 0, p1, "Tank", 0, 0, 26982, "Rejuvenation", 8, 400, 50, 0, false)
