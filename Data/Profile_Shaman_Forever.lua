-- T106 (docs/SPEC-next.md 4.3, section 11): the shaman's profile on the
-- Forever line -- the second class after the druid to be coached (decision 7:
-- Paladin -> Shaman -> Priest). It adds the `chain` kit type (Chain Heal,
-- T101) to what the engine models.
--
-- Names, kit types and rule choices only -- never a spell number: every number
-- comes from the client's own text through Spells/Book.lua (the heal, the
-- cost, the cast, Chain Heal's jumps and falloff from its text, Riptide's 6 s
-- cooldown from its tooltip line, T95). The names are the spellbook's own
-- English names (build 70009; tools/profilecheck.lua checks them against the
-- talentsforever export when its cache is present). The families named here
-- are the ones the Replay module's Kit_Forever.lua would build from the book
-- by shape anyway (T101); naming them fixes their keys, their order, their kit
-- types and Riptide's HoT slot.
--
-- Every rule below is VERIFY (docs/SPEC-next.md 3 principle 9 and 4.5):
-- nothing here has been measured on a Forever shaman yet -- docs/TESTING.md
-- in-game check 11 is the measurement (gate 8 says whether Chain Heal's heals
-- were attributed; /st measure gives Riptide's tick period).
--
-- Not a family, so not modelled -- listed as `unmodelled`, which the coach
-- card names when a fight casts one (each kept exactly as recorded,
-- Scenario_Forever.lua, T101 -- never guessed into a type):
--   * Healing Stream Totem -- a totem's ticks, not the caster's decision per
--     heal (docs/SPEC-next.md 3 principle 8);
--   * Nature's Swiftness -- a next-cast modifier.
-- (Mana Spring Totem, Mana Tide Totem and Water Shield are mana, not heals:
-- T105's sources, not listed.)
local _, MD = ...

MD.Profiles.Register("SHAMAN", {
    label = "Shaman",
    critSchool = 4,                -- Nature (VERIFY: Forever merges crit; the probe reads one value)
    -- The druid's Forever capabilities, less `simulate` (the TBC Simulate
    -- window; nothing on the Forever TOCs asks for it): coach and practice
    -- are granted because tools/classcoach.lua passes on this class's book
    -- (docs/SPEC-next.md 4.3); on Forever `coach` also asks MD.KitLive.
    caps = { clock = true, tooltip = true, rankTable = true, coach = true, practice = true },
    families = {
        -- single-target direct heals
        HealingWave       = { names = { "Healing Wave" },        kit = "direct" },
        LesserHealingWave = { names = { "Lesser Healing Wave" }, kit = "direct" },
        -- its target, then the most injured party members at the cast at the
        -- text's falloff (1, 0.5, 0.25): 4.5's assumption, optimistic, VERIFY
        -- -- no positions are recorded, and the client's own jump rule is not
        -- known; the coach card says so (SP.GROUP_ASSUMPTION)
        ChainHeal         = { names = { "Chain Heal" },          kit = "chain" },
        -- a direct heal and a HoT; ticks every 3 s (VERIFY: the text gives the
        -- total and the duration only), 6 s cooldown from its tooltip line
        Riptide           = { names = { "Riptide" },             kit = "hybrid", hot = true },
    },
    -- The dashboard order (MD.SpellData.familyOrder).
    order = { "HealingWave", "LesserHealingWave", "ChainHeal", "Riptide" },
    -- Riptide's HoT in slot 1 (the engine's per-target HoT slots).
    hotSlots = { "Riptide" },
    -- Solver only (no `rules`: the threshold rules are the druid's tactics,
    -- docs/SPEC-next.md 4.2 P2); the candidates in this order (order decides
    -- only ties -- Engine/SimSolver.lua scores every one).
    planner = {
        families = { "Riptide", "ChainHeal", "LesserHealingWave", "HealingWave" },
    },
    unmodelled = { "Healing Stream Totem", "Nature's Swiftness" },
})
