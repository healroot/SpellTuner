-- Minimap button: standard round button parented to Minimap under a global
-- name, which is the pattern minimap-button collectors (MinimapButtonButton,
-- MBB, ElvUI's minimap-icon bar) detect and adopt. Left-click: dashboard.
-- Right-click: settings tab. Drag: move around the minimap edge.
--
-- T79 (P36 of docs/PLAN-refactor-ux.md, section 8.1 item 10, mockups M1 and
-- M6): one file for both lines. It calls only the widget toolkit (CreateFrame,
-- Minimap, GetCursorPosition) and MD:ToggleDashboard / MD:OpenDashboardSettings,
-- which both lines define (UI/Dashboard.lua, UI/Dashboard_Forever.lua). What
-- differs per line comes through two named seams, never a client test:
--   * the tooltip's clock lines: MD.MinimapLines(hints), provided once per
--     line with MD:Provide("MinimapLines", fn) -- TBC's is Tip:Clock
--     (UI/Tip_TBC.lua), Forever's MD.Clock:SummaryLines (UI/Clock_Forever.lua);
--     fn answers the title and the clock lines, plus the hints when given any;
--   * the tooltip's shape: UI.THEMED. Unthemed (TBC today) the old call, byte
--     for byte; themed, M6's kit tooltip -- the provider's lines, a spacer, the
--     three hint pairs and the muted line saying where to hide it.
local _, MD = ...

-- The default, declared once, here (P20's rule: the file that reads a setting
-- owns its default). Core_TBC.lua's DEFAULTS carried it until T79.
MD:RegisterDefaults({ minimap = { hide = false, angle = 220 } })

local btn

local function Reposition()
    if not btn then return end
    local angle = math.rad(MD.db.minimap.angle or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    MD.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Reposition()
end

-- The provider's lines, or a bare title where no line provides any.
local function ClockLines(hints)
    if MD.MinimapLines then return MD.MinimapLines(hints) end
    local lines = { { l = "SpellTuner", c = "accent" } }
    if hints then
        lines[#lines + 1] = {}
        for _, h in ipairs(hints) do lines[#lines + 1] = { l = h, c = "muted" } end
    end
    return lines
end

-- M6: the hint pairs' values are white (the mockup's `w`); the labels and the
-- hide line read the `label` and `muted` tokens, the provider `accent` and
-- `mana` -- never `text2`, which P34 merges into `label`.
local WHITE = { 1, 1, 1 }
local function Pair(l, r) return { l = l, r = r, c = "label", rc = WHITE } end

-- Themed: M6's kit tooltip. Built fresh at each hover (the clock moves).
local function ThemedLines()
    local lines = ClockLines(nil)
    lines[#lines + 1] = {}
    lines[#lines + 1] = Pair("Left-click", "open the window")
    lines[#lines + 1] = Pair("Right-click", "Settings")
    lines[#lines + 1] = Pair("Drag", "move it round the map")
    lines[#lines + 1] = { l = "Hide it: Settings -> General -> Windows.", c = "muted", wrap = true }
    return lines
end

local function CreateButton()
    btn = CreateFrame("Button", "SpellTunerMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_Manaburn")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -5)

    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            MD:OpenDashboardSettings()
        else
            MD:ToggleDashboard()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    -- Not gated by db.widgetTooltip: that setting is the floating clock's, and
    -- the clock is a thing you park somewhere and stop looking at. A minimap
    -- button is a thing you go to on purpose, so its tooltip always shows.
    btn:SetScript("OnEnter", function(self)
        if MD.UI and MD.UI.THEMED then
            MD.Tip:Show(self, ThemedLines(), { anchor = "ANCHOR_LEFT" })
        else
            MD.Tip:Show(self, "ANCHOR_LEFT",
                ClockLines({ "Left-click: dashboard", "Right-click: settings" }))
        end
    end)
    btn:SetScript("OnLeave", function() MD.Tip:Hide() end)

    Reposition()
    MD:UpdateMinimapButton()
end

function MD:UpdateMinimapButton()
    if not btn then return end
    if MD.db.minimap.hide then btn:Hide() else btn:Show() end
    Reposition()
end

MD:RegisterCallback("MD_READY", CreateButton)
