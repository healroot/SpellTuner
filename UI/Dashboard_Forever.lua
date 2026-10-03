-- Forever's window (T2 of docs/ROADMAP-FOREVER.md): the Cell-style navigation
-- frame from UI/Style.lua (shared) with four groups -- Spells (since T36 a
-- rail group, UI/SpellsPane.lua since T120), Reports, Simulate and Settings
-- (-> General; -> Modules switches the three LoadOnDemand siblings on or off;
-- -> About lists every command, T70). Built on first use, not at load: TBC's
-- own UI/Dashboard.lua stays TBC-only and reads none of this.
--
-- Client calls only through MD.API; nothing here calls one directly (the
-- widget toolkit and WoW's Lua extensions are not client calls -- CLAUDE.md,
-- T1b Facts).
local _, MD = ...
local UI = MD.UI

-- T32 (docs/SPEC-forever-ui.md 6.7): the window's size is one per group, kept
-- by the window manager (UI/Windows.lua). T80 (C1, review A22): this table is
-- the dashboard's own and is handed to MD.Win at Register. Reports and
-- Simulate at 1036 x 646 for the Review and Practice panes' 912-wide content;
-- T40: Simulate goes down to 900 x 560 now that Practice wraps its fight
-- fields onto a second row and sizes its table to the pane. T75 (P31, review
-- U14, mockup M1): Spells and Settings do not reflow (the rank table and card
-- are a fixed 540, Settings' two columns fit 860 x 560), so their minimum is
-- their size -- fixed groups, no resize grip. WIDTH / HEIGHT are only the size
-- the frame is built at, before MD.Win places it.
local SIZES = {
    spells   = { w = 860,  h = 560, minW = 860,  minH = 560 },
    settings = { w = 860,  h = 560, minW = 860,  minH = 560 },
    reports  = { w = 1036, h = 646, minW = 1036, minH = 600 },
    simulate = { w = 1036, h = 646, minW = 900,  minH = 560 },
}
local WIDTH, HEIGHT = 860, 560

local nav, frame

local function Groups()
    return {
        -- T36 (docs/SPEC-forever-ui.md 3.1): a rail group; its rows are the
        -- player's own spell list (UI/SpellsPane.lua)
        MD.SpellsPane:Group(),
        { id = "reports", text = "Reports", views = {
            { id = "review", text = "Review" } } },
        -- T18: a placeholder until the Practice module is on (Files/Rules),
        -- same shape as Reports -> Review's own placeholder-then-module.
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" } } },
        -- T119 (docs/SPEC-one-ui.md 7): UI/Settings.lua's views in its order
        -- -- General, Clock (T102), Review, this line's Modules, About (T70)
        { id = "settings", text = "Settings", views = MD.Settings and MD.Settings.Views() or {
            { id = "general", text = "General" }, { id = "clock", text = "Clock" },
            { id = "modules", text = "Modules" }, { id = "about", text = "About" } } },
    }
end

--------------------------------------------------------------------------------
-- Settings -> General, Review and About: this line's rows
--------------------------------------------------------------------------------
-- T119 (docs/SPEC-one-ui.md 7, mockup M6): the three views are UI/Settings.lua's
-- on both lines. What was this file's (T42, T70, T79, T102: the two columns,
-- SPELL TOOLTIPS, APPEARANCE, WINDOWS, MANA CLOCK, REVIEW, TOOLS, INTEGRATIONS,
-- the About page) moved there; what stays is what only Forever has, as data:
--   clock         MANA CLOCK: show, lock (unticking previews the clock 60 s),
--                 Reset position, Show now, Customise..., the two hints
--   tools         TOOLS: the debug console, a copy of /st dump
--   integrations  INTEGRATIONS' extra switch: EllesmereUI's /unlock mover
--   recording     Review / RECORDING: the five settings the replay and the
--                 coach read (T70, U24) and the danger line for built fights,
--                 live only while the Replay module is loaded (it registers
--                 their keys); recordingNote says so on the title row
--   model         Review / MODEL: Measure (T70's TOOLS button, moved), its hint
--   modelHint     what "~" means on this line
--   views         Settings -> Modules, between Review and About
-- The words, keys and tooltips are T70's, unchanged.
local REPLAY = "SpellTuner_Replay"

local function ReplayLoaded()
    return MD:ModuleState(REPLAY) == "loaded"
end

local function MeasureLabel()
    return (MD.Measure and MD.Measure.on) and "Measure: on" or "Measure: off"
end

-- T102 (docs/SPEC-next.md 7.4): Settings -> Clock's Text (since T116) and When tabs hold
-- this line's own switches (db.clock: the rest segment, shown, locked,
-- click-through), the keys MANA CLOCK and /st clock write.
local function ClockDB()
    MD.db.clock = MD.db.clock or {}
    return MD.db.clock
end
local function RefreshClock()
    if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
end
local CLOCK_SWITCHES = {
    show = {
        { text = "Rest time (rest 2:10)", segment = "rest", tips = { "Rest time", "Time to full if you stop casting right now,",
              "beside the clock. Same as /st clock rest." },
          get = function() return ClockDB().showRest ~= false end,
          set = function(on) ClockDB().showRest = on; RefreshClock() end },
    },
    when = {
        { text = "Show the mana clock", tips = { "Show the mana clock", "Same as /st clock." },
          get = function() return ClockDB().shown ~= false end,
          set = function(on) ClockDB().shown = on; RefreshClock() end },
        { text = "Locked", tips = { "Lock in place", "Unticked: it stays up for 60 s, even at full mana,",
              "so you can drag it. Same as /st clock lock." },
          get = function() return ClockDB().locked == true end,
          set = function(on)
              if MD.Clock and MD.Clock.SetLocked then MD.Clock:SetLocked(on) else ClockDB().locked = on end
          end },
        { text = "Click-through", tips = { "Click-through", "The clock takes no mouse input (no hover, no click)",
              "except while you place it. Same as /st clock clickthrough." },
          get = function() return ClockDB().clickThrough == true end,
          set = function(on) ClockDB().clickThrough = on; RefreshClock() end },
    },
}

local function ClientLine()
    -- This file is on the Forever TOCs only, so the client is named here, not
    -- read (apicheck: the client's name is a flavour's policy, not a branch).
    local version, build = MD.API.BuildInfo()
    local parts = { "WoW: Forever" }
    if type(build) == "string" and build ~= "" then
        parts[#parts + 1] = "build " .. build
    elseif type(version) == "string" and version ~= "" then
        parts[#parts + 1] = version
    end
    return table.concat(parts, ", ")
end

-- T70 (U24): the settings the replay and the coach read that Forever had no
-- control for. The keys are the Replay module's (Engine/SimModel.lua
-- registers their defaults), so the controls are live only while it is loaded.
local REVIEW_CHECKS = {
    { kind = "check", key = "replayAutoCoach", text = "Coach a fight when it opens",
      live = ReplayLoaded, collect = "reviewChecks",
      tips = { "Coach a fight when it opens", "Opening a replay with no plan validates and coaches it.",
               "Off: open it, then Coach from Review." } },
    { kind = "check", key = "replayNextPull", text = "Next pull follows",
      live = ReplayLoaded, collect = "reviewChecks",
      tips = { "Next pull follows", "In a run, a pull played to its end opens the next one.",
               "Off: the replay stops at each pull's end." } },
    { kind = "check", key = "replayTicks", text = "Snapshot ticks on the bars",
      live = ReplayLoaded, collect = "reviewChecks",
      tips = { "Snapshot ticks on the bars", "The recorder's real health every 5 s, drawn over the",
               "engine's reconstruction on the left bars." } },
    { kind = "check", key = "simAllowRebinds", text = "Let Coach change ranks",
      live = ReplayLoaded, collect = "reviewChecks",
      tips = { "Let Coach change ranks", "Off: the card suggests thresholds for the ranks you already cast.",
               "On: it may also suggest binding a different rank." } },
    { kind = "slider", key = "simFullHp", text = "Full health is above (%)", min = 70, max = 99, step = 1,
      scale = 100, percent = true, live = ReplayLoaded, mark = "fullHpSlider",
      tips = { "Full health is above",
               "A cast on a target at or above this counts as healing nobody.",
               "0.85 came from the first dungeon log, not from a rulebook." } },
    -- T119: the slider TBC's Settings had (T73's words); drawn always, live
    -- with the Replay module like the rest
    { kind = "slider", key = "simFloor", text = "Danger line for built fights (%)", min = 10, max = 60,
      step = 1, scale = 100, percent = true, live = ReplayLoaded, mark = "floorSlider",
      tips = { "Fights built in Simulate score seconds a target spends below",
               "this first, ahead of mana. A recorded fight measures its own line:",
               "the biggest hit each target took." } },
}

MD.SettingsLine = {
    client = ClientLine,
    -- T119: Settings -> Modules, between Review and About
    views = { { id = "modules", text = "Modules" } },

    -- T70 (U18): the Forever clock could not be placed at full mana (shown
    -- only in combat or under 90 %), and lock was only /st clock lock. TBC's
    -- "Lock widget" and "Reset position", plus Show now (M1's choice: the
    -- same preview); T102: Customise... opens Settings -> Clock.
    clock = {
        { kind = "check", text = "Show the mana clock", mark = "clockCheck", -- tools/clockcheck.lua
          get = function() return ClockDB().shown ~= false end,
          set = function(on) ClockDB().shown = on and true or false; RefreshClock() end },
        { kind = "check", text = "Lock in place", mark = "clockLockCheck",
          get = function() return ClockDB().locked == true end,
          set = function(on)
              if MD.Clock and MD.Clock.SetLocked then MD.Clock:SetLocked(on) else ClockDB().locked = on end
          end,
          tips = { "Lock in place", "Locked: the clock cannot be dragged.",
                   "Unticked: it stays up for 60 s, even at full mana, so you can drag it.",
                   "Same as /st clock lock." } },
        { kind = "hint", indent = 19,
          text = "Unlocked: the clock stays up for 60 s, even at full mana, so you can drag it." },
        { kind = "buttons",
          { text = "Reset position", width = 112, mark = "clockReset",
            tips = { "Reset position", "The clock back at the top of the screen." },
            onClick = function()
                if MD.Clock and MD.Clock.ResetPosition then MD.Clock:ResetPosition() end
                MD:Print("mana clock: position reset")
            end },
          { text = "Show now", width = 86, mark = "clockShowNow",
            enabled = function() return ClockDB().shown ~= false end,
            tips = { "Show now", "The clock up for 60 s at any mana level, to see or move it." },
            onClick = function()
                if MD.Clock and MD.Clock.Preview then MD.Clock:Preview() end
            end },
          { text = "Customise...", width = 92, mark = "clockCustomise",
            tips = { "Customise the clock", "Settings -> Clock: the layout, the colours, the bar, with a preview." },
            onClick = function() MD:SelectView("settings", "clock") end } },
        { kind = "hint", text = "Left-click the clock to open this window." },
    },

    -- T70 (U24): what was slash-only -- the console and the dump
    tools = {
        { kind = "buttons",
          { text = "Debug console", width = 104, mark = "consoleButton",
            tips = { "Debug console", "The debug log, filterable, with a copy box (/st debug)." },
            onClick = function() if MD.ToggleDebugConsole then MD:ToggleDebugConsole() end end },
          { text = "Copy /st dump", width = 108, mark = "dumpButton",
            tips = { "Copy /st dump", "One copyable block for a bug report: the client, the saved",
                     "variables, the modules, the errors and the debug log." },
            onClick = function()
                if MD.BuildDump and MD.ShowCopyPopup then MD:ShowCopyPopup("SpellTuner dump", MD:BuildDump()) end
            end } },
    },

    -- T102 (docs/SPEC-next.md 6.3, mockup M9d): with EllesmereUI loaded, its
    -- /unlock mover (db.eui.unlock, Integrations/EllesmereUI_Forever.lua's;
    -- switched off it leaves after a reload)
    integrations = {
        {
            text = "Clock mover in EllesmereUI's /unlock",
            tips = { "Clock mover", "The SpellTuner clock as a mover in EllesmereUI's /unlock.",
                     "Off: after a reload it is not offered." },
            shown = function() return MD.EUI ~= nil and MD.Surfaces ~= nil and MD.Surfaces.eui ~= nil end,
            get = function() return not (type(MD.db.eui) == "table" and MD.db.eui.unlock == false) end,
            set = function(on)
                MD.db.eui = MD.db.eui or {}
                MD.db.eui.unlock = on
                if on and MD.EUI and MD.EUI.RegisterMover then MD.EUI.RegisterMover() end
            end,
        },
    },

    recording = REVIEW_CHECKS,
    recordingNote = function()
        return ReplayLoaded() and "needs the Replay module" or "needs the Replay module - off"
    end,

    model = {
        { kind = "buttons",
          { text = "Measure: off", label = MeasureLabel, width = 98, mark = "measureButton",
            tips = { "Measure", "Each own cast matched to what landed and judged against its own",
                     "text, one line in chat per cast (/st measure; /st measure dump for the list)." },
            onClick = function() if MD.Measure and MD.Measure.Toggle then MD.Measure:Toggle() end end } },
        { kind = "hint", text = "Measure checks each cast that lands against its own text." },
    },
    modelHint = "~ marks a number the model computed, not one the game showed.",
}

--------------------------------------------------------------------------------
-- Settings -> Modules
--------------------------------------------------------------------------------
local function ModuleLabel(name)
    for _, m in ipairs(MD.modules or {}) do
        if m.name == name then return m.label end
    end
    return name
end

-- One line, MD:ModuleStateText (Core.lua, T55) -- ASCII only, the reason
-- already sanitised by the registry (a bad LoadAddOn reason becomes "unknown"
-- there). T73 (P29) dropped this file's own copy of it.
local function StateText(name) return MD:ModuleStateText(name) end

local modulesPane

-- T73 (P29, review U11, mockup M1): a module switched off but still loaded
-- this session ("unloads") keeps running until a reload; its row carries a
-- Reload UI button. ReloadUI through the adapter, as every client call.
local function ReloadInterface()
    MD.API.Call("ReloadUI")
end

local function RefreshModulesPane()
    if not modulesPane or not modulesPane.rows then return end
    for _, m in ipairs(MD.modules or {}) do
        local row = modulesPane.rows[m.name]
        if row then
            row.check:SetChecked(MD.db.modules and MD.db.modules[m.name] == true)
            row.state:SetText(StateText(m.name))
            if MD:ModuleState(m.name) == "unloads" then row.reload:Show() else row.reload:Hide() end
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
        state:SetPoint("RIGHT", row, "RIGHT", -90, 0)
        state:SetJustifyH("LEFT")

        -- T73: shown only while the module unloads at the next reload
        local reload = UI.CreateButton(row, "Reload UI", "accent-hover", { 84, 18 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL, "Reload UI", "Reloads the interface now, which unloads "
            .. m.label .. ".")
        reload:SetPoint("LEFT", state, "RIGHT", 6, 0)
        reload:SetScript("OnClick", ReloadInterface)
        reload:Hide()

        pane.rows[m.name] = { check = check, state = state, reload = reload }
        prevRow = row
    end

    return pane
end

--------------------------------------------------------------------------------
-- Spells: T36 moved the whole group into UI/SpellsPane_Forever.lua (the rail,
-- the list, the picker, Overview, a family's view). T39: the old Spellbook
-- view is gone -- Overview's Whole book is today's table under the new look,
-- My spells one row per listed family, and Export moved there (3.6). This
-- file only wires it: the group's definition, onCreate, onShow, and the
-- rail's footer once the nav exists.
--
-- T120 (docs/tasks/T120-one-spells-pane.md): the pane is UI/SpellsPane.lua on
-- both lines; what differs by line is MD.SpellsLine, Forever's here -- the
-- footer, the card's Crit note, nothing else (no After overheal, no RANKS
-- note, no Overview note; What if is T122's).
--------------------------------------------------------------------------------
MD.SpellsLine = {
    footer = "Values come from the spell's own text. ~ = modelled.",
    critNote = "x1.5, unverified",
}

--------------------------------------------------------------------------------
-- Reports -> Review (T16b) and Simulate -> Practice (T18): the shared panes
-- (UI/Dashboard_Review.lua, UI/PracticePanel.lua) once their module is
-- loaded; until then a placeholder. T73 (P29, review U11 / A24, mockup M1,
-- the author's answer 6): one MODULE_VIEWS table describes both, the
-- placeholder carries a Turn on button that switches the module on (and what
-- it needs) and loads it at once, and the real pane takes the placeholder's
-- place through nav:ReplacePane -- no reaching into the kit's nav.panes.
-- Settings -> Modules stays the way to switch one off.
--------------------------------------------------------------------------------
local reviewPane        -- the api object MD.DashboardParts.CreateReview hands back
local practicePane      -- the api object MD.DashboardParts.CreatePractice hands back

local function BuildReviewPane(content)
    reviewPane = MD.DashboardParts.CreateReview(content, 912)
    reviewPane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    reviewPane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return reviewPane.frame
end

local function RefreshReviewPane()
    if reviewPane then reviewPane:Render() end
end

local function BuildPracticePane(content)
    practicePane = MD.DashboardParts.CreatePractice(content, 912)
    practicePane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    practicePane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return practicePane.frame
end

-- One row per view a module brings: the module, the DashboardParts
-- constructor its last file defines, the real pane's builder, and the
-- placeholder's words (M1). `mark` names the flag the suites find the
-- placeholder by (tools/reviewforever.lua, tools/practiceforever.lua).
local MODULE_VIEWS = {
    { group = "reports", view = "review", module = "SpellTuner_Replay", part = "CreateReview",
      build = BuildReviewPane, mark = "reviewPlaceholder",
      title = "REVIEW", heading = "Review needs the Replay module",
      text = "Replay plays a recorded fight back as unit frames and coaches it. "
          .. "It needs Recorder, which turns on with it." },
    { group = "simulate", view = "practice", module = "SpellTuner_Practice", part = "CreatePractice",
      build = BuildPracticePane, mark = "practicePlaceholder",
      title = "PRACTICE", heading = "Practice needs the Practice module",
      text = "Practice plays a fight you heal in real time, then reviews it like a real pull. "
          .. "It needs Replay and Recorder, which turn on with it." },
}
local placeholders = {} -- MODULE_VIEWS row -> its placeholder frame, while it is the view's pane

local function ModuleViewFor(group, view)
    for _, def in ipairs(MODULE_VIEWS) do
        if def.group == group and def.view == view then return def end
    end
end

-- The footnote under Turn on: what it will do, or why the last try failed.
local function PlaceholderNote(def)
    local state, reason = MD:ModuleState(def.module)
    if state == "failed" then
        return "could not load: " .. tostring(reason) .. ". Settings -> Modules shows each module.", "bad"
    end
    return "Loads now, no reload. To turn it off again: Settings -> Modules.", "muted"
end

local function RefreshPlaceholder(def)
    local pane = placeholders[def]
    if not pane then return end
    local text, token = PlaceholderNote(def)
    pane.note:SetText(text)
    pane.note:SetTextColor(UI.RGB(token))
end

local function BuildPlaceholder(def, content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    -- the block, centred in the pane (M1: a little above the middle)
    local block = CreateFrame("Frame", nil, pane)
    block:SetSize(470, 130)
    block:SetPoint("CENTER", pane, "CENTER", 0, 20)

    local title = block:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    title:SetPoint("TOP", block, "TOP", 0, 0)
    title:SetTextColor(UI.RGB("accent"))
    title:SetText(def.title)

    local heading = block:CreateFontString(nil, "OVERLAY", UI.FONT_HEAD or UI.FONT_TITLE)
    heading:SetPoint("TOP", title, "BOTTOM", 0, -6)
    heading:SetText(def.heading)
    pane.heading = heading

    local text = block:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    text:SetPoint("TOP", heading, "BOTTOM", 0, -6)
    text:SetWidth(470)
    text:SetJustifyH("CENTER")
    text:SetTextColor(UI.RGB("text2"))
    text:SetText(def.text)

    local button = UI.CreateButton(block, "Turn on", "accent", { 110, 22 }, false, false, nil, nil,
        "Turn on", "Switches the module on, with what it needs, and loads it now.")
    button:SetPoint("TOP", text, "BOTTOM", 0, -14)
    button:SetScript("OnClick", function()
        -- the swap itself is MODULE_LOADED's (below): the module's last file
        -- fires it from inside this call once every file ran
        MD:SetModule(def.module, true)
        RefreshPlaceholder(def)
    end)
    pane.turnOn = button

    local note = block:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    note:SetPoint("TOP", button, "BOTTOM", 0, -10)
    note:SetWidth(470)
    note:SetJustifyH("CENTER")
    pane.note = note

    pane[def.mark] = true
    pane.moduleView = def
    placeholders[def] = pane
    RefreshPlaceholder(def)
    return pane
end

-- The view's pane: the real one when its module is loaded, else the
-- placeholder.
local function BuildModuleView(def, content)
    if MD.DashboardParts[def.part] then return def.build(content) end
    return BuildPlaceholder(def, content)
end

-- A module finished loading (its own Ready.lua) and brought a constructor:
-- each placeholder whose pane can now be built is replaced. Loading Practice
-- loads Replay first, so Review's placeholder is replaced on the way.
local function SwapPlaceholders()
    if not nav then return end
    for _, def in ipairs(MODULE_VIEWS) do
        if placeholders[def] and MD.DashboardParts[def.part] then
            local pane = def.build(nav:Content())
            placeholders[def] = nil
            nav:ReplacePane(def.group, def.view, pane)
        end
    end
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
            elseif ModuleViewFor(group, view) then
                return BuildModuleView(ModuleViewFor(group, view), content) -- T73: Review, Practice
            elseif group == "settings" and MD.Settings and MD.Settings.Owns(view) then
                -- T119: General, Review and About (UI/Settings.lua, this
                -- line's rows in MD.SettingsLine above)
                return MD.Settings.Build(view, content)
            elseif group == "settings" and view == "clock" then
                -- T102: Settings -> Clock (UI/ClockSettings.lua)
                if MD.ClockSettings and MD.ClockSettings.Build then
                    return MD.ClockSettings.Build(content, CLOCK_SWITCHES)
                end
                return nil
            elseif group == "settings" and view == "modules" then
                modulesPane = BuildModulesPane(content)
                return modulesPane
            end
            return nil
        end,
        function(group, view, pane)
            -- T32: the group's own size, the TOPLEFT kept (6.7)
            MD.Win:SetGroup("main", group)
            if group == "settings" and MD.Settings and MD.Settings.Owns(view) then MD.Settings.Refresh(view) end
            if group == "settings" and view == "clock" and MD.ClockSettings then MD.ClockSettings.Show(pane) end
            if group == "settings" and view == "modules" then RefreshModulesPane() end
            if group == "reports" and view == "review" then RefreshReviewPane() end
            local def = ModuleViewFor(group, view)
            if def then RefreshPlaceholder(def) end -- T73: a failed load's reason, if any
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
    -- T80 (C1, review A22): the dashboard hands the manager what it knows --
    -- its sizes, its first group, how to open it on a view, how to read the
    -- view it shows, and the practice view a session goes back to.
    MD.Win:Register(frame, { key = "main", role = "host", sizes = SIZES, group = "spells",
        open = function(group, view) return MD:OpenMainWindow(group, view) end,
        selected = function() return MD:SelectedView() end,
        practicePath = { "simulate", "practice" } })
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
    else
        MD.Win:ShowMain() -- T32: on the remembered view
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
    CreateDashboard() -- T80: the host registers with MD.Win when it is built
    return MD.Win:ShowMain(group, view)
end

-- T79 (P36): the minimap button's right-click (UI/MinimapButton.lua), as on
-- TBC (UI/Dashboard.lua): the window on Settings -> General.
function MD:OpenDashboardSettings()
    return MD:SelectView("settings", "general")
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
-- T70: Settings -> Review goes live with the Replay module, and About lists
-- the commands a module registered as it loaded -- since T119 UI/Settings.lua
-- refreshes its own panes on MODULE_LOADED.

-- T16b / T18: a module finishing load (its own last file, Ready.lua) brings
-- its DashboardParts constructor; T73 (P29, review A24): every placeholder
-- that can now be built is replaced through nav:ReplacePane, which re-selects
-- the view if it is the one on screen (shown and refreshed) and keeps the new
-- pane hidden otherwise. (T32: the window no longer grows here -- Reports has
-- its own size, 6.7.)
MD:RegisterCallback("MODULE_LOADED", SwapPlaceholders)
