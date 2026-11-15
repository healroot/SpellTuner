-- tools/run.sh [--flavour f] tools/perf/<this>.lua -- not a suite (make check skips tools/perf/). garbage and time per tick handler and per event handler, by source line
HARNESS_FLAVOUR = HARNESS_FLAVOUR or "forever"
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
    local key = label .. " " .. info.short_src:gsub("^.*worktrees/forever%-talents/", "") .. ":" .. info.linedefined
    return function(...)
        local m0 = collectgarbage("count")
        local t0 = os.clock()
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

collectgarbage("collect")
collectgarbage("stop")
for i = 1, 120 do
    S.Tick(0.5)
    S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    S.Fire("UNIT_AURA", "player")
end
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
for i = 1, 120 do
    S.Tick(0.5)
    for _ = 1, 4 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    S.Fire("UNIT_AURA", "player")
    if i % 4 == 0 then S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g" .. i, 5185) end
end
S.inCombat = false
S.Fire("PLAYER_REGEN_ENABLED")
collectgarbage("restart")

local rows = {}
for k, v in pairs(stats) do rows[#rows + 1] = { k = k, v = v } end
table.sort(rows, function(a, b) return a.v.kb > b.v.kb end)
print(string.format("%-78s %6s %9s %8s", "handler", "calls", "KB total", "ms total"))
for i = 1, math.min(#rows, 30) do
    local r = rows[i]
    print(string.format("%-78s %6d %9.1f %8.1f", r.k:sub(1, 78), r.v.n, r.v.kb, r.v.s * 1000))
end
