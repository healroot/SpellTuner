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
-- What is held, on both flavours:
--   * the layouts (line, compact, bar): CV.SetLayout saves db.clockLook.layout
--     and fires CLOCK_LOOK once, an unknown layout is refused;
--   * each layout x each ClockFace.SAMPLES face (as this line draws it) FITS
--     its frame at font offsets -2..+2: every piece shown inside the frame, no
--     two pieces overlapping, no text over the bar's backing where the text
--     sits beside the bar (line, compact) -- and a second round of switches
--     builds no new region (one pool per frame);
--   * `bar.source = "none"` hides the bar, its backing and the spark, on every
--     layout, and the bar comes back when the source does;
--   * a layout switch leaves the frame's shown state alone (shown and hidden),
--     with no Show / Hide on the frame; and over a whole scenario (fights,
--     ticks, switches, overrides, a style, the preview) every Show / Hide on
--     the frame comes from the line's one visibility owner (counted);
--   * the bar's sources draw what they say (time, fsr, pool; model on
--     Forever), the spark sweeps the five seconds after a spend and hides;
--   * `pool` is refused for the ring on Forever (allowed on TBC), `model` on
--     TBC, and a refused source falls back to the line's own;
--   * the panel is UI.Skin(widget, "clock"): a style's clock role paints the
--     fill, the bar's backing and its colour, an override wins over it, Reset
--     to style gives the style back, Flat gives today's paint back;
--   * the dump line is absent at the default look and names the layout and
--     the overrides once the look is not the default;
--   * Forever, under the stub's forever profile: every layout x source x spark
--     paints in a fight without touching a secret (the pool's secret reaches
--     the bar unread, every other value is plain); TBC: the same matrix paints
--     without raising.
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

local T = dofile(here .. "/lib/t.lua")
local check = T.check

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = root
S.flavour = flavour

local MD = {}
local toc = "SpellTuner_TBC.toc"
if flavour == "forever" then
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
local frame = W.frame or (flavour == "forever" and _G.SpellTunerClock or _G.SpellTunerWidget)
local function View() return W.view or (frame and frame.view) or (MD.Clock and MD.Clock.view) end

-- the first run's 60-s placing preview (TBC unlocks the clock at a first
-- login) ended, the clock locked: what the visibility checks start from
if MD.db then MD.db.locked = true end
if W.Preview then pcall(W.Preview, W, 0) end

-- A check whose body may raise (on the parent, before T98, most of what it
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

-- The faces as this line draws them: SAMPLES (TBC-shaped), with Forever's
-- marks on Forever (the "~" before the label, one colour, "0:15").
local function Faces()
    local out = {}
    for _, s in ipairs(CF.SAMPLES or {}) do
        local f = {}
        for k, v in pairs(s.face) do f[k] = v end
        if flavour == "forever" then f.modelled, f.mono, f.timeFmt = true, true, "mss" end
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
    if v.bar and v.bar:IsShown() then
        local br, bk = Rect(v.bar), Rect(v.barBack)
        if not (br and bk) then return "the bar has no place" end
        if not Inside(br, fr) then return "the bar " .. R(br) .. " outside the frame " .. R(fr) end
        if not Inside(bk, fr) then return "the bar's backing " .. R(bk) .. " outside the frame " .. R(fr) end
        if layout ~= "bar" then
            for _, p in ipairs(pieces) do
                if Overlap(p.r, bk) then return p.k .. " " .. R(p.r) .. " over the bar " .. R(bk) end
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

local faces = Faces()
local regionsAfterFirstRound
for _, layout in ipairs(LAYOUTS) do
    Try("fits: " .. layout .. " -- every SAMPLES face at font offsets -2..+2", function()
        CV.SetLayout(layout)
        local v = View()
        local n, bad = 0, nil
        for offset = -2, 2 do
            UI.ApplyFonts(offset)
            for _, f in ipairs(faces) do
                Paint(f.face)
                n = n + 1
                local why = Misfit(v, layout)
                if why and not bad then bad = string.format("offset %+d, %s: %s", offset, f.key, why) end
            end
        end
        UI.ApplyFonts(0)
        local fw, fh = frame:GetWidth(), frame:GetHeight()
        return bad == nil and n == 5 * #faces and n > 0 and v.look.layout == layout,
            bad or string.format("%d paints, frame %sx%s", n, tostring(fw), tostring(fh))
    end)
end
regionsAfterFirstRound = #S.allFrames

Try("a second round of switches builds no region (one pool per frame)", function()
    for _, layout in ipairs(LAYOUTS) do
        CV.SetLayout(layout)
        Paint(faces[1].face)
    end
    CV.SetLayout("line")
    Paint(faces[1].face)
    return #S.allFrames == regionsAfterFirstRound, string.format("%d -> %d regions", regionsAfterFirstRound,
        #S.allFrames)
end)

Try("the line layout is T93's: 180 x 30, a 160 x 4 bar 5 above the bottom", function()
    CV.SetLayout("line")
    local v = Paint(faces[1].face)
    local br = Rect(v.bar)
    return frame:GetWidth() == 180 and frame:GetHeight() == 30 and v.bar:GetWidth() == 160
        and v.bar:GetHeight() == 4 and br ~= nil and Near(br.b, 5) and Near(br.l, 10),
        string.format("frame %sx%s bar %s", tostring(frame:GetWidth()), tostring(frame:GetHeight()), R(br))
end)

--------------------------------------------------------------------------------
T.section("the bar")
--------------------------------------------------------------------------------
Try("bar.source none hides the bar, its backing and the spark, on every layout; back with a source", function()
    local bad
    for _, layout in ipairs(LAYOUTS) do
        CV.SetLayout(layout)
        CV.Set("bar.spark", "fsr")
        CV.Set("bar.source", "time")
        local v = Paint(faces[1].face)
        local on = v.bar:IsShown() and v.barBack:IsShown()
        CV.Set("bar.source", "none")
        Paint(faces[1].face)
        local off = not v.bar:IsShown() and not v.barBack:IsShown() and not (v.spark and v.spark:IsShown())
        local fits = Misfit(v, layout)
        CV.Set("bar.source", "time")
        Paint(faces[1].face)
        local back = v.bar:IsShown() and v.barBack:IsShown()
        if not (on and off and back and fits == nil) and not bad then
            bad = string.format("%s: on %s, off %s, back %s, %s", layout, tostring(on), tostring(off),
                tostring(back), tostring(fits))
        end
    end
    CV.ResetToStyle()
    CV.SetLayout("line")
    return bad == nil, bad
end)

local realFSR = MD.Regen and MD.Regen.FSRRemaining
local function FSRNow(seconds)
    -- the line's own five-second rule: the model's last priced spend on
    -- Forever, the regen model's on TBC
    if flavour == "forever" then
        MD.Pool.model.lastSpend = GetTime() - (5 - seconds)
    else
        MD.Regen.FSRRemaining = function() return seconds end
    end
end
local function FSRDone()
    if flavour == "forever" then MD.Pool.model.lastSpend = -1e9 else MD.Regen.FSRRemaining = realFSR end
end

Try("the sources draw what they say: time, fsr, pool" .. (flavour == "forever" and ", model" or ""), function()
    local v = View()
    local face = { mode = "oom", label = "OOM", value = 90, known = "point", tone = "normal", combat = true,
        pct = 0.4, timeFmt = "auto" }
    if flavour == "forever" then face.modelled, face.timeFmt = true, "mss" end
    local res = {}
    CV.Set("bar.source", "time")
    Paint(face)
    res.time = Near(v.bar.value, 0.5) and Near(v.bar.maxV, 1) and Same(v.bar.barColor, 1, 1, 1)
    CV.Set("bar.horizon", 360)
    Paint(face)
    res.horizon = Near(v.bar.value, 0.25)
    CV.Set("bar.source", "fsr")
    FSRNow(3)
    Paint(face)
    res.fsr = Near(v.bar.value, 2) and Near(v.bar.maxV, 5) and Same(v.bar.barColor, 1, 0.67, 0.2)
    FSRNow(0)
    Paint(face)
    res.regen = Near(v.bar.value, 5) and Same(v.bar.barColor, 0.2, 1, 0.4)
    FSRDone()
    CV.Set("bar.source", "pool")
    Paint(face)
    if flavour == "forever" then
        res.pool = issecretvalue(v.bar.value) == true and Same(v.bar.barColor, 0.3, 0.6, 1)
        CV.Set("bar.source", "model")
        Paint(face)
        res.model = Near(v.bar.value, 0.4) and Same(v.bar.barColor, 0.3, 0.6, 1)
    else
        res.pool = v.bar.value == UnitPower("player", 0) and v.bar.maxV == UnitPowerMax("player", 0)
            and Same(v.bar.barColor, 0.3, 0.6, 1)
    end
    CV.Set("bar.color", "tone")
    face.value, face.tone = 12, "crit"
    CV.Set("bar.source", "time")
    Paint(face)
    res.tone = Same(v.bar.barColor, 1, 0x44 / 255, 0x44 / 255)
    CV.ResetToStyle()
    local all = true
    local parts = {}
    for k, x in pairs(res) do
        parts[#parts + 1] = k .. "=" .. tostring(x)
        if not x then all = false end
    end
    table.sort(parts)
    return all, table.concat(parts, " ")
end)

Try("the spark sweeps the five seconds after a spend (yellow), then hides", function()
    local v = View()
    CV.Set("bar.spark", "fsr")
    FSRNow(3)
    Paint(faces[1].face)
    local s = v.spark
    local pt = s and s.points and s.points[#s.points]
    local placed = s ~= nil and s:IsShown() and pt ~= nil and pt[2] == v.bar and pt[3] == "LEFT"
        and Near(pt[4], 0.4 * v.bar:GetWidth()) and Same(s.color, 1, 1, 0)
    FSRNow(0)
    Paint(faces[1].face)
    local gone = s ~= nil and not s:IsShown()
    FSRDone()
    CV.ResetToStyle()
    Paint(faces[1].face)
    local off = s ~= nil and not s:IsShown()
    return placed and gone and off, string.format("placed %s (x %s of %s), gone %s, off %s", tostring(placed),
        tostring(pt and pt[4]), tostring(v.bar:GetWidth()), tostring(gone), tostring(off))
end)

Try("pool is refused for the ring " .. (flavour == "forever" and "on Forever" or "nowhere on TBC")
        .. "; model only where there is a modelled pool; a refused source falls back", function()
    local facts = W.facts or {}
    local ringPool, why = CV.SourceOK("ring", "pool", facts)
    local barPool = CV.SourceOK("bar", "pool", facts)
    local model = CV.SourceOK("line", "model", facts)
    local look = CV.Resolve({ layout = "line", over = { bar = { source = "model" } } }, CV.Role(), facts)
    if flavour == "forever" then
        return ringPool == false and type(why) == "string" and barPool == true and model == true
            and look.bar.source == "model",
            string.format("ring pool %s (%s), bar pool %s, model %s", tostring(ringPool), tostring(why),
                tostring(barPool), tostring(model))
    end
    return ringPool == true and barPool == true and model == false and look.bar.source == "fsr"
        and look.refused["bar.source"] ~= nil,
        string.format("ring pool %s, bar pool %s, model %s, resolved %s", tostring(ringPool), tostring(barPool),
            tostring(model), tostring(look.bar.source))
end)

--------------------------------------------------------------------------------
T.section("F1: the bar's height and the smooth five-second rule")
--------------------------------------------------------------------------------
-- F1 (the author on 0.16.6, Settings -> Clock -> Bar: "the height does not
-- really change anything"): every layout that shows a bar draws it at the
-- Height setting -- the bar layout used the frame's height less 4 whatever
-- the setting said.
Try("Height: every layout draws its bar at the setting (two heights, two bars); the frame holds it", function()
    local bad
    for _, layout in ipairs(LAYOUTS) do
        CV.SetLayout(layout)
        CV.Set("bar.source", "fsr")
        local drawn = {}
        for _, h in ipairs({ 6, 14, 24 }) do
            CV.Set("bar.height", h)
            local v = Paint(faces[1].face)
            drawn[h] = v.bar:GetHeight()
            local why = Misfit(v, layout)
            if (drawn[h] ~= h or why) and not bad then
                bad = string.format("%s: height %d drew %s (frame %sx%s)%s", layout, h, tostring(drawn[h]),
                    tostring(frame:GetWidth()), tostring(frame:GetHeight()), why and (", " .. why) or "")
            end
        end
        if drawn[6] == drawn[14] and not bad then bad = layout .. ": 6 and 14 drew the same bar" end
        CV.ResetToStyle()
    end
    CV.SetLayout("bar")
    local v = Paint(faces[1].face)
    local default = v.bar:GetHeight() == 14 and frame:GetHeight() >= 18
    CV.SetLayout("line")
    return bad == nil and default, bad or string.format("bar layout default: bar %s, frame %s",
        tostring(v.bar:GetHeight()), tostring(frame:GetHeight()))
end)

-- F1 ("5-sec rule bar - I like it but the fillment should be more smooth"):
-- while the rule runs the bar (source fsr) and the spark move every frame,
-- not only at the line's paint; the per-frame step is removed when the rule
-- ends or the source changes.
local function RuleFor(seconds)
    if flavour == "forever" then
        MD.Pool.model.lastSpend = GetTime() - (5 - seconds)
    else
        MD.Regen.fsrEnd = GetTime() + seconds
    end
end
local function RuleOff()
    if flavour == "forever" then MD.Pool.model.lastSpend = -1e9 else MD.Regen.fsrEnd = 0 end
end

Try("smooth: the five-second rule bar and the spark move every frame between two paints", function()
    CV.SetLayout("bar")
    CV.Set("bar.source", "fsr")
    CV.Set("bar.spark", "fsr")
    local v = View()
    RuleFor(4)
    Paint(faces[1].face)
    local values, sparks = { v.bar.value }, {}
    local function SparkX()
        local pt = v.spark and v.spark.points and v.spark.points[#v.spark.points]
        return pt and pt[4]
    end
    sparks[1] = SparkX()
    local moved, still = 0, 0
    for i = 2, 9 do -- 0.03 s apart: under the TBC widget's 0.1 s and Forever's 0.5 s paint
        S.Tick(0.03)
        values[i], sparks[i] = v.bar.value, SparkX()
        if type(values[i]) == "number" and type(values[i - 1]) == "number" and values[i] > values[i - 1] + 1e-9
            and type(sparks[i]) == "number" and type(sparks[i - 1]) == "number" and sparks[i] > sparks[i - 1] then
            moved = moved + 1
        else
            still = still + 1
        end
    end
    local onTrack = Near(v.bar.value, 5 - (4 - 8 * 0.03), 1e-6)
    local fn = v.bar:GetScript("OnUpdate")
    RuleOff()
    CV.ResetToStyle()
    CV.SetLayout("line")
    return moved == 8 and still == 0 and onTrack and fn ~= nil,
        string.format("%d of 8 frames moved, value %s, values %s", moved, tostring(values[#values]),
            table.concat((function()
                local o = {}
                for i, x in ipairs(values) do o[i] = string.format("%.3f", tonumber(x) or -1) end
                return o
            end)(), " "))
end)

Try("smooth: the per-frame step ends with the rule (full, green, no spark) and with a source change", function()
    CV.SetLayout("line")
    CV.Set("bar.source", "fsr")
    CV.Set("bar.spark", "fsr")
    local v = View()
    RuleFor(0.1)
    Paint(faces[1].face)
    local on1 = v.bar:GetScript("OnUpdate")
    for _ = 1, 5 do S.Tick(0.03) end
    local ended = v.bar:GetScript("OnUpdate") == nil and Near(v.bar.value, 5)
        and Same(v.bar.barColor, 0.2, 1, 0.4) and not (v.spark and v.spark:IsShown())
    RuleFor(4)
    Paint(faces[1].face)
    local on2 = v.bar:GetScript("OnUpdate")
    local sameFn = on1 ~= nil and on1 == on2 -- built once per view, nothing allocated per install
    CV.Set("bar.source", "time")
    CV.Set("bar.spark", "none")
    local offBySource = v.bar:GetScript("OnUpdate") == nil
    CV.Set("bar.spark", "fsr")
    Paint(faces[1].face)
    local sparkOnly = v.bar:GetScript("OnUpdate") ~= nil -- the spark alone still sweeps
    -- the bar's own step alone (no line paint in between): it moves the
    -- spark, never another source's value
    local valueBefore, step = v.bar.value, v.bar:GetScript("OnUpdate")
    local function X() local pt = v.spark and v.spark.points and v.spark.points[#v.spark.points]; return pt and pt[4] end
    local x0 = X()
    S.now = S.now + 0.03
    if step then step(v.bar, 0.03) end
    local timeKept = v.bar.value == valueBefore and type(X()) == "number" and type(x0) == "number" and X() > x0
    CV.Set("bar.source", "none")
    local offByNone = v.bar:GetScript("OnUpdate") == nil
    RuleOff()
    CV.ResetToStyle()
    Paint(faces[1].face)
    return on1 ~= nil and ended and sameFn and offBySource and sparkOnly and timeKept and offByNone,
        string.format("installed %s, ended %s, same fn %s, off by source %s, spark only %s, time kept %s, off by none %s",
            tostring(on1 ~= nil), tostring(ended), tostring(sameFn), tostring(offBySource), tostring(sparkOnly),
            tostring(timeKept), tostring(offByNone))
end)

--------------------------------------------------------------------------------
T.section("the frame's visibility: one owner")
--------------------------------------------------------------------------------
local function Shown() return frame:IsShown() end

Try("a layout switch leaves the frame's shown state alone (shown and hidden), no Show / Hide", function()
    S.Fire("PLAYER_REGEN_DISABLED")
    Tick(2)
    local bad
    local wasShown = Shown()
    for _, layout in ipairs({ "compact", "bar", "line" }) do
        local before, n = Shown(), #visCalls
        CV.SetLayout(layout)
        if Shown() ~= before or #visCalls ~= n then bad = bad or ("in combat, to " .. layout) end
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    if flavour == "forever" then
        MD.Pool.model.mana = MD.Pool.model.max
    else
        S.mana = UnitPowerMax("player", 0)
    end
    Tick(4)
    local wasHidden = not Shown()
    for _, layout in ipairs({ "bar", "compact", "line" }) do
        local before, n = Shown(), #visCalls
        CV.SetLayout(layout)
        if Shown() ~= before or #visCalls ~= n then bad = bad or ("out of combat, to " .. layout) end
    end
    return wasShown and wasHidden and bad == nil,
        string.format("shown in a fight %s, hidden at full %s, %s", tostring(wasShown), tostring(wasHidden),
            tostring(bad))
end)

Try("every Show / Hide on the frame comes from the visibility owner (counted)", function()
    -- a scenario: fights, ticks, every layout, overrides, a reset, the preview
    for _, layout in ipairs(LAYOUTS) do
        S.Fire("PLAYER_REGEN_DISABLED")
        CV.SetLayout(layout)
        CV.Set("bar.source", "none")
        Tick(2)
        CV.ResetToStyle()
        S.Fire("PLAYER_REGEN_ENABLED")
        Tick(3)
    end
    if W.Preview then W:Preview(60) end
    Tick(2)
    if W.Preview then W:Preview(0) end
    if flavour == "forever" and MD.Clock.SetLocked then MD.Clock:SetLocked(true) end
    Tick(3)
    CV.SetLayout("line")
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
T.section("the panel and the style's clock role")
--------------------------------------------------------------------------------
Try("UI.Skin(widget, \"clock\"): the frame is registered by the clock role in today's paint", function()
    local rec = UI.skinned and UI.skinned[frame]
    local P = UI.PALETTE
    return rec ~= nil and rec.role == "clock" and Same(frame.bg, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
        and Same(frame.border, P.border[1], P.border[2], P.border[3], P.border[4])
        and Same(View().barBack.color, 0, 0, 0, 1),
        string.format("role %s, bg %s, edge %s", tostring(rec and rec.role), C(frame.bg), C(frame.border))
end)

Try("a style's clock role paints the clock; an override wins over it; Reset to style and Flat give it back", function()
    local TEST = {
        name = "T98", hint = "clockui's own.", accent = "class",
        roles = { clock = { kind = "pixel", fill = { 0.1, 0.2, 0.3, 1 }, edge = "border",
            bar = { 0.5, 0, 0, 1 }, barFill = { 0, 1, 0, 1 } } },
        needs = {},
    }
    UI.Styles.Register("t98", TEST)
    UI.SetStyle("t98")
    local v = View()
    CV.Set("bar.source", "time")
    CV.ResetToStyle()
    Paint(faces[1].face)
    local styled = Same(frame.bg, 0.1, 0.2, 0.3, 1) and Same(v.barBack.color, 0.5, 0, 0, 1)
        and Same(v.bar.barColor, 0, 1, 0)
    CV.Set("panel.fill", { 0.9, 0.8, 0.7, 1 })
    CV.Set("bar.back", { 0, 0, 0.5, 1 })
    CV.Set("bar.color", "tone")
    Paint(faces[1].face)
    local over = Same(frame.bg, 0.9, 0.8, 0.7, 1) and Same(v.barBack.color, 0, 0, 0.5, 1)
        and Same(v.bar.barColor, 1, 1, 1)
    CV.ResetToStyle()
    Paint(faces[1].face)
    local reset = Same(frame.bg, 0.1, 0.2, 0.3, 1) and Same(v.barBack.color, 0.5, 0, 0, 1)
        and Same(v.bar.barColor, 0, 1, 0)
    UI.SetStyle("flat")
    Paint(faces[1].face)
    local P = UI.PALETTE
    local flat = Same(frame.bg, P.bg[1], P.bg[2], P.bg[3], P.bg[4]) and Same(v.barBack.color, 0, 0, 0, 1)
        and UI.skinned[frame].role == "clock"
    return styled and over and reset and flat,
        string.format("styled %s, over %s, reset %s, flat %s (bg %s)", tostring(styled), tostring(over),
            tostring(reset), tostring(flat), C(frame.bg))
end)

--------------------------------------------------------------------------------
T.section("the dump line")
--------------------------------------------------------------------------------
Try("the dump line names the layout and the overrides once the look is not the default", function()
    -- a fresh look first: the line was added by the switches above; its words now
    local function Line()
        for _, d in ipairs(MD:DumpLines()) do
            if d.key == "clock" then return d.fn() end
        end
        return nil
    end
    CV.ResetToStyle()
    CV.SetLayout("line")
    local plain = Line()
    CV.SetLayout("bar")
    CV.Set("bar.source", "time")
    local one = Line()
    CV.Set("colors.crit", "ff0000")
    local two = Line()
    CV.ResetToStyle()
    CV.SetLayout("line")
    local okText = T.Ascii == nil or (T.Ascii(two or "") ~= false)
    return plain == "clock: layout line, 0 overrides" and one == "clock: layout bar, 1 override (bar.source)"
        and two == "clock: layout bar, 2 overrides (bar.source, colors.crit)" and okText,
        string.format("%q / %q / %q", tostring(plain), tostring(one), tostring(two))
end)

--------------------------------------------------------------------------------
T.section(flavour == "forever" and "secrets" or "the source matrix")
--------------------------------------------------------------------------------
Try(flavour == "forever"
        and "forever profile: every layout x source x spark paints in a fight without touching a secret"
        or "every layout x source x spark paints in a fight without raising", function()
    S.Fire("PLAYER_REGEN_DISABLED")
    local errs, n, secretText = {}, 0, false
    for _, layout in ipairs(LAYOUTS) do
        for _, src in ipairs(CV.SOURCES or {}) do
            for _, spark in ipairs({ "none", "fsr" }) do
                CV.SetLayout(layout)
                CV.Set("bar.source", src)
                CV.Set("bar.spark", spark)
                FSRNow(2.5)
                local okP, e = pcall(function()
                    if flavour == "forever" then MD.Clock:Refresh() end
                    S.Tick(0.5)
                end)
                n = n + 1
                if not okP then errs[#errs + 1] = layout .. "/" .. src .. "/" .. spark .. ": " .. tostring(e) end
                local v = View()
                for _, k in ipairs({ "label", "value", "second" }) do
                    local fs = v[k]
                    if fs and (issecretvalue and issecretvalue(fs.text)) then secretText = true end
                end
                if flavour == "forever" and v.bar:IsShown() then
                    local val = v.bar.value
                    local isSecret = issecretvalue(val)
                    if (src == "pool") ~= (isSecret == true) and not errs[1] then
                        errs[#errs + 1] = layout .. "/" .. src .. ": bar value secret=" .. tostring(isSecret)
                    end
                end
                FSRDone()
            end
        end
    end
    CV.ResetToStyle()
    CV.SetLayout("line")
    S.Fire("PLAYER_REGEN_ENABLED")
    return #errs == 0 and n == 3 * 5 * 2 and not secretText,
        string.format("%d paints, %d raised%s, secret text %s", n, #errs, errs[1] and (": " .. errs[1]) or "",
            tostring(secretText))
end)

if printing then
    for _, c in ipairs(visCalls) do print(c[1] .. " from " .. c[2]) end
end

T.done()
