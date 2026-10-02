-- tools/run.sh --flavour tbc tools/clocktextcheck.lua
-- tools/run.sh --flavour forever tools/clocktextcheck.lua
--
-- T114 (docs/tasks/T114-clock-face-slots.md; docs/mockups/clock-v2.html C1):
-- the clock's SLOTS and their words, as plain data. Engine/ClockFace.lua's
-- slot kinds (CF.KINDS), the slots per layout (CF.TEXT / CF.TEXT_OPTIONS),
-- CF.ResolveText (the time never lost), CF.Slots, the word options (labels,
-- ofMax, time), Segments / JoinSegments / LineString following Line's slots
-- -- byte-identical by default -- and the two producers' new fields (TBC
-- MD:GetClockFace, Forever ManaModel.Face: mana / manaMax / manaModelled, fsr,
-- the regen feed's mp5). Thirteen checks per flavour, all failing on the
-- parent (no CF.Slots):
--    1. CF.Time's formats;          2. the defaults are today's words;
--    3. CF.ResolveText;             4. TBC's words;  5. Forever's words;
--    6. mp5 is the regen feed's number;  7. fsr;  8. labels = lower, left = none;
--    9. the time is never lost;    10. right2;  11. Compact and Bar pieces;
--   12. the matrix (ASCII, no bare pipe, never a lone 0);  13. the producers.
-- The words of 4 / 5 / 8-12 are pure (Engine/ClockFace.lua is shared): each
-- flavour runs them on a TBC-shaped and a Forever-shaped face; 6, 7 and 13
-- drive this flavour's own producer.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")
local check = T.check
local FLAVOUR = S.flavour
local FOREVER = FLAVOUR == "forever"
local CF = MD.ClockFace
local HEX = "|cff16c3f2"

-- A block that raises (on the parent: no CF.Slots) is one FAIL, not the end.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

local function HasSlots() return type(CF.Slots) == "function" and type(CF.TEXT) == "table"
    and type(CF.ResolveText) == "function" end

local function Copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end
local function Sample(key)
    for _, s in ipairs(CF.SAMPLES) do if s.key == key then return Copy(s.face) end end
end
-- A face as the Forever line words it: modelled, one colour, M:SS, no arrow.
local function ForeverShaped(f)
    f = Copy(f)
    f.modelled, f.mono, f.timeFmt, f.unstable, f.arrow = true, true, "mss", false, nil
    f.pctModelled, f.mp5Modelled, f.manaModelled = true, true, true
    return f
end
local function LineShaped(f) return FOREVER and ForeverShaped(f) or f end

-- The words fixture: OOM 1:20 v, rest 2:10, 62 %, 4210 of 6800, 92 mp5.
local function Words(extra)
    local f = Sample("oom")
    f.pct, f.mana, f.manaMax, f.mp5 = 0.62, 4210, 6800, 92
    f.pctModelled, f.mp5Modelled, f.manaModelled = false, false, false
    f.second = { kind = "rest", label = "rest", value = 130 }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

local function Plain(s) return T.Strip(s or "") end
local function VT(p) return p and CF.ValueText(p) or nil end
local function Join(face, text, look)
    look = look and Copy(look) or {}
    look.text = text
    return CF.JoinSegments(CF.Segments(face, look))
end

-- Feeds on TBC: the harness drops UI/ (but for UI/Summary.lua); load it by
-- hand, handing it the MD_READY it missed.
if not MD.Feeds then
    local ready, realReg = {}, MD.RegisterCallback
    MD.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    local okLoad, err = pcall(S.Load, { "UI/Feeds.lua" }, "SpellTuner", MD)
    MD.RegisterCallback = realReg
    if not okLoad then print("load UI/Feeds.lua: " .. tostring(err)) end
    for _, fn in ipairs(ready) do pcall(fn) end
end

local function Ticks(n) for _ = 1, n do S.Tick(0.5) end end
Ticks(4)

--------------------------------------------------------------------------------
-- 1. CF.Time
--------------------------------------------------------------------------------
T.section("1. CF.Time")
Guarded("1. CF.Time", function()
    local cases = {
        { 15, "auto", "15s" }, { 80, "auto", "1:20" }, { 15, "mss", "0:15" }, { 80, "mss", "1:20" },
        { 80, "sec", "80s" }, { 15, "sec", "15s" }, { 80, "msec", "1m20" }, { 120, "msec", "2m00" },
        { 15, "msec", "15s" },
        { 601, "auto", ">10m" }, { 601, "mss", ">10m" }, { 601, "sec", ">10m" }, { 601, "msec", ">10m" },
        { nil, "auto", "--" }, { nil, "mss", "--" }, { nil, "sec", "--" }, { nil, "msec", "--" },
    }
    local bad = {}
    for _, c in ipairs(cases) do
        local got = CF.Time(c[1], c[2])
        if got ~= c[3] then bad[#bad + 1] = tostring(c[1]) .. "/" .. c[2] .. "=" .. tostring(got) end
    end
    check("1. CF.Time: auto / mss unchanged; sec 80s; msec 1m20 / 2m00 / 15s; >10m in all; nil --",
        #bad == 0 and HasSlots(), table.concat(bad, ", "))
end)

--------------------------------------------------------------------------------
-- 2. the defaults are today's
--------------------------------------------------------------------------------
T.section("2. defaults")
Guarded("2. defaults", function()
    local bad
    for _, s in ipairs(CF.SAMPLES) do
        local f = LineShaped(s.face)
        for _, hex in ipairs({ false, HEX }) do
            local h = hex or nil
            local today = CF.LineString(f, h)
            if CF.LineString(f, h, CF.TEXT.line) ~= today or CF.LineString(f, h, {}) ~= today then
                bad = s.key .. " LineString"
            end
        end
        local todayJ = CF.JoinSegments(CF.Segments(f))
        if Join(f, CF.TEXT.line) ~= todayJ or Join(f, {}) ~= todayJ then bad = s.key .. " Join" end
        local def = CF.Segments(f, { text = CF.TEXT.line })
        local old = CF.Segments(f)
        if VT(def.label) ~= VT(old.label) or VT(def.value) ~= VT(old.value) or VT(def.second) ~= VT(old.second)
            or (def.label and def.label.tone) ~= (old.label and old.label.tone)
            or (def.value and def.value.tone) ~= (old.value and old.value.tone) then
            bad = s.key .. " pieces"
        end
    end
    check("2. defaults are today's: LineString / Segments with CF.TEXT.line equal without, every sample",
        HasSlots() and bad == nil, bad)
end)

--------------------------------------------------------------------------------
-- 3. CF.ResolveText
--------------------------------------------------------------------------------
T.section("3. ResolveText")
Guarded("3. ResolveText", function()
    local facts = { cd = not FOREVER }
    local same = true
    for layout, defaults in pairs(CF.TEXT) do
        local t, refused = CF.ResolveText(nil, layout, facts)
        for k, v in pairs(defaults) do if t[k] ~= v then same = false end end
        if refused ~= nil then same = false end
    end
    local t1, r1 = CF.ResolveText({ right = "bogus", labels = "shout" }, "line", facts)
    local unknown = t1.right == "rest" and t1.labels == "caps" and r1 and r1["text.line.right"] ~= nil
        and r1["text.line.labels"] ~= nil
    local t2, r2 = CF.ResolveText({ right = "cd" }, "line", facts)
    local cdOk
    if FOREVER then
        cdOk = t2.right == "rest" and r2 and r2["text.line.right"] == "cd is not offered on this line"
    else
        cdOk = t2.right == "cd" and r2 == nil
    end
    local _, r3 = CF.ResolveText({ right = "cd" }, "line", { cd = false })
    local t4 = CF.ResolveText({ right = "cd" }, "line", { cd = true })
    local offs = CF.TEXT.line.right2 == "none" and CF.TEXT.compact.bottom == "none"
    check("3. ResolveText: the defaults per layout; an unknown value refused and named; cd per line; "
        .. "right2 / bottom none", same and unknown and cdOk and r3 and r3["text.line.right"] ~= nil
        and t4.right == "cd" and offs,
        string.format("same=%s unknown=%s cd=%s", tostring(same), tostring(unknown), tostring(cdOk)))
end)

--------------------------------------------------------------------------------
-- 4. TBC's words
--------------------------------------------------------------------------------
T.section("4. TBC words")
Guarded("4. TBC words", function()
    local f = Words()
    local function R(kind, extra)
        local text = { right = kind }
        for k, v in pairs(extra or {}) do text[k] = v end
        return VT(CF.Slots(f, text, "line").right)
    end
    local cdFace = Words({ second = { kind = "cd", label = "inn", value = 130 } })
    local cd = VT(CF.Slots(cdFace, { right = "cd" }, "line").right)
    local cdOnRest = CF.Slots(f, { right = "cd" }, "line").right
    local got = { R("pct"), R("mana"), R("mana", { ofMax = true }), R("mp5"), cd }
    check("4. TBC words: 62%, 4210, 4210/6800, 92 mp5, inn 2:10 (cd only on a cooldown secondary)",
        got[1] == "62%" and got[2] == "4210" and got[3] == "4210/6800" and got[4] == "92 mp5"
        and got[5] == "inn 2:10" and cdOnRest == nil
        and Plain(CF.LineString(f, nil, { right = "pct" })) == "OOM 1:20 v  62%",
        table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]), tostring(got[4]), tostring(got[5]) }, " / "))
end)

--------------------------------------------------------------------------------
-- 5. Forever's words
--------------------------------------------------------------------------------
T.section("5. Forever words")
Guarded("5. Forever words", function()
    local f = ForeverShaped(Words())
    local function R(face, kind, extra)
        local text = { right = kind }
        for k, v in pairs(extra or {}) do text[k] = v end
        return VT(CF.Slots(face, text, "line").right)
    end
    local inFight = Copy(f); inFight.combat = true
    local out = Copy(f); out.combat = false
    local got = { R(f, "pct"), R(f, "mana"), R(f, "mana", { ofMax = true }), R(inFight, "mp5"), R(out, "mp5") }
    check("5. Forever words: ~62%, ~4210, ~4210/6800; mp5 ~92 mp5 in a fight, 92 mp5 out of one",
        got[1] == "~62%" and got[2] == "~4210" and got[3] == "~4210/6800" and got[4] == "~92 mp5"
        and got[5] == "92 mp5" and CF.LineString(f, nil, { right = "pct" }) == "~OOM 1:20  ~62%",
        table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]), tostring(got[4]), tostring(got[5]) }, " / "))
end)

--------------------------------------------------------------------------------
-- 6. mp5 is the regen feed's number
--------------------------------------------------------------------------------
T.section("6. mp5 = the regen feed")
local function Spend(n)
    if FOREVER then
        MD.Pool.model:Spend(n, GetTime())
    else
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        S.mana = S.mana - n
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
end
local function Face() return CF.Current(GetTime()) end
local function Mp5Words(face) return VT(CF.Slots(face, { right = "mp5" }, "line").right) end
Guarded("6. mp5", function()
    local read = MD.Feeds and MD.Feeds.RegenReading
    local rows = {}
    local function Row(tag)
        local face, r = Face(), read()
        local words = Mp5Words(face)
        local n = words and tonumber(words:match("^~?(%d+) mp5$"))
        local mark = words and words:sub(1, 1) == "~"
        rows[#rows + 1] = { tag = tag, n = n, want = r and r.mp5, mark = mark, wantMark = r and r.modelled, fsr = r and r.fsr }
    end
    Ticks(14)
    Row("out")
    Spend(100)
    Row("in rule")
    if FOREVER then
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Spend(100)
        Ticks(1)
        Row("fight, rule")
        Ticks(12)
        Row("fight")
        S.Fire("PLAYER_REGEN_ENABLED")
        S.inCombat = false
    end
    Ticks(12)
    local bad, sawIn, sawOut = nil, false, false
    for _, r in ipairs(rows) do
        if r.n == nil or r.n ~= r.want or r.mark ~= (r.wantMark == true) then
            bad = string.format("%s: %s vs feed %s (mark %s/%s)", r.tag, tostring(r.n), tostring(r.want),
                tostring(r.mark), tostring(r.wantMark))
        end
        if r.fsr then sawIn = true else sawOut = true end
    end
    check("6. mp5's number is the regen feed's (RegenReading), in and out of the rule"
        .. (FOREVER and ", ~ in a fight" or ""), type(read) == "function" and HasSlots() and bad == nil
        and sawIn and sawOut and rows[1].n ~= rows[2].n, bad)
end)

--------------------------------------------------------------------------------
-- 7. fsr
--------------------------------------------------------------------------------
T.section("7. fsr")
local function FsrWords() local p = CF.Slots(Face(), { right = "fsr" }, "line").right; return p and p.text end
Guarded("7. fsr", function()
    Ticks(14)
    local before = FsrWords()
    Spend(100)
    Ticks(4)
    local three = FsrWords()
    Ticks(6)
    local after = FsrWords()
    local free = true
    if FOREVER then
        local model = MD.Pool.model
        local last = model.lastSpend
        local realCost = MD.Pool.CostFor
        MD.Pool.CostFor = function(id) if id == 99001 then return 0 end return realCost(id) end
        S.Cast(99001)
        Ticks(1)
        MD.Pool.CostFor = realCost
        free = model.lastSpend == last and FsrWords() == nil
    else
        -- a cast with no mana leaving the pool starts nothing
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 5185)
        Ticks(1)
        free = FsrWords() == nil
    end
    check("7. fsr: 5SR 3.0 two seconds after a spend, empty after five, a free cast starts nothing",
        HasSlots() and before == nil and three == "5SR 3.0" and after == nil and free,
        string.format("before=%s three=%s after=%s free=%s", tostring(before), tostring(three), tostring(after),
            tostring(free)))
end)

--------------------------------------------------------------------------------
-- 8. labels = lower; left = none
--------------------------------------------------------------------------------
T.section("8. labels")
Guarded("8. labels", function()
    local tbc = Words()
    local full = ForeverShaped(Sample("full")); full.value = 45; full.tone = "warn"
    local fe = ForeverShaped(Words())
    local a = Plain(CF.LineString(tbc, nil, { labels = "lower" }))
    local b = CF.LineString(full, nil, { labels = "lower" })
    local c = Join(fe, { left = "none" })
    local d = VT(CF.Slots(fe, { left = "none" }, "line").main)
    local e = Join(tbc, { left = "none", right = "none" })
    check("8. labels lower: out 1:20 v / ~full 0:45; left none: Forever ~1:20, TBC 1:20 v",
        HasSlots() and a == "out 1:20 v  rest 2:10" and b == "~full 0:45" and c == "~1:20  rest 2:10"
        and d == "~1:20" and e == "1:20 v",
        table.concat({ tostring(a), tostring(b), tostring(c), tostring(d), tostring(e) }, " / "))
end)

--------------------------------------------------------------------------------
-- 9. the time is never lost
--------------------------------------------------------------------------------
T.section("9. the time")
Guarded("9. the time", function()
    local f = Words()
    local s1 = CF.Slots(f, { main = "pct" }, "line")
    local ok1 = VT(s1.left) == "OOM 1:20 v" and s1.main.text == "62%" and s1.main.tone == "mana"
        and Plain(CF.LineString(f, nil, { main = "pct" })) == "OOM 1:20 v 62%  rest 2:10"
    local s2 = CF.Slots(f, { main = "mana", top = "time" }, "compact")
    local s2b = CF.Slots(f, { main = "mana" }, "compact")
    local ok2 = VT(s2.top) == "OOM 1:20 v" and s2.main.text == "4210" and VT(s2b.top) == "OOM 1:20 v"
    local t3, r3 = CF.ResolveText({ main = "pct", left = "none" }, "line")
    local s3 = CF.Slots(f, { main = "pct", left = "none" }, "line")
    local ok3 = t3.main == "time" and r3 and r3["text.line.main"] ~= nil and s3.left == nil
        and VT(s3.main) == "1:20 v"
    local fe = ForeverShaped(Words())
    local s4 = CF.Slots(fe, { main = "pct" }, "compact")
    local s5 = CF.Slots(f, { left = "pct" }, "bar")
    local s6 = CF.Slots(fe, { left = "pct" }, "bar")
    local ok4 = VT(s4.top) == "~OOM 1:20" and s4.main.text == "~62%"
        and s5.left.text == "62%" and VT(s5.right) == "OOM 1:20 v" and s6.left.text == "~62%"
        and VT(s6.right) == "~OOM 1:20"
    local _, r7 = CF.ResolveText({ top = "time" }, "compact")
    check("9. the time is never lost: main = pct moves it left; compact top carries it; left = none "
        .. "refused; the mockup's Compact and Bar rows", HasSlots() and ok1 and ok2 and ok3 and ok4
        and r7 and r7["text.compact.top"] ~= nil,
        string.format("line=%s compact=%s none=%s rows=%s", tostring(ok1), tostring(ok2), tostring(ok3), tostring(ok4)))
end)

--------------------------------------------------------------------------------
-- 10. right2
--------------------------------------------------------------------------------
T.section("10. right2")
Guarded("10. right2", function()
    local f = Words()
    local a = Join(f, { right2 = "pct" })
    local b = Plain(CF.LineString(f, nil, { right2 = "pct" }))
    local c = Join(f, { right = "fsr", right2 = "pct" })
    local fe = ForeverShaped(Words())
    local d = CF.LineString(fe, nil, { right2 = "pct" })
    check("10. right2: rest 2:10  62% after two spaces (JoinSegments and LineString); an empty right closes up",
        HasSlots() and a == "OOM 1:20 v  rest 2:10  62%" and b == a and c == "OOM 1:20 v  62%"
        and d == "~OOM 1:20  rest 2:10  ~62%",
        table.concat({ tostring(a), tostring(b), tostring(c), tostring(d) }, " / "))
end)

--------------------------------------------------------------------------------
-- 11. Compact and Bar pieces for every kind
--------------------------------------------------------------------------------
T.section("11. Compact and Bar")
Guarded("11. pieces", function()
    local f = Words({ fsr = 3 })
    local EXPECT = { label = "OOM", pct = "62%", mana = "4210", mp5 = "92 mp5", fsr = "5SR 3.0",
        rest = "rest 2:10" } -- cd: nil on a rest secondary; none: nil
    local bad, n = {}, 0
    for _, layout in ipairs({ "compact", "bar" }) do
        for slot, kinds in pairs(CF.TEXT_OPTIONS[layout]) do
            for _, kind in ipairs(kinds) do
                local text = { [slot] = kind }
                local t = CF.ResolveText(text, layout)
                local pieces = CF.Slots(f, text, layout)
                local p = pieces[slot]
                local got = VT(p)
                local want
                if slot == t.timeAt then
                    want = t.timeLabel and "OOM 1:20 v" or "1:20 v"
                elseif t[slot] ~= kind then
                    want = got -- refused (compact top = time beside main = time): named in 3 / 9
                else
                    want = EXPECT[kind]
                end
                n = n + 1
                if got ~= want then bad[#bad + 1] = layout .. "." .. slot .. "=" .. kind .. ": " .. tostring(got) end
                local timeSomewhere = false
                for _, q in pairs(pieces) do if q and q.time then timeSomewhere = true end end
                if not timeSomewhere then bad[#bad + 1] = layout .. "." .. slot .. "=" .. kind .. ": no time" end
            end
        end
    end
    local c = CF.Slots(f, nil, "compact")
    local b = CF.Slots(f, nil, "bar")
    check("11. Compact (top / main / bottom) and Bar (left / right) pieces for every kind; the time always drawn",
        HasSlots() and #bad == 0 and n > 20 and c.top.text == "OOM" and VT(c.main) == "1:20 v" and c.bottom == nil
        and b.left.text == "OOM" and VT(b.right) == "1:20 v", table.concat(bad, "; "))
end)

--------------------------------------------------------------------------------
-- 12. the matrix
--------------------------------------------------------------------------------
T.section("12. matrix")
local function LoneZero(s)
    for word in Plain(s):gmatch("[^ ]+") do
        local w = word:gsub("^[~>]", "")
        if w == "0" or w == "0%" or w == "0s" or w == "0:00" or w == "0m00" or w == "0/0" or w == "0.0" then
            return true
        end
    end
    return false
end
Guarded("12. matrix", function()
    local bad, n = nil, 0
    local faces = {}
    for _, s in ipairs(CF.SAMPLES) do
        faces[#faces + 1] = { key = s.key, face = Copy(s.face) }
        faces[#faces + 1] = { key = s.key .. "~", face = ForeverShaped(s.face) }
    end
    for _, F in ipairs(faces) do
        for layout, slots in pairs(CF.TEXT_OPTIONS) do
            for slot, kinds in pairs(slots) do
                for _, kind in ipairs(kinds) do
                    for _, fmt in ipairs({ "line", "sec", "msec" }) do
                        for _, labels in ipairs({ "caps", "lower" }) do
                            local text = { [slot] = kind, time = fmt, labels = labels, ofMax = kind == "mana" }
                            local strs = {}
                            for _, p in pairs(CF.Slots(F.face, text, layout)) do strs[#strs + 1] = VT(p) end
                            if layout == "line" then
                                strs[#strs + 1] = CF.LineString(F.face, nil, text)
                                strs[#strs + 1] = CF.LineString(F.face, HEX, text)
                                strs[#strs + 1] = Join(F.face, text)
                            end
                            for _, s in ipairs(strs) do
                                n = n + 1
                                local okA, why = T.Ascii(s)
                                if not okA then bad = F.key .. " " .. layout .. "." .. slot .. "=" .. kind .. ": " .. why end
                                if s:find("nil", 1, true) then bad = F.key .. ": nil in " .. s end
                                if LoneZero(s) then bad = F.key .. " " .. layout .. "." .. slot .. "=" .. kind .. ": zero " .. s end
                                if F.face.mono and s ~= Plain(s) then bad = F.key .. ": colour on a mono face " .. s end
                            end
                        end
                    end
                end
            end
        end
    end
    check("12. every sample x every kind x every slot x the time formats: ASCII, no bare pipe, never a lone 0",
        HasSlots() and bad == nil and n > 1000, bad or (n .. " strings"))
end)

--------------------------------------------------------------------------------
-- 13. the producers
--------------------------------------------------------------------------------
T.section("13. producers")
Guarded("13. producers", function()
    local IsSecret = MD.API.IsSecret
    local function NoSecret(face)
        for k, v in pairs(face) do
            if IsSecret(v) then return k end
            if type(v) == "table" then for k2, v2 in pairs(v) do if IsSecret(v2) then return k .. "." .. k2 end end end
        end
        return nil
    end
    if FOREVER then
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Spend(200)
        Ticks(2)
        local face = Face()
        local model = MD.Pool.model
        local secretField = NoSecret(face)
        local base, casting = MD.API.ManaRegen()
        check("13. Forever ManaModel.Face: the model's mana / manaMax, manaModelled; no field a secret (in a fight)",
            face.mana == model.mana and face.manaMax == model.max and face.manaModelled == true
            and type(face.mana) == "number" and face.mana < model.max and secretField == nil
            and casting == "secret" and type(face.fsr) == "number" and face.mp5 ~= nil,
            string.format("mana=%s/%s max=%s secret=%s regen=%s/%s", tostring(face.mana), tostring(model.mana),
                tostring(face.manaMax), tostring(secretField), tostring(base), tostring(casting)))
        S.Fire("PLAYER_REGEN_ENABLED")
        S.inCombat = false
    else
        S.mana = 4210
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        Ticks(1)
        local face = MD:GetClockFace(GetTime())
        check("13. TBC MD:GetClockFace: mana / manaMax plain, manaModelled false",
            face and face.mana == 4210 and face.manaMax == S.manaMax and face.manaModelled == false
            and NoSecret(face) == nil,
            face and string.format("mana=%s max=%s modelled=%s", tostring(face.mana), tostring(face.manaMax),
                tostring(face.manaModelled)) or "no face")
    end
end)

T.done()
