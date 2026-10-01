-- T89 (docs/SPEC-next.md 2.1, S1 step 1): the druid's profile on the Forever line.
--
-- Names, kit types and rule choices only -- never a spell number: on Forever
-- every number comes from the client's own text through Spells/Book.lua. The
-- names are the spellbook's own English names (build 70009; the talentsforever
-- export carries every one of them, tools/profilecheck.lua checks that when its
-- cache is present). Forever has no Lifebloom and no Tree of Life, so neither
-- is a family here.
--
-- What derives from it at file load, by name (MD.Profiles.Require("DRUID")):
-- the Replay module's Kit_Forever.lua (FAMILY_KEY, FAMILY_TYPE, the excluded
-- families, the dashboard order, the crit school) and the Recorder module's
-- Stream_Forever.lua (MD.StreamV3.FAMILY_KEY), and Engine/SimPlanner.lua's
-- SP.BINDABLE and SP.HOT_RULE. Each derived table equals the constant it
-- replaced (tools/profilecheck.lua).
local _, MD = ...

-- What this line grants EVERY class, druid or not: Spells/Book.lua reads any
-- spellbook, so the tooltip block and the rank table already work for a class
-- with no profile of its own (docs/SPEC-next.md 2.1, the generic profile).
MD.Profiles.LineCaps({ tooltip = true, rankTable = true })

MD.Profiles.Register("DRUID", {
    label = "Druid",
    critSchool = 4,                -- Nature
    -- What a druid gets on this line today (the Replay and Practice modules
    -- decide whether the last three are switched on).
    caps = { clock = true, tooltip = true, rankTable = true,
             simulate = true, coach = true, practice = true },
    families = {
        HealingTouch = { names = { "Healing Touch" }, kit = "direct" },
        Regrowth     = { names = { "Regrowth" },      kit = "hybrid", hot = true },
        Rejuvenation = { names = { "Rejuvenation" },  kit = "hot",    hot = true },
        -- Swiftmend's own text parses to nothing; Kit_Forever values it off the
        -- HoTs it eats. Its 15 s cooldown is SM.SPELL_CD's.
        Swiftmend    = { names = { "Swiftmend" },     kit = "instant",
                         eats = { "Regrowth", "Rejuvenation" }, cooldown = 15 },
        -- In the kit, not in the engine's plans (as on TBC).
        Tranquility  = { names = { "Tranquility" },   kit = "channel", exclude = true },
    },
    -- The engine's own dashboard order (Kit_Forever's MD.SpellData.familyOrder).
    order = { "HealingTouch", "Rejuvenation", "Regrowth" },
    -- SM.HOT_INDEX's slots for the HoTs this line has, keeping their numbers.
    hotSlots = { "Rejuvenation", "Regrowth" },
    -- The threshold rules' own lists (Engine/SimPlanner.lua, Engine/SimSolver.lua):
    -- one strategy on both lines, written for the TBC druid. Lifebloom is in them
    -- although this line has no such family -- every rule skips a family the kit
    -- does not carry, as it always has.
    planner = {
        rules = "druid",
        bindable = { "Lifebloom", "Rejuvenation", "Regrowth", "HealingTouch", "Swiftmend" },
        hotRule = { "Lifebloom", "Rejuvenation" },
        families = { "Swiftmend", "Regrowth", "HealingTouch", "Lifebloom", "Rejuvenation" },
    },
})
