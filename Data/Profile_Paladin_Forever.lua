-- T106 (docs/SPEC-next.md 4.3, section 11): the paladin's profile on the
-- Forever line -- the first class after the druid to be coached (decision 7:
-- Paladin -> Shaman -> Priest), because its healing is direct heals plus one
-- cooldown: nothing the engine did not already model.
--
-- Names, kit types and rule choices only -- never a spell number: every number
-- comes from the client's own text through Spells/Book.lua (the heal, the
-- cost, the cast, and Holy Shock's 10 s cooldown from its tooltip line, T95).
-- The names are the spellbook's own English names (build 70009;
-- tools/profilecheck.lua checks them against the talentsforever export when
-- its cache is present). The families named here are the ones the Replay
-- module's Kit_Forever.lua would build from the book by shape anyway (T101);
-- naming them fixes their keys, their order and their kit types, so a later
-- reading change cannot silently move them.
--
-- Every rule below is VERIFY (docs/SPEC-next.md 3 principle 9): nothing here
-- has been measured on a Forever paladin yet -- docs/TESTING.md in-game
-- check 11 is the measurement.
--
-- Not a family, so not modelled -- listed as `unmodelled`, which the coach
-- card names when a fight casts one (each kept exactly as recorded,
-- Scenario_Forever.lua, T101 -- never guessed into a type):
--   * Light's Vigil -- a buff on the next Holy Shock ("Your next Holy Shock
--     ... heals their party"), not a heal of its own (the parser refuses it,
--     T91). Its other effect, that Holy Shock then triggers no cooldown, is
--     not modelled: a plan keeps Holy Shock's 10 s (pessimistic), a recorded
--     Holy Shock inside it is replayed as recorded (T90; docs/SPEC-next.md
--     10, X9).
--   * Lay on Hands -- its amount is the caster's maximum health, which the
--     text does not state.
--   * Divine Favor -- a next-cast modifier (a crit), not a heal.
--   * Blessing of Light -- a TARGET-side bonus, not in the caster's text.
local _, MD = ...

MD.Profiles.Register("PALADIN", {
    label = "Paladin",
    critSchool = 2,                -- Holy (VERIFY: Forever merges crit; the probe reads one value)
    -- The druid's Forever capabilities, less `simulate` (the TBC Simulate
    -- window; nothing on the Forever TOCs asks for it): coach and practice
    -- are granted because tools/classcoach.lua passes on this class's book
    -- (docs/SPEC-next.md 4.3); on Forever `coach` also asks MD.KitLive, so a
    -- book whose kit prices no heal is still refused, by the kit.
    caps = { clock = true, tooltip = true, rankTable = true, coach = true, practice = true },
    families = {
        -- single-target direct heals (VERIFY: the crit expectation is the
        -- engine's 1.5x, as the druid's)
        HolyLight    = { names = { "Holy Light" },     kit = "direct" },
        FlashOfLight = { names = { "Flash of Light" }, kit = "direct" },
        -- instant, with the 10 s cooldown its tooltip line carries (the book's,
        -- T95 -- not typed here); its damage half is T110's (VERIFY)
        HolyShock    = { names = { "Holy Shock" },     kit = "direct" },
    },
    -- The dashboard order (MD.SpellData.familyOrder): the big heal first.
    order = { "HolyLight", "FlashOfLight", "HolyShock" },
    -- No paladin heal leaves a HoT.
    hotSlots = {},
    -- Solver only (no `rules`: the threshold rules are the druid's tactics,
    -- docs/SPEC-next.md 4.2 P2); the candidates in this order (order decides
    -- only ties -- Engine/SimSolver.lua scores every one).
    planner = {
        families = { "HolyShock", "FlashOfLight", "HolyLight" },
    },
    unmodelled = { "Light's Vigil", "Lay on Hands", "Divine Favor" },
})
