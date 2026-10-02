-- tools/run.sh tools/clockcheck.lua
--
-- T11 (docs/tasks/T11-clock.md): the Forever mana clock -- Engine/ManaModel.lua
-- (pure), Engine/ManaPool_Forever.lua (the model instance, its events, the
-- pricing, the assume-full rule -- T68, P24) and UI/Clock_Forever.lua (the
-- widget and its hover, painting the pool). Forever only:
-- the modelled pool exists because current mana is secret on this client
-- (Facts); nothing here is meaningful on TBC, which reads UnitPower directly.
-- T93 (docs/SPEC-next.md 7.1): the clock's text is UI/ClockView.lua's three
-- segments (read back through ClockText below), and the Forever gaps F1, F3-F6
-- and the mover seam are held near the end.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB

-- Fixture: a family whose only cost is a percentage of base mana -- the
-- "unpriced, never guessed" case (item 8) alongside a secret spell id.
S.AddSpell(93010, "PercentSpell", "Rank 1",
    function() return "Heals a friendly target for 10 to 15." end,
    { cost = 0, costPercent = 10, level = 1 })

--------------------------------------------------------------------------------
-- ASCII / no-bare-pipe helper, shared by items 7, 12, 13.
--------------------------------------------------------------------------------
local function AsciiClean(s)
    if type(s) ~= "string" then return false end
    if s:find("|", 1, true) then return false end
    return s:match("^[\32-\126]*$") ~= nil
end

--------------------------------------------------------------------------------
-- Engine/ManaModel.lua: pure model, tested directly (no client call, no
-- MD.API call -- so a fresh instance needs nothing from the stub at all).
--------------------------------------------------------------------------------
local ManaModel = MD.ManaModel

-- item 1 is exercised through the real MD.Pool below (login behaviour);
-- this section covers 3, 6, 7 (Text), 12.

-- item 3: exact numbers across the 5s boundary.
-- base=10/s, casting=50/s, spend at t=0 (cost 0, just to set lastSpend).
-- t=0..3: fully inside the 5s window -> 3 * 50 = 150.
-- t=3..8: 3..5 inside the window (2s * 50 = 100), 5..8 outside (3s * 10 = 30)
--         -> +130, running total 280.
do
    local m = ManaModel.New()
    m:SetMax(1000000)
    m:SetRegen(10, 50)
    m:Anchor(0, 0, "start")
    m:Spend(0, 0)
    m:Advance(3)
    local at3 = m.mana
    m:Advance(8)
    local at8 = m.mana
    check("regen runs at the casting rate for five seconds after a spend, then the base rate",
        math.abs(at3 - 150) < 1e-9 and math.abs(at8 - 280) < 1e-9,
        string.format("at3=%s at8=%s", tostring(at3), tostring(at8)))
end

-- item 6: warmup, then a direction once spend and regen disagree.
do
    local m = ManaModel.New()
    m:SetMax(100000)
    m:SetRegen(10, 50)
    m:Anchor(0, 100000, "start")
    m:StartFight(0)
    local warm = m:Project(1)

    -- three cheap casts, still inside the 10s warmup window
    m:Spend(10, 1); m:Spend(10, 2); m:Spend(10, 3)
    local stillWarm = m:Project(5)

    -- spend fast (400 mana over the whole fight) so spend outruns regen
    m:Spend(390, 11)
    local oom = m:Project(11)

    local m2 = ManaModel.New()
    m2:SetMax(100000)
    m2:SetRegen(10, 50)
    m2:Anchor(0, 100000, "start")
    m2:StartFight(0)
    m2:Spend(1, 1); m2:Spend(1, 2); m2:Spend(1, 3)
    local full = m2:Project(30)

    check("the projection: warmup, then OOM when spending outruns regen, FULL when it does not",
        warm.mode == "warmup" and stillWarm.mode == "warmup"
        and oom.mode == "oom" and type(oom.tto) == "number"
        and full.mode == "full" and type(full.ttf) == "number",
        string.format("warm=%s stillWarm=%s oom=%s(tto=%s) full=%s(ttf=%s)",
            tostring(warm.mode), tostring(stillWarm.mode), tostring(oom.mode), tostring(oom.tto),
            tostring(full.mode), tostring(full.ttf)))
end

-- item 7: every Text() shape starts with "~" -- the hover half is checked
-- once the real clock exists, below; both feed one assertion.
local item7TextOk
do
    local shapes = {
        { mode = "warmup" },
        { mode = "oom", tto = 80, rest = 130 },
        { mode = "oom", tto = nil },
        { mode = "full", ttf = 45 },
        { mode = "hold" },
        { mode = "fullnow" },
        { mode = "ooc", ttf = 40 },
    }
    local allTilde, allAscii = true, true
    for _, s in ipairs(shapes) do
        local text = ManaModel.Text(s)
        if text:sub(1, 1) ~= "~" then allTilde = false end
        if not AsciiClean(text) then allAscii = false end
    end
    item7TextOk = allTilde and allAscii
end

-- item 12: rounded to the nearest 5s, capped at ten minutes.
do
    local a = ManaModel.Text({ mode = "oom", tto = 63, rest = 122 })
    local b = ManaModel.Text({ mode = "full", ttf = 600 })
    local c = ManaModel.Text({ mode = "full", ttf = 601 })
    check("times are rounded to five seconds and capped at ten minutes",
        a == "~OOM 1:05  rest 2:00" and b == "~FULL 10:00" and c == "~FULL >10m",
        string.format("a=%q b=%q c=%q", a, b, c))
end

-- T11b: each state worded as the TBC clock words it (Engine/TTO.lua
-- GetDisplayString), the "~" kept in front.
do
    local a = ManaModel.Text({ mode = "fullnow" })
    local b = ManaModel.Text({ mode = "ooc", ttf = 45 })
    local c = ManaModel.Text({ mode = "warmup", rest = 20 })
    local d = ManaModel.Text({ mode = "warmup" })
    local e = ManaModel.Text({ mode = "hold", rest = 20 })
    local f = ManaModel.Text({ mode = "oom", tto = 80, rest = 90 })
    local g = ManaModel.Text({ mode = "oom", tto = 80, rest = 130 })
    check("each state is worded as the TBC clock words it, marked modelled",
        a == "~FULL" and b == "~FULL 0:45" and c == "~OOM ...  rest 0:20" and d == "~OOM ..."
        and e == "~OOM --  rest 0:20" and f == "~OOM 1:20" and g == "~OOM 1:20  rest 2:10",
        string.format("a=%q b=%q c=%q d=%q e=%q f=%q g=%q", a, b, c, d, e, f, g))
end

--------------------------------------------------------------------------------
-- Engine/ManaPool_Forever.lua and UI/Clock_Forever.lua: the real pool and the
-- real clock, wired at MD_READY by the harness's own PLAYER_LOGIN. Everything
-- below drives the live MD.Pool model and the MD.Clock frame that paints it
-- (T68, P24: the model is the pool's; MD.Clock.model is only an alias).
--------------------------------------------------------------------------------
local Clock = MD.Clock
local Pool = MD.Pool
local model = Pool and Pool.model

-- T93: the clock's words as drawn, colour codes removed. Since T93 the text is
-- three font strings at fixed places (UI/ClockView.lua: label, value,
-- secondary), or the preview's message line over them; before it, one font
-- string (Clock.text). The same words either way: label, one space, the value,
-- two spaces, the secondary.
local function StripCodes(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function ClockText()
    local v = Clock.view
    if v then
        if v.msg and v.msg:IsShown() then return StripCodes(v.msg:GetText()) end
        local function Seg(fs)
            if not fs or not fs:IsShown() then return nil end
            local t = fs:GetText()
            if t == nil or t == "" then return nil end
            return StripCodes(t)
        end
        local l, val, s = Seg(v.label), Seg(v.value), Seg(v.second)
        local out = l or ""
        if val then out = out .. " " .. val end
        if s then out = out .. "  " .. s end
        return out
    end
    return Clock.text and Clock.text:GetText() or ""
end

-- item 1: assumed full at login.
check("the pool starts full at login and says it was assumed",
    model ~= nil and model.max ~= nil and model.mana == model.max
    and model.anchor.why == "assumed full at login",
    string.format("mana=%s max=%s why=%s", tostring(model and model.mana), tostring(model and model.max),
        tostring(model and model.anchor.why)))

-- item 2: a cast spends its cost from the book (774 = Rejuvenation rank 1, cost 25).
do
    local before = model.mana
    S.Cast(774)
    check("a cast spends its cost from the book, when it succeeds",
        model.mana == before - 25, string.format("before=%s after=%s", tostring(before), tostring(model.mana)))
end

-- item 10: another unit's cast spends nothing (and is not even counted unpriced).
do
    local before, beforeUnpriced = model.mana, model.unpriced
    S.Cast(774, "party1")
    check("another unit's cast spends nothing",
        model.mana == before and model.unpriced == beforeUnpriced)
end

-- item 8: a secret id, and a percent-only cost, are counted but never priced.
do
    local before, beforeUnpriced = model.mana, model.unpriced
    S.Cast(S.Secret())
    S.Cast(93010)
    check("a cast with a secret id or an unpriced cost is counted, never guessed",
        model.mana == before and model.unpriced == beforeUnpriced + 2,
        string.format("mana %s->%s unpriced %s->%s", tostring(before), tostring(model.mana),
            tostring(beforeUnpriced), tostring(model.unpriced)))
end

-- T45 (P1, review Q1): in a fight, a secret spell id never reaches the book as a
-- key. The client raises on `t[secret]`; Lua 5.1 cannot trap it, so the stub
-- would let `book.spells[secret]` pass as a quiet miss -- this watches every key
-- the clock hands the book (its spells table and ReadSpell) and fails on a secret
-- one. It goes red when UNIT_SPELLCAST_SUCCEEDED's IsSecret(spellID) half is
-- removed, now that type(secret) answers "number" as on the client.
do
    local Book = MD.Book
    local origGet, origRead = Book.Get, Book.ReadSpell
    local keys, secretKeys = 0, 0
    local function Seen(k)
        keys = keys + 1
        if issecretvalue(k) then secretKeys = secretKeys + 1 end
    end
    Book.Get = function(self, ...)
        local real = origGet(self, ...)
        if not real then return real end
        local spells = setmetatable({}, { __index = function(_, k)
            Seen(k)
            if issecretvalue(k) then return nil end
            return real.spells and real.spells[k]
        end })
        return setmetatable({ spells = spells }, { __index = real })
    end
    Book.ReadSpell = function(self, id, ...)
        Seen(id)
        if issecretvalue(id) then return nil end
        return origRead(self, id, ...)
    end
    local before = model.mana
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    S.Cast(S.Secret())
    S.Cast(774)
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    Book.Get, Book.ReadSpell = origGet, origRead
    check("in a fight the book is never indexed by a secret spell id",
        secretKeys == 0 and keys >= 1 and model.mana < before,
        string.format("keys=%d secret=%d mana %s->%s", keys, secretKeys, tostring(before), tostring(model.mana)))
end

-- item 4: in combat, the regen rate holds at what was last read out of combat.
do
    -- one tick out of combat first, to be sure base/casting are seeded.
    S.Tick(0.5)
    local base0, casting0 = model.base, model.casting
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    S.Tick(0.5); S.Tick(0.5); S.Tick(0.5)
    local held = (model.base == base0 and model.casting == casting0)
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    check("in combat the regen rate is the last one read out of combat", held,
        string.format("base %s->%s casting %s->%s", tostring(base0), tostring(model.base),
            tostring(casting0), tostring(model.casting)))
end

-- item 5: out of combat, once regen has had time to fill it, the pool is
-- anchored at full even though it has not literally integrated there yet --
-- GetManaRegen's own casting rate (28.33) is slower than its base rate
-- (69.24, Facts/CLAUDE.md ordering), so the plain integral falls a little
-- short of max at exactly max/base seconds; the anchor is what corrects it.
do
    model.mana = 0
    model.lastSpend = S.now
    model.anchor.why = "test seed"
    model.anchor.at = S.now
    local threshold = model.max / model.base
    local before = math.floor((threshold - 1) / 0.5)
    for _ = 1, before do S.Tick(0.5) end
    local manaBefore, whyBefore = model.mana, model.anchor.why
    for _ = 1, 6 do S.Tick(0.5) end -- +3s, past the threshold
    check("out of combat the pool is anchored at full once regen has had time to fill it",
        manaBefore < model.max and whyBefore == "test seed"
        and model.mana == model.max and model.anchor.why == "regen had time to fill it",
        string.format("before=%s(why=%s) after=%s(why=%s) max=%s",
            tostring(manaBefore), tostring(whyBefore), tostring(model.mana), tostring(model.anchor.why),
            tostring(model.max)))
end

-- item 9: DrawUnitPower hands the real pool to the bar unread.
do
    local calls = {}
    local origIsSecretValue = _G.issecretvalue
    _G.issecretvalue = function(v) calls[#calls + 1] = v; return origIsSecretValue(v) end
    local bar = CreateFrame("StatusBar", nil, UIParent)
    local drawOk = MD.API.DrawUnitPower(bar, "player", 0)
    _G.issecretvalue = origIsSecretValue

    local sawIt = false
    for _, v in ipairs(calls) do
        local same = pcall(function() return rawequal(v, bar.value) end)
        if same and rawequal(v, bar.value) then sawIt = true end
    end
    check("the bar is handed the real pool unread",
        drawOk == true and bar.value ~= nil and bar.minV == 0 and not sawIt,
        string.format("drawOk=%s minV=%s sawIt=%s", tostring(drawOk), tostring(bar.minV), tostring(sawIt)))
end

-- item 11: shown in combat; hidden at full out of combat; off means off.
do
    local frame = Clock.frame
    MD.db.clock.shown = true
    model.mana = model.max * 0.5
    Clock:Refresh()
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Clock:Refresh()
    local shownInCombat = frame:IsShown()

    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    model.mana = model.max -- full
    Clock:Refresh()
    local hiddenAtFull = not frame:IsShown()

    model.mana = model.max * 0.5
    Clock:Refresh()
    local shownWhenLow = frame:IsShown()

    MD.db.clock.shown = false
    Clock:Refresh()
    local hiddenWhenOff = not frame:IsShown()
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Clock:Refresh()
    local stillOffInCombat = not frame:IsShown()
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    MD.db.clock.shown = true
    Clock:Refresh()

    check("the clock shows in combat and hides at full out of combat; off means off",
        shownInCombat and hiddenAtFull and shownWhenLow and hiddenWhenOff and stillOffInCombat,
        string.format("shownInCombat=%s hiddenAtFull=%s shownWhenLow=%s hiddenWhenOff=%s stillOffInCombat=%s",
            tostring(shownInCombat), tostring(hiddenAtFull), tostring(shownWhenLow), tostring(hiddenWhenOff),
            tostring(stillOffInCombat)))
end

-- T11b: out-of-combat hysteresis -- appears under 90% of max, stays shown
-- until back over 95% (UI/Widget.lua MD:UpdateVisibility 144-173).
do
    local frame = Clock.frame
    MD.db.clock.shown = true
    S.inCombat = false

    model.mana = model.max
    Clock:Refresh()
    local startHidden = not frame:IsShown()

    model.mana = model.max * 0.94
    Clock:Refresh()
    local at94 = frame:IsShown()

    model.mana = model.max * 0.89
    Clock:Refresh()
    local at89 = frame:IsShown()

    model.mana = model.max * 0.93
    Clock:Refresh()
    local at93 = frame:IsShown()

    model.mana = model.max * 0.96
    Clock:Refresh()
    local at96 = frame:IsShown()

    check("out of combat the clock appears under 90% and stays until 95%",
        startHidden and not at94 and at89 and at93 and not at96,
        string.format("startHidden=%s at94=%s at89=%s at93=%s at96=%s",
            tostring(startHidden), tostring(at94), tostring(at89), tostring(at93), tostring(at96)))
end

-- item 7 (other half) + item 13: the hover names it modelled and is clean ASCII.
do
    GameTooltip.lines = {}
    local onEnter = Clock.frame:GetScript("OnEnter")
    onEnter(Clock.frame)
    local lines = GameTooltip.lines or {}
    local joined = {}
    local allAscii = true
    for _, l in ipairs(lines) do
        for _, part in ipairs(l) do
            if part ~= nil then
                joined[#joined + 1] = part
                if not AsciiClean(part) then allAscii = false end
            end
        end
    end
    local text = table.concat(joined, "\n")
    -- T76 (P32, review U9): the hover says what "~" means in a healer's words
    -- ("~ = modelled from your casts") and no longer talks about the client's
    -- secrets or the model's anchor (that was "the real pool is secret on
    -- this client" and "Anchored 1:20 ago: ...").
    local hoverOk = text:find("modelled", 1, true) ~= nil and text:find("~ =", 1, true) ~= nil
        and text:find("secret", 1, true) == nil and text:lower():find("anchored", 1, true) == nil
    check("every projection is marked modelled, in the text and the hover",
        item7TextOk and hoverOk, string.format("textHalf=%s hoverHalf=%s", tostring(item7TextOk), tostring(hoverOk)))

    local widgetText = ClockText()
    check("every string the clock renders is ASCII with no bare pipe",
        allAscii and AsciiClean(widgetText))
end

--------------------------------------------------------------------------------
-- Report demonstration: the widget's text and hover at three moments.
--------------------------------------------------------------------------------
local function HoverText()
    GameTooltip.lines = {}
    Clock.frame:GetScript("OnEnter")(Clock.frame)
    local out = {}
    for _, l in ipairs(GameTooltip.lines or {}) do
        out[#out + 1] = table.concat(l, "  |  ")
    end
    return table.concat(out, "\n  ")
end

print("\n-- demonstration: three moments of a scripted fight --")
model.mana = model.max
model.anchor.why = "assumed full at login"
S.Tick(0.5)

S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
S.Cast(5176) -- Wrath, cost 20 -- one cast in, still inside the warmup window
S.Tick(0.5)
print("warmup: " .. ClockText())
print("  " .. HoverText())

for i = 1, 40 do
    S.Cast(5176) -- Wrath, cost 20
    S.Tick(0.5)
end
print("oom: " .. ClockText())
print("  " .. HoverText())

-- T76 (P32, review U9): the hover as label / value pairs, read at a moment.
local function HoverPairs()
    GameTooltip.lines = {}
    Clock.frame:GetScript("OnEnter")(Clock.frame)
    local out = {}
    for _, l in ipairs(GameTooltip.lines or {}) do out[#out + 1] = { l = l[1], r = l[2], c = l.color, rc = l.rcolor } end
    return out
end
local function PairOf(list, label)
    for _, p in ipairs(list) do if p.l == label and p.r ~= nil then return p end end
    return nil
end
local function SameColour(c, token)
    local r, g, b = MD.UI.RGB(token)
    return type(c) == "table" and c[1] == r and c[2] == g and c[3] == b
end
local oomText = ClockText()
local oomPairs = HoverPairs()
local skinnedWhileShown = MD.Tip ~= nil and MD.Tip.Skinned ~= nil and MD.Tip:Skinned(GameTooltip)
Clock.frame:GetScript("OnLeave")(Clock.frame)
local skinnedAfter = MD.Tip ~= nil and MD.Tip.Skinned ~= nil and MD.Tip:Skinned(GameTooltip)

S.Fire("PLAYER_REGEN_ENABLED")
S.inCombat = false
S.Tick(0.5)
print("after combat: " .. ClockText())
print("  " .. HoverText())
local oocText = ClockText()
local oocPairs = HoverPairs()
Clock.frame:GetScript("OnLeave")(Clock.frame)

do
    local out = PairOf(oomPairs, "Out of mana in")
    local full = PairOf(oomPairs, "Full again in")
    local spend = PairOf(oomPairs, "Spending")
    local mana = PairOf(oomPairs, "Mana")
    local clockTime = oomText:match("^~OOM (%d+:%d%d)")
    check("T76: in a fight the hover says when mana runs out and when it is full again, as pairs",
        out ~= nil and clockTime ~= nil and out.r == "~" .. clockTime
        and full ~= nil and full.r:find("^~%d+:%d%d if you stop$") ~= nil
        and spend ~= nil and spend.r:find("^~%d+ a sec over %d+ casts$") ~= nil
        and mana ~= nil and mana.r:find("^~%d+ of %d+$") ~= nil
        and SameColour(out.c, "label") and SameColour(out.rc, "mana"),
        string.format("clock=%q out=%s full=%s spend=%s mana=%s", oomText, tostring(out and out.r),
            tostring(full and full.r), tostring(spend and spend.r), tostring(mana and mana.r)))

    local oocFull = PairOf(oocPairs, "Full again in")
    local oocTime = oocText:match("^~FULL (%d+:%d%d)")
    check("T76: out of combat the hover says when it is full again, with no fight lines",
        oocFull ~= nil and oocTime ~= nil and oocFull.r == "~" .. oocTime
        and PairOf(oocPairs, "Out of mana in") == nil and PairOf(oocPairs, "Spending") == nil
        and PairOf(oocPairs, "Left-click") ~= nil,
        string.format("clock=%q full=%s", oocText, tostring(oocFull and oocFull.r)))

    check("T76: the hover is MD.Tip's, in the kit skin while it shows and out of it after",
        skinnedWhileShown == true and skinnedAfter == false and #oomPairs > 0,
        string.format("skinned=%s after=%s", tostring(skinnedWhileShown), tostring(skinnedAfter)))
end

--------------------------------------------------------------------------------
-- review R13: an Energy cast spends no mana -- Claw's "45 Energy" (beta
-- client 1.60.1.70009) is not 45 mana off the modelled pool, and it is not
-- unpriced either: it is known to cost no mana.
--------------------------------------------------------------------------------
do
    S.AddSpell(93020, "Claw", "Rank 1",
        function() return "Claw the enemy for 110% normal damage plus 29. Awards 1 combo point." end,
        { cast = 0, level = 20, costLine = "45 Energy",
          costList = { { type = 3, name = "ENERGY", cost = 45, minCost = 45, costPercent = 0, costPerSec = 0,
                         requiredAuraID = 0, hasRequiredAura = false } } })
    MD.Book:MarkDirty()
    local m = Pool.model
    m.mana = m.max * 0.5
    local before, beforeUnpriced = m.mana, m.unpriced
    S.Cast(93020)
    check("an Energy cast spends no mana and is not unpriced",
        m.mana == before and m.unpriced == beforeUnpriced,
        string.format("mana %s->%s unpriced %s->%s", tostring(before), tostring(m.mana),
            tostring(beforeUnpriced), tostring(m.unpriced)))
end

--------------------------------------------------------------------------------
-- Review B19 (docs/review/2026-09-30-project-review.md): the opener's
-- UNIT_SPELLCAST_SUCCEEDED arrives before PLAYER_REGEN_DISABLED (R8's window).
-- A priced opener 0.3 s before the flag counts in the fight's casts and spend;
-- one 1 s before does not. An unpriced opener stays in the hover's count.
--------------------------------------------------------------------------------
local function HoverLines()
    GameTooltip.lines = {}
    Clock.frame:GetScript("OnEnter")(Clock.frame)
    local out = {}
    for _, l in ipairs(GameTooltip.lines or {}) do out[#out + 1] = table.concat(l, " ") end
    return table.concat(out, " / ")
end

do
    local m = Pool.model
    S.Tick(0.5)
    S.Cast(774)                    -- Rejuvenation rank 1, 25 mana, 1 s before the flag: not the opener
    S.now = S.now + 0.7
    S.Cast(774)                    -- the opener, 0.3 s before the flag
    S.now = S.now + 0.3
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    local casts, spent = m.fight and m.fight.casts, m.fight and m.fight.spent
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    check("an opener 0.3 s before the combat flag counts in the fight's casts and spend",
        casts == 1 and spent == 25,
        string.format("casts=%s spent=%s (want 1, 25)", tostring(casts), tostring(spent)))
end

do
    local m = Pool.model
    MD.db.clock.shown = true
    S.Tick(0.5)
    S.Cast(93010)                  -- a percent-of-base-mana cost: unpriced
    S.now = S.now + 0.3
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    local unpriced = m.unpriced
    local hover = HoverLines()
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    -- T76: a label / value pair now ("Unpriced casts" | "1")
    check("an unpriced opener stays in the hover's unpriced count",
        unpriced == 1 and hover:find("Unpriced casts 1", 1, true) ~= nil,
        string.format("unpriced=%s hover=%q", tostring(unpriced), hover))
end

--------------------------------------------------------------------------------
-- review R36/R37: a login or /reload in the middle of a fight -- no
-- PLAYER_REGEN_DISABLED will come -- starts the clock in combat: a fight
-- under way, shown, and never worded as the out-of-combat "~FULL".
--------------------------------------------------------------------------------
do
    MD.db.clock.shown = true
    S.inCombat = true
    MD:Fire("MD_READY") -- what PLAYER_LOGIN runs after a /reload
    local m = Pool.model
    S.Tick(0.5)
    local text = ClockText()
    local fightGood = m ~= model and m.fight ~= nil
    local shownGood = Clock.frame ~= nil and Clock.frame:IsShown()
    local wordGood = text:find("~OOM", 1, true) ~= nil and text:find("FULL", 1, true) == nil

    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    local endedGood = m.fight == nil

    check("a login in the middle of a fight starts the clock in combat",
        fightGood and shownGood and wordGood and endedGood,
        string.format("fight=%s shown=%s text=%q ended=%s", tostring(fightGood), tostring(shownGood), text,
            tostring(endedGood)))
end

--------------------------------------------------------------------------------
-- T41 (docs/SPEC-forever-ui.md 4.4): the clock under the theme -- the `bg`
-- fill and a pixel-snapped 1-px border, and a 1-px black backing behind the
-- 160x4 mana bar so it reads on bright ground; both re-snapped when the UI
-- scale changes, without a reload (the manager never touches the clock, 6.1).
--------------------------------------------------------------------------------
do
    local UI = MD.UI
    local P = UI.PALETTE
    local w = Clock.frame
    local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9 end
    local function SameColour(got, want)
        return type(got) == "table" and type(want) == "table" and Near(got[1], want[1]) and Near(got[2], want[2])
            and Near(got[3], want[3]) and Near(got[4], want[4])
    end

    S.physicalHeight = 1080
    w.GetEffectiveScale = function() return 1 end
    S.Tick(0.5)
    local e = UI.px(1, w)
    local bd = w.backdrop or {}
    check("the clock is filled with the theme's bg and edged in one physical pixel",
        SameColour(w.bg, P.bg) and SameColour(w.border, P.border) and Near(bd.edgeSize, e)
        and bd.insets ~= nil and Near(bd.insets.left, e) and UI.pixelFrames[w] ~= nil,
        string.format("bg=%s,%s,%s,%s edge=%s px=%s", tostring(w.bg and w.bg[1]), tostring(w.bg and w.bg[2]),
            tostring(w.bg and w.bg[3]), tostring(w.bg and w.bg[4]), tostring(bd.edgeSize), tostring(e)))

    -- T115 (clock v2): the mana bar 160 x 4 over the 160 x 3 five-second-rule
    -- strip, each on its own black backing
    local back, sback = Clock.barBack, Clock.stripBack
    check("the mana bar and the 5SR strip each have a black backing one physical pixel wider on every side",
        back ~= nil and back.parentFrame == w and SameColour(back.color, { 0, 0, 0, 1 })
        and Near(back.w, 160 + 2 * e) and Near(back.h, 4 + 2 * e)
        and Clock.bar and Clock.bar.w == 160 and Clock.bar.h == 4
        and sback ~= nil and sback.parentFrame == w and SameColour(sback.color, { 0, 0, 0, 1 })
        and Near(sback.w, 160 + 2 * e) and Near(sback.h, 3 + 2 * e)
        and Clock.strip and Clock.strip.w == 160 and Clock.strip.h == 3,
        string.format("back=%s w=%s h=%s want %s x %s; strip back=%s %s x %s", tostring(back ~= nil),
            tostring(back and back.w), tostring(back and back.h), tostring(160 + 2 * e), tostring(4 + 2 * e),
            tostring(sback ~= nil), tostring(sback and sback.w), tostring(sback and sback.h)))

    -- a UI scale change: the next tick re-snaps the edge and the backing
    w.GetEffectiveScale = function() return 0.64 end
    S.Tick(0.5)
    local e2 = UI.px(1, w)
    local bd2 = w.backdrop or {}
    check("a UI scale change re-snaps the clock's edge and the bar's backing without a reload",
        not Near(e, e2) and Near(bd2.edgeSize, e2) and back ~= nil and Near(back.w, 160 + 2 * e2)
        and Near(back.h, 4 + 2 * e2) and SameColour(w.bg, P.bg),
        string.format("edge=%s backW=%s want px=%s", tostring(bd2.edgeSize), tostring(back and back.w), tostring(e2)))
    w.GetEffectiveScale = function() return 1 end
    S.Tick(0.5)
end

--------------------------------------------------------------------------------
-- T115 (clock v2): the hover says what the bars are, by the look drawn --
-- stacked (the default), the order, the veil, the chip, Mana from the model,
-- one bar alone, none.
--------------------------------------------------------------------------------
do
    local CV = MD.ClockView
    local function Muted()
        local lines = Clock:HoverLines(GetTime()) or {}
        for _, l in ipairs(lines) do
            if type(l.l) == "string" and l.l:find("^~ = ") then return l.l end
        end
        return ""
    end
    local function Set(k, v) CV.Set("bars.line." .. k, v); S.Tick(0.5) end
    local okH, res = pcall(function()
        local r = {}
        CV.ResetToStyle()
        S.Tick(0.5)
        r.stacked = Muted()
        Set("order", "fsrOver"); r.fsrOver = Muted(); Set("order", nil)
        Set("join", "veil"); r.veil = Muted()
        Set("join", "chip"); r.chip = Muted(); Set("join", nil)
        Set("mana", "model"); r.model = Muted(); Set("mana", nil)
        Set("show", "mana"); r.mana = Muted()
        Set("show", "fsr"); r.fsr = Muted()
        Set("show", "none"); r.none = Muted()
        CV.ResetToStyle()
        S.Tick(0.5)
        return r
    end)
    local P = "~ = modelled from your casts."
    local want = {
        stacked = P .. " The bar is your real mana, drawn by the game; the strip under it is the five seconds after your last priced cast.",
        fsrOver = P .. " The bar is your real mana, drawn by the game; the strip over it is the five seconds after your last priced cast.",
        veil = P .. " The bar is your real mana, drawn by the game; the amber veil over it is the five seconds after your last priced cast.",
        chip = P .. " The bar is your real mana, drawn by the game; the square beside the label is the five seconds after your last priced cast.",
        model = P .. " The bar is your modelled mana (~); the strip under it is the five seconds after your last priced cast.",
        mana = P .. " The bar is your real mana, drawn by the game.",
        fsr = P .. " The bar is the five seconds after your last priced cast.",
        none = P,
    }
    local bad
    if not okH then
        bad = "raised: " .. tostring(res)
    else
        for _, k in ipairs({ "stacked", "fsrOver", "veil", "chip", "model", "mana", "fsr", "none" }) do
            if res[k] ~= want[k] and not bad then bad = string.format("%s: %q", k, tostring(res[k])) end
        end
    end
    check("the hover names the bars as drawn: stacked, the order, veil, chip, the model, one bar, none",
        bad == nil, bad)
end

--------------------------------------------------------------------------------
-- T70 (P26 of docs/PLAN-refactor-ux.md, review U18): the clock can be placed
-- at full mana. Unticking Settings -> General's "Lock in place" previews it for
-- 60 s at any mana level, as TBC's widget does, and it hides after; a
-- left-click on it opens the window, a drag, another button or a click in
-- combat does not.
--------------------------------------------------------------------------------
do
    local w = Clock.frame
    MD.db.clock.shown = true
    MD.db.clock.locked = true
    S.inCombat = false
    model.mana = model.max -- full: the 90/95 rule alone keeps it hidden
    Clock:Refresh()
    local hiddenAtFull = not w:IsShown()

    MD:SelectView("settings", "general")
    local lock
    for _, f in ipairs(S.allFrames) do
        if f.clockLockCheck then lock = f.clockLockCheck end
    end
    if lock then lock:SetChecked(false); lock.onClick(false, lock) end
    local at0 = w:IsShown()
    local word0 = ClockText()
    S.Tick(59)
    local at59 = w:IsShown()
    S.Tick(1.5)
    local after = not w:IsShown()
    local word1 = ClockText()
    local frame = _G.SpellTunerDashboard
    if frame then frame:Hide() end

    check("unticking Lock shows the clock at full mana for 60 s, then it hides",
        lock ~= nil and hiddenAtFull and MD.db.clock.locked == false and at0 and at59 and after
        and word0 == "SpellTuner - drag me" and word1:sub(1, 1) == "~" and model.mana == model.max,
        string.format("lock=%s hidden=%s at0=%s at59=%s after=%s word0=%q word1=%q", tostring(lock ~= nil),
            tostring(hiddenAtFull), tostring(at0), tostring(at59), tostring(after), word0, word1))
end

do
    local w = Clock.frame
    local calls = 0
    local orig = MD.ToggleDashboard
    MD.ToggleDashboard = function() calls = calls + 1 end
    local down, up = w:GetScript("OnMouseDown"), w:GetScript("OnMouseUp")
    local dragStart, dragStop = w:GetScript("OnDragStart"), w:GetScript("OnDragStop")
    local function Press(button, drag)
        if down then down(w, button) end
        if drag then dragStart(w); dragStop(w) end
        if up then up(w, button) end
    end
    local savedPoint = MD.db.clock.point
    S.inCombat = false
    Press("LeftButton")
    local clicked = calls == 1
    Press("LeftButton", true)
    local dragNot = calls == 1
    Press("RightButton")
    local rightNot = calls == 1
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Press("LeftButton")
    local combatNot = calls == 1
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    MD.ToggleDashboard = orig
    MD.db.clock.point = savedPoint

    GameTooltip.lines = {}
    w:GetScript("OnEnter")(w)
    local says = false
    for _, l in ipairs(GameTooltip.lines or {}) do
        if type(l[1]) == "string" and l[1]:find("Left-click", 1, true) then says = true end
    end
    check("a left-click on the clock calls MD:ToggleDashboard; a drag, a right-click or combat does not",
        down ~= nil and up ~= nil and clicked and dragNot and rightNot and combatNot and says,
        string.format("calls=%d clicked=%s drag=%s right=%s combat=%s hover=%s", calls, tostring(clicked),
            tostring(dragNot), tostring(rightNot), tostring(combatNot), tostring(says)))
end

--------------------------------------------------------------------------------
-- T93 (docs/SPEC-next.md 7.1, F1 and F3-F6; decisions 16 and 18): the Forever
-- clock's gaps. The clock paints MD.ManaModel.Face of the pool's projection;
-- here the projection answers chosen states, so a paint can be read at 10 s,
-- 45 s, 25 s. The words are UI/ClockView.lua's three segments.
--------------------------------------------------------------------------------
local CFace = MD.ClockFace
local function HexRGB(hex)
    local h = hex and hex:match("^|cff(%x%x%x%x%x%x)$")
    if not h then return nil end
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function Toned(fs, tone)
    local r, g, b = HexRGB(CFace and CFace.HEX and CFace.HEX[tone])
    local c = fs and fs.textColor
    return r ~= nil and type(c) == "table" and math.abs(c[1] - r) < 1e-6 and math.abs(c[2] - g) < 1e-6
        and math.abs(c[3] - b) < 1e-6
end
local realProject = Pool.Project
local function WithState(st, fn)
    Pool.Project = function(self, now)
        local s = {}
        for k, v in pairs(st) do s[k] = v end
        s.mana, s.max = s.mana or model.mana, s.max or model.max
        return s
    end
    local ok2, err = pcall(fn)
    Pool.Project = realProject
    if not ok2 then error(err, 0) end
end
local view = Clock.view or {}

do
    -- F1: the band's tones, TBC's literals (decision 16); never an arrow on Forever
    local r = {}
    MD.db.clock.shown = true
    WithState({ mode = "oom", tto = 12 }, function()
        Clock:Refresh()
        r.crit = { ClockText(), Toned(view.label, "crit"), Toned(view.value, "crit") }
    end)
    WithState({ mode = "oom", tto = 45 }, function()
        Clock:Refresh()
        r.warn = { ClockText(), Toned(view.label, "muted"), Toned(view.value, "warn") }
    end)
    WithState({ mode = "oom", tto = 80 }, function()
        Clock:Refresh()
        r.normal = { ClockText(), Toned(view.label, "muted"), Toned(view.value, "normal") }
    end)
    local okCrit = r.crit[1] == "~OOM 0:10" and r.crit[2] and r.crit[3]
    local okWarn = r.warn[1] == "~OOM 0:45" and r.warn[2] and r.warn[3]
    local okNormal = r.normal[1] == "~OOM 1:20" and r.normal[2] and r.normal[3]
    check("T93 F1: ~OOM 0:10 crit-toned with no arrow (0:45 amber, 1:20 white, labels muted)",
        okCrit and okWarn and okNormal,
        string.format("crit=%q %s/%s warn=%q %s/%s normal=%q %s/%s", tostring(r.crit[1]), tostring(r.crit[2]),
            tostring(r.crit[3]), tostring(r.warn[1]), tostring(r.warn[2]), tostring(r.warn[3]),
            tostring(r.normal[1]), tostring(r.normal[2]), tostring(r.normal[3])))
end

do
    -- F3: a character with no mana pool (a warrior, a rogue) gets no clock,
    -- in combat included; with a pool, the clock as before
    local w = Clock.frame
    local keep = MD.player.usesMana
    MD.db.clock.shown = true
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    MD.player.usesMana = false
    Clock:Refresh()
    local warriorHidden = not w:IsShown()
    MD.player.usesMana = true
    Clock:Refresh()
    local healerShown = w:IsShown()
    MD.player.usesMana = false
    Clock:Preview()
    local placedShown = w:IsShown()                     -- being placed: shown, whatever the class
    Clock:SetLocked(true)
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    MD.player.usesMana = keep
    Clock:Refresh()
    check("T93 F3: a Forever warrior has no clock in combat (a mana user does; a preview still shows)",
        warriorHidden and healerShown and placedShown,
        string.format("warrior hidden=%s healer shown=%s preview shown=%s", tostring(warriorHidden),
            tostring(healerShown), tostring(placedShown)))
end

do
    -- F4: click-through takes no mouse, except while the clock is being placed
    local FrameMT = getmetatable(UIParent)
    local realEM = rawget(FrameMT, "EnableMouse")
    FrameMT.EnableMouse = function(self, on) self.mouseOn = on and true or false end
    local w = Clock.frame
    local isDefault = MD.db.clock.clickThrough == false
    MD.db.clock.clickThrough = true
    Clock:Refresh()
    local through = w.mouseOn == false
    Clock:Preview()
    local placing = w.mouseOn == true
    Clock:SetLocked(true)
    MD.db.clock.clickThrough = false
    Clock:Refresh()
    local back = w.mouseOn == true
    -- by hand until Settings -> Clock: /st clock clickthrough, a sub matched
    -- before the verb (the clock stays shown)
    local shownBefore = MD.db.clock.shown
    SlashCmdList.SPELLTUNER("clock clickthrough")
    local cmdOn = MD.db.clock.clickThrough == true and w.mouseOn == false and MD.db.clock.shown == shownBefore
    SlashCmdList.SPELLTUNER("clock clickthrough")
    local cmdOff = MD.db.clock.clickThrough == false and w.mouseOn == true
    FrameMT.EnableMouse = realEM
    check("T93 F4: click-through takes no mouse (off by default; on while being placed)",
        isDefault and through and placing and back and cmdOn and cmdOff,
        string.format("default off=%s through=%s placing=%s back=%s /st clock clickthrough %s/%s",
            tostring(isDefault), tostring(through), tostring(placing), tostring(back), tostring(cmdOn),
            tostring(cmdOff)))
end

do
    -- F5: one pulse per fight, the first time the clock reads under 30 s; and
    -- MD:PulseWidget (MD:Alert's) pulses it while shown
    local pulse = view.pulse
    local n0 = pulse and pulse.plays or 0
    MD.db.clock.shown = true
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    local seq = {}
    for _, t in ipairs({ 45, 25, 20, 12 }) do
        WithState({ mode = "oom", tto = t }, function() Clock:Refresh() end)
        seq[#seq + 1] = (pulse and pulse.plays or 0) - n0
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    S.Fire("PLAYER_REGEN_DISABLED")
    WithState({ mode = "oom", tto = 25 }, function() Clock:Refresh() end)
    local second = (pulse and pulse.plays or 0) - n0
    local beforeAlert = pulse and pulse.plays or 0
    if MD.PulseWidget then MD:PulseWidget() end
    local alerted = pulse ~= nil and pulse.plays == beforeAlert + 1
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    Clock:Refresh()
    check("T93 F5: one pulse under 30 s per fight; MD:PulseWidget pulses the Forever clock",
        pulse ~= nil and seq[1] == 0 and seq[2] == 1 and seq[3] == 1 and seq[4] == 1 and second == 2 and alerted,
        string.format("plays %s, next fight %s, alert %s", table.concat(seq, ","), tostring(second), tostring(alerted)))
end

do
    -- F6: the rest segment can be turned off (db.clock.showRest, on by default)
    local isDefault = MD.db.clock.showRest == true
    local on, off, secHidden
    WithState({ mode = "oom", tto = 80, rest = 200 }, function()
        Clock:Refresh()
        on = ClockText()
        MD.db.clock.showRest = false
        Clock:Refresh()
        off = ClockText()
        secHidden = view.second ~= nil and not view.second:IsShown()
        MD.db.clock.showRest = true
        Clock:Refresh()
    end)
    -- by hand until Settings -> Clock: /st clock rest, a sub (the clock stays shown)
    local shownBefore = MD.db.clock.shown
    SlashCmdList.SPELLTUNER("clock rest")
    local cmdOff = MD.db.clock.showRest == false and MD.db.clock.shown == shownBefore
    SlashCmdList.SPELLTUNER("clock rest")
    local cmdOn = MD.db.clock.showRest == true
    check("T93 F6: the rest segment off (db.clock.showRest, on by default)",
        isDefault and on == "~OOM 1:20  rest 3:20" and off == "~OOM 1:20" and secHidden and cmdOff and cmdOn,
        string.format("default=%s on=%q off=%q second hidden=%s /st clock rest %s/%s", tostring(isDefault),
            tostring(on), tostring(off), tostring(secHidden), tostring(cmdOff), tostring(cmdOn)))
end

do
    -- T116 (clock v2, C1): Line's Right = Mana % draws the model's "~62%"
    -- (POWER_TEXT_READS stays off); the hover says the number is the model's;
    -- /st clock rest still drops a Right = Rest
    local CV = MD.ClockView
    local okT, res = pcall(function()
        local r = {}
        r.set = CV.Set("text.line.right", "pct") == true
        WithState({ mode = "oom", tto = 80, rest = 200, mana = model.max * 0.62 }, function()
            Clock:Refresh()
            r.pct = ClockText()
            r.hover = false
            for _, l in ipairs(Clock:HoverLines(GetTime()) or {}) do
                if l.l == "~62% is the model's; the game's own number cannot be shown yet." then r.hover = true end
            end
        end)
        CV.Set("text.line.right", nil)
        WithState({ mode = "oom", tto = 80, rest = 200 }, function()
            Clock:Refresh()
            r.rest = ClockText()
            SlashCmdList.SPELLTUNER("clock rest")
            Clock:Refresh()
            r.off = ClockText()
            SlashCmdList.SPELLTUNER("clock rest")
            Clock:Refresh()
            r.on = ClockText()
            r.noModelLine = true
            for _, l in ipairs(Clock:HoverLines(GetTime()) or {}) do
                if type(l.l) == "string" and l.l:find("is the model's;", 1, true) then r.noModelLine = false end
            end
        end)
        return r
    end)
    local r = okT and res or {}
    check("T116: Line's Right = Mana % draws the model's ~62% and the hover says so; /st clock rest drops Rest",
        okT and r.set and r.pct == "~OOM 1:20  ~62%" and r.hover and r.rest == "~OOM 1:20  rest 3:20"
            and r.off == "~OOM 1:20" and r.on == r.rest and r.noModelLine,
        okT and string.format("set %s pct %q hover %s rest %q off %q on %q no model line %s", tostring(r.set),
            tostring(r.pct), tostring(r.hover), tostring(r.rest), tostring(r.off), tostring(r.on),
            tostring(r.noModelLine)) or ("raised: " .. tostring(res)))
end

do
    -- the mover seam (docs/SPEC-next.md 6.3): ApplyPoint, ResetPosition and
    -- Preview on the clock, the same names the TBC widget exposes, as MD.ClockWidget
    local w = Clock.frame
    local realSP, realCAP = w.SetPoint, w.ClearAllPoints
    local last
    w.SetPoint = function(self, ...) last = { ... } end
    w.ClearAllPoints = function() last = nil end
    local saved = MD.db.clock.point
    MD.db.clock.point = { "CENTER", nil, "CENTER", 40, -30 }
    local seam = MD.ClockWidget == Clock and type(Clock.ApplyPoint) == "function"
        and type(Clock.ResetPosition) == "function" and type(Clock.Preview) == "function" and Clock.frame == w
    if seam then Clock:ApplyPoint() end
    local applied = last ~= nil and last[1] == "CENTER" and last[2] == UIParent and last[3] == "CENTER"
        and last[4] == 40 and last[5] == -30
    if seam then Clock:ResetPosition() end
    local reset = MD.db.clock.point == nil and last ~= nil and last[1] == "TOP" and last[5] == -120
    w.SetPoint, w.ClearAllPoints = realSP, realCAP
    MD.db.clock.point = saved
    check("T93: the mover seam (ApplyPoint, ResetPosition, Preview) as MD.ClockWidget",
        seam and applied and reset,
        string.format("seam=%s applied=%s reset=%s", tostring(seam), tostring(applied), tostring(reset)))
end

--------------------------------------------------------------------------------
-- T68 (P24, review A29): the pool owns the model, the events and the pricing,
-- so a cast is priced with no clock at all. A second copy of the addon's core
-- is loaded WITHOUT UI/Clock_Forever.lua (no clock file, so no clock frame can
-- be built): its MD_READY gives it a pool assumed full, and an own cast spends
-- the book's cost from it. On the parent the pricing lived in the clock file,
-- so this copy has no pool at all.
--------------------------------------------------------------------------------
do
    local files = {
        "Client/API.lua", "Client/API_Forever.lua", "Core.lua",
        "Spells/Parse.lua", "Spells/RankRules.lua", "Spells/Book.lua",
        "Engine/ManaModel.lua", "Engine/ManaPool_Forever.lua",
    }
    local MD2 = {}
    local loaded, loadErr = pcall(S.Load, files, "SpellTuner", MD2)
    local P2 = MD2.Pool
    local before, after, why, frameBuilt
    if loaded and P2 then
        MD2:Fire("MD_READY")
        local m2 = P2.model
        before, why = m2 and m2.mana, m2 and m2.anchor.why
        S.Cast(774) -- Rejuvenation rank 1, 25 mana
        after = m2 and m2.mana
    end
    frameBuilt = MD2.Clock ~= nil
    check("a cast is priced by the pool with no clock frame built (T68)",
        loaded and P2 ~= nil and not frameBuilt and type(before) == "number" and before > 0
        and why == "assumed full at login" and after == before - 25
        and (P2:Sample()) == after and P2:Pool().mana == after,
        string.format("loaded=%s err=%s pool=%s clock=%s before=%s after=%s why=%s", tostring(loaded),
            tostring(loadErr), tostring(P2 ~= nil), tostring(frameBuilt), tostring(before), tostring(after),
            tostring(why)))
end

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
