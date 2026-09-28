-- Forever's own core (T1b of docs/ROADMAP-FOREVER.md): the defaults the
-- kernel's login debug line reads and the first two commands. The window
-- itself arrives in T2 -- until then "/st" just shows the command list.
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
}

MD:AddCommand("", function()
    if MD.ToggleDashboard then
        MD:ToggleDashboard()
    else
        MD:ShowCommands()
    end
end, "/st", "open the SpellTuner window")

MD:AddCommand("help", function() MD:ShowCommands() end, "/st help", "this list")
