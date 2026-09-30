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
-- The stub's frames have no geometry (GetLeft is 0, SetPoint a no-op), so this
-- suite gives the frame metatable just enough of one for windows anchored to
-- UIParent: a scale per frame, points recorded, GetLeft / GetTop computed in a
-- 768-high base space (UIParent's effective scale is the game's UI scale, as
-- UI.px assumes). It is this suite's own, installed on the stub's frame
-- metatable after the addon loads (the main window is built on first use, so
-- every window this suite opens has it); no other suite sees it. T33 / T34
-- extend this file (T33: the ESC stack and combat, section 11).
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
-- Geometry, this suite's own (see the header)
--------------------------------------------------------------------------------
local FM = getmetatable(UIParent)
S.uiScale = 0.71
local function BaseW() return 768 * S.physicalWidth / S.physicalHeight end

UIParent.GetEffectiveScale = function() return S.uiScale end
UIParent.GetScale = function() return S.uiScale end
UIParent.GetWidth = function() return BaseW() / S.uiScale end
UIParent.GetHeight = function() return 768 / S.uiScale end
UIParent.GetLeft = function() return 0 end
UIParent.GetBottom = function() return 0 end
UIParent.GetTop = function() return 768 / S.uiScale end
UIParent.GetRight = function() return BaseW() / S.uiScale end

FM.SetScale = function(self, s) self.scaleV = s end
FM.GetScale = function(self) return self.scaleV or 1 end
FM.GetEffectiveScale = function(self)
    local p = self.parentFrame
    local pe = (p and p.GetEffectiveScale) and p:GetEffectiveScale() or 1
    return (self.scaleV or 1) * pe
end
FM.ClearAllPoints = function(self) self.points = {} end
FM.SetPoint = function(self, p, rel, rp, x, y)
    self.points = self.points or {}
    self.points[#self.points + 1] = { p, rel, rp, x, y }
end
FM.GetNumPoints = function(self) return self.points and #self.points or 0 end
FM.GetPoint = function(self, i)
    local pt = self.points and self.points[i or 1]
    if not pt then return "CENTER", nil, "CENTER", 0, 0 end
    return pt[1], pt[2], pt[3], pt[4], pt[5]
end
FM.SetFrameStrata = function(self, s) self.strata = s end
FM.GetFrameStrata = function(self) return self.strata or "MEDIUM" end
FM.SetFrameLevel = function(self, l) self.level = l end
FM.GetFrameLevel = function(self) return self.level or 1 end
FM.SetToplevel = function(self, v) self.toplevel = v and true or false end
FM.IsToplevel = function(self) return self.toplevel == true end
FM.SetUserPlaced = function(self, v) self.userPlaced = v and true or false end
FM.IsUserPlaced = function(self) return self.userPlaced == true end
FM.SetClampedToScreen = function(self, v) self.clamped = v and true or false end
FM.IsClampedToScreen = function(self) return self.clamped == true end
FM.SetResizable = function(self, v) self.resizable = v and true or false end
FM.IsResizable = function(self) return self.resizable == true end
FM.SetResizeBounds = function(self, a, b, c, d) self.bounds = { a, b, c, d } end

-- Where a frame's TOPLEFT is, in its own units from UIParent's BOTTOMLEFT;
-- only the one-point anchors to UIParent a window uses. nil for anything else.
local ANCHOR = {
    BOTTOMLEFT = function() return 0, 0 end,
    TOPLEFT = function() return 0, 768 end,
    CENTER = function() return BaseW() / 2, 384 end,
    TOP = function() return BaseW() / 2, 768 end,
}
local function TopLeft(self)
    local pt = self.points and self.points[#self.points]
    if not pt or #self.points ~= 1 then return nil end
    local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
    if rel == nil then rel, rp, x, y = UIParent, p, 0, 0 end
    if rel ~= UIParent or not ANCHOR[rp] then return nil end
    local es = self:GetEffectiveScale()
    local ax, ay = ANCHOR[rp]()
    local px, py = ax + (x or 0) * es, ay + (y or 0) * es
    local w, h = self:GetWidth() * es, self:GetHeight() * es
    local left, top
    if p == "TOPLEFT" then left, top = px, py
    elseif p == "TOP" then left, top = px - w / 2, py
    elseif p == "CENTER" then left, top = px - w / 2, py + h / 2
    else return nil end
    return left / es, top / es
end
FM.GetLeft = function(self) local l = TopLeft(self); if l then return l end return 0 end
FM.GetTop = function(self) local _, t = TopLeft(self); if t then return t end return self.h or 20 end

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
-- press; "the next frame" runs the C_Timer.After callbacks queued since the
-- last one (only those, so nothing an earlier section queued runs here).
--------------------------------------------------------------------------------
FM.GetName = function(self) return self.frameName end
local timerCursor = #(S.timers or {})
local function NextFrame()
    local t = S.timers or {}
    while timerCursor < #t do
        timerCursor = timerCursor + 1
        t[timerCursor]()
    end
end
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
    local queued = #(S.timers or {})
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
          and MD.db.ui.escTest == rec and #(S.timers or {}) == queued,
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
print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
