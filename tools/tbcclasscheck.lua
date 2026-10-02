-- tools/run.sh --flavour tbc tools/tbcclasscheck.lua
--
-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): a TBC priest, shaman or
-- paladin on the TBC rank table and spell tooltip. Held here:
--
--   * the client's own tooltip texts (the fixture below) become each rank's
--     base heal through Spells/Book_TBC.lua and Spells/Parse.lua -- the
--     spellbook walked through MD.API, each read falling back to the scan
--     tooltip's lines, a rank no read can price refused with its reason;
--   * Engine/RankMath.lua puts the TBC rules on top (coefficient by shape and
--     the BASE cast, the downrank penalty, the class talents of
--     RankMath.CLASS_RULES) and the numbers are the rule's, restated here;
--   * Compute, Explain, SuggestedRanks and Spells/Families_TBC.lua's book
--     read the class's source, and the kit RankMath:SpellKit builds passes
--     Engine/Kit.lua's Kit.Check, stamped with the class's profile;
--   * the druid is untouched (Data/SpellData.lua stays his source) and a mage
--     (no profile on this line) gets nothing.
--
-- The fixture is the TBC client's English tooltip text of every rank
-- (wowhead's TBC Classic tooltips, level 70: name, rank, cost, cast, required
-- level, description), typed from those pages. It is also a library:
-- `TBCCLASS_LIBRARY = true; local lib = dofile("tools/tbcclasscheck.lua")`
-- returns { FIXTURE, Install } without running a check (tools/wclcheckkit.lua
-- builds a priest's or shaman's kit from it for --fit).
HARNESS_FLAVOUR = "tbc"

--------------------------------------------------------------------------------
-- The fixture: per class, per family, the template of the description and
-- one row per rank { id, rank, cost, cast (s), level, a, b } -- a to b the
-- heal range (a alone: a HoT's total). Holy Shock carries its damage half too.
--------------------------------------------------------------------------------
local FIXTURE = {
    PRIEST = {
        { name = "Lesser Heal", text = "Heal your target for %d to %d.", ranks = {
            { 2050, 1, 30, 1.5, 1, 47, 58 }, { 2052, 2, 45, 2, 4, 76, 91 }, { 2053, 3, 75, 2.5, 10, 143, 165 } } },
        { name = "Heal", text = "Heal your target for %d to %d.", ranks = {
            { 2054, 1, 155, 3, 16, 307, 353 }, { 2055, 2, 205, 3, 22, 445, 507 },
            { 6063, 3, 255, 3, 28, 586, 662 }, { 6064, 4, 305, 3, 34, 734, 827 } } },
        { name = "Greater Heal", text = "A slow casting spell that heals a single target for %d to %d.", ranks = {
            { 2060, 1, 370, 3, 40, 924, 1039 }, { 10963, 2, 455, 3, 46, 1178, 1318 },
            { 10964, 3, 545, 3, 52, 1470, 1642 }, { 10965, 4, 655, 3, 58, 1835, 2044 },
            { 25314, 5, 710, 3, 60, 2006, 2235 }, { 25210, 6, 750, 3, 63, 2107, 2444 },
            { 25213, 7, 825, 3, 68, 2414, 2803 } } },
        { name = "Flash Heal", text = "Heals a friendly target for %d to %d.", ranks = {
            { 2061, 1, 125, 1.5, 20, 202, 247 }, { 9472, 2, 155, 1.5, 26, 269, 325 },
            { 9473, 3, 185, 1.5, 32, 339, 406 }, { 9474, 4, 215, 1.5, 38, 414, 492 },
            { 10915, 5, 265, 1.5, 44, 534, 633 }, { 10916, 6, 315, 1.5, 50, 662, 783 },
            { 10917, 7, 380, 1.5, 56, 833, 979 }, { 25233, 8, 400, 1.5, 61, 931, 1078 },
            { 25235, 9, 470, 1.5, 67, 1116, 1295 } } },
        { name = "Renew", text = "Heals the target for %d over 15 sec.", ranks = {
            { 139, 1, 30, 0, 8, 45 }, { 6074, 2, 65, 0, 14, 100 }, { 6075, 3, 105, 0, 20, 175 },
            { 6076, 4, 140, 0, 26, 245 }, { 6077, 5, 170, 0, 32, 315 }, { 6078, 6, 205, 0, 38, 400 },
            { 10927, 7, 250, 0, 44, 510 }, { 10928, 8, 305, 0, 50, 650 }, { 10929, 9, 365, 0, 56, 810 },
            { 25315, 10, 410, 0, 60, 970 }, { 25221, 11, 430, 0, 65, 1010 }, { 25222, 12, 450, 0, 70, 1110 } } },
        { name = "Prayer of Healing", text = "A powerful prayer heals party members within 30 yards for %d to %d.", ranks = {
            { 596, 1, 410, 3, 30, 312, 333 }, { 996, 2, 560, 3, 40, 458, 487 },
            { 10960, 3, 770, 3, 50, 675, 713 }, { 10961, 4, 1030, 3, 60, 960, 1013 },
            { 25316, 5, 1070, 3, 60, 1019, 1076 }, { 25308, 6, 1255, 3, 68, 1251, 1322 } } },
        { name = "Circle of Healing",
          text = "Heals friendly target and that target's party members within 15 yards of the target for %d to %d.", ranks = {
            { 34861, 1, 300, 0, 50, 250, 274 }, { 34863, 2, 337, 0, 56, 292, 323 },
            { 34864, 3, 375, 0, 60, 332, 367 }, { 34865, 4, 412, 0, 65, 376, 415 },
            { 34866, 5, 450, 0, 70, 409, 451 } } },
        { name = "Binding Heal", text = "Heals a friendly target and the caster for %d to %d.  Low threat.", ranks = {
            { 32546, 1, 705, 1.5, 64, 1053, 1350 } } },
    },
    SHAMAN = {
        { name = "Healing Wave", text = "Heals a friendly target for %d to %d.", ranks = {
            { 331, 1, 25, 1.5, 1, 36, 47 }, { 332, 2, 45, 2, 6, 69, 83 }, { 547, 3, 80, 2.5, 12, 136, 163 },
            { 913, 4, 155, 3, 18, 279, 328 }, { 939, 5, 200, 3, 24, 389, 454 }, { 959, 6, 265, 3, 32, 552, 639 },
            { 8005, 7, 340, 3, 40, 759, 874 }, { 10395, 8, 440, 3, 48, 1040, 1191 },
            { 10396, 9, 560, 3, 56, 1394, 1589 }, { 25357, 10, 620, 3, 60, 1647, 1878 },
            { 25391, 11, 655, 3, 63, 1756, 2001 }, { 25396, 12, 720, 3, 70, 2134, 2436 } } },
        { name = "Lesser Healing Wave", text = "Heals a friendly target for %d to %d.", ranks = {
            { 8004, 1, 105, 1.5, 20, 170, 195 }, { 8008, 2, 145, 1.5, 28, 257, 292 },
            { 8010, 3, 185, 1.5, 36, 349, 394 }, { 10466, 4, 235, 1.5, 44, 473, 529 },
            { 10467, 5, 305, 1.5, 52, 649, 723 }, { 10468, 6, 380, 1.5, 60, 853, 949 },
            { 25420, 7, 440, 1.5, 66, 1051, 1198 } } },
        { name = "Chain Heal",
          text = "Heals the friendly target for %d to %d, then jumps to heal additional nearby targets.  "
              .. "If cast on a party member, the heal will only jump to other party members.  "
              .. "Each jump reduces the effectiveness of the heal by 50%%.  Heals 3 total targets.", ranks = {
            { 1064, 1, 260, 2.5, 40, 332, 381 }, { 10622, 2, 315, 2.5, 46, 419, 479 },
            { 10623, 3, 405, 2.5, 54, 567, 646 }, { 25422, 4, 435, 2.5, 61, 624, 710 },
            { 25423, 5, 540, 2.5, 68, 833, 950 } } },
    },
    PALADIN = {
        { name = "Holy Light", text = "Heals a friendly target for %d to %d.", ranks = {
            { 635, 1, 35, 2.5, 1, 42, 51 }, { 639, 2, 60, 2.5, 6, 81, 96 }, { 647, 3, 110, 2.5, 14, 167, 196 },
            { 1026, 4, 190, 2.5, 22, 322, 368 }, { 1042, 5, 275, 2.5, 30, 506, 569 },
            { 3472, 6, 365, 2.5, 38, 717, 799 }, { 10328, 7, 465, 2.5, 46, 968, 1076 },
            { 10329, 8, 580, 2.5, 54, 1272, 1414 }, { 25292, 9, 660, 2.5, 60, 1619, 1799 },
            { 27135, 10, 710, 2.5, 62, 1773, 1971 }, { 27136, 11, 840, 2.5, 70, 2196, 2446 } } },
        { name = "Flash of Light", text = "Heals a friendly target for %d to %d.", ranks = {
            { 19750, 1, 35, 1.5, 20, 67, 77 }, { 19939, 2, 50, 1.5, 26, 102, 117 },
            { 19940, 3, 70, 1.5, 34, 153, 171 }, { 19941, 4, 90, 1.5, 42, 206, 231 },
            { 19942, 5, 115, 1.5, 50, 278, 310 }, { 19943, 6, 140, 1.5, 58, 356, 396 },
            { 27137, 7, 180, 1.5, 66, 458, 513 } } },
        -- the rank whose whole text the fixture has (its damage half included)
        { name = "Holy Shock", cooldown = 15,
          text = "Blasts the target with Holy energy, causing 721 to 779 Holy damage to an enemy, "
              .. "or %d to %d healing to an ally.", ranks = {
            { 33072, 5, 650, 0, 70, 913, 987 } } },
    },
}

-- The fixture's description of one rank.
local function TextOf(fam, r)
    if r[7] then return string.format(fam.text, r[6], r[7]) end
    return string.format(fam.text, r[6])
end

--------------------------------------------------------------------------------
-- Install(S, MD, class, opts): the class's spellbook in the stub's client.
--   opts.api = false   GetSpellDescription, GetSpellPowerCost (for these
--                      ids), GetSpellLevelLearned, GetSpellBaseCooldown and
--                      GetSpellInfo's cast answer nothing: every read takes
--                      the scan tooltip's lines
--   opts.castTaken     family name -> seconds the client's cast is shorter
--                      (a talent the client applies: Divine Fury)
--   opts.extra         more { id, name, rank, cost, cast, level, text } rows
-- Returns the id -> row index of what it installed.
--------------------------------------------------------------------------------
local CLIENT_NAMES = { "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo",
    "GetSpellInfo", "GetSpellDescription", "GetSpellPowerCost", "GetSpellLevelLearned",
    "GetSpellBaseCooldown" }

local function Install(S, MD, class, opts)
    opts = opts or {}
    local api = opts.api ~= false
    local rows, order = {}, {}
    for _, fam in ipairs(FIXTURE[class] or {}) do
        for _, r in ipairs(fam.ranks) do
            if (r[5] or 1) <= S.level then
                local cast = r[4] - ((opts.castTaken and opts.castTaken[fam.name]) or 0)
                rows[r[1]] = { id = r[1], name = fam.name, rank = r[2], cost = r[3], cast = cast,
                               level = r[5], text = TextOf(fam, r), cooldown = fam.cooldown }
                order[#order + 1] = r[1]
            end
        end
    end
    for _, x in ipairs(opts.extra or {}) do
        rows[x.id] = x
        order[#order + 1] = x.id
    end
    local saved = {}
    for _, n in ipairs(CLIENT_NAMES) do saved[n] = rawget(_G, n) end
    local prevInfo, prevCost = saved.GetSpellInfo, saved.GetSpellPowerCost

    _G.GetNumSpellTabs = function() return 2 end
    _G.GetSpellTabInfo = function(tab)
        if tab == 1 then return "General", "Interface\\Icons\\General", 0, 2 end
        if tab == 2 then return "Holy", "Interface\\Icons\\Holy", 2, #order end
        return nil
    end
    -- slots 1-2 are General's (not heals); then one slot per rank
    _G.GetSpellBookItemName = function(slot)
        if slot == 1 then return "Attack", nil, 6603 end
        if slot == 2 then return "Find Herbs", nil, 2383 end
        local id = order[slot - 2]
        local x = id and rows[id]
        if not x then return nil end
        return x.name, "Rank " .. x.rank, id
    end
    _G.GetSpellBookItemInfo = function(slot)
        local id = order[slot - 2]
        if id then return "SPELL", id end
        return nil
    end
    _G.GetSpellInfo = function(id)
        local x = rows[id]
        if x then
            return x.name, "Rank " .. x.rank, "Interface\\Icons\\Spell_" .. id, api and math.floor(x.cast * 1000 + 0.5) or nil,
                0, 40, id
        end
        return prevInfo(id)
    end
    _G.GetSpellDescription = api and function(id) return rows[id] and rows[id].text or "" end or nil
    _G.GetSpellPowerCost = function(id)
        local x = rows[id]
        if x then
            if not api then return nil end
            return { { type = 0, cost = x.cost, name = "MANA" } }
        end
        return prevCost(id)
    end
    _G.GetSpellLevelLearned = api and function(id) return rows[id] and rows[id].level or 0 end or nil
    _G.GetSpellBaseCooldown = api and function(id)
        local x = rows[id]
        return (x and x.cooldown or 0) * 1000, 1500
    end or nil

    -- the scan tooltip: the lines a TBC spell tooltip draws
    local SCAN = "SpellTunerScanTooltip"
    local tip = { n = 0 }
    function tip:SetOwner() end
    function tip:Hide() end
    function tip:ClearLines()
        for i = 1, self.n do _G[SCAN .. "TextLeft" .. i] = nil; _G[SCAN .. "TextRight" .. i] = nil end
        self.n = 0
    end
    local function Region(text) return { GetText = function() return text end } end
    function tip:SetSpellByID(id)
        local x = rows[id]
        if not x then return end
        local lines = {
            { x.name, "Rank " .. x.rank },
            { x.cost .. " Mana", "40 yd range" },
            { x.cast > 0 and (x.cast .. " sec cast") or "Instant", x.cooldown and (x.cooldown .. " sec cooldown") or nil },
            { x.text },
        }
        for i, ln in ipairs(lines) do
            _G[SCAN .. "TextLeft" .. i] = Region(ln[1])
            _G[SCAN .. "TextRight" .. i] = ln[2] and Region(ln[2]) or nil
        end
        self.n = #lines
    end
    function tip:NumLines() return self.n end
    _G[SCAN] = tip

    if MD and MD.API and MD.API.Invalidate then
        for _, n in ipairs(CLIENT_NAMES) do MD.API.Invalidate(n) end
    end
    local function Restore()
        for _, n in ipairs(CLIENT_NAMES) do _G[n] = saved[n] end
        _G[SCAN] = nil
        if MD and MD.API and MD.API.Invalidate then
            for _, n in ipairs(CLIENT_NAMES) do MD.API.Invalidate(n) end
        end
    end
    return rows, Restore
end

if TBCCLASS_LIBRARY then
    TBCCLASS_LIBRARY = nil
    return { FIXTURE = FIXTURE, Install = Install, TextOf = TextOf }
end

--------------------------------------------------------------------------------
-- The suite.
--------------------------------------------------------------------------------
local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
local function check(name, cond, detail)
    if cond or detail == "" then detail = nil end
    return T.check(name, cond, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB

local function Near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end
local function Show(v)
    if type(v) ~= "table" then return tostring(v) end
    local o = {}
    for k, x in pairs(v) do o[#o + 1] = tostring(k) .. "=" .. Show(x) end
    table.sort(o)
    return "{" .. table.concat(o, ",") .. "}"
end

--------------------------------------------------------------------------------
-- 0. The files (the TOC lines are the integrator's: loaded here until then)
--------------------------------------------------------------------------------
T.section("the files")
local function LoadIf(cond, files)
    if cond then return true end
    local ok, err = pcall(S.Load, files, "SpellTuner", MD)
    return ok, err
end
local okProf, errProf = LoadIf(MD.Profiles.byClass.PRIEST ~= nil,
    { "Data/Profile_Priest_TBC.lua", "Data/Profile_Shaman_TBC.lua", "Data/Profile_Paladin_TBC.lua" })
check("the three TBC class profiles load", okProf and MD.Profiles.byClass.PRIEST ~= nil
    and MD.Profiles.byClass.SHAMAN ~= nil and MD.Profiles.byClass.PALADIN ~= nil, tostring(errProf))
local okParse, errParse = LoadIf(MD.Parse ~= nil, { "Spells/Parse.lua" })
local okBook, errBook = LoadIf(MD.BookTBC ~= nil, { "Spells/Book_TBC.lua" })
check("Spells/Parse.lua and Spells/Book_TBC.lua load on the TBC line",
    okParse and okBook and MD.Parse ~= nil and MD.BookTBC ~= nil, tostring(errParse) .. " " .. tostring(errBook))
local B, RM, Kit = MD.BookTBC or {}, MD.RankMath, MD.Kit
-- the parent has no RankMath:Source (the suite then fails, it does not stop)
local function Src() if type(RM.Source) == "function" then return RM:Source() end return nil end
check("RankMath has the class path (Source, CLASS_RULES, ClassRow, ClassKit)",
    type(RM.Source) == "function" and type(RM.CLASS_RULES) == "table" and type(RM.ClassRow) == "function"
    and type(RM.ClassKit) == "function")

-- the druid's numbers before any class logs in (section 6 compares)
local druidBefore = {}
do
    local res = RM:Compute()
    for fam, r in pairs(res) do druidBefore[fam] = { n = #r.rows, s = r.suggestedID, h = r.rows[1] and r.rows[1].heal } end
end

local function LogIn(class, level)
    S.level = level or 70
    S.units.player.class = class
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
end
local function Rebuild() return type(B.Rebuild) == "function" and B:Rebuild() or nil end

--------------------------------------------------------------------------------
-- 1. The adapter's scan tooltip
--------------------------------------------------------------------------------
T.section("the scan tooltip")
S.level = 70 -- every rank of the fixture (Install lists those at or below it)
local rowsP, restoreP = Install(S, MD, "PRIEST", { castTaken = { Heal = 0.5, ["Greater Heal"] = 0.5 } })
do
    local lines, why = (MD.API.SpellTooltipLines or function() return nil, "unbound" end)(25213)
    check("MD.API.SpellTooltipLines reads the scan tooltip line by line",
        type(lines) == "table" and #lines == 4 and lines[1].l == "Greater Heal" and lines[1].r == "Rank 7"
        and lines[2].l == "825 Mana" and lines[4].l == rowsP[25213].text,
        Show(lines) .. " " .. tostring(why))
    local none, nwhy = (MD.API.SpellTooltipLines or function() return nil, "x" end)("x")
    check("SpellTooltipLines answers nil, absent for a non-number", none == nil and nwhy == "absent", tostring(nwhy))
end

--------------------------------------------------------------------------------
-- 2. A priest: the texts become bases
--------------------------------------------------------------------------------
T.section("a priest's book")
local PRIEST_TALENTS = { ["Spiritual Healing"] = 5, ["Empowered Healing"] = 5, ["Divine Fury"] = 5,
                         ["Improved Renew"] = 3 }
MD:SetTalents(PRIEST_TALENTS)
local rebuilt = 0
MD:RegisterCallback("SPELLS_REBUILT", function() rebuilt = rebuilt + 1 end)
LogIn("PRIEST", 70)
local before = rebuilt
local src = Rebuild()
check("the priest's profile is selected and grants the rank table, not the coach",
    MD.ClassProfile == MD.Profiles.byClass.PRIEST and MD.ClassProfile:Can("rankTable")
    and MD.ClassProfile:Can("tooltip") and not MD.ClassProfile:Can("coach"))
check("a rebuild fires SPELLS_REBUILT", rebuilt == before + 1, rebuilt .. " vs " .. before)
local nP = 0
for _ in pairs(rowsP) do nP = nP + 1 end
local nSrc = 0
for _ in pairs(src and src.spells or {}) do nSrc = nSrc + 1 end
check("every rank the spellbook lists is read, none refused", src ~= nil and nSrc == nP and next(src.refused) == nil,
    nSrc .. " of " .. nP .. " " .. Show(src and src.refused))
check("RankMath:Source() is the class's book", Src() == src)
check("the families in the profile's order",
    src and table.concat(src.familyOrder, " ") ==
        "GreaterHeal Heal FlashHeal LesserHeal Renew PrayerOfHealing CircleOfHealing BindingHeal",
    src and table.concat(src.familyOrder, " "))
do
    local gh = src and src.spells[25213] or {}
    check("Greater Heal 7: the text's 2414 to 2803, 825 mana, the client's 2.5 s, level 68, rank 7",
        gh.healMin == 2414 and gh.healMax == 2803 and gh.cost == 825 and gh.cast == 2.5 and gh.level == 68
        and gh.rank == 7 and gh.family == "GreaterHeal", Show(gh))
    local rn = src and src.spells[25222] or {}
    check("Renew 12: 1110 over 15 s", rn.hotTotal == 1110 and rn.hotDuration == 15 and rn.cast == 0, Show(rn))
    local coh = src and src.spells[34866] or {}
    check("Circle of Healing reaches the target's party (the TBC sentence)",
        coh.reach and coh.reach.targets == "party" and coh.reach.from == "target" and coh.reach.range == 15,
        Show(coh.reach))
    local poh = src and src.spells[25308] or {}
    check("Prayer of Healing reaches the caster's party within 30 yd",
        poh.reach and poh.reach.targets == "party" and poh.reach.from == "caster" and poh.reach.range == 30,
        Show(poh.reach))
    check("the known set and the highest rank per family",
        src and src.knownSet[25213] and src.maxRank.GreaterHeal == 25213 and src.maxRank.Renew == 25222
        and #src.all.GreaterHeal == 7 and src.all.GreaterHeal[1] == 2060)
end

--------------------------------------------------------------------------------
-- 3. The rules on top (restated: the coefficient of the BASE cast, the
--    downrank penalty, the talents)
--------------------------------------------------------------------------------
T.section("the rules")
local BONUS, CRIT = 450, 0.15 -- the stub's GetSpellBonusHealing / GetSpellCritChance
local ctx = RM:Context({ live = true })
check("the class context: +healing, the Holy school's crit, no Nature's Grace",
    ctx.class == "PRIEST" and ctx.bonus == BONUS and Near(ctx.crit, CRIT) and ctx.naturesGrace == 0
    and ctx.treeAura == 0 and ctx.ExpectedCast(2.5, 0.2) == 2.5, Show({ ctx.class, ctx.bonus, ctx.crit }))
do
    -- Greater Heal 7: cast 2.5 + Divine Fury's 0.5 back = 3.0 -> 3/3.5;
    -- Empowered Healing +0.20; Spiritual Healing x1.10; level 68 at 70: no
    -- penalty; crit 15% x 0.5
    local row = RM:Explain(25213, nil, { live = true })
    local c = row and row.calc or {}
    local coef = 3 / 3.5
    local want = ((2414 + 2803) / 2 + BONUS * (coef + 0.20)) * 1.10 * (1 + 0.5 * CRIT)
    check("Greater Heal 7's value is the rule's (base cast 3.0, +0.20 Empowered Healing, x1.10)",
        Near(row and row.heal, want, 1e-6) and Near(c.coef, coef) and Near(c.penalty, 1) and Near(c.talentMult, 1.10)
        and row.cast == 2.5 and row.cost == 825 and Near(row.hpm, want / 825),
        string.format("%s vs %.3f coef %s", tostring(row and row.heal), want, tostring(c.coef)))
    check("the row carries every field the TBC tooltip's Row reads",
        c.kind == "direct" and c.label == "Greater Heal" and c.base and c.bonus and c.bonusOut and c.critMult
        and c.costSource and c.castBase == 2.5 and c.castNG == 2.5 and c.netPerCast and c.mana
        and c.bonusMultName == "Empowered Healing" and c.min and c.max, Show(c))
    -- Heal 1: level 16 at 70 -> (16 + 11) / 70 x the sub-20 malus (1 - 4 x 0.0375)
    local h1 = RM:Explain(2054, nil, { live = true })
    local pen = (27 / 70) * (1 - 4 * 0.0375)
    check("a low rank takes the downrank and sub-20 penalties on its bonus",
        h1 and Near(h1.calc.penalty, pen) and Near(h1.heal,
            ((307 + 353) / 2 + BONUS * (3 / 3.5) * pen) * 1.10 * (1 + 0.5 * CRIT)),
        h1 and tostring(h1.calc.penalty))
    -- Renew 12: 15/15, x1.10 x1.15 (Improved Renew 3), five 3 s ticks
    local rn = RM:Explain(25222, nil, { live = true })
    check("Renew 12: coefficient 1.0, Spiritual Healing x Improved Renew, five ticks of 3 s",
        rn and Near(rn.heal, (1110 + BONUS) * 1.10 * 1.15) and rn.calc.kind == "hot" and rn.calc.ticks == 5
        and rn.calc.tickPeriod == 3 and rn.cast == 1.5,
        rn and string.format("%.2f ticks %s", rn.heal, tostring(rn.calc.ticks)))
    -- Prayer of Healing 6: a group heal, half the single-target coefficient
    local ph = RM:Explain(25308, nil, { live = true })
    check("Prayer of Healing: one target's value, half of 3/3.5 (RankMath.GROUP_COEF)",
        ph and Near(ph.calc.coef, 3 / 3.5 * 0.5) and Near(ph.heal,
            ((1251 + 1322) / 2 + BONUS * 3 / 3.5 * 0.5) * 1.10 * (1 + 0.5 * CRIT)),
        ph and tostring(ph.calc.coef))
    -- Binding Heal: 1.5/3.5 + 0.10 Empowered Healing
    local bh = RM:Explain(32546, nil, { live = true })
    check("Binding Heal: 1.5/3.5 + 0.10 Empowered Healing, the target's value",
        bh and Near(bh.heal, ((1053 + 1350) / 2 + BONUS * (1.5 / 3.5 + 0.10)) * 1.10 * (1 + 0.5 * CRIT)),
        bh and tostring(bh.heal))
end

--------------------------------------------------------------------------------
-- 4. The rank table, the tooltip's source and the kit
--------------------------------------------------------------------------------
T.section("the table and the kit")
do
    local res = RM:Compute()
    local fams = {}
    for k in pairs(res) do fams[#fams + 1] = k end
    table.sort(fams)
    local gh = res.GreaterHeal
    local sugg
    for _, r in ipairs(gh and gh.rows or {}) do if r.suggested then sugg = r end end
    check("Compute lists the priest's eight families with rows and a suggested rank",
        #fams == 8 and gh and #gh.rows == 7 and gh.suggestedID ~= nil and sugg ~= nil and gh.label == "Greater Heal",
        table.concat(fams, " "))
    local ranks = RM:SuggestedRanks()
    check("SuggestedRanks reads the class's ranks", ranks.GreaterHeal == (sugg and sugg.rank),
        Show(ranks))
    local book = MD.FamiliesTBC and MD.FamiliesTBC:Build() or { order = {} }
    check("the spell list's book (Spells/Families_TBC.lua) is the priest's",
        table.concat(book.order, " ") == "GreaterHeal Heal FlashHeal LesserHeal Renew PrayerOfHealing CircleOfHealing BindingHeal"
        and book.families.Renew and book.families.Renew.maxKnown and book.families.Renew.maxKnown.id == 25222,
        table.concat(book.order, " "))

    local okKit, kit = pcall(function() return RM:SpellKit({ live = true }) end)
    local valid, problems = false, nil
    if okKit and Kit then valid, problems = Kit.Validate(kit) end
    check("the priest's kit passes Kit.Check, stamped PRIEST", okKit and valid and kit.profile == "PRIEST",
        okKit and Show(problems) or tostring(kit))
    local c = okKit and kit.caster or {}
    local ghE, rnE, phE, bhE = c[25213] or {}, c[25222] or {}, c[25308] or {}, c[32546] or {}
    check("its entries by kit type: direct, hot (5 x 3 s), group with a direct part, selfAndTarget",
        ghE.type == "direct" and ghE.castBase == 2.5 and Near(ghE.directCrit, CRIT)
        and rnE.type == "hot" and rnE.ticks == 5 and rnE.tickPeriod == 3 and rnE.duration == 15
        and Near(rnE.tick * 5, (1110 + BONUS) * 1.10 * 1.15)
        and phE.type == "group" and phE.direct ~= nil and bhE.type == "selfAndTarget",
        Show({ ghE.type, rnE.type, rnE.ticks, phE.type, bhE.type }))
end

--------------------------------------------------------------------------------
-- 5. A refusal: a text no shape reads is not on the table
--------------------------------------------------------------------------------
T.section("a refusal")
restoreP()
local _, restoreR = Install(S, MD, "PRIEST", { extra = {
    { id = 900001, name = "Flash Heal", rank = 10, cost = 500, cast = 1.5, level = 70,
      text = "Heals a friendly target." } } })
local srcR = Rebuild()
check("a rank whose text has no heal range is refused with its reason, not guessed",
    srcR and srcR.refused[900001] == "Flash Heal: no heal range in its text" and srcR.spells[900001] == nil,
    Show(srcR and srcR.refused))
restoreR()

--------------------------------------------------------------------------------
-- 6. A shaman read from the tooltip alone; a paladin's Holy Shock
--------------------------------------------------------------------------------
T.section("a shaman and a paladin")
MD:SetTalents({ ["Purification"] = 5, ["Improved Chain Heal"] = 2 })
local _, restoreS = Install(S, MD, "SHAMAN", { api = false })
LogIn("SHAMAN", 70)
local srcS = Rebuild()
do
    local ch = srcS and srcS.spells[25423] or {}
    check("Chain Heal 5 from the tooltip's lines: 833 to 950, 540 mana, 2.5 s, 3 targets at 50%",
        ch.healMin == 833 and ch.healMax == 950 and ch.cost == 540 and ch.cast == 2.5 and ch.count == 3
        and ch.jumps == 2 and Near(ch.falloff, 0.5) and ch.costFrom == "tooltip" and ch.castFrom == "tooltip", Show(ch))
    local row = RM:Explain(25423, nil, { live = true })
    check("no learn level read: no penalty, and the row says so",
        row and row.calc.levelMissing == true and row.calc.penalty == 1
        and Near(row.heal, ((833 + 950) / 2 + BONUS * 2.5 / 3.5) * 1.10 * 1.20 * (1 + 0.5 * CRIT)),
        row and Show({ row.heal, row.calc.levelMissing }))
    local okKit, kit = pcall(function() return RM:SpellKit({ live = true }) end)
    local e = okKit and kit.caster[25423] or {}
    check("the shaman's kit: a chain entry with its jumps and falloff, stamped SHAMAN",
        okKit and kit.profile == "SHAMAN" and e.type == "chain" and e.jumps == 2 and Near(e.falloff, 0.5),
        okKit and Show(e) or tostring(kit))
end
restoreS()

MD:SetTalents({ ["Healing Light"] = 3 })
local _, restoreL = Install(S, MD, "PALADIN")
LogIn("PALADIN", 70)
local srcL = Rebuild()
do
    local hs = srcL and srcL.spells[33072] or {}
    check("Holy Shock 5: the heal half of its either-or sentence, its 15 s cooldown",
        hs.healMin == 913 and hs.healMax == 987 and hs.cooldown == 15 and hs.cast == 0, Show(hs))
    local row = RM:Explain(33072, nil, { live = true })
    check("Holy Shock per second is over its cooldown, not the GCD",
        row and row.cast == 1.5 and Near(row.hps, row.heal / 15) and row.calc.cooldown == 15,
        row and Show({ row.cast, row.hps, row.heal }))
    local hl = RM:Explain(27136, nil, { live = true })
    check("Holy Light 11: 2.5/3.5, Healing Light x1.12",
        hl and Near(hl.heal, ((2196 + 2446) / 2 + BONUS * 2.5 / 3.5) * 1.12 * (1 + 0.5 * CRIT)),
        hl and tostring(hl.heal))
    local okKit, kit = pcall(function() return RM:SpellKit({ live = true }) end)
    check("the paladin's kit passes Kit.Check with Holy Shock's cooldown",
        okKit and kit.profile == "PALADIN" and kit.caster[33072] and kit.caster[33072].cooldown == 15,
        tostring(okKit and kit.profile or kit))
end
restoreL()

--------------------------------------------------------------------------------
-- 7. The druid unchanged, a mage gets nothing
--------------------------------------------------------------------------------
T.section("the druid and a mage")
LogIn("MAGE", 64)
local mageRes, mageBuilt = RM:Compute(), Rebuild()
check("a mage (no TBC profile): no rank table, no source",
    next(mageRes) == nil and Src() == nil and mageBuilt == nil,
    Show({ next(mageRes), Src() ~= nil, mageBuilt ~= nil }))
MD:SetTalents(MD.harnessTalents)
LogIn("DRUID", 64)
Rebuild()
do
    check("the druid reads Data/SpellData.lua, and the class book builds nothing for him",
        Src() == MD.SpellData and type(B.Source) == "function" and B:Source() == nil)
    local res, same, detail = RM:Compute(), true, {}
    for fam, b in pairs(druidBefore) do
        local r = res[fam]
        if not (r and #r.rows == b.n and r.suggestedID == b.s and r.rows[1].heal == b.h) then
            same = false; detail[#detail + 1] = fam
        end
    end
    check("the druid's rank table is what it was before any class logged in",
        same and next(druidBefore) ~= nil, table.concat(detail, " "))
    local okKit, kit = pcall(function() return RM:SpellKit() end)
    check("the druid's kit is still the druid's", okKit and kit.profile == "DRUID" and next(kit.tree) ~= nil)
end

T.done()
