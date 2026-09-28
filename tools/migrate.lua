-- tools/run.sh tools/migrate.lua
--
-- The rename (2026-09-27): a client that loads SpellTuner over a WTF folder
-- written by ManaDemon must come up with every recording, fight and setting
-- it had. The .toc lists both globals, so the client hands us ManaDemonDB, and
-- Core.lua adopts it once. This runs that path under the stub with a fake
-- ManaDemonDB already in place before the addon loads.
local here = arg[0]:match("^(.*)/[^/]+$")

_G.ManaDemonDB = {
    locked = false, halfLife = 42,
    char = { ["Penek-Spineshatter"] = { recordings = { { id = 1, zone = "Hellfire Peninsula" } },
                                       practice = { { id = 2 } } } },
}

HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-52s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

check("ManaDemon's saved variables became SpellTuner's", _G.SpellTunerDB ~= nil and MD.db == _G.SpellTunerDB)
check("a setting survived", MD.db.halfLife == 42 and MD.db.locked == false)
check("the character's recordings survived",
    MD.db.char["Penek-Spineshatter"].recordings[1].zone == "Hellfire Peninsula")
check("and its practice fights", MD.db.char["Penek-Spineshatter"].practice[1].id == 2)
check("defaults were filled around what was there", MD.db.simFullHp ~= nil)
check("the old global is emptied so the client stops writing it", _G.ManaDemonDB == nil)
check("/md still answers, /st is the name now", _G.SLASH_SPELLTUNER2 == "/st" and _G.SLASH_SPELLTUNER3 == "/md")

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
