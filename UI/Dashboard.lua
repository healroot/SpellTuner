-- Rank dashboard (/st): a Cell-style movable frame (header bar with title and
-- close), the groups and their views. Reports keeps its header lines and the
-- recap. Settings -> General, Review and About are UI/Settings.lua's (T119),
-- Settings -> Clock UI/ClockSettings.lua's.
--
-- T119 (docs/SPEC-one-ui.md 7, mockup M6): Settings is one file on both lines
-- -- General, Clock, Review, About, built by ST.Settings from this line's rows
-- (UI/Settings_TBC.lua) -- at 860 x 560, fixed, as Forever's. The options
-- frame (ST.optionsFrame, UI/OptionsFrame.lua) is gone; ST:ShowOptionsFrame
-- stays as the door /st options and the minimap button use.
--
-- T84 (C5 of docs/PLAN-refactor-ux.md, section 7.1; mockup M4 layout B and
-- M6): the Spells group is the rail, as on Forever -- MY SPELLS, Overview
-- first, then one row per family of the player's own list (Spells/Tabs.lua
-- over Spells/Families_TBC.lua), with [ + Add ] and its picker, the Undo
-- line, drag to reorder, one x and the right-click row menu (UI/SpellRail.lua
-- installed on ST.SpellsTBC until T120). Overview is My spells
-- (UI/SpellsView_TBC.lua's CreateSpellsOverview); a family's row ("fam:<key>")
-- opens the TBC Spells view (T83, C3: the header, the chip and one
-- comparison, the rank table, the card, "After overheal" and "What if...").
-- C3's four view tabs are gone. /st opens on Overview the first time, then on
-- the remembered row; a path saved before C5 ("spells", "Regrowth") opens
-- that family's row.
--
-- T120 (docs/tasks/T120-one-spells-pane.md): the Spells group is the shared
-- pane, UI/SpellsPane.lua, wired as Forever wires it (Group, Create, Show,
-- Attach) over ST.Book (Spells/Book_Model.lua), at 860 x 560 fixed.
-- ST.SpellsTBC, UI/SpellsView_TBC.lua and the spells branch of Refresh are
-- gone; what differs on this line is ST.SpellsLine below (the footer, RANKS'
-- note, After overheal on db.effectiveMode, Overview's refusal for a class
-- without the rank table). No What if until T122.
--
-- T80 (C1 of docs/PLAN-refactor-ux.md, decision 10, the author's answer 1):
-- the window is the window manager's (UI/Windows.lua) as on Forever -- placed
-- by it, a size per group handed in at Register (SIZES below), on the ESC
-- stack instead of UISpecialFrames, hidden in combat and reopened on the same
-- view, and every ST:SelectView through ST.Win:ShowMain. A place the client
-- kept for it while it was user-placed is adopted once.
local _, ST = ...
local UI = ST.UI

local WIDTH, HEIGHT = 912, 617 -- +20% (author, 2026-09-06: not everything fit); was 760 x 514
local frame, statsFS, calloutFS, hintFS, recapFS
local wasteView, reviewView, practiceView, nav
local currentGroup = "spells"
local currentFamily = "overview" -- the selected VIEW id (a family's is "fam:<key>")
local lastSettingsView -- T119: the General / Review / About view last shown (ST:ShowOptionsFrame)

--------------------------------------------------------------------------------
-- T120: the Spells group is UI/SpellsPane.lua's (the rail, Overview, a
-- family's view), over ST.Book. What this line hands it is ST.SpellsLine.
--------------------------------------------------------------------------------
local VIEW_PREFIX = ST.SpellRail and ST.SpellRail.VIEW_PREFIX or "fam:"

-- A view id as the rail names it: a bare family key (a path saved before
-- C5, or a caller that names "Regrowth") becomes its row's id -- the
-- families are the book's (T120; ST.SpellData's before).
local function SpellsViewId(view)
    if type(view) ~= "string" or view:sub(1, #VIEW_PREFIX) == VIEW_PREFIX then return view end
    local book = ST.Book and ST.Book:Get() or nil
    if book and book.families and book.families[view] then return VIEW_PREFIX .. view end
    return view
end

-- The family's measured overheal, "25% measured" (C3's words), or nil.
local function MeasuredWord(fam)
    if not (ST.Overheal and ST.Overheal.FamilyFraction and fam and fam.key) then return nil end
    local frac = ST.Overheal:FamilyFraction(fam.key)
    if type(frac) ~= "number" then return nil end
    return string.format("%d%% measured", math.floor(frac * 100 + 0.5))
end

ST.SpellsLine = {
    footer = "Values from the model: your gear, talents and the downrank rules.",
    ranksNote = function(fam)
        if fam and fam.kind == "heal" then return "live: gear, talents, downrank rules" end
        if fam and fam.kind == "damage" then return "live: gear, talents" end
        return nil
    end,
    critNote = nil, -- the crit is the model's: the card says its chance
    -- C3's "After overheal", the same setting (db.effectiveMode)
    afterOverheal = {
        get = function() return ST.db.effectiveMode == true end,
        set = function(on) ST.db.effectiveMode = on and true or false end,
        word = MeasuredWord,
    },
    -- T99's refusal, on Overview now (it still lists what it can)
    overviewNote = function()
        local can, why = ST.ClassProfile:Can("rankTable")
        if can then return nil end
        return ST.Profiles.Refusal("rankTable", why, "Rank analysis")
            .. " - the OOM widget, datatext and advisor still work for your class."
    end,
}

local function RefreshSpellRail()
    if ST.SpellsPane and ST.SpellsPane.RefreshRail then ST.SpellsPane:RefreshRail() end
end

--------------------------------------------------------------------------------
-- refresh
--------------------------------------------------------------------------------
local function Shown(f, on) if not f then return end if on then f:Show() else f:Hide() end end

-- The regen line Reports keeps above Waste and Review (the Spells view says
-- the same in its +healing hover since T83).
local function StatsLine()
    local RM = ST.Regen
    local bonus = 0
    if GetSpellBonusHealing then
        local ok, v = pcall(GetSpellBonusHealing)
        if ok then bonus = v or 0 end
    end
    local spiritPerSec, mp5Gear, _, unreported = RM:Components()
    return string.format(
        "+%d healing   regen |cff33ff66%d|r mana/s out of 5SR, |cffffaa33%d|r casting   ~%d mp5 spirit, ~%d mp5 gear/buffs%s",
        bonus, RM.base, RM.casting, spiritPerSec * 5, mp5Gear,
        unreported > 0 and string.format(", +%d mp5 not in the API (Dreamstate %d, measured %d)",
            unreported * 5 + 0.5, RM.dreamstate * 5 + 0.5, RM.measured * 5 + 0.5) or "")
end

local function Refresh()
    if not frame or not frame:IsShown() then return end

    -- Only Reports owns this furniture now: the Spells view (T83) is a pane of
    -- its own, and Simulate and Settings bring their own panel -- drawing the
    -- header lines on top of them is what the author's screenshots showed
    -- (v0.11.5).
    local reports = currentGroup == "reports"
    Shown(statsFS, reports)
    Shown(calloutFS, reports)
    Shown(hintFS, reports)
    Shown(recapFS, reports)

    if not reports then return end -- T120: the Spells pane refreshes itself

    statsFS:SetText(StatsLine())

    -- the Waste and Review views; a pane is built on first sight, so either
    -- may still be nil
    local review = (currentFamily == "Review" or currentFamily == "Runs")
    if review and reviewView then
        calloutFS:SetText("|cffffcc00The fights this character recorded, and what the engine can reproduce about each.|r")
        -- T81: Review's words since C1 gave TBC the Result column and the
        -- row menu (it named a validate column and a passing-only Coach)
        hintFS:SetText(UI.Hex("muted") .. "A fight the engine cannot replay says why in the Result column. Coach runs " ..
            "only on fights that replay, because advice from a fight the engine gets wrong is worse than none; " ..
            "right-click a row for Coach anyway.|r")
        reviewView:Render()
    elseif currentFamily == "Waste" and wasteView then
        calloutFS:SetText("|cffffcc00Where the mana went and where the healing was wasted, from your own combat log.|r")
        hintFS:SetText("|cff888888Overheal is a share of gross healing. Wasted mana is each event that healed nothing, " ..
            "carrying its share of the cast's cost. Mana belongs to the spell, so it only appears in Spell mode.|r")
        wasteView:Render()
    end

    -- recap
    local last = ST.fightHistory and ST.fightHistory[#ST.fightHistory]
    if last then
        recapFS:SetText("Last fight: " .. (last.summary or "-") ..
            (#ST.fightHistory > 1 and ("  |cff666666(" .. #ST.fightHistory .. " fights this session)|r") or ""))
    else
        recapFS:SetText("|cff666666No fights recorded this session yet.|r")
    end
end

--------------------------------------------------------------------------------
-- frame construction (v0.11.1: the navigation kit, docs/SPEC-v0.11.md)
--
-- The window is groups down the left and that group's views along the top. The
-- three panes -- the rank table, Waste and Review -- are unchanged and simply
-- parent themselves to the content frame; they are built the first time their
-- view is selected and cached after, so a non-druid never builds a rank table.
--
-- `currentFamily` is the selected VIEW id, which is why the families and the
-- two reports can share one variable: a family's row ("fam:Rejuvenation"
-- since T84, the rail's) and a report id ("Waste") are both just the view
-- that is showing.
--------------------------------------------------------------------------------
local CONTENT_W = 912          -- what the panes were laid out for; the window is wider by the nav
local NAV_W, NAV_PAD = 108, 8
local WIN_W, WIN_H = CONTENT_W + NAV_W + 2 * NAV_PAD, 646

-- T80 (C1, review A22): TBC's sizes per group, handed to the window manager
-- at Register. Every pane here is laid out for the 912-wide content, so each
-- group is today's 1036 x 646 and fixed (its minimum is its size: no grip).
-- T120 (D4): Spells is the shared pane at Forever's size, fixed.
local SIZES = {
    spells   = { w = 860, h = 560, minW = 860, minH = 560 },
    reports  = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    simulate = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    -- T119 (SPEC-one-ui 7): Settings in two columns at Forever's size
    settings = { w = 860, h = 560, minW = 860, minH = 560 },
}

-- Reports' views depend on what has been recorded.
local function ReportViews()
    local views = { { id = "Waste", text = "Waste" }, { id = "Review", text = "Review" } }
    if ST.RunRecorder and #(ST.RunRecorder:List()) > 0 then
        views[#views + 1] = { id = "Runs", text = "Runs" }
    end
    return views
end

local function Groups()
    return {
        -- T84 (C5): the rail -- Overview, then the player's own list;
        -- T120: UI/SpellsPane.lua's group, as on Forever
        ST.SpellsPane:Group(),
        -- Waste and Review work for any class: a recorded stream is numbers
        -- Runs appears only once one has been recorded: a view that is always
        -- empty teaches nothing, and nav:SetViews puts it there the moment a
        -- run is stored (v0.11.4)
        { id = "reports", text = "Reports", views = ReportViews() },
        -- v0.15.0: Practice first. Building a fight for the planner to play
        -- answered a question nobody was asking; playing it yourself does
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" }, { id = "build", text = "Build a fight" } } },
        -- T102 (docs/SPEC-next.md 7.4): Clock between General and About;
        -- T119: Review after it (UI/Settings.lua's views, in order)
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" }, { id = "clock", text = "Clock" },
            { id = "review", text = "Review" }, { id = "about", text = "About" } } },
    }
end

-- T102 (docs/SPEC-next.md 7.3-7.4, mockup M8g): this line's own clock switches
-- for Settings -> Clock's Text (since T116) and When tabs -- the keys the OOM Widget pane
-- and /st rest, /st lock, /st tooltip write (UI/ClockSettings.lua never reads
-- a line's keys itself).
local function Visibility()
    if ST.UpdateVisibility then ST:UpdateVisibility() end
end
local CLOCK_SWITCHES = {
    show = {
        { text = "Rest time (rest 2:10)", segment = "rest", tips = { "Show rest time",
              "Grey 'rest 2:10' next to the clock:", "time to full if you stop casting right now. Same as /st rest." },
          get = function() return ST.db.showRest ~= false end,
          set = function(on) ST.db.showRest = on end },
        { text = "Mana cooldown (inn 2:10)", segment = "cd", tips = { "Mana cooldown projection",
              "Under 90s to OOM, with Innervate (or a potion) ready, what the clock",
              "becomes if you press it now. It replaces 'rest' there." },
          get = function() return ST.db.showCooldown ~= false end,
          set = function(on) ST.db.showCooldown = on end },
    },
    when = {
        { text = "Locked", tips = { "Lock widget", "Unticked: the clock stays up and can be dragged." },
          get = function() return ST.db.locked == true end,
          set = function(on) ST.db.locked = on; Visibility() end },
        { text = "Tooltip and left-click", tips = { "Tooltip on the floating clock",
              "Off: the clock takes no mouse input at all (click-through),",
              "and stays draggable while unlocked. Same as /st tooltip." },
          get = function() return ST.db.widgetTooltip ~= false end,
          set = function(on) ST.db.widgetTooltip = on; Visibility() end },
    },
}

local function CreateDashboard()
    if nav then return end     -- MD_READY can be fired more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIN_W, WIN_H, Groups(),
        function(group, view, content)
            -- built once, on first sight
            if group == "reports" and view == "Waste" then
                wasteView = ST.DashboardParts.CreateWaste(content, CONTENT_W)
                wasteView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                wasteView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return wasteView.frame
            elseif group == "reports" and view == "Runs" then
                -- the Review pane already knows how to list a run's pulls; the
                -- Runs view is that pane with a run selected instead of Fights
                if not reviewView then
                    reviewView = ST.DashboardParts.CreateReview(content, CONTENT_W)
                    reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                    reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                end
                return reviewView.frame
            elseif group == "reports" and view == "Review" then
                reviewView = ST.DashboardParts.CreateReview(content, CONTENT_W)
                reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return reviewView.frame
            elseif group == "simulate" and view == "practice" then
                practiceView = ST.DashboardParts.CreatePractice(content, CONTENT_W)
                practiceView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
                practiceView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
                return practiceView.frame
            elseif group == "simulate" then
                if ST.AdoptSimPanel then return ST:AdoptSimPanel(content) end
                return nil
            elseif group == "settings" and view == "clock" then
                -- T102: Settings -> Clock, a pane of its own (UI/ClockSettings.lua)
                if ST.ClockSettings and ST.ClockSettings.Build then
                    return ST.ClockSettings.Build(content, CLOCK_SWITCHES)
                end
                return nil
            elseif group == "settings" then
                -- T119: General, Review and About, UI/Settings.lua's
                if ST.Settings and ST.Settings.Owns(view) then return ST.Settings.Build(view, content) end
                return nil
            elseif group == "spells" then
                return ST.SpellsPane:Create(content) -- T120: one frame for every Spells view
            end
            return nil
        end,
        function(group, view, pane)
            -- T102: Settings -> Clock's controls from the saved look
            if group == "settings" and view == "clock" and ST.ClockSettings then ST.ClockSettings.Show(pane) end
            -- T119: General, Review and About re-read what they show, and
            -- the last of them is where /st options opens (Clock was never
            -- one of the options frame's tabs)
            if group == "settings" and ST.Settings and ST.Settings.Owns(view) then
                lastSettingsView = view
                ST.Settings.Refresh(view)
            end
            -- the source is set when the VIEW changes, never on a refresh: the
            -- 2s ticker calls Refresh, and setting it there put the run back
            -- one second after the author clicked Fights (v0.11.6)
            if group == "reports" and reviewView and view ~= currentFamily then
                reviewView:SetSource(view == "Runs" and "run" or "fights")
            end
            currentGroup, currentFamily = group, view
            ST.Win:SetGroup("main", group) -- T80: the group's own size, the TOPLEFT kept
            ST:Fire("UI_VIEW_SELECTED", group, view)
            -- T120: the pane draws the view (and clears a row's new dot)
            if group == "spells" then ST.SpellsPane:Show(view) end
            Refresh()

        end)
    frame = nav.frame
    local content = nav:Content()
    -- T84 (C5): the rail's [ + Add ] and Undo line (UI/SpellRail.lua);
    -- T120: the shared pane's
    ST.SpellsPane:Attach(nav)

    -- T83 (C3): "Effective" (now "After overheal") moved into the Spells
    -- view (T120: the shared pane's strip). The lines below are Reports'
    -- furniture.
    statsFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -46)
    statsFS:SetJustifyH("LEFT")
    statsFS:SetWidth(CONTENT_W - 8)

    calloutFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calloutFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -64)
    calloutFS:SetJustifyH("LEFT")
    calloutFS:SetWidth(CONTENT_W - 8)

    hintFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -82)
    hintFS:SetJustifyH("LEFT")
    hintFS:SetWidth(CONTENT_W - 8)

    recapFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recapFS:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2)
    recapFS:SetJustifyH("LEFT")
    recapFS:SetWidth(CONTENT_W - 8)

    frame:SetScript("OnShow", function()
        -- T84 (C5): Overview the first time (the rail's first row), then the
        -- remembered row; a path saved before C5 names a bare family
        local path = ST.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[1] == "spells" and SpellsViewId(path[2]) or path[2])
        else
            nav:Select("spells", nil)
        end
        Refresh()
    end)

    -- T80 (C1): the window manager's host (registered after the OnShow script
    -- above, since Register hooks OnShow): its strata, place and scale, the
    -- sizes per group, one ESC stack entry (no UISpecialFrames line), the
    -- combat hide; how to open it on a view and read the one it shows; the
    -- practice view a session goes back to. adoptPlaced: the place the client
    -- kept for it while it was user-placed (before C1) becomes its saved one.
    ST.Win:Register(frame, { key = "main", role = "host", sizes = SIZES, group = "spells",
        open = function(group, view) return ST:OpenMainWindow(group, view) end,
        selected = function() return ST:SelectedView() end,
        practicePath = { "simulate", "practice" }, adoptPlaced = true })

    -- The Casts column follows your current mana: re-render every 2s while
    -- the frame is open (rendering only; the model is event-driven).
    local acc = 0
    ST:OnTick(function(dt)
        if not frame:IsShown() then return end
        acc = acc + dt
        if acc >= 2 then
            acc = 0
            Refresh()
        end
    end)
end

function ST:SelectedView()
    if not nav then return nil end
    return nav:Selected()
end

-- What ST.Win:ShowMain opens (T80, the host's `open`): the window on the view
-- asked for, or on the remembered one when none is named.
function ST:OpenMainWindow(group, view)
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    if group then nav:Select(group, group == "spells" and SpellsViewId(view) or view) end
end

-- Every entry point that wants a particular view goes through here: /st sim,
-- /st options, the minimap button's right-click. T80 (C1): through the window
-- manager, which closes a replay first and refuses while practice plays.
function ST:SelectView(group, view)
    if not nav then return end
    return ST.Win:ShowMain(group, view)
end

function ST:ToggleDashboard()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else ST.Win:ShowMain() end
end

-- Kept for the minimap button's right-click.
function ST:OpenDashboardSettings()
    ST:SelectView("settings", "general")
end

-- T119: the door /st options (Core_TBC.lua) uses, kept when the options frame
-- (UI/OptionsFrame.lua) went --
--   ST:ShowOptionsFrame()      the settings group, on the last view used
--   ST:ShowOptionsFrame(view)  that view
function ST:ShowOptionsFrame(view)
    ST:SelectView("settings", view or lastSettingsView or "general")
end

-- a run stored while the window is open makes the Runs view appear
local function RefreshReportViews()
    if nav then nav:SetViews("reports", ReportViews()) end
end
ST:RegisterCallback("RUN_STORED", RefreshReportViews)

ST:RegisterCallback("MD_READY", CreateDashboard)
ST:RegisterCallback("TALENTS_CHANGED", Refresh)
-- T84 (C5): a rank trained -- Spells/Book_Model.lua (T118) rebuilt the book
-- and reconciled the list first (it registered earlier); the rail follows,
-- and talents and forms move its suggested-rank tags (T120: the pane's rail)
ST:RegisterCallback("SPELLS_REBUILT", RefreshSpellRail)
ST:RegisterCallback("TALENTS_CHANGED", RefreshSpellRail)
ST:RegisterCallback("FORM_CHANGED", RefreshSpellRail)
ST:RegisterCallback("SPELLS_REBUILT", Refresh)
ST:RegisterCallback("FIGHT_RECORDED", Refresh)
ST:RegisterCallback("FORM_CHANGED", Refresh) -- Tree of Life: costs and aura change
ST:On("PLAYER_EQUIPMENT_CHANGED", function()
    if frame and frame:IsShown() then
        RefreshSpellRail() -- T84: gear moves the suggested-rank tags
        Refresh()
    end
end)
