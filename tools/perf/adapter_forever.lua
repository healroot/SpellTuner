-- tools/run.sh [--flavour f] tools/perf/<this>.lua -- not a suite (make check skips tools/perf/). the adapter's cost per call vs a direct call, and Copy of a tooltip-sized table
HARNESS_FLAVOUR = "forever"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", "")) -- tools/, from tools/perf/
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
_G.PerfProbeFn = function(a) return a, 2, 3 end
local N = 20000
local function Bench(label, fn)
    collectgarbage("collect"); collectgarbage("stop")
    local m0, t0 = collectgarbage("count"), os.clock()
    for i = 1, N do fn(i) end
    local kb, s = collectgarbage("count") - m0, os.clock() - t0
    collectgarbage("restart")
    print(string.format("%-34s %7.3f us/call  %6.0f bytes/call", label, s * 1e6 / N, kb * 1024 / N))
end
Bench("direct call", function(i) return PerfProbeFn(i) end)
Bench("ST.API.Call", function(i) return ST.API.Call("PerfProbeFn", i) end)
Bench("ST.API.IsSecret", function(i) return ST.API.IsSecret(i) end)
local tip = { lines = {} }
for i = 1, 12 do tip.lines[i] = { leftText = "Line " .. i .. " some tooltip text", type = 0, leftColor = { r = 1, g = 1, b = 1 } } end
Bench("ST.API.Copy (12-line tooltip)", function() return ST.API.Copy(tip, 3) end)
