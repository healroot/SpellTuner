-- T16a (docs/tasks/T16a-replay-window.md): the Replay module's own command
-- and the settings the window and the engine read that Core_Forever.lua's own
-- MD.DEFAULTS never carried.
--
-- T65 (P21, review A1): /st validate and /st coach, and MD:ValidationReport
-- and MD:RunCoach behind them, are the shared ones now --
-- Engine/ReviewCommands.lua, listed by this module's TOCs right after this
-- file (so /st help keeps replay, validate, coach in that order); this file
-- provides the Forever half of its policy (MD.ReviewPolicy). The
-- defaults are declared through MD:RegisterDefaults (Core.lua): this module
-- loads after InitDB ran, so they back-fill MD.db at once, never over a value
-- the player already has, and a second owner declaring one of them with a
-- different value raises instead of drifting. Runs only once this module is
-- on -- this file is that module's own TOC entry. /st rec stays in
-- Modules/SpellTuner_Recorder/Recorder_Forever.lua.
local _, MD = ...

MD:RegisterDefaults({
    replaySpeed = 1, replayTicks = true, replayNextPull = true, replayAutoCoach = true,
    -- The sim* values Engine/SimModel.lua, Engine/SimPlanner.lua and
    -- Gates_Forever.lua read (Core_TBC.lua's own DEFAULTS, the same values),
    -- declared for the settings pane, which reads MD.db directly.
    simFullHp = 0.85, simFloor = 0.30, simDangerHits = 1, simReaction = 0.5, simMinActivity = 0,
    simGateManaMean = 0.02, simGateManaMax = 0.05, simGateHpMean = 0.05, simGateHpMax = 0.15,
    simForeignShare = 0.25, simAllowRebinds = false, simBigHit = 0.15,
})

-- The review policy Engine/ReviewCommands.lua reads (its TBC value is that
-- file's default): the card to chat only, /st validate as the report's verb,
-- /st in every hint. Provided here, before that file runs.
MD:Provide("ReviewPolicy", { copyBox = false, reportVerb = "validate", slash = "/st" })

-- tools/replayforever.lua's name for the report: a plain two-argument
-- function (MD:ValidationReport is a method; see Engine/ReviewCommands.lua).
MD.ValidationReportForever = function(rec, n) return MD:ValidationReport(rec, n) end

MD:AddCommand("replay", function(arg)
    if MD.ToggleReplay then MD:ToggleReplay(arg) end
end, "/st replay [n] [force]",
    "play recorded fight n as unit frames; force: draw the suggested column on a fight that does not replay")
