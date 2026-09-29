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
-- depth (default 1) is how many levels of nested non-secret table a field may
-- itself be walked instead of just Fmt'd -- T0c's one-level-deeper damage
-- meter dump (Describe(row, 2)) without a second, near-identical walker.
local function Describe(v, depth)
    depth = depth or 1
    if IsSecret(v) or v == nil or type(v) ~= "table" then return Fmt(v) end
    local ok, result = pcall(function()
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return Esc(tostring(a)) < Esc(tostring(b)) end)
        local parts, count = {}, 0
        for _, k in ipairs(keys) do
            count = count + 1
            if count > 24 then parts[#parts + 1] = "..."; break end
            local val = v[k]
            if depth > 1 and not IsSecret(val) and type(val) == "table" then
                parts[#parts + 1] = Esc(tostring(k)) .. "=" .. Describe(val, depth - 1)
            else
                parts[#parts + 1] = Esc(tostring(k)) .. "=" .. Fmt(val)
            end
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

-- Like Show, but renders every return through Describe at the given depth --
-- T7a: a spell's cost table is one level too shallow at Show's default depth
-- (1), which would print its inner row as "<table>" instead of the fields.
local function ShowDepth(name, depth, ...)
    local fn = MD.API.Has(name)
    if type(fn) ~= "function" then return "<absent>" end
    local n, packed = packPcall(pcall(fn, ...))
    if not packed[1] then return "<error: " .. Fmt(packed[2]) .. ">" end
    if n <= 1 then return "nothing" end
    local parts = {}
    for i = 2, n do parts[#parts + 1] = Describe(packed[i], depth) end
    return table.concat(parts, ", ")
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

-- COMBAT_LOG_EVENT_UNFILTERED is deliberately NOT here, and nowhere else in
-- this file (T0d): registering it is forbidden on Forever, not even under
-- pcall (docs/FOREVER-PLAN.md §1.2) -- the sixth report watched the client
-- fire ADDON_ACTION_FORBIDDEN and show the blocked-action dialog the moment
-- it was tried. Nothing in this file ever attempts it.
local EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA",
    "UNIT_FLAGS", "UNIT_COMBAT", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

-- The damage meter's per-session spell-row print cap (T0c item 4), one
-- constant for both sessions; the per-source row cap a few lines below is a
-- separate, untouched 5.
local SPELL_ROWS = 5

--------------------------------------------------------------------------------
-- Session state
--------------------------------------------------------------------------------
local phase = "ooc"
-- What the probe is doing right now (T0c item 1), so a blocked/forbidden
-- action that names us can say what it interrupted. Exact values: "load",
-- "register:<EVENT>", "ADDON_LOADED", "run", "snapshot", "idle" --
-- see the file's load-time section and Run()/TakeCombatSnapshot for where
-- each is set and restored.
local doing = "load"
local eventOutcomes = {}                 -- EVENT -> { ok = bool, err = "<error: ...>" }
local combatCounters, combatOrder = {}, {}
-- T13b: UNIT_COMBAT by exact token (nameplateN/raidN/raidpetN folded), beside
-- combatCounters' by-class counts -- which tokens make up "other" is UNKNOWN
-- (FOREVER-PLAN.md §6 Q3). tokenCounters/tokenOrder key by "phase\1token";
-- mirrorCounters/mirrorOrder key by phase alone; unitCombatEvents is the
-- CURRENT MOMENT's events only -- {phase, timeKey, action, amountKey, token,
-- guidKey}
-- -- a later event is checked against it to find a same-GetTime()-moment
-- mirror. Re-issue 1: a mirror can only ever be within one GetTime() moment,
-- so the list is emptied whenever a new moment arrives (lastUnitCombatTimeKey
-- tracks the moment the list currently holds) -- it never grows past one
-- frame's worth of events even over a whole dungeon session.
local tokenCounters, tokenOrder = {}, {}
local mirrorCounters, mirrorOrder = {}, {}
local unitCombatEvents = {}
local lastUnitCombatTimeKey = nil
local sentCounters, sentOrder = {}, {}
-- T7a: UNIT_SPELLCAST_SUCCEEDED, by phase -- beside sentCounters/sentOrder,
-- but a cast SUCCEEDED (not merely sent) is what the cost-at-cast shape needs.
local succeededCounters, succeededOrder = {}, {}
-- T7a: the most recent "first spell whose description contains heal" a walk
-- found (updated by ShapesLines every time one runs) -- the combat snapshot
-- re-reads THIS spell's shapes live rather than re-walking the book while
-- secrecy may have changed what a fresh walk could even find.
local knownFirstHeal = nil
local restrictionCounters, restrictionOrder = {}, {}   -- ADDON_RESTRICTION_STATE_CHANGED, by "<phase> <payload>"
local blockedCounters, blockedOrder = {}, {}           -- ADDON_ACTION_FORBIDDEN/BLOCKED naming us, by (event, phase, doing, function)
local actionForbiddenOutcome, actionBlockedOutcome = "throws <error: not registered>", "throws <error: not registered>"
local combatSnapshot = nil                -- { stamp, inCombat, partyExists, lines } or nil
-- review-probe R2: snapshot timers that fired after the fight had already
-- ended (PLAYER_REGEN_ENABLED came first) -- not taken, only counted.
local combatSnapshotsSkipped = 0
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
    -- review-probe R17: a pet's token starts with "party"/"raid" too, and a
    -- partypetN hit must not answer Q3 (is a PARTY MEMBER's UNIT_COMBAT seen).
    if u:sub(1, 8) == "partypet" then return "partypet" end
    if u:sub(1, 7) == "raidpet" then return "raidpet" end
    if u:sub(1, 5) == "party" then return "party" end
    if u:sub(1, 4) == "raid" then return "raid" end
    return "other"
end

local function ActionOf(a)
    if IsSecret(a) then return "<secret>" end
    if type(a) ~= "string" then return "<none>" end
    return Esc(a)
end

-- T13b: whole-word "heal"/"heals"/"healing" (a frontier pattern), not the
-- substring test that let Endurance ("Total Health increased by 5%") count
-- as a heal -- "Health" contains "heal" as a mere substring, "heal" bounded
-- by word edges does not match it. Takes an already-lowered description.
local function IsHealingText(lowered)
    if type(lowered) ~= "string" then return false end
    return lowered:find("%f[%a]heal%f[%A]") ~= nil
        or lowered:find("%f[%a]heals%f[%A]") ~= nil
        or lowered:find("%f[%a]healing%f[%A]") ~= nil
end

-- T13b: a NUMBER, an optional word (a school name), then the word "damage" --
-- not the substring test that let Plainsrunning ("Taking damage...") count
-- as a damage spell: nothing numeric precedes "damage" there. Takes an
-- already-lowered description.
local function IsDamageText(lowered)
    if type(lowered) ~= "string" then return false end
    return lowered:find("%d+%s+%a-%s*%f[%a]damage%f[%A]") ~= nil
end

-- T13b: a healing description naming a direct heal -- two numbers joined by
-- "to" ("Heals a friendly target for 40 to 55.").
local function IsDirectHealText(lowered)
    if type(lowered) ~= "string" then return false end
    return lowered:find("%d+%s+to%s+%d+") ~= nil
end

-- T13b: a healing description naming a heal over time -- the word "over"
-- ("Heals the target for 32 over 12 sec.").
local function IsOverTimeHealText(lowered)
    if type(lowered) ~= "string" then return false end
    return lowered:find("%f[%a]over%f[%A]") ~= nil
end

local function SafeDate()
    local ok, stamp = pcall(date, "%Y-%m-%d %H:%M:%S")
    if ok then return stamp end
    return "<no date>"
end

-- T13b: GetTime() rendered to a plain string (never used raw -- see the
-- Counters comment below), so two UNIT_COMBAT events can be compared for
-- "the same moment" by plain string equality only.
local function TimeKey()
    local getTime = MD.API.Has("GetTime")
    if type(getTime) ~= "function" then return "<absent>" end
    local ok, t = pcall(getTime)
    if not ok then return "<error>" end
    if IsSecret(t) then return "<secret>" end
    return Fmt(t)
end

-- T13b: a plain unit token, exact except numbered nameplate/raid/raidpet
-- tokens folded to their family (Files: "nameplateN folded to nameplate,
-- raidN to raid, raidpetN to raidpet") -- the individual number is not the
-- question, whether the FAMILY appears in UNIT_COMBAT's "other" bucket is.
local function FoldToken(tok)
    if IsSecret(tok) then return "<secret>" end
    if type(tok) ~= "string" then return "<none>" end
    if tok:match("^nameplate%d+$") then return "nameplate" end
    if tok:match("^raidpet%d+$") then return "raidpet" end
    if tok:match("^raid%d+$") then return "raid" end
    return Esc(tok)
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

-- T13b: UNIT_COMBAT by exact token, with GUID readability at the moment of
-- the event, and same-"GetTime()"-moment mirror detection (Files: "an event
-- is a mirror when an earlier event in the same GetTime() had the same
-- action and the same plain amount under a different token"), narrowed by
-- review-probe R18: not when both GUIDs read plain and differ.
local function BumpUnitCombatToken(currentPhase, unit, action, amount)
    local tokenText = FoldToken(unit)
    local key = currentPhase .. "\1" .. tokenText
    local c = tokenCounters[key]
    if not c then
        c = { phase = currentPhase, token = tokenText, n = 0, guidReadable = 0, guidSecret = 0 }
        tokenCounters[key] = c
        tokenOrder[#tokenOrder + 1] = key
    end
    c.n = c.n + 1

    -- review-probe R18: the GUID's text (Fmt of a plain, non-nil GUID only)
    -- is kept for the mirror test below; nil when it could not be read.
    local guidKey = nil
    if not IsSecret(unit) and type(unit) == "string" then
        local getGUID = MD.API.Has("UnitGUID")
        if type(getGUID) == "function" then
            local ok, guid = pcall(getGUID, unit)
            if ok then
                if IsSecret(guid) then
                    c.guidSecret = c.guidSecret + 1
                elseif guid ~= nil then
                    c.guidReadable = c.guidReadable + 1
                    guidKey = Fmt(guid)
                end
            end
        end
    end

    local mc = mirrorCounters[currentPhase]
    if not mc then
        mc = { phase = currentPhase, n = 0, mirrored = 0, unconfirmed = 0 }
        mirrorCounters[currentPhase] = mc
        mirrorOrder[#mirrorOrder + 1] = currentPhase
    end
    mc.n = mc.n + 1

    local timeKey = TimeKey()
    if timeKey ~= lastUnitCombatTimeKey then
        -- Re-issue 1: a new moment -- the previous moment's events can never
        -- be a mirror match again, so drop them rather than scan them forever.
        for i = #unitCombatEvents, 1, -1 do
            unitCombatEvents[i] = nil
        end
        lastUnitCombatTimeKey = timeKey
    end

    local actionText = ActionOf(action)
    local amountKey = "<none>"
    if not IsSecret(amount) and amount ~= nil then
        amountKey = Fmt(amount)
        -- review-probe R18: two DIFFERENT units hit or healed for the same
        -- amount in one frame (an area tick, Tranquility on player and
        -- party1) match on everything above; the GUID tells them apart. Two
        -- readable GUIDs that differ are never a mirror; the same GUID is a
        -- confirmed one; when either GUID could not be read the match is
        -- still counted, as before, but also counted as unconfirmed, so the
        -- report says it may be two units.
        local confirmed, unsure = false, false
        for _, ev in ipairs(unitCombatEvents) do
            if ev.phase == currentPhase and ev.timeKey == timeKey and ev.action == actionText
                and ev.amountKey == amountKey and ev.token ~= tokenText then
                if guidKey ~= nil and ev.guidKey ~= nil then
                    if ev.guidKey == guidKey then confirmed = true; break end
                else
                    unsure = true
                end
            end
        end
        if confirmed then
            mc.mirrored = mc.mirrored + 1
        elseif unsure then
            mc.mirrored = mc.mirrored + 1
            mc.unconfirmed = mc.unconfirmed + 1
        end
    end
    unitCombatEvents[#unitCombatEvents + 1] = {
        phase = currentPhase, timeKey = timeKey, action = actionText, amountKey = amountKey, token = tokenText,
        guidKey = guidKey,
    }
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

-- T7a item 7: UNIT_SPELLCAST_SUCCEEDED's spell id, by phase -- readable/secret
-- like every other counter here, plus whether GetSpellPowerCost(id) answers
-- for a readable one (its own readable/secret/absent/no-cost tally, never the
-- id's; review-probe R19 added "no cost" and the walk into the rows).
local function BumpSucceeded(currentPhase, spellID)
    local c = succeededCounters[currentPhase]
    if not c then
        c = { n = 0, readable = 0, secret = 0, sample = nil, costReadable = 0, costSecret = 0, costAbsent = 0, costNone = 0 }
        succeededCounters[currentPhase] = c
        succeededOrder[#succeededOrder + 1] = currentPhase
    end
    c.n = c.n + 1
    if IsSecret(spellID) then
        c.secret = c.secret + 1
    elseif spellID ~= nil then
        c.readable = c.readable + 1
        if not c.sample then c.sample = Fmt(spellID) end
        local getCost = MD.API.Has("C_Spell.GetSpellPowerCost")
        if type(getCost) ~= "function" then
            c.costAbsent = c.costAbsent + 1
        else
            local ok, result = pcall(getCost, spellID)
            if not ok then
                c.costAbsent = c.costAbsent + 1
            elseif IsSecret(result) then
                c.costSecret = c.costSecret + 1
            elseif result == nil then
                -- review-probe R19: nothing came back (a free spell's measured
                -- shape) -- nothing was read, so not "readable".
                c.costNone = c.costNone + 1
            elseif type(result) ~= "table" then
                c.costReadable = c.costReadable + 1
            else
                -- review-probe R19: a plain list can still hold secret rows or
                -- fields; each row and each field is asked, never indexed or
                -- used before IsSecret said no. A walk that raises counts as
                -- secret (indexing a secret is what raises on this client).
                local walked, anySecret, rows = pcall(function()
                    local secret, n = false, 0
                    for _, row in pairs(result) do
                        n = n + 1
                        if IsSecret(row) then
                            secret = true
                        elseif type(row) == "table" then
                            for _, v in pairs(row) do
                                if IsSecret(v) then secret = true end
                            end
                        end
                    end
                    return secret, n
                end)
                if not walked or anySecret then
                    c.costSecret = c.costSecret + 1
                elseif rows == 0 then
                    c.costNone = c.costNone + 1
                else
                    c.costReadable = c.costReadable + 1
                end
            end
        end
    end
end

-- ADDON_RESTRICTION_STATE_CHANGED(restrictionType, state, ...): every argument
-- through Fmt and joined, never inspected -- the planner reads the payload,
-- the probe only counts it (T0c item 3).
local function BumpRestriction(currentPhase, ...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[#parts + 1] = Fmt((select(i, ...))) end
    local payload = (n > 0) and table.concat(parts, ", ") or "nothing"
    local key = currentPhase .. " " .. payload
    local c = restrictionCounters[key]
    if not c then
        c = { phase = currentPhase, payload = payload, n = 0 }
        restrictionCounters[key] = c
        restrictionOrder[#restrictionOrder + 1] = key
    end
    c.n = c.n + 1
end

-- ADDON_ACTION_FORBIDDEN/ADDON_ACTION_BLOCKED(addonName, functionName): kept
-- only when the addon name is ours (Fmt/Esc compared as text, never raw --
-- T0c item 1), counted per (event, phase, doing, function), first-seen order.
-- review-probe R20: "ours" includes the LoadOnDemand modules, which the client
-- names by their own folders (SpellTuner_Recorder, _Replay, _Practice) -- the
-- same "SpellTuner_" prefix Core_Forever.lua's error capture accepts. Their
-- own actions would otherwise be dropped and the section print "none".
local function BumpBlocked(event, addonName, functionName)
    local nameText = Fmt(addonName)
    local own = Esc(ADDON_NAME)
    if nameText ~= own and nameText:sub(1, #own + 1) ~= own .. "_" then return end
    local fn = Fmt(functionName)
    local key = event .. "\1" .. phase .. "\1" .. doing .. "\1" .. fn
    local c = blockedCounters[key]
    if not c then
        c = { event = event, phase = phase, doing = doing, addon = Fmt(addonName), fn = fn, n = 0 }
        blockedCounters[key] = c
        blockedOrder[#blockedOrder + 1] = key
    end
    c.n = c.n + 1
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
    -- T0d: registering it is forbidden on Forever, not even under pcall, so
    -- there is no outcome to report here -- just the fact.
    lines[#lines + 1] = "COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)"
    return lines
end

--------------------------------------------------------------------------------
-- == blocked actions -- ADDON_ACTION_FORBIDDEN/ADDON_ACTION_BLOCKED naming us
-- (T0c item 1), right after == events.
--------------------------------------------------------------------------------
local function BlockedActionsLines()
    local lines = {
        "listening: ADDON_ACTION_FORBIDDEN " .. actionForbiddenOutcome
            .. ", ADDON_ACTION_BLOCKED " .. actionBlockedOutcome,
    }
    if #blockedOrder == 0 then
        lines[#lines + 1] = "none"
    else
        for _, key in ipairs(blockedOrder) do
            local c = blockedCounters[key]
            lines[#lines + 1] = string.format("%s phase=%s during=%s addon=%s function=%s n=%d",
                c.event, c.phase, c.doing, c.addon, c.fn, c.n)
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
-- T13e, FOREVER-PLAN.md planner ruling 1: whether a plain StatusBar handed a
-- client value through its own setters (SetMinMaxValues / SetValue) gives it
-- back through its own getters (GetMinMaxValues / GetValue) secret, plain, or
-- not at all. One hidden bar, built on first use and kept in this upvalue --
-- never shown, no name, no parent other than UIParent -- so every call in
-- this run reuses the same bar rather than leaking a frame per reading.
local probeBar
local function BarReadback(label, fnName, ...)
    local fn = MD.API.Has(fnName)
    if type(fn) ~= "function" then
        return "bar " .. label .. ": set <absent>, read nil"
    end
    if not probeBar then
        local cok, bar = pcall(CreateFrame, "StatusBar", nil, UIParent)
        if cok and type(bar) == "table" then probeBar = bar end
    end
    if not probeBar then
        return "bar " .. label .. ": set <error: no bar>, read nil"
    end

    -- T13e: "Max" in the function's own name is what tells a max reading
    -- (SetMinMaxValues/GetMinMaxValues) from a current-value one
    -- (SetMinMaxValues(0,1)+SetValue/GetValue) -- true for every name this
    -- task passes (UnitHealthMax vs UnitHealth/UnitPower).
    local isMax = fnName:find("Max", 1, true) ~= nil
    local args = { ... }
    -- One pcall hands the client's own return straight to the bar's setters,
    -- never touched by anything else in between (a secret handed to a setter
    -- is only ever stored, never read here).
    local setOk, setErr = pcall(function()
        local v = fn(unpack(args))
        if isMax then
            probeBar:SetMinMaxValues(0, v)
        else
            probeBar:SetMinMaxValues(0, 1)
            probeBar:SetValue(v)
        end
    end)

    local setText = "ok"
    if not setOk then setText = "error: " .. Fmt(setErr) end
    -- The bar is shared, so after a failed set it still holds the previous
    -- reading's value; reading it back would report someone else's answer.
    if not setOk then return "bar " .. label .. ": set " .. setText .. ", read skipped" end

    local readText
    if isMax then
        local readOk, errOrMin, maxV = pcall(function() return probeBar:GetMinMaxValues() end)
        if not readOk then
            readText = "error: " .. Fmt(errOrMin)
        elseif IsSecret(maxV) then
            readText = "secret"
        elseif maxV == nil then
            readText = "nil"
        else
            readText = "plain " .. Fmt(maxV)
        end
    else
        local readOk, val = pcall(function() return probeBar:GetValue() end)
        if not readOk then
            readText = "error: " .. Fmt(val)
        elseif IsSecret(val) then
            readText = "secret"
        elseif val == nil then
            readText = "nil"
        else
            readText = "plain " .. Fmt(val)
        end
    end

    return "bar " .. label .. ": set " .. setText .. ", read " .. readText
end

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
        -- T0c item 3: whether health/power are secret always or only under a
        -- restriction is the question this run exists to answer -- these
        -- eighteen are read live here and, via TakeCombatSnapshot copying
        -- this same function, again at the 2s-into-combat mark, so the two
        -- can be read side by side.
        "C_Secrets.HasSecretRestrictions() = " .. Show("C_Secrets.HasSecretRestrictions"),
        "C_Secrets.ShouldUnitHealthMaxBeSecret(player) = " .. Show("C_Secrets.ShouldUnitHealthMaxBeSecret", "player"),
        "C_Secrets.ShouldUnitPowerBeSecret(player) = " .. Show("C_Secrets.ShouldUnitPowerBeSecret", "player"),
        "C_Secrets.ShouldUnitPowerMaxBeSecret(player) = " .. Show("C_Secrets.ShouldUnitPowerMaxBeSecret", "player"),
        "C_Secrets.GetPowerTypeSecrecy(0) = " .. Show("C_Secrets.GetPowerTypeSecrecy", 0),
        "C_Secrets.CanCompareUnitTokens(player, player) = " .. Show("C_Secrets.CanCompareUnitTokens", "player", "player"),
        "UnitHealthMax(player) = " .. Show("UnitHealthMax", "player"),
        "UnitPowerMax(player, 0) = " .. Show("UnitPowerMax", "player", 0),
        "UnitHealth(player, true) = " .. Show("UnitHealth", "player", true),
        "UnitHealthPercent(player) = " .. Show("UnitHealthPercent", "player"),
        "UnitHealthPercent(player, true) = " .. Show("UnitHealthPercent", "player", true),
        "UnitHealthMissing(player) = " .. Show("UnitHealthMissing", "player"),
        "UnitPowerPercent(player, 0) = " .. Show("UnitPowerPercent", "player", 0),
        "UnitGetIncomingHeals(player) = " .. Show("UnitGetIncomingHeals", "player"),
        "UnitIsDeadOrGhost(player) = " .. Show("UnitIsDeadOrGhost", "player"),
        "UnitHealth(party1, true) = " .. Show("UnitHealth", "party1", true),
        "UnitHealthPercent(party1) = " .. Show("UnitHealthPercent", "party1"),
        "UnitHealthPercent(party1, true) = " .. Show("UnitHealthPercent", "party1", true),
        -- T13b: the party member reads a recorder keys and labels by --
        -- GUID, name, level, class and role -- plus the max-health secrecy
        -- predicate for party1 (only ever read for "player" before this).
        "C_Secrets.ShouldUnitHealthMaxBeSecret(party1) = " .. Show("C_Secrets.ShouldUnitHealthMaxBeSecret", "party1"),
        "UnitGUID(party1) = " .. Show("UnitGUID", "party1"),
        "UnitName(party1) = " .. First("UnitName", "party1"),
        "UnitLevel(party1) = " .. Show("UnitLevel", "party1"),
        "UnitClass(party1) = " .. Show("UnitClass", "party1"),
        "UnitGroupRolesAssigned(party1) = " .. Show("UnitGroupRolesAssigned", "party1"),
        -- T13e: does a plain StatusBar hand a secret back through its own
        -- getters (FOREVER-PLAN.md planner ruling 1)? Copied into the 2s
        -- combat snapshot along with everything else in this function.
        BarReadback("UnitHealthMax(party1)", "UnitHealthMax", "party1"),
        BarReadback("UnitHealth(player)", "UnitHealth", "player"),
        BarReadback("UnitPower(player, 0)", "UnitPower", "player", 0),
        "UnitHealthMissing(party1) = " .. Show("UnitHealthMissing", "party1"),
    }
end

-- Enum.SpellBookSpellBank.Player, read once and reused everywhere a spellbook
-- row needs its bank argument (T7a: the shapes section calls the book by slot
-- again, outside SpellWalk, and must ask for the same bank it did).
local function PlayerBank()
    local bankEnum = MD.API.Has("Enum.SpellBookSpellBank")
    if type(bankEnum) ~= "table" then return nil end
    local v, status = Field(bankEnum, "Player")
    if status == "ok" then return v end
    return nil
end

--------------------------------------------------------------------------------
-- == spells -- walk slots 1..500 of our own accord (the client is never
-- trusted to say when to stop); dumps id/name/rank/desc for healing spells
-- only, but the desc table returned covers every non-secret spell found, so a
-- future run can notice one that STOPPED or STARTED containing "heal".
--------------------------------------------------------------------------------
local function SpellWalk()
    local playerBank = PlayerBank()

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

                        local descText, healing, dmg, direct, overTime = "<absent>", false, false, false, false
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
                                local lowered = dVal:lower()
                                -- T13b: word-bounded heal/heals/healing and a
                                -- number-then-damage test, not the substring
                                -- test a passive's "Health"/"Taking damage"
                                -- text used to pass.
                                healing = IsHealingText(lowered)
                                dmg = IsDamageText(lowered)
                                if healing then
                                    direct = IsDirectHealText(lowered)
                                    overTime = IsOverTimeHealText(lowered)
                                end
                            else
                                descText = Fmt(dVal)
                            end
                        end
                        if healing then h = h + 1 end

                        descByKey[key] = descText
                        -- T7a: id and slot are kept (both already known non-secret at this
                        -- point -- id via idStatus == "ok", slot is our own loop counter) so
                        -- the shapes section can call the book again by slot/id without
                        -- re-walking, and so it never touches a raw value SpellWalk itself
                        -- has not already cleared.
                        order[#order + 1] = { key = key, id = id, slot = slot, name = name, rank = rank,
                            desc = descText, healing = healing, dmg = dmg, direct = direct, overTime = overTime }
                    end
                end
            elseif ok and type(info) == "table" and IsSecret(info) then
                secretN = secretN + 1
            end
        end
    end

    return n, h, e, secretN, errorN, order, descByKey
end

-- Bonus damage per school, schools 2-7 (the classic API's numbering: Holy,
-- Fire, Nature, Frost, Shadow, Arcane) -- beside GetSpellBonusHealing in the
-- spells header (T0c item 5), so a bonus-damage-only change (an elixir) shows
-- up there without needing a +healing item or a level.
local function BonusDamageString()
    local schools = { { 2, "Holy" }, { 3, "Fire" }, { 4, "Nature" }, { 5, "Frost" }, { 6, "Shadow" }, { 7, "Arcane" } }
    local parts = {}
    for _, s in ipairs(schools) do
        parts[#parts + 1] = s[2] .. "=" .. Show("GetSpellBonusDamage", s[1])
    end
    return table.concat(parts, " ")
end

-- Readable, plus none of the "one school did not answer" markers -- a single
-- <absent>/<error:>/nil/nothing school makes the WHOLE string unusable for a
-- before/after comparison (T0c item 5's Q1 rule).
local function BonusDamageReadable(s)
    if not Readable(s) then return false end
    if s:find("<", 1, true) then return false end
    if s:find("=nil", 1, true) then return false end
    if s:find("=nothing", 1, true) then return false end
    return true
end

--------------------------------------------------------------------------------
-- == talents
--------------------------------------------------------------------------------
-- Second return: the rendered {tier=1, column=1} result, so Run() can tell
-- Q6 apart without re-deriving it from the lines (T0c item 6).
local function TalentsLines()
    local lines = {}
    lines[#lines + 1] = "C_SpecializationInfo.GetTalentInfo(1, 1) = " .. Show("C_SpecializationInfo.GetTalentInfo", 1, 1)
    local tierColumnShow = Show("C_SpecializationInfo.GetTalentInfo", { tier = 1, column = 1 })
    lines[#lines + 1] = "C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) = " .. tierColumnShow

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
    return lines, tierColumnShow
end

--------------------------------------------------------------------------------
-- == spells against the previous run
--------------------------------------------------------------------------------
-- info.compared, .old*/.new* (Bonus, Damage, Level), .changedCount,
-- .totalCount -- used by the to-do section's Q1 line without redoing the
-- SavedVariables read.
local function AgainstPreviousLines(order, descByKey, bonusStr, damageStr, levelStr, buildKey)
    local lines = { "== spells against the previous run" }
    local info = { compared = false }

    local prevRecord = nil
    if type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table"
        and type(SpellTunerDB.probe.reports) == "table" then
        prevRecord = SpellTunerDB.probe.reports[buildKey]
    end

    if type(prevRecord) == "table" and type(prevRecord.desc) == "table" then
        info.compared = true
        info.oldBonus, info.newBonus = prevRecord.bonus, bonusStr
        info.oldDamage, info.newDamage = prevRecord.damage, damageStr
        info.oldLevel, info.newLevel = prevRecord.level, levelStr
        local label = writtenThisSession[buildKey] and "this session" or "saved"
        lines[#lines + 1] = string.format(
            "previous: %s at %s, bonus healing %s -> %s, bonus damage %s -> %s, level %s -> %s",
            label, Fmt(prevRecord.at), Fmt(prevRecord.bonus), bonusStr,
            Fmt(prevRecord.damage), damageStr, Fmt(prevRecord.level), levelStr)

        -- A spell present in both runs is COMPARABLE only when both
        -- descriptions are Readable -- "<secret>" this run against a real
        -- sentence last run (or the reverse) is not a change, it is a hole in
        -- what either run could read. Each changed one keeps its stored texts
        -- so the first 12 can print was/now (T0c item 5) -- already Esc'd
        -- once when read/saved, so they print here exactly as stored: a
        -- second Esc would double-escape a pipe or a non-ASCII byte.
        local changed, comparedCount, notComparable = {}, 0, 0
        for _, sp in ipairs(order) do
            local prevDesc = prevRecord.desc[sp.key]
            local curDesc = descByKey[sp.key]
            if prevDesc ~= nil then
                if Readable(prevDesc) and Readable(curDesc) then
                    comparedCount = comparedCount + 1
                    if prevDesc ~= curDesc then
                        changed[#changed + 1] = { id = sp.key, name = sp.name, was = prevDesc, now = curDesc }
                    end
                else
                    notComparable = notComparable + 1
                end
            end
        end
        info.changedCount, info.totalCount = #changed, comparedCount
        if #changed > 0 then
            for i, c in ipairs(changed) do
                lines[#lines + 1] = "changed " .. c.id .. " " .. c.name
                if i <= 12 then
                    lines[#lines + 1] = "  was: " .. c.was
                    lines[#lines + 1] = "  now: " .. c.now
                end
            end
            if #changed > 12 then
                lines[#lines + 1] = "was/now shown for the first 12 of " .. #changed .. " changed spells"
            end
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
-- == shapes (T7a): every client return M2's spellbook reader, tooltip,
-- dashboard and clock will read, dumped whole so those modules can be built
-- against an answer rather than the retail documentation alone.
--------------------------------------------------------------------------------

-- One spell's tooltip: <n> lines, then each line's left/right text. Fmt
-- already escapes a string (so a pipe in the text reads "||") and renders
-- <secret>/nil/<table> for anything else -- there is no raw value here that
-- reaches the report unescaped.
local function TooltipLines(sp)
    local out = {}
    local getSpell = MD.API.Has("C_TooltipInfo.GetSpellByID")
    if type(getSpell) ~= "function" then
        out[1] = "tooltip = <absent>"
        return out
    end
    local ok, err = pcall(function()
        local n, packed = packPcall(pcall(getSpell, sp.id))
        if not packed[1] then
            out[1] = "tooltip " .. sp.key .. " = <error: " .. Fmt(packed[2]) .. ">"
            return
        end
        local result = packed[2]
        if IsSecret(result) then
            out[1] = "tooltip " .. sp.key .. " = <secret>"
            return
        end
        if type(result) ~= "table" then
            out[1] = "tooltip " .. sp.key .. " = <absent>"
            return
        end
        local linesField, status = Field(result, "lines")
        if status ~= "ok" or type(linesField) ~= "table" then
            out[1] = "tooltip " .. sp.key .. " = <absent>"
            return
        end
        local rowCount, rowLines = 0, {}
        for i, row in ipairs(linesField) do
            rowCount = rowCount + 1
            if not IsSecret(row) and type(row) == "table" then
                rowLines[#rowLines + 1] = "  line " .. i .. ": " .. Fmt(row.leftText) .. " || " .. Fmt(row.rightText)
            else
                rowLines[#rowLines + 1] = "  line " .. i .. ": <secret>"
            end
        end
        out[1] = "tooltip " .. sp.key .. " = " .. tostring(rowCount) .. " lines"
        for _, l in ipairs(rowLines) do out[#out + 1] = l end
    end)
    if not ok then
        out = { "tooltip " .. sp.key .. " = <error: " .. Fmt(err) .. ">" }
    end
    return out
end

-- The one healing spell the combat snapshot re-reads live (T7a item 6): every
-- call already goes through Show/ShowDepth, which is what clears the secrecy
-- a call made in combat may now answer with, exactly as everywhere else.
local function FirstHealShapesLine(sp)
    if not sp then return nil end
    return string.format("  desc=%s; info=%s; cost=%s; crit4=%s; bonus healing=%s",
        Show("C_Spell.GetSpellDescription", sp.id),
        Show("C_Spell.GetSpellInfo", sp.id),
        ShowDepth("C_Spell.GetSpellPowerCost", 2, sp.id),
        Show("GetSpellCritChance", 4),
        Show("GetSpellBonusHealing"))
end

-- UNIT_SPELLCAST_SUCCEEDED, one line per phase seen (T7a item 7).
local function SucceededLines()
    local lines = {}
    for _, p in ipairs(succeededOrder) do
        local c = succeededCounters[p]
        lines[#lines + 1] = string.format(
            "UNIT_SPELLCAST_SUCCEEDED %s n=%d readable=%d secret=%d sample=%s; cost at cast readable=%d secret=%d absent=%d no cost=%d",
            p, c.n, c.readable, c.secret, c.sample or "", c.costReadable, c.costSecret, c.costAbsent, c.costNone)
    end
    if #lines == 0 then lines[1] = "UNIT_SPELLCAST_SUCCEEDED: none this session" end
    return lines
end

-- order is the SAME walk Run() already did for == spells -- the shapes
-- section reads every id/slot it remembered rather than walking the book a
-- second time.
local function ShapesLines(order)
    local lines = {}

    -- item 1: the skill lines, whole -- only per-line if the count answers a
    -- plain, small, non-secret number (never looped on a client value that
    -- could be secret, absent or absurd).
    lines[#lines + 1] = "skill lines: " .. Show("C_SpellBook.GetNumSpellBookSkillLines")
    local getNumLines = MD.API.Has("C_SpellBook.GetNumSpellBookSkillLines")
    if type(getNumLines) == "function" then
        local ok, n = pcall(getNumLines)
        if ok and not IsSecret(n) and type(n) == "number" and n >= 1 and n <= 20 then
            for i = 1, n do
                lines[#lines + 1] = "skill line " .. i .. " = " .. Show("C_SpellBook.GetSpellBookSkillLineInfo", i)
            end
        end
    end

    -- item 2: every spell the walk found, in walk order.
    local bank = PlayerBank()
    for _, sp in ipairs(order) do
        lines[#lines + 1] = string.format(
            "book %s %s %s: info=%s; cost=%s; learned=%s; base=%s; lowrank=%s; row=%s",
            sp.key, sp.name, sp.rank,
            Show("C_Spell.GetSpellInfo", sp.id),
            ShowDepth("C_Spell.GetSpellPowerCost", 2, sp.id),
            Show("C_Spell.GetSpellLevelLearned", sp.id),
            Show("C_Spell.GetBaseSpell", sp.id),
            Show("C_SpellBook.IsSpellBookItemLowRank", sp.slot, bank),
            Show("C_SpellBook.GetSpellBookItemInfo", sp.slot, bank))
    end

    -- item 3 (T13b): the first direct heal's, the first heal-over-time's and
    -- the first damage spell's tooltip, each at most once, in walk order --
    -- a healing description with "to" between two numbers is a direct heal,
    -- one with "over" is a HoT (Facts: the old picks were two passives,
    -- Endurance and Plainsrunning, never an actual heal spell).
    -- knownFirstHeal is refreshed here so the combat snapshot, taken
    -- independently of any /st probe run, has a spell to re-read live.
    local foundDirect, foundOverTime, foundDamage = false, false, false
    for _, sp in ipairs(order) do
        if not foundDirect and sp.direct then
            foundDirect = true
            knownFirstHeal = sp
            for _, l in ipairs(TooltipLines(sp)) do lines[#lines + 1] = l end
        end
        if not foundOverTime and sp.overTime then
            foundOverTime = true
            for _, l in ipairs(TooltipLines(sp)) do lines[#lines + 1] = l end
        end
        if not foundDamage and sp.dmg then
            foundDamage = true
            for _, l in ipairs(TooltipLines(sp)) do lines[#lines + 1] = l end
        end
    end

    -- item 4: crit chance per school, 1 (Physical) through 7 (Arcane).
    local schoolNames = { "Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
    local critParts = {}
    for i, name in ipairs(schoolNames) do
        critParts[#critParts + 1] = name .. "=" .. Show("GetSpellCritChance", i)
    end
    lines[#lines + 1] = "crit: " .. table.concat(critParts, " ")

    -- item 5: bonus healing, read again here beside the schools above.
    lines[#lines + 1] = "bonus healing: " .. Show("GetSpellBonusHealing")

    -- item 6: the same few shapes, read again from inside combat.
    if not combatSnapshot then
        lines[#lines + 1] = "in combat: none this session"
    else
        lines[#lines + 1] = "in combat (" .. Fmt(combatSnapshot.stamp) .. "):"
        lines[#lines + 1] = combatSnapshot.shapesFirstHeal or "  <none>"
    end

    -- item 7: UNIT_SPELLCAST_SUCCEEDED, id and cost-at-cast readability.
    for _, l in ipairs(SucceededLines()) do lines[#lines + 1] = l end

    return lines
end

--------------------------------------------------------------------------------
-- Combat snapshot: taken 2s into PLAYER_REGEN_DISABLED (or at once if the
-- client has no C_Timer.After), and kept -- the last one of the session wins,
-- but only one taken while the fight was still on (review-probe R2).
--------------------------------------------------------------------------------
local function TakeCombatSnapshot()
    local savedDoing = doing
    doing = "snapshot"
    local lines = {}
    for _, l in ipairs(SecretsLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ReadingsLines()) do lines[#lines + 1] = l end
    combatSnapshot = {
        stamp = SafeDate(),
        inCombat = Show("UnitAffectingCombat", "player"),
        partyExists = Show("UnitExists", "party1"),
        lines = lines,
        shapesFirstHeal = FirstHealShapesLine(knownFirstHeal),
    }
    doing = savedDoing
end

--------------------------------------------------------------------------------
-- == combat snapshot
--------------------------------------------------------------------------------
local function CombatSnapshotLines()
    local lines
    if not combatSnapshot then
        lines = { "none this session" }
    else
        lines = { "taken " .. Fmt(combatSnapshot.stamp) .. ", in combat: " .. combatSnapshot.inCombat }
        for _, l in ipairs(combatSnapshot.lines) do lines[#lines + 1] = l end
    end
    -- review-probe R2: printed only when a snapshot was skipped, so a
    -- session with none skipped reads exactly as before.
    if combatSnapshotsSkipped > 0 then
        lines[#lines + 1] = string.format("skipped %d: the fight had ended before the 2 s snapshot", combatSnapshotsSkipped)
    end
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
    for _, key in ipairs(restrictionOrder) do
        local c = restrictionCounters[key]
        lines[#lines + 1] = string.format("ADDON_RESTRICTION_STATE_CHANGED %s payload=%s n=%d",
            c.phase, c.payload, c.n)
    end
    if #lines == 0 then lines[1] = "none" end
    return lines
end

--------------------------------------------------------------------------------
-- == unit combat tokens (T13b): per phase, per exact token, how many
-- UNIT_COMBAT events arrived and whether that token's GUID was readable at
-- the time -- which tokens make up "other" (FOREVER-PLAN.md §6 Q3) and
-- whether the same hit arrives twice under two tokens.
--------------------------------------------------------------------------------
local function UnitCombatTokensLines()
    local lines = {}
    for _, key in ipairs(tokenOrder) do
        local c = tokenCounters[key]
        lines[#lines + 1] = string.format("%s %s n=%d guid readable=%d guid secret=%d",
            c.phase, c.token, c.n, c.guidReadable, c.guidSecret)
    end
    for _, p in ipairs(mirrorOrder) do
        local mc = mirrorCounters[p]
        local line = string.format("%s mirrored: %d of %d", p, mc.mirrored, mc.n)
        -- review-probe R18: only when a counted mirror's unit was not
        -- confirmed by GUID, so a clean session's line reads as before.
        if (mc.unconfirmed or 0) > 0 then
            line = line .. string.format(" (%d with a guid not readable, so possibly two units)", mc.unconfirmed)
        end
        lines[#lines + 1] = line
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
                            -- depth 2 (T0c item 4): combatSpellDetails, a
                            -- field of this row, is itself walked one level
                            -- rather than printed as <table>.
                            if i <= SPELL_ROWS then spellLines[#spellLines + 1] = "  spell " .. i .. " = " .. Describe(sp, 2) end
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

-- T0d: Q1's answer, once given, is sticky per build -- a run with no change
-- since the last one must not flip an answered Q1 back to "to do" (ninth
-- report). Reads only this build's own record; a record for another build is
-- never consulted. at/text are our own strings read back from
-- SavedVariables, so both are type-checked before use.
local function PreviousQ1(buildKey)
    if type(SpellTunerDB) ~= "table" or type(SpellTunerDB.probe) ~= "table"
        or type(SpellTunerDB.probe.reports) ~= "table" then
        return nil
    end
    local rec = SpellTunerDB.probe.reports[buildKey]
    if type(rec) ~= "table" or type(rec.q1) ~= "table" then return nil end
    if type(rec.q1.at) ~= "string" or type(rec.q1.text) ~= "string" then return nil end
    return rec.q1
end

--------------------------------------------------------------------------------
-- Run(): builds the report, saves it, shows it, prints one chat line, returns
-- the report string. Never raises -- every section builder above already
-- swallows its own client-call failures.
--------------------------------------------------------------------------------
local function Run()
    -- T0c item 1: "run" for the whole build, restored on the way out so a
    -- blocked/forbidden action that fires from inside (e.g. the copy box)
    -- names it, and so the very next idle-phase action does not still read
    -- "run" (Run() never raises, so a plain save/restore is enough -- no
    -- early return to miss).
    local savedDoing = doing
    doing = "run"

    local lines = {}
    lines[#lines + 1] = "SpellTuner probe " .. Version() .. " -- " .. SafeDate()

    lines[#lines + 1] = "== client"
    for _, l in ipairs(ClientLines()) do lines[#lines + 1] = l end

    local functionsLines, presentN, absentN = FunctionsLines()
    lines[#lines + 1] = string.format("== functions (%d present, %d absent)", presentN, absentN)
    for _, l in ipairs(functionsLines) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== events"
    for _, l in ipairs(EventsSummaryLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== blocked actions"
    for _, l in ipairs(BlockedActionsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== secrets now"
    for _, l in ipairs(SecretsLines()) do lines[#lines + 1] = l end

    local bonusStr = Show("GetSpellBonusHealing")
    local damageStr = BonusDamageString()
    local levelStr = First("UnitLevel", "player")
    local n, h, e, secretN, errorN, order, descByKey = SpellWalk()
    lines[#lines + 1] = string.format("== spells (bonus healing %s, bonus damage %s)", bonusStr, damageStr)
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
    local againstLines, q1Info = AgainstPreviousLines(order, descByKey, bonusStr, damageStr, levelStr, buildKey)
    for _, l in ipairs(againstLines) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== talents"
    local talentsLines, tierColumnShow = TalentsLines()
    for _, l in ipairs(talentsLines) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== shapes"
    for _, l in ipairs(ShapesLines(order)) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== readings now"
    for _, l in ipairs(ReadingsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== combat snapshot"
    for _, l in ipairs(CombatSnapshotLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== events seen this session"
    for _, l in ipairs(EventsSeenLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== unit combat tokens"
    for _, l in ipairs(UnitCombatTokensLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== damage meter"
    for _, l in ipairs(DamageMeterLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== saved variables"
    for _, l in ipairs(SavedVarsLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== toc"
    for _, l in ipairs(TocLines()) do lines[#lines + 1] = l end

    lines[#lines + 1] = "== to do"

    -- T0c item 5: Q1 now also answers from a bonus-damage or a level change --
    -- either is as good a test as bonus healing when there is no +healing
    -- item. At least one comparable description must ALSO have changed: a
    -- level-up with every description unreadable proves nothing.
    local q1Trigger = false
    if q1Info.compared then
        if Readable(q1Info.oldBonus) and Readable(q1Info.newBonus) and q1Info.oldBonus ~= q1Info.newBonus then
            q1Trigger = true
        elseif BonusDamageReadable(q1Info.oldDamage) and BonusDamageReadable(q1Info.newDamage)
            and q1Info.oldDamage ~= q1Info.newDamage then
            q1Trigger = true
        elseif Readable(q1Info.oldLevel) and Readable(q1Info.newLevel) and q1Info.oldLevel ~= q1Info.newLevel then
            q1Trigger = true
        end
    end

    -- T0d: kept per build (buildKey computed a few lines above, for
    -- AgainstPreviousLines) -- an answered Q1 stays answered on a later run
    -- of the same build with nothing new to report.
    local prevQ1 = PreviousQ1(buildKey)
    local q1Record = nil
    if q1Info.compared and (q1Info.changedCount or 0) > 0 and q1Trigger then
        local q1Text = string.format(
            "%d of %d spell descriptions changed when bonus healing went %s -> %s, bonus damage %s -> %s, level %s -> %s",
            q1Info.changedCount, q1Info.totalCount, Fmt(q1Info.oldBonus), q1Info.newBonus,
            Fmt(q1Info.oldDamage), q1Info.newDamage, Fmt(q1Info.oldLevel), q1Info.newLevel)
        lines[#lines + 1] = "Q1 answered: " .. q1Text
        q1Record = { at = SafeDate(), text = q1Text }
    elseif prevQ1 then
        lines[#lines + 1] = "Q1 answered (kept from " .. prevQ1.at .. "): " .. prevQ1.text
        q1Record = prevQ1
    else
        lines[#lines + 1] = "Q1 to do: turn on show all ranks in the spellbook (the arrow at its top right), then change your bonus healing or bonus damage (put on or take off a +healing item, drink a spell power elixir, or take a buff that changes a number in the spells header) or gain a level with no gear change (as good a test when you have no +healing item), then type /st probe again in the same session"
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

    -- T0c item 6: answered only once the query table actually returns a
    -- table (rendered as a "{...}" string) -- below level 10 it reads "nil".
    if type(tierColumnShow) == "string" and tierColumnShow:sub(1, 1) == "{" then
        lines[#lines + 1] = "Q6 answered: see == talents"
    else
        lines[#lines + 1] = "Q6 to do: talents start at level 10, so C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) is answered at level 10 or above; type /st probe again then"
    end

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
            damage = damageStr,
            level = levelStr,
            desc = descSave,
            q1 = q1Record,
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

    doing = savedDoing
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
    -- T0c item 1: "ADDON_LOADED" for the whole handler, even the immediate
    -- no-op for another addon's load -- restored on every exit since the
    -- guard below used to be an early return.
    local savedDoing = doing
    doing = "ADDON_LOADED"
    if loadedName == ADDON_NAME then
        -- handled once: a later ADDON_LOADED for some other addon would still
        -- reach this handler otherwise, uselessly re-scanning SpellTunerDB.
        pcall(frame.UnregisterEvent, frame, "ADDON_LOADED")

        svTypeAtLoad = type(SpellTunerDB)
        -- review-probe R3: Core_Forever.lua's guard runs first and has already
        -- replaced a missing or broken SpellTunerDB with {} -- what the client
        -- handed back is the guard's own record of it, when there is one.
        if type(MD.sv) == "table" and type(MD.sv.atLoad) == "string" then
            svTypeAtLoad = MD.sv.atLoad
        end
        if type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table" then
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
    doing = savedDoing
end

local function OnRegenDisabled()
    phase = "combat"
    local after = MD.API.Has("C_Timer.After")
    if type(after) == "function" then
        -- runs later, outside every other pcall. review-probe R2: only if the
        -- fight is still on -- a fight over within 2 s would otherwise answer
        -- Q2/Q5 from out-of-combat readings and replace a good snapshot.
        pcall(after, 2, function()
            if phase == "combat" then
                pcall(TakeCombatSnapshot)
            else
                combatSnapshotsSkipped = combatSnapshotsSkipped + 1
            end
        end)
    else
        TakeCombatSnapshot()
    end
end

local function OnRegenEnabled()
    phase = "ooc"
end

local function OnCombatEvent(unit, action, descriptor, amount)
    BumpCombat(phase, unit, action, amount)
    BumpUnitCombatToken(phase, unit, action, amount)
end

local function OnSpellcastSent(unit, target)
    BumpSent(phase, target)
end

-- T7a item 7: only for the player's own cast, and only once IsSecret has
-- cleared the unit token -- the same "first argument == 'player'" rule
-- Client/Probe.lua's other unit-scoped counters do not need, since UNIT_COMBAT
-- and UNIT_SPELLCAST_SENT are read for party1 on purpose.
local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if IsSecret(unit) then return end
    if unit ~= "player" then return end
    BumpSucceeded(phase, spellID)
end

-- T0c items 1 and 3: the payload is only ever passed to Fmt/BumpBlocked,
-- never compared or indexed raw.
local function OnRestrictionStateChanged(...)
    BumpRestriction(phase, ...)
end

local function OnAddonActionForbidden(addonName, functionName)
    BumpBlocked("ADDON_ACTION_FORBIDDEN", addonName, functionName)
end

local function OnAddonActionBlocked(addonName, functionName)
    BumpBlocked("ADDON_ACTION_BLOCKED", addonName, functionName)
end

local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_REGEN_DISABLED = OnRegenDisabled,
    PLAYER_REGEN_ENABLED = OnRegenEnabled,
    UNIT_COMBAT = OnCombatEvent,
    UNIT_SPELLCAST_SENT = OnSpellcastSent,
    UNIT_SPELLCAST_SUCCEEDED = OnSpellcastSucceeded,
    ADDON_RESTRICTION_STATE_CHANGED = OnRestrictionStateChanged,
    ADDON_ACTION_FORBIDDEN = OnAddonActionForbidden,
    ADDON_ACTION_BLOCKED = OnAddonActionBlocked,
}

frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    local handler = HANDLERS[event]
    if handler then pcall(handler, ...) end
end)

-- T0c item 1: the FIRST two RegisterEvent calls this file makes, so the frame
-- is already listening for a blocked/forbidden action before anything else
-- (including its own later registrations) can trip one.
-- doing names each listener too: registering BLOCKED could itself trip
-- FORBIDDEN, which is already being listened for by then.
do
    local saved = doing
    doing = "register:ADDON_ACTION_FORBIDDEN"
    local ok, err = pcall(frame.RegisterEvent, frame, "ADDON_ACTION_FORBIDDEN")
    doing = saved
    actionForbiddenOutcome = ok and "ok" or ("throws <error: " .. Fmt(err) .. ">")
end
do
    local saved = doing
    doing = "register:ADDON_ACTION_BLOCKED"
    local ok, err = pcall(frame.RegisterEvent, frame, "ADDON_ACTION_BLOCKED")
    doing = saved
    actionBlockedOutcome = ok and "ok" or ("throws <error: " .. Fmt(err) .. ">")
end

do
    local saved = doing
    doing = "register:ADDON_LOADED"
    pcall(frame.RegisterEvent, frame, "ADDON_LOADED")
    doing = saved
end

for _, event in ipairs(EVENTS) do
    local saved = doing
    doing = "register:" .. event
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    -- "ok and nil or X" would always pick X (nil is falsy, so the "or" side
    -- always runs) -- the trap CLAUDE.md warns about, written out instead.
    local errText = nil
    if not ok then errText = "<error: " .. Fmt(err) .. ">" end
    eventOutcomes[event] = { ok = ok, err = errText }
    doing = saved
end

-- T1b: once Core.lua's kernel is on the TOC (it is, right before this file --
-- Client/Probe.lua stays load-order-independent so it still answers if the
-- kernel fails to load, T0's own Goal), the probe registers through it
-- instead of owning the slash command outright -- one dispatcher, one place
-- that prints "commands:".
if type(MD.AddCommand) == "function" then
    MD:AddCommand("probe", function(arg)
        if arg == "clog" then
            -- T0d: clog is gone -- never register it, and never run the probe
            -- here either, since a run saves a record and would move the
            -- "previous run" every later comparison reads.
            DEFAULT_CHAT_FRAME:AddMessage(
                "SpellTuner probe: clog is gone - the combat log registration is forbidden on Forever. Type /st probe.")
        else
            Run()
        end
    end, "/st probe", "the capability report for the planner")
else
    -- No kernel: today's standalone block, unchanged, so the probe still
    -- answers if Core.lua fails to load.
    SLASH_SPELLTUNER1 = "/spelltuner"
    SLASH_SPELLTUNER2 = "/st"
    SLASH_SPELLTUNER3 = "/md"
    SlashCmdList.SPELLTUNER = function(msg)
        local first, second = tostring(msg or ""):match("^%s*(%S*)%s*(%S*)")
        first = (first or ""):lower()
        second = (second or ""):lower()
        if first == "probe" and second == "clog" then
            -- T0d: clog is gone -- never register it, and never run the probe
            -- here either, since a run saves a record and would move the
            -- "previous run" every later comparison reads.
            DEFAULT_CHAT_FRAME:AddMessage(
                "SpellTuner probe: clog is gone - the combat log registration is forbidden on Forever. Type /st probe.")
        elseif first == "probe" then
            Run()
        else
            DEFAULT_CHAT_FRAME:AddMessage("SpellTuner probe: type /st probe")
        end
    end
end

-- Re-issue 1: exposed for tools/probecheck.lua only, so the suite can assert
-- the mirror list never grows past one moment's events without adding a
-- report section for a purely internal bookkeeping fact.
local function UnitCombatEventsCount()
    return #unitCombatEvents
end

MD.Probe = { Run = Run, UnitCombatEventsCount = UnitCombatEventsCount }

-- The file's last statement (T0c item 1): nothing is "in flight" once load
-- finishes.
doing = "idle"
