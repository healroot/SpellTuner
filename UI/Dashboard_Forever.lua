-- Forever's window (T2 of docs/ROADMAP-FOREVER.md): the Cell-style navigation
-- frame from UI/Style.lua (shared) with four groups -- Spells (since T36 a
-- rail group, UI/SpellsPane_Forever.lua), Reports, Simulate and Settings
-- (-> Modules switches the three LoadOnDemand siblings on or off). Built on first use, not at load: TBC's
-- own UI/Dashboard.lua stays TBC-only and reads none of this.
--
-- Client calls only through MD.API; nothing here calls one directly (the
-- widget toolkit and WoW's Lua extensions are not client calls -- CLAUDE.md,
-- T1b Facts).
local _, MD = ...
local UI = MD.UI

-- T32 (docs/SPEC-forever-ui.md 6.7): the window's size is the window
-- manager's, one per group (UI/Windows_Forever.lua, MD.Win.SIZES) -- Reports
-- and Simulate at 1036 x 646 for the Review and Practice panes' 912-wide
-- content, Spells and Settings at 860 x 560. The late grow on MODULE_LOADED is
-- gone. These are only the size the frame is built at, before MD.Win places it.
local WIDTH, HEIGHT = 860, 560

local nav, frame

local function Groups()
    return {
        -- T36 (docs/SPEC-forever-ui.md 3.1): a rail group; its rows are the
        -- player's own spell list (UI/SpellsPane_Forever.lua)
        MD.SpellsPane:Group(),
        { id = "reports", text = "Reports", views = {
            { id = "review", text = "Review" } } },
        -- T18: a placeholder until the Practice module is on (Files/Rules),
        -- same shape as Reports -> Review's own placeholder-then-module.
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" } } },
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" },
            { id = "modules", text = "Modules" } } },
    }
end

--------------------------------------------------------------------------------
-- Settings -> General
--------------------------------------------------------------------------------
-- T42 (docs/SPEC-forever-ui.md section 9's T42 row, 4.2, 4.3, 6.5, 6.6): three
-- titled panes, Cell's (title at 0, the rule at -17, the first control at -27,
-- 12 between panes):
--   SPELL TOOLTIPS  the block on or off, and T37's detail key (5.6)
--   APPEARANCE      the font offset (-2..+2, UI.ApplyFonts: every font object
--                   re-sized and the Spells pane re-rendered, 4.2), the window
--                   scale (70-120 %, MD.Win:SetScale, 4.3), the mana clock
--   WINDOWS         combat hide / keep (6.6), one window per ESC (6.5,
--                   db.ui.escStack), Reset window positions (/st ui reset)
-- Each control writes its db field and applies it at once. The font offset
-- follows the slider as it moves; the scale waits for the mouse-up (Cell's
-- rule: the window must not scale under the pointer mid-drag).
local generalPane

local PANE_GAP = 12

local function Round(v) return math.floor((tonumber(v) or 0) + 0.5) end

local function RefreshGeneralPane()
    if not generalPane or not generalPane.tooltipCheck then return end
    local p = generalPane
    p.tooltipCheck:SetChecked(MD.db.spellTooltip ~= false)
    if p.clockCheck then
        p.clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    end
    if p.detailDropdown and MD.SpellTip and MD.SpellTip.DetailMode then
        p.detailDropdown:SetValue(MD.SpellTip:DetailMode())
    end
    local u = type(MD.db.ui) == "table" and MD.db.ui or {}
    if p.fontSlider then p.fontSlider:SetValue(Round(UI.fontOffset or u.fontOffset)) end
    if p.scaleSlider and MD.Win then p.scaleSlider:SetValue(MD.Win:ScalePercent()) end
    if p.combatDropdown and MD.Win then p.combatDropdown:SetValue(MD.Win:CombatMode()) end
    if p.escCheck and MD.Win then p.escCheck:SetChecked(MD.Win:EscStackOn()) end
end

-- A titled pane across the view, under `above` (nil: the view's top).
local function Section(pane, text, height, above)
    local t = UI.CreateTitledPane(pane, text, 400, height)
    if above then
        t:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -PANE_GAP)
    else
        t:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    end
    t:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    return t
end

local function BuildTooltipSection(pane)
    local sec = Section(pane, "SPELL TOOLTIPS", 64)

    local check = UI.CreateCheckButton(sec, "Add SpellTuner lines to spell tooltips", function(checked)
        MD.db.spellTooltip = checked and true or false
    end)
    check:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -27)
    check:SetChecked(MD.db.spellTooltip ~= false)
    pane.tooltipCheck = check -- marks this pane for tools/tipcheck.lua

    -- T37 (5.6, decision 5): the key that shows the block's detail lines
    if MD.SpellTip and MD.SpellTip.DETAIL_MODES then
        local detailLabel = sec:CreateFontString(nil, "OVERLAY", UI.FONT)
        detailLabel:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -10)
        detailLabel:SetText("Detail lines")
        local dd = UI.CreateDropdown(sec, 120, 18, function(id)
            MD.db.spellTooltipDetail = id
        end)
        dd:SetPoint("LEFT", detailLabel, "RIGHT", 8, 0)
        dd:SetItems(MD.SpellTip.DETAIL_MODES)
        dd:SetValue(MD.SpellTip:DetailMode())
        pane.detailDropdown = dd -- marks this pane for tools/tipcheck.lua
    end
    return sec
end

local function BuildAppearanceSection(pane, above)
    local sec = Section(pane, "APPEARANCE", 104, above)

    -- 4.2: -2..+2 (decision 13), every SpellTuner font; the Spells pane's
    -- pitches follow (UI.ApplyFonts is wrapped by UI/SpellsPane_Forever.lua)
    if UI.ApplyFonts then
        local lo, hi = UI.FONT_OFFSET_MIN or -2, UI.FONT_OFFSET_MAX or 2
        local slider = UI.CreateSlider("Font offset", sec, lo, hi, 150, 1, function(value)
            local u = MD.db.ui
            if type(u) ~= "table" then u = {}; MD.db.ui = u end
            u.fontOffset = UI.ApplyFonts(value)
        end, nil, false,
            "Font offset", "Every SpellTuner text a size bigger or smaller, -2 to +2.",
            "Spells' rows and cards move apart with it.")
        slider:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -45)
        pane.fontSlider = slider
    end

    -- 4.3: 70-120 %, through the window manager (the saved places converted)
    if MD.Win then
        local lo, hi = Round(MD.Win.SCALE_MIN * 100), Round(MD.Win.SCALE_MAX * 100)
        local slider = UI.CreateSlider("Window scale", sec, lo, hi, 150, 5, nil, function(value)
            MD.Win:SetScale((tonumber(value) or 100) / 100)
        end, true,
            "Window scale", "The main, replay and practice windows, the console and the copy box.")
        slider:SetPoint("TOPLEFT", sec, "TOPLEFT", 205, -45)
        pane.scaleSlider = slider
    end

    local clockCheck = UI.CreateCheckButton(sec, "Show the mana clock", function(checked)
        MD.db.clock = MD.db.clock or {}
        MD.db.clock.shown = checked and true or false
        if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
    end)
    clockCheck:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -84)
    clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    pane.clockCheck = clockCheck -- marks this pane for tools/clockcheck.lua
    return sec
end

local function BuildWindowsSection(pane, above)
    if not MD.Win then return nil end
    local sec = Section(pane, "WINDOWS", 100, above)

    -- 6.6, decision 4
    local combatLabel = sec:CreateFontString(nil, "OVERLAY", UI.FONT)
    combatLabel:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -29)
    combatLabel:SetText("In combat")
    local dd = UI.CreateDropdown(sec, 160, 18, function(id)
        MD.Win:SetCombat(id)
    end)
    dd:SetPoint("LEFT", combatLabel, "RIGHT", 8, 0)
    dd:SetItems(MD.Win.COMBAT_MODES)
    dd:SetValue(MD.Win:CombatMode())
    pane.combatDropdown = dd

    -- 6.5: off is the fallback, one UISpecialFrames entry per window
    local esc = UI.CreateCheckButton(sec, "Close one window per ESC", function(checked)
        MD.Win:SetEscStack(checked)
    end, "Close one window per ESC",
        "On: each ESC closes the window opened last, then the next.",
        "Off: one ESC closes every SpellTuner window at once.")
    esc:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -55)
    esc:SetChecked(MD.Win:EscStackOn())
    pane.escCheck = esc

    local reset = UI.CreateButton(sec, "Reset window positions", "accent-hover", { 170, 20 }, false, false,
        nil, nil, "Reset window positions",
        "Every SpellTuner window back at its default place and size (/st ui reset).")
    reset:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -77)
    reset:SetScript("OnClick", function()
        MD.Win:Reset()
        MD:Print("windows: every position and size reset")
    end)
    pane.resetButton = reset
    return sec
end

local function BuildGeneralPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local tips = BuildTooltipSection(pane)
    local look = BuildAppearanceSection(pane, tips)
    BuildWindowsSection(pane, look)
    return pane
end

--------------------------------------------------------------------------------
-- Settings -> Modules
--------------------------------------------------------------------------------
local function ModuleLabel(name)
    for _, m in ipairs(MD.modules or {}) do
        if m.name == name then return m.label end
    end
    return name
end

-- One line, from MD:ModuleState -- ASCII only, the reason already sanitised
-- by Core.lua's registry (a bad LoadAddOn reason becomes "unknown" there).
local function StateText(name)
    local state, reason = MD:ModuleState(name)
    if state == "loaded" then return "loaded" end
    if state == "on" then return "on - loads at login" end
    if state == "failed" then return "could not load: " .. tostring(reason) end
    if state == "unloads" then return "off - unloads at your next /reload" end
    return "off"
end

local modulesPane

local function RefreshModulesPane()
    if not modulesPane or not modulesPane.rows then return end
    for _, m in ipairs(MD.modules or {}) do
        local row = modulesPane.rows[m.name]
        if row then
            row.check:SetChecked(MD.db.modules and MD.db.modules[m.name] == true)
            row.state:SetText(StateText(m.name))
        end
    end
end

local function BuildModulesPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.rows = {}

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    title:SetText("Modules")

    local prevRow
    for _, m in ipairs(MD.modules or {}) do
        local row = CreateFrame("Frame", nil, pane)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -10)
        else
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -30)
        end
        row:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
        row:SetHeight(48)

        local check = UI.CreateCheckButton(row, m.label, function(checked)
            MD:SetModule(m.name, checked)
            RefreshModulesPane()
        end)
        check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

        local text = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        text:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 19, -2)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetText(m.text or "")

        local anchor = text
        if m.needs and #m.needs > 0 then
            local labels = {}
            for _, n in ipairs(m.needs) do labels[#labels + 1] = ModuleLabel(n) end
            local needsFS = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
            needsFS:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
            needsFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            needsFS:SetJustifyH("LEFT")
            needsFS:SetText("needs " .. table.concat(labels, ", "))
            anchor = needsFS
        end

        local state = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        state:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        state:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        state:SetJustifyH("LEFT")

        pane.rows[m.name] = { check = check, state = state }
        prevRow = row
    end

    return pane
end

--------------------------------------------------------------------------------
-- Spells: T36 moved the whole group into UI/SpellsPane_Forever.lua (the rail,
-- the list, the picker, Overview with today's Spellbook table and Export, a
-- family's view). This file only wires it: the group's definition, onCreate,
-- onShow, and the rail's footer once the nav exists.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Reports -> Review (T16b, docs/tasks/T16b-review-tab.md): the TBC Review tab
-- (UI/Dashboard_Review.lua, shared) with the Replay module on; a placeholder
-- naming how to switch it on, off. The placeholder never loads the module --
-- only the Modules pane's own switch does (Rules).
--------------------------------------------------------------------------------
local reviewPane        -- the api object MD.DashboardParts.CreateReview hands back
local reviewPlaceholder -- the placeholder frame, while the module is off

local function BuildReviewPlaceholder(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local text = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    text:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText("Review needs the Replay module - Settings -> Modules")

    pane.reviewPlaceholder = true -- marks this pane for tools/reviewforever.lua
    reviewPlaceholder = pane
    return pane
end

local function BuildReviewPane(content)
    reviewPane = MD.DashboardParts.CreateReview(content, 912)
    reviewPane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    reviewPane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return reviewPane.frame
end

local function RefreshReviewPane()
    if reviewPane then reviewPane:Render() end
end

--------------------------------------------------------------------------------
-- Simulate -> Practice (T18, docs/tasks/T18-practice-forever.md): the TBC
-- practice panel (UI/PracticePanel.lua, shared with TBC) with the Practice
-- module on; a placeholder naming how to switch it on while it is off, same
-- shape as Reports -> Review's own (Rules: never loads the module itself).
--------------------------------------------------------------------------------
local practicePane        -- the api object MD.DashboardParts.CreatePractice hands back
local practicePlaceholder -- the placeholder frame, while the module is off

local function BuildPracticePlaceholder(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local text = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    text:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText("Practice needs the Practice module - Settings -> Modules")

    pane.practicePlaceholder = true -- marks this pane for tools/practiceforever.lua
    practicePlaceholder = pane
    return pane
end

local function BuildPracticePane(content)
    practicePane = MD.DashboardParts.CreatePractice(content, 912)
    practicePane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    practicePane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return practicePane.frame
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function CreateDashboard()
    if nav then return end -- MD_READY-equivalent callers may ask more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIDTH, HEIGHT, Groups(),
        function(group, view, content)
            if group == "spells" then
                return MD.SpellsPane:Create(content) -- T36: one frame for every Spells view
            elseif group == "reports" and view == "review" then
                if MD.DashboardParts.CreateReview then
                    return BuildReviewPane(content)
                end
                return BuildReviewPlaceholder(content)
            elseif group == "simulate" and view == "practice" then
                if MD.DashboardParts.CreatePractice then
                    return BuildPracticePane(content)
                end
                return BuildPracticePlaceholder(content)
            elseif group == "settings" and view == "general" then
                generalPane = BuildGeneralPane(content)
                return generalPane
            elseif group == "settings" and view == "modules" then
                modulesPane = BuildModulesPane(content)
                return modulesPane
            end
            return nil
        end,
        function(group, view, pane)
            -- T32: the group's own size, the TOPLEFT kept (6.7)
            if MD.Win then MD.Win:SetGroup("main", group) end
            if group == "settings" and view == "general" then RefreshGeneralPane() end
            if group == "settings" and view == "modules" then RefreshModulesPane() end
            if group == "reports" and view == "review" then RefreshReviewPane() end
            -- "refreshed on show" (Goal): nav:Select runs this on every visit,
            -- the FIRST included -- a plain Show()/OnShow pair would miss the
            -- first one, since a frame is created already shown (CLAUDE.md's
            -- "one owner" rule is about hide/show, not about this).
            if group == "spells" then MD.SpellsPane:Show(view) end
        end, { resizable = true, notUserPlaced = true })
    frame = nav.frame
    MD.SpellsPane:Attach(nav) -- T36: the rail's [ + Add ] and Undo line

    frame:SetScript("OnShow", function()
        local path = MD.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[2])
        else
            nav:Select("spells", nil) -- T36: the rail's first row, Overview
        end
    end)

    -- T32: strata, place, scale, the size per group (6.2, 6.7). T33 (6.5): the
    -- manager's ESC stack instead of a UISpecialFrames entry of its own (one
    -- ESC would otherwise close this and the top of the stack together);
    -- registered after the OnShow script above, since Register hooks OnShow.
    if MD.Win then
        MD.Win:Register(frame, { key = "main", role = "host", sizes = MD.Win.SIZES })
    else
        tinsert(UISpecialFrames, "SpellTunerDashboard") -- ESC closes
    end
end

function MD:ShowDashboard()
    CreateDashboard()
    if frame then frame:Show() end
end

function MD:ToggleDashboard()
    CreateDashboard()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    elseif MD.Win then
        MD.Win:ShowMain() -- T32: on the remembered view
    else
        frame:Show()
    end
end

-- T32: what MD.Win:ShowMain opens -- the window on the view asked for, or on
-- the remembered one when none is named. Opens the window if closed.
function MD:OpenMainWindow(group, view)
    CreateDashboard()
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    if group then nav:Select(group, view) end
end

-- Every entry point that wants a particular view goes through here (/st
-- modules today; the same door M2/M3/M4 use). Since T32 (6.3) it goes
-- through the window manager, which T34 teaches the takeover rules.
function MD:SelectView(group, view)
    if MD.Win then return MD.Win:ShowMain(group, view) end
    return MD:OpenMainWindow(group, view)
end

function MD:SelectedView()
    if not nav then return nil end
    return nav:Selected()
end

-- A module can finish loading while the pane is open (the click that
-- switched it on already refreshes; this covers CORE_READY's own login-time
-- loads landing while the window happens to be up from a previous session
-- were that ever possible, and any other module firing MODULE_LOADED later).
MD:RegisterCallback("MODULE_LOADED", RefreshModulesPane)

-- T16b: SpellTuner_Replay finishing load (its own last file, Ready.lua)
-- brings MD.DashboardParts.CreateReview with it. If a placeholder is what the
-- Review view is currently showing, replace it with the real pane --
-- re-selecting it if it happens to be the one on screen, which both shows the
-- new pane (nav.panes already carries it) and refreshes it. (T32: the window
-- no longer grows here -- Reports has its own size, 6.7.)
MD:RegisterCallback("MODULE_LOADED", function(name)
    if name ~= "SpellTuner_Replay" or not MD.DashboardParts.CreateReview then return end
    if nav and nav.panes and nav.panes.reports and nav.panes.reports.review == reviewPlaceholder
            and reviewPlaceholder then
        local content = nav:Content()
        local pane = BuildReviewPane(content)
        nav.panes.reports.review = pane
        reviewPlaceholder:Hide()
        reviewPlaceholder = nil
        if nav.group == "reports" and nav.view == "review" then
            nav:Select("reports", "review")
        end
    end
end)

-- T18: SpellTuner_Practice finishing load brings MD.DashboardParts.CreatePractice
-- with it -- same swap as the Review one above, on the Simulate -> Practice
-- placeholder.
MD:RegisterCallback("MODULE_LOADED", function(name)
    if name ~= "SpellTuner_Practice" or not MD.DashboardParts.CreatePractice then return end
    if nav and nav.panes and nav.panes.simulate and nav.panes.simulate.practice == practicePlaceholder
            and practicePlaceholder then
        local content = nav:Content()
        local pane = BuildPracticePane(content)
        nav.panes.simulate.practice = pane
        practicePlaceholder:Hide()
        practicePlaceholder = nil
        if nav.group == "simulate" and nav.view == "practice" then
            nav:Select("simulate", "practice")
        end
    end
end)
