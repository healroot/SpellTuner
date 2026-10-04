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
    and math.abs(score - (3.38 / 1.11) * (54 / 90) ^ 0.25) < 1e-9, -- T128: the multiplicative score
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

-- 7. a score of exactly 1 goes to max (T128: x2 per mana, x0.25 per sec at
-- k 0.5 is 2 * 0.5); the first of equals wins a tie
SetK("damage", 0.5)
rows, best, max, eff = Run({ { 1, 8, 25, 100 }, { 2, 4, 100, 200 } }, "damage")
local zero = Said(best, max, eff)
local goodZero = best == rows[2] and eff == rows[1]
SetK("damage", nil)
rows, best, max, eff = Run({ { 1, 5, 60, 100 }, { 2, 5, 60, 100 }, { 3, 4, 100, 200 } }, "damage")
check("7. a score of exactly 1 goes to max; equal rows: the first wins",
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

-- 12. the stamp: the rule's version and both k, so a snapshot of best ranks
-- taken under another rule is known as such (review T127 M1)
local st0 = RR.Stamp and RR.Stamp()
SetK("heal", 0.5)
local st1 = RR.Stamp and RR.Stamp()
SetK("heal", nil)
check("12. RR.Stamp names the rule version and both k; a k change changes it",
    type(st0) == "string" and st0 ~= st1 and RR.Stamp() == st0 and st0:find("0.25", 1, true) ~= nil,
    tostring(st0) .. " / " .. tostring(st1))

-- 13. TBC: the Advisor's gear toast (UI/Advisor.lua) never toasts a shift the
-- rule caused -- an old snapshot (no stamp, or another k) is re-seeded
-- silently; RANK_RULES_CHANGED re-seeds; a real shift says "best rank"
if ST.RankMath and ST.RankMath.SuggestedRanks and _G.STUB and ST.ClassProfile:Can("advisor") then
    local S = _G.STUB
    local chat = {}
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
    local function Toasts(from)
        local n = 0
        for i = from or 1, #chat do if chat[i]:find("gear change", 1, true) then n = n + 1 end end
        return n
    end
    local ready, realReg = {}, ST.RegisterCallback
    ST.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    S.Load({ "UI/Advisor.lua" }, "SpellTuner", ST)
    ST.RegisterCallback = realReg
    local function Wait(sec) for _ = 1, sec * 2 do S.Tick(0.5) end end
    local Stamp = RR.Stamp or function() return "no RR.Stamp" end
    local current = ST.RankMath:SuggestedRanks()
    local anyFamily
    for fam in pairs(current) do anyFamily = anyFamily or fam end
    local function Old(stamp)
        local ranks = {}
        for fam, r in pairs(current) do ranks[fam] = r end
        ranks[anyFamily] = current[anyFamily] + 1 -- as the old rule had it
        return { form = ST:InTreeForm() and "tree" or "caster", ranks = ranks, rule = stamp }
    end
    -- a: MD_READY with a pre-T127 snapshot re-seeds it, stamped
    ST.cdb.suggestedRanks = Old(nil)
    for _, fn in ipairs(ready) do fn() end
    Wait(6)
    local a = ST.cdb.suggestedRanks.rule == Stamp() and ST.cdb.suggestedRanks.ranks[anyFamily] == current[anyFamily]
    -- b: a gear change over a pre-T127 snapshot: no toast, re-seeded
    local mark = #chat + 1
    ST.cdb.suggestedRanks = Old(nil)
    S.Fire("PLAYER_EQUIPMENT_CHANGED")
    Wait(3)
    local b = Toasts(mark) == 0 and ST.cdb.suggestedRanks.rule == Stamp()
    -- c: a snapshot from another k: no toast either
    ST.cdb.suggestedRanks = Old("marks:other")
    S.Fire("PLAYER_EQUIPMENT_CHANGED")
    Wait(3)
    local c = Toasts(mark) == 0 and ST.cdb.suggestedRanks.rule == Stamp()
    -- d: a slider move re-seeds silently (heal k 0 moves best), the next gear change says nothing
    SetK("heal", 0)
    ST:Fire("RANK_RULES_CHANGED")
    local afterK = ST.RankMath:SuggestedRanks()
    local d = ST.cdb.suggestedRanks.rule == Stamp() and ST.cdb.suggestedRanks.ranks[anyFamily] == afterK[anyFamily]
    S.Fire("PLAYER_EQUIPMENT_CHANGED")
    Wait(3)
    d = d and Toasts(mark) == 0
    SetK("heal", nil)
    ST:Fire("RANK_RULES_CHANGED")
    -- e: a real shift under the same rule toasts, in the new words
    ST.cdb.suggestedRanks = Old(Stamp())
    S.Fire("PLAYER_EQUIPMENT_CHANGED")
    Wait(3)
    local said = chat[#chat] or ""
    local e = Toasts(mark) == 1 and said:find("is now your best rank", 1, true) ~= nil
    _G.DEFAULT_CHAT_FRAME = realChat
    check("13. tbc Advisor: an old snapshot re-seeded silently (MD_READY, gear), RANK_RULES_CHANGED re-seeds, "
        .. "a real shift says best rank",
        a and b and c and d and e,
        string.format("a=%s b=%s c=%s d=%s e=%s said=%q", tostring(a), tostring(b), tostring(c), tostring(d),
            tostring(e), said))
end

-- 14. Review T127 m7: Words agree with RR.Marks in the edge cases.
do
    local W = ST.Words
    local top = { rank = 5, known = true } -- the highest known, no value (a gap)
    local mx = { rank = 4, known = true, value = 1000 }
    local fam = { maxKnown = top, maxRank = mx }
    local low, high = { value = 300 }, { value = 500 }
    local under = W.UnderFloor(low, fam, "heal") and not W.UnderFloor(high, fam, "heal")
        and not W.UnderFloor(low, fam, "damage")
    local c = { perMana = 10, value = -20, cast = 0 }
    local hMax, hHigh = W.Compare(c, 4, "heal", "full"), W.Compare(c, 5, "heal", "full", true)
    local heads = hMax:find("(max)", 1, true) ~= nil and hHigh:find("(highest)", 1, true) ~= nil
        and hHigh:find("(max)", 1, true) == nil
    local same = W.CompareSame("full")
    local rule = W.SuggestedRule()
    local words = same:find("best per mana", 1, true) == nil and rule:find("fastest", 1, true) == nil
        and rule:find("most per second", 1, true) ~= nil
    check("14. Words: UnderFloor falls back to max's value, the highest stand-in heads (highest), "
        .. "CompareSame / SuggestedRule say what the rule does",
        under and heads and words,
        string.format("under=%s heads=%q/%q same=%q rule=%q", tostring(under), hMax, hHigh, same, rule))
end

-- 15. Review T127 n1: a k move that leaves best in place still redraws (the
-- Spells pane's signature, and on TBC the book's generation).
do
    local SP = ST.SpellsPane
    local sig0 = SP and SP.Signature and SP:Signature("probe", false)
    local gen0 = ST.Book.generation
    if ST.Book.Refresh and gen0 then ST.Book:Refresh(); gen0 = ST.Book.generation end
    SetK("heal", 0.2)
    ST:Fire("RANK_RULES_CHANGED")
    local sig1 = SP and SP.Signature and SP:Signature("probe", false)
    local genOk = true
    if ST.Book.Refresh and gen0 then
        ST.Book:Refresh()
        genOk = ST.Book.generation ~= gen0
    end
    SetK("heal", nil)
    ST:Fire("RANK_RULES_CHANGED")
    -- the TBC harness loads no Spells pane: there the book's generation is the test
    local sigOk
    if sig0 == nil then sigOk = ST.Book.Refresh ~= nil and gen0 ~= nil else sigOk = sig0 ~= sig1 end
    check("15. a k move changes the Spells pane's signature (and the TBC book's generation)",
        sigOk and genOk,
        string.format("pane=%s sig moved=%s gen moved=%s", tostring(sig0 ~= nil), tostring(sig0 ~= sig1),
            tostring(genOk)))
end

-- 16. T128 (docs/tasks/T128-trade-score-and-rank-tips.md): the author's
-- Starfire, What if +550 spell damage (1010) and live (460), per mana / per
-- sec as the screenshots show them, verbatim. The score multiplies:
-- (eff / eff of max) * (rate / rate of max) ^ k.
local SF1010 = {
    { 1, 6.13, 166.5 }, { 2, 5.43, 209.6 }, { 3, 5.17, 265.8 }, { 4, 4.98, 327.1 },
    { 5, 4.95, 389.3 }, { 6, 5.02, 451.7 }, { 7, 4.87, 472.8 }, { 8, 4.59, 484.8 },
}
local SF460 = {
    { 1, 3.43, 93.1 }, { 2, 3.16, 122.0 }, { 3, 3.10, 159.2 }, { 4, 3.07, 201.6 },
    { 5, 3.12, 244.9 }, { 6, 3.20, 288.3 }, { 7, 3.16, 307.0 }, { 8, 3.02, 319.0 },
}
rows, best, max, eff = Run(SF1010, "damage")
local s6, s7, s1 = RR.Score(rows[6], rows[8], F, 0.25), RR.Score(rows[7], rows[8], F, 0.25),
    RR.Score(rows[1], rows[8], F, 0.25)
local said1010 = Said(best, max, eff)
local good1010 = best == rows[6] and max == rows[8] and eff == rows[1]
    and math.abs(s6 - 1.0745) < 5e-4 and math.abs(s7 - 1.0544) < 5e-4 and math.abs(s1 - 1.0224) < 5e-4
    and RR.Score(rows[8], rows[8], F, 0.25) == 1
rows, best, max, eff = Run(SF460, "damage")
local said460 = Said(best, max, eff)
local good460 = best == rows[7] and max == rows[8] and eff == rows[1]
check("16. Starfire at 1010 -> best R6 (1.075 > R7 1.054 > R1 1.022), at 460 -> best R7; max R8, eff R1",
    good1010 and good460,
    string.format("1010 %s s6=%.4f s7=%.4f s1=%.4f / 460 %s", said1010, s6 or -1, s7 or -1, s1 or -1, said460))

-- 17. a small gain for a big loss never pays; a big gain for a moderate loss does
rows, best, max, eff = Run({ { 1, 1.05, 50, 100 }, { 2, 1.00, 100, 200 } }, "damage")
local small = best == rows[2]
local smallSaid = Said(best, max, eff)
rows, best, max, eff = Run({ { 1, 3.0, 60, 100 }, { 2, 1.0, 100, 200 } }, "damage")
check("17. +5% per mana / -50% per sec -> max; x3 per mana / x0.6 per sec -> that rank",
    small and best == rows[1], smallSaid .. " / " .. Said(best, max, eff))

-- 18. k = 0: best is eff (a heal: the most per mana within the floor)
SetK("damage", 0)
rows, best, max, eff = Run(SF1010, "damage")
local d0ok = best == eff and eff == rows[1]
SetK("damage", nil)
SetK("heal", 0)
rows, best, max, eff = Run(HT, "heal")
local h0ok = best == rows[6] and eff == rows[5]
SetK("heal", nil)
check("18. k 0 -> best is eff (heals: the most per mana over the floor)", d0ok and h0ok,
    "damage " .. tostring(d0ok) .. " heal " .. Said(best, max, eff))

-- 19. T128: the TRADE block's words (Words.TradeLines) -- the numbers against
-- max, the score as a ratio, and one verdict per case
do
    local W = ST.Words
    rows = Rows({ { 1, 6.13, 166.5, 1 }, { 2, 5.43, 209.6, 1 }, { 3, 5.17, 265.8, 1 }, { 4, 4.98, 327.1, 1 },
        { 5, 4.95, 389.3, 1 }, { 6, 5.02, 451.7, 1 }, { 7, 4.87, 472.8, 1 }, { 8, 4.59, 484.8, 1 } })
    RR.Pareto(rows, F)
    best, max, eff = RR.Marks(rows, rows[8], F, "damage")
    local function Name(r) return "Rank " .. tostring(r.rank) end
    local function Ctx(e, extra)
        local c = { e = e, best = best, max = max, eff = eff, kind = "damage", name = Name }
        for k2, v in pairs(extra or {}) do c[k2] = v end
        return c
    end
    local function Join(lines)
        local out = {}
        for _, l in ipairs(lines) do out[#out + 1] = tostring(l[1]) .. "=" .. tostring(l[2]) end
        return table.concat(out, "; ")
    end
    local t6, t7 = Join(W.TradeLines(Ctx(rows[6]))), Join(W.TradeLines(Ctx(rows[7])))
    local t5 = Join(W.TradeLines(Ctx(rows[5], { beatenBy = rows[6] })))
    local t8, t1 = Join(W.TradeLines(Ctx(rows[8]))), Join(W.TradeLines(Ctx(rows[1])))
    local t2 = Join(W.TradeLines(Ctx(rows[2])))
    local tf = Join(W.TradeLines(Ctx(rows[2], { kind = "heal", floorRow = rows[8] })))
    local good = t6:find("Per mana=+9%", 1, true) and t6:find("Per sec=-7%", 1, true)
        and t6:find("Score=1.075 vs max 1.000", 1, true) and t6:find("holds best", 1, true)
        and t7:find("Rank 6 trades better (1.075 vs 1.054)", 1, true)
        and t5:find("beaten by Rank 6", 1, true)
        and t8:find("holds max", 1, true) and t1:find("holds eff", 1, true)
        and t1:find("Rank 6 trades better (1.075 vs 1.022)", 1, true)
        and t2:find("trade does not pay (0.959)", 1, true)
        and tf:find("under 40% of Rank 8's heal", 1, true)
    check("19. Words.TradeLines: per mana / per sec against max, score as a ratio, the verdicts",
        good and true or false, t6 .. " | " .. t7 .. " | " .. t5 .. " | " .. t8 .. " | " .. t1 .. " | " .. t2 .. " | " .. tf)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails > 0 and 1 or 0)
