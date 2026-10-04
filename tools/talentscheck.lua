-- tools/run.sh --flavour forever tools/talentscheck.lua
--
-- T129 (docs/tasks/T129-forever-talent-casts.md): Forever reads the player's
-- talent ranks and the +bonus estimate takes a cast-time talent's spell at
-- its cast BEFORE the talent.
--
--   1. Data/Talents_Forever.lua's shape (ST.TalentRules): every class known;
--      each rule's castPerRank positive, strictly ascending, as long as the
--      talent's ranks; spells non-empty; Improved Wrath 0.1..0.5; no Eclipse /
--      Maelstrom Weapon / Nature's Swiftness
--   2. ST.API.TalentRanks: absent without C_Traits; the stub's druid config
--      (Improved Wrath 2) read by name, the untaken node left out; a config
--      without trees absent; a secret node "secret"
--   3. the book, druid with Improved Wrath 2 (oracles of section 4):
--      Wrath R2 (client 1.5) baseCast 1.7, estimate 1.7/3.5 x its sub-20
--      factor, why "1.5 + 0.2 Improved Wrath 2"; R1 (client 1.3) 1.5 (the
--      clamp); R3 (client 1.8) 2.0/3.5; Healing Touch with no Naturalist point
--      unchanged
--   4. C_Traits absent: no baseCast, "talents not read", the old counts
--   5. a secret in the walk: the same, the reason "secret"
--   6. a rank above the rule: "<talent> <r>: no rule", no baseCast, the old words
--   7. a respec (PLAYER_TALENT_UPDATE) moves the base cast
--   8. /st dump's talents line and /st tooltip why's cast talent
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
local Book = ST.Book
local Coef = ST.Coefficients

local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9 end
local function Has(s, part) return type(s) == "string" and s:find(part, 1, true) ~= nil end

local TRAIT_NAMES = { "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes",
    "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo" }
local function Forget()
    for _, n in ipairs(TRAIT_NAMES) do ST.API.Invalidate(n) end
end
-- install a talent fixture (nil: C_Traits absent) and rescan
local function Use(talents, opts)
    if talents == false then
        C_Traits, C_ClassTalents = nil, nil
    else
        S.AddTraits(talents, opts)
    end
    Forget()
    S.Fire("PLAYER_TALENT_UPDATE")
    Book:MarkDirty()
    return Book:Get()
end

-- Wrath: R1 is the stub's own 5176 (cast 1.3 with 2 points, as the author's
-- client), R2 1.5 (1.7 base), R3 1.8 (2.0 base). Healing Touch 5185 is the
-- stub's, cast 1.5, no Naturalist point.
S.AddSpell(5176, "Wrath", "Rank 1", function() return "Causes 13 to 16 Nature damage to the target." end,
    { cast = 1300, cost = 20, level = 1 })
S.AddSpell(95402, "Wrath", "Rank 2", function() return "Causes 27 to 31 Nature damage to the target." end,
    { cast = 1500, cost = 35, level = 6 })
S.AddSpell(95403, "Wrath", "Rank 3", function() return "Causes 48 to 55 Nature damage to the target." end,
    { cast = 1800, cost = 55, level = 14 })

--------------------------------------------------------------------------------
-- 1: the data file
--------------------------------------------------------------------------------
T("1 the talent rules: every class, castPerRank ascending, one per rank", function()
    local R = ST.TalentRules
    if type(R) ~= "table" then return false, "no ST.TalentRules" end
    local bad = {}
    for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        if type(R[c]) ~= "table" then bad[#bad + 1] = "class " .. c end
    end
    for c, rules in pairs(R) do
        for name, r in pairs(rules) do
            local where = c .. "/" .. tostring(name)
            if type(r.talent) ~= "string" or r.talent == "" then bad[#bad + 1] = where .. " talent" end
            if type(r.spells) ~= "table" or #r.spells == 0 then bad[#bad + 1] = where .. " spells" end
            for _, s in ipairs(r.spells or {}) do
                if type(s) ~= "string" or s == "" then bad[#bad + 1] = where .. " spell name" end
            end
            local cpr = r.castPerRank
            if type(cpr) ~= "table" or #cpr == 0 or #cpr ~= r.ranks then
                bad[#bad + 1] = where .. " ranks"
            else
                for i, v in ipairs(cpr) do
                    if type(v) ~= "number" or v <= 0 or (i > 1 and v <= cpr[i - 1]) then
                        bad[#bad + 1] = where .. " castPerRank[" .. i .. "]"
                    end
                end
            end
        end
    end
    return #bad == 0, table.concat(bad, "; ")
end)

T("1 Improved Wrath is 0.1..0.5 on Wrath; no proc or charge talent", function()
    local iw = ST.TalentRules.DRUID["Improved Wrath"]
    local want = { 0.1, 0.2, 0.3, 0.4, 0.5 }
    local good = iw and iw.spells[1] == "Wrath" and #iw.spells == 1 and #iw.castPerRank == 5
    for i = 1, 5 do good = good and Near(iw.castPerRank[i], want[i]) end
    local banned = { ["Eclipse"] = true, ["Maelstrom Weapon"] = true, ["Nature's Swiftness"] = true }
    local found = {}
    for _, rules in pairs(ST.TalentRules) do
        for name, r in pairs(rules) do
            if banned[name] or banned[r.talent] then found[#found + 1] = name end
        end
    end
    return good and #found == 0, "found " .. table.concat(found, ", ")
end)

--------------------------------------------------------------------------------
-- 2: the adapter
--------------------------------------------------------------------------------
T("2 TalentRanks: absent without C_Traits", function()
    C_Traits, C_ClassTalents = nil, nil
    Forget()
    local r, why = ST.API.TalentRanks()
    return r == nil and why == "absent", tostring(r) .. " " .. tostring(why)
end)

T("2 TalentRanks: the druid config by name, rank > 0 only", function()
    S.AddTraits(S.DRUID_TALENTS)
    Forget()
    local r, why = ST.API.TalentRanks()
    local n = 0
    for _ in pairs(r or {}) do n = n + 1 end
    return type(r) == "table" and r["Improved Wrath"] == 2 and n == 1 and why == nil,
        string.format("n=%d iw=%s why=%s", n, tostring(r and r["Improved Wrath"]), tostring(why))
end)

T("2 TalentRanks: a config without trees answers absent", function()
    S.AddTraits()
    Forget()
    local r, why = ST.API.TalentRanks()
    return r == nil and why == "absent", tostring(why)
end)

T("2 TalentRanks: a secret node makes the answer secret", function()
    S.AddTraits(S.DRUID_TALENTS, { secret = "node" })
    Forget()
    local r, why = ST.API.TalentRanks()
    return r == nil and why == "secret", tostring(why)
end)

--------------------------------------------------------------------------------
-- 3: the book with Improved Wrath 2
--------------------------------------------------------------------------------
local book = Use(S.DRUID_TALENTS)

T("3 Wrath R2 (client 1.5): baseCast 1.7, estimate 1.7 / 3.5 x sub-20", function()
    local e = book.spells[95402]
    local b = e and e.bonus
    local want = (1.7 / 3.5) * Coef.Sub20(6)
    return e and Near(e.cast, 1.5) and Near(e.baseCast, 1.7) and e.castTalent == "Improved Wrath 2"
        and b and b.from == "estimated" and Near(b.counts, want)
        and Has(b.why, "cast 1.7 / 3.5 (1.5 + 0.2 Improved Wrath 2) x "),
        string.format("cast=%s base=%s counts=%s want=%s why=%s", tostring(e and e.cast), tostring(e and e.baseCast),
            tostring(b and b.counts), tostring(want), tostring(b and b.why))
end)

T("3 Wrath R1 (client 1.3): baseCast 1.5, estimate 1.5 / 3.5 (the clamp)", function()
    local e = book.spells[5176]
    local b = e and e.bonus
    return e and Near(e.cast, 1.3) and Near(e.baseCast, 1.5) and b and Near(b.counts, (1.5 / 3.5) * Coef.Sub20(1))
        and Has(b.why, "cast 1.5 / 3.5 (1.3 + 0.2 Improved Wrath 2)"),
        string.format("base=%s counts=%s why=%s", tostring(e and e.baseCast), tostring(b and b.counts), tostring(b and b.why))
end)

T("3 Wrath R3 (client 1.8): estimate 2.0 / 3.5", function()
    local e = book.spells[95403]
    local b = e and e.bonus
    return e and Near(e.baseCast, 2.0) and b and Near(b.counts, (2.0 / 3.5) * Coef.Sub20(14))
        and Has(b.why, "cast 2.0 / 3.5 (1.8 + 0.2 Improved Wrath 2)"),
        string.format("base=%s why=%s", tostring(e and e.baseCast), tostring(b and b.why))
end)

T("3 Healing Touch with no Naturalist point: unchanged, no castTalent", function()
    local e = book.spells[5185]
    local b = e and e.bonus
    local plain = { cast = e.cast, level = e.level, castKind = e.castKind }
    local counts, why = Coef.Estimate(plain, "direct")
    return e and e.baseCast == nil and e.castTalent == nil and b and b.counts == counts and b.why == why
        and not Has(b.why, "("),
        string.format("castTalent=%s why=%s", tostring(e and e.castTalent), tostring(b and b.why))
end)

T("3 the card's Cast stays the client's; the seam's fields pass the contract", function()
    local e = book.spells[95402]
    return e.cast == 1.5 and Book._seamFields.baseCast == true and Book._seamFields.castTalent == true
end)

--------------------------------------------------------------------------------
-- 4 / 5: talents not read
--------------------------------------------------------------------------------
T("4 C_Traits absent: no baseCast, 'talents not read', the old counts", function()
    local b4 = Use(false)
    local e, h = b4.spells[95402], b4.spells[5185]
    local b = e and e.bonus
    local want = Coef.Direct(1.5) * Coef.Sub20(6)
    return e.baseCast == nil and e.castTalent == "talents not read" and Near(b.counts, want)
        and Has(b.why, "cast 1.5 / 3.5 (talents not read) x ") and Book._talentsWhy == "absent"
        and h.castTalent == "talents not read",
        string.format("castTalent=%s counts=%s why=%s", tostring(e.castTalent), tostring(b.counts), tostring(b.why))
end)

T("5 a secret in the walk: as absent, the reason secret", function()
    local b5 = Use(S.DRUID_TALENTS, { secret = "node" })
    local e = b5.spells[95402]
    local b = e and e.bonus
    return e.baseCast == nil and e.castTalent == "talents not read" and Near(b.counts, Coef.Direct(1.5) * Coef.Sub20(6))
        and Has(b.why, "(talents not read)") and Book._talentsWhy == "secret",
        tostring(Book._talentsWhy)
end)

--------------------------------------------------------------------------------
-- 6: a rank the rule does not cover
--------------------------------------------------------------------------------
T("6 a rank above the rule: no rule, no baseCast, the old words", function()
    local b6 = Use({ ["Improved Wrath"] = 6 })
    local e = b6.spells[95402]
    local b = e and e.bonus
    return e.baseCast == nil and e.castTalent == "Improved Wrath 6: no rule"
        and Near(b.counts, Coef.Direct(1.5) * Coef.Sub20(6)) and not Has(b.why, "("),
        string.format("castTalent=%s why=%s", tostring(e.castTalent), tostring(b.why))
end)

--------------------------------------------------------------------------------
-- 7: a respec
--------------------------------------------------------------------------------
T("7 a respec to Improved Wrath 3 moves the base cast", function()
    Use(S.DRUID_TALENTS)
    local b7 = Use({ ["Improved Wrath"] = 3 })
    local e = b7.spells[95402]
    return Near(e.baseCast, 1.8) and e.castTalent == "Improved Wrath 3" and Has(e.bonus.why, "(1.5 + 0.3 Improved Wrath 3)"),
        tostring(e.bonus and e.bonus.why)
end)

--------------------------------------------------------------------------------
-- 8: /st dump and /st tooltip why
--------------------------------------------------------------------------------
local function DumpLine()
    for _, d in ipairs(ST:DumpLines()) do
        if d.key == "talents" then return d.fn() end
    end
end

T("8 /st dump: the talents line, or why none were read", function()
    Use(S.DRUID_TALENTS)
    local read = DumpLine()
    Use(false)
    local absent = DumpLine()
    Use(S.DRUID_TALENTS, { secret = "node" })
    local secret = DumpLine()
    Use({})
    local none = DumpLine()
    local dump = ST.BuildDump and ST:BuildDump() or ""
    return read == "talents: Improved Wrath 2" and absent == "talents: not read (absent)"
        and secret == "talents: not read (secret)" and none == "talents: none taken"
        and Has(dump, "talents: none taken"),
        string.format("%s | %s | %s | %s", tostring(read), tostring(absent), tostring(secret), tostring(none))
end)

T("8 /st tooltip why names the last block's cast talent", function()
    Use(S.DRUID_TALENTS)
    S.ShowSpellTooltip(GameTooltip, 95402)
    local said = {}
    local prev = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
    local okCall = pcall(SlashCmdList.SPELLTUNER, "tooltip why")
    _G.DEFAULT_CHAT_FRAME = prev
    local text = table.concat(said, "\n")
    return okCall and Has(text, "last block 95402 cast talent: Improved Wrath 2"), text
end)

print(string.format("\n%d ok, %d failed", ok, #fails))
os.exit(#fails > 0 and 1 or 0)
