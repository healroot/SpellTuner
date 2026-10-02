-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the shaman's profile on the
-- TBC line -- for the rank table and the spell tooltip only (not granted
-- yet: see `caps`). The TBC coach stays
-- the druid's (decision 8): no `coach`, `practice`, `simulate` or `advisor`,
-- and no planner.
--
-- Names and kit types only -- never a spell number. Every number comes from
-- the client's own text (Spells/Book_TBC.lua through Spells/Parse.lua; Chain
-- Heal's target count and falloff read from its own sentences), and the TBC
-- rules -- coefficients by shape, the downrank penalty, the shaman's talents --
-- are Engine/RankMath.lua's RankMath.CLASS_RULES, every one VERIFY.
--
-- Not a family, so not on the rank table: Earth Shield (a heal on a later
-- hit, with charges), Healing Stream Totem (a totem), Nature's Swiftness (a
-- next-cast modifier).
local _, MD = ...

MD.Profiles.Register("SHAMAN", {
    label = "Shaman",
    critSchool = 4,                -- Nature (GetSpellCritChance's school; VERIFY)
    -- the mana clock only, as before this file (the generic profile's).
    -- `rankTable` and `tooltip` wait until the TBC files that read
    -- Data/SpellData.lua directly read RankMath:Source() instead
    -- (UI/SpellsView_TBC.lua, UI/Dashboard.lua, UI/SpellTooltip.lua,
    -- UI/Tip_TBC.lua) and the two gates that take `rankTable` to mean
    -- Data/SpellData.lua stop doing so (UI/Summary.lua's max-rank share,
    -- Diagnostics_TBC.lua's /md profile): granted before that, the
    -- Spells view is half blank and the fight summary says
    -- `max-rank casts 0%` (docs/tasks/T111-tbc-other-classes.md).
    caps = { clock = true },
    families = {
        HealingWave       = { names = { "Healing Wave" },        kit = "direct" },
        LesserHealingWave = { names = { "Lesser Healing Wave" }, kit = "direct" },
        -- its target, then its jumps at the text's falloff; the table shows
        -- the first target's numbers (decision 12)
        ChainHeal         = { names = { "Chain Heal" },          kit = "chain" },
    },
    order = { "HealingWave", "LesserHealingWave", "ChainHeal" },
    hotSlots = {},
    unmodelled = { "Earth Shield", "Healing Stream Totem", "Nature's Swiftness" },
})
