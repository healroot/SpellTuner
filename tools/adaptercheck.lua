-- tools/run.sh --flavour forever tools/adaptercheck.lua
-- tools/run.sh --flavour tbc tools/adaptercheck.lua
--
-- T1/T1b: the shared adapter (Client/API.lua) plus its two per-flavour bindings
-- (Client/API_Forever.lua, Client/API_TBC.lua). Assertions 1-9 run under both
-- flavours, 10-15 under forever only, 16-17 under tbc only -- matching the
-- Facts in docs/tasks/T1-client-adapter.md about what is secret on which
-- client. Never runs under a flavour it did not declare (tools/harness.lua).
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local okLoad, MD = pcall(dofile, here .. "/harness.lua")
arg[0] = a0
if not okLoad then
    print("harness failed to load: " .. tostring(MD))
    os.exit(1)
end
local S = _G.STUB
local flavour = S.flavour

local SHARED_NAMES = {
    "UnitClass", "UnitName", "UnitLevel", "UnitGUID", "UnitExists", "UnitIsDeadOrGhost",
    "UnitAffectingCombat", "InCombatLockdown", "UnitHealth", "UnitHealthMax", "UnitPower",
    "UnitPowerMax", "UnitPowerType", "ManaRegen", "RealmName", "BuildInfo", "After", "NewTicker",
}
local ADDON_NAMES = { "AddOnMetadata", "IsAddOnLoaded", "LoadAddOn", "IsAddOnLoadOnDemand", "AddOnInfo" }

--------------------------------------------------------------------------------
-- 1-9: both flavours
--------------------------------------------------------------------------------

do
    local allNames = {}
    for _, n in ipairs(SHARED_NAMES) do allNames[#allNames + 1] = n end
    for _, n in ipairs(ADDON_NAMES) do allNames[#allNames + 1] = n end

    local allFunctions = true
    for _, n in ipairs(allNames) do
        if type(MD.API[n]) ~= "function" then allFunctions = false end
    end

    local caps = MD.API.Capabilities()
    local byName = {}
    local sorted = true
    for i, c in ipairs(caps) do
        byName[c.name] = c
        if i > 1 and caps[i - 1].name > c.name then sorted = false end
        if type(c.client) ~= "string" or type(c.present) ~= "boolean" then sorted = false end
    end
    local exactlyOne = true
    for _, n in ipairs(allNames) do
        if not byName[n] then exactlyOne = false end
    end

    check("every binding is on MD.API and in the capability table",
        allFunctions and #caps == #allNames and exactlyOne and sorted)
end

do
    MD.API.Bind({ T1Missing = "NoSuchNamespace.NoSuchFn" })
    local a, b = MD.API.T1Missing()
    local caps = MD.API.Capabilities()
    local present
    for _, c in ipairs(caps) do if c.name == "T1Missing" then present = c.present end end
    check("a missing client function answers nil, absent",
        a == nil and b == "absent" and present == false)
end

do
    _G.T1_RAISE = function() error("boom") end
    MD.API.Bind({ T1Raise = "T1_RAISE" })
    local a, b, c = MD.API.T1Raise()
    check("a raising client function answers nil, error",
        a == nil and b == "error" and type(c) == "string" and c:find("boom", 1, true) ~= nil)
end

do
    _G.T1_MULTI = function() return nil, 5, nil end
    MD.API.Bind({ T1Multi = "T1_MULTI" })
    local n1 = select("#", MD.API.T1Multi())
    local _, second = MD.API.T1Multi()
    check("every return comes back, nils in the middle kept", n1 == 3 and second == 5)
end

do
    local hadHas = MD.API.Has
    MD.API.Bind({ Has = "T1_MULTI" })
    local caps = MD.API.Capabilities()
    local hasEntry
    for _, c in ipairs(caps) do if c.name == "Has" then hasEntry = c end end
    check("Bind never replaces the adapter's own members",
        MD.API.Has == hadHas and hasEntry == nil)
end

do
    local expected
    local tocName = (flavour == "forever") and "SpellTuner_Mainline.toc" or "SpellTuner_TBC.toc"
    local f = io.open(ROOT .. "/" .. tocName, "r")
    if f then
        for line in f:lines() do
            local v = line:match("^## Version:%s*(.-)%s*$")
            if v then expected = v; break end
        end
        f:close()
    end
    check("AddonVersion reads the flavour's TOC", MD.API.AddonVersion() == expected,
        "got " .. tostring(MD.API.AddonVersion()) .. ", expected " .. tostring(expected))
end

do
    local seen
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) seen = m end
    MD.API.Print("t1-print-probe")
    frame.AddMessage = orig
    check("Print reaches the chat frame", seen == "t1-print-probe")
end

do
    -- T1b re-issue: DEFAULT_CHAT_FRAME is a variable the UI may reassign
    -- (a chat addon, a UI reload) -- Print must not trust a cached table.
    local originalFrame = _G.DEFAULT_CHAT_FRAME
    MD.API.Print("t1-print-old-frame")
    local oldSeen
    originalFrame.AddMessage = function(_, m) oldSeen = m end

    local newSeen
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) newSeen = m end }
    MD.API.Print("t1-print-new-frame")
    _G.DEFAULT_CHAT_FRAME = originalFrame

    check("Print follows the chat frame the UI has now",
        newSeen == "t1-print-new-frame" and oldSeen == nil)
end

do
    if flavour == "forever" then S.inCombat = false end
    local caps = MD.API.Capabilities()
    local okAll = pcall(function()
        for _, c in ipairs(caps) do
            MD.API[c.name]("player")
        end
        if flavour == "forever" then S.inCombat = true end
        for _, c in ipairs(caps) do
            MD.API[c.name]("player")
        end
        if flavour == "forever" then S.inCombat = false end
    end)
    check("no binding raises, whatever it is given", okAll == true)
end

--------------------------------------------------------------------------------
-- 10-15: forever only
--------------------------------------------------------------------------------

if flavour == "forever" then
    do
        S.inCombat = false
        local h1, hr1 = MD.API.UnitHealth("player")
        local p1, pr1 = MD.API.UnitPower("player", 0)
        S.inCombat = true
        local h2, hr2 = MD.API.UnitHealth("player")
        local p2, pr2 = MD.API.UnitPower("player", 0)
        S.inCombat = false
        check("current health and power are nil, secret, in and out of combat",
            h1 == nil and hr1 == "secret" and p1 == nil and pr1 == "secret"
            and h2 == nil and hr2 == "secret" and p2 == nil and pr2 == "secret")
    end

    do
        if not S.units.party1 then S.AddUnit("party1", { guid = "Party-1", name = "Bob", class = "PRIEST", hp = 4000, hpMax = 4000 }) end
        local hMax = MD.API.UnitHealthMax("player")
        local pMax = MD.API.UnitPowerMax("player", 0)
        local partyMax, reason = MD.API.UnitHealthMax("party1")
        check("the player's maxima are plain and a party member's health max is nil, secret",
            type(hMax) == "number" and type(pMax) == "number" and partyMax == nil and reason == "secret")
    end

    do
        S.inCombat = false
        local r1a, r1b = MD.API.ManaRegen()
        S.inCombat = true
        local r2, reason = MD.API.ManaRegen()
        S.inCombat = false
        check("GetManaRegen: two numbers out of combat, nil, secret in combat",
            type(r1a) == "number" and type(r1b) == "number" and r2 == nil and reason == "secret")
    end

    do
        check("the combat log is forbidden on Forever, other events are not",
            MD.API.CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == false
            and MD.API.CanRegisterEvent("UNIT_COMBAT") == true)
    end

    do
        local caps = MD.API.Capabilities()
        local byName = {}
        for _, c in ipairs(caps) do byName[c.name] = c end
        check("the add-on bindings are C_AddOns on Forever",
            byName.AddOnMetadata and byName.AddOnMetadata.client == "C_AddOns.GetAddOnMetadata"
            and byName.LoadAddOn and byName.LoadAddOn.client == "C_AddOns.LoadAddOn"
            and byName.IsAddOnLoaded and byName.IsAddOnLoaded.client == "C_AddOns.IsAddOnLoaded"
            and byName.IsAddOnLoadOnDemand and byName.IsAddOnLoadOnDemand.client == "C_AddOns.IsAddOnLoadOnDemand"
            and byName.AddOnInfo and byName.AddOnInfo.client == "C_AddOns.GetAddOnInfo"
            and byName.AddOnMetadata.present == true and byName.IsAddOnLoaded.present == true)
    end

    do
        local caps = MD.API.Capabilities()
        local values = {}
        S.inCombat = false
        for _, c in ipairs(caps) do
            local a, b = MD.API[c.name]("player")
            values[#values + 1] = a; values[#values + 1] = b
        end
        S.inCombat = true
        for _, c in ipairs(caps) do
            local a, b = MD.API[c.name]("player")
            values[#values + 1] = a; values[#values + 1] = b
        end
        local hMax = MD.API.UnitHealthMax("party1")
        local r = { MD.API.ManaRegen() }
        S.inCombat = false
        local none = true
        local function checkOne(v)
            local sv = (type(_G.issecretvalue) == "function") and select(2, pcall(_G.issecretvalue, v)) or false
            local st = (type(_G.issecrettable) == "function") and select(2, pcall(_G.issecrettable, v)) or false
            if sv == true or st == true then none = false end
        end
        for _, v in ipairs(values) do checkOne(v) end
        checkOne(hMax)
        for _, v in ipairs(r) do checkOne(v) end
        check("no secret ever leaves the adapter", none == true)
    end
end

--------------------------------------------------------------------------------
-- 16-17: tbc only
--------------------------------------------------------------------------------

if flavour == "tbc" then
    do
        local h = MD.API.UnitHealth("player")
        local p = MD.API.UnitPower("player", 0)
        local r1, r2 = MD.API.ManaRegen()
        check("TBC readings pass through plain",
            h == 5000 and p == 7009 and type(r1) == "number" and type(r2) == "number"
            and MD.API.CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == true
            and MD.API.IsSecret(5) == false)
    end

    do
        local caps = MD.API.Capabilities()
        local byName = {}
        for _, c in ipairs(caps) do byName[c.name] = c end
        check("the add-on bindings are the classic globals on TBC",
            byName.AddOnMetadata and byName.AddOnMetadata.client == "GetAddOnMetadata"
            and byName.LoadAddOn and byName.LoadAddOn.client == "LoadAddOn"
            and byName.IsAddOnLoaded and byName.IsAddOnLoaded.client == "IsAddOnLoaded"
            and byName.IsAddOnLoadOnDemand and byName.IsAddOnLoadOnDemand.client == "IsAddOnLoadOnDemand"
            and byName.AddOnInfo and byName.AddOnInfo.client == "GetAddOnInfo")
    end
end

_G.T1_RAISE = nil
_G.T1_MULTI = nil

print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
