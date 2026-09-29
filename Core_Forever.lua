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
    spellTooltip = true,  -- UI/SpellTip_Forever.lua's block on spell tooltips
    clock = { shown = true, locked = false, point = nil },  -- UI/Clock_Forever.lua
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
    if svHandled or MD.API.IsSecret(loadedName) or loadedName ~= ADDON_NAME then return end
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

--------------------------------------------------------------------------------
-- Error capture (T3): installed right here, at load, not at an event -- this
-- file is the earliest a Forever file can start (right after Core.lua). The
-- FIRST occurrence of one of OUR errors is forwarded to whatever handler was
-- already installed (the client, or BugGrabber, still shows it once); every
-- repeat is only counted and never forwarded; another addon's error, or
-- anything that is not a plain readable string, passes through untouched and
-- is never recorded. Whether replacing the handler is even allowed here is
-- UNKNOWN (Facts) -- the whole install, and all of the handler's own
-- bookkeeping, run under pcall so a "no" shows up as a recorded reason, never
-- a login-time error; only the forward to the previous handler does not (R21).
--------------------------------------------------------------------------------
MD.errors = {}
MD.errorTotal = 0
MD.errorOverflow = 0
local errorIndex = {}
local MAX_DISTINCT_ERRORS = 50

-- The retail message names the addon folder ("Interface/AddOns/SpellTuner/...");
-- the sibling modules ship under their own folder names, which all start with
-- "SpellTuner_" and so also match "SpellTuner" below. Falls back to the bare
-- name if there is no path at all (Facts: whether every message carries one
-- is UNKNOWN).
local function IsOurs(msg)
    if msg:find("AddOns/SpellTuner", 1, true) then return true end
    return msg:find("SpellTuner", 1, true) ~= nil
end

-- The stack is read through the adapter (MD.API.DebugStack -> MD.API.Call ->
-- pcall(debugstack)), from inside Record's pcall, under the handler, under
-- the client's call of it -- so its first lines are the capture's own frames,
-- not the code that raised (review R22: asking for level 2, one line, always
-- named Client/API.lua's Call). Read from level 1, several lines, and skip
-- every leading line that belongs to the capture: this file, the adapter,
-- C frames (pcall, and `error` itself), tail-call markers and the "..."
-- elision; the first line left is the frame that raised.
local STACK_LINES = 16
local function IsCaptureLine(line)
    return line:find("Core_Forever.lua", 1, true) ~= nil
        or line:find("Client/API.lua", 1, true) ~= nil
        or line:find("Client\\API.lua", 1, true) ~= nil
        or line:find("[C]", 1, true) ~= nil
        or line:find("(tail call)", 1, true) ~= nil
        or line == "..."
end

local function FirstUsefulLine(stack)
    if type(stack) ~= "string" then return nil end
    for line in stack:gmatch("[^\n]+") do
        if not IsCaptureLine(line) then
            return line
        end
    end
    return nil
end

-- Runs entirely under pcall's protection (both the install below and every
-- call to Record); never calls MD:Print/MD:Debug/anything that could error
-- back into it.
local function InstallErrorHandler()
    local prev = MD.API.GetErrorHandler()
    if type(prev) ~= "function" then prev = nil end

    -- Classifies and records `msg`; answers true when the previous handler
    -- should be shown it too, false for a repeat of our own error.
    local function Record(msg)
        if type(msg) ~= "string" or MD.API.IsSecret(msg) then return true end
        if not IsOurs(msg) then return true end

        local key = msg:sub(1, 300)
        local now = GetTime()
        local entry = errorIndex[key]
        if entry then
            entry.count = entry.count + 1
            entry.last = now
            MD.errorTotal = MD.errorTotal + 1
            return false -- a repeat of our own error is never forwarded
        end

        if #MD.errors >= MAX_DISTINCT_ERRORS then
            MD.errorOverflow = MD.errorOverflow + 1
            MD.errorTotal = MD.errorTotal + 1
            -- new to the client even though we stop keeping it ourselves
            return true
        end

        entry = { msg = key, count = 1, first = now, last = now,
                  stack = FirstUsefulLine(MD.API.DebugStack(1, STACK_LINES, 0)) }
        errorIndex[key] = entry
        MD.errors[#MD.errors + 1] = entry
        MD.errorTotal = MD.errorTotal + 1
        return true
    end

    -- The bookkeeping runs under its own pcall and is finished before the
    -- forward, which is a TAIL call from this function (review R21): the
    -- previous handler (the client's, or BugGrabber's) reads the stack and
    -- locals at fixed levels relative to itself, so it must run where it
    -- would have run without us -- not under a pcall and a closure of ours.
    -- A raise inside Record is ours and is swallowed (the message is then
    -- forwarded, so the client still sees it); a raise inside the previous
    -- handler is that handler's own, exactly as it would be had SpellTuner
    -- never installed anything.
    local function handler(msg, ...)
        local ok, forward = pcall(Record, msg)
        if ok and forward == false then return nil end
        if prev then return prev(msg, ...) end
        return nil
    end

    -- nil,nil on success; nil,"absent"/"error"[,detail] if the adapter could
    -- not install it (SetErrorHandler is absent, or itself raised).
    local _, why = MD.API.SetErrorHandler(handler)
    return why
end

local installOk, installWhy = pcall(InstallErrorHandler)
if installOk and installWhy == nil then
    MD.errorHandlerInstalled = true
else
    MD.errorHandlerInstalled = (installOk and installWhy) or "error"
end

MD:AddCommand("debug", function() MD:ToggleDebugConsole() end, "/st debug", "the debug console")
MD:AddCommand("dump", function()
    if MD.BuildDump and MD.ShowCopyPopup then
        MD:ShowCopyPopup("SpellTuner dump", MD:BuildDump())
    end
end, "/st dump", "one copyable block for a bug report")

MD:AddCommand("", function()
    if MD.ToggleDashboard then
        MD:ToggleDashboard()
    else
        MD:ShowCommands()
    end
end, "/st", "open the SpellTuner window")

MD:AddCommand("help", function() MD:ShowCommands() end, "/st help", "this list")

MD:AddCommand("tooltip", function(arg)
    -- T28 (docs/SPEC-forever-ui.md 5.5): one line saying why the last macro
    -- hover showed a block or none; it changes nothing.
    if arg == "why" then
        if MD.SpellTip and MD.SpellTip.Why then
            MD:Print(MD.SpellTip:Why())
        else
            MD:Print("tooltip why: the spell tooltip is not loaded")
        end
        return
    end
    MD.db.spellTooltip = not MD.db.spellTooltip
    MD:Print("spell tooltip lines: " .. (MD.db.spellTooltip and "on" or "off"))
end, "/st tooltip [why]",
"turn the SpellTuner block on spell tooltips on or off; why: what the last macro hover did, step by step")

MD:AddCommand("clock", function(arg)
    MD.db.clock = MD.db.clock or {}
    if arg == "lock" then
        MD.db.clock.locked = not MD.db.clock.locked
        MD:Print("mana clock: " .. (MD.db.clock.locked and "locked" or "unlocked"))
    else
        MD.db.clock.shown = not MD.db.clock.shown
        MD:Print("mana clock: " .. (MD.db.clock.shown and "shown" or "hidden"))
    end
    if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
end, "/st clock [lock]", "show or hide the mana clock, or lock it in place")

MD:AddCommand("measure", function(arg)
    if arg == "dump" or arg == "dump all" then
        if MD.Measure and MD.Measure.Dump and MD.ShowCopyPopup then
            MD:ShowCopyPopup("SpellTuner measure", MD.Measure:Dump(arg == "dump all"))
        end
    elseif arg == "clear" then
        if MD.Measure and MD.Measure.Clear then
            local n = MD.Measure:Clear()
            MD:Print("measure: cleared " .. n .. " line(s)")
        end
    elseif MD.Measure and MD.Measure.Toggle then
        MD.Measure:Toggle()
    end
end, "/st measure [dump [all] / clear]",
"measure a landed cast against its own description (a diagnostic session); dump shows this version's lines, dump all every line with its stamp, clear empties the list")

MD:AddCommand("modules", function()
    if MD.SelectView then
        MD:SelectView("settings", "modules")
    else
        MD:ShowCommands()
    end
end, "/st modules", "switch the Recorder, Replay and Practice modules on or off")
