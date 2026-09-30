-- tools/run.sh tools/wincheck.lua
--
-- T32 (docs/SPEC-forever-ui.md 4.3 "Window scale", 6.1, 6.2, 6.7, section 9's T32
-- row): the window manager's core -- UI/Windows_Forever.lua (MD.Win): Register
-- with a role's strata / level / toplevel, the main window anchored TOPLEFT at
-- its saved place (SetUserPlaced(false), clamped to the screen), a size and a
-- minimum per group with the resize grip (UI.CreateMovableFrame opts.resizable),
-- db.ui.scale with the saved position converted, UI.RestylePixels on
-- UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED, MD:SelectView through
-- MD.Win:ShowMain, /st ui reset, and the late grow on MODULE_LOADED gone.
-- Forever only: the TBC TOC does not list the manager.
--
-- The stub's frames have no geometry by default (GetLeft is 0, SetPoint a
-- no-op), so this suite switches on the stub's opt-in one, S.Geometry(true)
-- (T54: it was this suite's own until then): a scale per frame, points
-- recorded, GetLeft / GetTop computed in a 768-high base space (UIParent's
-- effective scale is the game's UI scale, as UI.px assumes) and a
-- deterministic text metric. It goes on after the addon loads (the main window
-- is built on first use, so every window this suite opens has it). T33 / T34
-- extend this file (T33: the ESC stack and combat, section 11; T34: the
-- replay and practice takeover, section 12; T42: Settings -> General's
-- controls, section 13).
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-78s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < (eps or 1e-6) end
local function fmt(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local UI = MD.UI

--------------------------------------------------------------------------------
-- Geometry: the stub's opt-in one (T54, P10, review Q12 -- this suite's own
-- until then, promoted into tools/wowstub.lua's S.Geometry unchanged, plus a
-- deterministic text metric), switched on after the addon loads at the game's
-- UI scale this suite has always used.
--------------------------------------------------------------------------------
local FM = getmetatable(UIParent)
S.uiScale = 0.71
S.Geometry(true)

-- A drag: the client moves the frame and the kit's OnDragStop calls OnMoved.
local function DragTo(f, x, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    local stop = f.header and f.header:GetScript("OnDragStop")
    if stop then stop(f.header) end
end
-- A resize: the grip's mouse-up after the client sized the frame.
local function ResizeTo(f, w, h)
    f:SetSize(w, h)
    local up = f.resizeGrip and f.resizeGrip:GetScript("OnMouseUp")
    if up then up(f.resizeGrip, "LeftButton") end
end

local Win = MD.Win

--------------------------------------------------------------------------------
-- 1. The manager is on the Forever TOCs only
--------------------------------------------------------------------------------
do
    local function has(toc)
        for _, f in ipairs(S.TocFiles(toc)) do if f == "UI/Windows_Forever.lua" then return true end end
        return false
    end
    check("UI/Windows_Forever.lua is in both Forever TOCs and not in TBC's",
        has("SpellTuner_Mainline.toc") and has("SpellTuner.toc") and not has("SpellTuner_TBC.toc"))
    check("MD.Win exists with Register, ShowMain, SetScale and Reset",
        type(Win) == "table" and type(Win.Register) == "function" and type(Win.ShowMain) == "function"
          and type(Win.SetScale) == "function" and type(Win.Reset) == "function")
end
if type(Win) ~= "table" then
    -- nothing below can run without the manager
    print(string.format("%d ok, %d failed (stopped: no MD.Win)", ok, #fails)); os.exit(1)
end

--------------------------------------------------------------------------------
-- 2. MD:SelectView goes through MD.Win:ShowMain; the main window registers
--------------------------------------------------------------------------------
local shown = {}
do
    local orig = Win.ShowMain
    Win.ShowMain = function(self, g, v) shown[#shown + 1] = { g, v }; return orig(self, g, v) end
    MD:SelectView("spells", "book")
    Win.ShowMain = orig
end
local frame = _G.SpellTunerDashboard
check("MD:SelectView is routed through MD.Win:ShowMain(group, view)",
    #shown == 1 and shown[1][1] == "spells" and shown[1][2] == "book" and frame and frame:IsShown())
check("the main window is registered as the host",
    Win.windows and Win.windows.main and Win.windows.main.frame == frame and Win.windows.main.role == "host")

--------------------------------------------------------------------------------
-- 3. Strata per 6.2: HIGH / 10 and toplevel; SetUserPlaced(false); clamped
--------------------------------------------------------------------------------
check("the main window is HIGH / 10 and toplevel (6.2)",
    frame:GetFrameStrata() == "HIGH" and frame:GetFrameLevel() == 10 and frame:IsToplevel(),
    frame:GetFrameStrata() .. "/" .. tostring(frame:GetFrameLevel()))
check("the main window is not user-placed and is clamped to the screen",
    frame.userPlaced == false and frame:IsClampedToScreen())
do
    local p, rel, rp = frame:GetPoint(1)
    check("the main window is anchored by its TOPLEFT to UIParent's BOTTOMLEFT",
        frame:GetNumPoints() == 1 and p == "TOPLEFT" and rel == UIParent and rp == "BOTTOMLEFT",
        tostring(p) .. " " .. tostring(rp))
end
check("the role table gives a takeover DIALOG and a tool FULLSCREEN (6.1, 6.2)",
    Win.ROLES and Win.ROLES.takeover and Win.ROLES.takeover.strata == "DIALOG"
      and Win.ROLES.tool and Win.ROLES.tool.strata == "FULLSCREEN")

--------------------------------------------------------------------------------
-- 4. Sizes per group (6.7), the grip, the minimum
--------------------------------------------------------------------------------
check("Spells opens at 860 x 560 with the minimum 860 x 480",
    frame:GetWidth() == 860 and frame:GetHeight() == 560 and frame.bounds
      and frame.bounds[1] == 860 and frame.bounds[2] == 480,
    frame:GetWidth() .. "x" .. frame:GetHeight())
check("the main window is resizable, with a 16x16 grip at the bottom right",
    frame:IsResizable() and frame.resizeGrip and frame.resizeGrip:GetWidth() == 16
      and frame.resizeGrip:GetHeight() == 16)

local l0, t0 = frame:GetLeft(), frame:GetTop()
MD:SelectView("reports", "review")
check("switching Spells -> Reports gives 1036 x 646 and a 1036 x 600 minimum",
    frame:GetWidth() == 1036 and frame:GetHeight() == 646 and frame.bounds
      and frame.bounds[1] == 1036 and frame.bounds[2] == 600,
    frame:GetWidth() .. "x" .. frame:GetHeight())
check("switching Spells -> Reports keeps the TOPLEFT (the nav stays put)",
    near(frame:GetLeft(), l0, 1e-3) and near(frame:GetTop(), t0, 1e-3),
    fmt(l0) .. "," .. fmt(t0) .. " -> " .. fmt(frame:GetLeft()) .. "," .. fmt(frame:GetTop()))

MD:SelectView("spells", "book")
ResizeTo(frame, 900, 600)
MD:SelectView("reports", "review")
local reportsW = frame:GetWidth()
MD:SelectView("spells", "book")
check("a per-group size is restored: Spells resized to 900 x 600 comes back so",
    reportsW == 1036 and frame:GetWidth() == 900 and frame:GetHeight() == 600,
    tostring(reportsW) .. " / " .. frame:GetWidth() .. "x" .. frame:GetHeight())
do
    local sv = MD.db.ui.win.main
    check("the group's size is saved in db.ui.win.main.sizes",
        sv and sv.sizes and sv.sizes.spells and sv.sizes.spells[1] == 900 and sv.sizes.spells[2] == 600)
end
ResizeTo(frame, 700, 300)
check("a size under the group's minimum is raised to it (860 x 480)",
    frame:GetWidth() == 860 and frame:GetHeight() == 480,
    frame:GetWidth() .. "x" .. frame:GetHeight())

--------------------------------------------------------------------------------
-- 5. A drag saves the TOPLEFT; a clamp; the saved place comes back
--------------------------------------------------------------------------------
DragTo(frame, 120, 900)
do
    local sv = MD.db.ui.win.main
    check("a drag saves the TOPLEFT in db.ui.win.main (frame units, from BOTTOMLEFT)",
        sv and near(sv.x, 120) and near(sv.y, 900) and frame.userPlaced == false,
        sv and (fmt(sv.x) .. "," .. fmt(sv.y)) or "nil")
end
do
    -- the screen in the frame's units: 1920x1080 at UI scale 0.71, window scale 1
    local sw = UIParent:GetWidth()
    DragTo(frame, sw - 100, 900)
    local es = frame:GetEffectiveScale()
    local right = (frame:GetLeft() + frame:GetWidth())
    check("a window dragged past the right edge is clamped back onto the screen",
        near(right, sw, 1e-3), "right " .. fmt(right) .. " screen " .. fmt(sw) .. " es " .. fmt(es))
    MD:SelectView("reports", "review")
    local rightReports = frame:GetLeft() + frame:GetWidth()
    check("a bigger group that would run off the screen is pulled back in",
        near(rightReports, sw, 1e-3) and frame:GetWidth() == 1036, fmt(rightReports))
    DragTo(frame, 50, 5000)
    check("a window above the screen is clamped so its header stays on it",
        near(frame:GetTop(), UIParent:GetHeight() - 20, 1e-3), fmt(frame:GetTop()))
    MD:SelectView("spells", "book")
end

--------------------------------------------------------------------------------
-- 6. db.ui.scale: SetScale applies it and converts the saved position
--------------------------------------------------------------------------------
DragTo(frame, 100, 700)
do
    local es0 = frame:GetEffectiveScale()
    local pxL, pxT = frame:GetLeft() * es0, frame:GetTop() * es0
    Win:SetScale(0.8)
    local sv = MD.db.ui.win.main or {}
    local es1 = frame:GetEffectiveScale()
    check("MD.Win:SetScale(0.8) writes db.ui.scale and scales the window",
        MD.db.ui.scale == 0.8 and frame:GetScale() == 0.8)
    check("a scale change converts the saved position (x * old / new)",
        near(sv.x, 100 / 0.8) and near(sv.y, 700 / 0.8), fmt(sv.x) .. "," .. fmt(sv.y))
    check("after a scale change the window's TOPLEFT is where it was on screen",
        near(frame:GetLeft() * es1, pxL, 1e-3) and near(frame:GetTop() * es1, pxT, 1e-3))
    Win:SetScale(5)
    check("the window scale is held to 70-120 %", MD.db.ui.scale == 1.2 and frame:GetScale() == 1.2)
    Win:SetScale(1)
end

-- T51 (P7, B17): a scale change converts EVERY saved place, not only the
-- windows registered this session. The replay window is not built yet here, so
-- its saved place is db.ui.win.replay alone; a change 1.0 -> 0.8 must carry it
-- to x * 1.0 / 0.8, or the next /st replay opens 20 % toward the bottom-left.
do
    local notYet = Win.windows.replay == nil
    MD.db.ui.win.replay = { x = 100, y = 700 }
    Win:SetScale(0.8)
    local sv = MD.db.ui.win.replay
    check("T51: a scale change converts a saved place whose window is not registered yet",
        notYet and near(sv.x, 100 / 0.8) and near(sv.y, 700 / 0.8),
        "registered=" .. tostring(not notYet) .. " " .. fmt(sv.x) .. "," .. fmt(sv.y))
    Win:SetScale(1)
    MD.db.ui.win.replay = nil
end

--------------------------------------------------------------------------------
-- 7. UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED restyle the pixel edges
--------------------------------------------------------------------------------
do
    local function edge() return frame.backdrop and frame.backdrop.edgeSize end
    local before = edge()
    S.physicalHeight, S.physicalWidth = 1440, 2560
    S.Fire("UI_SCALE_CHANGED")
    local want = (768 / 1440) / frame:GetEffectiveScale()
    check("UI_SCALE_CHANGED restyles the window's 1-px edge",
        near(edge(), want) and not near(before, want), fmt(before) .. " -> " .. fmt(edge()))
    S.uiScale = 0.64
    S.Fire("DISPLAY_SIZE_CHANGED")
    local want2 = (768 / 1440) / frame:GetEffectiveScale()
    check("DISPLAY_SIZE_CHANGED restyles it too", near(edge(), want2), fmt(edge()))
    local e3 = edge()
    Win:SetScale(0.9)
    check("a window scale change restyles it", near(edge(), (768 / 1440) / (0.64 * 0.9)) and not near(e3, edge()),
        fmt(edge()))
    Win:SetScale(1)
    S.physicalHeight, S.physicalWidth, S.uiScale = 1080, 1920, 0.71
    S.Fire("UI_SCALE_CHANGED")
end

-- T51 (P7, B18): a frame styled at UIParent's scale and then registered at a
-- window scale of 0.8 has its 1-px edges re-snapped at 0.8 by Register, not
-- left at the scale it was styled under until the next UI_SCALE_CHANGED.
do
    Win:SetScale(0.8)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(300, 200)
    UI.StylizeFrame(f)
    local styled = f.backdrop and f.backdrop.edgeSize
    Win:Register(f, { key = "t51edges", role = "tool" })
    local e = f.backdrop and f.backdrop.edgeSize
    check("T51: a frame registered at 0.8 has its 1-px edge snapped at 0.8",
        f:GetScale() == 0.8 and near(e, UI.px(1, f)) and not near(styled, e),
        fmt(styled) .. " -> " .. fmt(e) .. " want " .. fmt(UI.px(1, f)))
    Win.windows.t51edges = nil
    MD.db.ui.win.t51edges = nil
    f:Hide()
    Win:SetScale(1)
end

--------------------------------------------------------------------------------
-- 8. The late grow is gone: the Replay module loading resizes nothing
--------------------------------------------------------------------------------
do
    MD:SelectView("spells", "book")
    local w, h = frame:GetWidth(), frame:GetHeight()
    local had = MD.DashboardParts.CreateReview
    MD.DashboardParts.CreateReview = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        return { frame = f, Render = function() end }
    end
    MD:Fire("MODULE_LOADED", "SpellTuner_Replay")
    MD.DashboardParts.CreateReview = had
    check("MODULE_LOADED no longer grows the window (Spells keeps its size)",
        frame:GetWidth() == w and frame:GetHeight() == h, frame:GetWidth() .. "x" .. frame:GetHeight())
end

--------------------------------------------------------------------------------
-- 9. /st ui reset: every saved place and size gone, the window back at centre
--------------------------------------------------------------------------------
do
    DragTo(frame, 10, 500)
    ResizeTo(frame, 950, 620)
    SlashCmdList.SPELLTUNER("ui reset")
    local win = MD.db.ui.win
    check("/st ui reset clears db.ui.win", type(win) == "table" and next(win) == nil)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local cx = frame:GetLeft() + frame:GetWidth() / 2
    local cy = frame:GetTop() - frame:GetHeight() / 2
    check("after a reset the window is centred at its group's default size, TOPLEFT-anchored",
        frame:GetWidth() == 860 and frame:GetHeight() == 560 and near(cx, sw / 2, 1e-3)
          and near(cy, sh / 2, 1e-3) and (frame:GetPoint(1)) == "TOPLEFT",
        fmt(cx) .. "," .. fmt(cy))
end

--------------------------------------------------------------------------------
-- 10. A saved place survives a reload (a new session reads db.ui.win.main)
--------------------------------------------------------------------------------
do
    -- what a reload reads back: a saved place and one group's saved size
    MD.db.ui.win.main = { x = 200, y = 800, sizes = { reports = { 1100, 700 } } }
    Win:Place("main")
    MD:SelectView("reports", "review")
    check("a saved place and a group's saved size are used when the window is placed",
        near(frame:GetLeft(), 200) and near(frame:GetTop(), 800) and frame:GetWidth() == 1100
          and frame:GetHeight() == 700, fmt(frame:GetLeft()) .. "," .. fmt(frame:GetTop()))
end

--------------------------------------------------------------------------------
-- 11. T33 (6.5, 6.6): the ESC stack and combat. ESC is the client's
-- CloseSpecialWindows: every shown frame named in UISpecialFrames hidden in one
-- press; "the next frame" is a tick of the stub's clock, which runs the
-- C_Timer.After callbacks then due (T54, P10, review Q8: it used to run the
-- queued ones by hand).
--------------------------------------------------------------------------------
FM.GetName = function(self) return self.frameName end
local function NextFrame() S.Tick(0) end
local function Esc()
    local list = {}
    for _, name in ipairs(UISpecialFrames) do list[#list + 1] = name end
    for _, name in ipairs(list) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
end
local function InSpecial(name)
    for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
    return false
end
local function Stack() return type(Win.stack) == "table" and Win.stack or {} end
local function Top() local s = Stack(); return s[#s] and s[#s].frame end
local function EntriesFor(f)
    local n = 0
    for _, e in ipairs(Stack()) do if e.frame == f then n = n + 1 end end
    return n
end

NextFrame()
MD:SelectView("spells", "book")
MD:ToggleDebugConsole()
local console = _G.SpellTunerDebugConsole
local proxy = _G.SpellTunerEscProxy

-- the console: a tool in FULLSCREEN, one stack entry, out of UISpecialFrames
check("T33: the console is one entry: FULLSCREEN / 10 on top of the stack, not a special frame",
    console and console:IsShown() and console:GetFrameStrata() == "FULLSCREEN" and console:GetFrameLevel() == 10
      and console:IsToplevel() and EntriesFor(console) == 1 and Top() == console
      and not InSpecial("SpellTunerDebugConsole") and not InSpecial("SpellTunerDashboard")
      and proxy ~= nil and InSpecial("SpellTunerEscProxy") and proxy:IsShown(),
    console and (console:GetFrameStrata() .. "/" .. tostring(console:GetFrameLevel()) .. " entries "
      .. EntriesFor(console) .. " special " .. tostring(InSpecial("SpellTunerDebugConsole"))) or "no console")

-- one ESC, one entry: a dropdown list (UI.OnPopup), then the console, then the main window
do
    local dd = UI.CreateDropdown(frame, 120, 18)
    dd:SetItems({ { id = 1, text = "one" }, { id = 2, text = "two" } })
    dd:GetScript("OnClick")(dd)
    local listTop = Top() == dd.list and dd.list:IsShown()
    Esc()
    local a = not dd.list:IsShown() and console:IsShown() and frame:IsShown() and #Stack() == 2
    NextFrame()
    Esc()
    local b = not console:IsShown() and frame:IsShown() and #Stack() == 1 and Top() == frame
    check("T33: one ESC closes one entry: the list, then the console, the main window last",
        listTop and a and b, tostring(listTop) .. " " .. tostring(a) .. " " .. tostring(b))
end

-- the proxy re-arms on the next frame, and the last ESC leaves it down
do
    local downAfterPress = proxy ~= nil and not proxy:IsShown()
    NextFrame()
    local rearmed = proxy ~= nil and proxy:IsShown()
    Esc()
    NextFrame()
    check("T33: the proxy re-arms on the next frame; the last ESC closes the main window and leaves it down",
        downAfterPress and rearmed and not frame:IsShown() and #Stack() == 0 and not proxy:IsShown(),
        tostring(downAfterPress) .. " " .. tostring(rearmed) .. " " .. #Stack())
end

-- a window closed by its x leaves no entry
do
    MD:SelectView("spells", "book")
    MD:ToggleDebugConsole()
    local two = #Stack() == 2
    console.header.closeBtn:GetScript("OnClick")(console.header.closeBtn)
    local one = #Stack() == 1 and Top() == frame and proxy ~= nil and proxy:IsShown()
    frame.header.closeBtn:GetScript("OnClick")(frame.header.closeBtn)
    check("T33: a window closed by its x leaves no entry, and the proxy goes down with the last",
        two and one and #Stack() == 0 and proxy ~= nil and not proxy:IsShown(),
        tostring(two) .. " " .. tostring(one))
end

-- the stack emptied by code: the proxy hides quietly, nothing is popped or recorded
do
    local calls = 0
    local A = CreateFrame("Frame", "SpellTunerTestA", UIParent)
    local B = CreateFrame("Frame", "SpellTunerTestB", UIParent)
    A:Show(); B:Show()
    if Win.Push then
        Win:Push(A, function() calls = calls + 1 end)
        Win:Push(B, function() calls = calls + 1 end)
    end
    local rec = MD.db.ui.escTest
    local queued = S.Pending() -- T54 (P10): the pending timers
    -- UIParent hidden (Alt+Z): the client runs OnHide on frames that stay
    -- shown; neither the proxy's nor a window's may pop or drop anything
    if proxy then proxy:GetScript("OnHide")(proxy) end
    A:GetScript("OnHide")(A)
    local altZ = #Stack() == 2
    B:Hide()
    local still = proxy ~= nil and proxy:IsShown() and #Stack() == 1
    A:Hide()
    check("T33: a code hide of the proxy pops nothing: no onEsc, no press recorded, quiet cleared",
        altZ and still and calls == 0 and not proxy:IsShown() and proxy.quiet == nil and #Stack() == 0
          and MD.db.ui.escTest == rec and S.Pending() == queued,
        tostring(altZ) .. " " .. tostring(still) .. " calls " .. calls)
end

-- practice's entry: its first ESC pauses and stays, the second ends it
do
    local P = UI.CreateMovableFrame("Practice", "SpellTunerTestPractice", 492, 400, nil, nil, true)
    local paused, ended = false, false
    P:Show()
    if Win.Push then
        Win:Push(P, function(f)
            if not paused then paused = true; return true end
            ended = true
            f:Hide()
        end)
    end
    Esc()
    local first = P:IsShown() and paused and not ended and Top() == P and #Stack() == 1
    NextFrame()
    local armed = proxy ~= nil and proxy:IsShown()
    Esc()
    NextFrame()
    check("T33: practice's entry stays on its first ESC (pause) and goes on the second (end)",
        first and armed and ended and not P:IsShown() and #Stack() == 0 and not proxy:IsShown(),
        tostring(first) .. " " .. tostring(armed) .. " " .. tostring(ended))
    P:Hide()
end

-- combat: hide, then back on the same view; "keep" leaves it
do
    MD.db.ui.combat = "hide"
    MD:SelectView("reports", "review")
    S.Fire("PLAYER_REGEN_DISABLED")
    local hidden = not frame:IsShown() and #Stack() == 0 and proxy ~= nil and not proxy:IsShown()
    MD:SelectView("spells", "book")   -- a command in combat opens it (nothing auto-opens) ...
    frame:Hide()                      -- ... and the player closes it again
    S.Fire("PLAYER_REGEN_ENABLED")
    local g, v = MD:SelectedView()
    local back = frame:IsShown() and g == "reports" and v == "review" and Top() == frame
    MD.db.ui.combat = "keep"
    S.Fire("PLAYER_REGEN_DISABLED")
    local kept = frame:IsShown()
    S.Fire("PLAYER_REGEN_ENABLED")
    MD.db.ui.combat = "hide"
    check("T33: combat hides the main window and restores it on the same view; keep leaves it",
        hidden and back and kept, tostring(hidden) .. " " .. tostring(back) .. " " .. tostring(g) .. "/"
          .. tostring(v) .. " " .. tostring(kept))
end

-- during a takeover only the replay comes back
do
    local R = UI.CreateMovableFrame("Replay", "SpellTunerTestReplay", 492, 400, nil, nil, true)
    Win:Register(R, { key = "testreplay", role = "takeover" })
    frame:Hide()
    R:Show()
    local onStack = Top() == R and R:GetFrameStrata() == "DIALOG"
    S.Fire("PLAYER_REGEN_DISABLED")
    local gone = not R:IsShown() and not frame:IsShown()
    S.Fire("PLAYER_REGEN_ENABLED")
    check("T33: during a takeover combat hides the replay, and only the replay comes back",
        onStack and gone and R:IsShown() and not frame:IsShown() and Top() == R,
        tostring(onStack) .. " " .. tostring(gone) .. " " .. tostring(R:IsShown()) .. " " .. tostring(frame:IsShown()))
    R:Hide()
    Win.windows.testreplay = nil
end

-- db.ui.escStack = false: today's per-window entries, and back
do
    if Win.SetEscStack then Win:SetEscStack(false) end
    MD:SelectView("spells", "book")
    local fallback = MD.db.ui.escStack == false and InSpecial("SpellTunerDashboard")
      and proxy ~= nil and not proxy:IsShown() and #Stack() == 0
    Esc()
    local closed = not frame:IsShown()
    if Win.SetEscStack then Win:SetEscStack(true) end
    MD:SelectView("spells", "book")
    check("T33: db.ui.escStack = false falls back to one UISpecialFrames entry per window, and back",
        fallback and closed and MD.db.ui.escStack == true and not InSpecial("SpellTunerDashboard")
          and Top() == frame and proxy ~= nil and proxy:IsShown(),
        tostring(fallback) .. " " .. tostring(closed))
end

--------------------------------------------------------------------------------
-- 12. T34 (6.3): the replay and the practice session take the main window's
-- place. The Practice module brings Recorder and Replay with it; the replay
-- plays a tools/foreverfixture.lua stream. A "chat" open is one with the main
-- window hidden; Review's Play is MD.Replay:Open with it shown.
--------------------------------------------------------------------------------
local function CapturedChat(body)
    local lines = {}
    local cf = _G.DEFAULT_CHAT_FRAME
    local orig = cf.AddMessage
    cf.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    cf.AddMessage = orig
    return lines
end
local function Under(f, root)
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end
local function ButtonUnder(root, text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and Under(f, root) then return f end
    end
    return nil
end
local function Click(b) local fn = b and b:GetScript("OnClick"); if fn then fn(b, "LeftButton") end end
-- a frame's top centre in screen pixels (6.3's cx / top)
local function TopCentrePx(f)
    local es = f:GetEffectiveScale()
    return (f:GetLeft() + f:GetWidth() / 2) * es, f:GetTop() * es
end

-- T70 (P26, U24): before the Replay module loads (the next line loads it),
-- Settings -> General's REVIEW pane is shown but not live -- its keys are the
-- module's (Engine/SimModel.lua registers them) -- and it says so; About lists
-- each module that is not loaded as one line instead of commands it has not
-- registered yet.
local function GeneralPane()
    for _, f in ipairs(S.allFrames) do
        if f.fontSlider and f.reviewChecks then return f end
    end
    return nil
end
local function AboutPane()
    for _, f in ipairs(S.allFrames) do
        if f.about == true and f.rows then return f end
    end
    return nil
end
local function AboutRows(p)
    local out = {}
    for i = 1, (p and p.shown or 0) do
        local r = p.rows[i]
        out[#out + 1] = { usage = r.usage:GetText(), text = r.text:GetText() or "", command = r.command, tips = r.tooltips }
    end
    return out
end
do
    MD:SelectView("settings", "general")
    local p = GeneralPane()
    local allOff = p ~= nil and #p.reviewChecks == 4
    for _, c in ipairs(p and p.reviewChecks or {}) do
        if c.check:IsEnabled() then allOff = false end
    end
    local sliderOff = p and p.fullHpSlider and not p.fullHpSlider:IsEnabled()
    local note = p and p.reviewNote and p.reviewNote:GetText()
    MD:SelectView("settings", "about")
    local rows = AboutRows(AboutPane())
    local replayLine, replayCmd = false, false
    for _, r in ipairs(rows) do
        if r.usage == "Replay" and r.text:find("off: its commands are listed here once it is on", 1, true) then
            replayLine = true
        end
        if r.usage and r.usage:find("^/st replay") then replayCmd = true end
    end
    check("T70: with Replay not loaded, REVIEW is shown disabled and says so; About lists Replay as off",
        allOff and sliderOff and note == "needs the Replay module - off" and replayLine and not replayCmd
          and MD:ModuleState("SpellTuner_Replay") ~= "loaded",
        string.format("checksOff=%s sliderOff=%s note=%s replayLine=%s replayCmd=%s", tostring(allOff),
          tostring(sliderOff), tostring(note), tostring(replayLine), tostring(replayCmd)))
end

MD:SetModule("SpellTuner_Practice", true)
MD.player.isDruid = true
local buildFixture = dofile(here .. "/foreverfixture.lua")
local recT34 = buildFixture()
recT34.id = 2000000000
MD.cdb.recordings = { recT34 }
MD.cdb.practice = {}
MD.db.replayAutoCoach = false -- no search running under the checks
local mainShows = 0
frame:HookScript("OnShow", function() mainShows = mainShows + 1 end)

-- replayPos migrated once: the old anchor becomes db.ui.win.replay's TOPLEFT,
-- the old key is deleted, and a drag afterwards writes only the new one
local replay, backBtn
do
    frame:Hide()
    MD.db.replayPos = { "TOPLEFT", "BOTTOMLEFT", 40, 600 }
    MD:OpenReplay("1")
    replay = _G.SpellTunerReplayWindow
    backBtn = replay and replay.header and replay.header.backBtn
    local sv = MD.db.ui.win.replay
    local migrated = MD.db.replayPos == nil and sv ~= nil and near(sv.x, 40) and near(sv.y, 600)
      and replay:IsShown() and near(replay:GetLeft(), 40) and near(replay:GetTop(), 600)
    if replay then DragTo(replay, 60, 620) end
    sv = MD.db.ui.win.replay
    check("T34: db.replayPos is migrated into db.ui.win.replay once, then deleted",
        migrated and MD.db.replayPos == nil and sv and near(sv.x, 60) and near(sv.y, 620),
        tostring(migrated) .. " " .. (sv and (fmt(sv.x) .. "," .. fmt(sv.y)) or "nil"))
    if replay then replay:Hide() end
    MD.db.ui.win.replay = nil
end
if not replay then
    print(string.format("%d ok, %d failed (stopped: no replay window)", ok, #fails)); os.exit(1)
end

-- a replay from chat: no back button, centred, a takeover in DIALOG, the main
-- window left hidden
do
    frame:Hide()
    local before = mainShows
    MD:OpenReplay("1")
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local cx = replay:GetLeft() + replay:GetWidth() / 2
    local cy = replay:GetTop() - replay:GetHeight() / 2
    check("T34: a replay from chat has no back button, opens centred in DIALOG, main stays hidden",
        replay:IsShown() and backBtn ~= nil and not backBtn:IsShown() and replay:GetFrameStrata() == "DIALOG"
          and near(cx, sw / 2, 1e-3) and near(cy, sh / 2, 1e-3) and not frame:IsShown() and mainShows == before
          and Top() == replay and not InSpecial("SpellTunerReplayWindow"),
        tostring(backBtn and backBtn:IsShown()) .. " " .. tostring(replay:GetFrameStrata()) .. " "
          .. fmt(cx) .. "," .. fmt(cy))
    replay:Hide()
end

-- Review -> Play: the main window hides with its path; back restores it
do
    MD:SelectView("reports", "review")
    MD.Replay:Open("1")
    local took = replay:IsShown() and not frame:IsShown() and backBtn:IsShown() and Top() == replay
    Click(backBtn)
    local g, v = MD:SelectedView()
    local back = not replay:IsShown() and frame:IsShown() and g == "reports" and v == "review" and Top() == frame
    -- ESC does the same, one entry: the replay, not the main window it gives back
    MD.Replay:Open("1")
    NextFrame()
    Esc()
    NextFrame()
    local g2, v2 = MD:SelectedView()
    local esc = not replay:IsShown() and frame:IsShown() and g2 == "reports" and v2 == "review" and Top() == frame
      and proxy:IsShown()
    check("T34: Play hides the main window with its path; < SpellTuner or ESC closes the replay and restores it",
        took and back and esc and backBtn.text == "< SpellTuner",
        tostring(took) .. " " .. tostring(back) .. " " .. tostring(esc) .. " " .. tostring(g) .. "/" .. tostring(v))
end

-- the placement: the replay's top centre on the main window's, in screen
-- pixels, at UI scales 0.71 and 1 (a window scale of 0.9 on both)
do
    local res = {}
    Win:SetScale(0.9)
    for _, us in ipairs({ 0.71, 1 }) do
        S.uiScale = us
        S.Fire("UI_SCALE_CHANGED")
        MD:SelectView("reports", "review")
        DragTo(frame, 150, 700)
        local mx, mt = TopCentrePx(frame)
        MD.Replay:Open("1")
        local rx, rt = TopCentrePx(replay)
        local p = replay:GetPoint(1)
        res[#res + 1] = { ok = near(mx, rx, 1e-3) and near(mt, rt, 1e-3) and p == "TOP" and not frame:IsShown(),
                          d = fmt(mx) .. "," .. fmt(mt) .. " vs " .. fmt(rx) .. "," .. fmt(rt) .. " " .. tostring(p) }
        Click(backBtn)
    end
    Win:SetScale(1)
    S.uiScale = 0.71
    S.Fire("UI_SCALE_CHANGED")
    check("T34: the replay opens with its top centre on the main window's, at UI scales 0.71 and 1",
        res[1].ok and res[2].ok, res[1].d .. " / " .. res[2].d)
end

-- /st during a replay takeover: the replay closes, the requested view opens
do
    MD:SelectView("reports", "review")
    MD.Replay:Open("1")
    local took = replay:IsShown() and not frame:IsShown()
    SlashCmdList.SPELLTUNER("modules")
    local g, v = MD:SelectedView()
    check("T34: /st modules during a replay takeover closes it and opens Settings -> Modules",
        took and not replay:IsShown() and frame:IsShown() and g == "settings" and v == "modules"
          and Top() == frame,
        tostring(took) .. " " .. tostring(replay:IsShown()) .. " " .. tostring(g) .. "/" .. tostring(v))
end

-- practice: always a takeover; /st refused; ESC pauses, ESC again ends it and
-- opens its replay, the main window never shown; back is Simulate -> Practice
local PR = MD.Practice
local function StartPractice()
    MD:SelectView("simulate", "practice")
    MD.db.practiceBinds = { { key = "1", family = "Rejuvenation" } }
    local setup = PR.DefaultSetup("2", 64)
    setup.dur, setup.fixedSeed = 30, 9
    MD:OpenPractice(setup, 9)
    local live = MD.Replay._live()
    S.Tick(0.5)
    if live then live:Cast(MD.SpellData.maxRank.Rejuvenation, 1) end
    S.Tick(0.5)
    return live
end
do
    local live = StartPractice()
    local took = live ~= nil and replay:IsShown() and not frame:IsShown() and not backBtn:IsShown()
    local before = mainShows
    local lines = CapturedChat(function()
        SlashCmdList.SPELLTUNER("")
        SlashCmdList.SPELLTUNER("modules")
    end)
    local refusedLine = 0
    for _, l in ipairs(lines) do
        if l:find("Practice is running: ESC pauses, ESC again ends it.", 1, true) then refusedLine = refusedLine + 1 end
    end
    check("T34: /st during practice is refused with one line and nothing shows",
        took and refusedLine == 2 and #lines == 2 and not frame:IsShown() and mainShows == before
          and replay:IsShown() and MD.Replay._live() == live,
        tostring(took) .. " lines " .. #lines .. " " .. table.concat(lines, " / "))

    Esc()
    local paused = MD.Replay._live() == live and live.paused == true and replay:IsShown() and Top() == replay
    NextFrame()
    Esc()
    NextFrame()
    local st = MD.Replay._state()
    local reopened = MD.Replay._live() == nil and replay:IsShown() and st.rp and not st.rp.live
      and st.rp.rec == MD:GetRecording("p1") and not frame:IsShown() and mainShows == before
      and backBtn:IsShown() and Top() == replay
    Click(backBtn)
    local g, v = MD:SelectedView()
    check("T34: practice ESC pauses, ESC again ends it into its replay; back goes to Simulate -> Practice",
        paused and reopened and frame:IsShown() and g == "simulate" and v == "practice",
        tostring(paused) .. " " .. tostring(reopened) .. " " .. tostring(g) .. "/" .. tostring(v))
end

-- End opens the replay directly, the main window not shown in between
do
    local live = StartPractice()
    local before = mainShows
    local endBtn = ButtonUnder(replay, "End")
    Click(endBtn)
    local st = MD.Replay._state()
    local ok6 = live ~= nil and endBtn ~= nil and MD.Replay._live() == nil and replay:IsShown()
      and st.rp and not st.rp.live and not frame:IsShown() and mainShows == before and backBtn:IsShown()
    Click(backBtn)
    local g, v = MD:SelectedView()
    check("T34: End opens the replay without showing the main window; back returns to Practice",
        ok6 and frame:IsShown() and g == "simulate" and v == "practice",
        tostring(ok6) .. " " .. tostring(g) .. "/" .. tostring(v))
end

--------------------------------------------------------------------------------
-- 13. T42 (section 9's T42 row, 4.2, 4.3, 6.5, 6.6): Settings -> General's
-- controls. Each writes its db field and applies it at once; a slider is driven
-- as the player types a value into its box (the kit's OnEnterPressed runs both
-- of its callbacks), a dropdown and a button as they are clicked.
--------------------------------------------------------------------------------
MD:SelectView("settings", "general")
local gp
for _, f in ipairs(S.allFrames) do
    if f.fontSlider then gp = f end
end
local function Type(slider, text)
    local eb = slider and slider.currentEditBox
    if not eb then return end
    eb:SetText(text)
    eb:GetScript("OnEnterPressed")(eb)
end
local function Pick(dd, id)
    if not dd then return end
    for i, it in ipairs(dd.items) do
        if it.id == id and dd.rows[i] then dd.rows[i]:GetScript("OnClick")(dd.rows[i]) end
    end
end
local function FontSize(name)
    local obj = (UI.fontObjects and UI.fontObjects[name]) or _G[name]
    if not obj then return nil end
    local _, size = obj:GetFont()
    return size
end
local function Click(b)
    if b and b:GetScript("OnClick") then b:GetScript("OnClick")(b) end
end

do
    local titles = {}
    for _, f in ipairs(S.allFrames) do
        if f.title and f.line and gp and f.parentFrame == gp then titles[f.title:GetText()] = f end
    end
    local detailIn = gp and gp.detailDropdown and gp.detailDropdown.parentFrame
    check("T42: Settings -> General has SPELL TOOLTIPS, APPEARANCE and WINDOWS titled panes",
        gp ~= nil and titles["SPELL TOOLTIPS"] ~= nil and titles["APPEARANCE"] ~= nil and titles["WINDOWS"] ~= nil
          and detailIn == titles["SPELL TOOLTIPS"] and gp.fontSlider.parentFrame == titles["APPEARANCE"]
          and gp.combatDropdown ~= nil and gp.combatDropdown.parentFrame == titles["WINDOWS"],
        (not gp) and "no pane" or nil)
end

do
    local s = gp and gp.fontSlider
    local rail = MD.SpellsPane and MD.SpellsPane.nav and MD.SpellsPane.nav.rails
      and MD.SpellsPane.nav.rails.spells and MD.SpellsPane.nav.rails.spells.rail
    Type(s, "2")
    local rows = rail and rail:Rows() or {}
    local size = FontSize(UI.FONT)
    local row2 = rows[1] and rows[1]:GetHeight()
    local applied = MD.db.ui.fontOffset == 2 and UI.fontOffset == 2 and size == 15 and row2 == 22
    Type(s, "4")
    local clamped = s ~= nil and MD.db.ui.fontOffset == 2 and s.high == 2 and s.low == -2
    Type(s, "0")
    local size0 = FontSize(UI.FONT)
    check("T42: the font offset slider (-2..+2) writes db.ui.fontOffset and applies it (fonts, the Spells rail)",
        s ~= nil and applied and clamped and MD.db.ui.fontOffset == 0 and size0 == 13 and rows[1] ~= nil and rows[1]:GetHeight() == 20,
        s and string.format("at +2 size=%s row=%s; back at %s size=%s row=%s; range %s..%s", tostring(size),
          tostring(row2), tostring(MD.db.ui.fontOffset), tostring(size0), tostring(rows[1] and rows[1]:GetHeight()),
          tostring(s.low), tostring(s.high)) or "no slider")
end

do
    local s = gp and gp.scaleSlider
    DragTo(frame, 100, 700)
    local es0 = frame:GetEffectiveScale()
    local pxL, pxT = frame:GetLeft() * es0, frame:GetTop() * es0
    Type(s, "90")
    local es1 = frame:GetEffectiveScale()
    local applied = near(MD.db.ui.scale, 0.9) and near(frame:GetScale(), 0.9)
      and near(frame:GetLeft() * es1, pxL, 1e-3) and near(frame:GetTop() * es1, pxT, 1e-3)
    Type(s, "150")
    local clamped = s ~= nil and near(MD.db.ui.scale, 1.2) and s.low == 70 and s.high == 120
    Type(s, "100")
    check("T42: the window scale slider (70-120 %) writes db.ui.scale and applies it through MD.Win",
        s ~= nil and applied and clamped and near(MD.db.ui.scale, 1) and near(frame:GetScale(), 1),
        s and string.format("scale=%s frame=%s", fmt(MD.db.ui.scale), fmt(frame:GetScale())) or "no slider")
end

do
    local dd = gp and gp.combatDropdown
    local shownDefault = dd and dd:Value() == "hide"
    Pick(dd, "keep")
    local wrote = MD.db.ui.combat == "keep"
    S.Fire("PLAYER_REGEN_DISABLED")
    local kept = frame:IsShown()
    S.Fire("PLAYER_REGEN_ENABLED")
    Pick(dd, "hide")
    local wrote2 = MD.db.ui.combat == "hide"
    S.Fire("PLAYER_REGEN_DISABLED")
    local hid = not frame:IsShown()
    S.Fire("PLAYER_REGEN_ENABLED")
    local g, v = MD:SelectedView()
    check("T42: the combat dropdown writes db.ui.combat (hide / keep) and the next pull follows it",
        dd ~= nil and shownDefault and wrote and kept and wrote2 and hid and frame:IsShown()
          and g == "settings" and v == "general",
        string.format("%s %s %s %s %s", tostring(shownDefault), tostring(wrote), tostring(kept),
          tostring(wrote2), tostring(hid)))
end

do
    local cb = gp and gp.escCheck
    local on = cb and cb:GetChecked()
    if cb then cb:SetChecked(false); cb.onClick(false, cb) end
    local off = MD.db.ui.escStack == false and InSpecial("SpellTunerDashboard") and #Stack() == 0
      and proxy ~= nil and not proxy:IsShown()
    if cb then cb:SetChecked(true); cb.onClick(true, cb) end
    check("T42: 'Close one window per ESC' writes db.ui.escStack and switches the stack at once",
        cb ~= nil and on and off and MD.db.ui.escStack == true and not InSpecial("SpellTunerDashboard")
          and Top() == frame and proxy ~= nil and proxy:IsShown(),
        tostring(on) .. " " .. tostring(off))
end

do
    local b = gp and gp.resetButton
    DragTo(frame, 10, 500)
    ResizeTo(frame, 950, 620)
    local saved = type(MD.db.ui.win.main) == "table"
    Click(b)
    local win = MD.db.ui.win
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local cx = frame:GetLeft() + frame:GetWidth() / 2
    local cy = frame:GetTop() - frame:GetHeight() / 2
    check("T42: 'Reset window positions' clears db.ui.win and re-centres the window at its default size",
        b ~= nil and saved and type(win) == "table" and next(win) == nil and frame:GetWidth() == 860
          and frame:GetHeight() == 560 and near(cx, sw / 2, 1e-3) and near(cy, sh / 2, 1e-3),
        fmt(cx) .. "," .. fmt(cy))
end

--------------------------------------------------------------------------------
-- 14. T70 (P26 of docs/PLAN-refactor-ux.md, review U18, U24, U15, mockup M1):
-- Settings -> General in two columns with the MANA CLOCK, REVIEW and TOOLS
-- panes, and Settings -> About. The Replay module is loaded here (section 12).
--------------------------------------------------------------------------------
MD:SelectView("settings", "general")
gp = GeneralPane()

-- the pane a titled pane hangs from: follow its first point up the chain
-- to the one anchored on the General pane itself, and read that x
local function ColumnX(sec)
    local guard = 0
    while sec and guard < 10 do
        local _, rel, _, x = sec:GetPoint(1)
        if rel == gp then return x end
        sec, guard = rel, guard + 1
    end
    return nil
end
local function FontStringUnder(parent, text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "FontString" and f.parentFrame == parent and f:GetText() == text then return f end
    end
    return nil
end

do
    local titles = {}
    for _, f in ipairs(S.allFrames) do
        if f.title and f.line and gp and f.parentFrame == gp then titles[f.title:GetText()] = f end
    end
    local left, right = true, true
    for _, t in ipairs({ "SPELL TOOLTIPS", "APPEARANCE", "WINDOWS" }) do
        if ColumnX(titles[t]) ~= 4 then left = false end
    end
    for _, t in ipairs({ "MANA CLOCK", "REVIEW", "TOOLS" }) do
        if ColumnX(titles[t]) ~= 376 then right = false end
    end
    local named = gp and FontStringUnder(gp.fontSlider, "Text size") ~= nil
      and FontStringUnder(gp.scaleSlider, "Window size") ~= nil
      and gp.fontHint and gp.fontHint:GetText() == "Every SpellTuner text, one size bigger or smaller."
      and gp.scaleHint and gp.scaleHint:GetText() == "Every SpellTuner window, bigger or smaller."
      and FontStringUnder(gp.fontSlider, "Font offset") == nil
    check("T70: General in two columns (tooltips, appearance, windows | clock, review, tools); Text size, Window size",
        gp ~= nil and left and right and named and gp.clockCheck.parentFrame == titles["MANA CLOCK"],
        string.format("left=%s right=%s named=%s", tostring(left), tostring(right), tostring(named)))
end

-- A block that raises (on the parent: no such pane) is one FAIL, not the end
-- of the suite.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

-- MANA CLOCK: show, lock, Show now, and Reset position clearing the saved point
Guarded("T70: MANA CLOCK", function()
    local Clock = MD.Clock
    local w = Clock.frame
    local show, lock = gp and gp.clockCheck, gp and gp.clockLockCheck
    if show then show:SetChecked(false); show.onClick(false, show) end
    local off = MD.db.clock.shown == false and w and not w:IsShown() and not gp.clockShowNow:IsEnabled()
    if show then show:SetChecked(true); show.onClick(true, show) end
    local on = MD.db.clock.shown == true and gp.clockShowNow:IsEnabled()
    if lock then lock:SetChecked(true); lock.onClick(true, lock) end
    local locked = MD.db.clock.locked == true and not Clock:Previewing()
    Click(gp and gp.clockShowNow)
    local preview = Clock:Previewing() and w:IsShown()
    MD.db.clock.point = { "CENTER", nil, "CENTER", 40, -30 }
    w:ClearAllPoints()
    w:SetPoint("CENTER", UIParent, "CENTER", 40, -30)
    Click(gp and gp.clockReset)
    local p, rel, rp, x, y = w:GetPoint(1)
    local reset = MD.db.clock.point == nil and p == "TOP" and rel == UIParent and rp == "TOP" and x == 0 and y == -120
    if lock then lock:SetChecked(false); lock.onClick(false, lock) end
    S.Tick(61)
    check("T70: MANA CLOCK writes db.clock.shown / locked, Show now previews, Reset position clears the point",
        show ~= nil and lock ~= nil and off and on and locked and preview and reset
          and MD.db.clock.locked == false and not Clock:Previewing(),
        string.format("off=%s on=%s locked=%s preview=%s reset=%s (%s %s %s)", tostring(off), tostring(on),
          tostring(locked), tostring(preview), tostring(reset), tostring(p), tostring(rp), tostring(y)))
end)

-- REVIEW: live now that Replay is loaded; each control writes its key
Guarded("T70: REVIEW", function()
    local keys, wrote, live = {}, true, true
    local saved = {}
    for _, c in ipairs(gp and gp.reviewChecks or {}) do
        keys[#keys + 1] = c.key
        saved[c.key] = MD.db[c.key]
        if not c.check:IsEnabled() then live = false end
        c.check:SetChecked(true); c.check.onClick(true, c.check)
        if MD.db[c.key] ~= true or MD:Setting(c.key) ~= true then wrote = false end
        c.check:SetChecked(false); c.check.onClick(false, c.check)
        if MD.db[c.key] ~= false or MD:Setting(c.key) ~= false then wrote = false end
    end
    local sv = MD.db.simFullHp
    Type(gp and gp.fullHpSlider, "90")
    local hp = near(MD.db.simFullHp, 0.9) and near(MD:Setting("simFullHp"), 0.9)
    Type(gp and gp.fullHpSlider, "120")
    local clamped = near(MD.db.simFullHp, 0.99)
    MD.db.simFullHp = sv
    for k, v in pairs(saved) do MD.db[k] = v end
    check("T70: REVIEW's four checks and 'Full health is above' write their keys once Replay is loaded",
        #keys == 4 and table.concat(keys, ",") == "replayAutoCoach,replayNextPull,replayTicks,simAllowRebinds"
          and live and wrote and hp and clamped and gp.fullHpSlider:IsEnabled()
          and gp.reviewNote:GetText() == "needs the Replay module",
        string.format("keys=%s live=%s wrote=%s hp=%s clamped=%s", table.concat(keys, ","), tostring(live),
          tostring(wrote), tostring(hp), tostring(clamped)))
end)

-- TOOLS: the console, the dump in the copy box, measure on and off
Guarded("T70: TOOLS", function()
    local console = _G.SpellTunerDebugConsole
    if console then console:Hide() end
    Click(gp and gp.consoleButton)
    console = _G.SpellTunerDebugConsole
    local consoleShown = console ~= nil and console:IsShown()
    if console then console:Hide() end
    Click(gp and gp.dumpButton)
    local copy = _G.SpellTunerDebugCopyFrame
    local dumped = copy ~= nil and copy:IsShown() and type(copy.text) == "string"
      and copy.text:find("SpellTuner dump", 1, true) == 1
    if copy then copy:Hide() end
    local wasOn = MD.Measure.on
    Click(gp and gp.measureButton)
    local turnedOn = MD.Measure.on == true and gp.measureButton:GetText() == "Measure: on"
    Click(gp and gp.measureButton)
    local turnedOff = not MD.Measure.on and gp.measureButton:GetText() == "Measure: off"
    check("T70: TOOLS opens the console, puts /st dump in the copy box, and turns measure on and off",
        consoleShown and dumped and not wasOn and turnedOn and turnedOff,
        string.format("console=%s dump=%s measure %s/%s", tostring(consoleShown), tostring(dumped),
          tostring(turnedOn), tostring(turnedOff)))
end)

-- About: every command MD:Commands() lists, the modules' included, cut at "; "
Guarded("T70: About", function()
    MD:SelectView("settings", "about")
    local ap = AboutPane()
    local rows = AboutRows(ap)
    local byUsage = {}
    for _, r in ipairs(rows) do byUsage[r.usage] = r end
    local want, missing = 0, {}
    for _, e in ipairs(MD:Commands()) do
        if not e.hidden and e.usage ~= "" then
            want = want + 1
            if not byUsage[e.usage] then missing[#missing + 1] = e.usage end
        end
    end
    local m = byUsage["/st measure [dump [all] / clear]"]
    local cut = m ~= nil and m.text == "measure a landed cast against its own description (a diagnostic session)"
      and m.tips and m.tips[2] and m.tips[2]:find("dump all every line", 1, true) ~= nil
    local offLine = false
    for _, r in ipairs(rows) do
        if r.text:find("off: its commands", 1, true) then offLine = true end
    end
    local hasReplay = false
    for u in pairs(byUsage) do if u:find("^/st replay") then hasReplay = true end end
    local head = ap and ap.version:GetText() == "SpellTuner " .. tostring(MD.version)
      and ap.client:GetText():find("^WoW: Forever") ~= nil
    check("T70: About lists every visible command (the modules' too), the long ones cut at '; ' with the rest on hover",
        ap ~= nil and #missing == 0 and #rows == want and cut and hasReplay and not offLine and head,
        string.format("rows=%d want=%d missing=%s cut=%s replay=%s head=%s", #rows, want,
          table.concat(missing, " | "), tostring(cut), tostring(hasReplay), tostring(head)))
end)

--------------------------------------------------------------------------------
print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
