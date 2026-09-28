-- tools/run.sh --flavour forever tools/svcheck.lua
-- tools/run.sh --flavour tbc     tools/svcheck.lua
--
-- T4: the SavedVariables guard (Core_Forever.lua). Each acceptance point is a
-- fresh dofile of tools/harness.lua (which re-dofiles tools/wowstub.lua too),
-- with SpellTunerDB set in _G BEFORE the dofile -- the way the client hands
-- the file back at ADDON_LOADED -- so every case is an honest fresh load, not
-- state left over from the previous one.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function try(name, body)
    local runOk, err = pcall(body)
    if not runOk then check(name, false, "raised: " .. tostring(err)) end
end

-- A fresh SpellTuner + fresh stub, exactly as a fresh login would see it.
-- presetDB (may be nil, a table or a non-table) becomes SpellTunerDB BEFORE
-- ADDON_LOADED fires -- harness.lua fires ADDON_LOADED/PLAYER_LOGIN/
-- PLAYER_ENTERING_WORLD itself, synchronously, inside this dofile.
local function NewSession(presetDB)
    _G.SpellTunerDB = presetDB
    _G.ManaDemonDB = nil
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    return MD
end

local envFlavour = os.getenv("ST_FLAVOUR")
local flavour = (envFlavour ~= nil and envFlavour ~= "") and envFlavour or "forever"

if flavour == "forever" then

-- 1: a first run
try("a first run says nothing came back and stamps session 1", function()
    local MD = NewSession(nil)
    check("a first run says nothing came back and stamps session 1",
        MD.sv.atLoad == "nil"
        and MD:SavedVarsLine() == "SavedVariables: none at load (a first run, or the client did not read the file back)"
        and _G.SpellTunerDB.session.count == 1
        and type(_G.SpellTunerDB.session.stamp) == "string")
end)

-- 2: a returning database
try("a returning database names the previous session and keeps everything else", function()
    local charTbl = { ["Penek-Anniversary"] = { x = 1 } }
    local modulesTbl = { SpellTuner_Recorder = true }
    local probeTbl = { stamp = "p", reports = {} }
    local preset = {
        session = { stamp = "2026-09-27 10:00:00", count = 4 },
        char = charTbl,
        modules = modulesTbl,
        probe = probeTbl,
    }
    local MD = NewSession(preset)
    check("a returning database names the previous session and keeps everything else",
        MD:SavedVarsLine() == "SavedVariables: came back (previous session 2026-09-27 10:00:00, this is session 5)"
        and MD.db.char == charTbl
        and MD.db.char["Penek-Anniversary"].x == 1
        and MD.db.modules == modulesTbl
        and MD.db.modules.SpellTuner_Recorder == true
        and _G.SpellTunerDB.probe == probeTbl
        and type(_G.SpellTunerDB.probe.reports) == "table"
        and MD:ModuleState("SpellTuner_Recorder") == "loaded")
end)

-- 3: no stamp
try("a database without a stamp says so", function()
    local MD = NewSession({ probe = { stamp = "p" } })
    check("a database without a stamp says so",
        MD:SavedVarsLine() == "SavedVariables: came back, with no session stamp (first run of this build of SpellTuner)"
        and _G.SpellTunerDB.session.count == 1)
end)

-- 4: broken database
try("a broken database is replaced, not indexed", function()
    local MD = NewSession("garbage")
    check("a broken database is replaced, not indexed",
        MD:SavedVarsLine() == "SavedVariables: was a string, not a table - replaced with an empty one"
        and type(_G.SpellTunerDB) == "table")
end)

-- 5: guard runs before the probe
try("the guard runs before the probe", function()
    local MD = NewSession(nil)
    check("the guard runs before the probe",
        MD.sv.atLoad == "nil"
        and type(_G.SpellTunerDB.probe) == "table")
end)

-- 6: the debug log carries the line
try("the debug log carries the line", function()
    local MD = NewSession({ probe = { stamp = "p" } })
    local expected = "SavedVariables: came back, with no session stamp (first run of this build of SpellTuner)"
    local captured = {}
    MD.db.debug.enabled = true
    MD.DebugLog = function(self, category, text)
        captured[#captured + 1] = { category, text }
    end
    MD:Fire("MD_READY")
    local hits = 0
    for _, rec in ipairs(captured) do
        if rec[1] == "other" and rec[2] == expected then hits = hits + 1 end
    end
    check("the debug log carries the line", hits == 1, "hits=" .. hits)
end)

else -- tbc

-- 7: the TBC database gets no session stamp
try("the TBC database gets no session stamp", function()
    local MD = NewSession(nil)
    check("the TBC database gets no session stamp",
        MD.sv == nil and _G.SpellTunerDB.session == nil)
end)

end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
