-- T9 (docs/tasks/T9-spell-tooltip.md, M2): the SpellTuner block on every
-- spell tooltip -- the spellbook, an action bar, a chat link -- through
-- TooltipDataProcessor (Client/API_Forever.lua's MD.API.OnSpellTooltip).
-- Forever only. Reaches the client only through MD.API and Book/Parse's own
-- output; the tooltip frame's own methods (AddLine, AddDoubleLine,
-- HookScript, Show) are the widget toolkit, not a client call (CLAUDE.md).
local _, MD = ...
local Book = MD.Book

MD.SpellTip = MD.SpellTip or {}
local SpellTip = MD.SpellTip

-- Facts: vanilla's crit rule (1.5x); Forever's own is UNVERIFIED (HoTs crit
-- since 70009, REFERENCES-FOREVER.md sec4, amount not stated). T12 checks it
-- against a landed heal above this range's top.
local CRIT_MULT = 1.5

local GREY = "|cff999999"
local ACCENT = "|cff9966ff" -- MD:Print's own accent (Core.lua)
local RESET = "|r"
local function Grey(s) return GREY .. s .. RESET end
local function Accent(s) return ACCENT .. s .. RESET end

-- A number that is nil renders "-", never 0 (CLAUDE.md/this task's Rules).
local function Num(v, decimals)
    if type(v) ~= "number" then return "-" end
    if v ~= v then return "-" end -- NaN, never trusted as a number to show
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

-- The relevant half of the entry's own parsed description -- read fresh from
-- entry.parsed rather than from entry.min/max/over/dur, because a tick shape
-- (Tranquility) and an absorb both leave those four nil and would otherwise
-- be indistinguishable.
local function PartOf(entry, kind)
    if type(entry.parsed) ~= "table" then return nil end
    if kind == "damage" then return entry.parsed.damage end
    return entry.parsed.heal
end

-- The value line's own text -- the four shapes Spells/Parse.lua hands out,
-- read back rather than re-derived: a plain range, an over-time total, the
-- two combined, a repeating tick, or (heal only) a flat absorb.
local function ValueText(entry, kind)
    local verb = (kind == "damage") and "Damage" or "Heals"
    local part = PartOf(entry, kind)
    if part == nil then
        if kind == "heal" and entry.parsed and entry.parsed.absorb ~= nil then
            return "Absorbs " .. Num(entry.parsed.absorb)
        end
        return nil
    end
    if part.tick ~= nil and part.periodDur ~= nil then
        if part.period == 1 then
            return verb .. " " .. Num(part.tick) .. " every sec for " .. Num(part.periodDur) .. " sec"
        end
        return verb .. " " .. Num(part.tick) .. " every " .. Num(part.period) .. " sec for " .. Num(part.periodDur) .. " sec"
    end
    if part.min ~= nil and part.max ~= nil and part.over ~= nil and part.dur ~= nil then
        return verb .. " " .. Num(part.min) .. " - " .. Num(part.max) .. ", then " .. Num(part.over) .. " over " .. Num(part.dur) .. " sec"
    end
    if part.min ~= nil and part.max ~= nil then
        return verb .. " " .. Num(part.min) .. " - " .. Num(part.max)
    end
    if part.over ~= nil and part.dur ~= nil then
        return verb .. " " .. Num(part.over) .. " over " .. Num(part.dur) .. " sec"
    end
    return nil
end

-- Crit only for a direct part (one with its own min/max) -- a HoT tick or an
-- absorb never crits in this text. Review R42: the multiplier is the one
-- number on the block not read from the game, so the line says so on its
-- right-hand side rather than showing the range as the game's own.
local CRIT_NOTE = "1.5x, unverified"
local function CritLine(entry)
    if entry.min == nil or entry.max == nil then return nil end
    return "Crit " .. Num(entry.min * CRIT_MULT) .. " - " .. Num(entry.max * CRIT_MULT)
end

-- {l, r} lines for one spell id, or nil for no block: a spell in the
-- player's book whose family has a kind, else Book:ReadSpell(id) when THAT
-- has a value, else nil (Facts).
-- T28: the outcome is kept in SpellTip.lastOutcome (only there: a second
-- return would reach every caller that passes Lines' result on), for
-- /st tooltip why: "block", "not in book" (an id the book does not list
-- and Book:ReadSpell cannot value) or "no value" (a book spell with no
-- amount to show), "no id" for anything but a number.
function SpellTip:Lines(id)
    if type(id) ~= "number" then
        SpellTip.lastOutcome = "no id"
        return nil
    end

    local book = Book:Get()
    local entry = book.spells[id]
    local inBook = entry ~= nil
    local family = entry and book.families[entry.name]

    if not (family and family.kind) then
        entry = Book:ReadSpell(id)
        family = nil
    end
    if not entry or entry.value == nil then
        SpellTip.lastOutcome = inBook and "no value" or "not in book"
        return nil
    end
    SpellTip.lastOutcome = "block"

    local kind = family and family.kind or entry.kind
    local lines = {}

    -- 1: title, "Rank N of M known" (M = this family's known ranks); blank
    -- for an unranked spell, or just "Rank N" outside a family (ReadSpell
    -- has no sibling ranks to count).
    local rankRight
    if entry.rank then
        if family then
            local knownCount = 0
            for _, e in ipairs(family.ranks) do
                if e.known then knownCount = knownCount + 1 end
            end
            rankRight = "Rank " .. entry.rank .. " of " .. knownCount .. " known"
        else
            rankRight = "Rank " .. entry.rank
        end
    end
    lines[#lines + 1] = { Grey("SpellTuner"), rankRight }

    -- 2: the value
    lines[#lines + 1] = { ValueText(entry, kind) or "-", "avg " .. Num(entry.value) }

    -- 3: crit range
    local crit = CritLine(entry)
    if crit then lines[#lines + 1] = { crit, CRIT_NOTE } end

    -- 4: per mana -- review R13: a Rage / Focus / Energy cost is no mana,
    -- and named (Book's own word, one of three fixed ASCII words)
    local perManaRight
    if entry.perMana then
        perManaRight = Num(entry.perMana, 2)
    elseif entry.cost and type(entry.cost.power) == "string" and type(entry.cost.powerAmount) == "number" then
        perManaRight = "no mana (" .. Num(entry.cost.powerAmount) .. " " .. entry.cost.power .. ")"
    elseif entry.costState == "free" then
        perManaRight = "free"
    elseif entry.cost and entry.cost.percent then
        perManaRight = Num(entry.cost.percent, 0) .. "% of base mana"
    else
        perManaRight = "cost unknown"
    end
    lines[#lines + 1] = { "Per mana", perManaRight }

    -- 5: per second, with the interval named on the same line BY KIND (T10
    -- review of this file: naming every interval "sec cast" read as
    -- "12.0 sec cast" for a HoT whose interval is its own duration, and for a
    -- channel -- neither of which is a cast bar). castKind is the same field
    -- Book already derived (T7): "cast" for a direct/hybrid spell with a real
    -- cast time, "instant" for one at the GCD, "channeled" for a channel; a
    -- pure over-time entry (no direct part, entry.min/max nil) has no
    -- castKind at all but does have an interval (its own duration).
    local perSecRight = "-"
    if entry.perSec and entry.interval then
        -- T10 review's own four examples: a cast bar or the GCD keeps one
        -- decimal (a fractional cast time is real -- Nature's Grace-style
        -- averages elsewhere in the tree carry one too); a HoT's or a
        -- channel's own duration is whole seconds in every description this
        -- tree has ever parsed, so it renders without one, matching the
        -- literal wording the review gave ("over 12 sec", "10 sec channel").
        -- T10b review: "no direct range" also describes an absorb (no
        -- min/max AND no over/dur -- Book's IntervalFor treats it as the
        -- direct/hybrid case, one instant effect), which is not over-time
        -- and must not read "over" -- it has no duration to be over.
        local isAbsorb = entry.parsed and entry.parsed.absorb ~= nil
        local unit
        if entry.castKind == "channeled" then
            unit = Num(entry.interval, 0) .. " sec channel"
        elseif entry.min == nil and entry.max == nil and not isAbsorb then
            unit = "over " .. Num(entry.interval, 0) .. " sec"
        elseif entry.castKind == "instant" then
            unit = Num(entry.interval, 1) .. " sec GCD"
        else
            unit = Num(entry.interval, 1) .. " sec cast"
        end
        perSecRight = Num(entry.perSec, 1) .. " (" .. unit .. ")"
    end
    lines[#lines + 1] = { "Per second", perSecRight }

    -- 6: casts to OOM -- a family row number (Book:Rows, from
    -- Book:DefaultPool(), i.e. from a full pool); a standalone entry
    -- (ReadSpell) never has one. Review R31/R38: the Spellbook pane no longer
    -- rewrites it with the clock's modelled pool, so it is always from full,
    -- and the label says so (the pane's own column is the modelled count).
    local castsRight = "-"
    if entry.casts == math.huge then
        castsRight = "inf"
    elseif type(entry.casts) == "number" then
        castsRight = Num(entry.casts, 0)
    end
    lines[#lines + 1] = { "Casts to OOM from full", castsRight }

    if family then
        -- 7: compared with the highest known rank, when this is not it
        local maxKnown = family.maxKnown
        if maxKnown and maxKnown ~= entry and maxKnown.value ~= nil then
            local valueRatio
            if entry.value and maxKnown.value and maxKnown.value > 0 then
                valueRatio = entry.value / maxKnown.value
            end
            local costRatio
            local a1 = entry.cost and entry.cost.amount
            local a2 = maxKnown.cost and maxKnown.cost.amount
            if a1 and a2 and a2 > 0 then costRatio = a1 / a2 end
            local word = (kind == "damage") and "damage" or "heal"
            lines[#lines + 1] = { "vs Rank " .. tostring(maxKnown.rank),
                Num(valueRatio, 2) .. "x the " .. word .. " for " .. Num(costRatio, 2) .. "x the mana" }
        end

        -- 8: the suggested rank, named on itself and on the others
        if entry.suggested == true then
            lines[#lines + 1] = { Accent("Suggested rank"), nil }
        elseif family.suggested and family.suggested ~= entry then
            lines[#lines + 1] = { "Suggested: Rank " .. tostring(family.suggested.rank),
                Num(family.suggested.perMana, 2) .. " per mana" }
        end

        -- 9: a rank the book does not list
        if family.gaps and #family.gaps > 0 then
            lines[#lines + 1] = { "Rank " .. table.concat(family.gaps, ", ") ..
                " not listed (untrained, or hidden - show all ranks)", nil }
        end
    end

    -- 10: read before combat
    if entry.stale then
        lines[#lines + 1] = { Grey("Read before combat"), nil }
    end

    return lines
end

--------------------------------------------------------------------------------
-- The hook
--------------------------------------------------------------------------------

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
local function OnSpell(tt, id)
    if not tt or type(id) ~= "number" then return false, "no id" end
    if MD.db and MD.db.spellTooltip == false then return true, "off" end

    if not tt._spellTipHooked and tt.HookScript then
        tt._spellTipHooked = true
        tt:HookScript("OnTooltipCleared", function(self) self._spellTipId = nil end)
    end
    if tt._spellTipId ~= nil then
        -- without the clear hook the guard cannot reset, so it holds only
        -- for the id it was set for (the pre-T28 rule)
        if tt._spellTipHooked or tt._spellTipId == id then return true, "already shown" end
    end

    -- The builder never raises into the game's tooltip.
    SpellTip.lastOutcome = nil
    local ok, lines = pcall(SpellTip.Lines, SpellTip, id)
    if not ok then
        MD:Debug("other", "spell tooltip for %s failed: %s", tostring(id), tostring(lines))
        return false, "error"
    end
    if type(lines) ~= "table" then return false, SpellTip.lastOutcome or "no value" end

    tt._spellTipId = id
    for _, line in ipairs(lines) do
        if line[2] ~= nil then
            tt:AddDoubleLine(line[1], line[2])
        else
            tt:AddLine(line[1])
        end
    end
    if tt.Show then tt:Show() end
    return true, "block"
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
end)
