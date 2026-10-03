-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the paladin's profile on the
-- TBC line -- for the rank table and the spell tooltip (granted by T123,
-- with the class's damage spells). The TBC coach stays
-- the druid's (decision 8): no `coach`, `practice`, `simulate` or `advisor`,
-- and no planner.
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
local _, MD = ...

MD.Profiles.Register("PALADIN", {
    label = "Paladin",
    critSchool = 2,                -- Holy (GetSpellCritChance's school; VERIFY)
    -- T123: the rank table and the tooltip, now that every TBC reader of
    -- Data/SpellData.lua reads RankMath:Source() (docs/tasks/T123-tbc-classes-damage.md)
    caps = { clock = true, rankTable = true, tooltip = true },
    families = {
        HolyLight    = { names = { "Holy Light" },     kit = "direct" },
        FlashOfLight = { names = { "Flash of Light" }, kit = "direct" },
        HolyShock    = { names = { "Holy Shock" },     kit = "direct" },
    },
    order = { "HolyLight", "FlashOfLight", "HolyShock" },
    hotSlots = {},
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
})
