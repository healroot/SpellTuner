-- tools/run.sh tools/probecheck.lua
--
-- T0's own harness: loads the TBC line the way tools/migrate.lua does (step
-- 1), then the Forever line fresh under the "forever" stub profile through a
-- scripted fight (step 2), then a fresh Forever load with SavedVariables
-- already sitting in _G, the way a real client hands them back (step 3).
local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- Plain substring test (never a pattern -- report text can contain "%").
local function Has(s, sub) return s ~= nil and s:find(sub, 1, true) ~= nil end

-- Wraps the CURRENT DEFAULT_CHAT_FRAME.AddMessage so every message a step
-- prints is also kept in a table the checks can search, without changing
-- what actually prints. Call fresh after each dofile(wowstub.lua), which
-- installs a new DEFAULT_CHAT_FRAME.
local function ChatCapture()
    local captured = {}
    local orig = DEFAULT_CHAT_FRAME.AddMessage
    DEFAULT_CHAT_FRAME.AddMessage = function(self, m)
        captured[#captured + 1] = tostring(m)
        return orig(self, m)
    end
    return captured
end

-- Every byte is 10 or printable ASCII, and no bare "|" survives removing "||".
local function AsciiSafe(s)
    for i = 1, #s do
        local b = s:byte(i)
        if not (b == 10 or (b >= 32 and b <= 126)) then return false end
    end
    local stripped = s:gsub("||", "")
    return not stripped:find("|", 1, true)
end

-- The fifteen "== " headers, each paired with enough of what follows to tell
-- it apart from the one it is a prefix of ("== spells" / "== events").
local HEADERS_IN_ORDER = {
    "== client", "== functions (", "== events\n", "== blocked actions\n", "== secrets now", "== spells (",
    "== spells against the previous run", "== talents", "== readings now",
    "== combat snapshot", "== events seen this session", "== damage meter",
    "== saved variables", "== toc", "== to do",
}
-- The text strictly between two markers, or nil if either is missing.
local function Between(s, startMarker, endMarker)
    local i = s:find(startMarker, 1, true)
    if not i then return nil end
    local j = s:find(endMarker, i + #startMarker, true)
    if not j then return nil end
    return s:sub(i + #startMarker, j - 1)
end

local function HeadersInOrder(report)
    local pos = 0
    for _, marker in ipairs(HEADERS_IN_ORDER) do
        local s = report:find(marker, pos + 1, true)
        if not s then return false end
        pos = s
    end
    return true
end

-- T0c: how many times ANY frame's RegisterEvent attempted the combat log
-- event, across the current stub's frame registry -- proves clog moved the
-- registration off the load path (it never runs at load) and onto /st probe
-- clog (it runs exactly once per call).
local function ClogAttempts(stub)
    local n = 0
    for _, f in ipairs(stub.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "COMBAT_LOG_EVENT_UNFILTERED" then n = n + 1 end
        end
    end
    return n
end

-- The probe's own frame: the one whose very first registration attempts are
-- the two blocked-action listeners (T0c item 1's "first two RegisterEvent
-- calls"), found here by the ADDON_LOADED attempt every profile of the probe
-- makes, so a test can read its "attempts" list directly.
local function ProbeFrame(stub)
    for _, f in ipairs(stub.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "ADDON_LOADED" then return f end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Step 1: the TBC line
--------------------------------------------------------------------------------
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD1 = dofile(here .. "/harness.lua"); arg[0] = a0

local tbcVersion = nil
do
    local f = io.open(ROOT .. "/SpellTuner_TBC.toc", "r")
    if f then
        for line in f:lines() do
            local v = line:match("^## Version:%s*(.-)%s*$")
            if v then tbcVersion = v; break end
        end
        f:close()
    end
end

check("the TBC line reads its version from SpellTuner_TBC.toc",
    tbcVersion ~= nil and MD1.version == tbcVersion and MD1.version ~= "0.0.0")
check("Client/API.lua loads under the TBC line",
    type(MD1.API) == "table" and type(MD1.API.Has) == "function"
    and MD1.API.Has("UnitHealth") and _G.SPELLTUNER_TOC == "TBC")

--------------------------------------------------------------------------------
-- Step 2: Forever, fresh -- a scripted fight through the real event frame
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = ROOT
S.UseProfile("forever")
-- T0d: a bad event that is not the combat log -- the combat log is never
-- registered by anything in this file any more, so "registering a bad event
-- is caught" needs its own stand-in event to prove the load path still
-- catches one.
S.raiseOnRegister = { UNIT_FLAGS = true }

_G.SpellTunerDB, _G.ManaDemonDB = nil, nil
_G.SPELLTUNER_TOC = nil
_G.SLASH_SPELLTUNER1, _G.SLASH_SPELLTUNER2, _G.SLASH_SPELLTUNER3 = nil, nil, nil

local baseline = {}
for k in pairs(_G) do baseline[k] = true end

S.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })

local chat2 = ChatCapture()

local MD2 = {}
S.Load({ "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD2)

-- Every scripted action goes through here, under its own pcall, and the
-- outcome is collected for "the probe never raises". No call site needs the
-- return value, so nothing is packed or returned.
local raises = {}
local function Do(fn, ...)
    raises[#raises + 1] = pcall(fn, ...)
end

Do(S.Fire, "ADDON_LOADED", "SpellTuner")
Do(S.Fire, "PLAYER_LOGIN")

check("MD.API.client is forever on interface 16001", MD2.API.client == "forever")
check("MD.API.Has walks dotted names and says false for a missing one",
    MD2.API.Has("C_Spell.GetSpellDescription") and MD2.API.Has("C_Spell.NoSuchThing") == false
    and MD2.API.Has("NoSuchNamespace.X") == false)

-- run 1: out of combat, bonus healing 0 -- called directly so its own return
-- value can be checked against the saved text (Do() discards it).
local ok1, r1 = pcall(MD2.Probe.Run)
raises[#raises + 1] = ok1
local report1 = r1
local report1Char = SpellTunerDB.probe.reports["70009"].char
-- checked here, before step 3 replaces SpellTunerDB with its own fixture
check("the report is keyed by build",
    ok1 == true and type(report1) == "string"
    and type(SpellTunerDB.probe.reports["70009"]) == "table"
    and type(SpellTunerDB.probe.reports["70009"].char) == "string"
    and SpellTunerDB.probe.reports["70009"].text == report1
    and Has(table.concat(chat2, "\n"), "lines, saved."))

-- T0c: a restriction-state change right after run 1, out of combat -- counted
-- twice under the same payload.
Do(S.Fire, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
Do(S.Fire, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1)

Do(S.Fire, "UNIT_COMBAT", "party1", "HEAL", "", 120, 1)
Do(S.Fire, "UNIT_COMBAT", "party1", "BLOCK|X", "", 5, 1)
S.inCombat = true
Do(S.Fire, "PLAYER_REGEN_DISABLED")
for _, fn in ipairs(S.timers or {}) do Do(fn) end
-- T0c: a different restriction payload and a blocked action, both in combat.
Do(S.Fire, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
Do(S.Fire, "ADDON_ACTION_BLOCKED", "SpellTuner", "Frame:Show()")
Do(S.Fire, "UNIT_COMBAT", "party1", "WOUND", "", S.Secret(), 1)
Do(S.Fire, "UNIT_SPELLCAST_SENT", "player", "Tankname", "Cast-1", 774)

-- run 2: in combat
Do(SlashCmdList.SPELLTUNER, "probe")
local report2 = SpellTunerDB.probe.reports["70009"].text

S.inCombat = false
Do(S.Fire, "PLAYER_REGEN_ENABLED")
S.bonusHealing = 50

-- T0c: two forbidden actions naming us (counted together) and one naming
-- another addon (ignored entirely), all out of combat, idle.
Do(S.Fire, "ADDON_ACTION_FORBIDDEN", "SpellTuner", "UNKNOWN()")
Do(S.Fire, "ADDON_ACTION_FORBIDDEN", "SpellTuner", "UNKNOWN()")
Do(S.Fire, "ADDON_ACTION_FORBIDDEN", "EllesmereUI", "CastSpellByName()")

-- T0c: the combat log leaves the load path -- never attempted until /st probe
-- clog asks for it, and attempted exactly once when it does.
local clogBefore2 = ClogAttempts(S)
Do(SlashCmdList.SPELLTUNER, "probe clog")
local clogAfter2 = ClogAttempts(S)

-- run 3: out of combat, bonus healing 50
Do(SlashCmdList.SPELLTUNER, "probe")
local report3 = SpellTunerDB.probe.reports["70009"].text

--------------------------------------------------------------------------------
-- Step 3: Forever, SavedVariables came back
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S3 = _G.STUB
S3.root = ROOT
S3.UseProfile("forever")
S3.AddTraits()

_G.SpellTunerDB = {
    probe = {
        stamp = "2026-09-26 10:00:00",
        reports = {
            ["69893"] = { char = "Healroot-Test", at = "2026-09-26 10:05:00", text = "old" },
            ["70009"] = { char = "Healroot-Test", at = "2026-09-26 10:06:00", text = "old",
                bonus = "<error: stub>",
                desc = { ["774"] = "Heals the target for 32 over 12 sec.", ["5185"] = "<secret>" } },
        },
    },
}

local chat3 = ChatCapture()

local MD3 = {}
S3.Load({ "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD3)
local step3AddonLoadedOk = pcall(S3.Fire, "ADDON_LOADED", "SpellTuner")
local step3RunOk = pcall(SlashCmdList.SPELLTUNER, "probe")
local report4 = SpellTunerDB.probe.reports["70009"].text

--------------------------------------------------------------------------------
-- Step 4: Forever, in combat with no snapshot taken -- exercises the Q4/Q8
-- fixes and MD.API.Has never handing back a secret.
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S4 = _G.STUB
S4.root = ROOT
S4.UseProfile("forever")
S4.meterSecretInCombat = false

_G.T0B_SECRET = S4.Secret()
_G.T0B_SECRET_TABLE = S4.SecretTable()

local chat4 = ChatCapture()

local MD4 = {}
local step4LoadOk = pcall(S4.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD4)
local step4AddonLoadedOk = pcall(S4.Fire, "ADDON_LOADED", "SpellTuner")

local step4RegenDisabledOk = pcall(S4.Fire, "PLAYER_REGEN_DISABLED")
-- S4.timers is deliberately never run -- no combat snapshot is taken.

S4.inCombat = true
local step4SentOk = pcall(S4.Fire, "UNIT_SPELLCAST_SENT", "player", "Tankname", "Cast-2", 774)

_G.SpellTunerDB = nil
local ok5, report5 = pcall(MD4.Probe.Run)

-- Computed here, while the globals are still in place; cleared right after so
-- "the probe adds no global but its own" below sees a clean _G (these two are
-- test fixtures, not something the probe itself creates).
local hasSecretScalar = MD4.API.Has("T0B_SECRET") == true
local hasSecretTable = MD4.API.Has("T0B_SECRET_TABLE") == true
_G.T0B_SECRET, _G.T0B_SECRET_TABLE = nil, nil

--------------------------------------------------------------------------------
-- Step 5: Healroot levels up and tries the combat log -- a forbidden
-- UNIT_FLAGS registration at load and a forbidden clog registration later,
-- both naming the registration that caused them; then a level-only Q1/Q6
-- change (no bonus healing, no bonus damage, no gear).
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S5 = _G.STUB
S5.root = ROOT
S5.UseProfile("forever")
S5.level = 9
S5.forbidOnRegister = { UNIT_FLAGS = "Frame:RegisterEvent()", COMBAT_LOG_EVENT_UNFILTERED = "Frame:RegisterEvent()" }

_G.SpellTunerDB = nil
local chat5 = ChatCapture()

local MD5 = {}
local step5LoadOk = pcall(S5.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD5)
local step5AddonLoadedOk = pcall(S5.Fire, "ADDON_LOADED", "SpellTuner")

local clogBefore5 = ClogAttempts(S5)
local okA, reportA = pcall(MD5.Probe.Run)
-- Not called through Do(): its own pcall result is one of the named "the
-- probe never raises" checks for this step (Acceptance).
local step5ClogOk = pcall(SlashCmdList.SPELLTUNER, "probe clog")
local clogAfter5 = ClogAttempts(S5)
S5.level = 10
S5.descShift = 3
local okB, reportB = pcall(MD5.Probe.Run)

-- T0d: one more run of the same build with nothing changed since reportB --
-- the ninth report's bug flipped an answered Q1 back to "to do" here.
local okB2, reportB2 = pcall(MD5.Probe.Run)

-- Do NOT call S5.AddTraits() here -- "the probe adds no global but its own"
-- runs after this step and only tolerates the probe's own new globals.
local probeFrame5 = ProbeFrame(S5)
-- Read here, before step 6 replaces SpellTunerDB with its own fixture.
local step5Q1Record = SpellTunerDB.probe.reports["70009"].q1

--------------------------------------------------------------------------------
-- Step 6: a spell power elixir -- fourteen extra spellbook rows so a Q1
-- answer driven by bonus damage alone (no bonus healing, no level change) has
-- plenty of comparable descriptions, and the was/now dump has more than 12
-- changes to cap.
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S6 = _G.STUB
S6.root = ROOT
S6.UseProfile("forever")
for i = 1, 13 do
    S6.AddSpell(900000 + i, "Stub Bolt", "Rank " .. i, function()
        return "Causes " .. (10 + i + (S6.bonusDamage[4] or 0)) .. " Nature damage to the target."
    end)
end

_G.SpellTunerDB = nil

local MD6 = {}
local step6LoadOk = pcall(S6.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD6)
local step6AddonLoadedOk = pcall(S6.Fire, "ADDON_LOADED", "SpellTuner")

local okC, reportC = pcall(MD6.Probe.Run)
S6.bonusDamage[4] = 5
local okD, reportD = pcall(MD6.Probe.Run)
local recD = SpellTunerDB.probe.reports["70009"]

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------
check("the probe never raises", (function()
    if not (step3AddonLoadedOk and step3RunOk) then return false end
    if not (step4LoadOk and step4AddonLoadedOk and step4RegenDisabledOk and step4SentOk and ok5) then
        return false
    end
    if not (step5LoadOk and step5AddonLoadedOk and okA and step5ClogOk and okB and okB2) then return false end
    if not (step6LoadOk and step6AddonLoadedOk and okC and okD) then return false end
    for _, r in ipairs(raises) do if not r then return false end end
    return true
end)())

check("a missing function is reported absent, not raised",
    Has(report1, "absent CombatLogGetCurrentEventInfo") and Has(report1, "absent GetSpellInfo")
    and Has(report1, "C_ClassTalents.GetActiveConfigID() = <absent>"))

check("registering a bad event is caught",
    Has(report1, "COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)")
    and Has(report1, "ok UNIT_COMBAT")
    and Has(report1, "throws UNIT_FLAGS <error:")
    and Has(report3, "throws UNIT_FLAGS <error:")
    and Has(report3, "COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)")
    and not Has(report3, "by /st probe clog"))

do
    local _, secretHealthCount = report2:gsub("UnitHealth%(party1%) = <secret>", "")
    check("a secret value is reported secret, not summed",
        secretHealthCount >= 2 and Has(report2, "UNIT_COMBAT combat party WOUND n=1 readable=0 secret=1 nil=0"))
end

check("a client error is reported as a string",
    Has(report2, "C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <error:"))

check("the report is ASCII with no bare pipe",
    AsciiSafe(report1) and AsciiSafe(report2) and AsciiSafe(report3) and AsciiSafe(report4)
    and AsciiSafe(report5) and AsciiSafe(reportA) and AsciiSafe(reportB) and AsciiSafe(reportC)
    and AsciiSafe(reportD))

do
    local lastEditBox = nil
    for _, f in ipairs(S.allFrames) do if f.kind == "EditBox" then lastEditBox = f end end
    check("the report reaches the copy box", lastEditBox ~= nil and lastEditBox.text == report3)
end

check("the report sections are in order", HeadersInOrder(report1) and HeadersInOrder(reportB))
check("the header names build 70009 and interface 16001",
    Has(report1, "70009") and Has(report1, "16001"))

check("healing spells are dumped with id, name, rank and the whole description",
    Has(report1, "spell 774\n  name: Rejuvenation\n  rank: Rank 1\n  desc: Heals the target for 32 over 12 sec.")
    -- the report holds the ESCAPED text (literal backslash + digits), not the
    -- raw UTF-8 bytes -- "\\226" here is a literal backslash then "226".
    and Has(report1, "Heals a friendly target for 40 to 55.||nIt is \\226\\128\\156quoted\\226\\128\\157."))

check("a spell that does not heal is not dumped", not Has(report1, "spell 5176"))

check("a change in bonus healing is reported against the previous run",
    Has(report3, "bonus healing 0 -> 50") and Has(report3, "changed 774 Rejuvenation")
    and not Has(report3, "changed 5185"))

do
    local seg = Between(report2, "\n== combat snapshot\n", "\n== events seen this session\n")
    check("the combat snapshot is taken in combat",
        seg ~= nil and Has(seg, "taken ") and Has(seg, "in combat: true"))
end

check("UNIT_COMBAT and UNIT_SPELLCAST_SENT are counted by phase",
    Has(report3, "UNIT_COMBAT ooc party HEAL n=1 readable=1 secret=0 nil=0 sample=120")
    and Has(report3, "UNIT_SPELLCAST_SENT combat n=1 readable=1 secret=0 empty=0 sample=Tankname"))

check("the damage meter in combat is reported secret, not walked",
    Has(report2, "session Current HealingDone = <secret>"))

check("the damage meter after combat lists sources and spells",
    Has(report3, "session Current HealingDone = sources=1") and Has(report3, "combatSpells=1")
    and Has(report3, "spellID=774"))

check("SavedVariables that did not come back are reported as such",
    Has(report1, "SpellTunerDB at load: nil") and Has(report1, "previous session stamp: none")
    and Has(report1, "Q7 to do"))

check("SavedVariables that came back are reported with their stamp",
    Has(report4, "previous session stamp: 2026-09-26 10:00:00")
    and Has(report4, "69893 (Healroot-Test, 2026-09-26 10:05:00)") and Has(report4, "Q7 answered"))

check("the report prints the TOC that loaded",
    Has(report1, "SPELLTUNER_TOC = Mainline") and Has(report3, "SPELLTUNER_TOC = Mainline"))

do
    local extra = {}
    for k in pairs(_G) do if not baseline[k] then extra[#extra + 1] = k end end
    local allowed = {
        SPELLTUNER_TOC = true, SpellTunerDB = true, SLASH_SPELLTUNER1 = true,
        SLASH_SPELLTUNER2 = true, SLASH_SPELLTUNER3 = true, SpellTunerProbeFrame = true,
    }
    local onlyAllowed = true
    for _, k in ipairs(extra) do if not allowed[k] then onlyAllowed = false end end
    check("the probe adds no global but its own", onlyAllowed, table.concat(extra, ", "))
end

check("/st and /md both reach the probe",
    SLASH_SPELLTUNER2 == "/st" and SLASH_SPELLTUNER3 == "/md" and type(SlashCmdList.SPELLTUNER) == "function")

check("the to-do list names what is left",
    Has(report1, "Q1 to do") and Has(report1, "Q2 to do")
    and Has(report3, "Q1 answered") and Has(report3, "Q2 answered")
    and Has(report3, "Q9 answered: SPELLTUNER_TOC = Mainline"))

--------------------------------------------------------------------------------
-- T0b: the new assertions
--------------------------------------------------------------------------------
check("an unreadable description is not counted as changed",
    Has(report3, "changed 774 Rejuvenation")
    and Has(report3, "1 not comparable (unreadable on one run)")
    and not Has(report3, "changed 5185"))

check("the Q1 count covers comparable descriptions only",
    Has(report3, "Q1 answered: 1 of 3 spell descriptions changed when bonus healing went 0 -> 50"))

check("Q1 is answered only when both bonus readings are readable",
    Has(report4, "Q1 to do") and Has(report4, "1 not comparable (unreadable on one run)"))

check("event and secret names are escaped",
    Has(report3, "UNIT_COMBAT ooc party BLOCK||X n=1") and Has(report3, "ShouldStub||Piped = false"))

check("MD.API.Has never hands back a secret", hasSecretScalar and hasSecretTable)

check("a secret table is reported secret",
    Has(report2, "session Current HealingDone = <secret>"))

do
    local lastEditBox = nil
    for _, f in ipairs(S.allFrames) do if f.kind == "EditBox" then lastEditBox = f end end
    check("the copy box has no letter cap", lastEditBox ~= nil and lastEditBox.maxLetters == 0)
end

check("an in-combat damage meter read does not answer Q4",
    Has(report5, "session Current HealingDone = sources=1") and Has(report5, "Q4 to do"))

check("Q8 needs the combat snapshot",
    Has(report5, "none this session") and Has(report5, "Q8 to do"))

check("a spellbook row that raises is counted as an error",
    Has(report1, "slots 1-500: 4 with a spell, 3 healing, 0 empty description, 0 secret, 1 error"))

check("the chat line says saved only when it saved",
    Has(table.concat(chat4, "\n"), "not saved (no SavedVariables table)"))

check("the character line shows the first return only",
    Has(report1, "character: Penek Anniversary DRUID level 64")
    and report1Char == "Penek-Anniversary")

check("the dump counts ranks per spell name",
    Has(report1, "ranks per name: Healing Touch 1; Rejuvenation 2"))

check("the talent APIs that exist are called and shown",
    Has(report4, "C_ClassTalents.GetActiveConfigID() = 7")
    and Has(report4, "C_Traits.GetConfigInfo(<first return above>) = {ID=7, name=Stub loadout, type=1}"))

--------------------------------------------------------------------------------
-- T0c: the new assertions
--------------------------------------------------------------------------------

do
    local seg = Between(report1, "\n== blocked actions\n", "\n== secrets now\n")
    check("blocked and forbidden actions naming us are recorded",
        seg == "listening: ADDON_ACTION_FORBIDDEN ok, ADDON_ACTION_BLOCKED ok\nnone"
        and Has(report3, "ADDON_ACTION_BLOCKED phase=combat during=idle addon=SpellTuner function=Frame:Show() n=1")
        and Has(report3, "ADDON_ACTION_FORBIDDEN phase=ooc during=idle addon=SpellTuner function=UNKNOWN() n=2"))
end

do
    local seg = Between(report3, "\n== blocked actions\n", "\n== secrets now\n")
    check("a blocked action naming another addon is ignored",
        seg ~= nil and not Has(seg, "EllesmereUI") and not Has(seg, "CastSpellByName"))
end

check("COMBAT_LOG_EVENT_UNFILTERED is never registered, not even by clog",
    clogBefore2 == 0 and clogAfter2 == 0 and clogBefore5 == 0 and clogAfter5 == 0
    and Has(table.concat(chat2, "\n"), "SpellTuner probe: clog is gone - the combat log registration is forbidden on Forever. Type /st probe.")
    and not Has(table.concat(chat2, "\n"), "registering COMBAT_LOG_EVENT_UNFILTERED"))

check("a blocked action at load names the registration that caused it",
    Has(reportB, "ADDON_ACTION_FORBIDDEN phase=ooc during=register:UNIT_FLAGS addon=SpellTuner function=Frame:RegisterEvent() n=1")
    and not Has(reportB, "during=clog")
    and probeFrame5 ~= nil and probeFrame5.attempts[1] == "ADDON_ACTION_FORBIDDEN"
    and probeFrame5.attempts[2] == "ADDON_ACTION_BLOCKED"
    and not Has(table.concat(chat5, "\n"), "registered without a Lua error"))

-- T0d: Q1's answer, once given, stays given on a later run of the same build
-- with nothing changed -- the ninth report's bug.
do
    local reportBQ1Line = (function()
        local i = reportB:find("Q1 answered: ", 1, true)
        if not i then return nil end
        local j = reportB:find("\n", i, true) or (#reportB + 1)
        return reportB:sub(i, j - 1)
    end)()
    local q1Text = reportBQ1Line and reportBQ1Line:sub(#"Q1 answered: " + 1) or nil
    check("Q1 stays answered on a later run of the same build",
        reportBQ1Line ~= nil and q1Text ~= nil
        and Has(reportB2, "Q1 answered (kept from ")
        and Has(reportB2, "): " .. q1Text)
        and not Has(reportB2, "Q1 to do")
        and type(step5Q1Record) == "table" and step5Q1Record.text == q1Text)
end

-- The eighteen secret-question labels (item 3), left-hand side only -- their
-- values differ run to run, the labels and their order do not.
local SECRET_QUESTION_LABELS = {
    "C_Secrets.HasSecretRestrictions() = ", "C_Secrets.ShouldUnitHealthMaxBeSecret(player) = ",
    "C_Secrets.ShouldUnitPowerBeSecret(player) = ", "C_Secrets.ShouldUnitPowerMaxBeSecret(player) = ",
    "C_Secrets.GetPowerTypeSecrecy(0) = ", "C_Secrets.CanCompareUnitTokens(player, player) = ",
    "UnitHealthMax(player) = ", "UnitPowerMax(player, 0) = ", "UnitHealth(player, true) = ",
    "UnitHealthPercent(player) = ", "UnitHealthPercent(player, true) = ", "UnitHealthMissing(player) = ",
    "UnitPowerPercent(player, 0) = ", "UnitGetIncomingHeals(player) = ", "UnitIsDeadOrGhost(player) = ",
    "UnitHealth(party1, true) = ", "UnitHealthPercent(party1) = ", "UnitHealthPercent(party1, true) = ",
}
local function LabelsInOrder(seg)
    if not seg then return false end
    local pos = 0
    for _, label in ipairs(SECRET_QUESTION_LABELS) do
        local s = seg:find(label, pos + 1, true)
        if not s then return false end
        pos = s
    end
    return true
end

do
    local seg1 = Between(report1, "\n== readings now\n", "\n== combat snapshot\n")
    local seg2 = Between(report2, "\n== combat snapshot\n", "\n== events seen this session\n")
    -- T5: build 70009 answered HasSecretRestrictions true and party1's health
    -- percent secret whether or not combat was running (Facts) -- the sixth
    -- report's ooc reading is not "false"/"100" any more.
    check("the secret readings are taken out of combat and in the snapshot",
        LabelsInOrder(seg1) and LabelsInOrder(seg2)
        and Has(seg1, "C_Secrets.HasSecretRestrictions() = true") and Has(seg1, "UnitHealthPercent(party1) = <secret>")
        and Has(seg2, "C_Secrets.HasSecretRestrictions() = true") and Has(seg2, "UnitHealthPercent(party1) = <secret>"))
end

check("the restriction state event is counted with its payload",
    Has(report3, "ADDON_RESTRICTION_STATE_CHANGED ooc payload=5, 1 n=2")
    and Has(report3, "ADDON_RESTRICTION_STATE_CHANGED combat payload=5, 0 n=1"))

check("the damage meter expands combatSpellDetails one level",
    Has(report3, "spell 1 = {combatSpellDetails={specIconID=0, unitClassFilename=WARRIOR, unitName=Tankname}, spellID=774, totalAmount=1000}")
    and Has(report3, "local source = {amountPerSecond=41, isLocalPlayer=true, sourceGUID=Player-1, totalAmount=1234}"))

do
    local seg = Between(report3, "session Overall HealingDone", "\n== saved variables\n")
    check("the damage meter prints at most 5 spells a session",
        seg ~= nil and Has(seg, "combatSpells=6") and Has(seg, "  spell 5 = ") and not Has(seg, "  spell 6 = "))
end

check("Q1 is answered by a level change",
    Has(reportA, "Q1 to do")
    and Has(reportB, ", level 9 -> 10")
    and Has(reportB, "Q1 answered: 1 of 4 spell descriptions changed when bonus healing went 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0, level 9 -> 10"))

check("Q6 waits for level 10",
    Has(reportA, "Q6 to do: talents start at level 10")
    and Has(reportB, "Q6 answered: see == talents"))

--------------------------------------------------------------------------------
-- The release: proves the build ships exactly the three surviving TOCs.
--------------------------------------------------------------------------------
local RELEASE_OUT = ROOT .. "/tools/.lua/probecheck-release"
local releaseOutput = ""
do
    local p = io.popen("bash \"" .. ROOT .. "/release.sh\" --out \"" .. RELEASE_OUT .. "\" 2>&1")
    if p then releaseOutput = p:read("*a") or ""; p:close() end
end

local releaseTocs = {}
do
    local p = io.popen("ls \"" .. RELEASE_OUT .. "/SpellTuner\"/*.toc 2>/dev/null")
    if p then
        for line in p:lines() do releaseTocs[#releaseTocs + 1] = line:match("([^/]+)$") end
        p:close()
    end
    table.sort(releaseTocs)
end

local function FileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

check("the build ships three TOCs",
    Has(releaseOutput, "Built ")
    and #releaseTocs == 3
    and releaseTocs[1] == "SpellTuner.toc" and releaseTocs[2] == "SpellTuner_Mainline.toc"
    and releaseTocs[3] == "SpellTuner_TBC.toc"
    and FileExists(RELEASE_OUT .. "/SpellTuner/Client/TOC_Mainline.lua")
    and FileExists(RELEASE_OUT .. "/SpellTuner/Client/TOC_Plain.lua")
    and not FileExists(RELEASE_OUT .. "/SpellTuner/Client/TOC_Forever.lua")
    and not FileExists(RELEASE_OUT .. "/SpellTuner/Client/TOC_Vanilla.lua")
    and not FileExists(ROOT .. "/SpellTuner_Forever.toc")
    and not FileExists(ROOT .. "/SpellTuner_Vanilla.toc"))

local function ReadLines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
    f:close()
    return lines
end

do
    local plainLines = ReadLines(ROOT .. "/SpellTuner.toc")
    local mainlineLines = ReadLines(ROOT .. "/SpellTuner_Mainline.toc")
    local hasVersion = false
    for _, l in ipairs(plainLines) do if l == "## Version: 1.0.0-alpha.1" then hasVersion = true end end
    local hasVersion2 = false
    for _, l in ipairs(mainlineLines) do if l == "## Version: 1.0.0-alpha.1" then hasVersion2 = true end end
    local sameCount = #plainLines == #mainlineLines
    local diffs, diffOk = 0, true
    if sameCount then
        for i = 1, #plainLines do
            if plainLines[i] ~= mainlineLines[i] then
                diffs = diffs + 1
                if not (plainLines[i] == "Client\\TOC_Plain.lua" and mainlineLines[i] == "Client\\TOC_Mainline.lua") then
                    diffOk = false
                end
            end
        end
    end
    local PREFIX = "SpellTuner probe 1.0.0-alpha.1 -- "
    check("the Forever TOCs are 1.0.0-alpha.1 and differ only in their marker",
        hasVersion and hasVersion2 and sameCount and diffs == 1 and diffOk
        and report1:sub(1, #PREFIX) == PREFIX)
end

check("a changed description prints what it was and what it is now",
    Has(report3, "changed 774 Rejuvenation\n  was: Heals the target for 32 over 12 sec.\n  now: Heals the target for 82 over 12 sec."))

local function CountLinesStarting(s, prefix)
    local n = 0
    for line in (s .. "\n"):gmatch("(.-)\n") do
        if line:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end

do
    local seg = Between(reportD, "\n== spells against the previous run\n", "\n== talents\n")
    check("was and now are shown for the first 12 changed spells, the rest counted",
        seg ~= nil
        and CountLinesStarting(seg, "changed ") == 14
        and CountLinesStarting(seg, "  was: ") == 12
        and CountLinesStarting(seg, "  now: ") == 12
        and Has(seg, "was/now shown for the first 12 of 14 changed spells")
        and Has(seg, "changed 5176 Wrath\n  was: Causes 13 to 16 Nature damage to the target.\n  now: Causes 18 to 21 Nature damage to the target."))
end

check("the spells header shows bonus damage per school",
    Has(reportD, "== spells (bonus healing 0, bonus damage Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0)")
    and Has(reportD, "bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0")
    and type(recD) == "table" and recD.damage == "Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0"
    and recD.level == "64")

check("Q1 is answered by a change in bonus damage",
    Has(reportC, "Q1 to do")
    and Has(reportD, "Q1 answered: 14 of 17 spell descriptions changed when bonus healing went 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0, level 64 -> 64"))

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
