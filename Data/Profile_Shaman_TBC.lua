-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the shaman's profile on the
-- TBC line -- for the rank table and the spell tooltip (granted by T123,
-- with the class's damage spells). The TBC coach stays
-- the druid's (decision 8): no `coach`, `simulate` or `advisor` (practice,
-- 2026-10-11, on the class's own kit),
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
local _, ST = ...

ST.Profiles.Register("SHAMAN", {
    label = "Shaman",
    critSchool = 4,                -- Nature (GetSpellCritChance's school; VERIFY)
    -- T123: the rank table and the tooltip, now that every TBC reader of
    -- Data/SpellData.lua reads RankMath:Source() (docs/tasks/T123-tbc-classes-damage.md)
    -- 2026-10-11 (the author): practice for every class, on the class's own
    -- kit (Engine/RankMath.lua's ClassKit over this book)
    caps = { clock = true, rankTable = true, tooltip = true, practice = true },
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
    -- T123: the damage spells Engine/DamageMath.lua values from each rank's
    -- own tooltip text, by the spellbook's name: the school (Fire 3, Nature
    -- 4, Frost 5), the coefficient's shape and cast, the tick (every one
    -- VERIFY; no talent of the class is modelled on them, and the tooltip
    -- says so). Chain Lightning's value is its first target's; Flame Shock's
    -- hit is the text's "N Fire damage immediately".
    damage = {
        ["Lightning Bolt"]  = { school = 4, kind = "direct", baseCast = 3.0 },
        ["Chain Lightning"] = { school = 4, kind = "direct", baseCast = 2.5 },
        ["Earth Shock"]     = { school = 4, kind = "direct", baseCast = 1.5 },
        ["Flame Shock"]     = { school = 3, kind = "hybrid", baseCast = 1.5, tick = 3 },
        ["Frost Shock"]     = { school = 5, kind = "direct", baseCast = 1.5 },
    },
    damageOrder = { "Lightning Bolt", "Chain Lightning", "Earth Shock", "Flame Shock", "Frost Shock" },
})
