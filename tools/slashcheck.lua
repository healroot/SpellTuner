-- tools/run.sh tools/slashcheck.lua [--print | --golden]
--
-- T61 (P17, review A1): a golden transcript of EVERY TBC slash verb and alias
-- under the stub. Core_TBC.lua's hand-kept MD.COMMANDS list and its 100-line
-- MD.SlashFallback if-chain became MD:AddCommand registrations (Core.lua's
-- registry, the one Forever already used); this suite is what proves the move
-- changed nothing a player sees. The golden at the bottom was captured on the
-- parent commit (8c4cc93), before the first edit, with `--golden`, and every
-- verb's chat lines, the functions it called and the settings it changed must
-- equal it line for line. `--print` shows the transcript as it would read.
--
-- What is recorded per verb:
--   * every chat line (the addon's version string replaced by {version});
--   * every call into the functions the verbs reach -- the dashboard, the
--     options, the widget, the practice panel, the diagnostics, the simulator,
--     the replay, the run recorder, the debug console -- as "call MD:Name(args)".
--     They are replaced by spies: what those functions then do is other suites'
--     business (tools/verifycheck.lua runs the diagnostics for real);
--   * every account setting a verb touched, as "db.key: before -> after".
-- Two passes: first with the spies in place (every branch reaches its callee),
-- then with every one of those functions ABSENT (each verb's guard: a TBC
-- build without the UI must still answer every verb without raising).
-- A last section loads UI/Settings.lua (UI/Options_About.lua until T119) and
-- reads back the command rows the About page paints, which were MD.COMMANDS
-- and are now MD:Commands().
-- T94: the TBC line has a `ui` verb now (`/md ui style <name>`, created by
-- UI/Styles.lua through MD:AddSubcommand); the golden was re-based for it.
HARNESS_FLAVOUR = "tbc"

local here = arg[0]:match("^(.*)/[^/]+$")
local mode = "check"
for i = 2, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")

-- T87 (docs/SPEC-next.md decision 22): Client/Probe.lua is on the TBC line, the
-- TOC's last file. Until SpellTuner_TBC.toc lists it, it is loaded here where
-- the TOC will put it, so the transcript below is the one the TBC client gets:
-- /md probe a hidden row, the help and the About tab unchanged.
do
    local listed = false
    for _, rel in ipairs(S.loadedFiles or {}) do if rel == "Client/Probe.lua" then listed = true end end
    if not listed then S.Load({ "Client/Probe.lua" }, "SpellTuner", MD) end
end

-- T94 (docs/SPEC-next.md 2.5, 5.4): UI/Styles.lua registers `ui style` with
-- MD:AddSubcommand, which on TBC (no `ui` verb of its own) creates `/md ui`.
-- The TBC harness drops UI/ files, so the kit, the theme and the registry are
-- loaded here as SpellTuner_TBC.toc lists them (UI/Styles.lua right after
-- UI/Theme_Flat.lua), and CORE_LOGIN, which ran before them, runs again so
-- the saved style is applied as at a login. The golden below is re-based for
-- the new verb: its help and About row, and the five `ui` lines in VERBS.
do
    local listed = false
    for _, rel in ipairs(S.loadedFiles or {}) do if rel == "UI/Styles.lua" then listed = true end end
    if not listed then
        S.Load({ "UI/Style.lua", "UI/Theme_Flat.lua", "UI/Styles.lua" }, "SpellTuner", MD)
        MD:Fire("CORE_LOGIN")
    end
end

-- T102 (docs/SPEC-next.md 2.5, 7.4): UI/ClockSettings.lua registers `clock
-- layout`, `clock look` and `clock preview` with MD:AddSubcommand, which on
-- TBC (no `clock` verb of its own) creates `/md clock`. It is loaded here as
-- SpellTuner_TBC.toc lists it (after UI/ClockView.lua and UI/Widget.lua, which
-- the harness drops too: the renderer is loaded, the widget is not, so
-- `/md clock preview` says the clock is not loaded). The golden below is
-- re-based for the new verb: its help and About row, and the seven `clock`
-- lines in VERBS (no verb whose answer lists the layouts: T104's ring changes
-- that list).
do
    local listed = false
    for _, rel in ipairs(S.loadedFiles or {}) do if rel == "UI/ClockSettings.lua" then listed = true end end
    if not listed then
        local f = io.open((S.root or ".") .. "/UI/ClockSettings.lua", "r")
        if f then
            f:close()
            S.Load({ "UI/ClockView.lua", "UI/ClockSettings.lua" }, "SpellTuner", MD)
        end
    end
end

local out = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out + 1] = m end }
MD.db.debug = MD.db.debug or {}
MD.db.debug.enabled = false

-- A value as Lua source: quotes, backslashes, tabs and every other control or
-- high byte escaped, so an editor cannot eat a tab or a trailing space.
local function Quote(s)
    return '"' .. s:gsub('[%c"\\\128-\255]', function(ch)
        if ch == "\t" then return "\\t" end
        if ch == '"' or ch == "\\" then return "\\" .. ch end
        return string.format("\\%03d", ch:byte())
    end) .. '"'
end

local function Show(v)
    local t = type(v)
    if t == "string" then return Quote(v) end
    if t == "table" then
        -- a position is four plain values; anything else is named by its type
        if #v == 4 and type(v[1]) == "string" then
            return "{" .. Quote(v[1]) .. "," .. Quote(tostring(v[2])) .. "," .. tostring(v[3]) .. "," .. tostring(v[4]) .. "}"
        end
        return "<table>"
    end
    return tostring(v)
end

--------------------------------------------------------------------------------
-- The spies: every function a TBC verb reaches.
--------------------------------------------------------------------------------
local SPIED = {
    "ToggleDashboard", "ShowDashboard", "SelectView", "ShowOptionsFrame",
    "UpdateVisibility", "ApplyWidgetPosition", "OpenPractice", "ToggleBindings",
    "RunVerify", "RunProfile", "RunExport", "RunCalibrate", "RunFSRTest",
    "RunRegenTest", "RunSpamTest", "RunSimRun", "RunSimReplay", "RunCoach",
    "ToggleSimWindow", "ToggleReplay", "RunCommand", "RunCoachRun",
    "ToggleDebugConsole", "ForceWidgetPreview",
}
local calls = {}
local function InstallSpies()
    for _, name in ipairs(SPIED) do
        MD[name] = function(self, ...)
            local shown = {}
            for i = 1, select("#", ...) do shown[i] = Show((select(i, ...))) end
            calls[#calls + 1] = "call MD:" .. name .. "(" .. table.concat(shown, ", ") .. ")"
        end
    end
end
local function RemoveSpies()
    for _, name in ipairs(SPIED) do MD[name] = nil end
end

-- The settings the verbs write.
local WATCHED = { "locked", "pos", "muted", "drinkReminder", "showRest", "spellTooltip",
                  "widgetTooltip", "halfLife" }
local function Snapshot()
    local s = {}
    for _, k in ipairs(WATCHED) do s[k] = Show(MD.db[k]) end
    s.practiceSetup = Show(MD.cdb.practiceSetup ~= nil)
    return s
end

--------------------------------------------------------------------------------
-- The verbs. Every TBC verb and alias, the arguments each branch reads, the
-- toggles twice (so the second pass starts where the first began), mixed case
-- and padding (the dispatcher lower-cases the verb, keeps the raw tail).
--------------------------------------------------------------------------------
local VERBS = {
    "", "help",
    "options", "config", "settings",
    "lock", "unlock", "reset",
    "mute", "mute", "drink", "drink", "rest", "rest",
    "practice", "practice start", "practice Start",
    "binds", "bindings",
    "spelltip", "spelltip",
    "tooltip", "tip",
    "window 30", "window 5", "window 60", "window 4", "window 61", "window abc", "window",
    "verify", "profile", "export", "calibrate", "calib",
    "fsrtest", "regentest", "regentest 45", "regentest clear", "spamtest",
    "simrun", "simreplay", "simreplay fixture", "simreplay 2",
    "coach", "coach 1 force", "coach cancel",
    "sim",
    "replay", "replay 2:7 force", "replay run 2",
    "run start Blood Furnace", "run status", "run stop",
    "coachrun", "coachrun 1",
    "debug",
    "ui", "ui style", "ui style flat", "ui style Nosuch", "ui reset",
    "clock", "Clock Layout Bar", "clock layout compact", "clock layout line", "clock look",
    "clock look reset", "clock preview",
    "nosuch", "  MUTE  ", "Mute", "RUN Start The Underbog",
}

local version = MD.version or "dev"
local function Plain(s, find, repl)
    local i, j = s:find(find, 1, true)
    while i do
        s = s:sub(1, i - 1) .. repl .. s:sub(j + 1)
        i, j = s:find(find, i + #repl, true)
    end
    return s
end

local transcript = {}
local function Pass(label)
    for _, verb in ipairs(VERBS) do
        out, calls = {}, {}
        local before = Snapshot()
        local ran, err = pcall(SlashCmdList.SPELLTUNER, verb)
        local after = Snapshot()
        local lines = {}
        for _, l in ipairs(out) do lines[#lines + 1] = Plain(l, version, "{version}") end
        for _, c in ipairs(calls) do lines[#lines + 1] = c end
        for _, k in ipairs(WATCHED) do
            if before[k] ~= after[k] then lines[#lines + 1] = "db." .. k .. ": " .. before[k] .. " -> " .. after[k] end
        end
        if before.practiceSetup ~= after.practiceSetup then
            lines[#lines + 1] = "cdb.practiceSetup: " .. before.practiceSetup .. " -> " .. after.practiceSetup
        end
        if not ran then lines[#lines + 1] = "RAISED " .. tostring(err) end
        transcript[#transcript + 1] = { cmd = label .. " /md " .. verb, lines = lines }
    end
end

InstallSpies()
Pass("spied")
RemoveSpies()
Pass("bare")

--------------------------------------------------------------------------------
-- The About tab's command rows (UI/Options_About.lua), painted under the stub.
--------------------------------------------------------------------------------
-- T119 (SPEC-one-ui 7, re-based): the About page is UI/Settings.lua's on both
-- lines, built from TBC's MD.SettingsLine (UI/Settings_TBC.lua). Each row is
-- read as its usage, then its whole text -- the row shows the text up to its
-- first "; " and the hover the whole (tooltips[2]) -- so the golden's lines are
-- the ones the old tab painted, unchanged.
do
    S.Load({ "UI/Style.lua", "UI/Settings.lua", "UI/Settings_TBC.lua" }, "SpellTuner", MD)
    local content = CreateFrame("Frame", nil, UIParent)
    content:SetSize(736, 520)
    local p = MD.Settings.Build("about", content)
    local lines = {}
    for i = 1, p.shown do
        local r = p.rows[i]
        lines[#lines + 1] = r.usage:GetText()
        lines[#lines + 1] = (r.tooltips and r.tooltips[2]) or r.text:GetText()
    end
    transcript[#transcript + 1] = { cmd = "about tab rows", lines = lines }
end

if mode == "print" then
    for _, t in ipairs(transcript) do
        print("== " .. t.cmd .. " (" .. #t.lines .. ")")
        for _, l in ipairs(t.lines) do print(l) end
    end
    os.exit(0)
end

if mode == "golden" then
    print("local GOLDEN = {")
    for _, t in ipairs(transcript) do
        print("    { cmd = " .. Quote(t.cmd) .. ", lines = {")
        for _, l in ipairs(t.lines) do print("        " .. Quote(l) .. ",") end
        print("    } },")
    end
    print("}")
    os.exit(0)
end

--------------------------------------------------------------------------------
-- Compare
--------------------------------------------------------------------------------
local function Compare(GOLDEN)
    T.section("the golden transcript (captured on 8c4cc93, re-based by T94 for /md ui style, by T102 for /md clock)")
    T.check("the golden has every verb of both passes and the About rows", #GOLDEN == #transcript,
        string.format("%d entries, golden %d", #transcript, #GOLDEN))
    local mismatches = {}
    for i, t in ipairs(transcript) do
        local g = GOLDEN[i] or { cmd = "?", lines = {} }
        local detail
        if g.cmd ~= t.cmd then
            detail = "golden is for " .. g.cmd
        else
            for k = 1, math.max(#g.lines, #t.lines) do
                if g.lines[k] ~= t.lines[k] then
                    detail = string.format("line %d of %d (golden %d): now %s, golden %s",
                        k, #t.lines, #g.lines, t.lines[k] and Quote(t.lines[k]) or "(none)",
                        g.lines[k] and Quote(g.lines[k]) or "(none)")
                    break
                end
            end
        end
        if detail then mismatches[#mismatches + 1] = t.cmd .. ": " .. detail end
    end
    -- one assertion per group, so a regression names the verb and the line
    local groups = {
        { "the spied pass: every verb's lines, calls and settings as on the parent", "^spied " },
        { "the bare pass: every verb's guard as on the parent", "^bare " },
        { "the About tab's command rows as on the parent", "^about " },
    }
    for _, g in ipairs(groups) do
        local first, n = nil, 0
        for _, m in ipairs(mismatches) do
            if m:find(g[2]) then n = n + 1; first = first or m end
        end
        T.check(g[1], n == 0, first and (n .. " differ; first: " .. first))
    end

    T.section("what the transcript says")
    local seenRaise, anyEmpty = nil, nil
    local helpRows
    for _, t in ipairs(transcript) do
        for _, l in ipairs(t.lines) do
            if l:find("^RAISED ") then seenRaise = seenRaise or (t.cmd .. ": " .. l) end
        end
        if t.cmd == "spied /md help" then helpRows = #t.lines end
    end
    for _, t in ipairs(transcript) do
        if t.cmd:find("^spied ") and t.cmd ~= "spied /md " and #t.lines == 0 then anyEmpty = anyEmpty or t.cmd end
    end
    T.check("no verb raised, in either pass", seenRaise == nil, seenRaise)
    T.check("every verb but the bare one answers something with the spies in place", anyEmpty == nil, anyEmpty)
    local allAscii, why = true, nil
    for _, t in ipairs(transcript) do
        for _, l in ipairs(t.lines) do
            if not l:find("^call ") and not l:find("^db%.") and not l:find("^cdb%.") then
                local okA, w = T.Ascii(l)
                if not okA then allAscii, why = false, t.cmd .. ": " .. w end
            end
        end
    end
    T.check("every chat line and About row is ASCII with no bare pipe", allAscii, why)
    T.check("the help is its heading and 29 rows (T94: /md ui style; T102: /md clock)", helpRows == 30,
        helpRows ~= 30 and (tostring(helpRows) .. " lines") or nil)

    T.section("T87: the probe on the TBC line")
    local probeRow
    for _, c in ipairs(MD:Commands()) do if c.name == "probe" then probeRow = c end end
    T.check("/md probe is registered as a hidden row (the help and About rows above are unchanged)",
        probeRow ~= nil and probeRow.hidden == true and probeRow.usage == "/st probe")
    out = {}
    local ran = pcall(SlashCmdList.SPELLTUNER, "probe")
    local said = false
    for _, l in ipairs(out) do if l:find("SpellTuner probe: build ", 1, true) then said = true end end
    T.check("/md probe runs the probe and says so in one chat line", ran and said)
    T.done()
end

--------------------------------------------------------------------------------
-- The golden: `tools/run.sh tools/slashcheck.lua --golden` on 8c4cc93, pasted.
-- T94 re-based it (docs/SPEC-next.md 2.5, 5.4): the one new row
-- `/st ui style <name>` in both helps (and in every pass that prints the help:
-- the bare verb aside, `nosuch`), the five `ui` verbs, two About lines; every
-- other line equal to the 8c4cc93 golden (compared with --print before and
-- after the edit). T102 re-based it the same way (docs/SPEC-next.md 2.5, 7.4):
-- the new row `/st clock layout <name> / look reset / preview` in both helps
-- and `nosuch`'s, the seven `clock` verbs of each pass, two About lines; every
-- other line equal to the T94 golden (compared with --print before and
-- after the edit).
--------------------------------------------------------------------------------
local GOLDEN = {
    { cmd = "spied /md ", lines = {
        "call MD:ToggleDashboard()",
    } },
    { cmd = "spied /md help", lines = {
        "|cff9966ffSpellTuner:|r commands:",
        "|cff9966ffSpellTuner:|r   |cffffff00/st|r - toggle the rank dashboard",
        "|cff9966ffSpellTuner:|r   |cffffff00/st options|r - open the settings window",
        "|cff9966ffSpellTuner:|r   |cffffff00/st lock, unlock|r - lock / unlock (drag) the OOM widget",
        "|cff9966ffSpellTuner:|r   |cffffff00/st reset|r - reset the widget position",
        "|cff9966ffSpellTuner:|r   |cffffff00/st mute|r - toggle alert messages",
        "|cff9966ffSpellTuner:|r   |cffffff00/st drink|r - toggle the drink reminder",
        "|cff9966ffSpellTuner:|r   |cffffff00/st rest|r - toggle the 'rest' segment (time to full if you stop casting)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st tooltip|r - hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st binds|r - what each key and mouse button casts in practice; import from Cell or Clique",
        "|cff9966ffSpellTuner:|r   |cffffff00/st practice|r - heal a fight you play and get it back as a recording (start: play the saved setup now)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spelltip|r - heal values on the game's spell tooltips (bars, spellbook); Shift for the maths",
        "|cff9966ffSpellTuner:|r   |cffffff00/st window N|r - spend estimator half-life in seconds (5-60, default 15)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st verify|r - check static spell data against the live client",
        "|cff9966ffSpellTuner:|r   |cffffff00/st profile|r - copyable dump of every model input - use this for bug reports",
        "|cff9966ffSpellTuner:|r   |cffffff00/st export|r - fights, overheal and roster as tab-separated text, for analysis",
        "|cff9966ffSpellTuner:|r   |cffffff00/st calibrate|r - the model against every heal you landed: ratio per spell and event kind",
        "|cff9966ffSpellTuner:|r   |cffffff00/st fsrtest|r - log mana ticks for 15s (five-second-rule anchor test)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st regentest [N or clear]|r - idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spamtest|r - arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simrun|r - self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simreplay [n]|r - replay recorded fight n (or the BF-1 fixture) and score it against the log",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coach [n]|r - search for a better plan on recorded fight n and show the card (cancel stops it)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st sim|r - simulation window: build a fight and find the cheapest plan that holds it",
        "|cff9966ffSpellTuner:|r   |cffffff00/st replay [n] [force]|r - play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay",
        "|cff9966ffSpellTuner:|r   |cffffff00/st run start / stop / status|r - record a whole dungeon: every pull and the gaps between them",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coachrun [n]|r - coach a recorded RUN: one plan and a drink policy for the whole dungeon",
        "|cff9966ffSpellTuner:|r   |cffffff00/st debug|r - toggle the debug console (enable logging there, Copy to export)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st ui style <name>|r - the look of SpellTuner's windows (no name: list the styles)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st clock layout <name> / look reset / preview|r - the mana clock's layout (Settings -> Clock shows each); every clock colour and bar setting back to the look's own; the clock on screen for 60 s, to see or move it",
    } },
    { cmd = "spied /md options", lines = {
        "call MD:ShowOptionsFrame()",
    } },
    { cmd = "spied /md config", lines = {
        "call MD:ShowOptionsFrame()",
    } },
    { cmd = "spied /md settings", lines = {
        "call MD:ShowOptionsFrame()",
    } },
    { cmd = "spied /md lock", lines = {
        "|cff9966ffSpellTuner:|r widget locked.",
        "call MD:UpdateVisibility()",
    } },
    { cmd = "spied /md unlock", lines = {
        "|cff9966ffSpellTuner:|r widget unlocked - drag it, then /md lock.",
        "call MD:UpdateVisibility()",
        "db.locked: true -> false",
    } },
    { cmd = "spied /md reset", lines = {
        "|cff9966ffSpellTuner:|r widget position reset.",
        "call MD:ApplyWidgetPosition()",
    } },
    { cmd = "spied /md mute", lines = {
        "|cff9966ffSpellTuner:|r alerts muted.",
        "db.muted: false -> true",
    } },
    { cmd = "spied /md mute", lines = {
        "|cff9966ffSpellTuner:|r alerts unmuted.",
        "db.muted: true -> false",
    } },
    { cmd = "spied /md drink", lines = {
        "|cff9966ffSpellTuner:|r drink reminder off.",
        "db.drinkReminder: true -> false",
    } },
    { cmd = "spied /md drink", lines = {
        "|cff9966ffSpellTuner:|r drink reminder on.",
        "db.drinkReminder: false -> true",
    } },
    { cmd = "spied /md rest", lines = {
        "|cff9966ffSpellTuner:|r rest segment off.",
        "db.showRest: true -> false",
    } },
    { cmd = "spied /md rest", lines = {
        "|cff9966ffSpellTuner:|r rest segment on.",
        "db.showRest: false -> true",
    } },
    { cmd = "spied /md practice", lines = {
        "call MD:ShowDashboard()",
        "call MD:SelectView(\"simulate\", \"practice\")",
    } },
    { cmd = "spied /md practice start", lines = {
        "call MD:OpenPractice(<table>, nil)",
        "cdb.practiceSetup: false -> true",
    } },
    { cmd = "spied /md practice Start", lines = {
        "call MD:OpenPractice(<table>, nil)",
    } },
    { cmd = "spied /md binds", lines = {
        "call MD:ToggleBindings()",
    } },
    { cmd = "spied /md bindings", lines = {
        "call MD:ToggleBindings()",
    } },
    { cmd = "spied /md spelltip", lines = {
        "|cff9966ffSpellTuner:|r spell tooltips: off.",
        "db.spellTooltip: true -> false",
    } },
    { cmd = "spied /md spelltip", lines = {
        "|cff9966ffSpellTuner:|r spell tooltips: on - hover a heal on your bars or in the spellbook; hold Shift for the maths.",
        "db.spellTooltip: false -> true",
    } },
    { cmd = "spied /md tooltip", lines = {
        "|cff9966ffSpellTuner:|r floating clock: tooltip off - it takes no mouse input at all now, so it neither pops a tooltip nor swallows clicks in its rectangle, and it is still draggable while unlocked. The minimap button and the ElvUI datatexts keep theirs.",
        "call MD:UpdateVisibility()",
        "db.widgetTooltip: true -> false",
    } },
    { cmd = "spied /md tip", lines = {
        "|cff9966ffSpellTuner:|r floating clock: tooltip on - hovering shows the breakdown, left-click opens the dashboard.",
        "call MD:UpdateVisibility()",
        "db.widgetTooltip: false -> true",
    } },
    { cmd = "spied /md window 30", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 30s.",
        "db.halfLife: 15 -> 30",
    } },
    { cmd = "spied /md window 5", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 5s.",
        "db.halfLife: 30 -> 5",
    } },
    { cmd = "spied /md window 60", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 60s.",
        "db.halfLife: 5 -> 60",
    } },
    { cmd = "spied /md window 4", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "spied /md window 61", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "spied /md window abc", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "spied /md window", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "spied /md verify", lines = {
        "call MD:RunVerify()",
    } },
    { cmd = "spied /md profile", lines = {
        "call MD:RunProfile()",
    } },
    { cmd = "spied /md export", lines = {
        "call MD:RunExport()",
    } },
    { cmd = "spied /md calibrate", lines = {
        "call MD:RunCalibrate()",
    } },
    { cmd = "spied /md calib", lines = {
        "call MD:RunCalibrate()",
    } },
    { cmd = "spied /md fsrtest", lines = {
        "call MD:RunFSRTest()",
    } },
    { cmd = "spied /md regentest", lines = {
        "call MD:RunRegenTest(nil)",
    } },
    { cmd = "spied /md regentest 45", lines = {
        "call MD:RunRegenTest(\"45\")",
    } },
    { cmd = "spied /md regentest clear", lines = {
        "call MD:RunRegenTest(\"clear\")",
    } },
    { cmd = "spied /md spamtest", lines = {
        "call MD:RunSpamTest()",
    } },
    { cmd = "spied /md simrun", lines = {
        "call MD:RunSimRun()",
    } },
    { cmd = "spied /md simreplay", lines = {
        "call MD:RunSimReplay(\"\")",
    } },
    { cmd = "spied /md simreplay fixture", lines = {
        "call MD:RunSimReplay(\"fixture\")",
    } },
    { cmd = "spied /md simreplay 2", lines = {
        "call MD:RunSimReplay(\"2\")",
    } },
    { cmd = "spied /md coach", lines = {
        "call MD:RunCoach(\"\")",
    } },
    { cmd = "spied /md coach 1 force", lines = {
        "call MD:RunCoach(\"1 force\")",
    } },
    { cmd = "spied /md coach cancel", lines = {
        "call MD:RunCoach(\"cancel\")",
    } },
    { cmd = "spied /md sim", lines = {
        "call MD:ToggleSimWindow()",
    } },
    { cmd = "spied /md replay", lines = {
        "call MD:ToggleReplay(\"\")",
    } },
    { cmd = "spied /md replay 2:7 force", lines = {
        "call MD:ToggleReplay(\"2:7 force\")",
    } },
    { cmd = "spied /md replay run 2", lines = {
        "call MD:ToggleReplay(\"run 2\")",
    } },
    { cmd = "spied /md run start Blood Furnace", lines = {
        "call MD:RunCommand(\"start Blood Furnace\")",
    } },
    { cmd = "spied /md run status", lines = {
        "call MD:RunCommand(\"status\")",
    } },
    { cmd = "spied /md run stop", lines = {
        "call MD:RunCommand(\"stop\")",
    } },
    { cmd = "spied /md coachrun", lines = {
        "call MD:RunCoachRun(\"\")",
    } },
    { cmd = "spied /md coachrun 1", lines = {
        "call MD:RunCoachRun(\"1\")",
    } },
    { cmd = "spied /md debug", lines = {
        "call MD:ToggleDebugConsole()",
    } },
    { cmd = "spied /md ui", lines = {
        "|cff9966ffSpellTuner:|r usage: /st ui style <name>",
    } },
    { cmd = "spied /md ui style", lines = {
        "|cff9966ffSpellTuner:|r style: flat (styles: flat)",
    } },
    { cmd = "spied /md ui style flat", lines = {
        "|cff9966ffSpellTuner:|r style: flat - Flat",
    } },
    { cmd = "spied /md ui style Nosuch", lines = {
        "|cff9966ffSpellTuner:|r unknown style 'nosuch' (styles: flat)",
    } },
    { cmd = "spied /md ui reset", lines = {
        "|cff9966ffSpellTuner:|r usage: /st ui style <name>",
    } },
    { cmd = "spied /md clock", lines = {
        "|cff9966ffSpellTuner:|r usage: /st clock layout <name>",
        "|cff9966ffSpellTuner:|r usage: /st clock look reset",
        "|cff9966ffSpellTuner:|r usage: /st clock preview",
    } },
    { cmd = "spied /md Clock Layout Bar", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout bar",
    } },
    { cmd = "spied /md clock layout compact", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout compact",
    } },
    { cmd = "spied /md clock layout line", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout line",
    } },
    { cmd = "spied /md clock look", lines = {
        "|cff9966ffSpellTuner:|r usage: /st clock look reset",
    } },
    { cmd = "spied /md clock look reset", lines = {
        "|cff9966ffSpellTuner:|r mana clock: every colour and bar setting back to the look's own",
    } },
    { cmd = "spied /md clock preview", lines = {
        "|cff9966ffSpellTuner:|r mana clock: not loaded",
    } },
    { cmd = "spied /md nosuch", lines = {
        "|cff9966ffSpellTuner:|r commands:",
        "|cff9966ffSpellTuner:|r   |cffffff00/st|r - toggle the rank dashboard",
        "|cff9966ffSpellTuner:|r   |cffffff00/st options|r - open the settings window",
        "|cff9966ffSpellTuner:|r   |cffffff00/st lock, unlock|r - lock / unlock (drag) the OOM widget",
        "|cff9966ffSpellTuner:|r   |cffffff00/st reset|r - reset the widget position",
        "|cff9966ffSpellTuner:|r   |cffffff00/st mute|r - toggle alert messages",
        "|cff9966ffSpellTuner:|r   |cffffff00/st drink|r - toggle the drink reminder",
        "|cff9966ffSpellTuner:|r   |cffffff00/st rest|r - toggle the 'rest' segment (time to full if you stop casting)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st tooltip|r - hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st binds|r - what each key and mouse button casts in practice; import from Cell or Clique",
        "|cff9966ffSpellTuner:|r   |cffffff00/st practice|r - heal a fight you play and get it back as a recording (start: play the saved setup now)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spelltip|r - heal values on the game's spell tooltips (bars, spellbook); Shift for the maths",
        "|cff9966ffSpellTuner:|r   |cffffff00/st window N|r - spend estimator half-life in seconds (5-60, default 15)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st verify|r - check static spell data against the live client",
        "|cff9966ffSpellTuner:|r   |cffffff00/st profile|r - copyable dump of every model input - use this for bug reports",
        "|cff9966ffSpellTuner:|r   |cffffff00/st export|r - fights, overheal and roster as tab-separated text, for analysis",
        "|cff9966ffSpellTuner:|r   |cffffff00/st calibrate|r - the model against every heal you landed: ratio per spell and event kind",
        "|cff9966ffSpellTuner:|r   |cffffff00/st fsrtest|r - log mana ticks for 15s (five-second-rule anchor test)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st regentest [N or clear]|r - idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spamtest|r - arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simrun|r - self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simreplay [n]|r - replay recorded fight n (or the BF-1 fixture) and score it against the log",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coach [n]|r - search for a better plan on recorded fight n and show the card (cancel stops it)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st sim|r - simulation window: build a fight and find the cheapest plan that holds it",
        "|cff9966ffSpellTuner:|r   |cffffff00/st replay [n] [force]|r - play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay",
        "|cff9966ffSpellTuner:|r   |cffffff00/st run start / stop / status|r - record a whole dungeon: every pull and the gaps between them",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coachrun [n]|r - coach a recorded RUN: one plan and a drink policy for the whole dungeon",
        "|cff9966ffSpellTuner:|r   |cffffff00/st debug|r - toggle the debug console (enable logging there, Copy to export)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st ui style <name>|r - the look of SpellTuner's windows (no name: list the styles)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st clock layout <name> / look reset / preview|r - the mana clock's layout (Settings -> Clock shows each); every clock colour and bar setting back to the look's own; the clock on screen for 60 s, to see or move it",
    } },
    { cmd = "spied /md   MUTE  ", lines = {
        "|cff9966ffSpellTuner:|r alerts muted.",
        "db.muted: false -> true",
    } },
    { cmd = "spied /md Mute", lines = {
        "|cff9966ffSpellTuner:|r alerts unmuted.",
        "db.muted: true -> false",
    } },
    { cmd = "spied /md RUN Start The Underbog", lines = {
        "call MD:RunCommand(\"Start The Underbog\")",
    } },
    { cmd = "bare /md ", lines = {
    } },
    { cmd = "bare /md help", lines = {
        "|cff9966ffSpellTuner:|r commands:",
        "|cff9966ffSpellTuner:|r   |cffffff00/st|r - toggle the rank dashboard",
        "|cff9966ffSpellTuner:|r   |cffffff00/st options|r - open the settings window",
        "|cff9966ffSpellTuner:|r   |cffffff00/st lock, unlock|r - lock / unlock (drag) the OOM widget",
        "|cff9966ffSpellTuner:|r   |cffffff00/st reset|r - reset the widget position",
        "|cff9966ffSpellTuner:|r   |cffffff00/st mute|r - toggle alert messages",
        "|cff9966ffSpellTuner:|r   |cffffff00/st drink|r - toggle the drink reminder",
        "|cff9966ffSpellTuner:|r   |cffffff00/st rest|r - toggle the 'rest' segment (time to full if you stop casting)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st tooltip|r - hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st binds|r - what each key and mouse button casts in practice; import from Cell or Clique",
        "|cff9966ffSpellTuner:|r   |cffffff00/st practice|r - heal a fight you play and get it back as a recording (start: play the saved setup now)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spelltip|r - heal values on the game's spell tooltips (bars, spellbook); Shift for the maths",
        "|cff9966ffSpellTuner:|r   |cffffff00/st window N|r - spend estimator half-life in seconds (5-60, default 15)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st verify|r - check static spell data against the live client",
        "|cff9966ffSpellTuner:|r   |cffffff00/st profile|r - copyable dump of every model input - use this for bug reports",
        "|cff9966ffSpellTuner:|r   |cffffff00/st export|r - fights, overheal and roster as tab-separated text, for analysis",
        "|cff9966ffSpellTuner:|r   |cffffff00/st calibrate|r - the model against every heal you landed: ratio per spell and event kind",
        "|cff9966ffSpellTuner:|r   |cffffff00/st fsrtest|r - log mana ticks for 15s (five-second-rule anchor test)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st regentest [N or clear]|r - idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spamtest|r - arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simrun|r - self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simreplay [n]|r - replay recorded fight n (or the BF-1 fixture) and score it against the log",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coach [n]|r - search for a better plan on recorded fight n and show the card (cancel stops it)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st sim|r - simulation window: build a fight and find the cheapest plan that holds it",
        "|cff9966ffSpellTuner:|r   |cffffff00/st replay [n] [force]|r - play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay",
        "|cff9966ffSpellTuner:|r   |cffffff00/st run start / stop / status|r - record a whole dungeon: every pull and the gaps between them",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coachrun [n]|r - coach a recorded RUN: one plan and a drink policy for the whole dungeon",
        "|cff9966ffSpellTuner:|r   |cffffff00/st debug|r - toggle the debug console (enable logging there, Copy to export)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st ui style <name>|r - the look of SpellTuner's windows (no name: list the styles)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st clock layout <name> / look reset / preview|r - the mana clock's layout (Settings -> Clock shows each); every clock colour and bar setting back to the look's own; the clock on screen for 60 s, to see or move it",
    } },
    { cmd = "bare /md options", lines = {
    } },
    { cmd = "bare /md config", lines = {
    } },
    { cmd = "bare /md settings", lines = {
    } },
    { cmd = "bare /md lock", lines = {
        "|cff9966ffSpellTuner:|r widget locked.",
        "db.locked: false -> true",
    } },
    { cmd = "bare /md unlock", lines = {
        "|cff9966ffSpellTuner:|r widget unlocked - drag it, then /md lock.",
        "db.locked: true -> false",
    } },
    { cmd = "bare /md reset", lines = {
        "|cff9966ffSpellTuner:|r widget position reset.",
    } },
    { cmd = "bare /md mute", lines = {
        "|cff9966ffSpellTuner:|r alerts muted.",
        "db.muted: false -> true",
    } },
    { cmd = "bare /md mute", lines = {
        "|cff9966ffSpellTuner:|r alerts unmuted.",
        "db.muted: true -> false",
    } },
    { cmd = "bare /md drink", lines = {
        "|cff9966ffSpellTuner:|r drink reminder off.",
        "db.drinkReminder: true -> false",
    } },
    { cmd = "bare /md drink", lines = {
        "|cff9966ffSpellTuner:|r drink reminder on.",
        "db.drinkReminder: false -> true",
    } },
    { cmd = "bare /md rest", lines = {
        "|cff9966ffSpellTuner:|r rest segment off.",
        "db.showRest: true -> false",
    } },
    { cmd = "bare /md rest", lines = {
        "|cff9966ffSpellTuner:|r rest segment on.",
        "db.showRest: false -> true",
    } },
    { cmd = "bare /md practice", lines = {
    } },
    { cmd = "bare /md practice start", lines = {
    } },
    { cmd = "bare /md practice Start", lines = {
    } },
    { cmd = "bare /md binds", lines = {
    } },
    { cmd = "bare /md bindings", lines = {
    } },
    { cmd = "bare /md spelltip", lines = {
        "|cff9966ffSpellTuner:|r spell tooltips: off.",
        "db.spellTooltip: true -> false",
    } },
    { cmd = "bare /md spelltip", lines = {
        "|cff9966ffSpellTuner:|r spell tooltips: on - hover a heal on your bars or in the spellbook; hold Shift for the maths.",
        "db.spellTooltip: false -> true",
    } },
    { cmd = "bare /md tooltip", lines = {
        "|cff9966ffSpellTuner:|r floating clock: tooltip off - it takes no mouse input at all now, so it neither pops a tooltip nor swallows clicks in its rectangle, and it is still draggable while unlocked. The minimap button and the ElvUI datatexts keep theirs.",
        "db.widgetTooltip: true -> false",
    } },
    { cmd = "bare /md tip", lines = {
        "|cff9966ffSpellTuner:|r floating clock: tooltip on - hovering shows the breakdown, left-click opens the dashboard.",
        "db.widgetTooltip: false -> true",
    } },
    { cmd = "bare /md window 30", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 30s.",
        "db.halfLife: 60 -> 30",
    } },
    { cmd = "bare /md window 5", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 5s.",
        "db.halfLife: 30 -> 5",
    } },
    { cmd = "bare /md window 60", lines = {
        "|cff9966ffSpellTuner:|r spend half-life set to 60s.",
        "db.halfLife: 5 -> 60",
    } },
    { cmd = "bare /md window 4", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "bare /md window 61", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "bare /md window abc", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "bare /md window", lines = {
        "|cff9966ffSpellTuner:|r usage: /md window N (5-60 seconds)",
    } },
    { cmd = "bare /md verify", lines = {
    } },
    { cmd = "bare /md profile", lines = {
    } },
    { cmd = "bare /md export", lines = {
    } },
    { cmd = "bare /md calibrate", lines = {
    } },
    { cmd = "bare /md calib", lines = {
    } },
    { cmd = "bare /md fsrtest", lines = {
    } },
    { cmd = "bare /md regentest", lines = {
    } },
    { cmd = "bare /md regentest 45", lines = {
    } },
    { cmd = "bare /md regentest clear", lines = {
    } },
    { cmd = "bare /md spamtest", lines = {
    } },
    { cmd = "bare /md simrun", lines = {
    } },
    { cmd = "bare /md simreplay", lines = {
    } },
    { cmd = "bare /md simreplay fixture", lines = {
    } },
    { cmd = "bare /md simreplay 2", lines = {
    } },
    { cmd = "bare /md coach", lines = {
    } },
    { cmd = "bare /md coach 1 force", lines = {
    } },
    { cmd = "bare /md coach cancel", lines = {
    } },
    { cmd = "bare /md sim", lines = {
    } },
    { cmd = "bare /md replay", lines = {
    } },
    { cmd = "bare /md replay 2:7 force", lines = {
    } },
    { cmd = "bare /md replay run 2", lines = {
    } },
    { cmd = "bare /md run start Blood Furnace", lines = {
    } },
    { cmd = "bare /md run status", lines = {
    } },
    { cmd = "bare /md run stop", lines = {
    } },
    { cmd = "bare /md coachrun", lines = {
    } },
    { cmd = "bare /md coachrun 1", lines = {
    } },
    { cmd = "bare /md debug", lines = {
    } },
    { cmd = "bare /md ui", lines = {
        "|cff9966ffSpellTuner:|r usage: /st ui style <name>",
    } },
    { cmd = "bare /md ui style", lines = {
        "|cff9966ffSpellTuner:|r style: flat (styles: flat)",
    } },
    { cmd = "bare /md ui style flat", lines = {
        "|cff9966ffSpellTuner:|r style: flat - Flat",
    } },
    { cmd = "bare /md ui style Nosuch", lines = {
        "|cff9966ffSpellTuner:|r unknown style 'nosuch' (styles: flat)",
    } },
    { cmd = "bare /md ui reset", lines = {
        "|cff9966ffSpellTuner:|r usage: /st ui style <name>",
    } },
    { cmd = "bare /md clock", lines = {
        "|cff9966ffSpellTuner:|r usage: /st clock layout <name>",
        "|cff9966ffSpellTuner:|r usage: /st clock look reset",
        "|cff9966ffSpellTuner:|r usage: /st clock preview",
    } },
    { cmd = "bare /md Clock Layout Bar", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout bar",
    } },
    { cmd = "bare /md clock layout compact", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout compact",
    } },
    { cmd = "bare /md clock layout line", lines = {
        "|cff9966ffSpellTuner:|r mana clock: layout line",
    } },
    { cmd = "bare /md clock look", lines = {
        "|cff9966ffSpellTuner:|r usage: /st clock look reset",
    } },
    { cmd = "bare /md clock look reset", lines = {
        "|cff9966ffSpellTuner:|r mana clock: every colour and bar setting back to the look's own",
    } },
    { cmd = "bare /md clock preview", lines = {
        "|cff9966ffSpellTuner:|r mana clock: not loaded",
    } },
    { cmd = "bare /md nosuch", lines = {
        "|cff9966ffSpellTuner:|r commands:",
        "|cff9966ffSpellTuner:|r   |cffffff00/st|r - toggle the rank dashboard",
        "|cff9966ffSpellTuner:|r   |cffffff00/st options|r - open the settings window",
        "|cff9966ffSpellTuner:|r   |cffffff00/st lock, unlock|r - lock / unlock (drag) the OOM widget",
        "|cff9966ffSpellTuner:|r   |cffffff00/st reset|r - reset the widget position",
        "|cff9966ffSpellTuner:|r   |cffffff00/st mute|r - toggle alert messages",
        "|cff9966ffSpellTuner:|r   |cffffff00/st drink|r - toggle the drink reminder",
        "|cff9966ffSpellTuner:|r   |cffffff00/st rest|r - toggle the 'rest' segment (time to full if you stop casting)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st tooltip|r - hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st binds|r - what each key and mouse button casts in practice; import from Cell or Clique",
        "|cff9966ffSpellTuner:|r   |cffffff00/st practice|r - heal a fight you play and get it back as a recording (start: play the saved setup now)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spelltip|r - heal values on the game's spell tooltips (bars, spellbook); Shift for the maths",
        "|cff9966ffSpellTuner:|r   |cffffff00/st window N|r - spend estimator half-life in seconds (5-60, default 15)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st verify|r - check static spell data against the live client",
        "|cff9966ffSpellTuner:|r   |cffffff00/st profile|r - copyable dump of every model input - use this for bug reports",
        "|cff9966ffSpellTuner:|r   |cffffff00/st export|r - fights, overheal and roster as tab-separated text, for analysis",
        "|cff9966ffSpellTuner:|r   |cffffff00/st calibrate|r - the model against every heal you landed: ratio per spell and event kind",
        "|cff9966ffSpellTuner:|r   |cffffff00/st fsrtest|r - log mana ticks for 15s (five-second-rule anchor test)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st regentest [N or clear]|r - idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st spamtest|r - arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simrun|r - self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st simreplay [n]|r - replay recorded fight n (or the BF-1 fixture) and score it against the log",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coach [n]|r - search for a better plan on recorded fight n and show the card (cancel stops it)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st sim|r - simulation window: build a fight and find the cheapest plan that holds it",
        "|cff9966ffSpellTuner:|r   |cffffff00/st replay [n] [force]|r - play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay",
        "|cff9966ffSpellTuner:|r   |cffffff00/st run start / stop / status|r - record a whole dungeon: every pull and the gaps between them",
        "|cff9966ffSpellTuner:|r   |cffffff00/st coachrun [n]|r - coach a recorded RUN: one plan and a drink policy for the whole dungeon",
        "|cff9966ffSpellTuner:|r   |cffffff00/st debug|r - toggle the debug console (enable logging there, Copy to export)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st ui style <name>|r - the look of SpellTuner's windows (no name: list the styles)",
        "|cff9966ffSpellTuner:|r   |cffffff00/st clock layout <name> / look reset / preview|r - the mana clock's layout (Settings -> Clock shows each); every clock colour and bar setting back to the look's own; the clock on screen for 60 s, to see or move it",
    } },
    { cmd = "bare /md   MUTE  ", lines = {
        "|cff9966ffSpellTuner:|r alerts muted.",
        "db.muted: false -> true",
    } },
    { cmd = "bare /md Mute", lines = {
        "|cff9966ffSpellTuner:|r alerts unmuted.",
        "db.muted: true -> false",
    } },
    { cmd = "bare /md RUN Start The Underbog", lines = {
    } },
    { cmd = "about tab rows", lines = {
        "/st",
        "toggle the rank dashboard",
        "/st options",
        "open the settings window",
        "/st lock, unlock",
        "lock / unlock (drag) the OOM widget",
        "/st reset",
        "reset the widget position",
        "/st mute",
        "toggle alert messages",
        "/st drink",
        "toggle the drink reminder",
        "/st rest",
        "toggle the 'rest' segment (time to full if you stop casting)",
        "/st tooltip",
        "hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)",
        "/st binds",
        "what each key and mouse button casts in practice; import from Cell or Clique",
        "/st practice",
        "heal a fight you play and get it back as a recording (start: play the saved setup now)",
        "/st spelltip",
        "heal values on the game's spell tooltips (bars, spellbook); Shift for the maths",
        "/st window N",
        "spend estimator half-life in seconds (5-60, default 15)",
        "/st verify",
        "check static spell data against the live client",
        "/st profile",
        "copyable dump of every model input - use this for bug reports",
        "/st export",
        "fights, overheal and roster as tab-separated text, for analysis",
        "/st calibrate",
        "the model against every heal you landed: ratio per spell and event kind",
        "/st fsrtest",
        "log mana ticks for 15s (five-second-rule anchor test)",
        "/st regentest [N or clear]",
        "idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)",
        "/st spamtest",
        "arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column",
        "/st simrun",
        "self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)",
        "/st simreplay [n]",
        "replay recorded fight n (or the BF-1 fixture) and score it against the log",
        "/st coach [n]",
        "search for a better plan on recorded fight n and show the card (cancel stops it)",
        "/st sim",
        "simulation window: build a fight and find the cheapest plan that holds it",
        "/st replay [n] [force]",
        "play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay",
        "/st run start / stop / status",
        "record a whole dungeon: every pull and the gaps between them",
        "/st coachrun [n]",
        "coach a recorded RUN: one plan and a drink policy for the whole dungeon",
        "/st debug",
        "toggle the debug console (enable logging there, Copy to export)",
        "/st ui style <name>",
        "the look of SpellTuner's windows (no name: list the styles)",
        "/st clock layout <name> / look reset / preview",
        "the mana clock's layout (Settings -> Clock shows each); every clock colour and bar setting back to the look's own; the clock on screen for 60 s, to see or move it",
    } },
}
Compare(GOLDEN)
