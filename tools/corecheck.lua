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
    print("0 ok, 13 failed")
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

end -- tbc only

print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
