-- tools/run.sh [--flavour tbc|forever] tools/clocke2e.lua
--
-- T145d (docs/SPEC-clock-v3.md 4.2; docs/tasks/T145d-clock-pane.md): the
-- AUTHOR'S PATH, end to end -- a Settings -> Clock control -> db.clockLook ->
-- CLOCK_LOOK -> the live clock on screen (UI/Clock_Forever.lua on Forever,
-- UI/Widget.lua on TBC, both drawn by UI/ClockBar.lua). The whole flavour TOC
-- is loaded with the stub's geometry, OnUpdate only on visible frames, the
-- integrations, and the hosts that let every choice be drawn (EllesmereUI's
-- textures and font; the game's bar art): a choice the client cannot draw is
-- clockbarcheck's and clocksettings' business (its fallback and its note).
-- The pane is the real one, opened through the dashboard; every control is
-- operated through its own widget (a click, a dropdown pick, a check, a
-- number box's Enter, the colour picker's move).
--
--   E1  every control visibly changes the live clock (P1): from each of four
--       base looks (the defaults; the author's migrated 2026-11-08 store; every
--       text on with the line off; every text off), every entry of CS.CONTROLS visible there,
--       every sample value that differs: the live clock's Drawn() differs on a
--       field the control names. An empty inert list is the pass; there is no
--       exception list. The same for the pane's own preview.
--   E2  every control the look makes inert is hidden (its widget not shown),
--       every other one shown.
--   E3  every write is ONE CLOCK_LOOK, and the store is valid after it.
--   E4  presets: from each base look, each preset keeps the time and the 5SR
--       line on (P2), the line is drawn mid-rule, and Undo restores the store
--       and the live clock's Drawn() exactly.
--   E5  a fight end to end, driven by the model (Forever) or the pool (TBC),
--       on the defaults and on the author's look (tools/lib/clockdrive.lua);
--       and (U3's open point 3) the refill: out of combat, below max and
--       regenerating, the time reads FULL m:ss and then FULL, never a bare
--       number or a zero; on Forever also a fight entered below max with light
--       casting (a refill in a fight: FULL m:ss).
--   E6  the moving line, mid-rule, across every disturbance of clockdrive and
--       across every Bar control operated from the pane.
--   E7  (Forever) the quiet pool: events every 0.2 s -> no anchor; quiet for
--       QUIET outside the rule -> anchored, the time FULL; quiet inside the
--       rule -> no anchor; base x QUIET < 2 -> no anchor; dead or a ghost ->
--       no anchor, and after PLAYER_ALIVE none until a fresh event (N5).
--
-- The moment E1 holds the live clock at (a seam, not the model's own path):
-- Forever, the model's fight fields set at 60 % mana so the time to OOM is
-- 80 s (40 s for Warn colours) with the rule running and the rest far enough
-- from it to be drawn, out of combat so the Settings window
-- stays open; TBC, ST:GetClockFace answering that face. Each control is
-- operated from that moment, then one 0.5 s tick.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: clocke2e.lua runs under tbc, forever only")
    os.exit(3)
end
local forever = flavour == "forever"

local T = dofile(here .. "/lib/t.lua")
local check = T.check
local D = dofile(here .. "/lib/clockdrive.lua")

local ST, S = D.Load(here, root, flavour, { integrations = true, before = function(S0)
    if not forever then S0.UseAtlases() end -- the game's bar art on both lines (see the header)
end })

-- EllesmereUI's textures, mana colour and font (the author's host)
local EUI_DIR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
_G.EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI.BuildBarTextureTables = function()
    return { atrocity = EUI_DIR .. "atrocity.tga", ["pixels-dark"] = EUI_DIR .. "pixels-dark.tga" },
        { none = "None", atrocity = "Atrocity", ["pixels-dark"] = "Pixels Dark" },
        { "none", "atrocity", "pixels-dark" }
end
_G.EllesmereUI.GetPowerColor = function(key) if key == "MANA" then return { r = 0, g = 0.55, b = 1 } end end
ST.EUIParent = ST.EUIParent or { GetFontPath = function() return "Fonts\\EUI.ttf" end }
if not ST.EUIParent.GetFontPath then ST.EUIParent.GetFontPath = function() return "Fonts\\EUI.ttf" end end

-- the game's colour picker: SetupColorPickerAndShow keeps its info; a move
-- answers `cur`
local picker = { cur = { 1, 1, 1, 1 } }
_G.ColorPickerFrame = {
    SetupColorPickerAndShow = function(_, info) picker.info = info end,
    GetColorRGB = function() return picker.cur[1], picker.cur[2], picker.cur[3] end,
    GetColorAlpha = function() return picker.cur[4] end,
}
if ST.API.Invalidate then ST.API.Invalidate("ColorPickerFrame") end

local Store = ST.ClockStore
local CS = ST.ClockSettings
local CW = ST.ClockWords
local W = ST.ClockWidget
local R = D.Renderer(ST)

local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end

local events = 0
ST:RegisterCallback("CLOCK_LOOK", function() events = events + 1 end)

--------------------------------------------------------------------------------
-- The four base looks
--------------------------------------------------------------------------------
local function Copy(v) return D.Copy(v) end
local BASES = {}
BASES[1] = { name = "the defaults", look = Copy(Store.DEFAULTS) }
BASES[2] = { name = "the author's migrated store", look = D.AuthorLook(root, ST) }
do
    local all = Copy(Store.DEFAULTS)
    for _, kind in ipairs(Store.KINDS) do all.texts[kind].on = true end
    all.line = false
    BASES[3] = { name = "every text on, the line off", look = all }
end
do
    -- T145 review N2: every text off is reachable (P2 binds presets only)
    local none = Copy(Store.DEFAULTS)
    for _, kind in ipairs(Store.KINDS) do none.texts[kind].on = false end
    BASES[4] = { name = "every text off", look = none }
end

--------------------------------------------------------------------------------
-- The moment (see the header)
--------------------------------------------------------------------------------
local MAX = forever and ST.Pool.model.max or S.manaMax
local function TbcFace(tto)
    return { mode = "oom", label = "OOM", value = tto, known = "point", tone = ST.ClockFace.Tone(tto), combat = true,
        timeFmt = "auto", arrow = "v", pct = 0.4, mana = math.floor(MAX * 0.4), manaMax = MAX, manaModelled = false,
        mp5 = 92, fsr = 3, second = { kind = "rest", label = "rest", value = 130 } }
end
local tbcFace = nil
if not forever then
    local real = ST.GetClockFace
    rawset(ST, "GetClockFace", function(self, now)
        if tbcFace then return tbcFace end
        return real(self, now)
    end)
end

local function Hold(tto)
    tto = tto or 80
    local now = S.now
    if forever then
        local m = ST.Pool.model
        -- 60 %: the rest (about 45 s at the stub's rates) is more than 25 %
        -- away from the 80 s time, so the Rest text has words (review S2)
        local mana = m.max * 0.6
        m.casting = m.casting or 5
        local spend = mana / tto + m.casting
        m:Anchor(now, mana, "e2e")
        m.lastSpend = now
        m.fight = { start = now - 20, spent = spend * 20, casts = 5, fsrTime = 20 }
        local latch = ST.Clock.SteadyLatch and ST.Clock:SteadyLatch()
        if type(latch) == "table" then for k in pairs(latch) do latch[k] = nil end end
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    else
        tbcFace = TbcFace(tto)
        S.mana = math.floor(MAX * 0.4)
        ST.Regen.fsrEnd = now + 5
    end
end
local function Release()
    if forever then
        local m = ST.Pool.model
        m.fight = nil
        m:Anchor(S.now, m.max, "e2e done")
    else
        tbcFace = nil
        S.mana = MAX
    end
end

-- which moment each control is judged at: Warn colours need a running-out
-- time under a minute; everything else the 80 s one (the time's own colour)
local MOMENT = { warn = 40 }
local PREVIEW_CHIP = { warn = "low" }

--------------------------------------------------------------------------------
-- The pane, opened through the dashboard
--------------------------------------------------------------------------------
local pane, p
pcall(function()
    ST:SelectView("settings", "clock")
    for _, f in ipairs(S.allFrames) do if f.clockSettings then pane, p = f, f.clockSettings end end
end)

--------------------------------------------------------------------------------
-- Operating a control through its widget
--------------------------------------------------------------------------------
local function HexRGB(h) return ST.ClockBar.HexRGB(h) end

local function Fire(c, value)
    local w = p.widgets[c.id]
    if not w then return false, "no widget" end
    if c.kind == "buttons" then
        for _, b in ipairs(w.buttons) do
            if b.id == value then b:GetScript("OnClick")(b, "LeftButton"); return true end
        end
        return false, "no button " .. tostring(value)
    elseif c.kind == "slider" then
        local eb = w.currentEditBox
        eb:SetText(tostring(value))
        eb:GetScript("OnEnterPressed")(eb)
        return true
    elseif c.kind == "dropdown" then
        for i, it in ipairs(w.items) do
            if it.id == value and w.rows[i] then w.rows[i]:GetScript("OnClick")(w.rows[i]); return true end
        end
        return false, "not listed: " .. tostring(value)
    elseif c.kind == "check" then
        w:SetChecked(value == true)
        w:GetScript("OnClick")(w)
        return true
    elseif c.kind == "number" then
        w:SetText(tostring(value))
        w:GetScript("OnEnterPressed")(w)
        return true
    elseif c.kind == "step" then
        w:GetScript("OnClick")(w, "LeftButton")
        return true
    elseif c.kind == "swatch" then
        local hex, a = value, 1
        if type(value) == "table" then hex, a = value[1], value[2] end
        local r, g, b = HexRGB(hex)
        picker.info = nil
        w:GetScript("OnClick")(w, "LeftButton")
        if not picker.info then return false, "the picker did not open" end
        picker.cur = { r, g, b, a }
        picker.info.swatchFunc()
        return true
    end
    return false, "kind " .. tostring(c.kind)
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- the dotted paths where two snapshots differ (for a failure's detail)
local function DiffPaths(a, b, pre, out)
    out = out or {}
    pre = pre or ""
    if type(a) ~= "table" or type(b) ~= "table" then
        if not Same(a, b) then out[#out + 1] = pre .. "=" .. tostring(a) .. "/" .. tostring(b) end
        return table.concat(out, ", ")
    end
    local keys = {}
    for k in pairs(a) do keys[k] = true end
    for k in pairs(b) do keys[k] = true end
    for k in pairs(keys) do DiffPaths(a[k], b[k], pre == "" and tostring(k) or (pre .. "." .. tostring(k)), out) end
    return table.concat(out, ", ")
end

-- a Drawn() field by a dotted name ("text.mana.size"; "text.*.face": any text)
local function Field(snap, path)
    local t = snap
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end
-- T145 review S2: a text's change counts only when the text has something to
-- draw -- every snapshot where it is shown holds non-empty words, and it is
-- shown in at least one (an empty Rest text moved is nothing on screen).
local function Visible(s0, s1, kind)
    local shown = 0
    for _, s in ipairs({ s0, s1 }) do
        local t = s.text and s.text[kind]
        if t and t.shown then
            if type(t.words) ~= "string" or t.words == "" then return false end
            shown = shown + 1
        end
    end
    return shown > 0
end
local function Differs(s0, s1, affects)
    for _, path in ipairs(affects) do
        if path:find("%*") then
            local pre, post = path:match("^(.-)%.%*%.(.+)$")
            for _, kind in ipairs(Store.KINDS) do
                local f = pre .. "." .. kind .. "." .. post
                if not Same(Field(s0, f), Field(s1, f)) and (pre ~= "text" or Visible(s0, s1, kind)) then
                    return true
                end
            end
        else
            local kind = path:match("^text%.([^.]+)%.")
            if not Same(Field(s0, path), Field(s1, path)) and (kind == nil or Visible(s0, s1, kind)) then
                return true
            end
        end
    end
    return false
end

-- The values a control is operated with from a look: each sample that
-- differs from the current value; a step control is clicked round its cycle.
local function ValuesFrom(c, look)
    local now = c.get(look)
    local out = {}
    if c.kind == "step" then
        for _ = 1, #c.values - 1 do out[#out + 1] = "click" end
        return out
    end
    for _, v in ipairs(c.values) do
        if not Same(v, now) then out[#out + 1] = v end
    end
    return out
end

--------------------------------------------------------------------------------
T.section("0. the pane and the live clock")
--------------------------------------------------------------------------------
check("Settings -> Clock opened through the dashboard; the live clock has its renderer",
    p ~= nil and pane:IsVisible() and R ~= nil and type(CS.CONTROLS) == "table" and #CS.CONTROLS > 60,
    tostring(p) .. " controls " .. tostring(CS.CONTROLS and #CS.CONTROLS))

Try("the pane has the mockup's controls, one to one (Bar 10, Texts 7 x 8 + Time as + Warn colours)", function()
    local ids = {}
    for _, c in ipairs(CS.CONTROLS) do ids[#ids + 1] = c.id end
    local bar = table.concat(ids, ",", 1, 10)
    local want = "width,height,shape,frame,texture,font,fill,fillColour,back,line"
    local widgets = 0
    for _, c in ipairs(CS.CONTROLS) do if p.widgets[c.id] then widgets = widgets + 1 end end
    return bar == want and #ids == 10 + 7 * 8 + 2 and widgets == #ids and #p.presetButtons == 2
        and p.undoButton ~= nil and #p.chips == 5,
        string.format("%s; %d controls, %d widgets", bar, #ids, widgets)
end)

--------------------------------------------------------------------------------
T.section("E1-E3. every control, from every base look, on the live clock and the preview")
--------------------------------------------------------------------------------
local function UseBase(base)
    D.UseLook(ST, base.look)
end

local function RunE1(target)
    local inert, multi, invalid, hiddenBad, shownBad, failed = {}, {}, {}, {}, {}, {}
    local n = 0
    for _, base in ipairs(BASES) do
        UseBase(base)
        local look0 = Store.Look()
        for _, c in ipairs(CS.CONTROLS) do
            UseBase(base)
            local w = p.widgets[c.id]
            local vis = c.visible(look0)
            -- E2
            if target == "live" then
                if not vis and w and w:IsShown() then hiddenBad[#hiddenBad + 1] = base.name .. ": " .. c.id end
                if vis and c.id ~= "fill" and w and not w:IsShown() then shownBad[#shownBad + 1] = base.name .. ": " .. c.id end
            end
            if vis then
                for _, v in ipairs(ValuesFrom(c, Store.Look())) do
                    local snap
                    if target == "live" then
                        Hold(MOMENT[c.id])
                        S.Tick(0.5)
                        snap = function() return R:Drawn() end
                    else
                        CS.Chip(p, PREVIEW_CHIP[c.id] or "fight")
                        S.Tick(0.5)
                        snap = function() return p.view:Drawn() end
                    end
                    local s0 = snap()
                    local e0 = events
                    local okF, why = Fire(c, v)
                    S.Tick(0.5)
                    local s1 = snap()
                    n = n + 1
                    local tag = base.name .. ": " .. c.id .. " = " .. tostring(type(v) == "table" and v[1] or v)
                    if not okF then
                        failed[#failed + 1] = tag .. " (" .. tostring(why) .. ")"
                    else
                        if not Differs(s0, s1, c.affects) then inert[#inert + 1] = tag end
                        if events - e0 ~= 1 then multi[#multi + 1] = tag .. " fired " .. (events - e0) end
                        local okV, note = Store.Valid(ST.db.clockLook)
                        if not okV then invalid[#invalid + 1] = tag .. ": " .. tostring(note) end
                    end
                end
            end
        end
    end
    Release()
    return { n = n, inert = inert, multi = multi, invalid = invalid, hiddenBad = hiddenBad, shownBad = shownBad,
        failed = failed }
end

-- The comparison is not blind: with nothing operated, the same moment twice
-- draws the same snapshot, so no control's fields differ by themselves.
Try("E1's comparison: the same moment twice, nothing operated, draws the same clock (no field differs)", function()
    UseBase(BASES[3])
    Hold(); S.Tick(0.5); Hold(); S.Tick(0.5)
    local s0 = R:Drawn()
    Hold(); S.Tick(0.5)
    local s1 = R:Drawn()
    local blind = {}
    for _, c in ipairs(CS.CONTROLS) do if Differs(s0, s1, c.affects) then blind[#blind + 1] = c.id end end
    Release()
    return Same(s0, s1) and #blind == 0 and s0.line.shown == false and s0.text.time.shown,
        DiffPaths(s0, s1) .. " " .. table.concat(blind, ", ")
end)

local live, preview
Try("E1 (live): every visible control changes what the live clock draws -- the inert list is empty", function()
    live = RunE1("live")
    return #live.inert == 0 and #live.failed == 0 and live.n > 150,
        string.format("%d operations; inert: %s; not operated: %s", live.n, table.concat(live.inert, "; "),
            table.concat(live.failed, "; "))
end)
Try("E1 (preview): every visible control changes what the pane's preview draws -- the inert list is empty", function()
    preview = RunE1("preview")
    return #preview.inert == 0 and #preview.failed == 0 and preview.n > 150,
        string.format("%d operations; inert: %s; not operated: %s", preview.n, table.concat(preview.inert, "; "),
            table.concat(preview.failed, "; "))
end)
Try("E2: a control the look makes inert is hidden (an off text's fields, Custom's swatch, Time as / Warn), "
        .. "every other one shown", function()
    local hiddenN = 0
    for _, base in ipairs(BASES) do
        for _, c in ipairs(CS.CONTROLS) do if not c.visible(base.look) then hiddenN = hiddenN + 1 end end
    end
    return live and #live.hiddenBad == 0 and #live.shownBad == 0 and hiddenN > 20,
        string.format("%d hidden by the bases; shown while inert: %s; hidden while live: %s", hiddenN,
            table.concat(live and live.hiddenBad or {}, "; "), table.concat(live and live.shownBad or {}, "; "))
end)
Try("E3: every operation fires exactly one CLOCK_LOOK and leaves a valid store", function()
    local m, v = {}, {}
    for _, r in ipairs({ live or {}, preview or {} }) do
        for _, x in ipairs(r.multi or {}) do m[#m + 1] = x end
        for _, x in ipairs(r.invalid or {}) do v[#v + 1] = x end
    end
    return live and preview and #m == 0 and #v == 0, table.concat(m, "; ") .. " | " .. table.concat(v, "; ")
end)

-- T145 review N4: on the Live chip the preview's mana texts are the game's,
-- as on the live clock, never the model's words beside them
Try("E1 (preview, Live): the preview's power texts are drawn as the live clock draws them (review N4)", function()
    UseBase(BASES[3])
    Hold(); S.Tick(0.5)
    CS.Chip(p, "live")
    S.Tick(0.5)
    local live, pv = R:Drawn(), p.view:Drawn()
    local bad = {}
    for _, kind in ipairs({ "mana", "manaMax", "pct" }) do
        local a, b = live.text[kind].words, pv.text[kind].words
        if a ~= b then bad[#bad + 1] = kind .. " " .. tostring(a) .. "/" .. tostring(b) end
    end
    CS.Chip(p, "fight")
    Release()
    return #bad == 0 and live.text.mana.words ~= nil, table.concat(bad, "; ") .. " live mana " .. tostring(live.text.mana.words)
end)

--------------------------------------------------------------------------------
T.section("E4. presets")
--------------------------------------------------------------------------------
Try("E4: each preset from each base keeps the time and the line on, draws the line mid-rule; Undo restores "
        .. "the store and the clock exactly", function()
    local bad = {}
    for _, base in ipairs(BASES) do
        for _, b in ipairs(p.presetButtons) do
            UseBase(base)
            Hold()
            S.Tick(0.5) -- the host's own rule shows the clock (it was full and hidden before)
            Hold()
            S.Tick(0.5)
            local store0, s0 = Copy(ST.db.clockLook), R:Drawn()
            b:GetScript("OnClick")(b)
            Hold()
            S.Tick(0.5)
            local look = Store.Look()
            local s1 = R:Drawn()
            local tag = base.name .. " -> " .. b.id
            if not (look.line == true and look.texts.time.on == true) then bad[#bad + 1] = tag .. ": P2" end
            if not (s1.line.shown and s1.line.x) then bad[#bad + 1] = tag .. ": no line mid-rule" end
            if not (s1.text.time.shown and type(s1.text.time.words) == "string") then bad[#bad + 1] = tag .. ": no time" end
            if not (p.undoButton:IsShown()) then bad[#bad + 1] = tag .. ": no Undo offered" end
            p.undoButton:GetScript("OnClick")(p.undoButton)
            UseBase({ look = ST.db.clockLook }) -- the same table: one more Apply, no change
            Hold()
            S.Tick(0.5)
            local s2 = R:Drawn()
            if not Same(store0, ST.db.clockLook) then bad[#bad + 1] = tag .. ": the store differs after Undo" end
            if not Same(s0, s2) then bad[#bad + 1] = tag .. ": the clock differs after Undo (" .. DiffPaths(s0, s2) .. ")" end
            if p.undoButton:IsShown() then bad[#bad + 1] = tag .. ": Undo still offered" end
        end
    end
    Release()
    return #bad == 0, table.concat(bad, "; ")
end)

--------------------------------------------------------------------------------
T.section("E5. a fight end to end; the refill")
--------------------------------------------------------------------------------
local function Words() return D.TimeWords(ST) end

for _, base in ipairs({ BASES[1], BASES[2] }) do
    Try("E5 on " .. base.name .. ": never 0s / 0:00, FULL within a tick of max and while there, "
            .. "a refill always FULL ..., an OOM time changes at most once a second", function()
        D.UseLook(ST, base.look)
        if forever then ST.Pool.model:Anchor(S.now, ST.Pool.model.max, "e5") end
        local trace = D.E5(ST, S)
        local ok, why = D.E5Verdict(trace)
        local sawFull = false
        for _, e in ipairs(trace) do if e.words == "FULL" then sawFull = true end end
        return ok and sawFull and #trace > 40, why or (#trace .. " ticks")
    end)
end

-- U3's open point 3: out of combat, below max, the clock regenerating. The
-- game fires UNIT_POWER_FREQUENT while the pool moves (every 0.2 s here), so
-- the quiet-pool rule does not cut the refill short.
Try("E5b: out of combat, regenerating, the time on screen reads FULL m:ss counting down -- never a bare "
        .. "number, never a zero; at full the clock goes (over 95 %) and its words are FULL", function()
    D.UseLook(ST, BASES[1].look)
    local trace, words = {}, {}
    if forever then
        local m = ST.Pool.model
        m.fight = nil
        m:Anchor(S.now, m.max * 0.5, "e5b")
        m.lastSpend = S.now - 10
    else
        S.mana = math.floor(MAX * 0.5)
        ST.Regen.fsrEnd = S.now - 10
    end
    local guard = 0
    local atMax
    while guard < 2400 do
        guard = guard + 1
        for _ = 1, 2 do
            -- TBC: the pool moves first and the game says so, then time
            -- passes (the clock paints on the tick what the pool is then)
            if not forever and S.mana < MAX then
                S.mana = math.min(MAX, S.mana + 10)
                S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
            end
            local full = forever and ST.Pool.model.mana >= ST.Pool.model.max or (not forever and S.mana >= MAX)
            if not full then S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
            S.Tick(0.25)
        end
        local w = Words()
        local mana = forever and ST.Pool.model.mana or S.mana
        local max = forever and ST.Pool.model.max or MAX
        trace[#trace + 1] = { w = w, mana = mana, max = max, shown = D.Frame(ST):IsShown() }
        if mana >= max then
            atMax = atMax or guard
            if guard - atMax >= 10 then break end
        end
    end
    -- what the user sees: the clock is on screen out of combat under 90 %
    -- and hides over 95 % (UI/Visibility.lua), so only a shown tick is read
    local bad, counting, last, shownTicks = nil, 0, nil, 0
    for i, e in ipairs(trace) do
        local w = e.w
        if e.shown then shownTicks = shownTicks + 1 end
        if e.shown and w == nil then bad = bad or ("tick " .. i .. ": no time") end
        if e.shown and type(w) == "string" then
            if w:match("^%d") or w == "0s" or w == "0:00" or w:find("FULL 0:00", 1, true) or w:find("FULL 0s", 1, true) then
                bad = bad or ("tick " .. i .. ": " .. w)
            end
            if w:match("^FULL %d") then counting = counting + 1 end
            -- FULL within one tick of the pool at max (spec E5): TBC's widget
            -- paints on its own 0.25 s frame, before the tick that reads the
            -- pool, so the first tick at max may still show the last refill
            local prev = trace[i - 1]
            if e.mana >= e.max and prev and prev.mana >= prev.max and w ~= "FULL" then
                bad = bad or ("tick " .. i .. " at max for a tick reads " .. w)
            end
        end
        if e.shown then words[#words + 1] = tostring(w) end
    end
    -- at full the clock is down; the words it would say are FULL
    local face = ST.ClockFace.Current(S.now)
    last = CW.Build(face, Store.Look(), nil, S.now, nil, forever and ST.Pool:QuietFull(S.now) or false).time.text
    local hidden = not D.Frame(ST):IsShown()
    return bad == nil and counting >= 3 and last == "FULL" and hidden and atMax ~= nil and shownTicks > 10,
        (bad or "") .. " counting " .. counting .. ", at full " .. tostring(last) .. ", hidden " .. tostring(hidden)
        .. "; " .. table.concat(words, ",", 1, math.min(#words, 12))
end)

if forever then
    -- a fight entered below max with light casting: the model's net is a
    -- refill, so the time is FULL m:ss in a fight too
    Try("E5c (Forever): a fight entered at half a pool with light casting reads FULL m:ss, then FULL", function()
        D.UseLook(ST, BASES[1].look)
        local m = ST.Pool.model
        m:Anchor(S.now, m.max * 0.5, "e5c")
        m.lastSpend = S.now - 10
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") -- the pool moved: not quiet
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        -- the rates in a fight are the last plain reading; a cast every 3 s
        -- keeps the rule running, so the pool fills at the casting rate
        -- (35 / s) against a spend of 5 / s: about two minutes to full
        m:SetRegen(70, 35)
        local seen, bad, atMax = {}, nil, nil
        for i = 1, 600 do
            S.Tick(0.5)
            if i % 6 == 0 then m:Spend(15, S.now) end
            S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
            local w = Words()
            seen[#seen + 1] = tostring(w)
            if type(w) == "string" and (w == "0s" or w == "0:00" or w:match("^%d")) then bad = bad or w end
            if m.mana >= m.max then
                atMax = atMax or i
                if i > atMax and w ~= "FULL" then bad = bad or ("at max: " .. tostring(w)) end
                if i - atMax >= 20 then break end
            end
        end
        S.inCombat = false
        S.Fire("PLAYER_REGEN_ENABLED")
        local refill = false
        for _, w in ipairs(seen) do if w:match("^FULL %d") then refill = true end end
        return refill and bad == nil and seen[#seen] == "FULL", (bad or "") .. " " .. table.concat(seen, ",", 1, math.min(#seen, 40))
    end)
end

--------------------------------------------------------------------------------
T.section("E6. the moving line")
--------------------------------------------------------------------------------
Try("E6: eight frames move the line right across every disturbance; hidden within a frame of the rule's "
        .. "end; one driver script throughout", function()
    D.UseLook(ST, BASES[1].look)
    local results, same, hiddenInTime = D.E6(ST, S)
    local stuck = {}
    for _, r in ipairs(results) do if not r.moved then stuck[#stuck + 1] = r.name end end
    return #stuck == 0 and same and hiddenInTime and #results > 20,
        string.format("%d disturbances; stuck: %s; same %s; hidden %s", #results, table.concat(stuck, "; "),
            tostring(same), tostring(hiddenInTime))
end)

Try("E6b: the line keeps moving while each Bar control is operated from the pane mid-rule", function()
    D.UseLook(ST, BASES[2].look)
    local script = R.driver:GetScript("OnUpdate")
    local stuck, n = {}, 0
    if forever then ST.Pool.model:Anchor(S.now, ST.Pool.model.max * 0.5, "e6b") else S.mana = math.floor(MAX * 0.5) end
    S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    S.Tick(0.5)
    for _, c in ipairs(CS.CONTROLS) do
        if not c.text and c.visible(Store.Look()) and c.id ~= "line" then
            for _, v in ipairs(ValuesFrom(c, Store.Look())) do
                D.StartRule(ST, S)
                S.Tick(0.03)
                Fire(c, v)
                local moved = D.Frames(ST, S, 8)
                n = n + 1
                if not moved then stuck[#stuck + 1] = c.id .. " = " .. tostring(type(v) == "table" and v[1] or v) end
            end
        end
    end
    local same = R.driver:GetScript("OnUpdate") == script
    Release()
    return #stuck == 0 and same and n > 15, n .. " operations; stuck: " .. table.concat(stuck, "; ")
end)

--------------------------------------------------------------------------------
if forever then
T.section("E7. the quiet pool (Forever)")
--------------------------------------------------------------------------------
    local Pool = ST.Pool
    local function Setup(manaShare, base)
        local m = Pool.model
        m.fight = nil
        m:SetRegen(base, base / 2)
        m:Anchor(S.now, m.max * manaShare, "e7")
        m.lastSpend = S.now - 20
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
        return m
    end
    local function Run(seconds, every)
        local t, next = 0, 0
        while t < seconds - 1e-9 do
            S.Tick(0.1)
            t = t + 0.1
            if every and t >= next - 1e-9 then S.Fire("UNIT_POWER_FREQUENT", "player", "MANA"); next = t + every end
        end
    end
    -- the pool's own tick reads GetManaRegen out of combat: hold the stub's
    -- rates to the case's
    local realRegen = _G.GetManaRegen
    local function Rates(base) _G.GetManaRegen = function() return base, base / 2 end; ST.API.Invalidate("GetManaRegen") end

    Try("E7: events every 0.2 s at 80 %: no anchor", function()
        Rates(0.001)
        local m = Setup(0.8, 0.001)
        local a0 = Pool.quietAnchors
        Run(6, 0.2)
        return Pool.quietAnchors == a0 and m.mana < m.max and D.TimeWords(ST) ~= "FULL", tostring(D.TimeWords(ST))
    end)
    Try("E7: the events stop for QUIET outside the rule: anchored at max, the time reads FULL", function()
        Rates(5)
        local m = Setup(0.8, 5)
        local a0 = Pool.quietAnchors
        Run(CW.QUIET + 1, nil)
        return Pool.quietAnchors == a0 + 1 and m.mana >= m.max and D.TimeWords(ST) == "FULL",
            string.format("anchors %d, mana %s / %s, time %s", Pool.quietAnchors - a0, tostring(m.mana), tostring(m.max),
                tostring(D.TimeWords(ST)))
    end)
    Try("E7: the events stop inside the rule: no anchor", function()
        Rates(5)
        local m = Setup(0.5, 5)
        local a0 = Pool.quietAnchors
        m:Spend(1, S.now)
        Run(5 + CW.QUIET - 0.5, nil)
        return Pool.quietAnchors == a0 and m.mana < m.max, "anchors " .. (Pool.quietAnchors - a0)
    end)
    Try("E7: base x QUIET under 2: no anchor", function()
        local base = (CW.QUIET_POINTS - 0.1) / CW.QUIET
        Rates(base)
        local m = Setup(0.5, base)
        local a0 = Pool.quietAnchors
        Run(CW.QUIET + 2, nil)
        return Pool.quietAnchors == a0 and m.mana < m.max, "anchors " .. (Pool.quietAnchors - a0)
    end)
    -- T145 review N1: the tick no longer hands the bar its range twice a second
    Try("E7: the tick sets the bar's range only when the max moved, else every RANGE_EVERY s (review N1)", function()
        local d = R.draw
        local real, calls = d.poolMax, 0
        d.poolMax = function(...) calls = calls + 1; return real(...) end
        Run(1, 0.2) -- settle
        calls = 0
        Run(ST.Clock.RANGE_EVERY - 1, 0.2)
        local steady = calls
        calls = 0
        local m = Pool.model
        local oldMax = S.manaMax
        S.manaMax = oldMax + 100
        Run(1, 0.2)
        local moved = calls
        S.manaMax = oldMax
        Run(1, 0.2)
        d.poolMax = real
        return steady <= 1 and moved >= 1 and m.max == oldMax,
            string.format("%d range calls over %d s steady, %d after the max moved", steady, ST.Clock.RANGE_EVERY - 1, moved)
    end)
    -- T145 review N5: a dead or ghost player's pool does not move either
    Try("E7: dead or a ghost, quiet for QUIET outside the rule: no anchor (review N5)", function()
        Rates(5)
        local m = Setup(0.35, 5)
        local a0 = Pool.quietAnchors
        S.units.player.dead = true
        S.Fire("PLAYER_DEAD")
        Run(CW.QUIET + 1, nil)
        local deadOK = Pool.quietAnchors == a0 and m.mana < m.max
        -- alive again at 35 %: no anchor until a fresh power event, then the
        -- quiet rule as before
        S.units.player.dead = false
        S.Fire("PLAYER_ALIVE")
        Run(CW.QUIET + 1, nil)
        local aliveOK = Pool.quietAnchors == a0 and m.mana < m.max
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
        Run(CW.QUIET + 1, nil)
        local after = Pool.quietAnchors == a0 + 1
        return deadOK and aliveOK and after,
            string.format("dead %s, alive %s, after a fresh event %s", tostring(deadOK), tostring(aliveOK), tostring(after))
    end)
    _G.GetManaRegen = realRegen
    ST.API.Invalidate("GetManaRegen")
end

T.done()
