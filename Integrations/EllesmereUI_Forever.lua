-- Integrations/EllesmereUI_Forever.lua (T97, docs/SPEC-next.md 6.3 and 5.5;
-- R-ellesmere.md 2.2-2.3, 3.3, 3.5): EllesmereUI's public entry points, on the
-- Forever TOCs only (EllesmereUI refuses to run below 12.1 except on Forever,
-- so it never loads on TBC), after Integrations/Surface_LDB.lua. Inert without
-- EllesmereUI. The brokers are Surface_LDB.lua's (any LibDataBroker host).
--
-- 1. The skin facade. EllesmereUI.RegisterSkin("SpellTuner", fn), once, at
--    file load (the TOCs' "## OptionalDeps: EllesmereUI" puts the parent's
--    queueing stub there first). EllesmereUI's BlizzardSkin hands fn the facade
--    S at its own PLAYER_LOGIN, or at once for a late registration, or never
--    (third-party skinning off for SpellTuner, BlizzardSkin disabled). fn keeps
--    S as MD.EUISkin and fires EUI_SKIN_READY once, whatever the order between
--    the two addons (X4: the Ellesmere style repaints on it). The follow is
--    the Ellesmere style's (UI/Style_Ellesmere.lua, T100); this file reads no
--    getter. Only apiVersion 2 -- the documented, additive-only contract -- is
--    followed: its OnLooksChanged fires EUI_LOOKS_CHANGED; any other version
--    is not hooked and says "skin apiVersion <n>: not followed".
--    SpellTuner's frames are never handed to S.Shell / S.Panel / S.Button
--    (they fade every texture region; decision 5, X3).
-- 2. The mover. One element "SpellTuner_Clock" ("SpellTuner clock", group
--    "SpellTuner") in EllesmereUI's /unlock mode, built through
--    EllesmereUI.MakeUnlockElement with fields on its whitelist ONLY
--    (EllesmereUI.lua 2280-2381; anything else is dropped silently, X2):
--    getFrame, getSize, savePos (the clock's own stored point -- EllesmereUI
--    hands CENTER/CENTER on UIParent, the shape of db.clock.point), loadPos,
--    clearPos (the clock's reset), applyPos (the clock's ApplyPoint), isHidden
--    (the clock switched off), noResize. A listener shows the clock's preview
--    while /unlock is open (a clock hidden at full mana could otherwise only be
--    placed as an empty mover) and ends it after; it never calls Show / Hide
--    (the clock's own visibility owner does). The clock is reached through the
--    mover seam MD.ClockWidget (T93). Without RegisterUnlockElements the clock
--    keeps its own drag and the line says "mover: not offered by this
--    EllesmereUI". db.eui.unlock (default on) turns it off.
-- 3. The version guard. TESTED_EUI is the version this was built against;
--    another runs (every call is guarded: `type(...) == "function"` and
--    pcall), and the INTEGRATIONS / dump line prints "(tested 9.3.4)" beside
--    the running version so a report shows the drift.
--
-- It never reads or writes EllesmereUI._ModuleNS, EllesmereUIDataBarsDB or
-- EllesmereUIDB, never calls RegisterModule, never attaches to
-- ManaRegenSpark, registers no event on a frame of its own (MD:On), and never
-- moves a frame in combat (a point applied in combat waits for the end).
-- Host addons are reached only from Integrations/ (apicheck rule 11).
local _, MD = ...

-- docs/SPEC-next.md 6.3: the mover's switch, declared by the file that reads it.
MD:RegisterDefaults({ eui = { unlock = true } })

MD.Surfaces = MD.Surfaces or {}

local EUI = {}
MD.EUI = EUI

EUI.TESTED = "9.3.4"   -- TESTED_EUI: the EllesmereUI this was built and tested against
EUI.API_VERSION = 2    -- the skin facade contract followed (SKINNING_API.md)
EUI.MOVER_KEY = "SpellTuner_Clock"
EUI.MOVER_LABEL = "SpellTuner clock"
EUI.GROUP = "SpellTuner"
EUI.PREVIEW_SECONDS = 3600 -- the preview while /unlock is open; ended when it closes

local function Host()
    local E = EllesmereUI
    if type(E) == "table" then return E end
    return nil
end

--------------------------------------------------------------------------------
-- 1. The skin facade
--------------------------------------------------------------------------------
EUI.skinRegistered = false -- RegisterSkin was called (once)
EUI.skinApi = nil          -- the facade's apiVersion, once it arrived
local skinArrived = false

local function OnSkin(S)
    if skinArrived then return end
    skinArrived = true
    MD.EUISkin = S
    local v = type(S) == "table" and S.apiVersion or nil
    EUI.skinApi = v
    if v == EUI.API_VERSION and type(S.OnLooksChanged) == "function" then
        pcall(S.OnLooksChanged, function() MD:Fire("EUI_LOOKS_CHANGED") end)
    end
    MD:Fire("EUI_SKIN_READY", S)
end

-- Whether the facade is followed: it arrived and speaks apiVersion 2.
function EUI.SkinFollowed()
    return skinArrived and EUI.skinApi == EUI.API_VERSION
end

do
    local E = Host()
    if E and type(E.RegisterSkin) == "function" then
        EUI.skinRegistered = true
        pcall(E.RegisterSkin, "SpellTuner", OnSkin)
    end
end

--------------------------------------------------------------------------------
-- 2. The mover
--------------------------------------------------------------------------------
EUI.mover = nil     -- the element's key, once registered
EUI.moverWhy = nil  -- why there is none: "off", "not offered by this EllesmereUI", "no clock"
local pendingApply = false
local ourPreview = false

local function Clock() return MD.ClockWidget end

local function ClockDB()
    MD.db.clock = MD.db.clock or {}
    return MD.db.clock
end

-- The clock at its stored place; in combat, after the fight.
local function Apply()
    local W = Clock()
    if not (W and W.ApplyPoint) then return end
    if MD.inCombat then pendingApply = true; return end
    pendingApply = false
    W:ApplyPoint()
end

-- The element's options, every one on MakeUnlockElement's whitelist.
local function Element()
    return {
        key = EUI.MOVER_KEY, label = EUI.MOVER_LABEL, group = EUI.GROUP, order = 900,
        getFrame = function() local W = Clock(); return W and W.frame end,
        getSize = function()
            local W = Clock()
            local f = W and W.frame
            if f then return f:GetWidth(), f:GetHeight() end
            return 0, 0
        end,
        savePos = function(_, point, relPoint, x, y)
            ClockDB().point = { point, nil, relPoint or point, x or 0, y or 0 }
            Apply()
        end,
        loadPos = function()
            local p = MD.db.clock and MD.db.clock.point
            if type(p) == "table" and p[1] then
                return { point = p[1], relPoint = p[3] or p[1], x = p[4] or 0, y = p[5] or 0 }
            end
            return nil
        end,
        clearPos = function()
            local W = Clock()
            if W and W.ResetPosition then W:ResetPosition() end
        end,
        applyPos = function() Apply() end,
        isHidden = function() return not (MD.db.clock and MD.db.clock.shown) end,
        noResize = true,
    }
end
EUI.Element = Element

-- /unlock opened: the clock previewed (its own 60-s path, longer); closed:
-- the preview this listener started is ended. Show / Hide stay the clock's.
local function OnUnlockMode(active)
    local W = Clock()
    if not (W and W.Preview) then return end
    if active then
        ourPreview = true
        W:Preview(EUI.PREVIEW_SECONDS)
    elseif ourPreview then
        ourPreview = false
        W:Preview(0)
    end
end
EUI.OnUnlockMode = OnUnlockMode

function EUI.RegisterMover()
    local E = Host()
    if not E then return false end
    if EUI.mover then return true end
    if not (MD.db.eui and MD.db.eui.unlock ~= false) then EUI.moverWhy = "off"; return false end
    if type(E.RegisterUnlockElements) ~= "function" or type(E.MakeUnlockElement) ~= "function" then
        EUI.moverWhy = "not offered by this EllesmereUI"
        return false
    end
    local W = Clock()
    if not (W and W.frame) then EUI.moverWhy = "no clock"; return false end
    local okM, elem = pcall(E.MakeUnlockElement, Element())
    if not okM or type(elem) ~= "table" then EUI.moverWhy = "not offered by this EllesmereUI"; return false end
    local okR = pcall(E.RegisterUnlockElements, E, { elem }, EUI.GROUP)
    if not okR then EUI.moverWhy = "not offered by this EllesmereUI"; return false end
    EUI.mover, EUI.moverWhy = EUI.MOVER_KEY, nil
    if type(E.RegisterUnlockModeListener) == "function" then
        pcall(E.RegisterUnlockModeListener, E, EUI.GROUP, OnUnlockMode)
    end
    return true
end

MD:On("PLAYER_REGEN_ENABLED", function()
    if pendingApply then Apply() end
end)

--------------------------------------------------------------------------------
-- 3. What is said about it (Surface_LDB.lua's MD.Integrations joins it)
--------------------------------------------------------------------------------
-- The running EllesmereUI's version from its TOC, or "?".
function EUI.Version()
    if type(MD.API.AddOnMetadata) ~= "function" then return "?" end
    local v = MD.API.AddOnMetadata("EllesmereUI", "Version")
    if type(v) == "string" and v ~= "" then return v end
    return "?"
end

local function Head()
    return string.format("EllesmereUI %s (tested %s)", EUI.Version(), EUI.TESTED)
end

function EUI.SkinText()
    if not skinArrived then return "skin: not handed over" end
    local v = EUI.skinApi
    if v == EUI.API_VERSION then return "skin apiVersion " .. tostring(v) end
    return "skin apiVersion " .. tostring(v) .. ": not followed"
end

function EUI.MoverText(forDump)
    if EUI.mover then return "mover " .. (forDump and EUI.mover or EUI.MOVER_LABEL) end
    return "mover: " .. (EUI.moverWhy or "not registered")
end

-- The INTEGRATIONS pane's line.
function EUI.PanePart(brokers)
    return Head() .. ": " .. brokers .. "; " .. EUI.MoverText(false)
end

-- The dump line's parts, in order.
function EUI.DumpParts(brokers)
    return { Head(), EUI.SkinText(), brokers, EUI.MoverText(true) }
end

MD:RegisterCallback("MD_READY", function()
    if not Host() then return end
    MD.Surfaces.eui = { tested = EUI.TESTED }
    EUI.RegisterMover()
    if MD.Integrations and MD.Integrations.Note then MD.Integrations.Note() end
end)
