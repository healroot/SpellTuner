-- tools/run.sh [--flavour f] tools/perf/<this>.lua -- not a suite (make check skips tools/perf/). TBC garbage and time per handler, raid-like combat log
HARNESS_FLAVOUR = "tbc"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", "")) -- tools/, from tools/perf/
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB

local function Up(fn, name)
    for i = 1, 50 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
    end
end
local tickers = Up(ST.OnTick, "tickers")
local handlers = Up(ST.On, "handlers")
local stats = {}
local function Wrap(fn, label)
    local info = debug.getinfo(fn, "S")
    local key = label .. " " .. info.short_src:gsub("^.*forever%-talents/", "") .. ":" .. info.linedefined
    return function(...)
        local m0, t0 = collectgarbage("count"), os.clock()
        local r1, r2, r3 = fn(...)
        local st = stats[key] or { kb = 0, s = 0, n = 0 }
        st.kb = st.kb + (collectgarbage("count") - m0)
        st.s = st.s + (os.clock() - t0)
        st.n = st.n + 1
        stats[key] = st
        return r1, r2, r3
    end
end
for i, fn in ipairs(tickers) do tickers[i] = Wrap(fn, "tick") end
for ev, list in pairs(handlers) do
    for i, fn in ipairs(list) do list[i] = Wrap(fn, ev) end
end

local me = UnitGUID("player")
local p1 = UnitGUID("party1") or "Player-1-00000002"
local mob = "Creature-0-0-0-0-1234-0000000001"
collectgarbage("collect"); collectgarbage("stop")
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
for i = 1, 300 do
    -- 20 log events per half second: others' swings, damage, heals, auras
    for j = 1, 4 do S.Combat(0, "SWING_DAMAGE", false, mob, "Mob", 0, 0, p1, "Tank", 0, 0, 900, 0, 1) end
    for j = 1, 4 do S.Combat(0, "SPELL_DAMAGE", false, p1, "Tank", 0, 0, mob, "Mob", 0, 0, 25222, "Shield Slam", 1, 1200) end
    for j = 1, 4 do S.Combat(0, "SPELL_PERIODIC_HEAL", false, "Player-1-9", "Priest", 0, 0, p1, "Tank", 0, 0, 25222, "Renew", 2, 300, 0, 0, false) end
    for j = 1, 4 do S.Combat(0, "SPELL_AURA_APPLIED", false, "Player-1-9", "Priest", 0, 0, p1, "Tank", 0, 0, 25218, "Power Word: Shield", 2, "BUFF") end
    S.Combat(0, "SPELL_PERIODIC_HEAL", false, me, "Me", 0, 0, p1, "Tank", 0, 0, 26982, "Rejuvenation", 8, 400, 50, 0, false)
    S.Combat(0, "SPELL_HEAL", false, me, "Me", 0, 0, p1, "Tank", 0, 0, 26979, "Healing Touch", 8, 2500, 300, 0, false)
    S.Combat(0, "SPELL_CAST_SUCCESS", false, "Player-1-9", "Priest", 0, 0, p1, "Tank", 0, 0, 25222, "Renew", 2)
    S.Combat(0, "SPELL_CAST_SUCCESS", false, me, "Me", 0, 0, p1, "Tank", 0, 0, 26982, "Rejuvenation", 8)
    for _ = 1, 4 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    S.Fire("UNIT_AURA", "player")
    S.Fire("UNIT_HEALTH", "party1")
    if i % 4 == 0 then S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g" .. i, 26982) end
    S.Tick(0.5)
end
S.inCombat = false
S.Fire("PLAYER_REGEN_ENABLED")
collectgarbage("restart")

local rows = {}
for k, v in pairs(stats) do rows[#rows + 1] = { k = k, v = v } end
table.sort(rows, function(a, b) return a.v.kb > b.v.kb end)
print(string.format("%-72s %6s %9s %8s", "handler (150 s of raid combat)", "calls", "KB total", "ms total"))
for i = 1, math.min(#rows, 22) do
    local r = rows[i]
    print(string.format("%-72s %6d %9.1f %8.1f", r.k:sub(1, 72), r.v.n, r.v.kb, r.v.s * 1000))
end
local sv = 0
