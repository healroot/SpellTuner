-- tools/run.sh [--flavour forever|tbc] tools/probecheck.lua
--
-- T0's own harness: loads the TBC line the way tools/migrate.lua does (step
-- 1), then the Forever line fresh under the "forever" stub profile through a
-- scripted fight (step 2), then a fresh Forever load with SavedVariables
-- already sitting in _G, the way a real client hands them back (step 3).
--
-- T87 (docs/SPEC-next.md decision 22): the probe is on both clients, so this
-- runs under both flavours. Under forever: step 1 and every Forever step, then
-- step 15 (the five sections the next round asks for). Under tbc: step 1, then
-- the probe on the TBC line's own file list (the T87 block right after step 1)
-- -- and nothing of the Forever steps, which end the run there.
local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

HARNESS_FLAVOUR = { "forever", "tbc" }
-- the harness's own rule: ST_FLAVOUR picks among the declared ones, the first
-- when none is named
local FLAVOUR = os.getenv("ST_FLAVOUR")
if FLAVOUR == nil or FLAVOUR == "" then FLAVOUR = "forever" end
if FLAVOUR ~= "forever" and FLAVOUR ~= "tbc" then
    print("skip: probecheck.lua runs under forever, tbc only")
    os.exit(3)
end
-- T87: the art and clock fakes (textures, atlases, GetFileIDFromPath,
-- SetRotation, the colour curve, the colour picker), installed per step
local ART = dofile(here .. "/stub_art.lua")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- T54 (P10, review Q8): the probe's combat snapshot is C_Timer.After(2, ...),
-- and the stub now fires a timer when its clock reaches it. Each step ticks
-- the clock past the delay instead of calling the queued functions by hand,
-- and notes here whatever it left pending; one check at the end says nothing.
local leftovers = {}
local function NoteLeft(Sx, label)
    local n = Sx.Pending and Sx.Pending() or #(Sx.timers or {})
    if n ~= 0 then leftovers[#leftovers + 1] = string.format("%s: %d pending", label, n) end
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

-- The sixteen "== " headers, each paired with enough of what follows to tell
-- it apart from the one it is a prefix of ("== spells" / "== events").
local HEADERS_IN_ORDER = {
    "== client", "== functions (", "== events\n", "== blocked actions\n", "== secrets now", "== spells (",
    "== spells against the previous run", "== talents", "== readings now",
    "== combat snapshot", "== events seen this session", "== unit combat tokens\n", "== damage meter",
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

-- T87: the sections the next round adds, in the order Run() prints them,
-- between == windows and == to do.
local NEXT_HEADERS = { "\n== windows\n", "\n== art\n", "\n== hosts\n", "\n== clock\n",
    "\n== cooldowns\n", "\n== auras\n", "\n== to do\n" }
local function InOrder(report, markers)
    if type(report) ~= "string" then return false end
    local pos = 0
    for _, marker in ipairs(markers) do
        local s = report:find(marker, pos + 1, true)
        if not s then return false end
        pos = s
    end
    return true
end

-- T87: a borrowed LibStub as a host addon leaves it -- a callable table with
-- its own minor and GetLibrary(major, silent) answering the instance and its
-- minor, nil for a library nobody loaded.
local function FakeLibStub(libs)
    local LS = { minor = 2, libs = {}, minors = {} }
    for name, minor in pairs(libs) do LS.libs[name] = { name = name }; LS.minors[name] = minor end
    function LS:GetLibrary(major, silent)
        if not self.libs[major] then
            if not silent then error("Cannot find a library instance of " .. tostring(major)) end
            return nil
        end
        return self.libs[major], self.minors[major]
    end
    return setmetatable(LS, { __call = LS.GetLibrary })
end

--------------------------------------------------------------------------------
-- Step 1: the TBC line
--------------------------------------------------------------------------------
HARNESS_FLAVOUR = "tbc"
HARNESS_FORCE = true -- T87: the TBC line inside a forever run as well as a tbc one
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
-- T87 (docs/SPEC-next.md decision 22, risk X10): the probe on the TBC line --
-- a Forever-shaped file on a 20506 client. The TBC harness's own load (its file
-- list, its UI filter, its login), with Client/Probe.lua where the integrator
-- puts it on SpellTuner_TBC.toc -- the last line, the place the Forever TOCs
-- give it -- while the TOC does not list it yet; once it does, the TOC's own
-- list is loaded unchanged. The stub's TBC profile: no C_Secrets, no
-- C_SpellBook, no C_TooltipInfo, no C_DamageMeter, no C_UnitAuras.
--------------------------------------------------------------------------------
if FLAVOUR == "tbc" then
    local function KeepForTbc(rel) -- tools/harness.lua's rule
        if rel:sub(1, 3) == "UI/" then return rel == "UI/Summary.lua" end
        if rel:sub(1, 13) == "Integrations/" then return false end
        return true
    end
    local function LoadTbc(setup)
        dofile(here .. "/wowstub.lua")
        local St = _G.STUB
        St.root = ROOT
        St.flavour = "tbc"
        if setup then setup(St) end
        local files, listed = {}, false
        for _, rel in ipairs(St.TocFiles("SpellTuner_TBC.toc")) do
            if rel == "Client/Probe.lua" then listed = true end
            if KeepForTbc(rel) then files[#files + 1] = rel end
        end
        if not listed then files[#files + 1] = "Client/Probe.lua" end
        St.loadedFiles = files
        local MDt = {}
        local okLoad, err = pcall(function()
            St.Load(files, "SpellTuner", MDt)
            MDt:SetTalents({})
            St.Fire("ADDON_LOADED", "SpellTuner")
            St.Fire("PLAYER_LOGIN")
            St.Fire("PLAYER_ENTERING_WORLD")
        end)
        if not okLoad then print("tbc load: " .. tostring(err)) end
        return okLoad and MDt or nil, St
    end

    -- ManaDemon's saved variables still waiting to be adopted (tools/migrate.lua's
    -- case): the probe's ADDON_LOADED comes before Core.lua's PLAYER_LOGIN
    -- adoption and must not make an empty SpellTunerDB that blocks it.
    _G.SpellTunerDB = nil
    _G.ManaDemonDB = { halfLife = 42, char = {} }
    local MDt, St = LoadTbc(function(Sx)
        ART.Install(Sx, { atlases = false, colorPicker = "classic" })
        function GetBuildInfo() return "2.5.5", "65000", "Sep 1 2026", 20506 end
        -- ElvUI loaded and a borrowed LibStub with LDB, EllesmereUI absent (it
        -- refuses to run below 12.1 except on Forever)
        function IsAddOnLoaded(name) return name == "SpellTuner" or name == "ElvUI" end
        local ownMeta = GetAddOnMetadata
        function GetAddOnMetadata(name, field)
            if name == "ElvUI" and field == "Version" then return "13.74" end
            if name ~= "SpellTuner" then return nil end
            return ownMeta(name, field)
        end
        function GetAddOnInfo(name)
            if name == "ElvUI" or name == "SpellTuner" then return name, name, "", true, nil end
            return name, nil, nil, false, "MISSING"
        end
        _G.LibStub = FakeLibStub({ ["LibDataBroker-1.1"] = 4, ["CallbackHandler-1.0"] = 7 })
        function GetSpellBaseCooldown(id)
            if id == 18562 then return 15000, 0 end
            return 0, 1500
        end
    end)
    local okT = MDt ~= nil
    local chatT = okT and ChatCapture() or {}
    local okRun1 = okT and pcall(SlashCmdList.SPELLTUNER, "probe")
    local rec1 = okT and type(SpellTunerDB) == "table" and type(SpellTunerDB.probe) == "table"
        and type(SpellTunerDB.probe.reports) == "table" and SpellTunerDB.probe.reports["65000"] or nil
    local reportT1 = type(rec1) == "table" and rec1.text or nil

    -- a fight: the regen events set the TBC profile's combat flag, the clock
    -- runs the probe's 2 s snapshot, a hit is counted by action
    local okFight = okT and pcall(function()
        St.Fire("PLAYER_REGEN_DISABLED")
        St.Tick(1)
        St.Tick(1)
        St.Fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1)
        St.Fire("PLAYER_REGEN_ENABLED")
        St.Tick(5) -- Core_TBC.lua's profile write, 5 s after login
    end)
    local okRun2, reportT2 = false, nil
    if okT then okRun2, reportT2 = pcall(MDt.Probe.Run) end
    if okT then NoteLeft(St, "tbc") end

    check("T87 tbc: the TBC file list loads with the probe on it, its client named tbc",
        okT and type(MDt.Probe) == "table" and type(MDt.Probe.Run) == "function"
        and MDt.API.client == "tbc")

    do
        local row, helpNames = nil, false
        if okT then
            for _, c in ipairs(MDt:Commands()) do if c.name == "probe" then row = c end end
            local lines = {}
            local frame = _G.DEFAULT_CHAT_FRAME
            local orig = frame.AddMessage
            frame.AddMessage = function(_, m) lines[#lines + 1] = m end
            pcall(SlashCmdList.SPELLTUNER, "help")
            frame.AddMessage = orig
            helpNames = Has(table.concat(lines, "\n"), "probe")
        end
        check("T87 tbc: /md probe is a hidden row, so the help does not list it",
            row ~= nil and row.hidden == true and row.usage == "/st probe" and not helpNames)
    end

    check("T87 tbc: /md probe runs the probe and saves the report keyed by build",
        okRun1 == true and type(reportT1) == "string" and Has(reportT1, "SpellTuner probe ")
        and Has(table.concat(chatT, "\n"), "SpellTuner probe: build 65000")
        and Has(table.concat(chatT, "\n"), "lines, saved."))

    check("T87 tbc: no section raises -- every section in order, no <error> anywhere",
        okFight == true and okRun2 == true and HeadersInOrder(reportT1) and HeadersInOrder(reportT2)
        and InOrder(reportT2, NEXT_HEADERS)
        and not Has(reportT1, "<error") and not Has(reportT2, "<error"),
        (function()
            if type(reportT2) ~= "string" then return "no report" end
            return reportT2:match("[^\n]*<error[^\n]*") or "a section missing or out of order"
        end)())

    do
        local function Section(r, header, nextHeader) return Between(r or "", header, nextHeader) end
        check("T87 tbc: the Forever-only sections read absent, and so do the Forever questions",
            Section(reportT2, "\n== secrets now\n", "\n== spells (") == "absent (Forever only)"
            and Has(reportT2, "\nslots 1-500: absent (Forever only)\n")
            and Section(reportT2, "\n== spells against the previous run\n", "\n== talents\n") == "absent (Forever only)"
            and Section(reportT2, "\n== talents\n", "\n== shapes\n") == "absent (Forever only)"
            and Section(reportT2, "\n== shapes\n", "\n== readings now\n") == "absent (Forever only)"
            and Section(reportT2, "\n== damage meter\n", "\n== saved variables\n") == "absent (Forever only)"
            and Section(reportT2, "\n== auras\n", "\n== to do\n") == "absent (Forever only)"
            and Has(reportT2, "\nQ1-Q8: Forever questions, absent on this client\n")
            and not Has(reportT2, "Q1 to do") and not Has(reportT2, "macro to do")
            and Has(reportT2, "\nQ9 answered: SPELLTUNER_TOC = TBC"))
    end

    check("T87 tbc: == art reads every TBC path, the atlases absent",
        Has(reportT2, "\n== art\nGetFileIDFromPath present, C_Texture.GetAtlasInfo absent\n")
        and Has(reportT2, "\nfile Interface\\\\DialogFrame\\\\UI-DialogBox-Border id=137015 set=true get=137015\n")
        and Has(reportT2, "\nfile Interface\\\\Tooltips\\\\UI-Tooltip-Border id=137017 set=true get=137017\n")
        and Has(reportT2, "\nfile Interface\\\\Buttons\\\\UI-Panel-Button-Up id=137019 set=true get=137019\n")
        and Has(reportT2, "\nfile Interface\\\\QuestFrame\\\\QuestBG id=absent set=false get=nil\n")
        and Has(reportT2, "\natlas Options_List_Hover <absent>\n")
        and Has(reportT2, "\natlas 128-RedButton-Left <absent>\n"))

    check("T87 tbc: == clock answers Q-clock-3 and Q-clock-4, the curve and the secret text absent",
        Has(reportT2, "\nQ-clock-1 colour curve: C_CurveUtil.CreateColorCurve absent, CreateColor absent, UnitPowerPercent absent\n")
        and Has(reportT2, "\nQ-clock-2 percent as text: UnitPowerPercent <absent>\n")
        and Has(reportT2, "\nQ-clock-3 ColorPickerFrame present, SetupColorPickerAndShow absent, SetColorRGB present\n")
        and Has(reportT2, "\nQ-clock-4 texture Interface\\\\TargetingFrame\\\\UI-StatusBar id=137013 set=true get=137013\n")
        and Has(reportT2, "\nQ-clock-4 texture Interface\\\\RaidFrame\\\\Raid-Bar-Hp-Fill id=absent set=false get=nil\n")
        and Has(reportT2, "\nQ-clock-4 font Fonts\\\\MORPHEUS.ttf set=true get=Fonts\\\\MORPHEUS.ttf\n")
        and Has(reportT2, "\nQ-clock-4 rotation SetRotation(0.5) nothing, GetRotation 0.5\n"))

    check("T87 tbc: == hosts names ElvUI and the borrowed LibStub, EllesmereUI absent",
        Has(reportT2, "\naddon ElvUI loaded=true version=13.74\n")
        and Has(reportT2, "\naddon EllesmereUI loaded=false reason=MISSING\n")
        and Has(reportT2, "\nEllesmereUI absent\n") and Has(reportT2, "\nElvUI absent\n")
        and Has(reportT2, "\nLibStub present minor=2\n")
        and Has(reportT2, "\nlib LibDataBroker-1.1 minor=4\n")
        and Has(reportT2, "\nlib LibSharedMedia-3.0 absent\n"))

    check("T87 tbc: == cooldowns reads the base cooldowns and counts a hit by action",
        Has(reportT2, "\nGetSpellBaseCooldown(18562 Swiftmend) = 15000, 0\n")
        and Has(reportT2, "\nGetSpellCooldown(18562 Swiftmend) = 0, 0, 1\n")
        and Has(reportT2, "\nbook cooldown: absent (Forever only)\n")
        and Has(reportT2, "\nUnitGetTotalAbsorbs(player) = <absent>\n")
        and Has(reportT2, "\nUnitGetTotalAbsorbs(player) in combat = <absent>\n")
        and Has(reportT2, "\nUNIT_COMBAT combat action=WOUND descriptor=none n=1 amount readable=1 secret=0\n"))

    check("T87 tbc: the combat snapshot is taken on TBC too",
        Has(Between(reportT2 or "", "\n== combat snapshot\n", "\n== events seen this session\n") or "", "in combat: true"))

    check("T87 tbc: ManaDemon's saved variables are still adopted with the probe on the TOC",
        okT and MDt.db ~= nil and MDt.db.halfLife == 42 and _G.ManaDemonDB == nil
        and MDt.db == _G.SpellTunerDB and type(MDt.db.probe) == "table"
        and type(MDt.db.probe.reports) == "table")

    check("T87 tbc: the report is ASCII with no bare pipe",
        type(reportT1) == "string" and type(reportT2) == "string" and AsciiSafe(reportT1) and AsciiSafe(reportT2))

    check("review Q8: every step's timers ran on the clock; none is left pending",
        #leftovers == 0, #leftovers > 0 and table.concat(leftovers, "; ") or nil)

    print(string.format("\n%d ok, %d failed", ok, #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
    if #fails > 0 then os.exit(1) end
    os.exit(0)
end

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

-- T7a item 7: a readable player cast, out of combat, and a party1 cast --
-- the latter must not be counted at all.
Do(S.Fire, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", 774)
Do(S.Fire, "UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-P", 774)

Do(S.Fire, "UNIT_COMBAT", "party1", "HEAL", "", 120, 1)
Do(S.Fire, "UNIT_COMBAT", "party1", "BLOCK|X", "", 5, 1)
S.inCombat = true
Do(S.Fire, "PLAYER_REGEN_DISABLED")
-- T54 (P10): two seconds on the clock, in combat -- the snapshot runs then
Do(S.Tick, 1)
Do(S.Tick, 1)
NoteLeft(S, "step 2")
-- T7a item 7: a secret spell id, in combat.
Do(S.Fire, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", S.Secret())
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
-- The release (T23): the Forever package ships the two Forever TOCs, the TBC package
-- the TBC one, and neither carries the other's TOC marker file.
--------------------------------------------------------------------------------
local RELEASE_OUT = ROOT .. "/tools/.lua/probecheck-release"
local releaseOutput = ""
do
    local p = io.popen("bash \"" .. ROOT .. "/release.sh\" --out \"" .. RELEASE_OUT .. "\" 2>&1")
    if p then releaseOutput = p:read("*a") or ""; p:close() end
end

local function TocsIn(dir)
    local tocs = {}
    local p = io.popen("ls \"" .. dir .. "\"/*.toc 2>/dev/null")
    if p then
        for line in p:lines() do tocs[#tocs + 1] = line:match("([^/]+)$") end
        p:close()
    end
    table.sort(tocs)
    return tocs
end
local foreverTocs = TocsIn(RELEASE_OUT .. "/forever/SpellTuner")
local tbcTocs = TocsIn(RELEASE_OUT .. "/tbc/SpellTuner")

local function FileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

check("the Forever package ships two TOCs and the TBC package one",
    Has(releaseOutput, "Built ")
    and #foreverTocs == 2
    and foreverTocs[1] == "SpellTuner.toc" and foreverTocs[2] == "SpellTuner_Mainline.toc"
    and #tbcTocs == 1 and tbcTocs[1] == "SpellTuner_TBC.toc"
    and FileExists(RELEASE_OUT .. "/forever/SpellTuner/Client/TOC_Mainline.lua")
    and FileExists(RELEASE_OUT .. "/forever/SpellTuner/Client/TOC_Plain.lua")
    and not FileExists(RELEASE_OUT .. "/tbc/SpellTuner/Client/TOC_Mainline.lua")
    and not FileExists(RELEASE_OUT .. "/tbc/SpellTuner/Client/TOC_Plain.lua")
    and FileExists(RELEASE_OUT .. "/tbc/SpellTuner/Client/TOC_TBC.lua")
    and not FileExists(RELEASE_OUT .. "/forever/SpellTuner/Client/TOC_TBC.lua")
    and not FileExists(RELEASE_OUT .. "/forever/SpellTuner/Client/TOC_Forever.lua")
    and not FileExists(RELEASE_OUT .. "/forever/SpellTuner/Client/TOC_Vanilla.lua")
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

local function TocVersion(path)
    for _, l in ipairs(ReadLines(path)) do
        local v = l:match("^## Version: (.+)$")
        if v then return v end
    end
    return nil
end

do
    local plainLines = ReadLines(ROOT .. "/SpellTuner.toc")
    local mainlineLines = ReadLines(ROOT .. "/SpellTuner_Mainline.toc")
    local version = TocVersion(ROOT .. "/SpellTuner.toc")
    local sameVersion = version ~= nil
        and TocVersion(ROOT .. "/SpellTuner_Mainline.toc") == version
        and TocVersion(ROOT .. "/SpellTuner_TBC.toc") == version
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
    local PREFIX = "SpellTuner probe " .. tostring(version) .. " -- "
    check("the Forever TOCs carry the one version and differ only in their marker",
        sameVersion and sameCount and diffs == 1 and diffOk
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

--------------------------------------------------------------------------------
-- T7a: the == shapes section
--------------------------------------------------------------------------------

-- The exact text of the line starting at the given marker, or nil.
local function LineContaining(s, marker)
    local i = s:find(marker, 1, true)
    if not i then return nil end
    local j = s:find("\n", i, true) or (#s + 1)
    return s:sub(i, j - 1)
end

check("the shapes section sits between the talents and the readings",
    Between(report1, "\n== talents\n", "\n== shapes\n") ~= nil
    and Between(report1, "\n== shapes\n", "\n== readings now\n") ~= nil)

check("the shapes section lists every skill line whole",
    Has(report1, "skill lines: 2")
    and Has(report1, "skill line 1 = {iconID=1, isGuild=false, itemIndexOffset=0, name=General, numSpellBookItems=0, shouldHide=false}")
    and Has(report1, "skill line 2 = {iconID=2, isGuild=false, itemIndexOffset=0, name=Druid, numSpellBookItems=5, shouldHide=false}"))

--------------------------------------------------------------------------------
-- Step 7: Forever, fresh -- a low-rank spell added via S.AddSpell's fifth
-- argument, and (after the first run) C_TooltipInfo removed entirely.
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S7 = _G.STUB
S7.root = ROOT
S7.UseProfile("forever")
S7.AddSpell(900100, "Stub Shield", "Rank 1", function() return "Reduces damage taken." end, { lowRank = true })

_G.SpellTunerDB = nil
local MD7 = {}
local step7LoadOk = pcall(S7.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD7)
local step7AddonLoadedOk = pcall(S7.Fire, "ADDON_LOADED", "SpellTuner")
local okE, reportE = pcall(MD7.Probe.Run)

--------------------------------------------------------------------------------
-- Step 8: Forever, fresh, C_TooltipInfo missing entirely -- a FRESH load
-- (T7a assertion 6), since MD.API.Has caches its answer for the life of one
-- API table and Step 7's MD7 already cached C_TooltipInfo.GetSpellByID as
-- present before this could remove it.
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S8 = _G.STUB
S8.root = ROOT
S8.UseProfile("forever")
C_TooltipInfo = nil

_G.SpellTunerDB = nil
local MD8 = {}
local step8LoadOk = pcall(S8.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD8)
local step8AddonLoadedOk = pcall(S8.Fire, "ADDON_LOADED", "SpellTuner")
local okF, reportF = pcall(MD8.Probe.Run)

--------------------------------------------------------------------------------
-- Step 9 (T13b): Endurance's and Plainsrunning's real texts (m2 140, 175) --
-- a passive whose description says "Health" or "Taking damage" must not be
-- picked as a heal or a damage spell -- and UNIT_COMBAT counted per exact
-- token, with a same-frame repeat under a different token counted as a
-- mirror.
--------------------------------------------------------------------------------
dofile(here .. "/wowstub.lua")
local S9 = _G.STUB
S9.root = ROOT
S9.UseProfile("forever")
S9.AddSpell(20550, "Endurance", "Racial Passive",
    function() return "Total Health increased by 5% and chance to hit increased by 1%." end)
S9.AddSpell(1259918, "Plainsrunning", "Racial Passive",
    function()
        return "Gain 1% increased movement speed every 5 sec spent moving, up to a maximum of 30% increase. "
            .. "Taking damage or standing still will reduce this effect."
    end)
S9.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })

_G.SpellTunerDB = nil
local MD9 = {}
local step9LoadOk = pcall(S9.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD9)
local step9AddonLoadedOk = pcall(S9.Fire, "ADDON_LOADED", "SpellTuner")

S9.now = 100
local step9C1 = pcall(S9.Combat, "player", "HEAL", 12)
local step9C2 = pcall(S9.Combat, "nameplate1", "HEAL", 12)
S9.now = 105
local step9C3 = pcall(S9.Combat, "party1", "WOUND", 5)

local okG, reportG = pcall(MD9.Probe.Run)

check("every spell in the book has one shapes line: info, cost, learned, base, low rank, row",
    okE == true
    and Has(reportE, "book 5185 Healing Touch Rank 1: info=")
    and Has(reportE, "book 774 Rejuvenation Rank 1: info=")
    and Has(reportE, "book 5176 Wrath Rank 1: info=")
    and Has(reportE, "book 1058 Rejuvenation Rank 2: info=")
    and (function()
        local line = LineContaining(reportE, "book 900100 Stub Shield Rank 1:")
        return line ~= nil and Has(line, "lowrank=true")
    end)())

check("a spell's cost is rendered two levels deep",
    Has(report1, "cost={1={cost=25, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=25, name=MANA, requiredAuraID=0, type=0}}"))

check("the first heal and the first damage spell carry their tooltip lines, pipes escaped",
    Has(report1, "tooltip 5185 = 4 lines")
    and Has(report1, "  line 4: Heals a friendly target for 40 to 55.||nIt is \\226\\128\\156quoted\\226\\128\\157. || nil")
    and Has(report1, "tooltip 5176 = 4 lines"))

-- T13b
check("the shapes section dumps the tooltip lines of a direct heal, a HoT and a damage spell",
    Has(report1, "tooltip 5185 = 4 lines")
    and Has(report1, "tooltip 774 = 4 lines")
    and Has(report1, "tooltip 5176 = 4 lines"))

check("a passive whose text says Health or taking damage is not picked as a heal or a damage spell",
    step9LoadOk == true and step9AddonLoadedOk == true and okG == true
    and not Has(reportG, "spell 20550")
    and not Has(reportG, "spell 1259918")
    and not Has(reportG, "tooltip 20550 ")
    and not Has(reportG, "tooltip 1259918 "))

do
    local seg1 = Between(report1, "\n== readings now\n", "\n== combat snapshot\n")
    local seg2 = Between(report2, "\n== combat snapshot\n", "\n== events seen this session\n")
    local function HasAll(seg)
        return seg ~= nil
            and Has(seg, "C_Secrets.ShouldUnitHealthMaxBeSecret(party1) = true")
            and Has(seg, "UnitGUID(party1) = Party-1")
            and Has(seg, "UnitName(party1) = Tankname")
            and Has(seg, "UnitLevel(party1) = 64")
            and Has(seg, "UnitClass(party1) = Warrior, WARRIOR")
            and Has(seg, "UnitGroupRolesAssigned(party1) = TANK")
    end
    check("party readings carry the max-health predicate, guid, name, level, class and role",
        HasAll(seg1) and HasAll(seg2))
end

do
    local seg = Between(reportG, "\n== unit combat tokens\n", "\n== damage meter\n")
    check("UNIT_COMBAT is counted per token with its guid readability, and a same-frame repeat as a mirror",
        step9C1 == true and step9C2 == true and step9C3 == true and okG == true
        and seg ~= nil
        and Has(seg, "ooc player n=1 guid readable=1 guid secret=0")
        and Has(seg, "ooc nameplate n=1 guid readable=0 guid secret=0")
        and Has(seg, "ooc party1 n=1 guid readable=1 guid secret=0")
        and Has(seg, "ooc mirrored: 1 of 3"))
end

-- Re-issue 1: 50 UNIT_COMBAT events across 50 different S.now values must
-- never leave more than one moment's events sitting in the probe's mirror
-- list -- each one arrives at its own GetTime() moment, so the list is
-- emptied and refilled with just that one event every time.
local step9ManyOk = true
for i = 1, 50 do
    S9.now = 300 + i
    local ok = pcall(S9.Combat, "player", "HEAL", 12)
    if not ok then step9ManyOk = false end
end
check("the mirror list holds one moment's events, not the session's",
    step9ManyOk == true
    and type(MD9.Probe.UnitCombatEventsCount) == "function"
    and MD9.Probe.UnitCombatEventsCount() == 1)

check("a shape function the client lacks reads <absent>",
    okF == true and Has(reportF, "tooltip = <absent>") and HeadersInOrder(reportF))

do
    local seg = Between(report2, "\n== shapes\n", "\n== readings now\n")
    check("the combat snapshot carries the shapes read in combat",
        seg ~= nil and Has(seg, "in combat (") and Has(seg, "desc=<secret>") and Has(seg, "crit4=<secret>"))
end

check("UNIT_SPELLCAST_SUCCEEDED is counted with its id readable or secret, and the cost read at the cast",
    Has(report2, "UNIT_SPELLCAST_SUCCEEDED ooc n=1 readable=1 secret=0 sample=774; cost at cast readable=1 secret=0 absent=0")
    and Has(report2, "UNIT_SPELLCAST_SUCCEEDED combat n=1 readable=0 secret=1 sample=; cost at cast readable=0 secret=0 absent=0"))

--------------------------------------------------------------------------------
-- T13e: does a plain StatusBar hand a secret back through its own getters?
-- report1 (ooc) and report2's combat snapshot already carry the bar readings
-- under the forever stub's always-secret UnitHealthMax(party1) -- no new
-- fixture needed for the secret case.
--------------------------------------------------------------------------------
check("a status bar handed a secret reports whether it reads back secret",
    Has(report1, "bar UnitHealthMax(party1): set ok, read secret")
    and Has(report1, "bar UnitHealth(player): set ok, read secret")
    and Has(report1, "bar UnitPower(player, 0): set ok, read secret")
    and (function()
        local seg = Between(report2, "\n== combat snapshot\n", "\n== events seen this session\n")
        return seg ~= nil
            and Has(seg, "bar UnitHealthMax(party1): set ok, read secret")
            and Has(seg, "bar UnitHealth(player): set ok, read secret")
            and Has(seg, "bar UnitPower(player, 0): set ok, read secret")
    end)())

do
    dofile(here .. "/wowstub.lua")
    local S10 = _G.STUB
    S10.root = ROOT
    S10.UseProfile("forever")
    S10.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })

    local MD10 = {}
    _G.SpellTunerDB = nil
    local step10LoadOk = pcall(S10.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD10)
    local step10AddonLoadedOk = pcall(S10.Fire, "ADDON_LOADED", "SpellTuner")

    -- UnitHealthMax(party1) made plain for this item only, restored after.
    local origUnitHealthMax = UnitHealthMax
    UnitHealthMax = function(u)
        if u == "party1" then return 12345 end
        return origUnitHealthMax(u)
    end
    -- The bar's own GetValue raises for this item -- the current-value path
    -- (UnitHealth(player)/UnitPower(player, 0)), never GetMinMaxValues.
    local barMT = getmetatable(_G.UIParent)
    local origGetValue = barMT.GetValue
    barMT.GetValue = function(self) error("stub GetValue raised") end

    local okH, reportH = pcall(MD10.Probe.Run)

    UnitHealthMax = origUnitHealthMax
    barMT.GetValue = origGetValue

    check("a status bar handed a plain number reads it back plain",
        step10LoadOk == true and step10AddonLoadedOk == true and okH == true
        and Has(reportH, "bar UnitHealthMax(party1): set ok, read plain 12345")
        and Has(reportH, "bar UnitHealth(player): set ok, read error:")
        and Has(reportH, "bar UnitPower(player, 0): set ok, read error:"))
end

--------------------------------------------------------------------------------
-- Step 11 (review-probe, docs/review/2026-09-29-forever-review.md R2, R17,
-- R18, R19, R20): a fresh Forever load in a party.
--   R19: a free spell (GetSpellPowerCost answers nothing) and one whose cost
--        list is plain but whose fields are secret, both cast out of combat.
--   R18: player and party1 healed for the same amount in one moment (two
--        units, both GUIDs readable) and a target seen again as nameplate1
--        (one unit, the same GUID) in the next.
--   R20: blocked actions naming a module, and an addon that merely starts
--        with our name.
--   R2 + R17: a fight that ends before the 2 s snapshot, with only a party
--        member's PET taking damage in it; then a fight long enough for the
--        snapshot, then a short one after it.
--------------------------------------------------------------------------------
do
    dofile(here .. "/wowstub.lua")
    local S11 = _G.STUB
    S11.root = ROOT
    S11.UseProfile("forever")
    S11.AddUnit("party1", { guid = "Party-1", name = "Tankname", class = "WARRIOR", role = "TANK", hp = 4000, hpMax = 4000 })
    S11.AddUnit("target", { guid = "Creature-9", name = "Mob", class = "WARRIOR", hp = 900, hpMax = 900 })
    S11.AddUnit("nameplate1", { guid = "Creature-9", name = "Mob", class = "WARRIOR", hp = 900, hpMax = 900 })

    -- R19's two spells, wrapped before the load: MD.API.Has keeps what it found.
    local origCost = C_Spell.GetSpellPowerCost
    C_Spell.GetSpellPowerCost = function(id)
        if id == 900201 then return end
        if id == 900202 then return { { type = 0, name = "MANA", cost = S11.Secret(), minCost = S11.Secret() } } end
        return origCost(id)
    end

    _G.SpellTunerDB = nil
    local MD11 = {}
    local loadOk = pcall(S11.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD11)
    local addonLoadedOk = pcall(S11.Fire, "ADDON_LOADED", "SpellTuner")
    local steps = {}
    local function Do11(fn, ...) steps[#steps + 1] = pcall(fn, ...) end

    Do11(S11.Fire, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-F", 900201)
    Do11(S11.Fire, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-S", 900202)

    S11.now = 500
    Do11(S11.Combat, "player", "HEAL", 7)
    Do11(S11.Combat, "party1", "HEAL", 7)
    S11.now = 501
    Do11(S11.Combat, "target", "WOUND", 40)
    Do11(S11.Combat, "nameplate1", "WOUND", 40)

    Do11(S11.Fire, "ADDON_ACTION_BLOCKED", "SpellTuner_Recorder", "Frame:RegisterEvent()")
    Do11(S11.Fire, "ADDON_ACTION_FORBIDDEN", "SpellTuner_Practice", "UNKNOWN()")
    Do11(S11.Fire, "ADDON_ACTION_FORBIDDEN", "SpellTunerX", "CastSpellByName()")

    -- the short fight: over before its snapshot timer runs
    S11.inCombat = true
    Do11(S11.Fire, "PLAYER_REGEN_DISABLED")
    Do11(S11.Combat, "partypet1", "WOUND", 30)
    S11.inCombat = false
    Do11(S11.Fire, "PLAYER_REGEN_ENABLED")
    -- T54 (P10): the snapshot's two seconds pass on the clock, out of combat
    Do11(S11.Tick, 2)
    NoteLeft(S11, "step 11, short fight")
    local okI, reportI = pcall(MD11.Probe.Run)

    -- a fight the snapshot is taken in, then a short one after it
    S11.inCombat = true
    Do11(S11.Fire, "PLAYER_REGEN_DISABLED")
    Do11(S11.Tick, 2)
    S11.inCombat = false
    Do11(S11.Fire, "PLAYER_REGEN_ENABLED")
    S11.inCombat = true
    Do11(S11.Fire, "PLAYER_REGEN_DISABLED")
    S11.inCombat = false
    Do11(S11.Fire, "PLAYER_REGEN_ENABLED")
    Do11(S11.Tick, 2)
    NoteLeft(S11, "step 11, two fights")
    local okJ, reportJ = pcall(MD11.Probe.Run)

    local allOk = loadOk and addonLoadedOk and okI and okJ
    for _, r in ipairs(steps) do if not r then allOk = false end end
    check("step 11 never raises", allOk == true)
    if type(reportI) ~= "string" then reportI = "" end
    if type(reportJ) ~= "string" then reportJ = "" end

    -- R2
    do
        local seg = Between(reportI, "\n== combat snapshot\n", "\n== events seen this session\n")
        check("R2: a fight over before the 2 s snapshot answers neither Q2 nor Q5",
            seg ~= nil and Has(seg, "none this session")
            and Has(seg, "skipped 1: the fight had ended before the 2 s snapshot")
            and Has(reportI, "Q2 to do") and Has(reportI, "Q5 to do")
            and not Has(reportI, "Q2 answered") and not Has(reportI, "Q5 answered"))
    end
    do
        local seg = Between(reportJ, "\n== combat snapshot\n", "\n== events seen this session\n")
        check("R2: a short fight after a good snapshot does not replace it",
            seg ~= nil and Has(seg, "in combat: true") and not Has(seg, "in combat: false")
            and Has(seg, "skipped 2: the fight had ended before the 2 s snapshot")
            and Has(reportJ, "Q2 answered") and Has(reportJ, "Q5 answered"))
    end

    -- R17
    check("R17: a party pet's UNIT_COMBAT is its own class and does not answer Q3",
        Has(reportI, "UNIT_COMBAT combat partypet WOUND n=1")
        and not Has(reportI, "UNIT_COMBAT combat party WOUND")
        and Has(reportI, "Q3 to do") and not Has(reportI, "Q3 answered"))

    -- R18
    do
        local seg = Between(reportI, "\n== unit combat tokens\n", "\n== damage meter\n")
        check("R18: two units hit for the same amount in one moment are not a mirror; one unit under two tokens is",
            seg ~= nil and Has(seg, "ooc mirrored: 1 of 4\n") and not Has(seg, "possibly two units"))
    end

    -- R19
    check("R19: a free spell's cost is no cost, and secret fields in a plain list are secret",
        Has(reportI, "UNIT_SPELLCAST_SUCCEEDED ooc n=2 readable=2 secret=0 sample=900201; cost at cast readable=0 secret=1 absent=0 no cost=1"))

    -- R20
    do
        local seg = Between(reportI, "\n== blocked actions\n", "\n== secrets now\n")
        check("R20: a blocked action naming one of our modules is recorded; a lookalike name is not",
            seg ~= nil
            and Has(seg, "ADDON_ACTION_BLOCKED phase=ooc during=idle addon=SpellTuner_Recorder function=Frame:RegisterEvent() n=1")
            and Has(seg, "ADDON_ACTION_FORBIDDEN phase=ooc during=idle addon=SpellTuner_Practice function=UNKNOWN() n=1")
            and not Has(seg, "SpellTunerX") and not Has(seg, "CastSpellByName"))
    end
end

-- R18: step 9's mirror (player and nameplate1, whose GUID the stub does not
-- answer) is still counted, and now says the unit could not be told apart.
do
    local seg = Between(reportG, "\n== unit combat tokens\n", "\n== damage meter\n")
    check("R18: a mirror whose unit cannot be confirmed by GUID says so",
        seg ~= nil and Has(seg, "ooc mirrored: 1 of 3 (1 with a guid not readable, so possibly two units)"))
end

--------------------------------------------------------------------------------
-- Step 12 (review-probe R3): the whole Forever TOC, so Core_Forever.lua's
-- SavedVariables guard runs before the probe's ADDON_LOADED -- the probe's
-- "at load" line must say what the client handed back, not what the guard
-- replaced it with.
--------------------------------------------------------------------------------
do
    local function Session(preset)
        HARNESS_FLAVOUR = "forever"
        HARNESS_FORCE = true -- T57 (P13): Forever inside a tbc run (tools/check.sh runs this under tbc)
        _G.SpellTunerDB = preset
        _G.ManaDemonDB = nil
        local a1 = arg[0]; arg[0] = here .. "/harness.lua"
        local okLoad, MDx = pcall(dofile, here .. "/harness.lua"); arg[0] = a1
        if not okLoad or type(MDx) ~= "table" or type(MDx.Probe) ~= "table" then return nil end
        local okRun, report = pcall(MDx.Probe.Run)
        if not okRun or type(report) ~= "string" then return nil end
        return report
    end
    local reportNil = Session(nil)
    local reportBroken = Session("junk")
    check("R3: the at-load line reads the guard's record, not the table it made",
        reportNil ~= nil and Has(reportNil, "SpellTunerDB at load: nil\n")
        and Has(reportNil, "previous session stamp: none")
        and reportBroken ~= nil and Has(reportBroken, "SpellTunerDB at load: string\n"))
end

--------------------------------------------------------------------------------
-- Step 13 (T25a): the macro lines of == shapes. The stub's own macro fixtures
-- (S.actions with a third return, S.macroSpells, S.macros / S.macroOrder,
-- S.actionTooltips, S.ShowMacroTooltip) stand in for the client's.
--------------------------------------------------------------------------------
do
    local function Fresh(before)
        dofile(here .. "/wowstub.lua")
        local St = _G.STUB
        St.root = ROOT
        St.UseProfile("forever")
        if before then before(St) end
        _G.SpellTunerDB = nil
        local MDm = {}
        local loadOk = pcall(St.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MDm)
        local addonOk = pcall(St.Fire, "ADDON_LOADED", "SpellTuner")
        return St, MDm, loadOk and addonOk
    end
    local function Shapes(report)
        return Between(report, "\n== shapes\n", "\n== readings now\n") or ""
    end

    -- 1: the two constants
    do
        local St, MDm, loaded = Fresh()
        local okR, rep = pcall(MDm.Probe.Run)
        check("shapes names the tooltip data types for Spell and Macro",
            loaded and okR and Has(Shapes(rep), "macro types Spell=1 Macro=25\n"))
    end

    -- 2: a macro action whole
    do
        local St, MDm, loaded = Fresh(function(St)
            St.actions[13] = { "macro", 2, "spell" }
            St.macroSpells[2] = 5185
            St.macros["Heal Mac"] = "#showtooltip"
            St.macroOrder[2] = "Heal Mac"
            St.actionTooltips[13] = {
                type = 25, id = 2,
                lines = {
                    { type = 0, tooltipType = 1, tooltipID = 5185, leftText = "Heal" },
                    { type = 0, leftText = "a|cff00ff00b" },
                },
            }
        end)
        local okR, rep = pcall(MDm.Probe.Run)
        local seg = Shapes(rep)
        check("shapes dumps a macro action's GetActionInfo, GetMacroSpell and tooltip data whole",
            loaded and okR
            and Has(seg, "macro action 13 info=macro,2,spell GetMacroSpell=5185 GetMacroInfo=Heal Mac,")
            and Has(seg, "macro action 13 tooltip type=25 id=2 lines=2\n")
            and Has(seg, "macro action 13 line 1 type=0 tooltipType=1 tooltipID=5185 left=Heal\n")
            and Has(seg, "macro action 13 line 2 type=0 tooltipType=nil tooltipID=nil left=a||cff00ff00b")
            and not Has(seg, "macro actions: none")
            and AsciiSafe(rep))
    end

    -- 3: the probe's own Macro post-call
    do
        local St, MDm, loaded = Fresh()
        local okA, before = pcall(MDm.Probe.Run)
        local tt = CreateFrame("GameTooltip")
        local owner = { action = 13, GetAttribute = function(_, k) if k == "action" then return 13 end end }
        local okS = pcall(St.ShowMacroTooltip, tt,
            { type = 25, id = 77, lines = { { tooltipType = 1, tooltipID = 5185 } } }, owner)
        local okB, after = pcall(MDm.Probe.Run)
        check("a hovered macro is recorded by the probe's own post-call, and the to-do line goes",
            loaded and okA and okS and okB
            and Has(before, "macro to do: put a macro that casts a spell on an action bar, hover it, then type /st probe")
            and Has(Shapes(before), "macro hover: 0 seen")
            and Has(Shapes(after),
                "macro hover: 1 seen, last type=25 id=77 line1 tooltipType=1 tooltipID=5185 owner action=13 attr=13")
            and not Has(after, "macro to do")
            and tt:NumLines() == 0)
    end

    -- 4: secret, raising and absent
    do
        local St, MDm, loaded = Fresh(function(St)
            St.actions[13] = { "macro", 2, "spell" }
            St.actions[14] = { "macro", St.Secret(), "spell" }
            St.macros["Heal Mac"] = "#showtooltip"
            St.macroOrder[2] = "Heal Mac"
            _G.GetMacroSpell = nil
            C_TooltipInfo.GetAction = function() error("stub GetAction raised") end
        end)
        local okR, rep = pcall(MDm.Probe.Run)
        local seg = Shapes(rep)
        check("the macro lines never raise on a secret or raising client",
            loaded and okR
            and Has(seg, "macro action 13 info=macro,2,spell GetMacroSpell=<absent>")
            and Has(seg, "macro action 14 info=macro,<secret>,spell")
            and Has(seg, "macro action 13 tooltip <error:")
            and AsciiSafe(rep))
    end
end

--------------------------------------------------------------------------------
-- Step 14 (T33, docs/SPEC-forever-ui.md 6.5): the esc= line. The whole Forever
-- TOC (the window manager with it); "untested" and a to-do line until one ESC
-- press, then what that press did -- here two windows open (the main window
-- and the console) and one closed, the proxy shown again on the next frame.
-- ESC is the client's CloseSpecialWindows; the next frame runs the
-- C_Timer.After callbacks queued since the press.
--------------------------------------------------------------------------------
do
    HARNESS_FLAVOUR = "forever"
    HARNESS_FORCE = true -- T57 (P13): as step 12
    _G.SpellTunerDB, _G.ManaDemonDB = nil, nil
    local a1 = arg[0]; arg[0] = here .. "/harness.lua"
    local okLoad, MDx = pcall(dofile, here .. "/harness.lua"); arg[0] = a1
    local Sx = _G.STUB
    local before, after
    local okAll = okLoad and pcall(function()
        before = MDx.Probe.Run()
        if _G.SpellTunerProbeFrame then _G.SpellTunerProbeFrame:Hide() end
        MDx:SelectView("spells")
        MDx:ToggleDebugConsole()
        local names = {}
        for _, n in ipairs(UISpecialFrames) do names[#names + 1] = n end
        for _, n in ipairs(names) do
            local f = _G[n]
            if f and f:IsShown() then f:Hide() end
        end
        -- T54 (P10): the next frame is a tick of the clock (the proxy's
        -- After(0) re-arm runs in it), not a hand-run of the queued callbacks
        Sx.Tick(0)
        NoteLeft(Sx, "step 14")
        after = MDx.Probe.Run()
    end)
    check("T33: the esc= line: untested with a to-do line, then esc=stack after one press",
        okAll and type(before) == "string" and type(after) == "string"
        and Has(before, "\n== windows\nesc=untested\n") and Has(before, "\nesc to do: ")
        and Has(after, "\nesc=stack (last press: 2 open, 1 closed, the proxy shown again)\n")
        and not Has(after, "esc to do") and AsciiSafe(after),
        type(after) == "string" and (Between(after, "== windows\n", "\n") or "no == windows") or "no report")
    -- T87: the row is hidden on TBC only; Forever's help keeps listing it
    local probeRow = nil
    if okLoad then for _, c in ipairs(MDx:Commands()) do if c.name == "probe" then probeRow = c end end end
    check("T87: on Forever /st probe stays a listed row",
        probeRow ~= nil and probeRow.hidden == false and probeRow.usage == "/st probe")
end

--------------------------------------------------------------------------------
-- Step 15 (T87, docs/SPEC-next.md 5.3, 6, 7.5, 4.2 P1/P3/P4): the five sections
-- the next round asks for, between == windows and == to do -- == art (every
-- path and atlas a style names), == hosts (EllesmereUI, ElvUI, LibStub, LDB),
-- == clock (Q-clock-1..4), == cooldowns (base cooldowns, the book's cooldown
-- spell's tooltip whole, absorbs, UNIT_COMBAT by action), == auras
-- (ShouldAurasBeSecret out of and in combat, a mana source's fields). 15a has
-- every function the sections ask about; 15b none of them.
--------------------------------------------------------------------------------
do
    dofile(here .. "/wowstub.lua")
    local Sn = _G.STUB
    Sn.root = ROOT
    Sn.UseProfile("forever")
    ART.Install(Sn, { atlases = { Options_List_Hover = { file = 4552, width = 128, height = 32 } },
        colorCurve = true, colorPicker = "modern" })
    _G.SpellTunerDB, _G.ManaDemonDB, _G.SPELLTUNER_TOC = nil, nil, nil
    -- EllesmereUI 9.3.4 loaded, with its skin and unlock entry points; LDB
    -- borrowed through the LibStub it loaded
    _G.EllesmereUI = { RegisterSkin = function() end, RegisterUnlockElements = function() end,
        MakeUnlockElement = function() end }
    _G.LibStub = FakeLibStub({ ["LibDataBroker-1.1"] = 4 })
    Sn.addOnLoaded["EllesmereUI"] = true
    -- one of its modules on disk but disabled, as on the author's client
    Sn.RegisterAddOnFolder("EllesmereUIDataBars", "Nowhere")
    Sn.addOnDisabled["EllesmereUIDataBars"] = true
    local ownMeta = C_AddOns.GetAddOnMetadata
    C_AddOns.GetAddOnMetadata = function(name, field)
        if name == "EllesmereUI" and field == "Version" then return "9.3.4" end
        return ownMeta(name, field)
    end
    -- Swiftmend in the book with the cooldown on its tooltip's third line, the
    -- base cooldowns, absorbs secret for a party member (as its health is) and
    -- for the player in combat
    Sn.AddSpell(18562, "Swiftmend", "Rank 1",
        function() return "Consumes a Rejuvenation or Regrowth effect on a friendly target to instantly heal them." end,
        { cost = 205 })
    local ownTip = C_TooltipInfo.GetSpellByID
    C_TooltipInfo.GetSpellByID = function(id)
        local data = ownTip(id)
        if id == 18562 and type(data) == "table" then data.lines[3].rightText = "15 sec cooldown" end
        return data
    end
    function GetSpellBaseCooldown(id)
        if id == 18562 then return 15000, 0 end
        return 0, 1500
    end
    function UnitGetTotalAbsorbs(u)
        if u == "player" then
            if Sn.inCombat then return Sn.Secret() end
            return 0
        end
        if u == "party1" then return Sn.Secret() end
        return nil
    end
    -- the player's auras: Mark of the Wild, an Innervate party1 cast, one whose
    -- name and id are secret; in combat only the Innervate, its fields secret
    local secretName = Sn.Secret("string")
    C_UnitAuras.GetAuraDataByIndex = function(u, i, filter)
        if u ~= "player" then return nil end
        if Sn.inCombat then
            if i == 1 then
                return { name = "Innervate", spellId = 29166, duration = Sn.Secret(),
                    expirationTime = Sn.Secret(), sourceUnit = Sn.Secret("string") }
            end
            return nil
        end
        local rows = {
            { name = "Mark of the Wild", spellId = 1126, duration = 1800 },
            { name = "Innervate", spellId = 29166, duration = 20, expirationTime = 120, sourceUnit = "party1" },
            { name = secretName, spellId = Sn.Secret(), duration = 10 },
        }
        return rows[i]
    end

    local MDn = {}
    local okN = pcall(Sn.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MDn)
    okN = okN and pcall(Sn.Fire, "ADDON_LOADED", "SpellTuner")
    local okA, reportA = false, nil
    if okN then okA, reportA = pcall(MDn.Probe.Run) end
    local okFight = okN and pcall(function()
        Sn.inCombat = true
        Sn.Fire("PLAYER_REGEN_DISABLED")
        Sn.Tick(1)
        Sn.Tick(1)
        Sn.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
        Sn.Fire("UNIT_COMBAT", "player", "ABSORB", "", Sn.Secret(), 1)
        Sn.inCombat = false
        Sn.Fire("PLAYER_REGEN_ENABLED")
    end)
    local okB, reportB = false, nil
    if okN then okB, reportB = pcall(MDn.Probe.Run) end
    NoteLeft(Sn, "step 15a")

    -- 15b: a client with none of them
    _G.EllesmereUI, _G.LibStub, _G.GetSpellBaseCooldown, _G.UnitGetTotalAbsorbs = nil, nil, nil, nil
    _G.GetFileIDFromPath, _G.C_Texture, _G.C_CurveUtil, _G.CreateColor, _G.ColorPickerFrame = nil, nil, nil, nil, nil
    dofile(here .. "/wowstub.lua")
    local Sb = _G.STUB
    Sb.root = ROOT
    Sb.UseProfile("forever")
    _G.SpellTunerDB, _G.SPELLTUNER_TOC = nil, nil
    local MDb = {}
    local okNb = pcall(Sb.Load, { "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MDb)
    okNb = okNb and pcall(Sb.Fire, "ADDON_LOADED", "SpellTuner")
    local okC, reportC = false, nil
    if okNb then okC, reportC = pcall(MDb.Probe.Run) end
    NoteLeft(Sb, "step 15b")

    check("T87: five new sections between == windows and == to do, in order, and none raises",
        okA == true and okFight == true and okB == true and okC == true
        and InOrder(reportA, NEXT_HEADERS) and InOrder(reportB, NEXT_HEADERS) and InOrder(reportC, NEXT_HEADERS)
        and HeadersInOrder(reportA) and HeadersInOrder(reportC))

    check("T87: == art -- a file's id and texture read back, a present atlas its file and size, the rest absent",
        Has(reportA, "\n== art\nGetFileIDFromPath present, C_Texture.GetAtlasInfo present\n")
        and Has(reportA, "\nfile Interface\\\\Buttons\\\\WHITE8x8 id=137012 set=true get=137012\n")
        and Has(reportA, "\nfile Interface\\\\QuestFrame\\\\QuestBG id=absent set=false get=nil\n")
        and Has(reportA, "\natlas Options_List_Hover file=4552 128x32\n")
        and Has(reportA, "\natlas Options_List_Active absent\n"))

    check("T87: == hosts -- EllesmereUI's version and entry points, the borrowed LDB, an absent addon",
        Has(reportA, "\naddon EllesmereUI loaded=true version=9.3.4\n")
        and Has(reportA, "\naddon ElvUI loaded=false reason=MISSING\n")
        and Has(reportA, "\naddon EllesmereUIDataBars loaded=false reason=DISABLED\n")
        and Has(reportA, "\nEllesmereUI present: RegisterSkin present, RegisterUnlockElements present, MakeUnlockElement present, GetAccentColor absent, GetFontPath absent\n")
        and Has(reportA, "\nLibStub present minor=2\n") and Has(reportA, "\nlib LibDataBroker-1.1 minor=4\n")
        and Has(reportA, "\nlib CallbackHandler-1.0 absent\n"))

    check("T87: == clock -- a curve colour into a texture, a secret into a font string, the picker, textures, fonts, rotation",
        Has(reportA, "\nQ-clock-1 colour curve: value colour (GetRGB present), SetVertexColor ok, read back secret\n")
        and Has(reportA, "\nQ-clock-2 percent as text: SetText ok, GetText secret, width plain 40\n")
        and Has(reportA, "\nQ-clock-3 ColorPickerFrame present, SetupColorPickerAndShow present, SetColorRGB absent\n")
        and Has(reportA, "\nQ-clock-4 texture Interface\\\\TargetingFrame\\\\UI-StatusBar id=137013 set=true get=137013\n")
        and Has(reportA, "\nQ-clock-4 font Fonts\\\\FRIZQT__.TTF set=true get=Fonts\\\\FRIZQT__.TTF\n")
        and Has(reportA, "\nQ-clock-4 rotation SetRotation(0.5) nothing, GetRotation 0.5\n"))

    check("T87: == cooldowns -- base cooldowns, the book's cooldown spell with its tooltip whole, absorbs, hits by action",
        Has(reportA, "\nGetSpellBaseCooldown(18562 Swiftmend) = 15000, 0\n")
        and Has(reportA, "\nGetSpellBaseCooldown(20473 Holy Shock) = 0, 1500\n")
        and Has(reportA, "\nbook cooldown 18562 Swiftmend Rank 1: base 15000\ntooltip 18562 = 4 lines\n")
        and Has(reportA, "\n  line 3: Instant || 15 sec cooldown\n")
        and Has(reportA, "\nUnitGetTotalAbsorbs(player) = 0\n")
        and Has(reportA, "\nUnitGetTotalAbsorbs(party1) = <secret>\n")
        and Has(reportA, "\nUnitGetTotalAbsorbs in combat: none this session\n")
        and Has(reportA, "\nUNIT_COMBAT by action: none this session\n")
        and Has(reportB, "\nUnitGetTotalAbsorbs(player) in combat = <secret>\n")
        and Has(reportB, "\nUNIT_COMBAT combat action=WOUND descriptor=none n=1 amount readable=1 secret=0\n")
        and Has(reportB, "\nUNIT_COMBAT combat action=ABSORB descriptor=none n=1 amount readable=0 secret=1\n"))

    check("T87: == auras -- ShouldAurasBeSecret out of and in combat, a mana source readable out of combat and secret in it",
        Has(reportA, "\n== auras\nC_Secrets.ShouldAurasBeSecret() now = false (in combat: false)\n"
            .. "C_Secrets.ShouldAurasBeSecret() in combat = none this session\n"
            .. "helpful auras on you: 3, mana sources 1, secret names 1, secret rows 0\n"
            .. "aura 2 mana source: id=29166 name=Innervate duration=20 expires=120 source=party1\n"
            .. "aura 3: id=<secret> name=<secret> duration=10 expires=nil source=nil\n"
            .. "auras in combat: none this session\n")
        and Has(reportB, "\nC_Secrets.ShouldAurasBeSecret() in combat = true\n")
        and Has(reportB, "\nin combat: helpful auras on you: 1, mana sources 1, secret names 0, secret rows 0\n")
        and Has(reportB, "\nin combat: aura 1 mana source: id=29166 name=Innervate duration=<secret> expires=<secret> source=<secret>\n"))

    check("T87: with none of the functions every new line reads absent, and nothing raises",
        okC == true
        and Has(reportC, "\nGetFileIDFromPath absent, C_Texture.GetAtlasInfo absent\n")
        and Has(reportC, "\nfile Interface\\\\Buttons\\\\WHITE8x8 id=<absent> set=nothing get=nothing\n")
        and Has(reportC, "\natlas Options_List_Hover <absent>\n")
        and Has(reportC, "\nEllesmereUI absent\n") and Has(reportC, "\nLibStub absent\n")
        and Has(reportC, "\nQ-clock-1 colour curve: C_CurveUtil.CreateColorCurve absent, CreateColor absent, UnitPowerPercent present\n")
        and Has(reportC, "\nQ-clock-3 ColorPickerFrame absent, SetupColorPickerAndShow absent, SetColorRGB absent\n")
        and Has(reportC, "\nGetSpellBaseCooldown(18562 Swiftmend) = <absent>\n")
        and Has(reportC, "\nbook cooldown: none")
        and Has(reportC, "\nUnitGetTotalAbsorbs(player) = <absent>\n"))

    check("T87: the new sections are ASCII with no bare pipe; the auras and absorb to-dos go once answered",
        type(reportA) == "string" and type(reportB) == "string" and type(reportC) == "string"
        and AsciiSafe(reportA) and AsciiSafe(reportB) and AsciiSafe(reportC)
        and Has(reportA, "\nauras to do: ") and Has(reportA, "\nabsorb to do: ")
        and not Has(reportB, "auras to do") and not Has(reportB, "absorb to do"))
end

-- T54 (P10, review Q8)
check("review Q8: every step's timers ran on the clock; none is left pending",
    #leftovers == 0, #leftovers > 0 and table.concat(leftovers, "; ") or nil)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
