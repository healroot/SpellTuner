-- tools/run.sh tools/releasecheck.lua
--
-- T23: two installations from one tree. Runs release.sh (and nothing else: no
-- harness, no stub) into scratch folders under tools/.lua/releasecheck/ whose
-- paths contain a space, as the author's do, and proves that the TBC package
-- holds exactly the TBC TOC's files, the Forever package exactly the Forever
-- TOCs' files plus the three modules, that an install puts one flavour into one
-- client and removes the other's, that a path of unknown flavour is refused, and
-- that the version is one thing the TOCs agree on.
--
-- NOTHING here writes outside tools/.lua/releasecheck/: every install goes into
-- a scratch "AddOns" folder below it. The scratch tree is cleaned at the START
-- of a run so a failure can be inspected afterwards.
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-84s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- Run a shell command; answers its combined output and its exit status.
local function sh(cmd)
    local p = io.popen("(" .. cmd .. ") 2>&1; echo \"__rc=$?\"")   -- parenthesised: a caller's own 2>/dev/null stays inside
    if not p then return "", -1 end
    local out = p:read("*a") or ""
    p:close()
    local rc = out:match("__rc=(%d+)%s*$")
    out = out:gsub("__rc=%d+%s*$", "")
    return out, tonumber(rc) or -1
end

local function Has(s, sub) return s ~= nil and s:find(sub, 1, true) ~= nil end

local function Lines(path)
    local t = {}
    local f = io.open(path, "rb")
    if not f then return t end
    for line in f:lines() do t[#t + 1] = (line:gsub("\r$", "")) end
    f:close()
    return t
end

local function Slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- The TOC's load entries as paths (backslashes as slashes), comments dropped.
local function Entries(path)
    local t = {}
    for _, l in ipairs(Lines(path)) do
        if l ~= "" and l:sub(1, 1) ~= "#" then t[#t + 1] = (l:gsub("\\", "/")) end
    end
    return t
end

local function Version(path)
    for _, l in ipairs(Lines(path)) do
        local v = l:match("^## Version:%s*(.-)%s*$")
        if v then return v end
    end
    return nil
end

-- Sorted list of every file below dir, relative to it. Empty when there is none.
local function FileList(dir)
    local out = sh("cd " .. q(dir) .. " 2>/dev/null && find . -type f | sort")
    local t = {}
    for line in out:gmatch("[^\n]+") do
        local rel = line:match("^%./(.+)$")
        if rel then t[#t + 1] = rel end
    end
    return t
end

local function DirNames(dir)
    local out = sh("ls -A " .. q(dir) .. " 2>/dev/null")
    local t = {}
    for line in out:gmatch("[^\n]+") do t[#t + 1] = line end
    table.sort(t)
    return t
end

-- A sorted set from a list, de-duplicated.
local function SetOf(list)
    local seen, t = {}, {}
    for _, v in ipairs(list) do
        if not seen[v] then seen[v] = true; t[#t + 1] = v end
    end
    table.sort(t)
    return t
end

-- Sets equal? Answers ok and, when not, the first differences.
local function SameSet(a, b)
    a, b = SetOf(a), SetOf(b)
    local inA, inB = {}, {}
    for _, v in ipairs(a) do inA[v] = true end
    for _, v in ipairs(b) do inB[v] = true end
    local diff = {}
    for _, v in ipairs(a) do if not inB[v] then diff[#diff + 1] = "extra " .. v end end
    for _, v in ipairs(b) do if not inA[v] then diff[#diff + 1] = "missing " .. v end end
    if #diff == 0 then return true end
    while #diff > 4 do table.remove(diff) end
    return false, table.concat(diff, "; ")
end

local function Prefixed(prefix, list)
    local t = {}
    for _, v in ipairs(list) do t[#t + 1] = prefix .. v end
    return t
end

local function Append(dst, src) for _, v in ipairs(src) do dst[#dst + 1] = v end end

local function Interfaces(path)
    local t = {}
    for _, l in ipairs(Lines(path)) do
        local v = l:match("^## Interface:%s*(.-)%s*$")
        if v then for n in v:gmatch("%d+") do t[#t + 1] = tonumber(n) end end
    end
    return t
end

local function TocsUnder(dir)
    local out = sh("cd " .. q(dir) .. " 2>/dev/null && find . -name '*.toc' | sort")
    local t = {}
    for line in out:gmatch("[^\n]+") do t[#t + 1] = dir .. "/" .. line:gsub("^%./", "") end
    return t
end

--------------------------------------------------------------------------------
-- The tree's own expectations, read from its TOCs.
--------------------------------------------------------------------------------
local TREE_VERSION = Version(ROOT .. "/SpellTuner_TBC.toc")

local tbcExpected = { "README.md", "SpellTuner_TBC.toc" }
Append(tbcExpected, Entries(ROOT .. "/SpellTuner_TBC.toc"))

local foreverExpected = { "README.md", "SpellTuner_Mainline.toc", "SpellTuner.toc" }
Append(foreverExpected, Entries(ROOT .. "/SpellTuner_Mainline.toc"))
Append(foreverExpected, Entries(ROOT .. "/SpellTuner.toc"))

local moduleNames = {}
do
    local out = sh("ls -1 " .. q(ROOT .. "/Modules"))
    for line in out:gmatch("[^\n]+") do moduleNames[#moduleNames + 1] = line end
    table.sort(moduleNames)
end

local function ModuleExpected(name)
    local t = {}
    local out = sh("ls -1 " .. q(ROOT .. "/Modules/" .. name))
    for line in out:gmatch("[^\n]+") do
        if line:match("^" .. name .. ".*%.toc$") then
            t[#t + 1] = line
            Append(t, Entries(ROOT .. "/Modules/" .. name .. "/" .. line))
        end
    end
    return t
end

--------------------------------------------------------------------------------
-- The scratch tree: cleaned at the start, paths with a space in them.
--------------------------------------------------------------------------------
local SCRATCH = ROOT .. "/tools/.lua/releasecheck/scratch tree"
assert(SCRATCH:find("tools/.lua/releasecheck/", 1, true), "scratch outside tools/.lua/releasecheck")
sh("rm -rf " .. q(SCRATCH) .. " && mkdir -p " .. q(SCRATCH))

local RELEASE = ROOT .. "/release.sh"
-- WOW_ADDONS must never reach a run (it would name a real client).
local function Release(script, ...)
    local args = {}
    for _, a in ipairs({ ... }) do args[#args + 1] = q(a) end
    return sh("env -u WOW_ADDONS bash " .. q(script) .. " " .. table.concat(args, " "))
end

local OUT = SCRATCH .. "/out dir"
local buildOut, buildRc = Release(RELEASE, "--out", OUT)
print("-- build: rc=" .. tostring(buildRc))
print((buildOut:gsub("\n$", "")))

--------------------------------------------------------------------------------
-- 1-3. What each package holds.
--------------------------------------------------------------------------------
do
    local same, detail = SameSet(FileList(OUT .. "/tbc/SpellTuner"), tbcExpected)
    local top = DirNames(OUT .. "/tbc")
    check("the TBC package holds exactly the TBC TOC's files",
        same and #top == 1 and top[1] == "SpellTuner", detail or table.concat(top, ","))
end

do
    local same, detail = SameSet(FileList(OUT .. "/forever/SpellTuner"), foreverExpected)
    check("the Forever package holds exactly the Forever TOCs' files", same, detail)
end

do
    local wantTop = { "SpellTuner" }
    Append(wantTop, moduleNames)
    local topSame, topDetail = SameSet(DirNames(OUT .. "/forever"), wantTop)
    local allSame, allDetail = #moduleNames == 3, "modules in tree: " .. #moduleNames
    for _, name in ipairs(moduleNames) do
        local same, detail = SameSet(FileList(OUT .. "/forever/" .. name), ModuleExpected(name))
        if not same then allSame = false; allDetail = name .. ": " .. tostring(detail) end
    end
    check("the Forever package carries the three modules, each exactly its TOCs' files",
        topSame and allSame, topDetail or allDetail)
end

--------------------------------------------------------------------------------
-- 4-5. Interfaces and the one version.
--------------------------------------------------------------------------------
do
    local bad
    local tbcTocs, foreverTocs = TocsUnder(OUT .. "/tbc"), TocsUnder(OUT .. "/forever")
    for _, toc in ipairs(tbcTocs) do
        for _, n in ipairs(Interfaces(toc)) do
            if n < 20000 or n > 29999 then bad = toc .. " " .. n end
        end
    end
    for _, toc in ipairs(foreverTocs) do
        for _, n in ipairs(Interfaces(toc)) do
            if n < 16000 or n > 19999 then bad = toc .. " " .. n end
        end
    end
    check("no TOC of the other flavour is in either package",
        bad == nil and #tbcTocs >= 1 and #foreverTocs >= 2, bad)
end

do
    local bad
    local all = TocsUnder(OUT .. "/tbc")
    Append(all, TocsUnder(OUT .. "/forever"))
    for _, toc in ipairs(all) do
        if Version(toc) ~= TREE_VERSION then bad = toc .. " " .. tostring(Version(toc)) end
    end
    check("every packaged TOC carries the tree's one version",
        TREE_VERSION ~= nil and bad == nil and #all >= 3, bad)
end

--------------------------------------------------------------------------------
-- 6. The zips.
--------------------------------------------------------------------------------
do
    local function ZipMembers(path)
        local out = sh("python3 -c " .. q("import sys, zipfile\n"
            .. "z = zipfile.ZipFile(sys.argv[1])\n"
            .. "print('\\n'.join(n for n in z.namelist() if not n.endswith('/')))") .. " " .. q(path))
        local t = {}
        for line in out:gmatch("[^\n]+") do t[#t + 1] = line end
        return t
    end
    local tbcZip = OUT .. "/SpellTuner-tbc-" .. tostring(TREE_VERSION) .. ".zip"
    local forZip = OUT .. "/SpellTuner-forever-" .. tostring(TREE_VERSION) .. ".zip"
    local tbcFiles = Prefixed("SpellTuner/", FileList(OUT .. "/tbc/SpellTuner"))
    local forFiles = FileList(OUT .. "/forever")
    local s1, d1 = SameSet(ZipMembers(tbcZip), tbcFiles)
    local s2, d2 = SameSet(ZipMembers(forZip), forFiles)
    check("each zip is named by flavour and version and holds exactly its package",
        #tbcFiles > 0 and #forFiles > 0 and s1 and s2,
        (d1 and ("tbc: " .. d1) or "") .. (d2 and (" forever: " .. d2) or ""))
end

--------------------------------------------------------------------------------
-- 7-8. On a scratch copy of the tree (uncommitted work included).
--------------------------------------------------------------------------------
local COPY = SCRATCH .. "/tree copy"
sh("mkdir -p " .. q(COPY) .. " && cd " .. q(ROOT)
    .. " && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null | tar -xf - -C " .. q(COPY))
local COPY_RELEASE = COPY .. "/release.sh"
local haveCopy = Slurp(COPY_RELEASE) ~= nil and Slurp(COPY .. "/SpellTuner_TBC.toc") ~= nil

local function AllTocs(dir)
    local t = {}
    local out = sh("cd " .. q(dir) .. " && find . -name '*.toc' -not -path './tools/*' | sort")
    for line in out:gmatch("[^\n]+") do
        local rel = line:match("^%./(.+)$")
        if rel then t[#t + 1] = rel end
    end
    return t
end

local function Checksums(dir)
    local out = sh("cd " .. q(dir) .. " && find . -type f | sort | while IFS= read -r f; do cksum \"$f\"; done")
    return out
end

do
    local badToc = "Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc"
    local badOut = SCRATCH .. "/out disagree"
    local text = Slurp(COPY .. "/" .. badToc)
    local wrote = false
    if text then
        local f = io.open(COPY .. "/" .. badToc, "wb")
        if f then f:write((text:gsub("## Version: [^\r\n]*", "## Version: 0.16.1", 1))); f:close(); wrote = true end
    end
    local out, rc = "", 0
    if haveCopy and wrote then out, rc = Release(COPY_RELEASE, "--out", badOut) end
    local noFolders = #DirNames(badOut .. "/tbc") == 0 and #DirNames(badOut .. "/forever") == 0
    check("the build refuses when two TOCs disagree on the version",
        haveCopy and wrote and rc ~= 0 and Has(out, badToc) and Has(out, "0.16.1")
        and Has(out, tostring(TREE_VERSION)) and noFolders,
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 160))
    -- put the copy back for the next check
    if text then
        local f = io.open(COPY .. "/" .. badToc, "wb")
        if f then f:write(text); f:close() end
    end
end

do
    local tocs = AllTocs(COPY)
    -- One TOC in CRLF, as a Windows editor leaves it: --set-version must keep every CR,
    -- the version line's included (lead review; the byte-for-byte comparison below and
    -- the explicit count here both see a lost CR).
    local CRLF_TOC = "SpellTuner_TBC.toc"
    local crlfMade = false
    do
        local text = Slurp(COPY .. "/" .. CRLF_TOC)
        if text and not text:find("\r", 1, true) then
            local f = io.open(COPY .. "/" .. CRLF_TOC, "wb")
            if f then f:write((text:gsub("\n", "\r\n"))); f:close(); crlfMade = true end
        end
    end
    local before = {}
    for _, rel in ipairs(tocs) do before[rel] = Slurp(COPY .. "/" .. rel) end
    local sumsBefore = Checksums(COPY)

    -- an invalid version changes nothing
    local _, rcBad = Release(COPY_RELEASE, "--set-version", "1.0")
    local unchanged = Checksums(COPY) == sumsBefore

    local out, rc = Release(COPY_RELEASE, "--set-version", "0.16.9")
    local allNew, onlyLine = #tocs >= 9, true
    local detail
    for _, rel in ipairs(tocs) do
        local after = Slurp(COPY .. "/" .. rel) or ""
        local expected = (before[rel]:gsub("(\n?)## Version:[ \t]*[^\r\n]*", "%1## Version: 0.16.9", 1))
        if Version(COPY .. "/" .. rel) ~= "0.16.9" then allNew = false; detail = rel .. " reads " .. tostring(Version(COPY .. "/" .. rel)) end
        if after ~= expected then onlyLine = false; detail = detail or (rel .. " differs beyond its version line") end
    end
    -- no other file changed: the checksums of everything else are as they were
    local function WithoutTocs(sums)
        local t = {}
        for line in sums:gmatch("[^\n]+") do
            if not line:find("%.toc$") then t[#t + 1] = line end
        end
        return table.concat(t, "\n")
    end
    local othersSame = WithoutTocs(Checksums(COPY)) == WithoutTocs(sumsBefore)
    local crlfKept
    do
        local text = Slurp(COPY .. "/" .. CRLF_TOC) or ""
        local _, lf = text:gsub("\n", "")
        local _, crlf = text:gsub("\r\n", "")
        crlfKept = crlfMade and lf > 0 and lf == crlf and Has(text, "## Version: 0.16.9\r\n")
        if not crlfKept then detail = detail or (CRLF_TOC .. " lost its CRLF: " .. crlf .. " of " .. lf) end
    end
    check("--set-version rewrites every TOC's version line and nothing else",
        haveCopy and rc == 0 and allNew and onlyLine and othersSame and rcBad ~= 0 and unchanged and crlfKept,
        detail or ("rc=" .. tostring(rc) .. " bad=" .. tostring(rcBad) .. " unchanged=" .. tostring(unchanged)
            .. " others=" .. tostring(othersSame) .. " " .. out:sub(1, 80)))
end

--------------------------------------------------------------------------------
-- 9-13. Installs -- only ever into scratch AddOns folders.
--------------------------------------------------------------------------------
local function Seed(path, text)
    sh("mkdir -p " .. q(path:match("^(.*)/[^/]+$")))
    local f = io.open(path, "wb")
    if f then f:write(text or "x\n"); f:close() end
end

local FOREVER_ADDONS = SCRATCH .. "/_classic_beta_/Interface/AddOns"
local TBC_ADDONS = SCRATCH .. "/_anniversary_/Interface/AddOns"
local UNKNOWN_ADDONS = SCRATCH .. "/somewhere/Interface/AddOns"
local INSTALL_OUT = SCRATCH .. "/out install"

local function Diff(a, b)
    local _, rc = sh("diff -r " .. q(a) .. " " .. q(b))
    return rc == 0
end

Seed(FOREVER_ADDONS .. "/SpellTuner/SpellTuner_TBC.toc")
Seed(FOREVER_ADDONS .. "/SpellTuner/Stale.lua")
Seed(FOREVER_ADDONS .. "/OtherAddon/x.lua")
do
    local out, rc = Release(RELEASE, "--out", INSTALL_OUT, "--install", FOREVER_ADDONS)
    local ok1 = rc == 0 and Diff(INSTALL_OUT .. "/forever/SpellTuner", FOREVER_ADDONS .. "/SpellTuner")
    for _, name in ipairs(moduleNames) do
        ok1 = ok1 and Diff(INSTALL_OUT .. "/forever/" .. name, FOREVER_ADDONS .. "/" .. name)
    end
    local top = DirNames(FOREVER_ADDONS)
    local want = { "OtherAddon", "SpellTuner" }
    Append(want, moduleNames)
    local topSame, topDetail = SameSet(top, want)
    check("an install into a Forever client puts only the Forever package there",
        ok1 and topSame and Slurp(FOREVER_ADDONS .. "/OtherAddon/x.lua") ~= nil
        and Slurp(FOREVER_ADDONS .. "/SpellTuner/SpellTuner_TBC.toc") == nil
        and Slurp(FOREVER_ADDONS .. "/SpellTuner/Stale.lua") == nil,
        topDetail or ("rc=" .. tostring(rc) .. " " .. out:sub(-120)))
end

Seed(TBC_ADDONS .. "/SpellTuner/SpellTuner_Mainline.toc")
Seed(TBC_ADDONS .. "/SpellTuner_Recorder/SpellTuner_Recorder.toc")
Seed(TBC_ADDONS .. "/OtherAddon/x.lua")
do
    local out, rc = Release(RELEASE, "--out", INSTALL_OUT, "--install", TBC_ADDONS)
    local same = rc == 0 and Diff(INSTALL_OUT .. "/tbc/SpellTuner", TBC_ADDONS .. "/SpellTuner")
    local noModules = true
    for _, name in ipairs(moduleNames) do
        if #FileList(TBC_ADDONS .. "/" .. name) > 0 or #DirNames(TBC_ADDONS .. "/" .. name) > 0 then noModules = false end
    end
    check("an install into a TBC client puts only the TBC package there and removes the modules",
        same and noModules and Has(out, "Removed stale") and Slurp(TBC_ADDONS .. "/OtherAddon/x.lua") ~= nil
        and Slurp(TBC_ADDONS .. "/SpellTuner/SpellTuner_Mainline.toc") == nil,
        "rc=" .. tostring(rc) .. " " .. out:sub(-160))
end

Seed(UNKNOWN_ADDONS .. "/sentinel.txt")
do
    local refuseOut = SCRATCH .. "/out refused"
    local out, rc = Release(RELEASE, "--out", refuseOut, "--install", UNKNOWN_ADDONS)
    local names = DirNames(UNKNOWN_ADDONS)
    check("an install into a path of unknown flavour is refused and writes nothing",
        rc ~= 0 and Has(out, "--install-tbc") and Has(out, "--install-forever")
        and #names == 1 and names[1] == "sentinel.txt" and #DirNames(refuseOut) == 0,
        "rc=" .. tostring(rc) .. " " .. out:sub(1, 120))
end

do
    local before = table.concat(FileList(FOREVER_ADDONS), "\n")
    local sumsBefore = Checksums(FOREVER_ADDONS)
    local out, rc = Release(RELEASE, "--out", SCRATCH .. "/out contradict", "--install-tbc", FOREVER_ADDONS)
    check("an explicit flavour that contradicts the path is refused",
        rc ~= 0 and table.concat(FileList(FOREVER_ADDONS), "\n") == before and Checksums(FOREVER_ADDONS) == sumsBefore,
        "rc=" .. tostring(rc) .. " " .. out:sub(1, 120))
end

do
    local out, rc = Release(RELEASE, "--out", INSTALL_OUT, "--install-forever", UNKNOWN_ADDONS)
    local ok1 = rc == 0 and Diff(INSTALL_OUT .. "/forever/SpellTuner", UNKNOWN_ADDONS .. "/SpellTuner")
    for _, name in ipairs(moduleNames) do
        ok1 = ok1 and Diff(INSTALL_OUT .. "/forever/" .. name, UNKNOWN_ADDONS .. "/" .. name)
    end
    check("the explicit flavour installs into a path it cannot detect",
        ok1 and Slurp(UNKNOWN_ADDONS .. "/sentinel.txt") ~= nil,
        "rc=" .. tostring(rc) .. " " .. out:sub(-120))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL: " .. f) end
os.exit(#fails == 0 and 0 or 1)
