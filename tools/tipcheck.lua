-- tools/run.sh tools/tipcheck.lua
--
-- T9 (docs/tasks/T9-spell-tooltip.md): the SpellTuner block on every spell
-- tooltip (UI/SpellTip_Forever.lua) through Client/API_Forever.lua's
-- MD.API.OnSpellTooltip and the stub's TooltipDataProcessor. Forever only.
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
-- 3: every number in the block is the book's
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local htR1 = book.spells[5185]
    local lines = SpellTip:Lines(5185)

    local valueLine = lines[2]
    local avgGood = valueLine[2] == "avg " .. tostring(math.floor(htR1.value + 0.5))

    local critLine = FindLine(lines, "Crit ")
    local critGood = critLine ~= nil
        and critLine[1] == string.format("Crit %d - %d",
            math.floor(htR1.min * 1.5 + 0.5), math.floor(htR1.max * 1.5 + 0.5))

    local perManaLine = FindLine(lines, "Per mana")
    local perManaGood = perManaLine ~= nil and perManaLine[2] == string.format("%.2f", htR1.perMana)

    local perSecLine = FindLine(lines, "Per second")
    local perSecGood = perSecLine ~= nil
        and perSecLine[2] == string.format("%.1f (%.1f sec cast)", htR1.perSec, htR1.interval)

    local castsLine = FindLine(lines, "Casts to OOM")
    local expectCasts
    if htR1.casts == math.huge then expectCasts = "inf"
    else expectCasts = tostring(math.floor(htR1.casts + 0.5)) end
    local castsGood = castsLine ~= nil and castsLine[2] == expectCasts

    check("every number in the block is the book's",
        avgGood and critGood and perManaGood and perSecGood and castsGood,
        string.format("avg=%s crit=%s perMana=%s perSec=%s casts=%s",
            tostring(avgGood), tostring(critGood), tostring(perManaGood), tostring(perSecGood), tostring(castsGood)))
end

--------------------------------------------------------------------------------
-- 4: a lower rank is compared with the highest known
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local htR1, htR2 = book.spells[5185], book.spells[92002]
    local lines = SpellTip:Lines(5185)
    local vsLine = FindLine(lines, "vs Rank")

    local expectedValueRatio = htR1.value / htR2.value
    local expectedCostRatio = htR1.cost.amount / htR2.cost.amount
    local expectedRight = string.format("%.2fx the heal for %.2fx the mana", expectedValueRatio, expectedCostRatio)

    -- the max rank itself carries no "vs Rank" line.
    local maxLines = SpellTip:Lines(92002)
    local maxHasVs = FindLine(maxLines, "vs Rank") ~= nil

    check("a lower rank is compared with the highest known",
        vsLine ~= nil and vsLine[1] == "vs Rank 2" and vsLine[2] == expectedRight and not maxHasVs,
        string.format("vsLine=%s maxHasVs=%s", vsLine and (vsLine[1] .. " / " .. vsLine[2]) or "nil", tostring(maxHasVs)))
end

--------------------------------------------------------------------------------
-- 5: the suggested rank is named on itself and on the others
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local sub1, sub2 = book.spells[92070], book.spells[92071]
    -- SubFamily: R1 is far more mana-efficient and still worth >= 40% of R2's
    -- value, so R1 (not the max rank) is suggested (tools/bookcheck.lua item 7).
    local suggestedIsR1 = sub1.suggested == true and sub2.suggested ~= true

    local r1Lines = SpellTip:Lines(92070)
    local r2Lines = SpellTip:Lines(92071)
    local onItself = FindLine(r1Lines, "Suggested rank") ~= nil
    local onTheOther = FindLine(r2Lines, "Suggested: Rank 1")
    local onTheOtherGood = onTheOther ~= nil
        and onTheOther[2] == string.format("%.2f per mana", sub1.perMana)

    check("the suggested rank is named on itself and on the others",
        suggestedIsR1 and onItself and onTheOtherGood,
        string.format("suggestedIsR1=%s onItself=%s onTheOther=%s",
            tostring(suggestedIsR1), tostring(onItself), onTheOther and onTheOther[2] or "nil"))
end

--------------------------------------------------------------------------------
-- 6: a rank the book does not list is named
--------------------------------------------------------------------------------
do
    local lines = SpellTip:Lines(92010)
    local gapLine = FindLine(lines, "not listed")
    check("a rank the book does not list is named",
        gapLine ~= nil and gapLine[1] == "Rank 1 not listed (untrained, or hidden - show all ranks)",
        gapLine and gapLine[1] or "no gap line")
end

--------------------------------------------------------------------------------
-- 7: a spell not in the book still gets its own numbers
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local notInBook = book.spells[92060] == nil
    local lines = SpellTip:Lines(92060)
    local valueLine = lines and lines[2]
    local hasNoFamilyLines = lines ~= nil
        and FindLine(lines, "vs Rank") == nil
        and FindLine(lines, "Suggested") == nil
        and FindLine(lines, "not listed") == nil

    check("a spell not in the book still gets its own numbers",
        notInBook and lines ~= nil and valueLine ~= nil
        and valueLine[1] == "Heals 60 - 80" and hasNoFamilyLines,
        string.format("notInBook=%s valueLine=%s hasNoFamilyLines=%s",
            tostring(notInBook), valueLine and valueLine[1] or "nil", tostring(hasNoFamilyLines)))
end

--------------------------------------------------------------------------------
-- 8: a spell with no amount gets no block
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
-- 10: values read before combat say so
--------------------------------------------------------------------------------
do
    S.inCombat = false
    Book:MarkDirty()
    Book:Get() -- an ok, non-stale read of 5185

    S.inCombat = true
    Book:MarkDirty()
    Book:Get() -- 5185's description goes secret; the stale value is kept
    S.inCombat = false

    local lines = SpellTip:Lines(5185)
    local staleLine = FindLine(lines, "Read before combat")
    check("values read before combat say so", staleLine ~= nil, staleLine and staleLine[1] or "no stale line")

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
-- 12: every line is ASCII with no bare pipe
--------------------------------------------------------------------------------
do
    local ids = { 5185, 92002, 92070, 92071, 92010, 92060, 774 }
    local bad
    for _, id in ipairs(ids) do
        local lines = SpellTip:Lines(id)
        for _, text in ipairs(AllText(lines)) do
            local good, why = AsciiNoBarePipe(text)
            if not good and not bad then bad = why .. " in '" .. text .. "' (id " .. id .. ")" end
        end
    end
    check("every line is ASCII with no bare pipe", bad == nil, bad)
end

--------------------------------------------------------------------------------
-- 13 (T10): the per-second line names its interval by kind
--------------------------------------------------------------------------------
do
    local book = Book:Get()

    local castLine = FindLine(SpellTip:Lines(5185), "Per second")
    local castGood = castLine ~= nil and castLine[2]:find(" sec cast)", 1, true) ~= nil

    local instantEntry = book.spells[92080]
    local instantLine = FindLine(SpellTip:Lines(92080), "Per second")
    local instantGood = instantEntry ~= nil and instantEntry.castKind == "instant"
        and instantLine ~= nil and instantLine[2] == string.format("%.1f (%.1f sec GCD)",
            instantEntry.perSec, instantEntry.interval)

    local overEntry = book.spells[774]
    local overLine = FindLine(SpellTip:Lines(774), "Per second")
    local overGood = overEntry ~= nil and overEntry.min == nil and overEntry.max == nil
        and overLine ~= nil and overLine[2] == string.format("%.1f (over %d sec)",
            overEntry.perSec, math.floor(overEntry.interval + 0.5))

    local chanEntry = book.spells[92090]
    local chanLine = FindLine(SpellTip:Lines(92090), "Per second")
    local chanGood = chanEntry ~= nil and chanEntry.castKind == "channeled"
        and chanLine ~= nil and chanLine[2] == string.format("%.1f (%d sec channel)",
            chanEntry.perSec, math.floor(chanEntry.interval + 0.5))

    check("the per-second line names its interval by kind",
        castGood and instantGood and overGood and chanGood,
        string.format("cast=%s instant=%s over=%s channel=%s",
            castLine and castLine[2] or "nil", instantLine and instantLine[2] or "nil",
            overLine and overLine[2] or "nil", chanLine and chanLine[2] or "nil"))
end

--------------------------------------------------------------------------------
-- 14 (T10b): an absorb's per-second line names a cast or the GCD, never over
--------------------------------------------------------------------------------
do
    local book = Book:Get()

    local absInstantEntry = book.spells[92095]
    local absInstantLine = FindLine(SpellTip:Lines(92095), "Per second")
    local absInstantGood = absInstantEntry ~= nil and absInstantEntry.min == nil and absInstantEntry.max == nil
        and absInstantEntry.castKind == "instant"
        and absInstantLine ~= nil and absInstantLine[2]:find(" sec GCD)", 1, true) ~= nil
        and absInstantLine[2]:find("over", 1, true) == nil

    local absCastEntry = book.spells[92096]
    local absCastLine = FindLine(SpellTip:Lines(92096), "Per second")
    local absCastGood = absCastEntry ~= nil and absCastEntry.min == nil and absCastEntry.max == nil
        and absCastEntry.castKind == "cast"
        and absCastLine ~= nil and absCastLine[2]:find(" sec cast)", 1, true) ~= nil
        and absCastLine[2]:find("over", 1, true) == nil

    check("an absorb's per-second line names a cast or the GCD, never over",
        absInstantGood and absCastGood,
        string.format("instant=%s cast=%s",
            absInstantLine and absInstantLine[2] or "nil", absCastLine and absCastLine[2] or "nil"))
end

--------------------------------------------------------------------------------
-- 15 (review R31): casts to OOM says it counts from a full pool, and does --
-- whatever another pool has been counted against on the side
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local htR1 = book.spells[5185]
    local fromFull = Book:CastsFor(htR1, Book:DefaultPool())
    Book:CastsFor(htR1, { max = 1000, mana = 5, regenCasting = 0 }) -- a drained pool, counted on the side
    local line = FindLine(SpellTip:Lines(5185), "Casts to OOM")
    local want = (fromFull == math.huge) and "inf" or tostring(fromFull)
    check("casts to OOM says it counts from a full pool, and does",
        line ~= nil and line[1] == "Casts to OOM from full" and line[2] == want,
        string.format("line=%s / %s want=%s", tostring(line and line[1]), tostring(line and line[2]), want))
end

--------------------------------------------------------------------------------
-- 16 (review R42): the crit range says its 1.5x multiplier is assumed --
-- Forever's own crit rule is UNVERIFIED (docs/REFERENCES-FOREVER.md sec4)
--------------------------------------------------------------------------------
do
    local critLine = FindLine(SpellTip:Lines(5185), "Crit ")
    check("the crit range says its 1.5x multiplier is assumed",
        critLine ~= nil and critLine[2] == "1.5x, unverified",
        string.format("crit=%s / %s", tostring(critLine and critLine[1]), tostring(critLine and critLine[2])))
end

--------------------------------------------------------------------------------
-- 17 (review R13): a Rage cost reads as no mana, named, never as a per-mana
-- number. Text and cost line: talentsforever's beta client 1.60.1.70009.
--------------------------------------------------------------------------------
do
    S.AddSpell(92300, "Rend", "Rank 1",
        function() return "Wounds the target causing them to bleed for 15 damage over 9 sec." end,
        { cast = 0, level = 4, costLine = "10 Rage",
          costList = { { type = 1, name = "RAGE", cost = 10, minCost = 10, costPercent = 0, costPerSec = 0,
                         requiredAuraID = 0, hasRequiredAura = false } } })
    Book:MarkDirty()
    local lines = SpellTip:Lines(92300)
    local perMana = FindLine(lines, "Per mana")
    local casts = FindLine(lines, "Casts to OOM")
    check("a Rage cost reads as no mana on the tooltip, named",
        perMana ~= nil and perMana[2] == "no mana (10 Rage)" and casts ~= nil and casts[2] == "-",
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
local function SpellBlock(id)
    local tt = CreateFrame("GameTooltip")
    S.ShowSpellTooltip(tt, id)
    return tt
end
local function MacroTooltip(data, owner)
    local tt = CreateFrame("GameTooltip")
    S.ShowMacroTooltip(tt, data, owner)
    return tt
end

do
    local want = SpellBlock(5185)
    local got = MacroTooltip({ type = MACRO, lines = { { tooltipType = 1, tooltipID = 5185 } } }, nil)
    check("a macro's tooltip gets its spell's block, from the tooltip data",
        SameLines(got, want), string.format("got=%d want=%d", got:NumLines(), want:NumLines()))
end

do
    local want = SpellBlock(5185)
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

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
