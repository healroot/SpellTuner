-- tools/run.sh [--flavour tbc|forever] tools/minimapcheck.lua [--print]
--
-- T79 (P36 of docs/PLAN-refactor-ux.md, section 8.1 item 10, mockups M1 and
-- M6): the minimap button, one file (UI/MinimapButton.lua) on both lines.
--
-- TBC half -- written and run on the parent commit 7fd71b3 before the first
-- edit, and equal after it (the button must not change on TBC until wave C):
--   the button's name, parent and size; its point at the default angle and
--   after a drag (due east, due north, at a minimap scale of 2); the clicks
--   (left: MD:ToggleDashboard, right: MD:OpenDashboardSettings); the hide
--   setting; the tooltip's anchor and every line, colours included, as a
--   golden (GOLDEN_TBC below, captured on the parent with --print); the
--   default on a fresh db.
--   T82 (C4, mockup M6): the TBC half now loads the theme as SpellTuner_TBC.toc
--   does (C1), so the tooltip is P36's themed shape, and GOLDEN_TBC is M6's
--   lines in TBC's words (UI/Tip_TBC.lua's Tip:Clock): the title, the clock
--   as label / value pairs, a spacer, the three hint pairs and the hide line.
--   One check more: with Shift held -- pressed while the tooltip is up -- the
--   raw lines follow the summary (GOLDEN_TBC_DETAIL), and released, they go.
-- Forever half -- red on the parent, which has no button on this line:
--   1. SpellTunerMinimapButton exists after MD_READY, parented to Minimap,
--      loaded by the main TOC (UI/MinimapButton.lua after UI/Clock_Forever.lua);
--   2. a drag with the pointer due east of the centre stores angle 0 and puts
--      the button at (75, 0);
--   3. with db.uiPath = reports/review a left-click opens the main window on
--      Review, a second closes it;
--   4. a right-click opens Settings -> General;
--   5. the WINDOWS pane's Minimap button checkbox hides the button and writes
--      db.minimap.hide = true, and shows it again;
--   6. the themed tooltip is M6's -- the provider's title and clock lines with
--      "~", a spacer, the three hint pairs, the muted hide line -- with no
--      bare pipe, and its clock lines are the clock hover's own
--      (MD.Clock:SummaryLines, one function for both);
--   7. on a fresh db, db.minimap is { hide = false, angle = 220 };
--   8. that default is declared once, by the button file (MD:RegisterDefaults),
--      and nowhere else on any TOC.
-- T97 (docs/SPEC-next.md 6.3; R-ellesmere.md 3.4), both halves, one check
-- each: a minimap-button collector (EllesmereUI's flyout, MBB) reparents the
-- button; MD:UpdateMinimapButton (Settings -> Windows' toggle) and the angle
-- drag then leave it where the collector put it, and the icon is the
-- button's `icon` field, anchored CENTER at the place it always had (so the
-- collector finds it by name, not by region order). Back on Minimap, the
-- button is repositioned as before. The TBC goldens are unchanged.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local PRINT = false
for _, a in ipairs(arg) do if a == "--print" then PRINT = true end end
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")
local check = T.check
local flavour = S.flavour
local root = S.root or "."

local BUTTON_FILE = "UI/MinimapButton.lua"

-- A block that raises (on the parent: no button, no setting) is one FAIL, not
-- the end of the suite.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- Loading. The TBC harness loads no UI file but UI/Summary.lua, so the kit,
-- the tooltip files and the button are loaded here and handed the MD_READY
-- they missed (only their own handlers, captured as they register --
-- re-firing MD_READY would re-run every other file's; tools/ttocheck.lua's
-- way). On Forever the main TOC loads the button; a tree whose TOC does not
-- list it yet has it loaded the same way, so the rest of the suite still
-- says something, and check 1 fails.
--------------------------------------------------------------------------------
local loadedByToc = false
for _, rel in ipairs(S.loadedFiles or {}) do
    if rel == BUTTON_FILE then loadedByToc = true end
end

local freshMinimap -- db.minimap as a fresh db has it, read before anything moves it
local function LoadByHand(files)
    local ready, realReg = {}, MD.RegisterCallback
    MD.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    local okLoad, err = pcall(S.Load, files, "SpellTuner", MD)
    MD.RegisterCallback = realReg
    if not okLoad then return false, err end
    for _, fn in ipairs(ready) do
        local okRun, e = pcall(fn)
        if not okRun then return false, e end
    end
    return true
end

local loadErr
if flavour == "tbc" then
    local okLoad
    -- T82: the theme after the kit, as SpellTuner_TBC.toc lists it (C1)
    okLoad, loadErr = LoadByHand({ "UI/Style.lua", "UI/Theme_Flat.lua", "UI/Tip.lua", "UI/Tip_TBC.lua",
        BUTTON_FILE })
    if not okLoad then print("load: " .. tostring(loadErr)) end
elseif not loadedByToc then
    local okLoad
    okLoad, loadErr = LoadByHand({ BUTTON_FILE })
    if not okLoad then print("load: " .. tostring(loadErr)) end
end
if type(MD.db) == "table" and type(MD.db.minimap) == "table" then
    freshMinimap = { hide = MD.db.minimap.hide, angle = MD.db.minimap.angle }
end

local B = _G.SpellTunerMinimapButton

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function Round(v, step)
    step = step or 0.001
    return math.floor(v / step + 0.5) * step
end

-- The button's point under the stub's geometry (S.Geometry keeps points),
-- after MD:UpdateMinimapButton repositioned it.
local function PointNow()
    local p, rel, rp, x, y = B:GetPoint(1)
    return p, rel, rp, x, y
end

-- One drag: the pointer at (dx, dy) screen pixels from the minimap's centre,
-- OnDragStart, one OnUpdate, OnDragStop. Answers the stored angle and the
-- point the button took.
local function DragTo(dx, dy)
    -- GetCenter is in the minimap's own units; the pointer is in screen pixels
    local c, k = S.minimapCenter, S.minimapScale
    S.cursorPos = { c[1] * k + dx, c[2] * k + dy }
    B:GetScript("OnDragStart")(B)
    local upd = B:GetScript("OnUpdate")
    if upd then upd(B, 0.016) end
    B:GetScript("OnDragStop")(B)
    S.cursorPos = nil
    local _, rel, _, x, y = PointNow()
    return MD.db.minimap.angle, x, y, rel, upd ~= nil, B:GetScript("OnUpdate") == nil
end

-- The tooltip as the game would hold it: every line's text and colours, and
-- the anchor SetOwner was given.
local owner
local realSetOwner = GameTooltip.SetOwner
GameTooltip.SetOwner = function(self, o, anchor, ...)
    owner = { o, anchor }
    if realSetOwner then return realSetOwner(self, o, anchor, ...) end
end
local function C(c)
    if type(c) ~= "table" then return "-" end
    return string.format("%.3f,%.3f,%.3f", c[1], c[2], c[3])
end
local function Hover()
    GameTooltip.lines = {}
    owner = nil
    B:GetScript("OnEnter")(B)
    local out = {}
    for _, l in ipairs(GameTooltip.lines or {}) do
        out[#out + 1] = { l = l[1], r = l[2], c = l.color, rc = l.rcolor }
    end
    B:GetScript("OnLeave")(B)
    return out, owner and owner[2]
end
local function Flatten(lines, anchor)
    local out = { "anchor " .. tostring(anchor) }
    for _, l in ipairs(lines) do
        out[#out + 1] = tostring(l.l) .. " | " .. tostring(l.r) .. " | " .. C(l.c) .. " | " .. C(l.rc)
    end
    return out
end
local function ShowGolden(name, got)
    print("-- " .. name .. " (paste between the braces):")
    for _, s in ipairs(got) do print(string.format("    %q,", s)) end
end
local function Same(a, b)
    if #a ~= #b then return false, string.format("%d lines, want %d", #a, #b) end
    for i = 1, #a do
        if a[i] ~= b[i] then return false, string.format("line %d: %q, want %q", i, a[i], b[i]) end
    end
    return true
end

--------------------------------------------------------------------------------
-- TBC: the button as before (its geometry, clicks and setting: captured on
-- 7fd71b3). T82 (C4, mockup M6): the tooltip is M6's in TBC's words; both
-- goldens below captured with --print on the C4 tree, red on its parent
-- 70b424d (docs/tasks/T82-one-clock-look.md).
--------------------------------------------------------------------------------
-- The stub's TBC druid in a fight (Fight below): one Healing Touch every
-- 3.5 s against a scripted low regen, until the clock says out of mana with
-- trusted digits -- the moment M6 draws.
local GOLDEN_TBC = {
    "anchor ANCHOR_LEFT",
    "SpellTuner | nil | 1.000,0.490,0.040 | -",
    "Out of mana in | 1:10 | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Full again in | 3:40 if you stop | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "  | nil | - | -",
    "Left-click | open the window | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Right-click | Settings | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Drag | move it round the map | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Hide it: Settings -> General -> Windows. | nil | 0.478,0.478,0.478 | -",
}

-- The same moment with Shift pressed while the tooltip is up: the raw lines
-- (Tip:Mana) after the summary, then the hints.
local GOLDEN_TBC_DETAIL = {
    "anchor ANCHOR_LEFT",
    "SpellTuner | nil | 1.000,0.490,0.040 | -",
    "Out of mana in | 1:10 | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Full again in | 3:40 if you stop | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "  | nil | - | -",
    "Time to OOM (raw) | 72s +- 20s | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Full if you stop casting | 221s | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Net rate (pessimistic) | -66 mana/s | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Spending | 53 +- 18 mana/s (9 casts, CV 0.35) | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Regen now / projected | 5 / 5 mana/s  (5SR 100% of time) | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Regen out of 5SR / casting | 10 / 5 mana/s | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Spirit / gear mp5 | ~35 / ~14 | 1.000,1.000,1.000 | 1.000,1.000,1.000",
    "Spirit regen resumes | 4.5s | 1.000,0.670,0.200 | 1.000,1.000,1.000",
    "  | nil | - | -",
    "Innervate | 671 mana -> OOM 82s | 0.780,0.780,0.780 | 0.310,0.660,0.940",
    "  | nil | - | -",
    "Left-click | open the window | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Right-click | Settings | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Drag | move it round the map | 0.702,0.702,0.702 | 1.000,1.000,1.000",
    "Hide it: Settings -> General -> Windows. | nil | 0.478,0.478,0.478 | -",
}

-- T97: a collector takes the button. Its flyout reparents it and puts it in a
-- grid (EllesmereUIMinimap.lua 474-503); the Settings toggle and the angle
-- drag must leave it there; its icon is found by name (`btn.icon`, 516-532).
-- Back on Minimap, MD:UpdateMinimapButton repositions it as before.
local function CollectedCheck(name)
    Guarded(name, function()
        S.Geometry(true)
        local flyout = CreateFrame("Frame", "T97FakeFlyout", UIParent)
        B:SetParent(flyout)
        B:ClearAllPoints()
        B:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -4)
        MD:UpdateMinimapButton()
        local p, rel, rp, x, y = B:GetPoint(1)
        local kept = B:GetParent() == flyout and B:GetNumPoints() == 1 and p == "TOPLEFT" and rel == flyout
            and rp == "TOPLEFT" and x == 4 and y == -4 and B:IsShown()
        -- the angle drag starts nothing while collected
        local angle = MD.db.minimap.angle
        B:GetScript("OnDragStart")(B)
        local noDrag = B:GetScript("OnUpdate") == nil
        B:GetScript("OnDragStop")(B)
        local icon = B.icon
        local iconOk = type(icon) == "table" and icon.kind == "Texture" and icon.parentFrame == B
        -- back on the minimap: repositioned at the stored angle, as before
        B:SetParent(Minimap)
        MD:UpdateMinimapButton()
        local p2, rel2 = B:GetPoint(1)
        local back = B:GetNumPoints() == 1 and p2 == "CENTER" and rel2 == Minimap
        S.Geometry(false)
        check(name, kept and noDrag and MD.db.minimap.angle == angle and iconOk and back,
            string.format("kept=%s (%s %s %s %s %s) noDrag=%s angle=%s icon=%s back=%s", tostring(kept), tostring(p),
                tostring(rel == flyout and "flyout" or rel), tostring(rp), tostring(x), tostring(y), tostring(noDrag),
                tostring(MD.db.minimap.angle), tostring(iconOk), tostring(back)))
    end)
end

-- Fight(): into combat and casting until the clock is out of mana, stable and
-- trusted; answers a function that ends the fight and puts everything back.
local function Fight()
    local realRegen = GetManaRegen
    GetManaRegen = function() return 10, 5 end
    S.Fire("PLAYER_REGEN_DISABLED")
    local SD = MD.SpellData
    for i = 1, 200 do
        if i % 7 == 1 then
            S.mana = S.mana - SD:GetCost(5189) -- Healing Touch rank 5
            S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 5189)
            S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        end
        S.Tick(0.5)
        local s = MD:GetManaState()
        if i > 40 and s and s.mode == "oom" and s.stable and s.confident then break end
    end
    return function()
        S.Fire("PLAYER_REGEN_ENABLED")
        GetManaRegen = realRegen
        S.mana = S.manaMax
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        S.Tick(0.5)
    end
end

if flavour == "tbc" then
    T.section("TBC: the button, and M6's tooltip")

    Guarded("tbc: the button is SpellTunerMinimapButton, on Minimap, 31 x 31", function()
        check("tbc: the button is SpellTunerMinimapButton, on Minimap, 31 x 31",
            B ~= nil and B:GetParent() == Minimap and B:GetWidth() == 31 and B:GetHeight() == 31
              and B.kind == "Button",
            loadErr and tostring(loadErr) or nil)
    end)

    check("tbc: on a fresh db, db.minimap is { hide = false, angle = 220 }",
        freshMinimap ~= nil and freshMinimap.hide == false and freshMinimap.angle == 220,
        freshMinimap and (tostring(freshMinimap.hide) .. " " .. tostring(freshMinimap.angle)) or "no db.minimap")

    Guarded("tbc: its point at 220 degrees, then dragged east, north, and at a minimap scale of 2", function()
        S.Geometry(true)
        MD:UpdateMinimapButton()
        local p, rel, rp, x0, y0 = PointNow()
        local a1, x1, y1, rel1, hadUpdate, cleared = DragTo(100, 0)
        local a2, x2, y2 = DragTo(0, 40)
        S.minimapScale = 2
        local a3, x3, y3 = DragTo(-60, -60) -- 60 screen px is 30 minimap units; the angle is the same
        S.minimapScale = 1
        S.Geometry(false)
        local got = string.format("%s %s %s %.3f %.3f | %.3f %.3f %.3f | %.3f %.3f %.3f | %.3f %.3f %.3f",
            p, rel == Minimap and "Minimap" or tostring(rel), rp, x0, y0,
            a1, x1, y1, a2, x2, y2, a3, x3, y3)
        local want = "CENTER Minimap CENTER -57.453 -48.209 | 0.000 75.000 0.000 | 90.000 0.000 75.000"
            .. " | 225.000 -53.033 -53.033"
        check("tbc: its point at 220 degrees, then dragged east, north, and at a minimap scale of 2",
            got == want and rel1 == Minimap and hadUpdate and cleared,
            got)
        MD.db.minimap.angle = 220
    end)

    Guarded("tbc: left-click toggles the dashboard, right-click opens its settings", function()
        local toggles, settings = 0, 0
        local rt, rs = MD.ToggleDashboard, MD.OpenDashboardSettings
        MD.ToggleDashboard = function() toggles = toggles + 1 end
        MD.OpenDashboardSettings = function() settings = settings + 1 end
        local click = B:GetScript("OnClick")
        click(B, "LeftButton")
        local afterLeft = toggles == 1 and settings == 0
        click(B, "RightButton")
        MD.ToggleDashboard, MD.OpenDashboardSettings = rt, rs
        check("tbc: left-click toggles the dashboard, right-click opens its settings",
            afterLeft and toggles == 1 and settings == 1,
            string.format("toggles=%d settings=%d", toggles, settings))
    end)

    Guarded("tbc: db.minimap.hide hides the button, and back", function()
        MD.db.minimap.hide = true
        MD:UpdateMinimapButton()
        local hidden = not B:IsShown()
        MD.db.minimap.hide = false
        MD:UpdateMinimapButton()
        check("tbc: db.minimap.hide hides the button, and back", hidden and B:IsShown())
    end)

    CollectedCheck("tbc: a collected button is not pulled back; its icon is btn.icon (T97)")

    local endFight
    Guarded("tbc: the tooltip in a fight is M6's, line for line (golden)", function()
        endFight = Fight()
        local lines, anchor = Hover()
        local got = Flatten(lines, anchor)
        if PRINT then ShowGolden("GOLDEN_TBC", got) end
        local same, why = Same(got, GOLDEN_TBC)
        check("tbc: the tooltip in a fight is M6's, line for line (golden)", same, why)
    end)

    Guarded("tbc: Shift pressed over it adds the raw lines (golden); released, they go", function()
        -- the tooltip up and owned by the button, as the game holds it
        local realOwner = GameTooltip.GetOwner
        GameTooltip.GetOwner = function() return B end
        GameTooltip.lines = {}
        B:GetScript("OnEnter")(B)
        local plainN = #GameTooltip.lines
        S.shift = true
        GameTooltip.lines = {}
        S.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        local got = { "anchor " .. tostring(owner and owner[2]) }
        for _, l in ipairs(GameTooltip.lines or {}) do
            got[#got + 1] = tostring(l[1]) .. " | " .. tostring(l[2]) .. " | " .. C(l.color) .. " | " .. C(l.rcolor)
        end
        if PRINT then ShowGolden("GOLDEN_TBC_DETAIL", got) end
        S.shift = false
        GameTooltip.lines = {}
        S.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
        local backN = #GameTooltip.lines
        B:GetScript("OnLeave")(B)
        GameTooltip.GetOwner = realOwner
        if endFight then endFight() end
        local same, why = Same(got, GOLDEN_TBC_DETAIL)
        check("tbc: Shift pressed over it adds the raw lines (golden); released, they go",
            same and plainN == #GOLDEN_TBC - 1 and backN == plainN,
            string.format("%s; plain %d, released %d", tostring(why), plainN, backN))
    end)

    T.done()
end

--------------------------------------------------------------------------------
-- Forever
--------------------------------------------------------------------------------
T.section("Forever: the same button")

local function TocLists(toc)
    local files = S.TocFiles(toc)
    local clockAt, buttonAt
    for i, rel in ipairs(files) do
        if rel == "UI/Clock_Forever.lua" then clockAt = i end
        if rel == BUTTON_FILE then buttonAt = i end
    end
    return buttonAt ~= nil and clockAt ~= nil and buttonAt > clockAt
end

-- 7 first, before the drag moves the angle
check("7. on a fresh db, db.minimap is { hide = false, angle = 220 }",
    freshMinimap ~= nil and freshMinimap.hide == false and freshMinimap.angle == 220,
    freshMinimap and (tostring(freshMinimap.hide) .. " " .. tostring(freshMinimap.angle)) or "no db.minimap")

Guarded("1. SpellTunerMinimapButton exists after MD_READY, on Minimap, from the main TOC", function()
    local mainline, plain = TocLists("SpellTuner_Mainline.toc"), TocLists("SpellTuner.toc")
    check("1. SpellTunerMinimapButton exists after MD_READY, on Minimap, from the main TOC",
        B ~= nil and B:GetParent() == Minimap and B:GetWidth() == 31 and loadedByToc and mainline and plain,
        string.format("button=%s loadedByToc=%s Mainline=%s plain=%s%s", tostring(B ~= nil),
            tostring(loadedByToc), tostring(mainline), tostring(plain),
            loadErr and (" load: " .. tostring(loadErr)) or ""))
end)

Guarded("2. a drag due east stores angle 0 and puts the button at (75, 0)", function()
    S.Geometry(true)
    local a, x, y, rel = DragTo(100, 0)
    S.Geometry(false)
    check("2. a drag due east stores angle 0 and puts the button at (75, 0)",
        a == 0 and rel == Minimap and Round(x) == 75 and Round(y) == 0,
        string.format("angle=%s x=%s y=%s", tostring(a), tostring(x), tostring(y)))
    MD.db.minimap.angle = 220
end)

local main = _G.SpellTunerDashboard
Guarded("3. left-click opens the window on the remembered view (Review); again closes it", function()
    if main and main:IsShown() then main:Hide() end
    MD.db.uiPath = { "reports", "review" }
    local click = B:GetScript("OnClick")
    click(B, "LeftButton")
    main = _G.SpellTunerDashboard
    local opened = main ~= nil and main:IsShown()
    local g, v = MD:SelectedView()
    click(B, "LeftButton")
    check("3. left-click opens the window on the remembered view (Review); again closes it",
        opened and g == "reports" and v == "review" and not main:IsShown(),
        string.format("opened=%s view=%s/%s closed=%s", tostring(opened), tostring(g), tostring(v),
            tostring(main and not main:IsShown())))
end)

local gp -- Settings -> General
Guarded("4. right-click opens Settings -> General", function()
    if main and main:IsShown() then main:Hide() end
    MD.db.uiPath = { "spells" }
    B:GetScript("OnClick")(B, "RightButton")
    main = _G.SpellTunerDashboard
    local g, v = MD:SelectedView()
    for _, f in ipairs(S.allFrames) do
        if f.fontSlider or f.tooltipCheck then gp = f end
    end
    check("4. right-click opens Settings -> General",
        main ~= nil and main:IsShown() and g == "settings" and v == "general",
        string.format("shown=%s view=%s/%s", tostring(main and main:IsShown()), tostring(g), tostring(v)))
end)

Guarded("5. WINDOWS: Minimap button hides the button and writes db.minimap.hide; ticked, back", function()
    local cb = gp and gp.minimapCheck
    local startTicked = cb and cb:GetChecked()
    local label = cb and cb.label and cb.label:GetText()
    local hint = gp and gp.minimapHint and gp.minimapHint:GetText()
    if cb then cb:SetChecked(false); cb.onClick(false, cb) end
    local off = MD.db.minimap.hide == true and not B:IsShown()
    if cb then cb:SetChecked(true); cb.onClick(true, cb) end
    local on = MD.db.minimap.hide == false and B:IsShown()
    -- the pane says what the db holds when it is shown again
    MD.db.minimap.hide = true
    if MD.SelectView then MD:SelectView("settings", "general") end
    local refreshed = cb and not cb:GetChecked()
    MD.db.minimap.hide = false
    MD:UpdateMinimapButton()
    check("5. WINDOWS: Minimap button hides the button and writes db.minimap.hide; ticked, back",
        cb ~= nil and startTicked and off and on and refreshed and label == "Minimap button"
          and hint == "Left-click opens the window, right-click opens Settings.",
        string.format("cb=%s start=%s off=%s on=%s refreshed=%s label=%s hint=%s", tostring(cb ~= nil),
            tostring(startTicked), tostring(off), tostring(on), tostring(refreshed), tostring(label),
            tostring(hint)))
end)
if main and main:IsShown() then main:Hide() end

Guarded("6. the themed tooltip is M6's, its clock lines the clock hover's own", function()
    -- a fight, so the clock has an out-of-mana time and a rest time to say
    local Clock = MD.Clock
    local model = MD.Pool.model
    model.mana = model.max
    S.Tick(0.5)
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    for _ = 1, 40 do
        S.Cast(5176) -- Wrath, cost 20
        S.Tick(0.5)
    end
    local lines, anchor = Hover()
    -- the clock's own hover at the same moment
    GameTooltip.lines = {}
    Clock.frame:GetScript("OnEnter")(Clock.frame)
    local clockLines = {}
    for _, l in ipairs(GameTooltip.lines or {}) do
        clockLines[#clockLines + 1] = { l = l[1], r = l[2], c = l.color, rc = l.rcolor }
    end
    Clock.frame:GetScript("OnLeave")(Clock.frame)
    local summary = Clock.SummaryLines and Clock:SummaryLines() or {}
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false

    local function Is(c, token)
        local r, g, b = MD.UI.RGB(token)
        return type(c) == "table" and c[1] == r and c[2] == g and c[3] == b
    end
    local function Pair(i, l, r) return lines[i] and lines[i].l == l and lines[i].r == r and Is(lines[i].c, "label") end
    local n = #lines
    local title = lines[1] and lines[1].l == "SpellTuner" and lines[1].r == nil and Is(lines[1].c, "accent")
    local out = lines[2] and lines[2].l == "Out of mana in" and type(lines[2].r) == "string"
        and lines[2].r:find("^~%d+:%d%d$") ~= nil and Is(lines[2].rc, "mana")
    local rest = lines[3] and lines[3].l == "Full again in" and type(lines[3].r) == "string"
        and lines[3].r:find("^~%d+:%d%d if you stop$") ~= nil and Is(lines[3].rc, "mana")
    -- the game (and the stub) holds a spacer as a line of one blank
    local spacer = lines[n - 4] and (lines[n - 4].l == nil or lines[n - 4].l == " ") and lines[n - 4].r == nil
    local hints = Pair(n - 3, "Left-click", "open the window") and Pair(n - 2, "Right-click", "Settings")
        and Pair(n - 1, "Drag", "move it round the map")
    local hide = lines[n] and lines[n].l == "Hide it: Settings -> General -> Windows." and lines[n].r == nil
        and Is(lines[n].c, "muted")
    -- the clock lines between the title and the spacer are SummaryLines', and
    -- the clock's own hover carries the same pairs (after its Mana line)
    -- title, summary, spacer, three hints, the hide line
    local fromSummary = #summary >= 2 and (n - 6) == #summary
    for i, s in ipairs(summary) do
        local l = lines[i + 1]
        if not (l and l.l == s.l and l.r == s.r) then fromSummary = false end
        local found = false
        for _, h in ipairs(clockLines) do if h.l == s.l and h.r == s.r then found = true end end
        if not found then fromSummary = false end
    end
    local clean = true
    for _, l in ipairs(lines) do
        for _, s in ipairs({ l.l, l.r }) do
            if type(s) == "string" and not T.Ascii(s) then clean = false end
        end
    end
    local shown = {}
    for _, l in ipairs(lines) do shown[#shown + 1] = tostring(l.l) .. "=" .. tostring(l.r) end
    check("6. the themed tooltip is M6's, its clock lines the clock hover's own",
        title and out and rest and spacer and hints and hide and fromSummary and clean and n == 8
          and anchor == "ANCHOR_LEFT",
        string.format("title=%s out=%s rest=%s spacer=%s hints=%s hide=%s summary=%s clean=%s anchor=%s [%s]",
            tostring(title), tostring(out), tostring(rest), tostring(spacer), tostring(hints), tostring(hide),
            tostring(fromSummary), tostring(clean), tostring(anchor), table.concat(shown, "; ")))
end)

CollectedCheck("9. a collected button is not pulled back; its icon is btn.icon (T97)")

-- 8: one owner for the default (P20's rule): the button file registers it and
-- no file on any TOC carries a `minimap = {` default of its own.
do
    local files, seen = {}, {}
    for _, toc in ipairs({ "SpellTuner_TBC.toc", "SpellTuner_Mainline.toc", "SpellTuner.toc" }) do
        for _, rel in ipairs(S.TocFiles(toc)) do
            if not seen[rel] then seen[rel] = true; files[#files + 1] = rel end
        end
    end
    if not seen[BUTTON_FILE] then files[#files + 1] = BUTTON_FILE end
    local owners = {}
    for _, rel in ipairs(files) do
        local f = io.open(root .. "/" .. rel, "r")
        if f then
            local src = f:read("*a"); f:close()
            for line in src:gmatch("[^\n]+") do
                local code = line:gsub("%-%-.*$", "")
                if (" " .. code):find("[^%.%w_]minimap%s*=%s*{") then owners[#owners + 1] = rel end
            end
        end
    end
    local registers = false
    local f = io.open(root .. "/" .. BUTTON_FILE, "r")
    if f then
        local src = f:read("*a"); f:close()
        registers = src:find("MD:RegisterDefaults%(%s*{%s*minimap%s*=%s*{%s*hide%s*=%s*false%s*,%s*angle%s*=%s*220%s*}") ~= nil
    end
    check("8. the minimap default is declared once, by the button file (MD:RegisterDefaults)",
        registers and #owners == 1 and owners[1] == BUTTON_FILE,
        "registers=" .. tostring(registers) .. " declared in: " .. table.concat(owners, ", "))
end

T.done()
