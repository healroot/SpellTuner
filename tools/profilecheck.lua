-- tools/run.sh --flavour forever|tbc tools/profilecheck.lua
--
-- T89 (docs/SPEC-next.md 2.1 and section 11, S1 step 1): the class profile
-- registry (Spells/Profiles.lua) and the two druid profiles
-- (Data/Profile_Druid_TBC.lua, Data/Profile_Druid_Forever.lua).
--
--   * every registered profile validates, and every family's `kit` names a
--     Kit.TYPES entry (Engine/Kit.lua);
--   * the tables derived from the druid profile at file load equal TODAY'S
--     CONSTANTS -- written out below as they stood at e2b13f4, and compared
--     with the live tables the files publish (SP.BINDABLE, SP.HOT_RULE,
--     MC.byClass.DRUID, the in-5SR talent row, Kit_Forever's FAMILY_KEY /
--     FAMILY_TYPE, MD.StreamV3.FAMILY_KEY), and with the engine constants T89
--     does not touch (SM.HOT_INDEX, SM.SWIFTMEND_ORDER, SM.SPELL_CD,
--     SV.FAMILIES; on tbc Data/SpellData.lua's families and order);
--   * ALSO WHEN THE STUB LOGS IN A PRIEST: the deriving files are loaded again
--     while MD.ClassProfile is a priest's, and derive the druid's tables still (the
--     derivation never reads MD.ClassProfile);
--   * ForKit of a kit with no profile is the druid's; a second registration
--     raises; the generic profile's caps;
--   * with tools/.cache/talentsforever.json (python3 tools/refcheck.py
--     --fetch), every Forever `names` entry is in that class's spellbook --
--     without the cache that check prints SKIP and is not counted as passed.
--
-- T106 (docs/SPEC-next.md 4.3): the three Forever class profiles
-- (Data/Profile_{Paladin,Shaman,Priest}_Forever.lua) validate with the rest;
-- every name they carry (families and `unmodelled`) is in that class's
-- committed book fixture (tools/data/books/<class>_forever.lua); each grants
-- coach and practice, is coached by the solver only (no threshold rules), and
-- the priest has no Power Word: Shield family until T109. The non-druid who
-- logs in to prove the derivation never reads MD.ClassProfile is a mage (a
-- class with no profile on either line) -- it was a priest until the priest
-- had a profile of its own.
--
-- T123 (tbc): Validate refuses a damage family with a kind or a school
-- Engine/DamageMath.lua does not have, a damage name that is a heal
-- family's, and a damageOrder key that is no damage family.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
-- A detail is printed only for a failure (some carry a function's address,
-- which would make two runs' outputs differ).
local function check(name, cond, detail)
    if cond or detail == "" then detail = nil end
    return T.check(name, cond, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local forever = S.flavour == "forever"

-- T106: the Forever class profiles are listed by the Forever main TOCs (the
-- integrator's line); until they are, they are loaded here, after every file
-- has run -- the same thing, since no file derives anything from them at load.
local CLASS_PROFILES = {
    { class = "PALADIN", file = "Data/Profile_Paladin_Forever.lua", book = "paladin" },
    { class = "SHAMAN", file = "Data/Profile_Shaman_Forever.lua", book = "shaman" },
    { class = "PRIEST", file = "Data/Profile_Priest_Forever.lua", book = "priest" },
}
local classLoad = {}
if forever then
    for _, c in ipairs(CLASS_PROFILES) do
        if MD.Profiles.byClass[c.class] == nil then
            local okL, err = pcall(S.Load, { c.file }, "SpellTuner", MD)
            if not okL then classLoad[c.class] = tostring(err) end
        end
    end
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Show(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then
        if type(v) == "string" then return string.format("%q", v) end
        return tostring(v)
    end
    if depth > 3 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Show(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Deep equality: same keys, same values; functions compared by identity.
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Same(name, got, want)
    local eq = Equal(got, want)
    check(name, eq, (not eq) and ("got " .. Show(got) .. " want " .. Show(want)) or nil)
end

local function Raises(fn, ...)
    local ok, err = pcall(fn, ...)
    return not ok, tostring(err)
end

--------------------------------------------------------------------------------
-- Load what derives from the profiles: on Forever the Replay module (which
-- needs the Recorder module) carries Kit_Forever, Stream_Forever, the engine.
--------------------------------------------------------------------------------
if forever then
    -- The stub's book has Healing Touch, Rejuvenation and Wrath; the kit's
    -- index should also see a hybrid, Swiftmend and the excluded Tranquility
    -- (the texts tools/kitcheck.lua uses).
    S.AddSpell(90201, "Regrowth", "Rank 1",
        function() return "Heals a friendly target for 93 to 107 and another 98 over 21 sec." end,
        { cast = 2000, cost = 80, level = 1 })
    S.AddSpell(90202, "Swiftmend", "Rank 1",
        function()
            return "Instantly heals a target with an active Rejuvenation or Regrowth effect " ..
                "for an amount equal to the full duration of the periodic effect of one of those spells."
        end,
        { cast = 0, cost = 100, level = 10 })
    S.AddSpell(90203, "Tranquility", "Rank 1",
        function()
            return "Regenerates all nearby party members within 20 yards for 98 every 2 sec for 10 sec. " ..
                "Druid must channel to maintain the spell."
        end,
        { cast = 0, cost = 375, level = 20 })
    MD:SetModule("SpellTuner_Replay", true)
end

local P = MD.Profiles
T.section("the registry")
check("MD.Profiles exists, with Register / Get / Require / ForKit / Select / Validate",
    type(P) == "table" and type(P.Register) == "function" and type(P.Get) == "function"
    and type(P.Require) == "function" and type(P.ForKit) == "function"
    and type(P.Select) == "function" and type(P.Validate) == "function")
if type(P) ~= "table" then T.done() end

local DRUID = P.byClass.DRUID
check("the druid profile is registered", DRUID ~= nil and DRUID.class == "DRUID" and DRUID.label == "Druid")
if DRUID == nil then T.done() end

check("Select ran at CORE_LOGIN: MD.ClassProfile is the logged-in druid's", MD.ClassProfile == DRUID)
if not forever then
    -- The spec's name, MD.Profile, is Diagnostics_TBC.lua's /md profile report.
    check("MD:Profile() is still the /md profile report (the registry never writes MD.Profile)",
        type(MD.Profile) == "function")
end

local Kit = MD.Kit
check("Engine/Kit.lua is loaded (Kit.TYPES)", Kit ~= nil and type(Kit.TYPES) == "table")
local TYPES = Kit and Kit.TYPES or {}

T.section("every profile validates; every kit names a Kit.TYPES entry")
local classes = {}
for class in pairs(P.byClass) do classes[#classes + 1] = class end
table.sort(classes)
for _, class in ipairs(classes) do
    local p = P.byClass[class]
    local ok, problems = P.Validate(p, TYPES)
    check(class .. ": Profiles.Validate against Kit.TYPES", ok, problems and problems[1])
    local bad = {}
    for key, def in pairs(p.families) do
        if TYPES[def.kit] == nil then bad[#bad + 1] = key .. "=" .. tostring(def.kit) end
    end
    table.sort(bad)
    check(class .. ": every family's kit is a Kit.TYPES entry", #bad == 0, table.concat(bad, " "))
end

T.section("Validate refuses")
do
    local okKit, pk = P.Validate({ class = "X", label = "X", caps = {},
        families = { A = { names = { "A" }, kit = "nonsense" } } }, TYPES)
    check("a kit type Kit.TYPES lacks, naming the family",
        okKit == false and pk and T.Has(pk[1], "families.A.kit nonsense"), pk and pk[1])
    local okField, pf = P.Validate({ class = "X", label = "X", caps = {}, families = {}, colour = "red" }, TYPES)
    check("an undeclared field", okField == false and pf and T.Has(pf[1], "profile.colour"), pf and pf[1])
    local okSlot, ps = P.Validate({ class = "X", label = "X", caps = {},
        families = { A = { names = { "A" }, kit = "direct" } }, hotSlots = { "A" } }, TYPES)
    check("a HoT slot that is not a HoT family", okSlot == false and ps and T.Has(ps[1], "hotSlots names A"),
        ps and ps[1])
    -- T106: a spell listed as not modelled may not also be a family's name
    local okUn, pu = P.Validate({ class = "X", label = "X", caps = {},
        families = { A = { names = { "A" }, kit = "direct" } }, unmodelled = { "B", "A" } }, TYPES)
    check("T106: an unmodelled name that is a family's", okUn == false and pu
        and T.Has(pu[1], "unmodelled names A, which is in the family A"), pu and pu[1])
    if not forever then
        -- T123: a TBC profile's damage spells (Engine/DamageMath.lua's shape)
        local function Dmg(def, extra)
            local p = { class = "X", label = "X", caps = {}, families = { A = { names = { "A" }, kit = "direct" } },
                        damage = { D = def } }
            for k, v in pairs(extra or {}) do p[k] = v end
            return P.Validate(p, TYPES)
        end
        local okK, pk2 = Dmg({ school = 2, kind = "channelled", baseCast = 1.5 })
        check("T123: a damage kind DamageMath does not have", okK == false and pk2
            and T.Has(pk2[1], "damage.D.kind channelled"), pk2 and pk2[1])
        local okS, ps2 = Dmg({ school = 9, kind = "direct", baseCast = 1.5 })
        check("T123: a damage school outside 1-7", okS == false and ps2 and T.Has(ps2[1], "damage.D.school 9"),
            ps2 and ps2[1])
        local okN, pn = Dmg({ names = { "D", "A" }, school = 2, kind = "direct", baseCast = 1.5 })
        check("T123: a damage name that is a heal family's", okN == false and pn
            and T.Has(pn[1], "damage.D names A, which is the heal family A"), pn and pn[1])
        local okO, po = Dmg({ school = 2, kind = "direct", baseCast = 1.5 }, { damageOrder = { "D", "E" } })
        check("T123: a damageOrder key that is no damage family", okO == false and po
            and T.Has(po[1], "damageOrder names E"), po and po[1])
    end
end

T.section("methods")
do
    local key = DRUID:Family("Healing Touch")
    local key2, def2 = DRUID:Family("Rejuvenation")
    check("Family maps a spellbook name and a key to the family",
        key == "HealingTouch" and key2 == "Rejuvenation" and def2 and def2.kit == "hot"
        and DRUID:Family("Wrath") == nil)
    local can, why = DRUID:Can("coach")
    local cannot, whyNot = DRUID:Can("nonsense")
    check("Can: the druid coaches; an ungranted cap answers false, \"class\"",
        can == true and why == nil and cannot == false and whyNot == "class")
end

--------------------------------------------------------------------------------
-- Today's constants, as they stood at e2b13f4.
--------------------------------------------------------------------------------
local BINDABLE = { "Lifebloom", "Rejuvenation", "Regrowth", "HealingTouch", "Swiftmend" }  -- SimPlanner.lua:87
local HOT_RULE = { "Lifebloom", "Rejuvenation" }                                          -- SimPlanner.lua:90
local SOLVER_FAMILIES = { "Swiftmend", "Regrowth", "HealingTouch", "Lifebloom", "Rejuvenation" } -- SimSolver.lua:279
local HOT_INDEX = { Rejuvenation = 1, Regrowth = 2, Lifebloom = 3 }                       -- SimModel.lua:91
local SWIFTMEND_ORDER = { "Regrowth", "Rejuvenation" }                                     -- SimModel.lua:119
local FAMILY_KEY = {                                                                       -- Kit_Forever.lua:21, Stream_Forever.lua:28
    ["Healing Touch"] = "HealingTouch", ["Regrowth"] = "Regrowth", ["Rejuvenation"] = "Rejuvenation",
    ["Swiftmend"] = "Swiftmend", ["Tranquility"] = "Tranquility",
}
local FAMILY_TYPE = {                                                                      -- Kit_Forever.lua:32
    HealingTouch = "direct", Regrowth = "hybrid", Rejuvenation = "hot",
    Swiftmend = "instant", Tranquility = "channel",
}
local FOREVER_ORDER = { "HealingTouch", "Rejuvenation", "Regrowth" }                       -- Kit_Forever.lua:179
local IN_FSR_TALENT = {                                                                    -- RegenModel.lua:155
    DRUID = { "Intensity", 0.10 }, PRIEST = { "Meditation", 0.05 }, MAGE = { "Arcane Meditation", 0.05 },
}

-- The derived tables, read off the files' published names. `reloaded` says
-- whether this is the second pass (after a priest logged in).
local function DerivedChecks(label)
    local SP = MD.SimPlanner
    Same(label .. "SP.BINDABLE equals the constant", SP and SP.BINDABLE, BINDABLE)
    Same(label .. "SP.HOT_RULE equals the constant", SP and SP.HOT_RULE, HOT_RULE)
    if forever then
        local RM = MD.RankMath
        Same(label .. "Kit_Forever's FAMILY_KEY equals the constant", RM and RM.FAMILY_KEY, FAMILY_KEY)
        Same(label .. "Kit_Forever's FAMILY_TYPE equals the constant", RM and RM.FAMILY_TYPE, FAMILY_TYPE)
        Same(label .. "MD.StreamV3.FAMILY_KEY equals the constant",
            MD.StreamV3 and MD.StreamV3.FAMILY_KEY, FAMILY_KEY)
    else
        local MC = MD.ManaCooldowns
        local d = MC and MC.byClass and MC.byClass.DRUID
        local e = d and d[1]
        check(label .. "MC.byClass.DRUID equals the constant (Innervate, InnervateValue)",
            d ~= nil and #d == 1 and e.key == "innervate" and e.short == "inn" and e.id == 29166
            and e.name == "Innervate" and e.duration == 20 and type(e.value) == "function"
            and e.value == MC.VALUES.innervate,
            Show(d))
        local keys = 0
        for _ in pairs(e or {}) do keys = keys + 1 end
        check(label .. "MC.byClass.DRUID's entry carries exactly the constant's six fields", keys == 6,
            tostring(keys))
        Same(label .. "the in-5SR talent table equals the constant",
            MD.Regen and MD.Regen.IN_FSR_TALENT, IN_FSR_TALENT)
    end
end

T.section("the derived tables equal today's constants")
DerivedChecks("")
Same("planner.families equals the constant", DRUID.planner.families, SOLVER_FAMILIES)
Same("planner.families equals SV.FAMILIES", DRUID.planner.families, MD.SimSolver and MD.SimSolver.FAMILIES)

do
    local SM = MD.SimModel
    local want = {}
    for fam, slot in pairs(HOT_INDEX) do
        if DRUID.families[fam] then want[fam] = slot end
    end
    Same("HotIndex keeps SM.HOT_INDEX's slot numbers for this line's HoTs", DRUID:HotIndex(), want)
    Same("SM.HOT_INDEX is still the constant", SM and SM.HOT_INDEX, HOT_INDEX)
    local sm = DRUID.families.Swiftmend
    Same("Swiftmend eats SM.SWIFTMEND_ORDER", sm and sm.eats, SM and SM.SWIFTMEND_ORDER)
    Same("SM.SWIFTMEND_ORDER is still the constant", SM and SM.SWIFTMEND_ORDER, SWIFTMEND_ORDER)
    check("Swiftmend's cooldown is SM.SPELL_CD[18562]",
        sm and SM and sm.cooldown == SM.SPELL_CD[18562] and sm.cooldown == 15,
        tostring(sm and sm.cooldown))
end

if forever then
    -- What Kit_Forever installs: the order, the exclude marks, the crit school.
    local crit = MD.API.SpellCritChance
    local schools = {}
    MD.API.SpellCritChance = function(school, ...)
        schools[#schools + 1] = school
        return crit(school, ...)
    end
    local built, err = pcall(function() return MD.RankMath:SpellKit() end)
    MD.API.SpellCritChance = crit
    local critOk = built and #schools >= 1 and schools[1] == 4
    check("Kit_Forever reads crit from the profile's school (Nature, 4)", critOk,
        (not critOk) and ((built and "" or tostring(err)) .. " schools " .. Show(schools)) or nil)
    local SD = MD.SpellData
    Same("MD.SpellData.familyOrder equals the constant", SD.familyOrder, FOREVER_ORDER)
    local seen = {}
    for key in pairs(SD.families or {}) do seen[#seen + 1] = key end
    table.sort(seen)
    check("the book's five druid families reached the kit's index",
        table.concat(seen, " ") == "HealingTouch Regrowth Rejuvenation Swiftmend Tranquility",
        table.concat(seen, " "))
    local excl = {}
    for key, fam in pairs(SD.families or {}) do excl[key] = fam.exclude end
    Same("only Tranquility is excluded from the plans (the constant's mark)", excl, { Tranquility = true })
    -- the same marks through Kit.Restore's policy (a snapshot back into a kit)
    local snapOk, restored = pcall(function()
        MD.RankMath.KitRestore(MD.RankMath.KitSnapshot())
        local out = {}
        for key, fam in pairs(MD.SpellData.families) do out[key] = fam.exclude end
        return out
    end)
    check("KitRestore keeps Tranquility excluded", snapOk and restored.Tranquility == true,
        (not snapOk) and tostring(restored) or nil)
else
    -- The TBC profile mirrors Data/SpellData.lua (which stays the verified source).
    local SD = MD.SpellData
    local mismatch = {}
    for key, fam in pairs(SD.families) do
        local def = DRUID.families[key]
        if def == nil then
            mismatch[#mismatch + 1] = key .. " missing"
        elseif def.kit ~= fam.type or def.names[1] ~= fam.label or #def.names ~= 1
            or (def.exclude == true) ~= (fam.exclude == true) then
            mismatch[#mismatch + 1] = key
        end
    end
    for key in pairs(DRUID.families) do
        if SD.families[key] == nil then mismatch[#mismatch + 1] = key .. " extra" end
    end
    table.sort(mismatch)
    check("the TBC profile's families are SD.families (type, label, exclude)", #mismatch == 0,
        table.concat(mismatch, " "))
    Same("the TBC profile's order is SD.familyOrder", DRUID.order, SD.familyOrder)
end

T.section("ForKit, a second registration, the generic profile")
check("ForKit of a kit with no profile (and of nil) is the druid's",
    P.ForKit({ caster = {} }) == DRUID and P.ForKit(nil) == DRUID and P.ForKit({ profile = "DRUID" }) == DRUID)
check("ForKit of a class with no profile is the generic one", P.ForKit({ profile = "WARLOCK" }) == P.generic)
do
    local raised, msg = Raises(P.Register, "DRUID", { label = "Druid", caps = {}, families = {} })
    check("a second registration for one class raises, naming it",
        raised and T.Has(msg, "second profile for DRUID") and P.byClass.DRUID == DRUID, msg)
    local raised2, msg2 = Raises(P.Register, "WARLOCK", { label = "Warlock", caps = {},
        families = { A = { names = { "A" } } } })
    check("a registration that fails Validate raises and registers nothing",
        raised2 and T.Has(msg2, "fails Profiles.Validate") and P.byClass.WARLOCK == nil, msg2)
end
do
    local g = P.Get("WARLOCK")
    local caps = {}
    for cap in pairs(g.caps) do caps[#caps + 1] = cap end
    table.sort(caps)
    local want = forever and "clock rankTable tooltip" or "clock"
    check("the generic profile's caps: what a class with no profile gets today (" .. want .. ")",
        g == P.generic and table.concat(caps, " ") == want, table.concat(caps, " "))
    local can, why = g:Can("coach")
    check("the generic profile cannot coach (false, \"class\")", can == false and why == "class")
    check("Get never answers nil", P.Get(nil) == P.generic and P.Get("NOPE") == P.generic)
    local raised = Raises(P.Require, "WARLOCK", "test")
    check("Require raises for a class with no profile", raised)
end

--------------------------------------------------------------------------------
-- A mage logs in (T106: a class with no profile on either line -- this was a
-- priest until the priest had a profile of its own). First with no mage
-- profile (the generic one), then with a test mage profile whose lists differ
-- from the druid's in every derived table; the deriving files are loaded again
-- and must still derive the druid's.
--------------------------------------------------------------------------------
T.section("a mage logs in")
S.units.player.class = "MAGE"
MD:DetectProfile()
MD:Fire("CORE_LOGIN")
check("a mage with no profile is given the generic one", MD.ClassProfile == P.generic and MD.player.class == "MAGE")

local MAGE = {
    label = "Mage", critSchool = 6, caps = { clock = true },
    families = {
        Heal  = { names = { "Healing Touch" }, kit = "direct" },   -- a name the druid uses, on purpose
        Renew = { names = { "Renew" }, kit = "hot", hot = true },
    },
    order = { "Renew", "Heal" },
    hotSlots = { "Renew" },
    planner = { bindable = { "Renew" }, hotRule = { "Renew" }, families = { "Renew" } },
}
if not forever then
    MAGE.manaCooldowns = { { key = "x", short = "x", id = 1, name = "X", duration = 1, value = "innervate" } }
    MAGE.regen = { inFsrTalent = { "Arcane Meditation", 0.99 } }
end
local registered = pcall(P.Register, "MAGE", MAGE)
MD:Fire("CORE_LOGIN")
check("with a mage profile registered, MD.ClassProfile is the mage's",
    registered and MD.ClassProfile == P.byClass.MAGE and MD.ClassProfile ~= DRUID)

local files
if forever then
    files = {
        { "Modules/SpellTuner_Recorder/Stream_Forever.lua", "SpellTuner_Recorder" },
        { "Modules/SpellTuner_Replay/Kit_Forever.lua", "SpellTuner_Replay" },
        { "Engine/SimPlanner.lua", "SpellTuner_Replay" },
    }
else
    files = {
        { "Engine/RegenModel.lua", "SpellTuner" },
        { "Engine/ManaCooldowns.lua", "SpellTuner" },
        { "Engine/SimPlanner.lua", "SpellTuner" },
    }
end
local reloaded = true
for _, f in ipairs(files) do
    local chunk, err = loadfile(S.root .. "/" .. f[1])
    local ok, rerr = false, err
    if chunk then ok, rerr = pcall(chunk, f[2], MD) end
    if not ok then
        reloaded = false
        print("reload " .. f[1] .. ": " .. tostring(rerr))
    end
end
check("the deriving files load again while a priest is logged in", reloaded)
DerivedChecks("mage logged in: ")
check("ForKit of a kit with no profile is still the druid's while a mage is logged in",
    P.ForKit({}) == DRUID)

-- And none of them names MD.ClassProfile at all (only MD.Profiles).
do
    local named = {}
    for _, f in ipairs(files) do
        local fh = io.open(S.root .. "/" .. f[1], "r")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        for line in src:gmatch("[^\n]+") do
            local code = line:gsub("%-%-.*$", "")
            if code:find("ClassProfile", 1, true) or code:find("MD%.Profile[^s]") then named[#named + 1] = f[1] end
        end
    end
    check("no deriving file reads MD.ClassProfile", #named == 0, table.concat(named, " "))
end

--------------------------------------------------------------------------------
-- T106: the Forever class profiles against their committed book fixtures.
--------------------------------------------------------------------------------
if forever then
    T.section("T106: the Forever class profiles")
    local SCHOOL = { PALADIN = 2, SHAMAN = 4, PRIEST = 2 }
    for _, c in ipairs(CLASS_PROFILES) do
        local p = P.byClass[c.class]
        local okB, book = pcall(dofile, S.root .. "/tools/data/books/" .. c.book .. "_forever.lua")
        local have = {}
        for _, row in ipairs(okB and book.spells or {}) do have[row.name] = true end
        local missing = {}
        for _, def in pairs(p and p.families or {}) do
            for _, name in ipairs(def.names) do
                if not have[name] then missing[#missing + 1] = name end
            end
        end
        for _, name in ipairs(p and p.unmodelled or {}) do
            if not have[name] then missing[#missing + 1] = name end
        end
        table.sort(missing)
        check(c.class .. ": registered, every name it carries is in its book fixture",
            p ~= nil and okB and #missing == 0,
            classLoad[c.class] or (not okB and tostring(book)) or table.concat(missing, ", "))
        local caps = {}
        for cap in pairs(p and p.caps or {}) do caps[#caps + 1] = cap end
        table.sort(caps)
        local shield = p and p:Family("Power Word: Shield")
        check(c.class .. ": coach and practice granted, solver only, its crit school",
            p ~= nil and table.concat(caps, " ") == "clock coach practice rankTable tooltip"
            and p.planner ~= nil and p.planner.rules == nil and p.planner.bindable == nil
            and p.critSchool == SCHOOL[c.class] and shield == nil
            and type(p.unmodelled) == "table" and #p.unmodelled > 0,
            string.format("caps=%s rules=%s school=%s shield=%s", table.concat(caps, " "),
                tostring(p and p.planner and p.planner.rules), tostring(p and p.critSchool), tostring(shield)))
    end
end

--------------------------------------------------------------------------------
-- The talentsforever cache: every Forever name in that class's spellbook.
--------------------------------------------------------------------------------
-- A small JSON reader (tools only; nothing shipped reads JSON).
local function DecodeJSON(s)
    local pos = 1
    local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
    local value
    local function str()
        pos = pos + 1
        local parts = {}
        while true do
            local a = s:find('["\\]', pos)
            if not a then error("unterminated string") end
            parts[#parts + 1] = s:sub(pos, a - 1)
            if s:sub(a, a) == '"' then pos = a + 1; break end
            local c = s:sub(a + 1, a + 1)
            local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
            if c == "u" then
                local code = tonumber(s:sub(a + 2, a + 5), 16) or 63
                parts[#parts + 1] = code < 128 and string.char(code) or "?"
                pos = a + 6
            else
                parts[#parts + 1] = map[c] or c
                pos = a + 2
            end
        end
        return table.concat(parts)
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                ws()
                local k = str()
                ws(); pos = pos + 1   -- ':'
                t[k] = value()
                ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "}" then return t end
            end
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value()
                ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "]" then return t end
            end
        elseif c == '"' then
            return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then error("bad JSON at " .. pos) end
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

T.section("the talentsforever cache")
if forever then
    local path = S.root .. "/tools/.cache/talentsforever.json"
    local fh = io.open(path, "r")
    if not fh then
        print("SKIP every Forever profile name is in that class's spellbook - no tools/.cache/talentsforever.json"
            .. " (python3 tools/refcheck.py --fetch); not counted as passed")
    else
        local text = fh:read("*a")
        fh:close()
        local okJ, data = pcall(DecodeJSON, text)
        local books = okJ and type(data) == "table" and data.spellbooks
        check("the cache reads as JSON with spellbooks", type(books) == "table", not okJ and tostring(data) or nil)
        for _, class in ipairs(classes) do
            if class ~= "MAGE" then   -- the test mage above is not a shipped profile
                local p = P.byClass[class]
                local book = books and books[class:sub(1, 1) .. class:sub(2):lower()]
                local have = {}
                for _, tab in ipairs(book and book.tabs or {}) do
                    for _, sp in ipairs(tab.spells or {}) do have[sp[1]] = true end
                end
                for _, sp in ipairs(book and book.general or {}) do have[sp[1]] = true end
                local missing = {}
                for _, def in pairs(p.families) do
                    for _, name in ipairs(def.names) do
                        if not have[name] then missing[#missing + 1] = name end
                    end
                end
                for _, name in ipairs(p.unmodelled or {}) do
                    if not have[name] then missing[#missing + 1] = name end
                end
                table.sort(missing)
                check(class .. ": every Forever name is in the talentsforever spellbook",
                    book ~= nil and #missing == 0, book == nil and "no spellbook for the class"
                        or table.concat(missing, ", "))
            end
        end
    end
end

T.done()
