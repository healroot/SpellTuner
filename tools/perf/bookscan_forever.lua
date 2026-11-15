-- tools/run.sh [--flavour f] tools/perf/<this>.lua -- not a suite (make check skips tools/perf/). one Forever book scan split by part
HARNESS_FLAVOUR = "forever"
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", "")) -- tools/, from tools/perf/
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local Book = ST.Book
local stats, order = {}, {}
local depth = 0
local function Wrap(tbl, name, label)
    local fn = tbl[name]
    if type(fn) ~= "function" then return end
    tbl[name] = function(...)
        depth = depth + 1
        local m0, t0 = collectgarbage("count"), os.clock()
        local a, b, c, d = fn(...)
        local st = stats[label]
        if not st then st = { kb = 0, s = 0, n = 0 }; stats[label] = st; order[#order + 1] = label end
        st.kb = st.kb + collectgarbage("count") - m0
        st.s = st.s + os.clock() - t0
        st.n = st.n + 1
        depth = depth - 1
        return a, b, c, d
    end
end
for _, n in ipairs({ "Scan", "Enumerate", "BuildEntry", "AddFutureRanks", "BuildFutureEntry", "GroupFamilies", "Rows",
    "MeasureBonus", "Talents", "DefaultPool", "Bonus", "Numbers" }) do Wrap(Book, n, "Book:" .. n) end
Wrap(ST.BookShape, "Check", "BookShape.Check")
Wrap(ST.Parse, "Description", "Parse.Description")
Wrap(ST.API, "TalentRanks", "API.TalentRanks")
Wrap(ST.API, "SpellTooltipData", "API.SpellTooltipData")
Wrap(ST.API, "SpellDescription", "API.SpellDescription")
Wrap(ST.Coefficients, "Estimate", "Coef.Estimate")
Wrap(ST.RankRules, "Marks", "RankRules.Marks")
for i, fn in ipairs(Book.adjust) do
    local box = { f = fn }
    Wrap(box, "f", "adjust[" .. i .. "]")
    Book.adjust[i] = box.f
end
Book:MarkDirty(); Book:Get()
for k in pairs(stats) do stats[k] = nil end
for i = #order, 1, -1 do order[i] = nil end
collectgarbage("collect"); collectgarbage("stop")
for _ = 1, 20 do Book:MarkDirty(); Book:Get() end
collectgarbage("restart")
print(string.format("%-28s %6s %9s %8s", "part (20 scans, nested)", "calls", "KB/scan", "ms/scan"))
for _, k in ipairs(order) do
    local st = stats[k]
    print(string.format("%-28s %6d %9.1f %8.2f", k, st.n, st.kb / 20, st.s * 1000 / 20))
end
local b = Book:Get()
local n = 0 for _ in pairs(b.spells) do n = n + 1 end
print("entries", n, "future", b.read.future)
