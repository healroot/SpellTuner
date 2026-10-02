-- tools/run.sh [--flavour tbc|forever] tools/clockui.lua [--print]
--
-- T98 (docs/SPEC-next.md 7.2-7.3, section 11 row T98; K3 of
-- docs/research/next/R-clock.md; decisions 13 and 15): the clock's LAYOUTS and
-- its look, drawn by UI/ClockView.lua into each line's own frame (TBC
-- UI/Widget.lua, Forever UI/Clock_Forever.lua). The whole TOC of the flavour
-- is loaded -- TBC's UI files included (the harness drops them) -- with the
-- stub's geometry on (S.Geometry(true): points kept, a deterministic text
-- metric that follows the font size), so where every piece of the clock sits
-- can be computed and compared with the frame it is drawn in.
--
-- T115 (clock v2, docs/tasks/T115-clock-bars-frame.md; docs/mockups/clock-v2.html
-- C2-C4, C6): mana and the five-second rule together, in three designs
-- (Join: stacked -- the default --, veil, chip), per layout under
-- bars.<layout>; the frame's width / height / scale per layout with a measured
-- minimum; the 5SR marks placed by time alone; F1's step driving the strip and
-- the veil every frame. Held here, on both flavours:
--   * the layouts (line, compact, bar): CV.SetLayout saves db.clockLook.layout
--     and fires CLOCK_LOOK once, an unknown layout is refused;
--   * the defaults: every layout draws the mana bar over a 3-px strip
--     (stacked, mana over 5SR, green after); Line 180 x 32 (text row, mana 4,
--     a 1-px gap, the strip 3), Compact 72 x 46 (at least its measure), Bar
--     200 x 22;
--   * each layout x each join x each `show` x each SAMPLES face FITS its frame
--     at font offsets -2..+2 (every piece inside, no overlap, no text over a
--     bar beside it), and a second round builds no region;
--   * Height gives its pixels to the mana bar (the text unmoved, the strip
--     kept), Width stretches both bars (the secondary at the right edge), a
--     size under the layout's measured minimum stops there and is named
--     (View:Minimum), Scale is SetScale with the clock's centre kept;
--   * stacked, veil and chip mid-rule and after it (green / empty), the
--     order, the strip's thickness, show fsr / none;
--   * the smooth step moves the strip and the veil every frame and is gone
--     at the rule's end, on a join or show change and under FillBar;
--   * a style's barFill tints the mana bar only; colors.manaBar = tone;
--     after = tick (TBC: RM:RegenTick's mark; Forever refused); Mana from the
--     model (Forever; refused on TBC); the textures (TBC; Forever flat only);
--     the ring rule;
--   * the frame's visibility has one owner (counted), a switch keeps it;
--   * the dump line names the new keys;
--   * Forever, under the stub's forever profile: every layout x join x show x
--     mana-from paints in a fight, only the mana bar holds the secret and
--     nothing reads it back; TBC: the same matrix paints without raising.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."
local printing = false
for i = 2, #arg do if arg[i] == "--print" then printing = true end end

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: clockui.lua runs under tbc, forever only")
    os.exit(3)
end
local forever = flavour == "forever"

local T = dofile(here .. "/lib/t.lua")
local check = T.check

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = root
S.flavour = flavour

local MD = {}
local toc = "SpellTuner_TBC.toc"
if forever then
    S.UseProfile("forever")
    toc = "SpellTuner_Mainline.toc"
end
S.Geometry(true)
local files = {}
for _, rel in ipairs(S.TocFiles(toc)) do
    -- Integrations/ needs a host addon (tools/surfacecheck.lua's); not the clock's business
    if rel:sub(1, 13) ~= "Integrations/" then files[#files + 1] = rel end
end
S.loadedFiles = files
S.Load(files, "SpellTuner", MD)
S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")

local UI = MD.UI
local CV = MD.ClockView or {}
local CF = MD.ClockFace or {}
local W = MD.ClockWidget or {}
local frame = W.frame or (forever and _G.SpellTunerClock or _G.SpellTunerWidget)
local function View() return W.view or (frame and frame.view) or (MD.Clock and MD.Clock.view) end

-- the first run's 60-s placing preview (TBC unlocks the clock at a first
-- login) ended, the clock locked: what the visibility checks start from
if MD.db then MD.db.locked = true end
if W.Preview then pcall(W.Preview, W, 0) end

-- A check whose body may raise (on the parent, before T115, much of what it
-- calls does not exist): the raise is the failure, never the suite's end.
local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end

local function Near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < (eps or 1e-6) end
local function Same(c, r, g, b, a)
    return type(c) == "table" and Near(c[1], r) and Near(c[2], g) and Near(c[3], b) and (a == nil or Near(c[4], a))
end
local function C(c)
    if type(c) ~= "table" then return tostring(c) end
    local out = {}
    for i = 1, 4 do out[i] = c[i] == nil and "-" or string.format("%.3g", c[i]) end
    return table.concat(out, ",")
end
local AMBER, GREEN, BLUE = { 1, 0.67, 0.2 }, { 0.2, 1, 0.4 }, { 0.3, 0.6, 1 }
local function Is(c, rgb) return Same(c, rgb[1], rgb[2], rgb[3]) end

-- The faces as this line draws them: SAMPLES (TBC-shaped), with Forever's
-- marks on Forever (the "~" before the label, one colour, "0:15").
local function Faces()
    local out = {}
    for _, s in ipairs(CF.SAMPLES or {}) do
        local f = {}
        for k, v in pairs(s.face) do f[k] = v end
        if forever then f.modelled, f.mono, f.timeFmt = true, true, "mss" end
        out[#out + 1] = { key = s.key, face = f }
    end
    return out
end

local function Tick(n) for _ = 1, n or 1 do S.Tick(0.5) end end

--------------------------------------------------------------------------------
-- Where a region sits, from its points, in the frame's own units with the
-- frame's bottom-left at 0, 0. A font string is as wide and as tall as its
-- text (the stub's metric); a texture or a frame as its size.
--------------------------------------------------------------------------------
local function PointXY(rect, p)
    local x = p:find("LEFT") and rect.l or (p:find("RIGHT") and rect.r) or (rect.l + rect.r) / 2
    local y = p:find("TOP") and rect.t or (p:find("BOTTOM") and rect.b) or (rect.b + rect.t) / 2
    return x, y
end
local function Size(r)
    if r.kind == "FontString" then return r:GetStringWidth(), r:GetStringHeight() end
    return r:GetWidth(), r:GetHeight()
end
local function Rect(r, depth)
    depth = depth or 0
    if r == nil then return nil end
    if r == frame then return { l = 0, b = 0, r = frame:GetWidth(), t = frame:GetHeight() } end
    if depth > 8 then return nil end
    local pts = r.points or {}
    if #pts == 0 then return nil end
    if #pts >= 2 then
        local box = {}
        for _, pt in ipairs(pts) do
            local rr = Rect(pt[2] or r.parentFrame, depth + 1)
            if not rr then return nil end
            local x, y = PointXY(rr, pt[3] or pt[1])
            x, y = x + (pt[4] or 0), y + (pt[5] or 0)
            if pt[1]:find("LEFT") then box.l = x end
            if pt[1]:find("RIGHT") then box.r = x end
            if pt[1]:find("TOP") then box.t = y end
            if pt[1]:find("BOTTOM") then box.b = y end
        end
        if box.l and box.r and box.t and box.b then return box end
        return nil
    end
    local p, rel, rp, x, y = pts[1][1], pts[1][2], pts[1][3], pts[1][4], pts[1][5]
    local rr = Rect(rel or r.parentFrame, depth + 1)
    if not rr then return nil end
    local ax, ay = PointXY(rr, rp or p)
    ax, ay = ax + (x or 0), ay + (y or 0)
    local w, h = Size(r)
    local l = p:find("LEFT") and ax or (p:find("RIGHT") and (ax - w)) or (ax - w / 2)
    local t = p:find("TOP") and ay or (p:find("BOTTOM") and (ay + h)) or (ay + h / 2)
    return { l = l, r = l + w, t = t, b = t - h }
end
local EPS = 0.001
local function Inside(a, b)
    return a.l >= b.l - EPS and a.r <= b.r + EPS and a.b >= b.b - EPS and a.t <= b.t + EPS
end
local function Overlap(a, b)
    return a.l < b.r - EPS and b.l < a.r - EPS and a.b < b.t - EPS and b.b < a.t - EPS
end
local function R(r) return r and string.format("[%.1f..%.1f x %.1f..%.1f]", r.l, r.r, r.b, r.t) or "nil" end
local function Shown(r) return r ~= nil and r:IsShown() end

-- The bar regions shown now: the mana bar, the strip, the chip.
local function Bars(v)
    local out = {}
    for _, k in ipairs({ "bar", "strip", "chip" }) do
        if Shown(v[k]) then out[#out + 1] = { k = k, r = Rect(v[k]) } end
    end
    return out
end

-- What is wrong with the view as painted now: nil when every shown piece
-- fits, else a sentence.
local function Misfit(v, layout)
    local fr = Rect(frame)
    local pieces = {}
    for _, k in ipairs({ "label", "value", "second" }) do
        local fs = v[k]
        if fs and fs:IsShown() and (fs:GetText() or "") ~= "" then
            local r = Rect(fs)
            if not r then return k .. " has no place" end
            pieces[#pieces + 1] = { k = k, r = r, text = fs:GetText() }
        end
    end
    if #pieces == 0 then return "nothing drawn" end
    for _, p in ipairs(pieces) do
        if not Inside(p.r, fr) then
            return string.format("%s %q %s outside the frame %s", p.k, p.text, R(p.r), R(fr))
        end
    end
    for i = 1, #pieces do
        for j = i + 1, #pieces do
            if Overlap(pieces[i].r, pieces[j].r) then
                return string.format("%s %s overlaps %s %s", pieces[i].k, R(pieces[i].r), pieces[j].k, R(pieces[j].r))
            end
        end
    end
    local bars = Bars(v)
    for _, b in ipairs(bars) do
        if not b.r then return "the " .. b.k .. " has no place" end
        if not Inside(b.r, fr) then return "the " .. b.k .. " " .. R(b.r) .. " outside the frame " .. R(fr) end
    end
    for i = 1, #bars do
        for j = i + 1, #bars do
            if Overlap(bars[i].r, bars[j].r) then
                return string.format("the %s %s overlaps the %s %s", bars[i].k, R(bars[i].r), bars[j].k, R(bars[j].r))
            end
        end
    end
    for _, back in ipairs({ "barBack", "stripBack" }) do
        if Shown(v[back]) then
            local bk = Rect(v[back])
            if not bk then return back .. " has no place" end
            if not Inside(bk, fr) then return back .. " " .. R(bk) .. " outside the frame " .. R(fr) end
        end
    end
    for _, p in ipairs(pieces) do
        for _, b in ipairs(bars) do
            -- the bar layout's text sits IN its mana bar (or the strip in its
            -- place, show = fsr); everywhere else text and bars sit apart
            local inBar = layout == "bar" and (b.k == "bar" or (b.k == "strip" and not Shown(v.bar)))
            if not inBar and Overlap(p.r, b.r) then return p.k .. " " .. R(p.r) .. " over the " .. b.k .. " " .. R(b.r) end
        end
        if layout ~= "bar" then
            for _, back in ipairs({ "barBack", "stripBack" }) do
                if Shown(v[back]) and Overlap(p.r, Rect(v[back])) then
                    return p.k .. " " .. R(p.r) .. " over the " .. back .. " " .. R(Rect(v[back]))
                end
            end
        end
    end
    return nil
end

-- Every Show / Hide on the frame, with the name of the function that called it.
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

-- CLOCK_LOOK, counted
local looks = 0
MD:RegisterCallback("CLOCK_LOOK", function() looks = looks + 1 end)

local function Paint(face)
    local v = View()
    v:Paint(face)
    v:PaintBar(GetTime())
    return v
end

local LAYOUTS = { "line", "compact", "bar" }
local JOINS = { "stacked", "veil", "chip" }
local SHOWS = { "both", "mana", "fsr", "none" }

-- the line's own five-second rule: the model's last priced spend on
-- Forever, the regen model's end on TBC
local function RuleFor(seconds)
    if forever then
        MD.Pool.model.lastSpend = GetTime() - (5 - seconds)
    else
        MD.Regen.fsrEnd = GetTime() + seconds
    end
end
local function RuleOff()
    if forever then MD.Pool.model.lastSpend = -1e9 else MD.Regen.fsrEnd = 0 end
end
local function Bars_(layout, key, value) return CV.Set("bars." .. layout .. "." .. key, value) end
local function Reset() CV.ResetToStyle(); CV.SetLayout("line") end

local faces = Faces()
local face1 = faces[1] and faces[1].face

--------------------------------------------------------------------------------
T.section("the layouts (" .. flavour .. ")")
--------------------------------------------------------------------------------
Try("line, compact and bar; SetLayout saves and fires CLOCK_LOOK once; an unknown one refused", function()
    local listed = table.concat(CV.LAYOUTS or {}, ",") == "line,compact,bar"
    local n0 = looks
    local okC = CV.SetLayout("compact")
    local saved = MD.db.clockLook and MD.db.clockLook.layout
    local fired = looks - n0
    local n1 = looks
    local okBad, why = CV.SetLayout("hexagon")
    local unchanged = MD.db.clockLook.layout == "compact" and looks == n1
    CV.SetLayout("line")
    return listed and okC == true and saved == "compact" and fired == 1 and okBad == false
        and type(why) == "string" and why:find("line", 1, true) ~= nil and unchanged,
        string.format("listed %s, saved %s, fired %d, refused %s (%s)", tostring(listed), tostring(saved), fired,
            tostring(okBad == false), tostring(why))
end)

-- 1. the defaults
for _, layout in ipairs(LAYOUTS) do
    Try("defaults: " .. layout .. " draws mana over a 3-px strip, stacked, green after", function()
        Reset()
        CV.SetLayout(layout)
        RuleOff()
        local v = Paint(face1)
        local b = v.look.bars or {}
        local d = CV.BARS_DEFAULT or {}
        local resolved = b.show == "both" and b.join == "stacked" and b.order == "manaOver" and b.mana == "game"
            and b.fsr == 3 and b.after == "green" and b.texture == "flat"
            and d.show == "both" and d.join == "stacked" and d.fsr == 3 and d.after == "green"
        local mr, sr = Rect(v.bar), Rect(v.strip)
        local drawn = Shown(v.bar) and Shown(v.strip) and not Shown(v.chip) and not Shown(v.veil)
            and mr ~= nil and sr ~= nil and Near(sr.t - sr.b, 3) and Near(mr.b, sr.t + 1)
            and Is(v.strip.barColor, GREEN) and Near(v.strip.value, 5)
        return resolved and drawn, string.format("bars %s/%s/%s/%s, mana %s strip %s",
            tostring(b.show), tostring(b.join), tostring(b.order), tostring(b.fsr), R(mr), R(sr))
    end)
end

Try("sizes: Line 180 x 32 (text, mana 4, gap 1, strip 3), Compact 72 x 46 (or its measure), Bar 200 x 22", function()
    Reset()
    local v = Paint(face1)
    local mr, sr, lr = Rect(v.bar), Rect(v.strip), Rect(v.label)
    local line = frame:GetWidth() == 180 and frame:GetHeight() == 32 and v.bar:GetWidth() == 160
        and v.bar:GetHeight() == 4 and v.strip:GetWidth() == 160 and v.strip:GetHeight() == 3
        and mr and sr and lr and Near(sr.b, 5) and Near(sr.l, 10) and Near(mr.b, 9) and lr.b >= mr.t + 1
    local lineS = string.format("line %sx%s mana %s strip %s", tostring(frame:GetWidth()),
        tostring(frame:GetHeight()), R(mr), R(sr))
    CV.SetLayout("compact")
    Paint(face1)
    local mw = v.Minimum and select(1, v:Minimum()) or 0
    local compact = frame:GetHeight() == 46 and frame:GetWidth() == math.max(72, mw)
        and CV.LAYOUT.compact.width == 72 and CV.LAYOUT.compact.height == 46
    local compactS = string.format("compact %sx%s (min w %s)", tostring(frame:GetWidth()), tostring(frame:GetHeight()),
        tostring(mw))
    CV.SetLayout("bar")
    Paint(face1)
    local bar = frame:GetWidth() == 200 and frame:GetHeight() == 22 and v.bar:GetHeight() == 16
        and v.strip:GetHeight() == 3
    local barS = string.format("bar %sx%s mana %s", tostring(frame:GetWidth()), tostring(frame:GetHeight()),
        tostring(v.bar:GetHeight()))
    Reset()
    return line and compact and bar, lineS .. "; " .. compactS .. "; " .. barS
end)

-- 2. every face fits every layout x join x show at every font offset
local regionsAfterFirstRound
for _, layout in ipairs(LAYOUTS) do
    Try("fits: " .. layout .. " -- every join x show x SAMPLES face at font offsets -2..+2", function()
        CV.ResetToStyle()
        CV.SetLayout(layout)
        local v = View()
        local n, bad = 0, nil
        RuleFor(3)
        for _, join in ipairs(JOINS) do
            for _, show in ipairs(SHOWS) do
                Bars_(layout, "join", join)
                Bars_(layout, "show", show)
                for offset = -2, 2 do
                    UI.ApplyFonts(offset)
                    for _, f in ipairs(faces) do
                        Paint(f.face)
                        n = n + 1
                        local why = Misfit(v, layout)
                        if why and not bad then
                            bad = string.format("%s/%s offset %+d, %s: %s", join, show, offset, f.key, why)
                        end
                    end
                end
            end
        end
        UI.ApplyFonts(0)
        RuleOff()
        CV.ResetToStyle()
        return bad == nil and n == 3 * 4 * 5 * #faces and n > 0 and v.look.layout == layout,
            bad or string.format("%d paints", n)
    end)
end
regionsAfterFirstRound = #S.allFrames

Try("a second round of switches builds no region (one pool per frame)", function()
    for _, layout in ipairs(LAYOUTS) do
        CV.SetLayout(layout)
        for _, join in ipairs(JOINS) do
            Bars_(layout, "join", join)
            Paint(face1)
        end
    end
    Reset()
    Paint(face1)
    return #S.allFrames == regionsAfterFirstRound, string.format("%d -> %d regions", regionsAfterFirstRound,
        #S.allFrames)
end)

--------------------------------------------------------------------------------
T.section("the frame: height, width, the minimum, scale")
--------------------------------------------------------------------------------
-- 3. Height's pixels go to the mana bar
Try("height: Line 32 -> 44 gives the mana bar 12 px, moves no text; Bar 22 -> 30 grows its bar; the strip kept", function()
    Reset()
    local v = Paint(face1)
    local function TextTops()
        local out = {}
        for _, k in ipairs({ "label", "value", "second" }) do
            local r = Rect(v[k])
            out[#out + 1] = r and (frame:GetHeight() - r.t) or -1
        end
        return table.concat(out, ",")
    end
    local m0, tops0 = v.bar:GetHeight(), TextTops()
    CV.Set("frame.line.h", 44)
    Paint(face1)
    local line = frame:GetHeight() == 44 and v.bar:GetHeight() == m0 + 12 and v.strip:GetHeight() == 3
        and TextTops() == tops0 and Misfit(v, "line") == nil
    local lineS = string.format("line mana %s -> %s, text %s -> %s", tostring(m0), tostring(v.bar:GetHeight()),
        tops0, TextTops())
    CV.SetLayout("bar")
    Paint(face1)
    local b0 = v.bar:GetHeight()
    CV.Set("frame.bar.h", 30)
    Paint(face1)
    local bar = b0 == 16 and frame:GetHeight() == 30 and v.bar:GetHeight() == 24 and v.strip:GetHeight() == 3
        and Misfit(v, "bar") == nil
    Reset()
    return line and bar, lineS .. string.format("; bar %s -> %s", tostring(b0), tostring(v.bar:GetHeight()))
end)

-- 4. Width stretches both bars
Try("width: Line 180 -> 300 stretches both bars; the secondary stays at the right edge", function()
    Reset()
    local v = Paint(faces[7] and faces[7].face or face1) -- "rest": a secondary segment
    CV.Set("frame.line.w", 300)
    Paint(faces[7] and faces[7].face or face1)
    local sr = Rect(v.second)
    local okW = frame:GetWidth() == 300 and v.bar:GetWidth() == 280 and v.strip:GetWidth() == 280
        and sr ~= nil and Near(sr.r, 300 - CV.INSET)
    Reset()
    return okW, string.format("frame %s, bars %s / %s, second %s", tostring(frame:GetWidth()),
        tostring(v.bar:GetWidth()), tostring(v.strip:GetWidth()), R(sr))
end)

-- 5. the measured minimum
Try("minimum: a size under it stops at it and is named; View:Minimum() is the measure; a bigger font raises it", function()
    Reset()
    local v = Paint(face1)
    local mw, mh = v:Minimum()
    CV.Set("frame.line.w", 100)
    CV.Set("frame.line.h", 26)
    Paint(face1)
    local stopped = frame:GetWidth() == mw and frame:GetHeight() == mh and mw > 100 and mh > 26
    local why = v.look.refused and v.look.refused["frame.line.w"]
    local whyH = v.look.refused and v.look.refused["frame.line.h"]
    local named = type(why) == "string" and why == "under this layout's minimum (" .. mw .. ")"
        and type(whyH) == "string" and whyH:find("minimum", 1, true) ~= nil
    UI.ApplyFonts(2)
    Paint(face1)
    local mw2, mh2 = v:Minimum()
    UI.ApplyFonts(0)
    Paint(face1)
    -- no secondary (rest and cooldown both off): the minimum drops by the
    -- secondary's room (C2: 100 x 30 with no secondary)
    local sh = v.look.show
    local rest0, cd0 = sh.rest, sh.cd
    sh.rest, sh.cd = false, false
    Paint(face1)
    local mwNo, mhNo = v:Minimum()
    local dropped = CV.HasSecondary(v.look) == false and mwNo < mw and mwNo <= 110 and mhNo == mh
        and frame:GetWidth() == mwNo and Misfit(v, "line") == nil
    sh.rest, sh.cd = rest0, cd0
    Paint(face1)
    local back = select(1, v:Minimum()) == mw
    Reset()
    return stopped and named and mw2 > mw and mh2 >= mh and dropped and back,
        string.format("min %sx%s, frame %sx%s, refused %q, +2: %sx%s, no secondary %sx%s, back %s", tostring(mw),
            tostring(mh), tostring(frame:GetWidth()), tostring(frame:GetHeight()), tostring(why), tostring(mw2),
            tostring(mh2), tostring(mwNo), tostring(mhNo), tostring(back))
end)

-- 6. Scale: SetScale per layout, the centre kept
local function Centre()
    local es = frame:GetEffectiveScale()
    return (frame:GetLeft() + frame:GetWidth() / 2) * es, (frame:GetTop() - frame:GetHeight() / 2) * es
end
Try("scale: SetScale per layout (50-200 %), the clock's centre kept across a change ("
        .. (forever and "db.clock.point" or "db.pos") .. ")", function()
    Reset()
    Tick(1)
    local x0, y0 = Centre()
    local s0 = frame:GetScale()
    CV.Set("frame.line.scale", 150)
    local x1, y1 = Centre()
    local s1 = frame:GetScale()
    CV.Set("frame.line.scale", 50)
    local x2, y2 = Centre()
    local refused = CV.Set("frame.line.scale", 40) == false and CV.Set("frame.line.scale", 201) == false
    CV.SetLayout("compact")
    local sc = frame:GetScale()
    CV.SetLayout("line")
    local back = frame:GetScale()
    local saved = forever and MD.db.clock.point or MD.db.pos
    CV.Set("frame.line.scale", nil)
    local x3, y3 = Centre()
    Reset()
    return Near(s0, 1) and Near(s1, 1.5) and Near(sc, 1) and Near(back, 0.5) and refused
        and Near(x1, x0, 0.01) and Near(y1, y0, 0.01) and Near(x2, x0, 0.01) and Near(y2, y0, 0.01)
        and Near(x3, x0, 0.01) and Near(y3, y0, 0.01) and type(saved) == "table",
        string.format("scales %s %s compact %s back %s; centre %.2f,%.2f -> %.2f,%.2f -> %.2f,%.2f -> %.2f,%.2f",
            tostring(s0), tostring(s1), tostring(sc), tostring(back), x0, y0, x1 or -1, y1 or -1, x2 or -1,
            y2 or -1, x3 or -1, y3 or -1)
end)

--------------------------------------------------------------------------------
T.section("the three designs and the five-second rule")
--------------------------------------------------------------------------------
-- 7. Stacked
Try("stacked: mid-rule (3.0 s left) the strip is 2/5 amber; after, full green; after = empty: empty", function()
    Reset()
    RuleFor(3)
    local v = Paint(face1)
    local mid = Near(v.strip.value, 2, 1e-6) and Near(v.strip.maxV, 5) and Is(v.strip.barColor, AMBER)
        and Is(v.bar.barColor, BLUE)
    RuleOff()
    Paint(face1)
    local after = Near(v.strip.value, 5) and Is(v.strip.barColor, GREEN)
    Bars_("line", "after", "empty")
    Paint(face1)
    local empty = Near(v.strip.value, 0) and Shown(v.strip)
    Reset()
    return mid and after and empty, string.format("mid %s (%s), after %s, empty %s", tostring(mid),
        tostring(v.strip.value), tostring(after), tostring(empty))
end)

Try("order: 5SR over mana swaps them; the strip's thickness 1-8 keeps the mana bar the rest", function()
    Reset()
    CV.Set("frame.line.h", 44)
    local v = Paint(face1)
    local m0, s0 = Rect(v.bar), Rect(v.strip)
    Bars_("line", "order", "fsrOver")
    Paint(face1)
    local m1, s1 = Rect(v.bar), Rect(v.strip)
    local swapped = m0 and s0 and m1 and s1 and m0.b > s0.t and s1.b > m1.t
    Bars_("line", "order", nil)
    local sum
    local okT = true
    for _, px in ipairs({ 1, 6, 8 }) do
        Bars_("line", "fsr", px)
        Paint(face1)
        local total = v.bar:GetHeight() + v.strip:GetHeight()
        sum = sum or total
        if v.strip:GetHeight() ~= px or total ~= sum then okT = false end
    end
    local range = Bars_("line", "fsr", 0) == false and Bars_("line", "fsr", 9) == false
    Reset()
    return swapped and okT and range, string.format("swapped %s, thickness %s, range %s", tostring(swapped),
        tostring(okT), tostring(range))
end)

Try("a new spend restarts the strip at 0 at once (amber)", function()
    Reset()
    RuleOff()
    local v = Paint(face1)
    local green = Near(v.strip.value, 5)
    RuleFor(5)
    Paint(face1)
    local restarted = Near(v.strip.value, 0, 1e-6) and Is(v.strip.barColor, AMBER)
    RuleOff()
    Reset()
    return green and restarted, tostring(v.strip.value)
end)

-- 8. The veil
Try("veil: width = barW x remaining / 5 at the bar's right edge; after, a 1-px green top line; empty: none", function()
    Reset()
    for _, layout in ipairs(LAYOUTS) do Bars_(layout, "join", "veil") end
    local bad
    for _, layout in ipairs(LAYOUTS) do
        CV.SetLayout(layout)
        RuleFor(3)
        local v = Paint(face1)
        local pt = v.veil and v.veil.points and v.veil.points[#v.veil.points]
        local mid = Shown(v.veil) and not Shown(v.strip) and Near(v.veil:GetWidth(), v.bar:GetWidth() * 3 / 5, 1e-6)
            and pt and pt[1] == "RIGHT" and pt[2] == v.bar and pt[3] == "RIGHT"
            and Same(v.veil.color, AMBER[1], AMBER[2], AMBER[3], 0.45) and Shown(v.veilEdge)
            and not Shown(v.greenLine)
        RuleOff()
        Paint(face1)
        local after = not Shown(v.veil) and Shown(v.greenLine) and v.greenLine:GetHeight() == 1
            and Is(v.greenLine.color, GREEN)
        Bars_(layout, "after", "empty")
        Paint(face1)
        local empty = not Shown(v.veil) and not Shown(v.greenLine)
        Bars_(layout, "after", nil)
        if not (mid and after and empty) and not bad then
            bad = string.format("%s: mid %s (w %s of %s), after %s, empty %s", layout, tostring(mid),
                tostring(v.veil and v.veil:GetWidth()), tostring(v.bar:GetWidth()), tostring(after), tostring(empty))
        end
    end
    Reset()
    return bad == nil, bad
end)

-- 9. The chip
Try("chip: SetCooldown(lastSpend, 5) once per spend, green after; the label moves 13 px on Line", function()
    Reset()
    local v = Paint(face1)
    local lx0 = Rect(v.label).l
    Bars_("line", "join", "chip")
    -- the stub counts SetCooldown over the view's life (the fits above drew
    -- the chip too): counted from here
    local c0 = v.cd and v.cd.cdCalls or 0
    RuleFor(4)
    local spend = forever and MD.Pool.model.lastSpend or (MD.Regen.fsrEnd - 5)
    Paint(face1)
    Paint(face1)
    S.Tick(0.03)
    local cd = v.cd
    local once = cd ~= nil and cd.cdCalls - c0 == 1 and Near(cd.cdStart, spend, 1e-6) and cd.cdDur == 5
        and Shown(v.chip) and Is(v.chipBg.color, AMBER)
    local moved = Near(Rect(v.label).l, lx0 + 13)
    RuleFor(5)
    Paint(face1)
    local again = cd ~= nil and cd.cdCalls - c0 == 2
    RuleOff()
    Paint(face1)
    local green = Is(v.chipBg.color, GREEN) and Shown(v.chip)
    Reset()
    return once and moved and again and green, string.format("calls %s start %s/%s, moved %s, again %s, green %s",
        tostring(cd and cd.cdCalls), tostring(cd and cd.cdStart), tostring(spend), tostring(moved), tostring(again),
        tostring(green))
end)

-- 10. The smooth step
Try("smooth: the strip and the veil move on each of eight 0.03-s frames between two line paints", function()
    local res = {}
    for _, case in ipairs({ { "line", "stacked" }, { "bar", "veil" } }) do
        Reset()
        CV.SetLayout(case[1])
        Bars_(case[1], "join", case[2])
        RuleFor(4)
        local v = Paint(face1)
        local function Read() if case[2] == "veil" then return -v.veil:GetWidth() end return v.strip.value end
        local prev, moved = Read(), 0
        for _ = 1, 8 do
            S.Tick(0.03)
            local now = Read()
            if type(now) == "number" and type(prev) == "number" and now > prev + 1e-9 then moved = moved + 1 end
            prev = now
        end
        local want = case[2] == "veil" and -(v.bar:GetWidth() * (4 - 8 * 0.03) / 5) or (5 - (4 - 8 * 0.03))
        res[#res + 1] = case[2] .. " " .. moved .. "/8 " .. tostring(Near(prev, want, 1e-6))
        if not (moved == 8 and Near(prev, want, 1e-6)) then res.bad = true end
    end
    RuleOff()
    Reset()
    return not res.bad, table.concat(res, ", ")
end)

Try("smooth: gone at the rule's end, on a join or show change and under FillBar; one function per view", function()
    Reset()
    local v = View()
    RuleFor(0.1)
    Paint(face1)
    local host = v.stepHost
    local fn1 = host and host:GetScript("OnUpdate")
    for _ = 1, 5 do S.Tick(0.03) end
    local ended = host and host:GetScript("OnUpdate") == nil and Near(v.strip.value, 5) and Is(v.strip.barColor, GREEN)
    RuleFor(4)
    Paint(face1)
    local fn2 = v.stepHost and v.stepHost:GetScript("OnUpdate")
    local sameFn = fn1 ~= nil and fn1 == fn2 and fn1 == v.step
    Bars_("line", "join", "chip")
    local offJoin = (v.strip:GetScript("OnUpdate") == nil) and (v.bar:GetScript("OnUpdate") == nil)
    Bars_("line", "join", nil)
    Paint(face1)
    local onAgain = v.stepHost:GetScript("OnUpdate") ~= nil
    Bars_("line", "show", "mana")
    local offShow = (v.strip:GetScript("OnUpdate") == nil) and (v.bar:GetScript("OnUpdate") == nil)
    Bars_("line", "show", nil)
    Paint(face1)
    v:FillBar(1, 0, 0)
    local offFill = (v.strip:GetScript("OnUpdate") == nil) and (v.bar:GetScript("OnUpdate") == nil)
        and Near(v.bar.value, v.bar.maxV) and Is(v.bar.barColor, { 1, 0, 0 }) and Near(v.strip.value, 5)
    RuleOff()
    Reset()
    return fn1 ~= nil and ended and sameFn and offJoin and onAgain and offShow and offFill,
        string.format("installed %s, ended %s, same fn %s, off by join %s, on again %s, off by show %s, fill %s",
            tostring(fn1 ~= nil), tostring(ended), tostring(sameFn), tostring(offJoin), tostring(onAgain),
            tostring(offShow), tostring(offFill))
end)

-- 11. show = fsr / none
Try("show fsr: the strip in the mana bar's place; none: no bar, no strip, no chip", function()
    Reset()
    local v = Paint(face1)
    local mr = Rect(v.bar)
    Bars_("line", "show", "fsr")
    RuleFor(3)
    Paint(face1)
    local sr = Rect(v.strip)
    local fsr = not Shown(v.bar) and Shown(v.strip) and sr and mr and Near(sr.b, Rect(frame).b + 5)
        and Near(sr.t - sr.b, mr.t - mr.b) and Is(v.strip.barColor, AMBER)
    for _, j in ipairs(JOINS) do
        Bars_("line", "join", j)
        Bars_("line", "show", "none")
        Paint(face1)
        if Shown(v.bar) or Shown(v.strip) or Shown(v.chip) or Shown(v.veil) or Shown(v.barBack)
            or Shown(v.stripBack) or Shown(v.greenLine) then fsr = false end
        Bars_("line", "show", "fsr")
    end
    RuleOff()
    Reset()
    return fsr and true or false, string.format("strip %s, mana was %s", R(sr), R(mr))
end)

--------------------------------------------------------------------------------
T.section("colours, the tick, the model, textures, refusals")
--------------------------------------------------------------------------------
Try("UI.Skin(widget, \"clock\"): the frame is registered by the clock role in today's paint", function()
    Reset()
    Paint(face1)
    local rec = UI.skinned and UI.skinned[frame]
    local P = UI.PALETTE
    return rec ~= nil and rec.role == "clock" and Same(frame.bg, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
        and Same(frame.border, P.border[1], P.border[2], P.border[3], P.border[4])
        and Same(View().barBack.color, 0, 0, 0, 1) and Same(View().stripBack.color, 0, 0, 0, 1),
        string.format("role %s, bg %s, edge %s", tostring(rec and rec.role), C(frame.bg), C(frame.border))
end)

-- 12. a style's barFill tints the mana bar only
Try("a style's barFill tints the mana bar only (the strip amber / green); an override wins; Reset and Flat", function()
    local TEST = {
        name = "T115", hint = "clockui's own.", accent = "class",
        roles = { clock = { kind = "pixel", fill = { 0.1, 0.2, 0.3, 1 }, edge = "border",
            bar = { 0.5, 0, 0, 1 }, barFill = { 0, 1, 0, 1 } } },
        needs = {},
    }
    UI.Styles.Register("t115", TEST)
    UI.SetStyle("t115")
    Reset()
    local v = View()
    RuleFor(3)
    Paint(face1)
    local styled = Same(frame.bg, 0.1, 0.2, 0.3, 1) and Same(v.barBack.color, 0.5, 0, 0, 1)
        and Same(v.bar.barColor, 0, 1, 0) and Is(v.strip.barColor, AMBER)
    RuleOff()
    Paint(face1)
    local after = Is(v.strip.barColor, GREEN) and Same(v.bar.barColor, 0, 1, 0)
    CV.Set("panel.fill", { 0.9, 0.8, 0.7, 1 })
    CV.Set("bar.back", { 0, 0, 0.5, 1 })
    CV.Set("colors.manaBar", { 1, 1, 0 })
    Paint(face1)
    local over = Same(frame.bg, 0.9, 0.8, 0.7, 1) and Same(v.barBack.color, 0, 0, 0.5, 1)
        and Same(v.bar.barColor, 1, 1, 0) and Is(v.strip.barColor, GREEN)
    CV.ResetToStyle()
    Paint(face1)
    local reset = Same(frame.bg, 0.1, 0.2, 0.3, 1) and Same(v.barBack.color, 0.5, 0, 0, 1)
        and Same(v.bar.barColor, 0, 1, 0)
    UI.SetStyle("flat")
    Paint(face1)
    local P = UI.PALETTE
    local flat = Same(frame.bg, P.bg[1], P.bg[2], P.bg[3], P.bg[4]) and Same(v.barBack.color, 0, 0, 0, 1)
        and Is(v.bar.barColor, BLUE) and UI.skinned[frame].role == "clock"
    return styled and after and over and reset and flat,
        string.format("styled %s, after %s, over %s, reset %s, flat %s (bar %s)", tostring(styled), tostring(after),
            tostring(over), tostring(reset), tostring(flat), C(v.bar.barColor))
end)

-- 13. colors.manaBar = tone
Try("colors.manaBar = tone: crit red on the mana bar; class: the class colour", function()
    Reset()
    CV.Set("colors.manaBar", "tone")
    local face = { mode = "oom", label = "OOM", value = 12, known = "point", tone = "crit", combat = true,
        timeFmt = "auto", pct = 0.3 }
    if forever then face.modelled, face.mono, face.timeFmt = true, true, "mss" end
    local v = Paint(face)
    local tone = Same(v.bar.barColor, 1, 0x44 / 255, 0x44 / 255)
    CV.Set("colors.manaBar", "class")
    Paint(face)
    local a = UI.classAccent or UI.accent
    local class = Same(v.bar.barColor, a[1], a[2], a[3])
    local refused = CV.Set("colors.manaBar", "source") == false
    Reset()
    return tone and class and refused, string.format("tone %s, class %s, refused %s", C(v.bar.barColor),
        tostring(class), tostring(refused))
end)

-- 14. after = tick
if forever then
    Try("tick: refused on Forever, with its reason; the strip stays green", function()
        local facts = W.facts or {}
        local okB, why, field = CV.BarsOK("line", { after = "tick" }, facts)
        local look = CV.Resolve({ layout = "line", over = { bars = { line = { after = "tick" } } } }, CV.Role(), facts)
        return okB == false and why == CV.TICK_REFUSED and field == "after" and look.bars.after == "green"
            and look.refused["bars.line.after"] == CV.TICK_REFUSED
            and CV.TICK_REFUSED == "Forever cannot read your mana, so the 2-second regen tick cannot be learned: the strip stays green.",
            tostring(why)
    end)
else
    Try("tick: with RM:RegenTick() answering, a white mark sweeps the strip over 2 s after the rule; without, green", function()
        Reset()
        Bars_("line", "after", "tick")
        local realTick = MD.Regen.RegenTick
        local t0 = GetTime() - 0.5
        MD.Regen.RegenTick = function() return t0, 2 end
        RuleOff()
        local v = Paint(face1)
        local m = v.tickMark
        local function X() local pt = m and m.points and m.points[#m.points]; return pt and pt[4] end
        local x0 = X()
        local placed = Shown(m) and Near(x0, 0.25 * v.strip:GetWidth(), 1e-6) and Is(v.strip.barColor, GREEN)
            and Same(m.color, 1, 1, 1)
        S.Tick(0.03)
        local swept = type(X()) == "number" and X() > x0
        MD.Regen.RegenTick = function() return nil end
        Paint(face1)
        local plain = not Shown(m) and Is(v.strip.barColor, GREEN) and Near(v.strip.value, 5)
        MD.Regen.RegenTick = realTick
        Reset()
        return placed and swept and plain, string.format("placed %s (x %s), swept %s, without %s", tostring(placed),
            tostring(x0), tostring(swept), tostring(plain))
    end)
end

-- 15. Mana from the model
Try(forever and "mana from the model: the bar holds the face's plain pct, at 0.6 alpha"
        or "mana from the model: refused on TBC (no model)", function()
    Reset()
    local facts = W.facts or {}
    if forever then
        Bars_("line", "mana", "model")
        local face = { mode = "oom", label = "OOM", value = 90, known = "point", tone = "normal", combat = true,
            pct = 0.4, modelled = true, mono = true, timeFmt = "mss" }
        local v = Paint(face)
        local okM = Near(v.bar.value, 0.4) and Near(v.bar.maxV, 1) and not issecretvalue(v.bar.value)
            and Near(v.manaAlpha, 0.6)
        -- the model's value and alpha, read while plain (the game's draw below
        -- leaves a secret in the bar, which tostring may not touch)
        local modelV, modelA = v.bar.value, v.manaAlpha
        Bars_("line", "mana", nil)
        Paint(face)
        local game = issecretvalue(v.bar.value) == true and Near(v.manaAlpha, 1)
        Reset()
        return okM and game, string.format("model %s alpha %s, game %s", tostring(modelV), tostring(modelA),
            tostring(game))
    end
    local okB, why = CV.BarsOK("line", { mana = "model" }, facts)
    local look = CV.Resolve({ layout = "line", over = { bars = { line = { mana = "model" } } } }, CV.Role(), facts)
    return okB == false and type(why) == "string" and look.bars.mana == "game"
        and look.refused["bars.line.mana"] ~= nil, tostring(why)
end)

-- 16. Textures
Try(forever and "texture: Forever refuses all but flat" or "texture: TBC applies flat, statusbar and raid", function()
    Reset()
    local facts = W.facts or {}
    local bad
    for _, tx in ipairs({ "flat", "statusbar", "raid" }) do
        local okB = CV.BarsOK("line", { texture = tx }, facts)
        Bars_("line", "texture", tx)
        local v = Paint(face1)
        local want = forever and "flat" or tx
        if v.look.bars.texture ~= want or v.texturePath ~= CV.TEXTURES[want]
            or (okB == true) ~= (want == tx) then
            bad = bad or string.format("%s: resolved %s, path %s, ok %s", tx, tostring(v.look.bars.texture),
                tostring(v.texturePath), tostring(okB))
        end
    end
    local paths = CV.TEXTURES and CV.TEXTURES.statusbar == "Interface\\TargetingFrame\\UI-StatusBar"
        and CV.TEXTURES.raid == "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" and CV.TEXTURES.flat == UI.whiteTexture
    Reset()
    return bad == nil and paths, bad
end)

Try("the ring rule (T104): the game's pool on a ring refused " .. (forever and "on Forever" or "nowhere on TBC")
        .. "; an unknown value refused", function()
    local facts = W.facts or {}
    local ring, why = CV.BarsOK("ring", { show = "both", mana = "game" }, facts)
    local ringFsr = CV.BarsOK("ring", { show = "fsr" }, facts)
    local line = CV.BarsOK("line", { show = "both", mana = "game" }, facts)
    local bad = CV.BarsOK("line", { join = "zigzag" }, facts)
    local wantRing = not forever
    return (ring == true) == wantRing and ringFsr == true and line == true and bad == false
        and (wantRing or type(why) == "string"),
        string.format("ring %s (%s), ring fsr %s, line %s, zigzag %s", tostring(ring), tostring(why),
            tostring(ringFsr), tostring(line), tostring(bad))
end)

--------------------------------------------------------------------------------
T.section("the frame's visibility: one owner")
--------------------------------------------------------------------------------
local function IsUp() return frame:IsShown() end

Try("a layout or design switch leaves the frame's shown state alone (shown and hidden), no Show / Hide", function()
    Reset()
    S.Fire("PLAYER_REGEN_DISABLED")
    Tick(2)
    local bad
    local wasShown = IsUp()
    for _, layout in ipairs({ "compact", "bar", "line" }) do
        local before, n = IsUp(), #visCalls
        CV.SetLayout(layout)
        Bars_(layout, "join", "chip")
        CV.Set("frame." .. layout .. ".scale", 120)
        if IsUp() ~= before or #visCalls ~= n then bad = bad or ("in combat, to " .. layout) end
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    if forever then
        MD.Pool.model.mana = MD.Pool.model.max
    else
        S.mana = UnitPowerMax("player", 0)
    end
    Tick(4)
    local wasHidden = not IsUp()
    for _, layout in ipairs({ "bar", "compact", "line" }) do
        local before, n = IsUp(), #visCalls
        CV.SetLayout(layout)
        Bars_(layout, "show", "none")
        if IsUp() ~= before or #visCalls ~= n then bad = bad or ("out of combat, to " .. layout) end
    end
    Reset()
    return wasShown and wasHidden and bad == nil,
        string.format("shown in a fight %s, hidden at full %s, %s", tostring(wasShown), tostring(wasHidden),
            tostring(bad))
end)

Try("every Show / Hide on the frame comes from the visibility owner (counted)", function()
    for _, layout in ipairs(LAYOUTS) do
        for _, join in ipairs(JOINS) do
            S.Fire("PLAYER_REGEN_DISABLED")
            CV.SetLayout(layout)
            Bars_(layout, "join", join)
            Bars_(layout, "show", "fsr")
            CV.Set("frame." .. layout .. ".w", 260)
            CV.Set("frame." .. layout .. ".scale", 80)
            Tick(2)
            CV.ResetToStyle()
            S.Fire("PLAYER_REGEN_ENABLED")
            Tick(3)
        end
    end
    if W.Preview then W:Preview(60) end
    Tick(2)
    if W.Preview then W:Preview(0) end
    if forever and MD.Clock.SetLocked then MD.Clock:SetLocked(true) end
    Tick(3)
    Reset()
    local shows, hides, other = 0, 0, {}
    for _, c in ipairs(visCalls) do
        if c[1] == "Show" then shows = shows + 1 else hides = hides + 1 end
        if c[2] ~= "UpdateVisibility" then other[#other + 1] = c[1] .. " from " .. c[2] end
    end
    return shows > 0 and hides > 0 and #other == 0,
        string.format("%d Show, %d Hide, %d from elsewhere%s", shows, hides, #other,
            #other > 0 and (": " .. other[1]) or "")
end)

--------------------------------------------------------------------------------
T.section("the dump line")
--------------------------------------------------------------------------------
Try("the dump line names the layout and the new keys once the look is not the default", function()
    local function Line()
        for _, d in ipairs(MD:DumpLines()) do
            if d.key == "clock" then return d.fn() end
        end
        return nil
    end
    Reset()
    local plain = Line()
    Bars_("line", "join", "veil")
    local one = Line()
    CV.Set("frame.line.h", 40)
    local two = Line()
    CV.SetLayout("bar")
    local three = Line()
    Reset()
    local okText = T.Ascii(two or "") ~= false
    return plain == "clock: layout line, 0 overrides" and one == "clock: layout line, 1 override (bars.line.join)"
        and two == "clock: layout line, 2 overrides (bars.line.join, frame.line.h)"
        and three == "clock: layout bar, 2 overrides (bars.line.join, frame.line.h)" and okText,
        string.format("%q / %q / %q / %q", tostring(plain), tostring(one), tostring(two), tostring(three))
end)

--------------------------------------------------------------------------------
T.section(forever and "secrets" or "the design matrix")
--------------------------------------------------------------------------------
Try(forever
        and "forever profile: every layout x join x show x mana-from paints in a fight; only the mana bar holds the secret, unread"
        or "every layout x join x show paints in a fight without raising", function()
    S.Fire("PLAYER_REGEN_DISABLED")
    local errs, n, secretText, reads = {}, 0, false, 0
    local v = View()
    local realGet = v.bar.GetValue
    v.bar.GetValue = function(self, ...) reads = reads + 1; return realGet(self, ...) end
    local manas = forever and { "game", "model" } or { "game" }
    for _, layout in ipairs(LAYOUTS) do
        for _, join in ipairs(JOINS) do
            for _, show in ipairs(SHOWS) do
                for _, mana in ipairs(manas) do
                    CV.SetLayout(layout)
                    Bars_(layout, "join", join)
                    Bars_(layout, "show", show)
                    Bars_(layout, "mana", mana ~= "game" and mana or nil)
                    RuleFor(2.5)
                    local okP, e = pcall(function()
                        if forever then MD.Clock:Refresh() end
                        S.Tick(0.5)
                        S.Tick(0.03)
                    end)
                    n = n + 1
                    local tag = layout .. "/" .. join .. "/" .. show .. "/" .. mana
                    if not okP then errs[#errs + 1] = tag .. ": " .. tostring(e) end
                    for _, k in ipairs({ "label", "value", "second" }) do
                        local fs = v[k]
                        if fs and (issecretvalue and issecretvalue(fs.text)) then secretText = true end
                    end
                    if forever then
                        local barSecret = Shown(v.bar) and issecretvalue(v.bar.value) == true
                        local want = Shown(v.bar) and mana == "game"
                        if barSecret ~= want and not errs[1] then
                            errs[#errs + 1] = tag .. ": bar secret " .. tostring(barSecret)
                        end
                        for _, x in ipairs({ v.strip.value, v.veil and v.veil:GetWidth(), v.cd and v.cd.cdStart }) do
                            if x ~= nil and issecretvalue(x) and not errs[1] then
                                errs[#errs + 1] = tag .. ": a secret outside the mana bar"
                            end
                        end
                    end
                    RuleOff()
                end
            end
        end
    end
    v.bar.GetValue = realGet
    Reset()
    S.Fire("PLAYER_REGEN_ENABLED")
    return #errs == 0 and n == 3 * 3 * 4 * #manas and not secretText and reads == 0,
        string.format("%d paints, %d raised%s, secret text %s, %d reads of the bar", n, #errs,
            errs[1] and (": " .. errs[1]) or "", tostring(secretText), reads)
end)

if printing then
    for _, c in ipairs(visCalls) do print(c[1] .. " from " .. c[2]) end
end

T.done()
