-- Forever's window (T2 of docs/ROADMAP-FOREVER.md): the Cell-style navigation
-- frame from UI/Style.lua (shared) with two groups -- Spells (a placeholder;
-- the spell tables arrive in M2) and Settings -> Modules (switch the three
-- LoadOnDemand siblings on or off). Built on first use, not at load: TBC's
-- own UI/Dashboard.lua stays TBC-only and reads none of this.
--
-- Client calls only through MD.API; nothing here calls one directly (the
-- widget toolkit and WoW's Lua extensions are not client calls -- CLAUDE.md,
-- T1b Facts).
local _, MD = ...
local UI = MD.UI

local WIDTH, HEIGHT = 700, 460

local nav, frame

local function Groups()
    return {
        { id = "spells", text = "Spells", views = {
            { id = "book", text = "Spellbook" } } },
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" },
            { id = "modules", text = "Modules" } } },
    }
end

--------------------------------------------------------------------------------
-- Settings -> General
--------------------------------------------------------------------------------
local generalPane

local function RefreshGeneralPane()
    if not generalPane or not generalPane.tooltipCheck then return end
    generalPane.tooltipCheck:SetChecked(MD.db.spellTooltip ~= false)
    if generalPane.clockCheck then
        generalPane.clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    end
end

local function BuildGeneralPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    title:SetText("General")

    local check = UI.CreateCheckButton(pane, "Add SpellTuner lines to spell tooltips", function(checked)
        MD.db.spellTooltip = checked and true or false
    end)
    check:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -30)
    check:SetChecked(MD.db.spellTooltip ~= false)

    pane.tooltipCheck = check -- marks this pane for tools/tipcheck.lua

    local clockCheck = UI.CreateCheckButton(pane, "Show the mana clock", function(checked)
        MD.db.clock = MD.db.clock or {}
        MD.db.clock.shown = checked and true or false
        if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
    end)
    clockCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -20)
    clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    pane.clockCheck = clockCheck -- marks this pane for tools/clockcheck.lua

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
-- Spells (placeholder -- M2)
--------------------------------------------------------------------------------
local function BuildSpellbookPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.spellsBook = true -- marks this pane for tools/modulecheck.lua

    local fs = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    fs:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    fs:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText("Your spells arrive in the next build: every rank, its value, cost and value per mana.")

    return pane
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function CreateDashboard()
    if nav then return end -- MD_READY-equivalent callers may ask more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIDTH, HEIGHT, Groups(),
        function(group, view, content)
            if group == "spells" and view == "book" then
                return BuildSpellbookPane(content)
            elseif group == "settings" and view == "general" then
                generalPane = BuildGeneralPane(content)
                return generalPane
            elseif group == "settings" and view == "modules" then
                modulesPane = BuildModulesPane(content)
                return modulesPane
            end
            return nil
        end,
        function(group, view)
            if group == "settings" and view == "general" then RefreshGeneralPane() end
            if group == "settings" and view == "modules" then RefreshModulesPane() end
        end)
    frame = nav.frame
    tinsert(UISpecialFrames, "SpellTunerDashboard") -- ESC closes

    frame:SetScript("OnShow", function()
        local path = MD.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[2])
        else
            nav:Select("spells", "book")
        end
    end)
end

function MD:ShowDashboard()
    CreateDashboard()
    if frame then frame:Show() end
end

function MD:ToggleDashboard()
    CreateDashboard()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Every entry point that wants a particular view goes through here (/st
-- modules today; the same door M2/M3/M4 use). Opens the window if closed.
function MD:SelectView(group, view)
    CreateDashboard()
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    nav:Select(group, view)
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
