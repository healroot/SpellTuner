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
local _, MD = ...
local Book = MD.Book
-- T67 (P23, review A13): the words -- per mana, per second, casts, the
-- value's parts, the crit range -- are Spells/Words.lua's, shared with the
-- Spells pane; this file picks the block's style (spec 5.x) and colours.
local Words = MD.Words

MD.SpellTip = MD.SpellTip or {}
local SpellTip = MD.SpellTip

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
    label    = { 0.616, 0.616, 0.616, hex = "|cff9d9d9d" },
    muted    = { 0.478, 0.478, 0.478, hex = "|cff7a7a7a" },
    disabled = { 0.302, 0.302, 0.302, hex = "|cff4d4d4d" },
    mana     = { 0.302, 0.6, 1, hex = "|cff4d99ff" },
    bad      = { 0.878, 0.376, 0.353, hex = "|cffe0605a" },
}
local function C(name)
    local t = MD.UI and MD.UI.TEXT
    return (t and t[name]) or FALLBACK[name]
end

-- One line of the block: {l, r, lr,lg,lb, rr,rg,rb}; r nil for a single line.
local function Pair(l, r, lTok, rTok)
    local lc, rc = C(lTok or "label"), C(rTok or "text")
    return { l, r, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3] }
end
local function Single(l, tok)
    local c = C(tok)
    return { l, nil, c[1], c[2], c[3] }
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

local function PerSecText(entry)
    return Words.PerSec(entry, nil, "tip")
end

-- The clock's modelled pool when it is below its max, else nil (5.1: at full
-- "~N now" would only repeat the first number).
local function PoolBelowMax()
    if not (MD.Clock and MD.Clock.Pool) then return nil end
    local ok, pool = pcall(MD.Clock.Pool, MD.Clock)
    if not ok or type(pool) ~= "table" then return nil end
    if type(pool.mana) ~= "number" or type(pool.max) ~= "number" then return nil end
    if pool.mana >= pool.max then return nil end
    return pool
end

-- Casts to OOM: from full (Book:Rows' count against Book:DefaultPool()), then
-- "~N now" in the mana colour from the clock's modelled pool while it is
-- below its max. `counted` is what Book:CastsFor counts (its cost and
-- interval).
local function CastsText(full, counted)
    if full == nil then return "-" end
    if full == math.huge then return "inf" end
    local text = Casts(full) .. " full"
    local pool = PoolBelowMax()
    if pool then
        local now = Book:CastsFor(counted, pool)
        if type(now) == "number" then
            text = text .. ", " .. C("mana").hex .. "~" .. Casts(now) .. " now|r"
        end
    end
    return text
end

-- A mana cost Book priced (not free, not Rage, not a percent it could not
-- turn into mana).
local function HasManaCost(entry)
    local cost = entry.cost
    return type(cost) == "table" and cost.power == nil and type(cost.amount) == "number" and cost.amount > 0
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

-- The first fact: which rank, never "press" (5.1).
local function SuggestedLine(family, entry)
    if entry.suggested == true then
        return Pair("Suggested", "this rank", "label", "accent")
    end
    if entry.dominated then
        local by = Dominator(family, entry)
        if by and by.rank then return Pair("Dominated by", "Rank " .. tostring(by.rank), "label", "accent") end
    end
    local s = family.suggested
    if s and s.rank then
        local text = "Rank " .. tostring(s.rank)
        if s.perMana then text = text .. " (" .. Num(s.perMana, 2) .. " per mana)" end
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

-- Every known rank with a value, this one marked, when there are two or more
-- to compare: value, per mana, casts to OOM from full.
local function RankLines(out, family, entry)
    local rows = {}
    for _, e in ipairs(family.ranks) do
        if e.known and e.rank and e.value ~= nil then rows[#rows + 1] = e end
    end
    if #rows < 2 then return end
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
-- disabled colour when there are detail lines to show.
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
        local hint = C("disabled").hex .. KEYS[mode][2] .. "|r"
        right = right and (right .. "  " .. hint) or hint
    end
    if right == nil then return Single("SpellTuner", "accent") end
    return Pair("SpellTuner", right, "accent", "text")
end

-- 5.4b: a spell whose text carries no heal and no damage -- the header and
-- casts to OOM, nothing else, no hint; nil for one with no mana cost.
local function OtherLines(entry, family, source)
    if not HasManaCost(entry) then return nil end
    local counted = { cost = entry.cost, interval = math.max(entry.cast or 0, GCD) }
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
    local family = entry and book.families[entry.name]

    if family and not family.kind then
        local other = OtherLines(entry, family, source)
        return other, other and "block" or "no value"
    end
    if not family then
        entry = Book:ReadSpell(id)
    end
    if not entry or entry.value == nil then
        return nil, inBook and "no value" or "not in book"
    end

    local kind = family and family.kind or entry.kind

    -- the detail lines, built first: the header's hint says whether any exist
    local more = {}
    local crit = ValueLines(more, entry, kind)
    if crit then
        -- "assumed", once, and only here (5.1)
        more[#more + 1] = Pair("Crit multiplier", Words.CritNote(), "label", "muted")
    end
    if family then
        RankLines(more, family, entry)
        if family.gaps and #family.gaps > 0 then
            more[#more + 1] = Pair("Not in your book", "Rank " .. table.concat(family.gaps, ", "), "muted", "muted")
        end
    end

    local lines = { Header(entry, family, source, #more > 0) }
    if family then
        local s = SuggestedLine(family, entry)
        if s then lines[#lines + 1] = s end
    end
    lines[#lines + 1] = Pair("Per mana", PerManaText(entry))
    lines[#lines + 1] = Pair("Per second", PerSecText(entry))
    -- casts to OOM: a family row's number only (a ReadSpell entry never has
    -- one, 5.4), and only for a mana cost (a Rage spell never runs dry)
    if family and (entry.cost == nil or entry.cost.power == nil) then
        lines[#lines + 1] = Pair("Casts to OOM", CastsText(entry.casts, entry))
    end
    -- the one warning: last in the plain block, never behind the key
    if entry.stale then
        lines[#lines + 1] = Single("Text read before combat", "bad")
    end

    if detail then
        for _, line in ipairs(more) do lines[#lines + 1] = line end
    end
    return lines, "block"
end

-- Writes Lines' result into a tooltip, colours passed as arguments.
function SpellTip:Render(tt, lines)
    for _, line in ipairs(lines or {}) do
        if line[2] ~= nil then
            tt:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8])
        else
            tt:AddLine(line[1], line[3], line[4], line[5])
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
local function OnSpell(tt, id, source)
    if not tt or type(id) ~= "number" then return false, "no id" end
    if MD.db and MD.db.spellTooltip == false then return true, "off" end

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
    local ok, lines, outcome = pcall(SpellTip.Lines, SpellTip, id, detail, source)
    if not ok then
        MD:Debug("other", "spell tooltip for %s failed: %s", tostring(id), tostring(lines))
        return false, "error"
    end
    if type(lines) ~= "table" then return false, outcome or "no value" end

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

MD:RegisterCallback("MD_READY", function()
    MD.API.OnSpellTooltip(OnSpell)
    -- T25: a macro's tooltip gets the block of the spell it casts.
    if MD.API.OnMacroTooltip then MD.API.OnMacroTooltip(OnSpell) end
    -- T28: and so does an action button's, from the slot SetAction is handed.
    if MD.API.OnActionTooltip then MD.API.OnActionTooltip(OnSpell) end
    -- T37: the detail key's refresh.
    MD:On("MODIFIER_STATE_CHANGED", OnModifier)
end)
