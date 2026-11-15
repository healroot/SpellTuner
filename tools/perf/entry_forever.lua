-- tools/run.sh --flavour forever tools/perf/entry_forever.lua -- not a suite. Garbage of one
-- book entry's build split by adapter call (perf F2).
HARNESS_FLAVOUR = "forever"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", ""))
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local Book = ST.Book
local stats, order = {}, {}
for name, fn in pairs(ST.API) do
    if type(fn) == "function" and name ~= "IsSecret" and name ~= "Has" and name ~= "Call" and name ~= "Copy" then
        ST.API[name] = function(...)
            local m0 = collectgarbage("count")
            local a, b, c, d = fn(...)
            local st = stats[name]
            if not st then st = { kb = 0, n = 0 }; stats[name] = st; order[#order + 1] = name end
            st.kb = st.kb + collectgarbage("count") - m0
            st.n = st.n + 1
            return a, b, c, d
        end
    end
end
Book:MarkDirty(); Book:Get()
for k in pairs(stats) do stats[k] = nil end
for i = #order, 1, -1 do order[i] = nil end
collectgarbage("collect"); collectgarbage("stop")
local m0 = collectgarbage("count")
for _ = 1, 20 do Book:MarkSoft(); Book:Get() end
local total = collectgarbage("count") - m0
collectgarbage("restart")
table.sort(order, function(a, b) return stats[a].kb > stats[b].kb end)
print(string.format("soft rescan: %.1f KB/scan total", total / 20))
for i = 1, math.min(#order, 15) do
    local st = stats[order[i]]
    print(string.format("  %-26s %5d calls %8.2f KB/scan", order[i], st.n / 20, st.kb / 20))
end
