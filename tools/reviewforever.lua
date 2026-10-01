-- tools/run.sh tools/reviewforever.lua
--
-- T16b (docs/tasks/T16b-review-tab.md): the Review tab in the Forever window
-- -- a Reports group with a Review view, a placeholder saying how to switch
-- the Replay module on while it is off, the real tab (UI/Dashboard_Review.lua,
-- shared with TBC) once it is on: rows for the v3 recordings
-- (tools/foreverfixture.lua), the row tooltip carrying the Forever gates
-- (T14), Coach refusing/forcing and Play opening the replay window (T16a).
-- Forever only, on two tools/foreverfixture.lua streams (one clean, one whose
-- meter drifts past the calibration limit -- here, no meter reading at all).
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-95s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
-- T71: UI/ContextMenu.lua is a main-TOC file (an integrator line); loaded
-- here when the TOC the harness read does not list it yet
if not MD.UI.CreateContextMenu then S.Load({ "UI/ContextMenu.lua" }, "SpellTuner", MD) end

local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

--------------------------------------------------------------------------------
-- helpers shared with tools/reviewui.lua's own reading-the-screen pattern
--------------------------------------------------------------------------------
local function Rows()
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.cells and f.shown and f.cells.n then out[#out + 1] = f end
    end
    return out
end
local function CellText(row, key)
    local t = row.cells[key] and row.cells[key]:GetText() or ""
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function ButtonNamed(text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false then return f end
    end
    return nil
end
local function Click(btn) local fn = btn and btn:GetScript("OnClick"); if fn then fn(btn) end end
-- IsVisible, not just IsShown: a hidden pane's own children stay .shown = true
-- (the client hides a whole subtree; only the ancestor's flag flips), so a
-- placeholder swapped for the real pane and Hidden must be checked the way
-- the eye would see it.
local function TextPresent(text)
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:IsVisible() then
            local okt, txt = pcall(f.GetText, f)
            if okt and txt == text then return true end
        end
    end
    return false
end
-- T71 (P27): under the theme the list is the generic table, whose rows take
-- OnMouseUp(self, button) -- a click -- and count a second LeftButton on the
-- same row within 0.4 s as a double-click. SelectRow moves the stub's clock
-- a second first, so two selections in a row are never read as one
-- double-click; DoubleClickRow clicks twice at the same moment.
local function RowClick(r, button)
    local fn = r and (r:GetScript("OnMouseUp") or r:GetScript("OnClick"))
    if fn then fn(r, button or "LeftButton") end
end
local function SelectRow(n, button)
    S.now = S.now + 1
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == tostring(n) then
            RowClick(r, button)
            return true
        end
    end
    return false
end
local function DoubleClickRow(n)
    S.now = S.now + 1
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == tostring(n) then
            RowClick(r, "LeftButton")
            -- the first click re-rendered the list: find the row again
            for _, r2 in ipairs(Rows()) do
                if CellText(r2, "n") == tostring(n) then RowClick(r2, "LeftButton"); return true end
            end
            return false
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 1: the Forever window has a Reports group with a Review view
--------------------------------------------------------------------------------
MD:SelectView("reports", "review")
local g, v = MD:SelectedView()
check("the Forever window has a Reports group with a Review view",
    g == "reports" and v == "review" and ButtonNamed("Reports") ~= nil,
    "group=" .. tostring(g) .. " view=" .. tostring(v))

--------------------------------------------------------------------------------
-- 2: with the Replay module off the Review view says how to switch it on and
--    loads nothing
--------------------------------------------------------------------------------
check("with the Replay module off the Review view says how to switch it on and loads nothing",
    TextPresent("Review needs the Replay module - Settings -> Modules")
    and MD:ModuleState("SpellTuner_Replay") == "off"
    and #S.loadAddOnCalls == 0)

--------------------------------------------------------------------------------
-- 3: switching the Replay module on replaces the placeholder with the Review
--    tab
--------------------------------------------------------------------------------
-- T43: the template each font string is built from, recorded by this script
-- (not the stub) so the Review pane's fonts can be read back below.
local fontTemplate = setmetatable({}, { __mode = "k" })
do
    local FrameMT = getmetatable(CreateFrame("Frame"))
    local origCFS = FrameMT.CreateFontString
    FrameMT.CreateFontString = function(self, name, layer, template)
        local fs = origCFS(self, name, layer, template)
        fontTemplate[fs] = template or false
        return fs
    end
end
MD:SetModule("SpellTuner_Replay", true) -- loads Recorder (a dependency), Kit/Scenario/Gates, the engine chain, the window and this pane
check("switching the Replay module on replaces the placeholder with the Review tab",
    not TextPresent("Review needs the Replay module - Settings -> Modules")
    and MD.DashboardParts.CreateReview ~= nil
    and ButtonNamed("Fights") ~= nil)

-- UI/Dashboard_Forever.lua anchors the pane to the content area with no
-- explicit SetSize (real WoW derives it from the anchors; the stub does not
-- -- tools/reviewui.lua's own harness hits the same gap and works around it
-- the same way: give the pane a real size before rendering any rows, since
-- UI/Dashboard_Review.lua's own row loop clips on `pane:GetHeight()`).
local reviewFrame = ButtonNamed("Fights") and ButtonNamed("Fights").parentFrame
if reviewFrame then reviewFrame:SetSize(912, 500) end

--------------------------------------------------------------------------------
-- recordings: a clean one that passes all eight gates, and one whose meter
-- never read at all (drifts past the calibration limit -- fails foreign
-- healing, model calibrated and heals attributed, all three needing a meter
-- reading this recording does not have). tools/gatecheck.lua's own baseline
-- shape: the meter and the mana curve are set to what the engine itself
-- produces replaying the fixture's own casts, a consistency check on a
-- known-consistent pair rather than a guessed number.
--------------------------------------------------------------------------------
local buildFixture = dofile(here .. "/foreverfixture.lua")
S.crit[4] = 0 -- zero Nature crit: recGood's own-heal amounts are the engine's own exact figures

local kit = MD.RankMath:SpellKit()
local SM = MD.SimModel
local function DeepCopy(a)
    local t = {}
    for i = 1, #a do t[i] = a[i] end
    return t
end
local baseSc = SM.ScenarioFromRecording(buildFixture(), kit)
local baseRun = SM:Run(baseSc, nil, { critMode = "ev" })
local baseSimOwn = (baseRun.healed or 0) - ((baseRun.healByFamily and baseRun.healByFamily.foreign) or 0)
local baseManaCurve = DeepCopy(baseRun.manaCurve) -- SM:Run reuses a pooled table; copy out now

local recGood = buildFixture({ meter = { own = baseSimOwn, others = 0, bySource = {}, bySpell = {}, read = "current" } })
recGood.id = 2000000000
recGood.mana.v = DeepCopy(baseManaCurve)
local recBad = buildFixture({ meterOverridden = true })
recBad.id = 1000000000
MD.cdb.recordings = { recGood, recBad }

MD:SelectView("reports", "review") -- re-render now that recordings exist

--------------------------------------------------------------------------------
-- 4: each recording is a row with its validate result
--------------------------------------------------------------------------------
-- Rows() picks up the header row too (it shares the same cells.n shape,
-- tools/reviewui.lua's own "a header and a row" count) -- three total for two
-- recordings.
-- Rows() picks up the header row too (it shares the same cells.n shape,
-- tools/reviewui.lua's own "a header and a row" count) -- three total for two
-- recordings (the selected one validated on sight since T49, the other
-- unchecked until Validate runs). Sanity, not one of the eight
-- named checks: a wrong count here would fail check 4 below anyway, less
-- clearly.
assert(#Rows() == 3, "expected a header and two data rows, got " .. #Rows())

--------------------------------------------------------------------------------
-- T49 (P5), B24: the selected row is validated before the rows are painted,
-- so on the very first render it already shows its verdict -- not "not
-- checked" beside buttons that already say Coach or Coach*.
--------------------------------------------------------------------------------
do
    local first
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == "1" then first = CellText(r, "valid") end
    end
    -- T71: the Result cell says "replays" where TBC's validate cell says "ok"
    check("B24: the selected, never validated row paints its verdict on the first render",
        first ~= nil and first:find("replays", 1, true) == 1,
        "row1=" .. tostring(first))
end

SelectRow(1)
local validateChat1 = CapturedChat(function() Click(ButtonNamed("Validate")) end)
SelectRow(2)
local validateChat2 = CapturedChat(function() Click(ButtonNamed("Validate")) end)

local function ValidText(n)
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == tostring(n) then return CellText(r, "valid") end
    end
    return nil
end
-- T71 (A31): the failing row's cell is the first failing gate's own `short`
-- ("no meter reading" for recBad's foreign healing gate), not its prose cut
-- at the first parenthesis
check("each recording is a row with its validate result",
    (ValidText(1) or ""):find("replays", 1, true) == 1
    and ValidText(2) == "does not replay: no meter reading",
    "row1=" .. tostring(ValidText(1)) .. " row2=" .. tostring(ValidText(2)))

--------------------------------------------------------------------------------
-- T71 (P27, review U20): Validate answers in the window -- the RESULT area
-- under the list shows the report (a row per gate: name, ok / FAIL, text),
-- and chat gets one line.
--------------------------------------------------------------------------------
local function ResultRows()
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.cells and f.cells.label and f.cells.state and f:IsVisible() and f.data then
            out[#out + 1] = f
        end
    end
    table.sort(out, function(a, b) return (a.index or 0) < (b.index or 0) end)
    return out
end
local function Strip(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The result area scrolls too: its lines are read by winding it to the top
-- with the wheel, then down a notch at a time, keyed by each row's place.
local function ResultText()
    local byIndex, maxIndex = {}, 0
    local function Collect()
        local new = 0
        for _, r in ipairs(ResultRows()) do
            local d = r.data
            if r.index and not byIndex[r.index] then
                byIndex[r.index] = d.wide and Strip(d.text)
                    or (Strip(d.label) .. " | " .. Strip(d.state) .. " | " .. Strip(d.text))
                if r.index > maxIndex then maxIndex = r.index end
                new = new + 1
            end
        end
        return new
    end
    local first = ResultRows()[1]
    local frame = first and first.parentFrame
    local wheel = frame and frame:GetScript("OnMouseWheel")
    if wheel then for _ = 1, 60 do wheel(frame, 1) end end
    Collect()
    for _ = 1, 60 do
        if not wheel then break end
        wheel(frame, -1)
        if Collect() == 0 then break end
    end
    if wheel then for _ = 1, 60 do wheel(frame, 1) end end
    local parts = {}
    for i = 1, maxIndex do parts[#parts + 1] = byIndex[i] or "?" end
    return parts
end
do
    local lines = ResultText()
    local gateRows, failForeign, verdict = 0, false, false
    for _, l in ipairs(lines) do
        if l:find(" | ok | ", 1, true) or l:find(" | FAIL | ", 1, true) then gateRows = gateRows + 1 end
        if l:find("foreign healing | FAIL | no damage meter reading", 1, true) then failForeign = true end
        if l:find("does NOT replay", 1, true) then verdict = true end
    end
    local plain = Strip(validateChat2[1] or "")
    check("T71: Validate shows the report in the result area, and chat gets one line",
        gateRows == 8 and failForeign and verdict and #validateChat1 == 1 and #validateChat2 == 1
        and plain:find("fight 2 validated - does not replay (foreign healing). The details are in Review.", 1, true) ~= nil,
        string.format("gate rows=%d foreign FAIL=%s verdict=%s chat=%d/%d %s", gateRows, tostring(failForeign),
            tostring(verdict), #validateChat1, #validateChat2, plain))
end

--------------------------------------------------------------------------------
-- T43 (docs/SPEC-forever-ui.md 4.4): under the Forever theme the Review pane's
-- four GameFontHighlightSmall strings -- the habits line, the progress line,
-- the run line and the row cells -- are built from UI.FONT_SMALL.
--------------------------------------------------------------------------------
do
    local small, gold, other = 0, 0, {}
    for fs, tpl in pairs(fontTemplate) do
        local p = fs.parentFrame
        local inPane = p == reviewFrame or (p and p.cells and p.parentFrame == reviewFrame)
        if inPane then
            if tpl == "GameFontHighlightSmall" then gold = gold + 1
            elseif tpl == MD.UI.FONT_SMALL then small = small + 1
            else other[#other + 1] = tostring(tpl) end
        end
    end
    -- the pane's three lines plus at least one row's cells (three rows are up)
    check("T43: the Review pane's small text is UI.FONT_SMALL, not GameFontHighlightSmall",
        reviewFrame ~= nil and gold == 0 and small > 3,
        string.format("FONT_SMALL=%d GameFontHighlightSmall=%d other=%s", small, gold, table.concat(other, ",")))
end

--------------------------------------------------------------------------------
-- 5: a row's tooltip carries every Forever gate line
--------------------------------------------------------------------------------
local function RowNumbered(n)
    for _, r in ipairs(Rows()) do if CellText(r, "n") == tostring(n) then return r end end
    return nil
end
local row1 = RowNumbered(1)
GameTooltip.lines = nil
local enter1 = row1 and row1:GetScript("OnEnter")
if enter1 then enter1(row1) end
local function LineHas(text)
    for _, line in ipairs(GameTooltip.lines or {}) do
        if type(line[1]) == "string" and line[1]:find(text, 1, true) then return true end
    end
    return false
end
local GATE_NAMES = { "mana mean", "mana max", "health curves", "no tracked death",
    "foreign healing", "model calibrated", "spend coverage", "heals attributed" }
local missingGate
for _, n in ipairs(GATE_NAMES) do
    if not LineHas(n) then missingGate = n; break end
end
check("a row's tooltip carries every Forever gate line", missingGate == nil, missingGate)

--------------------------------------------------------------------------------
-- R39 (review 2026-09-29): a v3 recording's mana samples are the clock's
-- model (UnitPower is secret), so the "low mana" cell says so with the
-- clock's own "~" and the row's tooltip names it modelled -- before any
-- Validate, since the gate text is not the column's explanation.
--------------------------------------------------------------------------------
local lowCell = row1 and CellText(row1, "low") or ""
local sawModelled = false
for _, line in ipairs(GameTooltip.lines or {}) do
    local both = tostring(line[1]) .. " " .. tostring(line[2])
    if both:find("low mana", 1, true) and both:find("modelled", 1, true) then sawModelled = true end
end
check("R39: the low mana cell of a v3 recording is marked modelled (~, and the tooltip says so)",
    lowCell:sub(1, 1) == "~" and sawModelled,
    "cell=" .. lowCell .. " tooltip modelled line=" .. tostring(sawModelled))
local leave1 = row1 and row1:GetScript("OnLeave")
if leave1 then leave1(row1) end

--------------------------------------------------------------------------------
-- R40 (review 2026-09-29): there is no export on Forever (MD.RunExport is
-- Verify.lua's, TBC only), so the Export button is not offered -- it used to
-- sit enabled and do nothing when clicked.
--------------------------------------------------------------------------------
local exportBtn
for _, f in ipairs(S.allFrames) do
    if f.kind == "Button" and f.text == "Export" then exportBtn = f end
end
check("R40: with no export on this client the Export button is not offered",
    MD.RunExport == nil and exportBtn ~= nil and (exportBtn.shown == false or exportBtn.enabled == false),
    "RunExport=" .. tostring(MD.RunExport) .. " shown=" .. tostring(exportBtn and exportBtn.shown)
    .. " enabled=" .. tostring(exportBtn and exportBtn.enabled))

--------------------------------------------------------------------------------
-- 6: Coach refuses the failing fight -- T71 (P27, section 8.1 item 5): with
--    no star, the refusal in the result area and one chat line; forcing is
--    the row menu's Coach anyway (below), a shift-click no longer forces.
--------------------------------------------------------------------------------
SelectRow(2) -- recBad: no meter reading, fails "foreign healing" among others
local coachBtn = ButtonNamed("Coach")
assert(coachBtn ~= nil and coachBtn.enabled ~= false and ButtonNamed("Coach*") == nil,
    "expected a clickable Coach with no star, got " .. tostring(coachBtn and coachBtn.text))

S.shift = true -- a held Shift changes nothing under the theme
local plainLines = CapturedChat(function() Click(coachBtn) end)
S.shift = false
-- a long line is cut into rows at word boundaries: read them as one text
local refusedInPane = table.concat(ResultText(), " "):gsub("%s+", " ")
    :find("Right-click the row -> Coach anyway to coach it regardless.", 1, true) ~= nil
local refused = MD.SimPlanner.plans[recBad.id] == nil and MD.coachSearch == nil and #plainLines == 1
    and Strip(plainLines[1]):find("fight 2 does not replay (foreign healing) - nothing to coach", 1, true) ~= nil
check("Coach refuses the failing fight in the result area with one chat line, shift or not",
    refused and refusedInPane,
    string.format("refused=%s inPane=%s chat=%d (%s)", tostring(refused), tostring(refusedInPane),
        #plainLines, tostring(plainLines[1])))

--------------------------------------------------------------------------------
-- T71 (P27, review U22): the right-click row menu -- Play, Validate, Coach
-- (greyed on a fight that does not replay, the reason beside it), Coach
-- anyway, Pin -- and its Coach anyway forces: the plan is made and marked
-- forced, the card lands in the result area, chat has one line.
--------------------------------------------------------------------------------
do
    SelectRow(2, "RightButton")
    -- the menu is the frame holding the "Coach anyway" item (UI/ContextMenu.lua)
    local menuFrame
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == "Coach anyway" and f.parentFrame and f.parentFrame ~= reviewFrame then
            menuFrame = f.parentFrame
        end
    end
    local labels, coachItem, anyway = {}, nil, nil
    local items = {}
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.parentFrame == menuFrame and f.shown then items[#items + 1] = f end
    end
    -- in the order they stand (the y of each row's TOPLEFT point is not kept by
    -- the stub, so the order is the order they were built, which is the menu's)
    for _, r in ipairs(items) do
        labels[#labels + 1] = r.text
        if r.text == "Coach" then coachItem = r end
        if r.text == "Coach anyway" then anyway = r end
    end
    local menu = { frame = menuFrame }
    local menuOk = menuFrame ~= nil and menuFrame:IsShown()
        and table.concat(labels, ",") == "Play,Validate,Coach,Coach anyway,Pin"
        and coachItem and coachItem.enabled == false and coachItem.note:GetText() == "does not replay"
        and anyway and anyway.enabled ~= false
    local chat = CapturedChat(function()
        Click(anyway)
        local frames = 0
        while MD.coachSearch and frames < 20000 do S.Tick(0.016); frames = frames + 1 end
    end)
    local SP = MD.SimPlanner
    local card = false
    for _, l in ipairs(ResultText()) do
        if l:find("caveat:", 1, true) then card = true end
    end
    check("T71: the row menu offers Play, Validate, Coach (greyed: does not replay), Coach anyway, Pin; Coach anyway forces",
        menuOk and not menu.frame:IsShown() and SP.plans[recBad.id] ~= nil and SP.forced[recBad.id] == true
        and card and #chat == 1 and Strip(chat[1]):find("fight 2 coached - used: you", 1, true) ~= nil,
        string.format("menu=%s items=%s plan=%s forced=%s card=%s chat=%d %s", tostring(menuOk),
            table.concat(labels, ","), tostring(SP.plans[recBad.id] ~= nil), tostring(SP.forced[recBad.id]),
            tostring(card), #chat, tostring(chat[1])))
end

--------------------------------------------------------------------------------
-- T71 (P27, review A17): the card's structured lines (SP.CardLines) join into
-- exactly the chat card SP.Coach returns, and the result area paints those
-- lines -- its first line is the head of the card the menu's Coach anyway
-- (above) made for the same fight.
--------------------------------------------------------------------------------
do
    local SP = MD.SimPlanner
    local card, _, _, _, cardLines = SP.Coach(recBad, { n = 2, force = true })
    local joined = SP.CardText(cardLines or {})
    local same = cardLines ~= nil and #joined == #card and #card > 5
    for i = 1, #card do if joined[i] ~= card[i] then same = false end end
    local muted = 0
    for _, l in ipairs(cardLines or {}) do if l.tone == "muted" then muted = muted + 1 end end
    local first = ResultText()[1] or ""
    local head = Strip(card[1]):match("^(.-)used:") or "?"
    check("T71: the card lines join into the chat card byte for byte; the result area shows them",
        same and muted > 0 and cardLines.used ~= nil and first:find(head, 1, true) == 1,
        string.format("lines=%d chat=%d same=%s muted=%d first=%s", cardLines and #cardLines or -1, #card,
            tostring(same), muted, first))
end

--------------------------------------------------------------------------------
-- T71 (P27, review U22): a double-click on a row plays it.
--------------------------------------------------------------------------------
do
    local W0 = MD.Replay._state()
    if W0.frame then W0.frame:Hide() end
    MD:SelectView("reports", "review")
    local opened = {}
    local origOpen = MD.Replay.Open
    MD.Replay.Open = function(self, spec, ...) opened[#opened + 1] = spec; return origOpen(self, spec, ...) end
    SelectRow(2) -- a single click opens nothing
    local afterSingle = #opened
    DoubleClickRow(1)
    MD.Replay.Open = origOpen
    local W = MD.Replay._state()
    check("T71: a double-click on a row opens the replay on it (a single click does not)",
        afterSingle == 0 and #opened == 1 and opened[1] == "1" and W.frame ~= nil and W.frame:IsShown(),
        string.format("single=%d opened=%s shown=%s", afterSingle, table.concat(opened, ","),
            tostring(W.frame and W.frame:IsShown())))
    if W.frame then W.frame:Hide() end
end

--------------------------------------------------------------------------------
-- 7: Play opens the replay window on the selected fight
--------------------------------------------------------------------------------
MD:SelectView("reports", "review")
SelectRow(1)
Click(ButtonNamed("Play"))
local W = MD.Replay._state()
check("Play opens the replay window on the selected fight", W.frame ~= nil and W.frame:IsShown())
if W.frame then W.frame:Hide() end

--------------------------------------------------------------------------------
-- 8: every string the tab paints is ASCII with no bare pipe -- a fixture
--    target named with a non-ASCII byte and a "|" (T14 review)
--------------------------------------------------------------------------------
local recBadName = buildFixture()
recBadName.id = 3000000000
-- roster[1] (Healroot), not roster[2] (Tank): the tab only ever reads a
-- roster name back out for the "excluded" tooltip line (Healroot takes no
-- damage in this fixture and is excluded every time), never for the target
-- whose health curve reproduces exactly -- so this is the one name the tab
-- is guaranteed to paint.
recBadName.roster[1].name = "Healroot\195\169|boss" -- an EU-style byte plus a bare pipe
MD.cdb.recordings = { recBadName, recGood, recBad }
MD:SelectView("reports", "review")
-- a row's OnEnter closes over the validation cached at the time the row was
-- built; select-and-Validate (as assertion 6 already does) forces a second
-- render with that cache warm, so the "excluded" line -- the one line that
-- ever reads a roster name back out -- is actually there to hover.
SelectRow(1)
Click(ButtonNamed("Validate"))

-- the root of the tab: any row's own parent is the Review pane itself
-- (UI/Dashboard_Review.lua's `pane`), not the window's nav chrome -- so this
-- walk never meets UI/Style.lua's own "x" close glyph (modulecheck's own
-- named exception for that byte; this suite has none to make).
-- T71: the rows sit in the list table, a child of the pane; the walk starts
-- at the pane, so the result area and the row menu are scanned too.
local function TabRoot()
    return reviewFrame
end
local function Under(f, root)
    if not root then return false end
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end

local badRow = RowNumbered(1) -- recBadName sorts newest first
GameTooltip.lines = nil
local enterBad = badRow and badRow:GetScript("OnEnter")
if enterBad then enterBad(badRow) end
local leaveBad = badRow and badRow:GetScript("OnLeave")

local function Pipes(s)
    -- a colour code, a reset and Esc's own "||" (a literal pipe, doubled so
    -- the client renders one rather than eating what follows) are all safe;
    -- anything left over is a BARE pipe.
    local stripped = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
local function NonAscii(s) return s:find("[^ -~]") ~= nil end
-- T16c: a name the client gave paints with its own bytes -- only its "|" is
-- doubled. So the fixture's name is expected to survive intact (pipe
-- doubled) wherever it is painted; everything ELSE this tab composes itself
-- must still be plain ASCII once that one known name is removed.
local NAME_PAINTED = "Healroot\195\169||boss"
local function StripPlain(s, sub)
    local out, i = {}, 1
    while true do
        local a, b = s:find(sub, i, true)
        if not a then out[#out + 1] = s:sub(i); break end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
    return table.concat(out)
end
local bad, sawName = {}, false
local function Scan(label, s)
    if type(s) ~= "string" then return end
    if Pipes(s) then bad[#bad + 1] = label .. " has a bare pipe: " .. s end
    if s:find(NAME_PAINTED, 1, true) then sawName = true end
    if NonAscii(StripPlain(s, NAME_PAINTED)) then bad[#bad + 1] = label .. " is not ASCII: " .. s end
end

local root = TabRoot()
for _, f in ipairs(S.allFrames) do
    if f.GetText and Under(f, root) then
        local okt, txt = pcall(f.GetText, f)
        if okt and type(txt) == "string" and txt ~= "" then Scan("tab text", txt) end
    end
end
for _, line in ipairs(GameTooltip.lines or {}) do
    Scan("tooltip l", line[1])
    Scan("tooltip r", line[2])
end
if leaveBad then leaveBad(badRow) end
local detail8 = bad[1]
if not detail8 and not sawName then detail8 = "the fixture name never painted with its own bytes" end
check("every string the tab paints is ASCII with no bare pipe", #bad == 0 and sawName, detail8)

--------------------------------------------------------------------------------
-- T49 (P5), B14: Review's Pin goes through the recorder's capped Pin -- two
-- pinned fights, and a third is refused with one line saying why, instead of
-- being pinned past the cap (after which every stored pull could end up
-- pinned and the next one lost).
--------------------------------------------------------------------------------
do
    for _, r in ipairs(MD.cdb.recordings) do r.pinned = false end
    MD:SelectView("reports", "review")
    local function PinRow(n)
        SelectRow(n)
        return CapturedChat(function() Click(ButtonNamed("Pin")) end)
    end
    local l1 = PinRow(1)
    local l2 = PinRow(2)
    local l3 = PinRow(3)
    local list = MD.FightRecorder:List()
    local refusal = l3[1] or ""
    local plain = refusal:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    check("B14: a third pin is refused with one line, and the first two stay pinned",
        #l1 == 0 and #l2 == 0 and list[1].pinned == true and list[2].pinned == true
        and list[3].pinned ~= true and #l3 == 1 and plain:find("pin: at most 2", 1, true) ~= nil
        and not plain:find("[^ -~]") and not plain:gsub("||", ""):find("|", 1, true),
        string.format("pins=%s,%s,%s line=%s", tostring(list[1].pinned), tostring(list[2].pinned),
            tostring(list[3].pinned), tostring(l3[1])))
    for _, r in ipairs(MD.cdb.recordings) do r.pinned = false end
end

--------------------------------------------------------------------------------
-- T71 (P27, review U25 / U17): a list longer than the pane scrolls -- the
-- table shows a window of rows, the mouse wheel moves it, the last row is
-- reachable, and no "... and N more" tail line is painted (TBC keeps P9's).
--------------------------------------------------------------------------------
do
    local many = {}
    for i = 1, 36 do
        local r = {}
        for k, v in pairs(recGood) do r[k] = v end
        r.id = 2000000000 + i * 60
        r.pinned = false
        many[i] = r
    end
    MD.cdb.recordings = many
    MD:SelectView("reports", "review")
    local function Shown()
        local nums = {}
        for _, r in ipairs(Rows()) do
            local n = tonumber(CellText(r, "n"))
            if n then nums[#nums + 1] = n end
        end
        table.sort(nums)
        return nums
    end
    local first = Shown()
    local listFrame = Rows()[1] and Rows()[1].parentFrame
    local wheel = listFrame and listFrame:GetScript("OnMouseWheel")
    local notches = 0
    while wheel and notches < 40 do
        local before = table.concat(Shown(), ",")
        wheel(listFrame, -1)
        notches = notches + 1
        if table.concat(Shown(), ",") == before then break end
    end
    local last = Shown()
    local tail = TextPresent("... and 27 more (scroll: not yet)")
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:IsVisible() then
            local okt, t = pcall(f.GetText, f)
            if okt and type(t) == "string" and t:find("more (scroll", 1, true) then tail = true end
        end
    end
    -- and back up to the top
    if wheel then for _ = 1, 40 do wheel(listFrame, 1) end end
    local top = Shown()
    check("T71: 36 fights scroll in the list -- the wheel reaches the last, no tail line",
        #first >= 3 and #first < 36 and first[1] == 1 and last[#last] == 36 and #last == #first
        and top[1] == 1 and not tail,
        string.format("first=%s..%s (%d) last=%s..%s notches=%d tail=%s", tostring(first[1]),
            tostring(first[#first]), #first, tostring(last[1]), tostring(last[#last]), notches, tostring(tail)))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
