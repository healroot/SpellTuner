-- T89 (docs/SPEC-next.md 2.1, S1 step 1): the druid's profile on the TBC line.
--
-- Names, kit types and rule choices only. The numbers stay where they were
-- verified: Data/SpellData.lua (spell values, costs, the alias ids), which this
-- file only mirrors -- each family below is one of SD.families with its label
-- as the name, SD's `type` as the kit type and SD's `exclude` mark, and `order`
-- is SD.familyOrder; tools/profilecheck.lua holds the two together. This file
-- is listed before Data/SpellData.lua (right after the flavour core), so it
-- reads nothing from it.
--
-- What derives from it at file load, by name (MD.Profiles.Require("DRUID")):
-- Engine/SimPlanner.lua's SP.BINDABLE and SP.HOT_RULE, Engine/ManaCooldowns.lua's
-- MC.byClass.DRUID, Engine/RegenModel.lua's in-5SR talent row for DRUID. Each
-- derived table equals the constant it replaced (tools/profilecheck.lua).
local _, MD = ...

MD.Profiles.Register("DRUID", {
    label = "Druid",
    critSchool = 4,                -- Nature
    -- What a druid gets on this line today (the isDruid gates, task T99).
    caps = { clock = true, tooltip = true, rankTable = true, advisor = true,
             simulate = true, coach = true, practice = true },
    families = {
        HealingTouch = { names = { "Healing Touch" }, kit = "direct" },
        Regrowth     = { names = { "Regrowth" },      kit = "hybrid", hot = true },
        Rejuvenation = { names = { "Rejuvenation" },  kit = "hot",    hot = true },
        Lifebloom    = { names = { "Lifebloom" },     kit = "lifebloom", hot = true },
        -- Swiftmend eats Regrowth first, then Rejuvenation (SM.SWIFTMEND_ORDER),
        -- and has a 15 s cooldown of its own (SM.SPELL_CD[18562]).
        Swiftmend    = { names = { "Swiftmend" },     kit = "instant", exclude = true,
                         eats = { "Regrowth", "Rejuvenation" }, cooldown = 15 },
        Tranquility  = { names = { "Tranquility" },   kit = "channel", exclude = true },
    },
    -- Data/SpellData.lua's familyOrder: the dashboard's rows.
    order = { "HealingTouch", "Lifebloom", "Rejuvenation", "Regrowth" },
    -- SM.HOT_INDEX in THIS order, so every trace keeps its slot numbers.
    hotSlots = { "Rejuvenation", "Regrowth", "Lifebloom" },
    -- The threshold rules are the druid's strategy (Engine/SimPlanner.lua);
    -- the lists in their order. Tranquility is never bindable: the spell table
    -- carries no heal value for it, so no plan spends mana on an unmeasured
    -- number. Regrowth belongs to rule 2 and Swiftmend consumes a HoT, so
    -- neither is a rule-4 HoT.
    planner = {
        rules = "druid",
        bindable = { "Lifebloom", "Rejuvenation", "Regrowth", "HealingTouch", "Swiftmend" },
        hotRule = { "Lifebloom", "Rejuvenation" },
        families = { "Swiftmend", "Regrowth", "HealingTouch", "Lifebloom", "Rejuvenation" },
    },
    -- Engine/ManaCooldowns.lua resolves `value` to its own value model.
    manaCooldowns = {
        { key = "innervate", short = "inn", id = 29166, name = "Innervate",
          duration = 20, value = "innervate" },
    },
    -- Intensity lets 10% per rank of spirit regen continue while casting.
    regen = { inFsrTalent = { "Intensity", 0.10 } },
})
