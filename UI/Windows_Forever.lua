-- T32 (docs/SPEC-forever-ui.md 4.3 "Window scale", 6.1, 6.2, 6.7): the window
-- manager, MD.Win. Listed by the Forever TOCs only, after UI/Theme_Forever.lua;
-- the TBC TOC does not list it, so a shared file that calls it does so behind
-- `if MD.Win then ... end` and TBC keeps its own windows as they are.
--
-- The core, this task: a window registers with a key and a role; the role gives
-- its strata, level and toplevel (6.2). A window is anchored by its TOPLEFT to
-- UIParent's BOTTOMLEFT at its saved place (db.ui.win[key].x / .y, in the
-- frame's own units), or centred until it is dragged; SetUserPlaced(false), so
-- the client's layout cache never fights the manager; clamped onto the screen
-- whenever it is placed. The main window keeps a size per group (6.7), with
-- that group's minimum on the resize grip. db.ui.scale (70-120 %) is applied
-- with SetScale, and a change converts every saved position (x * old / new) so
-- the window stays where it was on screen. UI.RestylePixels runs on
-- UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED and a scale change, so 1-px edges stay
-- one pixel without a reload. The ESC stack and combat (6.5, 6.6) are T33's;
-- the replay and practice takeover (6.3) T34's.
--
-- No client data is read here: the widget toolkit (frame geometry, strata,
-- scale) is not a client call (CLAUDE.md), and the two events go through the
-- kernel's MD:On.
local _, MD = ...
local UI = MD.UI

local Win = { windows = {} }
MD.Win = Win

-- 6.2: strata / level / toplevel per role. Sheets and popups are not windows
-- the manager places (6.4); T33 / T34 use the other rows.
Win.ROLES = {
    host     = { strata = "HIGH",       level = 10, toplevel = true },
    takeover = { strata = "DIALOG",     level = 10, toplevel = true },
    tool     = { strata = "FULLSCREEN", level = 10, toplevel = true },
}

-- 6.7: the main window's size per group, default and minimum.
Win.SIZES = {
    spells   = { w = 860,  h = 560, minW = 860,  minH = 480 },
    settings = { w = 860,  h = 560, minW = 860,  minH = 480 },
    reports  = { w = 1036, h = 646, minW = 1036, minH = 600 },
    simulate = { w = 1036, h = 646, minW = 1036, minH = 600 },
}
Win.DEFAULT_GROUP = "spells"

Win.SCALE_MIN, Win.SCALE_MAX = 0.7, 1.2
local HEADER = 20 -- the kit's header hangs above the frame (UI.CreateMovableFrame)

--------------------------------------------------------------------------------
-- Saved state: db.ui.win[key] = { x, y, sizes = { [group] = { w, h } } }
--------------------------------------------------------------------------------
local function UIdb()
    local db = MD.db
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then db.ui = {} end
    if type(db.ui.win) ~= "table" then db.ui.win = {} end
    return db.ui
end

local function Saved(key, create)
    local u = UIdb()
    if not u then return nil end
    local s = u.win[key]
    if type(s) ~= "table" then
        if not create then return nil end
        s = {}
        u.win[key] = s
    end
    return s
end

function Win:Scale()
    local u = UIdb()
    local s = u and tonumber(u.scale) or 1
    if s < Win.SCALE_MIN then s = Win.SCALE_MIN end
    if s > Win.SCALE_MAX then s = Win.SCALE_MAX end
    return s
end

--------------------------------------------------------------------------------
-- Geometry: the screen in a frame's own units, and the clamp
--------------------------------------------------------------------------------
local function ScreenIn(frame)
    local us = UIParent:GetEffectiveScale()
    local es = frame:GetEffectiveScale()
    if type(us) ~= "number" or type(es) ~= "number" or es <= 0 then
        return UIParent:GetWidth(), UIParent:GetHeight()
    end
    return UIParent:GetWidth() * us / es, UIParent:GetHeight() * us / es
end

-- A TOPLEFT (x, y from BOTTOMLEFT) pulled onto the screen: the frame's left and
-- right inside it (the left wins when it is wider than the screen, so the nav
-- stays reachable), its header's top and the frame's bottom inside it (the
-- header wins).
local function Clamp(frame, x, y)
    local sw, sh = ScreenIn(frame)
    local w, h = frame:GetWidth(), frame:GetHeight()
    if x + w > sw then x = sw - w end
    if x < 0 then x = 0 end
    if y - h < 0 then y = h end
    if y + HEADER > sh then y = sh - HEADER end
    return x, y
end

local function Anchor(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

-- The size a window takes now: its group's saved size, else the group's
-- default, never under the minimum; a window without groups keeps its own.
local function SizeFor(w)
    local def = w.sizes and w.sizes[w.group or Win.DEFAULT_GROUP]
    if not def then return nil end
    local sw, sh = def.w, def.h
    local s = Saved(w.key)
    local mine = s and type(s.sizes) == "table" and s.sizes[w.group or Win.DEFAULT_GROUP]
    if type(mine) == "table" and type(mine[1]) == "number" and type(mine[2]) == "number" then
        sw, sh = mine[1], mine[2]
    end
    if sw < def.minW then sw = def.minW end
    if sh < def.minH then sh = def.minH end
    return sw, sh, def
end

local function ApplySize(w)
    local sw, sh, def = SizeFor(w)
    if not sw then return end
    local f = w.frame
    if f.SetResizeBounds then
        f:SetResizeBounds(def.minW, def.minH)
    elseif f.SetMinResize then
        f:SetMinResize(def.minW, def.minH)
    end
    f:SetSize(sw, sh)
end

-- Place a registered window: at its saved TOPLEFT, else where it was put this
-- session, else centred; clamped; never user-placed. The wanted place is kept
-- apart from the clamped one, so a bigger group that the clamp pulled in goes
-- back where it was when a smaller group returns.
function Win:Place(key)
    local w = self.windows[key]
    if not w then return end
    local f = w.frame
    ApplySize(w)
    local s = Saved(key)
    local x, y
    if s and type(s.x) == "number" and type(s.y) == "number" then
        x, y = s.x, s.y
    elseif w.pos then
        x, y = w.pos[1], w.pos[2]
    else
        local sw, sh = ScreenIn(f)
        x, y = (sw - f:GetWidth()) / 2, (sh + f:GetHeight()) / 2
    end
    w.pos = { x, y }
    local cx, cy = Clamp(f, x, y)
    Anchor(f, cx, cy)
    f:SetUserPlaced(false)
end

-- After a drag (the kit's OnDragStop calls frame:OnMoved()): the TOPLEFT the
-- client left it at, clamped, saved and re-anchored.
function Win:SavePosition(key)
    local w = self.windows[key]
    if not w then return end
    local f = w.frame
    local x, y = f:GetLeft(), f:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    x, y = Clamp(f, x, y)
    local s = Saved(key, true)
    if not s then return end
    s.x, s.y = x, y
    w.pos = { x, y }
    Anchor(f, x, y)
    f:SetUserPlaced(false)
end

-- After a resize (the grip's mouse-up calls frame:OnResized()): the group's
-- size saved, raised to its minimum, and the window re-placed at its TOPLEFT.
function Win:SaveSize(key)
    local w = self.windows[key]
    if not w or not w.sizes then return end
    local f = w.frame
    local group = w.group or Win.DEFAULT_GROUP
    local def = w.sizes[group]
    if not def then return end
    local sw, sh = f:GetWidth(), f:GetHeight()
    if type(sw) ~= "number" or type(sh) ~= "number" then return end
    if sw < def.minW then sw = def.minW end
    if sh < def.minH then sh = def.minH end
    local s = Saved(key, true)
    if not s then return end
    if type(s.sizes) ~= "table" then s.sizes = {} end
    s.sizes[group] = { sw, sh }
    self:Place(key)
end

-- The main window's group changed (the dashboard's nav calls this on every
-- selection): its size and minimum, the TOPLEFT kept (6.1 rule 5).
function Win:SetGroup(key, group)
    local w = self.windows[key]
    if not w or not w.sizes or not group then return end
    if w.group == group then return end
    w.group = group
    self:Place(key)
end

--------------------------------------------------------------------------------
-- Register
--------------------------------------------------------------------------------
-- spec = { key = "main", role = "host", sizes = Win.SIZES?, group = "spells"? }
function Win:Register(frame, spec)
    if not frame or type(spec) ~= "table" or type(spec.key) ~= "string" then return end
    local role = Win.ROLES[spec.role or "host"] or Win.ROLES.host
    local w = { frame = frame, key = spec.key, role = spec.role or "host", sizes = spec.sizes,
                group = spec.group }
    self.windows[spec.key] = w

    frame:SetFrameStrata(role.strata)
    frame:SetFrameLevel(role.level)
    if frame.SetToplevel then frame:SetToplevel(role.toplevel) end
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(false)
    frame:SetScale(self:Scale())

    local moved, resized = frame.OnMoved, frame.OnResized
    frame.OnMoved = function(f)
        if moved then moved(f) end
        Win:SavePosition(spec.key)
    end
    frame.OnResized = function(f)
        if resized then resized(f) end
        Win:SaveSize(spec.key)
    end

    self:Place(spec.key)
    return w
end

--------------------------------------------------------------------------------
-- Scale, restyle, reset
--------------------------------------------------------------------------------
-- 4.3: db.ui.scale, 70-120 %. Each saved (and this session's) position is
-- converted from the old scale to the new one before the window is re-placed.
function Win:SetScale(s)
    local u = UIdb()
    if not u then return end
    s = tonumber(s) or 1
    if s < Win.SCALE_MIN then s = Win.SCALE_MIN end
    if s > Win.SCALE_MAX then s = Win.SCALE_MAX end
    u.scale = s
    for key, w in pairs(self.windows) do
        local f = w.frame
        local old = f:GetScale()
        if type(old) ~= "number" or old <= 0 then old = 1 end
        local k = old / s
        local sv = Saved(key)
        if sv and type(sv.x) == "number" and type(sv.y) == "number" then
            sv.x, sv.y = sv.x * k, sv.y * k
        end
        if w.pos then w.pos = { w.pos[1] * k, w.pos[2] * k } end
        f:SetScale(s)
        self:Place(key)
    end
    if UI.RestylePixels then UI.RestylePixels() end
    return s
end

-- The game's UI scale or the display changed: edges re-snapped, every window
-- pulled back onto the (possibly smaller) screen.
function Win:Restyle()
    if UI.RestylePixels then UI.RestylePixels() end
    for key in pairs(self.windows) do self:Place(key) end
end

-- /st ui reset: every saved place and size forgotten; every window back at its
-- default size, centred.
function Win:Reset()
    local u = UIdb()
    if u then u.win = {} end
    for key, w in pairs(self.windows) do
        w.pos = nil
        self:Place(key)
    end
end

--------------------------------------------------------------------------------
-- The main window
--------------------------------------------------------------------------------
-- Every caller of MD:SelectView comes through here (6.3). T32: open the main
-- window on the view asked for (nil: the remembered one). T34 adds the
-- takeover rules in front of this.
function Win:ShowMain(group, view)
    if MD.OpenMainWindow then return MD:OpenMainWindow(group, view) end
end

MD:On("UI_SCALE_CHANGED", function() Win:Restyle() end)
MD:On("DISPLAY_SIZE_CHANGED", function() Win:Restyle() end)
