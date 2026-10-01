-- Rank dashboard (/md): a Cell-style movable frame (header bar with title and
-- close), the groups and their views. The Spells group's one pane is the TBC
-- Spells view (T83, C3 of docs/PLAN-refactor-ux.md: UI/SpellsView_TBC.lua --
-- the header, the chip and one comparison, the rank table T81 built, the
-- card, "After overheal" and the Simulate strip behind "What if..."), with
-- the four families along the top until C5's rail. Reports keeps its header
-- lines and the recap. Settings are in the options frame
-- (UI/OptionsFrame.lua).
--
-- T80 (C1 of docs/PLAN-refactor-ux.md, decision 10, the author's answer 1):
-- the window is the window manager's (UI/Windows.lua) as on Forever -- placed
-- by it, a size per group handed in at Register (SIZES below), on the ESC
-- stack instead of UISpecialFrames, hidden in combat and reopened on the same
-- view, and every MD:SelectView through MD.Win:ShowMain. A place the client
-- kept for it while it was user-placed is adopted once.
local _, MD = ...
local UI = MD.UI

local WIDTH, HEIGHT = 912, 617 -- +20% (author, 2026-09-06: not everything fit); was 760 x 514
local frame, statsFS, calloutFS, hintFS, recapFS, messageFS
local spellsView, wasteView, reviewView, practiceView, nav
local currentGroup = "spells"
local currentFamily = "HealingTouch"
local userPicked = false   -- once a tab is clicked, stop picking one automatically

-- The family this character actually casts most (persisted counts kept by the
-- spend tracker), so the dashboard opens on the spell that matters. The first
-- dungeon log had one Healing Touch in 29 minutes and 245 Lifeblooms; it opened
-- on Healing Touch.
local function DefaultFamily()
    local counts = MD.cdb and MD.cdb.familyCasts
    local best, bestN = "HealingTouch", -1
    if counts then
        for _, family in ipairs(MD.SpellData.familyOrder) do
            local info = MD.SpellData.families[family]
            if info and not info.exclude and (counts[family] or 0) > bestN then
                best, bestN = family, counts[family] or 0
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- refresh
--------------------------------------------------------------------------------
local function Shown(f, on) if not f then return end if on then f:Show() else f:Hide() end end

-- The regen line Reports keeps above Waste and Review (the Spells view says
-- the same in its +healing hover since T83).
local function StatsLine()
    local RM = MD.Regen
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
    local spells, reports = currentGroup == "spells", currentGroup == "reports"
    Shown(statsFS, reports)
    Shown(calloutFS, reports)
    Shown(hintFS, reports)
    Shown(recapFS, reports)
    messageFS:Hide()

    if spells then
        -- T83 (C3): the TBC Spells view -- header, chip and comparison, the
        -- rank table, the card -- in place of the four prose lines.
        if not MD.player.isDruid then
            messageFS:Show()
            messageFS:SetText("Rank analysis is Druid-only in v1 - the OOM widget, datatext and advisor still work for your class.")
            return
        end
        if spellsView then spellsView:Render(currentFamily) end
        return
    end
    if not reports then return end

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
    local last = MD.fightHistory and MD.fightHistory[#MD.fightHistory]
    if last then
        recapFS:SetText("Last fight: " .. (last.summary or "-") ..
            (#MD.fightHistory > 1 and ("  |cff666666(" .. #MD.fightHistory .. " fights this session)|r") or ""))
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
-- two reports can share one variable: a family id ("Rejuvenation") and a report
-- id ("Waste") are both just the view that is showing.
--------------------------------------------------------------------------------
local CONTENT_W = 912          -- what the panes were laid out for; the window is wider by the nav
local NAV_W, NAV_PAD = 108, 8
local WIN_W, WIN_H = CONTENT_W + NAV_W + 2 * NAV_PAD, 646

-- T80 (C1, review A22): TBC's sizes per group, handed to the window manager
-- at Register. Every pane here is laid out for the 912-wide content, so each
-- group is today's 1036 x 646 and fixed (its minimum is its size: no grip).
-- T83 (C3) keeps Spells at that size: the view scrolls inside it (mockup M6
-- drew 860 x 560; tools/wincheck.lua, not C3's file, holds 1036 x 646).
local SIZES = {
    spells   = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    reports  = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    simulate = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    settings = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
}

-- Reports' views depend on what has been recorded.
local function ReportViews()
    local views = { { id = "Waste", text = "Waste" }, { id = "Review", text = "Review" } }
    if MD.RunRecorder and #(MD.RunRecorder:List()) > 0 then
        views[#views + 1] = { id = "Runs", text = "Runs" }
    end
    return views
end

local function Groups()
    local spells = {}
    for _, family in ipairs(MD.SpellData.familyOrder) do
        local info = MD.SpellData.families[family]
        if info and not info.exclude then
            spells[#spells + 1] = { id = family, text = info.label or family,
                                    hidden = not MD.player.isDruid }
        end
    end
    return {
        { id = "spells", text = "Spells", views = spells },
        -- Waste and Review work for any class: a recorded stream is numbers
        -- Runs appears only once one has been recorded: a view that is always
        -- empty teaches nothing, and nav:SetViews puts it there the moment a
        -- run is stored (v0.11.4)
        { id = "reports", text = "Reports", views = ReportViews() },
        -- v0.15.0: Practice first. Building a fight for the planner to play
        -- answered a question nobody was asking; playing it yourself does
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" }, { id = "build", text = "Build a fight" } } },
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" }, { id = "about", text = "About" } } },
    }
end

local function CreateDashboard()
    if nav then return end     -- MD_READY can be fired more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIN_W, WIN_H, Groups(),
        function(group, view, content)
            -- built once, on first sight
            if group == "reports" and view == "Waste" then
                wasteView = MD.DashboardParts.CreateWaste(content, CONTENT_W)
                wasteView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                wasteView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return wasteView.frame
            elseif group == "reports" and view == "Runs" then
                -- the Review pane already knows how to list a run's pulls; the
                -- Runs view is that pane with a run selected instead of Fights
                if not reviewView then
                    reviewView = MD.DashboardParts.CreateReview(content, CONTENT_W)
                    reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                    reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                end
                return reviewView.frame
            elseif group == "reports" and view == "Review" then
                reviewView = MD.DashboardParts.CreateReview(content, CONTENT_W)
                reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return reviewView.frame
            elseif group == "simulate" and view == "practice" then
                practiceView = MD.DashboardParts.CreatePractice(content, CONTENT_W)
                practiceView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
                practiceView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
                return practiceView.frame
            elseif group == "simulate" then
                if MD.AdoptSimPanel then return MD:AdoptSimPanel(content) end
                return nil
            elseif group == "settings" then
                -- one panel for both settings views; the tabs inside it show
                -- and hide themselves on the ShowOptionsTab callback
                if MD.AdoptOptionsPanel then MD:AdoptOptionsPanel(content) end
                return MD.optionsFrame
            elseif group == "spells" and not spellsView and MD.player.isDruid
                    and MD.DashboardParts.CreateSpellsView then
                -- T83 (C3): one view for every family, UI/SpellsView_TBC.lua's
                spellsView = MD.DashboardParts.CreateSpellsView(content, CONTENT_W, Refresh)
                spellsView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
                spellsView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
                return spellsView.frame
            end
            return spellsView and spellsView.frame or nil
        end,
        function(group, view)
            -- the source is set when the VIEW changes, never on a refresh: the
            -- 2s ticker calls Refresh, and setting it there put the run back
            -- one second after the author clicked Fights (v0.11.6)
            if group == "reports" and reviewView and view ~= currentFamily then
                reviewView:SetSource(view == "Runs" and "run" or "fights")
            end
            currentGroup, currentFamily = group, view
            userPicked = true
            MD.Win:SetGroup("main", group) -- T80: the group's own size, the TOPLEFT kept
            MD:Fire("UI_VIEW_SELECTED", group, view)
            Refresh()

        end)
    frame = nav.frame
    local content = nav:Content()

    -- T83 (C3): "Effective" (now "After overheal") and the Simulate strip
    -- (behind "What if...") moved into the Spells view, UI/SpellsView_TBC.lua.
    -- The lines below are Reports' furniture.
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

    messageFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -110)
    messageFS:SetJustifyH("LEFT")
    messageFS:SetWidth(CONTENT_W - 8)
    messageFS:Hide()

    recapFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recapFS:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2)
    recapFS:SetJustifyH("LEFT")
    recapFS:SetWidth(CONTENT_W - 8)

    frame:SetScript("OnShow", function()
        local path = MD.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[2])
        else
            nav:Select("spells", DefaultFamily())
        end
        Refresh()
    end)

    -- T80 (C1): the window manager's host (registered after the OnShow script
    -- above, since Register hooks OnShow): its strata, place and scale, the
    -- sizes per group, one ESC stack entry (no UISpecialFrames line), the
    -- combat hide; how to open it on a view and read the one it shows; the
    -- practice view a session goes back to. adoptPlaced: the place the client
    -- kept for it while it was user-placed (before C1) becomes its saved one.
    MD.Win:Register(frame, { key = "main", role = "host", sizes = SIZES, group = "spells",
        open = function(group, view) return MD:OpenMainWindow(group, view) end,
        selected = function() return MD:SelectedView() end,
        practicePath = { "simulate", "practice" }, adoptPlaced = true })

    -- The Casts column follows your current mana: re-render every 2s while
    -- the frame is open (rendering only; the model is event-driven).
    local acc = 0
    MD:OnTick(function(dt)
        if not frame:IsShown() then return end
        acc = acc + dt
        if acc >= 2 then
            acc = 0
            Refresh()
        end
    end)
end

function MD:SelectedView()
    if not nav then return nil end
    return nav:Selected()
end

-- What MD.Win:ShowMain opens (T80, the host's `open`): the window on the view
-- asked for, or on the remembered one when none is named.
function MD:OpenMainWindow(group, view)
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    if group then nav:Select(group, view) end
end

-- Every entry point that wants a particular view goes through here: /md sim,
-- /md options, the minimap button's right-click. T80 (C1): through the window
-- manager, which closes a replay first and refuses while practice plays.
function MD:SelectView(group, view)
    if not nav then return end
    return MD.Win:ShowMain(group, view)
end

function MD:ToggleDashboard()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else MD.Win:ShowMain() end
end

-- Kept for the minimap button's right-click.
function MD:OpenDashboardSettings()
    MD:ShowOptionsFrame("general")
end

-- a run stored while the window is open makes the Runs view appear
local function RefreshReportViews()
    if nav then nav:SetViews("reports", ReportViews()) end
end
MD:RegisterCallback("RUN_STORED", RefreshReportViews)

MD:RegisterCallback("MD_READY", CreateDashboard)
MD:RegisterCallback("TALENTS_CHANGED", Refresh)
MD:RegisterCallback("SPELLS_REBUILT", Refresh)
MD:RegisterCallback("FIGHT_RECORDED", Refresh)
MD:RegisterCallback("FORM_CHANGED", Refresh) -- Tree of Life: costs and aura change
MD:On("PLAYER_EQUIPMENT_CHANGED", function()
    if frame and frame:IsShown() then Refresh() end
end)
