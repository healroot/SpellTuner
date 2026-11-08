-- tools/lib/clockdrive.lua -- T145c (docs/SPEC-clock-v3.md 4.2-4.3): the clock
-- driven the way the author drives it, from the live host (UI/Clock_Forever.lua
-- on Forever, UI/Widget.lua on TBC) and its renderer (UI/ClockBar.lua), with no
-- settings pane. Not a suite: tools/clockbarcheck.lua (U3) and the end-to-end
-- suite (U4) load it with dofile and call:
--
--   D.Load(here, root, flavour, opts) -> ST, S   the flavour's whole TOC (no
--       Integrations/ unless opts.integrations), the stub's geometry on, OnUpdate
--       only on visible frames (S.VisibleOnUpdate), logged in, the clock locked
--       with no preview, shown (Forever db.clock.shown)
--   D.Renderer(ST) / D.Frame(ST)                the live clock's renderer and frame
--   D.TimeWords(ST)                             what the live time text reads
--   D.UseLook(ST, look)                         db.clockLook = a copy, one CLOCK_LOOK
--   D.AuthorLook(root)                          the author's 2026-11-08 store, as v3
--   D.E5(ST, S) -> trace, info                  a fight end to end (spec 4.2 E5)
--   D.E6(ST, S, disturbances) -> results        the moving line (E6)
--   D.Disturbances(ST, S)                       E6's list (name, fn) for this flavour
--
-- Every time is the stub's (S.now); nothing here reads a client value the
-- clock would not.
local D = {}

function D.Load(here, root, flavour, opts)
    opts = opts or {}
    dofile(here .. "/wowstub.lua")
    local S = _G.STUB
    S.root = root
    S.flavour = flavour
    local ST = {}
    local toc = "SpellTuner_TBC.toc"
    if flavour == "forever" then
        S.UseProfile("forever")
        if opts.atlases ~= false then S.UseAtlases() end
        toc = "SpellTuner_Mainline.toc"
    end
    S.Geometry(true)
    S.VisibleOnUpdate(true)
    if opts.before then opts.before(S) end
    local files = {}
    for _, rel in ipairs(S.TocFiles(toc)) do
        if opts.integrations or rel:sub(1, 13) ~= "Integrations/" then files[#files + 1] = rel end
    end
    S.loadedFiles = files
    S.Load(files, "SpellTuner", ST)
    S.Fire("ADDON_LOADED", "SpellTuner")
    S.Fire("PLAYER_LOGIN")
    S.Fire("PLAYER_ENTERING_WORLD")
    if ST.db then
        ST.db.locked = true
        ST.db.clock = ST.db.clock or {}
        ST.db.clock.shown = true
        ST.db.clock.locked = true
    end
    local W = ST.ClockWidget
    if W and W.Preview then pcall(W.Preview, W, 0) end
    S.Tick(0.5)
    return ST, S
end

function D.Renderer(ST)
    local W = ST.ClockWidget or {}
    return W.renderer or (ST.Clock and ST.Clock.renderer)
end

function D.Frame(ST)
    local W = ST.ClockWidget or {}
    return W.frame
end

function D.TimeWords(ST)
    local r = D.Renderer(ST)
    if not r then return nil end
    local t = r:Drawn().text.time
    return t and t.words
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end
D.Copy = Copy

function D.UseLook(ST, look)
    ST.db.clockLook = Copy(look)
    ST:Fire("CLOCK_LOOK")
end

function D.AuthorLook(root, ST)
    local raw = dofile(root .. "/tools/data/clock-v2-author.lua")
    return (ST.ClockStore.Migrate(raw))
end

--------------------------------------------------------------------------------
-- E5: a fight end to end, driven by the model (Forever) or the plain pool
-- (TBC). Every 0.5 s the live time text is recorded with the model's state.
--------------------------------------------------------------------------------
local function Mode(ST, S)
    if S.flavour == "forever" then
        local st = ST.Pool:Project(S.now)
        return st and st.mode
    end
    local st = ST.GetManaState and ST:GetManaState()
    return st and st.mode
end

local function Record(ST, S, trace, phase, extra)
    local e = { t = S.now, words = D.TimeWords(ST), phase = phase, mode = Mode(ST, S) }
    for k, v in pairs(extra or {}) do e[k] = v end
    trace[#trace + 1] = e
end

local function E5Forever(ST, S)
    local trace = {}
    local Pool = ST.Pool
    local model = Pool.model
    local max = model.max
    -- the pull
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    model:SetRegen(60, 30) -- base, casting: regen outruns the spend after the casts
    model:Anchor(S.now, max, "e5")
    model:Spend(math.floor(max * 0.3), S.now)
    for _ = 1, 3 do
        S.Tick(0.5)
        Record(ST, S, trace, "casts", { mana = model.mana, max = model.max })
        S.Tick(0.5)
        model:Spend(20, S.now)
        Record(ST, S, trace, "casts", { mana = model.mana, max = model.max })
    end
    -- regen outruns the spend until the model is at max, then 20 s more
    local guard, atMax = 0, nil
    while guard < 400 do
        guard = guard + 1
        S.Tick(0.5)
        Record(ST, S, trace, "regen", { mana = model.mana, max = model.max })
        if model.mana >= model.max then
            atMax = atMax or S.now
            if S.now - atMax >= 20 then break end
        end
    end
    -- out of combat, 20 s
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    for _ = 1, 40 do
        S.Tick(0.5)
        Record(ST, S, trace, "ooc", { mana = model.mana, max = model.max })
    end
    return trace, { atMax = atMax }
end

local function E5TBC(ST, S)
    local trace = {}
    local max = S.manaMax
    S.Fire("PLAYER_REGEN_DISABLED")
    S.mana = math.floor(max * 0.7)
    ST.Regen.fsrEnd = S.now + 5
    local atMax
    for _ = 1, 200 do
        S.Tick(0.5)
        if S.now > ST.Regen.fsrEnd then S.mana = math.min(max, S.mana + 40) end
        Record(ST, S, trace, "regen", { mana = S.mana, max = max })
        if S.mana >= max then
            atMax = atMax or S.now
            if S.now - atMax >= 20 then break end
        end
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    for _ = 1, 40 do
        S.Tick(0.5)
        Record(ST, S, trace, "ooc", { mana = S.mana, max = max })
    end
    return trace, { atMax = atMax }
end

function D.E5(ST, S)
    if S.flavour == "forever" then return E5Forever(ST, S) end
    return E5TBC(ST, S)
end

-- D.E5Verdict(trace) -> ok, why: E5's four promises over a trace.
function D.E5Verdict(trace)
    local stepAt, lastOOM
    for i, e in ipairs(trace) do
        local w = e.words
        if w == "0s" or w == "0:00" then return false, string.format("t=%.1f reads %s", e.t, w) end
        if type(w) == "string" and w:find("^FULL ") and not w:find("^FULL %S") then
            return false, string.format("t=%.1f reads %q", e.t, w)
        end
        local prev = trace[i - 1]
        if prev and prev.mana and prev.max and prev.mana >= prev.max and e.mana >= e.max and w ~= "FULL" then
            return false, string.format("t=%.1f at max for a tick and reads %s", e.t, tostring(w))
        end
        -- a refill time always starts with FULL: a bare number is only ever
        -- an OOM time
        if type(w) == "string" and w:match("^%d") and e.mode ~= "oom" then
            return false, string.format("t=%.1f a bare time %q in mode %s", e.t, w, tostring(e.mode))
        end
        if (e.mode == "full" or e.mode == "ooc") and type(w) == "string" and not w:find("^FULL") then
            return false, string.format("t=%.1f filling (%s) reads %q", e.t, e.mode, w)
        end
        -- an OOM countdown moves at most once a second, one step
        if type(w) == "string" and w:match("^%d") then
            if lastOOM and lastOOM ~= w then
                if stepAt and e.t - stepAt < 1 - 1e-6 then
                    return false, string.format("t=%.1f moved twice within a second", e.t)
                end
                stepAt = e.t
            end
            lastOOM = w
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- E6: the moving line, mid-rule, across every disturbance
--------------------------------------------------------------------------------
local function StartRule(ST, S)
    if S.flavour == "forever" then
        local m = ST.Pool.model
        m:Spend(10, S.now)
        -- a cast moves the game's pool, and the game says so: without the
        -- event the quiet-pool rule (T145a) would anchor the model full and
        -- the host's own rule could take the clock down out of combat
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    else
        ST.Regen.fsrEnd = S.now + 5
    end
end
D.StartRule = StartRule

-- Eight 0.03 s frames: did the line move right on each, shown?
function D.Frames(ST, S, n)
    local r = D.Renderer(ST)
    local xs, moved = {}, true
    for i = 1, n or 8 do
        S.Tick(0.03)
        xs[i] = r.lineShown and r.lineX or false
        if not xs[i] or (i > 1 and not (xs[i - 1] and xs[i] > xs[i - 1])) then moved = false end
    end
    return moved, xs
end

function D.Disturbances(ST, S)
    local Store = ST.ClockStore
    local W = ST.ClockWidget
    local list = {}
    local function add(name, fn) list[#list + 1] = { name = name, fn = fn } end
    for _, kv in ipairs({ { "width", 300 }, { "height", 12 }, { "shape", "pill" }, { "shape", "rect" },
        { "frame", "border" }, { "frame", "none" }, { "frame", "game" }, { "texture", "flat" },
        { "texture", "eui:pixels-dark" }, { "font", "st" }, { "fill", "class" }, { "fill", "112233" },
        { "back", "222222" }, { "backAlpha", 0.5 } }) do
        add("CLOCK_LOOK " .. kv[1] .. " = " .. tostring(kv[2]), function() Store.Set(kv[1], kv[2]) end)
    end
    add("texts.mana.size = 20", function() Store.SetText("mana", "size", 20) end)
    add("a UNIT_POWER_FREQUENT burst (20)", function()
        for _ = 1, 20 do S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") end
    end)
    add("the preview starts", function() W:Preview(60) end)
    add("the preview ends", function() W:Preview(0) end)
    add("PLAYER_REGEN_DISABLED", function() S.Fire("PLAYER_REGEN_DISABLED") end)
    add("PLAYER_REGEN_ENABLED", function() S.Fire("PLAYER_REGEN_ENABLED") end)
    add("PLAYER_REGEN_DISABLED again", function() S.Fire("PLAYER_REGEN_DISABLED") end)
    return list
end

-- D.E6(ST, S) -> { { name, moved }, ... }, sameScript, hiddenAfter, hostHidden
function D.E6(ST, S)
    local r = D.Renderer(ST)
    local frame = D.Frame(ST)
    local script = r.driver:GetScript("OnUpdate")
    local results = {}
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    -- half a pool, so the clock stays up out of combat too (the 90 / 95 rule)
    if S.flavour == "forever" then
        local m = ST.Pool.model
        m:Anchor(S.now, m.max * 0.5, "e6")
        S.Fire("UNIT_POWER_FREQUENT", "player", "MANA") -- the pool moved: not quiet
    else
        S.mana = math.floor(S.manaMax * 0.5)
    end
    -- the host's own rule shows the frame on its tick (never the renderer)
    S.Tick(0.5)
    -- each disturbance in its own rule, two frames in, then eight frames
    for _, d in ipairs(D.Disturbances(ST, S)) do
        StartRule(ST, S)
        S.Tick(0.03)
        d.fn()
        local moved, xs = D.Frames(ST, S, 8)
        results[#results + 1] = { name = d.name, moved = moved, xs = xs }
        if r.driver:GetScript("OnUpdate") ~= script then script = false end
    end
    -- the host hidden: nothing runs; shown again: the line moves on
    StartRule(ST, S)
    S.Tick(0.03)
    local x0 = r.lineX
    frame:Hide()
    S.Tick(0.03)
    local still = r.lineX == x0
    frame:Show()
    local movedAfter = D.Frames(ST, S, 8)
    results[#results + 1] = { name = "the host hidden then shown", moved = still and movedAfter }
    -- the rule's end: hidden within one frame
    local guard = 0
    while r.lineShown and guard < 400 do S.Tick(0.03); guard = guard + 1 end
    local endAt = S.flavour == "forever" and (ST.Pool.model.lastSpend + 5) or ST.Regen.fsrEnd
    local hiddenInTime = not r.lineShown and S.now - endAt <= 0.03 + 1e-6
    local same = script ~= false and r.driver:GetScript("OnUpdate") == script and script == r.step
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    return results, same, hiddenInTime
end

return D
