-- T106 (docs/SPEC-next.md 4.3, section 11): the priest's profile on the
-- Forever line -- the third class after the druid to be coached (decision 7:
-- Paladin -> Shaman -> Priest). It adds the `group` and `selfAndTarget` kit
-- types (Prayer of Healing, Holy Nova, Binding Heal, T101).
--
-- **Without Power Word: Shield until T109** (docs/SPEC-next.md 4.2 P3, 4.3):
-- the engine has no absorb, so a priest is coached without shields. The
-- shield is not named here, the kit skips it by name (an absorb), and a fight
-- that casts one replays it as recorded; the cast's mana is the healer's, the
-- damage it soaked never reached the recording.
--
-- Names, kit types and rule choices only -- never a spell number: every number
-- comes from the client's own text through Spells/Book.lua. The names are the
-- spellbook's own English names (build 70009; tools/profilecheck.lua checks
-- them against the talentsforever export when its cache is present). The
-- families named here are the ones the Replay module's Kit_Forever.lua would
-- build from the book by shape anyway (T101); naming them fixes their keys,
-- their order, their kit types and Renew's HoT slot.
--
-- Every rule below is VERIFY (docs/SPEC-next.md 3 principle 9 and 4.5):
-- nothing here has been measured on a Forever priest yet -- docs/TESTING.md
-- in-game check 11 is the measurement (gate 8 says whether Prayer of Healing's
-- heals were attributed; /st measure gives Renew's tick period).
--
-- Not a family, so not modelled -- listed as `unmodelled`, which the coach
-- card names when a fight casts one (each kept exactly as recorded,
-- Scenario_Forever.lua, T101 -- never guessed into a type; the kit also skips
-- the first four by name, MD.SpellData.skipped):
--   * Power Word: Shield, Contingency Plan -- absorbs (T109);
--   * Desperate Prayer -- heals the caster alone;
--   * Divine Grace -- heals only a target below a health line;
--   * Penance, Prayer of Mending, Lightwell, Vampiric Embrace -- refused by
--     the parser, or heals the plan cannot choose (docs/SPEC-next.md 3
--     principle 8);
--   * Inner Focus, Power Infusion -- next-cast modifiers.
local _, MD = ...

MD.Profiles.Register("PRIEST", {
    label = "Priest",
    critSchool = 2,                -- Holy (VERIFY: Forever merges crit; the probe reads one value)
    -- The druid's Forever capabilities, less `simulate` (the TBC Simulate
    -- window; nothing on the Forever TOCs asks for it): coach and practice
    -- are granted because tools/classcoach.lua passes on this class's book
    -- (docs/SPEC-next.md 4.3); on Forever `coach` also asks MD.KitLive.
    caps = { clock = true, tooltip = true, rankTable = true, coach = true, practice = true },
    families = {
        -- single-target direct heals
        LesserHeal      = { names = { "Lesser Heal" },       kit = "direct" },
        Heal            = { names = { "Heal" },              kit = "direct" },
        GreaterHeal     = { names = { "Greater Heal" },      kit = "direct" },
        FlashHeal       = { names = { "Flash Heal" },        kit = "direct" },
        -- a HoT; ticks every 3 s (VERIFY: the text gives the total and the
        -- duration only)
        Renew           = { names = { "Renew" },             kit = "hot", hot = true },
        -- every living tracked member of the caster's party, each healed by
        -- the text's amount: 4.5's assumption, optimistic, VERIFY -- no
        -- positions are recorded, and Holy Nova's 10 yd is read as "all of
        -- them"; the coach card says so (SP.GROUP_ASSUMPTION). Holy Nova's
        -- damage half is T110's.
        PrayerOfHealing = { names = { "Prayer of Healing" }, kit = "group" },
        HolyNova        = { names = { "Holy Nova" },         kit = "group" },
        -- the target and the caster (4.5; VERIFY)
        BindingHeal     = { names = { "Binding Heal" },      kit = "selfAndTarget" },
    },
    -- The dashboard order (MD.SpellData.familyOrder).
    order = { "GreaterHeal", "Heal", "FlashHeal", "LesserHeal", "Renew",
              "PrayerOfHealing", "BindingHeal", "HolyNova" },
    -- Renew's HoT in slot 1 (the engine's per-target HoT slots).
    hotSlots = { "Renew" },
    -- Solver only (no `rules`: the threshold rules are the druid's tactics,
    -- docs/SPEC-next.md 4.2 P2); the candidates in this order (order decides
    -- only ties -- Engine/SimSolver.lua scores every one).
    planner = {
        families = { "Renew", "FlashHeal", "GreaterHeal", "Heal", "LesserHeal",
                     "PrayerOfHealing", "BindingHeal", "HolyNova" },
    },
    unmodelled = { "Power Word: Shield", "Contingency Plan", "Desperate Prayer", "Divine Grace",
                   "Penance", "Prayer of Mending", "Lightwell", "Vampiric Embrace",
                   "Inner Focus", "Power Infusion" },
})
