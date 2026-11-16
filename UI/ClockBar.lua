-- T145c (docs/SPEC-clock-v3.md 2.3; docs/tasks/T145c-clock-bar.md): the
-- clock's RENDERER, on both lines. It replaces UI/ClockView.lua: one bar (the
-- game's own mana fill), texts placed round it, and the moving amber line
-- while the five-second rule runs. Each line's host (UI/Clock_Forever.lua,
-- UI/Widget.lua) owns the frame, its visibility, drag and hover, and builds
-- one renderer inside it:
--
--   ClockBar.New(host, draw) -> bar
--     draw.pool(statusBar)       the pool's value into the bar (Forever:
--                                ST.API.DrawUnitPower, never read)
--     draw.poolMax(statusBar)    its min / max (ST.API.DrawUnitPowerMax)
--     draw.powerText(fs, kind)   a mana / manaMax / pct text drawn by the
--                                game (ST.API.DrawPowerText); true when it did
--     draw.fsrEnd()              when the five-second rule ends: a plain time,
--                                or nil for no rule
--   bar:Apply(look)      LAYOUT, once per look change (ClockStore.Look()):
--                        the only function that anchors, sizes or sets a font.
--                        No string is measured and no text changes the frame's
--                        size; the host's hit rect reaches the outside texts
--   bar:Paint(words)     ClockWords.Build's words: SetText only when a string
--                        changed, the time's colour only when its tone did; no
--                        allocation, no anchor, no font
--   bar:PaintPower(withMax)  the game's pool into the bar (with withMax its
--                        range first: the frequent power event passes none, so
--                        the client's easing is never restarted) and the power
--                        texts; a refused one draws the model's words, marked
--   bar:Message(text, r, g, b)  the preview's line instead of the texts; nil
--                        ends it
--   bar:Pulse()          the attention pulse
--   bar:Drawn()          what the user sees, from this file's own write cache
--                        (never read back from a region): the test snapshot
--
-- THE MOVING LINE (P4): one driver, a plain 1x1 frame of its own (no texture,
-- no secret, not a StatusBar), its OnUpdate set ONCE in New and never cleared.
-- Each frame it asks draw.fsrEnd() and places the line at barW * (5 - left) / 5
-- while the rule runs, else hides it once. Apply changes only barW and lineOn;
-- nothing else touches the script, so no rebuild, preview or power event can
-- stop it. Only the host hidden stops it, and then there is nothing to draw.
--
-- What it never does: Show / Hide the host frame (each line's visibility has
-- one owner), call the client (frame methods and `draw` only), read a power
-- value back (no GetText / GetValue / GetStringWidth on anything the power
-- path wrote, and nothing anchored to it), read ST.db.
local _, ST = ...
local UI = ST.UI

ST.ClockBar = ST.ClockBar or {}
local CB = ST.ClockBar

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
CB.MEDIA = "Interface\\AddOns\\SpellTuner\\Media\\"
-- SpellTuner's bar textures (tools/buildmedia.py) and the game's two;
-- "eui:<key>" and "lsm:<name>" are a host's (Integrations/Media_LSM.lua).
CB.TEXTURES = {
    flat = UI.whiteTexture,
    soft = CB.MEDIA .. "Soft", smooth = CB.MEDIA .. "Smooth", gloss = CB.MEDIA .. "Gloss",
    striped = CB.MEDIA .. "Striped", minimal = CB.MEDIA .. "Minimal",
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
CB.EUI_PREFIX = "eui:"
CB.LSM_PREFIX = "lsm:"
CB.MASKS = { round = "Round", pill = "Pill" }

-- The reasons beside a control the client cannot honour (spec 2.6); the
-- choice is kept in the store for when it can be drawn.
CB.EUI_TEXTURE_MISSING = "EllesmereUI is not loaded: Soft"
CB.LSM_MISSING = "that texture's addon is not loaded: Flat"
CB.FONT_EUI_MISSING = "EllesmereUI is not loaded: SpellTuner's font"
CB.MASK_REFUSED = "this client has no mask textures: a rectangle"
CB.GAME_REFUSED = "this client has no game bar art: Border"

-- The fill's Mana blue (the author's 396DA7) and the line's amber (the
-- five-second rule's colour since v0.1), fixed: a meaning colour.
CB.MANA_BLUE = { 0x39 / 255, 0x6D / 255, 0xA7 / 255 }
CB.LINE_COLOR = { 1, 0.67, 0.2 }
CB.LINE_WIDTH = 2          -- physical pixels, with a 1-px dark edge each side
CB.LINE_EDGE_ALPHA = 0.85
CB.RULE = 5                -- seconds: the five-second rule

-- Text placing (T142 / T144): an inside text that is not centred sits PAD in
-- from its end; an outside one GAP from the bar's edge (one more on a Border).
CB.PAD = 2
CB.GAP = 1
CB.OUTLINE = { outline = "OUTLINE", thick = "THICKOUTLINE" }

-- The game's bar art (EllesmereUI's "Blizzard style", T142): the frame atlas
-- round the bar, the mask atlas on the fill and the background, four bevels.
CB.GAME_ATLAS = { frame = "UI-HUD-CoolDownManager-Bar-BG", mask = "UI-HUD-CoolDownManager-Bar" }
CB.GAME_REACH = { left = -2, top = 3, right = 6, bottom = -7 }

-- The kinds, in drawing order, and the ones the game can draw itself.
CB.KINDS = { "time", "mana", "manaMax", "pct", "mp5", "fsr", "rest" }
CB.POWER_KINDS = { "mana", "manaMax", "pct" }
local IS_POWER = { mana = true, manaMax = true, pct = true }

-- What a power text drawn by the game reads as in Drawn() (its words are
-- the client's and never read).
CB.POWER_WORDS = "<power>"

--------------------------------------------------------------------------------
-- Pure helpers
--------------------------------------------------------------------------------
local function HexRGB(h)
    if type(h) ~= "string" or not h:match("^%x%x%x%x%x%x$") then return 1, 1, 1 end
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
CB.HexRGB = HexRGB

local function Prefixed(v, pre) return type(v) == "string" and #v > #pre and v:sub(1, #pre) == pre end

-- CB.TexturePath(key) -> path, why: a host's missing texture falls back
-- (EllesmereUI's to Soft, LibSharedMedia's to Flat) and says why.
function CB.TexturePath(key)
    if Prefixed(key, CB.EUI_PREFIX) then
        local M = ST.Media
        local path = M and M.FetchEllesmere and M.FetchEllesmere(key:sub(#CB.EUI_PREFIX + 1))
        if type(path) == "string" and path ~= "" then return path end
        return CB.TEXTURES.soft, CB.EUI_TEXTURE_MISSING
    end
    if Prefixed(key, CB.LSM_PREFIX) then
        local M = ST.Media
        local path = M and M.Fetch and M.Fetch(key:sub(#CB.LSM_PREFIX + 1))
        if type(path) == "string" and path ~= "" then return path end
        return CB.TEXTURES.flat, CB.LSM_MISSING
    end
    return CB.TEXTURES[key] or CB.TEXTURES.soft
end

local function FontObj(name)
    return (UI.fontObjects and UI.fontObjects[name]) or _G[name]
end

-- CB.Font(look) -> face, why: EllesmereUI's font read live (the Ellesmere
-- style's own path), or the kit's.
function CB.Font(look)
    local why
    if type(look) == "table" and look.font == "eui" then
        local E = UI.Ellesmere
        local path = E and E.FontPath and E.FontPath()
        if type(path) == "string" and path ~= "" then return path end
        why = CB.FONT_EUI_MISSING
    end
    local obj = FontObj(UI.FONT)
    local face
    if obj and obj.GetFont then face = obj:GetFont() end
    if type(face) ~= "string" then face = "Fonts\\ARIALN.TTF" end
    return face, why
end

-- CB.FillRGB(fill) -> r, g, b: "mana" the Mana blue, "class" the player's
-- class colour, else six hex digits.
function CB.FillRGB(fill)
    if fill == "class" then
        local a = UI.classAccent or UI.accent or { 1, 1, 1 }
        return a[1], a[2], a[3]
    end
    if type(fill) == "string" and fill:match("^%x%x%x%x%x%x$") then return HexRGB(fill) end
    return CB.MANA_BLUE[1], CB.MANA_BLUE[2], CB.MANA_BLUE[3]
end

-- CB.GameFrameOK() -> true, or false and why: the client has both atlases
-- (asked through ST.API).
function CB.GameFrameOK()
    local A = ST.API
    if not (A and A.HasAtlas) then return false, CB.GAME_REFUSED end
    if A.HasAtlas(CB.GAME_ATLAS.frame) and A.HasAtlas(CB.GAME_ATLAS.mask) then return true end
    return false, CB.GAME_REFUSED
end

local SUFFIX = { left = "LEFT", center = "", right = "RIGHT" }

-- CB.TextAnchor(t, gap) -> point, relPoint, x, y: a text's anchor on the
-- bar's rect (T142 / T144): inside from the bar's left end, centre or right
-- end (PAD in when not centred); above / below hanging from the bar's top /
-- bottom edge, `gap` away. Pure.
function CB.TextAnchor(t, gap)
    local suf = SUFFIX[t.align] or ""
    if t.place == "inside" then
        local p = (suf == "") and "CENTER" or suf
        local pad = (suf == "LEFT" and CB.PAD) or (suf == "RIGHT" and -CB.PAD) or 0
        return p, p, pad + t.x, t.y
    elseif t.place == "above" then
        return "BOTTOM" .. suf, "TOP" .. suf, t.x, gap + t.y
    end
    return "TOP" .. suf, "BOTTOM" .. suf, t.x, -gap + t.y
end

-- CB.Insets(look) -> top, bottom: how far past the bar the outside texts
-- reach (each text's size + 2), for the host's hit rect. Never measured.
function CB.Insets(look)
    local top, bottom = 0, 0
    local texts = type(look) == "table" and look.texts or {}
    for _, kind in ipairs(CB.KINDS) do
        local t = texts[kind]
        if type(t) == "table" and t.on then
            local reach = (t.size or 0) + 2
            if t.place == "above" and reach > top then top = reach end
            if t.place == "below" and reach > bottom then bottom = reach end
        end
    end
    return top, bottom
end

-- T115, moved from UI/ClockView.lua: where a frame's point goes so its CENTRE
-- stays put when its scale and size change (`p` the frame's own point, x / y
-- its offsets at scale s0 and size w0 x h0; the offsets at s1, w1 x h1).
function CB.KeepCentre(p, x, y, s0, s1, w0, h0, w1, h1)
    p = type(p) == "string" and p or "CENTER"
    local function CX(w) if p:find("LEFT") then return w / 2 elseif p:find("RIGHT") then return -w / 2 end return 0 end
    local function CY(h) if p:find("TOP") then return -h / 2 elseif p:find("BOTTOM") then return h / 2 end return 0 end
    x, y = x or 0, y or 0
    local x1 = (x * s0 + CX(w0) * s0 - CX(w1) * s1) / s1
    local y1 = (y * s0 + CY(h0) * s0 - CY(h1) * s1) / s1
    return x1, y1
end

-- The time's colour for a tone: "text" the text's own hex, else the fixed
-- tones (ClockFace.HEX: crit, warn, muted).
local function ToneRGB(tone, hex)
    if tone == nil or tone == "text" then return HexRGB(hex) end
    return ST.ClockFace.ToneRGB(tone)
end

--------------------------------------------------------------------------------
-- Masks
--------------------------------------------------------------------------------
-- A pair of masks on `owner` (nil where the client has none); the textures
-- each clips are added once, a shape changes only the files.
local function MaskPair(owner)
    if type(owner.CreateMaskTexture) ~= "function" then return nil end
    local ok1, l = pcall(owner.CreateMaskTexture, owner)
    local ok2, r = pcall(owner.CreateMaskTexture, owner)
    if not (ok1 and ok2 and type(l) == "table" and type(r) == "table") then return nil end
    return { l, r, on = {} }
end
local function Clip(pair, tex)
    if not pair or type(tex) ~= "table" or type(tex.AddMaskTexture) ~= "function" or pair.on[tex] then return end
    pair.on[tex] = true
    tex:AddMaskTexture(pair[1])
    tex:AddMaskTexture(pair[2])
end
local function SizeMasks(pair, region, h)
    if not pair or not region then return end
    local l, r = pair[1], pair[2]
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
    l:SetSize(h, h)
    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
    r:SetSize(h, h)
end
local function NoSnap(tex)
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
end

--------------------------------------------------------------------------------
-- The renderer
--------------------------------------------------------------------------------
local Bar = {}
Bar.__index = Bar
CB.Bar = Bar

-- ClockBar.New(host, draw) -> bar: every region made once.
function CB.New(host, draw)
    local b = setmetatable({ host = host, draw = type(draw) == "table" and draw or {},
        wrote = {}, byPower = {}, modelled = {}, fonts = {}, points = {}, colours = {} }, Bar)

    -- the pulse: four quarter-second fades (UI/Widget.lua's since v0.1)
    local pulse = host:CreateAnimationGroup()
    for i, dir in ipairs({ 1, -1, 1, -1 }) do
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(dir > 0 and 1 or 0.2)
        a:SetToAlpha(dir > 0 and 0.2 or 1)
        a:SetDuration(0.25)
        a:SetOrder(i)
    end
    b.pulse = pulse

    -- the bar: the frame is the bar (T142)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetAllPoints(host)
    bar:SetStatusBarTexture(UI.whiteTexture)
    b.bar = bar
    -- its background and its edge (Frame = Border), textures of the host
    b.back = host:CreateTexture(nil, "ARTWORK", nil, 1)
    b.back:SetAllPoints(bar)
    b.edge = host:CreateTexture(nil, "ARTWORK", nil, 0)
    b.edge:SetPoint("CENTER", bar, "CENTER", 0, 0)
    b.edge:SetColorTexture(0, 0, 0, 1)
    b.edge:Hide()

    -- the moving line on its dark edge, on the bar so the bar's shape clips it
    b.lineBack = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    b.lineBack:SetColorTexture(0, 0, 0, CB.LINE_EDGE_ALPHA)
    b.lineBack:Hide()
    b.line = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    b.line:SetColorTexture(CB.LINE_COLOR[1], CB.LINE_COLOR[2], CB.LINE_COLOR[3], 1)
    b.line:Hide()
    b.lineShown = false

    -- the shape's masks: one pair on the bar (its fill and the line), one on
    -- the host for each of the background and the edge
    local barM = MaskPair(bar)
    if barM then
        b.masks = { bar = barM, back = MaskPair(host), edge = MaskPair(host) }
        Clip(b.masks.bar, b.line)
        Clip(b.masks.bar, b.lineBack)
        Clip(b.masks.back, b.back)
        Clip(b.masks.edge, b.edge)
    end

    -- the texts, on a holder above the bar, one font string per kind
    local holder = CreateFrame("Frame", nil, host)
    holder:SetAllPoints(bar)
    b.holder = holder
    b.texts = {}
    for _, kind in ipairs(CB.KINDS) do
        local fs = holder:CreateFontString(nil, "OVERLAY", UI.FONT)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText("")
        fs:Hide()
        b.texts[kind] = fs
    end
    b.msg = holder:CreateFontString(nil, "OVERLAY", UI.FONT)
    b.msg:SetPoint("CENTER", holder, "CENTER", 0, 0)
    b.msg:SetText("")
    b.msg:Hide()
    b.msgOn = false

    -- P4: the line's driver, its script set here once and never cleared
    local driver = CreateFrame("Frame", nil, host)
    driver:SetSize(1, 1)
    driver:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    b.driver = driver
    local PROF = ST.Prof
    b.step = function()
        if PROF.on then return PROF.Time("clock line (OnUpdate)", b.Step, b, GetTime()) end
        b:Step(GetTime())
    end
    driver:SetScript("OnUpdate", b.step)
    b.barW, b.lineOn = 0, false
    return b
end

--------------------------------------------------------------------------------
-- The game's bar frame (T142, moved as is)
--------------------------------------------------------------------------------
function Bar:BuildGame()
    if self.game then return self.game end
    local host, bar = self.host, self.bar
    local g = { on = {} }
    g.art = host:CreateTexture(nil, "BACKGROUND", nil, -2)
    NoSnap(g.art)
    g.art:Hide()
    g.mask = bar:CreateMaskTexture()
    g.mask:SetAllPoints(bar)
    g.backMask = host:CreateMaskTexture()
    g.backMask:SetAllPoints(self.back)
    self.back:AddMaskTexture(g.backMask)
    g.bevel = {}
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        local t = bar:CreateTexture(nil, "OVERLAY", nil, -3)
        t:SetTexture(UI.whiteTexture)
        t:AddMaskTexture(g.mask)
        NoSnap(t)
        t:Hide()
        g.bevel[k] = t
    end
    self.game = g
    return g
end

local function GameClip(g, tex)
    if type(tex) ~= "table" or type(tex.AddMaskTexture) ~= "function" or g.on[tex] then return end
    g.on[tex] = true
    tex:AddMaskTexture(g.mask)
end

function Bar:PlaceGame(on, w, h)
    if not on then
        local g = self.game
        if g then
            g.art:Hide()
            for _, t in pairs(g.bevel) do t:Hide() end
            -- off: the masks clip nothing
            pcall(g.mask.SetTexture, g.mask, UI.whiteTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
            pcall(g.backMask.SetTexture, g.backMask, UI.whiteTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
        end
        self.gameOn = false
        return
    end
    local g = self:BuildGame()
    local host, bar = self.host, self.bar
    local A = CB.GAME_ATLAS
    g.art:SetAtlas(A.frame)
    g.mask:SetAtlas(A.mask)
    g.backMask:SetAtlas(A.mask)
    GameClip(g, bar.GetStatusBarTexture and bar:GetStatusBarTexture())
    local R = CB.GAME_REACH
    g.art:ClearAllPoints()
    g.art:SetPoint("TOPLEFT", host, "BOTTOMLEFT", R.left, h + R.top)
    g.art:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", w + R.right, R.bottom)
    g.art:Show()
    local top = math.max(2, math.floor(h * 0.2))
    local bottom = math.max(1, math.floor(h * 0.1))
    local side = math.max(2, math.floor(w * 0.15))
    local B = g.bevel
    B.top:ClearAllPoints()
    B.top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    B.top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    B.top:SetHeight(top)
    ST.API.SetGradient(B.top, 0, 0, 0, 0, 0, 0, 0, 0.55, "VERTICAL")
    B.bottom:ClearAllPoints()
    B.bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    B.bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    B.bottom:SetHeight(bottom)
    ST.API.SetGradient(B.bottom, 0, 0, 0, 0.30, 0, 0, 0, 0, "VERTICAL")
    B.left:ClearAllPoints()
    B.left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    B.left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    B.left:SetWidth(side)
    ST.API.SetGradient(B.left, 0, 0, 0, 0.35, 0, 0, 0, 0)
    B.right:ClearAllPoints()
    B.right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    B.right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    B.right:SetWidth(side)
    ST.API.SetGradient(B.right, 0, 0, 0, 0, 0, 0, 0, 0.35)
    for _, t in pairs(B) do t:Show() end
    self.gameOn = true
end

--------------------------------------------------------------------------------
-- Apply: the layout, once per look change
--------------------------------------------------------------------------------
-- bar:Apply(look): a validated v3 look (ClockStore.Look()). look.notes gets
-- the reasons a choice is drawn otherwise ({ texture, font, shape, frame }).
function Bar:Apply(look)
    look = look or self.look
    if type(look) ~= "table" then return end
    self.look = look
    look.notes = {}
    local notes = look.notes
    local host, bar = self.host, self.bar
    local e = UI.px and UI.px(1, host) or 1
    self.px = e
    local w, h = look.width, look.height
    host:SetSize(w, h)
    self.size = { w, h }

    -- the fill: texture, colour; re-clipped (the client may hand back a new
    -- fill texture after SetStatusBarTexture)
    local tex, whyT = CB.TexturePath(look.texture)
    if whyT then notes.texture = whyT end
    bar:SetStatusBarTexture(tex)
    self.texPath = tex
    local r, g, b = CB.FillRGB(look.fill)
    bar:SetStatusBarColor(r, g, b)
    bar:SetAlpha(1)
    self.fillRGB = { r, g, b }
    -- the background
    local br, bg, bb = HexRGB(look.back)
    self.back:SetColorTexture(br, bg, bb, look.backAlpha)
    self.backRGBA = { br, bg, bb, look.backAlpha }

    -- the frame: the game's art where the client has it (and masks), else a
    -- Border; a Border is one physical pixel of black
    local mode = look.frame
    if mode == "game" then
        local okG, whyG = CB.GameFrameOK()
        if not okG or not self.masks then
            notes.frame = whyG or CB.GAME_REFUSED
            mode = "border"
        end
    end
    self.frameMode = mode
    local bd = (mode == "border") and e or 0
    if bd > 0 then
        self.edge:SetSize(w + 2 * bd, h + 2 * bd)
        self.edge:Show()
    else
        self.edge:Hide()
    end
    self.edgeShown = bd > 0

    -- the shape: the mask files (a rectangle: the white texture, which clips
    -- nothing), sized a square of their region's height at each end
    local base = CB.MASKS[look.shape]
    local mk = self.masks
    if base and not mk then notes.shape = CB.MASK_REFUSED end
    self.maskFile = nil
    if mk then
        Clip(mk.bar, bar.GetStatusBarTexture and bar:GetStatusBarTexture())
        for _, pair in pairs(mk) do
            local l = base and (CB.MEDIA .. base .. "L") or UI.whiteTexture
            local rr = base and (CB.MEDIA .. base .. "R") or UI.whiteTexture
            pcall(pair[1].SetTexture, pair[1], l, "CLAMPTOWHITE", "CLAMPTOWHITE")
            pcall(pair[2].SetTexture, pair[2], rr, "CLAMPTOWHITE", "CLAMPTOWHITE")
        end
        self.maskFile = base
        SizeMasks(mk.bar, bar, h)
        SizeMasks(mk.back, self.back, h)
        SizeMasks(mk.edge, self.edge, h + 2 * bd)
    end
    self:PlaceGame(mode == "game", w, h)

    -- the line: its size; the driver reads barW and lineOn (P4)
    local lw = UI.px and UI.px(CB.LINE_WIDTH, host) or CB.LINE_WIDTH
    self.line:SetSize(lw, h)
    self.lineBack:SetSize(lw + 2 * e, h)
    self.barW, self.lineOn = w, look.line == true

    -- the texts: font, flags, shadow, anchor, justify, shown, colour
    local face, whyF = CB.Font(look)
    if whyF then notes.font = whyF end
    self.face = face
    self.holder:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
    local gap = CB.GAP + ((mode == "border") and 1 or 0)
    for _, kind in ipairs(CB.KINDS) do
        local t = look.texts[kind]
        local fs = self.texts[kind]
        if t and t.on then
            local flags = CB.OUTLINE[t.outline] or ""
            fs:SetFont(face, t.size, flags)
            if t.outline == "shadow" then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            local p, rp, x, y = CB.TextAnchor(t, gap)
            fs:SetJustifyH((p:find("LEFT") and "LEFT") or (p:find("RIGHT") and "RIGHT") or "CENTER")
            fs:ClearAllPoints()
            fs:SetPoint(p, self.holder, rp, x, y)
            self.fonts[kind] = { face, t.size, flags, t.outline == "shadow" }
            self.points[kind] = { p, rp, x, y }
            local tr, tg, tb = HexRGB(t.colour)
            if kind == "time" then tr, tg, tb = ToneRGB(self.tone, t.colour) end
            fs:SetTextColor(tr, tg, tb)
            self.colours[kind] = { tr, tg, tb }
            if self.msgOn then fs:Hide() else fs:Show() end
        else
            fs:Hide()
            self.fonts[kind], self.points[kind], self.colours[kind] = nil, nil, nil
        end
    end
    self.msg:SetFont(face, 11, "OUTLINE")

    -- the host's hit rect reaches the texts above and below (hover, drag)
    local top, bottom = CB.Insets(look)
    if host.SetHitRectInsets then host:SetHitRectInsets(0, 0, -top, -bottom) end
    self.insets = { top, bottom }

    -- then the power and the last words again, into the new places
    for k in pairs(self.wrote) do self.wrote[k] = nil end
    self:PaintPower(true)
    if self.words then self:Paint(self.words) end
end

-- bar:Snap(): Apply again when the physical pixel moved (a UI scale or a
-- display change); a compare otherwise.
function Bar:Snap()
    if not self.look then return end
    local e = UI.px and UI.px(1, self.host) or 1
    if e ~= self.px then self:Apply(self.look) end
end

--------------------------------------------------------------------------------
-- Paint: text and colour only
--------------------------------------------------------------------------------
local function Write(self, kind, text)
    if text == nil then text = "" end
    if self.wrote[kind] ~= text then
        self.texts[kind]:SetText(text)
        self.wrote[kind] = text
    end
end

-- bar:Paint(words): ClockWords.Build's `out`. Kept for Apply and the power
-- path's refusals (the model's words).
function Bar:Paint(words)
    if type(words) ~= "table" then return end
    self.words = words
    local look = self.look
    if not look or self.msgOn then return end
    local texts = look.texts
    for i = 1, #CB.KINDS do
        local kind = CB.KINDS[i]
        local t = texts[kind]
        if t and t.on and not (IS_POWER[kind] and self.byPower[kind]) then
            local s = words[kind]
            Write(self, kind, s and s.text)
            if kind == "time" then
                local tone = (s and s.tone) or "text"
                if tone ~= self.tone then
                    self.tone = tone
                    local r, g, b = ToneRGB(tone, t.colour)
                    self.texts.time:SetTextColor(r, g, b)
                    local c = self.colours.time
                    if c then c[1], c[2], c[3] = r, g, b end
                end
            end
        end
    end
end

-- bar:PaintPower(withMax): the game's pool into the bar, and each shown power
-- text drawn by the game; a refusal draws the model's words from the last
-- Paint and marks the kind modelled (the hover says so, T144 S1).
function Bar:PaintPower(withMax)
    local d = self.draw
    local bar = self.bar
    if withMax and type(d.poolMax) == "function" then pcall(d.poolMax, bar) end
    if type(d.pool) == "function" then pcall(d.pool, bar) end
    local look = self.look
    if not look or self.msgOn then return end
    local words = self.words
    for i = 1, #CB.POWER_KINDS do
        local kind = CB.POWER_KINDS[i]
        local t = look.texts[kind]
        if t and t.on then
            local drawn = false
            if type(d.powerText) == "function" then
                local okP, res = pcall(d.powerText, self.texts[kind], kind)
                drawn = okP and res == true
            end
            if drawn then
                self.byPower[kind] = true
                self.wrote[kind] = CB.POWER_WORDS
                self.modelled[kind] = false
            else
                self.byPower[kind] = false
                local s = words and words[kind]
                if self.wrote[kind] == CB.POWER_WORDS then self.wrote[kind] = nil end
                Write(self, kind, s and s.text)
                self.modelled[kind] = (words and words.modelled and words.modelled[kind]) == true
            end
        else
            self.byPower[kind] = false
            self.modelled[kind] = false
        end
    end
end

-- bar:Modelled() -> the words of the first power text drawn from the model
-- (for the hover), or nil.
function Bar:Modelled()
    for _, kind in ipairs(CB.POWER_KINDS) do
        if self.modelled[kind] then
            local s = self.words and self.words[kind]
            return s and s.text or kind
        end
    end
    return nil
end

-- bar:Message(text, r, g, b): one centred line instead of the texts (the
-- preview's "SpellTuner - drag me"); nil ends it and puts the texts back.
-- The line and the bar are untouched.
function Bar:Message(text, r, g, b)
    if text ~= nil then
        if self.msgText ~= text then
            self.msg:SetText(text)
            self.msgText = text
        end
        if r then self.msg:SetTextColor(r, g, b) end
        if not self.msgOn then
            self.msgOn = true
            self.msg:Show()
            for _, kind in ipairs(CB.KINDS) do self.texts[kind]:Hide() end
        end
        return
    end
    if not self.msgOn then return end
    self.msgOn = false
    self.msg:Hide()
    local texts = self.look and self.look.texts or {}
    for _, kind in ipairs(CB.KINDS) do
        if texts[kind] and texts[kind].on then self.texts[kind]:Show() end
    end
    self:PaintPower(false)
    if self.words then self:Paint(self.words) end
end

function Bar:Pulse()
    self.pulse:Play()
end

--------------------------------------------------------------------------------
-- The driver's step (P4): one compare when idle
--------------------------------------------------------------------------------
function Bar:Step(now)
    local e
    if self.lineOn then
        local fn = self.draw.fsrEnd
        if type(fn) == "function" then
            local ok, v = pcall(fn)
            if ok and type(v) == "number" then e = v end
        end
    end
    if e and type(now) == "number" and now < e then
        local left = e - now
        if left > CB.RULE then left = CB.RULE end
        local x = self.barW * (CB.RULE - left) / CB.RULE
        local line, back, bar = self.line, self.lineBack, self.bar
        line:ClearAllPoints()
        line:SetPoint("CENTER", bar, "LEFT", x, 0)
        back:ClearAllPoints()
        back:SetPoint("CENTER", bar, "LEFT", x, 0)
        self.lineX = x
        if not self.lineShown then
            line:Show()
            back:Show()
            self.lineShown = true
        end
    elseif self.lineShown then
        self.line:Hide()
        self.lineBack:Hide()
        self.lineShown = false
        self.lineX = nil
    end
end

--------------------------------------------------------------------------------
-- Drawn: the test snapshot, from this file's own writes
--------------------------------------------------------------------------------
local function Copy3(c) if c then return { c[1], c[2], c[3], c[4] } end return nil end

function Bar:Drawn()
    local look = self.look or { texts = {} }
    local out = { text = {}, host = { w = self.size and self.size[1], h = self.size and self.size[2] } }
    for _, kind in ipairs(CB.KINDS) do
        local t = look.texts[kind]
        local on = t and t.on and not self.msgOn or false
        local f, p = self.fonts[kind], self.points[kind]
        local words = self.wrote[kind]
        out.text[kind] = {
            shown = on and true or false,
            words = on and words or nil,
            face = f and f[1], size = f and f[2], flags = f and f[3], shadow = f and f[4],
            point = p and table.concat({ p[1], p[2], tostring(p[3]), tostring(p[4]) }, " ") or nil,
            colour = on and Copy3(self.colours[kind]) or nil,
        }
    end
    out.bar = { shown = true, w = self.size and self.size[1], h = self.size and self.size[2],
        texture = self.texPath, colour = Copy3(self.fillRGB), alpha = 1 }
    out.back = { colour = Copy3(self.backRGBA), shown = true }
    out.edge = { shown = self.edgeShown == true }
    out.masks = { file = self.maskFile }
    out.game = self.gameOn == true
    out.line = { shown = self.lineShown == true, x = self.lineX, on = self.lineOn }
    out.msg = self.msgOn and self.msgText or nil
    out.insets = self.insets and { self.insets[1], self.insets[2] } or nil
    return out
end
