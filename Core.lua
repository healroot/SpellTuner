-- SpellTuner: the shared kernel, every TOC (T1b of docs/ROADMAP-FOREVER.md).
-- Namespace, event dispatch, internal pub/sub, the ticker, Print/Alert/Debug,
-- the player's identity, SavedVariables init, the login sequence and the
-- slash dispatcher with a command registry. Reaches the client only through
-- MD.API (Client/API.lua) -- no flavour check here (CLAUDE.md: a file listed
-- by both TOCs contains no client call and no flavour check). Everything
-- that is the TBC addon's own (defaults, Simulate, buffs/Tree of Life,
-- talents, the profile snapshot, its command list) lives in Core_TBC.lua;
-- Forever's own defaults and first two commands live in Core_Forever.lua.
local ADDON_NAME, MD = ...
_G.SpellTuner = MD

MD.version = MD.API.AddonVersion() or "dev"

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Register a handler; events unknown to this client are silently skipped, and
-- an event the adapter's flavour file has forbidden (Forever's combat log)
-- is never even attempted -- RegisterEvent trips the blocked-action dialog
-- for it, so the first registration has to be refused, not caught.
function MD:On(event, fn)
    if not handlers[event] then
        if not MD.API.CanRegisterEvent(event) then
            MD:Debug("other", "refused event %s", event)
            return
        end
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return end
        handlers[event] = {}
    end
    handlers[event][#handlers[event] + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

-- Internal pub/sub (module-to-module, not Blizzard events).
local callbacks = {}
function MD:RegisterCallback(name, fn)
    callbacks[name] = callbacks[name] or {}
    callbacks[name][#callbacks[name] + 1] = fn
end
function MD:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

--------------------------------------------------------------------------------
-- Master ticker: the model is event-driven; this drives accumulation/rendering.
--------------------------------------------------------------------------------
local tickers = {}
function MD:OnTick(fn)
    tickers[#tickers + 1] = fn
end

local TICK = 0.5
MD.API.NewTicker(TICK, function()
    for i = 1, #tickers do
        tickers[i](TICK)
    end
end)

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------
function MD:Print(msg)
    MD.API.Print("|cff9966ffSpellTuner:|r " .. tostring(msg))
    MD:Debug("chat", tostring(msg))
end

-- Alert respects /md mute and pulses the widget if present.
function MD:Alert(msg)
    MD:Debug("other", "alert%s: %s", (MD.db and MD.db.muted) and " (muted)" or "", tostring(msg))
    if MD.db and MD.db.muted then return end
    MD:Print(msg)
    if MD.PulseWidget then MD:PulseWidget() end
end

-- Debug log (Cell-style): a no-op unless debug logging is enabled in the
-- settings, otherwise one timestamped line into the in-memory ring that the
-- Debug Console (UI/DebugConsole.lua) shows and copies. Categories: regen,
-- mana, spend, tto, heal, cast, calib, combat, chat, sim, other. Extra arguments go through
-- string.format; a bad format never raises.
function MD:Debug(category, fmt, ...)
    local db = MD.db and MD.db.debug
    if not (db and db.enabled) then return end
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        text = ok and s or tostring(fmt)
    else
        text = tostring(fmt)
    end
    if MD.DebugLog then MD:DebugLog(category, text) end
end

--------------------------------------------------------------------------------
-- Player profile
--------------------------------------------------------------------------------
MD.player = { class = "UNKNOWN", level = 0, isDruid = false, guid = "", charKey = "?" }

function MD:DetectProfile()
    -- Multi-value adapter reads: `UnitClass` returns localized, token (or
    -- nil, "<reason>" on failure) -- the localized name is not the class
    -- token, so the SECOND value is the one every reader in the tree wants,
    -- and it is only meaningful when the first (the localized name) came
    -- back at all (T1b Review, re-issue 2).
    local loc, class = MD.API.UnitClass("player")
    if not loc then class = nil end
    MD.player.class = class or "UNKNOWN"
    MD.player.isDruid = class == "DRUID"
    MD.player.level = MD.API.UnitLevel("player") or 0
    MD.player.guid = MD.API.UnitGUID("player") or ""
    local name = MD.API.UnitName("player")
    local realm = MD.API.RealmName()
    MD.player.charKey = (name or "?") .. "-" .. (realm or "?")
    -- Druids are checked at login (caster form); cat/bear later doesn't change
    -- that mana is their healing resource.
    MD.player.usesMana = MD.API.UnitPowerType("player") == 0
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
-- Fill missing keys recursively so nested defaults (debug.categories) are
-- copied, never shared with the DEFAULTS table.
local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            FillDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function InitDB()
    -- The addon was ManaDemon until 2026-09-27. Its saved variables are still
    -- loaded (the .toc lists both) and adopted once, so nobody's recordings,
    -- fights or settings are lost to a rename. The old global is emptied after
    -- the copy so the client stops writing two files.
    if SpellTunerDB == nil and type(ManaDemonDB) == "table" then
        SpellTunerDB = ManaDemonDB
        ManaDemonDB = nil
    end
    SpellTunerDB = SpellTunerDB or {}
    FillDefaults(SpellTunerDB, MD.DEFAULTS or {})
    MD.db = SpellTunerDB
    MD.db.char[MD.player.charKey] = MD.db.char[MD.player.charKey] or {}
    MD.cdb = MD.db.char[MD.player.charKey]
end

MD:On("PLAYER_LOGIN", function()
    MD:DetectProfile()
    InitDB()
    MD:Debug("other", "=== PLAYER_LOGIN === SpellTuner v%s, %s level %d, debug categories: %s",
        MD.version, MD.player.class, MD.player.level, (function()
            local on = {}
            for k, v in pairs(MD.db.debug.categories) do if v then on[#on + 1] = k end end
            table.sort(on)
            return table.concat(on, " ")
        end)())
    -- Split from the flavour-specific tail (talent scan, the profile
    -- snapshot, the first-run message) so the kernel names none of them:
    -- CORE_LOGIN is for "the client is ready enough to read stats from",
    -- MD_READY is the shared readiness signal every module already listens
    -- for, CORE_READY is for "everything above has run, do your own tail now".
    MD:Fire("CORE_LOGIN")
    MD:Fire("MD_READY")
    MD:Fire("CORE_READY")
end)

MD:On("PLAYER_LEVEL_UP", function(level)
    MD.player.level = tonumber(level) or MD.API.UnitLevel("player") or MD.player.level
end)

--------------------------------------------------------------------------------
-- Module registry (T2 of docs/ROADMAP-FOREVER.md): inert until a flavour file
-- calls MD:DeclareModule -- the TBC flavour never does, so MD.modules stays
-- empty and MD.db.modules is never created (its DEFAULTS carries no such key).
-- A module is a sibling LoadOnDemand addon folder (Modules/<name>/ in this
-- checkout, built beside SpellTuner/ by release.sh) whose own Module.lua's
-- only job is to call MD:ModuleLoaded(name) once it runs.
--------------------------------------------------------------------------------
MD.modules = MD.modules or {}
local moduleIndex = {}

function MD:DeclareModule(name, label, needs, text)
    local m = { name = name, label = label, needs = needs or {}, text = text,
                loaded = false, failed = nil }
    MD.modules[#MD.modules + 1] = m
    moduleIndex[name] = m
end

-- Called by a sibling's Module.lua the moment it loads.
function MD:ModuleLoaded(name)
    local m = moduleIndex[name]
    if not m then return end
    m.loaded = true
    m.failed = nil
    MD:Fire("MODULE_LOADED", name)
end

-- LoadAddOn's own reason ("MISSING", "DISABLED", "DEP_MISSING", ...) is shown
-- only if it survived MD.API.Call as a plain, non-secret string of exactly
-- the shape the client uses; anything else (an adapter failure reason such
-- as "absent"/"error"/"secret", or nothing at all) becomes "unknown" rather
-- than leaking an internal detail into the chat line.
local function CleanReason(reason)
    if type(reason) == "string" and reason:match("^[A-Z_]+$") then return reason end
    return "unknown"
end

-- Attempts to load one module NOW if it is not already loaded, printing the
-- one line whose state actually changed. Never called for a module that is
-- not switched on -- the caller (SetModule, or CORE_READY below) decides that.
local function DoLoad(m)
    if m.loaded then return end
    local loaded, reason = MD.API.LoadAddOn(m.name)
    if loaded then
        m.loaded = true
        m.failed = nil
        MD:Print(m.label .. ": loaded")
    else
        m.failed = CleanReason(reason)
        MD:Print(m.label .. ": on, could not load (" .. m.failed .. ")")
    end
end

function MD:ModuleState(name)
    local m = moduleIndex[name]
    if not m then return "off" end
    local on = MD.db and MD.db.modules and MD.db.modules[name] == true
    if m.failed then return "failed", m.failed end
    if m.loaded then
        if on then return "loaded" end
        return "unloads"
    end
    if on then return "on" end
    return "off"
end

-- on: switch on `name` and everything it needs (recursively), then load every
-- one of those not yet loaded, in declaration order -- which is dependency
-- order, because a module's needs are always declared before it (Facts).
-- off: switch off `name` and every module that (transitively) needs it.
-- Neither direction ever unloads anything (WoW cannot); off only marks state
-- and, for a module that WAS loaded this session, warns it takes a /reload.
function MD:SetModule(name, on)
    if not moduleIndex[name] then return end
    MD.db.modules = MD.db.modules or {}
    local affected = {}
    if on then
        affected[name] = true
        local changed = true
        while changed do
            changed = false
            for _, m in ipairs(MD.modules) do
                if affected[m.name] then
                    for _, need in ipairs(m.needs) do
                        if not affected[need] then affected[need] = true; changed = true end
                    end
                end
            end
        end
        for _, m in ipairs(MD.modules) do
            if affected[m.name] then
                MD.db.modules[m.name] = true
                DoLoad(m)
            end
        end
    else
        affected[name] = true
        local changed = true
        while changed do
            changed = false
            for _, m in ipairs(MD.modules) do
                if not affected[m.name] then
                    for _, need in ipairs(m.needs) do
                        if affected[need] then affected[m.name] = true; changed = true; break end
                    end
                end
            end
        end
        for _, m in ipairs(MD.modules) do
            if affected[m.name] then
                MD.db.modules[m.name] = false
                m.failed = nil
                if m.loaded then
                    MD:Print(m.label .. ": off - unloads at your next /reload")
                else
                    MD:Print(m.label .. ": off")
                end
            end
        end
    end
end

-- Every declared module the player already switched on, loaded once the
-- client is ready enough -- same order, same DoLoad, no adapter call for one
-- whose switch is absent or false.
MD:RegisterCallback("CORE_READY", function()
    if not (MD.db and MD.db.modules) then return end
    for _, m in ipairs(MD.modules) do
        if MD.db.modules[m.name] == true then
            DoLoad(m)
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
-- name (lower-case) -> fn(arg, rawArg); COMMAND_LIST is the same set, in
-- registration order, for ShowCommands()/the About tab (MD.COMMANDS is the
-- TBC addon's own hand-kept list, unaffected by this registry).
local commandFns = {}
local commandHelp = {}

function MD:AddCommand(name, fn, usage, text)
    commandFns[name:lower()] = fn
    -- usage/text are optional (a caller registering only to claim a name, as
    -- tools/corecheck.lua's own test command does) -- ShowCommands still has
    -- to print every entry without raising.
    commandHelp[#commandHelp + 1] = { usage or "", text or "" }
end

function MD:ShowCommands()
    MD:Print("commands:")
    for _, c in ipairs(commandHelp) do
        MD:Print("  " .. c[1] .. " - " .. c[2])
    end
end

SLASH_SPELLTUNER1 = "/spelltuner"
SLASH_SPELLTUNER2 = "/st"
SLASH_SPELLTUNER3 = "/md"      -- ManaDemon's, kept for the hands that learned it
SlashCmdList.SPELLTUNER = function(msg)
    -- commands are matched lower-case; the RAW tail is kept because a run's
    -- name is the author's text ("/md run start Blood Furnace") and lower-casing
    -- it would hand them back a name they did not type
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    local _, rawArg = raw:match("^(%S*)%s*(.*)$")
    local fn = commandFns[cmd]
    if fn then
        fn(arg, rawArg)
    elseif type(MD.SlashFallback) == "function" then
        MD.SlashFallback(cmd, arg, rawArg)
    else
        MD:ShowCommands()
    end
end
