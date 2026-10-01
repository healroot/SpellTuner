-- tools/run.sh --flavour forever tools/adaptercheck.lua
-- tools/run.sh --flavour tbc tools/adaptercheck.lua
--
-- T1/T1b: the shared adapter (Client/API.lua) plus its two per-flavour bindings
-- (Client/API_Forever.lua, Client/API_TBC.lua). Assertions 1-12 run under both
-- flavours (10-12 added by T7: Copy/Constant/a copying binding), 13-18 under
-- forever only, 19-20 under tbc only -- matching the Facts in
-- docs/tasks/T1-client-adapter.md about what is secret on which client. Never
-- runs under a flavour it did not declare (tools/harness.lua).
-- T52 (P8): one more under both flavours, MD.API.Invalidate (23 forever, 16 tbc).
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
    -- T3: the three error-capture bindings, added to Client/API.lua's shared
    -- Bind call alongside the rest of this list.
    "GetErrorHandler", "SetErrorHandler", "DebugStack",
    -- T16a (UI/ReplayWindow.lua, Modules/SpellTuner_Replay/Commands_Forever.lua):
    -- the modifier-key predicates, the same global on both clients.
    "IsShiftKeyDown", "IsAltKeyDown", "IsControlKeyDown",
    -- T16a: SpellTexture is now bound on both -- Forever's own C_Spell.
    -- GetSpellTexture (T7) and TBC's own GetSpellTexture (Client/API_TBC.lua).
    "SpellTexture",
}
local ADDON_NAMES = { "AddOnMetadata", "IsAddOnLoaded", "LoadAddOn", "IsAddOnLoadOnDemand", "AddOnInfo" }
-- T7: Client/API_Forever.lua's own spellbook/spell bindings -- forever only,
-- so the exhaustiveness check below only expects them under that flavour.
local FOREVER_ONLY_NAMES = {
    "SpellBookItemInfo", "SpellBookSkillLines", "SpellBookSkillLineInfo",
    "SpellBookItemIsLowRank", "SpellKnown", "SpellName", "SpellSubtext",
    "SpellDescription", "SpellInfo", "SpellPowerCost", "SpellLevelLearned",
    "BaseSpell", "SpellTooltipData",
    -- T9: recorded explicitly (Client/API_Forever.lua), not through Bind.
    "OnSpellTooltip",
    -- T12: Spells/Measure.lua's own bonus-healing read.
    "SpellBonusHealing",
    -- T15: Modules/SpellTuner_Replay/Kit_Forever.lua's own crit reading.
    "SpellCritChance",
    -- T13: Modules/SpellTuner_Recorder/Recorder_Forever.lua's own bindings.
    "UnitGroupRolesAssigned", "RealZoneText", "AuraByIndex", "MeterSession", "MeterSource",
    -- T18 (Engine/Practice.lua): the bindings-import triad plus the macro/
    -- action reads, all present on the 69893 baseline.
    "BindingCount", "Binding", "BindingAction", "ActionInfo", "MacroInfo",
    -- T25 (UI/SpellTip_Forever.lua): a macro's spell, and the macro tooltip hook.
    "MacroSpell", "OnMacroTooltip",
    -- T28: the SetAction hook, recorded explicitly (Client/API_Forever.lua).
    "OnActionTooltip",
    -- T29 (UI/Style.lua's UI.px): the physical screen, for pixel-snapped edges.
    "PhysicalScreenSize", -- T29
    -- T37 (UI/SpellTip_Forever.lua): the detail key's tooltip refresh.
    "RefreshTooltip", -- T37
    -- T36 (UI/SpellsPane_Forever.lua): a spell dragged onto the Spells rail.
    "CursorInfo", -- T36
    -- T38 (UI/SpellsPane_Forever.lua): the game's spell tooltip for a rank row.
    "SetTooltipSpell", -- T38
    -- T95 (Spells/Book.lua): GetSpellBaseCooldown, read only while
    -- MD.API.BASE_CD_READS is true.
    "BaseCooldown", -- T95
}
-- T15: Client/API_TBC.lua's own binding -- GetSpellInfo, so
-- Engine/SimModel.lua and Engine/SimPlanner.lua's four call sites can go
-- through MD.API.SpellName(id) on either client.
-- T16b (UI/Dashboard_Review.lua): RealZoneText, TBC's own GetRealZoneText --
-- Forever's is FOREVER_ONLY_NAMES' own (Client/API_Forever.lua, T13).
-- T18: the same bindings-import triad as Forever's own FOREVER_ONLY_NAMES,
-- plus Specialization -- GetSpecialization, which Forever's own baseline
-- lacks (Client/API_Forever.lua's comment).
local TBC_ONLY_NAMES = { "SpellName", "RealZoneText",
    "BindingCount", "Binding", "BindingAction", "ActionInfo", "MacroInfo", "Specialization" }

--------------------------------------------------------------------------------
-- 1-9: both flavours
--------------------------------------------------------------------------------

do
    local allNames = {}
    for _, n in ipairs(SHARED_NAMES) do allNames[#allNames + 1] = n end
    for _, n in ipairs(ADDON_NAMES) do allNames[#allNames + 1] = n end
    if flavour == "forever" then
        for _, n in ipairs(FOREVER_ONLY_NAMES) do allNames[#allNames + 1] = n end
    else
        for _, n in ipairs(TBC_ONLY_NAMES) do allNames[#allNames + 1] = n end
    end

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
-- 10-12: T7's Copy / Constant / a copying binding -- both flavours
--------------------------------------------------------------------------------

do
    local secret = (flavour == "forever") and S.Secret() or "unused"
    local t = { name = "Bob", n = 5, ok = true, nested = { a = 1, deep = { x = 2 } } }
    if flavour == "forever" then
        t.hidden = secret
        -- T45 (P1, review Q1): no `t[secret] = ...` here any more -- the client
        -- raises on a secret used as a table key, so a table keyed by one cannot
        -- exist there; the stub (Lua 5.1) cannot trap it, and since type(secret)
        -- answers "number" the key would only be counted as a second secret.
    end
    local copy1 = MD.API.Copy(t, 1)
    local copy2 = MD.API.Copy(t, 2)
    local plainScalar = MD.API.Copy(5)
    local nilForSecret = (flavour == "forever") and MD.API.Copy(secret) == nil or true
    local nilForFunction = MD.API.Copy(print) == nil

    local depth1Good = copy1.name == "Bob" and copy1.n == 5 and copy1.ok == true
        and copy1.nested == nil and copy1 ~= t
    local depth2Good = copy2.nested.a == 1 and copy2.nested.deep == nil
    local secretCounted = true
    if flavour == "forever" then
        secretCounted = copy1._secret == 1 and copy1.hidden == nil
    end
    check("Copy keeps plain fields and drops secret ones",
        depth1Good and depth2Good and plainScalar == 5 and nilForSecret and nilForFunction and secretCounted,
        string.format("copy1.n=%s copy1.nested=%s copy2.nested.a=%s copy1._secret=%s",
            tostring(copy1.n), tostring(copy1.nested), tostring(copy2.nested and copy2.nested.a), tostring(copy1._secret)))
end

do
    -- Enum.SpellBookSpellBank.Player is a plain 0 on both stub profiles'
    -- Enum table on forever; on tbc there is no Enum table at all, so the
    -- walk simply answers nil rather than raising.
    local player = MD.API.Constant("Enum.SpellBookSpellBank.Player")
    local missing = MD.API.Constant("Enum.NoSuchThing.Nope")
    local notAFunction = MD.API.Constant("print")
    local ok
    if flavour == "forever" then
        ok = player == 0
    else
        ok = player == nil
    end
    check("Constant reads a plain enum value and nothing else",
        ok and missing == nil and notAFunction == nil,
        "player=" .. tostring(player) .. " missing=" .. tostring(missing) .. " notAFunction=" .. tostring(notAFunction))
end

do
    _G.T7_COPYSRC = function()
        local row = { id = 1, name = "Row" }
        if flavour == "forever" then row.secretField = S.Secret() end
        return row
    end
    MD.API.Bind({ T7Copying = { client = "T7_COPYSRC", copy = 1 } })
    local a = MD.API.T7Copying()
    local b = MD.API.T7Copying()
    _G.T7_COPYSRC = nil
    check("a copying binding hands back a copy, never the client's table",
        a ~= nil and a.id == 1 and a.name == "Row" and a ~= b and a.secretField == nil)
end

--------------------------------------------------------------------------------
-- T11: DrawUnitPower -- both flavours (a StatusBar's own setters are the one
-- sanctioned path for a secret to leave the adapter; nothing here asks what
-- either value was, so the shape of the check is the same whether or not
-- this client's UnitPower happens to be secret).
--------------------------------------------------------------------------------
do
    local bar = CreateFrame("StatusBar", nil, UIParent)
    local drawOk = MD.API.DrawUnitPower(bar, "player", 0)
    check("DrawUnitPower hands the values over without reading them",
        drawOk == true and bar.minV == 0 and bar.maxV ~= nil and bar.value ~= nil)
end

--------------------------------------------------------------------------------
-- T52 (P8, review Q15): MD.API.Invalidate(name) clears one Has cache entry, so
-- a test can swap a global after the adapter has already answered for it --
-- both flavours. Before it a later Has kept the first answer forever.
--------------------------------------------------------------------------------
do
    local runOk, err = pcall(function()
        _G.T52_LATE = nil
        local before = MD.API.Has("T52_LATE")
        _G.T52_LATE = function() return 7 end
        local stillCached = MD.API.Has("T52_LATE")
        MD.API.Invalidate("T52_LATE")
        local after = MD.API.Has("T52_LATE")
        local otherKept = type(MD.API.Has("UnitLevel")) == "function"
        _G.T52_LATE = nil
        MD.API.Invalidate("T52_LATE")
        local gone = MD.API.Has("T52_LATE")
        check("Invalidate makes a later Has see a new global",
            before == false and stillCached == false and type(after) == "function"
            and gone == false and otherKept == true,
            string.format("before=%s cached=%s after=%s gone=%s", tostring(before),
                tostring(stillCached), type(after), tostring(gone)))
    end)
    _G.T52_LATE = nil
    if not runOk then check("Invalidate makes a later Has see a new global", false, "raised: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- 13-18: forever only
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

    -- T95 (docs/SPEC-next.md 4.2 P1): GetSpellBaseCooldown is bound as
    -- BaseCooldown, a Forever-only name, its answer plain (or nil, absent),
    -- and MD.API.BASE_CD_READS ships false -- Spells/Book.lua reads the
    -- tooltip line until T87's Forever report says the call answers plain.
    do
        local listed = false
        for _, n in ipairs(FOREVER_ONLY_NAMES) do if n == "BaseCooldown" then listed = true end end
        local saved = rawget(_G, "GetSpellBaseCooldown")
        _G.GetSpellBaseCooldown = function(id)
            if id == 20473 then return 10000, 1500 end
            return 0, 1500
        end
        MD.API.Invalidate("GetSpellBaseCooldown")
        local read = type(MD.API.BaseCooldown) == "function" and MD.API.BaseCooldown or function() end
        local ms, gcd = read(20473)
        local none = read(5185)
        _G.GetSpellBaseCooldown = saved
        MD.API.Invalidate("GetSpellBaseCooldown")
        local gone, why = read(20473)
        check("T95: BaseCooldown is a Forever-only binding, read only once BASE_CD_READS is set",
            listed and MD.API._bindings.BaseCooldown == "GetSpellBaseCooldown" and MD.API.BASE_CD_READS == false
            and ms == 10000 and gcd == 1500 and none == 0 and gone == nil and why == "absent",
            string.format("listed=%s binding=%s flag=%s ms=%s gcd=%s none=%s gone=%s/%s", tostring(listed),
                tostring(MD.API._bindings.BaseCooldown), tostring(MD.API.BASE_CD_READS), tostring(ms),
                tostring(gcd), tostring(none), tostring(gone), tostring(why)))
    end

    -- T17c: HealthMax, a party member's real max through a hidden status bar,
    -- off (MD.API.BAR_READS_MAX false) until the probe's bar readback line says
    -- a bar hands a secret back plain. The getter is replaced through the bar
    -- metatable the stub shares (T13e's own technique) and always restored.
    do
        local barMT = getmetatable(_G.UIParent)
        local origGet = barMT.GetMinMaxValues
        local origFlag = MD.API.BAR_READS_MAX
        local calls = 0
        barMT.GetMinMaxValues = function(self) calls = calls + 1; return origGet(self) end
        MD.API.BAR_READS_MAX = false
        local a, b = MD.API.HealthMax("party1")
        local p, pr = MD.API.HealthMax("player")
        barMT.GetMinMaxValues = origGet
        MD.API.BAR_READS_MAX = origFlag
        check("a party member's max through a status bar is off until the probe says so",
            origFlag == false and a == nil and b == "secret" and calls == 0
            and type(p) == "number" and p == S.units.player.hpMax and pr == nil,
            string.format("flag=%s a=%s b=%s calls=%s p=%s", tostring(origFlag), tostring(a), tostring(b), tostring(calls), tostring(p)))
    end

    do
        local origFlag = MD.API.BAR_READS_MAX
        MD.API.BAR_READS_MAX = true
        local r = { MD.API.HealthMax("party1") }
        local n = select("#", MD.API.HealthMax("party1"))
        MD.API.BAR_READS_MAX = origFlag
        local leaked = false
        for i = 1, n do
            local v = select(i, MD.API.HealthMax("party1"))
            if _G.issecretvalue(v) then leaked = true end
        end
        for i = 1, 2 do if _G.issecretvalue(r[i]) then leaked = true end end
        check("with the readback on, a bar that hands back a secret gives nil, secret",
            r[1] == nil and r[2] == "secret" and not leaked,
            string.format("a=%s b=%s leaked=%s", tostring(r[1]), tostring(r[2]), tostring(leaked)))
    end

    do
        local barMT = getmetatable(_G.UIParent)
        local origGet = barMT.GetMinMaxValues
        local origFlag = MD.API.BAR_READS_MAX
        MD.API.BAR_READS_MAX = true
        barMT.GetMinMaxValues = function() return 0, 12345 end
        local plain = MD.API.HealthMax("party1")
        barMT.GetMinMaxValues = function() error("stub GetMinMaxValues raised") end
        local okRaise, ra, rb = pcall(MD.API.HealthMax, "party1")
        barMT.GetMinMaxValues = origGet
        MD.API.BAR_READS_MAX = origFlag
        check("with the readback on, a bar that hands back a plain max gives that number, and a raising bar gives nil, error",
            plain == 12345 and okRaise == true and ra == nil and rb == "error" and origFlag == false
            and barMT.GetMinMaxValues == origGet,
            string.format("plain=%s okRaise=%s ra=%s rb=%s", tostring(plain), tostring(okRaise), tostring(ra), tostring(rb)))
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
