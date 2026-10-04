-- T16a (docs/tasks/T16a-replay-window.md): the Replay module's own command.
--
-- T65 (P21, review A1): /st validate and /st coach, and ST:ValidationReport
-- and ST:RunCoach behind them, are the shared ones now --
-- Engine/ReviewCommands.lua, listed by this module's TOCs right after this
-- file (so /st help keeps replay, validate, coach in that order); this file
-- provides the Forever half of its policy (ST.ReviewPolicy). The settings the
-- window and the engine read are declared once, by Engine/SimModel.lua (T64,
-- P20: ST:RegisterDefaults; this module loads it before this file), and the
-- two v3 gate thresholds by Gates_Forever.lua -- this file declares none
-- (wave 8's merge: the REPLAY_DEFAULTS copy it kept, every key repeating
-- SimModel.lua's value, is gone). Runs only once this module is on -- this
-- file is that module's own TOC entry. /st rec stays in
-- Modules/SpellTuner_Recorder/Recorder_Forever.lua.
local _, ST = ...

-- The review policy Engine/ReviewCommands.lua reads (its TBC value is that
-- file's default): the card to chat only, /st validate as the report's verb,
-- /st in every hint. Provided here, before that file runs.
ST:Provide("ReviewPolicy", { copyBox = false, reportVerb = "validate", slash = "/st" })

-- tools/replayforever.lua's name for the report: a plain two-argument
-- function (ST:ValidationReport is a method; see Engine/ReviewCommands.lua).
ST.ValidationReportForever = function(rec, n) return ST:ValidationReport(rec, n) end

ST:AddCommand("replay", function(arg)
    if ST.ToggleReplay then ST:ToggleReplay(arg) end
end, "/st replay [n] [force]",
    "play recorded fight n as unit frames; force: draw the suggested column on a fight that does not replay")
