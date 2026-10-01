-- tools/run.sh --flavour forever tools/consolecheck.lua
-- tools/run.sh --flavour tbc     tools/consolecheck.lua
--
-- T3: the error handler (Core_Forever.lua), the debug console's errors line
-- and conditional Regen test button (UI/DebugConsole.lua, shared), and
-- /st dump (UI/Dump_Forever.lua). Cases 1-6, 8, 9 and 11 share ONE session
-- (a fresh login), because case 6's dump has to see case 1's 340-count entry
-- and case 5's cap has to see cases 1 and 3's entries already there -- exactly
-- the way one game session would. Case 7 gets its own fresh dofile (its own
-- Facts: "so the 50-entry cap from 5 is not in the way"). Case 10 reads the
-- TOCs from disk and compares them with the version the session reported.
-- Case 12 is TBC's own session. The 2026-09-29 review added case 13
-- (the shared session: the Enable box on Forever, R15/R16) and cases 14-15
-- (their own session, last: the captured stack line and the forward, R22/R21).
-- T55 (P11, review A4) added cases 19-21 in 14-15's session: the same capture
-- and forward for a handler raising inside MD:On, now that Core.lua runs every
-- handler under xpcall, and the event's arguments reaching it -- 20 forever.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

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
local function NewSession()
    _G.SpellTunerDB = nil
    _G.ManaDemonDB = nil
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    return MD, _G.STUB
end

local function CountEq(list, needle)
    local n = 0
    for _, v in ipairs(list) do
        if v == needle then n = n + 1 end
    end
    return n
end

-- Every byte is 10 or printable ASCII, and no bare "|" survives removing "||"
-- -- the same rule tools/probecheck.lua's own AsciiSafe checks (kept as its
-- own copy here, same as UI/Dump_Forever.lua keeps its own Esc).
local function AsciiSafe(s)
    for i = 1, #s do
        local b = s:byte(i)
        if not (b == 10 or (b >= 32 and b <= 126)) then return false end
    end
    local stripped = s:gsub("||", "")
    return not stripped:find("|", 1, true)
end

local function UnderWindow(f, root)
    if not root then return false end
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end

-- Every font string/button text under `root`, GetText read through pcall
-- (a widget with no text just answers nothing).
local function StringsUnder(S, root)
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.GetText and UnderWindow(f, root) then
            local okText, text = pcall(f.GetText, f)
            if okText and type(text) == "string" and text ~= "" then
                out[#out + 1] = text
            end
        end
    end
    return out
end

local function AnyEquals(list, needle)
    for _, s in ipairs(list) do if s == needle then return true end end
    return false
end

local function AnyFind(list, pattern)
    for _, s in ipairs(list) do
        local a, b = s:find(pattern)
        if a then return true, s end
    end
    return false
end

local envFlavour = os.getenv("ST_FLAVOUR")
local flavour = (envFlavour ~= nil and envFlavour ~= "") and envFlavour or "forever"

local function InSpecial(name)
    for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
    return false
end

if flavour == "forever" then

local MD, S = NewSession()

-- T33: this session's frames record their strata, level, toplevel and points
-- (the stub's are no-ops), and UIParent is a 1920 x 1080 screen, so cases 16-18
-- can read where the console and the copy box were put. Installed on this
-- session's frame metatable only; case 7's fresh session does not have it.
do
    local FM = getmetatable(UIParent)
    FM.SetFrameStrata = function(self, s) self.strata = s end
    FM.GetFrameStrata = function(self) return self.strata or "MEDIUM" end
    FM.SetFrameLevel = function(self, l) self.level = l end
    FM.GetFrameLevel = function(self) return self.level or 1 end
    FM.SetToplevel = function(self, v) self.toplevel = v and true or false end
    FM.IsToplevel = function(self) return self.toplevel == true end
    FM.ClearAllPoints = function(self) self.points = {} end
    FM.SetPoint = function(self, p, rel, rp, x, y)
        self.points = self.points or {}
        self.points[#self.points + 1] = { p, rel, rp, x, y }
    end
    UIParent:SetSize(1920, 1080)
end

--------------------------------------------------------------------------------
-- 1: our error is recorded once, counted, and shown to the client once
--------------------------------------------------------------------------------
try("our error is recorded once, counted, and shown to the client once", function()
    local msg = "Interface/AddOns/SpellTuner/Core.lua:12: boom"
    for i = 1, 340 do S.errorHandler(msg) end
    check("our error is recorded once, counted, and shown to the client once",
        #MD.errors == 1 and MD.errors[1].count == 340 and MD.errorTotal == 340
        and MD.errors[1].msg == msg and CountEq(S.clientErrors, msg) == 1)
end)

--------------------------------------------------------------------------------
-- 2: another addon's error passes through every time and is not recorded
--------------------------------------------------------------------------------
try("another addon's error passes through every time and is not recorded", function()
    local msg = "Interface/AddOns/EllesmereUI/x.lua:1: nope"
    local before = #MD.errors
    for i = 1, 3 do S.errorHandler(msg) end
    check("another addon's error passes through every time and is not recorded",
        #MD.errors == before and CountEq(S.clientErrors, msg) == 3)
end)

--------------------------------------------------------------------------------
-- 3: a sibling module's error is ours
--------------------------------------------------------------------------------
try("a sibling module's error is ours", function()
    local msg = "Interface/AddOns/SpellTuner_Recorder/Module.lua:3: x"
    local before = #MD.errors
    S.errorHandler(msg)
    check("a sibling module's error is ours",
        #MD.errors == before + 1 and MD.errors[before + 1].msg == msg)
end)

--------------------------------------------------------------------------------
-- 4: the handler never raises, whatever it is given
--------------------------------------------------------------------------------
try("the handler never raises, whatever it is given", function()
    local beforeDistinct, beforeTotal = #MD.errors, MD.errorTotal
    local sentinelTable = {}
    local okA = pcall(S.errorHandler, S.Secret())
    local okB = pcall(S.errorHandler, nil)
    local okC = pcall(S.errorHandler, sentinelTable)
    local forwardedTable = false
    for _, m in ipairs(S.clientErrors) do if m == sentinelTable then forwardedTable = true end end
    check("the handler never raises, whatever it is given",
        okA and okB and okC and #MD.errors == beforeDistinct and MD.errorTotal == beforeTotal
        and forwardedTable)
end)

--------------------------------------------------------------------------------
-- 5: at most 50 distinct errors are kept, the rest counted
--------------------------------------------------------------------------------
try("at most 50 distinct errors are kept, the rest counted", function()
    -- Two distinct errors of ours already sit in MD.errors (cases 1 and 3).
    -- Bring the running total of DISTINCT messages of ours to 60.
    local startDistinct = #MD.errors
    local newMsgs = {}
    for i = 1, 60 - startDistinct do
        newMsgs[i] = string.format("Interface/AddOns/SpellTuner/Distinct%d.lua:1: boom", i)
        S.errorHandler(newMsgs[i])
    end
    local eachOnce = true
    for _, m in ipairs(newMsgs) do
        if CountEq(S.clientErrors, m) ~= 1 then eachOnce = false end
    end
    check("at most 50 distinct errors are kept, the rest counted",
        #MD.errors == 50 and MD.errorOverflow == 10 and eachOnce
        and CountEq(S.clientErrors, "Interface/AddOns/SpellTuner/Core.lua:12: boom") == 1
        and CountEq(S.clientErrors, "Interface/AddOns/SpellTuner_Recorder/Module.lua:3: x") == 1)
end)

--------------------------------------------------------------------------------
-- 6: /st dump shows one block with every section, in order
--------------------------------------------------------------------------------
local dumpText
try("/st dump shows one block with every section, in order", function()
    local capturedTitle
    local orig = MD.ShowCopyPopup
    MD.ShowCopyPopup = function(self, title, text) capturedTitle, dumpText = title, text end
    SlashCmdList.SPELLTUNER("dump")
    MD.ShowCopyPopup = orig

    -- T73 (P29, review U19): what a report is read for first -- the saved
    -- variables, the modules, the errors (the handler line with them) --
    -- then one capabilities summary, the whole table and the log last
    local order = { "== client", "== saved variables", "== modules", "== errors (",
                     "error handler: installed", "340x ", "== capabilities (", "\nabsent: ",
                     "forbidden events: COMBAT_LOG_EVENT_UNFILTERED", "== capability table (",
                     "\npresent ", "== debug log (" }
    local inOrder, pos = true, 0
    for _, h in ipairs(order) do
        local at = dumpText and dumpText:find(h, pos + 1, true)
        if not at then inOrder = false break end
        pos = at
    end

    check("/st dump shows one block with every section, in order",
        capturedTitle == "SpellTuner dump" and type(dumpText) == "string" and inOrder
        and dumpText:find("forbidden events: COMBAT_LOG_EVENT_UNFILTERED", 1, true) ~= nil
        and dumpText:find("error handler: installed", 1, true) ~= nil
        and dumpText:find("340x ", 1, true) ~= nil
        and dumpText:find("Recorder: ", 1, true) ~= nil
        and dumpText:find("SavedVariables: ", 1, true) ~= nil)
end)

--------------------------------------------------------------------------------
-- 8: /st debug opens the console, which counts the errors
--------------------------------------------------------------------------------
try("/st debug opens the console, which counts the errors", function()
    SlashCmdList.SPELLTUNER("debug")
    local root = _G.SpellTunerDebugConsole
    local shown = root and root:IsShown()
    local expected = string.format("Errors this session: %d distinct, %d total - /st dump copies them",
        #MD.errors, MD.errorTotal)
    local strings = StringsUnder(S, root)
    check("/st debug opens the console, which counts the errors",
        shown == true and AnyEquals(strings, expected))
end)

--------------------------------------------------------------------------------
-- 9: the Forever console has no Regen test button
--------------------------------------------------------------------------------
try("the Forever console has no Regen test button", function()
    local root = _G.SpellTunerDebugConsole
    local strings = StringsUnder(S, root)
    check("the Forever console has no Regen test button", not AnyEquals(strings, "Regen test"))
end)

--------------------------------------------------------------------------------
-- 13 (review R15/R16): ticking "Enable Debug Logging" on Forever writes its
-- header line and raises nothing -- the callback used to call
-- MD:TalentSummary, which only Core_TBC.lua defines
--------------------------------------------------------------------------------
try("the Forever console's Enable box logs its line and raises nothing", function()
    local root = _G.SpellTunerDebugConsole
    local box
    for _, f in ipairs(S.allFrames) do
        if f.onClick and f.label and UnderWindow(f, root) then
            local okText, text = pcall(f.label.GetText, f.label)
            if okText and text == "Enable Debug Logging" then box = f end
        end
    end
    local wasEnabled = MD.db.debug.enabled
    local clicked, err = false, nil
    if box then
        box:SetChecked(true)
        clicked, err = pcall(box:GetScript("OnClick"), box)
    end
    local tail = MD:DebugLogTail(20)
    local _, line = AnyFind(tail, "debug logging enabled %(v")
    MD.db.debug.enabled = wasEnabled
    local good = box ~= nil and clicked and line ~= nil and not line:find("talents", 1, true)
    check("the Forever console's Enable box logs its line and raises nothing", good,
        (not good) and tostring(err or line) or nil)
end)

--------------------------------------------------------------------------------
-- 16-18 (T33, docs/SPEC-forever-ui.md 6.2, 6.5): the console is a tool in
-- FULLSCREEN with one ESC stack entry and a remembered place; the copy box is
-- FULLSCREEN_DIALOG / 20, on the stack, and closes an open list
--------------------------------------------------------------------------------
try("the Forever console is FULLSCREEN / 10, toplevel, one stack entry, not a special frame", function()
    local root = _G.SpellTunerDebugConsole
    local stack = MD.Win and MD.Win.stack or {}
    local n = 0
    for _, e in ipairs(stack) do if e.frame == root then n = n + 1 end end
    check("the Forever console is FULLSCREEN / 10, toplevel, one stack entry, not a special frame",
        root and root:IsShown() and root:GetFrameStrata() == "FULLSCREEN" and root:GetFrameLevel() == 10
        and root:IsToplevel() and n == 1 and not InSpecial("SpellTunerDebugConsole"),
        root and (root:GetFrameStrata() .. "/" .. tostring(root:GetFrameLevel()) .. " entries " .. n) or "no console")
end)

try("the Forever console opens where it was left, not re-centred", function()
    local root = _G.SpellTunerDebugConsole
    root:Hide()
    MD.db.ui.win.console = { x = 300, y = 700 }
    MD:ToggleDebugConsole()
    local pts = root.points or {}
    local pt = pts[#pts] or {}
    check("the Forever console opens where it was left, not re-centred",
        root:IsShown() and #pts == 1 and pt[1] == "TOPLEFT" and pt[2] == UIParent and pt[3] == "BOTTOMLEFT"
        and pt[4] == 300 and pt[5] == 700,
        tostring(pt[1]) .. " " .. tostring(pt[3]) .. " " .. tostring(pt[4]) .. "," .. tostring(pt[5]))
end)

try("the copy box is FULLSCREEN_DIALOG / 20, on top of the stack, and closes an open list", function()
    local root = _G.SpellTunerDebugConsole
    local dd = MD.UI.CreateDropdown(root, 120, 18)
    dd:SetItems({ { id = 1, text = "one" } })
    dd:GetScript("OnClick")(dd)
    local listOpen = dd.list:IsShown()
    MD:ShowCopyPopup("T33", "text")
    local copy = _G.SpellTunerDebugCopyFrame
    local stack = MD.Win and MD.Win.stack or {}
    local top = stack[#stack] and stack[#stack].frame
    check("the copy box is FULLSCREEN_DIALOG / 20, on top of the stack, and closes an open list",
        listOpen and not dd.list:IsShown() and copy and copy:IsShown()
        and copy:GetFrameStrata() == "FULLSCREEN_DIALOG" and copy:GetFrameLevel() == 20 and top == copy,
        tostring(listOpen) .. " " .. tostring(dd.list:IsShown()) .. " "
        .. (copy and (copy:GetFrameStrata() .. "/" .. tostring(copy:GetFrameLevel())) or "no copy box"))
    if copy then copy:Hide() end
end)

--------------------------------------------------------------------------------
-- 10: every TOC carries the version the addon reports
--------------------------------------------------------------------------------
try("every TOC carries the version the addon reports", function()
    -- The TOCs are listed from disk, never by hand. MD.version is what the
    -- forever session read through C_AddOns.GetAddOnMetadata, not a value this
    -- test read itself.
    local files = {}
    local p = io.popen("cd \"" .. ROOT .. "\" && ls SpellTuner*.toc Modules/*/*.toc 2>/dev/null")
    if p then
        for line in p:lines() do files[#files + 1] = line end
        p:close()
    end
    table.sort(files)
    local function VersionLines(rel)
        local found = {}
        local f = io.open(ROOT .. "/" .. rel, "r")
        if not f then return found end
        for line in f:lines() do
            local v = line:gsub("\r$", ""):match("^## Version: (.*)$")
            if v then found[#found + 1] = v end
        end
        f:close()
        return found
    end
    local reported = MD.version
    local allOk, detail = true, nil
    if #files ~= 9 then
        allOk, detail = false, "found " .. #files .. " TOCs, not 9"
    elseif type(reported) ~= "string" or reported == "" then
        allOk, detail = false, "the addon reports no version"
    else
        for _, f in ipairs(files) do
            local v = VersionLines(f)
            if #v ~= 1 then
                allOk, detail = false, f .. " has " .. #v .. " Version lines"
                break
            elseif v[1] ~= reported then
                allOk, detail = false, f .. " is " .. v[1] .. ", the addon reports " .. reported
                break
            end
        end
    end
    check("every TOC carries the version the addon reports", allOk, detail)
end)

--------------------------------------------------------------------------------
-- 11: nothing registers the combat log
--------------------------------------------------------------------------------
try("nothing registers the combat log", function()
    local attempted = false
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == "COMBAT_LOG_EVENT_UNFILTERED" then attempted = true end
        end
    end
    check("nothing registers the combat log",
        not attempted and #(S.forbidden or {}) == 0 and next(S.forbidden or {}) == nil)
end)

--------------------------------------------------------------------------------
-- 7: the dump is ASCII with no bare pipe, whatever the errors said
--
-- Run LAST among the forever cases, after everything that still needs the
-- shared session's globals (SlashCmdList.SPELLTUNER, CreateFrame's frame
-- registry): a fresh dofile of tools/harness.lua reloads tools/wowstub.lua,
-- which reassigns those globals to the fresh session's own versions -- fine
-- for the fresh MD2/S2 pair used here, but it would silently redirect every
-- later "SlashCmdList.SPELLTUNER(...)" call and frame creation in THIS file
-- at the outer MD if this ran any earlier than last.
--------------------------------------------------------------------------------
try("the dump is ASCII with no bare pipe, whatever the errors said", function()
    local MD2, S2 = NewSession()
    local msg = "Interface/AddOns/SpellTuner/Core.lua:5: |cffff0000bad" .. string.char(195, 169) .. "value"
    S2.errorHandler(msg)

    local capturedText
    local orig = MD2.ShowCopyPopup
    MD2.ShowCopyPopup = function(self, title, text) capturedText = text end
    SlashCmdList.SPELLTUNER("dump")
    MD2.ShowCopyPopup = orig

    check("the dump is ASCII with no bare pipe, whatever the errors said",
        type(capturedText) == "string" and AsciiSafe(capturedText)
        and capturedText:find("||cffff0000", 1, true) ~= nil
        and capturedText:find("\\195\\169", 1, true) ~= nil)
end)

--------------------------------------------------------------------------------
-- 14-15 (review R22, R21): the handler on a real stack. Each error is raised
-- by a function here under xpcall with the installed handler as its error
-- function -- the way the client calls it, with the frame that raised still
-- on the stack -- and tools/wowstub.lua's debugstack reads that stack.
-- Their own fresh session, after case 7's, for the same reason case 7 has one.
--------------------------------------------------------------------------------
local MD3, S3
try("the captured stack line names the code that raised", function()
    MD3, S3 = NewSession()
    local raisedAt
    local function Raise()
        raisedAt = debug.getinfo(1, "l").currentline; error("Interface/AddOns/SpellTuner/Boom.lua:7: boom", 0)
    end
    xpcall(Raise, S3.errorHandler)
    local entry = MD3.errors[#MD3.errors]
    local stack = entry and entry.stack
    local good = type(stack) == "string" and raisedAt ~= nil
        and stack:find("consolecheck.lua:" .. raisedAt .. ":", 1, true) ~= nil
    check("the captured stack line names the code that raised", good,
        (not good) and tostring(stack) or nil)
end)

-- R21: whatever the handler passes on reaches the previous handler with no
-- SpellTuner frame and no pcall between it and the code that raised (Blizzard's
-- and BugGrabber's handlers read the stack and locals at fixed levels).
try("the previous handler sees no SpellTuner frame and no pcall above the raise", function()
    local function Between(raiser)
        -- The stub's default handler appends to S3.clientErrors; a proxy
        -- there walks the stack at that moment: level 2 is the previous
        -- handler, everything after it up to `raiser` sits between.
        local found, bad, real = false, {}, S3.clientErrors
        S3.clientErrors = setmetatable({}, { __newindex = function(t, k, v)
            rawset(t, k, v)
            local l = 3
            while true do
                local info = debug.getinfo(l, "Sf")
                if not info then break end
                if info.func == raiser then found = true break end
                if info.func == pcall or info.func == xpcall then
                    bad[#bad + 1] = "pcall"
                elseif info.source and (info.source:find("Core_Forever.lua", 1, true)
                                        or info.source:find("API.lua", 1, true)) then
                    bad[#bad + 1] = info.short_src
                end
                l = l + 1
            end
        end })
        xpcall(raiser, S3.errorHandler)
        for _, m in ipairs(S3.clientErrors) do real[#real + 1] = m end
        S3.clientErrors = real
        return found, bad
    end
    local function Other() error("Interface/AddOns/EllesmereUI/x.lua:1: nope", 0) end
    local function Ours() error("Interface/AddOns/SpellTuner/Fresh.lua:2: new", 0) end
    local foundA, badA = Between(Other)
    local foundB, badB = Between(Ours)
    local good = foundA and foundB and #badA == 0 and #badB == 0
    check("the previous handler sees no SpellTuner frame and no pcall above the raise", good,
        (not good) and (tostring(foundA) .. " " .. tostring(foundB) .. ": "
            .. table.concat(badA, ",") .. " / " .. table.concat(badB, ",")) or nil)
end)

--------------------------------------------------------------------------------
-- 19-21 (T55, P11, review A4): the same capture, now that Core.lua runs every
-- event handler under xpcall with MD.ErrorSink. A handler raising inside
-- MD:On -- fired the way the client fires an event -- must still be named by
-- its own file and line (not Core.lua's loop or sink, Client/API.lua or a C
-- frame), reach the previous handler exactly once over two firings, and have
-- received the event's arguments (the client's xpcall passes them). Same
-- session as 14-15.
--------------------------------------------------------------------------------
local DISPATCH_MSG = "Interface/AddOns/SpellTuner/Dispatched.lua:3: raised in a handler"
local dispatchLine, dispatchArgs, dispatchAfter, dispatchFired = nil, nil, 0, {}
try("a handler raising inside MD:On is named by its own line (A4, R22)", function()
    local armed = true
    MD3:On("UNIT_COMBAT", function(...)
        if not armed then return end
        dispatchArgs = { n = select("#", ...), ... }
        dispatchLine = debug.getinfo(1, "l").currentline; error(DISPATCH_MSG, 0)
    end)
    MD3:On("UNIT_COMBAT", function() if armed then dispatchAfter = dispatchAfter + 1 end end)
    dispatchFired[1] = pcall(S3.Fire, "UNIT_COMBAT", "player", "HEAL", "", 120, 1)
    dispatchFired[2] = pcall(S3.Fire, "UNIT_COMBAT", "player", "HEAL", "", 120, 1)
    armed = false
    local entry
    for _, e in ipairs(MD3.errors) do
        if e.msg == DISPATCH_MSG then entry = e end
    end
    local stack = entry and entry.stack
    local good = type(stack) == "string" and dispatchLine ~= nil
        and stack:find("consolecheck.lua:" .. dispatchLine .. ":", 1, true) ~= nil
        and not stack:find("Core.lua", 1, true) and not stack:find("API.lua", 1, true)
        and not stack:find("[C]", 1, true)
        and entry.count == 2
    check("a handler raising inside MD:On is named by its own line (A4, R22)", good,
        (not good) and (tostring(stack) .. " count=" .. tostring(entry and entry.count)) or nil)
end)

try("the previous handler gets a dispatched error exactly once (A4, R21)", function()
    local forwarded = CountEq(S3.clientErrors, DISPATCH_MSG)
    check("the previous handler gets a dispatched error exactly once (A4, R21)",
        forwarded == 1 and dispatchFired[1] == true and dispatchFired[2] == true
        and dispatchAfter == 2,
        "forwarded=" .. forwarded .. " fired=" .. tostring(dispatchFired[1]) .. "/"
            .. tostring(dispatchFired[2]) .. " after=" .. dispatchAfter)
end)

try("a handler under xpcall receives the event's arguments (A4)", function()
    local a = dispatchArgs
    check("a handler under xpcall receives the event's arguments (A4)",
        a ~= nil and a.n == 5 and a[1] == "player" and a[2] == "HEAL" and a[3] == ""
        and a[4] == 120 and a[5] == 1,
        a and ("n=" .. tostring(a.n)) or "never called")
end)

else -- tbc

--------------------------------------------------------------------------------
-- 12: TBC installs no error handler and keeps its Regen test button
--------------------------------------------------------------------------------
try("TBC installs no error handler and keeps its Regen test button", function()
    local MD = NewSession()
    local S = _G.STUB
    S.Load({ "UI/Style.lua", "UI/DebugConsole.lua" }, "SpellTuner", MD)
    MD:ToggleDebugConsole()
    local root = _G.SpellTunerDebugConsole
    local strings = StringsUnder(S, root)
    -- T33: and its console keeps its own UISpecialFrames entry (no window
    -- manager on TBC, so no ESC stack)
    check("TBC installs no error handler and keeps its Regen test button",
        MD.errors == nil and AnyEquals(strings, "Regen test")
        and MD.Win == nil and InSpecial("SpellTunerDebugConsole"))
end)

end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
