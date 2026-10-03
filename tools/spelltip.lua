-- tools/run.sh --flavour tbc tools/spelltip.lua
--
-- The spell tooltip on TBC under the stub: a fake GameTooltip that records
-- what was added to it, driven the way the client drives the real one -- set a
-- spell, fire OnTooltipSetSpell (twice, as the client can), clear, re-set.
--
-- T121 (docs/tasks/T121-one-tooltip-block.md, docs/SPEC-one-ui.md; mockup
-- M5): the block is UI/SpellTip.lua's on both lines, drawn from the TBC book
-- (Spells/Book_Model.lua); UI/SpellTooltip.lua is only TBC's hook into it, and
-- Tip:Spell / Tip:Damage / Tip:Columns are deleted. Held here:
--
--   plumbing (kept from v0.14.9 / v0.15.3): the druid with the tooltip cap,
--   once per showing, off means off, `spellTooltipDamage = false` drops the
--   damage block only, never a bare pipe, a raising builder never breaks the
--   game's tooltip, the dashboard's what-if never reaches a tooltip;
--
--   the arithmetic, re-based on the block's lines:
--   1. Healing Touch R12: Per mana / Per sec are the book's entry, which is
--      RankMath's row (the simulator's value);
--   2. Casts to OOM "N from full" is RankMath:CastsToOOM for the entry from a
--      full pool;
--   3. the plain block has no HPM / Average / Downranked; the detail has
--      Heals, Crit ... 15%, After overheal (seeded), vs Rank 11 and the How
--      lines, equal to Tip:Spell's Shift lines captured on d6691fe (golden);
--   4. Swiftmend: the two Eats lines (golden from Tip:Spell);
--   5. Wrath, Moonfire, Hurricane: the block's numbers are DM.Compute's, the
--      How lines Tip:Damage's VERIFY lines (golden), Vengeance's 2.0x crit;
--   6. every detail mode: ALT shows the detail only with Alt, ALWAYS always,
--      NEVER never; the watcher re-runs OnEnter for the mode's key only;
--   7. a priest with the cap granted here (T111's fixture): the block draws
--      from the class book.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local SD, RM = MD.SpellData, MD.RankMath
local T = dofile(here .. "/lib/t.lua")
local check = T.check

-- a GameTooltip that remembers: hooks run in order, lines are stored
local tt = _G.GameTooltip
tt.hooks, tt.lines, tt.spell = {}, {}, nil
function tt:HookScript(k, fn) self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn) end
function tt:AddLine(l) self.lines[#self.lines + 1] = { l = l } end
function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = { l = l, r = r } end
function tt:NumLines() return #self.lines end
function tt:GetSpell() if self.spell then return "Spell", self.spell end end
function tt:IsShown() return true end
local owner
function tt:GetOwner() return owner end
local function fire(k) for _, fn in ipairs(tt.hooks[k] or {}) do fn(tt) end end
local function SetSpell(id)
    tt.lines = {}; fire("OnTooltipCleared")
    tt.spell = id; fire("OnTooltipSetSpell")
    return tt.lines
end

-- T80 (C1): the theme and the window manager after the kit, as the TBC TOC
-- lists them; T121: the block (UI/SpellTip.lua) right before the hook
S.Load({ "UI/Style.lua", "UI/Theme_Flat.lua", "UI/EscStack.lua", "UI/Windows.lua",
         "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/SpellTip.lua", "UI/SpellTooltip.lua" }, "SpellTuner", MD)

local function Plain(s) return (T.Strip(s or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function find(lines, label)
    for _, ln in ipairs(lines) do
        if ln.l and Plain(ln.l) == label then return ln end
    end
end
local function R(ln) return ln and Plain(ln.r) end
local function show(lines)
    for _, ln in ipairs(lines) do print("    | " .. Plain(ln.l) .. (ln.r and ("   " .. Plain(ln.r)) or "")) end
end
-- the How lines: the How pair's right side, then every line after it
local function HowLines(lines)
    local out, on = {}, false
    for _, ln in ipairs(lines) do
        if on then
            out[#out + 1] = Plain((ln.l or "") .. (ln.r and ("  " .. ln.r) or ""))
        elseif ln.l and Plain(ln.l) == "How" then
            on = true
            out[#out + 1] = Plain(ln.r)
        end
    end
    return out
end
local function SameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function List(t)
    local s = {}
    for i, v in ipairs(t) do s[i] = tostring(v) end
    return "{ " .. table.concat(s, " / ") .. " }"
end
local function Num(v, d)
    if d then return string.format("%." .. d .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

local Book = MD.Book
local function Fresh() return Book:Refresh() end

MD.player.isDruid = true
local book = Fresh()

--------------------------------------------------------------------------------
T.section("plumbing")
--------------------------------------------------------------------------------
local rejuv = SD.maxRank.Rejuvenation
local L = SetSpell(rejuv); show(L)
check("Rejuvenation gets the block: a spacer, SpellTuner, Rank N of M", L[1] ~= nil and Plain(L[1].l) == ""
    and (R(find(L, "SpellTuner")) or ""):find("^Rank %d+ of %d+") ~= nil, R(find(L, "SpellTuner")))
local before = #tt.lines
fire("OnTooltipSetSpell")
check("a second OnTooltipSetSpell adds nothing", before > 0 and #tt.lines == before, before .. " -> " .. #tt.lines)
check("re-setting after a clear adds it again", #SetSpell(rejuv) == before)
local bare
for _, id in ipairs({ rejuv, SD.maxRank.HealingTouch, SD.maxRank.Regrowth, SD.maxRank.Lifebloom,
                      SD.maxRank.Swiftmend }) do
    for _, key in ipairs({ false, true }) do
        S.shift = key
        for _, ln in ipairs(SetSpell(id)) do
            for _, str in ipairs({ ln.l or "", ln.r or "" }) do
                local good, why = T.Ascii(str)
                if not good then bare = bare or (id .. ": " .. why .. " in " .. str) end
            end
        end
    end
end
S.shift = false
check("ASCII only, no bare pipe, plain and detail", bare == nil, bare)
MD.db.spellTooltip = false
check("off means nothing is added", #SetSpell(rejuv) == 0)
MD.db.spellTooltip = true
check("a spell the book does not know adds nothing", #SetSpell(635) == 0)
-- T99: the gate is the class profile's `tooltip` capability
local druidProfile = MD.ClassProfile
MD.ClassProfile = MD.Profiles.generic
check("a class without the tooltip cap gets nothing", #SetSpell(rejuv) == 0)
MD.ClassProfile = druidProfile
local htID = SD.maxRank.HealingTouch
local pmLive = R(find(SetSpell(htID), "Per mana"))
MD.sim = { heal = 5000 }
local pmSim = R(find(SetSpell(htID), "Per mana"))
MD.sim = nil
check("the dashboard's what-if never reaches a tooltip", pmLive ~= nil and pmSim == pmLive,
    tostring(pmLive) .. " / " .. tostring(pmSim))
check("Tranquility has no value and no calc: no block", #SetSpell(SD.maxRank.Tranquility) == 0)

-- a builder that throws must not break the game's tooltip
local realLines = MD.SpellTip and MD.SpellTip.Lines
if MD.SpellTip then MD.SpellTip.Lines = function() error("boom") end end
local okCall, got = pcall(SetSpell, rejuv)
if MD.SpellTip then MD.SpellTip.Lines = realLines end
check("a failing builder never breaks the game's tooltip", MD.SpellTip ~= nil and okCall and #got == 0)

--------------------------------------------------------------------------------
T.section("1-3. Healing Touch R12")
--------------------------------------------------------------------------------
book = Fresh()
local e = book.spells[htID]
local ctx = RM:Context({ live = true })
local row = RM:RowFor(htID, ctx, nil, true)
L = SetSpell(htID); show(L)
check("1. Per mana / Per sec are the book's entry, which is RankMath's row",
    e ~= nil and R(find(L, "Per mana")) == Num(e.perMana, 2) and R(find(L, "Per sec")) == Num(e.perSec, 1)
    and e.perMana == row.hpm and e.perSec == row.hps,
    tostring(R(find(L, "Per mana"))) .. " / " .. tostring(R(find(L, "Per sec"))))
local pool = Book:DefaultPool()
local casts = e and RM:CastsToOOM(e.cost.amount, e.interval, pool.max, pool.regenCasting)
check("2. Casts to OOM N from full is RankMath:CastsToOOM from a full pool",
    type(casts) == "number" and R(find(L, "Casts to OOM")) == Num(casts) .. " from full",
    tostring(R(find(L, "Casts to OOM"))) .. " want " .. tostring(casts))
check("   the header says Rank 12 of 12 and the detail key", R(find(L, "SpellTuner")) == "Rank 12 of 12 Shift",
    R(find(L, "SpellTuner")))
check("   Suggested, then the facts; no HPM, Average, Downranked or overheal on the plain block",
    find(L, "Suggested") ~= nil and find(L, "HPM / HPS") == nil and find(L, "Average") == nil
    and find(L, "Heal") == nil and find(L, "Downranked") == nil and find(L, "After your overheal") == nil
    and find(L, "After overheal") == nil and find(L, "How") == nil)

-- the detail behind Shift, overheal seeded (bookshapecheck 17's seam)
local OH = MD.Overheal
local savedF, savedK = OH.Fraction, OH.KindFraction
OH.Fraction = function() return 0.25, 20, "rank" end
OH.KindFraction = function() return 0.25, 20, "kind" end
book = Fresh()
e = book.spells[htID]
S.shift = true
local LS = SetSpell(htID); show(LS)
S.shift = false
OH.Fraction, OH.KindFraction = savedF, savedK
local heals, crit, after, vs = find(LS, "Heals"), find(LS, "Crit"), find(LS, "After overheal"), find(LS, "vs Rank 11")
local critWant = Num(e.min * 1.5) .. " - " .. Num(e.max * 1.5) .. " " .. string.format("%d%%", e.crit * 100 + 0.5)
local GON = "then x 1.10 Gift of Nature"
local HOW_HT = { "2582 base + 540", "450 healing x 1.000 coef x 1.20 Emp. Touch", GON }
local cmp = Book:Compare(e, book.spells[SD.all.HealingTouch[11]])
check("3. detail: Heals, Crit ... 15%, After overheal (measured), vs Rank 11",
    R(heals) == Num(e.min) .. " - " .. Num(e.max) and R(crit) == critWant
    and e.afterOverheal ~= nil and R(after) == Num(e.afterOverheal.value) .. " 25% measured"
    and vs ~= nil and R(vs) == (MD.Words.Signed(cmp.perMana) .. " per mana, " .. MD.Words.Signed(cmp.perSec) .. " per sec"),
    List({ R(heals), tostring(R(crit)) .. " want " .. critWant, R(after), R(vs) }))
check("3. the How lines are Tip:Spell's Shift lines (golden, d6691fe)", SameList(HowLines(LS), HOW_HT),
    List(HowLines(LS)))
S.shift = true
local downL = SetSpell(SD.all.HealingTouch[7])
local rgL = SetSpell(SD.maxRank.Regrowth)
local lbL = SetSpell(SD.maxRank.Lifebloom)
S.shift = false
check("3. a downranked rank's How lines (golden)", SameList(HowLines(downL),
    { "1029 base + 413", "450 healing x 1.000 coef x 0.77 downrank x 1.20 Emp. Touch", GON }), List(HowLines(downL)))
check("3. Regrowth's and Lifebloom's How lines (golden)",
    SameList(HowLines(rgL), { "direct 1061 base + 128", "450 healing x 0.285 coef", "HoT 1064 base + 379",
        "450 healing x 0.701 coef x 1.20 Emp. Rejuvenation", GON })
    and SameList(HowLines(lbL), { "HoT 273 base + 280", "450 healing x 0.519 coef x 1.20 Emp. Rejuvenation",
        "bloom 600 base + 185", "450 healing x 0.342 coef x 1.20 Emp. Rejuvenation", GON }),
    List(HowLines(rgL)) .. " " .. List(HowLines(lbL)))
book = Fresh()

--------------------------------------------------------------------------------
T.section("4. Swiftmend")
--------------------------------------------------------------------------------
L = SetSpell(SD.maxRank.Swiftmend); show(L)
local eats = {}
for _, ln in ipairs(L) do
    local p = Plain((ln.l or "") .. (ln.r and ("  " .. ln.r) or ""))
    if p:find("^Eats ") then eats[#eats + 1] = p end
end
check("4. Swiftmend: the header and its two Eats lines, Tip:Spell's (golden), on the plain block",
    find(L, "SpellTuner") ~= nil and SameList(eats, { "Eats Rejuvenation 1725 (12s of its ticks)",
        "Eats Regrowth 1360 (18s of its ticks)" }) and find(L, "Per mana") == nil, List(eats))

--------------------------------------------------------------------------------
T.section("5. damage")
--------------------------------------------------------------------------------
local DAMAGE = {
    { 9912,  "Wrath",        "Rank 8", 2000,  "Causes 278 to 312 Nature damage to the target." },
    { 26986, "Starfire",     "Rank 8", 3500,  "Causes 540 to 636 Arcane damage to the target." },
    { 26988, "Moonfire",     "Rank 12", 0,    "Burns the enemy for 305 to 357 Arcane damage and then an additional " ..
                                              "600 Arcane damage over 12 sec." },
    { 27013, "Insect Swarm", "Rank 6", 0,     "The enemy target is swarmed by insects, decreasing their chance to hit " ..
                                              "by 2% and causing 792 Nature damage over 12 sec." },
    { 27012, "Hurricane",    "Rank 4", 10000, "Creates a violent storm in the target area causing 206 Nature damage " ..
                                              "to enemies every 1 sec, and increasing the time between attacks of " ..
                                              "enemies by 25%. Lasts 10 sec. Druid must channel to maintain the spell." },
    { 133,   "Fireball",     "Rank 1", 3500,  "Hurls a fiery ball that causes 100 to 120 Fire damage." },
}
local BOOK_NAMES = { "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo",
    "GetSpellInfo", "GetSpellDescription", "GetSpellPowerCost", "GetSpellLevelLearned", "GetSpellBonusDamage" }
local saved = {}
for _, n in ipairs(BOOK_NAMES) do saved[n] = rawget(_G, n) end
local byId = {}
for _, d in ipairs(DAMAGE) do byId[d[1]] = d end
local function Forget()
    for _, n in ipairs(BOOK_NAMES) do if MD.API.Invalidate then MD.API.Invalidate(n) end end
    if MD.BookTBC and MD.BookTBC.Forget then MD.BookTBC.Forget() end
end
_G.GetNumSpellTabs = function() return 1 end
_G.GetSpellTabInfo = function(tab) if tab == 1 then return "Balance", "icon", 0, #DAMAGE end end
_G.GetSpellBookItemName = function(slot) local d = DAMAGE[slot]; if d then return d[2], d[3], d[1] end end
_G.GetSpellBookItemInfo = function(slot) local d = DAMAGE[slot]; if d then return "SPELL", d[1] end end
_G.GetSpellInfo = function(id)
    local d = byId[id]
    if d then return d[2], d[3], "icon", d[4], 0, 30, id end
    return saved.GetSpellInfo(id)
end
_G.GetSpellDescription = function(id) local d = byId[id]; return d and d[5] or "" end
_G.GetSpellPowerCost = function(id)
    if byId[id] then return { { type = 0, cost = 340 } } end
    return saved.GetSpellPowerCost(id)
end
_G.GetSpellLevelLearned = function(id)
    if byId[id] then return nil end
    return saved.GetSpellLevelLearned and saved.GetSpellLevelLearned(id)
end
_G.GetSpellBonusDamage = function() return 300 end
Forget()

local TL = MD.harnessTalents
local savedT = {}
for _, k in ipairs({ "Moonfury", "Vengeance", "Wrath of Cenarius", "Improved Moonfire", "Focused Starlight" }) do
    savedT[k] = TL[k]; TL[k] = 0
end
local DM = MD.DamageMath
local function Damage(id, detail)
    Fresh()
    S.shift = detail or false
    local x = SetSpell(id)
    S.shift = false
    return x
end
local VERIFY = { "VERIFY: coefficients, tick periods and Balance talents are the",
                 "standard TBC rules, not yet checked against a hit on this client" }
local NOLEVEL = "the client does not say this rank's level: no downrank penalty applied"

L = Damage(9912, true); show(L)
local wc = DM.Compute(9912, "Wrath", DM.Parse("Wrath", byId[9912][5]))
check("5. Wrath: Per mana / Per sec are DM.Compute's dpm / dps",
    R(find(L, "Per mana")) == Num(wc.dpm, 2) and R(find(L, "Per sec")) == Num(wc.dps, 1) and Num(wc.dpm, 2) == "1.47",
    tostring(R(find(L, "Per mana"))) .. " / " .. tostring(R(find(L, "Per sec"))))
check("5. Wrath: Hits 449 - 483, Crit 674 - 725 15% (base + 300 x 2/3.5)",
    R(find(L, "Hits")) == "449 - 483" and R(find(L, "Crit")) == "674 - 725 15%",
    tostring(R(find(L, "Hits"))) .. " / " .. tostring(R(find(L, "Crit"))))
check("5. Wrath: the How lines are Tip:Damage's (golden)", SameList(HowLines(L), { "base damage: read from this tooltip",
    "hit +171 = 300 spell damage x 0.571 coef", NOLEVEL, VERIFY[1], VERIFY[2] }), List(HowLines(L)))
L = Damage(9912, false)
check("5. Wrath's plain block: no How, no Hits; the detail key's hint", #L > 0 and find(L, "How") == nil
    and find(L, "Hits") == nil and (R(find(L, "SpellTuner")) or ""):find("Shift$") ~= nil, R(find(L, "SpellTuner")))

L = Damage(26988, true); show(L)
check("5. Moonfire: Hits 351 - 403, Over time 755 over 12 s; How (golden)",
    R(find(L, "Hits")) == "351 - 403" and R(find(L, "Over time")) == "755 over 12 s"
    and SameList(HowLines(L), { "base damage: read from this tooltip", "hit +46 = 300 spell damage x 0.152 coef",
        "DoT +155 = 300 spell damage x 0.516 coef", NOLEVEL, VERIFY[1], VERIFY[2] }),
    tostring(R(find(L, "Hits"))) .. " / " .. tostring(R(find(L, "Over time"))) .. " " .. List(HowLines(L)))
L = Damage(27012, true); show(L)
check("5. Hurricane: How names the halved channel coefficient (golden)",
    find(L, "Per sec") ~= nil
    and SameList(HowLines(L), { "base damage: read from this tooltip",
        "channel +429 = 300 spell damage x 1.429 coef (halved: it hits everything)", NOLEVEL, VERIFY[1], VERIFY[2] }),
    tostring(R(find(L, "Per sec"))) .. " " .. List(HowLines(L)))

TL["Moonfury"], TL["Vengeance"], TL["Wrath of Cenarius"] = 5, 5, 5
L = Damage(9912, true)
check("5. Wrath with Moonfury 5, Wrath of Cenarius 5, Vengeance 5: Hits 527 - 565, Crit 1055 - 1130 at x2.0",
    R(find(L, "Hits")) == "527 - 565" and R(find(L, "Crit")) == "1055 - 1130 15% (x2.0)",
    tostring(R(find(L, "Hits"))) .. " / " .. tostring(R(find(L, "Crit"))))
TL["Moonfury"], TL["Vengeance"], TL["Wrath of Cenarius"] = 0, 0, 0

-- T121: a spell outside the druid's damage families is an Other spell of the
-- walked book (Spells/Book_Model.lua): Forever's 5.4b block, the header and
-- casts to OOM, no hint (Tip:Damage added nothing)
L = Damage(133)
check("a costed spell outside the druid's damage families: the Other block (header, Casts to OOM)",
    #L == 3 and R(find(L, "SpellTuner")) == "Rank 1 of 1" and find(L, "Casts to OOM") ~= nil
    and find(L, "Per mana") == nil, #L .. " lines")
MD.db.spellTooltipDamage = false
check("the damage setting off adds nothing to a damage spell", #Damage(9912) == 0)
check("and leaves the heals alone", #SetSpell(rejuv) > 0)
MD.db.spellTooltipDamage = true
check("the damage setting on again: Wrath's block is back", #Damage(9912) > 0)

for k, v in pairs(savedT) do TL[k] = v end
for _, n in ipairs(BOOK_NAMES) do _G[n] = saved[n] end
Forget()
Fresh()

--------------------------------------------------------------------------------
T.section("6. the detail modes and the watcher")
--------------------------------------------------------------------------------
local function HasDetail() return find(SetSpell(htID), "How") ~= nil end
MD.db.spellTooltipDetail = "ALT"
S.shift = true
local altShift = HasDetail()
S.shift = false; S.altDown = true
local altAlt = HasDetail()
S.altDown = false
local altHint = R(find(SetSpell(htID), "SpellTuner"))
MD.db.spellTooltipDetail = "ALWAYS"
local always = HasDetail()
local alwaysHint = R(find(SetSpell(htID), "SpellTuner"))
MD.db.spellTooltipDetail = "NEVER"
S.shift = true
local never = HasDetail()
S.shift = false
MD.db.spellTooltipDetail = "SHIFT"
check("6. ALT: the detail with Alt only; ALWAYS always; NEVER never; the hint names the key",
    not altShift and altAlt and always and not never and altHint == "Rank 12 of 12 Alt"
    and alwaysHint == "Rank 12 of 12",
    List({ altShift, altAlt, always, never, altHint, alwaysHint }))

local entered = 0
owner = CreateFrame("Frame")
owner:SetScript("OnEnter", function() entered = entered + 1 end)
local function Press(key) entered = 0; S.Fire("MODIFIER_STATE_CHANGED", key, 1); return entered end
SetSpell(htID)
local shiftRuns, altIgnored = Press("LSHIFT"), Press("LALT")
MD.db.spellTooltipDetail = "ALT"
local altRuns, shiftIgnored = Press("RALT"), Press("RSHIFT")
MD.db.spellTooltipDetail = "CTRL"
local ctrlRuns = Press("LCTRL")
MD.db.spellTooltipDetail = "ALWAYS"
local alwaysIgnored = Press("LSHIFT")
MD.db.spellTooltipDetail = "SHIFT"
tt.lines = {}; fire("OnTooltipCleared")
local noBlock = Press("LSHIFT")
owner = nil
check("6. the watcher re-runs OnEnter for the mode's key only, and only over a block",
    shiftRuns == 1 and altIgnored == 0 and altRuns == 1 and shiftIgnored == 0 and ctrlRuns == 1
    and alwaysIgnored == 0 and noBlock == 0,
    List({ shiftRuns, altIgnored, altRuns, shiftIgnored, ctrlRuns, alwaysIgnored, noBlock }))
check("the old TBC builders are gone: no Tip:Spell, Tip:Damage, Tip:Columns, MD:SpellTooltipAppend",
    MD.Tip.Spell == nil and MD.Tip.Damage == nil and MD.Tip.Columns == nil and MD.SpellTooltipAppend == nil
    and type(MD.Tip.Row) == "function" and type(MD.Tip.Clock) == "function"
    and MD.SpellTip ~= nil and type(MD.SpellTip.OnSpell) == "function")

-- T76 (P32 of docs/PLAN-refactor-ux.md, review A21): on TBC the renderer is
-- UI/Tip.lua's; MD.Tip:Show (its old shape, every TBC caller's) still renders
-- into GameTooltip, the kit tooltip untouched. T80 (C1, decision 10): the TBC
-- TOC lists the theme, so that GameTooltip is drawn in the kit's flat skin.
do
    local o = CreateFrame("Frame")
    tt.lines = {}
    MD.UI.tooltip.lines = nil
    MD.Tip:Show(o, "ANCHOR_LEFT", { { l = "SpellTuner", c = { 1, 1, 1 } } }, { { l = "Left-click: dashboard" } })
    local got2 = #tt.lines == 2 and tt.lines[1].l == "SpellTuner" and tt.lines[2].l == "Left-click: dashboard"
    check("T76/T80: TBC's Tip:Show is GameTooltip, in the kit's skin",
        type(MD.Tip.Skinned) == "function" and got2 and MD.Tip:Skinned(tt) and MD.UI.tooltip.lines == nil
        and MD.UI.THEMED == true, string.format("lines=%d", #tt.lines))
    MD.Tip:Hide()
end

--------------------------------------------------------------------------------
T.section("7. a priest with the cap granted")
--------------------------------------------------------------------------------
do
    TBCCLASS_LIBRARY = true
    local lib = dofile(here .. "/tbcclasscheck.lua")
    local savedLevel, savedClass = S.level, S.units.player.class
    S.level = 70
    local _, restore = lib.Install(S, MD, "PRIEST")
    local caps = MD.Profiles.byClass.PRIEST and MD.Profiles.byClass.PRIEST.caps
    local savedCaps = caps and { rankTable = caps.rankTable, tooltip = caps.tooltip }
    local good, why = pcall(function()
        caps.rankTable, caps.tooltip = true, true
        S.units.player.class = "PRIEST"
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        MD.BookTBC:Rebuild()
        local b = Fresh()
        local ge = b.spells[25213]
        local lines = SetSpell(25213)
        show(lines)
        return ge ~= nil and ge.family == "GreaterHeal"
            and R(find(lines, "Per mana")) == Num(ge.perMana, 2)
            and (R(find(lines, "SpellTuner")) or ""):find("^Rank 7 of %d+") ~= nil
            and find(lines, "Casts to OOM") ~= nil,
            ge and R(find(lines, "SpellTuner")) or "no Greater Heal 7 in the book"
    end)
    restore()
    if caps then caps.rankTable, caps.tooltip = savedCaps.rankTable, savedCaps.tooltip end
    S.level, S.units.player.class = savedLevel, savedClass
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
    if MD.BookTBC and MD.BookTBC.Rebuild then pcall(MD.BookTBC.Rebuild, MD.BookTBC) end
    pcall(Fresh)
    check("7. a priest's Greater Heal 7: the block from the class book (its family, per mana, Rank N of M)",
        good and why == true, tostring(why) .. (good and "" or " (raised)"))
end

T.done()
