-- Forever's own core (T1b/T2 of docs/ROADMAP-FOREVER.md): the defaults the
-- kernel's login debug line reads, the three LoadOnDemand sibling modules
-- (Core.lua's registry), and the first commands. UI/Dashboard_Forever.lua
-- loads after this file and gives "/st" and "/st modules" something to open.
local ADDON_NAME, MD = ...

MD.DEFAULTS = {
    debug = {
        enabled = false,  -- MD:Debug() is a no-op unless this is on
        maxLines = 1000,  -- memory ring size (Debug Console "keep lines")
        categories = { regen = true, mana = true, spend = true, tto = true,
                       heal = true, cast = true, calib = true, combat = true, chat = true,
                       sim = true, other = true },
    },
    char = {},
    modules = {},  -- name -> true|false, read/written by Core.lua's registry
}

-- The three siblings, in dependency order (each needs only what is declared
-- before it -- Core.lua's SetModule relies on that to load in the right
-- order without a topological sort of its own).
MD:DeclareModule("SpellTuner_Recorder", "Recorder", {},
    "records your fights: health, heals, casts and mana")
MD:DeclareModule("SpellTuner_Replay", "Replay", { "SpellTuner_Recorder" },
    "replays a recorded fight and coaches it")
MD:DeclareModule("SpellTuner_Practice", "Practice", { "SpellTuner_Replay" },
    "heal a fight you play, then review it")

MD:AddCommand("", function()
    if MD.ToggleDashboard then
        MD:ToggleDashboard()
    else
        MD:ShowCommands()
    end
end, "/st", "open the SpellTuner window")

MD:AddCommand("help", function() MD:ShowCommands() end, "/st help", "this list")

MD:AddCommand("modules", function()
    if MD.SelectView then
        MD:SelectView("settings", "modules")
    else
        MD:ShowCommands()
    end
end, "/st modules", "switch the Recorder, Replay and Practice modules on or off")
