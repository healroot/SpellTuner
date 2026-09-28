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
local function SelectRow(n)
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == tostring(n) then
            local fn = r:GetScript("OnClick")
            if fn then fn(r) end
            return true
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
-- recordings, unchecked until Validate runs. Sanity, not one of the eight
-- named checks: a wrong count here would fail check 4 below anyway, less
-- clearly.
assert(#Rows() == 3, "expected a header and two data rows, got " .. #Rows())

SelectRow(1)
Click(ButtonNamed("Validate"))
SelectRow(2)
Click(ButtonNamed("Validate"))

local function ValidText(n)
    for _, r in ipairs(Rows()) do
        if CellText(r, "n") == tostring(n) then return CellText(r, "valid") end
    end
    return nil
end
check("each recording is a row with its validate result",
    (ValidText(1) or ""):find("ok", 1, true) ~= nil
    and (ValidText(2) or ""):find("foreign healing", 1, true) ~= nil,
    "row1=" .. tostring(ValidText(1)) .. " row2=" .. tostring(ValidText(2)))

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
local leave1 = row1 and row1:GetScript("OnLeave")
if leave1 then leave1(row1) end

--------------------------------------------------------------------------------
-- 6: Coach refuses the failing fight and shift-click coaches it anyway
--------------------------------------------------------------------------------
SelectRow(2) -- recBad: no meter reading, fails "foreign healing" among others
local coachBtn = ButtonNamed("Coach*") or ButtonNamed("Coach")
assert(coachBtn ~= nil and coachBtn.text == "Coach*" and coachBtn.enabled ~= false,
    "expected a clickable Coach*, got " .. tostring(coachBtn and coachBtn.text))

S.shift = false
local plainLines = CapturedChat(function() Click(coachBtn) end)
local refused = MD.SimPlanner.plans[recBad.id] == nil and (function()
    for _, m in ipairs(plainLines) do if m:find("does not replay", 1, true) then return true end end
    return false
end)()

S.shift = true
Click(ButtonNamed("Coach*") or ButtonNamed("Coach"))
local frames = 0
while MD.coachSearch and frames < 20000 do S.Tick(0.016); frames = frames + 1 end
S.shift = false
local forced = MD.SimPlanner.plans[recBad.id] ~= nil

check("Coach refuses the failing fight and shift-click coaches it anyway",
    refused and forced,
    string.format("refused=%s (%s) forced=%s (%d frames)", tostring(refused),
        plainLines[1] or "no chat", tostring(forced), frames))

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
recBadName.roster[2].name = "Tank\195\169|boss" -- an EU-style byte plus a bare pipe
MD.cdb.recordings = { recBadName, recGood, recBad }
MD:SelectView("reports", "review")

-- the root of the tab: any row's own parent is the Review pane itself
-- (UI/Dashboard_Review.lua's `pane`), not the window's nav chrome -- so this
-- walk never meets UI/Style.lua's own "x" close glyph (modulecheck's own
-- named exception for that byte; this suite has none to make).
local function TabRoot()
    local r = Rows()[1]
    return r and r.parentFrame
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
local bad = {}
local function Scan(label, s)
    if type(s) ~= "string" then return end
    if Pipes(s) then bad[#bad + 1] = label .. " has a bare pipe: " .. s end
    if NonAscii(s) then bad[#bad + 1] = label .. " is not ASCII: " .. s end
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
check("every string the tab paints is ASCII with no bare pipe", #bad == 0, bad[1])

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
