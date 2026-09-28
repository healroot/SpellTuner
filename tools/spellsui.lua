-- tools/run.sh tools/spellsui.lua
--
-- T10 (docs/tasks/T10-spells-pane.md): the Spells -> Spellbook pane
-- (UI/Dashboard_Forever.lua) on UI/Dashboard_Rows.lua's now-shared table
-- widget. Forever only.
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

--------------------------------------------------------------------------------
-- fixtures -- named for which acceptance item they exercise. The four fixed
-- slots (5185 Healing Touch R1, 774/1058 Rejuvenation R1/R2, 5176 Wrath R1)
-- are already in the stub (tools/wowstub.lua); Rejuvenation R2 dominates R1
-- and is the family's suggested rank (T7's own scan, docs/tasks/T7-spell-book.md
-- Report), which item 3 relies on directly rather than re-deriving it.
--------------------------------------------------------------------------------

-- item 4: a third Healing Touch rank whose text carries no heal numbers at
-- all -- Book's own PartValue returns nil,nil for it, so value/per mana/per
-- second/casts must render "-", never 0, even though the family's kind is
-- still "heal" (from rank 1).
S.AddSpell(92003, "Healing Touch", "Rank 3",
    function() return "This rank requires no reagent." end,
    { cast = 0, cost = 10, level = 20 })

-- item 5: a family listed from rank 2 only (a gap) -- shares tools/bookcheck.lua's
-- own construction.
S.AddSpell(92011, "GapFamily", "Rank 2",
    function() return "Heals a friendly target for 40 to 50." end,
    { cast = 0, cost = 25, level = 10 })

-- item 1/Other section: a family with no heal/damage/absorb numbers at all.
S.AddSpell(92100, "Bearform", "Passive",
    function() return "You transform into a bear, increasing armor." end,
    { cast = 0, noCost = true, level = 10 })

-- item 6: a spell costly enough that the chain-cast interval does NOT let
-- regen alone cover it (Engine/RankMath.lua's CastsToOOM: "inf" whenever
-- regen*interval >= cost, no matter how little mana is left, which is why
-- the cheap fixtures above -- and the real Healing Touch/Wrath fixtures --
-- all read "inf" against either pool and cannot show the pool ever mattered).
-- 300 mana vs. this stub's out-of-combat casting rate (28.33) * a 1.5s
-- interval = 42.5 leaves a strictly positive net, so the current pool decides
-- a finite answer.
S.AddSpell(92050, "BigSpell", "Rank 1",
    function() return "Heals a friendly target for 90 to 110." end,
    { cast = 1500, cost = 300, level = 1 })

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function Num(v, decimals)
    if type(v) ~= "number" or v ~= v then return "-" end
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

local function ManaText(e)
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. "%" end
    end
    return "-"
end

local function CastText(e)
    if e.castKind == "instant" then return "inst" end
    if e.castKind == "channeled" then return "chan" end
    if type(e.cast) == "number" then return Num(e.cast, 1) .. "s" end
    return "-"
end

local function ToOOMText(e)
    if e.casts == math.huge then return "inf" end
    if type(e.casts) == "number" then return Num(e.casts, 0) end
    return "-"
end

local function NoteText(e, family)
    if e.known == false then return "not learned" end
    if e.dominated then return "dominated" end
    if family and family.maxKnown == e then return "max rank" end
    return ""
end

local function StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- UI/Style.lua's own header close button ("x", U+00D7, line 166) -- shared by
-- every Cell-style window in the tree and already an accepted, named
-- exception in tools/modulecheck.lua's own ASCII walk (Review, 2026-09-28).
local CLOSE_GLYPH = "\195\151"

local function AsciiNoBarePipe(text)
    if text == CLOSE_GLYPH then return true end
    for i = 1, #text do
        if text:byte(i) > 126 then return false, "non-ascii" end
    end
    local stripped = text:gsub("||", "")
    stripped = stripped:gsub("|c%x%x%x%x%x%x%x%x", "")
    stripped = stripped:gsub("|r", "")
    if stripped:find("|") then return false, "bare pipe" end
    return true
end

-- The pane is the frame UI/Dashboard_Forever.lua marks with .spellsBook, the
-- same convention modulecheck's placeholder-era fixture used.
local function FindPane()
    for _, f in ipairs(S.allFrames) do
        if f.spellsBook then return f end
    end
    return nil
end

-- The row frame CreateTable built for one row descriptor `r` -- table
-- identity, since row.data IS the very same table Render() was handed
-- (UI/Dashboard_Rows.lua's generic branch), never a copy.
local function RowFor(rows, r)
    for _, f in ipairs(S.allFrames) do
        if f.cells and f.data == r then return f end
    end
    return nil
end

local function CellText(row, key)
    local fs = row and row.cells and row.cells[key]
    return fs and StripColor(fs:GetText() or "") or nil
end

local function OpenPane()
    MD:SelectView("spells", "book")
    return FindPane()
end

local function FamilyRow(rows, name)
    for _, r in ipairs(rows or {}) do
        if r.kind == "family" and r.family.name == name then return r end
    end
    return nil
end
local function EntryRow(rows, id)
    for _, r in ipairs(rows or {}) do
        if r.kind == "entry" and r.entry.id == id then return r end
    end
    return nil
end
local function NoteRow(rows, substring)
    for _, r in ipairs(rows or {}) do
        if r.kind == "note" and r.text:find(substring, 1, true) then return r end
    end
    return nil
end

local function IndexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return nil
end

local pane = OpenPane()
if not pane then error("spellsui: no .spellsBook pane found -- fixture/build is broken, not one of the 11 acceptance items") end

--------------------------------------------------------------------------------
-- 1: the Spellbook view lists every family of the book, heals then damage
-- then other
--------------------------------------------------------------------------------
-- Heals/Damage families get a "family" row; a kindless family (Other) gets
-- one "other" line instead (Goal) -- both counted, in the same flat order.
local sectionOrder = {}
for _, r in ipairs(pane.lastRows or {}) do
    if r.kind == "family" then
        sectionOrder[#sectionOrder + 1] = r.family.name
    elseif r.kind == "other" then
        sectionOrder[#sectionOrder + 1] = r.text:match("^(%S+)")
    end
end
do
    local iHT, iRejuv = IndexOf(sectionOrder, "Healing Touch"), IndexOf(sectionOrder, "Rejuvenation")
    local iWrath = IndexOf(sectionOrder, "Wrath")
    local iBear = IndexOf(sectionOrder, "Bearform")
    local order = iHT ~= nil and iRejuv ~= nil and iWrath ~= nil and iBear ~= nil
        and iHT < iRejuv and iRejuv < iWrath and iWrath < iBear

    check("the Spellbook view lists every family of the book, heals then damage then other",
        order == true, "order=" .. table.concat(sectionOrder, ", "))
end

--------------------------------------------------------------------------------
-- 2: each rank row shows the book's own numbers
--------------------------------------------------------------------------------
do
    local bad
    local checked = 0
    for _, r in ipairs(pane.lastRows or {}) do
        if r.kind == "entry" then
            local e = r.entry
            local row = RowFor(pane.lastRows, r)
            if not row then
                bad = bad or ("no row frame for id " .. tostring(e.id))
            else
                checked = checked + 1
                local wantRank = e.rank and ("R" .. e.rank) or "-"
                if e.suggested then wantRank = wantRank .. " *" end
                local expect = {
                    { "rank", wantRank }, { "level", Num(e.level) }, { "mana", ManaText(e) },
                    { "value", Num(e.value) }, { "permana", Num(e.perMana, 2) }, { "persec", Num(e.perSec, 1) },
                    { "cast", CastText(e) }, { "toOOM", ToOOMText(e) }, { "note", NoteText(e, r.family) },
                }
                for _, p in ipairs(expect) do
                    local key, want = p[1], p[2]
                    local got = CellText(row, key)
                    if got ~= want and not bad then
                        bad = string.format("id=%s col=%s got=%q want=%q", tostring(e.id), key, tostring(got), tostring(want))
                    end
                end
            end
        end
    end
    check("each rank row shows the book's own numbers", bad == nil and checked > 0,
        bad or ("checked=" .. checked))
end

--------------------------------------------------------------------------------
-- 3: the suggested rank is starred and named in its family's header
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local rejuv = book.families["Rejuvenation"]
    local r2 = book.spells[1058]

    local headerRow = RowFor(pane.lastRows, FamilyRow(pane.lastRows, "Rejuvenation"))
    local headerText = CellText(headerRow, "rank")

    local r2Row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 1058))
    local r2RankCell = CellText(r2Row, "rank")

    check("the suggested rank is starred and named in its family's header",
        rejuv.suggested == r2 and r2.suggested == true
        and headerText ~= nil and headerText:find("suggested: Rank 2", 1, true) ~= nil
        and r2RankCell ~= nil and r2RankCell:find("%*") ~= nil,
        string.format("suggestedId=%s header=%q rankCell=%q",
            tostring(rejuv.suggested and rejuv.suggested.id), tostring(headerText), tostring(r2RankCell)))
end

--------------------------------------------------------------------------------
-- 4: a number the book does not have is a dash, never a zero
--------------------------------------------------------------------------------
do
    -- Healing Touch Rank 3 (92003) has no heal numbers in its own text
    -- (PartValue reads nil,nil for it -- Spells/Book.lua), so value/per
    -- mana/per second have nothing to be computed from. Casts to OOM stays
    -- OUT of this check: it is a function of cost/interval/pool alone
    -- (Spells/Book.lua's CastsToOOM), never of `value`, so a rank with no
    -- amount can still legitimately answer "inf" there -- that is not this
    -- rule's zero-vs-dash question.
    local book = Book:Get()
    local e = book.spells[92003]
    local row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 92003))
    local valueCell, permanaCell, persecCell = CellText(row, "value"), CellText(row, "permana"), CellText(row, "persec")

    check("a number the book does not have is a dash, never a zero",
        e.value == nil and e.perMana == nil and e.perSec == nil
        and valueCell == "-" and permanaCell == "-" and persecCell == "-",
        string.format("value=%s permana=%s persec=%s", tostring(valueCell), tostring(permanaCell), tostring(persecCell)))
end

--------------------------------------------------------------------------------
-- 5: gaps and stale values are noted under the family
--------------------------------------------------------------------------------
do
    local gapNote = NoteRow(pane.lastRows, "not listed")
    local gapGood = gapNote ~= nil
        and gapNote.text == "Rank 1 not listed (untrained, or hidden - show all ranks)"

    -- the stale value: 5185's description goes secret in combat (tools/wowstub.lua),
    -- the same mechanic tools/tipcheck.lua's own stale test uses.
    S.inCombat = false
    Book:MarkDirty(); Book:Get()
    S.inCombat = true
    Book:MarkDirty(); Book:Get()
    S.inCombat = false

    local pane2 = OpenPane()
    local staleNote = NoteRow(pane2.lastRows, "values read before combat")

    check("gaps and stale values are noted under the family",
        gapGood and staleNote ~= nil,
        string.format("gap=%s stale=%s", tostring(gapNote and gapNote.text), tostring(staleNote and staleNote.text)))

    Book:MarkDirty(); Book:Get()
    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 6: casts to OOM use the clock's modelled pool when there is one
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local defaultPool = Book:DefaultPool()
    Book:Rows(book.families["BigSpell"], defaultPool)
    local defaultCasts = book.spells[92050].casts -- against the DEFAULT pool (pool.max = 7009, no drain)

    -- drain the clock's own modelled pool below BigSpell's cost (300) --
    -- the default pool would never do this.
    MD.Clock.model:Anchor(GetTime(), 5, "test: drained for spellsui")
    local pane3 = OpenPane()
    local afterEntry = Book:Get().spells[92050]

    check("casts to OOM use the clock's modelled pool when there is one",
        type(defaultCasts) == "number" and defaultCasts > 0 and defaultCasts ~= math.huge and afterEntry.casts == 0,
        string.format("defaultPoolCasts=%s clockPoolCasts=%s",
            tostring(defaultCasts), tostring(afterEntry.casts)))

    -- restore a full modelled pool so nothing after this item is affected.
    MD.Clock.model:Anchor(GetTime(), MD.Clock.model.max, "test: restored")
    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 7: hovering a row shows the spell's tooltip block
--------------------------------------------------------------------------------
do
    local row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 5185))
    local enter = row and row:GetScript("OnEnter")
    local before = GameTooltip:NumLines()
    if enter then enter(row) end
    local after = GameTooltip:NumLines()

    local expected = MD.SpellTip:Lines(5185)
    check("hovering a row shows the spell's tooltip block",
        row ~= nil and after > before and after == #expected,
        string.format("before=%d after=%d expected=%d", before, after, #expected))

    local leave = row and row:GetScript("OnLeave")
    if leave then leave(row) end
end

--------------------------------------------------------------------------------
-- 8: the export is the probe's block format with cost, cast and level
--------------------------------------------------------------------------------
local exportText
do
    local captured
    local origShow = MD.ShowCopyPopup
    MD.ShowCopyPopup = function(self, title, text) captured = { title = title, text = text } end
    pane.exportBtn:GetScript("OnClick")(pane.exportBtn)
    MD.ShowCopyPopup = origShow

    exportText = captured and captured.text
    local hasCharLine = exportText ~= nil and exportText:find("^character: %S+ %S+ %S+ level %d+") ~= nil
    local hasSection = exportText ~= nil and exportText:find("\n== spells\n", 1, true) ~= nil
    local hasSpellBlock = exportText ~= nil
        and exportText:find("spell 5185\n  name: Healing Touch\n  rank: Rank 1\n  desc: ", 1, true) ~= nil
    local hasCostCastLevel = exportText ~= nil
        and exportText:find("\n  cost: 25 Mana\n", 1, true) ~= nil
        and exportText:find("\n  cast: 1.5 sec cast\n", 1, true) ~= nil
        and exportText:find("\n  level: 1", 1, true) ~= nil

    -- python3 tools/refcheck.py <export> --data tools/data/refcheck-fixture/data.json
    -- (Acceptance: run with os.execute only if python3 is on PATH, else a
    -- printed skip -- folded into this one item's own condition rather than a
    -- twelfth named assertion).
    local refcheckOk = true
    local hasPython = os.execute("command -v python3 >/dev/null 2>&1")
    if hasPython == true or hasPython == 0 then
        local root = S.root or "."
        local path = root .. "/.spellsui-export.tmp.txt"
        local f = io.open(path, "w")
        f:write(exportText or "")
        f:close()
        local cmd = string.format('python3 "%s/tools/refcheck.py" "%s" --data "%s/tools/data/refcheck-fixture/data.json" >/dev/null 2>&1',
            root, path, root)
        local rc = os.execute(cmd)
        os.remove(path)
        refcheckOk = (rc == true or rc == 0)
    else
        print("  (skip: python3 not on PATH -- refcheck.py not run)")
    end

    check("the export is the probe's block format with cost, cast and level",
        captured ~= nil and captured.title == "SpellTuner spellbook"
        and hasCharLine and hasSection and hasSpellBlock and hasCostCastLevel and refcheckOk,
        string.format("hasCharLine=%s hasSection=%s hasSpellBlock=%s hasCostCastLevel=%s refcheckOk=%s",
            tostring(hasCharLine), tostring(hasSection), tostring(hasSpellBlock), tostring(hasCostCastLevel), tostring(refcheckOk)))
end

--------------------------------------------------------------------------------
-- 9: the pane refreshes on show and every two seconds while shown, not while
-- hidden
--------------------------------------------------------------------------------
do
    pane = OpenPane() -- OnShow already refreshed it once
    local afterShow = pane.refreshCount

    for _ = 1, 3 do S.Tick(0.5) end -- 1.5s: not yet due
    local before2s = pane.refreshCount

    S.Tick(0.5) -- crosses 2s
    local after2s = pane.refreshCount

    -- hide the window (select another group) -- the ticker must not refresh
    -- a hidden pane.
    MD:SelectView("settings", "modules")
    for _ = 1, 8 do S.Tick(0.5) end -- 4s while hidden
    local whileHidden = pane.refreshCount

    check("the pane refreshes on show and every two seconds while shown, not while hidden",
        afterShow >= 1 and before2s == afterShow and after2s == afterShow + 1 and whileHidden == after2s,
        string.format("afterShow=%d before2s=%d after2s=%d whileHidden=%d",
            afterShow, before2s, after2s, whileHidden))

    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 10: no module beyond core is loaded to draw it
--------------------------------------------------------------------------------
check("no module beyond core is loaded to draw it", #S.loadAddOnCalls == 0,
    "#loadAddOnCalls=" .. #S.loadAddOnCalls)

--------------------------------------------------------------------------------
-- 11: every string the pane renders or exports is ASCII with no bare pipe
--------------------------------------------------------------------------------
do
    local bad
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText()
        if type(t) == "string" and t ~= "" and not bad then
            local good, why = AsciiNoBarePipe(t)
            if not good then bad = why .. " in painted '" .. t .. "'" end
        end
    end
    if not bad and exportText then
        local good, why = AsciiNoBarePipe(exportText)
        if not good then bad = why .. " in the export" end
    end
    check("every string the pane renders or exports is ASCII with no bare pipe", bad == nil, bad)
end

--------------------------------------------------------------------------------
-- 12 (T10b): each non-empty section has a title row before its first family,
-- and an empty one has none
--------------------------------------------------------------------------------
do
    pane = OpenPane()
    local rows = pane.lastRows or {}
    local sectionIdx, familyIdx, otherIdx = {}, {}, nil
    for i, r in ipairs(rows) do
        if r.kind == "section" then sectionIdx[r.text] = sectionIdx[r.text] or i end
        if r.kind == "family" and not familyIdx[1] then familyIdx[1] = { i, r.family.name } end
        if r.kind == "family" and r.family.name == "Wrath" and not familyIdx[2] then familyIdx[2] = { i, r.family.name } end
        if r.kind == "other" and not otherIdx then otherIdx = i end
    end

    -- this fixture book has no Damage-kind family with a "damage" kind row
    -- that isn't Wrath, so "Heals" precedes the first heal family and
    -- "Damage" precedes Wrath; both are non-empty here, and "Other" precedes
    -- the first "other" line (Bearform).
    local heals = sectionIdx["Heals"]
    local damage = sectionIdx["Damage"]
    local other = sectionIdx["Other"]
    local ok12 = heals ~= nil and damage ~= nil and other ~= nil
        and heals < familyIdx[1][1]
        and damage < familyIdx[2][1]
        and other < otherIdx

    -- an empty section has none: strip Wrath's kind so the book has no
    -- damage-kind family left, refresh, and check "Damage" is absent.
    local book = MD.Book:Get()
    local wrath = book.families["Wrath"]
    local savedKind = wrath.kind
    wrath.kind = nil
    local pane2 = OpenPane()
    local hasDamageSection = false
    for _, r in ipairs(pane2.lastRows or {}) do
        if r.kind == "section" and r.text == "Damage" then hasDamageSection = true end
    end
    wrath.kind = savedKind
    OpenPane() -- restore the real book's rows for anything after this

    check("each non-empty section has a title row before its first family, and an empty one has none",
        ok12 and not hasDamageSection,
        string.format("heals=%s damage=%s other=%s firstFamily=%d wrath=%d firstOther=%s emptyDamageAbsent=%s",
            tostring(heals), tostring(damage), tostring(other), familyIdx[1][1], familyIdx[2][1], tostring(otherIdx),
            tostring(not hasDamageSection)))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
