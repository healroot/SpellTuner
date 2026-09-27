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

-- The fourteen "== " headers, each paired with enough of what follows to tell
-- it apart from the one it is a prefix of ("== spells" / "== events").
local HEADERS_IN_ORDER = {
    "== client", "== functions (", "== events\n", "== secrets now", "== spells (",
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

--------------------------------------------------------------------------------
-- Step 1: the TBC line
--------------------------------------------------------------------------------
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

_G.SpellTunerDB, _G.ManaDemonDB = nil, nil
_G.SPELLTUNER_TOC = nil
_G.SLASH_SPELLTUNER1, _G.SLASH_SPELLTUNER2, _G.SLASH_SPELLTUNER3 = nil, nil, nil

local baseline = {}
for k in pairs(_G) do baseline[k] = true end

S.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })

local chat2 = ChatCapture()

local MD2 = {}
S.Load({ "Client/TOC_Forever.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD2)

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

Do(S.Fire, "UNIT_COMBAT", "party1", "HEAL", "", 120, 1)
Do(S.Fire, "UNIT_COMBAT", "party1", "BLOCK|X", "", 5, 1)
S.inCombat = true
Do(S.Fire, "PLAYER_REGEN_DISABLED")
for _, fn in ipairs(S.timers or {}) do Do(fn) end
Do(S.Fire, "UNIT_COMBAT", "party1", "WOUND", "", S.Secret(), 1)
Do(S.Fire, "UNIT_SPELLCAST_SENT", "player", "Tankname", "Cast-1", 774)

-- run 2: in combat
Do(SlashCmdList.SPELLTUNER, "probe")
local report2 = SpellTunerDB.probe.reports["70009"].text

S.inCombat = false
Do(S.Fire, "PLAYER_REGEN_ENABLED")
S.bonusHealing = 50

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
S3.Load({ "Client/TOC_Forever.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD3)
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
local step4LoadOk = pcall(S4.Load, { "Client/TOC_Forever.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD4)
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
-- Assertions
--------------------------------------------------------------------------------
check("the probe never raises", (function()
    if not (step3AddonLoadedOk and step3RunOk) then return false end
    if not (step4LoadOk and step4AddonLoadedOk and step4RegenDisabledOk and step4SentOk and ok5) then
        return false
    end
    for _, r in ipairs(raises) do if not r then return false end end
    return true
end)())

check("a missing function is reported absent, not raised",
    Has(report1, "absent CombatLogGetCurrentEventInfo") and Has(report1, "absent GetSpellInfo")
    and Has(report1, "C_ClassTalents.GetActiveConfigID() = <absent>"))

check("registering a bad event is caught",
    Has(report1, "throws COMBAT_LOG_EVENT_UNFILTERED") and Has(report1, "ok UNIT_COMBAT"))

do
    local _, secretHealthCount = report2:gsub("UnitHealth%(party1%) = <secret>", "")
    check("a secret value is reported secret, not summed",
        secretHealthCount >= 2 and Has(report2, "UNIT_COMBAT combat party WOUND n=1 readable=0 secret=1 nil=0"))
end

check("a client error is reported as a string",
    Has(report2, "C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <error:"))

check("the report is ASCII with no bare pipe",
    AsciiSafe(report1) and AsciiSafe(report2) and AsciiSafe(report3) and AsciiSafe(report4)
    and AsciiSafe(report5))

do
    local lastEditBox = nil
    for _, f in ipairs(S.allFrames) do if f.kind == "EditBox" then lastEditBox = f end end
    check("the report reaches the copy box", lastEditBox ~= nil and lastEditBox.text == report3)
end

check("the report sections are in order", HeadersInOrder(report1))
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
    Has(report1, "SPELLTUNER_TOC = Forever") and Has(report3, "SPELLTUNER_TOC = Forever"))

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
    and Has(report3, "Q9 answered: SPELLTUNER_TOC = Forever"))

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

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
