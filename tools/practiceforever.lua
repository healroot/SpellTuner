-- tools/run.sh tools/practiceforever.lua
--
-- T18 (docs/tasks/T18-practice-forever.md): Practice on Forever -- the
-- Simulate -> Practice view (a placeholder until the Practice module is on,
-- same shape as Reports -> Review's own), the panel built from the Forever
-- kit's own spells (Kit_Forever.lua/Spells/Book.lua, T15), a session played
-- against a fake clock and recorded (Engine/Practice.lua, one file for both
-- lines), the recording replaying through the same engine with every gate
-- passing, a bound key casting and an unbound one propagating (UI/
-- ReplayWindow.lua's practice mode), ending it reopening as a replay and
-- listing under Review, the commands existing only with the module on, and
-- every painted string ASCII with no bare pipe. Forever only.
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

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

-- IsVisible, not just IsShown (tools/reviewforever.lua's own reasoning): a
-- hidden pane's own children stay .shown = true, only the ancestor's flag
-- flips, so a placeholder swapped for the real pane must be checked the way
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
local function Button(text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false then return f end
    end
    return nil
end
local function Click(b, button) local fn = b and b:GetScript("OnClick"); if fn then fn(b, button or "LeftButton") end end

--------------------------------------------------------------------------------
-- 1: the Simulate group has a Practice view, a placeholder until the module
--    is on
--------------------------------------------------------------------------------
MD:SelectView("simulate", "practice")
local g, v = MD:SelectedView()
check("the Simulate group has a Practice view, a placeholder until the module is on",
    g == "simulate" and v == "practice"
    and TextPresent("Practice needs the Practice module - Settings -> Modules")
    and MD:ModuleState("SpellTuner_Practice") == "off"
    and #S.loadAddOnCalls == 0,
    "group=" .. tostring(g) .. " view=" .. tostring(v))

--------------------------------------------------------------------------------
-- 7: /st practice and /st binds exist only with the Practice module on
--------------------------------------------------------------------------------
local beforeOpenNil = (MD.OpenPractice == nil)
-- would have raised, unguarded, if either command already existed
CapturedChat(function() SlashCmdList.SPELLTUNER("practice") end)
CapturedChat(function() SlashCmdList.SPELLTUNER("binds") end)

MD:SetModule("SpellTuner_Practice", true) -- loads Recorder, Replay (engine/window/review) and this module's own files

check("/st practice and /st binds exist only with the Practice module on",
    beforeOpenNil and type(MD.OpenPractice) == "function" and type(MD.Practice) == "table"
    and type(MD.ToggleBindings) == "function" and MD.SimPlanner ~= nil,
    "beforeOpenNil=" .. tostring(beforeOpenNil) .. " afterOpen=" .. tostring(MD.OpenPractice))

local PR, SD, SM = MD.Practice, MD.SpellData, MD.SimModel

--------------------------------------------------------------------------------
-- 2: the practice panel builds a fight from the Forever kit's own spells --
--    PR.SpellFor resolves through MD.SpellData (Kit_Forever.lua's own read of
--    Spells/Book.lua), not a hand-kept table
--------------------------------------------------------------------------------
MD.player.isDruid = true
MD.cdb.practice, MD.db.practiceBinds = {}, nil
local parent = CreateFrame("Frame")
local panel = MD.DashboardParts.CreatePractice(parent, 912)
panel.frame:Show()
panel:Render()
local rejID = PR.SpellFor({ family = "Rejuvenation" })
check("the practice panel builds a fight from the Forever kit's spells",
    panel.frame ~= nil and MD.cdb.practiceSetup ~= nil and #MD.cdb.practiceSetup.targets == 5
    and rejID ~= nil and rejID == SD.maxRank.Rejuvenation
    and SD.spells[rejID] and SD.spells[rejID].family == "Rejuvenation",
    "rejID=" .. tostring(rejID) .. " maxRank=" .. tostring(SD.maxRank.Rejuvenation))

--------------------------------------------------------------------------------
-- 3: a session plays against a fake clock with the Forever kit and records a
--    practice stream
--------------------------------------------------------------------------------
MD.db.practiceBinds = { { key = "1", family = "Rejuvenation" }, { key = "2", family = "HealingTouch" } }
local setup = PR.DefaultSetup("2", 64) -- healer + tank, small and deterministic
setup.dur, setup.fixedSeed = 20, 9
local errors3 = {}
local s = PR.New(PR.CopySetup(setup), { seed = setup.fixedSeed, noStore = true,
    onError = function(m) errors3[#errors3 + 1] = m end })
assert(s.state == "ready", "expected a new session to be ready, not running, got " .. tostring(s.state))
s:Start()
local script = { { 1.0, SD.maxRank.Rejuvenation, 1 }, { 8.0, SD.maxRank.HealingTouch, 1 } }
local nextI = 1
while s.state == "running" do
    local p = script[nextI]
    if p and s.clock >= p[1] - 1e-9 then
        s:Cast(p[2], p[3])
        nextI = nextI + 1
    end
    s:Update(0.05)
end
local rec = s.rec
check("a session plays against a fake clock with the Forever kit and records a practice stream",
    s.state == "done" and rec ~= nil and rec.v == 2 and (rec.ownCasts or 0) >= 2 and #errors3 == 0,
    "state=" .. tostring(s.state) .. " rec=" .. tostring(rec ~= nil) ..
    " ownCasts=" .. tostring(rec and rec.ownCasts) .. " errors=" .. table.concat(errors3, "; "))

--------------------------------------------------------------------------------
-- R4 (review 2026-09-29): the healer regenerates. MD.Regen is TBC's
-- Engine/RegenModel.lua and is on no Forever TOC, so the regen rates come
-- from the adapter's GetManaRegen (plain out of combat, where practice
-- starts): the scenario, and so the recording, carry them -- not zero.
--------------------------------------------------------------------------------
do
    local wantBase, wantCast = GetManaRegen() -- the stub's plain out-of-combat pair
    local ini = rec and rec.initial or {}
    local mb = rec and rec.mana and rec.mana.base and rec.mana.base[1]
    local mc = rec and rec.mana and rec.mana.cast and rec.mana.cast[1]
    check("R4: a Forever practice session regenerates at the client's own GetManaRegen rates",
        MD.Regen == nil and type(wantBase) == "number" and wantBase > 0
        and ini.apiBase == wantBase and ini.apiCasting == wantCast and mb == wantBase and mc == wantCast,
        string.format("apiBase=%s apiCasting=%s mana.base[1]=%s want %s/%s", tostring(ini.apiBase),
            tostring(ini.apiCasting), tostring(mb), tostring(wantBase), tostring(wantCast)))
end

--------------------------------------------------------------------------------
-- 4: the recording replays to the health the player saw and every gate
--    passes -- the same engine, the Forever kit
--------------------------------------------------------------------------------
local kit = MD.RankMath:SpellKit({ live = true })
local v4 = SM:Validate(rec, kit)
local failed = {}
for _, gate in ipairs(v4.gates) do if not gate.ok then failed[#failed + 1] = gate.name .. ": " .. tostring(gate.text) end end
local sc = SM.ScenarioFromRecording(rec, kit)
local r4 = SM:Run(sc, nil, { critMode = "ev" })
local worst = 0
for i = 1, #rec.tracked do
    local n = #rec.hp.t
    local want = rec.hp.hp[i][n]
    local got = r4.hpCurve[i] and r4.hpCurve[i][#r4.hpCurve[i]]
    if want and got then worst = math.max(worst, math.abs(want - got)) end
end
check("the recording replays to the health the player saw and every gate passes",
    v4.ok and worst < 1,
    "gates: " .. table.concat(failed, "; ") .. " worst hp diff " .. string.format("%.3f", worst))

--------------------------------------------------------------------------------
-- 5: a key bound to a spell casts it; an unbound key propagates
--------------------------------------------------------------------------------
MD.cdb.practiceSetup = PR.CopySetup(setup)
MD.cdb.practiceSetup.dur = 20
MD:OpenPractice(PR.CopySetup(MD.cdb.practiceSetup), 5)
local live5 = MD.Replay._live()
local st5 = MD.Replay._state()
assert(live5 ~= nil and live5.state == "running" and st5.frame and st5.frame:IsShown(),
    "expected practice mode to open the replay window")

local tank5 = st5.left.frames[1]
tank5:GetScript("OnEnter")(tank5)
local _, hov5 = MD.Replay._live()
S.Tick(1.0)
st5.frame:GetScript("OnKeyDown")(st5.frame, "1") -- bound to Rejuvenation
S.Tick(0.3)
local castsBound = #live5.own
st5.frame:GetScript("OnKeyDown")(st5.frame, "9") -- not bound to anything
S.Tick(0.3)
local castsUnbound = #live5.own
check("a key bound to a spell casts it; an unbound key propagates",
    hov5 == 1 and castsBound >= 1 and castsUnbound == castsBound,
    "hover=" .. tostring(hov5) .. " castsBound=" .. tostring(castsBound) .. " castsUnbound=" .. tostring(castsUnbound))

--------------------------------------------------------------------------------
-- 6: ending the session reopens it as a replay and lists it in Review
--------------------------------------------------------------------------------
Click(Button("End"))
local live6 = MD.Replay._live()
local st6 = MD.Replay._state()
local reopened = live6 == nil and MD:GetRecording("p1") ~= nil
    and st6.rp and not st6.rp.live and st6.rp.rec == MD:GetRecording("p1")

local reviewParent = CreateFrame("Frame")
local review = MD.DashboardParts.CreateReview(reviewParent, 912)
review.frame:Show()
review:Render()
Click(Button("Practice"))
review:Render()
local listed = false
for _, f in ipairs(S.allFrames) do
    if type(f.text) == "string" and f.text:find("Practice: Duo") and f.shown ~= false then listed = true end
end
check("ending the session reopens it as a replay and lists it in Review", reopened and listed,
    "reopened=" .. tostring(reopened) .. " listed=" .. tostring(listed))

--------------------------------------------------------------------------------
-- 8: every string the panel and the bindings window paint is ASCII with no
--    bare pipe
--------------------------------------------------------------------------------
MD:ShowBindings()
local function Pipes(str)
    -- a colour code, a reset, the client's own "|n" newline escape and a
    -- doubled pipe (Esc's own "||", a literal pipe) are all safe; anything
    -- else left over is BARE.
    local stripped = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", ""):gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
-- ASCII (0x20-0x7e), plus the newline the bindings summary joins its lines
-- with (UI/PracticePanel.lua's BindLines, one font string, several lines).
-- ASCII (0x20-0x7e), plus the newline the bindings summary joins its lines
-- with (UI/PracticePanel.lua's BindLines, one font string, several lines).
local function NonAscii(str) return str:find("[^ -~\n]") ~= nil end
-- UI/Style.lua's own header close button ("x", U+00D7, line 166) -- shared by
-- every Cell-style window in the tree (UI.CreateMovableFrame, which the
-- bindings window uses) and already an accepted, named exception in
-- tools/modulecheck.lua's own ASCII walk.
local CLOSE_GLYPH = "\195\151"
local bad = {}
local function Scan(label, str)
    if type(str) ~= "string" or str == "" or str == CLOSE_GLYPH then return end
    if Pipes(str) then bad[#bad + 1] = label .. " has a bare pipe: " .. str end
    if NonAscii(str) then bad[#bad + 1] = label .. " is not ASCII: " .. str end
end
-- only under the panel's own frame and the bindings window (never UI/Style.lua's
-- own chrome, whose close button is a literal "x" close glyph -- the same
-- named exception tools/modulecheck.lua and tools/reviewforever.lua make)
local function Under(f, root)
    if not root then return false end
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end
local bindingsFrame = MD.BindingsWindow._frame()
for _, f in ipairs(S.allFrames) do
    if f.GetText and (Under(f, panel.frame) or Under(f, bindingsFrame)) then
        local okt, txt = pcall(f.GetText, f)
        if okt and type(txt) == "string" then Scan("frame text", txt) end
    end
end
check("every string the panel and the bindings window paint is ASCII with no bare pipe", #bad == 0, bad[1])

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
