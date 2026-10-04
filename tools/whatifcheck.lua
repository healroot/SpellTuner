-- tools/run.sh --flavour tbc|forever tools/whatifcheck.lua
--
-- T122 (docs/tasks/T122-what-if.md; docs/SPEC-one-ui.md 4, mockup M2): the
-- What if on both lines. Spells/WhatIf.lua's session state and its shared
-- arithmetic (Changes, Diff), TBC's provider (Spells/WhatIf_TBC.lua: ST.sim
-- written there only, the druid's Form / Moonglow rows, the static-cost
-- note), Forever's (Spells/WhatIf_Forever.lua: value + counts x delta, the
-- rules re-run) and Spells/Book.lua's measured coefficients.
--
--   1. ST.WhatIf: Set / Get / Clear / Active; an equal write fires nothing;
--      Clear fires once; nothing lands in db or cdb (both)
--   2. (tbc) +150 healing: the what-if book's Healing Touch is Compute()
--      under ST.sim.heal = live + 150, field for field; the live book and its
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
--      the suggested ranks (tbc) and ST.Book:Get() equal byte for byte (both)
--  10. a source scan: ST.sim written only by Spells/WhatIf_TBC.lua;
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
local ST = dofile(here .. "/harness.lua")
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
    S.Load(present, "SpellTuner", ST)
    ST.player.isDruid = true
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    ST:Fire("CORE_LOGIN")
    if ST.Book and ST.Book.Refresh then ST.Book:Refresh() end
    ST:Fire("MD_READY")
else
    ST:SetModule("SpellTuner_Replay", true) -- the Forever kit (check 9)
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
ST:RegisterCallback("WHATIF_CHANGED", function() events = events + 1 end)

--------------------------------------------------------------------------------
-- 1 (both)
--------------------------------------------------------------------------------
T("1 ST.WhatIf: Set / Get / Clear / Active; equal writes silent; not saved", function()
    local WI = ST.WhatIf
    if type(WI) ~= "table" then return false, "no ST.WhatIf" end
    WI:Clear()
    local db0, cdb0 = Ser(ST.db), Ser(ST.cdb)
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
    local saved = Ser(ST.db) == db0 and Ser(ST.cdb) == cdb0
    local good = inactive and moved ~= false and e1 == e0 + 1 and same == false and e2 == e1
        and crit == 100 and mana == 0 and active and WI:Get("heal") == nil and e4 == e3 + 1 and e5 == e4
        and not WI:Active() and saved and #WI.STATS == 6 and WI.STATS[1].key == "heal"
        and WI.STATS[1].step == 25 and WI.STATS[1].bigStep == 100 and WI.STATS[4].key == "mana"
        and WI.STATS[4].step == 250
    return good, string.format("events %d/%d/%d/%d/%d/%d crit=%s mana=%s saved=%s", e0, e1, e2, e3, e4, e5,
        tostring(crit), tostring(mana), tostring(saved))
end)

local WI = ST.WhatIf or {}

--------------------------------------------------------------------------------
-- 1b (both, T124): the +Spell damage row, right after +Healing, set / clear
-- as +Healing
--------------------------------------------------------------------------------
T("1b T124: +Spell damage is STATS[2], heal's steps; Set / Get / Clear as heal", function()
    WI:Clear()
    local s = WI.STATS and WI.STATS[2]
    local row = type(s) == "table" and s.key == "damage" and s.label == "+Spell damage" and s.step == 25
        and s.bigStep == 100
    local e0 = events
    local moved = WI:Set("damage", 420)
    local e1 = events
    local same = WI:Set("damage", 420)
    local e2 = events
    local got, active = WI:Get("damage"), WI:Active()
    WI:Set("damage", -10) -- clamped to 0
    local low = WI:Get("damage")
    WI:Clear()
    local good = row and moved ~= false and e1 == e0 + 1 and same == false and e2 == e1 and got == 420
        and active == true and low == 0 and WI:Get("damage") == nil and not WI:Active()
    return good, string.format("row=%s got=%s low=%s events %d/%d/%d", tostring(row), tostring(got),
        tostring(low), e0, e1, e2)
end)

--------------------------------------------------------------------------------
-- 8 (both, T124): the footer compares like with like -- every number it
-- prints is the what-if book's; the live family gives the old rank's id and
-- number only. WI.Diff's rounding as before.
--------------------------------------------------------------------------------
T("8 WI.Changes: every number from the what-if book; floor / beaten / trade reasons; ASCII; WI.Diff", function()
    -- entries: { rank, perMana, value, dominatedByRank }
    local function Fam(sugRank, entries, kind)
        local fam = { ranks = {}, kind = kind or "heal" }
        for _, x in ipairs(entries) do
            local e = { id = 1000 + x[1], rank = x[1], perMana = x[2], value = x[3] or 100, perSec = 10,
                        cost = { amount = 50 }, cast = 2.0, known = true,
                        dominatedBy = x[4] and (1000 + x[4]) or nil, dominated = x[4] and true or nil }
            fam.ranks[#fam.ranks + 1] = e
            if x[1] == sugRank then fam.suggested = e end
        end
        fam.maxKnown = fam.ranks[#fam.ranks]
        return fam
    end
    -- the live families' per mana deliberately unlike the what-if book's: a
    -- live number in a footer would show
    local liveA = Fam(12, { { 6, 6.20 }, { 12, 6.09 } })
    local liveB = Fam(6, { { 6, 3.33 }, { 9, 4.44 }, { 12, 5.55 } })
    local LIVE_DIGITS = { "6.20", "6.09", "3.33", "4.44", "5.55" }
    local moved = Fam(6, { { 6, 7.40 }, { 12, 6.83 } })                          -- the new rank better
    -- T127: the old rank's value 30 is under 40% of the top's 100 (a heal
    -- only: damage has no floor, so the same numbers there say the trade
    -- against max no longer pays)
    local floor = Fam(12, { { 6, 7.77, 30 }, { 9, 7.10 }, { 12, 5.51 } })        -- worse, the old under the floor
    local floorD = Fam(12, { { 6, 7.77, 30 }, { 9, 7.10 }, { 12, 5.51 } }, "damage")
    local trade = Fam(12, { { 6, 7.77 }, { 9, 7.10 }, { 12, 5.51 } })            -- worse, over the floor: the trade
    local beaten = Fam(12, { { 6, 7.77, 100, 9 }, { 9, 7.90 }, { 12, 5.51 } })   -- worse, the old beaten
    local stayed = Fam(12, { { 6, 9.99 }, { 12, 8.88 } })                        -- same id, numbers moved
    local a, f, fd = WI.Changes(liveA, moved), WI.Changes(liveB, floor), WI.Changes(liveB, floorD)
    local bt, c = WI.Changes(liveB, beaten), WI.Changes(liveA, stayed)
    local tr = WI.Changes(liveB, trade)
    local n1, n2 = WI.Changes(nil, moved), WI.Changes(liveA, nil)
    local ascii, leaked = true, {}
    for _, s in ipairs({ a, f, fd, bt, c, n1, n2, tr }) do
        if type(s) ~= "string" or s:find("[\128-\255]") or s:gsub("||", ""):find("|") then ascii = false end
        for _, d in ipairs(LIVE_DIGITS) do
            if type(s) == "string" and s:find(d, 1, true) then leaked[#leaked + 1] = d end
        end
    end
    local e1 = { value = 100.2, perMana = 2.001, perSec = 33.33, cost = { amount = 50 }, cast = 2.0, known = true }
    local e2 = { value = 100.4, perMana = 2.004, perSec = 33.34, cost = { amount = 50 }, cast = 2.0, known = true }
    local e3 = { value = 145.4, perMana = 2.91, perSec = 48.5, cost = { amount = 50 }, cast = 2.0, known = true }
    local d0 = WI.Diff(e1, e2, 10, 10)
    local d1 = WI.Diff(e1, e3, 10, 7)
    local n0 = 0
    for _ in pairs(d0) do n0 = n0 + 1 end
    local bad = {}
    local function Want(got, want, what)
        if got ~= want then bad[#bad + 1] = what .. "=" .. string.format("%q", tostring(got)) end
    end
    local WORSE = "Best: Rank 6 -> Rank 12. With these stats Rank 12 gives 5.51 per mana, Rank 6 7.77 (-29%)."
    Want(a, "Best: Rank 12 -> Rank 6. With these stats Rank 6 gives 7.40 per mana, Rank 12 6.83 (+8%).", "moved")
    Want(f, WORSE .. " Rank 6 is under 40% of Rank 12's heal.", "floor")
    Want(fd, WORSE .. " Rank 6's trade against max no longer pays.", "floor damage") -- T127: no damage floor
    Want(tr, WORSE .. " Rank 6's trade against max no longer pays.", "trade")
    Want(bt, WORSE .. " Rank 6 is beaten by Rank 9.", "beaten")
    Want(c, "No change to the best rank.", "stayed")
    Want(n1, "No change to the best rank.", "nil live")
    Want(n2, "No change to the best rank.", "nil what if")
    local good = #bad == 0 and ascii and #leaked == 0 and n0 == 0
        and d1.value and d1.perMana and d1.perSec and d1.casts and not d1.cost and not d1.cast
    return good, table.concat(bad, "; ") .. " leaked=" .. table.concat(leaked, ",") .. " ascii=" .. tostring(ascii)
end)

--------------------------------------------------------------------------------
-- 10 (both): ST.sim written by one file; Dashboard_Simulate on no TOC
--------------------------------------------------------------------------------
T("10 ST.sim written only by Spells/WhatIf_TBC.lua; no TOC lists Dashboard_Simulate", function()
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
                if code:find("ST%.sim%.[%w_]+%s*=[^=]") or code:find("ST%.sim%[[^%]]*%]%s*=[^=]")
                    or code:find("wipe%(%s*ST%.sim%s*%)") then
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
    local RM, SD = ST.RankMath, ST.SpellData

    local function HT(book)
        local fam = book.families.HealingTouch
        local by = {}
        for _, e in ipairs(fam.ranks) do by[e.rank] = e end
        return fam, by
    end

    --------------------------------------------------------------------------
    -- 2 (tbc)
    --------------------------------------------------------------------------
    T("2 tbc: +150 healing is Compute() under ST.sim, the live book untouched", function()
        WI:Clear()
        local liveBook = ST.Book:Get()
        local gen0, ser0 = ST.Book.generation, Ser(liveBook)
        local live = WI:Live()
        WI:Set("heal", live.heal + 150)
        local wb = WI:Book()
        local savedSim, savedInfo = ST.sim, RM.info
        ST.sim = { heal = live.heal + 150 }
        local res = RM:Compute()
        ST.sim, RM.info = savedSim, savedInfo
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
        local liveFam, liveBy = HT(ST.Book:Get())
        local moved = by[12] and liveBy[12] and by[12].value > liveBy[12].value
        local good = #bad == 0 and moved and fam.suggested and fam.suggested.id == res.HealingTouch.suggestedID
            and ST.Book.generation == gen0 and Ser(ST.Book:Get()) == ser0 and liveFam ~= fam
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
        local sim = ST.sim and ST.sim.tree == true and ST.sim.moonglow == 2
        WI:Clear()
        local wiped = ST.sim == nil or next(ST.sim) == nil
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
        local caps = ST.Profiles.byClass.PRIEST.caps
        local savedRT = caps.rankTable
        caps.rankTable = true
        S.units.player.class = "PRIEST"
        local good, res = pcall(function()
            ST:DetectProfile()
            ST:Fire("CORE_LOGIN")
            local rows = WI:ClassRows()
            return { rows = rows, note = WI:ClassNote(), book = ST.RankMath:IsClassBook() }
        end)
        S.units.player.class = "DRUID"
        caps.rankTable = savedRT
        ST:DetectProfile()
        ST:Fire("CORE_LOGIN")
        if not good then return false, "raised: " .. tostring(res) end
        return (res.rows == nil or #res.rows == 0) and res.note == nil and res.book == true, Ser(res)
    end)

    --------------------------------------------------------------------------
    -- 9 (tbc)
    --------------------------------------------------------------------------
    T("9 tbc: the clock, the block, the kit, the suggested ranks and the book ignore it", function()
        WI:Clear()
        ST.Book:Refresh()
        local function Snap()
            local id = ST.Book:Get().families.HealingTouch.maxKnown.id
            local savedInfo = RM.info
            local out = {
                clock = Ser(ST.ClockFace.Current(100)),
                tip = Ser({ ST.SpellTip:Lines(id, false) }),
                tipD = Ser({ ST.SpellTip:Lines(id, true) }),
                kit = Ser(RM:SpellKit()),
                ranks = Ser(RM:SuggestedRanks()),
                book = Ser(ST.Book:Refresh()),
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
        local active = ST.sim and next(ST.sim) ~= nil
        WI:Clear()
        local bad = {}
        for k, v in pairs(before) do if during[k] ~= v then bad[#bad + 1] = k end end
        return #bad == 0 and active, "changed: " .. table.concat(bad, ",") .. " sim set=" .. tostring(active)
    end)

    --------------------------------------------------------------------------
    -- 11 (tbc, T124): +Spell damage. A walk with Wrath (Nature) and Moonfire
    -- (Arcane), as tools/bookshapecheck.lua installs one; GetSpellBonusDamage
    -- answers `dmg[school]`.
    --------------------------------------------------------------------------
    local WALK = {
        { id = 5176, name = "Wrath", sub = "Rank 1", cost = 20, cast = 1500, level = 1,
          desc = "Causes 13 to 16 Nature damage to the target." },
        { id = 6780, name = "Wrath", sub = "Rank 2", cost = 35, cast = 2000, level = 14,
          desc = "Causes 51 to 58 Nature damage to the target." },
        { id = 8921, name = "Moonfire", sub = "Rank 1", cost = 25, cast = 0, level = 4,
          desc = "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec." },
    }
    local WALK_NAMES = { "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo",
        "GetSpellInfo", "GetSpellDescription", "GetSpellPowerCost", "GetSpellLevelLearned", "GetSpellBonusDamage" }
    local dmg = { [4] = 300, [7] = 310 }
    local function Forget()
        for _, n in ipairs(WALK_NAMES) do if ST.API.Invalidate then ST.API.Invalidate(n) end end
        if ST.BookTBC and type(ST.BookTBC.Forget) == "function" then ST.BookTBC.Forget() end
    end
    local function InstallWalk()
        local saved = {}
        for _, n in ipairs(WALK_NAMES) do saved[n] = rawget(_G, n) end
        local byId = {}
        for _, r in ipairs(WALK) do byId[r.id] = r end
        _G.GetNumSpellTabs = function() return 1 end
        _G.GetSpellTabInfo = function(tab) if tab == 1 then return "General", "icon", 0, #WALK end end
        _G.GetSpellBookItemName = function(slot) local r = WALK[slot]; if r then return r.name, r.sub, r.id end end
        _G.GetSpellBookItemInfo = function(slot) local r = WALK[slot]; if r then return "SPELL", r.id end end
        _G.GetSpellInfo = function(id)
            local r = byId[id]
            if r then return r.name, r.sub, "icon", r.cast or 0, 0, 30, id end
            if saved.GetSpellInfo then return saved.GetSpellInfo(id) end
        end
        _G.GetSpellDescription = function(id) local r = byId[id]; return r and r.desc or "" end
        _G.GetSpellPowerCost = function(id)
            local r = byId[id]
            if r then return { { type = 0, cost = r.cost } } end
            if saved.GetSpellPowerCost then return saved.GetSpellPowerCost(id) end
        end
        _G.GetSpellLevelLearned = function(id)
            local r = byId[id]
            if r then return r.level end
            if saved.GetSpellLevelLearned then return saved.GetSpellLevelLearned(id) end
        end
        _G.GetSpellBonusDamage = function(school) return dmg[school] or 0 end
        Forget()
        return function()
            for _, n in ipairs(WALK_NAMES) do _G[n] = saved[n] end
            Forget()
            ST.Book:Refresh()
        end
    end
    local function ByIdOf(fam)
        local out = {}
        for _, e in ipairs(fam and fam.ranks or {}) do out[e.id] = e end
        return out
    end

    T("11 tbc T124: +Spell damage -- ST.sim.damage, the damage ranks at live + delta, heals untouched", function()
        WI:Clear()
        local restore = InstallWalk()
        local good, detail, why = pcall(function()
            ST.Book:Refresh()
            local live = ST.Book:Get()
            local ser0 = Ser(live)
            local liveDmg = WI:Live().damage
            -- the oracle: the live book with every school 100 higher
            dmg[4], dmg[7] = 400, 410
            Forget()
            ST.Book:Refresh()
            local up = ST.Book:Get()
            dmg[4], dmg[7] = 300, 310
            Forget()
            ST.Book:Refresh()
            live = ST.Book:Get()
            ser0 = Ser(live)
            WI:Set("damage", 400)
            local simD = ST.sim and ST.sim.damage
            local wb = WI:Book()
            local summary = WI:Summary()
            local bad = {}
            local function Want(cond, what) if not cond then bad[#bad + 1] = what end end
            Want(liveDmg == 300, "live " .. tostring(liveDmg))
            Want(simD == 400, "sim " .. tostring(simD))
            Want(summary == "+100 spell damage", "summary " .. tostring(summary))
            for _, key in ipairs({ "Wrath", "Moonfire" }) do
                local lf, uf, wf = live.families[key], up.families[key], wb and wb.families[key]
                Want(lf and uf and wf, key .. " families")
                local L, U = ByIdOf(lf), ByIdOf(uf)
                for _, w in ipairs(wf and wf.ranks or {}) do
                    local l, u = L[w.id], U[w.id]
                    Want(l and u and w ~= l, key .. " copy " .. w.id)
                    if l and u then
                        Want(Near(w.value, u.value) and Near(w.perMana, u.perMana) and Near(w.perSec, u.perSec),
                            key .. " R" .. tostring(w.rank) .. " value " .. tostring(w.value) .. "/" .. tostring(u.value))
                        Want(w.value > l.value, key .. " moved " .. w.id)
                        Want(w.bonus and l.bonus and Near(w.bonus.amount - l.bonus.amount, l.bonus.counts * 100),
                            key .. " counts x delta " .. w.id)
                        Want(w.bonus and w.bonus.of == (dmg[key == "Wrath" and 4 or 7] + 100), key .. " of " .. w.id)
                    end
                end
            end
            -- heal ranks ignore damage
            local HT, WHT = ByIdOf(live.families.HealingTouch), ByIdOf(wb.families.HealingTouch)
            for id, l in pairs(HT) do
                Want(WHT[id] and WHT[id].value == l.value and WHT[id].perMana == l.perMana, "HT moved on damage " .. id)
            end
            Want(ST.Book:Get() == live and Ser(ST.Book:Get()) == ser0, "live book")
            -- damage ranks ignore heal
            WI:Clear()
            WI:Set("heal", WI:Live().heal + 150)
            local hb = WI:Book()
            local LW, HW = ByIdOf(live.families.Wrath), ByIdOf(hb.families.Wrath)
            for id, l in pairs(LW) do
                Want(HW[id] and HW[id].value == l.value and HW[id].perMana == l.perMana, "Wrath moved on heal " .. id)
            end
            WI:Clear()
            WI:Set("damage", 500)
            WI:Clear()
            Want(ST.sim == nil or next(ST.sim) == nil, "sim not emptied")
            return #bad == 0, table.concat(bad, "; ")
        end)
        WI:Clear()
        restore()
        if not good then return false, "raised: " .. tostring(detail) end
        return detail, why
    end)
else
    local Book = ST.Book
    local RR = ST.RankRules
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
        local store = ST.cdb and ST.cdb.bonusCounts
        local m = store and store[id]
        return m and m.counts, m
    end

    --------------------------------------------------------------------------
    -- 5 (forever)
    --------------------------------------------------------------------------
    T("5 forever: the share measured from two plain scans; the refusals", function()
        ST.inCombat, S.inCombat = false, false
        Scan(100)
        Scan(200)
        local c1, m1 = Counts(95201)
        local over = Counts(95211)
        local fixed = Counts(95221)
        local est = Counts(95202)
        -- in combat: nothing measured
        ST.inCombat, S.inCombat = true, true
        Scan(400)
        ST.inCombat, S.inCombat = false, false
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
        Want(wf.suggested == RR.Suggested(wf.ranks, wf.maxKnown, FIELDS, wf.kind), "suggested")
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
                clock = Ser(ST.ClockFace.Current(100)),
                tip = Ser({ ST.SpellTip:Lines(95201, false) }),
                tipD = Ser({ ST.SpellTip:Lines(95201, true) }),
                kit = Ser(ST.RankMath:SpellKit()),
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

    --------------------------------------------------------------------------
    -- 11 (forever, T124): +Spell damage through the provider -- a damage rank
    -- moves by its own share x the delta (here the estimate: the case starts
    -- with no earlier damage reading, so nothing is measured; 12 is the
    -- measured share), its numbers re-derived; heals ignore damage, damage ignores
    -- heal; the RANKS note counts the active stat's kind
    --------------------------------------------------------------------------
    T("11 forever T124: +Spell damage -- damage ranks by counts x delta, heals untouched", function()
        WI:Clear()
        ST.inCombat, S.inCombat = false, false
        local savedDmg = S.bonusDamage[4]
        S.bonusDamage[4] = 100
        -- no earlier reading and no stored share: Wrath stays estimated
        Book._lastRead = {}
        if ST.cdb and ST.cdb.bonusCounts then ST.cdb.bonusCounts[5176] = nil end
        local good, detail, why = pcall(function()
            local live = Scan(200)
            local liveSer = Ser(live)
            local l = live.spells[5176]
            local bad = {}
            local function Want(cond, what) if not cond then bad[#bad + 1] = what end end
            Want(l and l.bonus and l.bonus.from == "estimated" and l.bonus.of == 100,
                "live bonus " .. tostring(l and l.bonus and l.bonus.from) .. " of " .. tostring(l and l.bonus and l.bonus.of))
            local liveD = WI:Live().damage
            Want(liveD == 100, "Live().damage " .. tostring(liveD))
            WI:Set("damage", 250)
            local wb = WI:Book()
            local w = wb and wb.spells[5176]
            local c = l and l.bonus and l.bonus.counts or 0
            Want(w and w ~= l, "copy")
            if w and l then
                Want(c > 0 and Near(w.value, l.value + c * 150), "value " .. tostring(w.value) .. " live " .. tostring(l.value))
                local wd, ld = w.parsed and w.parsed.damage, l.parsed and l.parsed.damage
                Want(wd and ld and wd ~= ld and Near(wd.min, ld.min + c * 150) and Near(wd.max, ld.max + c * 150), "range")
                Want(Near(w.perMana, w.value / w.cost.amount), "perMana")
                Want(Near(w.perSec, w.value / Book.IntervalFor(w)), "perSec")
                Want(w.bonus and w.bonus.of == 250 and Near(w.bonus.amount, c * 250), "bonus.of")
            end
            for _, id in ipairs({ 95201, 95202 }) do
                local lm, wm = live.spells[id], wb and wb.spells[id]
                Want(wm and wm.value == lm.value and wm.perMana == lm.perMana, "Mend moved on damage " .. id)
            end
            local note = WI.provider.ranksNote(wb.families.Wrath)
            Want(note == "0 of 1 ranks measured, 1 estimated", "damage note " .. tostring(note))
            Want(Ser(Book:Get()) == liveSer and Book:Get() == live, "live book")
            WI:Clear()
            WI:Set("heal", 350)
            local hb = WI:Book()
            local hw = hb and hb.spells[5176]
            Want(hw and l and hw.value == l.value and hw.perMana == l.perMana, "Wrath moved on heal")
            local hnote = WI.provider.ranksNote(hb.families.Wrath)
            Want(hnote == nil, "heal note on Wrath " .. tostring(hnote))
            Want(ST.sim == nil or next(ST.sim) == nil, "ST.sim written")
            return #bad == 0, table.concat(bad, "; ")
        end)
        WI:Clear()
        S.bonusDamage[4] = savedDmg
        Book:MarkDirty()
        if not good then return false, "raised: " .. tostring(detail) end
        return detail, why
    end)

    --------------------------------------------------------------------------
    -- 12 (forever, T124 follow-up): a damage rank whose share MeasureBonus
    -- measured (two plain readings of its school's +spell damage) moves by
    -- the measured counts, and the RANKS note counts it as measured
    --------------------------------------------------------------------------
    T("12 forever: a measured damage rank moves by its measured counts; the note counts it", function()
        WI:Clear()
        ST.inCombat, S.inCombat = false, false
        local savedDmg = S.bonusDamage[4]
        -- "Spark": R1's text takes 60% of Nature spell damage, R2's none
        S.AddSpell(95301, "Spark", "Rank 1", function()
            local b = math.floor(0.6 * (S.bonusDamage[4] or 0) + 0.5)
            return "Causes " .. (100 + b) .. " to " .. (120 + b) .. " Nature damage to the target."
        end, { cast = 2000, cost = 50, level = 1 })
        S.AddSpell(95302, "Spark", "Rank 2", function()
            return "Causes 300 to 340 Nature damage to the target."
        end, { cast = 3000, cost = 120, level = 10 })
        Book._lastRead = {}
        local good, detail, why = pcall(function()
            S.bonusDamage[4] = 100
            Scan(200)
            S.bonusDamage[4] = 200
            local live = Scan(200)
            local l1, l2 = live.spells[95301], live.spells[95302]
            local bad = {}
            local function Want(cond, what) if not cond then bad[#bad + 1] = what end end
            local c1, m1 = Counts(95301)
            Want(Near(c1, 0.6) and m1 and m1.kind == "damage" and m1.school == "Nature",
                "stored " .. tostring(c1) .. " " .. tostring(m1 and m1.kind))
            Want(Counts(95302) == nil, "R2 measured")
            Want(l1 and l1.bonus and l1.bonus.from == "measured" and Near(l1.bonus.counts, 0.6),
                "R1 live bonus " .. tostring(l1 and l1.bonus and l1.bonus.from))
            Want(l2 and l2.bonus and l2.bonus.from == "estimated", "R2 live bonus " .. tostring(l2 and l2.bonus and l2.bonus.from))
            WI:Set("damage", 350)
            local wb = WI:Book()
            local w1, w2 = wb and wb.spells[95301], wb and wb.spells[95302]
            if w1 and l1 then
                Want(Near(w1.value, l1.value + 0.6 * 150), "R1 value " .. tostring(w1.value) .. " live " .. tostring(l1.value))
                Want(Near(w1.perMana, w1.value / w1.cost.amount), "R1 perMana")
                Want(w1.bonus and w1.bonus.from == "measured" and w1.bonus.of == 350, "R1 bonus " .. tostring(w1.bonus and w1.bonus.of))
            else
                Want(false, "copies")
            end
            local c2 = l2 and l2.bonus and l2.bonus.counts or 0
            Want(w2 and l2 and Near(w2.value, l2.value + c2 * 150), "R2 value " .. tostring(w2 and w2.value))
            local note = WI.provider.ranksNote(wb.families.Spark)
            Want(note == "1 of 2 ranks measured, 1 estimated", "note " .. tostring(note))
            return #bad == 0, table.concat(bad, "; ")
        end)
        WI:Clear()
        S.bonusDamage[4] = savedDmg
        Book:MarkDirty()
        if not good then return false, "raised: " .. tostring(detail) end
        return detail, why
    end)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
