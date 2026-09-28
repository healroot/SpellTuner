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

--------------------------------------------------------------------------------
-- The SavedVariables guard (T4): before anything else touches SpellTunerDB,
-- record whether it came back -- a table from an earlier session (and which),
-- nothing (a first run, or a file the client lost), or a value that is not a
-- table (a broken file, replaced by an empty one rather than indexed). Q7
-- (docs/tasks/T4-savedvariables-guard.md) found SavedVariables do come back on
-- build 70009, so this is the minimal guard: no seed workaround.
-- Fires once, on the first ADDON_LOADED for this addon's own name -- Core.lua
-- creates its event frame before Client/Probe.lua creates its own, and this
-- handler is added before Core_Forever.lua returns, so it runs before the
-- probe's ADDON_LOADED handler touches SpellTunerDB.probe.
--------------------------------------------------------------------------------
local svHandled = false
MD:On("ADDON_LOADED", function(loadedName)
    if svHandled or loadedName ~= ADDON_NAME then return end
    svHandled = true

    -- Our own SavedVariables are ours, not client values -- type() checks
    -- before any index, but no adapter is needed for them.
    local t = type(SpellTunerDB)
    MD.sv = { atLoad = t }

    local prevCount
    if t == "table" then
        local session = SpellTunerDB.session
        if type(session) == "table" and type(session.stamp) == "string"
           and type(session.count) == "number" then
            MD.sv.prevStamp = session.stamp
            MD.sv.prevCount = session.count
            prevCount = session.count
        end
    elseif t ~= "nil" then
        -- A broken file: dropped, not indexed.
        SpellTunerDB = {}
    else
        -- A first run, or the client did not read the file back.
        SpellTunerDB = {}
    end

    -- Stamp the session so the next load can tell. Nothing else in
    -- SpellTunerDB is read or written here.
    SpellTunerDB.session = { stamp = date("%Y-%m-%d %H:%M:%S"), count = (prevCount or 0) + 1 }
end)

-- One line for /st dump (T3) and the debug log.
function MD:SavedVarsLine()
    local sv = MD.sv
    if not sv or sv.atLoad == "nil" then
        return "SavedVariables: none at load (a first run, or the client did not read the file back)"
    elseif sv.atLoad == "table" then
        if sv.prevStamp then
            return "SavedVariables: came back (previous session " .. sv.prevStamp ..
                ", this is session " .. tostring(sv.prevCount + 1) .. ")"
        else
            return "SavedVariables: came back, with no session stamp (first run of this build of SpellTuner)"
        end
    else
        return "SavedVariables: was a " .. sv.atLoad .. ", not a table - replaced with an empty one"
    end
end

MD:RegisterCallback("MD_READY", function()
    MD:Debug("other", "%s", MD:SavedVarsLine())
end)

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
