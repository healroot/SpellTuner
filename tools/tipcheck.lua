-- tools/run.sh tools/tipcheck.lua
--
-- T9 (docs/tasks/T9-spell-tooltip.md): the SpellTuner block on every spell
-- tooltip (UI/SpellTip_Forever.lua) through Client/API_Forever.lua's
-- MD.API.OnSpellTooltip and the stub's TooltipDataProcessor. Forever only.
-- T37 (docs/SPEC-forever-ui.md 5.1-5.4b, 5.6): the block's new shapes --
-- SpellTip:Lines(id, detail, source) answering {l, r, lr,lg,lb, rr,rg,rb},
-- the spacer, the plain block and the detail lines behind the key.
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
local Book = MD.Book
local SpellTip = MD.SpellTip

--------------------------------------------------------------------------------
-- fixtures -- named for which acceptance item they are for.
--------------------------------------------------------------------------------

-- item 4: a second rank of Healing Touch, dominating rank 1 -- the "vs Rank M"
-- line's own numbers.
S.AddSpell(92002, "Healing Touch", "Rank 2",
    function() return "Heals a friendly target for 90 to 110." end,
    { cast = 2000, cost = 50, level = 10 })

-- item 5: a family where the highest known rank is NOT the suggested one
-- (same construction as tools/bookcheck.lua's SubFamily) -- tests "named on
-- itself" (rank 1) and "on the others" (rank 2) in one family.
S.AddSpell(92070, "SubFamily", "Rank 1",
    function() return "Heals a friendly target for 195 to 205." end,
    { cast = 1500, cost = 20, level = 1 })
S.AddSpell(92071, "SubFamily", "Rank 2",
    function() return "Heals a friendly target for 495 to 505." end,
    { cast = 1500, cost = 250, level = 10 })

-- item 6: a family the book lists from rank 2 only -- rank 1 is a gap.
S.AddSpell(92010, "GapFamily", "Rank 2",
    function() return "Heals a friendly target for 20 to 30." end,
    { cast = 0, cost = 15, level = 1 })

-- item 7: a spell Book:Scan() never lists (a flyout row, the same trick
-- tools/bookcheck.lua's item 9 uses) but whose id-keyed calls still answer --
-- the chat-link case Book:ReadSpell exists for.
S.AddSpell(92060, "FlyoutHeal", "Rank 1",
    function() return "Heals a friendly target for 60 to 80." end,
    { cast = 1500, cost = 30, level = 1, itemType = Enum.SpellBookItemType.Flyout })

-- item 8: no heal/damage/absorb numbers at all.
S.AddSpell(92040, "PassiveSpell", "Passive",
    function() return "A permanent racial passive." end,
    { cast = 0, noCost = true, level = 1 })

-- item 13 (T10, carried from this file's own T9 Review): an instant direct
-- heal (cast = 0, a min/max part, no tick -- Book's own rule gives it
-- castKind "instant", interval = max(0, GCD) = 1.5) and a channel (cast = 0,
-- a tick/periodDur part -- castKind "channeled", interval = periodDur). Both
-- alongside 5185 (a real cast) and 774 (a pure over-time HoT, already a
-- fixture) cover the per-second line's four kinds.
S.AddSpell(92080, "InstantHeal", "Rank 1",
    function() return "Heals a friendly target for 50 to 60." end,
    { cast = 0, cost = 20, level = 1 })
S.AddSpell(92090, "ChannelHeal", "Rank 1",
    function() return "Heals the target for 285 every 2 sec for 10 sec." end,
    { cast = 0, cost = 35, level = 1 })

-- T10b item 2: an absorb (no heal part, PartOf() nil for both) at the GCD
-- and behind a real cast bar -- Review's own bug was reading "no direct
-- range" as over-time, which an absorb also has no range for.
S.AddSpell(92095, "AbsorbInstant", "Rank 1",
    function() return "Shields the target, absorbing 120 damage." end,
    { cast = 0, cost = 20, level = 1 })
S.AddSpell(92096, "AbsorbCast", "Rank 1",
    function() return "Shields the target, absorbing 300 damage." end,
    { cast = 1500, cost = 45, level = 1 })

-- T37 (docs/SPEC-forever-ui.md 5.4): a hybrid damage spell, two ranks -- the
-- probe's own Moonfire R1 text and the spec's R2 (11 to 15, then 24 over 12).
S.AddSpell(92400, "Moonfire", "Rank 1",
    function() return "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec." end,
    { cast = 0, cost = 25, level = 4 })
S.AddSpell(92401, "Moonfire", "Rank 2",
    function() return "Burns the enemy for 11 to 15 Arcane damage and then an additional 24 Arcane damage over 12 sec." end,
    { cast = 0, cost = 50, level = 10 })

-- T37 (5.4b): an Other spell (no heal, no damage in its text: m2's own Mark
-- of the Wild texts) with a mana cost, and a free Other spell.
S.AddSpell(92500, "Mark of the Wild", "Rank 1",
    function() return "Increases the friendly target's armor by 34 for 1 |4hour:hrs;." end,
    { cast = 0, cost = 20, level = 1 })
S.AddSpell(92501, "Mark of the Wild", "Rank 2",
    function() return "Increases the friendly target's armor by 88 and all attributes by 3 for 1 |4hour:hrs;." end,
    { cast = 0, cost = 50, level = 10 })
S.AddSpell(92600, "Bear Form", nil,
    function() return "Shapeshift into a bear, increasing melee attack power by 120." end,
    { cast = 0, noCost = true, level = 10 })

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function ApproxEq(a, b, eps)
    eps = eps or 1e-6
    if type(a) ~= "number" or type(b) ~= "number" then return a == b end
    return math.abs(a - b) < eps
end

-- The wrapper Client/API_Forever.lua's OnSpellTooltip registered -- the same
-- one a real tooltip post-call would run, so a test can hand it whatever data
-- shape it likes without going through a whole S.ShowSpellTooltip cycle.
local function Wrapper()
    local list = S.tooltipPostCalls and S.tooltipPostCalls[Enum.TooltipDataType.Spell]
    return list and list[1]
end

-- Every {l, r} line as one list of strings, for the ASCII/bare-pipe walk.
local function AllText(lines)
    local out = {}
    for _, line in ipairs(lines or {}) do
        if line[1] ~= nil then out[#out + 1] = line[1] end
        if line[2] ~= nil then out[#out + 1] = line[2] end
    end
    return out
end

local function FindLine(lines, leftSubstring)
    for _, line in ipairs(lines or {}) do
        if type(line[1]) == "string" and line[1]:find(leftSubstring, 1, true) then return line end
    end
    return nil
end

-- T37: the line whose left side is exactly `left`.
local function LineAt(lines, left)
    for i, line in ipairs(lines or {}) do
        if line[1] == left then return line, i end
    end
    return nil
end

-- T37: the colours of theme token `name` as three numbers.
local T = MD.UI and MD.UI.TEXT or {}
local function IsColour(r, g, b, name)
    local c = T[name]
    return c ~= nil and ApproxEq(r, c[1], 1e-3) and ApproxEq(g, c[2], 1e-3) and ApproxEq(b, c[3], 1e-3)
end
local function Gold(r, g, b)
    return type(r) == "number" and ApproxEq(r, 1, 0.02) and type(g) == "number" and g > 0.78 and g < 0.84
        and ApproxEq(b, 0, 0.02)
end
local function HasGoldText(text)
    local lower = text:lower()
    return lower:find("ffcc00", 1, true) ~= nil or lower:find("ffd100", 1, true) ~= nil
end
local function Count(lines, left)
    local n = 0
    for _, line in ipairs(lines or {}) do if line[1] == left then n = n + 1 end end
    return n
end

local function AsciiNoBarePipe(text)
    for i = 1, #text do
        if text:byte(i) > 126 then return false, "non-ascii" end
    end
    local stripped = text:gsub("||", "")
    stripped = stripped:gsub("|c%x%x%x%x%x%x%x%x", "")
    stripped = stripped:gsub("|r", "")
    if stripped:find("|") then return false, "bare pipe" end
    return true
end

--------------------------------------------------------------------------------
-- 1: the hook is registered through the adapter, for the Spell data type
--------------------------------------------------------------------------------
do
    local caps = MD.API.Capabilities()
    local entry
    for _, c in ipairs(caps) do if c.name == "OnSpellTooltip" then entry = c end end

    local registeredGood = type(MD.API.OnSpellTooltip) == "function"
        and entry ~= nil and entry.client == "TooltipDataProcessor.AddTooltipPostCall" and entry.present == true
    -- harness.lua's own PLAYER_LOGIN already fired MD_READY, which is what
    -- calls MD.API.OnSpellTooltip -- so a wrapper is already sitting in the
    -- stub's per-type table, for the Spell type specifically.
    local wrapperGood = type(Wrapper()) == "function"
        and (S.tooltipPostCalls[Enum.TooltipDataType.Damage] == nil)

    check("the hook is registered through the adapter, for the Spell data type",
        registeredGood and wrapperGood,
        string.format("registeredGood=%s wrapperGood=%s", tostring(registeredGood), tostring(wrapperGood)))
end

--------------------------------------------------------------------------------
-- 2: a spell tooltip gets the SpellTuner block once per showing
--------------------------------------------------------------------------------
do
    local tt = CreateFrame("GameTooltip")
    S.ShowSpellTooltip(tt, 5185)
    local n1 = tt:NumLines()

    -- the callback run twice for ONE showing (no clear in between, the way an
    -- action button re-setting its own tooltip on a timer would) adds only
    -- the one block.
    local wrapper = Wrapper()
    wrapper(tt, { type = Enum.TooltipDataType.Spell, id = 5185 })
    local n2 = tt:NumLines()

    -- a clear and a new showing adds it again.
    S.ShowSpellTooltip(tt, 5185)
    local n3 = tt:NumLines()

    check("a spell tooltip gets the SpellTuner block once per showing",
        n1 > 0 and n2 == n1 and n3 == n1,
        string.format("n1=%d n2=%d n3=%d", n1, n2, n3))
end

--------------------------------------------------------------------------------
-- 3: every number in the block is the book's (T37: the plain block's four
-- facts, the value and crit behind the key)
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local htR1 = book.spells[5185]
    local lines = SpellTip:Lines(5185, true)

    local average = LineAt(lines, "Average")
    local avgGood = average ~= nil
        and average[2] == string.format("%d (%d - %d)", math.floor(htR1.value + 0.5), htR1.min, htR1.max)

    local critLine = LineAt(lines, "Crit")
    local critGood = critLine ~= nil
        and critLine[2] == string.format("%d - %d",
            math.floor(htR1.min * 1.5 + 0.5), math.floor(htR1.max * 1.5 + 0.5))

    local perManaLine = LineAt(lines, "Per mana")
    local perManaGood = perManaLine ~= nil and perManaLine[2] == string.format("%.2f", htR1.perMana)

    local perSecLine = LineAt(lines, "Per second")
    local perSecGood = perSecLine ~= nil and perSecLine[2] == string.format("%.1f", htR1.perSec)

    local castsLine = LineAt(lines, "Casts to OOM")
    local expectCasts
    if htR1.casts == math.huge then expectCasts = "inf"
    else expectCasts = tostring(math.floor(htR1.casts + 0.5)) .. " full" end
    local castsGood = castsLine ~= nil and castsLine[2] == expectCasts

    check("every number in the block is the book's",
        avgGood and critGood and perManaGood and perSecGood and castsGood,
        string.format("avg=%s crit=%s perMana=%s perSec=%s casts=%s",
            tostring(average and average[2]), tostring(critLine and critLine[2]),
            tostring(perManaLine and perManaLine[2]), tostring(perSecLine and perSecLine[2]),
            tostring(castsLine and castsLine[2])))
end

--------------------------------------------------------------------------------
-- 4: every known rank is compared behind the key, this one marked (T37: the
-- rank rows replace the "vs Rank M" line)
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local htR1, htR2 = book.spells[5185], book.spells[92002]
    local function Row(e)
        local casts = (e.casts == math.huge) and "inf" or tostring(e.casts)
        return string.format("%d   %.2f per mana   %s", math.floor(e.value + 0.5), e.perMana, casts)
    end
    local lines = SpellTip:Lines(5185, true)
    local this = LineAt(lines, "Rank 1 (this)")
    local other = LineAt(lines, "Rank 2")
    local plainHasRows = LineAt(SpellTip:Lines(5185, false), "Rank 2") ~= nil
    local noVs = FindLine(lines, "vs Rank") == nil

    check("every known rank is compared behind the key, this one marked",
        this ~= nil and other ~= nil and this[2] == Row(htR1) and other[2] == Row(htR2)
        and IsColour(this[6], this[7], this[8], "text") and IsColour(other[6], other[7], other[8], "text2")
        and not plainHasRows and noVs,
        string.format("this=%s other=%s plainHasRows=%s noVs=%s", tostring(this and this[2]),
            tostring(other and other[2]), tostring(plainHasRows), tostring(noVs)))
end

--------------------------------------------------------------------------------
-- 5: the suggested rank comes first: named on itself, on the others, and a
-- dominated rank names what dominates it
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local sub1, sub2 = book.spells[92070], book.spells[92071]
    local suggestedIsR1 = sub1.suggested == true and sub2.suggested ~= true

    local r1Lines = SpellTip:Lines(92070)
    local r2Lines = SpellTip:Lines(92071)
    local onItself = r1Lines[2][1] == "Suggested" and r1Lines[2][2] == "this rank"
    local onTheOther = r2Lines[2]
    local onTheOtherGood = onTheOther[1] == "Suggested"
        and onTheOther[2] == string.format("Rank 1 (%.2f per mana)", sub1.perMana)
        and IsColour(onTheOther[3], onTheOther[4], onTheOther[5], "label")
        and IsColour(onTheOther[6], onTheOther[7], onTheOther[8], "accent")

    -- Healing Touch rank 2 (90-110 for 50 in 2.0 s) beats rank 1 on both
    -- per mana and per second.
    local htR1 = book.spells[5185]
    local dom = SpellTip:Lines(5185)[2]
    local domGood = htR1.dominated == true and dom[1] == "Dominated by" and dom[2] == "Rank 2"

    check("the suggested rank comes first: on itself, on the others, and a dominated rank",
        suggestedIsR1 and onItself and onTheOtherGood and domGood,
        string.format("suggestedIsR1=%s onItself=%s/%s onTheOther=%s/%s dominated=%s/%s",
            tostring(suggestedIsR1), tostring(r1Lines[2][1]), tostring(r1Lines[2][2]),
            tostring(onTheOther[1]), tostring(onTheOther[2]), tostring(dom[1]), tostring(dom[2])))
end

--------------------------------------------------------------------------------
-- 6: a rank the book does not list is named, behind the key only (T37)
--------------------------------------------------------------------------------
do
    local plain = SpellTip:Lines(92010, false)
    local detail = SpellTip:Lines(92010, true)
    local gapLine = LineAt(detail, "Not in your book")
    check("T37: the gap line only with the key, in muted",
        gapLine ~= nil and gapLine[2] == "Rank 1" and LineAt(plain, "Not in your book") == nil
        and FindLine(plain, "not listed") == nil
        and IsColour(gapLine[3], gapLine[4], gapLine[5], "muted") and IsColour(gapLine[6], gapLine[7], gapLine[8], "muted"),
        gapLine and (gapLine[1] .. " / " .. tostring(gapLine[2])) or "no gap line")
end

--------------------------------------------------------------------------------
-- 7: a spell not in the book still gets its own numbers: the header, per
-- mana and per second (T37, 5.4), its value behind the key
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local notInBook = book.spells[92060] == nil
    local lines = SpellTip:Lines(92060)
    local detail = SpellTip:Lines(92060, true)
    local shape = lines ~= nil and #lines == 3 and lines[1][1] == "SpellTuner"
        and lines[2][1] == "Per mana" and lines[3][1] == "Per second"
    local average = LineAt(detail, "Average")

    check("a spell not in the book gets the header, per mana and per second",
        notInBook and shape and average ~= nil and average[2] == "70 (60 - 80)"
        and FindLine(detail, "Suggested") == nil and FindLine(detail, "Casts to OOM") == nil,
        string.format("notInBook=%s lines=%s average=%s", tostring(notInBook),
            tostring(lines and #lines), tostring(average and average[2])))
end

--------------------------------------------------------------------------------
-- 8: a spell with no amount and no cost gets no block
--------------------------------------------------------------------------------
do
    local lines = SpellTip:Lines(92040)
    check("a spell with no amount gets no block", lines == nil, tostring(lines))
end

--------------------------------------------------------------------------------
-- 9: a secret id, a missing id or a builder error never reaches the game's
-- tooltip
--------------------------------------------------------------------------------
do
    local wrapper = Wrapper()

    local tt1 = CreateFrame("GameTooltip")
    local okSecret = pcall(wrapper, tt1, { type = Enum.TooltipDataType.Spell, id = S.Secret() })
    local secretGood = okSecret and tt1:NumLines() == 0

    local tt2 = CreateFrame("GameTooltip")
    local okMissing1 = pcall(wrapper, tt2, { type = Enum.TooltipDataType.Spell })          -- no id field
    local okMissing2 = pcall(wrapper, tt2, { type = Enum.TooltipDataType.Spell, id = "x" }) -- not a number
    local missingGood = okMissing1 and okMissing2 and tt2:NumLines() == 0

    local tt3 = CreateFrame("GameTooltip")
    local savedLines = SpellTip.Lines
    SpellTip.Lines = function() error("builder blew up (test)") end
    local okBuilder = pcall(S.ShowSpellTooltip, tt3, 5185)
    SpellTip.Lines = savedLines
    local builderGood = okBuilder and tt3:NumLines() == 0

    check("a secret id, a missing id or a builder error never reaches the game's tooltip",
        secretGood and missingGood and builderGood,
        string.format("secretGood=%s missingGood=%s builderGood=%s",
            tostring(secretGood), tostring(missingGood), tostring(builderGood)))
end

--------------------------------------------------------------------------------
-- 10: values read before combat say so, last in the plain block (T37: at
-- most 5 plain lines when fresh, 6 when stale)
--------------------------------------------------------------------------------
do
    local freshPlain = SpellTip:Lines(5185, false)
    local freshCount = freshPlain and #freshPlain

    S.inCombat = false
    Book:MarkDirty()
    Book:Get() -- an ok, non-stale read of 5185

    S.inCombat = true
    Book:MarkDirty()
    Book:Get() -- 5185's description goes secret; the stale value is kept
    S.inCombat = false

    local plain = SpellTip:Lines(5185, false)
    local detail = SpellTip:Lines(5185, true)
    local last = plain[#plain]
    local _, staleAt = LineAt(detail, "Text read before combat")
    check("T37: at most 5 plain lines when fresh, 6 when stale, the stale line last",
        freshCount == 5 and #plain == 6 and last[1] == "Text read before combat" and last[2] == nil
        and IsColour(last[3], last[4], last[5], "bad") and staleAt == #plain and #detail > #plain
        and FindLine(freshPlain, "before combat") == nil,
        string.format("fresh=%s stale=%d last=%s staleAt=%s detail=%d", tostring(freshCount), #plain,
            tostring(last and last[1]), tostring(staleAt), #detail))

    -- leave the book clean for anything run after this.
    Book:MarkDirty()
    Book:Get()
end

--------------------------------------------------------------------------------
-- 11: off means off, from the command and the checkbox
--------------------------------------------------------------------------------
do
    local onByDefault = MD.db.spellTooltip == true

    SlashCmdList.SPELLTUNER("tooltip")
    local offByCommand = MD.db.spellTooltip == false
    local tt1 = CreateFrame("GameTooltip")
    S.ShowSpellTooltip(tt1, 5185)
    local suppressedByCommand = tt1:NumLines() == 0
    SlashCmdList.SPELLTUNER("tooltip")
    local onAgain = MD.db.spellTooltip == true

    MD:SelectView("settings", "general")
    local pane
    for _, f in ipairs(S.allFrames) do
        if f.tooltipCheck then pane = f end
    end
    local check1 = pane and pane.tooltipCheck
    local checkboxGood = false
    local suppressedByCheckbox = false
    if check1 then
        check1.onClick(false, check1)
        local offByCheckbox = MD.db.spellTooltip == false
        local tt2 = CreateFrame("GameTooltip")
        S.ShowSpellTooltip(tt2, 5185)
        suppressedByCheckbox = tt2:NumLines() == 0
        check1.onClick(true, check1)
        checkboxGood = offByCheckbox and MD.db.spellTooltip == true
    end

    check("off means off, from the command and the checkbox",
        onByDefault and offByCommand and suppressedByCommand and onAgain
        and check1 ~= nil and checkboxGood and suppressedByCheckbox,
        string.format("onByDefault=%s offByCommand=%s suppressedByCommand=%s onAgain=%s hasCheckbox=%s checkboxGood=%s suppressedByCheckbox=%s",
            tostring(onByDefault), tostring(offByCommand), tostring(suppressedByCommand), tostring(onAgain),
            tostring(check1 ~= nil), tostring(checkboxGood), tostring(suppressedByCheckbox)))
end

--------------------------------------------------------------------------------
-- 12: every line is ASCII with no bare pipe -- plain, detail and from a macro
--------------------------------------------------------------------------------
do
    local ids = { 5185, 92002, 92070, 92071, 92010, 92060, 774, 92090, 92095, 92400, 92401, 92500, 92501 }
    local bad
    for _, id in ipairs(ids) do
        for _, args in ipairs({ { false }, { true }, { true, "macro" } }) do
            local lines = SpellTip:Lines(id, args[1], args[2])
            for _, text in ipairs(AllText(lines)) do
                local good, why = AsciiNoBarePipe(text)
                if not good and not bad then bad = why .. " in '" .. text .. "' (id " .. id .. ")" end
            end
        end
    end
    check("every line is ASCII with no bare pipe", bad == nil, bad)
end

--------------------------------------------------------------------------------
-- 13 (T10, T37): per second -- a plain number for a cast, the GCD or a
-- hybrid; "over N s" for a HoT and a channel; never the cast line again
--------------------------------------------------------------------------------
do
    local book = Book:Get()

    local castEntry = book.spells[5185]
    local castLine = LineAt(SpellTip:Lines(5185), "Per second")
    local castGood = castLine ~= nil and castLine[2] == string.format("%.1f", castEntry.perSec)

    local instantEntry = book.spells[92080]
    local instantLine = LineAt(SpellTip:Lines(92080), "Per second")
    local instantGood = instantEntry ~= nil and instantEntry.castKind == "instant"
        and instantLine ~= nil and instantLine[2] == string.format("%.1f", instantEntry.perSec)

    local overEntry = book.spells[774]
    local overLine = LineAt(SpellTip:Lines(774), "Per second")
    local overGood = overEntry ~= nil and overEntry.min == nil and overEntry.max == nil
        and overLine ~= nil and overLine[2] == string.format("%.1f over %d s",
            overEntry.perSec, math.floor(overEntry.interval + 0.5))

    local chanEntry = book.spells[92090]
    local chanLine = LineAt(SpellTip:Lines(92090), "Per second")
    local chanGood = chanEntry ~= nil and chanEntry.castKind == "channeled"
        and chanLine ~= nil and chanLine[2] == string.format("%.1f over %d s",
            chanEntry.perSec, math.floor(chanEntry.interval + 0.5))

    local mfLine = LineAt(SpellTip:Lines(92401), "Per second")
    local mfGood = mfLine ~= nil and mfLine[2] == "24.7"

    check("per second: plain for a cast, the GCD or a hybrid, over N s for a HoT or channel",
        castGood and instantGood and overGood and chanGood and mfGood,
        string.format("cast=%s instant=%s over=%s channel=%s hybrid=%s",
            castLine and castLine[2] or "nil", instantLine and instantLine[2] or "nil",
            overLine and overLine[2] or "nil", chanLine and chanLine[2] or "nil", mfLine and mfLine[2] or "nil"))
end

--------------------------------------------------------------------------------
-- 14 (T10b, T37): an absorb's per-second line is a plain number, never over
--------------------------------------------------------------------------------
do
    local book = Book:Get()

    local absInstantEntry = book.spells[92095]
    local absInstantLine = LineAt(SpellTip:Lines(92095), "Per second")
    local absInstantGood = absInstantEntry ~= nil and absInstantEntry.castKind == "instant"
        and absInstantLine ~= nil and absInstantLine[2] == string.format("%.1f", absInstantEntry.perSec)

    local absCastEntry = book.spells[92096]
    local absCastLine = LineAt(SpellTip:Lines(92096), "Per second")
    local absCastGood = absCastEntry ~= nil and absCastEntry.castKind == "cast"
        and absCastLine ~= nil and absCastLine[2] == string.format("%.1f", absCastEntry.perSec)

    local absorbs = LineAt(SpellTip:Lines(92095, true), "Absorbs")

    check("an absorb's per-second line is a plain number, never over",
        absInstantGood and absCastGood and absorbs ~= nil and absorbs[2] == "120",
        string.format("instant=%s cast=%s absorbs=%s",
            absInstantLine and absInstantLine[2] or "nil", absCastLine and absCastLine[2] or "nil",
            tostring(absorbs and absorbs[2])))
end

--------------------------------------------------------------------------------
-- 15 (review R31, T37): casts to OOM counts from a full pool, and adds
-- "~N now" in mana blue only while the modelled pool is below its max
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    -- SubFamily rank 2 (250 mana a cast) runs dry; Healing Touch rank 1
    -- never does against the stub's regen.
    local entry = book.spells[92071]
    local fromFull = Book:CastsFor(entry, Book:DefaultPool())
    local model = MD.Clock and MD.Clock.model
    model:Anchor(GetTime(), model.max, "test: full")
    local atFull = LineAt(SpellTip:Lines(92071), "Casts to OOM")

    model:Anchor(GetTime(), 500, "test: drained for tipcheck")
    local now = Book:CastsFor(entry, MD.Clock:Pool())
    local drained = LineAt(SpellTip:Lines(92071), "Casts to OOM")
    model:Anchor(GetTime(), model.max, "test: restored")

    local want = tostring(fromFull) .. " full"
    local wantNow = want .. ", " .. T.mana.hex .. "~" .. tostring(now) .. " now|r"
    check("T37: casts to OOM from full, and ~N now only below max",
        atFull ~= nil and atFull[2] == want and drained ~= nil and drained[2] == wantNow
        and type(fromFull) == "number" and fromFull ~= math.huge and type(now) == "number" and now < fromFull,
        string.format("full=%s drained=%s want=%s / %s", tostring(atFull and atFull[2]),
            tostring(drained and drained[2]), want, wantNow))
end

--------------------------------------------------------------------------------
-- 16 (review R42, T37): the 1.5x crit multiplier is said to be assumed,
-- once, and only behind the key
--------------------------------------------------------------------------------
do
    local plain = SpellTip:Lines(5185, false)
    local detail = SpellTip:Lines(5185, true)
    local mult = LineAt(detail, "Crit multiplier")
    local hot = SpellTip:Lines(774, true)
    check("the 1.5x crit multiplier is said to be assumed, once, behind the key",
        mult ~= nil and mult[2] == "x1.5, not measured" and Count(detail, "Crit multiplier") == 1
        and IsColour(mult[6], mult[7], mult[8], "muted")
        and LineAt(plain, "Crit") == nil and LineAt(plain, "Crit multiplier") == nil
        and LineAt(hot, "Crit") == nil and LineAt(hot, "Crit multiplier") == nil,
        string.format("mult=%s", tostring(mult and mult[2])))
end

--------------------------------------------------------------------------------
-- 17 (review R13): a Rage cost reads as no mana, named, never as a per-mana
-- number, and no casts to OOM. Text and cost line: talentsforever's beta
-- client 1.60.1.70009.
--------------------------------------------------------------------------------
do
    S.AddSpell(92300, "Rend", "Rank 1",
        function() return "Wounds the target causing them to bleed for 15 damage over 9 sec." end,
        { cast = 0, level = 4, costLine = "10 Rage",
          costList = { { type = 1, name = "RAGE", cost = 10, minCost = 10, costPercent = 0, costPerSec = 0,
                         requiredAuraID = 0, hasRequiredAura = false } } })
    Book:MarkDirty()
    local lines = SpellTip:Lines(92300)
    local perMana = LineAt(lines, "Per mana")
    local casts = FindLine(lines, "Casts to OOM")
    check("a Rage cost reads as no mana on the tooltip, named",
        perMana ~= nil and perMana[2] == "no mana (10 Rage)" and casts == nil,
        string.format("perMana=%s casts=%s", tostring(perMana and perMana[2]), tostring(casts and casts[2])))
end

--------------------------------------------------------------------------------
-- T25: the block on a macro's tooltip, through MD.API.OnMacroTooltip
--------------------------------------------------------------------------------
local MACRO = 25
local function SameLines(a, b)
    if a:NumLines() ~= b:NumLines() or a:NumLines() == 0 then return false end
    for i = 1, a:NumLines() do
        if a.lines[i][1] ~= b.lines[i][1] or a.lines[i][2] ~= b.lines[i][2] then return false end
    end
    return true
end
-- T37: what a macro's tooltip should carry -- the spacer, then the spell's
-- own plain block with "- macro" on its header (SpellTip:Lines(id, false,
-- "macro")), written line by line the way the hook writes them.
local function MacroBlock(id)
    local tt = CreateFrame("GameTooltip")
    tt:AddLine(" ")
    for _, line in ipairs(SpellTip:Lines(id, false, "macro") or {}) do
        if line[2] ~= nil then tt:AddDoubleLine(line[1], line[2]) else tt:AddLine(line[1]) end
    end
    return tt
end
local function MacroTooltip(data, owner)
    local tt = CreateFrame("GameTooltip")
    S.ShowMacroTooltip(tt, data, owner)
    return tt
end

do
    local want = MacroBlock(5185)
    local got = MacroTooltip({ type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } }, nil)
    check("a macro's tooltip gets its spell's block, from the tooltip data",
        SameLines(got, want), string.format("got=%d want=%d", got:NumLines(), want:NumLines()))
end

do
    local want = MacroBlock(5185)
    local noSpell = { type = MACRO, lines = { { tooltipType = 0, tooltipID = 9 } } }
    S.actions[7] = { "macro", 3 }
    S.macroSpells[3] = 5185
    local viaIndex = MacroTooltip(noSpell, { action = 7 })

    S.macroSpells[3] = nil
    S.actions[7] = { "macro", 5185, "spell" }
    local viaSpell = MacroTooltip(noSpell, { action = 7 })

    local viaAttr = MacroTooltip(noSpell, {
        GetAttribute = function(_, k) if k == "action" then return 7 end return nil end })

    S.actions[7] = nil
    check("a macro's spell is found through its action slot when the data does not name it",
        SameLines(viaIndex, want) and SameLines(viaSpell, want) and SameLines(viaAttr, want),
        string.format("index=%d spell=%d attr=%d want=%d", viaIndex:NumLines(), viaSpell:NumLines(),
            viaAttr:NumLines(), want:NumLines()))
end

do
    local data = { type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } }
    local tt = MacroTooltip(data, nil)
    local n1 = tt:NumLines()
    S.tooltipPostCalls[MACRO][1](tt, data)
    local n2 = tt:NumLines()
    S.ShowMacroTooltip(tt, data, nil)
    local n3 = tt:NumLines()
    check("a macro's block appears once per showing",
        n1 > 0 and n2 == n1 and n3 == n1, string.format("n1=%d n2=%d n3=%d", n1, n2, n3))
end

do
    local noSpell = { type = MACRO, lines = { { tooltipType = 0, tooltipID = 9 } } }
    local total, allOk = 0, true
    local function Try(data, owner)
        local tt = CreateFrame("GameTooltip")
        local ok = pcall(S.ShowMacroTooltip, tt, data, owner)
        if not ok then allOk = false end
        total = total + tt:NumLines()
    end
    Try(noSpell, nil)                                                              -- no spell line, no slot
    Try({ type = MACRO, lines = { { tooltipType = 1, tooltipID = S.Secret() } } }, nil) -- a secret id
    S.actions[8] = { "macro", 4 }                                                  -- GetMacroSpell answers nil
    Try(noSpell, { action = 8 })
    S.actions[8] = nil
    Try(noSpell, { GetAttribute = function() error("owner blew up (test)") end })  -- a raising owner
    Try(nil, nil)                                                                  -- data = nil
    check("a macro with no spell, a secret id or a raising owner adds nothing and never raises",
        allOk and total == 0, string.format("allOk=%s lines=%d", tostring(allOk), total))
end

do
    local list = S.tooltipPostCalls[MACRO]
    local one = list ~= nil and #list == 2 and type(list[2]) == "function" -- the probe's own (T25a, at load), then the adapter's
    local entry
    for _, c in ipairs(MD.API.Capabilities()) do if c.name == "OnMacroTooltip" then entry = c end end
    MD.db.spellTooltip = false
    local tt = MacroTooltip({ type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } }, nil)
    local off = tt:NumLines() == 0
    MD.db.spellTooltip = true
    check("the macro hook is registered through the adapter, and off means off",
        one and off and entry ~= nil and entry.present == true,
        string.format("one=%s off=%s entry=%s", tostring(one), tostring(off), tostring(entry ~= nil)))
end

--------------------------------------------------------------------------------
-- T28 (docs/SPEC-forever-ui.md 5.5): the untyped first line, the SetAction
-- path and /st tooltip why
--------------------------------------------------------------------------------
-- What `/st tooltip why` printed, and whether it left the setting alone.
local function Why()
    local said = {}
    local prev = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
    local before = MD.db.spellTooltip
    local okCall = pcall(SlashCmdList.SPELLTUNER, "tooltip why")
    _G.DEFAULT_CHAT_FRAME = prev
    return table.concat(said, "\n"), okCall and MD.db.spellTooltip == before, #said
end
local function Has(text, part) return text:find(part, 1, true) ~= nil end

do
    local want = MacroBlock(5185)
    local typed0 = MacroTooltip(S.MacroDataUntyped(5185, 0), nil)
    local noType = MacroTooltip({ type = MACRO, lines = { { tooltipID = 5185 } } }, nil)
    check("T28: an untyped first line gives the block",
        SameLines(typed0, want) and SameLines(noType, want),
        string.format("type0=%d none=%d want=%d", typed0:NumLines(), noType:NumLines(), want:NumLines()))
end

do
    local want = MacroBlock(5185)
    S.actions[61] = { "macro", 3 }
    S.macroSpells[3] = 5185
    local tt = S.SetActionTooltip(61)          -- no Macro post-call fires, no owner
    local owner = tt:GetOwner()
    local got = SameLines(tt, want)
    S.actions[61], S.macroSpells[3] = nil, nil
    local entry
    for _, c in ipairs(MD.API.Capabilities()) do if c.name == "OnActionTooltip" then entry = c end end
    check("T28: the SetAction path gives the block from the slot argument, with no owner",
        got and owner == nil and S.secureHooks.SetAction == 1 and entry ~= nil and entry.present == true,
        string.format("got=%d want=%d hooks=%s entry=%s", tt:NumLines(), want:NumLines(),
            tostring(S.secureHooks.SetAction), tostring(entry and entry.present)))
end

do
    -- the post-call names Healing Touch rank 1, the slot rank 2: one block,
    -- the first one, whatever id the second path resolved
    local want = MacroBlock(5185)
    S.actions[61] = { "macro", 3 }
    S.macroSpells[3] = 92002
    local tt = S.SetActionTooltip(61, { type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } })
    local got = SameLines(tt, want)
    local n = tt:NumLines()
    S.actions[61], S.macroSpells[3] = nil, nil
    local why = Why()
    check("T28: a Macro post-call and the SetAction hook on one showing give the block once",
        got and Has(why, "path macro post-call, SetAction hook")
        and Has(why, "SetAction slot 61 -> macro 3 -> GetMacroSpell 92002 -> already shown"),
        string.format("lines=%d want=%d why=%s", n, want:NumLines(), why))
end

do
    -- 1: an id neither in the book nor readable, and no owner
    MacroTooltip(S.MacroDataUntyped(424242, 0), nil)
    local why1, kept1, n1 = Why()
    -- 2: a book spell with no value on the first line, then the owner's slot
    S.actions[7] = { "macro", 3 }
    S.macroSpells[3] = 5185
    local tt = MacroTooltip(S.MacroDataUntyped(92040, 0), { action = 7 })
    S.actions[7], S.macroSpells[3] = nil, nil
    local why2, kept2 = Why()
    local ascii1, ascii2 = AsciiNoBarePipe(why1), AsciiNoBarePipe(why2)
    check("T28: /st tooltip why names the path, each step and what Lines said",
        n1 == 1 and kept1 and kept2 and ascii1 and ascii2 and tt:NumLines() > 0
        and Has(why1, "path macro post-call") and Has(why1, "spell line: none")
        and Has(why1, "first line: type 0 id 424242 -> not in book") and Has(why1, "slot: no owner")
        and Has(why2, "first line: type 0 id 92040 -> no value")
        and Has(why2, "slot 7 -> macro 3 -> GetMacroSpell 5185 -> block")
        and Has(why2, "macro post-call on") and Has(why2, "SetAction hook on"),
        why1 .. " // " .. why2)
end

do
    local total = 0
    local function Count(tt) total = total + tt:NumLines() end
    local noId = { type = MACRO, lines = { { tooltipType = 0 } } }
    local ok1 = pcall(function()
        Count(MacroTooltip(noId, { GetAttribute = function() error("owner blew up (test)") end }))
    end)
    local why1 = Why()
    -- GetOwner itself raising, straight into the adapter's post-call
    local tt = CreateFrame("GameTooltip")
    tt.GetOwner = function() error("GetOwner blew up (test)") end
    local ok2 = pcall(S.tooltipPostCalls[MACRO][2], tt, noId)
    Count(tt)
    -- a slot whose ActionInfo raises, and a secret slot
    S.actions[62] = setmetatable({}, { __index = function() error("slot blew up (test)") end })
    local ok3 = pcall(function() Count(S.SetActionTooltip(62, noId)) end)
    S.actions[62] = nil
    local why3 = Why()
    local ok4 = pcall(function() Count(S.SetActionTooltip(S.Secret())) end)
    check("T28: a raising owner or slot adds nothing, never raises, and why says so",
        ok1 and ok2 and ok3 and ok4 and total == 0 and Has(why1, "slot: owner raised")
        and Has(why3, "SetAction slot 62 -> ActionInfo error"),
        string.format("ok=%s,%s,%s,%s lines=%d why1=%s why3=%s", tostring(ok1), tostring(ok2),
            tostring(ok3), tostring(ok4), total, why1, why3))
end

--------------------------------------------------------------------------------
-- T37 (docs/SPEC-forever-ui.md 5.1-5.4b, 5.6): the block's look, its plain /
-- detail split, the Other block, the macro marker, the detail key
--------------------------------------------------------------------------------
-- A showing through the Spell post-call, with the detail key up or down.
local function Shown(id, shift)
    S.shift = shift == true
    local tt = CreateFrame("GameTooltip")
    S.ShowSpellTooltip(tt, id)
    S.shift = false
    return tt
end
local function RenderedText(tt)
    local out = {}
    for _, line in ipairs(tt.lines or {}) do
        if line[1] ~= nil then out[#out + 1] = line[1] end
        if line[2] ~= nil then out[#out + 1] = line[2] end
    end
    return out
end

do
    -- the block after a spacer, its header in the accent, its pairs in the
    -- label colour and white, every colour passed as an argument and none
    -- of them Blizzard gold
    local tt = Shown(5185, true)
    local l = tt.lines or {}
    local head, pair = l[2] or {}, l[4] or {}
    local allColoured, gold = #l > 2, false
    for i = 2, #l do
        local c, rc = l[i].color, l[i].rcolor
        if type(c) ~= "table" or type(c[1]) ~= "number" or type(c[3]) ~= "number" then allColoured = false end
        if l[i][2] ~= nil and (type(rc) ~= "table" or type(rc[1]) ~= "number" or type(rc[3]) ~= "number") then
            allColoured = false
        end
        if c and Gold(c[1], c[2], c[3]) then gold = true end
        if rc and Gold(rc[1], rc[2], rc[3]) then gold = true end
    end
    for _, text in ipairs(RenderedText(tt)) do if HasGoldText(text) then gold = true end end
    check("T37: a spacer, then the block with its colours passed and no gold",
        l[1] ~= nil and l[1][1] == " " and l[1][2] == nil and head[1] == "SpellTuner"
        and head.color and IsColour(head.color[1], head.color[2], head.color[3], "accent")
        and head.rcolor and IsColour(head.rcolor[1], head.rcolor[2], head.rcolor[3], "text")
        and pair[1] == "Per mana" and pair.color and IsColour(pair.color[1], pair.color[2], pair.color[3], "label")
        and pair.rcolor and IsColour(pair.rcolor[1], pair.rcolor[2], pair.rcolor[3], "text")
        and allColoured and not gold,
        string.format("spacer=%s head=%s pair=%s allColoured=%s gold=%s", tostring(l[1] and l[1][1]),
            tostring(head[1]), tostring(pair[1]), tostring(allColoured), tostring(gold)))
end

do
    -- the header names the rank of the family's known ranks and the key
    local head = SpellTip:Lines(5185)[1]
    local maxHead = SpellTip:Lines(92002)[1]
    check("T37: the header says Rank N of M and the detail key in the disabled colour",
        head[1] == "SpellTuner" and head[2] == "Rank 1 of 2  " .. T.disabled.hex .. "Shift|r"
        and maxHead[2] == "Rank 2 of 2  " .. T.disabled.hex .. "Shift|r",
        string.format("head=%s max=%s", tostring(head[2]), tostring(maxHead[2])))
end

do
    -- nothing the game already printed: no description range, no cast line
    local digitsRange = "%d+ %- %d+"
    local bad
    for _, id in ipairs({ 5185, 92002, 92060, 92090, 92400, 92401, 774 }) do
        for _, text in ipairs(AllText(SpellTip:Lines(id, false))) do
            if text:find(digitsRange) or text:find("sec cast", 1, true) or text:find("GCD", 1, true) then
                bad = bad or (tostring(id) .. ": " .. text)
            end
        end
    end
    check("T37: no range and no cast line on the plain block", bad == nil, bad)
end

do
    -- detail lines only with the key (Shift by default), always with
    -- ALWAYS, never with NEVER
    local plainN = 1 + #SpellTip:Lines(5185, false)
    local detailN = 1 + #SpellTip:Lines(5185, true)
    local up, down = Shown(5185, false):NumLines(), Shown(5185, true):NumLines()
    MD.db.spellTooltipDetail = "ALWAYS"
    local always = Shown(5185, false):NumLines()
    local alwaysHead = SpellTip:Lines(5185)[1][2]
    MD.db.spellTooltipDetail = "NEVER"
    local never = Shown(5185, true):NumLines()
    MD.db.spellTooltipDetail = "SHIFT"
    check("T37: detail lines only with the key",
        detailN > plainN and up == plainN and down == detailN and always == detailN and never == plainN
        and alwaysHead == "Rank 1 of 2",
        string.format("plain=%d detail=%d up=%d down=%d always=%d never=%d alwaysHead=%s", plainN, detailN,
            up, down, always, never, tostring(alwaysHead)))
end

do
    -- 5.4: a hybrid's detail lines -- the hit, the over-time part, the total
    local d = SpellTip:Lines(92401, true)
    local hit, over, total = LineAt(d, "Hit"), LineAt(d, "Over time"), LineAt(d, "Total")
    local sugg = SpellTip:Lines(92401)[2]
    check("T37: a hybrid's detail is the hit, the over-time part and the total",
        hit ~= nil and hit[2] == "avg 13, crit 17 - 23" and over ~= nil and over[2] == "24 over 12 s"
        and total ~= nil and total[2] == "37" and LineAt(d, "Crit multiplier") ~= nil
        and sugg[1] == "Suggested" and sugg[2]:find("^Rank 1 %(") ~= nil,
        string.format("hit=%s over=%s total=%s suggested=%s/%s", tostring(hit and hit[2]),
            tostring(over and over[2]), tostring(total and total[2]), tostring(sugg[1]), tostring(sugg[2])))
end

do
    -- 5.4b: a spell with no heal and no damage: the header and casts to OOM,
    -- no hint, the same with the key down
    local book = Book:Get()
    local fam = book.families["Mark of the Wild"]
    local plain, detail = SpellTip:Lines(92501, false), SpellTip:Lines(92501, true)
    local casts = Book:CastsFor({ cost = book.spells[92501].cost, interval = 1.5 }, Book:DefaultPool())
    local want = (casts == math.huge) and "inf" or (tostring(casts) .. " full")
    local tt = Shown(92501, true)
    check("T37: an Other spell gets two lines and no hint",
        fam ~= nil and fam.kind == nil and plain ~= nil and #plain == 2 and #detail == 2
        and plain[1][1] == "SpellTuner" and plain[1][2] == "Rank 2 of 2"
        and plain[2][1] == "Casts to OOM" and plain[2][2] == want and tt:NumLines() == 3,
        string.format("kind=%s lines=%s head=%s casts=%s want=%s shown=%d", tostring(fam and fam.kind),
            tostring(plain and #plain), tostring(plain and plain[1][2]), tostring(plain and plain[2] and plain[2][2]),
            want, tt:NumLines()))
end

do
    -- a free Other spell: nothing SpellTuner could add
    local lines, outcome = SpellTip:Lines(92600)
    local tt = Shown(92600, true)
    check("T37: a free Other spell gets no block",
        lines == nil and outcome == "no value" and tt:NumLines() == 0,
        string.format("lines=%s outcome=%s shown=%d", tostring(lines), tostring(outcome), tt:NumLines()))
end

do
    -- the macro marker: "- macro" from the source, on a macro's tooltip only
    local head = (SpellTip:Lines(5185, false, "macro") or {})[1] or {}
    local other = (SpellTip:Lines(92501, false, "macro") or {})[1] or {}
    local got = MacroTooltip({ type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } }, nil)
    local spell = Shown(5185, false)
    check("T37: the macro marker",
        head[2] == "Rank 1 of 2 - macro  " .. T.disabled.hex .. "Shift|r" and other[2] == "Rank 2 of 2 - macro"
        and got.lines[2] ~= nil and got.lines[2][2] == head[2]
        and spell.lines[2] ~= nil and tostring(spell.lines[2][2]):find("macro", 1, true) == nil,
        string.format("head=%s other=%s got=%s", tostring(head[2]), tostring(other[2]),
            tostring(got.lines[2] and got.lines[2][2])))
end

do
    -- 5.6: the detail key down while the tooltip is up refreshes it through
    -- the adapter, and the block is rebuilt once, with its detail lines; the
    -- key up puts the plain block back; another key refreshes nothing
    local entry
    for _, c in ipairs(MD.API.Capabilities()) do if c.name == "RefreshTooltip" then entry = c end end
    MD.db.spellTooltipDetail = "SHIFT"
    local plainN = 1 + #SpellTip:Lines(5185, false)
    local detailN = 1 + #SpellTip:Lines(5185, true)
    S.shift = false
    S.ShowSpellTooltip(GameTooltip, 5185)
    local n0 = GameTooltip:NumLines()
    local r0 = GameTooltip.refreshes or 0

    S.shift = true
    S.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    local n1 = GameTooltip:NumLines()
    local heads = Count(GameTooltip.lines, "SpellTuner")
    -- the same showing handed to the post-call again (no clear): nothing added
    Wrapper()(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 5185 })
    local n1b = GameTooltip:NumLines()

    S.shift = false
    S.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    local n2 = GameTooltip:NumLines()
    local r2 = GameTooltip.refreshes or 0

    S.altDown = true
    S.Fire("MODIFIER_STATE_CHANGED", "LALT", 1)
    S.altDown = false
    local r3 = GameTooltip.refreshes or 0

    check("T37: the detail key refreshes the tooltip and the block is rebuilt once",
        entry ~= nil and entry.present == true and n0 == plainN and n1 == detailN and heads == 1
        and n1b == n1 and n2 == plainN and r2 - r0 == 2 and r3 == r2,
        string.format("entry=%s n0=%d n1=%d heads=%d again=%d n2=%d want=%d/%d refreshes=%d,%d",
            tostring(entry and entry.present), n0, n1, heads, n1b, n2, plainN, detailN, r2 - r0, r3 - r2))
end

do
    -- the setting, in Settings -> General: Shift by default, Alt picked
    MD:SelectView("settings", "general")
    local pane
    for _, f in ipairs(S.allFrames) do
        if f.detailDropdown then pane = f end
    end
    local dd = pane and pane.detailDropdown
    local default, picked, hint, altShown, ids = nil, false, nil, nil, {}
    if dd then
        default = dd:Value()
        for i, it in ipairs(dd.items) do
            ids[#ids + 1] = it.id
            if it.id == "ALT" and dd.rows[i] then
                dd.rows[i]:GetScript("OnClick")(dd.rows[i])
                picked = MD.db.spellTooltipDetail == "ALT"
            end
        end
        hint = SpellTip:Lines(5185)[1][2]
        S.altDown = true
        altShown = Shown(5185, false):NumLines()
        S.altDown = false
        MD.db.spellTooltipDetail = "SHIFT"
    end
    check("T37: the detail key is a Settings -> General dropdown",
        dd ~= nil and MD.DEFAULTS.spellTooltipDetail == "SHIFT" and default == "SHIFT" and picked
        and table.concat(ids, ",") == "SHIFT,ALT,CTRL,ALWAYS,NEVER"
        and hint == "Rank 1 of 2  " .. T.disabled.hex .. "Alt|r" and altShown == 1 + #SpellTip:Lines(5185, true),
        string.format("dd=%s default=%s picked=%s ids=%s hint=%s altShown=%s", tostring(dd ~= nil),
            tostring(default), tostring(picked), table.concat(ids, ","), tostring(hint), tostring(altShown)))
end

--------------------------------------------------------------------------------
-- T67 (P23, review A13): Lines answers `lines, outcome`; the outcome is no
-- longer a field any caller overwrites, so a rank-row hover in the Spells
-- pane (which builds the block through Lines) leaves /st tooltip why naming
-- the last macro hover, and SpellTip.lastOutcome is gone
--------------------------------------------------------------------------------
do
    MacroTooltip(S.MacroDataUntyped(424242, 0), nil)
    local why1 = Why()

    -- the rank-row hover: Overview -> Whole book, Healing Touch rank 1
    MD:SelectView("spells", "overview")
    if MD.SpellsPane.SetOverviewMode then MD.SpellsPane:SetOverviewMode("book") end
    local pane
    for _, f in ipairs(S.allFrames) do if f.spellsBook then pane = f end end
    local rowData
    for _, r in ipairs(pane and pane.lastRows or {}) do
        if r.kind == "rank" and r.entry.id == 5185 then rowData = r end
    end
    local rowFrame
    for _, f in ipairs(S.allFrames) do
        if f.cells and rowData and f.data == rowData then rowFrame = f end
    end
    GameTooltip.lines = nil
    local enter = rowFrame and rowFrame:GetScript("OnEnter")
    if enter then enter(rowFrame) end
    local blocks = 0
    for _, line in ipairs(GameTooltip.lines or {}) do if line[1] == "SpellTuner" then blocks = blocks + 1 end end
    local leave = rowFrame and rowFrame:GetScript("OnLeave")
    if leave then leave(rowFrame) end
    local fieldAfterHover = SpellTip.lastOutcome

    local why2 = Why()
    local _, blockOutcome = SpellTip:Lines(5185)
    local _, noIdOutcome = SpellTip:Lines("x")
    local _, notInBook = SpellTip:Lines(424242)
    check("T67: why after a rank-row hover still names the last macro hover",
        enter ~= nil and blocks == 1 and why2 == why1
        and Has(why2, "first line: type 0 id 424242 -> not in book")
        and fieldAfterHover == nil and SpellTip.lastOutcome == nil
        and blockOutcome == "block" and noIdOutcome == "no id"
        and notInBook == "not in book",
        string.format("hovered=%s blocks=%d same=%s lastOutcome=%s outcomes=%s/%s/%s why=%s",
            tostring(enter ~= nil), blocks, tostring(why2 == why1), tostring(fieldAfterHover),
            tostring(blockOutcome), tostring(noIdOutcome), tostring(notInBook), why2))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
