-- UI/Tip_TBC.lua (T76, P32 of docs/PLAN-refactor-ux.md; review A21): the TBC
-- line's tooltip builders, moved out of UI/Tooltip.lua unchanged. It holds
-- three: the clock and its regen terms (Tip:Mana), recent fights (Tip:Fights)
-- and the widget / minimap composite (Tip:Clock). T121: the spell and damage
-- blocks (Tip:Spell, Tip:Damage) and the column glossary (Tip:Columns) are
-- deleted -- the game's spell tooltip draws UI/SpellTip.lua's block on both
-- lines. T123: the rank table's row (Tip:Row) is deleted too -- nothing called it. Every one reads the TBC engine (MD.Regen,
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
