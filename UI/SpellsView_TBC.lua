-- The TBC Spells view (T83, C3 of docs/PLAN-refactor-ux.md; review U6;
-- mockup M6 in docs/mockups/refactor-ux.html, approved 2026-09-30).
--
-- One family's view in the Forever structure (UI/SpellsPane_Forever.lua's
-- T38 view), with TBC's numbers -- Engine/RankMath.lua's rows, as the rank
-- table always had them. Top to bottom, 12 px apart, inside one scroll frame
-- (the view scrolls when 13 ranks and the card do not fit):
--   1. the header: the icon, the name, what the family is (its shape, the
--      highest known rank, the cast), the mana at the right and the +healing
--      under it; while a what-if value is set the changed stats are in the
--      accent. The old stats line's regen, relic and Tree aura are the
--      +healing line's hover.
--   2. the decision strip: the SUGGESTED chip (SIMULATED while a what-if
--      value is set) and one comparison with the highest known rank, never
--      what to press; at the right "After overheal" (the old "Effective"),
--      the family's measured overheal under it, and "What if...", which
--      unfolds the Simulate strip (UI/Dashboard_Simulate.lua) under the
--      strip. The gold callout and the glossary hint line are gone.
--   3. RANKS: UI/Dashboard_Rows.lua's one table with T81's options and M6's
--      words -- Heal (Total for a HoT), Per mana, Per sec, Casts (`inf` when
--      regen keeps up, `999+` past 999) -- each header explaining itself in
--      one sentence; a click selects a rank (the white 2-px bar, T78), the
--      suggested row keeps its fill and accent bar.
--   4. the rank card for the selected rank (the suggested one by default):
--      the spell's base numbers, then label / value pairs -- the heal and its
--      crit, the downrank share of +healing, the cost.
--
-- The rank table itself (MD.DashboardParts.CreateRankTable) moved here from
-- UI/Dashboard.lua, where T81 built it; UI/Dashboard.lua keeps the four
-- families as views along the top (C5 replaces them with the rail) and
-- builds this view as the Spells group's one pane. TBC TOC only.
local _, MD = ...
local UI = MD.UI

MD.DashboardParts = MD.DashboardParts or {}

local RESET = "|r"
local RANK_W = 600
local VIEW_W = 720          -- the view inside the 912 content (mockup M6)
local HEADER_H = 48
local STRIP_H = 48
local CHIP_W = 150
local SIDE_W = 156          -- the strip's right column: After overheal, What if...
local BLOCK_GAP = 12
local PANE_TOP = 27         -- a titled pane's first control (Cell)
local CARD_PAIR = 17
local CARD_COL = 300
local CARD_LABEL_W = 70
local WHATIF_H = 46         -- UI/Dashboard_Simulate.lua's two rows
local CASTS_CAP = 999       -- past this a Casts cell reads "999+"

local function Pitch(n) return UI.Pitch and UI.Pitch(n) or n end

local function Fmt(n, decimals)
    return string.format(decimals and ("%." .. decimals .. "f") or "%d", n)
end

local function Round(x) return math.floor((x or 0) + 0.5) end

-- What a Casts cell says: inf when regen keeps up, 999+ past 999.
local function CastsText(n)
    if n == math.huge then return "inf" end
    if type(n) ~= "number" then return "-" end
    if n > CASTS_CAP then return CASTS_CAP .. "+" end
    return Fmt(n)
end

-- Any what-if value set (MD.sim, the Simulate strip's).
local function Simulating() return MD.sim ~= nil and next(MD.sim) ~= nil end

--------------------------------------------------------------------------------
-- The rank table (T81, moved here by T83): an opts set on the one table.
--------------------------------------------------------------------------------
-- Columns whose values become overheal-adjusted with "After overheal" on.
-- Mana, Cast and Casts never move: mana spent is mana spent.
local EFFECTIVE_COLS = { heal = true, hpm = true, hps = true }


local function AfterOverhealNote()
    if MD.db and MD.db.effectiveMode then
        return " After overheal: times (1 - your measured overheal)."
    end
    return ""
end

-- One sentence per header (U9 / U10, T78's shape): the words, with the
-- numbers the column counts from where it has them.
local HEAD_TIPS = {
    rank = "The spell's rank. x2 and x3 are Lifebloom kept rolling at that many stacks.",
    level = "The level you learn this rank at.",
    cost = "What one cast costs.",
    heal = function(label)
        if label == "Total" then
            return "All of one cast at your stats, every tick, with crits averaged in." .. AfterOverhealNote()
        end
        return "One cast at your stats, with crits averaged in." .. AfterOverhealNote()
    end,
    hpm = function() return "Healing for each point of mana." .. AfterOverhealNote() end,
    hps = function() return "Healing per second of cast (1.5 s for an instant)." .. AfterOverhealNote() end,
    cast = function()
        local info = MD.RankMath and MD.RankMath.info
        local ng = info and info.naturesGrace and info.naturesGrace > 0
        return "Cast time." .. (ng and " A * means Nature's Grace is averaged in." or "")
    end,
    casts = function()
        local info = MD.RankMath and MD.RankMath.info
        if not info then return "Casts in a row from your mana, counting your regen while casting." end
        return string.format("Casts in a row from %d mana, counting your regen while casting (%d mp5); "
            .. "inf when regen keeps up.", Round(info.mana), Round(info.castingRegen * 5))
    end,
}

-- A row's tag (the author's words, docs/PLAN-refactor-ux.md 8.1 item 7):
-- nil for none.
local function TagOf(r)
    if not r then return nil end
    if not r.known then return "learn at " .. tostring(r.level) end
    if r.virtual then return "rolling" end
    if r.suggested then return "best" end
    if r.isMax then return "max" end
    if r.dominated then return "beaten" end
    return nil
end

local function TagText(r)
    local tag = TagOf(r)
    if not tag then return "" end
    return UI.Hex(tag == "best" and "accent" or "label") .. tag .. RESET
end

-- A tag explains itself (T78's shape, mockup M5 / M6): one sentence, and a
-- beaten rank names the rank that beats it with both numbers side by side.
local function TagTip(r)
    local tag = TagOf(r)
    if not tag then return nil end
    if tag == "beaten" then
        local by = r.beatenBy -- the row the table's Render found (below)
        if not by then
            return { { l = "Beaten", c = "text" },
                     { l = "Another rank wins on both healing per mana and per second.", c = "label", wrap = true } }
        end
        local name = "Rank " .. by.rank
        return {
            { l = "Beaten by " .. name, c = "text" },
            { l = "Per mana", r = Fmt(by.hpm, 2) .. " vs " .. Fmt(r.hpm, 2), c = "label", rc = "text" },
            { l = "Per sec", r = Fmt(by.hps) .. " vs " .. Fmt(r.hps), c = "label", rc = "text" },
            { l = name .. " is better on both, and you know it.", c = "muted", wrap = true },
        }
    end
    local title, sentence
    if tag == "best" then
        title = "Best"
        sentence = "The rank SpellTuner suggests: the best healing per mana among the ranks nothing beats, "
            .. "of those that heal at least " .. Fmt((MD.Rules and MD.Rules.SUGGESTED_FLOOR or 0.4) * 100)
            .. "% of your highest." .. (r.isMax and " It is your highest rank too." or "")
    elseif tag == "max" then
        title, sentence = "Max", "Your highest known rank."
    elseif tag == "rolling" then
        title = "Rolling " .. tostring(r.rankLabel or "")
        sentence = "Lifebloom refreshed before it blooms, at this many stacks: 6 ticks, no bloom. "
            .. "A different use of the spell, so it is not ranked against the single casts."
    else
        title = "Not learned"
        sentence = "Not learned yet: learn at level " .. tostring(r.level) .. "."
    end
    return { { l = title, c = "text" }, { l = sentence, c = "label", wrap = true } }
end

-- Keys stay T81's (the data each cell shows); the words are M6's.
local RANK_COLS = {
    { key = "rank",  x = 8,   w = 44,  label = "Rank",     tooltip = HEAD_TIPS.rank },
    { key = "level", x = 52,  w = 34,  label = "Lvl",      justify = "RIGHT", tooltip = HEAD_TIPS.level },
    { key = "cost",  x = 86,  w = 50,  label = "Mana",     justify = "RIGHT", tooltip = HEAD_TIPS.cost },
    { key = "heal",  x = 136, w = 74,  label = "Heal",     justify = "RIGHT", tooltip = HEAD_TIPS.heal },
    { key = "hpm",   x = 210, w = 124, label = "Per mana", justify = "RIGHT", type = "bar", barWidth = 80, gap = 4,
      tooltip = HEAD_TIPS.hpm },
    { key = "hps",   x = 334, w = 58,  label = "Per sec",  justify = "RIGHT", tooltip = HEAD_TIPS.hps },
    { key = "cast",  x = 392, w = 52,  label = "Cast",     justify = "RIGHT", tooltip = HEAD_TIPS.cast },
    { key = "casts", x = 444, w = 58,  label = "Casts",    justify = "RIGHT", tooltip = HEAD_TIPS.casts },
    { key = "tag",   x = 510, w = 84,  label = "", font = UI.FONT_SMALL, cellTooltip = function(r) return TagTip(r) end },
}

-- The values a row shows: overheal-adjusted with After overheal on when the
-- row has a measurement of its own, else raw with `unmeasured` set.
local function ShownValues(r, effective)
    if effective and r.overheal then return r.effHeal, r.effHpm, r.effHps, false end
    return r.heal, r.hpm, r.hps, effective
end

-- r.hpmFrac (the Per mana bar's fill) and r.beatenBy (the row that beats a
-- beaten one) are written on the rows by the table's Render, below: RankMath
-- hands out fresh rows on every Compute, so they never outlive the render.
local function RenderRank(row, r, color)
    local effective = MD.db and MD.db.effectiveMode and true or false
    local heal, hpm, hps, unmeasured = ShownValues(r, effective)
    local c = row.cells
    c.wide:SetText("")
    c.rank:SetText(color .. (r.rankLabel or ("R" .. r.rank)) .. RESET)
    c.level:SetText(color .. r.level .. RESET)
    c.cost:SetText(color .. Fmt(r.cost) .. RESET)
    -- with After overheal on, a row with no measurement of its own keeps its
    -- raw value and gets a "?" so the two are never confused
    c.heal:SetText(color .. Fmt(heal) .. RESET .. (unmeasured and (UI.Hex("muted") .. "?" .. RESET) or ""))
    c.hpm:SetText(color .. Fmt(hpm, 2) .. RESET)
    c.hps:SetText(color .. Fmt(hps) .. RESET)
    -- the "*" means the cast time is a Nature's Grace average
    c.cast:SetText(color .. Fmt(r.cast, 1) .. "s" .. RESET .. (r.ng and (UI.Hex("muted") .. "*" .. RESET) or ""))
    c.casts:SetText(color .. CastsText(r.casts) .. RESET)
    c.tag:SetText(TagText(r))
    row:SetBar("hpm", r.hpmFrac, (not r.known) and 0.25 or nil)
end

local function RankEnter(row, r)
    if not (r and MD.Tip and MD.RankMath) then return end
    MD.Tip:Show(row, MD.Tip:Row(MD.RankMath:Explain(r.id, r.variant)), { anchor = "beside" })
end

-- MD.DashboardParts.CreateRankTable(content, width, extra) -> the table's
-- api, whose Render takes RankMath:Compute()'s rows for one family. `extra`
-- (optional): onClick(row, r) and selection = "bar", which the view passes.
function MD.DashboardParts.CreateRankTable(content, width, extra)
    local header = {}
    extra = extra or {}
    local api = MD.DashboardParts.CreateTable(content, width, {
        cols = RANK_COLS, header = header,
        font = UI.FONT_NUM or UI.FONT, wideFont = UI.FONT_SMALL,
        rowHeight = Pitch(20), headerHeight = Pitch(22),
        headerRule = true, zebra = true, rowWidth = RANK_W, marker = "bar",
        selection = extra.selection,
        headerFont = UI.FONT_SPECIAL, headerColor = UI.Hex("label"),
        render = RenderRank, onEnter = RankEnter, onClick = extra.onClick,
        onLeave = function() if MD.Tip then MD.Tip:Hide() end end,
    })
    -- the value column's word, which the view sets per family: Heal for a
    -- direct heal, Total for anything over time (Forever's rule, T38)
    api.valueLabel = "Heal"
    local paint = api.Render
    -- rows come straight from RankMath:Compute(). With After overheal on, the
    -- three healing columns' headers take the accent, so it is never
    -- ambiguous which numbers moved.
    function api:Render(rows)
        local effective = MD.db and MD.db.effectiveMode and true or false
        for i, col in ipairs(RANK_COLS) do
            local label = (col.key == "heal") and api.valueLabel or col.label
            if effective and EFFECTIVE_COLS[col.key] then
                header[i] = UI.Hex("accent") .. label .. RESET
            else
                header[i] = (label ~= col.label) and label or nil
            end
        end
        rows = rows or {}
        -- the bar's scale: the best per mana shown among the real ranks
        local suggested, maxHpm
        for _, r in ipairs(rows) do
            if r.suggested then suggested = r end
            local _, hpm = ShownValues(r, effective)
            if not r.virtual and type(hpm) == "number" and (not maxHpm or hpm > maxHpm) then maxHpm = hpm end
        end
        -- who beats a beaten rank (Spells/RankRules.lua, the rule the
        -- dominance came from; a beater is always a known, real rank)
        if MD.RankRules and MD.RankMath and MD.RankMath.RULE_FIELDS then
            MD.RankRules.DominatedBy(rows, suggested, MD.RankMath.RULE_FIELDS)
        end
        for _, r in ipairs(rows) do
            local _, hpm = ShownValues(r, effective)
            r.hpmFrac = (maxHpm and maxHpm > 0 and type(hpm) == "number") and hpm / maxHpm or nil
            r.beatenBy = nil
            if r.dominatedBy ~= nil then
                for _, x in ipairs(rows) do
                    if x.id == r.dominatedBy and not x.virtual then r.beatenBy = x end
                end
            end
        end
        return paint(api, rows)
    end
    return api
end

--------------------------------------------------------------------------------
-- The view's words
--------------------------------------------------------------------------------
local function FamilyType(family)
    local info = MD.SpellData.families[family]
    return info and info.type
end

-- The highest known real rank, and how many real ranks are known.
local function KnownTop(rows)
    local top, n = nil, 0
    for _, r in ipairs(rows) do
        if r.known and not r.virtual then
            n = n + 1
            if not top or r.rank > top.rank then top = r end
        end
    end
    return top, n
end

local function CastPhrase(r)
    if not r then return nil end
    return string.format("%.1f s cast", r.cast) .. (r.ng and " with Nature's Grace averaged" or "")
end

-- 1. The header's second line, by the family's shape.
local function HeaderSub(family, rows, info, res)
    local top, n = KnownTop(rows)
    local rankPart = top and string.format("Rank %d of %d known", top.rank, n) or "not learned yet"
    local s = top and MD.SpellData.spells[top.id]
    local dur = s and s.hotDuration
    local t = FamilyType(family)
    local parts
    if t == "direct" then
        parts = { "Direct heal", rankPart, CastPhrase(top) }
    elseif t == "hot" then
        parts = { "Heal over time", rankPart, dur and (dur .. " s") or nil }
    elseif t == "hybrid" then
        parts = { "Heal, hit and over time", rankPart, CastPhrase(top) }
    elseif t == "lifebloom" then
        parts = { "Heal over time and a bloom", rankPart, dur and (dur .. " s") or nil }
    else
        parts = { "Heal", rankPart }
    end
    local out = {}
    for i = 1, 3 do if parts[i] then out[#out + 1] = parts[i] end end
    local text = table.concat(out, " - ")
    if info and info.inTree and res and not res.tol then
        text = text .. UI.Hex("bad") .. "  - not castable in Tree of Life" .. RESET
    end
    return text
end

-- The header's mana: the live pool, or the what-if mana in the accent.
local function HeaderManaText(info)
    local sim = MD.sim or {}
    if sim.mana and info then
        return UI.Hex("accent") .. Fmt(Round(info.mana)) .. " mana" .. RESET .. UI.Hex("muted") .. "  what if" .. RESET
    end
    local mana = UnitPower and UnitPower("player", 0) or 0
    local max = UnitPowerMax and UnitPowerMax("player", 0) or 0
    return Fmt(Round(mana or 0)) .. " / " .. Fmt(Round(max or 0)) .. " mana"
end

-- The header's second right-hand line: +healing, and every what-if stat in
-- the accent (M6: "the header shows the changed stats in the accent").
local function HeaderStatsText(info)
    if not info then return "" end
    local sim = MD.sim or {}
    local acc, txt, mut = UI.Hex("accent"), UI.Hex("text2"), UI.Hex("muted")
    local heal = string.format("+%d", Round(info.statBonus))
    local parts = { (sim.heal and acc or UI.Hex("text")) .. heal .. RESET .. txt .. " healing" .. RESET }
    if info.treeAura and info.treeAura > 0 then
        parts[#parts + 1] = mut .. string.format("+%d Tree aura", Round(info.treeAura)) .. RESET
    end
    if sim.crit then parts[#parts + 1] = acc .. string.format("%.1f%% crit", sim.crit) .. RESET end
    if sim.casting then parts[#parts + 1] = acc .. string.format("%d mp5 casting", Round(sim.casting)) .. RESET end
    if sim.base then parts[#parts + 1] = acc .. string.format("%d mp5 resting", Round(sim.base)) .. RESET end
    if sim.tree ~= nil then parts[#parts + 1] = acc .. (sim.tree and "Tree of Life" or "caster form") .. RESET end
    if sim.moonglow then parts[#parts + 1] = acc .. "Moonglow " .. sim.moonglow .. RESET end
    return table.concat(parts, "  ")
end

-- The old stats line, as the +healing line's hover: what the numbers are
-- counted from.
local function StatsTip(info)
    local lines = { { l = "Your numbers", c = "text" } }
    if not info then return lines end
    local function P(l, r) lines[#lines + 1] = { l = l, r = r, c = "label", rc = "text" } end
    P("+healing", string.format("%d", Round(info.statBonus)) .. (MD.sim and MD.sim.heal and "  (what if)" or ""))
    if info.treeAura and info.treeAura > 0 then P("Tree of Life aura", string.format("+%d on party targets", Round(info.treeAura))) end
    P("Crit", string.format("%.1f%%", (info.crit or 0) * 100))
    local RM = MD.Regen
    P("Regen while casting", string.format("%d mp5", Round(info.castingRegen * 5)))
    P("Regen resting", string.format("%d mp5", Round(info.baseRegen * 5)))
    if RM and RM.Components then
        local spirit, gear, _, unreported = RM:Components()
        P("  from spirit / gear", string.format("%d / %d mp5", Round((spirit or 0) * 5), Round(gear or 0)))
        if unreported and unreported > 0 then
            P("  not in the API", string.format("%d mp5 (Dreamstate %d, measured %d)", Round(unreported * 5),
                Round((RM.dreamstate or 0) * 5), Round((RM.measured or 0) * 5)))
        end
    end
    P("Mana", string.format("%d", Round(info.mana)))
    local r = info.relic
    if r then
        local fl = r.family and MD.SpellData.families[r.family] and MD.SpellData.families[r.family].label or "?"
        local what = r.flat and string.format("+%d %s", r.flat, fl)
            or r.perTick and string.format("+%d per %s tick", r.perTick, fl)
            or r.castReduce and string.format("-%.2f s %s cast", r.castReduce, fl)
            or r.cost and string.format("-%d mana %s", r.cost, fl)
            or r.aura and string.format("+%d Tree aura", r.aura) or ""
        if r.verify then what = what .. ", unverified" end
        P("Relic", tostring(r.name) .. "  " .. what)
    end
    if info.inTree and not (info.treeAura and info.treeAura > 0) then
        lines[#lines + 1] = { l = "Tree of Life aura not counted (Settings).", c = "muted", wrap = true }
    end
    if info.costCtx then
        lines[#lines + 1] = { l = "Costs from the static table while a form or talent is simulated.", c = "muted", wrap = true }
    end
    return lines
end

-- 2. The strip's comparison line: the suggested rank against the highest.
local function Pct(a, b) return (b and b ~= 0) and Round((a / b) * 100) or nil end
local function CompareText(s, top)
    if not s then return "" end
    if not top or s == top then return "Your highest rank is also the best per mana." end
    local parts = {}
    local pm = Pct(s.hpm, top.hpm)
    if pm then
        local d = pm - 100
        if d == 0 then parts[#parts + 1] = "the same healing per mana"
        else parts[#parts + 1] = math.abs(d) .. "% " .. (d > 0 and "more" or "less") .. " healing per mana" end
    end
    local v = Pct(s.heal, top.heal)
    if v then parts[#parts + 1] = v .. "% of the heal" end
    local c = Pct(s.cast, top.cast)
    if c then
        local d = c - 100
        if d == 0 then parts[#parts + 1] = "the same cast"
        else parts[#parts + 1] = "a " .. math.abs(d) .. "% " .. (d < 0 and "shorter" or "longer") .. " cast" end
    end
    return "vs Rank " .. top.rank .. " (your highest): " .. table.concat(parts, ", ") .. "."
end

-- Lifebloom with tick and bloom overheal measured: which use of the highest
-- rank is worth more on this player's targets (the old callout's note).
local function RollNote(rows, top)
    if not (top and top.overheal and top.overheal.scope == "kind") then return nil end
    for _, r in ipairs(rows) do
        if r.id == top.id and r.variant == 3 and r.effHpm and top.effHpm then
            local better = r.effHpm > top.effHpm
            return string.format("After overheal, %s: rolled x3 %.2f vs one cast %.2f per mana.",
                better and "keep the stack rolling" or "let it bloom", r.effHpm, top.effHpm)
        end
    end
    return nil
end

local function MeasuredText(family)
    if not (MD.Overheal and MD.Overheal.FamilyFraction) then return UI.Hex("muted") .. "not measured yet" .. RESET end
    local frac = MD.Overheal:FamilyFraction(family)
    if not frac then return UI.Hex("muted") .. "not measured yet" .. RESET end
    return UI.Hex("muted") .. string.format("%d%% measured", Round(frac * 100)) .. RESET
end

-- 4. The card: the spell's own base numbers, then label / value pairs.
local function Range(lo, hi)
    lo, hi = Round(lo), Round(hi)
    if lo == hi then return tostring(lo) end
    return lo .. " - " .. hi
end

local function BaseLine(r)
    local s = MD.SpellData.spells[r.id]
    if not s then return "" end
    local t = FamilyType(s.family)
    local base
    if t == "direct" then
        base = "Base heal " .. Range(s.healMin, s.healMax)
    elseif t == "hot" then
        base = string.format("Base heal %d over %d s", Round(s.hotTotal), s.hotDuration or 0)
    elseif t == "hybrid" then
        base = string.format("Base heal %s, and %d over %d s", Range(s.healMin, s.healMax), Round(s.hotTotal),
            s.hotDuration or 0)
    elseif t == "lifebloom" then
        base = string.format("Base heal %d over %d s and a %d bloom", Round(s.hotTotal), s.hotDuration or 0,
            Round(s.bloom or 0))
    else
        return ""
    end
    return base .. ", before your +healing and the rules below."
end

local function CardPairs(r)
    local out = {}
    local mut = UI.Hex("muted")
    local function P(l, v) out[#out + 1] = { l, v } end
    local full = MD.RankMath and MD.RankMath:Explain(r.id, r.variant)
    local c = full and full.calc
    if not c then
        P("Cost", Fmt(r.cost) .. " mana")
        return out
    end
    if c.kind == "direct" then
        P("Heals", Range(c.min, c.max) .. mut .. string.format("  (%d with %d%% crit)", Round(r.heal), Round(c.crit * 100)) .. RESET)
        P("Crit", Range(c.min * 1.5, c.max * 1.5))
    elseif c.kind == "hot" then
        P("Tick", string.format("%d", Round(r.heal / c.ticks)) .. mut .. string.format("  x%d, every 3 s", c.ticks) .. RESET)
        P("Total", string.format("%d", Round(r.heal)) .. mut .. string.format("  over %d s", c.duration) .. RESET)
    elseif c.kind == "hybrid" then
        P("Direct", Range(c.min, c.max))
        P("Crit", Range(c.min * 1.5, c.max * 1.5))
        P("Over time", string.format("%d", Round(c.hot)) .. mut .. string.format("  over %d s", c.duration) .. RESET)
        P("Total", string.format("%d", Round(r.heal)) .. mut .. string.format("  with %d%% crit", Round(c.crit * 100)) .. RESET)
    elseif c.kind == "lifebloom" then
        if r.virtual then
            P("Rolled", string.format("%d", Round(r.heal)) .. mut .. string.format("  a refresh at %d stacks, no bloom", c.stacks or 0) .. RESET)
            P("Tick", string.format("%d", Round(c.tick * (c.stacks or 1))) .. mut .. string.format("  at %d stacks", c.stacks or 0) .. RESET)
        else
            P("Tick", string.format("%d", Round(c.tick)) .. mut .. "  x7, every 1 s" .. RESET)
            P("Bloom", string.format("%d", Round(c.bloom)) .. mut .. string.format("  crit %d", Round(c.bloom * 1.5)) .. RESET)
            P("Total", string.format("%d", Round(c.hot + c.bloom)))
        end
    end
    P("Downrank", string.format("%d%%", Round(c.penalty * 100)) .. mut .. "  of your +healing counts" .. RESET)
    P("Cost", Fmt(r.cost) .. " mana")
    if r.overheal then
        P("After overheal", string.format("%d", Round(r.effHeal)) .. mut .. string.format("  %d%% overheal, %s",
            Round(r.overheal.frac * 100), r.overheal.scope == "family" and "family average" or "measured") .. RESET)
    end
    return out
end

--------------------------------------------------------------------------------
-- Building the view
--------------------------------------------------------------------------------
local function TitledPane(parent, text)
    local pane = UI.CreateTitledPane(parent, text, VIEW_W, 60)
    local rc = UI.PALETTE and UI.PALETTE.rule
    if rc and pane.line then pane.line:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 0.6) end
    pane.note = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    pane.note:SetPoint("BOTTOMRIGHT", pane.line, "TOPRIGHT", 0, 3)
    pane.note:SetJustifyH("RIGHT")
    pane.note:SetTextColor(UI.RGB("text2"))
    return pane
end

local function KitTip(owner, lines)
    if MD.Tip then MD.Tip:Show(owner, lines, { anchor = "beside" }) end
end

local function SelectKey(r) return r and (tostring(r.id) .. ":" .. tostring(r.variant or 0)) or nil end

-- MD.DashboardParts.CreateSpellsView(parent, width, onChange) -> api:
--   api.frame, api:Render(family), api.rankTable, api.whatIf (the strip),
--   api:SetWhatIfOpen(on), api:WhatIfOpen(). onChange() is called when a
--   what-if value or After overheal changes (the dashboard's Refresh).
function MD.DashboardParts.CreateSpellsView(parent, width, onChange)
    local api = {}
    local f = CreateFrame("Frame", nil, parent)
    f.spellsViewTBC = true -- marks this pane for tools/dashui.lua
    f.api = api
    api.frame = f
    api.renderCount = 0
    local selected = {} -- family -> SelectKey of the rank the card shows

    f.scroll = UI.CreateScrollFrame(f, 0, 4)
    local content = f.scroll.content

    -- 1. the header
    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    header:SetSize(VIEW_W, Pitch(HEADER_H))
    header.iconEdge = header:CreateTexture(nil, "ARTWORK")
    header.iconEdge:SetSize(34, 34)
    header.iconEdge:SetPoint("LEFT", header, "LEFT", 4, 0)
    header.iconEdge:SetColorTexture(0, 0, 0, 1)
    header.icon = header:CreateTexture(nil, "OVERLAY")
    header.icon:SetSize(32, 32)
    header.icon:SetPoint("LEFT", header, "LEFT", 5, 0)
    header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    header.name = header:CreateFontString(nil, "OVERLAY", UI.FONT_HEAD or UI.FONT_TITLE)
    header.name:SetPoint("TOPLEFT", header, "TOPLEFT", 46, -6)
    header.name:SetJustifyH("LEFT")
    header.name:SetWordWrap(false)
    header.name:SetTextColor(UI.RGB("text"))
    header.sub = header:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    header.sub:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
    header.sub:SetJustifyH("LEFT")
    header.sub:SetWordWrap(false)
    header.sub:SetTextColor(UI.RGB("text2"))
    header.mana = header:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    header.mana:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -6)
    header.mana:SetJustifyH("RIGHT")
    header.mana:SetTextColor(UI.RGB("text"))
    header.stats = header:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    header.stats:SetPoint("TOPRIGHT", header.mana, "BOTTOMRIGHT", 0, -6)
    header.stats:SetJustifyH("RIGHT")
    header.stats:SetWordWrap(false)
    header.statsHit = CreateFrame("Frame", nil, header)
    header.statsHit:SetPoint("TOPRIGHT", header.stats, "TOPRIGHT", 0, 2)
    header.statsHit:SetSize(260, 16)
    header.statsHit:EnableMouse(true)
    header.statsHit:SetScript("OnEnter", function(self) KitTip(self, StatsTip(MD.RankMath and MD.RankMath.info)) end)
    header.statsHit:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
    f.header = header

    -- 2. the decision strip
    local strip = CreateFrame("Frame", nil, content)
    strip:SetSize(VIEW_W, Pitch(STRIP_H))
    local P = UI.PALETTE or {}
    local chip = CreateFrame("Frame", nil, strip, "BackdropTemplate")
    chip:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    chip:SetSize(CHIP_W, Pitch(STRIP_H))
    UI.StylizeFrame(chip, P.pane or { 0.11, 0.11, 0.11, 1 }, P.border or { 0, 0, 0, 1 })
    local a = UI.accent
    chip.bar = chip:CreateTexture(nil, "OVERLAY")
    chip.bar:SetPoint("TOPLEFT", chip, "TOPLEFT", 0, 0)
    chip.bar:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT", 0, 0)
    chip.bar:SetWidth(2)
    chip.bar:SetColorTexture(a[1], a[2], a[3], 1)
    strip.chipLabel = chip:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    strip.chipLabel:SetPoint("TOPLEFT", chip, "TOPLEFT", 10, -4)
    strip.chipLabel:SetJustifyH("LEFT")
    strip.chipLabel:SetTextColor(a[1], a[2], a[3])
    strip.chipLabel:SetText("SUGGESTED")
    strip.chipRank = chip:CreateFontString(nil, "OVERLAY", UI.FONT_BIG or UI.FONT_TITLE)
    strip.chipRank:SetPoint("TOPLEFT", chip, "TOPLEFT", 10, -17)
    strip.chipRank:SetJustifyH("LEFT")
    strip.chipRank:SetTextColor(UI.RGB("text"))
    chip:EnableMouse(true)
    chip:SetScript("OnEnter", function(self)
        local lines = TagTip({ known = true, suggested = true })
        lines[1] = { l = "Suggested rank", c = "text" }
        if Simulating() then
            lines[#lines + 1] = { l = "SIMULATED: counted from your what-if values, not your live stats.",
                c = "accent", wrap = true }
        end
        KitTip(self, lines)
    end)
    chip:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
    strip.chip = chip
    strip.compare = strip:CreateFontString(nil, "OVERLAY", UI.FONT)
    strip.compare:SetPoint("TOPLEFT", chip, "TOPRIGHT", BLOCK_GAP, -4)
    strip.compare:SetWidth(VIEW_W - CHIP_W - SIDE_W - 2 * BLOCK_GAP)
    strip.compare:SetJustifyH("LEFT")
    strip.compare:SetWordWrap(true)
    strip.compare:SetMaxLines(2)
    strip.compare:SetTextColor(UI.RGB("text2"))

    -- the right column: After overheal (was "Effective"), its share, What if...
    local side = CreateFrame("Frame", nil, strip)
    side:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    side:SetSize(SIDE_W, Pitch(STRIP_H))
    strip.after = UI.CreateCheckButton(side, "After overheal", function(checked)
        MD.db.effectiveMode = checked
        if onChange then onChange() end
    end, "After overheal", "Heal, Per mana and Per sec become value x (1 - measured overheal),",
        "from your own combat log. Mana, Cast and Casts never move.",
        "A grey ? means that rank has no measurement of its own yet.")
    strip.after:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -2)
    strip.measured = side:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    strip.measured:SetPoint("TOPLEFT", side, "TOPLEFT", 20, -18)
    strip.measured:SetJustifyH("LEFT")
    strip.whatIfBtn = UI.CreateButton(side, "What if...", "accent-hover", { SIDE_W, 16 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "What if...",
        "Try other stats, a form or a Moonglow rank on this table.",
        "Only this view reads them; the clock and the advisor never do.")
    strip.whatIfBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -31)
    f.strip = strip

    -- the what-if strip, folded until What if... opens it
    local whatIf = MD.DashboardParts.CreateStrip and MD.DashboardParts.CreateStrip(content, 0, 0, onChange)
    if whatIf then
        whatIf.frame:ClearAllPoints()
        whatIf.frame:SetWidth(VIEW_W)
        whatIf:SetShown(false)
    end
    api.whatIf = whatIf
    local whatIfOpen = false
    function api:WhatIfOpen() return whatIfOpen end
    function api:SetWhatIfOpen(on)
        whatIfOpen = on and true or false
        if whatIf then whatIf:SetShown(whatIfOpen) end
        api:Layout()
    end
    strip.whatIfBtn:SetScript("OnClick", function() api:SetWhatIfOpen(not whatIfOpen) end)

    -- 3. RANKS
    f.ranks = TitledPane(content, "RANKS")
    local family -- the family on show
    api.rankTable = MD.DashboardParts.CreateRankTable(f.ranks, VIEW_W, {
        selection = "bar",
        onClick = function(_, r)
            if not (r and family) then return end
            selected[family] = SelectKey(r)
            api:Render(family)
        end,
    })
    api.rankTable.frame:SetPoint("TOPLEFT", f.ranks, "TOPLEFT", 0, -(PANE_TOP - 4))
    api.rankTable.frame:SetWidth(VIEW_W)

    -- 4. the card
    local card = TitledPane(content, "RANK")
    card.pairPool = {}
    card.base = card:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
    card.base:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -PANE_TOP)
    card.base:SetWidth(VIEW_W - 16)
    card.base:SetJustifyH("LEFT")
    card.base:SetWordWrap(true)
    card.base:SetTextColor(UI.RGB("text2"))
    f.card = card

    local function CardPair(i)
        local p = card.pairPool[i]
        if p then return p end
        p = {}
        p.label = card:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
        p.label:SetJustifyH("LEFT")
        p.label:SetWordWrap(false)
        p.label:SetWidth(CARD_LABEL_W)
        p.label:SetTextColor(UI.RGB("label"))
        p.value = card:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
        p.value:SetJustifyH("LEFT")
        p.value:SetWordWrap(false)
        p.value:SetWidth(CARD_COL - CARD_LABEL_W - 8)
        p.value:SetTextColor(UI.RGB("text"))
        card.pairPool[i] = p
        return p
    end

    -- Returns the card's height.
    local function RenderCard(r)
        card.row = r
        local title = "RANK " .. tostring(r.rank)
        if r.virtual then title = title .. ", ROLLED " .. tostring(r.rankLabel or "") end
        card:SetTitle(title)
        local level = MD.player and MD.player.level
        card.note:SetText((r.known and "learned at " or "learn at ") .. tostring(r.level)
            .. (level and (" - you are " .. level) or ""))
        local y = PANE_TOP
        local base = BaseLine(r)
        card.base:SetText(base)
        if base ~= "" then
            card.base:Show()
            local h = card.base:GetStringHeight()
            y = y + ((type(h) == "number" and h > 0) and h or 12) + 8
        else
            card.base:Hide()
        end
        local pitch = Pitch(CARD_PAIR)
        local spec = CardPairs(r)
        for _, p in ipairs(card.pairPool) do p.label:Hide(); p.value:Hide() end
        for i, pair in ipairs(spec) do
            local p = CardPair(i)
            local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
            local x, py = 8 + col * CARD_COL, y + line * pitch
            p.label:ClearAllPoints()
            p.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, -py)
            p.value:ClearAllPoints()
            p.value:SetPoint("TOPLEFT", card, "TOPLEFT", x + CARD_LABEL_W + 2, -py)
            p.label:SetText(pair[1])
            p.value:SetText(pair[2])
            p.label:Show(); p.value:Show()
        end
        api.cardPairs = spec
        return y + math.ceil(#spec / 2) * pitch + 4
    end

    -- Places the blocks top to bottom, 12 px apart.
    local cardH = PANE_TOP
    function api:Layout()
        local y = Pitch(HEADER_H) + BLOCK_GAP
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + strip:GetHeight() + BLOCK_GAP
        if whatIf and whatIfOpen then
            whatIf.frame:ClearAllPoints()
            whatIf.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
            whatIf.frame:SetWidth(VIEW_W - 2)
            y = y + WHATIF_H + BLOCK_GAP
        end
        f.ranks:ClearAllPoints()
        f.ranks:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + f.ranks:GetHeight() + BLOCK_GAP
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        card:SetHeight(cardH)
        y = y + cardH + 4
        f.scroll:SetContentHeight(y)
        api.contentHeight = y
    end

    -- A full render of one family, from a fresh RankMath:Compute() (the
    -- dashboard's 2-s refresh calls it while the view shows).
    function api:Render(fam)
        family = fam
        api.renderCount = api.renderCount + 1
        local results = MD.RankMath:Compute()
        local info = MD.RankMath.info
        local res = results[fam]
        if not res then
            f.header.name:SetText("")
            f.header.sub:SetText("")
            strip:Hide(); f.ranks:Hide(); card:Hide()
            api.rankTable:Release()
            return
        end
        strip:Show(); f.ranks:Show(); card:Show()
        local rows = res.rows
        local top = KnownTop(rows)
        local suggested
        for _, r in ipairs(rows) do if r.suggested then suggested = r end end

        -- 1. the header
        local iconId = MD.SpellData.maxRank[fam] or (MD.SpellData.all[fam] and MD.SpellData.all[fam][1])
        local icon
        if iconId and GetSpellTexture then
            local ok, tex = pcall(GetSpellTexture, iconId)
            if ok then icon = tex end
        end
        if icon then
            header.icon:SetTexture(icon); header.icon:Show(); header.iconEdge:Show()
        else
            header.icon:Hide(); header.iconEdge:Hide()
        end
        header.name:SetText(res.label or fam)
        header.sub:SetText(HeaderSub(fam, rows, info, res))
        header.mana:SetText(HeaderManaText(info))
        header.stats:SetText(HeaderStatsText(info))

        -- 2. the strip
        local sim = Simulating()
        strip.chipLabel:SetText(sim and "SIMULATED" or "SUGGESTED")
        strip.chipRank:SetText(suggested and ("Rank " .. suggested.rank) or "-")
        local compare = suggested and CompareText(suggested, top) or "No rank learned yet."
        local roll = RollNote(rows, top)
        if roll then compare = compare .. " " .. roll end
        strip.compare:SetText(compare)
        strip.after:SetChecked(MD.db and MD.db.effectiveMode and true or false)
        strip.measured:SetText(MeasuredText(fam))
        if whatIf and info then whatIf:SetPlaceholders(info.live) end

        -- 3. RANKS
        local t = FamilyType(fam)
        api.rankTable.valueLabel = (t == "hot" or t == "hybrid" or t == "lifebloom") and "Total" or "Heal"
        if sim then
            f.ranks.note:SetText(UI.Hex("accent") .. "what if" .. (info and info.costCtx and
                ": costs from the static table" or ": your what-if values") .. RESET)
        else
            f.ranks.note:SetText("live: gear, talents, downrank rules")
        end
        local sel
        local want = selected[fam]
        for _, r in ipairs(rows) do
            if want and SelectKey(r) == want then sel = r end
        end
        sel = sel or suggested or top or rows[1]
        selected[fam] = SelectKey(sel)
        for _, r in ipairs(rows) do r.selected = (r == sel) or nil end
        api.selectedRow = sel
        api.rankTable:Render(rows)
        local rt = api.rankTable
        local tableH = 4 + rt.headerHeight + #rows * rt.rowHeight
        rt.frame:SetHeight(tableH)
        f.ranks:SetHeight(PANE_TOP - 4 + tableH)

        -- 4. the card
        cardH = sel and RenderCard(sel) or PANE_TOP
        if not sel then card:Hide() end
        api:Layout()
    end

    return api
end
