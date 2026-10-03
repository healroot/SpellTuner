-- UI/SpellTip.lua (T117: moved from UI/SpellTip_Forever.lua; T121: the one
-- tooltip block of both lines).
--
-- T9 (docs/tasks/T9-spell-tooltip.md, M2): the SpellTuner block on every
-- spell tooltip -- the spellbook, an action bar, a chat link -- through
-- TooltipDataProcessor (Client/API_Forever.lua's MD.API.OnSpellTooltip).
-- Forever only. Reaches the client only through MD.API and Book/Parse's own
-- output; the tooltip frame's own methods (AddLine, AddDoubleLine,
-- HookScript, Show, NumLines, IsShown) are the widget toolkit, not a client
-- call (CLAUDE.md).
--
-- T37 (docs/SPEC-forever-ui.md 5.1-5.4b, 5.6): the block redesigned. A
-- spacer, then a header in the accent, then at most four facts (Suggested
-- first, then per mana, per second, casts to OOM) plus the one warning (a
-- text read before combat, last); everything assumed or derived -- the
-- value and its range, the crit and its 1.5x, every known rank, a gap --
-- behind the detail key (db.spellTooltipDetail). Colours are passed as
-- arguments, so the tooltip's default gold is never inherited.
-- T121 (docs/tasks/T121-one-tooltip-block.md, docs/SPEC-one-ui.md 6, mockup
-- M5): both lines draw this block from their own MD.Book -- Forever's text
-- read book, TBC's model book (Spells/Book_Model.lua) -- with the family by
-- `entry.family`, the pool by MD.Book:Pool() ("~N now" only for a modelled
-- pool) and How from `entry.calc` and the bonus behind the detail key. The
-- three settings are registered here; the damage half (spellTooltipDamage)
-- and the class profile's tooltip cap gate the block on both lines.
-- SpellTip.OnSpell(tt, id, source) is exported: TBC's hook
-- (UI/SpellTooltip.lua) hands it the id; Forever's hooks are registered at
-- MD_READY only where the adapter has them.
local _, MD = ...
local Book = MD.Book
-- T67 (P23, review A13): the words -- per mana, per second, casts, the
-- value's parts, the crit range -- are Spells/Words.lua's, shared with the
-- Spells pane; this file picks the block's style (spec 5.x) and colours.
local Words = MD.Words

MD.SpellTip = MD.SpellTip or {}
local SpellTip = MD.SpellTip

-- T121: the block's settings, the same values both cores carry (a second
-- registration of the same value is allowed; the cores' copies go when each
-- core is next touched).
MD:RegisterDefaults({ spellTooltip = true, spellTooltipDamage = true, spellTooltipDetail = "SHIFT" })

-- Book's own global cooldown (Spells/Book.lua's GCD): an Other spell's
-- interval for casts to OOM, which Book:Rows never fills for a kindless
-- family.
local GCD = Words.GCD

--------------------------------------------------------------------------------
-- Colours: the theme's tokens (UI/Theme_Forever.lua's UI.TEXT, 4.1), else the
-- spec's own values, so the block never falls back to the tooltip's gold.
--------------------------------------------------------------------------------
local FALLBACK = {
    accent   = { 1, 0.486, 0.039, hex = "|cffff7c0a" },
    text     = { 1, 1, 1, hex = "|cffffffff" },
    text2    = { 0.702, 0.702, 0.702, hex = "|cffb3b3b3" },
    label    = { 0.702, 0.702, 0.702, hex = "|cffb3b3b3" }, -- T78: text2 and label are one grey
    muted    = { 0.478, 0.478, 0.478, hex = "|cff7a7a7a" },
    disabled = { 0.302, 0.302, 0.302, hex = "|cff4d4d4d" },
    mana     = { 0.302, 0.6, 1, hex = "|cff4d99ff" },
    bad      = { 0.878, 0.376, 0.353, hex = "|cffe0605a" },
}
-- T69 (P25): UI.TEXT is present on TBC too now (its gold among it), so the
-- block asks UI.THEMED: without the theme it keeps these values, as before.
local function C(name)
    local t = MD.UI and MD.UI.THEMED and MD.UI.TEXT
    return (t and t[name]) or FALLBACK[name]
end

-- One line of the block: {l, r, lr,lg,lb, rr,rg,rb}; r nil for a single line.
-- T76 (P32, review A21): each line is also UI/Tip.lua's line model -- the same
-- text and colours as named fields (l, r, c, rc) -- so MD.Tip:Render draws it
-- as it is; the positional fields stay one release for their readers.
local function Pair(l, r, lTok, rTok)
    local lc, rc = C(lTok or "label"), C(rTok or "text")
    return { l, r, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3],
             l = l, r = r, c = { lc[1], lc[2], lc[3] }, rc = { rc[1], rc[2], rc[3] } }
end
local function Single(l, tok)
    local c = C(tok or "text")
    return { l, nil, c[1], c[2], c[3], l = l, c = { c[1], c[2], c[3] } }
end

-- A number that is nil renders "-", never 0 (CLAUDE.md/this task's Rules).
local Num = Words.Num

local function Casts(n)
    return Words.Casts(n, "short")
end

--------------------------------------------------------------------------------
-- The detail key (5.6)
--------------------------------------------------------------------------------
-- db.spellTooltipDetail: the key that shows the detail lines, or ALWAYS /
-- NEVER. Each key: the adapter's reader, the word in the header's hint.
local KEYS = {
    SHIFT = { "IsShiftKeyDown", "Shift" },
    ALT = { "IsAltKeyDown", "Alt" },
    CTRL = { "IsControlKeyDown", "Ctrl" },
}
-- The dropdown's items (UI/Dashboard_Forever.lua, Settings -> General).
SpellTip.DETAIL_MODES = {
    { id = "SHIFT", text = "With Shift" },
    { id = "ALT", text = "With Alt" },
    { id = "CTRL", text = "With Ctrl" },
    { id = "ALWAYS", text = "Always" },
    { id = "NEVER", text = "Never" },
}

-- The mode in force: anything the setting does not name is Shift.
function SpellTip:DetailMode()
    local m = MD.db and MD.db.spellTooltipDetail
    if m == "ALWAYS" or m == "NEVER" or KEYS[m] then return m end
    return "SHIFT"
end

-- Whether the detail lines are shown now: the key's state through the
-- adapter, a plain true only.
function SpellTip:DetailShown()
    local m = SpellTip:DetailMode()
    if m == "ALWAYS" then return true end
    if m == "NEVER" then return false end
    local read = MD.API[KEYS[m][1]]
    if type(read) ~= "function" then return false end
    return read() == true
end

--------------------------------------------------------------------------------
-- The facts
--------------------------------------------------------------------------------

-- Per mana -- review R13: a Rage / Focus / Energy cost is no mana, and named
-- (Book's own word, one of three fixed ASCII words). Per second: a plain
-- number for a cast, the GCD or a hybrid; "over N s" when the interval is
-- the spell's own duration. Both Spells/Words.lua's "tip" style (5.1).
local function PerManaText(entry)
    return Words.PerMana(entry, "tip")
end

-- T121: a TBC heal's interval is its cast or the global cooldown (the
-- model's, intervalBy "cast"), never the HoT's own duration -- so its per
-- second is the plain number, where Words' "tip" would say "over 2 s" for a
-- HoT with no direct part. Fold into Spells/Words.lua's PerSec when that
-- file is next free (T120 owns it this wave).
local function PerSecText(entry)
    if entry.intervalBy == "cast" and entry.castKind ~= "channeled" and type(entry.perSec) == "number" then
        return Num(entry.perSec, 1)
    end
    return Words.PerSec(entry, nil, "tip")
end

-- The book's pool when it is below its max, else nil (5.1: at full "N now"
-- would only repeat the first number). T121: MD.Book:Pool() on both lines --
-- Forever's the clock's modelled pool, TBC's the pool the client reads.
local function NowPool()
    if not (Book and Book.Pool) then return nil end
    local ok, pool = pcall(Book.Pool, Book)
    if not ok or type(pool) ~= "table" then return nil end
    if type(pool.mana) ~= "number" or type(pool.max) ~= "number" then return nil end
    if pool.mana >= pool.max then return nil end
    return pool
end

-- Casts to OOM: from full (Book:CastsFor against Book:DefaultPool()), then
-- "N now" in the mana colour from the book's pool while it is below its max,
-- "~N now" when that pool is modelled (Forever). `counted` is what
-- Book:CastsFor counts (its cost and interval). T78 (P34, review U9; mockup
-- M5): "6 from full, ~5 now".
local function CastsText(full, counted)
    if full == nil then return "-" end
    if full == math.huge then return "inf" end
    local text = Casts(full) .. " from full"
    local pool = NowPool()
    if pool then
        local now = Book:CastsFor(counted, pool)
        if type(now) == "number" then
            text = text .. ", " .. C("mana").hex .. (pool.modelled == true and "~" or "") .. Casts(now) .. " now|r"
        end
    end
    return text
end

-- T121: casts to OOM from a full pool. TBC's entry.casts counts from the mana
-- the player has now (RankMath's row); the block's first number is from
-- full on both lines, so it is counted here; the entry's own count when the
-- book cannot.
local function CastsFromFull(entry)
    local okPool, pool = pcall(Book.DefaultPool, Book)
    if okPool and type(pool) == "table" then
        local n = Book:CastsFor(entry, pool)
        if n ~= nil then return n end
    end
    return entry.casts
end

-- T121: a cost in another power -- Forever's book names it (cost.power a
-- word, "Rage"); TBC's book keeps the mana power type there (0).
local function OtherPowerCost(cost)
    return type(cost) == "table" and cost.power ~= nil and cost.power ~= 0
end

-- A mana cost Book priced (not free, not Rage, not a percent it could not
-- turn into mana).
local function HasManaCost(entry)
    local cost = entry.cost
    return type(cost) == "table" and not OtherPowerCost(cost) and type(cost.amount) == "number" and cost.amount > 0
end

-- The known rank that dominates `entry`: Book's own entry.dominatedBy
-- (Spells/RankRules.lua's rule, T67 -- this file no longer re-runs it), a
-- spell id looked up among the family's ranks.
local function Dominator(family, entry)
    local id = entry.dominatedBy
    if id == nil then return nil end
    for _, e in ipairs(family.ranks) do
        if e.id == id then return e end
    end
    return nil
end

-- How much more (or less) the suggested rank heals per mana than this one,
-- as the block says it (T78, mockup M5): "+2% per mana", "-5% per mana",
-- "same per mana"; nil when either number is missing.
local function PerManaDiff(s, entry)
    if type(s.perMana) ~= "number" or type(entry.perMana) ~= "number" or entry.perMana <= 0 then
        return nil
    end
    local pct = math.floor((s.perMana / entry.perMana - 1) * 100 + 0.5)
    if pct == 0 then return "same per mana" end
    return string.format("%+d%% per mana", pct)
end

-- The first fact: which rank, never "press" (5.1). T78 (P34, review U9;
-- mockup M5): the suggested rank against this one ("Rank 1 (+2% per mana)"),
-- and the author's word for a dominated rank, "Beaten by".
local function SuggestedLine(family, entry)
    if entry.suggested == true then
        return Pair("Suggested", "this rank", "label", "accent")
    end
    if entry.dominated then
        local by = Dominator(family, entry)
        if by and by.rank then return Pair("Beaten by", "Rank " .. tostring(by.rank), "label", "accent") end
    end
    local s = family.suggested
    if s and s.rank then
        local text = "Rank " .. tostring(s.rank)
        local diff = PerManaDiff(s, entry)
        if diff then text = text .. " (" .. diff .. ")" end
        return Pair("Suggested", text, "label", "accent")
    end
    return nil
end

--------------------------------------------------------------------------------
-- The detail lines
--------------------------------------------------------------------------------

-- The value by shape (5.2-5.4): Spells/Words.lua's "tip" parts, each a pair
-- in the block's colours. Answers whether a crit range was given, for the one
-- multiplier line.
local function ValueLines(out, entry, kind)
    local parts, crit = Words.Value(entry, kind, "tip")
    for _, p in ipairs(parts) do out[#out + 1] = Pair(p[1], p[2]) end
    return crit
end

-- T121: the crit multiplier a model entry's value carries (TBC's book keeps
-- no field for it): the value with crits over the average hit, the crit
-- chance taken out -- 1.5, or Vengeance's 2.0 on a Balance druid's damage.
-- Rounded to two places; 1.5 when it cannot be read or lands outside what a
-- crit can be.
local function CritMult(e)
    local avg = (e.min + e.max) / 2
    local crit = e.crit
    if type(crit) ~= "number" or crit <= 0 or avg <= 0 or type(e.value) ~= "number" then return Words.CRIT_MULT end
    local m = 1 + ((e.value - (e.over or 0)) / avg - 1) / crit
    if m ~= m or m < 1.4 or m > 3 then return Words.CRIT_MULT end
    return math.floor(m * 100 + 0.5) / 100
end

-- T121 (mockup M5, "TBC after, Shift held"): a model entry's value (TBC's
-- book: no text was parsed) -- Heals / Hits min - max, Crit at its multiplier
-- with the crit chance, the part over time and the total. Fold into
-- Spells/Words.lua's Value when it is free.
local function ModelValueLines(out, entry, kind)
    local label = (kind == "damage") and "Hits" or "Heals"
    local hasRange = type(entry.min) == "number" and type(entry.max) == "number"
    if hasRange then
        out[#out + 1] = Pair(label, Num(entry.min) .. " - " .. Num(entry.max))
        local m = CritMult(entry)
        local text = Num(entry.min * m) .. " - " .. Num(entry.max * m)
        if type(entry.crit) == "number" then
            text = text .. "  " .. Num(entry.crit * 100) .. "%"
            if m > Words.CRIT_MULT + 0.01 then text = text .. string.format("  (x%.1f)", m) end
        else
            text = text .. "  x" .. Num(Words.CRIT_MULT, 1) .. " assumed"
        end
        out[#out + 1] = Pair("Crit", text)
    end
    if type(entry.over) == "number" then
        local over = Num(entry.over)
        if type(entry.dur) == "number" then over = over .. " over " .. Num(entry.dur) .. " s" end
        out[#out + 1] = Pair(hasRange and "Over time" or label, over)
    end
    if type(entry.value) == "number" and type(entry.over) == "number"
        and (hasRange or math.abs(entry.value - entry.over) > 0.5) then
        out[#out + 1] = Pair("Total", Num(entry.value))
    end
end

-- T121 (mockup M5): how the number was made -- the entry's calc, the first
-- line on "How", the rest under it as they are (indented, wrapped), then the
-- +healing (+damage) share when it was measured or estimated (a model bonus's
-- factors are already in calc).
local function HowLines(out, entry, kind)
    local calc = entry.calc
    if type(calc) ~= "table" or type(calc[1]) ~= "string" then return end
    out[#out + 1] = Pair("How", calc[1], "label", "text2")
    for i = 2, #calc do
        if type(calc[i]) == "string" then
            local line = Single("  " .. calc[i], "muted")
            line.wrap = true
            out[#out + 1] = line
        end
    end
    local b = entry.bonus
    if type(b) == "table" and (b.from == "measured" or b.from == "estimated") then
        local words = Words.Bonus(entry, "how", kind)
        if words then
            local line = Single("  " .. words, "muted")
            line.wrap = true
            out[#out + 1] = line
        end
    end
end

-- T121 (mockup M5): the measured share of the heal that lands, behind the
-- key (TBC's book; Forever has no combat log): "3035  25% measured".
local function AfterOverhealLine(out, entry)
    local a = entry.afterOverheal
    if type(a) ~= "table" or type(a.value) ~= "number" then return end
    local text = Num(a.value)
    if type(a.frac) == "number" then
        text = text .. "  " .. Num(a.frac * 100) .. "% " .. (a.scope == "family" and "family average" or "measured")
    end
    out[#out + 1] = Pair("After overheal", text)
end

-- T95 (docs/SPEC-next.md 4.2 P1): what the text and the tooltip line say
-- about reach and pace -- whom it reaches (an upper bound, in words: the
-- numbers above are one target's), the cooldown, the per-target lockout and
-- a health condition. Each only when the book read one.
local function ReachLines(out, entry)
    local reach = Words.ReachDetail(entry)
    if reach then out[#out + 1] = Pair("Reaches", reach) end
    if type(entry.cooldown) == "number" then
        out[#out + 1] = Pair("Cooldown", Words.Seconds(entry.cooldown))
    end
    if type(entry.lockout) == "number" then
        out[#out + 1] = Pair("Lockout", Words.Seconds(entry.lockout) .. " per target")
    end
    local below = type(entry.reach) == "table" and entry.reach.belowPct
    if type(below) == "number" then
        out[#out + 1] = Pair("Only", "on a target below " .. Num(below) .. "% health")
    end
end

-- T121: at most this many known ranks are listed one per line; a family
-- with more (TBC's Healing Touch has 12) gets the one comparison line M5
-- draws, "vs Rank N".
local RANK_ROWS_MAX = 4

-- T121 (mockup M5): "vs Rank 11  +1% per mana, +3% per sec" -- the highest
-- known rank against the next one down, any other rank against the highest
-- (Book:Compare's percentages). Fold into Spells/Words.lua when it is free.
local function VsLine(out, rows, entry)
    local top = rows[#rows]
    local other
    if entry == top then
        other = rows[#rows - 1]
    else
        other = top
    end
    if not other or not other.rank then return end
    local cmp = Book:Compare(entry, other)
    if type(cmp) ~= "table" or (cmp.perMana == nil and cmp.perSec == nil) then return end
    out[#out + 1] = Pair("vs Rank " .. tostring(other.rank),
        Words.Signed(cmp.perMana) .. " per mana, " .. Words.Signed(cmp.perSec) .. " per sec")
end

-- Every known rank with a value, this one marked, when there are two or more
-- to compare: value, per mana, casts to OOM from full. T121: more than
-- RANK_ROWS_MAX of them give the one "vs Rank N" line instead.
local function RankLines(out, family, entry)
    local rows = {}
    for _, e in ipairs(family.ranks) do
        if e.known and e.rank and e.value ~= nil then rows[#rows + 1] = e end
    end
    if #rows < 2 then return end
    if #rows > RANK_ROWS_MAX then return VsLine(out, rows, entry) end
    for _, e in ipairs(rows) do
        local right = Num(e.value) .. "   " .. Num(e.perMana, 2) .. " per mana   " .. Casts(e.casts)
        if e == entry then
            out[#out + 1] = Pair("Rank " .. tostring(e.rank) .. " (this)", right, "label", "text")
        else
            out[#out + 1] = Pair("Rank " .. tostring(e.rank), right, "label", "text2")
        end
    end
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

-- The header: "SpellTuner" in the accent; on the right the rank ("Rank N of
-- M", M = this family's known ranks; "Rank N" outside a family), "- macro"
-- when the id came from a macro (5.5), and the detail key's name in the
-- muted colour when there are detail lines to show (T78, review U7: it tells
-- you something, so it is no longer the disabled grey).
local function Header(entry, family, source, hasDetail)
    local right
    if entry.rank then
        if family then
            local knownCount = 0
            for _, e in ipairs(family.ranks) do
                if e.known then knownCount = knownCount + 1 end
            end
            right = "Rank " .. entry.rank .. " of " .. knownCount
        else
            right = "Rank " .. entry.rank
        end
    end
    if source == "macro" then right = right and (right .. " - macro") or "macro" end
    local mode = SpellTip:DetailMode()
    if hasDetail and KEYS[mode] then
        local hint = C("muted").hex .. KEYS[mode][2] .. "|r"
        right = right and (right .. "  " .. hint) or hint
    end
    if right == nil then return Single("SpellTuner", "accent") end
    return Pair("SpellTuner", right, "accent", "text")
end

-- 5.4b: a spell whose text carries no heal and no damage -- the header and
-- casts to OOM, nothing else, no hint; nil for one with no mana cost.
local function OtherLines(entry, family, source)
    if not HasManaCost(entry) then return nil end
    -- T95: never under the spell's cooldown (Book's IntervalFor, no part).
    local counted = { cost = entry.cost, interval = (Book.IntervalFor and Book.IntervalFor(entry, nil))
        or math.max(entry.cast or 0, GCD) }
    local full = Book:CastsFor(counted, Book:DefaultPool())
    return {
        Header(entry, family, source, false),
        Pair("Casts to OOM", CastsText(full, counted)),
    }
end

-- Lines for one spell id: a list of {l, r, lr,lg,lb, rr,rg,rb} (r nil for a
-- single line), or nil for no block. The plain block always; the detail
-- lines after it when `detail` is true. `source` "macro" marks the header.
-- A spell in the player's book whose family has a kind; a book spell with no
-- kind (5.4b); else Book:ReadSpell(id) when THAT has a value; else nil.
-- T28 / T67 (P23, review A13): the second return is the outcome, for
-- /st tooltip why: "block", "not in book" (an id the book does not list
-- and Book:ReadSpell cannot value) or "no value" (a book spell with no
-- amount to show and no mana cost), "no id" for anything but a number. It
-- was a field (SpellTip.lastOutcome) until T67, which any caller -- the
-- Spells pane's rank-row hover -- overwrote; a return reaches only the
-- caller that asked.
function SpellTip:Lines(id, detail, source)
    if type(id) ~= "number" then
        return nil, "no id"
    end

    local book = Book:Get()
    local entry = book.spells[id]
    local inBook = entry ~= nil
    -- T121: the family by the entry's key (TBC's book keys families by
    -- SpellData's id, not by the spell's name)
    local family = entry and book.families[entry.family or entry.name]

    if family and not family.kind then
        local other = OtherLines(entry, family, source)
        return other, other and "block" or "no value"
    end
    if not family then
        entry = Book:ReadSpell(id)
    end
    -- T121: a heal with no value of its own but a derivation (TBC's
    -- Swiftmend: the two Eats lines) -- the header and its calc lines, on the
    -- plain block, as Tip:Spell drew them
    if entry and entry.value == nil and family and type(entry.calc) == "table" and #entry.calc > 0 then
        local lines = { Header(entry, family, source, false) }
        for _, s in ipairs(entry.calc) do
            if type(s) == "string" then lines[#lines + 1] = Single(s, "text2") end
        end
        return lines, "block", family.kind
    end
    if not entry or entry.value == nil then
        return nil, inBook and "no value" or "not in book"
    end

    -- T110 (docs/SPEC-next.md 4.2 P6): an either-or spell (Holy Shock, Holy
    -- Nova) shows the half the player's role casts it for -- the role is
    -- Spells/Tabs.lua's (the book's talent spells, else the list's kind) --
    -- and names the other half behind the detail key. A heal role, no role
    -- or any other spell: the block as it was.
    local role = MD.Tabs and MD.Tabs.Role and MD.Tabs:Role(book)
    if role == "damage" then
        if family then
            local view = Book:Half(family, role)
            if view ~= family then
                for _, v in ipairs(view.ranks) do
                    if v.of == entry then entry = v break end
                end
                family = view
            end
        else
            entry = Book:HalfOf(entry, role)
        end
    end

    local kind = family and family.kind or entry.kind

    -- the detail lines, built first: the header's hint says whether any exist.
    -- T121 (mockup M5): the value (Forever's parsed text; TBC's model entry),
    -- After overheal, the ranks, the reach, the other half, then How.
    local more = {}
    if type(entry.parsed) == "table" then
        local crit = ValueLines(more, entry, kind)
        if crit then
            -- "assumed", once, and only here (5.1)
            more[#more + 1] = Pair("Crit multiplier", Words.CritNote(), "label", "muted")
        end
    else
        ModelValueLines(more, entry, kind)
    end
    AfterOverhealLine(more, entry)
    if family then
        RankLines(more, family, entry)
        if family.gaps and #family.gaps > 0 then
            more[#more + 1] = Pair("Not in your book", "Rank " .. table.concat(family.gaps, ", "), "muted", "muted")
        end
    end
    ReachLines(more, entry) -- T95
    local otherLabel, otherText = Words.OtherHalf(entry) -- T110
    if otherLabel then more[#more + 1] = Pair(otherLabel, otherText) end
    local how = {}
    HowLines(how, entry, kind)
    if #how > 0 then
        if #more > 0 then more[#more + 1] = Single(" ") end
        for _, line in ipairs(how) do more[#more + 1] = line end
    end
    local hasDetail = #more > 0
    if hasDetail then table.insert(more, 1, Single(" ")) end

    local lines = { Header(entry, family, source, hasDetail) }
    if family then
        local s = SuggestedLine(family, entry)
        if s then lines[#lines + 1] = s end
    end
    lines[#lines + 1] = Pair("Per mana", PerManaText(entry))
    lines[#lines + 1] = Pair("Per sec", PerSecText(entry)) -- T78: the table's word
    -- casts to OOM: a family row's number only (a ReadSpell entry never has
    -- one, 5.4), and only for a mana cost (a Rage spell never runs dry)
    if family and not OtherPowerCost(entry.cost) then
        lines[#lines + 1] = Pair("Casts to OOM", CastsText(CastsFromFull(entry), entry))
    end
    -- the one warning: last in the plain block, never behind the key
    if entry.stale then
        lines[#lines + 1] = Single("Text read before combat", "bad")
    end

    if detail then
        for _, line in ipairs(more) do lines[#lines + 1] = line end
    end
    -- T121: the third return is the block's kind ("heal" / "damage" / nil),
    -- for the damage setting the hooks read
    return lines, "block", kind
end

-- Writes Lines' result into a tooltip, colours passed as arguments.
-- T76 (P32, review A21): it also takes UI/Tip.lua's line model -- a line with
-- no positional text ({ l, r, c, rc, wrap }, colours as arrays or token
-- names) goes through MD.Tip:Render; the positional arrays are read as
-- before, for one release.
function SpellTip:Render(tt, lines)
    for _, line in ipairs(lines or {}) do
        if line[1] == nil and (line.l ~= nil or line.r ~= nil) and MD.Tip and MD.Tip.Render then
            MD.Tip:Render(tt, { line })
        elseif line[2] ~= nil then
            tt:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8])
        else
            -- T121: a How line under the first wraps (line.wrap)
            tt:AddLine(line[1], line[3], line[4], line[5], line.wrap == true or nil)
        end
    end
end

--------------------------------------------------------------------------------
-- The hook
--------------------------------------------------------------------------------

-- Tooltips that carry a block, for the detail key's refresh (weak: a
-- tooltip frame is never collected, but nothing here should hold one).
local withBlock = setmetatable({}, { __mode = "k" })

-- One block per showing: the id is remembered on the tooltip frame itself
-- until OnTooltipCleared, hooked once per frame (an action button re-sets its
-- tooltip on a timer, and the callback can run more than once for one
-- showing -- Facts).
-- T28: the guard is shared by every path (the Spell and Macro post-calls and
-- the SetAction hook all hand their id here) and holds whatever the id: once
-- a showing has its block, a second path resolving another id (a macro's
-- post-call naming rank 1, its slot rank 2) adds nothing. _spellTipId is set
-- only when a block was added, so an id that gave none leaves the next path
-- its turn. Answers `done, outcome` for the adapter's chain and
-- /st tooltip why: done when a block is on the tooltip or the block is off.
-- T37 (5.6): the guard is keyed by (id, detail). The detail key's refresh
-- (MD.API.RefreshTooltip) clears the tooltip and runs the post-calls again
-- -- whether OnTooltipCleared fires on the way is UNVERIFIED on Forever -- so
-- the same showing may rebuild its block once the block is no longer on the
-- tooltip (fewer lines than it ended at): a post-call run again without a
-- clear never adds a second block, whatever the detail. Without a line count
-- the key decides: a changed detail rebuilds. `source`
-- is "macro" from the macro paths (5.5), nil from the Spell post-call.
-- T121: exported as SpellTip.OnSpell (TBC's UI/SpellTooltip.lua hands it the
-- id); the class profile's tooltip cap (T99's rule, now on both lines) and
-- db.spellTooltipDamage (a damage family's block) gate it here, not in
-- Lines, so the Spells pane's rank-row hover keeps its block.
local function OnSpell(tt, id, source)
    if not tt or type(id) ~= "number" then return false, "no id" end
    if MD.db and MD.db.spellTooltip == false then return true, "off" end
    local profile = MD.ClassProfile
    if not (profile and profile.Can and profile:Can("tooltip")) then return true, "off" end

    if not tt._spellTipHooked and tt.HookScript then
        tt._spellTipHooked = true
        tt:HookScript("OnTooltipCleared", function(self) self._spellTipId = nil end)
    end
    local detail = SpellTip:DetailShown()
    if tt._spellTipId ~= nil then
        -- without the clear hook the guard cannot reset, so it holds only
        -- for the id it was set for (the pre-T28 rule)
        if tt._spellTipHooked or tt._spellTipId == id then
            local stillOn
            if tt.NumLines and type(tt._spellTipEnd) == "number" then
                stillOn = tt:NumLines() >= tt._spellTipEnd
            else
                stillOn = (tt._spellTipDetail == detail)
            end
            if stillOn then return true, "already shown" end
        end
    end

    -- The builder never raises into the game's tooltip.
    local ok, lines, outcome, kind = pcall(SpellTip.Lines, SpellTip, id, detail, source)
    if not ok then
        MD:Debug("other", "spell tooltip for %s failed: %s", tostring(id), tostring(lines))
        return false, "error"
    end
    if type(lines) ~= "table" then return false, outcome or "no value" end
    if kind == "damage" and MD.db and MD.db.spellTooltipDamage == false then return true, "off" end

    tt._spellTipId = id
    tt._spellTipDetail = detail
    -- 5.1: a spacer first (ElvUI's convention for its own blocks), so the
    -- block does not read as part of the game's description.
    tt:AddLine(" ")
    SpellTip:Render(tt, lines)
    if tt.NumLines then tt._spellTipEnd = tt:NumLines() end
    withBlock[tt] = true
    if tt.Show then tt:Show() end
    return true, "block"
end
SpellTip.OnSpell = OnSpell

-- T37 (5.6): the detail key pressed or released while a tooltip carries a
-- block refreshes that tooltip through the adapter, so the detail lines come
-- and go without moving the mouse. Only the key the setting names, and only
-- for a tooltip on screen with a block on it.
local function OnModifier(key)
    local mode = SpellTip:DetailMode()
    if not KEYS[mode] then return end
    if MD.API.IsSecret(key) or type(key) ~= "string" or not key:find(mode, 1, true) then return end
    local list = {}
    for tt in pairs(withBlock) do list[#list + 1] = tt end
    for _, tt in ipairs(list) do
        if tt._spellTipId ~= nil and (not tt.IsShown or tt:IsShown()) then
            MD.API.RefreshTooltip(tt)
        end
    end
end

-- T28: /st tooltip why -- one line: whether each macro path is registered,
-- then what the last macro hover did (MD.API.LastMacroHover: the path that
-- fired, each step's answer and what Lines said about each id). Every piece
-- is the adapter's own ASCII strings.
function SpellTip:Why()
    local hooks = MD.API.tooltipHooks or {}
    local head = "tooltip why: macro post-call " .. tostring(hooks.macro or "not registered")
        .. ", SetAction hook " .. tostring(hooks.action or "not registered")
    if MD.db and MD.db.spellTooltip == false then head = head .. " (block off: /st tooltip)" end
    local rec = MD.API.LastMacroHover and MD.API.LastMacroHover()
    if type(rec) ~= "table" then
        return head .. "; last macro hover: path none"
    end
    local line = head .. "; last macro hover: path " .. table.concat(rec.path, ", ")
    if #rec.steps > 0 then line = line .. "; " .. table.concat(rec.steps, "; ") end
    return line
end

-- T121: registered only where the adapter has the hooks (the presence of an
-- adapter function, never the client's name -- apicheck rule 10). TBC's
-- adapter has none: its hook is UI/SpellTooltip.lua, which calls OnSpell and
-- re-runs the owner's OnEnter for the detail key itself.
MD:RegisterCallback("MD_READY", function()
    if not MD.API.OnSpellTooltip then return end
    MD.API.OnSpellTooltip(OnSpell)
    -- T25: a macro's tooltip gets the block of the spell it casts.
    if MD.API.OnMacroTooltip then MD.API.OnMacroTooltip(OnSpell) end
    -- T28: and so does an action button's, from the slot SetAction is handed.
    if MD.API.OnActionTooltip then MD.API.OnActionTooltip(OnSpell) end
    -- T37: the detail key's refresh.
    if MD.API.RefreshTooltip then MD:On("MODIFIER_STATE_CHANGED", OnModifier) end
end)
