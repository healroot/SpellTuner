-- T93 (docs/SPEC-next.md 2.4 and 7.1, K2 of docs/research/next/R-clock.md):
-- the clock's RENDERER, on both lines. Engine/ClockFace.lua says what the clock
-- says (a pure face, cut into pieces by ClockFace.Segments); this file draws a
-- face into a frame the line owns -- the TBC widget (UI/Widget.lua) and the
-- Forever clock (UI/Clock_Forever.lua) each build one view inside their own
-- frame and hand it a face every paint.
--
-- What it draws today (layout "line", L1):
--   * three font strings at FIXED places (F2, decision 14; DECISIONS "Widget
--     text left-anchored ... centred text slides when the digit count
--     changes"): the label from the left edge in the kit's font, the value
--     and its arrow at a fixed x in the kit's number font, the secondary
--     segment right-aligned to the right edge -- so when "OOM 59s" becomes
--     "OOM 1:00" or "OOM >10m" only the value's own digits move;
--   * each piece in its tone's colour (F1, decision 16: TBC's literals,
--     ClockFace.HEX, on both lines; a look's `colors` may re-tint them), the
--     arrow in its own tone where it differs;
--   * a message line (the unlock / "Show now" preview's words), centred where
--     T82 put the one string, drawn instead of the pieces;
--   * the pulse (F5): one animation, MD:Alert's and the once-per-fight flash
--     under 30 s, played by whichever line owns the frame.
-- The value's fixed x is the label slot's width: the widest label the line
-- draws (`look.labelSample`, "FULL" on TBC, "~FULL" on Forever) measured in the
-- label's own font, plus a gap. It is measured again at each paint and the
-- value re-anchored ONLY when that width changed (a font offset, a font that
-- loaded late), never because the words did.
--
-- What it never does: Show / Hide the frame it draws into (each line keeps
-- the single visibility owner, CLAUDE.md), read a client value (the face is
-- plain; the Forever pool's bar is the line's, drawn by MD.API.DrawUnitPower),
-- or read MD.db (the line passes the look). Layouts (Compact, Bar) and the
-- bar sources are T98's; the ring T104's.
local _, MD = ...
local UI = MD.UI

MD.ClockView = MD.ClockView or {}
local CV = MD.ClockView

CV.INSET = 8      -- the label's and the secondary's distance from the frame's edges
CV.TOP = -4       -- the text row, from the frame's top (T82's)
CV.GAP = 6        -- between the label slot and the value

local View = {}
View.__index = View

local function Measure(fs, text)
    fs:SetText(text)
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or w ~= w then w = 0 end
    return math.ceil(w)
end

-- MD.ClockView.Build(parent, look) -> view. `parent` is the line's frame;
-- `look` (optional): labelSample, colors (tone -> "rrggbb"), show (rest, cd).
function CV.Build(parent, look)
    local v = setmetatable({ parent = parent, look = look or {} }, View)

    v.label = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    v.label:SetJustifyH("LEFT")
    v.label:SetPoint("TOPLEFT", parent, "TOPLEFT", CV.INSET, CV.TOP)

    -- the label slot is measured on a font string of the label's font that is
    -- never shown, so a measure never flashes on screen
    v.probe = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    v.probe:Hide()

    v.value = parent:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    v.value:SetJustifyH("LEFT")
    v.valueX = CV.INSET + Measure(v.probe, v.look.labelSample or "FULL") + CV.GAP
    v.value:SetPoint("TOPLEFT", parent, "TOPLEFT", v.valueX, CV.TOP)

    v.second = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    v.second:SetJustifyH("RIGHT")
    v.second:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CV.INSET, CV.TOP)

    v.msg = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    v.msg:SetPoint("TOP", parent, "TOP", 0, CV.TOP)
    v.msg:SetText("")
    v.msg:Hide()

    -- the pulse: four quarter-second fades (UI/Widget.lua's since v0.1)
    local pulse = parent:CreateAnimationGroup()
    for i, dir in ipairs({ 1, -1, 1, -1 }) do
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(dir > 0 and 1 or 0.2)
        a:SetToAlpha(dir > 0 and 0.2 or 1)
        a:SetDuration(0.25)
        a:SetOrder(i)
    end
    v.pulse = pulse
    return v
end

-- The value's place again, only when the label slot's width moved.
function View:Layout()
    local x = CV.INSET + Measure(self.probe, self.look.labelSample or "FULL") + CV.GAP
    if x ~= self.valueX then
        self.valueX = x
        self.value:ClearAllPoints()
        self.value:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, CV.TOP)
    end
end

local function Put(fs, text, tone, colors)
    if text == nil or text == "" then
        fs:SetText("")
        fs:Hide()
        return
    end
    fs:SetText(text)
    fs:SetTextColor(MD.ClockFace.ToneRGB(tone, colors))
    fs:Show()
end

-- view:Paint(face, look): the face's pieces, each in its tone. `look`
-- replaces the build's (the line's switches may have changed); nil keeps it.
-- A face that is not a table draws the warm-up's "OOM ..." -- the TBC
-- widget's words before its first state.
function View:Paint(face, look)
    if look then self.look = look end
    local CF = MD.ClockFace
    local segs = CF.Segments(face, self.look)
        or CF.Segments({ mode = "warmup", label = "OOM", known = "pending", tone = "muted" }, self.look)
    local colors = self.look.colors
    self:Layout()
    self.msg:SetText("")
    self.msg:Hide()

    Put(self.label, segs.label.text, segs.label.tone, colors)
    local val = segs.value
    if val then
        local text = val.text
        if val.arrow then
            if val.arrowTone and val.arrowTone ~= val.tone then
                text = text .. " " .. CF.ToneHex(val.arrowTone, colors) .. val.arrow .. "|r"
            else
                text = text .. " " .. val.arrow
            end
        end
        Put(self.value, text, val.tone, colors)
    else
        Put(self.value, nil)
    end
    if segs.second then
        Put(self.second, segs.second.text, segs.second.tone, colors)
    else
        Put(self.second, nil)
    end
    self.segs = segs
end

-- view:Message(text, r, g, b): one centred line instead of the pieces (the
-- preview's "SpellTuner - drag me", in the colour the line passes).
function View:Message(text, r, g, b)
    for _, fs in ipairs({ self.label, self.value, self.second }) do
        fs:SetText("")
        fs:Hide()
    end
    self.msg:SetText(text or "")
    if r then self.msg:SetTextColor(r, g, b) end
    self.msg:Show()
    self.segs = nil
end

-- view:Text(): the words as drawn, plain -- the message, or the pieces joined
-- as ClockFace.JoinSegments joins them.
function View:Text()
    if self.msg:IsShown() then return self.msg:GetText() or "" end
    return MD.ClockFace.JoinSegments(self.segs)
end

function View:Pulse()
    self.pulse:Play()
end
