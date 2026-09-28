-- Loads one flavour of SpellTuner under tools/wowstub.lua and returns the
-- addon table. arg[1] is the repo root.
--
-- Which flavour: a tool sets HARNESS_FLAVOUR (a string, or a list of strings)
-- before dofile-ing this file; absent means Forever only, since M1's tools
-- are all Forever. ST_FLAVOUR (set by run.sh --flavour) picks among the
-- declared ones; a tool run under a flavour it did not declare skips rather
-- than running against the wrong client.
local here = arg[0]:match("^(.*)/[^/]+$")

local declared = HARNESS_FLAVOUR
if declared == nil then declared = { "forever" } end
if type(declared) == "string" then declared = { declared } end

local function Contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local flavour
local envFlavour = os.getenv("ST_FLAVOUR")
if envFlavour ~= nil and envFlavour ~= "" then
    if Contains(declared, envFlavour) then
        flavour = envFlavour
    else
        -- The tool's name is its own main chunk's, found by walking up from
        -- the dofile: a suite that loads this under pcall puts pcall's [C]
        -- frame in between, so a fixed level would name "[C]".
        local level, info = 3, nil; repeat info = debug.getinfo(level, "S"); level = level + 1 until not info or info.what == "main"
        local scriptName = (info and info.short_src or "?"):match("([^/]+)$") or "?"
        print("skip: " .. scriptName .. " runs under " .. table.concat(declared, ", ") .. " only")
        os.exit(0)
    end
else
    flavour = declared[1]
end

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = arg[1] or "."
S.flavour = flavour

local MD = {}

if flavour == "forever" then
    S.UseProfile("forever")
    local files = S.TocFiles("SpellTuner_Mainline.toc")
    S.loadedFiles = files
    S.Load(files, "SpellTuner", MD)
    S.Fire("ADDON_LOADED", "SpellTuner")
    S.Fire("PLAYER_LOGIN")
    S.Fire("PLAYER_ENTERING_WORLD")
    return MD
end

-- tbc: the TOC's own order minus everything that draws (UI/ other than
-- UI/Summary.lua, which owns the combat-log handler and the fight lifecycle
-- rather than a widget; Integrations/, which only wires up ElvUI).
local function KeepForTbc(rel)
    if rel:sub(1, 3) == "UI/" then return rel == "UI/Summary.lua" end
    if rel:sub(1, 13) == "Integrations/" then return false end
    return true
end
local allFiles = S.TocFiles("SpellTuner_TBC.toc")
local files = {}
for _, rel in ipairs(allFiles) do
    if KeepForTbc(rel) then files[#files + 1] = rel end
end
S.loadedFiles = files
S.Load(files, "SpellTuner", MD)

-- Everything the BF-1 druid knew: every rank at or below level 64.
local SD = MD.SpellData
for id, s in pairs(SD.spells) do
    if (s.level or 1) <= S.level then S.known[id] = true end
end
-- The client names every spell; the stub only knows the healing table, so the
-- non-healing ids the fixtures cast are named here. Without them MD:ClassifyCast
-- has nothing to fall back on and calls a Mark of the Wild "unknown", which is
-- a property of the harness rather than of the addon.
S.spellNames = setmetatable({
    [9885]  = "Mark of the Wild",
    [2782]  = "Remove Curse",
    [17116] = "Nature's Swiftness",
    [33891] = "Tree of Life",
    [26987] = "Moonfire", [25298] = "Starfire", [24977] = "Insect Swarm",
    [9853]  = "Entangling Roots", [17329] = "Nature's Grasp", [24858] = "Moonkin Form",
}, { __index = function(_, k)
    local s = SD.spells[k]
    return s and (s.family .. " r" .. tostring(s.rank)) or ("Spell" .. tostring(k))
end })

-- The log's talent build. Resto to the teeth, and NO Dreamstate -- the BF-1
-- log's regen lines carry no Dreamstate suffix, so the engine must not get it.
local TALENTS = {
    ["Gift of Nature"] = 5, ["Empowered Touch"] = 2, ["Empowered Rejuvenation"] = 5,
    ["Improved Rejuvenation"] = 3, ["Naturalist"] = 5, ["Moonglow"] = 3,
    ["Tranquil Spirit"] = 5, ["Improved Regrowth"] = 5, ["Nature's Grace"] = 1,
    ["Intensity"] = 3, ["Dreamstate"] = 0,
}
function MD:TalentRank(name) return TALENTS[name] or 0 end
MD.harnessTalents = TALENTS

S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")
return MD
