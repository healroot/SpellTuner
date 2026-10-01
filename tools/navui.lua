-- tools/run.sh tools/navui.lua
--
-- The navigation kit (docs/SPEC-v0.11.md §3) under the stub: groups down the
-- left, that group's views along the top, panes built lazily and cached, the
-- selection remembered. It is the piece every other window is about to be
-- rebuilt on, so it gets its own suite before anything moves.
--
-- T31 (docs/SPEC-forever-ui.md 3.1, 3.2, 6.2, 6.4) adds ten: a rail group (no
-- top row, the content anchored per group, rail rows as views, one reorder per
-- drag), the view-button pool, a sheet's mask, and the dropdown lists' strata.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
S.Load({ "UI/Style.lua" }, "SpellTuner", MD)
local UI = MD.UI

-- T31: geometry and layering, recorded for THIS suite only (the stub keeps
-- none, and every other suite sees it exactly as before): anchors, strata,
-- frame levels (a child one above its parent, as in the client) and mouse.
local FrameMT = getmetatable(UIParent)
function FrameMT:SetPoint(p, rel, rp, x, y)
    if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
    self.points = self.points or {}
    self.points[p] = { rel = rel or self.parentFrame, rp = rp or p, x = x or 0, y = y or 0 }
end
function FrameMT:ClearAllPoints() self.points = {}; self.allPoints = nil end
function FrameMT:SetAllPoints(rel) self.points = {}; self.allPoints = rel or self.parentFrame end
function FrameMT:SetFrameStrata(s) self.strata = s end
function FrameMT:GetFrameStrata()
    if self.strata then return self.strata end
    local p = self.parentFrame
    return p and p:GetFrameStrata() or "MEDIUM"
end
function FrameMT:SetFrameLevel(n) self.level = n end
function FrameMT:GetFrameLevel()
    if self.level then return self.level end
    local p = self.parentFrame
    return p and (p:GetFrameLevel() + 1) or 0
end
function FrameMT:EnableMouse(v) self.mouse = v and true or false end
function FrameMT:IsMouseEnabled() return self.mouse == true end

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-46s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local built, selections = {}, {}
local groups = {
    { id = "spells", text = "Spells", views = {
        { id = "ht", text = "Healing Touch" }, { id = "rg", text = "Regrowth" } } },
    { id = "reports", text = "Reports", views = {
        { id = "waste", text = "Waste" }, { id = "review", text = "Review" } } },
    { id = "settings", text = "Settings", views = { { id = "general", text = "General" } } },
}
local shows = {}
local nav = UI.CreateNavFrame("SpellTuner", "MDNavTest", 900, 600, groups,
    function(g, v, content)
        local key = g .. ":" .. tostring(v)
        built[key] = (built[key] or 0) + 1
        local pane = CreateFrame("Frame", nil, content)
        pane.key = key
        return pane
    end,
    function(g, v)
        selections[#selections + 1] = g .. "/" .. tostring(v)
        local key = g .. ":" .. tostring(v)
        shows[key] = (shows[key] or 0) + 1
    end)

check("a nav frame is created", nav ~= nil and nav.frame ~= nil)
check("one button per group", #nav.buttons == 3, tostring(#nav.buttons))
check("nothing is selected before it is asked", nav.group == nil and nav.view == nil)

nav:Select("spells")
local g, v = nav:Selected()
check("selecting a group takes its first view", g == "spells" and v == "ht", tostring(g) .. "/" .. tostring(v))
check("the view row is that group's", #nav.viewButtons == 2, tostring(#nav.viewButtons))
check("the pane was built once", built["spells:ht"] == 1)

nav:Select("spells", "rg")
check("selecting a view keeps the group", nav.group == "spells" and nav.view == "rg")
check("its pane is built too", built["spells:rg"] == 1)

nav:Select("spells", "ht")
check("going back does not rebuild the pane", built["spells:ht"] == 1, tostring(built["spells:ht"]))
check("but it is shown again, so it can refresh", shows["spells:ht"] == 2,
    tostring(shows["spells:ht"]))

nav:Select("reports")
check("the view row follows the group", #nav.viewButtons == 2 and nav.view == "waste",
    tostring(nav.view))
check("a group's panes are not built until it is opened", built["reports:review"] == nil)
nav:Select("reports", "review")
check("and then they are", built["reports:review"] == 1)

-- one pane visible at a time, and it is the selected one
local function shownKeys()
    local out = {}
    for _, panes in pairs(nav.panes or {}) do
        for _, pane in pairs(panes) do if pane:IsShown() then out[#out + 1] = pane.key end end
    end
    return out
end
local shown = shownKeys()
check("exactly one pane is shown", #shown == 1 and shown[1] == "reports:review",
    table.concat(shown, ", "))

-- the path is remembered for the next session
check("the selection is written to the database", MD.db.uiPath ~= nil
    and MD.db.uiPath[1] == "reports" and MD.db.uiPath[2] == "review",
    MD.db.uiPath and table.concat(MD.db.uiPath, "/") or "nothing saved")

-- a group whose views change while the window is open
nav:SetViews("reports", { { id = "waste", text = "Waste" }, { id = "review", text = "Review" },
                          { id = "runs", text = "Runs" } })
check("views can change while it is open", #nav.viewButtons == 3, tostring(#nav.viewButtons))
nav:Select("reports", "runs")
check("and the new one selects", nav.view == "runs", tostring(nav.view))

-- a hidden view is not offered, and asking for it lands somewhere real
nav:SetViews("spells", { { id = "ht", text = "Healing Touch" },
                         { id = "sm", text = "Swiftmend", hidden = true } })
nav:Select("spells", "sm")
check("a hidden view is refused, not shown", nav.view == "ht", tostring(nav.view))
check("hidden views get no button", #nav.viewButtons == 1, tostring(#nav.viewButtons))

-- an unknown group falls back rather than erroring
nav:Select("nosuchgroup")
check("an unknown group falls back to the first", nav.group == "spells", tostring(nav.group))

-- T74 (P30, review U1): the theme's selection language (selected fill + a
-- 2-px bar, hover laid over) is gated on UI.THEMED; TBC keeps today's -- the
-- active button in its hover colour with its hover scripts dropped, the others
-- lighting to that colour under the pointer, no bar built.
check("on TBC the active style is today's", (function()
    nav:Select("spells", "ht")
    local act, other = nav.buttons[1], nav.buttons[2]
    local tab = nav.viewButtons[1]
    local function is(c, w) return c and w and c[1] == w[1] and c[2] == w[2] and c[3] == w[3] and c[4] == w[4] end
    local activeOk = UI.THEMED == false and is(act.bg, act.hoverColor) and act.hoverColor[4] == 0.6
        and act:GetScript("OnEnter") == nil and act:GetScript("OnLeave") == nil and act.selBar == nil
        and is(tab.bg, tab.hoverColor) and tab:GetScript("OnEnter") == nil and tab.selBar == nil
    local restOk = is(other.bg, other.color) and other.color[1] == 0.115
    local enter = other:GetScript("OnEnter")
    if enter then enter(other) end
    local lit = is(other.bg, other.hoverColor)
    if other:GetScript("OnLeave") then other:GetScript("OnLeave")(other) end
    return activeOk and restOk and lit and is(other.bg, other.color) and other.selBar == nil
end)())

-- T73 (P29, review A24): nav:ReplacePane puts a new pane in a view's place
-- (a module placeholder swapped for the real pane) -- on screen: the old one
-- hidden, the new one shown and refreshed; off screen: cached, kept hidden,
-- shown when its view is next selected; nothing rebuilt by onCreate.
check("ReplacePane swaps a view's pane on and off screen", (function()
    if not nav.ReplacePane then return false end
    nav:Select("reports", "review")
    local old = nav.panes.reports.review
    local buildsBefore, showsBefore = built["reports:review"], shows["reports:review"]
    local fresh = CreateFrame("Frame", nil, nav:Content()); fresh.key = "reports:review"
    local back = nav:ReplacePane("reports", "review", fresh)
    local onScreen = back == old and not old:IsShown() and fresh:IsShown()
        and shows["reports:review"] == showsBefore + 1 and #shownKeys() == 1
    local off = CreateFrame("Frame", nil, nav:Content()); off.key = "spells:ht"
    local oldHt = nav.panes.spells.ht
    nav:ReplacePane("spells", "ht", off)
    local offScreen = not off:IsShown() and fresh:IsShown() and nav.group == "reports"
        and not oldHt:IsShown()
    nav:Select("spells", "ht")
    local later = off:IsShown() and not fresh:IsShown() and built["spells:ht"] == 1
        and built["reports:review"] == buildsBefore
    return onScreen and offScreen and later
end)())

--------------------------------------------------------------------------------
-- the level-3 box: the same rule inside a pane
--------------------------------------------------------------------------------
local boxSel = {}
local box = UI.CreateNavBox(nav:Content(), 400, 200, {
    { id = "a", text = "Alpha", views = { { id = "one", text = "One" }, { id = "two", text = "Two" } } },
    { id = "b", text = "Beta", views = { { id = "three", text = "Three" } } },
}, function(g2, v2) boxSel[#boxSel + 1] = g2 .. "/" .. tostring(v2) end)
check("a nav box is created", box ~= nil and box.frame ~= nil)
box:Select("a")
check("the box selects its first view", boxSel[#boxSel] == "a/one", boxSel[#boxSel])
box:Select("b")
check("the box switches groups", boxSel[#boxSel] == "b/three", boxSel[#boxSel])
check("the box has its own content frame", box:Content() ~= nav:Content())

-- palette: one place decides
check("there is a single palette", UI.PALETTE ~= nil and UI.PALETTE.frame and UI.PALETTE.header)

--------------------------------------------------------------------------------
-- T31 (docs/SPEC-forever-ui.md 3.1, 3.2, 6.2, 6.4): a rail group, the content
-- anchored per group, the view-button pool, sheets and masks, the lists' strata
--------------------------------------------------------------------------------
local function ButtonsOn(parent)
    local n = 0
    for _, fr in ipairs(S.allFrames) do
        if fr.kind == "Button" and fr.parentFrame == parent then n = n + 1 end
    end
    return n
end
local function ShownButtonsOn(parent)
    local n = 0
    for _, fr in ipairs(S.allFrames) do
        if fr.kind == "Button" and fr.parentFrame == parent and fr:IsShown() then n = n + 1 end
    end
    return n
end
local function Views(names)
    local out = { { id = "overview", text = "Overview", fixed = true } }
    for _, n in ipairs(names) do out[#out + 1] = { id = "fam:" .. n, text = n, tag = "R1" } end
    return out
end

local moves = {}
local railGroups = {
    { id = "spells", text = "Spells", layout = "rail",
      views = Views({ "Healing Touch", "Rejuvenation", "Wrath" }),
      rail = { title = "MY SPELLS", onMove = function(id, to) moves[#moves + 1] = id .. ">" .. tostring(to) end } },
    { id = "reports", text = "Reports", views = {
        { id = "waste", text = "Waste" }, { id = "review", text = "Review" } } },
}
local nav2 = UI.CreateNavFrame("SpellTuner", "MDNavRailTest", 860, 560, railGroups,
    function(g2, v2, content)
        local pane = CreateFrame("Frame", nil, content)
        pane.key = g2 .. ":" .. tostring(v2)
        return pane
    end)
local win = nav2.frame

nav2:Select("spells")
local tl = nav2:Content().points and nav2:Content().points.TOPLEFT
local railTop = tl and tl.y
check("a rail group: no top row, content at -8", #nav2.viewButtons == 0 and ShownButtonsOn(win) == 0
    and tl ~= nil and tl.y == -8,
    string.format("%d view buttons, %d shown, top %s", #nav2.viewButtons, ShownButtonsOn(win),
        tostring(tl and tl.y)))

nav2:Select("reports")
tl = nav2:Content().points and nav2:Content().points.TOPLEFT
check("a view-row group puts it back at -32", railTop == -8 and tl ~= nil and tl.y == -32
    and #nav2.viewButtons == 2,
    string.format("top %s -> %s, %d buttons", tostring(railTop), tostring(tl and tl.y), #nav2.viewButtons))

nav2:Select("spells", "fam:Healing Touch")
local before = ButtonsOn(win)
nav2:SetViews("spells", Views({ "Healing Touch", "Rejuvenation", "Wrath", "Moonfire" }))
check("SetViews on a rail group creates no button", ButtonsOn(win) == before and #nav2.viewButtons == 0
    and ShownButtonsOn(win) == 0, string.format("%d -> %d", before, ButtonsOn(win)))

nav2:Select("reports")
local three = { { id = "waste", text = "Waste" }, { id = "review", text = "Review" }, { id = "runs", text = "Runs" } }
nav2:SetViews("reports", three)
local once = ButtonsOn(win)
for _ = 1, 5 do nav2:SetViews("reports", three) end
check("five SetViews on Reports: same button frames", ButtonsOn(win) == once and #nav2.viewButtons == 3,
    string.format("%d -> %d", once, ButtonsOn(win)))

nav2:Select("spells", "fam:Healing Touch")
local rail = nav2.Rail and nav2:Rail("spells")
local rows = rail and rail:Rows() or {}
local rj
for _, r in ipairs(rows) do if r.id == "fam:Rejuvenation" then rj = r end end
if rj then rj:GetScript("OnClick")(rj, "LeftButton") end
local viaClick = nav2.view
nav2:Select("spells", "fam:Wrath")
local wrathRow
for _, r in ipairs(rows) do if r.id == "fam:Wrath" then wrathRow = r end end
check("rail rows are views", #rows == 5 and viaClick == "fam:Rejuvenation"
    and MD.db.uiPath[2] == "fam:Wrath" and wrathRow ~= nil and wrathRow.selected == true
    and rj.selected ~= true, string.format("%d rows, click -> %s", #rows, tostring(viaClick)))

-- drag Wrath (third in the list) up onto Rejuvenation's top half: one move,
-- to 2, however many times the client fires OnDragStop (Cell's note: twice)
local ht
for _, r in ipairs(rows) do if r.id == "fam:Healing Touch" then ht = r end end
if rail and wrathRow and rj then
    rail.frame.GetTop = function() return 500 end
    local rjTop = rj.points and rj.points.TOPLEFT and rj.points.TOPLEFT.y or 0
    local savedCursor = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 50, 500 + rjTop - 2 end
    wrathRow:GetScript("OnDragStart")(wrathRow, "LeftButton")
    if rail.frame:GetScript("OnUpdate") then rail.frame:GetScript("OnUpdate")(rail.frame, 0.02) end
    wrathRow:GetScript("OnDragStop")(wrathRow)
    wrathRow:GetScript("OnDragStop")(wrathRow)
    _G.GetCursorPosition = savedCursor
end
check("reorder fires once", #moves == 1 and moves[1] == "fam:Wrath>2", table.concat(moves, ", "))

-- a sheet's mask: over its region it takes the click, outside it does not
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                 FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Rect(fr)
    if fr.rect then return fr.rect[1], fr.rect[2], fr.rect[3], fr.rect[4] end
    if fr.allPoints then return Rect(fr.allPoints) end
end
local function HitAt(x, y)
    local best
    for _, fr in ipairs(S.allFrames) do
        if fr.mouse and fr:IsVisible() then
            local l, b, r, t = Rect(fr)
            if l and x >= l and x <= r and y >= b and y <= t then
                local s, bs = STRATA[fr:GetFrameStrata()] or 0, best and (STRATA[best:GetFrameStrata()] or 0)
                if not best or s > bs or (s == bs and fr:GetFrameLevel() > best:GetFrameLevel()) then best = fr end
            end
        end
    end
    return best
end
local host = CreateFrame("Frame", nil, UIParent)
host:SetFrameLevel(10); host.rect = { 0, 0, 736, 560 }
local railArea = CreateFrame("Button", nil, host); railArea.rect = { 0, 0, 172, 560 }; railArea:EnableMouse(true)
local viewArea = CreateFrame("Frame", nil, host); viewArea.rect = { 180, 0, 736, 560 }
local viewBtn = CreateFrame("Button", nil, viewArea); viewBtn.rect = { 200, 500, 300, 520 }; viewBtn:EnableMouse(true)
local sheet = UI.CreateSheet and UI.CreateSheet(host, viewArea, 300, 400, "ADD SPELLS")
local beforeHit = HitAt(250, 510)
if sheet then sheet:Show() end
local onHit = HitAt(250, 510)
check("a mask swallows clicks on its region", sheet ~= nil and beforeHit == viewBtn
    and onHit ~= viewBtn and onHit == sheet.mask)
check("and not outside it", sheet ~= nil and HitAt(80, 300) == railArea)
if sheet then sheet:Hide() end

-- the dropdown lists: UI.LIST_STRATA (nil = DIALOG, TBC's), UI.OnPopup told
UI.LIST_STRATA, UI.OnPopup = nil, nil
local d0 = UI.CreateDropdown(UIParent, 100, 18)
local popups = {}
UI.LIST_STRATA = "FULLSCREEN_DIALOG"
UI.OnPopup = function(list, shown) popups[#popups + 1] = { list, shown } end
local d1 = UI.CreateDropdown(UIParent, 100, 18)
d1:SetItems({ { id = 1, text = "A" }, { id = 2, text = "B" } })
d1:GetScript("OnClick")(d1)
d1:Close()
check("a list takes UI.LIST_STRATA", d0.list:GetFrameStrata() == "DIALOG"
    and d1.list:GetFrameStrata() == "FULLSCREEN_DIALOG" and #popups == 2
    and popups[1][1] == d1.list and popups[1][2] == true and popups[2][2] == false,
    string.format("%s / %s, %d popup calls", d0.list:GetFrameStrata(), d1.list:GetFrameStrata(), #popups))

local t1 = UI.CreateTreeDropdown(UIParent, 100, 18)
t1:SetItems({ { id = "a", text = "A", children = { { id = "a1", text = "A1" } } } })
t1:GetScript("OnClick")(t1)
t1.rows[1]:GetScript("OnEnter")(t1.rows[1])
check("the second list is above the first", t1.sub:IsShown()
    and t1.sub:GetFrameStrata() == t1.list:GetFrameStrata()
    and t1.sub:GetFrameLevel() == t1.list:GetFrameLevel() + 10,
    string.format("%s %d / %s %d", t1.list:GetFrameStrata(), t1.list:GetFrameLevel(),
        t1.sub:GetFrameStrata(), t1.sub:GetFrameLevel()))
t1:Close()
UI.LIST_STRATA, UI.OnPopup = nil, nil

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
