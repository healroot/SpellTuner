-- tools/run.sh --flavour forever tools/corecheck.lua
-- tools/run.sh --flavour tbc tools/corecheck.lua
--
-- T1b: Core.lua splits into the shared kernel (namespace, event dispatch,
-- pub/sub, ticker, Print/Alert/Debug, player identity, SavedVariables init,
-- login sequence, the slash dispatcher and command registry -- every TOC)
-- and Core_TBC.lua / Core_Forever.lua, one flavour each, hanging off the
-- kernel's CORE_LOGIN/CORE_READY callbacks and MD:AddCommand.
-- Assertions 1-5 run under both flavours, 6-10 under forever only, 11-13
-- under tbc only (docs/tasks/T1b-shared-core.md Acceptance 1).
-- T52 (P8, review B1, B2, A31): three more under both flavours (whether the
-- player has a mana pool is read from UnitPowerMax(..., 0), the power type only
-- when that read is unreadable) and two more under tbc (a secret level from
-- PLAYER_LEVEL_UP is never stored -- tbc because the forever stub cannot
-- register that event; Tree form: the buff scan only when GetShapeshiftFormID
-- is missing or raised) -- 13 forever, 13 tbc.
-- T55 (P11, review A3, A4, A9, A16, A28): nine more under both flavours --
-- a raising handler stops neither MD:On's nor MD:Fire's loop and reaches the
-- error handler once, with no handler at all the loop re-raises after every
-- handler ran, RegisterDefaults back-fills after login without overwriting,
-- MD.inCombat seeded from the adapter and flipped by the regen events,
-- Provide refusing a second provider, MD.Text's two escapes, PrintSafe, and
-- MD.Util -- 22 forever, 22 tbc.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- Runs one assertion's body under pcall: before the split, most of these
-- raise outright (MD.player, MD.AddCommand, ... do not exist yet on the
-- flavour under test) -- a raise must still be reported as a named failure,
-- not stop the suite from trying the rest.
local function try(name, body)
    local runOk, err = pcall(body)
    if not runOk then check(name, false, "raised: " .. tostring(err)) end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local okLoad, MD = pcall(dofile, here .. "/harness.lua")
arg[0] = a0
if not okLoad then
    print("harness failed to load: " .. tostring(MD))
    print("0 ok, 22 failed")
    os.exit(1)
end
local S = _G.STUB
local flavour = S.flavour

local function TocVersion(tocName)
    local expected
    local f = io.open(ROOT .. "/" .. tocName, "r")
    if f then
        for line in f:lines() do
            local v = line:match("^## Version:%s*(.-)%s*$")
            if v then expected = v; break end
        end
        f:close()
    end
    return expected
end

--------------------------------------------------------------------------------
-- 1-5: both flavours
--------------------------------------------------------------------------------

try("the core loads and names itself", function()
    local tocName = (flavour == "forever") and "SpellTuner_Mainline.toc" or "SpellTuner_TBC.toc"
    local expectedVersion = TocVersion(tocName)
    check("the core loads and names itself",
        _G.SpellTuner == MD
        and MD.version == expectedVersion
        and type(MD.db) == "table"
        and MD.player.class == "DRUID"
        and MD.player.charKey == "Penek-Anniversary")
end)

try("events, callbacks and the ticker run", function()
    local gotArgs
    MD:On("UNIT_COMBAT", function(...) gotArgs = { ... } end)
    S.Fire("UNIT_COMBAT", "party1", "HEAL", "", 120, 1)

    local cbA, cbB
    MD:RegisterCallback("CoreCheckCB", function(a, b) cbA, cbB = a, b end)
    MD:Fire("CoreCheckCB", "x", "y")

    local ticked = false
    MD:OnTick(function() ticked = true end)
    S.Tick(0.5)

    check("events, callbacks and the ticker run",
        gotArgs and gotArgs[1] == "party1" and gotArgs[2] == "HEAL" and gotArgs[3] == ""
        and gotArgs[4] == 120 and gotArgs[5] == 1
        and cbA == "x" and cbB == "y" and ticked == true)
end)

try("an event the adapter refuses is never attempted", function()
    MD.API.ForbidEvent("PLAYER_TARGET_CHANGED")
    MD:On("PLAYER_TARGET_CHANGED", function() end)
    local attempted = false
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "PLAYER_TARGET_CHANGED" then attempted = true end
        end
    end
    check("an event the adapter refuses is never attempted", not attempted)
end)

try("a registered command gets its argument and the raw text", function()
    local gotArg, gotRaw
    MD:AddCommand("t1btest", function(arg, rawArg) gotArg, gotRaw = arg, rawArg end)
    SlashCmdList.SPELLTUNER("  T1BTest Blood Furnace ")
    check("a registered command gets its argument and the raw text",
        gotArg == "blood furnace" and gotRaw == "Blood Furnace")
end)

try("Print goes through the adapter to the chat frame", function()
    local seen
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) seen = m end
    MD:Print("hello")
    frame.AddMessage = orig
    check("Print goes through the adapter to the chat frame",
        type(seen) == "string" and seen:find("SpellTuner:", 1, true) ~= nil
        and seen:find("hello", 1, true) ~= nil)
end)

-- T52 (P8, review B1): usesMana is whether the player HAS a mana pool, read
-- from UnitPowerMax("player", 0) -- a druid who logs in or reloads in Cat or
-- Bear form still has one. Each case re-runs the login's own read
-- (MD:DetectProfile) and puts the stub back afterwards, whatever happened.
local function WithPower(setup, body)
    local savedType, savedMax, savedClass = S.powerType, S.powerMax, S.units.player.class
    S.powerMax = {}
    local runOk, err = pcall(function() setup(); body() end)
    S.powerType, S.powerMax, S.units.player.class = savedType, savedMax, savedClass
    MD:DetectProfile()
    if not runOk then error(err, 0) end
end

try("a login in Cat form keeps the mana side (B1)", function()
    WithPower(function() S.powerType = 3 end, function()
        MD:DetectProfile()
        check("a login in Cat form keeps the mana side (B1)",
            MD.player.usesMana == true and MD.player.isDruid == true,
            "usesMana=" .. tostring(MD.player.usesMana))
    end)
end)

try("a class with no mana pool does not use mana (B1)", function()
    WithPower(function()
        S.units.player.class = "WARRIOR"
        S.powerType = 1
        S.powerMax[0] = 0
    end, function()
        MD:DetectProfile()
        check("a class with no mana pool does not use mana (B1)",
            MD.player.usesMana == false, "usesMana=" .. tostring(MD.player.usesMana))
    end)
end)

-- Forever: the max comes back secret. TBC has no secrets, so the unreadable
-- case there is a UnitPowerMax that raises -- swapped in through the
-- adapter's new MD.API.Invalidate (the Has cache would otherwise keep the
-- stub's function forever). Either way the power type decides (3: no mana).
try("an unreadable mana max falls back to the power type (B1)", function()
    local realMax = _G.UnitPowerMax
    local ranRaise = false
    local function Restore()
        _G.UnitPowerMax = realMax
        if flavour ~= "forever" and MD.API.Invalidate then MD.API.Invalidate("UnitPowerMax") end
    end
    local runOk, err = pcall(WithPower, function()
        S.powerType = 3
        if flavour == "forever" then
            S.powerMax[0] = S.Secret()
        else
            _G.UnitPowerMax = function() ranRaise = true; error("stub: UnitPowerMax raised") end
            MD.API.Invalidate("UnitPowerMax")
        end
    end, function()
        local callOk = pcall(function() MD:DetectProfile() end)
        local usesMana = MD.player.usesMana
        Restore()
        check("an unreadable mana max falls back to the power type (B1)",
            callOk == true and usesMana == false
            and (flavour == "forever" or ranRaise == true),
            "usesMana=" .. tostring(usesMana) .. " raised=" .. tostring(ranRaise))
    end)
    Restore()
    if not runOk then error(err, 0) end
end)

--------------------------------------------------------------------------------
-- T55 (P11): the kernel's seams, both flavours
--------------------------------------------------------------------------------

-- Swaps the client's geterrorhandler for one answering `handler` (nil: the
-- global is gone), reached through the adapter's Invalidate since Has caches
-- the function it found; puts the real one back whatever happened.
local function WithErrorHandler(handler, body)
    local real = rawget(_G, "geterrorhandler")
    if handler then
        _G.geterrorhandler = function() return handler end
    else
        _G.geterrorhandler = nil
    end
    MD.API.Invalidate("geterrorhandler")
    local runOk, err = pcall(body)
    _G.geterrorhandler = real
    MD.API.Invalidate("geterrorhandler")
    if not runOk then error(err, 0) end
end

-- A4: one raise no longer stops the handlers after it. The raising handler is
-- armed only for its own firing (a handler cannot be unregistered).
local armedOn, armedFire = false, false
MD:On("UNIT_COMBAT", function() if armedOn then error("corecheck: raised in MD:On", 0) end end)
local secondOnRan = false
MD:On("UNIT_COMBAT", function() if armedOn then secondOnRan = true end end)
MD:RegisterCallback("CoreCheckRaise", function() if armedFire then error("corecheck: raised in MD:Fire", 0) end end)
local secondFireRan = false
MD:RegisterCallback("CoreCheckRaise", function() if armedFire then secondFireRan = true end end)

try("a raising MD:On handler stops nothing and reaches the handler once (A4)", function()
    local seen = {}
    local fireOk
    WithErrorHandler(function(msg) seen[#seen + 1] = msg end, function()
        armedOn = true
        fireOk = pcall(S.Fire, "UNIT_COMBAT", "player", "HEAL", "", 10, 1)
        armedOn = false
    end)
    check("a raising MD:On handler stops nothing and reaches the handler once (A4)",
        fireOk == true and secondOnRan == true and #seen == 1
        and seen[1] == "corecheck: raised in MD:On",
        "fired=" .. tostring(fireOk) .. " second=" .. tostring(secondOnRan) .. " seen=" .. #seen)
end)

try("a raising MD:Fire callback stops nothing and reaches the handler once (A4)", function()
    local seen = {}
    local fireOk
    WithErrorHandler(function(msg) seen[#seen + 1] = msg end, function()
        armedFire = true
        fireOk = pcall(MD.Fire, MD, "CoreCheckRaise")
        armedFire = false
    end)
    check("a raising MD:Fire callback stops nothing and reaches the handler once (A4)",
        fireOk == true and secondFireRan == true and #seen == 1
        and seen[1] == "corecheck: raised in MD:Fire",
        "fired=" .. tostring(fireOk) .. " second=" .. tostring(secondFireRan) .. " seen=" .. #seen)
end)

-- With no error handler to sink into (only a stub lacks one) the error is not
-- swallowed: it is raised after every handler ran, so a suite goes red.
try("with no error handler the loop re-raises after every handler ran (A4)", function()
    secondFireRan = false
    local fireOk, err
    WithErrorHandler(nil, function()
        armedFire = true
        fireOk, err = pcall(MD.Fire, MD, "CoreCheckRaise")
        armedFire = false
    end)
    check("with no error handler the loop re-raises after every handler ran (A4)",
        fireOk == false and err == "corecheck: raised in MD:Fire" and secondFireRan == true,
        "fired=" .. tostring(fireOk) .. " err=" .. tostring(err))
end)

-- A3: a feature file registering its defaults after login fills what the
-- player does not have and leaves what they set; a second, different default
-- for the same key raises; MD:Setting falls back to the registered default.
try("RegisterDefaults after login back-fills and never overwrites (A3)", function()
    MD.db.coreCheckKept = "user"
    MD.db.coreCheckOff = false
    MD:RegisterDefaults({ coreCheckKept = "default", coreCheckNew = 3,
                          coreCheckOff = true, coreCheckNest = { a = 1 } })
    local filled = MD.db.coreCheckKept == "user" and MD.db.coreCheckNew == 3
        and MD.db.coreCheckOff == false and type(MD.db.coreCheckNest) == "table"
        and MD.db.coreCheckNest.a == 1
    local sameOk = pcall(MD.RegisterDefaults, MD, { coreCheckNew = 3 })
    local otherOk, otherErr = pcall(MD.RegisterDefaults, MD, { coreCheckNew = 4 })
    local nestOk = pcall(MD.RegisterDefaults, MD, { coreCheckNest = { a = 2 } })
    MD.db.coreCheckNew = nil
    local setting = MD:Setting("coreCheckNew")
    local stored = MD:Setting("coreCheckOff")
    check("RegisterDefaults after login back-fills and never overwrites (A3)",
        filled and sameOk and otherOk == false and nestOk == false
        and type(otherErr) == "string" and otherErr:find("coreCheckNew", 1, true) ~= nil
        and setting == 3 and stored == false,
        string.format("filled=%s same=%s other=%s nest=%s setting=%s stored=%s", tostring(filled),
            tostring(sameOk), tostring(otherOk), tostring(nestOk), tostring(setting), tostring(stored)))
end)

-- A28: the flag is seeded at MD_READY from the adapter (a /reload mid-fight
-- starts in combat), an unreadable answer leaves it, the regen events flip it.
try("MD.inCombat seeded from the adapter, flipped by the regen events (A28)", function()
    local real = rawget(_G, "UnitAffectingCombat")
    local seeded, kept, afterEnd, afterStart
    local runOk, err = pcall(function()
        _G.UnitAffectingCombat = function() return true end
        MD.API.Invalidate("UnitAffectingCombat")
        MD.inCombat = false
        MD:Fire("MD_READY")
        seeded = MD.inCombat
        _G.UnitAffectingCombat = function() error("stub: UnitAffectingCombat raised") end
        MD.API.Invalidate("UnitAffectingCombat")
        MD:Fire("MD_READY")
        kept = MD.inCombat
        _G.UnitAffectingCombat = real
        MD.API.Invalidate("UnitAffectingCombat")
        S.Fire("PLAYER_REGEN_ENABLED")
        afterEnd = MD.inCombat
        S.Fire("PLAYER_REGEN_DISABLED")
        afterStart = MD.inCombat
        S.Fire("PLAYER_REGEN_ENABLED")
    end)
    _G.UnitAffectingCombat = real
    MD.API.Invalidate("UnitAffectingCombat")
    if not runOk then error(err, 0) end
    check("MD.inCombat seeded from the adapter, flipped by the regen events (A28)",
        seeded == true and kept == true and afterEnd == false and afterStart == true
        and MD.inCombat == false,
        string.format("seeded=%s kept=%s end=%s start=%s", tostring(seeded), tostring(kept),
            tostring(afterEnd), tostring(afterStart)))
end)

-- A16: a seam has one provider; the second raises and names it.
try("Provide fills a seam once and refuses a second provider (A16)", function()
    local fn1, fn2 = function() return 1 end, function() return 2 end
    MD:Provide("CoreCheckSeam", fn1)
    local secondOk, secondErr = pcall(MD.Provide, MD, "CoreCheckSeam", fn2)
    MD.CoreCheckTable = {}
    MD:Provide("CoreCheckTable.Pin", fn1)
    local dottedAgain = pcall(MD.Provide, MD, "CoreCheckTable.Pin", fn2)
    local noTable = pcall(MD.Provide, MD, "NoSuchTable.Pin", fn1)
    check("Provide fills a seam once and refuses a second provider (A16)",
        MD.CoreCheckSeam == fn1 and secondOk == false and type(secondErr) == "string"
        and secondErr:find("CoreCheckSeam", 1, true) ~= nil
        and MD.CoreCheckTable.Pin == fn1 and dottedAgain == false and noTable == false)
end)

-- A9: the two escaping rules, named apart. Esc doubles a pipe and leaves a
-- non-ASCII byte to the font; EscASCII is the probe's reversible escape.
try("MD.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)", function()
    local T = MD.Text
    local accented = "Penek\195\169"
    check("MD.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)",
        T.Esc("a|b") == "a||b" and T.Esc(accented) == accented
        and T.EscASCII("a|b") == "a||b" and T.EscASCII(accented) == "Penek\\195\\169"
        and T.EscASCII("c:\\x") == "c:\\\\x" and T.Esc(nil) == "" and T.EscASCII(12) == "12",
        T.EscASCII(accented))
end)

try("PrintSafe keeps a well-formed colour code and escapes the rest (A9)", function()
    local seen
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) seen = m end
    MD:PrintSafe("|cff888888grey|r a|b \195\169 |cffzz")
    frame.AddMessage = orig
    local want = "|cff888888grey|r a||b \\195\\169 ||cffzz"
    check("PrintSafe keeps a well-formed colour code and escapes the rest (A9)",
        type(seen) == "string" and seen:sub(-#want) == want, tostring(seen))
end)

try("MD.Util: Median copies, Clock and K format (A9)", function()
    local U = MD.Util
    local list = { 5, 1, 3, 2 }
    local m, mLow = U.Median(list), U.Median(list, "low")
    check("MD.Util: Median copies, Clock and K format (A9)",
        m == 2.5 and mLow == 2 and U.Median({ 3, 1, 2 }) == 2 and U.Median({}) == nil
        and list[1] == 5 and list[2] == 1
        and U.Clock(75) == "1:15" and U.Clock(75.25, true) == "1:15.2" and U.Clock(-3) == "0:00"
        and U.K(2345) == "2.3k" and U.K(2345, 10000) == "2345" and U.K(999.6) == "1000"
        and U.RECORD_GATE.sec == 20 and U.RECORD_GATE.casts == 5
        and MD.Rules.SUGGESTED_FLOOR == 0.4,
        string.format("median=%s low=%s", tostring(m), tostring(mLow)))
end)

--------------------------------------------------------------------------------
-- 6-10: forever only
--------------------------------------------------------------------------------

if flavour == "forever" then

try("an unknown command prints the Forever command list", function()
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    SlashCmdList.SPELLTUNER("nosuch")
    frame.AddMessage = orig
    local hasCommands, hasProbe, hasHelp = false, false, false
    for _, l in ipairs(lines) do
        if l:find("commands:", 1, true) then hasCommands = true end
        if l:find("/st probe", 1, true) then hasProbe = true end
        if l:find("/st help", 1, true) then hasHelp = true end
    end
    check("an unknown command prints the Forever command list", hasCommands and hasProbe and hasHelp)
end)

try("/st probe runs the probe through the core", function()
    SlashCmdList.SPELLTUNER("probe")
    local reports = SpellTunerDB and SpellTunerDB.probe and SpellTunerDB.probe.reports
    local rec = reports and reports["70009"]
    check("/st probe runs the probe through the core",
        type(rec) == "table" and type(rec.text) == "string"
        and rec.text:sub(1, #"SpellTuner probe ") == "SpellTuner probe ")
end)

try("/st probe clog runs nothing", function()
    local before = SpellTunerDB.probe.reports["70009"].at
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    SlashCmdList.SPELLTUNER("probe clog")
    frame.AddMessage = orig
    local after = SpellTunerDB.probe.reports["70009"].at
    local sawNotice = false
    for _, l in ipairs(lines) do
        if l:find("clog is gone", 1, true) then sawNotice = true end
    end
    check("/st probe clog runs nothing", sawNotice and after == before)
end)

try("nothing on the Forever TOC registers the combat log", function()
    MD:On("COMBAT_LOG_EVENT_UNFILTERED", function() end)
    local attempted = false
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "COMBAT_LOG_EVENT_UNFILTERED" then attempted = true end
        end
    end
    check("nothing on the Forever TOC registers the combat log",
        not attempted and type(S.forbidden) == "table" and #S.forbidden == 0)
end)

try("the kernel reads the client only through the adapter", function()
    local savedClass, savedName, savedGuid, savedLevel =
        S.units.player.class, S.units.player.name, S.units.player.guid, S.level
    S.units.player.class = S.Secret()
    S.units.player.name = S.Secret()
    S.units.player.guid = S.Secret()
    S.level = S.Secret()
    local callOk = pcall(function() MD:DetectProfile() end)
    S.units.player.class, S.units.player.name, S.units.player.guid, S.level =
        savedClass, savedName, savedGuid, savedLevel
    check("the kernel reads the client only through the adapter",
        callOk == true and MD.player.class == "UNKNOWN" and MD.player.level == 0
        and MD.player.guid == "" and MD.player.charKey:sub(1, 2) == "?-")
end)

end -- forever only

--------------------------------------------------------------------------------
-- 11-13: tbc only
--------------------------------------------------------------------------------

if flavour == "tbc" then

try("TBC keeps its talents, profile and slash chain", function()
    local before = MD.db.muted
    SlashCmdList.SPELLTUNER("mute")
    local mid = MD.db.muted
    SlashCmdList.SPELLTUNER("mute")
    local after = MD.db.muted
    check("TBC keeps its talents, profile and slash chain",
        type(MD.talents) == "table" and MD.cdb.profile.level == 64
        and mid == (not before) and after == before)
end)

try("TBC's login order is talents, MD_READY, profile", function()
    local order = {}
    MD:RegisterCallback("TALENTS_CHANGED", function() order[#order + 1] = "TALENTS_CHANGED" end)
    MD:RegisterCallback("MD_READY", function() order[#order + 1] = "MD_READY" end)
    local origWriteProfile = MD.WriteProfile
    MD.WriteProfile = function(...)
        order[#order + 1] = "WriteProfile"
        return origWriteProfile(...)
    end
    S.Fire("PLAYER_LOGIN")
    MD.WriteProfile = origWriteProfile
    check("TBC's login order is talents, MD_READY, profile",
        order[1] == "TALENTS_CHANGED" and order[2] == "MD_READY" and order[3] == "WriteProfile")
end)

try("TBC's unknown command prints its own help", function()
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    SlashCmdList.SPELLTUNER("nosuch")
    frame.AddMessage = orig
    local sawVerify = false
    for _, l in ipairs(lines) do
        if l:find("/st verify", 1, true) then sawVerify = true end
    end
    check("TBC's unknown command prints its own help", sawVerify)
end)

-- T52 (P8, review A31): PLAYER_LEVEL_UP's argument may be secret on Forever,
-- and Core.lua is on every TOC. Run under tbc because the forever stub refuses
-- to register PLAYER_LEVEL_UP (it is not in its FOREVER_EVENTS), so the
-- kernel's handler never exists there. A secret is stood in for here: a
-- marker table, an issecretvalue that recognises it (reached through the
-- adapter's new MD.API.Invalidate, since Has had already cached "absent"),
-- and a tonumber that hands a secret back unchanged -- as the client's does,
-- a secret number having type "number" -- where Lua's own answers nil for a
-- table. Storing the argument unasked then shows up as MD.player.level being
-- the marker.
try("a secret level from PLAYER_LEVEL_UP is not stored (A31)", function()
    assert(type(MD.API.Invalidate) == "function", "no MD.API.Invalidate") -- before any global moves
    local marker = setmetatable({}, {})
    local realTonumber, realIsSecret = tonumber, rawget(_G, "issecretvalue")
    _G.issecretvalue = function(v) return rawequal(v, marker) end
    MD.API.Invalidate("issecretvalue")
    _G.tonumber = function(v, base)
        if rawequal(v, marker) then return v end
        if base == nil then return realTonumber(v) end
        return realTonumber(v, base)
    end
    local fireOk, err = pcall(S.Fire, "PLAYER_LEVEL_UP", marker, 0, 0, 0, 0)
    _G.tonumber = realTonumber
    local stored = rawequal(MD.player.level, marker)
    local plain = (not stored) and MD.player.level == S.level
    _G.issecretvalue = realIsSecret
    MD.API.Invalidate("issecretvalue")
    MD.player.level = S.level
    local plainNow
    pcall(S.Fire, "PLAYER_LEVEL_UP", 65, 0, 0, 0, 0)
    plainNow = MD.player.level == 65
    MD.player.level = S.level
    check("a secret level from PLAYER_LEVEL_UP is not stored (A31)",
        fireOk == true and plain == true and plainNow == true,
        fireOk and ("stored=" .. tostring(stored) .. " plain65=" .. tostring(plainNow))
            or ("raised: " .. tostring(err)))
end)

-- T52 (P8, review B2): GetShapeshiftFormID answering nil means caster form;
-- the "Tree of Life" buff may be ANOTHER druid's aura (34123 carries the same
-- name). The buff scan is a fallback for a missing or raising API only. Both
-- names are in the buff list: Core_TBC.lua captured GetSpellInfo(33891) at
-- load, before the harness named 33891 "Tree of Life".
try("Tree form: the buff scan only when the form API is missing or raised (B2)", function()
    local savedBuffs, savedFn = S.buffs, rawget(_G, "GetShapeshiftFormID")
    S.buffs = { "Tree of Life", "Spell33891" }
    local answers = {}
    local runOk, err = pcall(function()
        _G.GetShapeshiftFormID = function() return nil end
        answers.answeredNil = MD:InTreeForm()
        _G.GetShapeshiftFormID = function() return 2 end
        answers.answeredTree = MD:InTreeForm()
        _G.GetShapeshiftFormID = function() error("stub: GetShapeshiftFormID raised") end
        answers.raised = MD:InTreeForm()
        _G.GetShapeshiftFormID = nil
        answers.absent = MD:InTreeForm()
    end)
    S.buffs, _G.GetShapeshiftFormID = savedBuffs, savedFn
    if not runOk then error(err, 0) end
    check("Tree form: the buff scan only when the form API is missing or raised (B2)",
        answers.answeredNil == false and answers.answeredTree == true
        and answers.raised == true and answers.absent == true,
        string.format("nil->%s 2->%s raised->%s absent->%s", tostring(answers.answeredNil),
            tostring(answers.answeredTree), tostring(answers.raised), tostring(answers.absent)))
end)

end -- tbc only

print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
