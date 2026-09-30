-- tools/run.sh tools/practiceui.lua
--
-- Practice from the author's side of the screen (v0.15.0): the Simulate ->
-- Practice panel, the replay window in practice mode, presses on its frames,
-- the End button, the replay that opens afterwards, and the Review tab's
-- Practice list. Under the stub: frames store what they paint and scripts are
-- called by hand, the way the client would call them.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
S.Load({ "UI/Style.lua", "UI/Tooltip.lua", "UI/Dashboard_Review.lua", "UI/PracticePanel.lua",
         "UI/BindingsWindow.lua", "UI/ReplayWindow.lua" }, "SpellTuner", MD)
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
local bindSummary = nil
for _, f in ipairs(S.allFrames) do
    if type(f.text) == "string" and f.text:find("BUTTON5") and f.text:find("Lifebloom") then bindSummary = f end
end
check("the panel lists what your presses cast", bindSummary ~= nil)
check("and has a button to edit them", Button("Edit bindings") ~= nil)
local pipes = false
for _, f in ipairs(S.allFrames) do
    local t = f.text
    if type(t) == "string" and t:gsub("||", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("|", 1, true) then pipes = true end
end
check("no bare pipe on the panel", not pipes)

-- the bindings window ---------------------------------------------------------
Click(Button("Edit bindings"))
local bw = MD.BindingsWindow._frame()
check("the bindings window opens", bw ~= nil and bw:IsShown())
local brows = MD.BindingsWindow._rows()
check("one row per binding", #brows >= 6 and brows[1].key.text:find("BUTTON5") ~= nil,
    brows[1] and brows[1].key.text)
-- rebind row 1 to Alt-Q by clicking its key box and pressing
brows[1].key:GetScript("OnClick")(brows[1].key, "LeftButton")
check("clicking a key box waits for a press", brows[1].key.text:find("press") ~= nil, brows[1].key.text)
S.altDown = true
brows[1].key:GetScript("OnKeyDown")(brows[1].key, "Q")
S.altDown = false
check("the press becomes the binding", PR.Binds()[1].key == "ALT-Q", PR.Binds()[1].key)
check("and it casts what it did", select(2, PR.BindFor("ALT-Q")) == SD.maxRank.Lifebloom)
-- the spell picker is a tree: families, ranks under them (v0.15.2)
local dd = brows[2].spell
dd:GetScript("OnClick")(dd)
check("the picker opens a short list, one row per family", dd.list:IsShown() and #dd.items <= 6,
    tostring(#dd.items))
local rejRow
for _, r in ipairs(dd.rows) do if r.text and r.text:find("Rejuvenation") then rejRow = r end end
local plain = rejRow and rejRow.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or ""
check("no rank is in the top list", rejRow ~= nil and not plain:find("%d"), plain)
rejRow:GetScript("OnEnter")(rejRow)
check("hovering a family shows its ranks beside it", dd.sub:IsShown() and #dd.subRows > 3,
    tostring(#dd.subRows))
local rank5
for _, r in ipairs(dd.subRows) do if r.text == "Rejuvenation 5" then rank5 = r end end
check("and one of them is the rank you want", rank5 ~= nil)
Click(rank5)
check("clicking it binds that rank", PR.Binds()[2].family == "Rejuvenation" and PR.Binds()[2].rank == 5)
check("and the list closes", not dd.list:IsShown() and not dd.sub:IsShown())
Click(Button("Defaults"))

Click(Button("+ binding"))
check("a binding can be added", #PR.Binds() == 7 and PR.Binds()[7].key == "")
Click(brows[7].del)
check("and removed", #PR.Binds() == 6)

-- import: the author's own Cell click-castings
S.macros["Main overtime"] = "#showtooltip\n/cast [known:33763,@mouseover,help]Lifebloom;[@mouseover,help]Rejuvenation"
S.macros["efficient Rej"] = "/cast [@mouseover, help, exists][] Rejuvenation(Rank 5)"
_G.CellCharacterDB = { clickCastings = { useCommon = true, common = {
    { "type5", "macro", "Main overtime" },
    { "shift-type5", "macro", "efficient Rej" },
    { "type1", "target" },
} } }
table.insert(PR.Binds(), { key = "CTRL-E", family = "Swiftmend" })   -- one of your own
PR.BindFor("SHIFT-BUTTON5").rank = nil                                -- and one Cell will correct
Click(Button("Cell"))
check("Import from Cell adds on top: your own binding stays", select(2, PR.BindFor("CTRL-E")) == SD.maxRank.Swiftmend
    and #PR.Binds() == 7, tostring(#PR.Binds()))
local _, r5 = PR.BindFor("SHIFT-BUTTON5")
check("and a key both had now casts Cell's spell", r5 and SD.spells[r5].rank == 5)
local report = MD.BindingsWindow._status()
check("it says what it added, replaced and kept", report:find("0 added") and report:find("1 replaced")
    and report:find("kept") and report:find("target"), report)
_G.CellCharacterDB = nil
Click(Button("Clique"))
check("no Clique, and it says so", MD.BindingsWindow._status():find("not loaded") ~= nil,
    MD.BindingsWindow._status())
-- the game's own keybindings
S.macros["Main overtime"] = "/cast [known:33763,@mouseover,help]Lifebloom;[@mouseover,help]Rejuvenation"
S.macroOrder = { "Main overtime" }
S.actions = { [49] = { "macro", 1 }, [13] = { "item", 22795 } }
S.bindings = { { "MULTIACTIONBAR2BUTTON1", "BUTTON5" }, { "MULTIACTIONBAR4BUTTON1", "ALT-F11" } }
Click(Button("Keybindings"))
check("Import Keybindings reads your bars, on top of the rest", #PR.Binds() == 7
    and select(2, PR.BindFor("BUTTON5")) == SD.maxRank.Lifebloom
    and select(2, PR.BindFor("CTRL-E")) == SD.maxRank.Swiftmend, tostring(#PR.Binds()))
check("and reports what it would not guess", MD.BindingsWindow._status():find("ALT%-F11") ~= nil,
    MD.BindingsWindow._status())
S.bindings, S.actions = {}, {}

Click(Button("Defaults"))
check("Defaults puts your Cell click-casting back", #PR.Binds() == 6
    and select(2, PR.BindFor("SHIFT-BUTTON5")) ~= nil)
bw:Hide()

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
-- 2026-09-29: a practice fight a report is about can be pinned from Review
local pinB = Button("Pin")
local pinOn = pinB ~= nil and pinB:IsEnabled()
Click(pinB); review:Render()
check("Pin keeps a practice fight past the next eight",
    pinOn and MD:GetRecording("p1").pinned == true and Button("Unpin") ~= nil)
Click(Button("Unpin")); review:Render()

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
S.Fire("PLAYER_REGEN_ENABLED")

-- T51 (P7, B23): the pointer on a frame's icon ----------------------------------
-- The client fires the button's OnLeave as the pointer moves onto one of its
-- mouse-enabled icons, then the icon's OnEnter; leaving the icon outward fires
-- only the icon's OnLeave. "1" is bound to Regrowth above.
do
    MD:OpenPractice(PR.CopySetup(MD.cdb.practiceSetup), 8)
    local live8, st8 = MD.Replay._live(), MD.Replay._state()
    local fn = st8.frame:GetScript("OnUpdate")
    local function T(sec) for _ = 1, math.floor(sec / 0.05 + 0.5) do S.now = S.now + 0.05; fn(st8.frame, 0.05) end end
    local tank8 = st8.left.frames[1]
    local icon = tank8.dot
    T(1.0)
    S.mouseFocus = tank8
    tank8:GetScript("OnEnter")(tank8)
    S.mouseFocus = icon
    tank8:GetScript("OnLeave")(tank8)
    local enter = icon:GetScript("OnEnter")
    if enter then enter(icon) end
    local before = #(live8 and live8.own or {})
    st8.frame:GetScript("OnKeyDown")(st8.frame, "1")
    T(2.5)
    local onTank = false
    for i = before + 1, #(live8 and live8.own or {}) do
        local o = live8.own[i]
        if o.kind == MD.SimModel.K.OWNCAST and o.tgt == 1 then onTank = true end
    end
    check("T51: a key with the pointer on the Swiftmend icon heals that frame", onTank,
        "casts " .. before .. " -> " .. #(live8 and live8.own or {}))

    -- onto a HoT icon from the frame's body (the HoT icons always took the
    -- hover on enter), then out of it, off the frame altogether
    local hot = tank8.hots[1]
    S.mouseFocus = tank8
    tank8:GetScript("OnEnter")(tank8)
    S.mouseFocus = hot
    tank8:GetScript("OnLeave")(tank8)
    local henter = hot:GetScript("OnEnter")
    if henter then henter(hot) end
    S.mouseFocus = nil
    local leave = hot:GetScript("OnLeave")
    if leave then leave(hot) end
    local _, hov8 = MD.Replay._live()
    T(2.0) -- past the GCD, so a refusal can only be the target
    local n0 = #(live8 and live8.own or {})
    st8.frame:GetScript("OnKeyDown")(st8.frame, "1")
    T(0.2)
    check("T51: after leaving an icon outward a key reports No target",
        hov8 == nil and #(live8 and live8.own or {}) == n0
          and (st8.frame.hint.text or ""):find("No target") ~= nil,
        "hover=" .. tostring(hov8) .. " hint=" .. tostring(st8.frame.hint.text))
    st8.frame:Hide()
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
