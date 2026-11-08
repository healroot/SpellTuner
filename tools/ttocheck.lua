-- tools/run.sh tools/ttocheck.lua
--
-- T58 (P14, review A28): the TBC mana clock (Engine/TTO.lua) through a
-- scripted spend and regen stream -- the most log-debugged code in the
-- project, verified until now only in-game, because the TBC stub answered
-- UnitAffectingCombat with false always and the TTO polled it, so every suite
-- that drove a fight had the clock believe it was out of combat.
--
-- What is held, in order:
--   1. the stub's combat state answers the regen events (and the kernel's
--      ST.inCombat with it);
--   2. out of combat at full: FULL, no rest segment, the widget hidden;
--   3. a /reload mid-fight: the kernel's flag seeded true with no regen event
--      and the poll left saying no -- the clock, the widget, the pull budget,
--      the Advisor's two checks and the gear reminder all read the flag;
--   4. the pull budget's median (the lower middle, never the caller's order);
--   5. warmup -> oom after three priced casts, "~" until the estimate is
--      stable, the rest segment's 25% rule and its value, the arrow while
--      casting;
--   6. the confidence gate: the bound at once, the digits back only after
--      two confident ticks;
--   7. casting stops: "^", and rest = deficit / base out of the FSR;
--   8. hold, 9. full (never a rest segment next to FULL), 10. bad news at
--      once; 11. leaving combat: FULL with the time to full;
--   12.-13. T82 (C4, mockup M6): with the theme loaded as the TBC TOC lists
--      it, the widget is the Forever clock's panel, font and 160 x 4 bar
--      (still the five-second rule), and the unlock preview is in the accent;
--      since T93 the font check reads the three fixed segments, and the
--      preview is the view's message line over them;
--   14.-16. T93 (docs/SPEC-next.md 7.1 F2, decisions 14 and 17): the label,
--      the value and the rest segment keep their x across 59s -> 1:00 ->
--      >10m; what the segments draw is the line's text byte for byte (`vv`
--      included); a left-click opens the window out of combat only, and the
--      mover seam (ST.ClockWidget: ApplyPoint, ResetPosition, Preview).
-- The stream is real events -- UNIT_SPELLCAST_SUCCEEDED priced by
-- Data/SpellData.lua, UNIT_POWER_UPDATE, the regen events -- and a scripted
-- GetManaRegen; nothing in the model is replaced.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-66s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
local function Said(pat, from)
    local n = 0
    for i = (from or 1), #chat do if chat[i]:find(pat) then n = n + 1 end end
    return n
end

-- The TBC harness loads no UI file but UI/Summary.lua; the widget and the
-- Advisor are loaded here, after login, and handed the MD_READY they missed
-- (only their own handlers, captured as they register -- re-firing MD_READY
-- would re-run every other module's).
do
    local ready, realReg = {}, ST.RegisterCallback
    ST.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    -- T68 (P24): UI/Visibility.lua holds the widget's show/hide rule, so it
    -- loads before UI/Widget.lua, as in SpellTuner_TBC.toc.
    -- T82 (C4): and the theme after the kit, as the TOC lists it since C1.
    -- T93: the clock's renderer before the widget, as the TOC lists it; since
    -- T145c the store and the renderer (UI/ClockStore.lua, UI/ClockBar.lua).
    local files = { "UI/Style.lua", "UI/Theme_Flat.lua", "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/Visibility.lua",
        "UI/ClockStore.lua", "UI/ClockBar.lua" }
    files[#files + 1] = "UI/Widget.lua"
    files[#files + 1] = "UI/Advisor.lua"
    S.Load(files, "SpellTuner", ST)
    ST.RegisterCallback = realReg
    -- T82: the stub's CreateFontString takes no template and SetPoint keeps
    -- nothing (geometry off); while the widget is made, each font string
    -- keeps its template and each region its first point, so check 12 can
    -- read the widget's font and layout.
    local FrameMT = getmetatable(UIParent)
    local realCFS, realSP = FrameMT.CreateFontString, rawget(FrameMT, "SetPoint")
    FrameMT.CreateFontString = function(self, name, layer, tmpl)
        local fs = realCFS(self, name, layer, tmpl)
        fs.template = tmpl
        return fs
    end
    FrameMT.SetPoint = function(self, ...)
        self.firstPoint = self.firstPoint or { ... }
        self.lastPoint = { ... } -- T93: the anchor a region holds now (check 14)
        if realSP then return realSP(self, ...) end
    end
    -- T145c: the Bar is the only layout; the checks below read the default look
    ST.db.clockLook = nil
    for _, fn in ipairs(ready) do fn() end
    FrameMT.CreateFontString, FrameMT.SetPoint = realCFS, realSP
end
local W = _G.SpellTunerWidget

-- A scripted regen: RM:Refresh reads GetManaRegen on every tick. Low, so the
-- casts below drain faster than it refills (net ~50/s: a clock of a minute
-- or two, the range the display layer was tuned on).
local regenBase, regenCast = 10, 5
function GetManaRegen() return regenBase, regenCast end

local SD = ST.SpellData
local HT5 = 5189 -- Healing Touch rank 5: 219 mana after the harness's talents
local function Cast(id)
    S.mana = S.mana - SD:GetCost(id)
    S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", id)
    S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
end
local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Shown() return Plain(ST:GetDisplayString()) end
local function State() return ST:GetManaState() end
local function Ticks(n) for _ = 1, n do S.Tick(0.5) end end
-- "1:15" -> 75, "50s" -> 50, ">10m" -> nil
local function Secs(txt)
    if not txt then return nil end
    local m, s = txt:match("^(%d+):(%d%d)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return tonumber(txt:match("^(%d+)s$"))
end
-- TTO.lua's own rendering of a rest value (Quantize, then FmtTime)
local function RestText(r)
    local step = r < 30 and 1 or 5
    local q = step * math.floor(r / step + 0.5)
    if q >= 60 then return string.format("%d:%02d", math.floor(q / 60), math.floor(q % 60)) end
    return string.format("%ds", math.floor(q))
end

Ticks(4)

--------------------------------------------------------------------------------
-- 1. the stub answers the regen events, and the kernel's flag follows them
--------------------------------------------------------------------------------
check("stub: out of combat before any regen event",
    UnitAffectingCombat("player") == false and InCombatLockdown() == false and ST.inCombat == false)
S.Fire("PLAYER_REGEN_DISABLED")
check("stub: PLAYER_REGEN_DISABLED -> UnitAffectingCombat, InCombatLockdown true",
    UnitAffectingCombat("player") == true and InCombatLockdown() == true)
check("kernel: ST.inCombat true on PLAYER_REGEN_DISABLED", ST.inCombat == true)
S.Fire("PLAYER_REGEN_ENABLED")
check("stub: PLAYER_REGEN_ENABLED -> both false again, ST.inCombat false",
    UnitAffectingCombat("player") == false and InCombatLockdown() == false and ST.inCombat == false)
Ticks(2)

--------------------------------------------------------------------------------
-- 2. out of combat at full mana
--------------------------------------------------------------------------------
check("full, out of combat: mode fullnow, shown FULL, no rest segment",
    State().mode == "fullnow" and Shown() == "FULL" and State().inCombat == false, Shown())
check("widget: locked, out of combat, full mana -> hidden", W and not W:IsShown())

--------------------------------------------------------------------------------
-- 3. a /reload mid-fight. PLAYER_REGEN_DISABLED already fired before the
-- reload; Core.lua seeds ST.inCombat at MD_READY through the adapter. The
-- flag is set here the way that seed sets it, and the stub's own poll is left
-- saying "out of combat", so only a reader of the kernel's flag passes.
--------------------------------------------------------------------------------
local realHist = ST.fightHistory
ST.fightHistory = {
    { avgSpendRate = 10, duration = 30 }, { avgSpendRate = 20, duration = 30 },
    { avgSpendRate = 5, duration = 30 },  { avgSpendRate = 40, duration = 30 },
}
check("pull budget out of combat: tooltip lines", #ST.PullBudget:Lines() > 0)
-- 4. the median: 300, 600, 150, 1200 -> the lower middle of 150 300 600 1200
local e = ST.PullBudget:Estimate()
check("pull budget: median of an even count is the lower middle (300)",
    e and e.perPull == 300 and e.n == 4, e and string.format("%s of %d", tostring(e.perPull), e.n))
check("pull budget: the history's own order is untouched",
    ST.fightHistory[1].avgSpendRate == 10 and ST.fightHistory[3].avgSpendRate == 5)

ST.inCombat = true
Ticks(1)
check("reload mid-fight: the poll says no, the kernel's flag says yes",
    UnitAffectingCombat("player") == false and ST.inCombat == true)
check("reload mid-fight: the clock projects in combat at once (warmup)",
    State().inCombat == true and State().mode == "warmup" and Shown():find("^OOM %.%.%.") ~= nil, Shown())
check("reload mid-fight: the widget shows at full mana", W and W:IsShown())
check("reload mid-fight: no pull-budget lines in combat", #ST.PullBudget:Lines() == 0)

local mark = #chat + 1
ST.cdb.mp5 = { at = 1700000000, mp5 = 12 }
S.Fire("PLAYER_EQUIPMENT_CHANGED")
check("reload mid-fight: no gear reminder in combat", Said("item mp5 was measured", mark) == 0)

-- The Advisor: Innervate known, the deficit swallows it -> the alert; low
-- mana while in combat is not a drink moment.
S.known[29166] = true
S.mana = 1000
local plays = W and W.pulse and W.pulse.plays or 0
Ticks(12)
check("reload mid-fight: the Advisor calls Innervate", Said("Innervate now", mark) == 1,
    tostring(Said("Innervate now", mark)))
check("...and that alert, the only one, pulses the widget",
    Said("Innervate now", mark) == 1 and W and W.pulse and W.pulse.plays == plays + 1)
check("reload mid-fight: no drink reminder in combat", Said("Drink", mark) == 0)

ST.inCombat = false
Ticks(1)
check("out of combat again: the clock leaves combat", State().inCombat == false and State().mode ~= "warmup",
    State().mode)
S.Fire("PLAYER_EQUIPMENT_CHANGED")
check("out of combat: the gear reminder, once", Said("item mp5 was measured", mark) == 1)
Ticks(12)
check("out of combat, 14% mana, standing still: the drink reminder", Said("Drink", mark) == 1,
    tostring(Said("Drink", mark)))
check("pull budget out of combat again: tooltip lines", #ST.PullBudget:Lines() > 0)

ST.fightHistory = realHist
S.known[29166] = nil
S.mana = S.manaMax
S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
Ticks(12) -- past the five-second rule the drain above never started (no power event)
check("back at full: FULL, widget hidden", Shown() == "FULL" and W and not W:IsShown(), Shown())

--------------------------------------------------------------------------------
-- 5. warmup -> oom through a steady stream: one Healing Touch every 3.5 s
--------------------------------------------------------------------------------
S.Fire("PLAYER_REGEN_DISABLED")
Ticks(1)
check("pull: warmup, shown 'OOM ...'", State().mode == "warmup" and Shown():find("^OOM %.%.%.") ~= nil, Shown())
check("warmup: the rest segment is shown (nothing to compare against)", Shown():find("  rest ") ~= nil, Shown())

local log = {}       -- every tick: { t, mode, shown, state }
local modeAfter = {} -- cast number -> mode on the tick after it
local casts = 0
local function Step(castNow)
    if castNow then Cast(HT5); casts = casts + 1 end
    S.Tick(0.5)
    local st = State()
    log[#log + 1] = { t = S.now, mode = st.mode, shown = Shown(), st = st, casting = true }
    if castNow then modeAfter[casts] = st.mode end
end
for i = 1, 100 do Step(i % 7 == 1) end

check("warmup holds through two priced casts", modeAfter[1] == "warmup" and modeAfter[2] == "warmup",
    tostring(modeAfter[1]) .. ", " .. tostring(modeAfter[2]))
check("the third priced cast: oom at once", modeAfter[3] == "oom", tostring(modeAfter[3]))

local firstOom, stableClean, tilde, restHidden, restOk, restBad = nil, false, false, false, 0, nil
local up, down = 0, 0
for _, r in ipairs(log) do
    if r.mode == "oom" then
        firstOom = firstOom or r
        local num = r.shown:match("^OOM (~?[%d:s]+)")
        if num and num:sub(1, 1) == "~" then tilde = true end
        if r.st.stable and num and num:sub(1, 1) ~= "~" then stableClean = true end
        if r.shown:find(" %^") then up = up + 1 end
        if r.shown:find(" v") then down = down + 1 end
        local v = Secs(num and num:gsub("^~", ""))
        local seg = r.shown:match("  rest (%S+)$")
        if v and r.st.rest then
            local far = math.abs(r.st.rest - v) / math.max(v, 1) >= 0.25
            if not far and not seg then restHidden = true end
            if far and seg == RestText(r.st.rest) then restOk = restOk + 1
            elseif far or seg then restBad = restBad or r.shown end
        end
    end
end
check("oom: digits with '~' while the estimate is not stable", firstOom and not firstOom.st.stable
    and firstOom.shown:find("^OOM ~%d") ~= nil and tilde, firstOom and firstOom.shown)
check("oom: once stable, the digits lose the '~'", stableClean)
check("rest: hidden within 25% of the clock", restHidden)
check("rest: shown beyond 25%, as the quantized time to full", restOk > 0 and restBad == nil,
    restBad or tostring(restOk))
check("arrow while casting steadily: 'v' seen, never '^'", down > 0 and up == 0,
    string.format("v %d, ^ %d", down, up))

--------------------------------------------------------------------------------
-- 6. the confidence gate (db.oomConfidence): the bound at once, the digits
-- back only after two confident ticks
--------------------------------------------------------------------------------
local rel = State().rel
ST.db.oomConfidence = rel / 2
Ticks(1)
check("rel above the gate: not confident, the bound at once",
    State().confident == false and Shown():find("^OOM >[%d:s]+ =") ~= nil, Shown())
Ticks(2)
check("...and it stays the bound", Shown():find("^OOM >") ~= nil, Shown())
ST.db.oomConfidence = 0.7
Ticks(1)
check("gate restored: one confident tick still shows the bound",
    State().confident == true and Shown():find("^OOM >") ~= nil, Shown())
Ticks(1)
check("the second confident tick brings the digits back", Shown():find("^OOM %d") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 7. casting stops: the clock climbs, and rest is the plain time to full
--------------------------------------------------------------------------------
local stopShown, sawUp = Shown(), false
for _ = 1, 30 do
    S.Tick(0.5)
    if Shown():find(" %^") then sawUp = true end
end
check("casting stops: '^' within 15 s", sawUp, stopShown .. " -> " .. Shown())
local st = State()
local want = (S.manaMax - S.mana) / ST.Regen.base
check("out of the five-second rule: rest = deficit / base regen",
    st.rest and math.abs(st.rest - want) < 1e-6 and ST.Regen:FSRRemaining() == 0,
    string.format("%s vs %.1f", tostring(st.rest), want))

--------------------------------------------------------------------------------
-- 8. hold: regen matched to spend + one sigma, so |net| <= sigma
--------------------------------------------------------------------------------
local rate, sigma = ST.Spend:Estimate()
regenBase, regenCast = rate + sigma, rate + sigma
Ticks(1)
check("hold is better news: the first tick keeps oom", State().mode == "hold" and Shown():find("^OOM ") ~= nil
    and Shown():find("^OOM >") == nil, Shown())
Ticks(1)
check("hold on the second tick: 'OOM >bound ='", State().mode == "hold" and Shown():find("^OOM >[%d:sm]+ =") ~= nil,
    Shown())

--------------------------------------------------------------------------------
-- 9. full: regen well above spend
--------------------------------------------------------------------------------
regenBase, regenCast = 3 * (rate + sigma), 3 * (rate + sigma)
Ticks(2)
check("full in combat: 'FULL <time>', no rest segment beside it",
    State().mode == "full" and Shown():find("^FULL [%d:s]+$") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 10. bad news applies at once
--------------------------------------------------------------------------------
regenBase, regenCast = 10, 5
Ticks(1)
check("regen falls back: oom on the very next tick", State().mode == "oom" and Shown():find("^OOM ") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 11. leaving combat
--------------------------------------------------------------------------------
S.Fire("PLAYER_REGEN_ENABLED")
Ticks(1)
st = State()
check("combat ends: out of combat, 'FULL <time to full>', no rest segment",
    st.inCombat == false and st.mode == "ooc" and Shown():find("^FULL [%d:s]+$") ~= nil, Shown())
check("...the time to full is the deficit over the base rate",
    st.ttf and math.abs(st.ttf - (S.manaMax - S.mana) / ST.Regen.base) < 1e-6,
    string.format("%s", tostring(st.ttf)))
check("widget: below 90% out of combat -> still shown", W and W:IsShown())

--------------------------------------------------------------------------------
-- 12. T82 / T115, re-based by T145c (docs/SPEC-clock-v3.md D1, 2.2): the
-- widget is the Bar -- the frame width x height of the look, the bar the
-- plain pool (UnitPower over its max) in the look's fill, the five-second
-- rule a moving line that runs while the rule does and is hidden after.
--------------------------------------------------------------------------------
local UI = ST.UI
local CB = ST.ClockBar
local R = W and W.renderer
local function Same3(a, b)
    return type(a) == "table" and type(b) == "table" and math.abs(a[1] - b[1]) < 1e-6
        and math.abs(a[2] - b[2]) < 1e-6 and math.abs(a[3] - b[3]) < 1e-6
end
do
    local look = ST.ClockStore and ST.ClockStore.Look() or {}
    local bar = R and R.bar
    S.Fire("PLAYER_REGEN_DISABLED")
    Cast(HT5)
    S.Tick(0.5)
    local inRule = R and R.lineShown == true and type(R.lineX) == "number"
    local x0 = R and R.lineX
    S.Tick(0.5)
    local moved = R and R.lineShown and type(R.lineX) == "number" and type(x0) == "number" and R.lineX > x0
    local manaValue, manaMax = bar and bar.value, bar and bar.maxV
    Ticks(12)
    local after = R and R.lineShown == false
    S.Fire("PLAYER_REGEN_ENABLED")
    local size = W:GetWidth() == look.width and W:GetHeight() == look.height
    local mana = manaValue == S.mana and manaMax == S.manaMax
    local fill = bar and type(bar.barColor) == "table"
    check("widget: the Bar -- width x height of the look, the plain pool, the moving line in the rule and gone after",
        R ~= nil and size and mana and fill and inRule and moved and after,
        string.format("size=%s mana=%s (%s/%s) fill=%s rule=%s moved=%s after=%s", tostring(size), tostring(mana),
            tostring(manaValue), tostring(manaMax), tostring(fill), tostring(inRule), tostring(moved),
            tostring(after)))
end

--------------------------------------------------------------------------------
-- 13. T82: the unlock preview says what it is for in the accent; the texts
-- hidden under it and back after (T145c: the renderer's Message).
--------------------------------------------------------------------------------
do
    local txt = R and R.msg or {}
    local time = R and R.texts and R.texts.time
    ST:ForceWidgetPreview(60)
    S.Tick(0.5)
    local accent = { UI.RGB("accent") }
    local previewText = txt.text
    local previewColor = txt.textColor
    local shownNow = W:IsShown()
    local hidden = time ~= nil and not time:IsShown() and txt.shown == true
    ST:ForceWidgetPreview(0)
    S.Tick(0.5)
    local back = hidden and txt.shown == false and time:IsShown() and type(time.text) == "string"
        and time.text ~= ""
    check("widget: the unlock text is in the accent, the texts under it hidden and back after",
        previewText == "SpellTuner - drag me" and Same3(previewColor, accent) and shownNow and back,
        string.format("%s %s shown=%s hidden=%s back=%s", tostring(previewText),
            previewColor and table.concat(previewColor, ",") or "-", tostring(shownNow), tostring(hidden),
            tostring(back)))
end

--------------------------------------------------------------------------------
-- 14.-16. T93, re-based by T145c: the widget paints ST:GetClockFace() through
-- ST.ClockWords; here that call answers chosen faces, so the paint can be
-- read at exactly 59s, 1:00 and >10m. The texts never move (P5).
--------------------------------------------------------------------------------
local CF = ST.ClockFace
local realFace = ST.GetClockFace
local function PaintFace(face)
    ST.GetClockFace = function() return face end
    S.Tick(0.5)
    ST.GetClockFace = realFace
end
local function OomFace(v, tone)
    return { mode = "oom", label = "OOM", value = v, known = "point", tone = tone, arrow = "v", combat = true,
        modelled = false, mono = false, unstable = false, timeFmt = "auto",
        second = { kind = "rest", label = "rest", value = 130 } }
end
-- what the clock's words say for a face, built as the widget builds them
local function Want(face)
    local out = {}
    ST.ClockWords.Build(face, ST.ClockStore.Look(), nil, GetTime(), out, false)
    return out
end
local function Shown(kind)
    local fs = R and R.texts and R.texts[kind]
    if not fs or not fs:IsShown() then return nil end
    return fs.text
end

do
    local FrameMT = getmetatable(UIParent)
    local realSP = rawget(FrameMT, "SetPoint")
    local sets = 0
    FrameMT.SetPoint = function(self, ...)
        if R and (self == R.texts.time or self == R.texts.rest) then sets = sets + 1 end
        if realSP then return realSP(self, ...) end
    end
    local texts, wants = {}, {}
    for _, f in ipairs({ OomFace(59, "warn"), OomFace(60, "normal"), OomFace(900, "normal") }) do
        PaintFace(f)
        texts[#texts + 1] = Shown("time")
        wants[#wants + 1] = Want(f).time.text
    end
    FrameMT.SetPoint = realSP
    local words = texts[1] ~= nil and texts[1] == wants[1] and texts[2] == wants[2] and texts[3] == wants[3]
        and texts[1] ~= texts[2] and texts[2] ~= texts[3]
    check("T93: the time across 59s -> 1:00 -> >10m is the clock's words, never re-anchored",
        R ~= nil and words and sets == 0,
        string.format("words=%s re-anchored=%d (%s | %s | %s; want %s | %s | %s)", tostring(words), sets,
            tostring(texts[1]), tostring(texts[2]), tostring(texts[3]), tostring(wants[1]), tostring(wants[2]),
            tostring(wants[3])))
end

do
    -- every sample face, and the three above: the drawn time is the words'
    -- bytes, the crit band's included
    local faces = { OomFace(59, "warn"), OomFace(60, "normal"), OomFace(900, "normal") }
    for _, smp in ipairs(CF and CF.SAMPLES or {}) do faces[#faces + 1] = smp.face end
    local bad, n = nil, 0
    for _, f in ipairs(faces) do
        PaintFace(f)
        local want = Want(f).time.text
        local got = Shown("time")
        n = n + 1
        if got ~= want then bad = bad or string.format("%q drawn as %q", tostring(want), tostring(got)) end
    end
    check("T93: the drawn time is the clock's words byte for byte, every sample face",
        n > 3 and R ~= nil and bad == nil, bad)
    S.Tick(0.5) -- the real face again
end

do
    -- decision 17: a left-click opens the window out of combat only, as on
    -- Forever; and the mover seam (ApplyPoint, ResetPosition, Preview) the
    -- TBC widget exposes as ST.ClockWidget, the Forever clock as the same name
    local calls = 0
    local orig = ST.ToggleDashboard
    ST.ToggleDashboard = function() calls = calls + 1 end
    local up = W:GetScript("OnMouseUp")
    ST.db.locked = true
    ST.inCombat = false
    if up then up(W, "LeftButton") end
    local outOk = calls == 1
    ST.inCombat = true
    if up then up(W, "LeftButton") end
    local inNot = calls == 1
    ST.inCombat = false
    ST.ToggleDashboard = orig

    local M = ST.ClockWidget
    local seam = type(M) == "table" and type(M.ApplyPoint) == "function" and type(M.ResetPosition) == "function"
        and type(M.Preview) == "function" and M.frame == W
    local reset, preview = false, false
    if seam then
        ST.db.pos = { "TOPLEFT", "TOPLEFT", 10, -10 }
        M:ResetPosition()
        local d = ST.DEFAULTS.pos
        reset = ST.db.pos[1] == d[1] and ST.db.pos[2] == d[2] and ST.db.pos[3] == d[3] and ST.db.pos[4] == d[4]
            and ST.db.pos ~= d
        S.mana = S.manaMax
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        Ticks(2)
        local hidden = not W:IsShown()
        M:Preview(60)
        preview = hidden and W:IsShown()
        M:Preview(0)
        Ticks(1)
        preview = preview and not W:IsShown()
    end
    check("T93: left-click opens the window out of combat only; the mover seam (ST.ClockWidget)",
        up ~= nil and outOk and inNot and seam and reset and preview,
        string.format("out=%s inCombat=%s seam=%s reset=%s preview=%s", tostring(outOk), tostring(inNot),
            tostring(seam), tostring(reset), tostring(preview)))
end

--------------------------------------------------------------------------------
-- 16b. T116, re-based by T145c: the rest text. On (texts.rest.on) it draws the
-- words' rest; off it is hidden, on again it is back (the store's switch,
-- which Settings -> Clock and Forever's /st clock rest write; TBC's /st rest
-- takes the secondary off the face itself, ST.db.showRest).
--------------------------------------------------------------------------------
do
    local okS, res = pcall(function()
        local r = {}
        local Store = ST.ClockStore
        local was = Store.Get("texts.rest.on")
        local face = OomFace(80, "normal")
        Store.SetText("rest", "on", true)
        PaintFace(face)
        r.rest = Shown("rest")
        r.want = Want(face).rest.text
        Store.SetText("rest", "on", false)
        PaintFace(face)
        r.off = Shown("rest")
        Store.SetText("rest", "on", true)
        PaintFace(face)
        r.on = Shown("rest")
        Store.SetText("rest", "on", was == true)
        S.Tick(0.5)
        return r
    end)
    local r = okS and res or {}
    check("T116: the rest text draws the words' rest; off it is hidden, on it is back",
        okS and type(r.rest) == "string" and r.rest == r.want and r.rest:find("^rest ") ~= nil
            and r.off == nil and r.on == r.rest,
        okS and string.format("rest %q want %q off %q on %q", tostring(r.rest), tostring(r.want), tostring(r.off),
            tostring(r.on)) or ("raised: " .. tostring(res)))
end

--------------------------------------------------------------------------------
-- 17. T115 (clock v2, C4's "Regen tick"): RM:RegenTick(now) -- the last three
-- rises of the player's mana, in and out of combat; two gaps of 2 s (within
-- 0.15 s) answer the last rise and the period 2, a rise older than 4 s or an
-- irregular gap answer nil. What the strip's tick mark is placed from.
--------------------------------------------------------------------------------
do
    local RM = ST.Regen
    local function Rise(n)
        S.mana = math.min(S.manaMax, S.mana + (n or 10))
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
    local okR, a, b, c, d = pcall(function()
        S.mana = S.manaMax - 500
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        Ticks(9)
        Rise(); Ticks(4); Rise(); Ticks(4); Rise()
        local t3 = GetTime()
        local last, period = RM:RegenTick(GetTime())
        Ticks(3)
        local still = RM:RegenTick(GetTime())
        Ticks(6) -- 4.5 s after the last rise
        local stale = RM:RegenTick(GetTime())
        return last == t3 and period == 2, still == t3, stale == nil, tostring(last) .. "/" .. tostring(period)
    end)
    check("RM:RegenTick: three rises 2 s apart answer (the last, 2); still at 1.5 s; nil 4 s after",
        okR and a and b and c, okR and string.format("answer %s, still %s, stale %s (%s)", tostring(a), tostring(b),
            tostring(c), tostring(d)) or ("raised: " .. tostring(a)))

    local okI, x, y, z = pcall(function()
        S.Fire("PLAYER_REGEN_DISABLED")
        Ticks(9)
        Rise(); Ticks(4); Rise(); Ticks(6); Rise()
        local irregular = RM:RegenTick(GetTime())
        Ticks(4); Rise()
        local t4 = GetTime()
        local mixed = RM:RegenTick(GetTime()) -- gaps 3 s, 2 s
        Ticks(4); Rise()
        local t5 = GetTime()
        local inCombat = RM:RegenTick(GetTime())
        S.Fire("PLAYER_REGEN_ENABLED")
        return irregular == nil and mixed == nil, inCombat == t5, t4 ~= nil
    end)
    check("RM:RegenTick: an irregular gap answers nil; rises in combat count",
        okI and x and y and z, okI and string.format("irregular nil %s, in combat %s", tostring(x), tostring(y))
            or ("raised: " .. tostring(x)))
end

-- every rendered string: ASCII, no bare pipe
local bad
for _, r in ipairs(log) do
    local raw = r.shown
    if raw:find("[\128-\255]") or raw:find("|", 1, true) then bad = raw break end
end
check("every shown string ASCII with no bare pipe", bad == nil, bad)

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
