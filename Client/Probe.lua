-- The capability probe (T0 of docs/ROADMAP-FOREVER.md): answers docs/FOREVER-PLAN.md
-- §6's nine questions as far as the client allows at the moment it runs, for
-- the planner (who reads the pasted report) and the author (who runs it on
-- the beta). It must survive the beta's own bugs, so it calls the client
-- directly (Client/API.lua is the adapter every OTHER file goes through; this
-- file's whole job is to see the raw value the adapter would turn into nil)
-- but never lets a raw value touch arithmetic, comparison, a table key or the
-- rendered text without going through IsSecret/Fmt/Esc first, and every call
-- is under pcall -- the beta stops reporting errors after 100 of them.
local ADDON_NAME, MD = ...

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Packs the results of ONE call (pass it pcall(fn, ...) directly, never call
-- fn twice) into a plain table plus its true count, so a nil in the middle of
-- the returns is not lost the way "#packed" or "a and f() or b" would lose it.
local function packPcall(...)
    return select("#", ...), { ... }
end

-- True when either issecretvalue or issecrettable says so. EllesmereUI checks both before
-- touching a value; which of the two the client's damage meter session or aura tables
-- answer is UNKNOWN (Facts), so a table either one flags is reported <secret>.
-- Each is reached through Has and called under its own pcall; an absent one counts as false,
-- never raises, so callers can check this before anything else.
local function IsSecret(v)
    local isValue = MD.API.Has("issecretvalue")
    if type(isValue) == "function" then
        local ok, secret = pcall(isValue, v)
        if ok and secret == true then return true end
    end
    local isTable = MD.API.Has("issecrettable")
    if type(isTable) == "function" then
        local ok, secret = pcall(isTable, v)
        if ok and secret == true then return true end
    end
    return false
end

-- True only for a string that is not "", "nil" or "nothing" and does not
-- start with "<" -- i.e. our own rendered text actually says something, as
-- opposed to standing in for an absence, a raise or a secret. Applied to our
-- own stored strings only, never to a raw client value.
local function Readable(s)
    if type(s) ~= "string" then return false end
    if s == "" or s == "nil" or s == "nothing" then return false end
    if s:sub(1, 1) == "<" then return false end
    return true
end

-- Reversible ASCII escaping: \ -> \\, | -> ||, then every byte outside the
-- printable range -> \ddd. In that order, so the backslashes the third step
-- adds are never re-escaped by the first. Each step keeps its own local
-- (gsub returns two values; a chained call would carry the match count into
-- the next gsub's subject otherwise).
local function Esc(s)
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

-- The one place a raw client scalar becomes text. A table is never walked
-- here (see Describe) -- this is what a value embedded in a sentence gets.
local function Fmt(v)
    if IsSecret(v) then return "<secret>" end
    if v == nil then return "nil" end
    local t = type(v)
    if t == "string" then return Esc(v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then return "<table>" end
    return "<" .. t .. ">"
end

-- Like Fmt, but a non-secret table is shown shallow: {k=v, ...}, sorted by
-- the escaped key text, capped so one huge table cannot blow up the report.
local function Describe(v)
    if IsSecret(v) or v == nil or type(v) ~= "table" then return Fmt(v) end
    local ok, result = pcall(function()
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return Esc(tostring(a)) < Esc(tostring(b)) end)
        local parts, count = {}, 0
        for _, k in ipairs(keys) do
            count = count + 1
            if count > 24 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = Esc(tostring(k)) .. "=" .. Fmt(v[k])
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end)
    if not ok then return "<error: " .. Fmt(result) .. ">" end
    return result
end

-- Calls a dotted client function by name, under pcall, and renders the
-- outcome: <absent> if Has does not find a function, <error: ...> if the call
-- raised, else every return value through Describe, "nothing" if it returned
-- none at all (never confused with a single nil return).
local function Show(name, ...)
    local fn = MD.API.Has(name)
    if type(fn) ~= "function" then return "<absent>" end
    local n, packed = packPcall(pcall(fn, ...))
    if not packed[1] then return "<error: " .. Fmt(packed[2]) .. ">" end
    if n <= 1 then return "nothing" end
    local parts = {}
    for i = 2, n do parts[#parts + 1] = Describe(packed[i]) end
    return table.concat(parts, ", ")
end

-- Like Show, but renders only the FIRST return through Describe. UnitName answers name,
-- realm (realm nil on your own realm) and Show joins every return, so the character line
-- read "Healroot, nil"; First keeps the one value the line means.
local function First(name, ...)
    local fn = MD.API.Has(name)
    if type(fn) ~= "function" then return "<absent>" end
    local n, packed = packPcall(pcall(fn, ...))
    if not packed[1] then return "<error: " .. Fmt(packed[2]) .. ">" end
    if n <= 1 then return "nothing" end
    return Describe(packed[2])
end

-- Reads t[key] under pcall (indexing a secret table raises rather than
-- reading nil -- plan §1.2), and separately flags a secret RESULT. Only used
-- where the surrounding code needs the raw value, not just its rendering.
local function Field(t, key)
    local ok, v = pcall(function() return t[key] end)
    if not ok then return nil, "error" end
    if IsSecret(v) then return nil, "secret" end
    return v, "ok"
end

--------------------------------------------------------------------------------
-- Constants (exact lists; see docs/tasks/T0-probe.md)
--------------------------------------------------------------------------------
local FUNCTIONS = {
    -- plan §1.1, gone or protected
    "GetSpellInfo", "UnitAura", "UnitBuff", "GetTalentInfo", "GetItemInfo", "ReloadUI",
    -- plan §1.2
    "CombatLogGetCurrentEventInfo", "C_CombatLog.IsCombatLogRestricted", "C_Secrets.ShouldAurasBeSecret",
    "issecretvalue", "C_DamageMeter.GetCombatSessionFromType",
    -- plan §1.3, survive
    "GetManaRegen", "GetSpellBonusHealing", "GetSpellBonusDamage", "GetSpellCritChance", "UnitStat",
    "UnitPower", "UnitPowerMax", "UnitHealth", "UnitHealthMax", "UnitThreatSituation", "UnitCastingInfo",
    "GetShapeshiftFormID", "GetInventoryItemID", "GetMacroInfo", "GetBinding", "GetActionInfo", "IsSpellKnown",
    -- plan §1.3, moved
    "C_Spell.GetSpellInfo", "C_Spell.GetSpellPowerCost", "C_Spell.GetSpellDescription",
    "C_Spell.GetSpellSubtext", "C_Spell.GetSpellLevelLearned", "C_Spell.GetSpellName",
    "C_Spell.GetSpellTexture", "C_Spell.GetSpellCooldown", "C_SpellBook.GetNumSpellBookSkillLines",
    "C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.IsSpellKnown",
    "TooltipDataProcessor.AddTooltipPostCall", "C_TooltipInfo", "C_SpecializationInfo.GetTalentInfo",
    "C_Traits.GetConfigInfo", "C_ClassTalents.GetActiveConfigID", "C_UnitAuras.GetAuraDataByIndex",
    -- plan §2.2 and §3.1
    "C_Spell.GetBaseSpell", "C_AddOns.LoadAddOn",
    -- EllesmereUI (Facts)
    "C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.IsDamageMeterAvailable",
    "Enum.DamageMeterType", "Enum.DamageMeterSessionType", "Enum.SpellBookSpellBank", "C_Timer.After",
    -- what this probe and Core.lua call
    "GetBuildInfo", "GetAddOnMetadata", "C_AddOns.GetAddOnMetadata", "GetNumTalentTabs",
    "UnitAffectingCombat", "UnitExists", "UnitName", "UnitClass", "UnitLevel", "GetRealmName", "CreateFrame",
}

local EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA",
    "UNIT_FLAGS", "UNIT_COMBAT", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "ADDON_RESTRICTION_STATE_CHANGED", "COMBAT_LOG_EVENT_UNFILTERED",
}

--------------------------------------------------------------------------------
-- Session state
--------------------------------------------------------------------------------
local phase = "ooc"
local eventOutcomes = {}                 -- EVENT -> { ok = bool, err = "<error: ...>" }
local combatCounters, combatOrder = {}, {}
local sentCounters, sentOrder = {}, {}
local combatSnapshot = nil                -- { stamp, inCombat, partyExists, lines } or nil
local writtenThisSession = {}             -- build key -> true, once this session saved it
local sawDamageMeterCurrentSources = false
local probeFrame, probeEditBox = nil, nil

local svTypeAtLoad = "nil"
local svPrevStamp = nil
local svReportsAtLoad = {}

--------------------------------------------------------------------------------
-- Small classifiers (own constants / literal comparisons only, per the rules)
--------------------------------------------------------------------------------
local function UnitClassOf(u)
    if IsSecret(u) then return "<secret>" end
    if type(u) ~= "string" then return "<none>" end
    if u == "player" then return "player" end
    if u == "target" then return "target" end
    if u:sub(1, 5) == "party" then return "party" end
    if u:sub(1, 4) == "raid" then return "raid" end
    return "other"
end

local function ActionOf(a)
    if IsSecret(a) then return "<secret>" end
    if type(a) ~= "string" then return "<none>" end
    return Esc(a)
end

local function SafeDate()
    local ok, stamp = pcall(date, "%Y-%m-%d %H:%M:%S")
    if ok then return stamp end
    return "<no date>"
end

-- Fmt of GetBuildInfo()'s second return, "unknown" if the function is absent
-- or the call raised (Save's own rule for the record's key).
local function BuildKey()
    local getBuild = MD.API.Has("GetBuildInfo")
    if type(getBuild) ~= "function" then return "unknown" end
    local ok, _, build = pcall(getBuild)
    if not ok then return "unknown" end
    return Fmt(build)
end

local function Version()
    local getMeta = MD.API.Has("C_AddOns.GetAddOnMetadata")
    if type(getMeta) == "function" then
        local ok, v = pcall(getMeta, ADDON_NAME, "Version")
        if ok and type(v) == "string" and not IsSecret(v) then return Esc(v) end
    end
    local globalMeta = MD.API.Has("GetAddOnMetadata")
    if type(globalMeta) == "function" then
        local ok, v = pcall(globalMeta, ADDON_NAME, "Version")
        if ok and type(v) == "string" and not IsSecret(v) then return Esc(v) end
    end
    return "<absent>"
end

--------------------------------------------------------------------------------
-- Counters (own integers only; the client value itself is never added,
-- compared or used as a key -- only Fmt(it) ever becomes text or a key)
--------------------------------------------------------------------------------
local function BumpCombat(currentPhase, unit, action, amount)
    local key = currentPhase .. " " .. UnitClassOf(unit) .. " " .. ActionOf(action)
    local c = combatCounters[key]
    if not c then
        c = { n = 0, readable = 0, secret = 0, nilCount = 0, sample = nil }
        combatCounters[key] = c
        combatOrder[#combatOrder + 1] = key
    end
    c.n = c.n + 1
    if IsSecret(amount) then
        c.secret = c.secret + 1
    elseif amount == nil then
        c.nilCount = c.nilCount + 1
    else
        c.readable = c.readable + 1
        if not c.sample then c.sample = Fmt(amount) end
    end
end

local function BumpSent(currentPhase, target)
    local c = sentCounters[currentPhase]
    if not c then
        c = { n = 0, readable = 0, secret = 0, empty = 0, sample = nil }
        sentCounters[currentPhase] = c
        sentOrder[#sentOrder + 1] = currentPhase
    end
    c.n = c.n + 1
    if IsSecret(target) then
        c.secret = c.secret + 1
    elseif target == nil or target == "" then
        c.empty = c.empty + 1
    elseif type(target) == "string" then
        c.readable = c.readable + 1
        if not c.sample then c.sample = Fmt(target) end
    else
        -- neither a usable name nor secret nor nil/"" -- not seen in practice,
        -- grouped with "empty" since there is nothing readable to show either way
        c.empty = c.empty + 1
    end
end

--------------------------------------------------------------------------------
-- == client
--------------------------------------------------------------------------------
local function ClientLines()
    local lines = {}

    local getBuild = MD.API.Has("GetBuildInfo")
    if type(getBuild) ~= "function" then
        lines[#lines + 1] = "build: <absent>"
    else
        local n, packed = packPcall(pcall(getBuild))
        if not packed[1] then
            lines[#lines + 1] = "build: <error: " .. Fmt(packed[2]) .. ">"
        else
            lines[#lines + 1] = "build: " .. Fmt(packed[2]) .. " " .. Fmt(packed[3]) .. " "
                .. Fmt(packed[4]) .. " interface " .. Fmt(packed[5])
        end
    end

    lines[#lines + 1] = "client: " .. Fmt(MD.API.client)

    local ok, id, main, classic, tbc = pcall(function()
        return _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC, _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC
    end)
    if ok then
        lines[#lines + 1] = string.format("project: WOW_PROJECT_ID=%s WOW_PROJECT_MAINLINE=%s WOW_PROJECT_CLASSIC=%s WOW_PROJECT_BURNING_CRUSADE_CLASSIC=%s",
            Fmt(id), Fmt(main), Fmt(classic), Fmt(tbc))
    else
        lines[#lines + 1] = "project: <error: " .. Fmt(id) .. ">"
    end

    local classText = "<absent>"
    local classFn = MD.API.Has("UnitClass")
    if type(classFn) == "function" then
        local n2, packed2 = packPcall(pcall(classFn, "player"))
        if not packed2[1] then
            classText = "<error: " .. Fmt(packed2[2]) .. ">"
        elseif n2 >= 3 then
            classText = Fmt(packed2[3])
        else
            classText = "nil"
        end
    end
    lines[#lines + 1] = "character: " .. First("UnitName", "player") .. " " .. First("GetRealmName")
        .. " " .. classText .. " level " .. Show("UnitLevel", "player")

    lines[#lines + 1] = "in combat: " .. Show("UnitAffectingCombat", "player")
    return lines
end

--------------------------------------------------------------------------------
-- == functions
--------------------------------------------------------------------------------
local function FunctionsLines()
    local lines, presentN, absentN = {}, 0, 0
    for _, name in ipairs(FUNCTIONS) do
        if MD.API.Has(name) == false then
            lines[#lines + 1] = "absent " .. name
            absentN = absentN + 1
        else
            lines[#lines + 1] = "present " .. name
            presentN = presentN + 1
        end
    end
    return lines, presentN, absentN
end

--------------------------------------------------------------------------------
-- == events (registration outcomes recorded once, at load)
--------------------------------------------------------------------------------
local function EventsSummaryLines()
    local lines = {}
    for _, event in ipairs(EVENTS) do
        local rec = eventOutcomes[event]
        if rec and rec.ok then
            lines[#lines + 1] = "ok " .. event
        elseif rec then
            lines[#lines + 1] = "throws " .. event .. " " .. rec.err
        else
            lines[#lines + 1] = "throws " .. event .. " <error: not registered>"
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- == secrets now -- every C_Secrets.Should* function, called with no argument
--------------------------------------------------------------------------------
local function SecretsLines()
    local secretsTbl = MD.API.Has("C_Secrets")
    if type(secretsTbl) ~= "table" then return { "C_Secrets absent" } end

    local ok, names = pcall(function()
        local found = {}
        for k in pairs(secretsTbl) do
            if type(k) == "string" and k:match("^Should") then found[#found + 1] = k end
        end
        table.sort(found)
        return found
    end)
    if not ok then return { "<error: " .. Fmt(names) .. ">" } end

    local lines = {}
    for _, name in ipairs(names) do
        lines[#lines + 1] = Esc(name) .. " = " .. Show("C_Secrets." .. name)
    end
    if #lines == 0 then lines[1] = "no Should* functions found" end
    return lines
end

--------------------------------------------------------------------------------
-- == readings now -- always computed live, whatever the current phase is
--------------------------------------------------------------------------------
local function ReadingsLines()
    return {
        "UnitExists(party1) = " .. Show("UnitExists", "party1"),
        "UnitHealth(player) = " .. Show("UnitHealth", "player"),
        "UnitHealth(party1) = " .. Show("UnitHealth", "party1"),
        "UnitHealthMax(party1) = " .. Show("UnitHealthMax", "party1"),
        "UnitHealth(target) = " .. Show("UnitHealth", "target"),
        "UnitPower(player, 0) = " .. Show("UnitPower", "player", 0),
        "GetManaRegen() = " .. Show("GetManaRegen"),
        "GetShapeshiftFormID() = " .. Show("GetShapeshiftFormID"),
        "C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = " .. Show("C_UnitAuras.GetAuraDataByIndex", "player", 1, "HELPFUL"),
        "C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = " .. Show("C_UnitAuras.GetAuraDataByIndex", "party1", 1, "HELPFUL"),
    }
end

--------------------------------------------------------------------------------
-- == spells -- walk slots 1..500 of our own accord (the client is never
-- trusted to say when to stop); dumps id/name/rank/desc for healing spells
-- only, but the desc table returned covers every non-secret spell found, so a
-- future run can notice one that STOPPED or STARTED containing "heal".
--------------------------------------------------------------------------------
local function SpellWalk()
    local bankEnum = MD.API.Has("Enum.SpellBookSpellBank")
    local playerBank = nil
    if type(bankEnum) == "table" then
        local v, status = Field(bankEnum, "Player")
        if status == "ok" then playerBank = v end
    end

    local getItem = MD.API.Has("C_SpellBook.GetSpellBookItemInfo")
    local getName = MD.API.Has("C_Spell.GetSpellName")
    local getSubtext = MD.API.Has("C_Spell.GetSpellSubtext")
    local getDesc = MD.API.Has("C_Spell.GetSpellDescription")

    local n, h, e, secretN, errorN = 0, 0, 0, 0, 0
    local seen, order, descByKey = {}, {}, {}

    if type(getItem) == "function" then
        for slot = 1, 500 do
            local ok, info = pcall(getItem, slot, playerBank)
            if ok and type(info) == "table" and not IsSecret(info) then
                local id, idStatus = Field(info, "spellID")
                if idStatus == "secret" then
                    secretN = secretN + 1
                elseif idStatus == "error" then
                    -- the row exists (the call itself did not raise) but
                    -- reading its spellID did -- counted nowhere before T0b.
                    errorN = errorN + 1
                elseif idStatus == "ok" and id ~= nil then
                    local key = Fmt(id)
                    if not seen[key] then
                        seen[key] = true
                        n = n + 1

                        local name = "<absent>"
                        if type(getName) == "function" then
                            local nOk, nVal = pcall(getName, id)
                            name = nOk and Fmt(nVal) or ("<error: " .. Fmt(nVal) .. ">")
                        end
                        local rank = "<absent>"
                        if type(getSubtext) == "function" then
                            local rOk, rVal = pcall(getSubtext, id)
                            rank = rOk and Fmt(rVal) or ("<error: " .. Fmt(rVal) .. ">")
                        end

                        local descText, healing = "<absent>", false
                        if type(getDesc) == "function" then
                            local dOk, dVal = pcall(getDesc, id)
                            if not dOk then
                                descText = "<error: " .. Fmt(dVal) .. ">"
                            elseif IsSecret(dVal) then
                                descText = "<secret>"; secretN = secretN + 1
                            elseif dVal == nil then
                                descText = "nil"; e = e + 1
                            elseif dVal == "" then
                                descText = ""; e = e + 1
                            elseif type(dVal) == "string" then
                                descText = Esc(dVal)
                                healing = dVal:lower():find("heal", 1, true) ~= nil
                            else
                                descText = Fmt(dVal)
                            end
                        end
                        if healing then h = h + 1 end

                        descByKey[key] = descText
                        order[#order + 1] = { key = key, name = name, rank = rank, desc = descText, healing = healing }
                    end
                end
            elseif ok and type(info) == "table" and IsSecret(info) then
                secretN = secretN + 1
            end
        end
    end

    return n, h, e, secretN, errorN, order, descByKey
end

--------------------------------------------------------------------------------
-- == talents
--------------------------------------------------------------------------------
local function TalentsLines()
    local lines = {}
    lines[#lines + 1] = "C_SpecializationInfo.GetTalentInfo(1, 1) = " .. Show("C_SpecializationInfo.GetTalentInfo", 1, 1)
    lines[#lines + 1] = "C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) = "
        .. Show("C_SpecializationInfo.GetTalentInfo", { tier = 1, column = 1 })

    local configID, activeShow = nil, "<absent>"
    local getActive = MD.API.Has("C_ClassTalents.GetActiveConfigID")
    if type(getActive) == "function" then
        local n, packed = packPcall(pcall(getActive))
        if not packed[1] then
            activeShow = "<error: " .. Fmt(packed[2]) .. ">"
        elseif n <= 1 then
            activeShow = "nothing"
        else
            configID = packed[2]
            local parts = {}
            for i = 2, n do parts[#parts + 1] = Describe(packed[i]) end
            activeShow = table.concat(parts, ", ")
        end
    end
    lines[#lines + 1] = "C_ClassTalents.GetActiveConfigID() = " .. activeShow
    lines[#lines + 1] = "C_Traits.GetConfigInfo(<first return above>) = " .. Show("C_Traits.GetConfigInfo", configID)
    return lines
end

--------------------------------------------------------------------------------
-- == spells against the previous run
--------------------------------------------------------------------------------
-- info.compared, .oldBonus, .newBonus, .changedCount, .totalCount -- used by
-- the to-do section's Q1 line without redoing the SavedVariables read.
local function AgainstPreviousLines(order, descByKey, bonusStr, buildKey)
    local lines = { "== spells against the previous run" }
    local info = { compared = false }

    local prevRecord = nil
    if type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table"
        and type(SpellTunerDB.probe.reports) == "table" then
        prevRecord = SpellTunerDB.probe.reports[buildKey]
    end

    if type(prevRecord) == "table" and type(prevRecord.desc) == "table" then
        info.compared = true
        info.oldBonus = prevRecord.bonus
        info.newBonus = bonusStr
        local label = writtenThisSession[buildKey] and "this session" or "saved"
        lines[#lines + 1] = string.format("previous: %s at %s, bonus healing %s -> %s",
            label, Fmt(prevRecord.at), Fmt(prevRecord.bonus), bonusStr)

        -- A spell present in both runs is COMPARABLE only when both
        -- descriptions are Readable -- "<secret>" this run against a real
        -- sentence last run (or the reverse) is not a change, it is a hole in
        -- what either run could read.
        local changed, comparedCount, notComparable = {}, 0, 0
        for _, sp in ipairs(order) do
            local prevDesc = prevRecord.desc[sp.key]
            local curDesc = descByKey[sp.key]
            if prevDesc ~= nil then
                if Readable(prevDesc) and Readable(curDesc) then
                    comparedCount = comparedCount + 1
                    if prevDesc ~= curDesc then
                        changed[#changed + 1] = "changed " .. sp.key .. " " .. sp.name
                    end
                else
                    notComparable = notComparable + 1
                end
            end
        end
        info.changedCount, info.totalCount = #changed, comparedCount
        if #changed > 0 then
            for _, l in ipairs(changed) do lines[#lines + 1] = l end
        else
            lines[#lines + 1] = "no description changed"
        end
        if notComparable > 0 then
            lines[#lines + 1] = notComparable .. " not comparable (unreadable on one run)"
        end
    else
        lines[#lines + 1] = "no previous run to compare"
    end
    return lines, info
end

--------------------------------------------------------------------------------
-- Combat snapshot: taken 2s into PLAYER_REGEN_DISABLED (or at once if the
-- client has no C_Timer.After), and kept -- the last one of the session wins.
--------------------------------------------------------------------------------
local function TakeCombatSnapshot()
    local lines = {}
    for _, l in ipairs(SecretsLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ReadingsLines()) do lines[#lines + 1] = l end
    combatSnapshot = {
        stamp = SafeDate(),
        inCombat = Show("UnitAffectingCombat", "player"),
        partyExists = Show("UnitExists", "party1"),
        lines = lines,
    }
end

--------------------------------------------------------------------------------
-- == combat snapshot
--------------------------------------------------------------------------------
local function CombatSnapshotLines()
    if not combatSnapshot then return { "none this session" } end
    local lines = { "taken " .. Fmt(combatSnapshot.stamp) .. ", in combat: " .. combatSnapshot.inCombat }
    for _, l in ipairs(combatSnapshot.lines) do lines[#lines + 1] = l end
    return lines
end

--------------------------------------------------------------------------------
-- == events seen this session
--------------------------------------------------------------------------------
local function EventsSeenLines()
    local lines = {}
    for _, key in ipairs(combatOrder) do
        local c = combatCounters[key]
        lines[#lines + 1] = string.format("UNIT_COMBAT %s n=%d readable=%d secret=%d nil=%d sample=%s",
            key, c.n, c.readable, c.secret, c.nilCount, c.sample or "")
    end
    for _, p in ipairs(sentOrder) do
        local c = sentCounters[p]
        lines[#lines + 1] = string.format("UNIT_SPELLCAST_SENT %s n=%d readable=%d secret=%d empty=%d sample=%s",
            p, c.n, c.readable, c.secret, c.empty, c.sample or "")
    end
    if #lines == 0 then lines[1] = "none" end
    return lines
end

--------------------------------------------------------------------------------
-- == damage meter -- one block per session type, everything inside ONE pcall
-- per type (a raise partway through is the finding, not a crash), and every
-- index happens only after IsSecret said no.
--------------------------------------------------------------------------------
local function SessionBlock(name, sessionVal, healingVal, getSession, getSource, onCurrentSources)
    if type(getSession) ~= "function" then
        return { "session " .. name .. " HealingDone = <absent>" }
    end

    -- Set exactly once, as a whole, complete and in order -- appending detail
    -- rows to an empty "lines" and only later overwriting lines[1] with the
    -- summary would silently clobber the first detail row.
    local lines = nil
    local ok, err = pcall(function()
        local sess = getSession(sessionVal, healingVal)
        if IsSecret(sess) then
            lines = { "session " .. name .. " HealingDone = <secret>" }
            return
        end
        if type(sess) ~= "table" then
            lines = { "session " .. name .. " HealingDone = <absent>" }
            return
        end
        local sources = sess.combatSources
        if IsSecret(sources) or type(sources) ~= "table" then
            lines = { "session " .. name .. " HealingDone = sources=0" }
            return
        end

        local rowCount, localRow, rowLines = 0, nil, {}
        for i, row in ipairs(sources) do
            rowCount = rowCount + 1
            if not IsSecret(row) and type(row) == "table" then
                if i <= 5 then
                    rowLines[#rowLines + 1] = string.format("  source %d isLocalPlayer=%s totalAmount=%s",
                        i, Fmt(row.isLocalPlayer), Fmt(row.totalAmount))
                end
                if not IsSecret(row.isLocalPlayer) and row.isLocalPlayer == true then localRow = row end
            end
        end
        lines = { "session " .. name .. " HealingDone = sources=" .. tostring(rowCount) }
        for _, l in ipairs(rowLines) do lines[#lines + 1] = l end
        if name == "Current" and rowCount >= 1 and onCurrentSources then onCurrentSources() end

        if localRow then
            lines[#lines + 1] = "  local source = " .. Describe(localRow)
            if type(getSource) ~= "function" then
                lines[#lines + 1] = "  local spells = <absent>"
            else
                local spellsResult = getSource(sessionVal, healingVal, localRow.sourceGUID, nil)
                if IsSecret(spellsResult) then
                    lines[#lines + 1] = "  local spells = <secret>"
                elseif type(spellsResult) ~= "table" then
                    lines[#lines + 1] = "  local spells = <absent>"
                else
                    local spells = spellsResult.combatSpells
                    if IsSecret(spells) or type(spells) ~= "table" then
                        lines[#lines + 1] = "  local spells = combatSpells=0"
                    else
                        local spellCount, spellLines = 0, {}
                        for i, sp in ipairs(spells) do
                            spellCount = spellCount + 1
                            if i <= 5 then spellLines[#spellLines + 1] = "  spell " .. i .. " = " .. Describe(sp) end
                        end
                        lines[#lines + 1] = "  local spells = combatSpells=" .. tostring(spellCount)
                        for _, l in ipairs(spellLines) do lines[#lines + 1] = l end
                    end
                end
            end
        end
    end)
    if not ok or not lines then
        lines = { "session " .. name .. " HealingDone = <error: " .. Fmt(err) .. ">" }
    end
    return lines
end

local function DamageMeterLines()
    local lines = { "C_DamageMeter.IsDamageMeterAvailable() = " .. Show("C_DamageMeter.IsDamageMeterAvailable") }
    -- Q4 (whether the damage meter answers out of combat) is read once, here,
    -- rather than trusting the Current block to have been read out of combat
    -- just because it wasn't secret this time.
    local outOfCombat = First("UnitAffectingCombat", "player") == "false"

    local sessTypeEnum = MD.API.Has("Enum.DamageMeterSessionType")
    local typeEnum = MD.API.Has("Enum.DamageMeterType")
    local healingDone = nil
    if type(typeEnum) == "table" then
        local v, status = Field(typeEnum, "HealingDone")
        if status == "ok" then healingDone = v end
    end
    local getSession = MD.API.Has("C_DamageMeter.GetCombatSessionFromType")
    local getSource = MD.API.Has("C_DamageMeter.GetCombatSessionSourceFromType")
    if type(getSession) ~= "function" then getSession = nil end
    if type(getSource) ~= "function" then getSource = nil end

    local function MarkSeen()
        if outOfCombat then sawDamageMeterCurrentSources = true end
    end

    for _, name in ipairs({ "Current", "Overall" }) do
        local sessionVal = nil
        if type(sessTypeEnum) == "table" then
            local v, status = Field(sessTypeEnum, name)
            if status == "ok" then sessionVal = v end
        end
        for _, l in ipairs(SessionBlock(name, sessionVal, healingDone, getSession, getSource, MarkSeen)) do
            lines[#lines + 1] = l
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- == saved variables
--------------------------------------------------------------------------------
local function SavedVarsLines()
    local lines = { "SpellTunerDB at load: " .. svTypeAtLoad }
    lines[#lines + 1] = "previous session stamp: " .. (svPrevStamp ~= nil and Fmt(svPrevStamp) or "none")
    if #svReportsAtLoad > 0 then
        lines[#lines + 1] = "reports at load: " .. table.concat(svReportsAtLoad, "; ")
    else
        lines[#lines + 1] = "reports at load: none"
    end
    local thisStamp = "<no date>"
    if type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table" and SpellTunerDB.probe.stamp then
        thisStamp = tostring(SpellTunerDB.probe.stamp)
    end
    lines[#lines + 1] = "this session stamp: " .. thisStamp
    return lines
end

--------------------------------------------------------------------------------
-- == toc
--------------------------------------------------------------------------------
local function TocLines()
    return { "SPELLTUNER_TOC = " .. Fmt(_G.SPELLTUNER_TOC) }
end

--------------------------------------------------------------------------------
-- The copy box: a read-only scroll edit box holding plain text. Built once,
-- on the first Run(); the whole thing is one pcall, so a widget surprise on
-- the beta falls back to printing the report to chat instead of raising.
--------------------------------------------------------------------------------
local function ShowReportBox(report)
    return pcall(function()
        if not probeFrame then
            local f = CreateFrame("Frame", "SpellTunerProbeFrame", UIParent, "BackdropTemplate")
            f:SetSize(560, 420)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
            f:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

            local scroll = CreateFrame("ScrollFrame", nil, f)
            scroll:SetPoint("TOPLEFT", 8, -8)
            scroll:SetPoint("BOTTOMRIGHT", -28, 8)

            local eb = CreateFrame("EditBox", nil, scroll)
            eb:SetMultiLine(true)
            eb:SetAutoFocus(false)
            eb:SetWidth(520)
            eb:SetMaxLetters(0)
            pcall(eb.SetFont, eb, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
            scroll:SetScrollChild(eb)

            scroll:EnableMouseWheel(true)
            -- GetVerticalScroll/GetVerticalScrollRange are the widget's own
            -- geometry, not a client value -- the one exempt arithmetic.
            scroll:SetScript("OnMouseWheel", function(self, delta)
                local cur = self:GetVerticalScroll()
                local top = self:GetVerticalScrollRange()
                local new = cur - delta * 20
                if new < 0 then new = 0 end
                if new > top then new = top end
                self:SetVerticalScroll(new)
            end)

            tinsert(UISpecialFrames, "SpellTunerProbeFrame")
            probeFrame, probeEditBox = f, eb
        end

        probeEditBox:SetText(report)
        probeFrame:Show()
        probeEditBox:SetFocus()
        probeEditBox:HighlightText()
    end)
end

--------------------------------------------------------------------------------
-- Run(): builds the report, saves it, shows it, prints one chat line, returns
-- the report string. Never raises -- every section builder above already
-- swallows its own client-call failures.
--------------------------------------------------------------------------------
local function Run()
    local lines = {}
    lines[#lines + 1] = "SpellTuner probe " .. Version() .. " -- " .. SafeDate()

    lines[#lines + 1] = "== client"
    for _, l in ipairs(ClientLines()) do lines[#lines + 1] = l end

    local functionsLines, presentN, absentN = FunctionsLines()
    lines[#lines + 1] = string.format("== functions (%d present, %d absent)", presentN, absentN)
    for _, l in ipairs(functionsLines) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== events"
    for _, l in ipairs(EventsSummaryLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== secrets now"
    for _, l in ipairs(SecretsLines()) do lines[#lines + 1] = l end

    local bonusStr = Show("GetSpellBonusHealing")
    local n, h, e, secretN, errorN, order, descByKey = SpellWalk()
    lines[#lines + 1] = string.format("== spells (bonus healing %s)", bonusStr)
    lines[#lines + 1] = string.format(
        "slots 1-500: %d with a spell, %d healing, %d empty description, %d secret, %d error",
        n, h, e, secretN, errorN)

    -- Ranks per name: how many ranks of each healing spell were found, so a
    -- run after turning on "show all ranks" in the spellbook can be diffed
    -- against one before.
    do
        local rankCounts, rankNames = {}, {}
        for _, sp in ipairs(order) do
            if sp.healing then
                if not rankCounts[sp.name] then
                    rankCounts[sp.name] = 0
                    rankNames[#rankNames + 1] = sp.name
                end
                rankCounts[sp.name] = rankCounts[sp.name] + 1
            end
        end
        table.sort(rankNames)
        if #rankNames == 0 then
            lines[#lines + 1] = "ranks per name: none"
        else
            local parts = {}
            for _, nm in ipairs(rankNames) do parts[#parts + 1] = nm .. " " .. rankCounts[nm] end
            lines[#lines + 1] = "ranks per name: " .. table.concat(parts, "; ")
        end
    end

    for _, sp in ipairs(order) do
        if sp.healing then
            lines[#lines + 1] = "spell " .. sp.key
            lines[#lines + 1] = "  name: " .. sp.name
            lines[#lines + 1] = "  rank: " .. sp.rank
            lines[#lines + 1] = "  desc: " .. sp.desc
        end
    end

    local buildKey = BuildKey()
    local againstLines, q1Info = AgainstPreviousLines(order, descByKey, bonusStr, buildKey)
    for _, l in ipairs(againstLines) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== talents"
    for _, l in ipairs(TalentsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== readings now"
    for _, l in ipairs(ReadingsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== combat snapshot"
    for _, l in ipairs(CombatSnapshotLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== events seen this session"
    for _, l in ipairs(EventsSeenLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== damage meter"
    for _, l in ipairs(DamageMeterLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== saved variables"
    for _, l in ipairs(SavedVarsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== toc"
    for _, l in ipairs(TocLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== to do"

    if q1Info.compared and Readable(q1Info.oldBonus) and Readable(q1Info.newBonus)
        and q1Info.oldBonus ~= q1Info.newBonus then
        lines[#lines + 1] = string.format("Q1 answered: %d of %d spell descriptions changed when bonus healing went %s -> %s",
            q1Info.changedCount or 0, q1Info.totalCount or 0, Fmt(q1Info.oldBonus), q1Info.newBonus)
    else
        lines[#lines + 1] = "Q1 to do: turn on show all ranks in the spellbook (the arrow at its top right), then change your bonus healing (put on or take off a +healing item, or take a buff that changes the number in the spells header), then type /st probe again in the same session"
    end

    local partyOk = combatSnapshot ~= nil and combatSnapshot.partyExists == "true"
    local q2q5todo = "in a party, pull a mob; the probe reads itself 2 seconds into the fight; type /st probe after the fight"
    if partyOk then
        lines[#lines + 1] = "Q2 answered: UnitExists(party1) read true in the combat snapshot"
        lines[#lines + 1] = "Q5 answered: UnitExists(party1) read true in the combat snapshot"
    else
        lines[#lines + 1] = "Q2 to do: " .. q2q5todo
        lines[#lines + 1] = "Q5 to do: " .. q2q5todo
    end

    local q3ok = false
    for _, key in ipairs(combatOrder) do
        if key:match("^combat party ") then q3ok = true; break end
    end
    if q3ok then
        lines[#lines + 1] = "Q3 answered: a UNIT_COMBAT combat party counter was seen"
    else
        lines[#lines + 1] = "Q3 to do: in the same fight, let the party member take damage and be healed, then type /st probe after the fight"
    end

    if sawDamageMeterCurrentSources then
        lines[#lines + 1] = "Q4 answered: the damage meter listed at least one source out of combat"
    else
        lines[#lines + 1] = "Q4 to do: after a fight, out of combat, type /st probe"
    end

    lines[#lines + 1] = "Q6 answered: see == talents"

    if svPrevStamp ~= nil then
        lines[#lines + 1] = "Q7 answered: SavedVariables came back (previous stamp " .. Fmt(svPrevStamp) .. ")"
    else
        lines[#lines + 1] = "Q7 to do: type /reload, then /st probe; if this line still says to do, SavedVariables did not come back"
    end

    local sentCombat = sentCounters["combat"]
    if combatSnapshot ~= nil and sentCombat and sentCombat.n >= 1 then
        lines[#lines + 1] = "Q8 answered: a UNIT_SPELLCAST_SENT combat counter was seen"
    else
        lines[#lines + 1] = "Q8 to do: cast a heal on the party member during the fight, then type /st probe after the fight"
    end

    lines[#lines + 1] = "Q9 answered: SPELLTUNER_TOC = " .. Fmt(_G.SPELLTUNER_TOC)

    local report = table.concat(lines, "\n")

    -- Save: keyed by build, overwriting only after everything above already
    -- read the OLD record for the comparison and the to-do line.
    local saved = false
    if type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table"
        and type(SpellTunerDB.probe.reports) == "table" then
        local descSave = {}
        for _, sp in ipairs(order) do descSave[sp.key] = descByKey[sp.key] end
        SpellTunerDB.probe.reports[buildKey] = {
            char = First("UnitName", "player") .. "-" .. First("GetRealmName"),
            at = SafeDate(),
            text = report,
            bonus = bonusStr,
            desc = descSave,
        }
        writtenThisSession[buildKey] = true
        saved = true
    end

    local boxOk = ShowReportBox(report)
    if not boxOk then
        DEFAULT_CHAT_FRAME:AddMessage("SpellTuner probe: could not open the copy box, printing the report:")
        for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage(l) end
    end
    if saved then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "SpellTuner probe: build %s, %d lines, saved. Click the box, Ctrl+A, Ctrl+C.", buildKey, #lines))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "SpellTuner probe: build %s, %d lines, not saved (no SavedVariables table). Click the box, Ctrl+A, Ctrl+C.",
            buildKey, #lines))
    end

    return report
end

--------------------------------------------------------------------------------
-- Load-time: the frame, ADDON_LOADED's SavedVariables guard, the phase/event
-- handlers, event registration and the slash commands.
--------------------------------------------------------------------------------
-- Forward-declared so OnAddonLoaded (defined before the frame exists) can
-- still unregister itself on it once ADDON_NAME has come through.
local frame

local function OnAddonLoaded(loadedName)
    if loadedName ~= ADDON_NAME then return end
    -- handled once: a later ADDON_LOADED for some other addon would still
    -- reach this handler otherwise, uselessly re-scanning SpellTunerDB.
    pcall(frame.UnregisterEvent, frame, "ADDON_LOADED")

    svTypeAtLoad = type(SpellTunerDB)
    if svTypeAtLoad == "table" and type(SpellTunerDB.probe) == "table" then
        svPrevStamp = SpellTunerDB.probe.stamp
        if type(SpellTunerDB.probe.reports) == "table" then
            local keys = {}
            for k in pairs(SpellTunerDB.probe.reports) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local rec = SpellTunerDB.probe.reports[k]
                local char = (type(rec) == "table") and Fmt(rec.char) or "<absent>"
                local at = (type(rec) == "table") and Fmt(rec.at) or "<absent>"
                svReportsAtLoad[#svReportsAtLoad + 1] = tostring(k) .. " (" .. char .. ", " .. at .. ")"
            end
        end
    end

    if type(SpellTunerDB) ~= "table" then SpellTunerDB = {} end
    if type(SpellTunerDB.probe) ~= "table" then SpellTunerDB.probe = {} end
    if type(SpellTunerDB.probe.reports) ~= "table" then SpellTunerDB.probe.reports = {} end
    SpellTunerDB.probe.stamp = SafeDate()
end

local function OnRegenDisabled()
    phase = "combat"
    local after = MD.API.Has("C_Timer.After")
    if type(after) == "function" then
        pcall(after, 2, function() pcall(TakeCombatSnapshot) end)  -- runs later, outside every other pcall
    else
        TakeCombatSnapshot()
    end
end

local function OnRegenEnabled()
    phase = "ooc"
end

local function OnCombatEvent(unit, action, descriptor, amount)
    BumpCombat(phase, unit, action, amount)
end

local function OnSpellcastSent(unit, target)
    BumpSent(phase, target)
end

local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_REGEN_DISABLED = OnRegenDisabled,
    PLAYER_REGEN_ENABLED = OnRegenEnabled,
    UNIT_COMBAT = OnCombatEvent,
    UNIT_SPELLCAST_SENT = OnSpellcastSent,
}

frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    local handler = HANDLERS[event]
    if handler then pcall(handler, ...) end
end)

pcall(frame.RegisterEvent, frame, "ADDON_LOADED")

for _, event in ipairs(EVENTS) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    -- "ok and nil or X" would always pick X (nil is falsy, so the "or" side
    -- always runs) -- the trap CLAUDE.md warns about, written out instead.
    local errText = nil
    if not ok then errText = "<error: " .. Fmt(err) .. ">" end
    eventOutcomes[event] = { ok = ok, err = errText }
end

SLASH_SPELLTUNER1 = "/spelltuner"
SLASH_SPELLTUNER2 = "/st"
SLASH_SPELLTUNER3 = "/md"
SlashCmdList.SPELLTUNER = function(msg)
    local first = tostring(msg or ""):match("^%s*(%S*)")
    if first and first:lower() == "probe" then
        Run()
    else
        DEFAULT_CHAT_FRAME:AddMessage("SpellTuner probe: type /st probe")
    end
end

MD.Probe = { Run = Run }
