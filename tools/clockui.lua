-- tools/run.sh [--flavour tbc|forever] tools/clockui.lua
--
-- The clock's HOST, on both flavours (TBC UI/Widget.lua, Forever
-- UI/Clock_Forever.lua): its visibility, its drag and its hover. Cut down by
-- T145c (docs/SPEC-clock-v3.md 5 U3): the renderer's checks -- layouts,
-- designs, slots, sizes, textures, secrets -- left with UI/ClockView.lua; the
-- Bar's drawing is tools/clockbarcheck.lua's, the look's store
-- tools/clockstorecheck.lua's. Held here:
--   * a look change (every Bar setting, a text, each preset, Reset) leaves the
--     frame's shown state alone -- shown in a fight, hidden at full out of
--     combat -- and calls no Show / Hide (the renderer never shows or hides
--     the clock, 2.3);
--   * every Show / Hide on the frame comes from the visibility owner (counted
--     by its caller's name);
--   * a Width change keeps the clock's centre where it was (a TOPLEFT point
--     moves by half the change); a Height change moves nothing;
--   * the drag: unlocked (or previewed) it moves and saves its point; locked,
--     Forever's does not start;
--   * the hover: the clock's tooltip, ASCII, no bare pipe; on Forever it names
--     the bar as drawn.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: clockui.lua runs under tbc, forever only")
    os.exit(3)
end
local forever = flavour == "forever"

local T = dofile(here .. "/lib/t.lua")
local check = T.check
local D = dofile(here .. "/lib/clockdrive.lua")
local ST, S = D.Load(here, root, flavour)

local Store = ST.ClockStore
local W = ST.ClockWidget or {}
local frame = D.Frame(ST)

-- the first run's 60-s placing preview (TBC unlocks the clock at a first
-- login) ended, the clock locked: what the visibility checks start from
if ST.db then ST.db.locked = true end
if W.Preview then pcall(W.Preview, W, 0) end

local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end
local function Tick(n) for _ = 1, n or 1 do S.Tick(0.5) end end

-- every Show / Hide on the clock's frame, with its caller's name
local visCalls = {}
if frame then
    local realShow, realHide = frame.Show, frame.Hide
    frame.Show = function(self, ...)
        local info = debug.getinfo(2, "n")
        visCalls[#visCalls + 1] = { "Show", info and info.name or "?" }
        return realShow(self, ...)
    end
    frame.Hide = function(self, ...)
        local info = debug.getinfo(2, "n")
        visCalls[#visCalls + 1] = { "Hide", info and info.name or "?" }
        return realHide(self, ...)
    end
end

local function Half()
    if forever then
        local m = ST.Pool.model
        m:Anchor(GetTime(), m.max * 0.5, "clockui")
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    else
        S.mana = math.floor(S.manaMax * 0.5)
    end
end
local function Full()
    if forever then
        local m = ST.Pool.model
        m:Anchor(GetTime(), m.max, "clockui")
    else
        S.mana = S.manaMax
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
end

-- every look change a user can make: each Bar setting, a text, each preset,
-- Reset
local function LookChanges()
    local list = {}
    local function add(fn) list[#list + 1] = fn end
    for _, kv in ipairs({ { "width", 300 }, { "height", 14 }, { "shape", "pill" }, { "shape", "rect" },
        { "frame", "border" }, { "frame", "none" }, { "texture", "flat" }, { "fill", "class" },
        { "back", "222222" }, { "backAlpha", 0.4 }, { "line", false }, { "line", true }, { "warn", false },
        { "timeFmt", "sec" } }) do
        add(function() Store.Set(kv[1], kv[2]) end)
    end
    add(function() Store.SetText("mp5", "on", true) end)
    add(function() Store.SetText("time", "place", "inside") end)
    add(function() Store.SetText("time", "size", 20) end)
    for _, p in ipairs(Store.PRESETS or {}) do
        add(function() Store.ApplyPreset(p.key or p) end)
    end
    add(function() Store.Reset() end)
    return list
end

--------------------------------------------------------------------------------
T.section("the frame's visibility: one owner (" .. flavour .. ")")
--------------------------------------------------------------------------------
Try("a look change leaves the frame's shown state alone (shown in a fight, hidden at full), no Show / Hide", function()
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Half()
    Tick(2)
    local bad
    local wasShown = frame:IsShown()
    local changes = LookChanges()
    for i, fn in ipairs(changes) do
        local before, n = frame:IsShown(), #visCalls
        fn()
        if frame:IsShown() ~= before or #visCalls ~= n then bad = bad or ("in a fight, change " .. i) end
    end
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    Full()
    Tick(4)
    local wasHidden = not frame:IsShown()
    for i, fn in ipairs(changes) do
        local before, n = frame:IsShown(), #visCalls
        fn()
        if frame:IsShown() ~= before or #visCalls ~= n then bad = bad or ("at full, change " .. i) end
    end
    Store.Reset()
    return wasShown and wasHidden and bad == nil and #changes > 15,
        string.format("shown in a fight %s, hidden at full %s, %d changes, %s", tostring(wasShown),
            tostring(wasHidden), #changes, tostring(bad))
end)

Try("every Show / Hide on the frame comes from the visibility owner (counted)", function()
    local n0 = #visCalls
    for _, fn in ipairs(LookChanges()) do
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Half()
        fn()
        Tick(2)
        S.inCombat = false
        S.Fire("PLAYER_REGEN_ENABLED")
        Full()
        Tick(3)
    end
    if W.Preview then W:Preview(60) end
    Tick(2)
    if W.Preview then W:Preview(0) end
    if forever and ST.Clock.SetLocked then ST.Clock:SetLocked(true) end
    Tick(3)
    Store.Reset()
    local shows, hides, other = 0, 0, {}
    for i = n0 + 1, #visCalls do
        local c = visCalls[i]
        if c[1] == "Show" then shows = shows + 1 else hides = hides + 1 end
        if c[2] ~= "UpdateVisibility" then other[#other + 1] = c[1] .. " from " .. c[2] end
    end
    return shows > 0 and hides > 0 and #other == 0,
        string.format("%d Show, %d Hide, %d from elsewhere%s", shows, hides, #other,
            #other > 0 and (": " .. other[1]) or "")
end)

--------------------------------------------------------------------------------
T.section("the place: a Width change keeps the centre (" .. flavour .. ")")
--------------------------------------------------------------------------------
Try("a Width change moves a TOPLEFT point by half the change; a Height change moves nothing", function()
    Store.Reset()
    local w0 = Store.Look().width
    local function Point()
        if forever then
            local p = ST.db.clock.point
            return p and p[4], p and p[5]
        end
        local p = ST.db.pos
        return p and p[3], p and p[4]
    end
    if forever then
        ST.db.clock.point = { "TOPLEFT", nil, "TOPLEFT", 100, -100 }
        ST.Clock:ApplyPoint()
    else
        ST.db.pos = { "TOPLEFT", "TOPLEFT", 100, -100 }
        ST:ApplyWidgetPosition()
    end
    Store.Set("width", w0 + 100)
    local x1, y1 = Point()
    Store.Set("height", Store.Look().height + 6)
    local x2, y2 = Point()
    local fp, _, _, fx, fy = frame:GetPoint(1)
    Store.Reset()
    if forever then ST.Clock:ResetPosition() else W:ResetPosition() end
    return x1 == 50 and y1 == -100 and x2 == 50 and y2 == -100 and fp == "TOPLEFT" and fx == 50 and fy == -100,
        string.format("after width %s,%s; after height %s,%s; frame %s %s,%s", tostring(x1), tostring(y1),
            tostring(x2), tostring(y2), tostring(fp), tostring(fx), tostring(fy))
end)

--------------------------------------------------------------------------------
T.section("the drag and the hover (" .. flavour .. ")")
--------------------------------------------------------------------------------
Try(forever and "the drag: previewed it moves and saves its point; locked it does not start"
        or "the drag: unlocked it moves and saves its point", function()
    local start, stop = frame:GetScript("OnDragStart"), frame:GetScript("OnDragStop")
    local moved = 0
    local realStart = frame.StartMoving
    frame.StartMoving = function(self, ...) moved = moved + 1 end
    if not forever then ST.db.locked = false end
    if W.Preview then W:Preview(60) end
    Tick(1)
    start(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 12, 34)
    stop(frame)
    local saved
    if forever then
        local p = ST.db.clock.point
        saved = type(p) == "table" and p[1] == "CENTER" and p[4] == 12 and p[5] == 34
    else
        local p = ST.db.pos
        saved = type(p) == "table" and p[1] == "CENTER" and p[3] == 12 and p[4] == 34
    end
    local unlockedMoves = moved == 1
    if W.Preview then W:Preview(0) end
    local lockedStill = true
    if forever then
        ST.Clock:SetLocked(true)
        start(frame)
        lockedStill = moved == 1
    else
        ST.db.locked = true
    end
    Tick(1)
    frame.StartMoving = realStart
    if forever then ST.Clock:ResetPosition() else W:ResetPosition() end
    return unlockedMoves and saved and lockedStill,
        string.format("moved %d saved %s locked still %s", moved, tostring(saved), tostring(lockedStill))
end)

Try("the hover: the clock's tooltip, ASCII, no bare pipe" .. (forever and "; it names the bar as drawn" or ""), function()
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Half()
    Tick(2)
    GameTooltip.lines = {}
    local enter = frame:GetScript("OnEnter")
    if enter then enter(frame) end
    local lines = GameTooltip.lines or {}
    local bad, bar = nil, not forever
    for _, l in ipairs(lines) do
        for i = 1, 2 do
            local s = l[i]
            if type(s) == "string" then
                local plain = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                if T.Ascii(plain) == false or plain:find("|", 1, true) then bad = bad or s end
                if plain:find("The bar is your real mana, drawn by the game", 1, true) then bar = true end
            end
        end
    end
    local leave = frame:GetScript("OnLeave")
    if leave then leave(frame) end
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    Tick(1)
    return #lines > 2 and bad == nil and bar,
        string.format("%d lines, bad %s, bar sentence %s", #lines, tostring(bad), tostring(bar))
end)

T.done()
