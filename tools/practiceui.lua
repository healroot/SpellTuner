-- tools/run.sh tools/practiceui.lua
--
-- Practice from the author's side of the screen (v0.15.0): the Simulate ->
-- Practice panel, the replay window in practice mode, presses on its frames,
-- the End button, the replay that opens afterwards, and the Review tab's
-- Practice list. Under the stub: frames store what they paint and scripts are
-- called by hand, the way the client would call them.
local here = arg[0]:match("^(.*)/[^/]+$")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
S.Load({ "UI/Style.lua", "UI/Tooltip.lua", "UI/Dashboard_Review.lua", "UI/PracticePanel.lua",
         "UI/ReplayWindow.lua" }, "ManaDemon", MD)
local PR, SD = MD.Practice, MD.SpellData

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-56s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local chat = {}
function MD:Print(m) chat[#chat + 1] = m end
local function Said(pat) for _, m in ipairs(chat) do if m:find(pat) then return m end end end
local function Button(text, parent)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false then return f end
    end
end
local function Click(b, button) local fn = b and b:GetScript("OnClick"); if fn then fn(b, button or "LeftButton") end end

MD.cdb.practice, MD.db.practiceBinds = {}, nil
MD.player.isDruid = true

-- the panel -------------------------------------------------------------------
local parent = CreateFrame("Frame")
local panel = MD.DashboardParts.CreatePractice(parent, 912)
panel.frame:Show()
panel:Render()
check("the panel builds and has a Start button", Button("Start practice") ~= nil)
check("it starts from a party of five", MD.cdb.practiceSetup and #MD.cdb.practiceSetup.targets == 5)
Click(Button("Raid 10"))
check("choosing Raid 10 makes ten", #MD.cdb.practiceSetup.targets == 10)
Click(Button("Party"))
check("and back to five", #MD.cdb.practiceSetup.targets == 5)
check("the bindings list shows your Cell click-casting", Button("BUTTON5") ~= nil and Button("ALT-BUTTON5") ~= nil)
local pipes = false
for _, f in ipairs(S.allFrames) do
    local t = f.text
    if type(t) == "string" and t:gsub("||", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("|", 1, true) then pipes = true end
end
check("no bare pipe on the panel", not pipes)

-- play ------------------------------------------------------------------------
MD.cdb.practiceSetup.dur = 30
MD.cdb.practiceSetup.fixedSeed = 5
Click(Button("Start practice"))
local live, hover = MD.Replay._live()
check("Start opens the window in practice mode", live ~= nil and live.state == "running")
local st = MD.Replay._state()
check("one column, five frames", st.rows and #st.rows == 5 and st.frame:IsShown())
check("the scrubber is hidden: the future has not happened", not st.scrubber:IsShown())
check("an End button is shown", Button("End") ~= nil)

local function Tick(sec)
    local fn = st.frame:GetScript("OnUpdate")
    for _ = 1, math.floor(sec / 0.05 + 0.5) do S.now = S.now + 0.05; fn(st.frame, 0.05) end
end
local tank = st.left.frames[1]
Tick(1.0)
-- Button5 on the tank: Lifebloom, as Cell has it
tank:GetScript("OnMouseDown")(tank, "Button5")
Tick(0.3)
check("Button5 on a frame casts Lifebloom on it", live.own[1] and live.own[1].x == SD.maxRank.Lifebloom
    and live.own[1].tgt == 1, live.own[1] and tostring(live.own[1].x))
Tick(1.5)
check("the frame shows the HoT", tank.hots[3]:IsShown())
-- a key over a frame: bind "1" to Regrowth, hover the tank, press 1
table.insert(PR.Binds(), { key = "1", family = "Regrowth" })
tank:GetScript("OnEnter")(tank)
local _, hov = MD.Replay._live()
check("hovering a frame makes it the mouseover", hov == 1)
st.frame:GetScript("OnKeyDown")(st.frame, "1")
Tick(2.5)
local casts = 0
for _, o in ipairs(live.own) do if o.kind == MD.SimModel.K.OWNCAST then casts = casts + 1 end end
check("a bound key over a frame casts on it", casts == 2, tostring(casts))
-- a press with nothing to eat names the reason
local ranged = st.left.frames[4]
ranged:GetScript("OnMouseDown")(ranged, "RightButton")
Tick(0.2)
check("a refused press says why", (st.frame.hint.text or ""):find("Nothing to consume") ~= nil, st.frame.hint.text)
-- space pauses
st.frame:GetScript("OnKeyDown")(st.frame, "SPACE")
local was = live.clock
Tick(1)
check("space pauses the fight", live.clock == was and live.paused)
st.frame:GetScript("OnKeyDown")(st.frame, "SPACE")
Tick(1)
check("and resumes it", live.clock > was)
check("the clock reads the fight", (st.timeFS.text or ""):find("/ 0:30") ~= nil, st.timeFS.text)

-- end -------------------------------------------------------------------------
Click(Button("End"))
local live2 = MD.Replay._live()
check("End leaves practice mode", live2 == nil)
check("what was played is kept as p1", MD:GetRecording("p1") ~= nil and MD:GetRecording("p1").ownCasts == 2)
check("and says where to find it", Said("kept as") ~= nil, Said("kept as"))
local st2 = MD.Replay._state()
check("it opens as an ordinary replay", st2.rp and not st2.rp.live and st2.rp.rec == MD:GetRecording("p1"))
check("with the scrubber back", st2.scrubber:IsShown())
check("the replay validates: same engine", st2.rp.validation and st2.rp.validation.ok)

-- review ----------------------------------------------------------------------
local reviewParent = CreateFrame("Frame")
local review = MD.DashboardParts.CreateReview(reviewParent, 912)
review.frame:Show()
review:Render()
Click(Button("Practice"))
review:Render()
local listed = false
for _, f in ipairs(S.allFrames) do
    if type(f.text) == "string" and f.text:find("Practice: Party") and f.shown ~= false then listed = true end
end
check("Review lists it under Practice", listed)

-- closing the window mid-fight keeps it --------------------------------------------
MD:OpenPractice(PR.CopySetup(MD.cdb.practiceSetup), 6)
local st3 = MD.Replay._state()
local f1 = st3.left.frames[1]
Tick(0.5)
f1:GetScript("OnMouseDown")(f1, "Button5")
Tick(1)
st3.frame:Hide()
check("closing the window ends practice and keeps it", MD.Replay._live() == nil and #MD.cdb.practice == 2)
check("closing does not reopen the window", not st3.frame:IsShown())

-- combat ends it ----------------------------------------------------------------
MD:OpenPractice(PR.CopySetup(MD.cdb.practiceSetup), 7)
Tick(0.5)
S.Fire("PLAYER_REGEN_DISABLED")
check("entering combat ends practice", MD.Replay._live() == nil and not MD.Replay._state().frame:IsShown())

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
