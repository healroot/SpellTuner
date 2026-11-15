-- tools/run.sh --flavour forever tools/perf/clock_forever.lua -- not a suite. Garbage of the
-- clock's 0.5 s paint split by part (perf F5).
HARNESS_FLAVOUR = "forever"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", ""))
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local stats, order = {}, {}
local function Wrap(tbl, name, label)
    local fn = tbl and tbl[name]
    if type(fn) ~= "function" then print("no " .. label) return end
    tbl[name] = function(...)
        local m0 = collectgarbage("count")
        local a, b, c, d = fn(...)
        local st = stats[label]
        if not st then st = { kb = 0, n = 0 }; stats[label] = st; order[#order + 1] = label end
        st.kb = st.kb + collectgarbage("count") - m0
        st.n = st.n + 1
        return a, b, c, d
    end
end
Wrap(ST.Pool, "Project", "Pool:Project")
Wrap(ST.ManaModel, "Face", "ManaModel.Face")
Wrap(ST.ClockWords, "Build", "ClockWords.Build")
Wrap(ST.Pool, "QuietFull", "Pool:QuietFull")
local bar = ST.ClockBar
local B = bar and bar.Bar or (bar and bar.mt)
local renderer
for i = 1, 60 do
    local n, v = debug.getupvalue(ST.Clock.Refresh, i)
    if not n then break end
end
-- the renderer's methods live on its metatable's __index
local function RendererMethods()
    for _, fnName in ipairs({ "Refresh" }) do end
end
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
for _ = 1, 10 do S.Tick(0.5) end
collectgarbage("collect"); collectgarbage("stop")
local m0 = collectgarbage("count")
for _ = 1, 100 do S.Tick(0.5) end
local total = collectgarbage("count") - m0
collectgarbage("restart")
print(string.format("in combat, all ticks: %.2f KB per tick", total / 100))
for _, k in ipairs(order) do
    print(string.format("  %-20s %5d calls %7.2f KB per tick", k, stats[k].n, stats[k].kb / 100))
end
