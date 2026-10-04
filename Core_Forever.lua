-- Forever's own core (T1b/T2 of docs/ROADMAP-FOREVER.md): the defaults the
-- kernel's login debug line reads, the three LoadOnDemand sibling modules
-- (Core.lua's registry), and the first commands. UI/Dashboard_Forever.lua
-- loads after this file and gives "/st" and "/st modules" something to open.
local ADDON_NAME, ST = ...

-- Only this TOC's own settings. A LoadOnDemand module's settings are declared
-- by the file that reads them (ST:RegisterDefaults, T64 / P20: the engine's,
-- the planner's, the replay window's and the gates' in Engine/SimModel.lua and
-- Gates_Forever.lua), which back-fills ST.db when the module loads -- so no
-- key is hand-copied here. tools/defaultscheck.lua holds that every setting a
-- file on these TOCs reads has a default once the modules are loaded.
ST.DEFAULTS = {
    debug = {
        enabled = false,  -- ST:Debug() is a no-op unless this is on
        maxLines = 1000,  -- memory ring size (Debug Console "keep lines")
        categories = { regen = true, mana = true, spend = true, tto = true,
                       heal = true, cast = true, calib = true, combat = true, chat = true,
                       sim = true, other = true },
    },
    char = {},
    modules = {},  -- name -> true|false, read/written by Core.lua's registry
    -- T64 (P20, review A3: "Core_Forever.lua DEFAULTS lacks keys shared files
    -- read"): two settings shared files read on this TOC, off as nil read
    -- before -- Core.lua's ST:Alert (muted) and UI/Dashboard_Rows.lua's
    -- Effective mode (effectiveMode, which nothing on Forever turns on).
    muted = false,
    effectiveMode = false,
    spellTooltip = true,  -- UI/SpellTip_Forever.lua's block on spell tooltips
    -- T37 (docs/SPEC-forever-ui.md 5.6): the key that shows the block's detail
    -- lines -- "SHIFT", "ALT", "CTRL", or "ALWAYS" / "NEVER" (Settings -> General).
    spellTooltipDetail = "SHIFT",
    clock = { shown = true, locked = false, point = nil },  -- UI/Clock_Forever.lua
    -- T80 (C1 of docs/PLAN-refactor-ux.md): db.ui (T29: the font offset, the
    -- window scale, the combat rule, one window per ESC, the saved places) is
    -- declared by the files that read it -- UI/Theme_Flat.lua (fontOffset),
    -- UI/EscStack.lua (escStack), UI/Windows.lua (scale, combat, win) -- with
    -- ST:RegisterDefaults, so the TBC TOC, which lists them too, has it.
}

-- The three siblings, in dependency order (each needs only what is declared
-- before it -- Core.lua's SetModule relies on that to load in the right
-- order without a topological sort of its own).
ST:DeclareModule("SpellTuner_Recorder", "Recorder", {},
    "records your fights: health, heals, casts and mana")
ST:DeclareModule("SpellTuner_Replay", "Replay", { "SpellTuner_Recorder" },
    "replays a recorded fight and coaches it")
ST:DeclareModule("SpellTuner_Practice", "Practice", { "SpellTuner_Replay" },
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
ST:On("ADDON_LOADED", function(loadedName)
    if svHandled or ST.API.IsSecret(loadedName) or loadedName ~= ADDON_NAME then return end
    svHandled = true

    -- Our own SavedVariables are ours, not client values -- type() checks
    -- before any index, but no adapter is needed for them.
    local t = type(SpellTunerDB)
    ST.sv = { atLoad = t }

    local prevCount
    if t == "table" then
        local session = SpellTunerDB.session
        if type(session) == "table" and type(session.stamp) == "string"
           and type(session.count) == "number" then
            ST.sv.prevStamp = session.stamp
            ST.sv.prevCount = session.count
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
function ST:SavedVarsLine()
    local sv = ST.sv
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

ST:RegisterCallback("MD_READY", function()
    ST:Debug("other", "%s", ST:SavedVarsLine())
end)

-- T35 (docs/SPEC-forever-ui.md 3.3): the character's spell list is in place
-- from login -- Spells/Tabs.lua creates ST.cdb.spellTabs (empty, not seeded;
-- the seed runs on the Spells pane's first open) and repairs a damaged one.
ST:RegisterCallback("CORE_LOGIN", function()
    if ST.Tabs then ST.Tabs:Store() end
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
ST.errors = {}
ST.errorTotal = 0
ST.errorOverflow = 0
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

-- The stack is read through the adapter (ST.API.DebugStack -> ST.API.Call ->
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
-- call to Record); never calls ST:Print/ST:Debug/anything that could error
-- back into it.
local function InstallErrorHandler()
    local prev = ST.API.GetErrorHandler()
    if type(prev) ~= "function" then prev = nil end

    -- Classifies and records `msg`; answers true when the previous handler
    -- should be shown it too, false for a repeat of our own error.
    local function Record(msg)
        if type(msg) ~= "string" or ST.API.IsSecret(msg) then return true end
        if not IsOurs(msg) then return true end

        local key = msg:sub(1, 300)
        local now = GetTime()
        local entry = errorIndex[key]
        if entry then
            entry.count = entry.count + 1
            entry.last = now
            ST.errorTotal = ST.errorTotal + 1
            return false -- a repeat of our own error is never forwarded
        end

        if #ST.errors >= MAX_DISTINCT_ERRORS then
            ST.errorOverflow = ST.errorOverflow + 1
            ST.errorTotal = ST.errorTotal + 1
            -- new to the client even though we stop keeping it ourselves
            return true
        end

        entry = { msg = key, count = 1, first = now, last = now,
                  stack = FirstUsefulLine(ST.API.DebugStack(1, STACK_LINES, 0)) }
        errorIndex[key] = entry
        ST.errors[#ST.errors + 1] = entry
        ST.errorTotal = ST.errorTotal + 1
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
    local _, why = ST.API.SetErrorHandler(handler)
    return why
end

local installOk, installWhy = pcall(InstallErrorHandler)
if installOk and installWhy == nil then
    ST.errorHandlerInstalled = true
else
    ST.errorHandlerInstalled = (installOk and installWhy) or "error"
end

ST:AddCommand("debug", function() ST:ToggleDebugConsole() end, "/st debug", "the debug console")
ST:AddCommand("dump", function()
    if ST.BuildDump and ST.ShowCopyPopup then
        ST:ShowCopyPopup("SpellTuner dump", ST:BuildDump())
    end
end, "/st dump", "one copyable block for a bug report")

ST:AddCommand("", function()
    if ST.ToggleDashboard then
        ST:ToggleDashboard()
    else
        ST:ShowCommands()
    end
end, "/st", "open the SpellTuner window")

ST:AddCommand("help", function() ST:ShowCommands() end, "/st help", "this list")

ST:AddCommand("tooltip", function(arg)
    -- T28 (docs/SPEC-forever-ui.md 5.5): one line saying why the last macro
    -- hover showed a block or none; it changes nothing.
    if arg == "why" then
        if ST.SpellTip and ST.SpellTip.Why then
            ST:Print(ST.SpellTip:Why())
        else
            ST:Print("tooltip why: the spell tooltip is not loaded")
        end
        return
    end
    ST.db.spellTooltip = not ST.db.spellTooltip
    ST:Print("spell tooltip lines: " .. (ST.db.spellTooltip and "on" or "off"))
end, "/st tooltip [why]",
"turn the SpellTuner block on spell tooltips on or off; why: what the last macro hover did, step by step")

ST:AddCommand("clock", function(arg)
    ST.db.clock = ST.db.clock or {}
    if arg == "lock" then
        ST.db.clock.locked = not ST.db.clock.locked
        ST:Print("mana clock: " .. (ST.db.clock.locked and "locked" or "unlocked"))
    else
        ST.db.clock.shown = not ST.db.clock.shown
        ST:Print("mana clock: " .. (ST.db.clock.shown and "shown" or "hidden"))
    end
    if ST.Clock and ST.Clock.Refresh then ST.Clock:Refresh() end
end, "/st clock [lock]", "show or hide the mana clock, or lock it in place")

ST:AddCommand("measure", function(arg)
    if arg == "dump" or arg == "dump all" then
        if ST.Measure and ST.Measure.Dump and ST.ShowCopyPopup then
            ST:ShowCopyPopup("SpellTuner measure", ST.Measure:Dump(arg == "dump all"))
        end
    elseif arg == "clear" then
        if ST.Measure and ST.Measure.Clear then
            local n = ST.Measure:Clear()
            ST:Print("measure: cleared " .. n .. " line(s)")
        end
    elseif ST.Measure and ST.Measure.Toggle then
        ST.Measure:Toggle()
    end
end, "/st measure [dump [all] / clear]",
"measure a landed cast against its own description (a diagnostic session); dump shows this version's lines, dump all every line with its stamp, clear empties the list")

-- T32 (docs/SPEC-forever-ui.md 6.7): every SpellTuner window back at its
-- default place and size (UI/Windows.lua's ST.Win:Reset).
ST:AddCommand("ui", function(arg)
    if arg == "reset" then
        ST.Win:Reset()
        ST:Print("windows: every position and size reset")
    else
        ST:Print("usage: /st ui reset")
    end
end, "/st ui reset", "put every SpellTuner window back at its default place and size")

-- T36 (docs/SPEC-forever-ui.md 3.1): a spell's view in the Spells rail, by
-- a case-insensitive prefix of its family's name (the raw text, so the echo
-- of a name that matches nothing is what was typed). Not in the list: its
-- preview. Through ST:SelectView, so the window manager's ShowMain decides.
ST:AddCommand("spell", function(arg, rawArg)
    if ST.OpenSpell then
        ST:OpenSpell(rawArg or arg)
    else
        ST:ShowCommands()
    end
end, "/st spell <name>", "open that spell's view in the Spells list (a preview when it is not in your list)")

ST:AddCommand("modules", function()
    if ST.SelectView then
        ST:SelectView("settings", "modules")
    else
        ST:ShowCommands()
    end
end, "/st modules", "switch the Recorder, Replay and Practice modules on or off")
