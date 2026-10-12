-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the paladin's profile on the
-- TBC line -- for the rank table and the spell tooltip (granted by T123,
-- with the class's damage spells), practice (2026-10-11, on the class's own
-- kit) and, since T130 (2026-10-12, the author: "make all features available
-- for all classes"), the coach, Simulate and the advisor on the same kit. The
-- coach is solver only: the planner names families and no threshold rules
-- (those are the druid's tactics, docs/SPEC-next.md 4.2 P2), as on Forever.
--
-- Names and kit types only -- never a spell number. Every number comes from
-- the client's own text (Spells/Book_TBC.lua through Spells/Parse.lua; Holy
-- Shock's heal half of its either-or sentence, its cooldown from the
-- tooltip's own line), and the TBC rules -- coefficients by shape, the
-- downrank penalty, the paladin's talents -- are Engine/RankMath.lua's
-- RankMath.CLASS_RULES, every one VERIFY.
--
-- Not a family, so not on the rank table: Lay on Hands (its amount is the
-- paladin's whole mana), Divine Favor (a next-cast modifier). Illumination's
-- mana back on a crit is not modelled (the cost is the client's).
local _, ST = ...

ST.Profiles.Register("PALADIN", {
    label = "Paladin",
    critSchool = 2,                -- Holy (GetSpellCritChance's school; VERIFY)
    -- T123: the rank table and the tooltip, now that every TBC reader of
    -- Data/SpellData.lua reads RankMath:Source() (docs/tasks/T123-tbc-classes-damage.md)
    -- 2026-10-11 (the author): practice for every class, on the class's own
    -- kit (Engine/RankMath.lua's ClassKit over this book)
    -- T130 (2026-10-12): coach, simulate and advisor, on the same kit
    caps = { clock = true, rankTable = true, tooltip = true, practice = true,
             coach = true, simulate = true, advisor = true },
    families = {
        HolyLight    = { names = { "Holy Light" },     kit = "direct" },
        FlashOfLight = { names = { "Flash of Light" }, kit = "direct" },
        HolyShock    = { names = { "Holy Shock" },     kit = "direct" },
    },
    order = { "HolyLight", "FlashOfLight", "HolyShock" },
    hotSlots = {},
    -- T130: the solver's candidate families, in Forever's order; no `rules`,
    -- so solver only
    planner = {
        families = { "HolyShock", "FlashOfLight", "HolyLight" },
    },
    unmodelled = { "Lay on Hands", "Divine Favor" },
    -- T123: the damage spells Engine/DamageMath.lua values from each rank's
    -- own tooltip text, by the spellbook's name: the school (Holy 2), the
    -- coefficient's shape and cast, the tick (every one VERIFY; no talent of
    -- the class is modelled on them, and the tooltip says so). Holy Shock's
    -- damage half stays part of its heal family.
    damage = {
        ["Exorcism"]     = { school = 2, kind = "direct", baseCast = 1.5 },
        ["Holy Wrath"]   = { school = 2, kind = "direct", baseCast = 2.0, aoe = true },
        ["Consecration"] = { school = 2, kind = "dot",    baseCast = 1.5, tick = 1, aoe = true },
    },
    damageOrder = { "Exorcism", "Holy Wrath", "Consecration" },
    -- T130b (review M1): the class's other casts by the spellbook's name, so
    -- the spend-coverage gate knows what the mana went on (Data/DruidSpells.lua's
    -- DS.ClassKind). Every row VERIFY: a wrong row costs a label, never a
    -- number -- the cast's cost comes from the recording either way.
    castKinds = {
        ["Cleanse"] = "utility", ["Purify"] = "utility", ["Redemption"] = "utility",
        ["Judgement"] = "utility", ["Seal of Light"] = "utility", ["Seal of Wisdom"] = "utility",
        ["Seal of Righteousness"] = "utility", ["Seal of Command"] = "utility",
        ["Seal of Justice"] = "utility", ["Seal of the Crusader"] = "utility",
        ["Seal of Vengeance"] = "utility", ["Seal of Blood"] = "utility",
        ["Blessing of Wisdom"] = "utility", ["Blessing of Kings"] = "utility",
        ["Blessing of Might"] = "utility", ["Blessing of Light"] = "utility",
        ["Blessing of Salvation"] = "utility", ["Blessing of Sanctuary"] = "utility",
        ["Greater Blessing of Wisdom"] = "utility", ["Greater Blessing of Kings"] = "utility",
        ["Greater Blessing of Might"] = "utility", ["Greater Blessing of Light"] = "utility",
        ["Greater Blessing of Salvation"] = "utility", ["Greater Blessing of Sanctuary"] = "utility",
        ["Blessing of Freedom"] = "utility", ["Blessing of Protection"] = "utility",
        ["Blessing of Sacrifice"] = "utility", ["Divine Shield"] = "utility",
        ["Divine Protection"] = "utility", ["Divine Intervention"] = "utility",
        ["Righteous Fury"] = "utility", ["Holy Shield"] = "utility", ["Avenging Wrath"] = "utility",
        ["Divine Illumination"] = "utility",
        ["Hammer of Wrath"] = "damage", ["Avenger's Shield"] = "damage",
        ["Crusader Strike"] = "damage",
        ["Hammer of Justice"] = "cc", ["Repentance"] = "cc", ["Turn Undead"] = "cc",
        ["Turn Evil"] = "cc",
    },
})
