-- tools/run.sh tools/clockcheck.lua
--
-- T11 (docs/tasks/T11-clock.md): the Forever mana clock -- Engine/ManaModel.lua
-- (pure), Engine/ManaPool_Forever.lua (the model instance, its events, the
-- pricing, the assume-full rule -- T68, P24) and UI/Clock_Forever.lua (the
-- widget and its hover, painting the pool). Forever only:
-- the modelled pool exists because current mana is secret on this client
-- (Facts); nothing here is meaningful on TBC, which reads UnitPower directly.
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
    local hoverOk = text:find("modelled", 1, true) ~= nil and text:find("secret on this client", 1, true) ~= nil
    check("every projection is marked modelled, in the text and the hover",
        item7TextOk and hoverOk, string.format("textHalf=%s hoverHalf=%s", tostring(item7TextOk), tostring(hoverOk)))

    local widgetText = Clock.text and Clock.text:GetText() or ""
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
print("warmup: " .. Clock.text:GetText())
print("  " .. HoverText())

for i = 1, 40 do
    S.Cast(5176) -- Wrath, cost 20
    S.Tick(0.5)
end
print("oom: " .. Clock.text:GetText())
print("  " .. HoverText())

S.Fire("PLAYER_REGEN_ENABLED")
S.inCombat = false
S.Tick(0.5)
print("after combat: " .. Clock.text:GetText())
print("  " .. HoverText())

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
    check("an unpriced opener stays in the hover's unpriced count",
        unpriced == 1 and hover:find("Unpriced casts: 1", 1, true) ~= nil,
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
    local text = Clock.text and Clock.text:GetText() or ""
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

    local back = Clock.barBack
    check("the mana bar has a black backing one physical pixel wider on every side",
        back ~= nil and back.parentFrame == w and SameColour(back.color, { 0, 0, 0, 1 })
        and Near(back.w, 160 + 2 * e) and Near(back.h, 4 + 2 * e)
        and Clock.bar and Clock.bar.w == 160 and Clock.bar.h == 4,
        string.format("back=%s w=%s h=%s want %s x %s", tostring(back ~= nil), tostring(back and back.w),
            tostring(back and back.h), tostring(160 + 2 * e), tostring(4 + 2 * e)))

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
