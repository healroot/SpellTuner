-- tools/run.sh tools/releasecheck.lua
--
-- T23: two installations from one tree. Runs release.sh (and nothing else: no
-- harness, no stub) into scratch folders under tools/.lua/releasecheck/ whose
-- paths contain a space, as the author's do, and proves that the TBC package
-- holds exactly the TBC TOC's files, the Forever package exactly the Forever
-- TOCs' files plus the three modules, that an install puts one flavour into one
-- client and removes the other's, that a path of unknown flavour is refused, and
-- that the version is one thing the TOCs agree on. T47 (P3): a TOC's flavour is
-- its marker file (or its Modules/ folder), the interface band from
-- tools/data/flavours.txt only a fallback -- a launch interface outside every
-- band still packages, and only a TOC with neither is refused.
--
-- T57 (P13, review Q7, A10): the scratch copy of the tree is asserted before
-- anything reads it (git's file list, or find where there is no repository),
-- --set-version's one folded check is four, and the two plain Forever TOCs are
-- asserted identical but for their marker line.
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
-- T47: the flavour table release.sh classifies by (tools/data/flavours.txt):
-- a TOC is the flavour whose marker file it loads, a TOC under Modules/ is
-- forever, and the interface band decides only for a TOC with neither.
local FLAVOURS = {}
for _, l in ipairs(Lines(ROOT .. "/tools/data/flavours.txt")) do
    local name, files, lo, hi = l:match("^%s*([^#%s]%S*)%s+(%S+)%s+(%d+)%-(%d+)%s*$")
    if name then
        local markers = {}
        for m in files:gmatch("[^,]+") do markers[m] = true end
        FLAVOURS[#FLAVOURS + 1] = { name = name, markers = markers, lo = tonumber(lo), hi = tonumber(hi) }
    end
end

local function FlavourOf(toc, isModule)
    for _, e in ipairs(Entries(toc)) do
        for _, fl in ipairs(FLAVOURS) do
            if fl.markers[e] then return fl.name end
        end
    end
    if isModule then return "forever" end
    local nums = Interfaces(toc)
    for _, fl in ipairs(FLAVOURS) do
        local all = #nums > 0
        for _, n in ipairs(nums) do if n < fl.lo or n > fl.hi then all = false end end
        if all then return fl.name end
    end
    return nil
end

do
    local bad
    local tbcTocs, foreverTocs = TocsUnder(OUT .. "/tbc"), TocsUnder(OUT .. "/forever")
    for _, toc in ipairs(tbcTocs) do
        if FlavourOf(toc, false) ~= "tbc" then bad = toc .. " " .. tostring(FlavourOf(toc, false)) end
    end
    for _, toc in ipairs(foreverTocs) do
        local isModule = not toc:find("/forever/SpellTuner/", 1, true)
        if FlavourOf(toc, isModule) ~= "forever" then bad = toc .. " " .. tostring(FlavourOf(toc, isModule)) end
    end
    check("no TOC of the other flavour is in either package",
        #FLAVOURS >= 2 and bad == nil and #tbcTocs >= 1 and #foreverTocs >= 2, bad or ("flavours " .. #FLAVOURS))
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
-- git's own file list (uncommitted work included, ignored files left out);
-- outside a repository -- an unpacked archive, a copied folder -- every file
-- but the ones git would ignore here: tools/.lua (this scratch tree among
-- them), dist, .git, .claude, .logs, caches.
local copySource
do
    local _, inGit = sh("cd " .. q(ROOT) .. " && git rev-parse --is-inside-work-tree >/dev/null 2>&1")
    sh("mkdir -p " .. q(COPY))
    if inGit == 0 then
        copySource = "git"
        sh("cd " .. q(ROOT) .. " && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null | tar -xf - -C " .. q(COPY))
    else
        copySource = "find"
        sh("cd " .. q(ROOT) .. " && find . \\( -path ./.git -o -path ./tools/.lua -o -path ./dist -o -path ./.claude"
            .. " -o -path ./.logs -o -path ./tools/.cache -o -name __pycache__ \\) -prune -o -type f -print0"
            .. " | tar --null -T - -cf - 2>/dev/null | tar -xf - -C " .. q(COPY))
    end
end
local COPY_RELEASE = COPY .. "/release.sh"
local copyTocs = #TocsUnder(COPY)
local haveCopy = Slurp(COPY_RELEASE) ~= nil and Slurp(COPY .. "/SpellTuner_TBC.toc") ~= nil and copyTocs >= 9
-- Asserted before any check reads the copy: an empty copy used to surface as
-- "lost its CRLF: 0 of 0" three checks later (review Q7).
check("the scratch copy of the tree holds release.sh and every TOC (" .. copySource .. ")",
    haveCopy, "release.sh " .. tostring(Slurp(COPY_RELEASE) ~= nil) .. ", " .. copyTocs .. " TOCs in " .. COPY)

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
    -- a version no tree ever carries, so the check holds whatever the tree's own is
    local OTHER = "9.9.9-disagree"
    if text then
        local f = io.open(COPY .. "/" .. badToc, "wb")
        if f then f:write((text:gsub("## Version: [^\r\n]*", "## Version: " .. OTHER, 1))); f:close(); wrote = true end
    end
    local out, rc = "", 0
    if haveCopy and wrote then out, rc = Release(COPY_RELEASE, "--out", badOut) end
    local noFolders = #DirNames(badOut .. "/tbc") == 0 and #DirNames(badOut .. "/forever") == 0
    check("the build refuses when two TOCs disagree on the version",
        haveCopy and wrote and rc ~= 0 and Has(out, badToc) and Has(out, OTHER)
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

    check("--set-version refuses a version that is not x.y.z and changes nothing",
        haveCopy and rcBad ~= 0 and unchanged, "rc=" .. tostring(rcBad) .. " unchanged=" .. tostring(unchanged))

    local out, rc = Release(COPY_RELEASE, "--set-version", "0.16.9")
    local allNew, onlyLine = #tocs >= 9, true
    local detail
    for _, rel in ipairs(tocs) do
        local after = Slurp(COPY .. "/" .. rel) or ""
        local expected = (before[rel]:gsub("(\n?)## Version:[ \t]*[^\r\n]*", "%1## Version: 0.16.9", 1))
        if Version(COPY .. "/" .. rel) ~= "0.16.9" then allNew = false; detail = rel .. " reads " .. tostring(Version(COPY .. "/" .. rel)) end
        if after ~= expected then onlyLine = false; detail = detail or (rel .. " differs beyond its version line") end
    end
    check("--set-version rewrites every TOC's version line, and only that line",
        haveCopy and rc == 0 and allNew and onlyLine,
        detail or ("rc=" .. tostring(rc) .. " TOCs " .. #tocs .. " " .. out:gsub("\n", " / "):sub(1, 80)))
    -- no other file changed: the checksums of everything else are as they were
    local function WithoutTocs(sums)
        local t = {}
        for line in sums:gmatch("[^\n]+") do
            if not line:find("%.toc$") then t[#t + 1] = line end
        end
        return table.concat(t, "\n")
    end
    local othersSame = WithoutTocs(Checksums(COPY)) == WithoutTocs(sumsBefore)
    check("--set-version changes no file but the TOCs", haveCopy and rc == 0 and othersSame)
    local crlfKept, crlfDetail
    do
        local text = Slurp(COPY .. "/" .. CRLF_TOC) or ""
        local _, lf = text:gsub("\n", "")
        local _, crlf = text:gsub("\r\n", "")
        crlfKept = crlfMade and lf > 0 and lf == crlf and Has(text, "## Version: 0.16.9\r\n")
        if not crlfKept then
            crlfDetail = crlfMade and (CRLF_TOC .. " lost its CRLF: " .. crlf .. " of " .. lf)
                or (CRLF_TOC .. " could not be made CRLF in the copy")
        end
    end
    check("--set-version keeps a CRLF TOC's every CR, the version line's included",
        haveCopy and rc == 0 and crlfKept, crlfDetail)
end

--------------------------------------------------------------------------------
-- T57 (P13, review A10): SpellTuner.toc is SpellTuner_Mainline.toc's fallback
-- twin -- the client loads one or the other -- so the two are the same file but
-- for the marker line each loads first (Client\TOC_Plain.lua /
-- Client\TOC_Mainline.lua, the line the probe reads back). Nothing asserted it.
--------------------------------------------------------------------------------
do
    local a, b = Lines(ROOT .. "/SpellTuner.toc"), Lines(ROOT .. "/SpellTuner_Mainline.toc")
    local diffs = {}
    for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then diffs[#diffs + 1] = i end
    end
    local i = diffs[1]
    local markerOnly = #diffs == 1 and a[i] == "Client\\TOC_Plain.lua" and b[i] == "Client\\TOC_Mainline.lua"
    check("SpellTuner.toc and SpellTuner_Mainline.toc differ only in their marker line",
        #a > 0 and markerOnly,
        #diffs .. " differing line(s)" .. (i and (": " .. tostring(a[i]) .. " / " .. tostring(b[i])) or ""))
end

--------------------------------------------------------------------------------
-- 14-16 (T47, P3). The client is the TOC's: a launch interface outside every
-- band changes nothing for a TOC that loads its marker (or sits under
-- Modules/), and only a TOC with neither is refused, by name. On the scratch
-- copy, whose TOCs --set-version left at one version; put back afterwards.
--------------------------------------------------------------------------------
do
    local MAIN = "SpellTuner_Mainline.toc"
    local MOD = "Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc"
    local mainText, modText = Slurp(COPY .. "/" .. MAIN), Slurp(COPY .. "/" .. MOD)
    local function Rewrite(rel, text)
        local f = io.open(COPY .. "/" .. rel, "wb")
        if f then f:write((text:gsub("## Interface:[^\r\n]*", "## Interface: 120105", 1))); f:close(); return true end
        return false
    end
    local wrote = haveCopy and mainText ~= nil and modText ~= nil and Rewrite(MAIN, mainText) and Rewrite(MOD, modText)
    local launchOut = SCRATCH .. "/out launch"
    local out, rc = "", -1
    if wrote then out, rc = Release(COPY_RELEASE, "--out", launchOut, "--flavour", "forever") end
    local mainFiles = FileList(launchOut .. "/forever/SpellTuner")
    local hasMain = false
    for _, f in ipairs(mainFiles) do if f == MAIN then hasMain = true end end
    check("a Forever TOC at interface 120105 is packaged as forever (its marker), with a warning",
        wrote and rc == 0 and hasMain and #FileList(launchOut .. "/tbc") == 0
        and Has(out, "WARNING: " .. MAIN .. " has interface 120105"),
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
    local recFiles = FileList(launchOut .. "/forever/SpellTuner_Recorder")
    local hasMod = false
    for _, f in ipairs(recFiles) do if f == "SpellTuner_Recorder_Mainline.toc" then hasMod = true end end
    check("a module TOC at interface 120105 is packaged as forever (its folder), with a warning",
        wrote and rc == 0 and hasMod and Has(out, "WARNING: " .. MOD .. " has interface 120105"),
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
    if mainText then local f = io.open(COPY .. "/" .. MAIN, "wb"); if f then f:write(mainText); f:close() end end
    if modText then local f = io.open(COPY .. "/" .. MOD, "wb"); if f then f:write(modText); f:close() end end

    -- a TOC with no marker file, outside every band: refused, named, nothing built
    local ODD = "SpellTuner_Odd.toc"
    local version = Version(COPY .. "/SpellTuner_TBC.toc") or "0.0.0"
    local f = io.open(COPY .. "/" .. ODD, "wb")
    if f then f:write("## Interface: 120105\n## Title: SpellTuner\n## Version: " .. version .. "\n\nCore.lua\n"); f:close() end
    local oddOut = SCRATCH .. "/out odd"
    local out2, rc2 = "", -1
    if haveCopy and f then out2, rc2 = Release(COPY_RELEASE, "--out", oddOut) end
    os.remove(COPY .. "/" .. ODD)
    check("a TOC with no marker file and an interface in no band is refused, by name",
        haveCopy and f ~= nil and rc2 ~= 0 and Has(out2, ODD) and Has(out2, "no marker file")
        and #DirNames(oddOut) == 0,
        "rc=" .. tostring(rc2) .. " " .. out2:gsub("\n", " / "):sub(1, 200))
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

--------------------------------------------------------------------------------
-- T-publish: ./release.sh --publish, against a FAKE curl. Nothing here ever
-- reaches CurseForge: fakebin/curl comes first on PATH, records its argv, its
-- stdin (the curl config the token travels in), its cwd and the metadata it was
-- handed, and answers canned JSON. On a scratch git repository of the tree (a
-- clean, committed copy: --publish refuses anything else), whose
-- dist/publish tree/published.txt is the upload record.
--------------------------------------------------------------------------------
local PUB = SCRATCH .. "/publish tree"
local FAKEBIN = SCRATCH .. "/fakebin"
local CURL_LOG = SCRATCH .. "/curl log"
local VERSIONS_JSON = SCRATCH .. "/versions.json"
local TOKEN = "cf-TEST-token-7f3a9c0d"
local PUB_RECORD = PUB .. "/dist/publish tree/published.txt"

local function Write(path, text)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(text); f:close()
    return true
end

local pubReady
do
    sh("mkdir -p " .. q(PUB) .. " " .. q(FAKEBIN))
    sh("cd " .. q(COPY) .. " && tar -cf - --exclude=./.git . | tar -xf - -C " .. q(PUB))
    -- the copy carries --set-version's 0.16.9 by now: back to the tree's TOCs
    for _, rel in ipairs(AllTocs(ROOT)) do
        local text = Slurp(ROOT .. "/" .. rel)
        if text then Write(PUB .. "/" .. rel, text) end
    end
    -- a newest HISTORY entry with a quote, a backslash and a non-ASCII dash, for the changelog
    local hist = Slurp(PUB .. "/docs/HISTORY.md") or ""
    Write(PUB .. "/docs/HISTORY.md", hist .. "\n## 2099-01-01 \226\128\148 publish test\n\n"
        .. "A line with \"quotes\", a back\\slash and a dash \226\128\148 here.\n\n- one item\n")
    Write(VERSIONS_JSON, '[{"id": 7, "gameVersionTypeID": 517, "name": "11.2.0", "slug": "11-2-0"},'
        .. ' {"id": 10101, "gameVersionTypeID": 73713, "name": "2.5.6", "slug": "2-5-6"},'
        .. ' {"id": 10102, "gameVersionTypeID": 73713, "name": "2.5.5", "slug": "2-5-5"},'
        .. ' {"id": 20201, "gameVersionTypeID": 99001, "name": "1.60.1", "slug": "1-60-1"}]')
    -- The fake: argv one per line, stdin when "-K -", the cwd, the metadata file's
    -- content, whether the file part exists; -o / -w honoured; 200 always.
    Write(FAKEBIN .. "/curl", [=[#!/usr/bin/env bash
mkdir -p "$FAKE_CURL_LOG"
n=$(( $(cat "$FAKE_CURL_LOG/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_CURL_LOG/count"
printf '%s\n' "$@" > "$FAKE_CURL_LOG/$n.argv"
pwd > "$FAKE_CURL_LOG/$n.cwd"
out="" fmt="" url="" stdin=0 prev=""
for a in "$@"; do
    case "$prev" in
        -o) out="$a" ;;
        -w) fmt="$a" ;;
        -K) [[ "$a" == "-" ]] && stdin=1 ;;
        -F)
            case "$a" in
                metadata=\<*) cat "${a#metadata=<}" > "$FAKE_CURL_LOG/$n.metadata" ;;
                file=@*) f="${a#file=@}"; if [[ -f "$f" ]]; then echo "exists $f" > "$FAKE_CURL_LOG/$n.file"; else echo "missing $f" > "$FAKE_CURL_LOG/$n.file"; fi ;;
            esac ;;
    esac
    case "$a" in http*) url="$a" ;; esac
    prev="$a"
done
[[ $stdin -eq 1 ]] && cat > "$FAKE_CURL_LOG/$n.stdin"
echo "$url" > "$FAKE_CURL_LOG/$n.url"
case "$url" in
    */api/game/versions) body="$(cat "$FAKE_CURL_VERSIONS")" ;;
    */upload-file) body="{\"id\": $((4240 + n))}" ;;
    *) body='{"errorMessage": "fake curl: unknown url"}' ;;
esac
if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
[[ -n "$fmt" ]] && printf '%s' "${fmt//%\{http_code\}/200}"
exit 0
]=])
    sh("chmod +x " .. q(FAKEBIN .. "/curl"))
    local _, rc = sh("cd " .. q(PUB) .. " && git init -q . && git add -A"
        .. " && git -c user.name=releasecheck -c user.email=releasecheck@invalid commit -qm 'publish tree'")
    pubReady = rc == 0 and Slurp(PUB .. "/release.sh") ~= nil
end

local function Commit(rel, text)
    Write(PUB .. "/" .. rel, text)
    return select(2, sh("cd " .. q(PUB) .. " && git add -A"
        .. " && git -c user.name=releasecheck -c user.email=releasecheck@invalid commit -qm " .. q(rel))) == 0
end

local function Config(project, tbcNames, foreverNames, releaseType)
    return "# test config\nproject_id = " .. project .. "\ntbc_game_versions = " .. tbcNames
        .. "\nforever_game_versions = " .. foreverNames .. "\nrelease_type = " .. (releaseType or "beta") .. "\n"
end

-- One run of the scratch tree's release.sh with the fake curl first on PATH;
-- the token set unless opts.noToken, under bash -x when opts.trace.
local function Publish(opts, ...)
    sh("rm -rf " .. q(CURL_LOG))
    local args = {}
    for _, a in ipairs({ ... }) do args[#args + 1] = q(a) end
    local env = "env -u WOW_ADDONS -u CURSEFORGE_API_TOKEN PATH=" .. q(FAKEBIN) .. ":\"$PATH\""
        .. " FAKE_CURL_LOG=" .. q(CURL_LOG) .. " FAKE_CURL_VERSIONS=" .. q(VERSIONS_JSON)
    if not opts.noToken then env = env .. " CURSEFORGE_API_TOKEN=" .. q(TOKEN) end
    return sh(env .. " bash " .. (opts.trace and "-x " or "") .. q(PUB .. "/release.sh") .. " " .. table.concat(args, " "))
end

-- What the fake recorded: one table per call, in order.
local function Calls()
    local t = {}
    local n = tonumber((Slurp(CURL_LOG .. "/count") or ""):match("%d+")) or 0
    for i = 1, n do
        local p = CURL_LOG .. "/" .. i
        t[i] = { argv = Slurp(p .. ".argv") or "", stdin = Slurp(p .. ".stdin") or "",
            url = (Slurp(p .. ".url") or ""):gsub("%s+$", ""), metadata = Slurp(p .. ".metadata"),
            file = Slurp(p .. ".file"), cwd = Slurp(p .. ".cwd") or "" }
    end
    return t
end

local function Uploads(calls)
    local t = {}
    for _, c in ipairs(calls) do if c.url:find("/upload-file", 1, true) then t[#t + 1] = c end end
    return t
end

-- A metadata JSON as "key<TAB>value" lines (gameVersions joined by commas), through python.
local function Meta(json)
    if not json then return {} end
    local path = SCRATCH .. "/meta.json"
    Write(path, json)
    local out = sh("python3 -c " .. q("import json, sys\n"
        .. "m = json.load(open(sys.argv[1], encoding='utf-8'))\n"
        .. "print('keys\\t' + ','.join(sorted(m)))\n"
        .. "for k in ('changelogType', 'displayName', 'releaseType'): print(k + '\\t' + str(m.get(k)))\n"
        .. "print('gameVersions\\t' + ','.join(str(v) + ':' + type(v).__name__ for v in m.get('gameVersions', [])))\n"
        .. "sys.stdout.buffer.write(b'changelog\\t' + json.dumps(m.get('changelog')).encode() + b'\\n')") .. " " .. q(path))
    local t = {}
    for line in out:gmatch("[^\n]+") do
        local k, v = line:match("^([^\t]+)\t(.*)$")
        if k then t[k] = v end
    end
    return t
end

local TREE_V = tostring(TREE_VERSION)
local CHANGELOG_JSON = '"## 2099-01-01 \\u2014 publish test\\n\\nA line with \\"quotes\\", a back\\\\slash'
    .. ' and a dash \\u2014 here.\\n\\n- one item"'

check("publish: the scratch repository of the tree is committed and clean", pubReady,
    "release.sh " .. tostring(Slurp(PUB .. "/release.sh") ~= nil))

-- the committed config: no project id yet -> refused before building, naming the file
do
    local cfg = Slurp(ROOT .. "/tools/data/curseforge.txt") or ""
    local out, rc = Publish({}, "--publish")
    check("publish: the committed tools/data/curseforge.txt has an empty project_id and refuses before building",
        pubReady and cfg:find("\nproject_id =[ \t]*\n") ~= nil and rc ~= 0
        and Has(out, "tools/data/curseforge.txt") and Has(out, "project_id")
        and #DirNames(PUB .. "/dist") == 0 and #Calls() == 0,
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
end

local CONFIG_OK = Config("123456", "2.5.6", "1.60.1")
local committed = pubReady and Commit("tools/data/curseforge.txt", CONFIG_OK)

do
    local out, rc = Publish({ noToken = true }, "--publish")
    check("publish: refused with no CURSEFORGE_API_TOKEN, before building, nothing sent",
        committed and rc ~= 0 and Has(out, "CURSEFORGE_API_TOKEN") and #DirNames(PUB .. "/dist") == 0 and #Calls() == 0,
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
end

do
    Write(PUB .. "/stray.txt", "uncommitted\n")
    local out, rc = Publish({}, "--publish")
    os.remove(PUB .. "/stray.txt")
    check("publish: refused on a tree with uncommitted changes, naming them",
        committed and rc ~= 0 and Has(out, "stray.txt") and #DirNames(PUB .. "/dist") == 0 and #Calls() == 0,
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
end

do
    local out, rc = Publish({}, "--publish", "--dry-run")
    local built = Slurp(PUB .. "/dist/publish tree/SpellTuner-tbc-" .. TREE_V .. ".zip") ~= nil
        and Slurp(PUB .. "/dist/publish tree/SpellTuner-forever-" .. TREE_V .. ".zip") ~= nil
    check("publish --dry-run: builds both, sends nothing, records nothing",
        committed and rc == 0 and built and #Calls() == 0 and Slurp(PUB_RECORD) == nil,
        "rc=" .. tostring(rc) .. " calls " .. #Calls() .. " " .. out:gsub("\n", " / "):sub(1, 200))
    check("publish --dry-run: prints both display names, the release type, the changelog and the URL, says only that the token is present",
        rc == 0 and Has(out, "SpellTuner " .. TREE_V .. " (TBC)") and Has(out, "SpellTuner " .. TREE_V .. " (Forever)")
        and Has(out, '"releaseType": "beta"') and Has(out, '"changelogType": "markdown"') and Has(out, "publish test")
        and Has(out, "/api/projects/123456/upload-file") and Has(out, "token: present") and not Has(out, TOKEN),
        out:gsub("\n", " / "):sub(1, 240))
end

do
    -- Forever's name is one CurseForge does not list (Forever not on CurseForge yet)
    local wrote = pubReady and Commit("tools/data/curseforge.txt", Config("123456", "2.5.6", "1.60.1, 9.9.9-nope"))
    local out, rc = Publish({}, "--publish")
    local calls = Calls()
    check("publish: a game version name CurseForge does not list is refused by name before any upload",
        wrote and rc ~= 0 and Has(out, "9.9.9-nope") and Has(out, "forever") and #calls == 1
        and calls[1].url == "https://wow.curseforge.com/api/game/versions" and #Uploads(calls) == 0
        and Slurp(PUB_RECORD) == nil,
        "rc=" .. tostring(rc) .. " calls " .. #calls .. " " .. out:gsub("\n", " / "):sub(1, 200))
    check("publish: the refusal names the flavour that does resolve and offers --only tbc",
        rc ~= 0 and Has(out, "--only tbc"), out:gsub("\n", " / "):sub(1, 200))
end

do
    local out, rc = Publish({ trace = true }, "--publish", "--only", "tbc", "--release-type", "alpha")
    local calls = Calls()
    local ups = Uploads(calls)
    local meta = Meta(ups[1] and ups[1].metadata)
    check("publish --only tbc: one versions read, then one upload of the TBC zip",
        committed and rc == 0 and #calls == 2 and calls[1].url == "https://wow.curseforge.com/api/game/versions"
        and #ups == 1 and ups[1].url == "https://wow.curseforge.com/api/projects/123456/upload-file"
        and Has(ups[1].file, "exists") and Has(ups[1].file, "SpellTuner-tbc-" .. TREE_V .. ".zip"),
        "rc=" .. tostring(rc) .. " calls " .. #calls .. " " .. out:gsub("\n", " / "):sub(-240))
    check("publish: a game version name resolves to its id (2.5.6 -> 10101)",
        meta.gameVersions == "10101:int", tostring(meta.gameVersions))
    check("publish: the metadata JSON -- display name, markdown changelog of the newest HISTORY entry, --release-type",
        meta.keys == "changelog,changelogType,displayName,gameVersions,releaseType"
        and meta.displayName == "SpellTuner " .. TREE_V .. " (TBC)" and meta.changelogType == "markdown"
        and meta.releaseType == "alpha" and meta.changelog == CHANGELOG_JSON,
        tostring(meta.keys) .. " " .. tostring(meta.displayName) .. " " .. tostring(meta.releaseType)
        .. " " .. tostring(meta.changelog))
    local inArgv, viaStdin = false, true
    for _, c in ipairs(calls) do
        if Has(c.argv, TOKEN) or Has(c.cwd, TOKEN) then inArgv = true end
        if not Has(c.stdin, 'header = "X-Api-Token: ' .. TOKEN .. '"') then viaStdin = false end
    end
    check("publish: the token reaches curl only on stdin -- in no argv and in nothing printed, even under bash -x",
        rc == 0 and #calls == 2 and not inArgv and viaStdin and not Has(out, TOKEN) and Has(out, "+ "),
        "argv " .. tostring(inArgv) .. " stdin " .. tostring(viaStdin) .. " printed " .. tostring(Has(out, TOKEN)))
    local record = Slurp(PUB_RECORD) or ""
    local id = ups[1] and (4240 + 2)
    check("publish: the file id is printed and recorded in dist/<name>/published.txt",
        rc == 0 and Has(out, "file id " .. tostring(id)) and Has(record, TREE_V .. "\ttbc\t" .. tostring(id)),
        record:gsub("\n", " / "))
end

do
    local before = Slurp(PUB_RECORD)
    local out, rc = Publish({}, "--publish", "--only", "tbc")
    check("publish: a second upload of the same version is refused, before anything is sent",
        committed and rc ~= 0 and Has(out, "already published") and #Calls() == 0 and Slurp(PUB_RECORD) == before,
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(1, 200))
end

do
    local wrote = pubReady and Commit("tools/data/curseforge.txt", Config("123456", "2.5.6", "1.60.1"))
    local out, rc = Publish({}, "--publish", "--only", "forever")
    local ups = Uploads(Calls())
    local meta = Meta(ups[1] and ups[1].metadata)
    local record = Slurp(PUB_RECORD) or ""
    check("publish --only forever: the Forever zip under its own name, ids and the config's release type",
        wrote and rc == 0 and #ups == 1 and Has(ups[1].file, "exists")
        and Has(ups[1].file, "SpellTuner-forever-" .. TREE_V .. ".zip")
        and meta.displayName == "SpellTuner " .. TREE_V .. " (Forever)" and meta.gameVersions == "20201:int"
        and meta.releaseType == "beta" and Has(record, TREE_V .. "\ttbc\t") and Has(record, TREE_V .. "\tforever\t"),
        "rc=" .. tostring(rc) .. " " .. out:gsub("\n", " / "):sub(-200))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL: " .. f) end
os.exit(#fails == 0 and 0 or 1)
