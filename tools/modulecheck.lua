-- tools/run.sh tools/modulecheck.lua
--
-- T2: the module registry (Core.lua), the three declared modules
-- (Core_Forever.lua), the three LoadOnDemand sibling folders (Modules/), and
-- the Forever window with its Settings -> Modules pane (UI/Dashboard_Forever.lua).
-- Each acceptance point gets its own fresh session (a fresh dofile of
-- tools/harness.lua, which re-dofiles tools/wowstub.lua too) where isolation
-- matters -- a module once loaded stays loaded for the life of that MD/S pair,
-- the same way it would for the life of a game session.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function try(name, body)
    local runOk, err = pcall(body)
    if not runOk then check(name, false, "raised: " .. tostring(err)) end
end

-- A fresh SpellTuner + fresh stub, exactly as a fresh login would see it.
-- presetDB, if given, becomes the SavedVariables the client hands back BEFORE
-- PLAYER_LOGIN fires (harness.lua fires it itself, synchronously, inside this
-- dofile) -- the only way to test "loads at login" honestly.
local function NewSession(presetDB)
    _G.SpellTunerDB = presetDB
    _G.ManaDemonDB = nil
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    return MD, _G.STUB
end

-- Captures chat lines for the life of body(), the way corecheck/adaptercheck
-- do: patch AddMessage on the EXISTING DEFAULT_CHAT_FRAME table (MD.API.Print
-- reads the global fresh on every call, never through Has's cache -- T1b).
local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

local function ChatHas(lines, needle)
    for _, l in ipairs(lines) do
        if type(l) == "string" and l:find(needle, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- 1: three modules are declared, in dependency order
--------------------------------------------------------------------------------
try("three modules are declared, in dependency order", function()
    local MD = NewSession()
    local m = MD.modules
    check("three modules are declared, in dependency order",
        type(m) == "table" and #m == 3
        and m[1].name == "SpellTuner_Recorder" and #m[1].needs == 0
        and m[2].name == "SpellTuner_Replay" and #m[2].needs == 1
            and m[2].needs[1] == "SpellTuner_Recorder"
        and m[3].name == "SpellTuner_Practice" and #m[3].needs == 1
            and m[3].needs[1] == "SpellTuner_Replay")
end)

--------------------------------------------------------------------------------
-- 2: a module that is off is never loaded
--------------------------------------------------------------------------------
try("a module that is off is never loaded", function()
    local MD, S = NewSession()
    check("a module that is off is never loaded",
        #S.loadAddOnCalls == 0
        and MD:ModuleState("SpellTuner_Recorder") == "off"
        and MD:ModuleState("SpellTuner_Replay") == "off"
        and MD:ModuleState("SpellTuner_Practice") == "off")
end)

--------------------------------------------------------------------------------
-- 3: switching a module on loads it now and remembers it
--------------------------------------------------------------------------------
try("switching a module on loads it now and remembers it", function()
    local MD, S = NewSession()
    local lines = CapturedChat(function() MD:SetModule("SpellTuner_Recorder", true) end)
    check("switching a module on loads it now and remembers it",
        MD.db.modules.SpellTuner_Recorder == true
        and MD:ModuleState("SpellTuner_Recorder") == "loaded"
        and ChatHas(lines, "Recorder: loaded"))
end)

--------------------------------------------------------------------------------
-- 4: switching on a module switches on what it needs, first
--------------------------------------------------------------------------------
try("switching on a module switches on what it needs, first", function()
    local MD, S = NewSession()
    MD:SetModule("SpellTuner_Practice", true)
    check("switching on a module switches on what it needs, first",
        #S.loadAddOnCalls == 3
        and S.loadAddOnCalls[1] == "SpellTuner_Recorder"
        and S.loadAddOnCalls[2] == "SpellTuner_Replay"
        and S.loadAddOnCalls[3] == "SpellTuner_Practice"
        and MD:ModuleState("SpellTuner_Recorder") == "loaded"
        and MD:ModuleState("SpellTuner_Replay") == "loaded"
        and MD:ModuleState("SpellTuner_Practice") == "loaded")
end)

--------------------------------------------------------------------------------
-- 5: switching off a module switches off what needs it, and says so
--------------------------------------------------------------------------------
try("switching off a module switches off what needs it and says it unloads at the next reload", function()
    local MD, S = NewSession()
    MD:SetModule("SpellTuner_Practice", true)
    local before = #S.loadAddOnCalls
    local lines = CapturedChat(function() MD:SetModule("SpellTuner_Recorder", false) end)
    check("switching off a module switches off what needs it and says it unloads at the next reload",
        MD:ModuleState("SpellTuner_Recorder") == "unloads"
        and MD:ModuleState("SpellTuner_Replay") == "unloads"
        and MD:ModuleState("SpellTuner_Practice") == "unloads"
        and ChatHas(lines, "Recorder: off - unloads at your next /reload")
        and #S.loadAddOnCalls == before)
end)

--------------------------------------------------------------------------------
-- 6: a module that is on loads at login
--------------------------------------------------------------------------------
try("a module that is on loads at login", function()
    local MD, S = NewSession({ modules = { SpellTuner_Recorder = true } })
    check("a module that is on loads at login",
        MD:ModuleState("SpellTuner_Recorder") == "loaded"
        and MD:ModuleState("SpellTuner_Replay") == "off"
        and MD:ModuleState("SpellTuner_Practice") == "off"
        and #S.loadAddOnCalls == 1 and S.loadAddOnCalls[1] == "SpellTuner_Recorder")
end)

--------------------------------------------------------------------------------
-- 7: a module that cannot load says why
--------------------------------------------------------------------------------
try("a module that cannot load says why", function()
    local MD, S = NewSession()
    S.addOnDisabled.SpellTuner_Replay = true
    local lines = CapturedChat(function() MD:SetModule("SpellTuner_Replay", true) end)
    local state, reason = MD:ModuleState("SpellTuner_Replay")
    check("a module that cannot load says why",
        state == "failed" and reason == "DISABLED"
        and ChatHas(lines, "Replay: on, could not load (DISABLED)"))
end)

--------------------------------------------------------------------------------
-- 8: each sibling is a LoadOnDemand Forever addon that depends on SpellTuner
--------------------------------------------------------------------------------
try("each sibling is a LoadOnDemand Forever addon that depends on SpellTuner", function()
    local ROOT = arg[1] or "."
    local SIBLINGS = {
        { name = "SpellTuner_Recorder", need = nil },
        { name = "SpellTuner_Replay", need = "SpellTuner_Recorder" },
        { name = "SpellTuner_Practice", need = "SpellTuner_Replay" },
    }
    local function Slurp(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local t = f:read("*a")
        f:close()
        return t
    end
    local function TocEntries(text)
        local entries = {}
        for line in text:gmatch("[^\n]+") do
            line = line:gsub("\r$", "")
            if line:match("%S") and line:sub(1, 1) ~= "#" then
                entries[#entries + 1] = line
            end
        end
        return entries
    end
    local allGood = true
    for _, s in ipairs(SIBLINGS) do
        local dir = ROOT .. "/Modules/" .. s.name
        local mainline = Slurp(dir .. "/" .. s.name .. "_Mainline.toc")
        local plain = Slurp(dir .. "/" .. s.name .. ".toc")
        if mainline == nil or plain == nil or mainline ~= plain then allGood = false end
        if mainline then
            if not mainline:match("## Interface: 16001") then allGood = false end
            if not mainline:match("## LoadOnDemand: 1") then allGood = false end
            local deps = mainline:match("## Dependencies:%s*([^\r\n]+)")
            if not deps or not deps:match("^SpellTuner") then allGood = false end
            if s.need and not deps:find(s.need, 1, true) then allGood = false end
            local entries = TocEntries(mainline)
            if not (#entries == 1 and entries[1] == "Module.lua") then allGood = false end
        end
    end
    check("each sibling is a LoadOnDemand Forever addon that depends on SpellTuner", allGood)
end)

-- A pane is an ordinary frame with a custom .rows field (UI/Dashboard_Forever.lua's
-- own bookkeeping, not a stub feature) -- found the same way tools/dashui.lua
-- finds a named button, by walking every frame the stub ever created.
local function FindModulesPane(S)
    for _, f in ipairs(S.allFrames) do
        if type(f.rows) == "table" and f.rows.SpellTuner_Recorder then return f end
    end
    return nil
end
local function ButtonNamed(S, text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text then return f end
    end
    return nil
end

--------------------------------------------------------------------------------
-- 9: /st opens the window, /st again closes it
--------------------------------------------------------------------------------
try("/st opens the window, /st again closes it", function()
    local MD, S = NewSession()
    SlashCmdList.SPELLTUNER("")
    local frame = _G.SpellTunerDashboard
    local shownAfterOpen = frame and frame:IsShown()
    local hasSpells = ButtonNamed(S, "Spells") ~= nil
    local hasSettings = ButtonNamed(S, "Settings") ~= nil
    SlashCmdList.SPELLTUNER("")
    local shownAfterClose = frame and frame:IsShown()
    check("/st opens the window, /st again closes it",
        frame ~= nil and shownAfterOpen == true and hasSpells and hasSettings
        and shownAfterClose == false)
end)

--------------------------------------------------------------------------------
-- 10: the Modules pane switches a module and shows its state
--------------------------------------------------------------------------------
try("the Modules pane switches a module and shows its state", function()
    local MD, S = NewSession()
    MD:SelectView("settings", "modules")
    local pane = FindModulesPane(S)
    local rows = pane and pane.rows
    local hasThreeRows = rows ~= nil and rows.SpellTuner_Recorder ~= nil
        and rows.SpellTuner_Replay ~= nil and rows.SpellTuner_Practice ~= nil
    local recorderLoaded, replayOff = false, false
    if hasThreeRows then
        rows.SpellTuner_Recorder.check.onClick(true, rows.SpellTuner_Recorder.check)
        recorderLoaded = rows.SpellTuner_Recorder.state:GetText() == "loaded"
        replayOff = rows.SpellTuner_Replay.state:GetText() == "off"
    end
    check("the Modules pane switches a module and shows its state",
        hasThreeRows and recorderLoaded and replayOff)
end)

--------------------------------------------------------------------------------
-- 11: every string the window renders is ASCII with no bare pipe
--
-- Re-issue 1 (lead, 2026-09-28): walk EVERY font string and button text whose
-- parentFrame chain reaches SpellTunerDashboard itself -- the whole window,
-- title and nav buttons included, both panes built first so they are in the
-- tree -- with exactly one named exception: UI/Style.lua's own header close
-- button, whose label is the literal multiplication sign "\195\151"
-- (U+00D7). That glyph predates this task, is shared by every Cell-style
-- window in the tree (including TBC's accepted UI/Dashboard.lua), and
-- UI/Style.lua's Facts restrict this task to "Line 20 only. Nothing else
-- changes." -- so it is allowed by exact byte match, not by narrowing the
-- walk. A frame is "under" the window when its parentFrame chain reaches
-- _G.SpellTunerDashboard -- the stub tracks child->parent, not the other
-- way, so there is no cheaper way to ask "what did this window paint".
--------------------------------------------------------------------------------
local CLOSE_GLYPH = "\195\151" -- UI/Style.lua:166, the shared kit's "x" close button; see Review

local function UnderWindow(f, root)
    if not root then return false end
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end

try("every string the window renders is ASCII with no bare pipe", function()
    local MD, S = NewSession()
    MD:SelectView("spells", "book")
    MD:SelectView("settings", "modules")
    local root = _G.SpellTunerDashboard
    local bad
    local reached, titleCount, navButtonCount = 0, 0, 0
    for _, f in ipairs(S.allFrames) do
        if f.GetText and UnderWindow(f, root) then
            local okText, text = pcall(f.GetText, f)
            if okText and type(text) == "string" and text ~= "" then
                reached = reached + 1
                if text == "SpellTuner" then titleCount = titleCount + 1 end
                if text == "Spells" or text == "Settings" then navButtonCount = navButtonCount + 1 end
                if text == CLOSE_GLYPH then
                    -- the one named exception (UI/Style.lua:166, Review)
                elseif not bad then
                    for i = 1, #text do
                        if text:byte(i) > 126 then bad = "non-ascii in " .. text; break end
                    end
                    if not bad then
                        -- a bare pipe is a single "|" not part of an escaped "||"
                        -- or a colour code ("|cAARRGGBB" ... "|r")
                        local stripped = text:gsub("||", "")
                        stripped = stripped:gsub("|c%x%x%x%x%x%x%x%x", "")
                        stripped = stripped:gsub("|r", "")
                        if stripped:find("|") then bad = "bare pipe in " .. text end
                    end
                end
            end
        end
    end
    io.write(string.format(
        "  (assertion 11 walk: %d strings reached under the window, title seen %d time(s), nav buttons seen %d time(s))\n",
        reached, titleCount, navButtonCount))
    check("every string the window renders is ASCII with no bare pipe", bad == nil, bad)
end)

--------------------------------------------------------------------------------
-- 12: nothing on the Forever TOC or in a sibling registers the combat log
--------------------------------------------------------------------------------
try("nothing on the Forever TOC or in a sibling registers the combat log", function()
    local MD, S = NewSession()
    local fn = function() end
    MD:On("COMBAT_LOG_EVENT_UNFILTERED", fn)
    SlashCmdList.SPELLTUNER("")
    MD:SelectView("settings", "modules")
    MD:SetModule("SpellTuner_Practice", true)
    SlashCmdList.SPELLTUNER("")
    local attempted = false
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "COMBAT_LOG_EVENT_UNFILTERED" then attempted = true end
        end
    end
    check("nothing on the Forever TOC or in a sibling registers the combat log",
        not attempted and #(S.forbidden or {}) == 0 and next(S.forbidden or {}) == nil)
end)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
