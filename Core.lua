-- SpellTuner: the shared kernel, every TOC (T1b of docs/ROADMAP-FOREVER.md).
-- Namespace, event dispatch, internal pub/sub, the ticker, Print/Alert/Debug,
-- the player's identity, SavedVariables init, the login sequence and the
-- slash dispatcher with a command registry. Reaches the client only through
-- MD.API (Client/API.lua) -- no flavour check here (CLAUDE.md: a file listed
-- by both TOCs contains no client call and no flavour check). Everything
-- that is the TBC addon's own (defaults, Simulate, buffs/Tree of Life,
-- talents, the profile snapshot, its command list) lives in Core_TBC.lua;
-- Forever's own defaults and first two commands live in Core_Forever.lua.
-- T55 (P11, review A3, A4, A9, A16, A28): the kernel's seams -- every event
-- and callback handler under xpcall (one raise no longer stops the rest),
-- MD.Text / MD:PrintSafe (the escaping rules, named apart), MD.Util and
-- MD.Rules (helpers copied 3-11 times), MD:RegisterDefaults / MD:Setting,
-- MD.inCombat, MD:Provide and MD:ModuleStateText. Defined here; the
-- consumers move in P14, P16, P18, P20 and P23.
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

-- T55 (P11, review A4): fault isolation. Each handler runs as
-- xpcall(handler, MD.ErrorSink, ...), so a raise in one handler no longer
-- stops the ones after it (PLAYER_REGEN_ENABLED has eight: the recorder
-- closing its stream, the clock re-anchoring, the run recorder seeing the
-- pull). The error still reaches the installed error handler exactly once.
--   * Arguments: the WoW client's xpcall passes its extra arguments to the
--     function (Lua 5.1.5's own drops them; tools/wowstub.lua's xpcall passes
--     them as the client does, docs/PLAN-refactor-ux.md section 9 check 5).
--   * Cost: one C call per handler per event -- measured 0.085 us per
--     dispatch over the bare loop (docs/tasks/T55-kernel-seams.md), under the
--     1 us bound, so the combat log is isolated per handler like every event.
--   * The sink is a TAIL call into whatever geterrorhandler() answers at that
--     moment (BugGrabber, Core_Forever.lua's capture, or the client's own), so
--     no frame of ours sits between that handler and the code that raised:
--     Core_Forever.lua's capture still names the raising line (review R22)
--     and its forward to the previous handler still reaches it with nothing
--     of ours in between (R21).
--   * No handler at all (only an offline stub lacks geterrorhandler): the
--     sink hands the message back and the loop raises it once every handler
--     has run, so a suite still goes red on a raising handler.
--     (xpcall hands back only the sink's FIRST return, so the message rides
--     in an upvalue read the moment xpcall returns, with nothing between.)
local UNSUNK = {}
local unsunkMsg
function MD.ErrorSink(msg)
    local h = MD.API.GetErrorHandler()
    if type(h) == "function" and h ~= MD.ErrorSink then
        return h(msg)
    end
    unsunkMsg = msg
    return UNSUNK
end
local ErrorSink = MD.ErrorSink

local function Dispatch(list, ...)
    local unsunk
    for i = 1, #list do
        local ok, marker = xpcall(list[i], ErrorSink, ...)
        if not ok and marker == UNSUNK and unsunk == nil then unsunk = unsunkMsg end
    end
    if unsunk ~= nil then error(unsunk, 0) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    Dispatch(list, ...)
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
    Dispatch(list, ...)
end

--------------------------------------------------------------------------------
-- The combat flag (T55, P11, review A28): one owner. Set by the two regen
-- events -- registered here, first, so every other handler of those events
-- already reads the new value -- and seeded at MD_READY through the adapter,
-- so a login or /reload mid-fight starts in combat (the R36 fix, for every
-- reader). An unreadable answer (absent, raised, secret) leaves the flag as
-- it was. Readers move to it in P14.
--------------------------------------------------------------------------------
MD.inCombat = false
MD:On("PLAYER_REGEN_DISABLED", function() MD.inCombat = true end)
MD:On("PLAYER_REGEN_ENABLED", function() MD.inCombat = false end)
MD:RegisterCallback("MD_READY", function()
    -- (value, nil) is an answer -- nil or false out of combat, true (1 on an
    -- old client) in it; (nil, "absent" / "error" / "secret") is not.
    local v, why = MD.API.UnitAffectingCombat("player")
    if why == nil then MD.inCombat = (v == true or v == 1) end
end)

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

--------------------------------------------------------------------------------
-- Text (T55, P11, review A9): the two escaping rules the tree copies nine
-- times, named apart. Consumers move to these in P16; the probe may keep its
-- own copy (it must run with nothing else loaded).
--   Esc            pipe-doubling only: "|" -> "||". For text the game's own
--                  fonts draw (a player's accented name stays as it is).
--   EscASCII       the probe's reversible escape: a backslash doubled, "|" ->
--                  "||", then every byte outside printable ASCII -> "\ddd",
--                  in that order so the backslashes the last step adds are
--                  never doubled. For copy boxes, reports and chat lines that
--                  must be ASCII.
--   EscKeepColours EscASCII around every well-formed colour start ("|c" and
--                  eight hex digits) and reset ("|r"), which are kept as they
--                  are (the coach card's own colours, review R26).
-- Each takes any value: nil is "", a secret "<secret>", anything else its
-- tostring. Each gsub result is kept in its own local (gsub's second return,
-- the count, must not reach the next call).
--------------------------------------------------------------------------------
local function AsText(s)
    if type(s) == "string" then return s end
    if s == nil then return "" end
    if MD.API.IsSecret(s) then return "<secret>" end
    return tostring(s)
end

local Text = {}
MD.Text = Text

function Text.Esc(s)
    local out = AsText(s):gsub("|", "||")
    return out
end

function Text.EscASCII(s)
    local step1 = AsText(s):gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

function Text.EscKeepColours(s)
    s = AsText(s)
    local out, i = {}, 1
    while i <= #s do
        local a, b = s:find("|c%x%x%x%x%x%x%x%x", i)
        local c, d = s:find("|r", i, true)
        if c and (not a or c < a) then a, b = c, d end
        if not a then
            out[#out + 1] = Text.EscASCII(s:sub(i))
            break
        end
        out[#out + 1] = Text.EscASCII(s:sub(i, a - 1))
        out[#out + 1] = s:sub(a, b)
        i = b + 1
    end
    return table.concat(out)
end

-- A line from anywhere (a name, a card, a client string) printed safely:
-- ASCII, no bare pipe, its own well-formed colour codes kept.
function MD:PrintSafe(line)
    MD:Print(Text.EscKeepColours(line))
end

--------------------------------------------------------------------------------
-- Small shared helpers (T55, P11, review A9) and the one rule constant with a
-- planned consumer (P23). GCD and the crit multiplier are not defined here
-- until a task moves their six copies (docs/PLAN-refactor-ux.md section 6).
--------------------------------------------------------------------------------
local Util = {}
MD.Util = Util

-- The median of a list of numbers, never sorting the caller's table (review
-- A9: PullBudget's sorted it in place). An even count averages the two middle
-- values; mode "low" takes the lower of them instead (PullBudget's choice).
-- nil for an empty list.
function Util.Median(t, mode)
    local n = t and #t or 0
    if n == 0 then return nil end
    local c = {}
    for i = 1, n do c[i] = t[i] end
    table.sort(c)
    if n % 2 == 1 then return c[(n + 1) / 2] end
    if mode == "low" then return c[n / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
end

-- m:ss (seconds floored), or m:ss.t with tenths; a negative time is 0.
function Util.Clock(sec, tenths)
    sec = tonumber(sec) or 0
    if sec < 0 then sec = 0 end
    if tenths then
        return string.format("%d:%04.1f", math.floor(sec / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

-- 2345 -> "2.3k" from `from` on (default 1000; the Waste view uses 10000),
-- below it the rounded whole number.
function Util.K(n, from)
    n = tonumber(n) or 0
    if n >= (from or 1000) then return string.format("%.1fk", n / 1000) end
    return string.format("%d", math.floor(n + 0.5))
end

-- A fight is kept when it lasted this long with this many own casts (the
-- two recorders' own copies move to it in P18).
Util.RECORD_GATE = { sec = 20, casts = 5 }

MD.Rules = {
    -- A rank is suggested only while its value is at least this share of the
    -- highest known rank's (Spells/Book.lua, Engine/RankMath.lua; P23).
    SUGGESTED_FLOOR = 0.4,
}

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
    -- T52 (P8, review B1; docs/DECISIONS.md "usesMana is whether the player
    -- has a mana pool"): answered from data -- the player's mana maximum,
    -- read plain and above 0. A druid who logs in or reloads in Cat or Bear
    -- form still has a mana pool (the power TYPE answered 3 or 1 there and
    -- switched the whole mana side off for the session); a warrior or rogue
    -- has none. No class list: which classes use mana on Forever's retail
    -- engine is not ours to guess. Only when that read is absent, secret or
    -- raised does the current power type decide, as it did before.
    local manaMax = MD.API.UnitPowerMax("player", 0)
    if not MD.API.IsSecret(manaMax) and type(manaMax) == "number" then
        MD.player.usesMana = manaMax > 0
    else
        MD.player.usesMana = MD.API.UnitPowerType("player") == 0
    end
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

--------------------------------------------------------------------------------
-- Registered defaults (T55, P11, review A3): a feature file -- a
-- LoadOnDemand module included, which loads after InitDB ran -- declares its
-- own settings' defaults with MD:RegisterDefaults({ key = value, ... }).
-- Before login they are merged into MD.DEFAULTS (or kept until the flavour
-- core has assigned it) and InitDB fills them in; after login they back-fill
-- MD.db at once. Either way a value the user already has is never touched.
-- A key registered twice with a DIFFERENT value raises: one owner per default
-- (the drift A3 names -- a re-measured threshold landing in one list only).
-- MD:Setting(key) answers the db value, else the registered default, else
-- MD.DEFAULTS'. Consumers move to these in P20.
--------------------------------------------------------------------------------
local registered = {}

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = CopyValue(x) end
    return c
end

-- The first key whose default `tbl` would change in `existing`, as a dotted
-- path with both values; nil when every shared key agrees.
local function Conflict(existing, tbl, path)
    if type(existing) ~= "table" then return nil end
    for k, v in pairs(tbl) do
        local e = existing[k]
        if e ~= nil then
            local here = path .. tostring(k)
            if type(e) == "table" and type(v) == "table" then
                local c = Conflict(e, v, here .. ".")
                if c then return c end
            elseif e ~= v then
                return here .. " (" .. tostring(e) .. " and " .. tostring(v) .. ")"
            end
        end
    end
    return nil
end

function MD:RegisterDefaults(tbl)
    if type(tbl) ~= "table" then error("SpellTuner: RegisterDefaults takes a table", 2) end
    local c = Conflict(registered, tbl, "") or Conflict(MD.DEFAULTS, tbl, "")
    if c then error("SpellTuner: two defaults for " .. c, 2) end
    FillDefaults(registered, CopyValue(tbl))
    if type(MD.DEFAULTS) == "table" then FillDefaults(MD.DEFAULTS, tbl) end
    if type(MD.db) == "table" then FillDefaults(MD.db, tbl) end
end

function MD:Setting(key)
    local v
    if type(MD.db) == "table" then v = MD.db[key] end -- a stored false is an answer
    if v ~= nil then return v end
    v = registered[key]
    if v ~= nil then return v end
    if type(MD.DEFAULTS) == "table" then return MD.DEFAULTS[key] end
    return nil
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
    -- A default registered before the flavour core assigned MD.DEFAULTS
    -- joins it here (the conflict check ran against what existed then; on a
    -- key both carry, MD.DEFAULTS' value stays -- only Core.lua and Client/
    -- load before the flavour core, and neither registers anything).
    if type(MD.DEFAULTS) == "table" then FillDefaults(MD.DEFAULTS, registered) end
    FillDefaults(SpellTunerDB, MD.DEFAULTS or {})
    FillDefaults(SpellTunerDB, registered)
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

-- T52 (P8, review A31): the event's argument is a client value and this file
-- is on the Forever TOC -- asked IsSecret before tonumber, whose answer for a
-- secret number would be the secret itself. Unreadable: the adapter's own
-- UnitLevel, else the level we had.
MD:On("PLAYER_LEVEL_UP", function(level)
    local n
    if not MD.API.IsSecret(level) then n = tonumber(level) end
    MD.player.level = n or MD.API.UnitLevel("player") or MD.player.level
end)

--------------------------------------------------------------------------------
-- MD:Provide(name, fn) (T55, P11, review A16): the one way a file fills a
-- seam another flavour or module may also fill -- MD.GetRecording,
-- MD.ClassifyCast, MD.FightRecorder.Pin -- instead of `if MD.X == nil then`,
-- a guard that always passes on Forever and would hide a load-order mistake.
-- `name` may be dotted ("FightRecorder.Pin"); every table on the way must
-- exist. A second provider (anything already there, however it got there)
-- raises, naming the seam. Adopted where P18 and P22 touch those seams.
--------------------------------------------------------------------------------
function MD:Provide(name, fn)
    if type(name) ~= "string" or name == "" then
        error("SpellTuner: Provide needs a name", 2)
    end
    local owner, key = MD, nil
    local segs = {}
    for seg in name:gmatch("[^%.]+") do segs[#segs + 1] = seg end
    for i = 1, #segs - 1 do
        owner = owner[segs[i]]
        if type(owner) ~= "table" then
            error("SpellTuner: Provide " .. name .. ": MD." .. table.concat(segs, ".", 1, i)
                .. " is not a table", 2)
        end
    end
    key = segs[#segs]
    if owner[key] ~= nil then
        error("SpellTuner: a second provider for MD." .. name, 2)
    end
    owner[key] = fn
    return fn
end

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

-- The module's state as the Modules pane and /st dump word it (T55, P11,
-- review A9: two copies, UI/Dashboard_Forever.lua's and UI/Dump_Forever.lua's;
-- they move to this in P16). ASCII already: CleanReason only ever hands back
-- "[A-Z_]+" or "unknown".
function MD:ModuleStateText(name)
    local state, reason = MD:ModuleState(name)
    if state == "loaded" then return "loaded" end
    if state == "on" then return "on - loads at login" end
    if state == "failed" then return "could not load: " .. tostring(reason) end
    if state == "unloads" then return "off - unloads at your next /reload" end
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
