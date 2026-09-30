-- tools/run.sh --flavour forever tools/forevercheck.lua
-- tools/run.sh tools/forevercheck.lua (forever is the default when unset)
--
-- T5's own suite: loads the Forever TOC under the harness's "forever" profile
-- and proves the stub answers the way build 70009 answered the probe
-- (docs/probe/1.60.1_70009.md) rather than the looser T0-era stand-in --
-- secrets on for current health/power always, party maxima always, regen
-- only in combat; the combat log refused the way the client refuses it; and
-- every global function the stub leaves defined is one the 69893 capture
-- (tools/data/forever_api.json) actually has.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- Snapshotted BEFORE anything loads, so check 12 can tell "a global this stub
-- adds" apart from "a global Lua's own standard library already had".
local preStub = {}
for k in pairs(_G) do preStub[k] = true end

--------------------------------------------------------------------------------
-- 1: the Forever TOC loads under the harness with no error
--------------------------------------------------------------------------------
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local okLoad, MD = pcall(dofile, here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB

check("the Forever TOC loads under the harness with no error",
    okLoad == true and type(MD) == "table" and MD.API and MD.API.client == "forever"
    and S.flavour == "forever" and S.toc == "SpellTuner_Mainline.toc")

--------------------------------------------------------------------------------
-- 2: the harness loads exactly the Forever TOC's files, in order
--------------------------------------------------------------------------------
do
    local expected = S.TocFiles("SpellTuner_Mainline.toc")
    local sameLength = type(S.loadedFiles) == "table" and #S.loadedFiles == #expected
    local elementsMatch = sameLength
    if sameLength then
        for i = 1, #expected do
            if S.loadedFiles[i] ~= expected[i] then elementsMatch = false end
        end
    end
    check("the harness loads exactly the Forever TOC's files, in order",
        elementsMatch and #expected > 0)
end

--------------------------------------------------------------------------------
-- 3: nothing on the Forever TOC tries to register the combat log
--------------------------------------------------------------------------------
do
    local attempted = false
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "COMBAT_LOG_EVENT_UNFILTERED" then attempted = true end
        end
    end
    check("nothing on the Forever TOC tries to register the combat log",
        not attempted and type(S.forbidden) == "table" and #S.forbidden == 0)
end

--------------------------------------------------------------------------------
-- 4: the stub refuses the combat log the way the client does
--------------------------------------------------------------------------------
do
    local captured = {}
    local listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", function(self, event, ...) captured[#captured + 1] = { event, ... } end)
    listener:RegisterEvent("ADDON_ACTION_FORBIDDEN")

    local clogFrame = CreateFrame("Frame")
    local registerOk = pcall(function() clogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end)

    local receivedForbidden = false
    for _, c in ipairs(captured) do
        if c[1] == "ADDON_ACTION_FORBIDDEN" and c[2] == "SpellTuner" and c[3] == "UNKNOWN()" then
            receivedForbidden = true
        end
    end

    check("the stub refuses the combat log the way the client does",
        registerOk == true
        and type(S.forbidden) == "table" and #S.forbidden == 1
        and receivedForbidden
        and not clogFrame.events["COMBAT_LOG_EVENT_UNFILTERED"])
end

--------------------------------------------------------------------------------
-- 5: a secret trips arithmetic, comparison and concatenation
--------------------------------------------------------------------------------
do
    local addOk = pcall(function() return S.Secret() + 1 end)
    local ltOk = pcall(function() return S.Secret() < 1 end)
    local concatOk = pcall(function() return S.Secret() .. "x" end)
    check("a secret trips arithmetic, comparison and concatenation",
        addOk == false and ltOk == false and concatOk == false and issecretvalue(S.Secret()) == true)
end

--------------------------------------------------------------------------------
-- 6: code doing arithmetic on current health fails, in and out of combat
--------------------------------------------------------------------------------
do
    local healthChunk = loadstring("return UnitHealth('player') + 0")
    local powerChunk = loadstring("return UnitPower('player', 0) + 0")

    S.inCombat = false
    local healthOocOk = pcall(healthChunk)
    local powerOocOk = pcall(powerChunk)
    S.inCombat = true
    local healthCombatOk = pcall(healthChunk)
    local powerCombatOk = pcall(powerChunk)
    S.inCombat = false

    check("code doing arithmetic on current health fails, in and out of combat",
        healthOocOk == false and healthCombatOk == false
        and powerOocOk == false and powerCombatOk == false)
end

--------------------------------------------------------------------------------
-- 7: maxima are plain for the player and secret for a party member
--------------------------------------------------------------------------------
do
    S.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })

    local function bothStates()
        local hMax, pMax = UnitHealthMax("player"), UnitPowerMax("player", 0)
        local partyMaxSecret = issecretvalue(UnitHealthMax("party1"))
        return type(hMax) == "number" and type(pMax) == "number" and partyMaxSecret == true
    end

    S.inCombat = false
    local oocOk = bothStates()
    S.inCombat = true
    local combatOk = bothStates()
    S.inCombat = false

    check("maxima are plain for the player and secret for a party member", oocOk and combatOk)
end

--------------------------------------------------------------------------------
-- 8: GetManaRegen is plain out of combat and secret in combat
--------------------------------------------------------------------------------
do
    S.inCombat = false
    local a, b = GetManaRegen()
    local oocOk = type(a) == "number" and type(b) == "number"
    S.inCombat = true
    local sa, sb = GetManaRegen()
    local combatOk = issecretvalue(sa) == true and issecretvalue(sb) == true
    S.inCombat = false

    check("GetManaRegen is plain out of combat and secret in combat", oocOk and combatOk)
end

--------------------------------------------------------------------------------
-- 9: auras read out of combat and raise in combat
--------------------------------------------------------------------------------
do
    S.inCombat = false
    local oocOk, oocResult = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    S.inCombat = true
    local combatOk, combatErr = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    S.inCombat = false

    check("auras read out of combat and raise in combat",
        oocOk == true and type(oocResult) == "table"
        and combatOk == false and type(combatErr) == "string"
        and combatErr:find("Auras cannot be accessed when secret while tainted", 1, true) ~= nil)
end

--------------------------------------------------------------------------------
-- 10: HasSecretRestrictions is true in and out of combat
--------------------------------------------------------------------------------
do
    S.inCombat = false
    local oocVal = C_Secrets.HasSecretRestrictions()
    S.inCombat = true
    local combatVal = C_Secrets.HasSecretRestrictions()
    S.inCombat = false

    check("HasSecretRestrictions is true in and out of combat", oocVal == true and combatVal == true)
end

--------------------------------------------------------------------------------
-- 11: the Classic globals are gone and C_AddOns answers
--------------------------------------------------------------------------------
do
    local goneNames = {
        "GetSpellInfo", "UnitAura", "UnitBuff", "GetTalentInfo", "GetItemInfo",
        "CombatLogGetCurrentEventInfo", "GetAddOnMetadata", "GetSpellCooldown", "GetItemCount",
    }
    local allGone = true
    for _, name in ipairs(goneNames) do if _G[name] ~= nil then allGone = false end end

    local mainlineVersion = nil
    do
        local f = io.open(ROOT .. "/SpellTuner_Mainline.toc", "r")
        if f then
            for line in f:lines() do
                local v = line:match("^## Version:%s*(.-)%s*$")
                if v then mainlineVersion = v; break end
            end
            f:close()
        end
    end

    check("the Classic globals are gone and C_AddOns answers",
        allGone and type(C_AddOns) == "table"
        and C_AddOns.GetAddOnMetadata("SpellTuner", "Version") == mainlineVersion
        and mainlineVersion ~= nil)
end

--------------------------------------------------------------------------------
-- 12: every global function the stub leaves under forever is in the 69893
-- baseline -- read here, independently of the stub's own pruning.
--------------------------------------------------------------------------------
do
    local function ReadBaselineFunctions(path)
        local f = io.open(path, "r")
        if not f then return {} end
        local text = f:read("*a")
        f:close()
        local marker = text:find('"functions"', 1, true)
        if not marker then return {} end
        local openBracket = text:find("%[", marker)
        local closeBracket = text:find("%]", openBracket)
        local body = text:sub(openBracket + 1, closeBracket - 1)
        local set = {}
        for name in body:gmatch('"([^"]*)"') do set[name] = true end
        return set
    end
    local baseline = ReadBaselineFunctions(ROOT .. "/tools/data/forever_api.json")

    local allInBaseline = true
    local offenders = {}
    for k, v in pairs(_G) do
        if type(v) == "function" and not preStub[k] and k ~= "collectgarbage_count" then
            if not baseline[k] then
                allInBaseline = false
                offenders[#offenders + 1] = k
            end
        end
    end

    local prunedHasBoth = false
    if type(S.pruned) == "table" then
        local hasMeta, hasCooldown = false, false
        for _, name in ipairs(S.pruned) do
            if name == "GetAddOnMetadata" then hasMeta = true end
            if name == "GetSpellCooldown" then hasCooldown = true end
        end
        prunedHasBoth = hasMeta and hasCooldown
    end

    check("every global function the stub leaves under forever is in the 69893 baseline",
        allInBaseline and prunedHasBoth, table.concat(offenders, ", "))
end

--------------------------------------------------------------------------------
-- 13: a TBC-only tool skips under --flavour forever
--------------------------------------------------------------------------------
do
    local p = io.popen("cd \"" .. ROOT .. "\" && bash tools/run.sh --flavour forever tools/migrate.lua 2>&1")
    local out = ""
    if p then out = p:read("*a") or ""; p:close() end
    check("a TBC-only tool skips under --flavour forever",
        out == "skip: migrate.lua runs under tbc only\n")
end

--------------------------------------------------------------------------------
-- 14-16 (T47, P3): the client is the TOC's, the interface only a fallback.
-- Client/API.lua is re-run into a fresh table (as probecheck does for its
-- second MD) with the marker and the build's interface set by hand, then both
-- are put back.
--------------------------------------------------------------------------------
local function FreshClient(marker, iface)
    local savedMarker, savedBuild = rawget(_G, "SPELLTUNER_TOC"), rawget(_G, "GetBuildInfo")
    _G.SPELLTUNER_TOC = marker
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Sep 20 2026", iface end
    local fresh = {}
    local chunk, err = loadfile(ROOT .. "/Client/API.lua")
    local okRun = chunk and pcall(chunk, "SpellTuner", fresh)
    _G.SPELLTUNER_TOC, _G.GetBuildInfo = savedMarker, savedBuild
    if not okRun then return nil, tostring(err) end
    return fresh.API and fresh.API.client, fresh
end

do
    local client = FreshClient("Mainline", 120105)
    local plain = FreshClient("Plain", 120105)
    check("the Mainline marker at interface 120105 answers forever",
        client == "forever" and plain == "forever",
        "Mainline " .. tostring(client) .. ", Plain " .. tostring(plain))
end

do
    local client = FreshClient("TBC", 20506)
    local none = FreshClient(nil, 20506)
    local unknown = FreshClient(nil, 120105)
    check("the TBC marker at 20506 answers tbc; no marker falls back to the band",
        client == "tbc" and none == "tbc" and unknown == "unknown",
        "TBC " .. tostring(client) .. ", none/20506 " .. tostring(none) .. ", none/120105 " .. tostring(unknown))
end

do
    -- tools/data/flavours.txt: "<name> <marker files, comma-separated> <lo>-<hi>"
    local want, wantMarkers, lines = {}, {}, 0
    local f = io.open(ROOT .. "/tools/data/flavours.txt", "r")
    if f then
        for line in f:lines() do
            line = line:gsub("\r$", "")
            if line:match("%S") and not line:match("^%s*#") then
                local name, files, lo, hi = line:match("^%s*(%S+)%s+(%S+)%s+(%d+)%-(%d+)%s*$")
                if name then
                    lines = lines + 1
                    want[name] = { tonumber(lo), tonumber(hi) }
                    for file in files:gmatch("[^,]+") do
                        local m = file:match("^Client/TOC_(%w+)%.lua$")
                        wantMarkers[m or ("?" .. file)] = name
                    end
                end
            end
        end
        f:close()
    end
    local API = MD and MD.API or {}
    local same, detail = lines >= 2 and type(API.BANDS) == "table" and type(API.MARKERS) == "table", nil
    if same then
        for name, band in pairs(want) do
            local b = API.BANDS[name]
            if not (type(b) == "table" and b[1] == band[1] and b[2] == band[2]) then same = false; detail = "band " .. name end
        end
        for name in pairs(API.BANDS) do if not want[name] then same = false; detail = "extra band " .. tostring(name) end end
        for m, name in pairs(wantMarkers) do
            if API.MARKERS[m] ~= name then same = false; detail = "marker " .. m end
            -- and the marker file sets exactly that marker
            local mf = io.open(ROOT .. "/Client/TOC_" .. m .. ".lua", "r")
            local text = mf and mf:read("*a") or ""
            if mf then mf:close() end
            if not text:find('SPELLTUNER_TOC = "' .. m .. '"', 1, true) then same = false; detail = "Client/TOC_" .. m .. ".lua" end
        end
        for m in pairs(API.MARKERS) do if not wantMarkers[m] then same = false; detail = "extra marker " .. tostring(m) end end
    else
        detail = "flavours.txt lines " .. lines .. ", BANDS " .. type(API.BANDS) .. ", MARKERS " .. type(API.MARKERS)
    end
    check("MD.API.BANDS and MD.API.MARKERS equal tools/data/flavours.txt", same, detail)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
