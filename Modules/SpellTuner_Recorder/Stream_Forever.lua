-- T66 (P22, review A18): the v3 stream's constants, once. The Forever recorder
-- (Recorder_Forever.lua, this module) writes a v3 stream with these numbers;
-- the Replay module (Scenario_Forever.lua, Gates_Forever.lua) and the shared
-- review commands (Engine/ReviewCommands.lua) read it with the same ones. They
-- were hand-copied into four files before, each saying why it could not read
-- another module's locals: this file is listed first by the Recorder module's
-- TOCs, and the Replay module depends on the Recorder module, so every reader
-- finds MD.StreamV3 already published. Pure: no client call.
--
-- The kinds a v3 stream shares with the engine's own recorded kinds keep
-- SM.K's numbers (Engine/SimModel.lua: DMG 1, OWNCAST 3, CASTSTART 6, CANCEL 7,
-- DIED 9) -- Engine/SimModel.lua's SM.DangerHitFromOthers reads a v3 stream's
-- damage by SM.K.DMG. HEAL (15) is v3's own: a heal of unknown source, which
-- the scenario turns into nothing (own) or an SM.K.FHEAL (foreign) and which
-- must never equal any SM.K value -- the Replay module asserts both at load
-- (Scenario_Forever.lua).
local _, MD = ...

MD.StreamV3 = {
    -- the stream's own version number, `rec.v`
    V = 3,

    -- event kinds, `rec.ev.kind[i]` -- never renumbered: they are persisted
    K = { DMG = 1, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9, HEAL = 15 },

    -- the book's own English family name -> the engine's family key (the
    -- names `rec.initial.known` is keyed by). Only Healing Touch differs.
    -- T89 (docs/SPEC-next.md 2.1): the druid profile's names
    -- (Data/Profile_Druid_Forever.lua), derived at file load BY NAME -- never
    -- from MD.ClassProfile, the logged-in player's. Equal to the constant it
    -- replaced (tools/profilecheck.lua): Healing Touch -> HealingTouch,
    -- Regrowth, Rejuvenation, Swiftmend, Tranquility -> themselves.
    FAMILY_KEY = MD.Profiles.Require("DRUID", "Stream_Forever.lua"):FamilyKeys(),
}
