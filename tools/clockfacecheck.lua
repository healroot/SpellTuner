-- tools/run.sh [--flavour tbc|forever] tools/clockfacecheck.lua [--print | --golden]
--
-- T88 (docs/SPEC-next.md 2.4, S4 step 1, task K1 of docs/research/next/R-clock.md):
-- the clock face. What the mana clock SAYS is a pure record (`face`), built by
-- each line's producer -- TBC `MD:GetClockFace()` in Engine/TTO.lua, Forever
-- `MD.ManaModel.Face(state, now)` in Engine/ManaModel.lua, each provided as
-- `MD.ClockFace.Current` -- and the words and colour codes are assembled in
-- ONE place, `MD.ClockFace.LineString(face, valueHex)` (Engine/ClockFace.lua,
-- pure). `MD:GetDisplayString(valueHex)` and `MD.ManaModel.Text(state)` are
-- wrappers over it and must stay byte-identical.
--
-- What is held:
--   1. Engine/ClockFace.lua loads, and renders every sample, in an environment
--      holding nothing but Lua's own library -- no frame API, no client call,
--      no MD.db (an unknown global raises);
--   2. the goldens, captured with --golden on the parent commit (e2b13f4)
--      BEFORE Engine/TTO.lua or Engine/ManaModel.lua was edited:
--        tbc:     GetDisplayString(nil) and GetDisplayString("|cff16c3f2") over
--                 a scripted fight (real events, the real latch, every tick)
--                 and over a grid of display states set straight into TTO's
--                 own `disp` / `state` (every mode, the bound, the arrow,
--                 "vv", the cd and rest segments with the 25 % rule, nil,
--                 >10m, showRest / showCooldown off) -- including `OOM 15s vv`,
--                 `FULL --` (nodata) and `OOM --` (oom with no value);
--        forever: ManaModel.Text over every mode x time x rest, the 5 s
--                 rounding edges, nil, a negative, >10m, a non-table;
--   3. the face API (fails on the parent: there is none): the producer exists,
--      is provided as ClockFace.Current, LineString of its face IS the string,
--      the "vv" crit face and the "nodata" face are what the spec names;
--   4. ClockFace.SAMPLES: every sample, as TBC and as Forever would draw it,
--      ASCII, no bare pipe, no "nil", and a missing value never a 0;
--   5. T93 (docs/SPEC-next.md 7.3 "When", F3): MD.Visibility.Want with a show
--      rule -- the default rule is the parent's Want on every case, however
--      it is asked; ooc = "never" (beside "always" and combat "never");
--      manaUsersOnly. UI/Visibility.lua loaded with Lua's library only.
--   6. T98 (docs/SPEC-next.md 7.3): the clock's look (UI/ClockView.lua's
--      CV.Resolve) -- `over` wins over the style's clock role, the role over
--      the layout's defaults; "Reset to style" wipes `over` (the layout kept,
--      CLOCK_LOOK once). TBC loads the four UI files it needs here.
--
-- `--print` prints the transcript; `--golden` prints the golden blocks to paste.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local mode = "check"
for i = 1, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local FLAVOUR = S.flavour

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. tostring(detail)) or ""))
end

local HEX = "|cff16c3f2"

-- A rendered string is clean when, its colour codes removed, it is printable
-- ASCII with no pipe left (every "|" was part of "|cffRRGGBB" or "|r").
local function Strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Clean(s)
    if type(s) ~= "string" then return false end
    if s:find("[\128-\255]") then return false end
    local plain = Strip(s)
    if plain:find("|", 1, true) then return false end
    return plain:match("^[\32-\126]*$") ~= nil
end
-- A time token that is a zero: "0s", "0:00".
local function ZeroTime(s)
    local plain = Strip(s)
    return plain:find("%f[%w]0s%f[%W]") ~= nil or plain:find("%f[%d]0:00") ~= nil
end

-- Lines of a golden block: "id<TAB>string[<TAB>string with HEX]" (the second
-- only where it differs from the first).
local function Line(id, a, b)
    if b ~= nil and b ~= a then return id .. "\t" .. a .. "\t" .. b end
    return id .. "\t" .. a
end
local function Fmt(v)
    if v == nil then return "nil" end
    if v == math.huge then return "inf" end
    return tostring(v)
end

--------------------------------------------------------------------------------
-- 1. Engine/ClockFace.lua is pure: Lua's library and nothing else.
--------------------------------------------------------------------------------
local pureCF, pureErr
do
    local chunk, err = loadfile(S.root .. "/Engine/ClockFace.lua")
    if chunk then
        local touched = {}
        local env = {
            string = string, math = math, table = table, type = type, pairs = pairs,
            ipairs = ipairs, tostring = tostring, tonumber = tonumber, select = select,
            next = next, setmetatable = setmetatable, getmetatable = getmetatable,
            error = error, pcall = pcall, rawget = rawget, rawset = rawset, unpack = unpack,
        }
        setmetatable(env, {
            __index = function(_, k) touched[#touched + 1] = tostring(k); error("global " .. tostring(k), 2) end,
            __newindex = function(_, k) touched[#touched + 1] = "set " .. tostring(k); error("sets global " .. tostring(k), 2) end,
        })
        setfenv(chunk, env)
        local fakeMD = {}
        local okLoad, e = pcall(chunk, "SpellTuner", fakeMD)
        if okLoad then
            pureCF = fakeMD.ClockFace
            -- render every sample in the same environment: no client call at render time either
            if pureCF and pureCF.SAMPLES and pureCF.LineString then
                for _, smp in ipairs(pureCF.SAMPLES) do
                    local okR, eR = pcall(pureCF.LineString, smp.face, HEX)
                    if not okR then pureErr = "render " .. tostring(smp.key) .. ": " .. tostring(eR) break end
                    okR, eR = pcall(pureCF.LineString, smp.face)
                    if not okR then pureErr = "render " .. tostring(smp.key) .. ": " .. tostring(eR) break end
                end
            end
        else
            pureErr = tostring(e)
        end
        if #touched > 0 then pureErr = (pureErr or "") .. " touched: " .. table.concat(touched, ",") end
    else
        pureErr = tostring(err)
    end
end
check("1. Engine/ClockFace.lua loads and renders with Lua's library only (no frame API)",
    pureCF ~= nil and type(pureCF.LineString) == "function" and type(pureCF.SAMPLES) == "table"
        and pureErr == nil, pureErr)

local CF = MD.ClockFace
check("1b. the file is loaded by this flavour's TOC (MD.ClockFace.LineString)",
    type(CF) == "table" and type(CF.LineString) == "function")

--------------------------------------------------------------------------------
-- 2. The transcripts the goldens hold.
--------------------------------------------------------------------------------
local transcript = {}
local function Rec(id, a, b) transcript[#transcript + 1] = Line(id, a, b) end

-- Every upvalue named `name` reachable from fn (fn's own, then one level into
-- the functions it closes over): TTO's `disp` and `state` locals, wherever the
-- display function lives (the parent's GetDisplayString, or GetClockFace).
local function FindUpvalue(fn, name, depth, seen)
    depth, seen = depth or 0, seen or {}
    if type(fn) ~= "function" or seen[fn] or depth > 3 then return nil end
    seen[fn] = true
    local i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if n == name then return fn, i, v end
        i = i + 1
    end
    i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if type(v) == "function" then
            local f, j, val = FindUpvalue(v, name, depth + 1, seen)
            if f then return f, j, val end
        end
        i = i + 1
    end
    return nil
end
local function FindTTO(name)
    for _, key in ipairs({ "GetClockFace", "GetDisplayString" }) do
        local f, i, v = FindUpvalue(MD[key], name)
        if f then return f, i, v end
    end
    return nil
end

local unreachableFullNil -- tbc: the one state the face renders differently (section 3)

if FLAVOUR == "tbc" then
    ----------------------------------------------------------------------------
    -- 2a. A scripted fight through the real events and the real latch
    -- (ttocheck's stream: Healing Touch rank 5 against a scripted regen).
    ----------------------------------------------------------------------------
    local regenBase, regenCast = 10, 5
    _G.GetManaRegen = function() return regenBase, regenCast end
    local SD = MD.SpellData
    local HT5 = 5189
    local function Cast(id)
        S.mana = S.mana - SD:GetCost(id)
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", id)
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
    local tick = 0
    local function Ticks(n, label)
        for _ = 1, n do
            S.Tick(0.5)
            tick = tick + 1
            Rec(string.format("fight %03d %s", tick, label), MD:GetDisplayString(), MD:GetDisplayString(HEX))
        end
    end
    Ticks(4, "full, out of combat")
    S.mana = 5200; S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    Ticks(6, "out of combat at 74%")
    S.Fire("PLAYER_REGEN_DISABLED")
    Ticks(2, "pull")
    for i = 1, 14 do                       -- a cast every 2 s: warmup, then oom
        Cast(HT5)
        Ticks(4, "casting every 2s #" .. i)
    end
    for i = 1, 6 do                        -- every 3.5 s: slower drain
        Cast(HT5)
        Ticks(7, "casting every 3.5s #" .. i)
    end
    Ticks(30, "stopped casting")           -- the clock goes up
    regenBase, regenCast = 400, 200        -- regen outruns the spend: full
    Ticks(12, "regen up")
    regenBase, regenCast = 10, 5
    for i = 1, 14 do                       -- a cast every second: into the crit band
        if S.mana > 300 then Cast(HT5) end
        Ticks(2, "casting every 1s #" .. i)
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    Ticks(8, "left combat")
    S.mana = 100; S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    regenBase, regenCast = 1, 0.5          -- a long way from full: >10m
    Ticks(6, "out of combat, slow regen")
    regenBase, regenCast = 0, 0
    Ticks(6, "out of combat, no regen")    -- nodata: FULL --

    ----------------------------------------------------------------------------
    -- 2b. A grid of display states set straight into TTO's own locals.
    ----------------------------------------------------------------------------
    local dispF, dispI, disp = FindTTO("disp")
    local stateF, stateI = FindTTO("state")
    check("2. TTO's display locals (disp, state) are reachable for the grid",
        dispF ~= nil and type(disp) == "table" and stateF ~= nil)
    local function SetState(st) debug.setupvalue(stateF, stateI, st) end

    local HISTORY = {
        none = function() return {} end,
        eq   = function(v) return { { S.now - 10, (v or 0) + 10 } } end, -- change 0  -> "="
        down = function(v) return { { S.now - 10, (v or 0) + 30 } } end, -- change -20 -> "v"
        up   = function(v) return { { S.now - 10, (v or 0) - 10 } } end, -- change 20 -> "^"
    }
    local saveRest, saveCd = MD.db.showRest, MD.db.showCooldown
    local function Render(id, d, st, dbo)
        disp.mode = d.mode
        disp.value = d.value
        disp.bounded = d.bounded or false
        disp.step = d.step or 5
        local h = HISTORY[d.history or "none"](d.value)
        for k in pairs(disp.history) do disp.history[k] = nil end
        for k, e in ipairs(h) do disp.history[k] = e end
        SetState({
            inCombat = st.inCombat, stable = st.stable ~= false, rest = st.rest, cd = st.cd,
            manaMax = st.manaMax or 10000, mana = 5000, pct = 0.5, regenNow = 5, mode = d.mode,
        })
        MD.db.showRest = dbo and dbo.showRest
        if MD.db.showRest == nil then MD.db.showRest = saveRest end
        MD.db.showCooldown = dbo and dbo.showCooldown
        if MD.db.showCooldown == nil then MD.db.showCooldown = saveCd end
        Rec(id, MD:GetDisplayString(), MD:GetDisplayString(HEX))
    end

    local MODES = { "fullnow", "nodata", "ooc", "full", "warmup", "hold", "oom" }
    local VALUES = { nil, 0, 15, 19, 20, 45, 59, 60, 61, 90, 125, 600, 601, 605, 900 }
    local NV = 15
    -- A: every mode x value x in/out of combat
    for _, m in ipairs(MODES) do
        for vi = 1, NV do
            local v = VALUES[vi]
            for _, c in ipairs({ false, true }) do
                if not ((m == "ooc" or m == "full") and v == nil) then -- unreachable: section 3
                    Render(string.format("A %s v=%s combat=%s", m, Fmt(v), tostring(c)),
                        { mode = m, value = v }, { inCombat = c, rest = 300 })
                end
            end
        end
    end
    -- B: oom -- value x bounded x stable x arrow history
    local BV = { nil, 15, 45, 60, 90, 125, 605 }
    for vi = 1, 7 do
        local v = BV[vi]
        for _, b in ipairs({ false, true }) do
            for _, stable in ipairs({ true, false }) do
                for _, hk in ipairs({ "none", "eq", "down", "up" }) do
                    Render(string.format("B oom v=%s bounded=%s stable=%s arrow=%s", Fmt(v), tostring(b), tostring(stable), hk),
                        { mode = "oom", value = v, bounded = b, history = hk }, { inCombat = true, stable = stable, rest = 300 })
                end
            end
        end
    end
    -- C: the rest segment's 25 % rule, in combat
    local CV = { nil, 60, 90, 700 }
    local CR = { nil, 20.4, 29.6, 50, 75, 100, 700 }
    for _, m in ipairs({ "warmup", "hold", "oom" }) do
        for vi = 1, 4 do
            for ri = 1, 7 do
                local v, r = CV[vi], CR[ri]
                Render(string.format("C %s v=%s rest=%s", m, Fmt(v), Fmt(r)),
                    { mode = m, value = v }, { inCombat = true, rest = r })
                if m == "oom" then
                    Render(string.format("C oom bounded v=%s rest=%s", Fmt(v), Fmt(r)),
                        { mode = m, value = v, bounded = true }, { inCombat = true, rest = r })
                end
            end
        end
    end
    -- D: the mana cooldown segment ("inn"), and the two switches
    local CDS = {
        { short = "inn", tto = 40, delta = 2000 },
        { short = "inn", tto = 130, delta = 2000 },
        { short = "inn", tto = 130, delta = 500 },   -- under 10 % of the pool: not offered
        { short = "inn", tto = nil, delta = 2000 },  -- no projection: not offered
    }
    for ci, cd in ipairs(CDS) do
        for _, v in ipairs({ 60, 90, 95 }) do
            for _, b in ipairs({ false, true }) do
                for _, sc in ipairs({ true, false }) do
                    Render(string.format("D cd%d v=%s bounded=%s showCooldown=%s", ci, Fmt(v), tostring(b), tostring(sc)),
                        { mode = "oom", value = v, bounded = b }, { inCombat = true, rest = 400, cd = cd },
                        { showCooldown = sc })
                end
            end
        end
        Render(string.format("D cd%d hold v=90", ci), { mode = "hold", value = 90 }, { inCombat = true, rest = 400, cd = cd })
        Render(string.format("D cd%d out of combat v=90", ci), { mode = "oom", value = 90 }, { inCombat = false, rest = 400, cd = cd })
    end
    for _, m in ipairs({ "warmup", "hold", "oom" }) do
        Render("E " .. m .. " showRest=false", { mode = m, value = 60 }, { inCombat = true, rest = 400 }, { showRest = false })
    end

    -- The one state the face renders differently from the parent, kept out of
    -- the golden and asserted in section 3: FULL with no value (TTO's latch
    -- never reaches it -- the latch resets the value only on a mode the raw
    -- state already holds, and the raw ooc / full always carry ttf).
    unreachableFullNil = function()
        local out = {}
        for _, m in ipairs({ "ooc", "full" }) do
            Render("Z " .. m .. " v=nil", { mode = m, value = nil }, { inCombat = m == "full", rest = 300 })
            out[m] = { transcript[#transcript], MD:GetDisplayString(), MD:GetDisplayString(HEX) }
            transcript[#transcript] = nil
        end
        return out
    end
    MD.db.showRest, MD.db.showCooldown = saveRest, saveCd
else
    ----------------------------------------------------------------------------
    -- 2c. Forever: ManaModel.Text over every mode x time x rest.
    ----------------------------------------------------------------------------
    local Text = MD.ManaModel.Text
    local TIMES = { nil, -3, 0, 2.4, 2.6, 10, 19, 59, 62.4, 597.6, 600, 600.4, 601, 602.6, 1e9, math.huge }
    local NT = 16
    local RESTS = { nil, "same", "x1.2", "x1.3", "x0.7", 30, 700 }
    local function RestOf(r, t)
        if r == "same" then return t end
        if r == "x1.2" then return t and t * 1.2 end
        if r == "x1.3" then return t and t * 1.3 end
        if r == "x0.7" then return t and t * 0.7 end
        return r
    end
    for _, m in ipairs({ "fullnow", "ooc", "full" }) do
        for ti = 1, NT do
            local t = TIMES[ti]
            Rec(string.format("F %s ttf=%s", m, Fmt(t)), Text({ mode = m, ttf = t, tto = t, rest = 300 }))
        end
    end
    for _, m in ipairs({ "warmup", "hold", "oom" }) do
        for ti = 1, NT do
            for ri = 1, 7 do
                local t = TIMES[ti]
                local r = RestOf(RESTS[ri], t)
                Rec(string.format("F %s tto=%s rest=%s", m, Fmt(t), Fmt(r)), Text({ mode = m, tto = t, ttf = t, rest = r }))
            end
        end
    end
    Rec("F nil", Text(nil))
    Rec("F string", Text("oom"))
    Rec("F empty table", Text({}))
    Rec("F numeric mode", Text({ mode = 5, tto = 30 }))
    Rec("F unknown mode", Text({ mode = "bogus", tto = 30, rest = 400 }))
end

--------------------------------------------------------------------------------
-- The goldens (bottom of the file), compared line by line.
--------------------------------------------------------------------------------
local GOLDEN = {}

local function GoldenBlock()
    print("GOLDEN." .. FLAVOUR .. " = [==[")
    for _, l in ipairs(transcript) do print(l) end
    print("]==]")
end

if mode == "golden" then
    GoldenBlock()
    os.exit(0)
end
if mode == "print" then
    for _, l in ipairs(transcript) do print(l) end
end

-- Everything that reads the goldens runs from the bottom of the file, after
-- the long strings are assigned.
local function Finish()
do
    local g = GOLDEN[FLAVOUR]
    local want = {}
    if g then for l in g:gmatch("[^\n]+") do want[#want + 1] = l end end
    local first
    for i = 1, math.max(#want, #transcript) do
        if want[i] ~= transcript[i] then
            first = string.format("line %d:\n      now:    %s\n      golden: %s", i, tostring(transcript[i]), tostring(want[i]))
            break
        end
    end
    check(string.format("2. %s: the golden (%d lines, captured on e2b13f4 before the edit) holds", FLAVOUR, #want),
        #want > 0 and first == nil, first)
    local allClean = true
    for _, l in ipairs(transcript) do
        local _, a, b = l:match("^([^\t]*)\t([^\t]*)\t?(.*)$")
        if not Clean(a) or (b ~= "" and not Clean(b)) or (a and a:find("nil", 1, true)) then allClean = false; first = l break end
    end
    check("2b. every string in the transcript ASCII, no bare pipe, no 'nil'", allClean, not allClean and first or nil)
end

--------------------------------------------------------------------------------
-- 3. The face API.
--------------------------------------------------------------------------------
local LS = CF and CF.LineString
if FLAVOUR == "tbc" then
    check("3. MD:GetClockFace exists and is provided as MD.ClockFace.Current",
        type(MD.GetClockFace) == "function" and CF and type(CF.Current) == "function")

    -- Re-render a few grid states through the face and compare with the string.
    local dispF, _, disp = FindTTO("disp")
    local stateF, stateI = FindTTO("state")
    local function Put(d, st)
        disp.mode, disp.value, disp.bounded, disp.step = d.mode, d.value, d.bounded or false, 5
        for k in pairs(disp.history) do disp.history[k] = nil end
        debug.setupvalue(stateF, stateI, {
            inCombat = st.inCombat, stable = st.stable ~= false, rest = st.rest, cd = st.cd,
            manaMax = 10000, mana = 5000, pct = 0.5, regenNow = 5, mode = d.mode,
        })
    end
    local face, same
    if dispF and stateF and MD.GetClockFace and LS then
        Put({ mode = "oom", value = 15 }, { inCombat = true })
        face = MD:GetClockFace()
        check("3a. OOM 15s vv: the crit band's face (tone crit, arrow vv, known point)",
            face and face.mode == "oom" and face.tone == "crit" and face.arrow == "vv" and face.known == "point"
                and face.value == 15 and Strip(LS(face)) == "OOM 15s vv" and LS(face) == MD:GetDisplayString(),
            face and Strip(LS(face)))
        Put({ mode = "nodata" }, { inCombat = false })
        face = MD:GetClockFace()
        check("3b. FULL --: the nodata face (mode nodata, known none, value nil)",
            face and face.mode == "nodata" and face.known == "none" and face.value == nil and face.label == "FULL"
                and Strip(LS(face)) == "FULL --",
            face and Strip(LS(face)))
        Put({ mode = "oom", value = nil }, { inCombat = true })
        face = MD:GetClockFace()
        check("3c. OOM --: oom with no value (mode oom, known none) beside nodata's FULL --",
            face and face.mode == "oom" and face.known == "none" and Strip(LS(face)) == "OOM --",
            face and Strip(LS(face)))
        Put({ mode = "oom", value = 110, bounded = true }, { inCombat = true, rest = 400 })
        face = MD:GetClockFace()
        check("3d. the bound: known bound, arrow '=', the rest segment as `second`",
            face and face.known == "bound" and face.arrow == "=" and face.second and face.second.kind == "rest"
                and Strip(LS(face)) == "OOM >1:50 =  rest 6:40",
            face and Strip(LS(face)))
        Put({ mode = "oom", value = 90 }, { inCombat = true, rest = 400, cd = { short = "inn", tto = 130, delta = 2000 } })
        face = MD:GetClockFace()
        check("3e. the cooldown segment: second = { kind cd, label inn, value 135 }",
            face and face.second and face.second.kind == "cd" and face.second.label == "inn" and face.second.value == 135
                and not face.modelled and face.combat == true,
            face and Strip(LS(face)))
        same = true
        for _, d in ipairs({ { mode = "fullnow" }, { mode = "ooc", value = 250 }, { mode = "warmup" },
                { mode = "hold", value = 330 }, { mode = "oom", value = 75 } }) do
            Put(d, { inCombat = d.mode ~= "ooc" and d.mode ~= "fullnow", rest = 20 })
            local f = CF.Current()
            if not f or LS(f) ~= MD:GetDisplayString() or LS(f, HEX) ~= MD:GetDisplayString(HEX) then same = false end
        end
        check("3f. ClockFace.Current() rendered by LineString IS GetDisplayString, with and without a hex", same)
        local z = unreachableFullNil()
        check("3g. FULL with no value (unreachable through the latch) reads FULL --, never 0s",
            z.ooc[2] == "|cff999999FULL --|r" and z.full[2] == "|cff999999FULL --|r"
                and not ZeroTime(z.ooc[3]) and not ZeroTime(z.full[3]),
            tostring(z.ooc[2]) .. " / " .. tostring(z.full[2]))
        debug.setupvalue(stateF, stateI, nil)
        check("3h. no state: no face, and the string is empty as before",
            MD:GetClockFace() == nil and MD:GetDisplayString() == "")
    else
        for _, n in ipairs({ "3a", "3b", "3c", "3d", "3e", "3f", "3g", "3h" }) do
            check(n .. ". the face API (MD:GetClockFace, ClockFace.LineString)", false, "absent")
        end
    end
else
    local MM = MD.ManaModel
    check("3. ManaModel.Face exists and the pool's face is provided as MD.ClockFace.Current",
        type(MM.Face) == "function" and CF and type(CF.Current) == "function")
    if type(MM.Face) == "function" and LS then
        local same, bad = true, nil
        local TIMES = { nil, -3, 0, 2.4, 10, 19, 59, 62.4, 600, 600.4, 601, 1e9 }
        for _, m in ipairs({ "fullnow", "ooc", "full", "warmup", "hold", "oom", "bogus" }) do
            for ti = 1, 12 do
                for _, r in ipairs({ false, 30, 700 }) do
                    local st = { mode = m, tto = TIMES[ti], ttf = TIMES[ti], rest = r or nil }
                    if LS(MM.Face(st, 0)) ~= MM.Text(st) then same, bad = false, m .. " " .. Fmt(TIMES[ti]) end
                end
            end
        end
        check("3a. LineString(ManaModel.Face(s)) IS ManaModel.Text(s) on every shape", same, bad)
        local f = MM.Face({ mode = "oom", tto = 12 }, 0)
        check("3b. a modelled crit value: tone crit, value 10 (rounded), no arrow (never vv on Forever)",
            f.tone == "crit" and f.value == 10 and f.arrow == nil and f.modelled == true and LS(f) == "~OOM 0:10")
        f = MM.Face({ mode = "hold", rest = 20 }, 0)
        check("3c. hold on Forever is no value (known none), never a bound",
            f.mode == "hold" and f.known == "none" and f.value == nil and LS(f) == "~OOM --  rest 0:20", LS(f))
        f = MM.Face(nil, 0)
        check("3d. no state: the ~OOM -- face", f and f.known == "none" and LS(f) == "~OOM --")
        -- The provider reads the real pool: equal to the face of Pool:Project(now).
        local now = GetTime()
        local cur = CF.Current(now)
        local want = MM.Face(MD.Pool:Project(now), now)
        check("3e. ClockFace.Current(now) is the face of MD.Pool:Project(now)",
            cur and LS(cur) == LS(want) and cur.mode == want.mode and cur.modelled == true, cur and LS(cur))
        local curNoTime = CF.Current()
        check("3f. ClockFace.Current() with no time reads the model at its last tick, never raises",
            curNoTime ~= nil and type(LS(curNoTime)) == "string")
    else
        for _, n in ipairs({ "3a", "3b", "3c", "3d", "3e", "3f" }) do
            check(n .. ". the face API (ManaModel.Face, ClockFace.LineString)", false, "absent")
        end
    end
end

--------------------------------------------------------------------------------
-- 4. ClockFace.SAMPLES: the suite's faces AND the Settings preview's chips.
--------------------------------------------------------------------------------
if CF and type(CF.SAMPLES) == "table" and LS then
    local keys, bad = {}, nil
    for _, smp in ipairs(CF.SAMPLES) do
        keys[smp.key] = true
        local forever = {}
        for k, v in pairs(smp.face) do forever[k] = v end
        forever.modelled, forever.mono, forever.timeFmt, forever.unstable = true, true, "mss", false
        if forever.arrow then forever.arrow = nil end
        for _, f in ipairs({ smp.face, forever }) do
            for _, hex in ipairs({ false, HEX }) do
                local s = LS(f, hex or nil)
                if not Clean(s) or s:find("nil", 1, true) or s == "" then bad = smp.key .. ": " .. tostring(s) end
                if f.value == nil and f.known ~= "bound" and ZeroTime(s) then bad = smp.key .. " zero: " .. s end
                if f.modelled and Strip(s):sub(1, 1) ~= "~" then bad = smp.key .. " no ~: " .. s end
            end
        end
    end
    local need = { "oom", "crit", "bound", "hold", "warmup", "full", "rest", "ooc", "fullnow", "nodata", "none" }
    local missing = {}
    for _, k in ipairs(need) do if not keys[k] then missing[#missing + 1] = k end end
    check("4. SAMPLES: every preview chip (oom, crit, bound, hold, warm-up, FULL, rest, ooc, ...)",
        #missing == 0, #missing > 0 and table.concat(missing, ",") or nil)
    check("4b. SAMPLES as TBC and as Forever draw them: ASCII, no bare pipe, no nil, nil never 0, ~ kept",
        bad == nil, bad)
    local by = {}
    for _, smp in ipairs(CF.SAMPLES) do by[smp.key] = smp.face end
    check("4c. the crit sample is TBC's `OOM 15s vv`; nodata's is `FULL --`",
        by.crit and Strip(LS(by.crit)) == "OOM 15s vv" and by.nodata and LS(by.nodata) == "|cff999999FULL --|r")
else
    check("4. SAMPLES: every preview chip", false, "absent")
    check("4b. SAMPLES: ASCII, no bare pipe, no nil, nil never 0, ~ kept", false, "absent")
    check("4c. the crit sample is TBC's `OOM 15s vv`", false, "absent")
end

--------------------------------------------------------------------------------
-- 5. T93 (docs/SPEC-next.md 7.3 "When", F3): MD.Visibility.Want takes a show
-- rule. UI/Visibility.lua is pure, so it is loaded here the way section 1
-- loads the face -- Lua's library only -- and asked directly. The oracle is
-- the parent's Want, copied verbatim from UI/Visibility.lua at 231525d.
--------------------------------------------------------------------------------
do
    local OLD_SHOW, OLD_HIDE = 0.90, 0.95
    local function OldWant(pct, shown, inCombat, unlocked)
        if unlocked then return true end
        if inCombat then return true end
        if type(pct) ~= "number" then return false end
        if shown then return pct <= OLD_HIDE end
        return pct < OLD_SHOW
    end

    local V, vErr
    local chunk, err = loadfile(S.root .. "/UI/Visibility.lua")
    if chunk then
        local env = setmetatable({ type = type, pairs = pairs, ipairs = ipairs, math = math, string = string,
            tostring = tostring, error = error, setmetatable = setmetatable, rawget = rawget },
            { __index = function(_, k) error("global " .. tostring(k), 2) end })
        setfenv(chunk, env)
        local fakeMD = {}
        local okLoad, e = pcall(chunk, "SpellTuner", fakeMD)
        if okLoad then V = fakeMD.Visibility else vErr = tostring(e) end
    else
        vErr = tostring(err)
    end

    local PCTS = { "nil", 0, 0.5, 0.89, 0.8999, 0.9, 0.93, 0.95, 0.9501, 1 }
    local function Each(fn)
        for _, p in ipairs(PCTS) do
            local pct = (p ~= "nil") and p or nil
            for _, shown in ipairs({ false, true }) do
                for _, ic in ipairs({ false, true }) do
                    for _, un in ipairs({ false, true }) do
                        local bad = fn(pct, shown, ic, un)
                        if bad then return bad end
                    end
                end
            end
        end
    end
    local function Case(pct, shown, ic, un)
        return string.format("pct=%s shown=%s combat=%s unlocked=%s", tostring(pct), tostring(shown),
            tostring(ic), tostring(un))
    end

    -- 5. the default rule is today's rule on every case, however it is asked
    local bad5
    if V and type(V.Want) == "function" and type(V.DEFAULT_RULE) == "table" then
        bad5 = Each(function(pct, shown, ic, un)
            local want = OldWant(pct, shown, ic, un)
            local asks = {
                { "4 args", V.Want(pct, shown, ic, un) },
                { "rule nil", V.Want(pct, shown, ic, un, nil) },
                { "DEFAULT_RULE", V.Want(pct, shown, ic, un, V.DEFAULT_RULE) },
                { "DEFAULT_RULE, a mana user", V.Want(pct, shown, ic, un, V.DEFAULT_RULE, true) },
                { "an empty rule", V.Want(pct, shown, ic, un, {}) },
            }
            for _, a in ipairs(asks) do
                if a[2] ~= want then return Case(pct, shown, ic, un) .. " " .. a[1] .. ": " .. tostring(a[2]) end
            end
        end)
    else
        bad5 = vErr or "no Visibility.Want with a DEFAULT_RULE"
    end
    check("5. Visibility.Want's default rule is today's rule (" .. (#PCTS * 8) .. " cases x 5 ways of asking)",
        bad5 == nil, bad5)

    -- 5b. ooc = "never": out of combat never, in combat and while unlocked as before;
    -- its siblings ooc = "always" and combat = "never"
    local bad5b
    if V and type(V.DEFAULT_RULE) == "table" then
        local function Rule(over)
            local r = {}
            for k, v in pairs(V.DEFAULT_RULE) do r[k] = v end
            for k, v in pairs(over) do r[k] = v end
            return r
        end
        local never, always, noCombat = Rule({ ooc = "never" }), Rule({ ooc = "always" }), Rule({ combat = "never" })
        bad5b = Each(function(pct, shown, ic, un)
            local n = V.Want(pct, shown, ic, un, never)
            local a = V.Want(pct, shown, ic, un, always)
            local c = V.Want(pct, shown, ic, un, noCombat)
            local wantN = un or ic
            local wantA = true
            local wantC = un or (not ic and OldWant(pct, shown, false, false))
            if n ~= wantN or a ~= wantA or c ~= wantC then
                return Case(pct, shown, ic, un) .. string.format(" never=%s always=%s combat-never=%s",
                    tostring(n), tostring(a), tostring(c))
            end
        end)
    else
        bad5b = vErr or "no DEFAULT_RULE"
    end
    check("5b. ooc = \"never\" hides out of combat at any mana (ooc \"always\", combat \"never\" beside it)",
        bad5b == nil, bad5b)

    -- 5c. manaUsersOnly: a character with no mana pool gets no clock, in combat
    -- included, unless it is being placed; off, the old answer; a mana user
    -- (or an unknown) is untouched
    local bad5c
    if V and type(V.DEFAULT_RULE) == "table" and V.DEFAULT_RULE.manaUsersOnly == true then
        local off = {}
        for k, v in pairs(V.DEFAULT_RULE) do off[k] = v end
        off.manaUsersOnly = false
        bad5c = Each(function(pct, shown, ic, un)
            local old = OldWant(pct, shown, ic, un)
            local noPool = V.Want(pct, shown, ic, un, V.DEFAULT_RULE, false)
            local noPoolOff = V.Want(pct, shown, ic, un, off, false)
            local user = V.Want(pct, shown, ic, un, V.DEFAULT_RULE, true)
            if noPool ~= un or noPoolOff ~= old or user ~= old then
                return Case(pct, shown, ic, un) .. string.format(" noPool=%s off=%s user=%s",
                    tostring(noPool), tostring(noPoolOff), tostring(user))
            end
        end)
    else
        bad5c = vErr or "DEFAULT_RULE.manaUsersOnly is not on"
    end
    check("5c. manaUsersOnly (on by default): no mana pool, no clock -- in combat too, unless being placed",
        bad5c == nil, bad5c)
end

--------------------------------------------------------------------------------
-- 6. T98 (docs/SPEC-next.md 7.3): the clock's look, resolved as
--      the layout's defaults  <-  the active style's clock role  <-  over
-- (UI/ClockView.lua's CV.Resolve, pure), and "Reset to style" wiping `over`.
-- The TBC harness loads no UI file, so the kit, the theme, the registry and
-- the renderer are loaded here, in the TOC's order (Forever has them).
--------------------------------------------------------------------------------
do
    if not (MD.ClockView and MD.ClockView.Resolve) and FLAVOUR == "tbc" then
        pcall(S.Load, { "UI/Style.lua", "UI/Theme_Flat.lua", "UI/Styles.lua", "UI/ClockView.lua" }, "SpellTuner", MD)
    end
    local CV = MD.ClockView or {}
    local function Is(c, r, g, b, a)
        return type(c) == "table" and c[1] == r and c[2] == g and c[3] == b and c[4] == a
    end
    local role = { kind = "pixel", fill = { 0.1, 0.2, 0.3, 1 }, edge = "border", bar = { 0.5, 0, 0, 1 },
        barFill = { 0, 1, 0, 1 } }
    local forever = FLAVOUR == "forever"
    local facts = { line = FLAVOUR, poolPlain = not forever, model = forever, tick = not forever,
        textures = not forever, labelSample = forever and "~FULL" or "FULL", show = {} }

    -- 6. over wins over the style, and the style over the layout's defaults
    -- (T115: the bars per layout, the frame per layout)
    local ok6, why6 = pcall(function()
        local flat = CV.Resolve({ layout = "line", over = {} }, nil, facts)
        local styled = CV.Resolve({ layout = "line", over = {} }, role, facts)
        local stored = { layout = "line", over = {
            panel = { fill = { 0.9, 0.9, 0.9, 1 } },
            bar = { back = { 0, 0, 1, 1 } },
            bars = { line = { join = "veil", fsr = 5 }, bar = { join = "chip" } },
            frame = { line = { h = 44, scale = 120 } },
            colors = { crit = "ff0000", manaBar = "tone" } } }
        local over = CV.Resolve(stored, role, facts)
        over.bar.back[1] = 0.5 -- the resolved look is a copy: the store keeps its own
        local okDefaults = flat.panel.fill == "bg" and flat.panel.edge == "border" and Is(flat.bar.back, 0, 0, 0, 1)
            and flat.bars.show == "both" and flat.bars.join == "stacked" and flat.bars.order == "manaOver"
            and flat.bars.mana == "game" and flat.bars.fsr == 3 and flat.bars.after == "green"
            and flat.bars.texture == "flat" and flat.bars.fill == nil
            and flat.frame.w == 180 and flat.frame.h == 32 and flat.frame.scale == 100
        local okStyled = Is(styled.panel.fill, 0.1, 0.2, 0.3, 1) and Is(styled.bar.back, 0.5, 0, 0, 1)
            and Is(styled.bars.fill, 0, 1, 0, 1) and styled.bars.join == "stacked"
        local okOver = Is(over.panel.fill, 0.9, 0.9, 0.9, 1) and over.panel.edge == "border"
            and over.bars.join == "veil" and over.bars.fsr == 5 and over.frame.h == 44 and over.frame.scale == 120
            and over.frame.w == 180 and over.colors.crit == "ff0000" and over.colors.manaBar == "tone"
            and Is(stored.over.bar.back, 0, 0, 1, 1)
        -- another layout's keys are that layout's own
        stored.layout = "bar"
        local barLook = CV.Resolve(stored, role, facts)
        local okPer = barLook.bars.join == "chip" and barLook.bars.fsr == 3 and barLook.frame.h == 22
            and barLook.frame.w == 200 and barLook.frame.scale == 100
        if okDefaults and okStyled and okOver and okPer then return true end
        return string.format("defaults %s, styled %s, over %s, per layout %s", tostring(okDefaults),
            tostring(okStyled), tostring(okOver), tostring(okPer))
    end)
    check("6. the clock's look: over wins over the style's clock role, the role over the layout's defaults; bars and frame per layout",
        ok6 and why6 == true, (not ok6 and ("raised: " .. tostring(why6))) or (why6 ~= true and tostring(why6)) or nil)

    -- 6b. Reset to style: every override gone, the layout kept, CLOCK_LOOK once,
    -- and the look is the style's again
    local ok6b, why6b = pcall(function()
        local fired = 0
        MD:RegisterCallback("CLOCK_LOOK", function() fired = fired + 1 end)
        CV.SetLayout("bar")
        CV.Set("bars.bar.join", "veil")
        CV.Set("frame.bar.h", 30)
        CV.Set("colors.crit", "ff0000")
        local had = MD.db.clockLook.over.bars ~= nil and MD.db.clockLook.over.colors ~= nil
            and MD.db.clockLook.over.frame ~= nil
        local overLook = CV.Look(facts)
        local before = fired
        CV.ResetToStyle()
        local after = fired - before
        local look = CV.Look(facts)
        local empty = type(MD.db.clockLook.over) == "table" and next(MD.db.clockLook.over) == nil
        -- Set prunes: a key set back to nil leaves no empty table behind
        CV.Set("bars.line.fsr", 6)
        CV.Set("bars.line.fsr", nil)
        local pruned = next(MD.db.clockLook.over) == nil
        local okR = had and overLook.bars.join == "veil" and overLook.frame.h == 30 and empty
            and MD.db.clockLook.layout == "bar" and after == 1 and look.bars.join == "stacked"
            and look.frame.h == 22 and look.colors.crit == nil and pruned
        CV.SetLayout("line")
        if okR then return true end
        return string.format("had %s, empty %s, layout %s, fired %d, join %s, pruned %s", tostring(had),
            tostring(empty), tostring(MD.db.clockLook.layout), after, tostring(look.bars.join), tostring(pruned))
    end)
    check("6b. Reset to style wipes over (the layout kept, CLOCK_LOOK once, the style's look back); Set prunes",
        ok6b and why6b == true, (not ok6b and ("raised: " .. tostring(why6b))) or (why6b ~= true and tostring(why6b)) or nil)

    -- 6c. the 0.16.6 keys migrate: bar.source -> bars.<every layout>.show
    -- (+ mana = model where the line has a model), bar.color -> colors.manaBar;
    -- the spark, the horizon, the height and source "time" dropped, named once
    local ok6c, why6c = pcall(function()
        local bad = {}
        local function Mig(over)
            local stored = { layout = "line", over = over }
            local changed, dropped = CV.Migrate(stored, facts)
            return stored.over, changed, table.concat(dropped or {}, ",")
        end
        local o, ch, dr = Mig({ bar = { source = "pool", color = "tone", back = { 0, 0, 0, 1 } } })
        for _, L in ipairs({ "line", "compact", "bar" }) do
            if not (o.bars and o.bars[L] and o.bars[L].show == "mana" and o.bars[L].mana == nil) then
                bad[#bad + 1] = "pool -> " .. L
            end
        end
        if not (ch == true and dr == "" and o.colors and o.colors.manaBar == "tone" and o.bar
            and Is(o.bar.back, 0, 0, 0, 1) and o.bar.source == nil and o.bar.color == nil) then
            bad[#bad + 1] = "pool: changed " .. tostring(ch) .. " dropped " .. dr
        end
        o, ch, dr = Mig({ bar = { source = "model", spark = false, horizon = 3, height = 6 } })
        local wantMana = forever and "model" or nil
        if not (o.bars.line.show == "mana" and o.bars.line.mana == wantMana and o.bar == nil
            and dr == "bar.height,bar.horizon,bar.spark") then
            bad[#bad + 1] = "model: " .. tostring(o.bars.line.mana) .. " dropped " .. dr
        end
        o, ch, dr = Mig({ bar = { source = "fsr" } })
        if o.bars.compact.show ~= "fsr" then bad[#bad + 1] = "fsr" end
        o, ch, dr = Mig({ bar = { source = "none" } })
        if o.bars.bar.show ~= "none" then bad[#bad + 1] = "none" end
        o, ch, dr = Mig({ bar = { source = "time", color = "source" } })
        if not (o.bars == nil and o.bar == nil and dr == "bar.color,bar.source") then
            bad[#bad + 1] = "time: dropped " .. dr
        end
        o, ch, dr = Mig({ bar = { color = { 1, 0, 0, 1 } } })
        if not (type(o.colors) == "table" and Is(o.colors.manaBar, 1, 0, 0, 1)) then bad[#bad + 1] = "colour" end
        o, ch, dr = Mig({ bar = { color = "purple" } })
        if not (o.colors == nil and dr == "bar.color") then bad[#bad + 1] = "bad colour: " .. dr end
        -- a key already in the new shape is never overwritten
        o, ch, dr = Mig({ bar = { source = "fsr" }, bars = { line = { show = "both" } },
            colors = { manaBar = "class" } })
        if not (o.bars.line.show == "both" and o.bars.bar.show == "fsr" and o.colors.manaBar == "class") then
            bad[#bad + 1] = "kept"
        end
        if #bad == 0 then return true end
        return table.concat(bad, "; ")
    end)
    check("6c. the 0.16.6 keys migrate (source -> bars.<layout>.show, color -> colors.manaBar); the rest dropped by name",
        ok6c and why6c == true, (not ok6c and ("raised: " .. tostring(why6c))) or (why6c ~= true and tostring(why6c)) or nil)

    -- 6d. migrating twice changes nothing; a migrated store resolves as the
    -- same keys set by hand; the dump line names what was dropped
    local ok6d, why6d = pcall(function()
        local stored = { layout = "line", over = { bar = { source = "fsr", spark = true, back = { 0, 0, 0, 1 } } } }
        local c1 = CV.Migrate(stored, facts)
        local c2, d2 = CV.Migrate(stored, facts)
        local hand = { layout = "line", over = { bar = { back = { 0, 0, 0, 1 } },
            bars = { line = { show = "fsr" }, compact = { show = "fsr" }, bar = { show = "fsr" } } } }
        local a, b = CV.Resolve(stored, nil, facts), CV.Resolve(hand, nil, facts)
        local same = a.bars.show == b.bars.show and a.bars.show == "fsr"
        for _, L in ipairs({ "line", "compact", "bar" }) do
            if stored.over.bars[L].show ~= hand.over.bars[L].show then same = false end
        end
        -- the session's own store, migrated (forced again here), with the dump line
        MD.db.clockLook = { layout = "line", over = { bar = { source = "time", horizon = 3 } } }
        CV.MigrateStored(facts, true)
        local line
        for _, d in ipairs(MD:DumpLines()) do
            if d.key == "clockOld" then line = d.fn() end
        end
        local okLine = line == "clock: 2 old clock keys dropped (bar.horizon, bar.source)"
        local emptied = next(MD.db.clockLook.over) == nil
        MD.db.clockLook = { layout = "line", over = {} }
        if c1 == true and c2 == false and #(d2 or {}) == 0 and same and okLine and emptied then return true end
        return string.format("first %s, second %s, same %s, dump %q, emptied %s", tostring(c1), tostring(c2),
            tostring(same), tostring(line), tostring(emptied))
    end)
    check("6d. migrating twice changes nothing; a migrated store resolves as the same keys by hand; the dump names the dropped",
        ok6d and why6d == true, (not ok6d and ("raised: " .. tostring(why6d))) or (why6d ~= true and tostring(why6d)) or nil)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
end -- Finish

--------------------------------------------------------------------------------
-- The goldens: `tools/run.sh --flavour <f> tools/clockfacecheck.lua --golden`
-- on e2b13f4 (before Engine/TTO.lua and Engine/ManaModel.lua were edited), pasted.
--------------------------------------------------------------------------------
-- GOLDEN-TBC-BEGIN
GOLDEN.tbc = [==[
fight 001 full, out of combat	|cff33ff66FULL|r
fight 002 full, out of combat	|cff33ff66FULL|r
fight 003 full, out of combat	|cff33ff66FULL|r
fight 004 full, out of combat	|cff33ff66FULL|r
fight 005 out of combat at 74%	|cff999999FULL|r |cff33ff663:05|r	|cff999999FULL|r |cff16c3f23:05|r
fight 006 out of combat at 74%	|cff999999FULL|r |cff33ff663:05|r	|cff999999FULL|r |cff16c3f23:05|r
fight 007 out of combat at 74%	|cff999999FULL|r |cff33ff663:05|r	|cff999999FULL|r |cff16c3f23:05|r
fight 008 out of combat at 74%	|cff999999FULL|r |cff33ff663:05|r	|cff999999FULL|r |cff16c3f23:05|r
fight 009 out of combat at 74%	|cff999999FULL|r |cff33ff663:00|r	|cff999999FULL|r |cff16c3f23:00|r
fight 010 out of combat at 74%	|cff999999FULL|r |cff33ff663:00|r	|cff999999FULL|r |cff16c3f23:00|r
fight 011 pull	|cff999999OOM ...|r  |cff999999rest 3:00|r
fight 012 pull	|cff999999OOM ...|r  |cff999999rest 3:00|r
fight 013 casting every 2s #1	|cff999999OOM ...|r  |cff999999rest 3:25|r
fight 014 casting every 2s #1	|cff999999OOM ...|r  |cff999999rest 3:25|r
fight 015 casting every 2s #1	|cff999999OOM ...|r  |cff999999rest 3:25|r
fight 016 casting every 2s #1	|cff999999OOM ...|r  |cff999999rest 3:25|r
fight 017 casting every 2s #2	|cff999999OOM ...|r  |cff999999rest 3:45|r
fight 018 casting every 2s #2	|cff999999OOM ...|r  |cff999999rest 3:45|r
fight 019 casting every 2s #2	|cff999999OOM ...|r  |cff999999rest 3:45|r
fight 020 casting every 2s #2	|cff999999OOM ...|r  |cff999999rest 3:45|r
fight 021 casting every 2s #3	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r
fight 022 casting every 2s #3	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r
fight 023 casting every 2s #3	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r
fight 024 casting every 2s #3	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r
fight 025 casting every 2s #4	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:30|r
fight 026 casting every 2s #4	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r
fight 027 casting every 2s #4	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r
fight 028 casting every 2s #4	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r
fight 029 casting every 2s #5	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:55|r
fight 030 casting every 2s #5	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:50|r
fight 031 casting every 2s #5	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:50|r
fight 032 casting every 2s #5	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:50|r
fight 033 casting every 2s #6	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:15|r
fight 034 casting every 2s #6	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r
fight 035 casting every 2s #6	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r
fight 036 casting every 2s #6	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r
fight 037 casting every 2s #7	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r
fight 038 casting every 2s #7	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r
fight 039 casting every 2s #7	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r
fight 040 casting every 2s #7	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r
fight 041 casting every 2s #8	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r
fight 042 casting every 2s #8	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r
fight 043 casting every 2s #8	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r
fight 044 casting every 2s #8	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r
fight 045 casting every 2s #9	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 6:20|r
fight 046 casting every 2s #9	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 6:20|r
fight 047 casting every 2s #9	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 6:20|r
fight 048 casting every 2s #9	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:20|r
fight 049 casting every 2s #10	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:40|r
fight 050 casting every 2s #10	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:40|r
fight 051 casting every 2s #10	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:40|r
fight 052 casting every 2s #10	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:40|r
fight 053 casting every 2s #11	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 7:05|r
fight 054 casting every 2s #11	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:05|r
fight 055 casting every 2s #11	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:05|r
fight 056 casting every 2s #11	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:05|r
fight 057 casting every 2s #12	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r
fight 058 casting every 2s #12	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r
fight 059 casting every 2s #12	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r
fight 060 casting every 2s #12	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r
fight 061 casting every 2s #13	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:50|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:50|r
fight 062 casting every 2s #13	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:50|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:50|r
fight 063 casting every 2s #13	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:45|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:45|r
fight 064 casting every 2s #13	|cff999999OOM|r |cffffaa3325s|r |cffffaa33v|r  |cff999999rest 7:45|r	|cff999999OOM|r |cff16c3f225s|r |cffffaa33v|r  |cff999999rest 7:45|r
fight 065 casting every 2s #14	|cff999999OOM|r |cffffaa3325s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f225s|r |cff999999=|r  |cff999999rest 8:10|r
fight 066 casting every 2s #14	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:10|r
fight 067 casting every 2s #14	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:10|r
fight 068 casting every 2s #14	|cff999999OOM|r |cffffaa3325s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f225s|r |cff999999=|r  |cff999999rest 8:10|r
fight 069 casting every 3.5s #1	|cff999999OOM|r |cffffaa3325s|r |cff999999=|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f225s|r |cff999999=|r  |cff999999rest 8:30|r
fight 070 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r
fight 071 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r
fight 072 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r
fight 073 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r
fight 074 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:30|r
fight 075 casting every 3.5s #1	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:30|r
fight 076 casting every 3.5s #2	|cffff4444OOM 15s vv|r  |cff999999rest 8:55|r
fight 077 casting every 3.5s #2	|cffff4444OOM 15s vv|r  |cff999999rest 8:55|r
fight 078 casting every 3.5s #2	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:55|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:55|r
fight 079 casting every 3.5s #2	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:55|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:55|r
fight 080 casting every 3.5s #2	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:55|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:55|r
fight 081 casting every 3.5s #2	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:50|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:50|r
fight 082 casting every 3.5s #2	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:50|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:50|r
fight 083 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 084 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 085 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 086 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 087 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 088 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 089 casting every 3.5s #3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r
fight 090 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 091 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 092 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 093 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 094 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 095 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 096 casting every 3.5s #4	|cffff4444OOM 15s vv|r  |cff999999rest 9:35|r
fight 097 casting every 3.5s #5	|cffff4444OOM 15s vv|r  |cff999999rest 10:00|r
fight 098 casting every 3.5s #5	|cffff4444OOM 10s vv|r  |cff999999rest 10:00|r
fight 099 casting every 3.5s #5	|cffff4444OOM 10s vv|r  |cff999999rest 10:00|r
fight 100 casting every 3.5s #5	|cffff4444OOM 10s vv|r  |cff999999rest 10:00|r
fight 101 casting every 3.5s #5	|cffff4444OOM 10s vv|r  |cff999999rest 10:00|r
fight 102 casting every 3.5s #5	|cffff4444OOM 15s vv|r  |cff999999rest 10:00|r
fight 103 casting every 3.5s #5	|cffff4444OOM 15s vv|r  |cff999999rest 10:00|r
fight 104 casting every 3.5s #6	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 105 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 106 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 107 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 108 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 109 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 110 casting every 3.5s #6	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 111 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 112 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 113 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 114 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 115 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 116 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 117 stopped casting	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 118 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 119 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 120 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 121 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 122 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 123 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 124 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 125 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 126 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 127 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 128 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 129 stopped casting	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 130 stopped casting	|cff999999OOM|r |cffffaa3320s|r |cff33ff66^|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f220s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 131 stopped casting	|cff999999OOM|r |cffffaa3320s|r |cff33ff66^|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f220s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 132 stopped casting	|cff999999OOM|r |cffffaa3320s|r |cff33ff66^|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f220s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 133 stopped casting	|cff999999OOM|r |cffffaa3320s|r |cff33ff66^|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f220s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 134 stopped casting	|cff999999OOM|r |cffffaa3320s|r |cff33ff66^|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f220s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 135 stopped casting	|cff999999OOM|r |cff999999~20s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 136 stopped casting	|cff999999OOM|r |cff999999~20s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 137 stopped casting	|cff999999OOM|r |cff999999~20s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 138 stopped casting	|cff999999OOM|r |cff999999~20s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 139 stopped casting	|cff999999OOM|r |cff999999~25s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 140 stopped casting	|cff999999OOM|r |cff999999~25s|r |cff33ff66^|r  |cff999999rest >10m|r
fight 141 regen up	|cff999999OOM|r |cff999999~25s|r |cff33ff66^|r  |cff999999rest 15s|r
fight 142 regen up	|cff999999FULL|r |cff33ff6626s|r	|cff999999FULL|r |cff16c3f226s|r
fight 143 regen up	|cff999999FULL|r |cff33ff6626s|r	|cff999999FULL|r |cff16c3f226s|r
fight 144 regen up	|cff999999FULL|r |cff33ff6625s|r	|cff999999FULL|r |cff16c3f225s|r
fight 145 regen up	|cff999999FULL|r |cff33ff6625s|r	|cff999999FULL|r |cff16c3f225s|r
fight 146 regen up	|cff999999FULL|r |cff33ff6625s|r	|cff999999FULL|r |cff16c3f225s|r
fight 147 regen up	|cff999999FULL|r |cff33ff6624s|r	|cff999999FULL|r |cff16c3f224s|r
fight 148 regen up	|cff999999FULL|r |cff33ff6624s|r	|cff999999FULL|r |cff16c3f224s|r
fight 149 regen up	|cff999999OOM ...|r  |cff999999rest 15s|r
fight 150 regen up	|cff999999OOM ...|r  |cff999999rest 15s|r
fight 151 regen up	|cff999999OOM ...|r  |cff999999rest 15s|r
fight 152 regen up	|cff999999OOM ...|r  |cff999999rest 15s|r
fight 153 casting every 1s #1	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 154 casting every 1s #1	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 155 casting every 1s #2	|cffff4444OOM 15s vv|r  |cff999999rest >10m|r
fight 156 casting every 1s #2	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 157 casting every 1s #3	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r
fight 158 casting every 1s #3	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 159 casting every 1s #4	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 160 casting every 1s #4	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 161 casting every 1s #5	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 162 casting every 1s #5	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 163 casting every 1s #6	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 164 casting every 1s #6	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 165 casting every 1s #7	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 166 casting every 1s #7	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 167 casting every 1s #8	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 168 casting every 1s #8	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 169 casting every 1s #9	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 170 casting every 1s #9	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 171 casting every 1s #10	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 172 casting every 1s #10	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 173 casting every 1s #11	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 174 casting every 1s #11	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 175 casting every 1s #12	|cffff4444OOM 4s vv|r  |cff999999rest >10m|r
fight 176 casting every 1s #12	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 177 casting every 1s #13	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 178 casting every 1s #13	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 179 casting every 1s #14	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 180 casting every 1s #14	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r
fight 181 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 182 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 183 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 184 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 185 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 186 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 187 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 188 left combat	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 189 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 190 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 191 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 192 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 193 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 194 out of combat, slow regen	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
fight 195 out of combat, no regen	|cff999999FULL --|r
fight 196 out of combat, no regen	|cff999999FULL --|r
fight 197 out of combat, no regen	|cff999999FULL --|r
fight 198 out of combat, no regen	|cff999999FULL --|r
fight 199 out of combat, no regen	|cff999999FULL --|r
fight 200 out of combat, no regen	|cff999999FULL --|r
A fullnow v=nil combat=false	|cff33ff66FULL|r
A fullnow v=nil combat=true	|cff33ff66FULL|r
A fullnow v=0 combat=false	|cff33ff66FULL|r
A fullnow v=0 combat=true	|cff33ff66FULL|r
A fullnow v=15 combat=false	|cff33ff66FULL|r
A fullnow v=15 combat=true	|cff33ff66FULL|r
A fullnow v=19 combat=false	|cff33ff66FULL|r
A fullnow v=19 combat=true	|cff33ff66FULL|r
A fullnow v=20 combat=false	|cff33ff66FULL|r
A fullnow v=20 combat=true	|cff33ff66FULL|r
A fullnow v=45 combat=false	|cff33ff66FULL|r
A fullnow v=45 combat=true	|cff33ff66FULL|r
A fullnow v=59 combat=false	|cff33ff66FULL|r
A fullnow v=59 combat=true	|cff33ff66FULL|r
A fullnow v=60 combat=false	|cff33ff66FULL|r
A fullnow v=60 combat=true	|cff33ff66FULL|r
A fullnow v=61 combat=false	|cff33ff66FULL|r
A fullnow v=61 combat=true	|cff33ff66FULL|r
A fullnow v=90 combat=false	|cff33ff66FULL|r
A fullnow v=90 combat=true	|cff33ff66FULL|r
A fullnow v=125 combat=false	|cff33ff66FULL|r
A fullnow v=125 combat=true	|cff33ff66FULL|r
A fullnow v=600 combat=false	|cff33ff66FULL|r
A fullnow v=600 combat=true	|cff33ff66FULL|r
A fullnow v=601 combat=false	|cff33ff66FULL|r
A fullnow v=601 combat=true	|cff33ff66FULL|r
A fullnow v=605 combat=false	|cff33ff66FULL|r
A fullnow v=605 combat=true	|cff33ff66FULL|r
A fullnow v=900 combat=false	|cff33ff66FULL|r
A fullnow v=900 combat=true	|cff33ff66FULL|r
A nodata v=nil combat=false	|cff999999FULL --|r
A nodata v=nil combat=true	|cff999999FULL --|r
A nodata v=0 combat=false	|cff999999FULL --|r
A nodata v=0 combat=true	|cff999999FULL --|r
A nodata v=15 combat=false	|cff999999FULL --|r
A nodata v=15 combat=true	|cff999999FULL --|r
A nodata v=19 combat=false	|cff999999FULL --|r
A nodata v=19 combat=true	|cff999999FULL --|r
A nodata v=20 combat=false	|cff999999FULL --|r
A nodata v=20 combat=true	|cff999999FULL --|r
A nodata v=45 combat=false	|cff999999FULL --|r
A nodata v=45 combat=true	|cff999999FULL --|r
A nodata v=59 combat=false	|cff999999FULL --|r
A nodata v=59 combat=true	|cff999999FULL --|r
A nodata v=60 combat=false	|cff999999FULL --|r
A nodata v=60 combat=true	|cff999999FULL --|r
A nodata v=61 combat=false	|cff999999FULL --|r
A nodata v=61 combat=true	|cff999999FULL --|r
A nodata v=90 combat=false	|cff999999FULL --|r
A nodata v=90 combat=true	|cff999999FULL --|r
A nodata v=125 combat=false	|cff999999FULL --|r
A nodata v=125 combat=true	|cff999999FULL --|r
A nodata v=600 combat=false	|cff999999FULL --|r
A nodata v=600 combat=true	|cff999999FULL --|r
A nodata v=601 combat=false	|cff999999FULL --|r
A nodata v=601 combat=true	|cff999999FULL --|r
A nodata v=605 combat=false	|cff999999FULL --|r
A nodata v=605 combat=true	|cff999999FULL --|r
A nodata v=900 combat=false	|cff999999FULL --|r
A nodata v=900 combat=true	|cff999999FULL --|r
A ooc v=0 combat=false	|cff999999FULL|r |cff33ff660s|r	|cff999999FULL|r |cff16c3f20s|r
A ooc v=0 combat=true	|cff999999FULL|r |cff33ff660s|r	|cff999999FULL|r |cff16c3f20s|r
A ooc v=15 combat=false	|cff999999FULL|r |cff33ff6615s|r	|cff999999FULL|r |cff16c3f215s|r
A ooc v=15 combat=true	|cff999999FULL|r |cff33ff6615s|r	|cff999999FULL|r |cff16c3f215s|r
A ooc v=19 combat=false	|cff999999FULL|r |cff33ff6619s|r	|cff999999FULL|r |cff16c3f219s|r
A ooc v=19 combat=true	|cff999999FULL|r |cff33ff6619s|r	|cff999999FULL|r |cff16c3f219s|r
A ooc v=20 combat=false	|cff999999FULL|r |cff33ff6620s|r	|cff999999FULL|r |cff16c3f220s|r
A ooc v=20 combat=true	|cff999999FULL|r |cff33ff6620s|r	|cff999999FULL|r |cff16c3f220s|r
A ooc v=45 combat=false	|cff999999FULL|r |cff33ff6645s|r	|cff999999FULL|r |cff16c3f245s|r
A ooc v=45 combat=true	|cff999999FULL|r |cff33ff6645s|r	|cff999999FULL|r |cff16c3f245s|r
A ooc v=59 combat=false	|cff999999FULL|r |cff33ff6659s|r	|cff999999FULL|r |cff16c3f259s|r
A ooc v=59 combat=true	|cff999999FULL|r |cff33ff6659s|r	|cff999999FULL|r |cff16c3f259s|r
A ooc v=60 combat=false	|cff999999FULL|r |cff33ff661:00|r	|cff999999FULL|r |cff16c3f21:00|r
A ooc v=60 combat=true	|cff999999FULL|r |cff33ff661:00|r	|cff999999FULL|r |cff16c3f21:00|r
A ooc v=61 combat=false	|cff999999FULL|r |cff33ff661:01|r	|cff999999FULL|r |cff16c3f21:01|r
A ooc v=61 combat=true	|cff999999FULL|r |cff33ff661:01|r	|cff999999FULL|r |cff16c3f21:01|r
A ooc v=90 combat=false	|cff999999FULL|r |cff33ff661:30|r	|cff999999FULL|r |cff16c3f21:30|r
A ooc v=90 combat=true	|cff999999FULL|r |cff33ff661:30|r	|cff999999FULL|r |cff16c3f21:30|r
A ooc v=125 combat=false	|cff999999FULL|r |cff33ff662:05|r	|cff999999FULL|r |cff16c3f22:05|r
A ooc v=125 combat=true	|cff999999FULL|r |cff33ff662:05|r	|cff999999FULL|r |cff16c3f22:05|r
A ooc v=600 combat=false	|cff999999FULL|r |cff33ff6610:00|r	|cff999999FULL|r |cff16c3f210:00|r
A ooc v=600 combat=true	|cff999999FULL|r |cff33ff6610:00|r	|cff999999FULL|r |cff16c3f210:00|r
A ooc v=601 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A ooc v=601 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A ooc v=605 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A ooc v=605 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A ooc v=900 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A ooc v=900 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=0 combat=false	|cff999999FULL|r |cff33ff660s|r	|cff999999FULL|r |cff16c3f20s|r
A full v=0 combat=true	|cff999999FULL|r |cff33ff660s|r	|cff999999FULL|r |cff16c3f20s|r
A full v=15 combat=false	|cff999999FULL|r |cff33ff6615s|r	|cff999999FULL|r |cff16c3f215s|r
A full v=15 combat=true	|cff999999FULL|r |cff33ff6615s|r	|cff999999FULL|r |cff16c3f215s|r
A full v=19 combat=false	|cff999999FULL|r |cff33ff6619s|r	|cff999999FULL|r |cff16c3f219s|r
A full v=19 combat=true	|cff999999FULL|r |cff33ff6619s|r	|cff999999FULL|r |cff16c3f219s|r
A full v=20 combat=false	|cff999999FULL|r |cff33ff6620s|r	|cff999999FULL|r |cff16c3f220s|r
A full v=20 combat=true	|cff999999FULL|r |cff33ff6620s|r	|cff999999FULL|r |cff16c3f220s|r
A full v=45 combat=false	|cff999999FULL|r |cff33ff6645s|r	|cff999999FULL|r |cff16c3f245s|r
A full v=45 combat=true	|cff999999FULL|r |cff33ff6645s|r	|cff999999FULL|r |cff16c3f245s|r
A full v=59 combat=false	|cff999999FULL|r |cff33ff6659s|r	|cff999999FULL|r |cff16c3f259s|r
A full v=59 combat=true	|cff999999FULL|r |cff33ff6659s|r	|cff999999FULL|r |cff16c3f259s|r
A full v=60 combat=false	|cff999999FULL|r |cff33ff661:00|r	|cff999999FULL|r |cff16c3f21:00|r
A full v=60 combat=true	|cff999999FULL|r |cff33ff661:00|r	|cff999999FULL|r |cff16c3f21:00|r
A full v=61 combat=false	|cff999999FULL|r |cff33ff661:01|r	|cff999999FULL|r |cff16c3f21:01|r
A full v=61 combat=true	|cff999999FULL|r |cff33ff661:01|r	|cff999999FULL|r |cff16c3f21:01|r
A full v=90 combat=false	|cff999999FULL|r |cff33ff661:30|r	|cff999999FULL|r |cff16c3f21:30|r
A full v=90 combat=true	|cff999999FULL|r |cff33ff661:30|r	|cff999999FULL|r |cff16c3f21:30|r
A full v=125 combat=false	|cff999999FULL|r |cff33ff662:05|r	|cff999999FULL|r |cff16c3f22:05|r
A full v=125 combat=true	|cff999999FULL|r |cff33ff662:05|r	|cff999999FULL|r |cff16c3f22:05|r
A full v=600 combat=false	|cff999999FULL|r |cff33ff6610:00|r	|cff999999FULL|r |cff16c3f210:00|r
A full v=600 combat=true	|cff999999FULL|r |cff33ff6610:00|r	|cff999999FULL|r |cff16c3f210:00|r
A full v=601 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=601 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=605 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=605 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=900 combat=false	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A full v=900 combat=true	|cff999999FULL|r |cff33ff66>10m|r	|cff999999FULL|r |cff16c3f2>10m|r
A warmup v=nil combat=false	|cff999999OOM ...|r
A warmup v=nil combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=0 combat=false	|cff999999OOM ...|r
A warmup v=0 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=15 combat=false	|cff999999OOM ...|r
A warmup v=15 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=19 combat=false	|cff999999OOM ...|r
A warmup v=19 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=20 combat=false	|cff999999OOM ...|r
A warmup v=20 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=45 combat=false	|cff999999OOM ...|r
A warmup v=45 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=59 combat=false	|cff999999OOM ...|r
A warmup v=59 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=60 combat=false	|cff999999OOM ...|r
A warmup v=60 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=61 combat=false	|cff999999OOM ...|r
A warmup v=61 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=90 combat=false	|cff999999OOM ...|r
A warmup v=90 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=125 combat=false	|cff999999OOM ...|r
A warmup v=125 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=600 combat=false	|cff999999OOM ...|r
A warmup v=600 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=601 combat=false	|cff999999OOM ...|r
A warmup v=601 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=605 combat=false	|cff999999OOM ...|r
A warmup v=605 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A warmup v=900 combat=false	|cff999999OOM ...|r
A warmup v=900 combat=true	|cff999999OOM ...|r  |cff999999rest 5:00|r
A hold v=nil combat=false	|cff999999OOM >10m =|r
A hold v=nil combat=true	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
A hold v=0 combat=false	|cff999999OOM >0s =|r
A hold v=0 combat=true	|cff999999OOM >0s =|r  |cff999999rest 5:00|r
A hold v=15 combat=false	|cff999999OOM >15s =|r
A hold v=15 combat=true	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
A hold v=19 combat=false	|cff999999OOM >19s =|r
A hold v=19 combat=true	|cff999999OOM >19s =|r  |cff999999rest 5:00|r
A hold v=20 combat=false	|cff999999OOM >20s =|r
A hold v=20 combat=true	|cff999999OOM >20s =|r  |cff999999rest 5:00|r
A hold v=45 combat=false	|cff999999OOM >45s =|r
A hold v=45 combat=true	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
A hold v=59 combat=false	|cff999999OOM >59s =|r
A hold v=59 combat=true	|cff999999OOM >59s =|r  |cff999999rest 5:00|r
A hold v=60 combat=false	|cff999999OOM >1:00 =|r
A hold v=60 combat=true	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
A hold v=61 combat=false	|cff999999OOM >1:01 =|r
A hold v=61 combat=true	|cff999999OOM >1:01 =|r  |cff999999rest 5:00|r
A hold v=90 combat=false	|cff999999OOM >1:30 =|r
A hold v=90 combat=true	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
A hold v=125 combat=false	|cff999999OOM >2:05 =|r
A hold v=125 combat=true	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
A hold v=600 combat=false	|cff999999OOM >10:00 =|r
A hold v=600 combat=true	|cff999999OOM >10:00 =|r  |cff999999rest 5:00|r
A hold v=601 combat=false	|cff999999OOM >10m =|r
A hold v=601 combat=true	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
A hold v=605 combat=false	|cff999999OOM >10m =|r
A hold v=605 combat=true	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
A hold v=900 combat=false	|cff999999OOM >10m =|r
A hold v=900 combat=true	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
A oom v=nil combat=false	|cff999999OOM --|r
A oom v=nil combat=true	|cff999999OOM --|r  |cff999999rest 5:00|r
A oom v=0 combat=false	|cffff4444OOM 0s vv|r
A oom v=0 combat=true	|cffff4444OOM 0s vv|r  |cff999999rest 5:00|r
A oom v=15 combat=false	|cffff4444OOM 15s vv|r
A oom v=15 combat=true	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
A oom v=19 combat=false	|cffff4444OOM 19s vv|r
A oom v=19 combat=true	|cffff4444OOM 19s vv|r  |cff999999rest 5:00|r
A oom v=20 combat=false	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r
A oom v=20 combat=true	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=45 combat=false	|cff999999OOM|r |cffffaa3345s|r |cff999999=|r	|cff999999OOM|r |cff16c3f245s|r |cff999999=|r
A oom v=45 combat=true	|cff999999OOM|r |cffffaa3345s|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f245s|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=59 combat=false	|cff999999OOM|r |cffffaa3359s|r |cff999999=|r	|cff999999OOM|r |cff16c3f259s|r |cff999999=|r
A oom v=59 combat=true	|cff999999OOM|r |cffffaa3359s|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f259s|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=60 combat=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r
A oom v=60 combat=true	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=61 combat=false	|cff999999OOM|r |cffffffff1:01|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:01|r |cff999999=|r
A oom v=61 combat=true	|cff999999OOM|r |cffffffff1:01|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:01|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=90 combat=false	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
A oom v=90 combat=true	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=125 combat=false	|cff999999OOM|r |cffffffff2:05|r |cff999999=|r	|cff999999OOM|r |cff16c3f22:05|r |cff999999=|r
A oom v=125 combat=true	|cff999999OOM|r |cffffffff2:05|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f22:05|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=600 combat=false	|cff999999OOM|r |cffffffff10:00|r |cff999999=|r	|cff999999OOM|r |cff16c3f210:00|r |cff999999=|r
A oom v=600 combat=true	|cff999999OOM|r |cffffffff10:00|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f210:00|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=601 combat=false	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r
A oom v=601 combat=true	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=605 combat=false	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r
A oom v=605 combat=true	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 5:00|r
A oom v=900 combat=false	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r
A oom v=900 combat=true	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=true arrow=none	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=true arrow=eq	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=true arrow=down	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=true arrow=up	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=false arrow=none	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=false arrow=eq	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=false arrow=down	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=false stable=false arrow=up	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=true arrow=none	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=true arrow=eq	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=true arrow=down	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=true arrow=up	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=false arrow=none	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=false arrow=eq	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=false arrow=down	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=nil bounded=true stable=false arrow=up	|cff999999OOM --|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=true arrow=none	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=true arrow=eq	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=true arrow=down	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=true arrow=up	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=false arrow=none	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=false arrow=eq	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=false arrow=down	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=false stable=false arrow=up	|cffff4444OOM 15s vv|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=true arrow=none	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=true arrow=eq	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=true arrow=down	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=true arrow=up	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=false arrow=none	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=false arrow=eq	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=false arrow=down	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=15 bounded=true stable=false arrow=up	|cff999999OOM >15s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=true arrow=none	|cff999999OOM|r |cffffaa3345s|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f245s|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=true arrow=eq	|cff999999OOM|r |cffffaa3345s|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f245s|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=true arrow=down	|cff999999OOM|r |cffffaa3345s|r |cffffaa33v|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f245s|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=true arrow=up	|cff999999OOM|r |cffffaa3345s|r |cff33ff66^|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f245s|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=false arrow=none	|cff999999OOM|r |cff999999~45s|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=false arrow=eq	|cff999999OOM|r |cff999999~45s|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=false arrow=down	|cff999999OOM|r |cff999999~45s|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=45 bounded=false stable=false arrow=up	|cff999999OOM|r |cff999999~45s|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=true arrow=none	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=true arrow=eq	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=true arrow=down	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=true arrow=up	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=false arrow=none	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=false arrow=eq	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=false arrow=down	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=45 bounded=true stable=false arrow=up	|cff999999OOM >45s =|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=true arrow=none	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=true arrow=eq	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=true arrow=down	|cff999999OOM|r |cffffffff1:00|r |cffffaa33v|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:00|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=true arrow=up	|cff999999OOM|r |cffffffff1:00|r |cff33ff66^|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:00|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=false arrow=none	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=false arrow=eq	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=false arrow=down	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=60 bounded=false stable=false arrow=up	|cff999999OOM|r |cff999999~1:00|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=true arrow=none	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=true arrow=eq	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=true arrow=down	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=true arrow=up	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=false arrow=none	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=false arrow=eq	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=false arrow=down	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=60 bounded=true stable=false arrow=up	|cff999999OOM >1:00 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=true arrow=none	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=true arrow=eq	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=true arrow=down	|cff999999OOM|r |cffffffff1:30|r |cffffaa33v|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:30|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=true arrow=up	|cff999999OOM|r |cffffffff1:30|r |cff33ff66^|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f21:30|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=false arrow=none	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=false arrow=eq	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=false arrow=down	|cff999999OOM|r |cff999999~1:30|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=90 bounded=false stable=false arrow=up	|cff999999OOM|r |cff999999~1:30|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=true arrow=none	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=true arrow=eq	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=true arrow=down	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=true arrow=up	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=false arrow=none	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=false arrow=eq	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=false arrow=down	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=90 bounded=true stable=false arrow=up	|cff999999OOM >1:30 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=true arrow=none	|cff999999OOM|r |cffffffff2:05|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f22:05|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=true arrow=eq	|cff999999OOM|r |cffffffff2:05|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f22:05|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=true arrow=down	|cff999999OOM|r |cffffffff2:05|r |cffffaa33v|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f22:05|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=true arrow=up	|cff999999OOM|r |cffffffff2:05|r |cff33ff66^|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f22:05|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=false arrow=none	|cff999999OOM|r |cff999999~2:05|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=false arrow=eq	|cff999999OOM|r |cff999999~2:05|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=false arrow=down	|cff999999OOM|r |cff999999~2:05|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=125 bounded=false stable=false arrow=up	|cff999999OOM|r |cff999999~2:05|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=true arrow=none	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=true arrow=eq	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=true arrow=down	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=true arrow=up	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=false arrow=none	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=false arrow=eq	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=false arrow=down	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=125 bounded=true stable=false arrow=up	|cff999999OOM >2:05 =|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=true arrow=none	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=true arrow=eq	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=true arrow=down	|cff999999OOM|r |cffffffff>10m|r |cffffaa33v|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=true arrow=up	|cff999999OOM|r |cffffffff>10m|r |cff33ff66^|r  |cff999999rest 5:00|r	|cff999999OOM|r |cff16c3f2>10m|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=false arrow=none	|cff999999OOM|r |cff999999~>10m|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=false arrow=eq	|cff999999OOM|r |cff999999~>10m|r |cff999999=|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=false arrow=down	|cff999999OOM|r |cff999999~>10m|r |cffffaa33v|r  |cff999999rest 5:00|r
B oom v=605 bounded=false stable=false arrow=up	|cff999999OOM|r |cff999999~>10m|r |cff33ff66^|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=true arrow=none	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=true arrow=eq	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=true arrow=down	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=true arrow=up	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=false arrow=none	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=false arrow=eq	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=false arrow=down	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
B oom v=605 bounded=true stable=false arrow=up	|cff999999OOM >10m =|r  |cff999999rest 5:00|r
C warmup v=nil rest=nil	|cff999999OOM ...|r
C warmup v=nil rest=20.4	|cff999999OOM ...|r  |cff999999rest 20s|r
C warmup v=nil rest=29.6	|cff999999OOM ...|r  |cff999999rest 30s|r
C warmup v=nil rest=50	|cff999999OOM ...|r  |cff999999rest 50s|r
C warmup v=nil rest=75	|cff999999OOM ...|r  |cff999999rest 1:15|r
C warmup v=nil rest=100	|cff999999OOM ...|r  |cff999999rest 1:40|r
C warmup v=nil rest=700	|cff999999OOM ...|r  |cff999999rest >10m|r
C warmup v=60 rest=nil	|cff999999OOM ...|r
C warmup v=60 rest=20.4	|cff999999OOM ...|r  |cff999999rest 20s|r
C warmup v=60 rest=29.6	|cff999999OOM ...|r  |cff999999rest 30s|r
C warmup v=60 rest=50	|cff999999OOM ...|r
C warmup v=60 rest=75	|cff999999OOM ...|r  |cff999999rest 1:15|r
C warmup v=60 rest=100	|cff999999OOM ...|r  |cff999999rest 1:40|r
C warmup v=60 rest=700	|cff999999OOM ...|r  |cff999999rest >10m|r
C warmup v=90 rest=nil	|cff999999OOM ...|r
C warmup v=90 rest=20.4	|cff999999OOM ...|r  |cff999999rest 20s|r
C warmup v=90 rest=29.6	|cff999999OOM ...|r  |cff999999rest 30s|r
C warmup v=90 rest=50	|cff999999OOM ...|r  |cff999999rest 50s|r
C warmup v=90 rest=75	|cff999999OOM ...|r
C warmup v=90 rest=100	|cff999999OOM ...|r
C warmup v=90 rest=700	|cff999999OOM ...|r  |cff999999rest >10m|r
C warmup v=700 rest=nil	|cff999999OOM ...|r
C warmup v=700 rest=20.4	|cff999999OOM ...|r  |cff999999rest 20s|r
C warmup v=700 rest=29.6	|cff999999OOM ...|r  |cff999999rest 30s|r
C warmup v=700 rest=50	|cff999999OOM ...|r  |cff999999rest 50s|r
C warmup v=700 rest=75	|cff999999OOM ...|r  |cff999999rest 1:15|r
C warmup v=700 rest=100	|cff999999OOM ...|r  |cff999999rest 1:40|r
C warmup v=700 rest=700	|cff999999OOM ...|r  |cff999999rest >10m|r
C hold v=nil rest=nil	|cff999999OOM >10m =|r
C hold v=nil rest=20.4	|cff999999OOM >10m =|r  |cff999999rest 20s|r
C hold v=nil rest=29.6	|cff999999OOM >10m =|r  |cff999999rest 30s|r
C hold v=nil rest=50	|cff999999OOM >10m =|r  |cff999999rest 50s|r
C hold v=nil rest=75	|cff999999OOM >10m =|r  |cff999999rest 1:15|r
C hold v=nil rest=100	|cff999999OOM >10m =|r  |cff999999rest 1:40|r
C hold v=nil rest=700	|cff999999OOM >10m =|r  |cff999999rest >10m|r
C hold v=60 rest=nil	|cff999999OOM >1:00 =|r
C hold v=60 rest=20.4	|cff999999OOM >1:00 =|r  |cff999999rest 20s|r
C hold v=60 rest=29.6	|cff999999OOM >1:00 =|r  |cff999999rest 30s|r
C hold v=60 rest=50	|cff999999OOM >1:00 =|r
C hold v=60 rest=75	|cff999999OOM >1:00 =|r  |cff999999rest 1:15|r
C hold v=60 rest=100	|cff999999OOM >1:00 =|r  |cff999999rest 1:40|r
C hold v=60 rest=700	|cff999999OOM >1:00 =|r  |cff999999rest >10m|r
C hold v=90 rest=nil	|cff999999OOM >1:30 =|r
C hold v=90 rest=20.4	|cff999999OOM >1:30 =|r  |cff999999rest 20s|r
C hold v=90 rest=29.6	|cff999999OOM >1:30 =|r  |cff999999rest 30s|r
C hold v=90 rest=50	|cff999999OOM >1:30 =|r  |cff999999rest 50s|r
C hold v=90 rest=75	|cff999999OOM >1:30 =|r
C hold v=90 rest=100	|cff999999OOM >1:30 =|r
C hold v=90 rest=700	|cff999999OOM >1:30 =|r  |cff999999rest >10m|r
C hold v=700 rest=nil	|cff999999OOM >10m =|r
C hold v=700 rest=20.4	|cff999999OOM >10m =|r  |cff999999rest 20s|r
C hold v=700 rest=29.6	|cff999999OOM >10m =|r  |cff999999rest 30s|r
C hold v=700 rest=50	|cff999999OOM >10m =|r  |cff999999rest 50s|r
C hold v=700 rest=75	|cff999999OOM >10m =|r  |cff999999rest 1:15|r
C hold v=700 rest=100	|cff999999OOM >10m =|r  |cff999999rest 1:40|r
C hold v=700 rest=700	|cff999999OOM >10m =|r  |cff999999rest >10m|r
C oom v=nil rest=nil	|cff999999OOM --|r
C oom bounded v=nil rest=nil	|cff999999OOM --|r
C oom v=nil rest=20.4	|cff999999OOM --|r  |cff999999rest 20s|r
C oom bounded v=nil rest=20.4	|cff999999OOM --|r  |cff999999rest 20s|r
C oom v=nil rest=29.6	|cff999999OOM --|r  |cff999999rest 30s|r
C oom bounded v=nil rest=29.6	|cff999999OOM --|r  |cff999999rest 30s|r
C oom v=nil rest=50	|cff999999OOM --|r  |cff999999rest 50s|r
C oom bounded v=nil rest=50	|cff999999OOM --|r  |cff999999rest 50s|r
C oom v=nil rest=75	|cff999999OOM --|r  |cff999999rest 1:15|r
C oom bounded v=nil rest=75	|cff999999OOM --|r  |cff999999rest 1:15|r
C oom v=nil rest=100	|cff999999OOM --|r  |cff999999rest 1:40|r
C oom bounded v=nil rest=100	|cff999999OOM --|r  |cff999999rest 1:40|r
C oom v=nil rest=700	|cff999999OOM --|r  |cff999999rest >10m|r
C oom bounded v=nil rest=700	|cff999999OOM --|r  |cff999999rest >10m|r
C oom v=60 rest=nil	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r
C oom bounded v=60 rest=nil	|cff999999OOM >1:00 =|r
C oom v=60 rest=20.4	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 20s|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 20s|r
C oom bounded v=60 rest=20.4	|cff999999OOM >1:00 =|r  |cff999999rest 20s|r
C oom v=60 rest=29.6	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 30s|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 30s|r
C oom bounded v=60 rest=29.6	|cff999999OOM >1:00 =|r  |cff999999rest 30s|r
C oom v=60 rest=50	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r
C oom bounded v=60 rest=50	|cff999999OOM >1:00 =|r  |cff999999rest 50s|r
C oom v=60 rest=75	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 1:15|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 1:15|r
C oom bounded v=60 rest=75	|cff999999OOM >1:00 =|r  |cff999999rest 1:15|r
C oom v=60 rest=100	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 1:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 1:40|r
C oom bounded v=60 rest=100	|cff999999OOM >1:00 =|r  |cff999999rest 1:40|r
C oom v=60 rest=700	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest >10m|r
C oom bounded v=60 rest=700	|cff999999OOM >1:00 =|r  |cff999999rest >10m|r
C oom v=90 rest=nil	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
C oom bounded v=90 rest=nil	|cff999999OOM >1:30 =|r
C oom v=90 rest=20.4	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 20s|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 20s|r
C oom bounded v=90 rest=20.4	|cff999999OOM >1:30 =|r  |cff999999rest 20s|r
C oom v=90 rest=29.6	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 30s|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 30s|r
C oom bounded v=90 rest=29.6	|cff999999OOM >1:30 =|r  |cff999999rest 30s|r
C oom v=90 rest=50	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 50s|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 50s|r
C oom bounded v=90 rest=50	|cff999999OOM >1:30 =|r  |cff999999rest 50s|r
C oom v=90 rest=75	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
C oom bounded v=90 rest=75	|cff999999OOM >1:30 =|r  |cff999999rest 1:15|r
C oom v=90 rest=100	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
C oom bounded v=90 rest=100	|cff999999OOM >1:30 =|r  |cff999999rest 1:40|r
C oom v=90 rest=700	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest >10m|r
C oom bounded v=90 rest=700	|cff999999OOM >1:30 =|r  |cff999999rest >10m|r
C oom v=700 rest=nil	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r
C oom bounded v=700 rest=nil	|cff999999OOM >10m =|r
C oom v=700 rest=20.4	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 20s|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 20s|r
C oom bounded v=700 rest=20.4	|cff999999OOM >10m =|r  |cff999999rest 20s|r
C oom v=700 rest=29.6	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 30s|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 30s|r
C oom bounded v=700 rest=29.6	|cff999999OOM >10m =|r  |cff999999rest 30s|r
C oom v=700 rest=50	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 50s|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 50s|r
C oom bounded v=700 rest=50	|cff999999OOM >10m =|r  |cff999999rest 50s|r
C oom v=700 rest=75	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 1:15|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 1:15|r
C oom bounded v=700 rest=75	|cff999999OOM >10m =|r  |cff999999rest 1:15|r
C oom v=700 rest=100	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest 1:40|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest 1:40|r
C oom bounded v=700 rest=100	|cff999999OOM >10m =|r  |cff999999rest 1:40|r
C oom v=700 rest=700	|cff999999OOM|r |cffffffff>10m|r |cff999999=|r  |cff999999rest >10m|r	|cff999999OOM|r |cff16c3f2>10m|r |cff999999=|r  |cff999999rest >10m|r
C oom bounded v=700 rest=700	|cff999999OOM >10m =|r  |cff999999rest >10m|r
D cd1 v=60 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff4fa9f0inn 40s|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff4fa9f0inn 40s|r
D cd1 v=60 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd1 v=60 bounded=true showCooldown=true	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd1 v=60 bounded=true showCooldown=false	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd1 v=90 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff4fa9f0inn 40s|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff4fa9f0inn 40s|r
D cd1 v=90 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd1 v=90 bounded=true showCooldown=true	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd1 v=90 bounded=true showCooldown=false	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd1 v=95 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd1 v=95 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd1 v=95 bounded=true showCooldown=true	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd1 v=95 bounded=true showCooldown=false	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd1 hold v=90	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd1 out of combat v=90	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
D cd2 v=60 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff4fa9f0inn 2:15|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff4fa9f0inn 2:15|r
D cd2 v=60 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd2 v=60 bounded=true showCooldown=true	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd2 v=60 bounded=true showCooldown=false	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd2 v=90 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff4fa9f0inn 2:15|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff4fa9f0inn 2:15|r
D cd2 v=90 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd2 v=90 bounded=true showCooldown=true	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd2 v=90 bounded=true showCooldown=false	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd2 v=95 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd2 v=95 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd2 v=95 bounded=true showCooldown=true	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd2 v=95 bounded=true showCooldown=false	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd2 hold v=90	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd2 out of combat v=90	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
D cd3 v=60 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=60 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=60 bounded=true showCooldown=true	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd3 v=60 bounded=true showCooldown=false	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd3 v=90 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=90 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=90 bounded=true showCooldown=true	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd3 v=90 bounded=true showCooldown=false	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd3 v=95 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=95 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd3 v=95 bounded=true showCooldown=true	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd3 v=95 bounded=true showCooldown=false	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd3 hold v=90	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd3 out of combat v=90	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
D cd4 v=60 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=60 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=60 bounded=true showCooldown=true	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd4 v=60 bounded=true showCooldown=false	|cff999999OOM >1:00 =|r  |cff999999rest 6:40|r
D cd4 v=90 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=90 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=90 bounded=true showCooldown=true	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd4 v=90 bounded=true showCooldown=false	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd4 v=95 bounded=false showCooldown=true	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=95 bounded=false showCooldown=false	|cff999999OOM|r |cffffffff1:35|r |cff999999=|r  |cff999999rest 6:40|r	|cff999999OOM|r |cff16c3f21:35|r |cff999999=|r  |cff999999rest 6:40|r
D cd4 v=95 bounded=true showCooldown=true	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd4 v=95 bounded=true showCooldown=false	|cff999999OOM >1:35 =|r  |cff999999rest 6:40|r
D cd4 hold v=90	|cff999999OOM >1:30 =|r  |cff999999rest 6:40|r
D cd4 out of combat v=90	|cff999999OOM|r |cffffffff1:30|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:30|r |cff999999=|r
E warmup showRest=false	|cff999999OOM ...|r
E hold showRest=false	|cff999999OOM >1:00 =|r
E oom showRest=false	|cff999999OOM|r |cffffffff1:00|r |cff999999=|r	|cff999999OOM|r |cff16c3f21:00|r |cff999999=|r
]==]
-- GOLDEN-TBC-END
-- GOLDEN-FOREVER-BEGIN
GOLDEN.forever = [==[
F fullnow ttf=nil	~FULL
F fullnow ttf=-3	~FULL
F fullnow ttf=0	~FULL
F fullnow ttf=2.4	~FULL
F fullnow ttf=2.6	~FULL
F fullnow ttf=10	~FULL
F fullnow ttf=19	~FULL
F fullnow ttf=59	~FULL
F fullnow ttf=62.4	~FULL
F fullnow ttf=597.6	~FULL
F fullnow ttf=600	~FULL
F fullnow ttf=600.4	~FULL
F fullnow ttf=601	~FULL
F fullnow ttf=602.6	~FULL
F fullnow ttf=1000000000	~FULL
F fullnow ttf=inf	~FULL
F ooc ttf=nil	~FULL --
F ooc ttf=-3	~FULL 0:00
F ooc ttf=0	~FULL 0:00
F ooc ttf=2.4	~FULL 0:00
F ooc ttf=2.6	~FULL 0:05
F ooc ttf=10	~FULL 0:10
F ooc ttf=19	~FULL 0:20
F ooc ttf=59	~FULL 1:00
F ooc ttf=62.4	~FULL 1:00
F ooc ttf=597.6	~FULL 10:00
F ooc ttf=600	~FULL 10:00
F ooc ttf=600.4	~FULL >10m
F ooc ttf=601	~FULL >10m
F ooc ttf=602.6	~FULL >10m
F ooc ttf=1000000000	~FULL >10m
F ooc ttf=inf	~FULL >10m
F full ttf=nil	~FULL --
F full ttf=-3	~FULL 0:00
F full ttf=0	~FULL 0:00
F full ttf=2.4	~FULL 0:00
F full ttf=2.6	~FULL 0:05
F full ttf=10	~FULL 0:10
F full ttf=19	~FULL 0:20
F full ttf=59	~FULL 1:00
F full ttf=62.4	~FULL 1:00
F full ttf=597.6	~FULL 10:00
F full ttf=600	~FULL 10:00
F full ttf=600.4	~FULL >10m
F full ttf=601	~FULL >10m
F full ttf=602.6	~FULL >10m
F full ttf=1000000000	~FULL >10m
F full ttf=inf	~FULL >10m
F warmup tto=nil rest=nil	~OOM ...
F warmup tto=nil rest=nil	~OOM ...
F warmup tto=nil rest=nil	~OOM ...
F warmup tto=nil rest=nil	~OOM ...
F warmup tto=nil rest=nil	~OOM ...
F warmup tto=nil rest=30	~OOM ...  rest 0:30
F warmup tto=nil rest=700	~OOM ...  rest >10m
F warmup tto=-3 rest=nil	~OOM ...
F warmup tto=-3 rest=-3	~OOM ...  rest 0:00
F warmup tto=-3 rest=-3.6	~OOM ...  rest 0:00
F warmup tto=-3 rest=-3.9	~OOM ...  rest 0:00
F warmup tto=-3 rest=-2.1	~OOM ...  rest 0:00
F warmup tto=-3 rest=30	~OOM ...  rest 0:30
F warmup tto=-3 rest=700	~OOM ...  rest >10m
F warmup tto=0 rest=nil	~OOM ...
F warmup tto=0 rest=0	~OOM ...  rest 0:00
F warmup tto=0 rest=0	~OOM ...  rest 0:00
F warmup tto=0 rest=0	~OOM ...  rest 0:00
F warmup tto=0 rest=0	~OOM ...  rest 0:00
F warmup tto=0 rest=30	~OOM ...  rest 0:30
F warmup tto=0 rest=700	~OOM ...  rest >10m
F warmup tto=2.4 rest=nil	~OOM ...
F warmup tto=2.4 rest=2.4	~OOM ...  rest 0:00
F warmup tto=2.4 rest=2.88	~OOM ...  rest 0:05
F warmup tto=2.4 rest=3.12	~OOM ...  rest 0:05
F warmup tto=2.4 rest=1.68	~OOM ...  rest 0:00
F warmup tto=2.4 rest=30	~OOM ...  rest 0:30
F warmup tto=2.4 rest=700	~OOM ...  rest >10m
F warmup tto=2.6 rest=nil	~OOM ...
F warmup tto=2.6 rest=2.6	~OOM ...  rest 0:05
F warmup tto=2.6 rest=3.12	~OOM ...  rest 0:05
F warmup tto=2.6 rest=3.38	~OOM ...  rest 0:05
F warmup tto=2.6 rest=1.82	~OOM ...  rest 0:00
F warmup tto=2.6 rest=30	~OOM ...  rest 0:30
F warmup tto=2.6 rest=700	~OOM ...  rest >10m
F warmup tto=10 rest=nil	~OOM ...
F warmup tto=10 rest=10	~OOM ...  rest 0:10
F warmup tto=10 rest=12	~OOM ...  rest 0:10
F warmup tto=10 rest=13	~OOM ...  rest 0:15
F warmup tto=10 rest=7	~OOM ...  rest 0:05
F warmup tto=10 rest=30	~OOM ...  rest 0:30
F warmup tto=10 rest=700	~OOM ...  rest >10m
F warmup tto=19 rest=nil	~OOM ...
F warmup tto=19 rest=19	~OOM ...  rest 0:20
F warmup tto=19 rest=22.8	~OOM ...  rest 0:25
F warmup tto=19 rest=24.7	~OOM ...  rest 0:25
F warmup tto=19 rest=13.3	~OOM ...  rest 0:15
F warmup tto=19 rest=30	~OOM ...  rest 0:30
F warmup tto=19 rest=700	~OOM ...  rest >10m
F warmup tto=59 rest=nil	~OOM ...
F warmup tto=59 rest=59	~OOM ...  rest 1:00
F warmup tto=59 rest=70.8	~OOM ...  rest 1:10
F warmup tto=59 rest=76.7	~OOM ...  rest 1:15
F warmup tto=59 rest=41.3	~OOM ...  rest 0:40
F warmup tto=59 rest=30	~OOM ...  rest 0:30
F warmup tto=59 rest=700	~OOM ...  rest >10m
F warmup tto=62.4 rest=nil	~OOM ...
F warmup tto=62.4 rest=62.4	~OOM ...  rest 1:00
F warmup tto=62.4 rest=74.88	~OOM ...  rest 1:15
F warmup tto=62.4 rest=81.12	~OOM ...  rest 1:20
F warmup tto=62.4 rest=43.68	~OOM ...  rest 0:45
F warmup tto=62.4 rest=30	~OOM ...  rest 0:30
F warmup tto=62.4 rest=700	~OOM ...  rest >10m
F warmup tto=597.6 rest=nil	~OOM ...
F warmup tto=597.6 rest=597.6	~OOM ...  rest 10:00
F warmup tto=597.6 rest=717.12	~OOM ...  rest >10m
F warmup tto=597.6 rest=776.88	~OOM ...  rest >10m
F warmup tto=597.6 rest=418.32	~OOM ...  rest 7:00
F warmup tto=597.6 rest=30	~OOM ...  rest 0:30
F warmup tto=597.6 rest=700	~OOM ...  rest >10m
F warmup tto=600 rest=nil	~OOM ...
F warmup tto=600 rest=600	~OOM ...  rest 10:00
F warmup tto=600 rest=720	~OOM ...  rest >10m
F warmup tto=600 rest=780	~OOM ...  rest >10m
F warmup tto=600 rest=420	~OOM ...  rest 7:00
F warmup tto=600 rest=30	~OOM ...  rest 0:30
F warmup tto=600 rest=700	~OOM ...  rest >10m
F warmup tto=600.4 rest=nil	~OOM ...
F warmup tto=600.4 rest=600.4	~OOM ...  rest >10m
F warmup tto=600.4 rest=720.48	~OOM ...  rest >10m
F warmup tto=600.4 rest=780.52	~OOM ...  rest >10m
F warmup tto=600.4 rest=420.28	~OOM ...  rest 7:00
F warmup tto=600.4 rest=30	~OOM ...  rest 0:30
F warmup tto=600.4 rest=700	~OOM ...  rest >10m
F warmup tto=601 rest=nil	~OOM ...
F warmup tto=601 rest=601	~OOM ...  rest >10m
F warmup tto=601 rest=721.2	~OOM ...  rest >10m
F warmup tto=601 rest=781.3	~OOM ...  rest >10m
F warmup tto=601 rest=420.7	~OOM ...  rest 7:00
F warmup tto=601 rest=30	~OOM ...  rest 0:30
F warmup tto=601 rest=700	~OOM ...  rest >10m
F warmup tto=602.6 rest=nil	~OOM ...
F warmup tto=602.6 rest=602.6	~OOM ...  rest >10m
F warmup tto=602.6 rest=723.12	~OOM ...  rest >10m
F warmup tto=602.6 rest=783.38	~OOM ...  rest >10m
F warmup tto=602.6 rest=421.82	~OOM ...  rest 7:00
F warmup tto=602.6 rest=30	~OOM ...  rest 0:30
F warmup tto=602.6 rest=700	~OOM ...  rest >10m
F warmup tto=1000000000 rest=nil	~OOM ...
F warmup tto=1000000000 rest=1000000000	~OOM ...  rest >10m
F warmup tto=1000000000 rest=1200000000	~OOM ...  rest >10m
F warmup tto=1000000000 rest=1300000000	~OOM ...  rest >10m
F warmup tto=1000000000 rest=700000000	~OOM ...  rest >10m
F warmup tto=1000000000 rest=30	~OOM ...  rest 0:30
F warmup tto=1000000000 rest=700	~OOM ...  rest >10m
F warmup tto=inf rest=nil	~OOM ...
F warmup tto=inf rest=inf	~OOM ...  rest >10m
F warmup tto=inf rest=inf	~OOM ...  rest >10m
F warmup tto=inf rest=inf	~OOM ...  rest >10m
F warmup tto=inf rest=inf	~OOM ...  rest >10m
F warmup tto=inf rest=30	~OOM ...  rest 0:30
F warmup tto=inf rest=700	~OOM ...  rest >10m
F hold tto=nil rest=nil	~OOM --
F hold tto=nil rest=nil	~OOM --
F hold tto=nil rest=nil	~OOM --
F hold tto=nil rest=nil	~OOM --
F hold tto=nil rest=nil	~OOM --
F hold tto=nil rest=30	~OOM --  rest 0:30
F hold tto=nil rest=700	~OOM --  rest >10m
F hold tto=-3 rest=nil	~OOM --
F hold tto=-3 rest=-3	~OOM --  rest 0:00
F hold tto=-3 rest=-3.6	~OOM --  rest 0:00
F hold tto=-3 rest=-3.9	~OOM --  rest 0:00
F hold tto=-3 rest=-2.1	~OOM --  rest 0:00
F hold tto=-3 rest=30	~OOM --  rest 0:30
F hold tto=-3 rest=700	~OOM --  rest >10m
F hold tto=0 rest=nil	~OOM --
F hold tto=0 rest=0	~OOM --  rest 0:00
F hold tto=0 rest=0	~OOM --  rest 0:00
F hold tto=0 rest=0	~OOM --  rest 0:00
F hold tto=0 rest=0	~OOM --  rest 0:00
F hold tto=0 rest=30	~OOM --  rest 0:30
F hold tto=0 rest=700	~OOM --  rest >10m
F hold tto=2.4 rest=nil	~OOM --
F hold tto=2.4 rest=2.4	~OOM --  rest 0:00
F hold tto=2.4 rest=2.88	~OOM --  rest 0:05
F hold tto=2.4 rest=3.12	~OOM --  rest 0:05
F hold tto=2.4 rest=1.68	~OOM --  rest 0:00
F hold tto=2.4 rest=30	~OOM --  rest 0:30
F hold tto=2.4 rest=700	~OOM --  rest >10m
F hold tto=2.6 rest=nil	~OOM --
F hold tto=2.6 rest=2.6	~OOM --  rest 0:05
F hold tto=2.6 rest=3.12	~OOM --  rest 0:05
F hold tto=2.6 rest=3.38	~OOM --  rest 0:05
F hold tto=2.6 rest=1.82	~OOM --  rest 0:00
F hold tto=2.6 rest=30	~OOM --  rest 0:30
F hold tto=2.6 rest=700	~OOM --  rest >10m
F hold tto=10 rest=nil	~OOM --
F hold tto=10 rest=10	~OOM --  rest 0:10
F hold tto=10 rest=12	~OOM --  rest 0:10
F hold tto=10 rest=13	~OOM --  rest 0:15
F hold tto=10 rest=7	~OOM --  rest 0:05
F hold tto=10 rest=30	~OOM --  rest 0:30
F hold tto=10 rest=700	~OOM --  rest >10m
F hold tto=19 rest=nil	~OOM --
F hold tto=19 rest=19	~OOM --  rest 0:20
F hold tto=19 rest=22.8	~OOM --  rest 0:25
F hold tto=19 rest=24.7	~OOM --  rest 0:25
F hold tto=19 rest=13.3	~OOM --  rest 0:15
F hold tto=19 rest=30	~OOM --  rest 0:30
F hold tto=19 rest=700	~OOM --  rest >10m
F hold tto=59 rest=nil	~OOM --
F hold tto=59 rest=59	~OOM --  rest 1:00
F hold tto=59 rest=70.8	~OOM --  rest 1:10
F hold tto=59 rest=76.7	~OOM --  rest 1:15
F hold tto=59 rest=41.3	~OOM --  rest 0:40
F hold tto=59 rest=30	~OOM --  rest 0:30
F hold tto=59 rest=700	~OOM --  rest >10m
F hold tto=62.4 rest=nil	~OOM --
F hold tto=62.4 rest=62.4	~OOM --  rest 1:00
F hold tto=62.4 rest=74.88	~OOM --  rest 1:15
F hold tto=62.4 rest=81.12	~OOM --  rest 1:20
F hold tto=62.4 rest=43.68	~OOM --  rest 0:45
F hold tto=62.4 rest=30	~OOM --  rest 0:30
F hold tto=62.4 rest=700	~OOM --  rest >10m
F hold tto=597.6 rest=nil	~OOM --
F hold tto=597.6 rest=597.6	~OOM --  rest 10:00
F hold tto=597.6 rest=717.12	~OOM --  rest >10m
F hold tto=597.6 rest=776.88	~OOM --  rest >10m
F hold tto=597.6 rest=418.32	~OOM --  rest 7:00
F hold tto=597.6 rest=30	~OOM --  rest 0:30
F hold tto=597.6 rest=700	~OOM --  rest >10m
F hold tto=600 rest=nil	~OOM --
F hold tto=600 rest=600	~OOM --  rest 10:00
F hold tto=600 rest=720	~OOM --  rest >10m
F hold tto=600 rest=780	~OOM --  rest >10m
F hold tto=600 rest=420	~OOM --  rest 7:00
F hold tto=600 rest=30	~OOM --  rest 0:30
F hold tto=600 rest=700	~OOM --  rest >10m
F hold tto=600.4 rest=nil	~OOM --
F hold tto=600.4 rest=600.4	~OOM --  rest >10m
F hold tto=600.4 rest=720.48	~OOM --  rest >10m
F hold tto=600.4 rest=780.52	~OOM --  rest >10m
F hold tto=600.4 rest=420.28	~OOM --  rest 7:00
F hold tto=600.4 rest=30	~OOM --  rest 0:30
F hold tto=600.4 rest=700	~OOM --  rest >10m
F hold tto=601 rest=nil	~OOM --
F hold tto=601 rest=601	~OOM --  rest >10m
F hold tto=601 rest=721.2	~OOM --  rest >10m
F hold tto=601 rest=781.3	~OOM --  rest >10m
F hold tto=601 rest=420.7	~OOM --  rest 7:00
F hold tto=601 rest=30	~OOM --  rest 0:30
F hold tto=601 rest=700	~OOM --  rest >10m
F hold tto=602.6 rest=nil	~OOM --
F hold tto=602.6 rest=602.6	~OOM --  rest >10m
F hold tto=602.6 rest=723.12	~OOM --  rest >10m
F hold tto=602.6 rest=783.38	~OOM --  rest >10m
F hold tto=602.6 rest=421.82	~OOM --  rest 7:00
F hold tto=602.6 rest=30	~OOM --  rest 0:30
F hold tto=602.6 rest=700	~OOM --  rest >10m
F hold tto=1000000000 rest=nil	~OOM --
F hold tto=1000000000 rest=1000000000	~OOM --  rest >10m
F hold tto=1000000000 rest=1200000000	~OOM --  rest >10m
F hold tto=1000000000 rest=1300000000	~OOM --  rest >10m
F hold tto=1000000000 rest=700000000	~OOM --  rest >10m
F hold tto=1000000000 rest=30	~OOM --  rest 0:30
F hold tto=1000000000 rest=700	~OOM --  rest >10m
F hold tto=inf rest=nil	~OOM --
F hold tto=inf rest=inf	~OOM --  rest >10m
F hold tto=inf rest=inf	~OOM --  rest >10m
F hold tto=inf rest=inf	~OOM --  rest >10m
F hold tto=inf rest=inf	~OOM --  rest >10m
F hold tto=inf rest=30	~OOM --  rest 0:30
F hold tto=inf rest=700	~OOM --  rest >10m
F oom tto=nil rest=nil	~OOM --
F oom tto=nil rest=nil	~OOM --
F oom tto=nil rest=nil	~OOM --
F oom tto=nil rest=nil	~OOM --
F oom tto=nil rest=nil	~OOM --
F oom tto=nil rest=30	~OOM --  rest 0:30
F oom tto=nil rest=700	~OOM --  rest >10m
F oom tto=-3 rest=nil	~OOM 0:00
F oom tto=-3 rest=-3	~OOM 0:00
F oom tto=-3 rest=-3.6	~OOM 0:00  rest 0:00
F oom tto=-3 rest=-3.9	~OOM 0:00  rest 0:00
F oom tto=-3 rest=-2.1	~OOM 0:00  rest 0:00
F oom tto=-3 rest=30	~OOM 0:00  rest 0:30
F oom tto=-3 rest=700	~OOM 0:00  rest >10m
F oom tto=0 rest=nil	~OOM 0:00
F oom tto=0 rest=0	~OOM 0:00
F oom tto=0 rest=0	~OOM 0:00
F oom tto=0 rest=0	~OOM 0:00
F oom tto=0 rest=0	~OOM 0:00
F oom tto=0 rest=30	~OOM 0:00  rest 0:30
F oom tto=0 rest=700	~OOM 0:00  rest >10m
F oom tto=2.4 rest=nil	~OOM 0:00
F oom tto=2.4 rest=2.4	~OOM 0:00
F oom tto=2.4 rest=2.88	~OOM 0:00
F oom tto=2.4 rest=3.12	~OOM 0:00  rest 0:05
F oom tto=2.4 rest=1.68	~OOM 0:00  rest 0:00
F oom tto=2.4 rest=30	~OOM 0:00  rest 0:30
F oom tto=2.4 rest=700	~OOM 0:00  rest >10m
F oom tto=2.6 rest=nil	~OOM 0:05
F oom tto=2.6 rest=2.6	~OOM 0:05
F oom tto=2.6 rest=3.12	~OOM 0:05
F oom tto=2.6 rest=3.38	~OOM 0:05  rest 0:05
F oom tto=2.6 rest=1.82	~OOM 0:05  rest 0:00
F oom tto=2.6 rest=30	~OOM 0:05  rest 0:30
F oom tto=2.6 rest=700	~OOM 0:05  rest >10m
F oom tto=10 rest=nil	~OOM 0:10
F oom tto=10 rest=10	~OOM 0:10
F oom tto=10 rest=12	~OOM 0:10
F oom tto=10 rest=13	~OOM 0:10  rest 0:15
F oom tto=10 rest=7	~OOM 0:10  rest 0:05
F oom tto=10 rest=30	~OOM 0:10  rest 0:30
F oom tto=10 rest=700	~OOM 0:10  rest >10m
F oom tto=19 rest=nil	~OOM 0:20
F oom tto=19 rest=19	~OOM 0:20
F oom tto=19 rest=22.8	~OOM 0:20
F oom tto=19 rest=24.7	~OOM 0:20  rest 0:25
F oom tto=19 rest=13.3	~OOM 0:20  rest 0:15
F oom tto=19 rest=30	~OOM 0:20  rest 0:30
F oom tto=19 rest=700	~OOM 0:20  rest >10m
F oom tto=59 rest=nil	~OOM 1:00
F oom tto=59 rest=59	~OOM 1:00
F oom tto=59 rest=70.8	~OOM 1:00
F oom tto=59 rest=76.7	~OOM 1:00  rest 1:15
F oom tto=59 rest=41.3	~OOM 1:00  rest 0:40
F oom tto=59 rest=30	~OOM 1:00  rest 0:30
F oom tto=59 rest=700	~OOM 1:00  rest >10m
F oom tto=62.4 rest=nil	~OOM 1:00
F oom tto=62.4 rest=62.4	~OOM 1:00
F oom tto=62.4 rest=74.88	~OOM 1:00
F oom tto=62.4 rest=81.12	~OOM 1:00  rest 1:20
F oom tto=62.4 rest=43.68	~OOM 1:00  rest 0:45
F oom tto=62.4 rest=30	~OOM 1:00  rest 0:30
F oom tto=62.4 rest=700	~OOM 1:00  rest >10m
F oom tto=597.6 rest=nil	~OOM 10:00
F oom tto=597.6 rest=597.6	~OOM 10:00
F oom tto=597.6 rest=717.12	~OOM 10:00
F oom tto=597.6 rest=776.88	~OOM 10:00  rest >10m
F oom tto=597.6 rest=418.32	~OOM 10:00  rest 7:00
F oom tto=597.6 rest=30	~OOM 10:00  rest 0:30
F oom tto=597.6 rest=700	~OOM 10:00
F oom tto=600 rest=nil	~OOM 10:00
F oom tto=600 rest=600	~OOM 10:00
F oom tto=600 rest=720	~OOM 10:00
F oom tto=600 rest=780	~OOM 10:00  rest >10m
F oom tto=600 rest=420	~OOM 10:00  rest 7:00
F oom tto=600 rest=30	~OOM 10:00  rest 0:30
F oom tto=600 rest=700	~OOM 10:00
F oom tto=600.4 rest=nil	~OOM >10m
F oom tto=600.4 rest=600.4	~OOM >10m
F oom tto=600.4 rest=720.48	~OOM >10m
F oom tto=600.4 rest=780.52	~OOM >10m  rest >10m
F oom tto=600.4 rest=420.28	~OOM >10m  rest 7:00
F oom tto=600.4 rest=30	~OOM >10m  rest 0:30
F oom tto=600.4 rest=700	~OOM >10m
F oom tto=601 rest=nil	~OOM >10m
F oom tto=601 rest=601	~OOM >10m
F oom tto=601 rest=721.2	~OOM >10m
F oom tto=601 rest=781.3	~OOM >10m  rest >10m
F oom tto=601 rest=420.7	~OOM >10m  rest 7:00
F oom tto=601 rest=30	~OOM >10m  rest 0:30
F oom tto=601 rest=700	~OOM >10m
F oom tto=602.6 rest=nil	~OOM >10m
F oom tto=602.6 rest=602.6	~OOM >10m
F oom tto=602.6 rest=723.12	~OOM >10m
F oom tto=602.6 rest=783.38	~OOM >10m  rest >10m
F oom tto=602.6 rest=421.82	~OOM >10m  rest 7:00
F oom tto=602.6 rest=30	~OOM >10m  rest 0:30
F oom tto=602.6 rest=700	~OOM >10m
F oom tto=1000000000 rest=nil	~OOM >10m
F oom tto=1000000000 rest=1000000000	~OOM >10m
F oom tto=1000000000 rest=1200000000	~OOM >10m
F oom tto=1000000000 rest=1300000000	~OOM >10m  rest >10m
F oom tto=1000000000 rest=700000000	~OOM >10m  rest >10m
F oom tto=1000000000 rest=30	~OOM >10m  rest 0:30
F oom tto=1000000000 rest=700	~OOM >10m  rest >10m
F oom tto=inf rest=nil	~OOM >10m
F oom tto=inf rest=inf	~OOM >10m
F oom tto=inf rest=inf	~OOM >10m
F oom tto=inf rest=inf	~OOM >10m
F oom tto=inf rest=inf	~OOM >10m
F oom tto=inf rest=30	~OOM >10m
F oom tto=inf rest=700	~OOM >10m
F nil	~OOM --
F string	~OOM --
F empty table	~OOM --
F numeric mode	~OOM --
F unknown mode	~OOM --
]==]
-- GOLDEN-FOREVER-END

Finish()
