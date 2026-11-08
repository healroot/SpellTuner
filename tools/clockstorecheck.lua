-- tools/run.sh [--flavour tbc|forever] tools/clockstorecheck.lua
--
-- T145b (docs/SPEC-clock-v3.md 4.4 and 4.5; docs/tasks/T145b-clock-store.md):
-- the clock's look, stored -- UI/ClockStore.lua. What is held, on both
-- flavours:
--   1. the file is pure: it loads and runs with Lua's library and a fake ST
--      holding only db, Fire and AddDumpLine; every main TOC lists it just
--      before UI/ClockBar.lua; T145c: db.clockLook is v3 once MD_READY ran
--      (each clock host calls MigrateStored);
--   2. Normalize repairs each invalid field and names it, drops and names an
--      unknown key, and is idempotent; the defaults and both presets are valid;
--   3. every Set path: an accepted value written, ONE CLOCK_LOOK, the store
--      still valid; a refused value writes nothing and fires nothing;
--   4. presets replace the whole look, Undo restores it exactly, a change
--      ends the undo; P2 over PRESETS (no preset turns off the line or the
--      time) and a preset that would is refused; Reset;
--   5. the migration goldens (4.5): the author's 2026-11-08 store
--      (tools/data/clock-v2-author.lua) to the exact v3 look of 1.5 with its
--      notes; a v1 store, a line layout with overrides, compact, empty, none,
--      a v3 store unchanged, garbage; pure and idempotent; every dropped key
--      named;
--   6. MigrateStored rewrites db.clockLook as v3 only fields, once a
--      session, and the dump line names the notes; a v3 store repaired at
--      login is named too, and a later build's store (v 4) keeps every field
--      that validates (review N3).
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
local check = T.check

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local FLAVOUR = S.flavour

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

-- Deep equality; the first difference as a path.
local function Diff(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then return path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
    if type(a) ~= "table" then
        if a ~= b then return path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return nil
    end
    for k, v in pairs(a) do
        local d = Diff(v, b[k], path .. "." .. tostring(k))
        if d then return d end
    end
    for k, v in pairs(b) do
        if a[k] == nil then return path .. "." .. tostring(k) .. ": nil vs " .. tostring(v) end
    end
    return nil
end
local function Same(a, b) return Diff(a, b) == nil end

-- A fresh, pure copy of the file: Lua's library, and a fake ST.
local function Fresh(db)
    local env = {
        string = string, table = table, math = math, pairs = pairs, ipairs = ipairs, type = type,
        tostring = tostring, tonumber = tonumber, next = next, select = select, error = error,
        setmetatable = setmetatable, getmetatable = getmetatable, pcall = pcall, unpack = unpack,
    }
    local fake = { db = db or {}, fired = {}, dump = {} }
    function fake:Fire(event) self.fired[#self.fired + 1] = event end
    function fake:AddDumpLine(key, fn) self.dump[key] = fn end
    local chunk, err = loadfile(S.root .. "/UI/ClockStore.lua")
    if not chunk then error(err) end
    setfenv(chunk, setmetatable({}, { __index = function(_, k)
        local v = env[k]
        if v == nil then error("UI/ClockStore.lua is not pure: reads global " .. tostring(k), 2) end
        return v
    end }))
    chunk("SpellTuner", fake)
    return fake.ClockStore, fake
end

--------------------------------------------------------------------------------
T.section("1. pure, in every main TOC, and not yet read")
--------------------------------------------------------------------------------
local CS0
do
    local ok, err = pcall(function() CS0 = Fresh() end)
    check("1. UI/ClockStore.lua loads with Lua's library and a fake ST (db, Fire, AddDumpLine)",
        ok and type(CS0) == "table" and type(CS0.Migrate) == "function", tostring(err))
    local placed = {}
    for _, toc in ipairs({ "SpellTuner_Mainline.toc", "SpellTuner.toc", "SpellTuner_TBC.toc" }) do
        local files = S.TocFiles(toc)
        local store, view
        for i, rel in ipairs(files) do
            if rel == "UI/ClockStore.lua" then store = i end
            if rel == "UI/ClockBar.lua" then view = i end
        end
        placed[#placed + 1] = (store and view and store == view - 1) and true or false
    end
    check("1. every main TOC lists UI/ClockStore.lua just before UI/ClockBar.lua (T145c)",
        placed[1] and placed[2] and placed[3])
    if FLAVOUR == "forever" then
        local live = ST.db and ST.db.clockLook
        check("1. the Forever TOC loaded it; T145c: db.clockLook is v3 after MD_READY (MigrateStored wired)",
            type(ST.ClockStore) == "table" and type(live) == "table" and live.v == 3 and live.over == nil
            and CS0.Valid(live),
            "v=" .. tostring(live and live.v))
        local look = ST.ClockStore.Look()
        check("1. Look() of the live store is a valid v3 copy, not the stored table",
            CS0.Valid(look) and ST.db.clockLook.v == 3 and ST.db.clockLook ~= look and Same(look, ST.db.clockLook))
    else
        check("1. the TBC harness draws nothing (UI/ is not loaded): the pure copy stands in", ST.ClockStore == nil)
    end
end
local CS = CS0

--------------------------------------------------------------------------------
T.section("2. Normalize")
--------------------------------------------------------------------------------
do
    local d = CS.DEFAULTS
    local okD = CS.Valid(d)
    local okP = true
    for _, p in ipairs(CS.PRESETS) do if not CS.Valid(p.look) then okP = false end end
    check("2. the defaults and every preset are valid v3 looks", okD and okP)
    check("2. the defaults are the SpellTuner preset (the author's T142 pick)",
        Same(CS.Preset("spelltuner").look, d) and d.width == 200 and d.height == 8 and d.shape == "round"
        and d.frame == "game" and d.texture == "eui:pixels-dark" and d.font == "eui" and d.fill == "mana"
        and d.back == "0A0A0A" and d.backAlpha == 1 and d.line == true and d.timeFmt == "mss" and d.warn == true
        and d.texts.time.place == "below" and d.texts.time.align == "left" and d.texts.mana.place == "inside"
        and d.texts.mp5.on == true and d.texts.mp5.colour == "9FD7A9")

    local bad = {
        width = 99, height = 31, shape = "thin", frame = "panel", texture = "gradient", font = "x",
        fill = "tone", back = "12345", backAlpha = 1.5, line = "yes", timeFmt = "msec", warn = 1,
    }
    local allNamed, allRepaired = true, true
    for f, v in pairs(bad) do
        local raw = Copy(d); raw[f] = v
        local look, notes = CS.Normalize(raw)
        if look[f] ~= d[f] then allRepaired = false end
        if not (#notes == 1 and notes[1]:find(f, 1, true) == 1 and notes[1]:find("not accepted", 1, true)) then
            allNamed = false
        end
    end
    check("2. each invalid bar field is repaired to its default and named, alone", allNamed and allRepaired)

    local badText = { on = "on", place = "left", align = "middle", x = 41, y = -21, size = 5, colour = "red",
        outline = "mono" }
    local tNamed = true
    for f, v in pairs(badText) do
        local raw = Copy(d); raw.texts.pct[f] = v
        local look, notes = CS.Normalize(raw)
        if look.texts.pct[f] ~= d.texts.pct[f] or #notes ~= 1 or not notes[1]:find("texts.pct." .. f, 1, true) then
            tNamed = false
        end
    end
    check("2. each invalid text field is repaired and named, alone", tNamed)

    local raw = Copy(d)
    raw.over, raw.layout = {}, "bar"
    raw.texts.label = { on = true }
    raw.texts.mana.ofMax = true
    raw.texts.rest = nil
    raw.width = nil
    local look, notes = CS.Normalize(raw)
    local joined = table.concat(notes, " / ")
    check("2. unknown keys dropped and named, a missing text and field put back and named",
        Same(look, d) and #notes == 6 and joined:find("over dropped", 1, true) and joined:find("layout dropped", 1, true)
        and joined:find("texts.label dropped", 1, true) and joined:find("texts.mana.ofMax dropped", 1, true)
        and joined:find("texts.rest missing", 1, true) and joined:find("width missing", 1, true), joined)
    local again, notes2 = CS.Normalize(look)
    check("2. idempotent: Normalize of a Normalize changes nothing and names nothing",
        Same(again, look) and #notes2 == 0 and again ~= look)
    local g, gn = CS.Normalize("garbage")
    check("2. not a table: the defaults, named", Same(g, d) and #gn == 1)
end

--------------------------------------------------------------------------------
T.section("3. Set: one write, one CLOCK_LOOK; a refusal writes nothing")
--------------------------------------------------------------------------------
do
    local C, F = Fresh({ clockLook = Copy(CS0.DEFAULTS) })
    local good = {
        { "width", 260 }, { "height", 12 }, { "shape", "pill" }, { "frame", "border" }, { "texture", "lsm:Foo" },
        { "texture", "gloss" }, { "font", "st" }, { "fill", "class" }, { "fill", "112233" }, { "back", "222222" },
        { "backAlpha", 0.5 }, { "line", false }, { "timeFmt", "sec" }, { "warn", false },
        { "texts.mana.size", 20 }, { "texts.rest.on", true }, { "texts.time.place", "above" },
        { "texts.pct.colour", "ABCDEF" }, { "texts.fsr.outline", "thick" }, { "texts.mp5.x", -40 },
        { "texts.time.y", 20 }, { "texts.manaMax.align", "right" },
    }
    local allOk, detail = true, nil
    for _, kv in ipairs(good) do
        local n0 = #F.fired
        local ok, why = C.Set(kv[1], kv[2])
        local stored = C.Get(kv[1])
        local valid = C.Valid(F.db.clockLook)
        if not (ok and #F.fired == n0 + 1 and F.fired[#F.fired] == "CLOCK_LOOK" and stored == kv[2] and valid) then
            allOk, detail = false, kv[1] .. " " .. tostring(why)
        end
    end
    check("3. every field written through Set: stored, one CLOCK_LOOK, still valid (" .. #good .. ")", allOk, detail)

    local before = Copy(F.db.clockLook)
    local n0 = #F.fired
    local refused = {
        { "width", 401 }, { "height", 2.5 }, { "shape", "thin" }, { "texture", "gradient" }, { "texture", "eui:" },
        { "fill", "tone" }, { "backAlpha", -0.1 }, { "line", nil }, { "timeFmt", "line" }, { "layout", "bar" },
        { "texts.label.on", true }, { "texts.mana.ofMax", true }, { "texts.mana.size", 33 }, { "texts.mana.colour", "E4E1D" },
        { "v", 2 }, { 42, 1 },
    }
    local allRefused = true
    for _, kv in ipairs(refused) do
        local ok, why = C.Set(kv[1], kv[2])
        if ok or type(why) ~= "string" then allRefused = false end
    end
    check("3. every refused value answers false and why, writes nothing, fires nothing (" .. #refused .. ")",
        allRefused and Same(F.db.clockLook, before) and #F.fired == n0)
    local okT = C.SetText("rest", "size", 14)
    check("3. SetText is the same path", okT and C.Get("texts.rest.size") == 14 and #F.fired == n0 + 1)

    -- an older store is migrated by the first write, with the write's one event
    local C2, F2 = Fresh({ clockLook = { layout = "bar", over = { frame = { bar = { w = 300 } } }, v = 2 } })
    local ok2 = C2.Set("height", 10)
    check("3. a write to a v2 store: migrated first (v3, its width kept), one CLOCK_LOOK",
        ok2 and F2.db.clockLook.v == 3 and F2.db.clockLook.width == 300 and F2.db.clockLook.height == 10
        and F2.db.clockLook.over == nil and #F2.fired == 1)
    local C3, F3 = Fresh({})
    F3.db = nil
    check("3. no saved variables yet: refused", not C3.Set("width", 200))
end

--------------------------------------------------------------------------------
T.section("4. presets, Undo, Reset (P2)")
--------------------------------------------------------------------------------
do
    local p2 = true
    for _, p in ipairs(CS.PRESETS) do
        if p.look.line ~= true or p.look.texts.time.on ~= true or not CS.PresetOK(p.look) then p2 = false end
    end
    check("4. P2: no preset sets line = false or texts.time.on = false (" .. #CS.PRESETS .. " presets)", p2)
    check("4. two presets, SpellTuner and EllesmereUI",
        #CS.PRESETS == 2 and CS.PRESETS[1].key == "spelltuner" and CS.PRESETS[2].key == "ellesmere"
        and CS.PRESETS[1].name == "SpellTuner" and CS.PRESETS[2].name == "EllesmereUI")
    local e = CS.Preset("ellesmere").look
    check("4. EllesmereUI: game frame, round, 260 x 8, Pixels Dark, 008CFF on 111111 at 75 %, the line on, mana inside 15 y +2, time below right 11, regen off",
        e.frame == "game" and e.shape == "round" and e.width == 260 and e.height == 8 and e.texture == "eui:pixels-dark"
        and e.fill == "008CFF" and e.back == "111111" and e.backAlpha == 0.75 and e.line == true
        and e.texts.mana.place == "inside" and e.texts.mana.size == 15 and e.texts.mana.y == 2 and e.texts.mana.outline == "outline"
        and e.texts.time.place == "below" and e.texts.time.align == "right" and e.texts.time.size == 11
        and e.texts.time.outline == "outline" and e.texts.mp5.on == false)

    local mine = Copy(CS.DEFAULTS)
    mine.width, mine.line, mine.texts.rest.on, mine.texts.time.size = 333, false, true, 19
    local C, F = Fresh({ clockLook = Copy(mine) })
    local n0 = #F.fired
    local ok = C.ApplyPreset("ellesmere")
    check("4. a preset replaces the whole look in one CLOCK_LOOK, Undo offered",
        ok and Same(F.db.clockLook, CS.Preset("ellesmere").look) and #F.fired == n0 + 1 and C.HasUndo())
    local okU = C.Undo()
    check("4. Undo puts the previous look back exactly, in one CLOCK_LOOK, and is spent",
        okU and Same(F.db.clockLook, mine) and #F.fired == n0 + 2 and not C.HasUndo() and not C.Undo())
    C.ApplyPreset("spelltuner")
    C.Set("width", 150)
    check("4. a change after a preset ends the undo", not C.HasUndo() and F.db.clockLook.width == 150)
    C.ApplyPreset("ellesmere", { fill = "aabbcc" })
    check("4. EllesmereUI takes the host's mana colour when the pane passes one", F.db.clockLook.fill == "AABBCC")
    C.ApplyPreset("spelltuner", { fill = "aabbcc" })
    check("4. SpellTuner ignores a host colour", F.db.clockLook.fill == "mana")

    local before = Copy(F.db.clockLook)
    local n1 = #F.fired
    local bad = Copy(CS.DEFAULTS); bad.line = false
    C.PRESETS[#C.PRESETS + 1] = { key = "noline", name = "No line", look = bad }
    local bad2 = Copy(CS.DEFAULTS); bad2.texts.time.on = false
    C.PRESETS[#C.PRESETS + 1] = { key = "notime", name = "No time", look = bad2 }
    local r1, why1 = C.ApplyPreset("noline")
    local r2, why2 = C.ApplyPreset("notime")
    local r3 = C.ApplyPreset("nosuch")
    check("4. a preset that would hide the line or the time is refused, writing nothing",
        not r1 and not r2 and not r3 and Same(F.db.clockLook, before) and #F.fired == n1,
        tostring(why1) .. " / " .. tostring(why2))

    local okR = C.Reset()
    check("4. Reset: the defaults, one CLOCK_LOOK", okR and Same(F.db.clockLook, CS.DEFAULTS) and #F.fired == n1 + 1)
end

--------------------------------------------------------------------------------
T.section("5. migration goldens (4.5)")
--------------------------------------------------------------------------------
local function It(on, place, align, x, y, size, colour, outline)
    return { on = on, place = place, align = align, x = x, y = y, size = size, colour = colour, outline = outline }
end
do
    local author = dofile(S.root .. "/tools/data/clock-v2-author.lua")
    local pristine = Copy(author)
    local look, notes, from = CS.Migrate(author)
    -- SPEC-clock-v3 section 1.5, field for field
    local want = {
        v = 3, width = 260, height = 8, shape = "round", frame = "game", texture = "eui:pixels-dark", font = "eui",
        fill = "008CFF", back = "111111", backAlpha = 0.75, line = true, timeFmt = "sec", warn = true,
        texts = {
            time = It(true, "below", "right", 0, 1, 15, "E3E3E3", "outline"),
            mana = It(true, "inside", "center", 0, 1, 14, "E3E3E3", "outline"),
            mp5 = It(false, "inside", "left", 0, 1, 15, "CDD4D0", "outline"),
            manaMax = It(false, "inside", "center", 0, 0, 12, "E3E3E3", "outline"),
            pct = It(false, "inside", "right", -4, 0, 10, "E3E3E3", "outline"),
            fsr = It(false, "below", "left", 0, -1, 10, "FFAB33", "outline"),
            rest = It(false, "below", "right", 0, -1, 10, "8F8A83", "outline"),
        },
    }
    check("5. the author's store migrates to the exact v3 look of section 1.5", Same(look, want) and from == "v2",
        Diff(look, want))
    local wantNotes = {
        "dropped bars.bar.after = empty: the line simply ends with the rule",
        "dropped bars.bar.fsr = 2: only the stacked strip used it",
        "changed bars.bar.show = mana -> the 5SR line on",
        "dropped text.bar.items.label (inside left, 4/0, 10): its word is now part of the time",
    }
    check("5. and its notes: label, after = empty, fsr = 2 dropped; show = mana -> the line on",
        Same(notes, wantNotes), table.concat(notes, " / "))
    check("5. pure: the author's store is untouched", Same(author, pristine))
    local again, notes2, from2 = CS.Migrate(look)
    check("5. idempotent: the migrated look migrates to itself with no notes",
        Same(again, look) and #notes2 == 0 and from2 == "v3")

    -- every dropped key named: each leaf of the old over is a v3 field or in a note
    local mapped = { ["colors.manaBar"] = true, ["bar.back"] = true, ["frame.bar.w"] = true, ["text.bar.time"] = true }
    local unnamed = {}
    local function Walk(t, prefix)
        for k, x in pairs(t) do
            local key = prefix .. "." .. k
            if type(x) == "table" and x[1] == nil then Walk(x, key) else
                key = key:sub(2)
                local item = key:match("^text%.bar%.items%.([^.]+)")
                local named = mapped[key] or (item and item ~= "label")
                for _, n in ipairs(notes) do
                    if n:find(key, 1, true) or (item == "label" and n:find("text.bar.items.label", 1, true)) then named = true end
                end
                if not named then unnamed[#unnamed + 1] = key end
            end
        end
    end
    Walk(author.over, "")
    check("5. every key of the author's store is a v3 field or named in a note", #unnamed == 0, unnamed[1])

    -- a v1 store (0.16.6): bar.source = "model", a spark, a colour
    local v1 = { layout = "line", over = { bar = { source = "model", spark = true, color = { 1, 0, 0 }, height = 6 },
        frame = { line = { w = 220 } } } }
    local l1, n1, f1 = CS.Migrate(v1)
    local j1 = table.concat(n1, " / ")
    check("5. a v1 store: the defaults (T142 reset the Bar look), every old key named",
        f1 == "v1" and Same(l1, CS.DEFAULTS) and j1:find("bar.spark", 1, true) and j1:find("bar.height", 1, true)
        and j1:find("colors.manaBar", 1, true) and j1:find("bars.line.show", 1, true)
        and j1:find("frame.line.w = 220: Line and Compact are gone", 1, true)
        and j1:find("changed layout = line -> the Bar", 1, true), j1)

    -- a line layout with overrides, its Bar keys migrated
    local line = { layout = "line", v = 2, over = {
        bars = { line = { join = "veil" }, bar = { shape = "thin", texture = "gradient", border = 2, frame = "border" } },
        text = { line = { left = "pct" }, bar = { time = "msec", labels = "lower" } },
        colors = { manaBar = "tone", crit = "FF0000" }, panel = { fill = { 0, 0, 0, 0.5 } },
        frame = { bar = { h = 30, scale = 120 } } } }
    local l2, n2, f2 = CS.Migrate(line)
    local j2 = table.concat(n2, " / ")
    check("5. a line layout: the Bar with its Bar keys migrated (thin -> rect 4 px, gradient -> flat, tone -> mana, msec -> sec)",
        f2 == "v2" and l2.shape == "rect" and l2.height == 4 and l2.texture == "flat" and l2.frame == "border"
        and l2.fill == "mana" and l2.timeFmt == "sec" and l2.line == true and CS.Valid(l2), Diff(l2, CS.DEFAULTS))
    local names = { "bars.line.join", "text.line.left", "text.bar.labels", "colors.crit", "panel.fill", "frame.bar.h",
        "frame.bar.scale", "bars.bar.border", "layout = line", "shape = thin", "texture = gradient", "manaBar = tone",
        "time = msec" }
    local missing
    for _, k in ipairs(names) do if not j2:find(k, 1, true) then missing = k end end
    check("5. ... and every dropped or changed key named", missing == nil, missing or j2)

    local l3, n3 = CS.Migrate({ layout = "compact", v = 2, over = { text = { compact = { main = "pct" } } } })
    check("5. a compact layout: the defaults, compact and its keys named",
        Same(l3, CS.DEFAULTS) and table.concat(n3, " / "):find("layout = compact", 1, true)
        and table.concat(n3, " / "):find("text.compact.main", 1, true))

    local l4, n4, f4 = CS.Migrate({})
    local l5, n5, f5 = CS.Migrate(nil)
    check("5. an empty store and no store: the defaults, nothing named",
        Same(l4, CS.DEFAULTS) and #n4 == 0 and f4 == "none" and Same(l5, CS.DEFAULTS) and #n5 == 0 and f5 == "none")

    local mine = Copy(CS.DEFAULTS); mine.width, mine.texts.rest.on = 310, true
    local l6, n6, f6 = CS.Migrate(mine)
    check("5. a v3 store: unchanged (a copy), nothing named", Same(l6, mine) and l6 ~= mine and #n6 == 0 and f6 == "v3")

    local okG = true
    for _, g in ipairs({ "garbage", 42, true, { v = 2, layout = 7, over = "x" },
        { v = 2, over = { bars = { bar = { shape = 9, height = "tall" } }, text = { bar = { items = { time = { size = 99 }, nope = {} } } } } } }) do
        local lg, ng = CS.Migrate(g)
        if not CS.Valid(lg) or #ng == 0 then okG = false end
    end
    check("5. garbage stores: a valid look, the defaults where nothing was readable, every refusal named", okG)
    local _, ng2 = CS.Migrate({ v = 2, over = { text = { bar = { items = { time = { size = 99 }, nope = { on = true } } } } } })
    local jg = table.concat(ng2, " / ")
    check("5. an item field out of range and an unknown text are named",
        jg:find("text.bar.items.time.size = 99", 1, true) and jg:find("text.bar.items.nope", 1, true), jg)
end

--------------------------------------------------------------------------------
T.section("6. MigrateStored and the dump line")
--------------------------------------------------------------------------------
do
    local author = dofile(S.root .. "/tools/data/clock-v2-author.lua")
    local C, F = Fresh({ clockLook = author })
    local changed, notes = C.MigrateStored()
    local s = F.db.clockLook
    local onlyV3 = true
    for k in pairs(s) do
        local known = k == "v" or k == "texts"
        for _, f in ipairs(C.FIELDS) do if f == k then known = true end end
        if not known then onlyV3 = false end
    end
    check("6. MigrateStored: db.clockLook is the v3 look, only v3 fields (no over, no layout), no event",
        changed and s.v == 3 and s.over == nil and s.layout == nil and onlyV3 and C.Valid(s) and #F.fired == 0
        and #notes == 4)
    local again = C.MigrateStored()
    check("6. once a session: a second call changes nothing", again == false and F.db.clockLook == s)
    local line = F.dump.clock and F.dump.clock()
    local hasAll = type(line) == "string"
    for _, n in ipairs(notes) do if not (hasAll and line:find(n, 1, true)) then hasAll = false end end
    check("6. the dump line (key clock) says v3, what is set, and names every note",
        hasAll and line:sub(1, 10) == "clock: v3," and line:find("migrated from v2, 4 notes", 1, true)
        and line:find("width", 1, true) and not line:find("|", 1, true) and not line:find("[\128-\255]"), line)
    local fresh = select(1, Fresh({}))
    check("6. a fresh store's line: no fields set, no migration named",
        fresh.DumpLine() == "clock: v3, 0 fields set", fresh.DumpLine())
end
do
    -- T145 review N3: a v3 store repaired at login is named in the dump
    local C0 = select(1, Fresh({}))
    local bad = Copy(C0.DEFAULTS)
    bad.width = 9999
    local C, F = Fresh({ clockLook = bad })
    local _, notes = C.MigrateStored()
    local line = F.dump.clock and F.dump.clock()
    check("6. a v3 store repaired at login: the dump line names the repair (review N3)",
        #notes == 1 and type(line) == "string" and line:find("repaired v3, 1 note", 1, true)
        and line:find(notes[1], 1, true) ~= nil and F.db.clockLook.width == C.DEFAULTS.width, line)
    -- a store from a later build (v 4) keeps every field that validates
    local later = Copy(C0.DEFAULTS)
    later.v = 4
    later.width = 333
    later.texts.rest.on = true
    later.newThing = 1
    local look, lnotes, from = C0.Migrate(later)
    local text = table.concat(lnotes, "; ")
    check("6. a store from a later build (v 4): normalized, every valid field kept, the rest named (review N3)",
        from == "v4" and look.v == 3 and look.width == 333 and look.texts.rest.on == true and look.newThing == nil
        and text:find("v 4 -> 3", 1, true) ~= nil and text:find("newThing dropped", 1, true) ~= nil, from .. ": " .. text)
end

T.done()
