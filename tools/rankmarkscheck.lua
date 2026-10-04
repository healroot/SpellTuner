-- tools/run.sh [--flavour forever|tbc] tools/rankmarkscheck.lua
--
-- T127 (docs/tasks/T127-rank-marks.md, mockup docs/mockups/rank-marks.html):
-- the three rank marks of Spells/RankRules.lua -- eff (the most per mana),
-- max (the most per second) and best (the trade against max, scored with
-- ST.Rules.TRADE_K_DAMAGE / TRADE_K_HEAL, the settings tradeKDamage /
-- tradeKHeal read at each call) -- over the eligible, non-dominated rows,
-- and Lifebloom's rolled rows (RR.MarkVariants). Pure rows, both lines.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0

local RR = ST.RankRules
local F = {
    eff = "perMana", rate = "perSec", value = "value",
    eligible = function(e) return e.known and e.perMana and e.perSec end,
}

-- rows from { rank, perMana, perSec, value [, known] }
local function Rows(spec)
    local out = {}
    for i, s in ipairs(spec) do
        out[i] = { id = 1000 + s[1], rank = s[1], perMana = s[2], perSec = s[3], value = s[4],
                   known = s[5] ~= false }
    end
    return out
end
local function Top(rows)
    local top
    for _, r in ipairs(rows) do if r.known then top = r end end
    return top
end
local function Run(spec, kind)
    local rows = Rows(spec)
    RR.Pareto(rows, F)
    local best, max, eff = RR.Marks(rows, Top(rows), F, kind)
    return rows, best, max, eff
end
local function R(row) return row and ("R" .. tostring(row.rank)) or "nil" end
local function Said(best, max, eff) return "best=" .. R(best) .. " max=" .. R(max) .. " eff=" .. R(eff) end

local function SetK(kind, v)
    ST.db = ST.db or {}
    if kind == "damage" then ST.db.tradeKDamage = v else ST.db.tradeKHeal = v end
end

-- 1. the defaults and the settings read at each call
SetK("damage", nil); SetK("heal", nil)
local d0, h0 = RR.TradeK("damage"), RR.TradeK("heal")
SetK("damage", 0.5); SetK("heal", 0.05)
local d1, h1 = RR.TradeK("damage"), RR.TradeK("heal")
SetK("damage", 7); SetK("heal", "x")
local d2, h2 = RR.TradeK("damage"), RR.TradeK("heal")
SetK("damage", nil); SetK("heal", nil)
check("1. k: ST.Rules.TRADE_K_DAMAGE 0.25 / TRADE_K_HEAL 0.15, settings read at each call, junk refused",
    ST.Rules.TRADE_K_DAMAGE == 0.25 and ST.Rules.TRADE_K_HEAL == 0.15 and d0 == 0.25 and h0 == 0.15
    and d1 == 0.5 and h1 == 0.05 and d2 == 0.25 and h2 == 0.15,
    string.format("%s %s / %s %s / %s %s", tostring(d0), tostring(h0), tostring(d1), tostring(h1),
        tostring(d2), tostring(h2)))

-- 2. TBC Wrath (mockup M1): Rank 6 is +5% per mana for -49% per second ->
-- best = max = Rank 10, eff Rank 6; Ranks 1-5 beaten, 7-9 unmarked
local WRATH = {
    { 1, 3.00, 40, 60 }, { 2, 3.29, 77, 115 }, { 3, 3.73, 137, 205 }, { 4, 4.00, 187, 280 },
    { 5, 4.20, 280, 420 }, { 6, 4.44, 370, 555 }, { 7, 4.39, 453, 680 }, { 8, 4.33, 520, 780 },
    { 9, 4.29, 600, 900 }, { 10, 4.24, 720, 1080 },
}
local rows, best, max, eff = Run(WRATH, "damage")
local beaten = 0
for i = 1, 5 do if rows[i].dominated then beaten = beaten + 1 end end
check("2. TBC damage: +5% per mana for -49% per second is not worth it -> best = max",
    best == rows[10] and max == rows[10] and eff == rows[6] and beaten == 5 and not rows[7].dominated,
    Said(best, max, eff) .. " beaten=" .. beaten)

-- 3. Forever damage (mockup M2): Rank 3 at x0.6 damage, x3 per mana -> best
rows, best, max, eff = Run({ { 1, 1.36, 20, 30 }, { 2, 2.21, 36, 62 }, { 3, 3.38, 54, 108 }, { 4, 1.11, 90, 180 } },
    "damage")
local score = RR.Score(rows[3], rows[4], F, 0.25)
check("3. Forever damage: x0.6 per second, x3 per mana -> best = eff = Rank 3, max Rank 4",
    best == rows[3] and eff == rows[3] and max == rows[4] and score ~= nil
    and math.abs(score - (3.38 / 1.11 - 1 - 0.25 * 0.4)) < 1e-9,
    Said(best, max, eff) .. " score=" .. tostring(score))

-- 4. a heal (mockup M3's what-if numbers): Rank 5 the most per mana but under
-- the 40% floor, so eff only; at k 0.15 Rank 10 scores highest; max Rank 12
local HT = {
    { 1, 2.50, 33, 50 }, { 2, 2.89, 87, 130 }, { 3, 3.71, 174, 330 }, { 4, 4.27, 267, 640 },
    { 5, 4.75, 359, 1040 }, { 6, 4.69, 438, 1270 }, { 7, 4.63, 524, 1520 }, { 8, 4.56, 631, 1830 },
    { 9, 4.51, 755, 2190 }, { 10, 4.44, 893, 2590 }, { 11, 4.37, 976, 2830 }, { 12, 4.31, 986, 2860 },
    { 13, 4.13, 1079, 3130, false },
}
rows, best, max, eff = Run(HT, "heal")
check("4. heal: the floor keeps Rank 5 eff only; k 0.15 -> Rank 10; max Rank 12; Rank 13 unknown competes not",
    best == rows[10] and max == rows[12] and eff == rows[5] and not rows[13].dominated,
    Said(best, max, eff))

-- 5. max is the most per second, not the highest rank: a shorter cast wins
rows, best, max, eff = Run({ { 1, 2.0, 100, 150 }, { 2, 3.0, 200, 300 }, { 3, 3.2, 180, 540 } }, "damage")
check("5. a lower rank with more per second holds max; the top rank is eff and best",
    max == rows[2] and eff == rows[3] and best == rows[3] and rows[1].dominated and not rows[3].dominated,
    Said(best, max, eff))

-- 6. k = 0: best is the most per mana that passes the floor; k = 1: per mana
-- and per second weigh the same (heal: Rank 11's +1.4% for -1% still pays)
SetK("heal", 0)
rows, best = Run(HT, "heal")
local k0 = R(best)
local good0 = best == rows[6]
SetK("heal", 1)
rows, best = Run(HT, "heal")
local k1 = R(best)
local good1 = best == rows[11]
SetK("heal", nil)
SetK("damage", 1)
rows, best = Run(WRATH, "damage")
local good1d = best == rows[10]
SetK("damage", 0)
rows, best = Run(WRATH, "damage")
local good0d = best == rows[6]
SetK("damage", nil)
check("6. edges: k 0 -> the most per mana over the floor; k 1 -> one for one",
    good0 and good1 and good1d and good0d, "heal k0 " .. k0 .. " / heal k1 " .. k1)

-- 7. a score of exactly 0 goes to max; the first of equals wins a tie
SetK("damage", 0.5)
rows, best, max, eff = Run({ { 1, 5, 50, 100 }, { 2, 4, 100, 200 } }, "damage")
local zero = Said(best, max, eff)
local goodZero = best == rows[2] and eff == rows[1]
SetK("damage", nil)
rows, best, max, eff = Run({ { 1, 5, 60, 100 }, { 2, 5, 60, 100 }, { 3, 4, 100, 200 } }, "damage")
check("7. a score of 0 goes to max; equal rows: the first wins",
    goodZero and best == rows[1] and eff == rows[1] and max == rows[3], zero .. " / tie " .. Said(best, max, eff))

-- 8. one known rank holds all three; no eligible row: best is the top, no
-- max, no eff (RR.Suggested's old answer)
rows, best, max, eff = Run({ { 1, 3, 30, 60 }, { 2, 4, 40, 80, false } }, "heal")
local one = best == rows[1] and max == rows[1] and eff == rows[1]
local none = { { id = 1, rank = 1, known = true, value = 10 } }
RR.Pareto(none, F)
local b2, m2, e2 = RR.Marks(none, none[1], F, "heal")
check("8. one rank holds all three; no row with numbers -> best the top, no max, no eff",
    one and b2 == none[1] and m2 == nil and e2 == nil, Said(best, max, eff))

-- 9. RR.Suggested is RR.Marks' best (every reader of `suggested` keeps it)
rows = Rows(WRATH); RR.Pareto(rows, F)
local sDamage = RR.Suggested(rows, rows[10], F, "damage")
rows = Rows(HT); RR.Pareto(rows, F)
local sHeal = RR.Suggested(rows, rows[12], F)
check("9. RR.Suggested answers best (heal by default)", sDamage and sDamage.rank == 10 and sHeal and sHeal.rank == 10,
    tostring(sDamage and sDamage.rank) .. " " .. tostring(sHeal and sHeal.rank))

-- 10. Lifebloom (mockup M4): one rank and its rolled rows, equal cost on one
-- GCD -- the winner takes bestOfStacks, nothing else does
local function LB(r1, x2, x3)
    local e = { id = 33763, rank = 1, known = true, perMana = r1[1], perSec = r1[2], value = r1[3],
                variants = { { variant = 2, perMana = x2[1], perSec = x2[2], value = x2[3] },
                             { variant = 3, perMana = x3[1], perSec = x3[2], value = x3[3] } } }
    RR.MarkVariants(e)
    return e
end
local raw = LB({ 7.98, 1171, 1756 }, { 7.01, 1029, 1543 }, { 10.52, 1543, 2314 })
local after = LB({ 5.99, 878, 1317 }, { 4.21, 617, 926 }, { 4.73, 694, 1041 })
local again = LB({ 7.98, 1171, 1756 }, { 7.01, 1029, 1543 }, { 10.52, 1543, 2314 })
RR.MarkVariants(again)
local unknown = LB({ 7.98, 1171, 1756 }, { 7.01, 1029, 1543 }, { 10.52, 1543, 2314 })
unknown.known = false
RR.MarkVariants(unknown)
check("10. Lifebloom: x3 holds best over R1 and x2; R1 when it wins; re-marking clears; unknown none",
    raw.bestOfStacks == nil and raw.variants[1].bestOfStacks == nil and raw.variants[2].bestOfStacks == true
    and after.bestOfStacks == true and after.variants[1].bestOfStacks == nil and after.variants[2].bestOfStacks == nil
    and again.variants[2].bestOfStacks == true and again.bestOfStacks == nil
    and unknown.bestOfStacks == nil and unknown.variants[2].bestOfStacks == nil,
    string.format("raw %s/%s/%s after %s/%s/%s", tostring(raw.bestOfStacks), tostring(raw.variants[1].bestOfStacks),
        tostring(raw.variants[2].bestOfStacks), tostring(after.bestOfStacks), tostring(after.variants[1].bestOfStacks),
        tostring(after.variants[2].bestOfStacks)))

-- 11. the settings default once (ST:Setting answers them before any write)
check("11. tradeKDamage / tradeKHeal are registered defaults",
    ST:Setting("tradeKDamage") == 0.25 and ST:Setting("tradeKHeal") == 0.15,
    tostring(ST:Setting("tradeKDamage")) .. " " .. tostring(ST:Setting("tradeKHeal")))

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails > 0 and 1 or 0)
