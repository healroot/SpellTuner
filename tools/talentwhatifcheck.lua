-- tools/run.sh --flavour forever tools/talentwhatifcheck.lua
--
-- T134 (docs/tasks/T134-forever-launch-talents.md): the launch talents.
--
--   1. Bloom in the live book: the value and per mana carry it, textValue and
--      the bonus do not; Rejuvenation and Regrowth only; rank 0 nothing
--   2. Spirit: never read -> said, no amount; secret in combat -> the last
--      plain reading; a secret never leaves the adapter
--   3. the bonus fit reads the text, so Bloom never measures as a share
--   4. What if rows: every talent the tables name; the family on screen only;
--      clamped to the rule; no rows and a sentence when ranks are unread
--   5. What if numbers: Bloom, Spirit, Living Spirit, a multiplier, a periodic
--      multiplier on a hybrid, a cast talent, cost talents added; downwards too
--   6. the live book, its generation and its entries are never written; a
--      typed rank equal to the live one moves nothing; with +healing, in order
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
-- Forever values average crit in (Spells/Book.lua's CritFactor, tools/critcheck.lua);
-- this suite's numbers are the text's, so the stub's spell crit is 0 here
if type(S.crit) == "table" then for school = 1, 7 do S.crit[school] = 0 end end
local Book, WI = ST.Book, ST.WhatIf

S.level, ST.player.level = 26, 26

S.AddSpell(1430, "Rejuvenation", "Rank 3", function() return "Heals the target for 92 over 12 sec." end,
    { cast = 0, cost = 75, level = 16, base = 774 })
S.AddSpell(5187, "Healing Touch", "Rank 3", function() return "Heals a friendly target for 188 to 232." end,
    { cast = 2500, cost = 110, level = 14, base = 5185 })
S.AddSpell(8938, "Regrowth", "Rank 2", function()
    return "Heals a friendly target for 165 to 187 and another 154 over 21 sec." end,
    { cast = 2000, cost = 125, level = 18 })

local TRAIT_NAMES = { "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes",
    "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo" }
local function Use(talents)
    WI:Clear()
    if talents == false then
        C_Traits, C_ClassTalents = nil, nil
    else
        S.AddTraits(talents)
    end
    for _, n in ipairs(TRAIT_NAMES) do ST.API.Invalidate(n) end
    S.Fire("PLAYER_TALENT_UPDATE")
    Book:MarkDirty()
    return Book:Get()
end
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local realUnitStat = UnitStat
local function SetStat(fn)
    UnitStat = fn
    ST.API.Invalidate("UnitStat")
    Book._spirit, Book._spiritTriedAt = nil, nil
end

--------------------------------------------------------------------------------
-- 1: Bloom in the live book
--------------------------------------------------------------------------------
T("1 no Bloom: the value is the text, no expiry heal", function()
    local b = Use({})
    local e = b.spells[1430]
    return e and Near(e.value, 92) and Near(e.textValue, 92) and e.expiryHeal == nil, tostring(e and e.value)
end)

T("1 Bloom 1, Spirit 380: Rejuvenation 92 + 380; per mana and per second follow; text and share do not", function()
    local b = Use({ Bloom = 1 })
    local e = b.spells[1430]
    local x = e and e.expiryHeal
    return x and Near(e.value, 472) and Near(e.textValue, 92) and Near(e.perMana, 472 / 75)
        and x.talent == "Bloom" and x.amount == 380 and x.pct == 100
        and x.text == "+380 if it runs out (100% of 380 Spirit)"
        and x.words == "Bloom +380 if it runs out (100% of 380 Spirit)",
        string.format("value=%s words=%s", tostring(e and e.value), tostring(x and x.words))
end)

T("1 Bloom names Regrowth too, and not Healing Touch or Wrath", function()
    local b = Use({ Bloom = 1 })
    local r, h, w = b.spells[8938], b.spells[5187], b.spells[5176]
    return r and Near(r.value, r.textValue + 380) and h and h.expiryHeal == nil and Near(h.value, h.textValue)
        and w and w.expiryHeal == nil,
        tostring(r and r.value)
end)

T("1 the new tables as generated: Bloom, Living Spirit, Tranquil Spirit, Improved Healing, Tidal Focus", function()
    local e, s, c = ST.TalentExpiry, ST.TalentStats, ST.TalentCosts
    local bloom, ls = e.DRUID.Bloom, s.DRUID["Living Spirit"]
    local ts, ih, tf = c.DRUID["Tranquil Spirit"], c.PRIEST["Improved Healing"], c.SHAMAN["Tidal Focus"]
    return bloom.pctPerRank[1] == 100 and bloom.scope.stat == "Spirit"
        and table.concat(bloom.scope.spells, ",") == "Rejuvenation,Regrowth"
        and table.concat(ls.pctPerRank, ",") == "5,10,15"
        and table.concat(ts.pctPerRank, ",") == "2,4,6,8,10"
        and table.concat(ts.scope.spells, ",") == "Healing Touch,Tranquility"
        and table.concat(ih.pctPerRank, ",") == "5,10,15"
        and tf.scope.kind == "heal"
end)

--------------------------------------------------------------------------------
-- 2: Spirit
--------------------------------------------------------------------------------
T("2 Spirit never read: said, and no amount in the value", function()
    SetStat(nil)
    local b = Use({ Bloom = 1 })
    local e = b.spells[1430]
    local x = e.expiryHeal
    SetStat(realUnitStat)
    return x and x.amount == nil and x.text == "Spirit not read" and Near(e.value, 92), tostring(x and x.words)
end)

T("2 a secret Spirit keeps the last plain reading, and leaves the adapter as nil, secret", function()
    SetStat(realUnitStat)
    Use({ Bloom = 1 })
    S.stats[5] = 400
    Book:MarkDirty()
    local before = Book:Get().spells[1430].value
    local sec = S.Secret()
    UnitStat = function() return sec, sec, sec, sec end
    ST.API.Invalidate("UnitStat")
    local v, why = ST.API.Spirit()
    Book:MarkDirty()
    local after = Book:Get().spells[1430].value
    S.stats[5] = 380
    SetStat(realUnitStat)
    return v == nil and why == "secret" and Near(before, 492) and Near(after, 492),
        string.format("v=%s why=%s before=%s after=%s", tostring(v), tostring(why), tostring(before), tostring(after))
end)

--------------------------------------------------------------------------------
-- 3: the fit
--------------------------------------------------------------------------------
-- review m10: Spirit moves with the bonus, so a fit fed the value would see a steeper line
T("3 the bonus fit reads the text: a Bloom in the value does not change the measured share", function()
    SetStat(realUnitStat)
    Use({ Bloom = 1 })
    S.AddSpell(95300, "Rejuvenation", "Rank 9", function()
        return "Heals the target for " .. math.floor(500 + 0.8 * (S.bonusHealing or 0)) .. " over 12 sec." end,
        { cast = 0, cost = 200, level = 25, base = 774 })
    for _, bonus in ipairs({ 0, 150, 300, 450 }) do
        S.bonusHealing = bonus
        S.stats[5] = 380 + bonus * 2
        Book._spirit, Book._spiritTriedAt = nil, nil
        Book:MarkDirty()
        Book:Get()
    end
    local m = Book._Measured(95300, "heal")
    S.bonusHealing = 0
    S.stats[5] = 380
    Book._spirit, Book._spiritTriedAt = nil, nil
    Book:MarkDirty()
    return type(m) == "number" and math.abs(m - 0.8) < 0.02, tostring(m)
end)

--------------------------------------------------------------------------------
-- 4: rows
--------------------------------------------------------------------------------
local function Keys(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = r.key end
    return table.concat(out, ",")
end

T("4 the keys: Level first, each talent once, 0 to its top rank, steps of one; Spirit last", function()
    Use({})
    local rows = WI:ClassRows()
    local seen, bad = {}, {}
    for _, r in ipairs(rows or {}) do
        if seen[r.key] then bad[#bad + 1] = "twice " .. r.key end
        seen[r.key] = r
        if r.key ~= "spirit" and r.key ~= "level" and not (r.min == 0 and r.max >= 1 and r.step == 1 and r.compact) then
            bad[#bad + 1] = r.key
        end
    end
    return rows[1].key == "level" and rows[1].max == 60 and seen["talent:Bloom"] and seen["talent:Bloom"].max == 1
        and seen["talent:Naturalist"].max == 5 and rows[#rows].key == "spirit" and #bad == 0
        and WI:ClassTitle() == "LEVEL AND TALENTS", table.concat(bad, ",")
end)

T("4 T138 the drawer: Level, and Spirit where Bloom reads it; never a talent row", function()
    local b = Use({})
    local rj = Keys(WI:ClassRowsFor(b.families.Rejuvenation))
    local ht = Keys(WI:ClassRowsFor(b.families["Healing Touch"]))
    return rj == "level,spirit" and ht == "level", rj .. " / " .. ht
end)

T("4 T138 the sentence names the plan's talents, else your own", function()
    local b = Use({})
    local own = WI:ClassNote(b.families.Rejuvenation)
    WI:Set("talent:Bloom", 1)
    local planned = WI:ClassNote(b.families.Rejuvenation)
    WI:Clear()
    return own:find("Your own talents; Talent plan... tries a build.", 1, true) == 1
        and planned:find("Talents from your plan: Bloom 1.", 1, true) == 1, planned
end)

T("4 a typed rank clamps to the rule; a fraction floors; a talent of another class is refused", function()
    Use({})
    WI:Set("talent:Bloom", 9)
    local top = WI:Get("talent:Bloom")
    WI:Set("talent:Genesis", 2.7)
    local floor = WI:Get("talent:Genesis")
    WI:Set("talent:Tidal Focus", 3)
    local other = WI:Get("talent:Tidal Focus")
    WI:Clear()
    return top == 1 and floor == 2 and other == nil, string.format("%s %s %s", tostring(top), tostring(floor), tostring(other))
end)

T("4 ranks unread: only Level, a sentence, and nothing moves (never assumed 0)", function()
    local b = Use(false)
    local rows, note = WI:ClassRows(), WI:ClassNote()
    WI:Set("talent:Bloom", 1)
    local typed = WI:Get("talent:Bloom")
    local e = WI:Book().spells[1430]
    return Keys(rows) == "level" and note == "Your talents were not read yet, so a talent plan can't be tried here."
        and typed == nil and Near(e.value, b.spells[1430].value), tostring(note)
end)

--------------------------------------------------------------------------------
-- 5: numbers
--------------------------------------------------------------------------------
T("5 Bloom typed: +380 on Rejuvenation, the rules re-run, the card's words the typed ones", function()
    local b = Use({})
    WI:Set("talent:Bloom", 1)
    local w = WI:Book()
    local e = w.spells[1430]
    local h = w.spells[5187]
    WI:Clear()
    return Near(e.value, 472) and Near(e.perMana, 472 / 75) and Near(e.textValue, 92)
        and e.expiryHeal and e.expiryHeal.amount == 380
        and Near(h.value, b.spells[5187].value) and h.expiryHeal == nil, tostring(e.value)
end)

T("5 Bloom taken, typed off: the amount leaves", function()
    Use({ Bloom = 1 })
    WI:Set("talent:Bloom", 0)
    local e = WI:Book().spells[1430]
    WI:Clear()
    return Near(e.value, 92) and e.expiryHeal == nil, tostring(e.value)
end)

T("5 Spirit typed, Living Spirit typed: 1000 x 1.15; Living Spirit alone 380 x 1.15", function()
    Use({ Bloom = 1 })
    WI:Set("talent:Living Spirit", 3)
    local a = WI:Book().spells[1430]
    WI:Set("spirit", 1000)
    local c = WI:Book().spells[1430]
    WI:Clear()
    return Near(a.value, 92 + 380 * 1.15) and Near(c.value, 92 + 1000 * 1.15),
        string.format("%s %s", tostring(a.value), tostring(c.value))
end)

T("5 Living Spirit already taken: typed down, the client's Spirit is divided by it", function()
    Use({ Bloom = 1, ["Living Spirit"] = 3 })
    WI:Set("talent:Living Spirit", 0)
    local e = WI:Book().spells[1430]
    WI:Clear()
    return Near(e.value, 92 + 380 / 1.15), tostring(e.value)
end)

T("5 Improved Rejuvenation 3: the text and the share x1.15; Healing Touch untouched", function()
    local b = Use({})
    WI:Set("talent:Improved Rejuvenation", 3)
    local w = WI:Book()
    local e, h = w.spells[1430], w.spells[5187]
    local live = b.spells[1430]
    WI:Clear()
    return Near(e.value, 92 * 1.15) and Near(e.bonus.counts, live.bonus.counts * 1.15)
        and Near(h.value, b.spells[5187].value) and Near(live.value, 92),
        string.format("%s %s", tostring(e.value), tostring(e.bonus.counts))
end)

T("5 Improved Rejuvenation taken, typed down: divided, not multiplied", function()
    Use({ ["Improved Rejuvenation"] = 3 })
    WI:Set("talent:Improved Rejuvenation", 1)
    local e = WI:Book().spells[1430]
    WI:Clear()
    return Near(e.value, 92 * 1.05 / 1.15), tostring(e.value)
end)

T("5 Genesis 5: the part over time only -- Regrowth's over moves, its range does not", function()
    local b = Use({})
    WI:Set("talent:Genesis", 5)
    local e = WI:Book().spells[8938]
    local r = WI:Book().spells[1430]
    local l = b.spells[8938]
    local h = WI:Book().spells[5187]
    WI:Clear()
    return Near(e.parsed.heal.over, 154 * 1.10) and Near(e.parsed.heal.min, 165) and Near(e.parsed.heal.max, 187)
        and Near(r.value, 92 * 1.10) and Near(h.value, b.spells[5187].value) and l.parsed.heal.over == 154,
        tostring(e.parsed.heal.over)
end)

T("5 Naturalist 5: Healing Touch's cast down 0.5 s, per second follows; Regrowth's unchanged", function()
    local b = Use({})
    WI:Set("talent:Naturalist", 5)
    local w = WI:Book()
    local h, r = w.spells[5187], w.spells[8938]
    WI:Clear()
    return Near(h.cast, 2.0) and h.perSec > b.spells[5187].perSec and Near(r.cast, 2.0)
        and Near(b.spells[5187].cast, 2.5), tostring(h.cast)
end)

T("5 Naturalist taken, typed off: the cast comes back", function()
    Use({ Naturalist = 5 })
    WI:Set("talent:Naturalist", 0)
    local h = WI:Book().spells[5187]
    WI:Clear()
    return Near(h.cast, 3.0), tostring(h.cast)
end)

T("5 Tranquil Spirit 5: cost 110 -> 99, per mana follows; the live cost unchanged", function()
    local b = Use({})
    WI:Set("talent:Tranquil Spirit", 5)
    local h = WI:Book().spells[5187]
    WI:Clear()
    return h.cost.amount == 99 and Near(h.perMana, h.value / 99) and b.spells[5187].cost.amount == 110,
        tostring(h.cost.amount)
end)

T("5 cost talents add: live Moonglow-free Tranquil 5 typed to 2 is 110 x 0.96 / 0.90", function()
    Use({ ["Tranquil Spirit"] = 5 })
    WI:Set("talent:Tranquil Spirit", 2)
    local h = WI:Book().spells[5187]
    WI:Clear()
    return h.cost.amount == math.floor(110 * 0.96 / 0.90 + 0.5), tostring(h.cost.amount)
end)

-- review m10: the only pair a rank has: Improved Wrath and Moonglow on Wrath
S.AddSpell(5176, "Wrath", "Rank 3", function() return "Causes 40 to 50 Nature damage to the target." end,
    { cast = 400, cost = 100, level = 14 })

T("5 cost talents add: Improved Wrath 1 and Moonglow 1 on Wrath are 18% off, not the larger", function()
    Use({})
    WI:Set("talent:Improved Wrath", 1)
    WI:Set("talent:Moonglow", 1)
    local c = WI:Book().spells[5176].cost.amount
    WI:Clear()
    return c == 82, tostring(c)
end)

--------------------------------------------------------------------------------
-- review fixes
--------------------------------------------------------------------------------
T("7 a cast talent typed to an instant says so and keeps its row (m1)", function()
    local b = Use({})
    WI:Set("talent:Improved Wrath", 5)
    local w = WI:Book().spells[5176]
    WI:Clear()
    return w.cast == 0 and w.castKind == "instant", tostring(w.cast) .. " " .. tostring(w.castKind)
end)

T("7 a talent that says amount healed does not reach an absorb, unless it names the spell (m2)", function()
    local shield = { name = "Power Word: Shield", parsed = { absorb = 100 } }
    return Book.MultMatches({ kind = "heal" }, shield, "heal") == false
        and Book.MultMatches({ instant = true }, shield, "heal") == false
        and Book.MultMatches({ spells = { "Power Word: Shield" } }, shield, "heal") == true
        and Book.MultMatches({ kind = "heal" }, { name = "x", parsed = { heal = 5, absorb = 1 } }, "heal") == true
end)

T("7 a moved share says it moved: neither the measured range nor the live talent's words (m4, m5)", function()
    local b = Use({ ["Gift of Nature"] = 5 })
    WI:Set("talent:Gift of Nature", 0)
    local w = WI:Book().spells[5187]
    local card, how = ST.Words.Bonus(w, "card", "heal"), ST.Words.Bonus(w, "how", "heal")
    WI:Clear()
    return card:find("under the typed talents (was", 1, true) ~= nil and not card:find("Gift of Nature", 1, true)
        and how:find("under the typed talents", 1, true) ~= nil and b.spells[5187].bonus.movedFrom == nil, card
end)

T("7 the plain tooltip says Bloom is in its numbers; unread, it says that instead (m6)", function()
    SetStat(realUnitStat)
    Use({ Bloom = 1 })
    local function Find(want)
        for _, l in ipairs(ST.SpellTip:Lines(1430, false, "spell") or {}) do
            if type(l.l) == "string" and l.l:find(want, 1, true) then return true end
        end
        return false
    end
    local has = Find("Includes Bloom +380 if it runs out (100% of 380 Spirit) (predicted)")
    SetStat(function() return nil end)
    Book:MarkDirty()
    local unread = Find("Bloom: Spirit not read (predicted)") and not Find("Includes")
    SetStat(realUnitStat)
    Book:MarkDirty()
    return has and unread, tostring(has) .. " " .. tostring(unread)
end)

T("7 Spirit refuses infinity; an ordinary number still lands (m7)", function()
    Use({ Bloom = 1 })
    local refused = not WI:Set("spirit", "1e999") and WI:Get("spirit") == nil
    WI:Set("spirit", "500")
    local v = WI:Get("spirit")
    WI:Clear()
    return refused and v == 500, tostring(refused) .. " " .. tostring(v)
end)

T("7 the sentence names what does not move; a family no talent touches says only that (m8)", function()
    local b = Use({})
    local note = WI:ClassNote(b.families.Rejuvenation)
    local good = true
    for _, w in ipairs({ "Intellect to crit", "regen", "procs", "Oath of Light", "teaches" }) do
        good = good and note:find(w, 1, true) ~= nil
    end
    local none = WI:ClassNote({ ranks = {} })
    return good and none == "Your own talents; Talent plan... tries a build. No talent moves this spell in the What if.",
        tostring(none)
end)

--------------------------------------------------------------------------------
-- T138: the level
--------------------------------------------------------------------------------
T("9 Level: a heal rank's share moves by the ratio of the two penalties; the value with it", function()
    S.bonusHealing = 300
    local b = Use({})
    local Coef = ST.Coefficients
    local live = ST.player.level
    local pick
    for _, e in ipairs(b.families.Rejuvenation.ranks) do
        local pa = Coef.LevelPenalty(e.id, e.level, live, "heal")
        local pb = Coef.LevelPenalty(e.id, e.level, live + 10, "heal")
        if type(e.bonus) == "table" and type(e.bonus.counts) == "number" and type(e.bonus.of) == "number"
            and e.bonus.of > 0 and pa > 0 and pb < pa then pick = e break end
    end
    if not pick then
        local seen = {}
        for _, e in ipairs(b.families.Rejuvenation.ranks) do
            seen[#seen + 1] = string.format("%s L%s c%s of%s", tostring(e.id), tostring(e.level),
                tostring(e.bonus and e.bonus.counts), tostring(e.bonus and e.bonus.of))
        end
        return false, "no rank with a share the level moves: " .. table.concat(seen, "; ")
    end
    WI:Set("level", live + 10)
    local w = WI:Book().spells[pick.id]
    local pa = Coef.LevelPenalty(pick.id, pick.level, live, "heal")
    local pb = Coef.LevelPenalty(pick.id, pick.level, live + 10, "heal")
    local share = pick.bonus.counts * pb / pa
    local drop = (pick.bonus.counts - share) * pick.bonus.of
    WI:Clear()
    S.bonusHealing = 0
    Use({})
    return Near(w.bonus.counts, share) and w.bonus.atLevel == live + 10 and w.value < pick.value
        and w.perMana < pick.perMana, string.format("share %s -> %s value %s -> %s (drop %.1f)",
            tostring(pick.bonus.counts), tostring(w.bonus.counts), tostring(pick.value), tostring(w.value), drop)
end)

T("9 Level: the live level, or a damage rank, moves nothing; the sentence says what it moves", function()
    local b = Use({})
    WI:Set("level", ST.player.level)
    local same = WI:Get("level") == ST.player.level and Near(WI:Book().spells[1430].value, b.spells[1430].value)
    WI:Set("level", 60)
    local wr = b.families.Wrath.ranks[1]
    local dmg = Near(WI:Book().spells[wr.id].value, wr.value)
    local note = WI:ClassNote(b.families.Rejuvenation)
    WI:Set("level", 99)
    local clamped = WI:Get("level")
    WI:Clear()
    return same and dmg and clamped == 60 and note:find("Level 60: the ranks learned by then compete, each heal rank's +healing share", 1, true) == 1,
        tostring(note)
end)

--------------------------------------------------------------------------------
-- T136: durations
--------------------------------------------------------------------------------
T("8 the durations table as generated: Nature's Splendor in three groups, Improved SW:P", function()
    local d = ST.TalentDurations
    local ns = d.DRUID["Nature's Splendor (Moonfire, Rejuvenation)"]
    local rg = d.DRUID["Nature's Splendor (Regrowth)"]
    local swp = d.PRIEST["Improved Shadow Word: Pain"]
    return ns and ns.talent == "Nature's Splendor" and ns.secPerRank[1] == 3 and rg.secPerRank[1] == 6
        and d.DRUID["Nature's Splendor (Insect Swarm)"].secPerRank[1] == 2
        and swp.secPerRank[1] == 3 and swp.secPerRank[2] == 6 and d.SHAMAN["Call of Flame"] == nil
end)

T("8 Nature's Splendor typed: Rejuvenation 92 over 12 -> 115 over 15; per mana up, per second the same", function()
    local b = Use({})
    local e = b.spells[1430]
    WI:Set("talent:Nature's Splendor", 1)
    local w = WI:Book().spells[1430]
    WI:Clear()
    return Near(w.value, 92 * 15 / 12) and w.dur == 15 and Near(w.perMana, w.value / 75)
        and Near(w.perSec, e.perSec) and e.value == 92 and e.dur == 12,
        string.format("%s over %s, per sec %s vs %s", tostring(w.value), tostring(w.dur), tostring(w.perSec),
            tostring(e.perSec))
end)

T("8 Regrowth: only the over-time part lasts 6 s longer, the hit unchanged", function()
    local b = Use({})
    local e = b.spells[8938]
    WI:Set("talent:Nature's Splendor", 1)
    local w = WI:Book().spells[8938]
    WI:Clear()
    return Near(w.over, 154 * 27 / 21) and w.dur == 27 and w.min == e.min and w.max == e.max,
        tostring(w.over) .. " over " .. tostring(w.dur)
end)

T("8 taken live, typed off: the client's 15 s text goes back to 12", function()
    S.AddSpell(1430, "Rejuvenation", "Rank 3", function() return "Heals the target for 115 over 15 sec." end,
        { cast = 0, cost = 75, level = 16, base = 774 })
    Use({ ["Nature's Splendor"] = 1 })
    WI:Set("talent:Nature's Splendor", 0)
    local w = WI:Book().spells[1430]
    WI:Clear()
    S.AddSpell(1430, "Rejuvenation", "Rank 3", function() return "Heals the target for 92 over 12 sec." end,
        { cast = 0, cost = 75, level = 16, base = 774 })
    Use({})
    return Near(w.value, 92) and w.dur == 12, tostring(w.value) .. " over " .. tostring(w.dur)
end)

--------------------------------------------------------------------------------
-- 6: identity
--------------------------------------------------------------------------------
T("6 the live book is not written, its generation not moved, by a typed talent", function()
    local b = Use({})
    local gen, value, cost = b.generation, b.spells[1430].value, b.spells[5187].cost.amount
    WI:Set("talent:Bloom", 1)
    WI:Set("talent:Tranquil Spirit", 5)
    WI:Book()
    local a = Book:Get()
    local good = a.generation == gen and a.spells[1430].value == value and a.spells[5187].cost.amount == cost
        and a.spells[1430].expiryHeal == nil
    WI:Clear()
    return good
end)

T("6 a typed rank equal to the live one moves nothing", function()
    local b = Use({ Bloom = 1, Genesis = 3 })
    WI:Set("talent:Genesis", 3)
    local e = WI:Book().spells[1430]
    local l = b.spells[1430]
    WI:Clear()
    return Near(e.value, l.value) and Near(e.perMana, l.perMana) and e.expiryHeal.amount == 380
end)

T("6 with +150 healing: the typed talents' share prices the bonus, and Bloom stays flat", function()
    local b = Use({ })
    local live = b.spells[1430]
    local counts = live.bonus.counts
    WI:Set("heal", (live.bonus.of or 0) + 150)
    WI:Set("talent:Bloom", 1)
    WI:Set("talent:Improved Rejuvenation", 3)
    local e = WI:Book().spells[1430]
    WI:Clear()
    return Near(e.value, 92 * 1.15 + counts * 1.15 * 150 + 380), tostring(e.value)
end)

T("6 the summary names the talent; Clear brings the book back", function()
    local b = Use({})
    WI:Set("talent:Bloom", 1)
    local words = WI:Summary()
    WI:Clear()
    return words == "Bloom 1" and not WI:Active() and Near(WI:Book().spells[1430].value, b.spells[1430].value), words
end)

T("6 a live rank above the rule: no rule, nothing raises", function()
    Use({ Bloom = 2 })
    local e = Book:Get().spells[1430]
    WI:Set("talent:Genesis", 1)
    local w = WI:Book().spells[1430]
    WI:Clear()
    return e.expiryHeal and e.expiryHeal.amount == nil and e.expiryHeal.text == "rank 2: no rule"
        and Near(e.value, 92) and Near(w.value, 92 * 1.02), tostring(w.value)
end)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails > 0 and 1 or 0)
