-- T36 (docs/SPEC-forever-ui.md 3.1-3.4, 3.6; docs/tasks/T36-spells-rail-picker.md):
-- the Forever window's Spells group, split out of UI/Dashboard_Forever.lua.
--
-- The group is a rail group (UI.CreateNavFrame's layout = "rail", T31): no
-- view row, a 172-px list down the content's left edge -- MY SPELLS,
-- Overview, then one row per family of the player's own list
-- (Spells/Tabs.lua, T35), each row a real nav view ("fam:<family>"), so
-- db.uiPath remembers it and MD:SelectView("spells", "fam:Rejuvenation")
-- works. [ + Add ] opens the picker, a sheet over the spell view only (the
-- rail stays live under it); a spell dragged from the spellbook onto the rail
-- goes in at the drop row, read through MD.API.CursorInfo -- the cursor is
-- NEVER cleared (a spell picked off an action bar is off the bar; clearing it
-- would delete the player's button). /st spell <name> opens a family's view,
-- or its preview with a banner when it is not in the list.
--
-- Overview is T39's (3.6): My spells, one row per listed family, its
-- suggested rank against its highest; Whole book, today's Spellbook table
-- under 3.5's look (a header row per family with + or listed, a row per rank
-- in the RANKS columns); Export, the probe's format, the whole book.
-- A family's view is T38's (3.5): the header, the decision strip, the RANKS
-- table, the rank card, the row hover and the refresh split.
--
-- T84 (C5 of docs/PLAN-refactor-ux.md): the rail's glue -- its rows, the
-- footer and Undo line, the drop, the picker and the group's definition --
-- moved to UI/SpellRail.lua, shared with TBC's Spells group, and is
-- installed on SpellsPane below with the book as its source; what this pane
-- shows is unchanged (tools/spellsui.lua byte for byte).
--
-- Forever TOCs only. Client data only through MD.API (the book, the clock,
-- the cursor); the widget toolkit is not a client call (CLAUDE.md, T1b).
local _, MD = ...
local UI = MD.UI
-- T67 (P23, review A13): how a rank's cost, cast, per second, casts and
-- value are said is Spells/Words.lua's, shared with the spell tooltip's
-- block; this file picks the styles of 3.5 / 3.6 and the colours.
local Words = MD.Words

local SpellsPane = {}
MD.SpellsPane = SpellsPane

-- 3.2 / 4.3 metrics at font offset 0; every vertical pitch below goes through
-- UI.Pitch (4.2), so it grows with a positive offset.
-- (T84: the rail's row, footer and picker metrics went with the glue to
-- UI/SpellRail.lua.)
local HEADER_H = 48         -- a family view's header
local BANNER_H = 20         -- the preview banner
local VIEW_PREFIX = MD.SpellRail.VIEW_PREFIX -- "fam:", both lines (T84)

local function Pitch(n)
    if UI.Pitch then return UI.Pitch(n) end
    return n
end

-- Colours are the theme's tokens, read through UI.Hex / UI.RGB (T69, P25: the
-- tokens are always present, and the theme is always listed before this file
-- on Forever, so the private helpers and their flat fallbacks are gone).

local RESET = "|r"

-- The probe's escaping (a literal backslash doubled first, then a pipe as
-- "||", then any non-ASCII/control byte as "\ddd"), so every client-read name
-- on screen, in a tooltip or in the export stays ASCII with no bare pipe. Its
-- one copy is MD.Text.EscASCII in Core.lua (T60, P16, review A9); every caller
-- below hands it a string or nil (nil is "", as it was here).
local Esc = MD.Text.EscASCII

-- A number that is nil renders "-", never 0 (CLAUDE.md).
local Num = Words.Num

local function Book() return MD.Book end
local function Tabs() return MD.Tabs end

local FamilyKey = MD.SpellRail.FamilyKey

--------------------------------------------------------------------------------
-- Cells every table in the pane shares (the RANKS table, Whole book, the
-- export's words): today's Spellbook table went with T39 (3.6).
--------------------------------------------------------------------------------
-- Review R13: a spell that costs Rage / Focus / Energy costs no mana; its
-- own cost is named ("10 Rage") rather than read as mana or called "free".
-- The Mana and Cast cells: Spells/Words.lua's "cell" style (3.5).
local function ManaCellText(e)
    return Words.Cost(e, "cell")
end

local function CastCellText(e)
    return Words.Cast(e, "cell")
end

local function Pool()
    local pool
    if MD.Clock and MD.Clock.Pool then pool = MD.Clock:Pool() end
    return pool or MD.Book:DefaultPool()
end

--------------------------------------------------------------------------------
-- Export: the probe's dump block format, so tools/refcheck.py reads it the
-- way it reads a probe report. Scope: the whole book (3.6).
--------------------------------------------------------------------------------
-- The export's cost and cast: Spells/Words.lua's "export" style (3.6).
local function ExportCostText(e)
    return Words.Cost(e, "export")
end

local function ExportCastText(e)
    return Words.Cast(e, "export")
end

-- Review B20: the character line's name and realm come from the client like
-- every other string in the export, so they pass the same Esc (a name with a
-- diaeresis exports as "\ddd", never as raw bytes).
local function Str(v)
    return (type(v) == "string") and Esc(v) or "?"
end

local function ExportText()
    local book = MD.Book:Get()

    local name = MD.API.UnitName("player")
    local realm = MD.API.RealmName()
    local locClass, classToken = MD.API.UnitClass("player")
    if type(locClass) ~= "string" or type(classToken) ~= "string" then classToken = nil end
    local level = MD.API.UnitLevel("player")
    local levelText = (type(level) == "number") and tostring(level) or "?"

    local lines = {}
    lines[#lines + 1] = "character: " .. Str(name) .. " " .. Str(realm) .. " " .. Str(classToken)
        .. " level " .. levelText
    lines[#lines + 1] = "== spells"

    local function DumpFamily(name2)
        for _, e in ipairs(book.families[name2].ranks) do
            lines[#lines + 1] = "spell " .. tostring(e.id)
            lines[#lines + 1] = "  name: " .. Esc(e.name or "")
            lines[#lines + 1] = "  rank: " .. Esc(e.rankText or "")
            lines[#lines + 1] = "  desc: " .. Esc(e.desc or "")
            lines[#lines + 1] = "  cost: " .. ExportCostText(e)
            lines[#lines + 1] = "  cast: " .. ExportCastText(e)
            if type(e.level) == "number" then
                lines[#lines + 1] = "  level: " .. tostring(e.level)
            end
        end
    end

    for _, n in ipairs(book.order) do if book.families[n].kind == "heal" then DumpFamily(n) end end
    for _, n in ipairs(book.order) do if book.families[n].kind == "damage" then DumpFamily(n) end end
    for _, n in ipairs(book.order) do if not book.families[n].kind then DumpFamily(n) end end

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- T38 (docs/SPEC-forever-ui.md 3.5, docs/tasks/T38-one-spell-view.md): one
-- spell's view. Top to bottom, 12 px apart, inside one scroll frame (the
-- view scrolls when it is taller than the pane):
--   1. the header: the icon, the name, what the family is (its shape), and
--      the modelled pool at the right ("~" only on the current pool);
--   2. the decision strip: the SUGGESTED chip and one factual comparison
--      with the highest known rank (Book:Compare), never what to press;
--      no strip with one known rank;
--   3. RANKS: one row per rank from 1 to the highest listed, gaps included,
--      on UI/Dashboard_Rows.lua's table with T30's options (the per-mana
--      bar, the fills, the tags; no gold, no star, no legend);
--   4. the rank card for the selected rank (the suggested one by default),
--      and one footer line.
-- A row's hover is the game's own tooltip for that rank (MD.API.
-- SetTooltipSpell), the SpellTuner block under it from the Spell post-call,
-- or added here when the post-call did not run. The 2-s tick updates the
-- header's mana, the card's Now and the To OOM cells in place; a full render
-- happens on a book change, a new bonus-healing reading, a new pool max, a
-- font offset or a view switch. Every vertical pitch goes through UI.Pitch.
--------------------------------------------------------------------------------
local VIEW_W = 540          -- 524 of columns plus 8 px each side, inside the 556 view
local STRIP_H = 44
local CHIP_W = 150
local BLOCK_GAP = 12
local PANE_TOP = 27         -- a titled pane's first control (Cell)
local TABLE_ROW = 20
local TABLE_HEAD = 22
local CARD_PAIR = 17
local CARD_COL = 262
local CARD_LABEL_W = 70
local TIP_GAP = 6           -- the row tooltip's distance from the row
local SUGGESTED_RULE = Words.SuggestedRule() -- the floor is MD.Rules.SUGGESTED_FLOOR (T67)
local GAP_TEXT = 'not in your spellbook - untrained, or hidden by "show all ranks"'
local FOOTER_TEXT = "Values come from the spell's own text. ~ = modelled."

-- T78 (P34, review U9 / U10; mockup M5): one vocabulary -- "Per mana",
-- "Per sec", "Casts" -- and every header says what it is, one sentence each,
-- on hover (UI/Dashboard_Rows.lua's col.tooltip). What the healing words
-- name follows the family on show: SpellsPane.headKind is "heal" or "damage"
-- while a family's view is drawn, nil on Whole book (both kinds at once).
local function Amount()
    if SpellsPane.headKind == "heal" then return "Healing" end
    if SpellsPane.headKind == "damage" then return "Damage" end
    return "Healing or damage"
end
local HEAD_TIPS = {
    level = "The level you learn this rank at.",
    mana = "What one cast costs.",
    value = function(label)
        if label == "Heal" then return "The average heal of one cast, from the spell's own text." end
        if label == "Dmg" then return "The average damage of one cast, from the spell's own text." end
        if label == "Total" then return "All of one cast, over its whole duration, from the spell's own text." end
        return "The average heal or damage of one cast; all of it for one over time."
    end,
    permana = function() return Amount() .. " for each point of mana." end,
    persec = function() return Amount() .. " per second of casting." end,
    cast = "Cast time; inst for an instant, chan for a channel.",
    toOOM = "Casts in a row from a full pool.",
}
local TagTip -- the tag cell's hover (below, with the tags)

-- The RANKS columns (3.5): 524 wide from x = 8. The Tag column starts 8 px
-- into its 60 so a tag never touches the right-justified Casts number.
local RANK_COLS = {
    { key = "rank",    x = 8,   w = 52,  label = "Rank" },
    { key = "level",   x = 60,  w = 34,  label = "Lvl",      justify = "RIGHT", tooltip = HEAD_TIPS.level },
    { key = "mana",    x = 94,  w = 46,  label = "Mana",     justify = "RIGHT", tooltip = HEAD_TIPS.mana },
    { key = "value",   x = 140, w = 58,  label = "Heal",     justify = "RIGHT", tooltip = HEAD_TIPS.value },
    { key = "permana", x = 198, w = 116, label = "Per mana", justify = "RIGHT", type = "bar", barWidth = 72, gap = 4,
      tooltip = HEAD_TIPS.permana },
    { key = "persec",  x = 314, w = 54,  label = "Per sec",  justify = "RIGHT", tooltip = HEAD_TIPS.persec },
    { key = "cast",    x = 368, w = 46,  label = "Cast",     justify = "RIGHT", tooltip = HEAD_TIPS.cast },
    { key = "toOOM",   x = 414, w = 58,  label = "Casts",    justify = "RIGHT", tooltip = HEAD_TIPS.toOOM },
    { key = "tag",     x = 480, w = 52,  label = "", font = UI.FONT_SMALL,
      cellTooltip = function(r) return TagTip(r) end },
}
-- A family with no value (3.5 "Other-kind"): Rank / Lvl / Mana / Cast / Tag.
local OTHER_COLS = {
    { key = "rank",  x = 8,   w = 52, label = "Rank" },
    { key = "level", x = 60,  w = 34, label = "Lvl",  justify = "RIGHT", tooltip = HEAD_TIPS.level },
    { key = "mana",  x = 94,  w = 46, label = "Mana", justify = "RIGHT", tooltip = HEAD_TIPS.mana },
    { key = "cast",  x = 140, w = 46, label = "Cast", justify = "RIGHT", tooltip = HEAD_TIPS.cast },
    { key = "tag",   x = 202, w = 52, label = "", font = UI.FONT_SMALL,
      cellTooltip = function(r) return TagTip(r) end },
}

local function Round(x) return math.floor(x + 0.5) end

local function KnownRanks(fam)
    local n = 0
    for _, e in ipairs(fam.ranks or {}) do if e.known ~= false then n = n + 1 end end
    return n
end

-- The rank a family's words are read from: the highest known, else the
-- first listed.
local function Rep(fam)
    return fam.maxKnown or (fam.ranks and fam.ranks[1])
end

local PartOf = Words.PartOf

-- "2.0 s cast", "instant", "channeled"; nil when the book has no cast.
local function CastWord(e)
    return Words.Cast(e, "phrase")
end

-- A cost in words: "25 mana", "free", "5% of base mana", "10 Rage", "-".
local function CostWord(e)
    return Words.Cost(e, "card")
end

-- 1. The header's second line, by the family's shape (Book's family.shape).
local function HeaderSub(fam)
    local rep = Rep(fam)
    local top = fam.maxKnown
    local rankPart
    if top and type(top.rank) == "number" then
        rankPart = string.format("Rank %d of %d known", top.rank, KnownRanks(fam))
    elseif not top and KnownRanks(fam) == 0 then
        rankPart = "not learned yet"
    end
    local heal = fam.kind == "heal"
    local parts = {}
    local shape = fam.shape
    if shape == "direct" then
        local isAbsorb = heal and type(rep.parsed) == "table" and rep.parsed.heal == nil and rep.parsed.absorb ~= nil
        parts[1] = isAbsorb and "Absorb" or (heal and "Direct heal" or "Direct damage")
        parts[#parts + 1] = rankPart
        parts[#parts + 1] = CastWord(rep)
    elseif shape == "hot" then
        parts[1] = heal and "Heal over time" or "Damage over time"
        parts[#parts + 1] = rankPart
        local part = PartOf(rep, fam.kind)
        local dur = part and (part.dur or part.periodDur)
        if type(dur) == "number" then parts[#parts + 1] = Num(dur) .. " s" end
    elseif shape == "hybrid" then
        parts[1] = heal and "Heal" or "Damage"
        parts[2] = "hit and over time"
        local part = PartOf(rep, fam.kind)
        if part and type(part.school) == "string" then parts[3] = Esc(part.school) end
        parts[#parts + 1] = rankPart
    else
        parts[1] = "Utility"
        parts[#parts + 1] = rankPart
        parts[#parts + 1] = CostWord(rep)
    end
    local out = {}
    for i = 1, 6 do if parts[i] then out[#out + 1] = parts[i] end end
    return table.concat(out, " - ")
end

-- 2. The strip's comparison line (Book:Compare's numbers, rounded).
local function CompareText(a, b, kind)
    local c = MD.Book:Compare(a, b)
    if not c then return "" end
    local what = (kind == "damage") and "damage" or "healing"
    local noun = (kind == "damage") and "damage" or "heal"
    local parts = {}
    if c.perMana then
        local p = Round(math.abs(c.perMana))
        if p == 0 then
            parts[#parts + 1] = "the same " .. what .. " per mana"
        else
            parts[#parts + 1] = p .. "% " .. (c.perMana > 0 and "more" or "less") .. " " .. what .. " per mana"
        end
    end
    if c.value then parts[#parts + 1] = Round(c.value) .. "% of the " .. noun end
    if c.cast then
        local p = Round(math.abs(c.cast))
        if p == 0 then
            parts[#parts + 1] = "the same cast time"
        else
            parts[#parts + 1] = "a " .. p .. "% " .. (c.cast < 0 and "shorter" or "longer") .. " cast"
        end
    end
    local head = "vs Rank " .. tostring(b.rank or "-") .. " (your highest)"
    if #parts == 0 then return head .. "." end
    return head .. ": " .. table.concat(parts, ", ") .. "."
end

-- The header's pool: "~364 / 364 mana", the "~" and the mana colour on the
-- modelled current pool only; the max plain.
local function HeaderManaText(pool)
    if type(pool) == "table" and type(pool.mana) == "number" and type(pool.max) == "number" then
        return UI.Hex("mana") .. "~" .. Num(pool.mana) .. RESET .. " / " .. Num(pool.max) .. " mana"
    end
    return UI.Hex("muted") .. "mana not modelled yet" .. RESET
end

-- The pool a To OOM cell counts from: full, at the clock's (else the book's)
-- max and casting regen.
local function FullPool(pool)
    return { max = pool.max, regenCasting = pool.regenCasting }
end

local function CastsWord(n)
    return Words.Casts(n, "short")
end

--------------------------------------------------------------------------------
-- Tooltips beside a row (3.5): TOPLEFT at the row's TOPRIGHT +6, or, when
-- that runs off the screen's right edge, TOPRIGHT at the row's TOPLEFT -6.
-- Nothing anchors to the window edge. T76 (P32, review A21 / U28): the rule
-- is UI/Tip.lua's Tip:Place(tt, owner, "beside") now, shared with every
-- other placed tooltip; this file only asks for it.
--------------------------------------------------------------------------------
local function Place(tt, row)
    MD.Tip:Place(tt, row, "beside")
end

-- The kit tooltip (a gap row, a rank not learned, the chip): a title and
-- its lines, every colour passed, so no default gold is inherited. T76: the
-- kit's shape (Tip.Simple: title in `text`, the rest in `text2`, wrapped)
-- through MD.Tip:Kit, placed beside.
local function KitTip(owner, title, ...)
    if not UI.tooltip then return end
    MD.Tip:Kit(owner, MD.Tip.Simple({ title, ... }), { anchor = "beside" })
end

local function RankName(fam, rank)
    return Esc(fam.name or "") .. ((type(rank) == "number") and (" Rank " .. rank) or "")
end

-- A known rank: the game's own tooltip for that id, then the block. The
-- tooltip's guard (UI/SpellTip_Forever.lua's _spellTipId) is cleared first,
-- so "the block is there" is read from this showing alone.
-- T76 (P32, review U2; decision 7): still GameTooltip -- whether the Spell
-- post-call fires for SetSpellByID on another tooltip is unverified on
-- Forever -- with its content kept and the kit skin laid on it while this
-- row owns it (MD.Tip:Skin; off again when it hides or another owner
-- clears it), so it reads as the same tooltip as the rest of the window.
local function GameTip(row, fam, e)
    local tt = GameTooltip
    tt:SetOwner(row, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint("TOPLEFT", row, "TOPRIGHT", TIP_GAP, 0)
    tt._spellTipId = nil
    local shown = MD.API.SetTooltipSpell(tt, e.id)
    if not shown then
        tt:AddLine(RankName(fam, e.rank), UI.RGB("text"))
    end
    if tt._spellTipId ~= e.id and MD.SpellTip then
        local ok, lines = pcall(MD.SpellTip.Lines, MD.SpellTip, e.id, MD.SpellTip:DetailShown())
        if ok and type(lines) == "table" then
            tt:AddLine(" ")
            MD.SpellTip:Render(tt, lines)
        end
    end
    MD.Tip:Skin(tt, row)
    tt:Show()
    Place(tt, row)
end

--------------------------------------------------------------------------------
-- 3. The RANKS rows
--------------------------------------------------------------------------------
-- A rank row's tag: "best", "learn at N", "max" or "beaten" (T78, the
-- author's word for `dominated`, docs/PLAN-refactor-ux.md 8.1 item 7), nil
-- for none or for a row that is not a rank.
local function TagOf(r)
    local e = r and r.kind == "rank" and r.entry
    if not e then return nil end
    if e.suggested then return "best" end
    if e.known == false then
        return (type(e.level) == "number") and ("learn at " .. e.level) or "not learned"
    end
    if r.isMax then return "max" end
    if e.dominated then return "beaten" end
    return nil
end

-- T78 (U7): the tags in `label`, best in the accent; the explanations that
-- used to be `disabled` grey are readable.
local function TagText(r)
    local tag = TagOf(r)
    if not tag then return "" end
    if tag == "best" then return UI.Hex("accent") .. tag .. RESET end
    return UI.Hex("label") .. tag .. RESET
end

-- The known rank that beats `e` (Book's entry.dominatedBy, an id), or nil.
local function BeatenBy(fam, e)
    local id = e.dominatedBy
    if id == nil or not fam then return nil end
    for _, x in ipairs(fam.ranks or {}) do
        if x.id == id then return x end
    end
    return nil
end

-- T78 (U10; mockup M5): a tag explains itself on hover, one sentence; a
-- beaten rank names the rank that beats it with both numbers side by side.
local TAG_SENTENCE = {
    best = "The rank SpellTuner suggests.",
    max = "Your highest known rank.",
}
function TagTip(r)
    local tag = TagOf(r)
    if not tag then return nil end
    local e = r.entry
    if tag == "beaten" then
        local by = BeatenBy(r.family, e)
        if not (by and type(by.rank) == "number") then
            return { { l = "Beaten", c = "text" },
                     { l = "Another rank wins on both per mana and per sec.", c = "label", wrap = true } }
        end
        local name = "Rank " .. by.rank
        return {
            { l = "Beaten by " .. name, c = "text" },
            { l = "Per mana", r = Num(by.perMana, 2) .. " vs " .. Num(e.perMana, 2), c = "label", rc = "text" },
            { l = "Per sec", r = Num(by.perSec, 1) .. " vs " .. Num(e.perSec, 1), c = "label", rc = "text" },
            { l = name .. " is better on both, and you know it.", c = "muted", wrap = true },
        }
    end
    local title = tag:sub(1, 1):upper() .. tag:sub(2)
    local sentence = TAG_SENTENCE[tag] or "Not learned yet."
    return { { l = title, c = "text" }, { l = sentence, c = "label", wrap = true } }
end

local function RankCell(e)
    if type(e.rank) == "number" then return "R" .. e.rank end
    return "-"
end

local function SetWide(row, x, text)
    local wide = row.cells.wide
    if not wide then return end
    wide:ClearAllPoints()
    wide:SetPoint("LEFT", row, "LEFT", x, 0)
    wide:SetWidth(VIEW_W - x - 8)
    wide:SetText(text)
end

local function RenderRankRow(row, r, color)
    r.color = color
    for _, fs in pairs(row.cells) do fs:SetText("") end
    if r.kind == "gap" then
        -- T78 (U7): the number disabled, its explanation readable in `muted`
        row.cells.rank:SetText(UI.Hex("disabled") .. "R" .. r.rank .. RESET)
        SetWide(row, RANK_COLS[2].x, UI.Hex("muted") .. GAP_TEXT .. RESET)
        if row.SetBar then row:SetBar("permana", nil) end
        return
    end
    SetWide(row, 8, "")
    local e = r.entry
    local c = row.cells
    c.rank:SetText(color .. RankCell(e) .. RESET)
    c.level:SetText(color .. Num(e.level) .. RESET)
    c.mana:SetText(color .. ManaCellText(e) .. RESET)
    c.cast:SetText(color .. CastCellText(e) .. RESET)
    c.tag:SetText(TagText(r))
    if c.value then
        c.value:SetText(color .. Num(e.value) .. RESET)
        c.permana:SetText(color .. Num(e.perMana, 2) .. RESET)
        c.persec:SetText(color .. Num(e.perSec, 1) .. RESET)
        c.toOOM:SetText(color .. CastsWord(r.fullCasts) .. RESET)
        local frac
        if type(e.perMana) == "number" and type(r.maxPerMana) == "number" and r.maxPerMana > 0 then
            frac = e.perMana / r.maxPerMana
        end
        if row.SetBar then row:SetBar("permana", frac, (e.known == false) and 0.25 or nil) end
    end
end

-- The 2-s tick's in-place update (T30's onUpdateCells): the To OOM cell,
-- against the full pool SpellsPane:UpdateFamilyLive read once for the tick.
local function UpdateRankRow(row, r)
    if r.kind ~= "rank" or not row.cells.toOOM then return end
    r.fullCasts = MD.Book:CastsFor(r.entry, SpellsPane.liveFull or FullPool(Pool()))
    row.cells.toOOM:SetText((r.color or "") .. CastsWord(r.fullCasts) .. RESET)
end

local function RankRowEnter(row, r)
    if not r then return end
    local fam = r.family
    if r.kind == "gap" then
        KitTip(row, RankName(fam, r.rank), 'Not in your spellbook: untrained, or hidden by "show all ranks".')
        return
    end
    local e = r.entry
    if e.known == false then
        local why = (type(e.level) == "number") and ("Not learned yet: learn at level " .. e.level .. ".")
            or "Not learned yet."
        KitTip(row, RankName(fam, e.rank), why)
        return
    end
    if type(e.id) == "number" then GameTip(row, fam, e) end
end

local function RankRowLeave()
    GameTooltip:Hide()
    if UI.tooltip then UI.tooltip:Hide() end
end

local function RankRowClick(_, r)
    if not r or r.kind ~= "rank" then return end
    SpellsPane:SelectRank(r.entry.id)
end

-- The family's rows: one per rank from 1 to the highest listed, a gap a
-- spanning row; unranked entries (no rank number) after them, one each.
local function FamilyRows(fam, pool)
    local rows, byRank, unranked, maxListed = {}, {}, {}, 0
    local maxPerMana
    for _, e in ipairs(fam.ranks) do
        if type(e.rank) == "number" then
            byRank[e.rank] = byRank[e.rank] or e
            if e.rank > maxListed then maxListed = e.rank end
        else
            unranked[#unranked + 1] = e
        end
        if type(e.perMana) == "number" and (not maxPerMana or e.perMana > maxPerMana) then maxPerMana = e.perMana end
    end
    local full = FullPool(pool)
    local function Add(e)
        rows[#rows + 1] = { kind = "rank", rank = e.rank, entry = e, id = e.id, family = fam,
            known = e.known, suggested = e.suggested, dominated = e.dominated,
            isMax = (fam.maxKnown == e), maxPerMana = maxPerMana,
            fullCasts = MD.Book:CastsFor(e, full) }
    end
    for n = 1, maxListed do
        if byRank[n] then Add(byRank[n])
        else rows[#rows + 1] = { kind = "gap", rank = n, known = false, family = fam } end
    end
    for _, e in ipairs(unranked) do Add(e) end
    return rows
end

--------------------------------------------------------------------------------
-- 4. The rank card
--------------------------------------------------------------------------------
local function PerSecWord(e, kind)
    return Words.PerSec(e, kind, "card", { muted = UI.Hex("muted"), reset = RESET })
end

-- The label/value pairs for one rank, by shape: { {label, value}, ... }.
local function CardPairs(fam, e, pool)
    local out = {}
    local function P(l, v) out[#out + 1] = { l, v } end
    local kind = fam.kind
    if kind then
        local parts = Words.Value(e, kind, "card", { muted = UI.Hex("muted"), reset = RESET })
        for _, p in ipairs(parts) do P(p[1], p[2]) end
    end
    P("Cost", CostWord(e))
    P("Cast", Words.Cast(e, "card"))
    if kind then
        P("Per mana", Num(e.perMana, 2))
        P("Per sec", PerSecWord(e, kind)) -- T78: one vocabulary
    end
    -- T95 (docs/SPEC-next.md 4.2 P1): the reach in words (an upper bound;
    -- per mana and per sec above stay one target's, decision 12), the
    -- cooldown and the per-target lockout -- each only when the book read one.
    local reach = kind == "heal" and Words.Reach(e)
    if reach then P("Reach", reach) end
    if type(e.cooldown) == "number" then P("Cooldown", Words.Seconds(e.cooldown)) end
    if type(e.lockout) == "number" then P("Lockout", Words.Seconds(e.lockout) .. " per target") end
    local out2 = { pairs = out }
    local amount = e.cost and e.cost.power == nil and e.cost.amount
    if kind and type(amount) == "number" and amount > 0 then
        out2.toOOM = #out + 1
        P("Casts", "") -- T78: the table's word
        out2.now = #out + 1
        P("Now", "")
    end
    return out2
end

local function ToOOMWord(n)
    return Words.Casts(n, "card")
end

local function NowWord(e, pool)
    if type(pool.mana) ~= "number" then
        return UI.Hex("muted") .. "mana not modelled yet" .. RESET
    end
    local now = MD.Book:CastsFor(e, pool)
    local mana = UI.Hex("mana")
    if now == math.huge then return "never - regen keeps up" end
    return mana .. "~" .. CastsWord(now) .. RESET .. " from " .. mana .. "~" .. Num(pool.mana) .. RESET .. " mana"
end

local function CardPair(card, i)
    local p = card.pairPool[i]
    if p then return p end
    p = {}
    p.label = card:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
    p.label:SetJustifyH("LEFT")
    p.label:SetWordWrap(false)
    p.label:SetWidth(CARD_LABEL_W)
    UI.Tint(p.label, "text", "label")
    p.value = card:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    p.value:SetJustifyH("LEFT")
    p.value:SetWordWrap(false)
    p.value:SetWidth(CARD_COL - CARD_LABEL_W - 8)
    UI.Tint(p.value, "text", "text")
    card.pairPool[i] = p
    return p
end

-- The live half of the card (the tick's): To OOM and Now for the selected rank.
local function UpdateCardLive(f, pool)
    local card = f.card
    local e = card.entry
    if not e then return end
    if card.toOOMPair then card.toOOMPair.value:SetText(ToOOMWord(MD.Book:CastsFor(e, FullPool(pool)))) end
    if card.nowPair then card.nowPair.value:SetText(NowWord(e, pool)) end
end

-- Returns the card's height.
local function RenderCard(f, fam, e, pool)
    local card = f.card
    card.entry = e
    card.pitch = Pitch(CARD_PAIR)
    if type(e.rank) == "number" then
        card.title:SetText("RANK " .. e.rank)
    elseif type(e.rankText) == "string" and e.rankText ~= "" then
        card.title:SetText(Esc(e.rankText):upper())
    else
        card.title:SetText("SPELL")
    end
    if type(e.level) == "number" then
        card.learned:SetText((e.known == false and "learn at " or "learned at ") .. e.level)
    else
        card.learned:SetText(e.known == false and "not learned" or "")
    end

    local y = PANE_TOP
    if type(e.desc) == "string" and e.desc ~= "" then
        card.quote:SetText('"' .. Esc(e.desc) .. '"')
        card.quote:ClearAllPoints()
        card.quote:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y)
        card.quote:Show()
        local h = card.quote:GetStringHeight()
        y = y + ((type(h) == "number" and h > 0) and h or 12) + 8
    else
        card.quote:SetText("")
        card.quote:Hide()
    end

    local spec = CardPairs(fam, e, pool)
    for _, p in ipairs(card.pairPool) do p.label:Hide(); p.value:Hide() end
    card.shown, card.toOOMPair, card.nowPair = {}, nil, nil
    for i, pair in ipairs(spec.pairs) do
        local p = CardPair(card, i)
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, py = 8 + col * CARD_COL, y + line * card.pitch
        p.label:ClearAllPoints()
        p.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, -py)
        p.value:ClearAllPoints()
        p.value:SetPoint("TOPLEFT", card, "TOPLEFT", x + CARD_LABEL_W + 2, -py)
        p.label:SetText(pair[1])
        p.value:SetText(pair[2])
        p.label:Show(); p.value:Show()
        card.shown[#card.shown + 1] = p
        if i == spec.toOOM then card.toOOMPair = p end
        if i == spec.now then card.nowPair = p end
    end
    y = y + math.ceil(#spec.pairs / 2) * card.pitch
    UpdateCardLive(f, pool)

    if e.stale then
        card.stale:ClearAllPoints()
        card.stale:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -(y + 2))
        card.stale:Show()
        y = y + card.pitch + 2
    else
        card.stale:Hide()
    end
    return y + 4
end

--------------------------------------------------------------------------------
-- Building the view
--------------------------------------------------------------------------------
local function TitledPane(parent, text)
    local pane = UI.CreateTitledPane(parent, text, VIEW_W, 60)
    if UI.PALETTE and UI.PALETTE.rule and pane.line then UI.Tint(pane.line, "texture", "rule") end -- T107
    return pane
end

-- The two tables for the current pitch, built once per pitch (a font offset
-- changes the row height, which UI/Dashboard_Rows.lua fixes at creation).
local function Tables(f)
    local rowH, headH = Pitch(TABLE_ROW), Pitch(TABLE_HEAD)
    local k = rowH .. "/" .. headH
    f.tables = f.tables or {}
    local t = f.tables[k]
    if not t then
        local function Make(cols, header)
            local api = MD.DashboardParts.CreateTable(f.ranks, VIEW_W, {
                cols = cols, header = header,
                font = UI.FONT_NUM or UI.FONT, wideFont = UI.FONT_SMALL,
                rowHeight = rowH, headerHeight = headH, headerRule = true,
                zebra = true, rowWidth = true, marker = "bar",
                -- T78 (U1 / U7; mockup M5): the selected rank a white bar,
                -- the fill the suggested one's alone; headers 12 px in `label`
                selection = "bar", headerFont = UI.FONT_SPECIAL, headerColor = "label", -- T107: a token, read at render
                render = RenderRankRow, onUpdateCells = UpdateRankRow,
                onEnter = RankRowEnter, onLeave = RankRowLeave, onClick = RankRowClick,
            })
            api.frame:SetPoint("TOPLEFT", f.ranks, "TOPLEFT", 0, -(PANE_TOP - 4))
            api.frame:SetWidth(VIEW_W)
            api.frame:Hide()
            return api
        end
        t = { header = {} }
        t.rank = Make(RANK_COLS, t.header)
        t.other = Make(OTHER_COLS, nil)
        f.tables[k] = t
    end
    for key, other in pairs(f.tables) do
        if key ~= k then
            other.rank:Release(); other.rank.frame:Hide()
            other.other:Release(); other.other.frame:Hide()
        end
    end
    f.rankTable, f.otherTable = t.rank, t.other
    return t
end

local function LayoutFamily(f)
    local top = 0
    f.banner:SetHeight(Pitch(BANNER_H))
    if f.banner:IsShown() then top = Pitch(BANNER_H) + 6 end
    f.scroll:Resize(-top, 4)
    f.header:SetHeight(Pitch(HEADER_H))
end

local function BuildFamily(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    f.spellsFamily = true -- marks this pane for tools/spellsui.lua
    f.renderCount, f.liveCount = 0, 0
    local P = UI.PALETTE or {}

    -- the preview banner (3.6): "Not in your list.  [+ Add to my spells]"
    local banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    banner:SetHeight(Pitch(BANNER_H))
    UI.StylizeFrame(banner, P.suggested or P.pane or { 0.13, 0.13, 0.13, 1 }, P.border or { 0, 0, 0, 1 })
    banner.text = banner:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    banner.text:SetPoint("LEFT", banner, "LEFT", 8, 0)
    banner.text:SetJustifyH("LEFT")
    UI.Tint(banner.text, "text", "text2")
    banner.text:SetText("Not in your list.")
    banner.addBtn = UI.CreateButton(banner, "+ Add to my spells", "accent-hover", { 130, 16 },
        false, false, UI.FONT_SMALL, UI.FONT_SMALL)
    banner.addBtn:SetPoint("LEFT", banner.text, "RIGHT", 10, 0)
    banner.addBtn:SetScript("OnClick", function()
        local key = SpellsPane.preview
        if key then SpellsPane:AddFromPreview(key) end
    end)
    banner:Hide()
    f.banner = banner
    SpellsPane.banner = banner

    f.scroll = UI.CreateScrollFrame(f, 0, 4)
    local content = f.scroll.content

    -- 1. the header: a 32x32 icon with a 1-px black border, the name, what
    -- it is, and the modelled pool at the right
    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    header:SetWidth(VIEW_W)
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
    header.sub = header:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    header.sub:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
    header.sub:SetJustifyH("LEFT")
    header.sub:SetWordWrap(false)
    UI.Tint(header.sub, "text", "text2")
    header.mana = header:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    header.mana:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -8)
    header.mana:SetJustifyH("RIGHT")
    UI.Tint(header.mana, "text", "text")
    f.header = header

    -- a family the book no longer has (3.3)
    f.staleText = content:CreateFontString(nil, "OVERLAY", UI.FONT)
    f.staleText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -BLOCK_GAP)
    f.staleText:SetJustifyH("LEFT")
    UI.Tint(f.staleText, "text", "text2")
    f.staleText:Hide()
    f.removeBtn = UI.CreateButton(content, "Remove", "accent-hover", { 70, 20 })
    f.removeBtn:SetPoint("TOPLEFT", f.staleText, "BOTTOMLEFT", 0, -8)
    f.removeBtn:SetScript("OnClick", function()
        if f.key then SpellsPane:Remove(f.key) end
    end)
    f.removeBtn:Hide()

    -- 2. the decision strip: the chip, and the comparison beside it
    local strip = CreateFrame("Frame", nil, content)
    strip:SetWidth(VIEW_W)
    local chip = CreateFrame("Frame", nil, strip, "BackdropTemplate")
    chip:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    chip:SetWidth(CHIP_W)
    UI.StylizeFrame(chip, P.pane or { 0.11, 0.11, 0.11, 1 }, P.border or { 0, 0, 0, 1 })
    chip.bar = chip:CreateTexture(nil, "OVERLAY")
    chip.bar:SetPoint("TOPLEFT", chip, "TOPLEFT", 0, 0)
    chip.bar:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT", 0, 0)
    chip.bar:SetWidth(2)
    UI.Tint(chip.bar, "texture", "accent", 1) -- T107: the accent by name
    strip.chipLabel = chip:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    strip.chipLabel:SetPoint("TOPLEFT", chip, "TOPLEFT", 10, -4)
    strip.chipLabel:SetJustifyH("LEFT")
    UI.Tint(strip.chipLabel, "text", "accent")
    strip.chipLabel:SetText("SUGGESTED")
    strip.chipRank = chip:CreateFontString(nil, "OVERLAY", UI.FONT_BIG or UI.FONT_TITLE)
    strip.chipRank:SetPoint("TOPLEFT", chip, "TOPLEFT", 10, -17)
    strip.chipRank:SetJustifyH("LEFT")
    UI.Tint(strip.chipRank, "text", "text")
    chip:EnableMouse(true)
    chip:SetScript("OnEnter", function(self) KitTip(self, "Suggested rank", SUGGESTED_RULE) end)
    chip:SetScript("OnLeave", function() if UI.tooltip then UI.tooltip:Hide() end end)
    strip.chip = chip
    strip.compare = strip:CreateFontString(nil, "OVERLAY", UI.FONT)
    strip.compare:SetPoint("LEFT", chip, "RIGHT", BLOCK_GAP, 0)
    strip.compare:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    strip.compare:SetJustifyH("LEFT")
    strip.compare:SetWordWrap(true)
    strip.compare:SetMaxLines(2)
    UI.Tint(strip.compare, "text", "text2")
    strip:Hide()
    f.strip = strip

    -- 3. RANKS
    f.ranks = TitledPane(content, "RANKS")

    -- 4. the rank card, and the footer under it
    local card = TitledPane(content, "RANK")
    card.pairPool, card.shown = {}, {}
    card.learned = card:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    card.learned:SetPoint("BOTTOMRIGHT", card.line, "TOPRIGHT", 0, 3)
    card.learned:SetJustifyH("RIGHT")
    UI.Tint(card.learned, "text", "text2")
    card.quote = card:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
    card.quote:SetWidth(VIEW_W - 16)
    card.quote:SetJustifyH("LEFT")
    card.quote:SetWordWrap(true)
    UI.Tint(card.quote, "text", "text2")
    card.stale = card:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
    card.stale:SetJustifyH("LEFT")
    UI.Tint(card.stale, "text", "bad")
    card.stale:SetText("Text read before combat - may be out of date")
    card.stale:Hide()
    f.card = card
    f.footer = content:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    f.footer:SetJustifyH("LEFT")
    UI.Tint(f.footer, "text", "muted")
    f.footer:SetText(FOOTER_TEXT)

    LayoutFamily(f)

    -- the refresh split (3.5): every 2 s while shown, the live numbers in
    -- place, or a full render when what the view was drawn from changed
    MD:OnTick(function()
        if not f:IsVisible() or not f.key then return end
        local now = GetTime()
        if f.lastTick and (now - f.lastTick) < 2 then return end
        f.lastTick = now
        MD.Book:Get() -- a changed book fires BOOK_CHANGED here, and bumps bookGen
        if SpellsPane:Signature(f.key, f.preview) ~= f.signature then
            SpellsPane:RenderFamily(f.key, f.preview)
        else
            SpellsPane:UpdateFamilyLive()
        end
    end)
    return f
end

-- What a full render was drawn from (3.5): the view, the book's generation
-- (BOOK_CHANGED), the bonus-healing reading (the last plain one), the pool's
-- max and the pitch.
SpellsPane.bookGen = 0
function SpellsPane:Signature(key, preview)
    local bonus = MD.API.SpellBonusHealing and MD.API.SpellBonusHealing()
    if type(bonus) == "number" and not MD.API.IsSecret(bonus) then self.lastBonus = bonus end
    local pool = Pool()
    return table.concat({ tostring(key), tostring(preview and true or false), tostring(self.bookGen),
        tostring(self.lastBonus), tostring(pool.max), tostring(Pitch(TABLE_ROW)) }, "|")
end

-- The tick's in-place half: the header's mana, the card's To OOM and Now,
-- and the To OOM cells. Nothing released, re-acquired or re-laid out.
function SpellsPane:UpdateFamilyLive()
    local f = self.family
    if not f or not f.fam then return end
    local pool = Pool()
    f.header.mana:SetText(HeaderManaText(pool))
    UpdateCardLive(f, pool)
    self.liveFull = FullPool(pool)
    if f.activeTable and f.activeTable.UpdateCells then f.activeTable:UpdateCells() end
    self.liveFull = nil
    f.liveCount = f.liveCount + 1
end

-- A rank row clicked: the card follows, the fills repaint in place.
function SpellsPane:SelectRank(id)
    local f = self.family
    if not f or not f.fam then return end
    local e
    for _, x in ipairs(f.fam.ranks) do if x.id == id then e = x end end
    if not e then return end
    f.selectedId = id
    if f.activeTable then f.activeTable:SetSelected(id) end
    local h = RenderCard(f, f.fam, e, Pool())
    self:LayoutBlocks(h)
end

local function DefaultSelection(fam)
    if fam.suggested then return fam.suggested end
    if fam.maxKnown then return fam.maxKnown end
    for _, e in ipairs(fam.ranks) do if e.known ~= false then return e end end
    return fam.ranks[1]
end

-- Places the blocks top to bottom, 12 px apart; `cardH` is the card's own
-- height (RenderCard's answer).
function SpellsPane:LayoutBlocks(cardH)
    local f = self.family
    local content = f.scroll.content
    local y = Pitch(HEADER_H) + BLOCK_GAP
    if f.strip:IsShown() then
        f.strip:ClearAllPoints()
        f.strip:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + f.strip:GetHeight() + BLOCK_GAP
    end
    f.ranks:ClearAllPoints()
    f.ranks:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    y = y + f.ranks:GetHeight() + BLOCK_GAP
    f.card:ClearAllPoints()
    f.card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    f.card:SetHeight(cardH)
    y = y + cardH + 4
    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    y = y + 16
    f.scroll:SetContentHeight(y)
end

local function ShowBlocks(f, on)
    for _, b in ipairs({ f.ranks, f.card, f.footer }) do
        if on then b:Show() else b:Hide() end
    end
    if not on then f.strip:Hide() end
end

function SpellsPane:RenderFamily(key, preview)
    local f = self.family
    if not f then return end
    if f.key ~= key then f.selectedId = nil end
    f.key, f.preview = key, preview and true or false
    f.lastTick = GetTime()
    f.signature = self:Signature(key, preview)
    f.renderCount = f.renderCount + 1
    f.refreshCount = f.renderCount -- T36's name for it
    if preview then f.banner:Show() else f.banner:Hide() end
    LayoutFamily(f)
    local t = Tables(f)

    local book = MD.Book:Get()
    local fam = MD.Tabs:Resolve(key, book)
    if type(fam) ~= "table" then
        -- 3.3: kept, greyed, never dropped silently
        f.fam = nil
        f.header.icon:Hide(); f.header.iconEdge:Hide()
        f.header.name:SetText(Esc(key))
        UI.Tint(f.header.name, "text", "disabled")
        f.header.sub:SetText("")
        f.header.mana:SetText("")
        f.staleText:SetText(Esc(key) .. " is not in this character's spellbook.")
        f.staleText:Show()
        f.removeBtn:Show()
        f.rankTable:Release(); f.otherTable:Release()
        f.rankTable.frame:Hide(); f.otherTable.frame:Hide()
        f.activeTable = nil
        ShowBlocks(f, false)
        f.lastRows = {}
        f.scroll:SetContentHeight(Pitch(HEADER_H) + 60)
        return
    end
    f.fam = fam
    f.staleText:Hide()
    f.removeBtn:Hide()
    ShowBlocks(f, true)
    local pool = Pool()

    -- 1. the header
    local rep = Rep(fam)
    if rep and rep.icon then
        f.header.icon:SetTexture(rep.icon); f.header.icon:Show(); f.header.iconEdge:Show()
    else
        f.header.icon:Hide(); f.header.iconEdge:Hide()
    end
    f.header.name:SetText(Esc(fam.name or key))
    UI.Tint(f.header.name, "text", "text")
    f.header.sub:SetText(HeaderSub(fam))
    f.header.mana:SetText(HeaderManaText(pool))

    -- 2. the strip: two or more known ranks with a value, and a suggestion
    local valued = 0
    for _, e in ipairs(fam.ranks) do
        if e.known ~= false and e.value ~= nil then valued = valued + 1 end
    end
    local s = fam.suggested
    f.strip:SetHeight(Pitch(STRIP_H))
    f.strip.chip:SetHeight(Pitch(STRIP_H))
    if fam.kind and s and valued >= 2 then
        f.strip.chipRank:SetText((type(s.rank) == "number") and ("Rank " .. s.rank) or "-")
        if s == fam.maxKnown then
            f.strip.compare:SetText("Your highest rank is also the best per mana.")
        else
            f.strip.compare:SetText(CompareText(s, fam.maxKnown, fam.kind))
        end
        f.strip:Show()
    else
        f.strip:Hide()
    end

    -- 3. RANKS
    local rows = FamilyRows(fam, pool)
    local active
    SpellsPane.headKind = fam.kind -- T78: what the header tooltips call the amount
    if fam.kind then
        -- the value column's label by shape: a total for anything over time
        local label = (fam.kind == "damage") and "Dmg" or "Heal"
        if fam.shape == "hot" or fam.shape == "hybrid" then label = "Total" end
        wipe(t.header)
        t.header[4] = label
        active = t.rank
        t.other:Release(); t.other.frame:Hide()
    else
        active = t.other
        t.rank:Release(); t.rank.frame:Hide()
    end
    f.activeTable = active
    local sel
    if f.selectedId then
        for _, e in ipairs(fam.ranks) do if e.id == f.selectedId then sel = e end end
    end
    sel = sel or DefaultSelection(fam)
    f.selectedId = sel and sel.id or nil
    active.selectedId = f.selectedId
    active.frame:Show()
    active:Render(rows)
    f.lastRows = rows
    local tableH = 4 + active.headerHeight + #rows * active.rowHeight
    active.frame:SetHeight(tableH)
    f.ranks:SetHeight(PANE_TOP - 4 + tableH)

    -- 4. the card
    local cardH = sel and RenderCard(f, fam, sel, pool) or PANE_TOP
    self:LayoutBlocks(cardH)
end

--------------------------------------------------------------------------------
-- T39 (docs/SPEC-forever-ui.md 3.6, docs/tasks/T39-overview.md): Overview, the
-- rail's first row. A title row -- OVERVIEW, [My spells][Whole book] and
-- [Export] -- over one scroll frame that holds one of two tables:
--   My spells: one row per family in the list, in its order -- the suggested
--     rank (its value, per mana and To OOM from full) against the highest
--     known (its value and per mana); a click opens that family's view;
--   Whole book: today's Spellbook table under 3.5's look -- sections Heals /
--     Damage / Other, a header row per family (its icon, its name, a 16x16 +
--     or a grey "listed"), under it one row per rank in the RANKS columns,
--     gaps and ranks not learned included (the same rows a family's view
--     draws); Other lists only kindless spells cast for mana and counts the
--     rest (T10c); a click opens the family, as a preview when it is not in
--     the list; + adds it.
-- The 2-s tick while shown re-renders when what the tables were drawn from
-- changed (the book, the list, the bonus-healing reading, the pool's max,
-- the pitch); else only the To OOM cells move, in place (3.5's split).
--------------------------------------------------------------------------------
local OVERVIEW_TOP = 32     -- the title row (20) and the 12-px section gap
local MINE_SEP_X = 384      -- My spells: the rule between suggested and highest
local LISTED_W = 60         -- the right end of a family header: + or "listed"
local STALE_TEXT = "Text read before combat - may be out of date"
local MINE_HINT = "Click a row to open that spell."
local MINE_HINT2 = "Whole book lists every family in your spellbook the same way, with + to add it."
local MINE_EMPTY = "Your list is empty - + Add on the left, or + beside a family in Whole book."

-- My spells: 524 of columns from x = 8 (the icon at 8, the name at 28), as
-- 3.5's table; "Per mana" fits a 50-px Arial Narrow column.
-- T78 (U9 / U10): "Casts" as in RANKS, and a sentence on every header.
local MINE_COLS = {
    { key = "spell",     x = 28,  w = 128, label = "Spell" },
    { key = "suggested", x = 158, w = 62,  label = "Suggested",
      tooltip = "The rank SpellTuner suggests." },
    { key = "value",     x = 220, w = 46,  label = "Value",    justify = "RIGHT",
      tooltip = "The suggested rank's average heal or damage; all of it for one over time." },
    { key = "permana",   x = 266, w = 58,  label = "Per mana", justify = "RIGHT",
      tooltip = "The suggested rank's healing or damage for each point of mana." },
    { key = "toOOM",     x = 324, w = 52,  label = "Casts",    justify = "RIGHT",
      tooltip = HEAD_TIPS.toOOM },
    { key = "highest",   x = 392, w = 50,  label = "Highest",
      tooltip = "Your highest known rank." },
    { key = "hvalue",    x = 442, w = 40,  label = "Value",    justify = "RIGHT",
      tooltip = "Your highest rank's average heal or damage." },
    { key = "hpermana",  x = 482, w = 50,  label = "Per mana", justify = "RIGHT",
      tooltip = "Your highest rank's healing or damage for each point of mana." },
}
-- Whole book: 3.5's RANKS columns; heals and damage share the value column.
local BOOK_HEADER = { [4] = "Value" }

local function OverviewMode()
    local ui = MD.db and MD.db.ui
    local m = (type(ui) == "table") and ui.overview or SpellsPane.overviewMode
    if m == "book" or m == "mine" then return m end
    return "mine"
end

-- A family's icon at the row's left (x = 8, 16x16 on a 1-px black edge),
-- built on first use on a pooled row; hidden on any row that is not a family.
local function RowIcon(row, icon)
    if not row.famIcon then
        row.famEdge = row:CreateTexture(nil, "ARTWORK")
        row.famEdge:SetSize(18, 18)
        row.famEdge:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.famEdge:SetColorTexture(0, 0, 0, 1)
        row.famIcon = row:CreateTexture(nil, "OVERLAY")
        row.famIcon:SetSize(16, 16)
        row.famIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.famIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if icon then
        row.famIcon:SetTexture(icon)
        row.famIcon:Show(); row.famEdge:Show()
    else
        row.famIcon:Hide(); row.famEdge:Hide()
    end
end

local function HideExtras(row)
    if row.famIcon then row.famIcon:Hide(); row.famEdge:Hide() end
    if row.plusBtn then row.plusBtn:Hide() end
    if row.listed then row.listed:Hide() end
end

-- A family header's right end: a 16x16 + (adds it), or a grey "listed".
local function PlusParts(row)
    if row.plusBtn then return end
    local b = UI.CreateButton(row, "+", "accent-hover", { 16, 16 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL)
    b:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    b:SetScript("OnClick", function()
        local r = row.data
        if r and r.kind == "family" then SpellsPane:AddFromBook(r.key) end
    end)
    b:HookScript("OnEnter", function(self) KitTip(self, "Add to my spells", "It gets its own row on the left.") end)
    b:HookScript("OnLeave", function() if UI.tooltip then UI.tooltip:Hide() end end)
    row.plusBtn = b
    local fs = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    fs:SetJustifyH("RIGHT")
    UI.Tint(fs, "text", "muted")
    fs:SetText("listed")
    row.listed = fs
end

-- The spanning cell at x, `font` the size it is drawn in.
local function WideAt(row, x, w, text, font)
    local wide = row.cells.wide
    if not wide then return end
    if font then wide:SetFontObject(font) end
    wide:ClearAllPoints()
    wide:SetPoint("LEFT", row, "LEFT", x, 0)
    wide:SetWidth(w)
    wide:SetText(text)
end

--------------------------------------------------------------------------------
-- Whole book's rows
--------------------------------------------------------------------------------
local function RenderBookRow(row, r, color)
    HideExtras(row)
    if r.kind == "rank" or r.kind == "gap" then
        if row.cells.wide then row.cells.wide:SetFontObject(UI.FONT_SMALL) end
        RenderRankRow(row, r, color)
        if r.noValue and r.kind == "rank" then
            -- a family with no value: Rank / Lvl / Mana / Cast / Tag only (3.5)
            local c = row.cells
            c.value:SetText(""); c.permana:SetText(""); c.persec:SetText(""); c.toOOM:SetText("")
            if row.SetBar then row:SetBar("permana", nil) end
        end
        return
    end
    for _, fs in pairs(row.cells) do fs:SetText("") end
    if row.SetBar then row:SetBar("permana", nil) end
    if r.kind == "section" then
        WideAt(row, 8, VIEW_W - 16, UI.Hex("accent") .. r.text .. RESET, UI.FONT)
    elseif r.kind == "family" then
        local rep = Rep(r.family)
        RowIcon(row, rep and rep.icon or nil)
        WideAt(row, 28, VIEW_W - 28 - LISTED_W, color .. Esc(r.family.name or r.key) .. RESET, UI.FONT)
        PlusParts(row)
        if r.listed then
            row.plusBtn:Hide(); row.listed:Show()
        else
            row.listed:Hide(); row.plusBtn:Show()
        end
    elseif r.kind == "note" then
        local x = r.indent and 28 or 8
        WideAt(row, x, VIEW_W - x - 8, UI.Hex(r.tone or "muted") .. r.text .. RESET, UI.FONT_SMALL)
    end
end

local function UpdateBookRow(row, r)
    if r.noValue then return end
    UpdateRankRow(row, r)
end

local function BookRowEnter(row, r)
    if not r then return end
    if r.kind == "rank" or r.kind == "gap" then return RankRowEnter(row, r) end
    if r.kind == "family" then
        KitTip(row, Esc(r.family.name or r.key),
            r.listed and "In your list." or "Not in your list - + adds it.",
            "Click to open it.")
    end
end

local function OverviewClick(_, r)
    if not r then return end
    if r.kind == "family" or r.kind == "rank" or r.kind == "gap" or r.kind == "mine" then
        local key = r.key or (r.family and (r.family.key or r.family.name))
        if key then SpellsPane:OpenFamily(key) end
    end
end

-- Other's rule (T10c): a kindless family is listed when it is cast for mana.
local function OtherListed(fam)
    local rep = Rep(fam)
    if not rep or rep.passive then return false end
    return rep.cost ~= nil and (rep.cost.amount ~= nil or rep.cost.percent ~= nil)
end

-- One family: its header, a stale note, then 3.5's rows (FamilyRows).
local function AddBookFamily(rows, fam, pool)
    local key = fam.key or fam.name
    rows[#rows + 1] = { kind = "family", family = fam, key = key, listed = MD.Tabs:Has(key) }
    local stale = false
    for _, e in ipairs(fam.ranks) do if e.stale then stale = true end end
    if stale then
        rows[#rows + 1] = { kind = "note", family = fam, text = STALE_TEXT, tone = "bad", indent = true }
    end
    for _, r in ipairs(FamilyRows(fam, pool)) do
        r.key = key
        if not fam.kind then r.noValue = true end
        rows[#rows + 1] = r
    end
end

local function BookRows(book, pool)
    local rows = {}
    local heals, damage, other, skipped = {}, {}, {}, 0
    for _, name in ipairs(book.order) do
        local fam = book.families[name]
        if fam.kind == "heal" then heals[#heals + 1] = fam
        elseif fam.kind == "damage" then damage[#damage + 1] = fam
        elseif OtherListed(fam) then other[#other + 1] = fam
        else skipped = skipped + 1 end
    end
    local function Section(title, list, count)
        if #list == 0 and (count or 0) == 0 then return end
        rows[#rows + 1] = { kind = "section", text = title }
        for _, fam in ipairs(list) do AddBookFamily(rows, fam, pool) end
    end
    Section("Heals", heals)
    Section("Damage", damage)
    Section("Other", other, skipped)
    if skipped > 0 then
        rows[#rows + 1] = { kind = "note",
            text = tostring(skipped) .. " passives and spells with no mana cost not listed - Export has them" }
    end
    return rows
end

--------------------------------------------------------------------------------
-- My spells' rows
--------------------------------------------------------------------------------
local function RenderMineRow(row, r, color)
    for _, fs in pairs(row.cells) do fs:SetText("") end
    local c = row.cells
    if r.stale then
        RowIcon(row, nil)
        local dis = UI.Hex("disabled")
        c.spell:SetText(dis .. Esc(r.key) .. RESET)
        WideAt(row, MINE_COLS[2].x, VIEW_W - MINE_COLS[2].x - 8, dis .. "not in your spellbook" .. RESET)
        return
    end
    WideAt(row, 8, 0, "")
    local fam = r.family
    local rep = Rep(fam)
    RowIcon(row, rep and rep.icon or nil)
    c.spell:SetText(color .. Esc(fam.name or r.key) .. RESET)
    local s, h = fam.suggested, fam.maxKnown
    local valued = fam.kind ~= nil
    if s then
        c.suggested:SetText(UI.Hex("accent") .. RankCell(s) .. RESET)
        if valued then
            c.value:SetText(color .. Num(s.value) .. RESET)
            c.permana:SetText(color .. Num(s.perMana, 2) .. RESET)
            c.toOOM:SetText(color .. CastsWord(r.fullCasts) .. RESET)
        end
    else
        c.suggested:SetText(UI.Hex("muted") .. "-" .. RESET)
    end
    if h then
        c.highest:SetText(color .. RankCell(h) .. RESET)
        if valued then
            c.hvalue:SetText(color .. Num(h.value) .. RESET)
            c.hpermana:SetText(color .. Num(h.perMana, 2) .. RESET)
        end
    end
end

local function UpdateMineRow(row, r)
    if r.stale or not r.suggestedEntry or not r.family.kind then return end
    r.fullCasts = MD.Book:CastsFor(r.suggestedEntry, SpellsPane.liveFull or FullPool(Pool()))
    row.cells.toOOM:SetText((r.color or "") .. CastsWord(r.fullCasts) .. RESET)
end

local function RenderMineRowKeep(row, r, color)
    r.color = color
    RenderMineRow(row, r, color)
end

local function MineRowEnter(row, r)
    if not r then return end
    if r.stale then
        KitTip(row, Esc(r.key), "Not in this character's spellbook.", "Click to open it.")
        return
    end
    local s = r.family.suggested
    if s and s.known ~= false and type(s.id) == "number" then
        GameTip(row, r.family, s)
    else
        KitTip(row, Esc(r.family.name or r.key), "Click to open it.")
    end
end

local function MineRows(book, pool)
    local rows = {}
    local full = FullPool(pool)
    for _, key in ipairs(MD.Tabs:Get(book)) do
        local fam = MD.Tabs:Resolve(key, book)
        if type(fam) == "table" then
            local s = fam.suggested
            rows[#rows + 1] = { kind = "mine", key = key, family = fam, suggestedEntry = s,
                fullCasts = s and MD.Book:CastsFor(s, full) or nil }
        else
            rows[#rows + 1] = { kind = "mine", key = key, stale = true, known = false }
        end
    end
    return rows
end

--------------------------------------------------------------------------------
-- The pane
--------------------------------------------------------------------------------
-- The two tables for the current pitch, built once per pitch (a font offset
-- changes the row height, which UI/Dashboard_Rows.lua fixes at creation).
local function OverviewTables(pane)
    local rowH, headH = Pitch(TABLE_ROW), Pitch(TABLE_HEAD)
    local k = rowH .. "/" .. headH
    pane.tables = pane.tables or {}
    local t = pane.tables[k]
    if not t then
        local content = pane.scroll.content
        local function Make(cols, header, wideFont, render, onUpdate, onEnter)
            local api = MD.DashboardParts.CreateTable(content, VIEW_W, {
                cols = cols, header = header,
                font = UI.FONT_NUM or UI.FONT, wideFont = wideFont,
                rowHeight = rowH, headerHeight = headH, headerRule = true,
                zebra = true, rowWidth = true, marker = "bar",
                headerFont = UI.FONT_SPECIAL, headerColor = "label", -- T78, as RANKS; T107: a token
                render = render, onUpdateCells = onUpdate,
                onEnter = onEnter, onLeave = RankRowLeave, onClick = OverviewClick,
            })
            api.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            api.frame:SetWidth(VIEW_W)
            api.frame:Hide()
            return api
        end
        t = {}
        t.mine = Make(MINE_COLS, nil, UI.FONT_SMALL, RenderMineRowKeep, UpdateMineRow, MineRowEnter)
        t.book = Make(RANK_COLS, BOOK_HEADER, UI.FONT, RenderBookRow, UpdateBookRow, BookRowEnter)
        -- My spells' rule between the suggested rank and the highest
        local sep = t.mine.frame:CreateTexture(nil, "BORDER")
        sep:SetWidth(1)
        sep:SetPoint("TOPLEFT", t.mine.frame, "TOPLEFT", MINE_SEP_X, -4)
        if UI.PALETTE and UI.PALETTE.line then UI.Tint(sep, "texture", "line") -- T107
        else sep:SetColorTexture(0.165, 0.165, 0.165, 1) end
        t.mine.sep = sep
        pane.tables[k] = t
    end
    for key, other in pairs(pane.tables) do
        if key ~= k then
            other.mine:Release(); other.mine.frame:Hide()
            other.book:Release(); other.book.frame:Hide()
        end
    end
    pane.mineTable, pane.bookTable = t.mine, t.book
    return t
end

-- F3 (docs/tasks/F3-whole-book-empty.md): the author's "Whole book is empty
-- when opened, fixed once start scrolling". RenderOverview grows the scroll
-- child while the scroll frame is on screen (My spells' few rows -> Whole
-- book's hundreds), and the client draws the child through the rect it last
-- took from it; until F3 nothing in the pane gave it the new one -- the only
-- call that did was the mouse wheel's SetVerticalScroll (UI/Style.lua's
-- VerticalScroll), which is why a scroll "fixed" it. So every render ends by
-- handing the frame its child again: UpdateScrollChildRect, then the offset
-- set anew (0 on a new table -- a mode change starts at its top -- else the
-- old one, clamped to the new range). No timer: the same frame, at once.
local function RefreshScrollChild(scroll, top)
    if not scroll then return end
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local offset = 0
    if not top and scroll.GetVerticalScroll then
        local now = scroll:GetVerticalScroll()
        offset = tonumber(now) or 0
    end
    local range = 0
    if scroll.GetVerticalScrollRange then
        local r = scroll:GetVerticalScrollRange()
        range = tonumber(r) or 0
    end
    if offset > range then offset = range end
    if offset < 0 then offset = 0 end
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(offset) end
end

-- What a full render was drawn from: the mode, the book's generation, the
-- bonus-healing reading, the pool's max, the pitch (SpellsPane:Signature)
-- and the list.
local function OverviewSignature(mode)
    local list = MD.Tabs and MD.Tabs:Get() or {}
    return SpellsPane:Signature("overview:" .. mode, false) .. "|" .. table.concat(list, ",")
end

function SpellsPane:RenderOverview()
    local pane = self.overview
    if not (pane and MD.Book and MD.Tabs) then return end
    local mode = OverviewMode()
    if pane.highlightMode then pane.highlightMode(mode) end
    local t = OverviewTables(pane)
    local book = MD.Book:Get()
    local pool = Pool()
    local active, idle = t.mine, t.book
    if mode == "book" then active, idle = t.book, t.mine end
    idle:Release(); idle.frame:Hide()

    local rows = (mode == "book") and BookRows(book, pool) or MineRows(book, pool)
    SpellsPane.headKind = nil -- T78: Whole book holds both kinds
    active.frame:Show()
    active:Render(rows)
    pane.lastRows = rows -- tools/spellsui.lua's own hook: the exact render order
    local newTable = pane.mode ~= mode -- F3: a mode change starts at the top
    pane.mode, pane.activeTable = mode, active
    local tableH = 4 + active.headerHeight + #rows * active.rowHeight
    active.frame:SetHeight(tableH)
    if t.mine.sep then t.mine.sep:SetHeight(tableH - 4) end

    local y = tableH + BLOCK_GAP
    if mode == "mine" then
        pane.hint:ClearAllPoints()
        pane.hint:SetPoint("TOPLEFT", pane.scroll.content, "TOPLEFT", 8, -y)
        pane.hint:SetText(#rows == 0 and MINE_EMPTY or MINE_HINT)
        pane.hint:Show()
        pane.hint2:Show()
        y = y + Pitch(34)
    else
        pane.hint:Hide()
        pane.hint2:Hide()
    end
    pane.footer:ClearAllPoints()
    pane.footer:SetPoint("TOPLEFT", pane.scroll.content, "TOPLEFT", 8, -y)
    y = y + 16
    pane.scroll:SetContentHeight(y)
    RefreshScrollChild(pane.scroll, newTable) -- F3

    pane.signature = OverviewSignature(mode)
    pane.lastRefresh = GetTime()
    pane.renderCount = (pane.renderCount or 0) + 1
    pane.refreshCount = (pane.refreshCount or 0) + 1 -- tools/spellsui.lua's own hook
end

-- The tick's in-place half: the To OOM cells, nothing released.
function SpellsPane:UpdateOverviewLive()
    local pane = self.overview
    if not (pane and pane.activeTable) then return end
    self.liveFull = FullPool(Pool())
    pane.activeTable:UpdateCells()
    self.liveFull = nil
    pane.lastRefresh = GetTime()
    pane.liveCount = (pane.liveCount or 0) + 1
    pane.refreshCount = (pane.refreshCount or 0) + 1
end

function SpellsPane:SetOverviewMode(mode)
    if mode ~= "mine" and mode ~= "book" then return end
    local ui = MD.db and MD.db.ui
    if type(ui) == "table" then ui.overview = mode end
    self.overviewMode = mode
    if self.overview and self.overview:IsVisible() then self:RenderOverview() end
end

-- + on a Whole book family: it joins the list (at the end), and Overview
-- stays where it is; the rail follows (ListChanged), and the header reads
-- "listed".
function SpellsPane:AddFromBook(key)
    if type(key) ~= "string" or not MD.Tabs:Add(key, nil) then return end
    if self.preview == key then self.preview = nil end
    self:ListChanged()
    if self.overview and self.overview:IsVisible() then self:RenderOverview() end
end

local function BuildOverview(host)
    local pane = CreateFrame("Frame", nil, host)
    pane:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    pane.spellsBook = true -- marks this pane for tools/spellsui.lua

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -3)
    title:SetJustifyH("LEFT")
    UI.Tint(title, "text", "accent") -- T107
    title:SetText("OVERVIEW")
    pane.title = title

    -- [Export] at the view's right edge (556), never the window's
    local exportBtn = UI.CreateButton(pane, "Export", "accent-hover", { 70, 20 })
    exportBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", VIEW_W - 70, 0)
    exportBtn:SetScript("OnClick", function()
        MD:ShowCopyPopup("SpellTuner spellbook", ExportText())
    end)
    pane.exportBtn = exportBtn

    local bookBtn = UI.CreateButton(pane, "Whole book", "accent-hover", { 88, 20 })
    bookBtn.id = "book"
    bookBtn:SetPoint("TOPRIGHT", exportBtn, "TOPLEFT", -8, 0)
    local mineBtn = UI.CreateButton(pane, "My spells", "accent-hover", { 84, 20 })
    mineBtn.id = "mine"
    mineBtn:SetPoint("TOPRIGHT", bookBtn, "TOPLEFT", 1, 0)
    pane.mineBtn, pane.bookBtn = mineBtn, bookBtn
    pane.highlightMode = UI.CreateButtonGroup({ mineBtn, bookBtn }, function(id)
        SpellsPane:SetOverviewMode(id)
    end)

    pane.scroll = UI.CreateScrollFrame(pane, -OVERVIEW_TOP, 4)
    local content = pane.scroll.content

    local hint = content:CreateFontString(nil, "OVERLAY", UI.FONT_SPECIAL or UI.FONT_SMALL)
    hint:SetJustifyH("LEFT")
    UI.Tint(hint, "text", "text2")
    pane.hint = hint
    local hint2 = content:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    hint2:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -4)
    hint2:SetWidth(VIEW_W - 16)
    hint2:SetJustifyH("LEFT")
    UI.Tint(hint2, "text", "muted")
    hint2:SetText(MINE_HINT2)
    pane.hint2 = hint2
    local footer = content:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    footer:SetJustifyH("LEFT")
    UI.Tint(footer, "text", "muted")
    footer:SetText(FOOTER_TEXT)
    pane.footer = footer

    -- every 2 s while shown (T10's rule): a full render when what the table
    -- was drawn from changed, else the To OOM cells in place (3.5's split);
    -- the master ticker runs at 0.5 s and this never fires while hidden
    MD:OnTick(function()
        if not pane:IsVisible() then return end
        local now = GetTime()
        if pane.lastRefresh and (now - pane.lastRefresh) < 2 then return end
        MD.Book:Get() -- a changed book fires BOOK_CHANGED here, and bumps bookGen
        if OverviewSignature(OverviewMode()) ~= pane.signature then
            SpellsPane:RenderOverview()
        else
            SpellsPane:UpdateOverviewLive()
        end
    end)
    return pane
end

--------------------------------------------------------------------------------
-- The list: rail rows from Spells/Tabs.lua (3.2, 3.3)
--------------------------------------------------------------------------------
-- T77 (P33, review U8; mockup M4): a row's tooltip under its name -- the
-- suggested rank among the known ones ("Suggested  Rank 1 of 2 known", what
-- the R1 tag is), its per mana, and the line a stale reading earns ("Read
-- before combat: ..."); the rail adds "Drag to reorder. Right-click for
-- more." itself. Label/value pairs in UI/Tip.lua's line model.
local function RailTip(fam)
    local lines = {}
    local s = fam.suggested
    if s and type(s.rank) == "number" then
        lines[#lines + 1] = { l = "Suggested", r = string.format("Rank %d of %d known", s.rank, KnownRanks(fam)),
            c = "label", rc = "text" }
    end
    if s and type(s.perMana) == "number" then
        lines[#lines + 1] = { l = "Per mana", r = Words.PerMana(s, "cell"), c = "label", rc = "text" }
    end
    if s and s.stale then
        lines[#lines + 1] = { l = "Read before combat: the spell text was hidden during the fight.",
            c = "muted", wrap = true }
    end
    return lines
end

-- The rail's rows, the footer and Undo line, the drop, the picker and the
-- group's definition are UI/SpellRail.lua's (T84, C5: shared with TBC's
-- Spells group): installed on SpellsPane with the book as the source, this
-- pane's row (its icon, the suggested rank's tag, RailTip) and the picker's
-- tip. SpellsPane:Views / RefreshRail / ListChanged / Remove / Undo /
-- RefreshFooter / CanDrop / Drop / RefreshPicker / OpenPicker / Group /
-- Attach and the fields nav / addBtn / undoText / undoBtn / picker are as
-- they were.
MD.SpellRail.Install(SpellsPane, {
    source = function() return MD.Book and MD.Book:Get() or nil end,
    row = function(fam, key)
        local rep = fam.maxKnown or (fam.ranks and fam.ranks[1])
        local rank = fam.suggested and fam.suggested.rank
        return { text = Esc(fam.name or key), icon = rep and rep.icon or nil,
            tag = (type(rank) == "number") and ("R" .. rank) or nil, tooltip = RailTip(fam) }
    end,
    pickerTip = "Tip: drag a spell from your spellbook onto the list.",
})

--------------------------------------------------------------------------------
-- Selection, the preview, /st spell
--------------------------------------------------------------------------------
local function ShowOnly(which)
    local s = SpellsPane
    if s.overview then if which == "overview" then s.overview:Show() else s.overview:Hide() end end
    if s.family then if which == "family" then s.family:Show() else s.family:Hide() end end
end

-- onShow for the group (UI/Dashboard_Forever.lua): Overview, a family's view,
-- or -- on Overview while a preview is asked for -- that family's view with
-- the banner, no rail row selected (it is not in the list).
function SpellsPane:Show(view)
    if not self.host then return end
    local key = FamilyKey(view)
    if key then
        self.preview = nil
        ShowOnly("family")
        self:RenderFamily(key, false)
        if MD.Tabs:IsNew(key) then
            MD.Tabs:MarkSeen(key)
            self:RefreshRail()
        end
        return
    end
    local pv = self.preview
    if pv and MD.Tabs:Has(pv) then pv = nil; self.preview = nil end
    if pv then
        ShowOnly("family")
        self:RenderFamily(pv, true)
        local rail = self.nav and self.nav:Rail("spells")
        if rail then rail:Select(nil) end
        return
    end
    ShowOnly("overview")
    self:RenderOverview() -- T39
end

-- A rail row clicked (after the nav selected it): the Overview row ends a
-- preview.
function SpellsPane:RailSelected(id)
    if id == "overview" and self.preview then
        self.preview = nil
        self:Show("overview")
    end
end

-- A family's view, or its preview when it is not in the list (3.6).
function SpellsPane:OpenFamily(key)
    if type(key) ~= "string" then return end
    if MD.Tabs:Has(key) then
        self.preview = nil
        return MD:SelectView("spells", VIEW_PREFIX .. key)
    end
    self.preview = key
    MD:SelectView("spells", "overview")
    -- refused (a practice session holds the screen): nothing left pending
    local nav = self.nav
    local g, v
    if nav then g, v = nav:Selected() end
    if not (nav and nav.frame:IsShown() and g == "spells" and v == "overview") then
        self.preview = nil
    end
end

function SpellsPane:AddFromPreview(key)
    self.preview = nil
    MD.Tabs:Add(key, nil)
    self:ListChanged()
    MD:SelectView("spells", VIEW_PREFIX .. key)
end

-- /st spell <name>: an exact name first, then a prefix; the player's list
-- before the rest of the book; case-insensitive.
function SpellsPane:Find(text)
    local want = (type(text) == "string" and text or ""):lower()
    if want == "" or not MD.Book then return nil end
    local book = MD.Book:Get()
    local listed = MD.Tabs:Get(book)
    local function Scan(list, exact)
        for _, key in ipairs(list) do
            local n = key:lower()
            if (exact and n == want) or (not exact and n:sub(1, #want) == want) then return key end
        end
        return nil
    end
    return Scan(listed, true) or Scan(book.order, true) or Scan(listed, false) or Scan(book.order, false)
end

function SpellsPane:Open(text)
    text = strtrim(type(text) == "string" and text or "")
    if text == "" then return MD:SelectView("spells") end
    local key = self:Find(text)
    if not key then
        MD:Print("spell: no spell in your spellbook starts with '" .. Esc(text) .. "'")
        return
    end
    return self:OpenFamily(key)
end

function MD:OpenSpell(text)
    return SpellsPane:Open(text)
end

--------------------------------------------------------------------------------
-- The font offset (4.2): the pitches grow with it, re-rendered at once
--------------------------------------------------------------------------------
function SpellsPane:FontsChanged()
    local nav = self.nav
    if not nav then return end
    self:RailFontsChanged() -- UI/SpellRail.lua: the rail's pitch, the picker
    if self.family then LayoutFamily(self.family) end
    local group, view = nav:Selected()
    if group == "spells" then self:Show(view) end
end

-- T77 (P33, review A31): the kit's FONTS_CHANGED, once the fonts are
-- re-sized (it wrapped UI.ApplyFonts before)
MD:RegisterCallback("FONTS_CHANGED", function() SpellsPane:FontsChanged() end)

-- T107: a style switch re-renders what is shown -- the rail's rows and the
-- view's rows are built from token codes at render (the kit's STYLE_CHANGED,
-- registered first, has already repainted every tinted region)
function SpellsPane:StyleChanged()
    local nav = self.nav
    if not nav then return end
    self:RefreshRail()
    local group, view = nav:Selected()
    if group == "spells" then self:Show(view) end
end
MD:RegisterCallback("STYLE_CHANGED", function() SpellsPane:StyleChanged() end)

--------------------------------------------------------------------------------
-- Wiring (UI/Dashboard_Forever.lua)
--------------------------------------------------------------------------------
-- onCreate for any Spells view: one frame holds them all (the kit shows it
-- for each of them), Overview and a family's view inside it.
function SpellsPane:Create(content)
    if self.host then return self.host end
    local host = CreateFrame("Frame", nil, content)
    host:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    host.spellsHost = true
    self.host = host
    self.overview = BuildOverview(host)
    self.family = BuildFamily(host)
    self.family:Hide()
    return host
end

-- A rescan that changed the book (Spells/Tabs.lua reconciled first: it
-- registered before this file loaded): the rail follows, and (T38) a
-- family's view re-renders on its next tick -- the book's generation is in
-- what the view was drawn from.
MD:RegisterCallback("BOOK_CHANGED", function()
    SpellsPane.bookGen = (SpellsPane.bookGen or 0) + 1
    SpellsPane:RefreshRail()
end)

