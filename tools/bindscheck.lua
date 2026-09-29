-- tools/run.sh tools/bindscheck.lua
--
-- T19 (docs/tasks/T19-binds-import-check.md): `/st binds check` -- one copy-box
-- report of what the three import sources (the key bindings and the action
-- slots they lead to, Cell's click-castings, Clique's binds) look like on this
-- client, and importers that refuse a shape they do not recognise with a named
-- reason instead of guessing. Forever only. Nothing is imported by the check.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-95s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB

MD:SetModule("SpellTuner_Practice", true)
local PR, SD = MD.Practice, MD.SpellData
assert(PR, "the Practice module did not load")
-- a missing or raising report is a failed check, not a crashed suite
local function Report()
    if type(PR.BindsReport) ~= "function" then return "" end
    local okr, text = pcall(PR.BindsReport)
    if okr and type(text) == "string" then return text end
    print("  (BindsReport raised) " .. tostring(text))
    return ""
end

local function Has(text, plain) return text:find(plain, 1, true) ~= nil end
-- a colour code, a reset, the client's own "|n" and a doubled pipe (Esc's own
-- literal pipe) are safe; anything else left over is BARE
local function BarePipe(str)
    local stripped = str:gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
local function Lines(text)
    local t = {}
    for l in (text .. "\n"):gmatch("(.-)\n") do t[#t + 1] = l end
    return t
end
MD.RankMath:SpellKit({ live = true })   -- builds MD.SpellData from the Forever book (Kit_Forever.lua)
local REJ, HT = SD.maxRank.Rejuvenation, SD.maxRank.HealingTouch
assert(REJ and HT, "the Forever kit has no Rejuvenation / Healing Touch")

--------------------------------------------------------------------------------
-- 2 (first, on a clean world): neither Cell nor Clique, no bindings
--------------------------------------------------------------------------------
_G.CellCharacterDB, _G.Clique, _G.CliqueDB3, _G.CliqueDB = nil, nil, nil, nil
S.bindings, S.actions = {}, {}
local text2 = Report()
local okr = text2 ~= ""
check("with neither Cell nor Clique loaded the report says absent and nothing raises",
    okr and type(text2) == "string"
    and Has(text2, "CellCharacterDB: absent")
    and Has(text2, "Clique: absent")
    and Has(text2, "Clique.db.profile.binds: absent")
    and Has(text2, "CliqueDB3: absent")
    and Has(text2, "not recognised:"),
    text2)

--------------------------------------------------------------------------------
-- 3: a Cell table in the TBC shape is recognised and its first entry shown
--------------------------------------------------------------------------------
S.macros["Main|overtime"] = "#showtooltip\n/cast [@mouseover,help]Rejuvenation"
_G.CellCharacterDB = { clickCastings = {
    useCommon = true, class = "DRUID",
    common = {
        { "type5", "macro", "Main|overtime" },
        { "type1", "spell", REJ },
        { "shift-type1", "spell", HT },
        { "type2", "togglemenu" },
    },
    [1] = { { "type1", "target" } },
} }
local text3 = Report()
local cellSection3 = text3:match("== Cell\n(.-)\n== Clique") or ""
check("a Cell table in the TBC shape is recognised and its first entry shown",
    Has(cellSection3, "CellCharacterDB: table")
    and Has(cellSection3, "clickCastings: table, keys: 1, class, common, useCommon")
    and Has(cellSection3, 'first entry: {"type5", "macro", "Main||overtime"}')
    and Has(cellSection3, "importer: recognised: 3 bindings"),
    cellSection3)

--------------------------------------------------------------------------------
-- 4: a Cell table in an unknown shape is refused, with what was expected and
--    what was found
--------------------------------------------------------------------------------
_G.CellCharacterDB = { clickCastings = {
    useCommon = true,
    common = { { key = "BUTTON1", spell = "Rejuvenation" } },
} }
local list4, rep4 = PR.ImportCell()
rep4 = rep4 or {}
local text4 = Report()
local cellSection4 = text4:match("== Cell\n(.-)\n== Clique") or ""
local err4 = rep4 and rep4.error or ""
-- and a clickCastings that is not a table at all
_G.CellCharacterDB = { clickCastings = "a string" }
local list4b, rep4b = PR.ImportCell()
check("a Cell table in an unknown shape is refused with what was expected and what was found",
    list4 == nil and rep4 and rep4.source == "Cell"
    and Has(err4, "expected") and Has(err4, "found") and Has(err4, "key, spell")
    and Has(cellSection4, "importer: not recognised: " .. err4:gsub("|", "||"))
    and list4b == nil and rep4b and Has(rep4b.error, "expected") and Has(rep4b.error, "string"),
    err4 .. " // " .. tostring(rep4b and rep4b.error))
_G.CellCharacterDB = nil

--------------------------------------------------------------------------------
-- 5: a Clique table in an unknown shape is refused the same way
--------------------------------------------------------------------------------
_G.CliqueDB3 = { profiles = { ["Penek - Spineshatter"] = { binds = {
    { button = "1", action = "heal" },
} } } }
local list5, rep5 = PR.ImportClique()
local text5 = Report()
local cliqueSection5 = text5:match("== Clique\n(.*)$") or ""
local err5 = rep5 and rep5.error or ""
-- the TBC shape still imports (the behaviour the TBC suites hold)
_G.CliqueDB3 = { profiles = { ["Penek - Spineshatter"] = { binds = {
    { key = "BUTTON1", type = "spell", spell = "Rejuvenation" },
    { key = "BUTTON3", type = "target" },
} } } }
local list5b, rep5b = PR.ImportClique()
_G.CliqueDB3 = nil
_G.CliqueDB3 = { profiles = { ["Penek - Spineshatter"] = { binds = { { button = "1", action = "heal" } } } } }
check("a Clique table in an unknown shape is refused the same way",
    list5 == nil and rep5 and rep5.source == "Clique"
    and Has(err5, "expected") and Has(err5, "found") and Has(err5, "action, button")
    and Has(cliqueSection5, "CliqueDB3: table")
    and Has(cliqueSection5, "importer: not recognised: " .. err5:gsub("|", "||"))
    and list5b and rep5b.added == 1,
    err5)
_G.CliqueDB3 = nil

--------------------------------------------------------------------------------
-- 6: the keybinding section shows the first rows whole and counts what resolved
--------------------------------------------------------------------------------
S.macros["Heal M"] = "/cast [@mouseover,help] Rejuvenation"
S.macroOrder[1] = "Heal M"
S.bindings = {
    { "ACTIONBUTTON1", "1", "SHIFT-1" },
    { "ACTIONBUTTON2", "2" },
    { "MULTIACTIONBAR1BUTTON1", "Q" },
    { "TOGGLEBACKPACK", "B" },
    { "TARGETSELF", "F1" },
    { "MOVEFORWARD", "W" },
}
S.actions = { [1] = { "spell", REJ }, [2] = { "macro", 1 } }
local text6 = Report()
local kb6 = text6:match("== keybindings\n(.-)\n== Cell") or ""
local firstResolved = kb6:match("first 10 resolved:[^\n]*\n(.-)\nimporter:") or ""
check("the keybinding section shows the first rows whole and counts what resolved",
    Has(kb6, "count: 6")
    and Has(kb6, 'binding 1 = "ACTIONBUTTON1", "1", "SHIFT-1"')
    and Has(kb6, "binding 5 = ") and not Has(kb6, "binding 6 = ")
    and Has(kb6, "bound: 7 keys; resolved to a slot: 4; to a spell: 2; to a macro: 1")
    and Has(firstResolved, "1 -> ACTIONBUTTON1 -> slot 1 -> spell " .. REJ)
    and Has(firstResolved, "2 -> ACTIONBUTTON2 -> slot 2 -> macro")
    and Has(kb6, "importer: 3 bindings imported, 0 skipped"),
    kb6)

--------------------------------------------------------------------------------
-- 1: the report has the three sections in order, ASCII, no bare pipe -- also
--    with awkward bytes in every source, and through the command
--------------------------------------------------------------------------------
S.bindings[#S.bindings + 1] = { "CLICK Weird|Frame\200:LeftButton", "P|ipe" }
_G.CellCharacterDB = { clickCastings = { useCommon = true, common = { { "type5", "macro", "M\195\169|x" } } } }
_G.CliqueDB3 = { profiles = { p = { binds = { { key = "B|1", type = "spell", spell = "Reju\200" } } } } }
local text1 = Report()
local iH = text1:find("=== SpellTuner binds check", 1, true)
local iK = text1:find("\n== keybindings\n", 1, true)
local iC = text1:find("\n== Cell\n", 1, true)
local iQ = text1:find("\n== Clique\n", 1, true)
local nonAscii = text1:find("[^ -~\n]") ~= nil
-- the command hands it to the copy box
local shown
local origPopup = MD.ShowCopyPopup
MD.ShowCopyPopup = function(_, title, body) shown = { title = title, body = body } end
SlashCmdList.SPELLTUNER("binds check")
MD.ShowCopyPopup = origPopup
check("the report has the three sections in order, ASCII, with no bare pipe",
    iH == 1 and iK and iC and iQ and iK < iC and iC < iQ
    and Has(text1, "build 70009")
    and not nonAscii and not BarePipe(text1)
    and shown and shown.title == "SpellTuner binds check" and type(shown.body) == "string"
    and shown.body:sub(1, 26) == "=== SpellTuner binds check",
    "iH=" .. tostring(iH) .. " nonAscii=" .. tostring(nonAscii) .. " bare=" .. tostring(BarePipe(text1))
    .. " popup=" .. tostring(shown and shown.title))

-- the report is what a reader pastes: show it once, for the log
print("\n----- report -----\n" .. text1 .. "\n----- end -----")
print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
