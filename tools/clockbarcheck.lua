-- tools/run.sh [--flavour tbc|forever] tools/clockbarcheck.lua
--
-- T145c (docs/SPEC-clock-v3.md 4.3; docs/tasks/T145c-clock-bar.md): the
-- clock's renderer, UI/ClockBar.lua, alone and in its live host, on both
-- flavours -- the whole flavour TOC with the stub's geometry and OnUpdate only
-- on visible frames (S.VisibleOnUpdate). What is held:
--   1. the TOCs list UI/ClockBar.lua where UI/ClockView.lua was, and that file
--      is gone; the live clock has a renderer whose driver's script is set;
--   2. geometry: the frame is width x height at any text size, place and
--      offset; each text's anchor for every place x align, with x / y, and the
--      Border's extra pixel; the hit-rect insets cover the outside texts;
--   3. hot paths, by counting the stub's region calls on the clock: Paint with
--      unchanged words writes no text; Paint and PaintPower anchor, size, set
--      a font and measure nothing; an idle driver frame makes no call;
--      PaintPower() without withMax hands the bar no range;
--   4. secrets (Forever): the bar's value and range are the stub's secret
--      stand-in, handed over unread (no GetValue / GetText / GetStringWidth on
--      the clock); TBC: the same paths with plain reads;
--   5. the failure modes of 2.6: a refused power text (the model's words,
--      marked modelled), EllesmereUI absent (texture Soft, font SpellTuner's,
--      each with its note) and present, no mask textures (a rectangle and its
--      note), no game atlas (Border and its note);
--   6. Message: the texts hidden, Paint writes nothing, the line untouched;
--   7. E5 (4.2) from the host, no pane: a fight end to end on the defaults and
--      on the author's migrated store -- never 0s / 0:00, FULL within a tick of
--      the pool at max and while there, a refill always FULL ..., an OOM time
--      only in mode oom;
--   8. E6 (4.2) from the host: the line moves on each of eight 0.03-s frames
--      across every Bar setting applied mid-rule, a power burst, the preview,
--      the regen events and the host hidden then shown; hidden within a frame
--      of the rule's end; the driver's script one function throughout.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: clockbarcheck.lua runs under tbc, forever only")
    os.exit(3)
end
local forever = flavour == "forever"

local T = dofile(here .. "/lib/t.lua")
local check = T.check
local D = dofile(here .. "/lib/clockdrive.lua")
local ST, S = D.Load(here, root, flavour)

local CB = ST.ClockBar or {}
local Store = ST.ClockStore
local R = D.Renderer(ST)
local frame = D.Frame(ST)

local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end

local function Copy(v) return D.Copy(v) end
local function Defaults() return Copy(Store.DEFAULTS) end
local function Use(look) D.UseLook(ST, look) end

-- every region under the clock's frame (any depth)
local function UnderClock(f)
    local p, guard = f, 0
    while p and guard < 20 do
        if p == frame then return true end
        p, guard = p.parentFrame, guard + 1
    end
    return false
end

--------------------------------------------------------------------------------
T.section("1. the renderer, in every main TOC")
--------------------------------------------------------------------------------
do
    local placed, noView = true, true
    for _, toc in ipairs({ "SpellTuner_Mainline.toc", "SpellTuner.toc", "SpellTuner_TBC.toc" }) do
        local store, bar
        for i, rel in ipairs(S.TocFiles(toc)) do
            if rel == "UI/ClockStore.lua" then store = i end
            if rel == "UI/ClockBar.lua" then bar = i end
            if rel == "UI/ClockView.lua" then noView = false end
        end
        if not (store and bar and bar == store + 1) then placed = false end
    end
    local gone = io.open(root .. "/UI/ClockView.lua", "r") == nil
    check("1. every main TOC lists UI/ClockBar.lua right after UI/ClockStore.lua; UI/ClockView.lua is gone",
        placed and noView and gone)
    check("1. the live clock has a renderer on its own frame, the driver's script set once",
        R ~= nil and frame ~= nil and R.host == frame and R.driver:GetScript("OnUpdate") == R.step
        and ST.ClockView == nil)
end

-- in combat on half a pool, so the clock is up and its OnUpdate runs
-- (S.VisibleOnUpdate) through sections 2 to 6
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
if forever then
    local m = ST.Pool.model
    m:Anchor(S.now, m.max * 0.5, "clockbarcheck")
else
    S.mana = math.floor(S.manaMax * 0.5)
end
S.Tick(0.5)
check("1. in combat the clock is on screen (the host's rule, not the renderer's)", frame:IsShown() == true)

--------------------------------------------------------------------------------
T.section("2. geometry")
--------------------------------------------------------------------------------
local PLACES, ALIGNS = { "inside", "above", "below" }, { "left", "center", "right" }

Try("2. the frame is width x height at any text size, place and offset", function()
    local bad = {}
    for _, w in ipairs({ 100, 200, 400 }) do
        for _, h in ipairs({ 3, 8, 30 }) do
            local look = Defaults()
            look.width, look.height = w, h
            for i, kind in ipairs(CB.KINDS) do
                local t = look.texts[kind]
                t.on = true
                t.size = (i % 2 == 0) and 32 or 6
                t.place = PLACES[(i % 3) + 1]
                t.x, t.y = (i % 2 == 0) and 40 or -40, (i % 2 == 0) and 20 or -20
            end
            Use(look)
            S.Tick(0.5)
            local d = R:Drawn()
            if not (frame:GetWidth() == w and frame:GetHeight() == h and d.host.w == w and d.host.h == h) then
                bad[#bad + 1] = w .. "x" .. h .. " -> " .. frame:GetWidth() .. "x" .. frame:GetHeight()
            end
        end
    end
    Use(Defaults())
    return #bad == 0, table.concat(bad, "; ")
end)

-- the expected anchor, written out (T142 / T144): inside 2 px in unless
-- centred; outside 1 px from the edge (2 on a Border)
local function Want(place, align, x, y, border)
    local gap = border and 2 or 1
    local suf = ({ left = "LEFT", center = "", right = "RIGHT" })[align]
    if place == "inside" then
        local p = suf == "" and "CENTER" or suf
        local pad = (align == "left" and 2) or (align == "right" and -2) or 0
        return p, p, pad + x, y
    elseif place == "above" then
        return "BOTTOM" .. suf, "TOP" .. suf, x, gap + y
    end
    return "TOP" .. suf, "BOTTOM" .. suf, x, -gap + y
end

Try("2. each text's anchor for every place x align, with x / y, on the bar's own rect (a Border adds a pixel)", function()
    local bad, n = {}, 0
    for _, border in ipairs({ false, true }) do
        for _, place in ipairs(PLACES) do
            for _, align in ipairs(ALIGNS) do
                local look = Defaults()
                look.frame = border and "border" or "none"
                local t = look.texts.mana
                t.place, t.align, t.x, t.y = place, align, 7, -3
                Use(look)
                local fs = R.texts.mana
                local pt = fs.points and fs.points[#fs.points]
                local p, rp, x, y = Want(place, align, 7, -3, border)
                n = n + 1
                if not (pt and #fs.points == 1 and pt[1] == p and pt[2] == R.holder and pt[3] == rp and pt[4] == x
                    and pt[5] == y) then
                    bad[#bad + 1] = place .. "/" .. align .. (border and "/border" or "") .. ": "
                        .. (pt and table.concat({ tostring(pt[1]), tostring(pt[3]), tostring(pt[4]), tostring(pt[5]) }, " ") or "none")
                end
                local j = fs.justifyH
                if j ~= nil and j ~= ((p:find("LEFT") and "LEFT") or (p:find("RIGHT") and "RIGHT") or "CENTER") then
                    bad[#bad + 1] = place .. "/" .. align .. ": justify " .. tostring(j)
                end
            end
        end
    end
    Use(Defaults())
    return #bad == 0 and n == 18, table.concat(bad, "; ")
end)

Try("2. the hit rect reaches the outside texts (size + 2 each side), never a measure", function()
    local look = Defaults()
    look.texts.time.place, look.texts.time.size = "above", 20
    look.texts.mp5.place, look.texts.mp5.size = "below", 9
    look.texts.mana.place, look.texts.mana.size = "inside", 30
    Use(look)
    local d1 = R:Drawn()
    local look2 = Defaults()
    for _, kind in ipairs(CB.KINDS) do look2.texts[kind].place = "inside" end
    Use(look2)
    local d2 = R:Drawn()
    Use(Defaults())
    return d1.insets[1] == 22 and d1.insets[2] == 11 and d2.insets[1] == 0 and d2.insets[2] == 0,
        string.format("%s/%s %s/%s", tostring(d1.insets[1]), tostring(d1.insets[2]), tostring(d2.insets[1]),
            tostring(d2.insets[2]))
end)

--------------------------------------------------------------------------------
T.section("3. hot paths")
--------------------------------------------------------------------------------
local LAYOUT_CALLS = { "SetPoint", "ClearAllPoints", "SetFont", "SetSize", "SetWidth", "SetHeight",
    "GetStringWidth", "GetStringHeight", "SetAllPoints" }

Try("3. Paint with unchanged words writes no text; a changed word writes one", function()
    local look = Defaults()
    for _, kind in ipairs(CB.KINDS) do look.texts[kind].on = true end
    Use(look)
    local words = ST.ClockWords.Build(CF_FACE or { mode = "oom", label = "OOM", value = 80, known = "point",
        tone = "normal", timeFmt = "mss", mana = 4000, manaMax = 7000, pct = 0.57, mp5 = 90, fsr = 2 }, look, nil, S.now)
    R:Paint(words)
    S.CountCalls({ "SetText", "SetTextColor" }, UnderClock)
    S.ResetCalls()
    R:Paint(words)
    R:Paint(words)
    local quiet = (S.calls.SetText or 0) == 0 and (S.calls.SetTextColor or 0) == 0
    words.mp5.text = "91 mp5"
    R:Paint(words)
    local one = S.calls.SetText == 1
    S.CountCalls(false)
    Use(Defaults())
    return quiet and one, string.format("SetText %s", tostring(S.calls.SetText))
end)

Try("3. Paint and PaintPower (a tick, a power burst) anchor, size, set a font and measure nothing", function()
    local look = Defaults()
    for _, kind in ipairs(CB.KINDS) do look.texts[kind].on = true end
    Use(look)
    S.Tick(0.5)
    S.CountCalls(LAYOUT_CALLS, function(f) return UnderClock(f) and f ~= R.line and f ~= R.lineBack end)
    S.ResetCalls()
    S.Tick(0.5)
    S.Tick(0.5)
    for _ = 1, 10 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    if not forever then ST.Widget:Paint(S.now) end
    local n, which = 0, {}
    for k, v in pairs(S.calls) do n = n + v; which[#which + 1] = k .. "=" .. v end
    S.CountCalls(false)
    Use(Defaults())
    return n == 0, table.concat(which, " ")
end)

Try("3. an idle driver frame (no rule, or the line off mid-rule) makes no region call", function()
    if forever then ST.Pool.model.lastSpend = S.now - 30 else ST.Regen.fsrEnd = S.now - 30 end
    S.Tick(0.03)
    local ALL = { "SetPoint", "ClearAllPoints", "Show", "Hide", "SetText", "SetTextColor", "SetSize", "SetValue",
        "SetMinMaxValues", "SetFont", "SetColorTexture", "SetAlpha" }
    S.CountCalls(ALL, UnderClock)
    S.ResetCalls()
    R:Step(S.now + 0.03)
    R:Step(S.now + 0.06)
    local idle = next(S.calls) == nil
    S.CountCalls(false)
    local look = Defaults()
    look.line = false
    Use(look)
    D.StartRule(ST, S)
    R:Step(S.now + 0.01) -- the line hidden once, if it showed
    S.CountCalls(ALL, UnderClock)
    S.ResetCalls()
    R:Step(S.now + 0.03)
    R:Step(S.now + 0.06)
    local off = next(S.calls) == nil and not R.lineShown
    S.CountCalls(false)
    Use(Defaults())
    return idle and off, "idle " .. tostring(idle) .. " off " .. tostring(off)
end)

Try("3. PaintPower() without withMax hands the bar no range (the client's easing is never restarted)", function()
    S.CountCalls({ "SetMinMaxValues", "SetValue" }, function(f) return f == R.bar end)
    S.ResetCalls()
    R:PaintPower()
    for _ = 1, 5 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    local none = (S.calls.SetMinMaxValues or 0) == 0 and (S.calls.SetValue or 0) >= 1
    S.ResetCalls()
    R:PaintPower(true)
    local withMax = S.calls.SetMinMaxValues == 1 and S.calls.SetValue == 1
    S.CountCalls(false)
    return none and withMax, string.format("none %s withMax %s", tostring(none), tostring(withMax))
end)

--------------------------------------------------------------------------------
T.section(forever and "4. secrets" or "4. plain reads")
--------------------------------------------------------------------------------
Try(forever and "4. the bar holds the secret pool (its plain max), handed over unread; no power text or bar is read back"
        or "4. the bar holds the plain pool; the power texts are the game's numbers", function()
    local look = Defaults()
    for _, k in ipairs({ "mana", "manaMax", "pct" }) do look.texts[k].on = true end
    Use(look)
    S.CountCalls({ "GetText", "GetValue", "GetMinMaxValues", "GetStringWidth", "GetUnboundedStringWidth" },
        UnderClock)
    S.ResetCalls()
    for _ = 1, 4 do S.Tick(0.5) end
    for _ = 1, 5 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    local reads = 0
    for _, v in pairs(S.calls) do reads = reads + v end
    S.CountCalls(false)
    local d = R:Drawn()
    local ok
    if forever then
        -- the player's own maximum is plain on Forever (T5, eighth report);
        -- the value is the secret
        ok = issecretvalue(R.bar.value) and R.bar.maxV == S.manaMax and R.bar.minV == 0
            and d.text.mana.words == CB.POWER_WORDS and d.text.manaMax.words == CB.POWER_WORDS
    else
        ok = R.bar.value == S.mana and R.bar.maxV == S.manaMax and R.texts.mana.text == tostring(S.mana)
            and R.texts.manaMax.text == S.mana .. "/" .. S.manaMax
            and R.texts.pct.text == math.floor(S.mana / S.manaMax * 100 + 0.5) .. "%"
    end
    Use(Defaults())
    local detail = forever and string.format("value %s max %s min %s mana %s manaMax %s", tostring(issecretvalue(R.bar.value)),
        tostring(issecretvalue(R.bar.maxV)), tostring(R.bar.minV), tostring(d.text.mana.words),
        tostring(d.text.manaMax.words)) or ""
    return ok and reads == 0, string.format("ok %s reads %d %s", tostring(ok), reads, detail)
end)

--------------------------------------------------------------------------------
T.section("5. failure modes (2.6)")
--------------------------------------------------------------------------------
Try("5. a refused power text draws the model's words, marked modelled for the hover", function()
    local look = Defaults()
    look.texts.pct.on = true
    Use(look)
    local saved
    if forever then saved = ST.API.POWER_TEXT_READS; ST.API.POWER_TEXT_READS = false
    else saved = ST.API.DrawPowerText; ST.API.DrawPowerText = nil end
    S.Tick(0.5)
    local d = R:Drawn()
    local words = d.text.mana.words
    local modelled = R:Modelled()
    if forever then ST.API.POWER_TEXT_READS = saved else ST.API.DrawPowerText = saved end
    S.Tick(0.5)
    local back = R:Drawn().text.mana.words == CB.POWER_WORDS
    Use(Defaults())
    local want = forever and (modelled == words) or (modelled == nil)
    return type(words) == "string" and words:match("^%d+$") ~= nil and d.text.pct.words:match("^%d+%%$") ~= nil
        and want and back,
        string.format("words %s pct %s modelled %s back %s", tostring(words), tostring(d.text.pct.words),
            tostring(modelled), tostring(back))
end)

Try("5. EllesmereUI absent: Pixels Dark draws Soft, its font SpellTuner's, each named; present: its own", function()
    Use(Defaults())
    local look = R.look
    local soft = R.texPath == CB.TEXTURES.soft and look.notes.texture == CB.EUI_TEXTURE_MISSING
    local kitFace = CB.Font({ font = "st" })
    local stFont = R.fonts.time[1] == kitFace and look.notes.font == CB.FONT_EUI_MISSING
    local savedFetch, savedParent = ST.Media and ST.Media.FetchEllesmere, ST.EUIParent
    ST.Media = ST.Media or {}
    ST.Media.FetchEllesmere = function(k) if k == "pixels-dark" then return "Interface\\EUI\\pixels-dark.tga" end end
    ST.EUIParent = { GetFontPath = function() return "Interface\\EUI\\Expressway.ttf" end }
    Use(Defaults())
    look = R.look
    local own = R.texPath == "Interface\\EUI\\pixels-dark.tga" and look.notes.texture == nil
        and R.fonts.time[1] == "Interface\\EUI\\Expressway.ttf" and look.notes.font == nil
    ST.Media.FetchEllesmere, ST.EUIParent = savedFetch, savedParent
    Use(Defaults())
    return soft and stFont and own, string.format("soft %s st %s own %s", tostring(soft), tostring(stFont),
        tostring(own))
end)

Try("5. no mask textures: a rectangle, and the reason beside Shape", function()
    local realCreate = CreateFrame
    _G.CreateFrame = function(kind, ...)
        local f = realCreate(kind, ...)
        if kind == "StatusBar" then f.CreateMaskTexture = false end
        return f
    end
    local host = realCreate("Frame", nil, UIParent)
    local b = CB.New(host, {})
    _G.CreateFrame = realCreate
    local look = Defaults()
    look.shape = "pill"
    b:Apply(look)
    return b.masks == nil and look.notes.shape == CB.MASK_REFUSED and b.maskFile == nil
        and look.notes.frame == CB.GAME_REFUSED and b.frameMode == "border",
        string.format("shape %s frame %s", tostring(look.notes.shape), tostring(look.notes.frame))
end)

Try("5. no game atlas: Border and its reason; with it (Forever) the game's art", function()
    local savedHas = ST.API.HasAtlas
    ST.API.HasAtlas = function() return false, "absent" end
    Use(Defaults())
    local refused = R.frameMode == "border" and R.look.notes.frame == CB.GAME_REFUSED and R:Drawn().edge.shown
        and not R:Drawn().game
    ST.API.HasAtlas = savedHas
    Use(Defaults())
    local drawn
    if forever then
        drawn = R.frameMode == "game" and R.look.notes.frame == nil and R:Drawn().game and not R:Drawn().edge.shown
            and R.game.art.atlas == CB.GAME_ATLAS.frame
    else
        drawn = R.frameMode == "border" and R.look.notes.frame == CB.GAME_REFUSED -- the TBC stub has no atlases
    end
    return refused and drawn, string.format("refused %s drawn %s", tostring(refused), tostring(drawn))
end)

Try("5. a shape is mask files only: round and pill set every pair, rect clips nothing", function()
    local look = Defaults()
    look.shape = "pill"
    Use(look)
    local pill = R.maskFile == "Pill" and R.masks.bar[1].texPath == CB.MEDIA .. "PillL"
        and R.masks.back[2].texPath == CB.MEDIA .. "PillR"
    look.shape = "rect"
    Use(look)
    local rect = R.maskFile == nil and R.masks.edge[1].texPath == ST.UI.whiteTexture
    local clips = #(R.line.masks or {}) >= 2
    Use(Defaults())
    return pill and rect and clips, string.format("pill %s rect %s clips %s", tostring(pill), tostring(rect),
        tostring(clips))
end)

--------------------------------------------------------------------------------
T.section("6. Message")
--------------------------------------------------------------------------------
Try("6. a message hides the texts and Paint writes nothing; ended, the texts are back; the line untouched", function()
    Use(Defaults())
    S.Tick(0.5)
    D.StartRule(ST, S)
    S.Tick(0.03)
    local x0 = R.lineX
    R:Message("SpellTuner - drag me", 1, 1, 1)
    S.CountCalls({ "SetText" }, function(f) return UnderClock(f) and f ~= R.msg end)
    S.ResetCalls()
    local words = ST.ClockWords.Build({ mode = "oom", label = "OOM", value = 80, known = "point", timeFmt = "mss" },
        R.look, nil, S.now)
    R:Paint(words)
    local quiet = (S.calls.SetText or 0) == 0
    S.CountCalls(false)
    local d = R:Drawn()
    local hidden = d.msg == "SpellTuner - drag me" and not d.text.time.shown and not R.texts.time:IsShown()
    S.Tick(0.03)
    local moving = R.lineShown and R.lineX > x0
    R:Message(nil)
    local back = R.texts.time:IsShown() and R:Drawn().msg == nil and R.texts.time.text == "1:20"
    return quiet and hidden and moving and back, string.format("quiet %s hidden %s moving %s back %s",
        tostring(quiet), tostring(hidden), tostring(moving), tostring(back))
end)

--------------------------------------------------------------------------------
T.section("7. E5: a fight end to end, from the host")
--------------------------------------------------------------------------------
for _, which in ipairs({ "defaults", "author" }) do
    -- (the driven model never enters a refill mode in this script -- the
    -- spend estimate outlasts the regen -- so "a refill reads FULL ..." is
    -- held by the verdict whenever one appears, not required to appear)
    Try("7. E5 (" .. which .. "): never 0s, FULL within a tick of the pool at max and while there, no bare refill time", function()
        if which == "author" then Use(D.AuthorLook(root, ST)) else Use(Defaults()) end
        local trace, info = D.E5(ST, S)
        local ok, why = D.E5Verdict(trace)
        local sawFull = false
        for _, e in ipairs(trace) do
            if e.words == "FULL" then sawFull = true end
        end
        Use(Defaults())
        return ok and info.atMax ~= nil and sawFull and #trace > 40,
            string.format("%s; %d ticks, max at %s, FULL %s", tostring(why), #trace, tostring(info.atMax),
                tostring(sawFull))
    end)
end

--------------------------------------------------------------------------------
T.section("8. E6: the moving line, from the host")
--------------------------------------------------------------------------------
do
    Use(Defaults())
    local okE, results, same, hiddenInTime = pcall(D.E6, ST, S)
    if not okE then
        check("8. E6 ran", false, tostring(results))
    else
        local stopped = {}
        for _, r in ipairs(results) do
            if not r.moved then
                local xs = {}
                for i, x in ipairs(r.xs or {}) do xs[i] = type(x) == "number" and string.format("%.1f", x) or tostring(x) end
                stopped[#stopped + 1] = r.name .. " [" .. table.concat(xs, " ") .. "]"
            end
        end
        check("8. the line moves right on each of eight 0.03-s frames across " .. #results .. " disturbances",
            #stopped == 0 and #results >= 20, table.concat(stopped, "; "))
        check("8. hidden within one frame of the rule's end", hiddenInTime == true)
        check("8. the driver's script is the same function object throughout", same == true)
    end
end

T.done()
