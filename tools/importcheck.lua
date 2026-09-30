-- tools/run.sh tools/importcheck.lua
--
-- The recordings pipeline (docs/TOOLS.md §2): tools/import.lua on a Forever
-- SavedVariables file. No harness of its own -- it runs import.lua the way
-- the planner does, as a command, on tools/data/import-forever-sv.lua (built
-- by tools/importfixture.lua with the real Practice and Recorder code: two
-- practice fights, one stored with its kit and one without, and one v3
-- pull), and reads what it prints and writes. Scratch files go under
-- tools/.lua/importcheck/ (ignored).
local root = arg[1] or "."
local LUA = root .. "/tools/.lua/lua-5.1.5/src/lua"
local FIXTURE = root .. "/tools/data/import-forever-sv.lua"
local SCRATCH = root .. "/tools/.lua/importcheck"
os.execute(string.format("rm -rf %q && mkdir -p %q", SCRATCH, SCRATCH))

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-92s %s%s", name, cond and "ok" or "FAIL", (not cond and detail) and (" - " .. detail) or ""))
end

-- one command: its output and whether it exited 0
local runN = 0
local function Import(args, env)
    runN = runN + 1
    local out = string.format("%s/run%d.txt", SCRATCH, runN)
    local status = os.execute(string.format("%s bash %q tools/import.lua %s > %q 2>&1",
        env or "env -u ST_FLAVOUR -u MD_SAVEDVARS", root .. "/tools/run.sh", args, out))
    local f = io.open(out, "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    return text, status == 0
end
local function Has(text, s) return text:find(s, 1, true) ~= nil end
local function Line(text, prefix)
    for l in text:gmatch("[^\n]+") do if l:sub(1, #prefix) == prefix then return l end end
    return nil
end
local function Numbers(line)
    local t = {}
    for n in (line or ""):gmatch("%-?%d+%.?%d*") do t[#t + 1] = tonumber(n) end
    return t
end

-- the fixture as data, to hold the tool's numbers against
local function LoadSV(path)
    local env = {}
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
    return env.SpellTunerDB
end
local db = LoadSV(FIXTURE)
local CHAR = "Healroot-Classic Beta PvP"
local cdb = db.char[CHAR]
local function Newest(list)
    local l = {}
    for _, r in ipairs(list or {}) do l[#l + 1] = r end
    table.sort(l, function(a, b) return a.id > b.id end)
    return l
end
local practice, recordings = Newest(cdb.practice), Newest(cdb.recordings)
local p1, p2, r1 = practice[1], practice[2], recordings[1]

--------------------------------------------------------------------------------
-- 1: the committed fixture is what the code writes today
--------------------------------------------------------------------------------
do
    local fresh = SCRATCH .. "/fixture.lua"
    local status = os.execute(string.format("bash %q tools/importfixture.lua %q > %q 2>&1",
        root .. "/tools/run.sh", fresh, SCRATCH .. "/fixture.log"))
    local a, b = io.open(FIXTURE, "rb"), io.open(fresh, "rb")
    local same = a and b and a:read("*a") == b:read("*a")
    if a then a:close() end
    if b then b:close() end
    check("the committed fixture is what tools/importfixture.lua writes today", status == 0 and same,
        "rebuild with: bash tools/run.sh tools/importfixture.lua")
end

--------------------------------------------------------------------------------
-- 2: the game's own code keeps each fight's kit (Kit_Forever.lua's
--    KitSnapshot, on practice fights and real pulls) and the character's last
--    one (cdb.kit) -- the spells the fight was played with, which the stub's
--    spellbook does not have
--------------------------------------------------------------------------------
check("a practice fight and a v3 pull are stored with their kit, the character with its last one",
    p1 and p1.kit and p1.kit.caster[5186] and p1.kit.caster[5186].family == "HealingTouch"
    and r1 and r1.v == 3 and r1.kit and r1.kit.caster[5186] and cdb.kit and cdb.kit.caster[5186]
    and p2 and p2.kit == nil,
    string.format("p1.kit=%s r1.kit=%s cdb.kit=%s p2.kit=%s", tostring(p1 and p1.kit), tostring(r1 and r1.kit),
        tostring(cdb.kit), tostring(p2 and p2.kit)))

-- one kit record (MD.SimModel.KitSnapshot) on every one of them: the entries a
-- replay reads and nothing else -- no copy of the MD.SpellData index, no table
-- inside an entry -- and a practice fight says who played it
local function Lean(k)
    if type(k) ~= "table" or k.sd ~= nil then return false end
    for _, v in pairs(k) do
        if type(v) == "table" then
            for _, e in pairs(v) do
                if type(e) ~= "table" then return false end
                for _, x in pairs(e) do if type(x) == "table" then return false end end
            end
        end
    end
    return true
end
check("every stored kit is the one lean record; a practice fight carries client, level and version",
    p1 and Lean(p1.kit) and r1 and Lean(r1.kit) and Lean(cdb.kit)
    and p1.client == "forever" and p1.level == 10 and type(p1.version) == "string"
    and p2 and p2.client == nil,
    string.format("p1 client=%s level=%s version=%s", tostring(p1 and p1.client), tostring(p1 and p1.level),
        tostring(p1 and p1.version)))

--------------------------------------------------------------------------------
-- 3: read as Forever without being told, and by --flavour / run.sh --flavour
--------------------------------------------------------------------------------
local F = string.format("--file %q", FIXTURE)
local list, listOk = Import(F .. " list")
local told = Import(F .. " --flavour forever list")
local viaRun = Import(F .. " list", "env -u MD_SAVEDVARS ST_FLAVOUR=forever")
check("a Forever file is read as Forever, told or not",
    listOk and Has(list, "client: forever (read from the file: a v3 recording)")
    and Has(told, "client: forever (--flavour forever)") and Has(viaRun, "client: forever (--flavour forever)"),
    Line(list, "client:") or list:sub(1, 200))

--------------------------------------------------------------------------------
-- 4: list -- the recording and both practice fights, their kit and verdict
--------------------------------------------------------------------------------
do
    local l1, lp1, lp2 = Line(list, "1 "), Line(list, "p1 "), Line(list, "p2 ")
    check("list shows the v3 pull and the practice fights p1..pN with kit and verdict",
        l1 and Has(l1, "The Barrens") and Has(l1, "recorded")
        and lp1 and Has(lp1, "Practice: Party") and Has(lp1, "recorded") and lp1:match(" ok$")
        and lp2 and Has(lp2, "inferred") and lp2:match(" ok$")
        and Has(list, CHAR .. "   (1 recording(s), 2 practice fight(s))"),
        (l1 or "no 1") .. " / " .. (lp1 or "no p1") .. " / " .. (lp2 or "no p2"))
end

--------------------------------------------------------------------------------
-- 5: validate -- the Forever gates, as /st validate prints them
--------------------------------------------------------------------------------
do
    local vp, vpOk = Import(F .. " validate p1")
    local v1 = Import(F .. " validate 1")
    check("validate prints the Forever gate report for a practice fight and a v3 pull",
        vpOk and Has(vp, "verdict: REPLAYS") and Has(vp, "spend coverage     ok")
        and Has(v1, "verdict: does NOT replay") and Has(v1, "heals attributed") and Has(v1, "(modelled pool)"),
        vp:sub(1, 300))
end

--------------------------------------------------------------------------------
-- 6: replay pN --strategy -- both columns as text, YOU exactly the fight that
--    was played (spent, and the mana the recording wrote at its end)
--------------------------------------------------------------------------------
local function Column(text, name)
    local l = Line(text, name .. " ")
    local n = Numbers(l)
    -- spent, regen, overheal, lowest, dead, mana end, out of 5SR
    return l and { spent = n[1], regen = n[2], manaEnd = n[6], outside = n[7], line = l } or nil
end
local function LastMana(rec) return rec.mana.v[#rec.mana.v] end
do
    local rp, rpOk = Import(F .. " replay p1 --strategy solver-frugal")
    local you, plan = Column(rp, "YOU"), Column(rp, "SUGGESTED")
    local rows = 0
    for l in rp:gmatch("[^\n]+") do if l:match("^%s+%d+%.%d  %s*%d+[%* ]") then rows = rows + 1 end end
    local casts = 0
    local inCasts = false
    for l in rp:gmatch("[^\n]+") do
        if l:find("^your casts") then inCasts = true
        elseif l:find("^the plan") then inCasts = false
        elseif inCasts and l:match("^%s+%d+%.%d%d  %a") then casts = casts + 1 end
    end
    check("replay pN prints both columns; YOU is the fight as played, to the mana at its end",
        rpOk and you and plan and you.spent == p1.spent and math.abs(you.manaEnd - LastMana(p1)) <= 1
        and Has(plan.line, "Solver: frugal") and Has(rp, "kit:   recorded with the fight")
        and rows == math.floor(p1.dur / 2) + 1 and casts == p1.ownCasts,
        string.format("you=%s plan=%s want spent %d mana end %.0f, rows %d casts %d/%d",
            you and you.line or "nil", plan and plan.line or "nil", p1.spent, LastMana(p1), rows, casts, p1.ownCasts))
    check("replay marks the moments outside the five-second rule and counts them per column",
        Has(rp, "(* = outside the five-second rule") and you and you.outside and you.outside > 0
        and rp:find("%d%*") ~= nil and Has(rp, "out of 5SR"),
        you and you.line or "nil")
    check("replay lists the plan's casts with their reasons and its waits",
        Has(rp, "the plan's casts and waits of 2s or more") and Has(rp, "per mana") and Has(rp, "wait "),
        rp:sub(-400))
end

--------------------------------------------------------------------------------
-- 7: a practice fight stored without its kit (0.16.1) replays exactly from
--    the kit read back off its own heals -- the stub's spellbook has no
--    Healing Touch R2 and could not
--------------------------------------------------------------------------------
do
    local rp = Import(F .. " replay p2 --strategy rules")
    local you = Column(rp, "YOU")
    check("a practice fight stored without its kit replays exactly from its own heals",
        you and you.spent == p2.spent and math.abs(you.manaEnd - LastMana(p2)) <= 1
        and Has(rp, "kit:   read back off the fight's own heals") and Has(rp, "verdict: REPLAYS")
        and Has(rp, "HealingTouch R2"),
        string.format("%s want %d / %.0f", you and you.line or "nil", p2.spent, LastMana(p2)))
end

--------------------------------------------------------------------------------
-- 8: the kit fallbacks say so -- a pull without its kit uses the character's
--    last one, and with neither, the stub's book, and both are named
--------------------------------------------------------------------------------
do
    local W = dofile(root .. "/tools/svwrite.lua")
    local variant = LoadSV(FIXTURE)
    local vc = variant.char[CHAR]
    for _, r in ipairs(vc.recordings) do r.kit = nil end
    local lastPath = SCRATCH .. "/nokit-last.lua"
    W.Write(lastPath, { SpellTunerDB = variant })
    local last = Import(string.format("--file %q list", lastPath))
    local lastRp = Import(string.format("--file %q validate 1", lastPath))
    vc.kit = nil
    local stubPath = SCRATCH .. "/nokit-stub.lua"
    W.Write(stubPath, { SpellTunerDB = variant })
    local stub = Import(string.format("--file %q list", stubPath))
    local stubRp = Import(string.format("--file %q validate 1", stubPath))
    check("without its kit a pull uses the character's last kit, then the stub's book, and says which",
        Line(last, "1 ") and Has(Line(last, "1 "), " last ") and Has(lastRp, "kit:   NOT this fight's - the character's last kit")
        and Line(stub, "1 ") and Has(Line(stub, "1 "), " STUB ") and Has(stubRp, "kit:   NOT this fight's - the stub's spellbook"),
        (Line(last, "1 ") or "?") .. " / " .. (Line(stub, "1 ") or "?"))
end

--------------------------------------------------------------------------------
-- 9: coach -- the search and its card on a practice fight; a v3 pull that
--    fails its gates refused, and carded with force
--------------------------------------------------------------------------------
do
    local c, cOk = Import(F .. " coach p1")
    check("coach pN searches and prints the card",
        cOk and Has(c, "Bind: ") and Has(c, "strategies (one search, four ways of reading it)")
        and c:find("search: %d+ plans evaluated") ~= nil,
        c:sub(1, 300))
    local refused = Import(F .. " coach 1")
    local forced = Import(F .. " coach 1 force")
    check("coach on a pull that fails its gates refuses, and force prints the card anyway",
        Has(refused, "coach: this fight does not replay") and not Has(refused, "Bind: ")
        and Has(forced, "Bind: ") and Has(forced, "gates failed"),
        refused:sub(1, 200))
end

--------------------------------------------------------------------------------
-- 10: coach --strategy -- the chosen strategy's own card
--------------------------------------------------------------------------------
do
    local c, cOk = Import(F .. " coach p1 --strategy solver-frugal")
    local you, plan = Line(c, "  you "), Line(c, "  plan ")
    check("coach --strategy prints that strategy's card: binds, both columns, your casts against it",
        cOk and Has(c, "strategy: Solver: frugal - ") and Has(c, "  binds: ") and you and plan
        and Numbers(you)[1] == p1.spent and Has(c, "the plan spends") and Has(c, "your casts against it: "),
        c:sub(-600))
    local bad, badOk = Import(F .. " replay p1 --strategy nonsense")
    check("an unknown strategy is refused with the list of them",
        not badOk and Has(bad, 'unknown strategy "nonsense"') and Has(bad, "solver-frugal") and Has(bad, "regen"),
        bad:sub(-200))
end

--------------------------------------------------------------------------------
-- 11: export -- the fight as a SavedVariables file of its own, which imports
--     again, and the replay text beside it
--------------------------------------------------------------------------------
do
    local out = SCRATCH .. "/export"
    local e, eOk = Import(F .. string.format(" export p1 --strategy solver-frugal --out %q", out))
    local base = string.format("%s/p1-%d", out, p1.id)
    local txt = io.open(base .. ".txt", "r")
    local text = txt and txt:read("*a") or ""
    if txt then txt:close() end
    local again = Import(string.format("--file %q list", base .. ".lua"))
    local lp1 = Line(again, "p1 ")
    check("export writes the fight as an importable file and the replay as text",
        eOk and Has(e, "wrote ") and Has(text, "YOU ") and Has(text, "SUGGESTED ") and Has(text, "your casts")
        and lp1 and Has(lp1, "recorded") and lp1:match(" ok$") and Has(again, "(0 recording(s), 1 practice fight(s))"),
        (lp1 or again:sub(1, 300)))
end

--------------------------------------------------------------------------------
-- 11b: report -- the fight replayed beside every strategy (it was
--      tools/practicereport.lua's), on a SavedVariables file and on a
--      { rec, kit } fixture read with --fixture
--------------------------------------------------------------------------------
do
    local r, rOk = Import(F .. " report p1")
    local you = Line(r, "  you (the replay)")
    local rows = 0
    for l in r:gmatch("[^\n]+") do if l:match("^  Solver: ") or l:match("^  Rules: ") then rows = rows + 1 end end
    check("report pN puts the replay beside every strategy, with who played it",
        rOk and you and Numbers(you)[1] == p1.spent and rows >= 6 and Has(r, "gates: PASS")
        and Has(r, "played on forever, level 10") and Has(r, "kit:   recorded with the fight"),
        (you or "no you row") .. " / " .. rows .. " rows / " .. r:sub(1, 200))
    local fx, fxOk = Import(string.format("--fixture %q report", root .. "/tools/data/practice/1790701698.lua"))
    local fxYou = Line(fx, "  you (the replay)")
    check("report on a fixture (--fixture): the author's fight, every gate passing with its kit",
        fxOk and fxYou and Has(fx, "gates: PASS") and Has(fx, "Solver: frugal"),
        fx:sub(1, 400))
end

--------------------------------------------------------------------------------
-- 12: a TBC file still takes the TBC road
--------------------------------------------------------------------------------
do
    local W = dofile(root .. "/tools/svwrite.lua")
    local path = SCRATCH .. "/tbc.lua"
    W.Write(path, { SpellTunerDB = { char = { ["Penek-Anniversary"] = { recordings = {}, fights = {} } } } })
    local t = Import(string.format("--file %q list", path))
    local forced = Import(string.format("--file %q --flavour tbc list", FIXTURE))
    check("a TBC file is read as TBC, and --flavour tbc on a Forever file says what it looks like",
        not Has(t, "client: forever") and Has(t, "char:  Penek-Anniversary") and Has(t, "no recordings.")
        and Has(forced, "looks like a Forever one (a v3 recording)"),
        t:sub(1, 300))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
