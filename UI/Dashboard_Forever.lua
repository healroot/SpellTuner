-- Forever's window (T2 of docs/ROADMAP-FOREVER.md): the Cell-style navigation
-- frame from UI/Style.lua (shared) with four groups -- Spells (since T36 a
-- rail group, UI/SpellsPane_Forever.lua), Reports, Simulate and Settings
-- (-> General; -> Modules switches the three LoadOnDemand siblings on or off;
-- -> About lists every command, T70). Built on first use, not at load: TBC's
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
            { id = "modules", text = "Modules" },
            -- T70 (P26, U24): the version and every command
            { id = "about", text = "About" } } },
    }
end

--------------------------------------------------------------------------------
-- Settings -> General
--------------------------------------------------------------------------------
-- T42 (docs/SPEC-forever-ui.md section 9's T42 row, 4.2, 4.3, 6.5, 6.6) built
-- three titled panes; T70 (P26 of docs/PLAN-refactor-ux.md, review U18, U24,
-- U15, mockup M1) puts them in two columns and adds three, Cell's spacing
-- (title at 0, the rule at -17, the first control at -27, 12 between panes):
--   left   SPELL TOOLTIPS  the block on or off, and T37's detail key (5.6)
--          APPEARANCE      "Text size" (the font offset, -2..+2, UI.ApplyFonts:
--                          every font object re-sized and the Spells pane
--                          re-rendered, 4.2) and "Window size" (70-120 %,
--                          MD.Win:SetScale, 4.3), a sentence under each
--          WINDOWS         combat hide / keep (6.6), one window per ESC (6.5,
--                          db.ui.escStack), Reset window positions (/st ui reset)
--   right  MANA CLOCK      show, lock (unticking previews the clock for 60 s,
--                          as TBC does), Reset position, Show now
--          REVIEW          the five settings Forever read with no control:
--                          replayAutoCoach, replayNextPull, replayTicks,
--                          simAllowRebinds, simFullHp -- live only while the
--                          Replay module is loaded (it registers them)
--          TOOLS           the debug console, a copy of /st dump, measure
-- Each control writes its db field and applies it at once. The text size
-- follows the slider as it moves; the window size waits for the mouse-up
-- (Cell's rule: the window must not scale under the pointer mid-drag).
local generalPane

local PANE_GAP = 12
local LEFT_W = 352   -- the left column (M1)
local RIGHT_X = 376  -- where the right column starts

local REPLAY = "SpellTuner_Replay"

local function Round(v) return math.floor((tonumber(v) or 0) + 0.5) end

local function ReplayLoaded()
    return MD:ModuleState(REPLAY) == "loaded"
end

local function SetEnabled(w, on)
    if not w then return end
    if on then w:Enable() else w:Disable() end
end

local function MeasureLabel()
    return (MD.Measure and MD.Measure.on) and "Measure: on" or "Measure: off"
end

local function RefreshGeneralPane()
    if not generalPane or not generalPane.tooltipCheck then return end
    local p = generalPane
    p.tooltipCheck:SetChecked(MD.db.spellTooltip ~= false)
    local clock = type(MD.db.clock) == "table" and MD.db.clock or {}
    if p.clockCheck then p.clockCheck:SetChecked(clock.shown ~= false) end
    if p.clockLockCheck then p.clockLockCheck:SetChecked(clock.locked == true) end
    SetEnabled(p.clockShowNow, clock.shown ~= false)
    if p.detailDropdown and MD.SpellTip and MD.SpellTip.DetailMode then
        p.detailDropdown:SetValue(MD.SpellTip:DetailMode())
    end
    local u = type(MD.db.ui) == "table" and MD.db.ui or {}
    if p.fontSlider then p.fontSlider:SetValue(Round(UI.fontOffset or u.fontOffset)) end
    if p.scaleSlider and MD.Win then p.scaleSlider:SetValue(MD.Win:ScalePercent()) end
    if p.combatDropdown and MD.Win then p.combatDropdown:SetValue(MD.Win:CombatMode()) end
    if p.escCheck and MD.Win then p.escCheck:SetChecked(MD.Win:EscStackOn()) end

    -- REVIEW: the Replay module registers these keys (MD:RegisterDefaults), so
    -- a value is shown and written only while it is loaded; off, the pane says so
    local live = ReplayLoaded()
    if p.reviewChecks then
        for _, c in ipairs(p.reviewChecks) do
            local v = live and MD:Setting(c.key)
            c.check:SetChecked(v == true)
            SetEnabled(c.check, live)
        end
    end
    if p.fullHpSlider then
        local v = live and tonumber(MD:Setting("simFullHp"))
        if v then p.fullHpSlider:SetValue(Round(v * 100)) end
        SetEnabled(p.fullHpSlider, live)
    end
    if p.reviewNote then
        p.reviewNote:SetText(live and "needs the Replay module" or "needs the Replay module - off")
    end
    if p.measureButton then p.measureButton:SetText(MeasureLabel()) end
end

-- A titled pane in a column ("left" / "right"), under `above` (nil: the
-- column's top).
local function Section(pane, text, height, above, column)
    local t = UI.CreateTitledPane(pane, text, LEFT_W, height)
    if above then
        t:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -PANE_GAP)
    elseif column == "right" then
        t:SetPoint("TOPLEFT", pane, "TOPLEFT", RIGHT_X, -4)
    else
        t:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    end
    if column == "right" then t:SetPoint("RIGHT", pane, "RIGHT", -4, 0) end
    return t
end

-- A grey sentence under a control, `width` wide (nil: to the section's right).
local function Hint(sec, text, anchorTo, x, y, width)
    local fs = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", x or 0, y or -2)
    if width then fs:SetWidth(width) else fs:SetPoint("RIGHT", sec, "RIGHT", 0, 0) end
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(UI.RGB("muted"))
    fs:SetText(text)
    return fs
end

local function BuildTooltipSection(pane)
    local sec = Section(pane, "SPELL TOOLTIPS", 64, nil, "left")

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

-- T70 (U15): the two knobs named by what they change, a sentence under each.
-- The window size does not reach the kit's tooltips yet (U15's second half is
-- UI/Style.lua's, not this task's), so the sentence does not claim them.
local TEXT_SIZE_HINT = "Every SpellTuner text, one size bigger or smaller."
local WINDOW_SIZE_HINT = "Every SpellTuner window, bigger or smaller."

local function BuildAppearanceSection(pane, above)
    local sec = Section(pane, "APPEARANCE", 104, above, "left")

    -- 4.2: -2..+2 (decision 13), every SpellTuner font; the Spells pane's
    -- pitches follow (UI.ApplyFonts is wrapped by UI/SpellsPane_Forever.lua)
    if UI.ApplyFonts then
        local lo, hi = UI.FONT_OFFSET_MIN or -2, UI.FONT_OFFSET_MAX or 2
        local slider = UI.CreateSlider("Text size", sec, lo, hi, 150, 1, function(value)
            local u = MD.db.ui
            if type(u) ~= "table" then u = {}; MD.db.ui = u end
            u.fontOffset = UI.ApplyFonts(value)
        end, nil, false,
            "Text size", "Every SpellTuner text a size bigger or smaller, -2 to +2.",
            "Spells' rows and cards move apart with it.")
        slider:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -45)
        pane.fontSlider = slider
        pane.fontHint = Hint(sec, TEXT_SIZE_HINT, slider, 0, -20, 150)
    end

    -- 4.3: 70-120 %, through the window manager (the saved places converted)
    if MD.Win then
        local lo, hi = Round(MD.Win.SCALE_MIN * 100), Round(MD.Win.SCALE_MAX * 100)
        local slider = UI.CreateSlider("Window size", sec, lo, hi, 150, 5, nil, function(value)
            MD.Win:SetScale((tonumber(value) or 100) / 100)
        end, true,
            "Window size", "Makes the main, replay and practice windows bigger or smaller,",
            "along with the console and the copy box.")
        slider:SetPoint("TOPLEFT", sec, "TOPLEFT", 190, -45)
        pane.scaleSlider = slider
        pane.scaleHint = Hint(sec, WINDOW_SIZE_HINT, slider, 0, -20, 150)
    end
    return sec
end

local function BuildWindowsSection(pane, above)
    if not MD.Win then return nil end
    local sec = Section(pane, "WINDOWS", 100, above, "left")

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

-- T70 (U18): the Forever clock could not be placed at full mana (shown only
-- in combat or under 90 %), and lock was only /st clock lock. TBC's "Lock
-- widget" and "Reset position", plus Show now (M1's choice: the same preview).
local function BuildClockSection(pane)
    local sec = Section(pane, "MANA CLOCK", 132, nil, "right")

    local show = UI.CreateCheckButton(sec, "Show the mana clock", function(checked)
        MD.db.clock = MD.db.clock or {}
        MD.db.clock.shown = checked and true or false
        SetEnabled(pane.clockShowNow, checked)
        if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
    end)
    show:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -27)
    show:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    pane.clockCheck = show -- marks this pane for tools/clockcheck.lua

    local lock = UI.CreateCheckButton(sec, "Lock in place", function(checked)
        if MD.Clock and MD.Clock.SetLocked then
            MD.Clock:SetLocked(checked)
        else
            MD.db.clock = MD.db.clock or {}
            MD.db.clock.locked = checked and true or false
        end
    end, "Lock in place", "Locked: the clock cannot be dragged.",
        "Unticked: it stays up for 60 s, even at full mana, so you can drag it.",
        "Same as /st clock lock.")
    lock:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 0, -6)
    lock:SetChecked(MD.db.clock and MD.db.clock.locked == true)
    pane.clockLockCheck = lock
    local lockHint = Hint(sec, "Unlocked: the clock stays up for 60 s, even at full mana, so you can drag it.",
        lock, 19, -3)

    local reset = UI.CreateButton(sec, "Reset position", "accent-hover", { 112, 20 }, false, false,
        nil, nil, "Reset position", "The clock back at the top of the screen.")
    reset:SetPoint("TOPLEFT", lockHint, "BOTTOMLEFT", 0, -5)
    reset:SetScript("OnClick", function()
        if MD.Clock and MD.Clock.ResetPosition then MD.Clock:ResetPosition() end
        MD:Print("mana clock: position reset")
    end)
    pane.clockReset = reset

    local now = UI.CreateButton(sec, "Show now", "accent-hover", { 86, 20 }, false, false,
        nil, nil, "Show now", "The clock up for 60 s at any mana level, to see or move it.")
    now:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    now:SetScript("OnClick", function()
        if MD.Clock and MD.Clock.Preview then MD.Clock:Preview() end
    end)
    pane.clockShowNow = now

    Hint(sec, "Left-click the clock to open this window.", reset, 0, -6)
    return sec
end

-- T70 (U24): the five settings the replay and the coach read that Forever had
-- no control for. The keys are the Replay module's (Engine/SimModel.lua
-- registers their defaults), so the controls are live only while it is loaded.
local REVIEW_CHECKS = {
    { key = "replayAutoCoach", text = "Coach a fight when it opens",
      tips = { "Coach a fight when it opens", "Opening a replay with no plan validates and coaches it.",
               "Off: open it, then Coach from Review." } },
    { key = "replayNextPull", text = "Next pull follows",
      tips = { "Next pull follows", "In a run, a pull played to its end opens the next one.",
               "Off: the replay stops at each pull's end." } },
    { key = "replayTicks", text = "Snapshot ticks on the bars",
      tips = { "Snapshot ticks on the bars", "The recorder's real health every 5 s, drawn over the",
               "engine's reconstruction on the left bars." } },
    { key = "simAllowRebinds", text = "Let Coach change ranks",
      tips = { "Let Coach change ranks", "Off: the card suggests thresholds for the ranks you already cast.",
               "On: it may also suggest binding a different rank." } },
}

local function BuildReviewSection(pane, above)
    local sec = Section(pane, "REVIEW", 156, above, "right")

    local note = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    note:SetPoint("BOTTOMRIGHT", sec.line, "TOPRIGHT", 0, 3)
    note:SetJustifyH("RIGHT")
    note:SetTextColor(UI.RGB("muted"))
    note:SetText("needs the Replay module")
    pane.reviewNote = note

    pane.reviewChecks = {}
    local prev
    for _, def in ipairs(REVIEW_CHECKS) do
        local key = def.key
        local check = UI.CreateCheckButton(sec, def.text, function(checked)
            MD.db[key] = checked and true or false
        end, def.tips[1], def.tips[2], def.tips[3])
        if prev then
            check:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
        else
            check:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -27)
        end
        pane.reviewChecks[#pane.reviewChecks + 1] = { key = key, check = check }
        prev = check
    end

    local slider = UI.CreateSlider("Full health is above", sec, 70, 99, 160, 1, function(value)
        MD.db.simFullHp = (tonumber(value) or 85) / 100
    end, nil, true, "Full health is above",
        "A cast on a target at or above this counts as healing nobody.",
        "0.85 came from the first dungeon log, not from a rulebook.")
    slider:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 15, -28)
    pane.fullHpSlider = slider
    return sec
end

-- T70 (U24): what was slash-only -- the console, the dump, measuring.
local function BuildToolsSection(pane, above)
    local sec = Section(pane, "TOOLS", 72, above, "right")

    local console = UI.CreateButton(sec, "Debug console", "accent-hover", { 104, 20 }, false, false,
        nil, nil, "Debug console", "The debug log, filterable, with a copy box (/st debug).")
    console:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -27)
    console:SetScript("OnClick", function()
        if MD.ToggleDebugConsole then MD:ToggleDebugConsole() end
    end)
    pane.consoleButton = console

    local dump = UI.CreateButton(sec, "Copy /st dump", "accent-hover", { 108, 20 }, false, false,
        nil, nil, "Copy /st dump", "One copyable block for a bug report: the client, the saved",
        "variables, the modules, the errors and the debug log.")
    dump:SetPoint("LEFT", console, "RIGHT", 6, 0)
    dump:SetScript("OnClick", function()
        if MD.BuildDump and MD.ShowCopyPopup then MD:ShowCopyPopup("SpellTuner dump", MD:BuildDump()) end
    end)
    pane.dumpButton = dump

    local measure = UI.CreateButton(sec, MeasureLabel(), "accent-hover", { 98, 20 }, false, false,
        nil, nil, "Measure", "Each own cast matched to what landed and judged against its own",
        "text, one line in chat per cast (/st measure; /st measure dump for the list).")
    measure:SetPoint("LEFT", dump, "RIGHT", 6, 0)
    measure:SetScript("OnClick", function(self)
        if MD.Measure and MD.Measure.Toggle then MD.Measure:Toggle() end
        self:SetText(MeasureLabel())
    end)
    pane.measureButton = measure

    Hint(sec, "Measure checks each cast that lands against its own text.", console, 0, -6)
    return sec
end

local function BuildGeneralPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local tips = BuildTooltipSection(pane)
    local look = BuildAppearanceSection(pane, tips)
    BuildWindowsSection(pane, look)

    local clock = BuildClockSection(pane)
    local review = BuildReviewSection(pane, clock)
    BuildToolsSection(pane, review)
    return pane
end

--------------------------------------------------------------------------------
-- Settings -> About (T70, P26, review U24, mockup M1): the version, the client
-- and every command MD:Commands() lists, usage in the numbers font, the text
-- cut at its first "; " (the whole text on hover). Rebuilt on every show, so a
-- module that loaded since adds its commands. A module that is not loaded
-- gets one line: its commands are registered only when it loads.
--------------------------------------------------------------------------------
local aboutPane
local ABOUT_ROW_H = 17
local USAGE_W = 196

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

-- The command's text up to its first "; " -- the rest is the hover's.
local function ShortText(text)
    local cut = text:find("; ", 1, true)
    if cut then return text:sub(1, cut - 1), true end
    return text, false
end

local function AboutRow(pane, i)
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pane.list)
    r:SetHeight(ABOUT_ROW_H)
    r:SetPoint("TOPLEFT", pane.list, "TOPLEFT", 5, -27 - (i - 1) * ABOUT_ROW_H)
    r:SetPoint("RIGHT", pane.list, "RIGHT", 0, 0)
    r:EnableMouse(true)
    r.usage = r:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    r.usage:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.usage:SetWidth(USAGE_W - 6)
    r.usage:SetJustifyH("LEFT")
    r.usage:SetWordWrap(false)
    r.text = r:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    r.text:SetPoint("LEFT", r, "LEFT", USAGE_W, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    pane.rows[i] = r
    return r
end

local function RefreshAboutPane()
    local p = aboutPane
    if not p then return end
    p.version:SetText("SpellTuner " .. tostring(MD.version))
    p.client:SetText(ClientLine())

    local n = 0
    for _, e in ipairs(MD:Commands()) do
        if not e.hidden and type(e.usage) == "string" and e.usage ~= "" then
            n = n + 1
            local r = AboutRow(p, n)
            local short, cut = ShortText(e.text or "")
            r.usage:SetText(e.usage)
            r.text:SetText(short)
            r.text:SetTextColor(UI.RGB("text2"))
            r.command = e.name
            if cut then UI.SetTooltips(r, "ANCHOR_TOPLEFT", 0, 3, e.usage, e.text) else r.tooltips = nil end
            r:Show()
        end
    end
    for _, m in ipairs(MD.modules or {}) do
        if MD:ModuleState(m.name) ~= "loaded" then
            n = n + 1
            local r = AboutRow(p, n)
            r.usage:SetText(m.label)
            r.text:SetText("off: its commands are listed here once it is on (Settings -> Modules)")
            r.text:SetTextColor(UI.RGB("muted"))
            r.command, r.tooltips = nil, nil
            r:Show()
        end
    end
    for i = n + 1, #p.rows do p.rows[i]:Hide() end
    p.shown = n
    p.list:SetHeight(27 + n * ABOUT_ROW_H + 4)
end

local function BuildAboutPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.rows = {}
    pane.about = true -- marks this pane for tools/wincheck.lua

    local version = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    version:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    pane.version = version

    local client = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    client:SetPoint("LEFT", version, "RIGHT", 10, 0)
    client:SetTextColor(UI.RGB("muted"))
    pane.client = client

    local blurb = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    blurb:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -4)
    blurb:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    blurb:SetJustifyH("LEFT")
    blurb:SetTextColor(UI.RGB("text2"))
    blurb:SetText("Your spells rank by rank, your mana clock, and your fights recorded, replayed and coached.")

    local list = UI.CreateTitledPane(pane, "COMMANDS", LEFT_W, 60)
    list:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)
    list:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    local both = list:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    both:SetPoint("BOTTOMRIGHT", list.line, "TOPRIGHT", 0, 3)
    both:SetTextColor(UI.RGB("muted"))
    both:SetText("/st and /md both answer")
    pane.list = list

    aboutPane = pane
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
--------------------------------------------------------------------------------

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
            elseif group == "settings" and view == "general" then
                generalPane = BuildGeneralPane(content)
                return generalPane
            elseif group == "settings" and view == "modules" then
                modulesPane = BuildModulesPane(content)
                return modulesPane
            elseif group == "settings" and view == "about" then
                return BuildAboutPane(content)
            end
            return nil
        end,
        function(group, view, pane)
            -- T32: the group's own size, the TOPLEFT kept (6.7)
            if MD.Win then MD.Win:SetGroup("main", group) end
            if group == "settings" and view == "general" then RefreshGeneralPane() end
            if group == "settings" and view == "modules" then RefreshModulesPane() end
            if group == "settings" and view == "about" then RefreshAboutPane() end
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
-- T70: the REVIEW pane goes live with the Replay module, and About lists the
-- commands a module registered as it loaded.
MD:RegisterCallback("MODULE_LOADED", RefreshGeneralPane)
MD:RegisterCallback("MODULE_LOADED", RefreshAboutPane)

-- T16b / T18: a module finishing load (its own last file, Ready.lua) brings
-- its DashboardParts constructor; T73 (P29, review A24): every placeholder
-- that can now be built is replaced through nav:ReplacePane, which re-selects
-- the view if it is the one on screen (shown and refreshed) and keeps the new
-- pane hidden otherwise. (T32: the window no longer grows here -- Reports has
-- its own size, 6.7.)
MD:RegisterCallback("MODULE_LOADED", SwapPlaceholders)
