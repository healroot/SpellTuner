-- tools/run.sh --flavour tbc|forever tools/whatifcheck.lua
--
-- T122 (docs/tasks/T122-what-if.md; docs/SPEC-one-ui.md 4, mockup M2): the
-- What if on both lines. Spells/WhatIf.lua's session state and its shared
-- arithmetic (Changes, Diff), TBC's provider (Spells/WhatIf_TBC.lua: MD.sim
-- written there only, the druid's Form / Moonglow rows, the static-cost
-- note), Forever's (Spells/WhatIf_Forever.lua: value + counts x delta, the
-- rules re-run) and Spells/Book.lua's measured coefficients.
--
--   1. MD.WhatIf: Set / Get / Clear / Active; an equal write fires nothing;
--      Clear fires once; nothing lands in db or cdb (both)
--   2. (tbc) +150 healing: the what-if book's Healing Touch is Compute()
--      under MD.sim.heal = live + 150, field for field; the live book and its
--      generation unchanged
--   3. (tbc) Tree of Life and Moonglow 2: costs from SD:StaticCost; the RANKS
--      note says so
--   4. (tbc) the druid's class rows: Form (Live first) and Moonglow
--   5. (tbc) a priest with the rank table granted: no class row, no sentence
--   5. (forever) the measured share: two plain scans out of combat; combat,
--      a stale bonus, an unchanged text and a share outside [0, 2] measure
--      nothing
--   6. (forever) +150 healing: measured and estimated ranks move by their
--      share; per mana / per sec / casts recomputed; the suggestion is
--      RankRules.Suggested over the what-if rows
--   7. (forever) crit 30: the values unchanged, the entry's crit set
--   8. WI.Changes' three sentences and WI.Diff's rounding (both)
--   9. nothing else reads it: the clock face, the tooltip block, the kit,
--      the suggested ranks (tbc) and MD.Book:Get() equal byte for byte (both)
--  10. a source scan: MD.sim written only by Spells/WhatIf_TBC.lua;
--      UI/Dashboard_Simulate.lua on no TOC (both)
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local function T(name, fn)
    local good, cond, detail = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(cond)) return end
    check(name, cond == true, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local TBC = S.flavour == "tbc"

if TBC then
    -- the UI files the TBC TOC lists (UI/SpellTip.lua for check 9), as
    -- tools/spellsui.lua loads them
    S.Geometry(true)
    local loaded = {}
    for _, rel in ipairs(S.loadedFiles or {}) do loaded[rel] = true end
    local present = {}
    for _, rel in ipairs(S.TocFiles("SpellTuner_TBC.toc")) do
        if rel:sub(1, 3) == "UI/" and not loaded[rel] then present[#present + 1] = rel end
    end
    S.Load(present, "SpellTuner", MD)
    MD.player.isDruid = true
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    MD:Fire("CORE_LOGIN")
    if MD.Book and MD.Book.Refresh then MD.Book:Refresh() end
    MD:Fire("MD_READY")
else
    MD:SetModule("SpellTuner_Replay", true) -- the Forever kit (check 9)
end

-- A deterministic dump: keys sorted, a cycle named, functions by type.
local function Ser(v, seen, depth)
    seen, depth = seen or {}, depth or 0
    local t = type(v)
    if t == "number" then
        if v ~= v then return "nan" end
        return string.format("%.10g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t ~= "table" then
        return t == "boolean" and tostring(v) or (v == nil and "nil" or ("<" .. t .. ">"))
    end
    if seen[v] then return "<seen>" end
    if depth > 10 then return "<deep>" end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k], seen, depth + 1) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function Near(a, b, eps)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6)
end

local events = 0
MD:RegisterCallback("WHATIF_CHANGED", function() events = events + 1 end)

--------------------------------------------------------------------------------
-- 1 (both)
--------------------------------------------------------------------------------
T("1 MD.WhatIf: Set / Get / Clear / Active; equal writes silent; not saved", function()
    local WI = MD.WhatIf
    if type(WI) ~= "table" then return false, "no MD.WhatIf" end
    WI:Clear()
    local db0, cdb0 = Ser(MD.db), Ser(MD.cdb)
    local e0 = events
    local inactive = WI:Active() == false
    local moved = WI:Set("heal", 600)
    local e1 = events
    local same = WI:Set("heal", 600)
    local e2 = events
    WI:Set("crit", 150) -- clamped to 100
    local crit = WI:Get("crit")
    WI:Set("mana", -5) -- clamped to 0
    local mana = WI:Get("mana")
    local active = WI:Active() == true
    local vals = WI:Values()
    vals.heal = 1 -- a copy
    local e3 = events
    WI:Clear()
    local e4 = events
    WI:Clear() -- nothing set: nothing fired
    local e5 = events
    local saved = Ser(MD.db) == db0 and Ser(MD.cdb) == cdb0
    local good = inactive and moved ~= false and e1 == e0 + 1 and same == false and e2 == e1
        and crit == 100 and mana == 0 and active and WI:Get("heal") == nil and e4 == e3 + 1 and e5 == e4
        and not WI:Active() and saved and #WI.STATS == 5 and WI.STATS[1].key == "heal"
        and WI.STATS[1].step == 25 and WI.STATS[1].bigStep == 100 and WI.STATS[3].step == 250
    return good, string.format("events %d/%d/%d/%d/%d/%d crit=%s mana=%s saved=%s", e0, e1, e2, e3, e4, e5,
        tostring(crit), tostring(mana), tostring(saved))
end)

local WI = MD.WhatIf or {}

--------------------------------------------------------------------------------
-- 8 (both): the footer's sentences and the diff's rounding
--------------------------------------------------------------------------------
T("8 WI.Changes: the three sentences, ASCII; WI.Diff after the cells' rounding", function()
    local function Fam(sugRank, entries)
        local fam = { ranks = {} }
        for _, x in ipairs(entries) do
            local e = { id = 1000 + x[1], rank = x[1], perMana = x[2], value = x[3] or 100, perSec = 10,
                        cost = { amount = 50 }, cast = 2.0, known = true }
            fam.ranks[#fam.ranks + 1] = e
            if x[1] == sugRank then fam.suggested = e end
        end
        return fam
    end
    local live = Fam(12, { { 6, 6.20 }, { 12, 6.09 } })
    local moved = Fam(6, { { 6, 6.56 }, { 12, 6.41 } })
    local stayed = Fam(12, { { 6, 6.20 }, { 12, 6.41 } })
    local same = Fam(12, { { 6, 6.20 }, { 12, 6.091 } })
    local a, b, c = WI.Changes(live, moved), WI.Changes(live, stayed), WI.Changes(live, same)
    local ascii = true
    for _, s in ipairs({ a, b, c }) do
        if type(s) ~= "string" or s:find("[\128-\255]") or s:gsub("||", ""):find("|") then ascii = false end
    end
    local e1 = { value = 100.2, perMana = 2.001, perSec = 33.33, cost = { amount = 50 }, cast = 2.0, known = true }
    local e2 = { value = 100.4, perMana = 2.004, perSec = 33.34, cost = { amount = 50 }, cast = 2.0, known = true }
    local e3 = { value = 145.4, perMana = 2.91, perSec = 48.5, cost = { amount = 50 }, cast = 2.0, known = true }
    local d0 = WI.Diff(e1, e2, 10, 10)
    local d1 = WI.Diff(e1, e3, 10, 7)
    local n0 = 0
    for _ in pairs(d0) do n0 = n0 + 1 end
    local good = a == "Suggested: Rank 12 -> Rank 6. Rank 12 per mana 6.09 -> 6.41 (+5%)."
        and b == "No change to the suggestion. Rank 12 per mana 6.09 -> 6.41 (+5%)."
        and c == "No change to the suggestion."
        and ascii and n0 == 0
        and d1.value and d1.perMana and d1.perSec and d1.casts and not d1.cost and not d1.cast
    return good, string.format("a=%q b=%q c=%q diff0=%d", tostring(a), tostring(b), tostring(c), n0)
end)

--------------------------------------------------------------------------------
-- 10 (both): MD.sim written by one file; Dashboard_Simulate on no TOC
--------------------------------------------------------------------------------
T("10 MD.sim written only by Spells/WhatIf_TBC.lua; no TOC lists Dashboard_Simulate", function()
    local root = S.root
    local bad = {}
    local p = io.popen('cd "' .. root .. '" && find . -name "*.lua" -not -path "./tools/*" -not -path "./.git/*" '
        .. '-not -path "./dist/*" -not -path "./.logs/*"')
    for rel in p:lines() do
        rel = rel:gsub("^%./", "")
        if rel ~= "Spells/WhatIf_TBC.lua" then
            local fh = io.open(root .. "/" .. rel)
            local n = 0
            for line in fh:lines() do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                if code:find("MD%.sim%.[%w_]+%s*=[^=]") or code:find("MD%.sim%[[^%]]*%]%s*=[^=]")
                    or code:find("wipe%(%s*MD%.sim%s*%)") then
                    bad[#bad + 1] = rel .. ":" .. n
                end
            end
            fh:close()
        end
    end
    p:close()
    local tocs = io.popen('cd "' .. root .. '" && find . -name "*.toc" -not -path "./tools/*" -not -path "./dist/*" -not -path "./.git/*"')
    for rel in tocs:lines() do
        local fh = io.open(root .. "/" .. rel:gsub("^%./", ""))
        local text = fh:read("*a")
        fh:close()
        if text:find("Dashboard_Simulate", 1, true) then bad[#bad + 1] = rel end
    end
    tocs:close()
    return #bad == 0, table.concat(bad, ", ")
end)

if TBC then
    local RM, SD = MD.RankMath, MD.SpellData

    local function HT(book)
        local fam = book.families.HealingTouch
        local by = {}
        for _, e in ipairs(fam.ranks) do by[e.rank] = e end
        return fam, by
    end

    --------------------------------------------------------------------------
    -- 2 (tbc)
    --------------------------------------------------------------------------
    T("2 tbc: +150 healing is Compute() under MD.sim, the live book untouched", function()
        WI:Clear()
        local liveBook = MD.Book:Get()
        local gen0, ser0 = MD.Book.generation, Ser(liveBook)
        local live = WI:Live()
        WI:Set("heal", live.heal + 150)
        local wb = WI:Book()
        local savedSim, savedInfo = MD.sim, RM.info
        MD.sim = { heal = live.heal + 150 }
        local res = RM:Compute()
        MD.sim, RM.info = savedSim, savedInfo
        local fam, by = HT(wb)
        local bad = {}
        for _, row in ipairs(res.HealingTouch.rows) do
            if not row.variant then
                local e = by[row.rank]
                if not e then
                    bad[#bad + 1] = "R" .. tostring(row.rank) .. " missing"
                elseif not (e.value == row.heal and e.perMana == row.hpm and e.perSec == row.hps
                    and e.cost.amount == row.cost and e.cast == row.cast
                    and (e.suggested and true or false) == (row.suggested and true or false)) then
                    bad[#bad + 1] = "R" .. row.rank .. " " .. tostring(e.value) .. "/" .. tostring(row.heal)
                end
            end
        end
        local liveFam, liveBy = HT(MD.Book:Get())
        local moved = by[12] and liveBy[12] and by[12].value > liveBy[12].value
        local good = #bad == 0 and moved and fam.suggested and fam.suggested.id == res.HealingTouch.suggestedID
            and MD.Book.generation == gen0 and Ser(MD.Book:Get()) == ser0 and liveFam ~= fam
            and WI:Summary() == "+150 healing"
        WI:Clear()
        return good, table.concat(bad, "; ") .. " summary=" .. tostring(WI.Summary and "ok")
    end)

    --------------------------------------------------------------------------
    -- 3 (tbc)
    --------------------------------------------------------------------------
    T("3 tbc: Tree of Life and Moonglow 2 price from SD:StaticCost; the RANKS note says so", function()
        WI:Clear()
        WI:Set("form", "tree")
        WI:Set("moonglow", 2)
        local wb = WI:Book()
        local fam = wb.families.HealingTouch
        local bad = {}
        for _, e in ipairs(fam.ranks) do
            local want = SD:StaticCost(e.id, { inTree = true, moonglow = 2 })
            if e.cost.amount ~= want then bad[#bad + 1] = e.id .. ":" .. tostring(e.cost.amount) .. "/" .. tostring(want) end
        end
        local note = WI.provider.ranksNote(fam)
        local sim = MD.sim and MD.sim.tree == true and MD.sim.moonglow == 2
        WI:Clear()
        local wiped = MD.sim == nil or next(MD.sim) == nil
        local good = #bad == 0 and type(note) == "string" and note:find("costs from the static table", 1, true) ~= nil
            and sim and wiped
        return good, table.concat(bad, " ") .. " note=" .. tostring(note) .. " sim=" .. tostring(sim)
            .. " wiped=" .. tostring(wiped)
    end)

    --------------------------------------------------------------------------
    -- 4 (tbc): the druid's rows
    --------------------------------------------------------------------------
    T("4 tbc: the druid's class rows -- Form (Live first) and Moonglow 0-3", function()
        local rows = WI:ClassRows()
        local form, glow = rows and rows[1], rows and rows[2]
        local good = type(rows) == "table" and #rows == 2 and form.key == "form" and form.kind == "choice"
            and form.choices[1].id == "live" and form.choices[3].text == "Tree of Life"
            and glow.key == "moonglow" and glow.min == 0 and glow.max == 3
            and WI:ClassTitle() == "DRUID" and WI:ClassNote() == nil
        return good, Ser(rows)
    end)

    --------------------------------------------------------------------------
    -- 5 (tbc): a priest with the rank table granted
    --------------------------------------------------------------------------
    T("5 tbc: a priest with the rank table granted: no class row, no sentence", function()
        local caps = MD.Profiles.byClass.PRIEST.caps
        local savedRT = caps.rankTable
        caps.rankTable = true
        S.units.player.class = "PRIEST"
        local good, res = pcall(function()
            MD:DetectProfile()
            MD:Fire("CORE_LOGIN")
            local rows = WI:ClassRows()
            return { rows = rows, note = WI:ClassNote(), book = MD.RankMath:IsClassBook() }
        end)
        S.units.player.class = "DRUID"
        caps.rankTable = savedRT
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        if not good then return false, "raised: " .. tostring(res) end
        return (res.rows == nil or #res.rows == 0) and res.note == nil and res.book == true, Ser(res)
    end)

    --------------------------------------------------------------------------
    -- 9 (tbc)
    --------------------------------------------------------------------------
    T("9 tbc: the clock, the block, the kit, the suggested ranks and the book ignore it", function()
        WI:Clear()
        MD.Book:Refresh()
        local function Snap()
            local id = MD.Book:Get().families.HealingTouch.maxKnown.id
            local savedInfo = RM.info
            local out = {
                clock = Ser(MD.ClockFace.Current(100)),
                tip = Ser({ MD.SpellTip:Lines(id, false) }),
                tipD = Ser({ MD.SpellTip:Lines(id, true) }),
                kit = Ser(RM:SpellKit()),
                ranks = Ser(RM:SuggestedRanks()),
                book = Ser(MD.Book:Refresh()),
            }
            RM.info = savedInfo
            return out
        end
        local before = Snap()
        WI:Set("heal", WI:Live().heal + 150)
        WI:Set("crit", 30)
        WI:Set("form", "tree")
        WI:Book()
        local during = Snap()
        local active = MD.sim and next(MD.sim) ~= nil
        WI:Clear()
        local bad = {}
        for k, v in pairs(before) do if during[k] ~= v then bad[#bad + 1] = k end end
        return #bad == 0 and active, "changed: " .. table.concat(bad, ",") .. " sim set=" .. tostring(active)
    end)
else
    local Book = MD.Book
    local RR = MD.RankRules
    local FIELDS = {
        eff = "perMana", rate = "perSec", value = "value",
        eligible = function(e) return e.known and e.perMana and e.perSec end,
    }
    -- "Mend": R1's text takes 30% of the bonus, R2's none (an estimate),
    -- "Overmend" 300% (refused), "Fixed" never moves (nothing to measure)
    S.AddSpell(95201, "Mend", "Rank 1", function()
        local b = math.floor(0.3 * S.bonusHealing + 0.5)
        return "Heals a friendly target for " .. (100 + b) .. " to " .. (120 + b) .. "."
    end, { cast = 2000, cost = 50, level = 1 })
    S.AddSpell(95202, "Mend", "Rank 2", function()
        return "Heals a friendly target for 300 to 340."
    end, { cast = 3000, cost = 120, level = 10 })
    S.AddSpell(95211, "Overmend", "Rank 1", function()
        return "Heals a friendly target for " .. (100 + 3 * S.bonusHealing) .. " to " .. (120 + 3 * S.bonusHealing) .. "."
    end, { cast = 2000, cost = 50, level = 1 })
    S.AddSpell(95221, "Fixed Mend", "Rank 1", function()
        return "Heals a friendly target for 70 to 90."
    end, { cast = 1500, cost = 30, level = 1 })

    local function Scan(bonus)
        S.bonusHealing = bonus
        Book:MarkDirty()
        return Book:Get()
    end
    local function Counts(id)
        local store = MD.cdb and MD.cdb.bonusCounts
        local m = store and store[id]
        return m and m.counts, m
    end

    --------------------------------------------------------------------------
    -- 5 (forever)
    --------------------------------------------------------------------------
    T("5 forever: the share measured from two plain scans; the refusals", function()
        MD.inCombat, S.inCombat = false, false
        Scan(100)
        Scan(200)
        local c1, m1 = Counts(95201)
        local over = Counts(95211)
        local fixed = Counts(95221)
        local est = Counts(95202)
        -- in combat: nothing measured
        MD.inCombat, S.inCombat = true, true
        Scan(400)
        MD.inCombat, S.inCombat = false, false
        local afterCombat = select(2, Counts(95201))
        local combatOk = afterCombat and afterCombat.bonus == 200
        -- a stale bonus (the read secret out of the regen events)
        S.bonusHealingSecretInCombat, S.inCombat = true, true
        Scan(600)
        S.bonusHealingSecretInCombat, S.inCombat = false, false
        local afterStale = select(2, Counts(95201))
        local staleOk = afterStale and afterStale.bonus == 200
        local e = Book:Get().spells[95201]
        local good = Near(c1, 0.3) and type(m1.at) == "number" and m1.bonus == 200
            and over == nil and fixed == nil and est == nil and combatOk and staleOk
            and e.bonus and e.bonus.from == "measured"
        return good, string.format("counts=%s over=%s fixed=%s est=%s combat=%s stale=%s from=%s", tostring(c1),
            tostring(over), tostring(fixed), tostring(est), tostring(combatOk), tostring(staleOk),
            tostring(e and e.bonus and e.bonus.from))
    end)

    --------------------------------------------------------------------------
    -- 6 (forever)
    --------------------------------------------------------------------------
    T("6 forever: +150 healing moves each rank by its share; the rules re-run", function()
        WI:Clear()
        Scan(200)
        local live = Book:Get()
        local liveSer = Ser(live)
        local lf = live.families.Mend
        local l1, l2 = live.spells[95201], live.spells[95202]
        local c2 = l2.bonus and l2.bonus.counts
        WI:Set("heal", 350)
        local wb = WI:Book()
        local wf = wb.families.Mend
        local w1, w2 = wb.spells[95201], wb.spells[95202]
        local pool = Book:Pool()
        local wpool = { max = pool.max, regenCasting = pool.regenCasting }
        local bad = {}
        local function Want(cond, what) if not cond then bad[#bad + 1] = what end end
        Want(w1 ~= l1 and w2 ~= l2 and wf ~= lf, "copies")
        Want(Near(w1.value, l1.value + 0.3 * 150), "R1 value " .. tostring(w1.value))
        Want(Near(w1.min, l1.min + 45) and Near(w1.max, l1.max + 45), "R1 range")
        Want(l2.bonus and l2.bonus.from == "estimated" and Near(w2.value, l2.value + c2 * 150),
            "R2 value " .. tostring(w2.value))
        for _, p in ipairs({ { w1, l1 }, { w2, l2 } }) do
            local w = p[1]
            Want(Near(w.perMana, w.value / w.cost.amount), "perMana " .. w.id)
            Want(Near(w.perSec, w.value / Book.IntervalFor(w)), "perSec " .. w.id)
            Want(w.casts == Book:CastsFor(w, wpool), "casts " .. w.id)
        end
        Want(wf.suggested == RR.Suggested(wf.ranks, wf.maxKnown, FIELDS), "suggested")
        Want(Ser(Book:Get()) == liveSer and Book:Get() == live, "live book")
        Want(w1.bonus and w1.bonus.of == 350, "bonus.of")
        WI:Clear()
        return #bad == 0, table.concat(bad, "; ")
    end)

    --------------------------------------------------------------------------
    -- 7 (forever)
    --------------------------------------------------------------------------
    T("7 forever: crit 30 -- the values unchanged, the entry's crit set", function()
        WI:Clear()
        local live = Book:Get()
        WI:Set("crit", 30)
        local wb = WI:Book()
        local bad = {}
        for id, e in pairs(live.spells) do
            local w = wb.spells[id]
            if not w then bad[#bad + 1] = id .. " missing"
            elseif w.value ~= e.value or w.perMana ~= e.perMana then bad[#bad + 1] = tostring(id)
            elseif e.value ~= nil and live.families[e.family] and live.families[e.family].kind == "heal"
                and not Near(w.crit, 0.3) then bad[#bad + 1] = id .. " crit " .. tostring(w.crit) end
        end
        local liveCrit = live.spells[95201].crit
        WI:Clear()
        return #bad == 0 and liveCrit == nil, table.concat(bad, "; ")
    end)

    --------------------------------------------------------------------------
    -- 9 (forever)
    --------------------------------------------------------------------------
    T("9 forever: the clock, the block, the kit and the book ignore it", function()
        WI:Clear()
        local function Snap()
            return {
                clock = Ser(MD.ClockFace.Current(100)),
                tip = Ser({ MD.SpellTip:Lines(95201, false) }),
                tipD = Ser({ MD.SpellTip:Lines(95201, true) }),
                kit = Ser(MD.RankMath:SpellKit()),
                book = Ser(Book:Get()),
            }
        end
        local before = Snap()
        WI:Set("heal", 500)
        WI:Set("crit", 30)
        WI:Set("mana", 9000)
        WI:Book()
        local during = Snap()
        WI:Clear()
        local bad = {}
        for k, v in pairs(before) do if during[k] ~= v then bad[#bad + 1] = k end end
        return #bad == 0, "changed: " .. table.concat(bad, ",")
    end)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
