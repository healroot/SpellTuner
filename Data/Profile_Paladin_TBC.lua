-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the paladin's profile on the
-- TBC line -- the rank table and the spell tooltip only. The TBC coach stays
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
    caps = { clock = true, tooltip = true, rankTable = true },
    families = {
        HolyLight    = { names = { "Holy Light" },     kit = "direct" },
        FlashOfLight = { names = { "Flash of Light" }, kit = "direct" },
        HolyShock    = { names = { "Holy Shock" },     kit = "direct" },
    },
    order = { "HolyLight", "FlashOfLight", "HolyShock" },
    hotSlots = {},
    unmodelled = { "Lay on Hands", "Divine Favor" },
})
