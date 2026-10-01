-- ElvUI datatexts, themed with the user's ElvUI value colour: the ElvUI
-- SURFACE of the feeds (T92, docs/SPEC-next.md 2.3, S3 step 1). Until T92
-- this was Integrations/ElvUIDatatext.lua and built its own strings; now the
-- text of each datatext is a feed's (UI/Feeds.lua), so the datatext, the
-- floating clock, the minimap tooltip and (T97) the brokers can never say
-- different things. On TBC every string is byte for byte what it was
-- (tools/surfacecheck.lua's golden, captured before the move).
--
-- Loads only when ElvUI is present (the .toc lists ElvUI in OptionalDeps so
-- it always loads first when installed); with no ElvUI, or one without its
-- DataTexts module, it registers nothing. Two datatexts:
--   "SpellTuner"       -- the `clock` feed: the OOM readout, the widget's line
--   "SpellTuner Regen" -- the `regen` feed: CURRENT mana regen (casting regen
--                         inside the five-second rule, full regen outside);
--                         ElvUI's stock regen datatext only ever shows the
--                         out-of-casting value
-- Both share the tooltip and click behaviour. Host addons are reached only
-- from Integrations/ (docs/SPEC-next.md 2, apicheck rule 11).
local _, MD = ...

if not ElvUI then return end

local E = unpack(ElvUI)
if type(E) ~= "table" or type(E.GetModule) ~= "function" then return end
-- silent: an ElvUI without the module answers nil rather than raising
local DT = E:GetModule("DataTexts", true)
if not DT then return end

local Feeds = MD.Feeds
if not Feeds then return end

local hex = nil -- "|cffxxxxxx" from ApplySettings, nil until themed

-- ElvUI fires the first OnUpdate with elapsed = 20000; clamp it, then throttle.
local function Throttled(panel, elapsed)
    if elapsed > 100 then elapsed = 0.25 end
    panel.mdElapsed = (panel.mdElapsed or 0) + elapsed
    if panel.mdElapsed < 0.25 then return false end
    panel.mdElapsed = 0
    return true
end

-- Shift-click resets TBC's spend window (Engine/SpendTracker.lua); a line
-- without one toggles the window like a plain click.
local function OnClick()
    local shift = MD.API.IsShiftKeyDown and MD.API.IsShiftKeyDown()
    if shift and MD.Spend then
        MD.Spend:Reset()
        MD:Print("spend window reset.")
    elseif MD.ToggleDashboard then
        MD:ToggleDashboard()
    end
end

-- All lines come from the shared builders (UI/Tip.lua's line model). On TBC
-- the datatext keeps the lines it always had -- the raw mana lines and the
-- last fight (UI/Tip_TBC.lua's Tip:Mana / Tip:Fights) -- byte for byte; a
-- line without those builders shows the clock feed's tooltip (the minimap
-- button's lines). Not gated by db.widgetTooltip either (see
-- UI/MinimapButton.lua): hovering a datatext is deliberate.
local function OnEnter()
    DT.tooltip:ClearLines()
    if MD.Tip.Mana then
        DT.tooltip:AddLine("SpellTuner")
        MD.Tip:Render(DT.tooltip, MD.Tip:Mana())
        MD.Tip:Render(DT.tooltip, MD.Tip:Fights(1))
    else
        MD.Tip:Render(DT.tooltip, Feeds.Tooltip("clock"))
    end
    DT.tooltip:AddLine(" ")
    if MD.Spend then
        DT.tooltip:AddLine("Click: dashboard   Shift-click: reset window", 0.5, 0.5, 0.5)
    else
        DT.tooltip:AddLine("Click: open the window", 0.5, 0.5, 0.5)
    end
    DT.tooltip:Show()
end

local function ApplySettings(_, valueHex)
    hex = valueHex and ("|cff" .. valueHex:gsub("|cff", "")) or nil
end

--------------------------------------------------------------------------------
-- OOM datatext: the clock feed ("SpellTuner" before the clock has a state)
--------------------------------------------------------------------------------
local function OOMUpdate(panel, elapsed)
    if not Throttled(panel, elapsed) then return end
    panel.text:SetText(Feeds.Text("clock", { valueHex = hex }))
end

DT:RegisterDatatext("SpellTuner", nil, nil, nil, OOMUpdate, OnClick, OnEnter, nil, "SpellTuner", nil, ApplySettings)

--------------------------------------------------------------------------------
-- Current-regen datatext: the regen feed, "Regen: 123" (mp5), "(5SR)" while
-- casting regen is the one in effect.
--------------------------------------------------------------------------------
local function RegenUpdate(panel, elapsed)
    if not Throttled(panel, elapsed) then return end
    panel.text:SetText(Feeds.Text("regen", { valueHex = hex }))
end

DT:RegisterDatatext("SpellTuner Regen", nil, nil, nil, RegenUpdate, OnClick, OnEnter, nil, "SpellTuner Regen", nil, ApplySettings)

-- What this surface registered, for the INTEGRATIONS line and /st dump (T97).
MD.Surfaces = MD.Surfaces or {}
MD.Surfaces.elvui = { datatexts = { "SpellTuner", "SpellTuner Regen" } }
