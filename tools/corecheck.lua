-- tools/run.sh --flavour forever tools/corecheck.lua
-- tools/run.sh --flavour tbc tools/corecheck.lua
--
-- T1b: Core.lua splits into the shared kernel (namespace, event dispatch,
-- pub/sub, ticker, Print/Alert/Debug, player identity, SavedVariables init,
-- login sequence, the slash dispatcher and command registry -- every TOC)
-- and Core_TBC.lua / Core_Forever.lua, one flavour each, hanging off the
-- kernel's CORE_LOGIN/CORE_READY callbacks and ST:AddCommand.
-- Assertions 1-5 run under both flavours, 6-10 under forever only, 11-13
-- under tbc only (docs/tasks/T1b-shared-core.md Acceptance 1).
-- T52 (P8, review B1, B2, A31): three more under both flavours (whether the
-- player has a mana pool is read from UnitPowerMax(..., 0), the power type only
-- when that read is unreadable) and two more under tbc (a secret level from
-- PLAYER_LEVEL_UP is never stored -- tbc because the forever stub cannot
-- register that event; Tree form: the buff scan only when GetShapeshiftFormID
-- is missing or raised) -- 13 forever, 13 tbc.
-- T55 (P11, review A3, A4, A9, A16, A28): nine more under both flavours --
-- a raising handler stops neither ST:On's nor ST:Fire's loop and reaches the
-- error handler once, with no handler at all the loop re-raises after every
-- handler ran, RegisterDefaults back-fills after login without overwriting,
-- ST.inCombat seeded from the adapter and flipped by the regen events,
-- Provide refusing a second provider, ST.Text's two escapes, PrintSafe, and
-- ST.Util -- 22 forever, 22 tbc.
-- T61 (P17, review A1): two more under both flavours -- every verb the
-- flavour registers is in ST:Commands() (and the help is exactly its listed
-- rows; on tbc ST.COMMANDS and ST.SlashFallback are gone), and an alias runs
-- its verb without a second row -- 24 forever, 24 tbc.
-- T113 (docs/SPEC-next.md 2.5, S0): five more under both flavours -- a sub
-- runs before the verb; every other argument reaches the verb unchanged
-- (/st clock, /st clock lock, /st ui reset on forever, /md window on tbc);
-- ST:AddCommand after ST:AddSubcommand keeps the subs, in both load orders; a
-- sub on an unknown verb creates it with its usage printer; the verb's help
-- row gains the sub's usage -- 29 forever, 29 tbc.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- Runs one assertion's body under pcall: before the split, most of these
-- raise outright (ST.player, ST.AddCommand, ... do not exist yet on the
-- flavour under test) -- a raise must still be reported as a named failure,
-- not stop the suite from trying the rest.
local function try(name, body)
    local runOk, err = pcall(body)
    if not runOk then check(name, false, "raised: " .. tostring(err)) end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local okLoad, ST = pcall(dofile, here .. "/harness.lua")
arg[0] = a0
if not okLoad then
    print("harness failed to load: " .. tostring(ST))
    print("0 ok, 29 failed")
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
        _G.SpellTuner == ST
        and ST.version == expectedVersion
        and type(ST.db) == "table"
        and ST.player.class == "DRUID"
        and ST.player.charKey == "Penek-Anniversary")
end)

try("events, callbacks and the ticker run", function()
    local gotArgs
    ST:On("UNIT_COMBAT", function(...) gotArgs = { ... } end)
    S.Fire("UNIT_COMBAT", "party1", "HEAL", "", 120, 1)

    local cbA, cbB
    ST:RegisterCallback("CoreCheckCB", function(a, b) cbA, cbB = a, b end)
    ST:Fire("CoreCheckCB", "x", "y")

    local ticked = false
    ST:OnTick(function() ticked = true end)
    S.Tick(0.5)

    check("events, callbacks and the ticker run",
        gotArgs and gotArgs[1] == "party1" and gotArgs[2] == "HEAL" and gotArgs[3] == ""
        and gotArgs[4] == 120 and gotArgs[5] == 1
        and cbA == "x" and cbB == "y" and ticked == true)
end)

try("an event the adapter refuses is never attempted", function()
    ST.API.ForbidEvent("PLAYER_TARGET_CHANGED")
    ST:On("PLAYER_TARGET_CHANGED", function() end)
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
    ST:AddCommand("t1btest", function(arg, rawArg) gotArg, gotRaw = arg, rawArg end)
    SlashCmdList.SPELLTUNER("  T1BTest Blood Furnace ")
    check("a registered command gets its argument and the raw text",
        gotArg == "blood furnace" and gotRaw == "Blood Furnace")
end)

try("Print goes through the adapter to the chat frame", function()
    local seen
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) seen = m end
    ST:Print("hello")
    frame.AddMessage = orig
    check("Print goes through the adapter to the chat frame",
        type(seen) == "string" and seen:find("SpellTuner:", 1, true) ~= nil
        and seen:find("hello", 1, true) ~= nil)
end)

-- T52 (P8, review B1): usesMana is whether the player HAS a mana pool, read
-- from UnitPowerMax("player", 0) -- a druid who logs in or reloads in Cat or
-- Bear form still has one. Each case re-runs the login's own read
-- (ST:DetectProfile) and puts the stub back afterwards, whatever happened.
local function WithPower(setup, body)
    local savedType, savedMax, savedClass = S.powerType, S.powerMax, S.units.player.class
    S.powerMax = {}
    local runOk, err = pcall(function() setup(); body() end)
    S.powerType, S.powerMax, S.units.player.class = savedType, savedMax, savedClass
    ST:DetectProfile()
    if not runOk then error(err, 0) end
end

try("a login in Cat form keeps the mana side (B1)", function()
    WithPower(function() S.powerType = 3 end, function()
        ST:DetectProfile()
        check("a login in Cat form keeps the mana side (B1)",
            ST.player.usesMana == true and ST.player.isDruid == true,
            "usesMana=" .. tostring(ST.player.usesMana))
    end)
end)

try("a class with no mana pool does not use mana (B1)", function()
    WithPower(function()
        S.units.player.class = "WARRIOR"
        S.powerType = 1
        S.powerMax[0] = 0
    end, function()
        ST:DetectProfile()
        check("a class with no mana pool does not use mana (B1)",
            ST.player.usesMana == false, "usesMana=" .. tostring(ST.player.usesMana))
    end)
end)

-- Forever: the max comes back secret. TBC has no secrets, so the unreadable
-- case there is a UnitPowerMax that raises -- swapped in through the
-- adapter's new ST.API.Invalidate (the Has cache would otherwise keep the
-- stub's function forever). Either way the power type decides (3: no mana).
try("an unreadable mana max falls back to the power type (B1)", function()
    local realMax = _G.UnitPowerMax
    local ranRaise = false
    local function Restore()
        _G.UnitPowerMax = realMax
        if flavour ~= "forever" and ST.API.Invalidate then ST.API.Invalidate("UnitPowerMax") end
    end
    local runOk, err = pcall(WithPower, function()
        S.powerType = 3
        if flavour == "forever" then
            S.powerMax[0] = S.Secret()
        else
            _G.UnitPowerMax = function() ranRaise = true; error("stub: UnitPowerMax raised") end
            ST.API.Invalidate("UnitPowerMax")
        end
    end, function()
        local callOk = pcall(function() ST:DetectProfile() end)
        local usesMana = ST.player.usesMana
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
    ST.API.Invalidate("geterrorhandler")
    local runOk, err = pcall(body)
    _G.geterrorhandler = real
    ST.API.Invalidate("geterrorhandler")
    if not runOk then error(err, 0) end
end

-- A4: one raise no longer stops the handlers after it. The raising handler is
-- armed only for its own firing (a handler cannot be unregistered).
local armedOn, armedFire = false, false
ST:On("UNIT_COMBAT", function() if armedOn then error("corecheck: raised in ST:On", 0) end end)
local secondOnRan = false
ST:On("UNIT_COMBAT", function() if armedOn then secondOnRan = true end end)
ST:RegisterCallback("CoreCheckRaise", function() if armedFire then error("corecheck: raised in ST:Fire", 0) end end)
local secondFireRan = false
ST:RegisterCallback("CoreCheckRaise", function() if armedFire then secondFireRan = true end end)

try("a raising ST:On handler stops nothing and reaches the handler once (A4)", function()
    local seen = {}
    local fireOk
    WithErrorHandler(function(msg) seen[#seen + 1] = msg end, function()
        armedOn = true
        fireOk = pcall(S.Fire, "UNIT_COMBAT", "player", "HEAL", "", 10, 1)
        armedOn = false
    end)
    check("a raising ST:On handler stops nothing and reaches the handler once (A4)",
        fireOk == true and secondOnRan == true and #seen == 1
        and seen[1] == "corecheck: raised in ST:On",
        "fired=" .. tostring(fireOk) .. " second=" .. tostring(secondOnRan) .. " seen=" .. #seen)
end)

try("a raising ST:Fire callback stops nothing and reaches the handler once (A4)", function()
    local seen = {}
    local fireOk
    WithErrorHandler(function(msg) seen[#seen + 1] = msg end, function()
        armedFire = true
        fireOk = pcall(ST.Fire, ST, "CoreCheckRaise")
        armedFire = false
    end)
    check("a raising ST:Fire callback stops nothing and reaches the handler once (A4)",
        fireOk == true and secondFireRan == true and #seen == 1
        and seen[1] == "corecheck: raised in ST:Fire",
        "fired=" .. tostring(fireOk) .. " second=" .. tostring(secondFireRan) .. " seen=" .. #seen)
end)

-- With no error handler to sink into (only a stub lacks one) the error is not
-- swallowed: it is raised after every handler ran, so a suite goes red.
try("with no error handler the loop re-raises after every handler ran (A4)", function()
    secondFireRan = false
    local fireOk, err
    WithErrorHandler(nil, function()
        armedFire = true
        fireOk, err = pcall(ST.Fire, ST, "CoreCheckRaise")
        armedFire = false
    end)
    check("with no error handler the loop re-raises after every handler ran (A4)",
        fireOk == false and err == "corecheck: raised in ST:Fire" and secondFireRan == true,
        "fired=" .. tostring(fireOk) .. " err=" .. tostring(err))
end)

-- A3: a feature file registering its defaults after login fills what the
-- player does not have and leaves what they set; a second, different default
-- for the same key raises; ST:Setting falls back to the registered default.
try("RegisterDefaults after login back-fills and never overwrites (A3)", function()
    ST.db.coreCheckKept = "user"
    ST.db.coreCheckOff = false
    ST:RegisterDefaults({ coreCheckKept = "default", coreCheckNew = 3,
                          coreCheckOff = true, coreCheckNest = { a = 1 } })
    local filled = ST.db.coreCheckKept == "user" and ST.db.coreCheckNew == 3
        and ST.db.coreCheckOff == false and type(ST.db.coreCheckNest) == "table"
        and ST.db.coreCheckNest.a == 1
    local sameOk = pcall(ST.RegisterDefaults, ST, { coreCheckNew = 3 })
    local otherOk, otherErr = pcall(ST.RegisterDefaults, ST, { coreCheckNew = 4 })
    local nestOk = pcall(ST.RegisterDefaults, ST, { coreCheckNest = { a = 2 } })
    ST.db.coreCheckNew = nil
    local setting = ST:Setting("coreCheckNew")
    local stored = ST:Setting("coreCheckOff")
    check("RegisterDefaults after login back-fills and never overwrites (A3)",
        filled and sameOk and otherOk == false and nestOk == false
        and type(otherErr) == "string" and otherErr:find("coreCheckNew", 1, true) ~= nil
        and setting == 3 and stored == false,
        string.format("filled=%s same=%s other=%s nest=%s setting=%s stored=%s", tostring(filled),
            tostring(sameOk), tostring(otherOk), tostring(nestOk), tostring(setting), tostring(stored)))
end)

-- A28: the flag is seeded at MD_READY from the adapter (a /reload mid-fight
-- starts in combat), an unreadable answer leaves it, the regen events flip it.
try("ST.inCombat seeded from the adapter, flipped by the regen events (A28)", function()
    local real = rawget(_G, "UnitAffectingCombat")
    local seeded, kept, afterEnd, afterStart
    local runOk, err = pcall(function()
        _G.UnitAffectingCombat = function() return true end
        ST.API.Invalidate("UnitAffectingCombat")
        ST.inCombat = false
        ST:Fire("MD_READY")
        seeded = ST.inCombat
        _G.UnitAffectingCombat = function() error("stub: UnitAffectingCombat raised") end
        ST.API.Invalidate("UnitAffectingCombat")
        ST:Fire("MD_READY")
        kept = ST.inCombat
        _G.UnitAffectingCombat = real
        ST.API.Invalidate("UnitAffectingCombat")
        S.Fire("PLAYER_REGEN_ENABLED")
        afterEnd = ST.inCombat
        S.Fire("PLAYER_REGEN_DISABLED")
        afterStart = ST.inCombat
        S.Fire("PLAYER_REGEN_ENABLED")
    end)
    _G.UnitAffectingCombat = real
    ST.API.Invalidate("UnitAffectingCombat")
    if not runOk then error(err, 0) end
    check("ST.inCombat seeded from the adapter, flipped by the regen events (A28)",
        seeded == true and kept == true and afterEnd == false and afterStart == true
        and ST.inCombat == false,
        string.format("seeded=%s kept=%s end=%s start=%s", tostring(seeded), tostring(kept),
            tostring(afterEnd), tostring(afterStart)))
end)

-- A16: a seam has one provider; the second raises and names it.
try("Provide fills a seam once and refuses a second provider (A16)", function()
    local fn1, fn2 = function() return 1 end, function() return 2 end
    ST:Provide("CoreCheckSeam", fn1)
    local secondOk, secondErr = pcall(ST.Provide, ST, "CoreCheckSeam", fn2)
    ST.CoreCheckTable = {}
    ST:Provide("CoreCheckTable.Pin", fn1)
    local dottedAgain = pcall(ST.Provide, ST, "CoreCheckTable.Pin", fn2)
    local noTable = pcall(ST.Provide, ST, "NoSuchTable.Pin", fn1)
    check("Provide fills a seam once and refuses a second provider (A16)",
        ST.CoreCheckSeam == fn1 and secondOk == false and type(secondErr) == "string"
        and secondErr:find("CoreCheckSeam", 1, true) ~= nil
        and ST.CoreCheckTable.Pin == fn1 and dottedAgain == false and noTable == false)
end)

-- A9: the two escaping rules, named apart. Esc doubles a pipe and leaves a
-- non-ASCII byte to the font; EscASCII is the probe's reversible escape.
try("ST.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)", function()
    local T = ST.Text
    local accented = "Penek\195\169"
    check("ST.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)",
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
    ST:PrintSafe("|cff888888grey|r a|b \195\169 |cffzz")
    frame.AddMessage = orig
    local want = "|cff888888grey|r a||b \\195\\169 ||cffzz"
    check("PrintSafe keeps a well-formed colour code and escapes the rest (A9)",
        type(seen) == "string" and seen:sub(-#want) == want, tostring(seen))
end)

try("ST.Util: Median copies, Clock and K format (A9)", function()
    local U = ST.Util
    local list = { 5, 1, 3, 2 }
    local m, mLow = U.Median(list), U.Median(list, "low")
    check("ST.Util: Median copies, Clock and K format (A9)",
        m == 2.5 and mLow == 2 and U.Median({ 3, 1, 2 }) == 2 and U.Median({}) == nil
        and list[1] == 5 and list[2] == 1
        and U.Clock(75) == "1:15" and U.Clock(75.25, true) == "1:15.2" and U.Clock(-3) == "0:00"
        and U.K(2345) == "2.3k" and U.K(2345, 10000) == "2345" and U.K(999.6) == "1000"
        and U.RECORD_GATE.sec == 20 and U.RECORD_GATE.casts == 5
        and ST.Rules.SUGGESTED_FLOOR == 0.4,
        string.format("median=%s low=%s", tostring(m), tostring(mLow)))
end)

--------------------------------------------------------------------------------
-- T61 (P17, review A1): one command registry on both lines, both flavours
--------------------------------------------------------------------------------

-- Every verb each flavour's harness registers: names, then aliases (an alias
-- is a second spelling of a verb, listed under it). corecheck's own t1btest
-- (and its t1balias below) are left out of the comparison.
local VERBS = {
    tbc = {
        names = { "", "help", "options", "lock", "unlock", "reset", "mute", "drink", "rest",
                  "tooltip", "binds", "practice", "spelltip", "window", "verify", "profile",
                  "export", "calibrate", "fsrtest", "regentest", "spamtest", "simrun",
                  "simreplay", "coach", "sim", "replay", "run", "coachrun", "debug", "probe" },
        aliases = { config = "options", settings = "options", bindings = "binds",
                    tip = "tooltip", calib = "calibrate" },
    },
    forever = {
        names = { "debug", "dump", "", "help", "tooltip", "clock", "measure", "ui", "spell",
                  "modules", "probe" },
        aliases = {},
    },
}
local OWN = { t1btest = true, t1balias = true, t113verb = true, t113new = true, t113late = true,
              t113early = true, t113row = true }

-- The help as printed, colour codes out, the prefix and the row's "  " gone.
local function HelpRows()
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    SlashCmdList.SPELLTUNER("help")
    frame.AddMessage = orig
    local rows = {}
    for i = 2, #lines do
        local plain = lines[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        rows[#rows + 1] = plain:gsub("^SpellTuner:   ", "") -- the prefix and the row's indent
    end
    return rows
end

try("every verb is in ST:Commands() and the help is its listed rows (A1)", function()
    local want = VERBS[flavour]
    local list = ST:Commands()
    local byName, aliasOf, problems = {}, {}, {}
    for _, c in ipairs(list) do
        if byName[c.name] then problems[#problems + 1] = "twice: " .. c.name end
        byName[c.name] = c
        for _, a in ipairs(c.aliases or {}) do aliasOf[a] = c.name end
    end
    for _, n in ipairs(want.names) do
        if not byName[n] then problems[#problems + 1] = "missing: '" .. n .. "'" end
    end
    for a, n in pairs(want.aliases) do
        if aliasOf[a] ~= n then problems[#problems + 1] = "alias " .. a .. " -> " .. tostring(aliasOf[a]) end
    end
    local known = {}
    for _, n in ipairs(want.names) do known[n] = true end
    for n in pairs(byName) do
        if not known[n] and not OWN[n] then problems[#problems + 1] = "unexpected: '" .. n .. "'" end
    end
    -- the listed entries, in order, are exactly the rows /st help prints
    local rows, listed = HelpRows(), {}
    for _, c in ipairs(list) do
        if not c.hidden then listed[#listed + 1] = c.usage .. " - " .. c.text end
    end
    local same = #rows == #listed
    for i = 1, #rows do if rows[i] ~= listed[i] then same = false end end
    if not same then problems[#problems + 1] = string.format("help %d rows, listed %d", #rows, #listed) end
    if flavour == "tbc" and (ST.COMMANDS ~= nil or ST.SlashFallback ~= nil) then
        problems[#problems + 1] = "ST.COMMANDS / ST.SlashFallback still defined"
    end
    check("every verb is in ST:Commands() and the help is its listed rows (A1)",
        #problems == 0, problems[1])
end)

try("an alias runs its verb and is not listed twice (A1)", function()
    local gotArg, gotRaw
    ST:AddCommand("t1btest", function(arg, rawArg) gotArg, gotRaw = arg, rawArg end)
    ST:AddAlias("t1balias", "t1btest")
    SlashCmdList.SPELLTUNER("T1BAlias Blood Furnace")
    local entries, aliasListed = 0, false
    for _, c in ipairs(ST:Commands()) do
        if c.name == "t1btest" then entries = entries + 1 end
        if c.name == "t1balias" then aliasListed = true end
    end
    local calibOk = true
    if flavour == "tbc" then
        -- a real alias: /md calib is /md calibrate, and the help says calibrate once
        local saved, ran = ST.RunCalibrate, 0
        ST.RunCalibrate = function() ran = ran + 1 end
        SlashCmdList.SPELLTUNER("calib")
        ST.RunCalibrate = saved
        local rows, seen = HelpRows(), 0
        for _, r in ipairs(rows) do
            if r:find("calib", 1, true) then seen = seen + 1 end
        end
        calibOk = ran == 1 and seen == 1
    end
    check("an alias runs its verb and is not listed twice (A1)",
        gotArg == "blood furnace" and gotRaw == "Blood Furnace" and entries == 1
        and not aliasListed and calibOk,
        string.format("arg=%s entries=%d aliasListed=%s calib=%s", tostring(gotArg), entries,
            tostring(aliasListed), tostring(calibOk)))
end)

--------------------------------------------------------------------------------
-- T113 (docs/SPEC-next.md 2.5, S0): subcommands, both flavours
--------------------------------------------------------------------------------

-- Every chat line a slash command prints, the colour codes out.
local function Said(msg)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local runOk, err = pcall(SlashCmdList.SPELLTUNER, msg)
    frame.AddMessage = orig
    if not runOk then error(err, 0) end
    for i, l in ipairs(lines) do lines[i] = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    return lines
end

local function RowOf(name)
    for _, c in ipairs(ST:Commands()) do
        if c.name == name then return c end
    end
end

try("a sub runs before the verb, its first word matched in any case (T113)", function()
    local verbGot, subGot, subRaw = {}, nil, nil
    ST:AddCommand("t113verb", function(arg, rawArg) verbGot[#verbGot + 1] = { arg, rawArg } end,
        "/st t113verb", "a test verb")
    ST:AddSubcommand("t113verb", "style", function(rest, rawRest) subGot, subRaw = rest, rawRest end,
        "style <name>")
    SlashCmdList.SPELLTUNER("T113Verb STYLE  Blood Furnace ")
    local subFirst = subGot == "blood furnace" and subRaw == "Blood Furnace" and #verbGot == 0
    SlashCmdList.SPELLTUNER("t113verb style")
    local bare = subGot == "" and subRaw == "" and #verbGot == 0
    SlashCmdList.SPELLTUNER("t113verb styles Classic")
    local other = #verbGot == 1 and verbGot[1][1] == "styles classic" and verbGot[1][2] == "styles Classic"
    check("a sub runs before the verb, its first word matched in any case (T113)",
        subFirst and bare and other,
        string.format("sub=%s raw=%s verbCalls=%d", tostring(subGot), tostring(subRaw), #verbGot))
end)

try("every other argument reaches the verb unchanged (T113)", function()
    local subRuns = 0
    local function Sub() subRuns = subRuns + 1 end
    local problems = {}
    if flavour == "forever" then
        ST:AddSubcommand("clock", "t113sub", Sub, "t113sub")
        ST:AddSubcommand("ui", "t113sub", Sub, "t113sub")
        ST.db.clock = ST.db.clock or {}
        local shown, locked = ST.db.clock.shown, ST.db.clock.locked
        local said = Said("clock")
        if ST.db.clock.shown == shown or not (said[1] or ""):find("mana clock: ", 1, true) then
            problems[#problems + 1] = "/st clock did not toggle the clock"
        end
        said = Said("clock lock")
        if ST.db.clock.locked == locked or ST.db.clock.shown == shown
            or not (said[1] or ""):find("mana clock: ", 1, true) then
            problems[#problems + 1] = "/st clock lock did not toggle the lock alone"
        end
        local savedWin, resets = ST.Win, 0
        ST.Win = { Reset = function() resets = resets + 1 end }
        local okUi, errUi = pcall(function()
            said = Said("ui reset")
            if resets ~= 1 or not (said[1] or ""):find("every position and size reset", 1, true) then
                problems[#problems + 1] = "/st ui reset did not reset"
            end
            said = Said("ui")
            if resets ~= 1 or said[1] ~= "SpellTuner: usage: /st ui reset" then
                problems[#problems + 1] = "/st ui said " .. tostring(said[1])
            end
        end)
        ST.Win = savedWin
        if not okUi then error(errUi, 0) end
        Said("clock t113sub x")
        Said("ui t113sub")
        ST.db.clock.shown, ST.db.clock.locked = shown, locked
    else
        ST:AddSubcommand("window", "t113sub", Sub, "t113sub")
        local half = ST.db.halfLife
        local said = Said("window 20")
        if ST.db.halfLife ~= 20 or not (said[1] or ""):find("half-life set to 20s", 1, true) then
            problems[#problems + 1] = "/md window 20 did not set the half-life"
        end
        said = Said("window")
        if not (said[1] or ""):find("usage: /md window N", 1, true) then
            problems[#problems + 1] = "/md window said " .. tostring(said[1])
        end
        Said("window t113sub")
        Said("window T113SUB")
        ST.db.halfLife = half
    end
    if subRuns ~= 2 then problems[#problems + 1] = "the subs ran " .. subRuns .. " times, not 2" end
    check("every other argument reaches the verb unchanged (T113)", #problems == 0, problems[1])
end)

try("AddCommand after AddSubcommand keeps the subs, both load orders (T113)", function()
    local log = {}
    local function Rec(tag) return function(arg) log[#log + 1] = tag .. ":" .. arg end end
    -- the verb first, then its sub, then the verb again (a later file re-registering it)
    ST:AddCommand("t113early", Rec("verb1"), "/st t113early", "first")
    ST:AddSubcommand("t113early", "go", Rec("sub"), "go <x>")
    ST:AddCommand("t113early", Rec("verb2"), "/st t113early [y]", "second")
    SlashCmdList.SPELLTUNER("t113early go a")
    SlashCmdList.SPELLTUNER("t113early b")
    -- the sub first (it creates the verb), then the verb
    ST:AddSubcommand("t113late", "go", Rec("lsub"), "go <x>")
    ST:AddCommand("t113late", Rec("lverb"), "/st t113late [y]", "late")
    SlashCmdList.SPELLTUNER("t113late go c")
    SlashCmdList.SPELLTUNER("t113late d")
    local want = { "sub:a", "verb2:b", "lsub:c", "lverb:d" }
    local same = #log == #want
    for i = 1, #want do if log[i] ~= want[i] then same = false end end
    local early, late = RowOf("t113early"), RowOf("t113late")
    local rows = early and late
        and early.usage == "/st t113early [y] / go <x>" and early.text == "second"
        and late.usage == "/st t113late [y] / go <x>" and late.text == "late"
    local count = 0
    for _, c in ipairs(ST:Commands()) do
        if c.name == "t113early" or c.name == "t113late" then count = count + 1 end
    end
    check("AddCommand after AddSubcommand keeps the subs, both load orders (T113)",
        same and rows and count == 2,
        table.concat(log, ",") .. " early=" .. tostring(early and early.usage)
            .. " late=" .. tostring(late and late.usage) .. " rows=" .. count)
end)

try("a sub on an unknown verb creates it with its usage printer (T113)", function()
    local got
    ST:AddSubcommand("T113New", "Go", function(rest, rawRest) got = rawRest end, "go <name>", "go somewhere")
    ST:AddSubcommand("t113new", "stay", function() end, "stay", "stay here")
    local said = Said("t113new")
    local printer = #said == 2 and said[1] == "SpellTuner: usage: /st t113new go <name>"
        and said[2] == "SpellTuner: usage: /st t113new stay"
    Said("t113new GO Blood Furnace")
    local row = RowOf("t113new")
    check("a sub on an unknown verb creates it with its usage printer (T113)",
        printer and got == "Blood Furnace" and row ~= nil and row.hidden == false
        and row.usage == "/st t113new go <name> / stay" and row.text == "go somewhere; stay here",
        "said=" .. tostring(said[1]) .. " row=" .. tostring(row and row.usage) .. " got=" .. tostring(got))
end)

try("the verb's help row gains the sub's usage, one row per verb (T113)", function()
    ST:AddCommand("t113row", function() end, "/st t113row [x]", "row text")
    local function RowsFor()
        local found = {}
        for _, r in ipairs(HelpRows()) do
            if r:find("t113row", 1, true) then found[#found + 1] = r end
        end
        return found
    end
    local before = RowsFor()
    ST:AddSubcommand("t113row", "style", function() end, "style <name>")
    local after = RowsFor()
    ST:AddSubcommand("t113row", "style", function() end, "style <key>") -- again: replaced in place
    local again = RowsFor()
    local c = RowOf("t113row")
    check("the verb's help row gains the sub's usage, one row per verb (T113)",
        #before == 1 and before[1] == "/st t113row [x] - row text"
        and #after == 1 and after[1] == "/st t113row [x] / style <name> - row text"
        and #again == 1 and again[1] == "/st t113row [x] / style <key> - row text"
        and c ~= nil and c.usage == "/st t113row [x] / style <key>",
        tostring(before[1]) .. " | " .. tostring(after[1]) .. " | " .. tostring(again[1]))
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
    ST:On("COMBAT_LOG_EVENT_UNFILTERED", function() end)
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
    local callOk = pcall(function() ST:DetectProfile() end)
    S.units.player.class, S.units.player.name, S.units.player.guid, S.level =
        savedClass, savedName, savedGuid, savedLevel
    check("the kernel reads the client only through the adapter",
        callOk == true and ST.player.class == "UNKNOWN" and ST.player.level == 0
        and ST.player.guid == "" and ST.player.charKey:sub(1, 2) == "?-")
end)

end -- forever only

--------------------------------------------------------------------------------
-- 11-13: tbc only
--------------------------------------------------------------------------------

if flavour == "tbc" then

try("TBC keeps its talents, profile and slash chain", function()
    local before = ST.db.muted
    SlashCmdList.SPELLTUNER("mute")
    local mid = ST.db.muted
    SlashCmdList.SPELLTUNER("mute")
    local after = ST.db.muted
    check("TBC keeps its talents, profile and slash chain",
        type(ST.talents) == "table" and ST.cdb.profile.level == 64
        and mid == (not before) and after == before)
end)

try("TBC's login order is talents, MD_READY, profile", function()
    local order = {}
    ST:RegisterCallback("TALENTS_CHANGED", function() order[#order + 1] = "TALENTS_CHANGED" end)
    ST:RegisterCallback("MD_READY", function() order[#order + 1] = "MD_READY" end)
    local origWriteProfile = ST.WriteProfile
    ST.WriteProfile = function(...)
        order[#order + 1] = "WriteProfile"
        return origWriteProfile(...)
    end
    S.Fire("PLAYER_LOGIN")
    ST.WriteProfile = origWriteProfile
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
-- adapter's new ST.API.Invalidate, since Has had already cached "absent"),
-- and a tonumber that hands a secret back unchanged -- as the client's does,
-- a secret number having type "number" -- where Lua's own answers nil for a
-- table. Storing the argument unasked then shows up as ST.player.level being
-- the marker.
try("a secret level from PLAYER_LEVEL_UP is not stored (A31)", function()
    assert(type(ST.API.Invalidate) == "function", "no ST.API.Invalidate") -- before any global moves
    local marker = setmetatable({}, {})
    local realTonumber, realIsSecret = tonumber, rawget(_G, "issecretvalue")
    _G.issecretvalue = function(v) return rawequal(v, marker) end
    ST.API.Invalidate("issecretvalue")
    _G.tonumber = function(v, base)
        if rawequal(v, marker) then return v end
        if base == nil then return realTonumber(v) end
        return realTonumber(v, base)
    end
    local fireOk, err = pcall(S.Fire, "PLAYER_LEVEL_UP", marker, 0, 0, 0, 0)
    _G.tonumber = realTonumber
    local stored = rawequal(ST.player.level, marker)
    local plain = (not stored) and ST.player.level == S.level
    _G.issecretvalue = realIsSecret
    ST.API.Invalidate("issecretvalue")
    ST.player.level = S.level
    local plainNow
    pcall(S.Fire, "PLAYER_LEVEL_UP", 65, 0, 0, 0, 0)
    plainNow = ST.player.level == 65
    ST.player.level = S.level
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
        answers.answeredNil = ST:InTreeForm()
        _G.GetShapeshiftFormID = function() return 2 end
        answers.answeredTree = ST:InTreeForm()
        _G.GetShapeshiftFormID = function() error("stub: GetShapeshiftFormID raised") end
        answers.raised = ST:InTreeForm()
        _G.GetShapeshiftFormID = nil
        answers.absent = ST:InTreeForm()
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
