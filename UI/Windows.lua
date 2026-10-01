-- T32 (docs/SPEC-forever-ui.md 4.3 "Window scale", 6.1, 6.2, 6.7): the window
-- manager, MD.Win. T80 (C1 of docs/PLAN-refactor-ux.md, review A22, A6c):
-- listed by every main TOC -- TBC's too (decision 10, the author's answer 1)
-- -- after UI/Theme_Flat.lua and UI/EscStack.lua, so no shared file asks
-- `if MD.Win` any more. It knows no dashboard: the window that registers as
-- the host hands in its sizes per group, its first group, how to open it on a
-- view, how to read the view it shows, and where a practice session's way
-- back leads (UI/Dashboard.lua on TBC, UI/Dashboard_Forever.lua on Forever).
--
-- The core: a window registers with a key and a role; the role gives its
-- strata, level and toplevel (6.2). A window is anchored by its TOPLEFT to
-- UIParent's BOTTOMLEFT at its saved place (db.ui.win[key].x / .y, in the
-- frame's own units), or centred until it is dragged; SetUserPlaced(false), so
-- the client's layout cache never fights the manager; clamped onto the screen
-- whenever it is placed. The host keeps a size per group (6.7), with that
-- group's minimum on the resize grip. db.ui.scale (70-120 %) is applied with
-- SetScale, and a change converts every saved position (x * old / new) so the
-- window stays where it was on screen. UI.RestylePixels runs on
-- UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED, a scale change and (T51) Register,
-- so 1-px edges stay one pixel without a reload. A place kept before the
-- manager -- db.replayPos, or (spec.adoptPlaced) the place the client gave a
-- window that was user-placed -- is adopted once (Win:Adopt).
--
-- T33 (6.5, 6.6): the ESC stack is UI/EscStack.lua's (MD.EscStack); every
-- registered window joins it while shown, and its calls are on MD.Win too.
-- Entering combat hides the host (and a review replay) under db.ui.combat =
-- "hide"; PLAYER_REGEN_ENABLED shows them again, the host on the view it had.
--
-- T34 (6.3): the takeover. A replay or a practice session takes the host's
-- place: Win:TakeOver, called by the window right before it shows, hides the
-- host and remembers its path; the replay opens at its saved place
-- (db.ui.win.replay, once dragged), else with its top centre on the host's,
-- computed in screen pixels. Its "< SpellTuner" button (the kit's opts.back),
-- the x, ESC and End close it and show the host on that path; a practice
-- session's way back is the host's practice view, and its replay follows it
-- directly, the host never shown in between. ShowMain during a takeover
-- closes a replay and opens the requested view, and is refused -- with the
-- takeover window's own `busy` line -- while a practice session runs.
--
-- No client data is read here: the widget toolkit (frame geometry, strata,
-- scale) is not a client call (CLAUDE.md), and the events go through the
-- kernel's MD:On.
local _, MD = ...
local UI = MD.UI
local Esc = MD.EscStack

local Win = { windows = {} }
MD.Win = Win

-- T80 (C1): the manager's settings, declared by the file that reads them
-- (MD:RegisterDefaults, T55), so TBC has them as soon as it lists the manager.
-- fontOffset is the theme's (UI/Theme_Flat.lua), escStack the stack's.
MD:RegisterDefaults({ ui = { scale = 1, combat = "hide", win = {} } })

-- 6.2: strata / level / toplevel per role. Sheets and popups are not windows
-- the manager places (6.4); T33 / T34 use the other rows. T33: what entering
-- combat does to a shown window of that role (6.6) -- "hide" (and show it
-- again after) or "stay"; a window's own spec.combat (a string, or a function
-- asked at that moment: the practice session ends itself instead) wins.
Win.ROLES = {
    host     = { strata = "HIGH",       level = 10, toplevel = true, combat = "hide" },
    takeover = { strata = "DIALOG",     level = 10, toplevel = true, combat = "hide" },
    tool     = { strata = "FULLSCREEN", level = 10, toplevel = true, combat = "stay" },
}

-- 6.7: the host's size per group -- { [group] = { w, h, minW, minH } } -- is
-- the host's own (T80, C1, review A22): its dashboard hands the table in at
-- Register (spec.sizes; UI/Dashboard_Forever.lua's and UI/Dashboard.lua's
-- SIZES), with the group it opens on (spec.group). A group whose minimum is
-- its size (T75: nothing in it reflows) is fixed (Win:Fixed): no resize grip,
-- always its default size, whatever an older session saved. Win.SIZES is the
-- host's table once it has registered (nil before), for the suites.
Win.SIZES = nil

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

-- T75 (P31, review U14): a group whose minimum is its default size cannot be
-- resized -- nothing in it reflows -- so it shows no grip.
local function IsFixed(def)
    return type(def) == "table" and def.minW >= def.w and def.minH >= def.h
end
function Win:Fixed(key, group)
    local w = self.windows[key]
    local sizes = w and w.sizes
    return IsFixed(sizes and sizes[group or w.group or w.defaultGroup])
end

-- The size a window takes now: its group's saved size, else the group's
-- default, never under the minimum; a window without groups keeps its own.
-- T75: a fixed group is its default size (a size saved before it was fixed
-- is ignored: there is no grip left to shrink it back with).
local function SizeFor(w)
    local def = w.sizes and w.sizes[w.group or w.defaultGroup]
    if not def then return nil end
    local sw, sh = def.w, def.h
    local s = Saved(w.key)
    local mine = s and type(s.sizes) == "table" and s.sizes[w.group or w.defaultGroup]
    if not IsFixed(def) and type(mine) == "table" and type(mine[1]) == "number"
        and type(mine[2]) == "number" then
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
    -- T75 (P31, review U14): the grip only where the group can change size
    if f.resizeGrip then
        if IsFixed(def) then f.resizeGrip:Hide() else f.resizeGrip:Show() end
    end
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
    -- T34 (6.3): a takeover never dragged sits with its top centre on the
    -- point it took over (screen pixels, w.over), anchored by its TOP so a
    -- width that changes later (the suggested column filling in) keeps it
    -- centred there; clamped as a TOPLEFT would be.
    if not (s and type(s.x) == "number" and type(s.y) == "number") and w.over then
        local rs = f:GetEffectiveScale()
        if type(rs) == "number" and rs > 0 then
            local fw = f:GetWidth()
            local cx, cy = Clamp(f, w.over[1] / rs - fw / 2, w.over[2] / rs)
            f:ClearAllPoints()
            f:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx + fw / 2, cy)
            f:SetUserPlaced(false)
            return
        end
    end
    w.pos = { x, y }
    local cx, cy = Clamp(f, x, y)
    Anchor(f, cx, cy)
    f:SetUserPlaced(false)
end

-- T34: an old saved anchor { point, relPoint, x, y } (to UIParent, in the
-- frame's units: db.replayPos) turned into the manager's saved TOPLEFT, by
-- arithmetic on the screen and the frame's size -- no GetLeft, which a hidden
-- frame may not answer.
local FX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
             TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local FY = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
             TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
function Win:Adopt(key, p)
    local w = self.windows[key]
    if not w or type(p) ~= "table" then return false end
    local point, rel, x, y = p[1], p[2], tonumber(p[3]), tonumber(p[4])
    if not (FX[point] and FX[rel] and x and y) then return false end
    local f = w.frame
    local sw, sh = ScreenIn(f)
    local px, py = FX[rel] * sw + x, FY[rel] * sh + y
    local left = px - FX[point] * f:GetWidth()
    local top = py + (1 - FY[point]) * f:GetHeight()
    local s = Saved(key, true)
    if not s then return false end
    s.x, s.y = Clamp(f, left, top)
    self:Place(key)
    return true
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
    local group = w.group or w.defaultGroup
    local def = w.sizes[group]
    if not def then return end
    if IsFixed(def) then self:Place(key); return end -- T75: nothing to save
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

-- The host's group changed (the dashboard's nav calls this on every
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
-- spec = { key = "main", role = "host" | "takeover" | "tool",
--          onEsc = fn(frame) -> true to stay?, combat = "hide" | "stay" | fn?,
--          adoptPlaced = true? (T80: the place the client gave a window it was
--              told was user-placed, adopted once when nothing is saved),
--   the host (T80, C1, review A22: the dashboard hands its knowledge in):
--          sizes = { [group] = { w, h, minW, minH } }, group = the first group,
--          open = fn(group?, view?) (opens the window, on that view or the
--              remembered one), selected = fn() -> group, view,
--          practicePath = { group, view } (a practice session's way back),
--   a takeover: busy = the line ShowMain prints while it plays a practice }
-- T33: the window joins the ESC stack whenever it shows (hooked here, so a
-- caller sets its own OnShow script BEFORE registering: SetScript after this
-- would drop the hook).

-- T80 (C1): the one place a user-placed window holds -- a single point on
-- UIParent, and not the kit's untouched centre -- as Win:Adopt reads it.
local function ClientPlace(frame)
    if not (frame.IsUserPlaced and frame:IsUserPlaced() == true) then return nil end
    if not (frame.GetNumPoints and frame:GetNumPoints() == 1) then return nil end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if rel ~= nil and rel ~= UIParent then return nil end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if p == "CENTER" and rp == "CENTER" and x == 0 and y == 0 then return nil end
    return { p, rp, x, y }
end

function Win:Register(frame, spec)
    if not frame or type(spec) ~= "table" or type(spec.key) ~= "string" then return end
    local role = Win.ROLES[spec.role or "host"] or Win.ROLES.host
    local w = { frame = frame, key = spec.key, role = spec.role or "host", sizes = spec.sizes,
                defaultGroup = spec.group, onEsc = spec.onEsc, combat = spec.combat,
                open = spec.open, selected = spec.selected, practicePath = spec.practicePath,
                busy = spec.busy }
    self.windows[spec.key] = w
    if w.role == "host" then
        self.host = w
        self.SIZES = spec.sizes
    end
    local old = spec.adoptPlaced and not Saved(spec.key) and ClientPlace(frame)

    frame:SetFrameStrata(role.strata)
    frame:SetFrameLevel(role.level)
    if frame.SetToplevel then frame:SetToplevel(role.toplevel) end
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(false)
    frame:SetScale(self:Scale())
    -- T51 (B18): the kit styled this frame's 1-px edges at UIParent's scale,
    -- before the window scale above; re-snap them at the scale it now has
    if UI.RestylePixels then UI.RestylePixels() end

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
    if old then self:Adopt(spec.key, old) end

    -- T33 (6.5): on the stack while shown; its OnHide (Push's hook) takes it off
    frame:HookScript("OnShow", function(f)
        local cur = Win.windows[spec.key]
        Win:Push(f, cur and cur.onEsc)
    end)
    if frame:IsShown() then self:Push(frame, w.onEsc) end

    -- T34 (6.3): a takeover's back button (the kit's opts.back) and its every
    -- close -- back, the x, ESC, End -- give the host back
    if spec.role == "takeover" then
        if frame.header and frame.header.backBtn then
            frame.OnBack = function(f) f:Hide() end
        end
        frame:HookScript("OnHide", function(f)
            if f:IsShown() then return end -- UIParent hid (Alt+Z), not this
            Win:TakeoverHidden(spec.key)
        end)
    end
    return w
end

--------------------------------------------------------------------------------
-- Scale, restyle, reset
--------------------------------------------------------------------------------
-- 4.3: db.ui.scale, 70-120 %. Each saved (and this session's) position is
-- converted from the old scale to the new one before the window is re-placed.
-- T51 (B17): the old scale is read before the new one is written, and every
-- saved place in db.ui.win is converted, registered this session or not -- a
-- replay or console never opened yet keeps its place in the same units as the
-- ones that were.
function Win:SetScale(s)
    local u = UIdb()
    if not u then return end
    s = tonumber(s) or 1
    if s < Win.SCALE_MIN then s = Win.SCALE_MIN end
    if s > Win.SCALE_MAX then s = Win.SCALE_MAX end
    local old = self:Scale()
    u.scale = s
    for _, sv in pairs(u.win) do
        if type(sv) == "table" and type(sv.x) == "number" and type(sv.y) == "number" then
            sv.x, sv.y = sv.x * old / s, sv.y * old / s
        end
    end
    for key, w in pairs(self.windows) do
        local f = w.frame
        local fo = f:GetScale()
        if type(fo) ~= "number" or fo <= 0 then fo = old end
        local k = fo / s
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

-- T42: the scale as the Settings slider shows it, a whole percent (70-120).
function Win:ScalePercent()
    return math.floor(self:Scale() * 100 + 0.5)
end

-- /st ui reset and Settings -> General's "Reset window positions" (T42):
-- every saved place and size forgotten; every window back at its default
-- size, centred. The scale, the combat rule and the ESC rule are kept.
function Win:Reset()
    local u = UIdb()
    if u then u.win = {} end
    for key, w in pairs(self.windows) do
        w.pos = nil
        self:Place(key)
    end
end

--------------------------------------------------------------------------------
-- The host and the takeover (6.3, T34)
--------------------------------------------------------------------------------
-- Win.takeover = { key, kind = "replay" | "practice", path = { group, view } | nil }
-- T80 (C1, review A22): the host is the window registered with role "host";
-- its view, its opening and its practice path are its own spec's.

local function SetBack(f, on)
    local b = f.header and f.header.backBtn
    if not b then return end
    if on then b:Show() else b:Hide() end
end

local function OpenHost(group, view)
    local h = Win.host
    if h and h.open then return h.open(group, view) end
end

-- The window `key` is about to show as `kind`: "replay" (a review replay, or
-- a practice's) or "practice" (a session being played). With the host shown,
-- it hides and its path is remembered, and the window opens over its top
-- centre (unless it was ever dragged); with a takeover of this window already
-- on screen (End -> its replay, the next pull, the suggested column filling
-- in) the place and the way back are kept; otherwise (from chat) the saved
-- place or the centre, and no back button. A practice session always takes
-- over, and its way back is the host's practice view.
function Win:TakeOver(key, kind)
    local w = self.windows[key]
    if not w then return end
    local f = w.frame
    local main = self.host
    local cur = self.takeover
    local mainShown = main and main.frame:IsShown()
    local path
    if mainShown then
        local mf = main.frame
        if main.selected then
            local g, v = main.selected()
            if g then path = { g, v } end
        end
        local ms = mf:GetEffectiveScale()
        local l, t = mf:GetLeft(), mf:GetTop()
        if type(ms) == "number" and type(l) == "number" and type(t) == "number" then
            w.over = { (l + mf:GetWidth() / 2) * ms, t * ms }
        end
        w.pos = nil
    elseif cur and cur.key == key and f:IsShown() then
        path = cur.path
    else
        w.over, w.pos = nil, nil
    end
    if kind == "practice" then
        local pp = main and main.practicePath
        path = pp and { pp[1], pp[2] } or nil
    end
    self.takeover = { key = key, kind = kind, path = path }
    SetBack(f, kind ~= "practice" and path ~= nil)
    self:Place(key)
    if mainShown then main.frame:Hide() end
end

-- The takeover window hid (its OnHide, however it closed). A combat hide keeps
-- the takeover: the window comes back after, the host still hidden.
-- Otherwise the host returns on the remembered path -- after combat, if this
-- happened in one under db.ui.combat = "hide".
function Win:TakeoverHidden(key)
    local t = self.takeover
    if not t or t.key ~= key then return end
    if self.combatHiding then return end
    self.takeover = nil
    if not t.path then return end
    local u = UIdb()
    if self:InCombat() and not (u and u.combat == "keep") then
        if self.host then
            self.combatHidden = self.combatHidden or {}
            table.insert(self.combatHidden, { key = self.host.key, group = t.path[1], view = t.path[2] })
        end
        return
    end
    OpenHost(t.path[1], t.path[2])
end

-- Every takeover window closed without giving the host back (ShowMain opens
-- the view asked for instead); nothing of theirs returns after combat.
function Win:CloseTakeovers()
    self.takeover = nil
    for _, w in pairs(self.windows) do
        if w.role == "takeover" and w.frame:IsShown() then w.frame:Hide() end
    end
    local hidden = self.combatHidden
    if hidden then
        for i = #hidden, 1, -1 do
            local w = self.windows[hidden[i].key]
            if w and w.role == "takeover" then table.remove(hidden, i) end
        end
    end
end

function Win:InCombat()
    if self.inCombat then return true end
    local API = MD.API
    return (API and API.UnitAffectingCombat and API.UnitAffectingCombat("player") == true) or false
end

-- Every caller of MD:SelectView comes through here (6.3). Open the host on the
-- view asked for (nil: the remembered one). During a practice session it is
-- refused with the session window's one line; during a replay the replay
-- closes first -- the two are never shown together by a command.
function Win:ShowMain(group, view)
    local t = self.takeover
    if t and t.kind == "practice" then
        local w = self.windows[t.key]
        if w and w.frame:IsShown() then
            if w.busy then MD:Print(w.busy) end
            return
        end
    end
    self:CloseTakeovers()
    return OpenHost(group, view)
end

--------------------------------------------------------------------------------
-- The ESC stack (6.5, T33): UI/EscStack.lua's, on MD.Win too (T80, C1). The
-- same table and the same proxy, so a caller of either sees one stack.
--------------------------------------------------------------------------------
Win.stack = Esc.stack
Win.proxy = Esc.proxy
function Win:Push(frame, onEsc) return Esc:Push(frame, onEsc) end
function Win:Remove(frame) return Esc:Remove(frame) end
function Win:Prune() return Esc:Prune() end
function Win:OnEsc() return Esc:OnEsc() end
function Win:CloseLists() return Esc:CloseLists() end
function Win:TopWindow(exclude) return Esc:TopWindow(exclude) end
function Win:EscStackOn() return Esc:On() end
function Win:EscLine() return Esc:Line() end

-- db.ui.escStack (Settings -> General, T42): what is open now carries over --
-- turning the stack back on pushes every registered window that is shown.
function Win:SetEscStack(on)
    local shown = {}
    for _, w in pairs(self.windows) do
        if w.frame:IsShown() then shown[#shown + 1] = { frame = w.frame, onEsc = w.onEsc } end
    end
    return Esc:Set(on, shown)
end

--------------------------------------------------------------------------------
-- Combat (6.6, T33)
--------------------------------------------------------------------------------
local function CombatRule(w)
    local c = w.combat
    if type(c) == "function" then c = c(w.frame) end
    if c == nil then c = (Win.ROLES[w.role] or Win.ROLES.host).combat end
    return c
end

-- T42 (Settings -> General's WINDOWS pane, decision 4): the two modes, in the
-- order the dropdown lists them. "hide" is the default and what anything else
-- saved reads as.
Win.COMBAT_MODES = {
    { id = "hide", text = "Hide, reopen after",
      tooltip = "The main window and a replay hide when a fight starts and come back on the same view after it." },
    { id = "keep", text = "Keep them open", tooltip = "Nothing changes when a fight starts." },
}

function Win:CombatMode()
    local u = UIdb()
    if u and u.combat == "keep" then return "keep" end
    return "hide"
end

-- The next PLAYER_REGEN_DISABLED reads it; what a fight already hid still
-- comes back when it ends.
function Win:SetCombat(mode)
    local u = UIdb()
    if not u then return end
    if mode ~= "keep" then mode = "hide" end
    u.combat = mode
    return mode
end

-- db.ui.combat = "hide" (default): every shown window whose rule is "hide"
-- hides and is remembered, the main window with its view. "keep": nothing.
function Win:EnterCombat()
    self.inCombat = true -- T34: a takeover closed in combat gives the main window back after
    local u = UIdb()
    if u and u.combat == "keep" then return end
    local hidden = self.combatHidden or {}
    local list = {}
    for key, w in pairs(self.windows) do
        if w.frame:IsShown() and CombatRule(w) == "hide" then
            local rec = { key = key }
            if w == self.host and w.selected then rec.group, rec.view = w.selected() end
            list[#list + 1] = rec
        end
    end
    self.combatHidden = hidden
    self.combatHiding = true -- T34: a takeover hidden here stays a takeover
    for _, rec in ipairs(list) do
        hidden[#hidden + 1] = rec
        self.windows[rec.key].frame:Hide()
    end
    self.combatHiding = nil
    -- T73 (P29, review U11, mockup M1): the first time a fight hides a window,
    -- one chat line says why and where to change it -- once, ever
    -- (db.ui.combatNoted), not at every pull.
    if #list > 0 and u and not u.combatNoted then
        u.combatNoted = true
        MD:Print(Win.COMBAT_NOTE)
    end
end

Win.COMBAT_NOTE = "the window hides in combat and comes back after. Settings -> General -> Windows."
-- PLAYER_REGEN_ENABLED: what combat hid comes back where it was. During a
-- takeover the main window was already hidden, so only the replay returns.
function Win:LeaveCombat()
    self.inCombat = nil
    local hidden = self.combatHidden
    self.combatHidden = nil
    if not hidden then return end
    for _, rec in ipairs(hidden) do
        local w = self.windows[rec.key]
        if w and not w.frame:IsShown() then
            if w == self.host then
                self:ShowMain(rec.group, rec.view)
            else
                w.frame:Show()
            end
        end
    end
end

MD:On("UI_SCALE_CHANGED", function() Win:Restyle() end)
MD:On("DISPLAY_SIZE_CHANGED", function() Win:Restyle() end)
MD:On("PLAYER_REGEN_DISABLED", function() Win:EnterCombat() end)
MD:On("PLAYER_REGEN_ENABLED", function() Win:LeaveCombat() end)
