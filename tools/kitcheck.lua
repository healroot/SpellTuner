-- tools/run.sh tools/kitcheck.lua
--
-- T15 (docs/tasks/T15-kit-from-book.md): the engine's spell kit, built from
-- Spells/Book.lua through Modules/SpellTuner_Replay/Kit_Forever.lua, once the
-- Replay module is switched on. Forever, and since T63 (P19) tbc too: the kit's
-- shape has one owner (Engine/Kit.lua) and BOTH builders end with Kit.Check --
-- RankMath:SpellKit on tbc (the section at the end), Kit_Forever's here.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB

local function Footer()
    print(string.format("%d ok, %d failed", ok, #fails))
    if #fails > 0 then os.exit(1) end
    os.exit(0)
end

-- A copy of a kit, deep enough to break one entry without touching the
-- builder's own (a cached kit is shared).
local function CopyKit(kit)
    local c = {}
    for k, v in pairs(kit) do
        if type(v) == "table" then
            c[k] = {}
            for id, e in pairs(v) do
                local ce = {}
                for f, x in pairs(e) do ce[f] = x end
                c[k][id] = ce
            end
        else
            c[k] = v
        end
    end
    return c
end

-- The first direct-type entry of a kit's caster form, for the castBase test.
local function FirstDirect(kit)
    local ids = {}
    for id, e in pairs(kit.caster) do
        if e.type == "direct" and not e.dataMissing and not MD.Kit.UNPRICED[e.family] then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids[1]
end

local function CastBaseFails(kit)
    local id = FirstDirect(kit)
    local broken = CopyKit(kit)
    if id then broken.caster[id].castBase = nil end
    local okV, problems = MD.Kit.Validate(broken)
    local named = false
    for _, p in ipairs(problems or {}) do
        if p:find("caster%[" .. tostring(id) .. "%]", 1) and p:find("castBase", 1, true) then named = true end
    end
    return id ~= nil and okV == false and named, id, problems and problems[1]
end

--------------------------------------------------------------------------------
-- tbc (T63, P19): RankMath:SpellKit ends with Kit.Check, and the kit it builds
-- validates -- Innervate, priced for its mana only, included.
--------------------------------------------------------------------------------
if S.flavour == "tbc" then
    local Kit = MD.Kit
    local checks, realCheck = 0, Kit and Kit.Check
    if Kit then
        Kit.Check = function(...) checks = checks + 1; return realCheck(...) end
    end
    local built, kit = pcall(function() return MD.RankMath:SpellKit() end)
    if Kit then Kit.Check = realCheck end
    local valid, problems = false, nil
    if Kit and built then valid, problems = Kit.Validate(kit) end
    check("tbc: RankMath:SpellKit ends with Kit.Check and its kit validates",
        Kit ~= nil and built and checks == 1 and valid
        and kit.caster[29166] ~= nil and Kit.UNPRICED[kit.caster[29166].family] == true,
        string.format("Kit=%s built=%s checks=%d valid=%s first=%s",
            tostring(Kit ~= nil), tostring(built), checks, tostring(valid),
            tostring(problems and problems[1] or (not built and kit) or nil)))

    local failed, id, first = false, nil, nil
    if Kit and built then failed, id, first = CastBaseFails(kit) end
    check("tbc: a kit missing castBase fails validation, naming the entry",
        failed, string.format("id=%s first=%s", tostring(id), tostring(first)))

    local aliased, restoredOk, restoreProblem = false, false, nil
    if Kit and built then
        aliased = MD.SimModel.KitSnapshot == Kit.Snapshot
        local snap = Kit.Snapshot(kit)
        local restored = Kit.Restore(snap)
        restoredOk, restoreProblem = Kit.Validate(restored)
        restoredOk = restoredOk and restored.caster[29166] ~= nil
    end
    check("tbc: SM.KitSnapshot is Kit.Snapshot, and a snapshot restores into a kit that validates",
        aliased and restoredOk,
        string.format("aliased=%s restored=%s first=%s", tostring(aliased), tostring(restoredOk),
            tostring(restoreProblem and restoreProblem[1])))

    -- T96 (docs/SPEC-next.md 2.1): RankMath stamps the druid profile (SpellData
    -- is the druid's) and emits each family's cooldown from it -- Swiftmend's 15.
    local sm, smN, others = nil, 0, {}
    if built then
        for id, e in pairs(kit.caster) do
            if e.family == "Swiftmend" then
                smN = smN + 1
                if e.cooldown == 15 then sm = sm or id end
            elseif e.cooldown ~= nil then
                others[#others + 1] = e.family
            end
        end
    end
    local cdFam, cdSecs
    if sm and MD.SimModel.CooldownOf then cdFam, cdSecs = MD.SimModel.CooldownOf({ kit = kit }, sm) end
    check("tbc: RankMath stamps the druid profile and emits Swiftmend's 15 s cooldown (T96)",
        built and kit.profile == "DRUID" and smN > 0 and sm ~= nil and #others == 0
        and cdFam == "Swiftmend" and cdSecs == 15,
        string.format("profile=%s swiftmend ranks=%d with 15=%s others=%s cd=%s,%s",
            tostring(built and kit.profile), smN, tostring(sm), table.concat(others, ","),
            tostring(cdFam), tostring(cdSecs)))

    local snapP, backP = "?", "?"
    if Kit and built then
        local snap = Kit.Snapshot(kit)
        snapP = tostring(snap.profile)
        backP = tostring(Kit.Restore(snap).profile)
    end
    check("tbc: a druid kit's snapshot names no profile and restores as the druid's (T96)",
        snapP == "nil" and backP == "DRUID",
        string.format("snapshot=%s restored=%s", snapP, backP))
    Footer()
end

--------------------------------------------------------------------------------
-- Fixtures, on top of T7a's fixed five (5185 Healing Touch R1, 774
-- Rejuvenation R1, 1058 Rejuvenation R2, 5176 Wrath, the slot-4 error row).
--------------------------------------------------------------------------------
-- T63: Regrowth's numbers can move (a rescan that changes one entry).
local regrowthText = "Heals a friendly target for 93 to 107 and another 98 over 21 sec."
S.AddSpell(90201, "Regrowth", "Rank 1",
    function() return regrowthText end,
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

S.AddSpell(90204, "Wild Growth", "Rank 1",
    function() return "Heals the target and their party for 679 over 7 sec." end,
    { cast = 0, cost = 200, level = 40 })

-- A second Healing Touch rank the character has NOT learned yet.
S.AddSpell(90205, "Healing Touch", "Rank 2",
    function() return "Heals a friendly target for 90 to 110." end,
    { cast = 2000, cost = 55, level = 8, known = false })

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

local function WalkSecret(t, seen)
    if type(t) ~= "table" then return false end
    seen = seen or {}
    if seen[t] then return false end
    seen[t] = true
    for k, v in pairs(t) do
        if MD.API.IsSecret(k) or MD.API.IsSecret(v) then return true end
        if type(v) == "table" and WalkSecret(v, seen) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- 1: the kit loads with the Replay module and not before
--------------------------------------------------------------------------------
local beforeNil = (MD.RankMath == nil)
MD:SetModule("SpellTuner_Replay", true)
local kitAfter = MD.RankMath and MD.RankMath:SpellKit()
check("the kit loads with the Replay module and not before",
    beforeNil and type(MD.RankMath) == "table" and type(MD.RankMath.SpellKit) == "function"
    and type(kitAfter) == "table" and type(kitAfter.caster) == "table",
    "beforeNil=" .. tostring(beforeNil) .. " kitAfter=" .. tostring(kitAfter))

--------------------------------------------------------------------------------
-- 2: each healing rank is valued from its own text
--------------------------------------------------------------------------------
local kit = MD.RankMath:SpellKit()
local c1 = kit.caster[5185]
local c2 = kit.caster[774]
local c3 = kit.caster[90201]
check("each healing rank is valued from its own text",
    c1 and c1.direct == 47.5 and c1.type == "direct" and c1.family == "HealingTouch"
        and c1.cost == 25 and c1.cast == 1.5
    and c2 and c2.type == "hot" and c2.ticks == 4 and c2.tick == 8 and c2.tickPeriod == 3
    and c3 and c3.type == "hybrid" and c3.direct == 100 and c3.ticks == 7 and c3.tick == 14,
    string.format("c1=%s c2=%s c3=%s", tostring(c1 and c1.direct), tostring(c2 and c2.tick), tostring(c3 and c3.tick)))

--------------------------------------------------------------------------------
-- 3: Swiftmend eats the whole HoT, Forever's rule
--------------------------------------------------------------------------------
local SD = MD.SpellData
local rejuvMax = kit.caster[SD.maxRank.Rejuvenation]
local sm = kit.caster[90202]
check("Swiftmend eats the whole HoT, Forever's rule",
    sm and rejuvMax and sm.swiftmendRejuv == rejuvMax.tick * rejuvMax.ticks
    and sm.swiftmendRegrowth == 14 * 7 and sm.cast == 1.5,
    string.format("swiftmendRejuv=%s swiftmendRegrowth=%s cast=%s",
        tostring(sm and sm.swiftmendRejuv), tostring(sm and sm.swiftmendRegrowth), tostring(sm and sm.cast)))

--------------------------------------------------------------------------------
-- 4: a rank not known and a damage spell are not in the kit. T101 (docs/
--    SPEC-next.md 4.2 P2): Wild Growth -- a heal family the druid profile
--    does not name -- is, by its shape: a `group` HoT on the caster's party,
--    its total in uniform ticks (1 s, as 7 s is no multiple of 3: VERIFY,
--    never an invented front-loaded curve), named from the book; and
--    Tranquility's text reaches the party, so its channel lands on it.
--------------------------------------------------------------------------------
do
    local wg = kit.caster[90204]
    local tq = kit.caster[90203]
    check("a rank not known and a damage spell are not in the kit; Wild Growth is, a group HoT (T101)",
        kit.caster[90205] == nil and kit.caster[5176] == nil
        and wg and wg.type == "group" and wg.family == "WildGrowth" and wg.tickPeriod == 1 and wg.ticks == 7
        and wg.tick == 97 and wg.duration == 7 and wg.direct == nil and not wg.dataMissing
        and not Contains(SD.skipped, "Wild Growth")
        and SD.families.WildGrowth and SD.families.WildGrowth.label == "Wild Growth"
        and tq and tq.party == true,
        string.format("R2=%s wrath=%s wildgrowth=%s/%s/%sx%s every %s tranquility party=%s skipped=%s",
            tostring(kit.caster[90205]), tostring(kit.caster[5176]), tostring(wg and wg.type),
            tostring(wg and wg.family), tostring(wg and wg.ticks), tostring(wg and wg.tick),
            tostring(wg and wg.tickPeriod), tostring(tq and tq.party), table.concat(SD.skipped or {}, ",")))
end

--------------------------------------------------------------------------------
-- 5: the spell index answers what the engine asks
--------------------------------------------------------------------------------
check("the spell index answers what the engine asks",
    SD.spells[5185] and SD.spells[5185].family == "HealingTouch"
    and SD.families.HealingTouch and SD.families.HealingTouch.label == "Healing Touch"
    and SD.maxRank.Rejuvenation == 1058
    and SD.known.Rejuvenation[1] == 774 and SD.known.Rejuvenation[2] == 1058
    and SD.all.HealingTouch[1] == 5185 and SD.all.HealingTouch[2] == 90205,
    string.format("family=%s label=%s maxRank=%s known=%s,%s all=%s,%s",
        tostring(SD.spells[5185] and SD.spells[5185].family),
        tostring(SD.families.HealingTouch and SD.families.HealingTouch.label),
        tostring(SD.maxRank.Rejuvenation),
        tostring(SD.known.Rejuvenation[1]), tostring(SD.known.Rejuvenation[2]),
        tostring(SD.all.HealingTouch[1]), tostring(SD.all.HealingTouch[2])))

--------------------------------------------------------------------------------
-- 6: the engine runs a scenario on the Forever kit
--------------------------------------------------------------------------------
do
    local htID, rejID = SD.maxRank.HealingTouch, SD.maxRank.Rejuvenation
    local eHT, eRej = kit.caster[htID], kit.caster[rejID]
    local sc = {
        dur = 20, pool = 100000, initial = { mana = 100000, form = "caster" },
        targets = { { name = "T1", maxHP = 1000000, hp0 = 1, tracked = true } },
        kit = kit,
    }
    local runOk, r = pcall(function()
        return MD.SimModel:Run(sc, MD.SimModel.ScriptPlan({
            { 1, htID, eHT.cost, 1 },
            { 3, rejID, eRej.cost, 1 },
        }))
    end)
    local expected = (eHT.direct * (1 + 0.5 * (kit.crit or 0))) + (eRej.tick * eRej.ticks)
    check("the engine runs a scenario on the Forever kit",
        runOk and type(r) == "table" and math.abs((r.healed or 0) - expected) <= 1,
        string.format("runOk=%s healed=%s expected=%.2f",
            tostring(runOk), tostring(r and r.healed), expected))
end

--------------------------------------------------------------------------------
-- 7: the crit chance is a fraction from the Nature school, and never secret
--------------------------------------------------------------------------------
do
    S.inCombat = false
    S.crit[4] = 5.1
    local kitPlain = MD.RankMath:SpellKit()

    S.inCombat = true
    local kitSecret = MD.RankMath:SpellKit()
    S.inCombat = false

    check("the crit chance is a fraction from the Nature school, and never secret",
        kitPlain.crit == 0.051 and kitSecret.crit == 0.051 and not WalkSecret(kitSecret),
        string.format("kitPlain.crit=%s kitSecret.crit=%s", tostring(kitPlain.crit), tostring(kitSecret.crit)))
end

--------------------------------------------------------------------------------
-- T63 (P19 of docs/PLAN-refactor-ux.md, review A12 / A11): the kit has an
-- owner (Engine/Kit.lua), and the Forever kit is built once per book
-- generation.
--------------------------------------------------------------------------------
local Kit = MD.Kit
local Book = MD.Book

-- 8: the Forever builder ends with Kit.Check, and its kit validates -- a rank
--    whose cast time the book cannot read included (it is dataMissing)
do
    local checks, realCheck = 0, Kit and Kit.Check
    if Kit then Kit.Check = function(...) checks = checks + 1; return realCheck(...) end end
    S.crit[4] = 6.2                     -- a crit the cache has not seen: a build
    local built, k = pcall(function() return MD.RankMath:SpellKit() end)
    if Kit then Kit.Check = realCheck end
    local valid, problems = false, nil
    if Kit and built then valid, problems = Kit.Validate(k) end

    -- 5185 (Healing Touch R1) with no cast the book can read: neither
    -- SpellInfo nor the tooltip data answers
    local API = MD.API
    local rawInfo, rawTip = rawget(API, "SpellInfo"), rawget(API, "SpellTooltipData")
    local info, tip = API.SpellInfo, API.SpellTooltipData
    rawset(API, "SpellInfo", function(id, ...) if id == 5185 then return nil end return info(id, ...) end)
    rawset(API, "SpellTooltipData", function(id, ...) if id == 5185 then return nil end return tip(id, ...) end)
    if Book then Book:MarkDirty() end
    local builtNoCast, kNoCast = pcall(function() return MD.RankMath:SpellKit() end)
    rawset(API, "SpellInfo", rawInfo)
    rawset(API, "SpellTooltipData", rawTip)
    if Book then Book:MarkDirty() end
    local noCast = builtNoCast and kNoCast.caster[5185]
    local noCastOk = noCast and noCast.dataMissing == true and noCast.cast == nil
        and Kit and Kit.Validate(kNoCast)
    local back = MD.RankMath:SpellKit().caster[5185]

    check("the Forever builder ends with Kit.Check and its kit validates, an unreadable cast as dataMissing",
        Kit ~= nil and built and checks == 1 and valid and noCastOk == true
        and back and back.dataMissing == nil and back.cast == 1.5,
        string.format("Kit=%s built=%s checks=%d valid=%s first=%s noCast=%s back=%s",
            tostring(Kit ~= nil), tostring(built), checks, tostring(valid),
            tostring(problems and problems[1] or (not built and k) or nil),
            tostring(noCastOk), tostring(back and back.cast)))
end

-- 9: a kit missing castBase fails validation
do
    local failed, id, first = false, nil, nil
    if Kit then failed, id, first = CastBaseFails(MD.RankMath:SpellKit()) end
    check("a kit missing castBase fails validation, naming the entry",
        failed, string.format("id=%s first=%s", tostring(id), tostring(first)))
end

-- 10: two calls with an unchanged book return the same table and write
--     cdb.kit once
do
    local writes, realSnap = 0, Kit and Kit.Snapshot
    if Kit then Kit.Snapshot = function(...) writes = writes + 1; return realSnap(...) end end
    S.crit[4] = 6.4                     -- a change the cache has not seen: one build, one write
    local k1 = MD.RankMath:SpellKit()
    local gen1, saved1 = Book and Book.generation, MD.cdb.kit
    if Book then Book:MarkDirty() end   -- the book read again, unchanged
    local k2 = MD.RankMath:SpellKit()
    if Kit then Kit.Snapshot = realSnap end
    local gen2 = Book and Book.generation
    check("two calls with an unchanged book return the same table and write cdb.kit once",
        Kit ~= nil and gen1 ~= nil and rawequal(k1, k2) and gen1 == gen2
        and writes == 1 and rawequal(MD.cdb.kit, saved1),
        string.format("same=%s gen=%s->%s writes=%d cdbSame=%s",
            tostring(rawequal(k1, k2)), tostring(gen1), tostring(gen2), writes,
            tostring(rawequal(MD.cdb.kit, saved1))))
end

-- 11: a rescan that changes one entry bumps the generation and rebuilds
do
    local k1 = MD.RankMath:SpellKit()
    local gen1, saved1 = Book and Book.generation, MD.cdb.kit
    regrowthText = "Heals a friendly target for 193 to 207 and another 98 over 21 sec."
    if Book then Book:MarkDirty() end
    local k2 = MD.RankMath:SpellKit()
    local gen2 = Book and Book.generation
    local e2 = k2.caster[90201]
    local saved2 = MD.cdb.kit
    check("a rescan that changes one entry bumps the generation and rebuilds",
        gen1 ~= nil and gen2 == gen1 + 1 and not rawequal(k1, k2)
        and e2 and e2.direct == 200 and k1.caster[90201].direct == 100
        and not rawequal(saved2, saved1) and saved2.caster[90201].direct == 200,
        string.format("gen=%s->%s rebuilt=%s direct=%s->%s cdb=%s",
            tostring(gen1), tostring(gen2), tostring(not rawequal(k1, k2)),
            tostring(k1.caster[90201].direct), tostring(e2 and e2.direct),
            tostring(saved2 and saved2.caster[90201] and saved2.caster[90201].direct)))
end

--------------------------------------------------------------------------------
-- T96 (docs/SPEC-next.md 2.1, S1 step 2): the kit is built by its family's
-- KIT TYPE, carries its own cooldowns, and names the profile it was built by.
--------------------------------------------------------------------------------
local RM = MD.RankMath
local DRUID = MD.Profiles.Get("DRUID")

-- 12: one filler per kit type, and the entries it writes
do
    local KEF = RM.KitEntryFor
    local missing = {}
    for key, def in pairs(DRUID.families) do
        if def.kit ~= "instant" and not (KEF and type(KEF[def.kit]) == "function") then
            missing[#missing + 1] = key .. ":" .. def.kit
        end
    end
    table.sort(missing)
    local d, h, y, c = {}, {}, {}, {}
    if KEF then
        KEF.direct(d, { min = 40, max = 60 }, 0.1)
        KEF.hot(h, { over = 36, dur = 9 })
        KEF.hybrid(y, { min = 90, max = 110, over = 60, dur = 6 }, 0.2)
        KEF.channel(c, { parsed = { heal = { tick = 98, period = 2, periodDur = 10 } } })
    end
    local hy = { min = 90, max = 110 }
    local yMissing = {}
    if KEF then KEF.hybrid(yMissing, hy, 0) end
    local tq = MD.RankMath:SpellKit().caster[90203]
    check("T96: KitEntryFor fills each kit type the druid profile names",
        KEF ~= nil and #missing == 0 and KEF.instant == nil
        and d.direct == 50 and d.directCrit == 0.1 and d.dataMissing == nil
        and h.tick == 12 and h.ticks == 3 and h.tickPeriod == 3 and h.duration == 9
        and y.direct == 100 and y.directCrit == 0.2 and y.tick == 30 and y.ticks == 2
        and yMissing.dataMissing == true and yMissing.direct == nil
        and c.channelTick == 98 and c.channelTicks == 5 and c.tickPeriod == 2
        and tq and tq.type == "channel" and tq.channelTick == 98 and tq.tickPeriod == 2,
        string.format("fillers=%s missing=%s tq=%s/%s/%s", tostring(KEF ~= nil), table.concat(missing, ","),
            tostring(tq and tq.channelTick), tostring(tq and tq.channelTicks), tostring(tq and tq.tickPeriod)))
end

-- 13: Swiftmend's cooldown is the profile's 15 s, on the kit entry, and the
--     engine's per-family cooldown reads it
do
    local k = MD.RankMath:SpellKit()
    local sm = k.caster[90202]
    local others = {}
    for id, e in pairs(k.caster) do
        if id ~= 90202 and e.cooldown ~= nil then others[#others + 1] = tostring(id) end
    end
    local fam, secs = MD.SimModel.CooldownOf({ kit = k }, 90202)
    check("T96: Swiftmend's kit entry carries the profile's 15 s cooldown",
        sm and sm.cooldown == 15 and DRUID.families.Swiftmend.cooldown == 15 and #others == 0
        and fam == "Swiftmend" and secs == 15,
        string.format("cooldown=%s others=%s CooldownOf=%s,%s", tostring(sm and sm.cooldown),
            table.concat(others, ","), tostring(fam), tostring(secs)))
end

-- 14: kit.profile stamped and round-tripped by Snapshot / Restore
do
    local k = MD.RankMath:SpellKit()
    local valid = Kit.Validate(k)
    local snap = Kit.Snapshot(k)
    local back = Kit.Restore(snap)
    local priest = CopyKit(k)
    priest.profile = "PRIEST"
    local pSnap = Kit.Snapshot(priest)
    local pBack = Kit.Restore(pSnap)
    local bad = CopyKit(k)
    bad.profile = 7
    local badOk = Kit.Validate(bad)
    check("T96: kit.profile is stamped and round-trips through Snapshot / Restore",
        k.profile == "DRUID" and k.profile == DRUID.class and valid == true
        and snap.profile == nil and back.profile == "DRUID"
        and pSnap.profile == "PRIEST" and pBack.profile == "PRIEST" and badOk == false,
        string.format("profile=%s valid=%s snap=%s back=%s priest=%s/%s bad=%s", tostring(k.profile),
            tostring(valid), tostring(snap.profile), tostring(back.profile), tostring(pSnap.profile),
            tostring(pBack.profile), tostring(badOk)))
end

-- 15: a snapshot with no profile (every one stored before T96) restores as the
--     druid's, and the engine reads the druid's slots for it
do
    local old = { crit = 0, caster = { [774] = { family = "Rejuvenation", rank = 1, type = "hot", gcd = 1.5,
        cost = 25, cast = 0, tick = 8, ticks = 4, tickPeriod = 3, duration = 12 } }, tree = {} }
    local back = RM.KitRestore(old)
    local slots = MD.SimModel.HotSlots and MD.SimModel.HotSlots(back)
    check("T96: a snapshot without a profile restores as the druid's",
        back.profile == "DRUID" and MD.Profiles.ForKit(back) == DRUID
        and slots and slots.index.Rejuvenation == MD.SimModel.HOT_INDEX.Rejuvenation
        and slots.index.Regrowth == MD.SimModel.HOT_INDEX.Regrowth,
        string.format("profile=%s forKit=%s", tostring(back.profile),
            tostring(MD.Profiles.ForKit(back) and MD.Profiles.ForKit(back).class)))
    MD.RankMath:SpellKit()   -- the live index back (KitRestore installed the snapshot's)
end

-- 16: MD.KitLive, the Forever half of Can("coach"): the live kit prices a heal
do
    local live, n = false, nil
    if type(MD.KitLive) == "function" then live, n = MD.KitLive() end
    check("T96: MD.KitLive is provided and the live kit prices at least one heal",
        type(MD.KitLive) == "function" and live == true and type(n) == "number" and n > 0,
        string.format("provided=%s live=%s n=%s", tostring(type(MD.KitLive) == "function"),
            tostring(live), tostring(n)))
end

--------------------------------------------------------------------------------
-- T101 (docs/SPEC-next.md 4.2 P2, 4.3, 4.5): the kit is built from the book by
-- SHAPE for a class with no profile file -- a paladin, a shaman and a priest
-- log in with their level 60 books (tools/stub_books.lua, talentsforever's
-- extract of the beta client's own texts) and each book becomes a kit that
-- validates, stamped with the class, priced from the texts: `group`, `chain`
-- and `selfAndTarget` entries for the heals that reach several targets, the
-- book's own cooldowns on the entries, and the heals no type models yet
-- (absorbs, a heal on the caster alone, one only below a health line) named
-- in the skipped list instead of guessed into a type.
--------------------------------------------------------------------------------
local Books = dofile(here .. "/stub_books.lua")
local function LogIn(class)
    S.units.player.class = class
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
end

-- The class's kit, its validation, each family's highest known rank's entry,
-- the skipped names, KitLive, and the index a snapshot of it restores.
local function ClassKit(class)
    local undo = Books.Install(Books.Load(class:lower()), { alone = true, MD = MD })
    LogIn(class)
    local out = { top = {}, skipped = {} }
    local built, k = pcall(function() return MD.RankMath:SpellKit() end)
    out.built, out.kit = built, built and k or nil
    if not built then out.err = tostring(k) end
    if built then
        out.valid, out.problems = Kit.Validate(k)
        for fam, id in pairs(MD.SpellData.maxRank or {}) do out.top[fam] = k.caster[id] end
        for _, name in ipairs(MD.SpellData.skipped or {}) do out.skipped[name] = true end
        out.labels = {}
        for fam, def in pairs(MD.SpellData.families or {}) do out.labels[fam] = def.label end
        if type(MD.KitLive) == "function" then out.live, out.liveN = MD.KitLive() end
        local snap = Kit.Snapshot(k)
        out.snapProfile = snap.profile
        local back = RM.KitRestore(snap)
        out.backProfile = back.profile
        out.restored = {}
        for fam, def in pairs(MD.SpellData.families or {}) do out.restored[fam] = def.type end
    end
    undo()
    LogIn("DRUID")
    MD.RankMath:SpellKit()
    return out
end
local function Is(e, t) return type(e) == "table" and e.type == t and not e.dataMissing end

-- 17: a paladin
do
    local c = ClassKit("PALADIN")
    local hl, fl, hs = c.top.HolyLight, c.top.FlashOfLight, c.top.HolyShock
    check("T101: a paladin's book becomes a valid kit",
        c.built and c.valid and c.kit.profile == "PALADIN"
        and Is(hl, "direct") and hl.direct == 1580 and hl.cast == 2.5 and hl.castBase == 2.5
        and Is(fl, "direct") and Is(hs, "direct") and hs.cooldown == 10 and hl.cooldown == nil
        and c.top.LightsVigil == nil and c.labels.HolyLight == "Holy Light"
        and c.live == true and c.snapProfile == "PALADIN" and c.backProfile == "PALADIN"
        and c.restored.HolyLight == "direct" and c.restored.HolyShock == "direct",
        string.format("built=%s valid=%s first=%s profile=%s HL=%s FoL=%s HS cd=%s live=%s restored=%s",
            tostring(c.built), tostring(c.valid), tostring(c.err or (c.problems and c.problems[1])),
            tostring(c.kit and c.kit.profile), tostring(hl and hl.direct), tostring(fl and fl.type),
            tostring(hs and hs.cooldown), tostring(c.live), tostring(c.restored and c.restored.HolyLight)))
end

-- 18: a shaman -- Chain Heal a chain of three at 50 %, Riptide's 6 s cooldown
do
    local c = ClassKit("SHAMAN")
    local ch, rt, hw = c.top.ChainHeal, c.top.Riptide, c.top.HealingWave
    check("T101: a shaman's book becomes a valid kit",
        c.built and c.valid and c.kit.profile == "SHAMAN"
        and Is(ch, "chain") and ch.direct == 506 and ch.jumps == 2 and ch.falloff == 0.5 and ch.castBase == 2.5
        and Is(rt, "hybrid") and rt.cooldown == 6 and rt.direct == 841 and rt.ticks == 5 and rt.tickPeriod == 3
        and Is(hw, "direct") and Is(c.top.LesserHealingWave, "direct") and c.live == true
        and c.restored.ChainHeal == "chain",
        string.format("built=%s valid=%s first=%s chain=%s/%s/%s riptide=%s/%s hw=%s",
            tostring(c.built), tostring(c.valid), tostring(c.err or (c.problems and c.problems[1])),
            tostring(ch and ch.type), tostring(ch and ch.jumps), tostring(ch and ch.falloff),
            tostring(rt and rt.type), tostring(rt and rt.cooldown), tostring(hw and hw.type)))
end

-- 19: a priest -- Prayer of Healing and Holy Nova `group`, Binding Heal
--     `selfAndTarget`; the shield, Desperate Prayer (the caster alone), Divine
--     Grace (below 50 % only) and Contingency Plan skipped by name
do
    local c = ClassKit("PRIEST")
    local poh, nova, bind, renew = c.top.PrayerOfHealing, c.top.HolyNova, c.top.BindingHeal, c.top.Renew
    check("T101: a priest's book becomes a valid kit",
        c.built and c.valid and c.kit.profile == "PRIEST"
        and Is(poh, "group") and poh.direct == 649 and poh.castBase == 3
        and Is(nova, "group") and nova.direct == 311
        and Is(bind, "selfAndTarget") and bind.direct == 841
        and Is(renew, "hot") and renew.ticks == 5 and renew.tickPeriod == 3
        and Is(c.top.GreaterHeal, "direct")
        and c.skipped["Power Word: Shield"] and c.skipped["Desperate Prayer"] and c.skipped["Divine Grace"]
        and c.skipped["Contingency Plan"] and c.top.PowerWordShield == nil
        and c.snapProfile == "PRIEST" and c.restored.PrayerOfHealing == "group",
        string.format("built=%s valid=%s first=%s poh=%s/%s nova=%s bind=%s renew=%s skipped=%s",
            tostring(c.built), tostring(c.valid), tostring(c.err or (c.problems and c.problems[1])),
            tostring(poh and poh.type), tostring(poh and poh.direct), tostring(nova and nova.type),
            tostring(bind and bind.type), tostring(renew and renew.type),
            tostring(c.skipped["Power Word: Shield"])))
end

Footer()
