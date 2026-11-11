-- tools/run.sh --flavour forever tools/critcheck.lua
--
-- Crit in a rank's value (Spells/Book.lua's CritNow / CritFactor, 2026-11-11):
--
--   1. a direct heal's value, per mana and per second are the text's average x
--      (1 + crit x 0.5); entry.crit the chance; the parts and textValue the text's
--   2. a heal over time crits too: the same factor on its amount
--   3. a damage rank at its own school's chance
--   4. secret in combat: the last plain reading; never read: no crit, the text's value
--   5. What if Crit %: heals at the typed chance, a damage school moved by the same
--      step, the live book unwritten; Clear puts it back
HARNESS_FLAVOUR = "forever"

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
local Book, WI = ST.Book, ST.WhatIf

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
local function Fresh()
    Book:MarkDirty()
    return Book:Get()
end

-- The stub's book: Healing Touch R1 (5185, 40 to 55, 25 mana, 1.5 s),
-- Rejuvenation R1 / R2 (774, 1058: 56 over 12 s at R2), Wrath R1 (5176,
-- 13 to 16 Nature). The druid's heal crit school is Nature (4).
S.bonusHealing = 0
S.crit[4] = 10

-- 1 ---------------------------------------------------------------------------
T("1 a direct heal: value x (1 + 0.10 x 0.5); parts and textValue the text's", function()
    local e = Fresh().spells[5185]
    local avg = (40 + 55) / 2
    return near(e.crit, 0.10) and near(e.value, avg * 1.05) and near(e.textValue, avg)
        and e.min == 40 and e.max == 55 and near(e.perMana, avg * 1.05 / 25)
        and near(e.perSec, avg * 1.05 / 1.5),
        string.format("crit=%s value=%s text=%s", tostring(e.crit), tostring(e.value), tostring(e.textValue))
end)

-- 2 ---------------------------------------------------------------------------
T("2 a heal over time crits too: Rejuvenation R2 56 x 1.05", function()
    local e = Book:Get().spells[1058]
    return near(e.value, 56 * 1.05) and e.over == 56, "value=" .. tostring(e.value)
end)

-- 3 ---------------------------------------------------------------------------
T("3 a damage rank at its school's chance: Wrath at Nature 20%", function()
    S.crit[4] = 20
    local e = Fresh().spells[5176]
    local avg = (13 + 16) / 2
    S.crit[4] = 10
    return near(e.crit, 0.20) and near(e.value, avg * 1.10), "value=" .. tostring(e.value)
end)

-- 4 ---------------------------------------------------------------------------
T("4 secret in combat: the last plain reading", function()
    Fresh()
    S.inCombat = true
    local e = Fresh().spells[5185]
    S.inCombat = false
    return near(e.crit, 0.10), "crit=" .. tostring(e.crit)
end)

T("4 never read: no crit in the value", function()
    local saved = GetSpellCritChance
    GetSpellCritChance = function() return nil end
    ST.API.Invalidate("GetSpellCritChance")
    local last = Book._critLast
    Book._critLast = {}
    local e = Fresh().spells[5185]
    GetSpellCritChance = saved
    ST.API.Invalidate("GetSpellCritChance")
    Book._critLast = last
    Fresh()
    return e.crit == nil and near(e.value, (40 + 55) / 2), "crit=" .. tostring(e.crit) .. " value=" .. tostring(e.value)
end)

-- 5 ---------------------------------------------------------------------------
T("5 What if Crit 30: heals and Wrath (live 10%) moved to 30%", function()
    S.crit[4] = 10
    Fresh()
    WI:Clear()
    WI:Set("crit", 30)
    local wb = WI:Book()
    local ht, wr = wb.spells[5185], wb.spells[5176]
    local live = Book:Get().spells[5185]
    local good = near(ht.crit, 0.30) and near(ht.value, 47.5 * 1.15)
        and near(wr.crit, 0.30) and near(wr.value, 14.5 * 1.15)
        and near(live.crit, 0.10) and near(live.value, 47.5 * 1.05)
    WI:Clear()
    local back = WI:Book().spells[5185]
    return good and near(back.value, 47.5 * 1.05),
        string.format("ht=%s/%s wrath=%s/%s live=%s", tostring(ht.crit), tostring(ht.value), tostring(wr.crit),
            tostring(wr.value), tostring(live.value))
end)

T("5 What if Crit is clamped to 0..100 per school", function()
    WI:Clear()
    WI:Set("crit", 0)
    local wr = WI:Book().spells[5176]
    WI:Clear()
    return near(wr.crit, 0) and near(wr.value, 14.5), "crit=" .. tostring(wr.crit)
end)

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
