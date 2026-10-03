-- UI/Tip_TBC.lua (T76, P32 of docs/PLAN-refactor-ux.md; review A21): the TBC
-- line's tooltip builders, moved out of UI/Tooltip.lua unchanged -- the clock
-- and its regen terms (Tip:Mana), recent fights, the rank table's row, the
-- widget / minimap composite. T121: the spell and damage blocks (Tip:Spell,
-- Tip:Damage) and the column glossary (Tip:Columns) are deleted -- the game's
-- spell tooltip draws UI/SpellTip.lua's block on both lines. Every one reads the TBC engine (MD.Regen,
-- MD.RankMath, MD.SpellData, MD:GetManaState), so this file is on the TBC TOC
-- only; the line model, the renderer and Show / Hide are UI/Tip.lua's, which
-- loads just before it. Every hover surface on TBC (both ElvUI datatexts, the
-- minimap button, the floating widget, the dashboard's rows and recap line)
-- renders lines produced here, so they can never drift apart.
--
-- ASCII only in every string here (default WoW fonts lack arrow/infinity
-- glyphs) and never a bare "|" (it opens a colour escape).
local _, MD = ...
local UI = MD.UI

local Tip = MD.Tip

local WHITE  = { 1, 1, 1 }
local KEY    = { 0.78, 0.78, 0.78 }
local SUB    = { 0.63, 0.63, 0.63 }
local MUTED  = { 0.43, 0.43, 0.43 }
local WARN   = { 1, 0.67, 0.2 }
-- T43 (docs/SPEC-forever-ui.md 4.4): the theme's accent where it is loaded,
-- else gold (TBC). T69 (P25): a token read -- "tipGold", TBC's {1, 0.82, 0},
-- the accent themed.
local GOLD   = UI.TEXT.tipGold -- T107: the token's table (a style rewrites it in place), not a copy
local GOOD   = { 0.2, 1, 0.4 }
local MANA   = { 0.31, 0.66, 0.94 }

local function Accent()
    return UI.TEXT.accent -- T107: the token's table, read at each call
end

local function Plain(str)
    return (tostring(str):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--------------------------------------------------------------------------------
-- Mana state: the clock, what it is made of, and why it says what it says.
--------------------------------------------------------------------------------
function Tip:Mana()
    local lines = {}
    local s = MD.GetManaState and MD:GetManaState()
    if not s then return lines end
    local RM = MD.Regen
    local spiritPerSec, mp5Gear, _, unreported = RM:Components()

    if s.tto then
        lines[#lines + 1] = { l = "Time to OOM (raw)",
            r = string.format("%ds +- %ds", s.tto, s.sigmaT or 0) }
    elseif s.ttf then
        lines[#lines + 1] = { l = "Time to full (raw)", r = string.format("%ds", s.ttf) }
    elseif s.mode == "hold" then
        lines[#lines + 1] = { l = "Net rate within noise",
            r = s.bound and string.format("OOM no sooner than %ds", s.bound) or "sustainable" }
    end
    if s.inCombat and s.rest then
        lines[#lines + 1] = { l = "Full if you stop casting", r = string.format("%ds", s.rest) }
    end
    lines[#lines + 1] = { l = "Net rate (pessimistic)", r = string.format("%+d mana/s", -s.net) }
    lines[#lines + 1] = { l = "Spending",
        r = string.format("%d +- %d mana/s (%d casts, CV %.2f)", s.spend, s.sigma, s.casts, s.cv) }
    lines[#lines + 1] = { l = "Regen now / projected",
        r = string.format("%d / %d mana/s  (5SR %d%% of time)", s.regenNow, s.regen, s.duty * 100) }
    lines[#lines + 1] = { l = "Regen out of 5SR / casting",
        r = string.format("%d / %d mana/s", RM.base, RM.casting) }
    lines[#lines + 1] = { l = "Spirit / gear mp5",
        r = string.format("~%d / ~%d", spiritPerSec * 5, mp5Gear) }
    if unreported > 0 then
        lines[#lines + 1] = { l = "mp5 added, not in the API",
            r = string.format("%d  (Dreamstate %d, measured %d)", unreported * 5 + 0.5,
                RM.dreamstate * 5 + 0.5, RM.measured * 5 + 0.5) }
    end
    if RM:InFSR() then
        lines[#lines + 1] = { l = "Spirit regen resumes",
            r = string.format("%.1fs", RM:FSRRemaining()), c = WARN, rc = WHITE }
    end

    -- Between pulls: how many more this pool affords (Engine/PullBudget.lua).
    if MD.PullBudget then
        for _, ln in ipairs(MD.PullBudget:Lines()) do lines[#lines + 1] = ln end
    end

    -- What each mana source is worth right now, and what it buys on the clock.
    if MD.ManaCooldowns then
        local sources = MD.ManaCooldowns:All()
        if #sources > 0 then
            lines[#lines + 1] = {}
            for _, src in ipairs(sources) do
                local right
                if not src.ready then
                    right = string.format("%d mana, ready in %ds", src.delta, src.cdRemaining)
                elseif s.cd and s.cd.key == src.key and s.cd.tto then
                    right = string.format("%d mana -> OOM %ds", src.delta, s.cd.tto)
                else
                    right = string.format("%d mana, ready", src.delta)
                end
                lines[#lines + 1] = { l = src.name, r = right, c = KEY,
                    rc = src.ready and MANA or MUTED }
            end
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- Recent fights.
--------------------------------------------------------------------------------
function Tip:Fights(n)
    local lines = {}
    local hist = MD.fightHistory
    if not hist or #hist == 0 then return lines end
    n = math.min(n or 1, #hist)
    lines[#lines + 1] = {}
    if n == 1 then
        lines[#lines + 1] = { l = "Last fight: " .. Plain(hist[#hist].summary or "-"), c = SUB, wrap = true }
    else
        lines[#lines + 1] = { l = string.format("Last %d fights", n), c = Accent() }
        for i = #hist - n + 1, #hist do
            lines[#lines + 1] = { l = Plain(hist[i].summary or "-"), c = SUB, wrap = true }
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- Dashboard row: every term behind the numbers in the table, from row.calc
-- (RankMath:Explain). Nothing is modelled here that the row did not already
-- compute -- this is a view of RankMath, not a second opinion.
--------------------------------------------------------------------------------
local function Num(v, dec)
    return string.format(dec and ("%." .. dec .. "f") or "%d", v)
end

function Tip:Row(row)
    local lines = {}
    if not row then return lines end
    local c = row.calc
    if not c then return lines end

    local rankText = row.rankLabel and (c.label .. " (rolling " .. row.rankLabel .. ")")
        or string.format("%s (Rank %d)", c.label, row.rank)
    local note = row.suggested and "efficient rank" or row.isMax and "max rank"
        or row.dominated and "dominated" or (not row.known) and "not learned" or nil
    lines[#lines + 1] = { l = rankText, r = note,
        rc = row.suggested and GOLD or MUTED }
    lines[#lines + 1] = {}

    -- heal breakdown
    local healSuffix = ""
    if c.duration then
        healSuffix = string.format("  over %ds", c.duration)
        if c.ticks then healSuffix = healSuffix .. string.format(" (%d ticks)", c.ticks) end
    end
    lines[#lines + 1] = { l = "Heal", r = Num(row.heal) .. healSuffix, c = KEY }

    if c.kind == "lifebloom" then
        lines[#lines + 1] = { l = "  tick", r = Num(c.tick) .. " x7", c = SUB, rc = SUB }
        if not c.stacks then
            lines[#lines + 1] = { l = "  bloom", r = Num(c.bloom), c = SUB, rc = SUB }
        end
        lines[#lines + 1] = { l = string.format("  +healing  %d x %.4f hot / %.4f bloom coef x %.2f pen x %.2f %s",
            c.bonus, c.hotCoef, c.bloomCoef, c.penalty, c.bonusMult, c.bonusMultName), c = SUB }
        if c.relicTick and c.relicTick > 0 then
            lines[#lines + 1] = { l = "  relic", r = string.format("+%d per tick", c.relicTick), c = SUB, rc = SUB }
        end
    else
        lines[#lines + 1] = { l = "  base", r = Num(c.base), c = SUB, rc = SUB }
        if c.relicFlat and c.relicFlat > 0 then
            local relic = MD.RankMath.info and MD.RankMath.info.relic
            lines[#lines + 1] = { l = "  relic  " .. (relic and relic.name or "idol"),
                r = "+" .. Num(c.relicFlat), c = SUB, rc = SUB }
        end
        if c.kind == "hybrid" then
            lines[#lines + 1] = { l = string.format("  +healing direct  %d x %.2f coef x %.2f downrank",
                c.bonus, c.directCoef, c.penalty), r = "+" .. Num(c.directBonus), c = SUB, rc = SUB }
            lines[#lines + 1] = { l = string.format("  +healing hot  %d x %.2f coef x %.2f downrank x %.2f %s",
                c.bonus, c.hotCoef, c.penalty, c.bonusMult, c.bonusMultName),
                r = "+" .. Num(c.hotBonus), c = SUB, rc = SUB }
            lines[#lines + 1] = { l = string.format("  direct %d + hot %d", c.direct, c.hot), c = SUB }
        else
            lines[#lines + 1] = { l = string.format("  +healing  %d x %.2f coef x %.2f downrank x %.2f %s",
                c.bonus, c.coef, c.penalty, c.bonusMult, c.bonusMultName),
                r = "+" .. Num(c.bonusOut), c = SUB, rc = SUB }
        end
    end
    lines[#lines + 1] = { l = string.format("  talents  x%.2f", c.talentMult), c = SUB }
    if c.critMult then
        lines[#lines + 1] = { l = string.format("  crit  %.1f%% x1.5", c.crit * 100),
            r = string.format("x%.3f", c.critMult), c = SUB, rc = SUB }
    end

    lines[#lines + 1] = {}
    lines[#lines + 1] = { l = "Mana", r = Num(c.cost) .. "  " .. (c.costSource or "?"), c = KEY }
    lines[#lines + 1] = { l = "Cast", r = Num(row.cast, 1) .. "s" .. (row.ng and "*" or "") ..
        (row.cast <= 1.5 and "  GCD" or ""), c = KEY }
    if row.ng then
        lines[#lines + 1] = { l = string.format("  %.1fs base, %.1fs after a crit, %.1f%% crit -> %.2fs average",
            c.castBase, math.max(c.castBase - c.naturesGrace, 1.5), (c.ngCrit or 0) * 100, c.castNG), c = SUB }
        lines[#lines + 1] = { l = "  * Nature's Grace, chain-casting this one spell; an instant cast " ..
            "in between eats the buff for nothing.", c = MUTED, wrap = true }
    end

    lines[#lines + 1] = {}
    lines[#lines + 1] = { l = "HPM   heal per mana", r = Num(row.hpm, 2), c = KEY }
    lines[#lines + 1] = { l = "HPS   heal per second of cast", r = Num(row.hps), c = KEY }
    if row.casts == math.huge then
        lines[#lines + 1] = { l = "To OOM", r = "never: regen covers the cost", c = KEY, rc = GOOD }
    else
        lines[#lines + 1] = { l = "To OOM",
            r = string.format("%d casts from %d mana (net %d each)", row.casts, c.mana, c.netPerCast), c = KEY }
    end

    if row.overheal then
        local oh = row.overheal
        lines[#lines + 1] = {}
        lines[#lines + 1] = { l = "Overheal",
            r = string.format("%d%%  (%s, %d events)", oh.frac * 100,
                oh.scope == "rank" and "measured on this rank" or "family average", oh.n), c = KEY }
        lines[#lines + 1] = { l = "Effective",
            r = string.format("%d heal, %.2f HPM, %d HPS", row.effHeal, row.effHpm, row.effHps), c = KEY }
        if oh.tick then
            lines[#lines + 1] = { l = "  ticks / bloom overheal",
                r = string.format("%d%% / %s", oh.tick * 100 + 0.5, oh.bloom and string.format("%d%%", oh.bloom * 100 + 0.5) or "no bloom"),
                c = SUB, rc = SUB }
        end
        if oh.scope == "family" then
            lines[#lines + 1] = { l = "  A family average is the same factor on every rank, so it " ..
                "cannot say whether downranking overheals less. That needs samples on this rank.",
                c = MUTED, wrap = true }
        end
    end

    if row.virtual then
        lines[#lines + 1] = {}
        lines[#lines + 1] = { l = "Rolling stack: refreshed before it expires, so each cast is paid " ..
            "for with 6 ticks at the stack multiplier and never a bloom.", c = MUTED, wrap = true }
    end
    return lines
end

--------------------------------------------------------------------------------
-- The widget / minimap composite (T82, C4 of docs/PLAN-refactor-ux.md, mockup
-- M6): the title, then the clock in a healer's words as label / value pairs --
-- `Out of mana in 1:20`, `Full again in 2:10 if you stop` -- the words the
-- Forever clock says (UI/Clock_Forever.lua's SummaryLines), with TBC's numbers
-- and no "~" (nothing here is modelled). The raw lines (the time +- its
-- spread, the net rate, the spend with its CV, the regen terms, the mana
-- cooldowns, the pull budget: Tip:Mana) and the last fight are behind the
-- detail key, Shift on TBC as on the spell tooltip (UI/SpellTooltip.lua); a
-- press or a release while the widget's or the minimap button's tooltip is up
-- shows it again (the watcher below).
--------------------------------------------------------------------------------
-- A time as the tooltip says it: under 30 s to the second, else to 5 s, over
-- ten minutes ">10m" (the clock face's steps, Engine/TTO.lua), in M:SS.
local function Time(sec)
    if type(sec) ~= "number" or sec ~= sec then return "--" end
    if sec > 600 then return ">10m" end
    local step = sec < 30 and 1 or 5
    sec = step * math.floor(sec / step + 0.5)
    if sec > 600 then return ">10m" end
    return MD.Util.Clock(sec)
end
Tip.ClockTime = Time

-- A label / value pair: the label in `label`, the value white (M6's `w`).
local function Pair(l, r, rc) return { l = l, r = r, c = "label", rc = rc or "text" } end
Tip.ClockPair = Pair

-- Tip:ClockSummary(s): the pairs for one mana state (MD:GetManaState()'s);
-- {} without one.
function Tip:ClockSummary(s)
    local lines = {}
    if type(s) ~= "table" or not s.mode then return lines end
    local m = s.mode
    if m == "oom" then
        local r
        if s.confident == false and type(s.bound) == "number" then
            r = "no sooner than " .. Time(s.bound) -- the face's bound (`OOM >1:20 =`)
        elseif s.stable == false then
            r = "about " .. Time(s.tto)            -- the face's `~`
        else
            r = Time(s.tto)
        end
        lines[#lines + 1] = Pair("Out of mana in", r)
    elseif m == "warmup" then
        lines[#lines + 1] = Pair("Out of mana in", "a few more casts first", "muted")
    elseif m == "hold" then
        lines[#lines + 1] = Pair("Out of mana in", "not at this pace", "muted")
    elseif m == "full" or m == "ooc" then
        lines[#lines + 1] = Pair("Full again in", Time(s.ttf))
    elseif m == "nodata" then
        lines[#lines + 1] = Pair("Full again in", "--", "muted")
    elseif m == "fullnow" then
        lines[#lines + 1] = Pair("Full", "now")
    end
    -- the clock face's rule: a rest time beside an out-of-mana clock only,
    -- never next to FULL
    if s.inCombat and type(s.rest) == "number" and (m == "oom" or m == "hold" or m == "warmup") then
        lines[#lines + 1] = Pair("Full again in", Time(s.rest) .. " if you stop")
    end
    return lines
end

-- Tip:Clock(hints, detail): the lines. `hints`: a list of strings (a muted
-- line each) or line tables (as they are), after a spacer. `detail` adds the
-- raw lines and the last fight between the summary and the hints.
function Tip:Clock(hints, detail)
    local lines = { { l = "SpellTuner", c = "accent" } }
    local s = MD.GetManaState and MD:GetManaState()
    for _, ln in ipairs(Tip:ClockSummary(s)) do lines[#lines + 1] = ln end
    if detail then
        local mana = Tip:Mana()
        if #mana > 0 then
            lines[#lines + 1] = {}
            for _, ln in ipairs(mana) do lines[#lines + 1] = ln end
        end
        for _, ln in ipairs(Tip:Fights(1)) do lines[#lines + 1] = ln end
    end
    if hints and #hints > 0 then
        lines[#lines + 1] = {}
        for _, h in ipairs(hints) do
            if type(h) == "table" then
                lines[#lines + 1] = h
            else
                lines[#lines + 1] = { l = h, c = "muted" }
            end
        end
    end
    return lines
end

-- The detail key: Shift, read through the adapter.
function Tip.ClockDetail()
    return (MD.API and MD.API.IsShiftKeyDown and MD.API.IsShiftKeyDown() == true) or false
end

-- T79 (P36): the minimap button's clock lines on this line (UI/MinimapButton.lua);
-- T82: the detail key read at each hover.
MD:Provide("MinimapLines", function(hints) return Tip:Clock(hints, Tip.ClockDetail()) end)

-- T82: Shift pressed or released while the clock's tooltip is up -- the
-- widget's or the minimap button's -- runs the owner's OnEnter again, so the
-- detail lines come and go without moving the mouse (UI/SpellTooltip.lua's
-- rule for the spell tooltip). Both owners are named frames.
local CLOCK_OWNERS = { "SpellTunerWidget", "SpellTunerMinimapButton" }
function Tip.OnClockModifier(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not (GameTooltip and GameTooltip:IsShown()) then return end
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if not owner then return end
    for _, name in ipairs(CLOCK_OWNERS) do
        if owner == _G[name] then
            local enter = owner.GetScript and owner:GetScript("OnEnter")
            if enter then enter(owner) end
            return
        end
    end
end
MD:On("MODIFIER_STATE_CHANGED", Tip.OnClockModifier)
