-- Practice (v0.15.0, docs/SPEC-v0.15.md): heal a fight YOU play, in real time,
-- and get a recording out of it that the Review tab, the replay window and the
-- coach take exactly as they take a dungeon pull.
--
-- Three parts, no frames:
--   * a SETUP -- who is in the group, how much health they have, and what
--     damage each of them takes (a steady rate, spikes, randomness) plus
--     group-wide AoE -- turned into a damage timeline by a seeded generator;
--   * a SESSION -- Engine/SimModel.lua's own loop, run inside a coroutine and
--     paced to the wall clock (`opts.pace`), with a plan whose Decide reads the
--     player's queued input instead of rules. One engine: what you play is
--     what the replay reproduces, to the float;
--   * the RECORDING -- the session written down in Engine/FightRecorder.lua's
--     stream format (v = 2), kept in cdb.practice and addressed as "p1".
--
-- What the practice fight is NOT: it is not a model of any real encounter.
-- Every default in PR.ROLES is a placeholder with its provenance, and the
-- setup panel says so. It is a way to rehearse decisions, and a recording the
-- coach can answer.
local _, MD = ...

local PR = {}
MD.Practice = PR

PR.MAX_KEPT = 8
PR.QUEUE = 0.4          -- the client's spell queue window: a press this close to
                        -- the end of a cast or the GCD goes off when it ends
PR.POLL = 0.05          -- how often the engine asks for input while idle
PR.MAX_DUR = 600

--------------------------------------------------------------------------------
-- Defaults. PLACEHOLDERS, like everything in Data/SimPresets.lua: one healer's
-- impression of a TBC group, written as fractions of max health so they mean
-- the same thing at level 64 and 70.
--   dps         steady damage per second, as a fraction of max health
--   swing       seconds between the hits that deliver it (0 = a smooth 1s tick)
--   spike       one big hit, as a fraction of max health
--   spikeEvery  average seconds between spikes (0 = none)
--   jitter      0..1, how far hit sizes and intervals wander from the average
--------------------------------------------------------------------------------
PR.ROLES = {
    TANK   = { label = "Tank",   role = "TANK",    dps = 0.035, swing = 1.8, spike = 0.25, spikeEvery = 20, jitter = 0.3 },
    HEALER = { label = "Healer", role = "HEALER",  dps = 0,     swing = 0,   spike = 0.15, spikeEvery = 45, jitter = 0.5 },
    MELEE  = { label = "Melee",  role = "DAMAGER", dps = 0.003, swing = 3,   spike = 0.20, spikeEvery = 35, jitter = 0.5 },
    RANGED = { label = "Ranged", role = "DAMAGER", dps = 0,     swing = 0,   spike = 0.20, spikeEvery = 40, jitter = 0.5 },
}
PR.ROLE_ORDER = { "TANK", "HEALER", "MELEE", "RANGED" }

-- who is in the group, by size; the first HEALER slot is you
PR.GROUPS = {
    { id = "1",  label = "Solo",    slots = { "HEALER" } },
    { id = "2",  label = "Duo",     slots = { "TANK", "HEALER" } },
    { id = "5",  label = "Party",   slots = { "TANK", "HEALER", "MELEE", "RANGED", "RANGED" } },
    { id = "10", label = "Raid 10", slots = { "TANK", "TANK", "HEALER", "HEALER", "HEALER",
                                              "MELEE", "MELEE", "RANGED", "RANGED", "RANGED" } },
    { id = "25", label = "Raid 25", slots = { "TANK", "TANK", "TANK", "HEALER", "HEALER", "HEALER",
                                              "HEALER", "HEALER", "HEALER", "MELEE", "MELEE", "MELEE",
                                              "MELEE", "MELEE", "MELEE", "MELEE", "RANGED", "RANGED",
                                              "RANGED", "RANGED", "RANGED", "RANGED", "RANGED",
                                              "RANGED", "RANGED" } },
}

-- a class per slot kind, for the frame colour only
local CLASSES = {
    TANK = { "WARRIOR", "PALADIN", "DRUID" },
    HEALER = { "PRIEST", "SHAMAN", "PALADIN", "DRUID" },
    MELEE = { "ROGUE", "WARRIOR", "SHAMAN", "PALADIN" },
    RANGED = { "MAGE", "WARLOCK", "HUNTER", "PRIEST" },
}

-- Same shape as Data/SimPresets.lua's placeholder: a level 70 tank around 10k,
-- cloth around 6k, scaled linearly below 70.
local function DefaultHP(level, kind)
    local base = (kind == "TANK") and 10000 or 6000
    return math.floor(base * math.min(1, (level or 70) / 70))
end

function PR.DefaultSetup(groupID, level)
    level = level or (MD.player and MD.player.level) or 70
    local group
    for _, g in ipairs(PR.GROUPS) do if g.id == groupID then group = g end end
    group = group or PR.GROUPS[3]
    local setup = { group = group.id, dur = 120, startHp = 1.0, otherHealing = 0,
                    aoe = { size = 0.10, every = 25, jitter = 0.3 }, targets = {} }
    local count, you = {}, false
    for i, kind in ipairs(group.slots) do
        count[kind] = (count[kind] or 0) + 1
        local r = PR.ROLES[kind]
        local isYou = (kind == "HEALER" and not you)
        if isYou then you = true end
        local classes = CLASSES[kind]
        setup.targets[i] = {
            kind = kind, role = r.role,
            name = isYou and ((UnitName and UnitName("player")) or "You")
                or (r.label .. (count[kind] > 1 and (" " .. count[kind]) or "")),
            class = isYou and "DRUID" or classes[(count[kind] - 1) % #classes + 1],
            you = isYou or nil,
            maxHP = DefaultHP(level, kind),
            dps = r.dps, swing = r.swing, spike = r.spike, spikeEvery = r.spikeEvery, jitter = r.jitter,
        }
    end
    return setup
end

-- a role's defaults onto every target of that kind (the setup panel's "apply
-- to all tanks"), leaving name, class and health alone
function PR.ApplyRole(setup, kind, values)
    for _, tg in ipairs(setup.targets) do
        if tg.kind == kind then
            for _, k in ipairs({ "dps", "swing", "spike", "spikeEvery", "jitter" }) do
                if values[k] ~= nil then tg[k] = values[k] end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Bindings: what a press casts. A press is the key or mouse button with its
-- modifiers in the client's own spelling ("ALT-BUTTON5", "SHIFT-1"), made while
-- hovering a frame -- the mouseover healing the author plays with. A binding
-- names a family and a rank (nil = the highest you know), so it follows a new
-- rank the day it is trained.
--
-- The defaults are the author's own Cell click-casting, read from their
-- SavedVariables on 2026-09-17: Button5 "Main overtime" (Lifebloom on a
-- friendly mouseover), Alt-Button5 "rej/moofire" (Rejuvenation), Shift-Button5
-- "efficient Rej" (Rejuvenation Rank 5). Left and right click target and open
-- the menu in Cell, so they are free here and carry the two heals those macros
-- do not: Regrowth and Swiftmend. Shift-left is Healing Touch.
--------------------------------------------------------------------------------
PR.DEFAULT_BINDS = {
    { key = "BUTTON5",       family = "Lifebloom" },
    { key = "ALT-BUTTON5",   family = "Rejuvenation" },
    { key = "SHIFT-BUTTON5", family = "Rejuvenation", rank = 5 },
    { key = "BUTTON1",       family = "Regrowth" },
    { key = "BUTTON2",       family = "Swiftmend" },
    { key = "SHIFT-BUTTON1", family = "HealingTouch" },
}

-- the client's names for mouse buttons, as a binding spells them
PR.MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
             Button4 = "BUTTON4", Button5 = "BUTTON5" }

function PR.Binds()
    local db = MD.db
    if db and type(db.practiceBinds) == "table" then return db.practiceBinds end
    local out = {}
    for i, b in ipairs(PR.DEFAULT_BINDS) do out[i] = { key = b.key, family = b.family, rank = b.rank } end
    if db then db.practiceBinds = out end
    return out
end

-- modifiers in the order the client writes them
function PR.Mods(alt, ctrl, shift)
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "")
end

-- A binding's spell id: that rank if you know it, else your highest.
function PR.SpellFor(bind)
    local SD = MD.SpellData
    if not bind or not bind.family then return nil end
    if bind.rank then
        for _, id in ipairs(SD.known[bind.family] or {}) do
            if SD.spells[id].rank == bind.rank then return id end
        end
    end
    return SD.maxRank[bind.family]
end

function PR.BindFor(key)
    for _, b in ipairs(PR.Binds()) do
        if b.key == key then return b, PR.SpellFor(b) end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The damage timeline. Deterministic in the seed: the same setup and seed is
-- the same fight, which is what lets a session be played again.
--------------------------------------------------------------------------------
local function Rng(seed)
    local state = ((seed or 1) * 2654435761) % 2147483647
    if state == 0 then state = 1 end
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- a value that wanders `jitter` either side of `mean`, never below zero
local function Wander(r, mean, jitter)
    local v = mean * (1 + (jitter or 0) * (2 * r() - 1))
    return v > 0 and v or 0
end

function PR.BuildDamage(setup, seed)
    local SM = MD.SimModel
    local K = SM.K
    local r = Rng(seed)
    local dur = setup.dur or 120
    local raw = {}
    local function push(t, ti, amt, kind, x)
        if t > 0 and t <= dur and amt >= 1 then
            raw[#raw + 1] = { t = t, tgt = ti, amt = math.floor(amt + 0.5), kind = kind or K.DMG, x = x or 0 }
        end
    end
    local OPEN = 1.5    -- nobody is hit the instant the pull starts
    for ti, tg in ipairs(setup.targets) do
        local maxHP = tg.maxHP or 1
        local jit = tg.jitter or 0
        if (tg.dps or 0) > 0 then
            local every = (tg.swing or 0) > 0 and tg.swing or 1
            local t = OPEN + every * r()
            while t <= dur do
                push(t, ti, Wander(r, tg.dps * maxHP * every, jit))
                t = t + Wander(r, every, jit * 0.2)
                if every <= 0 then break end
            end
        end
        if (tg.spike or 0) > 0 and (tg.spikeEvery or 0) > 0 then
            local t = OPEN + Wander(r, tg.spikeEvery, jit)
            while t <= dur do
                push(t, ti, Wander(r, tg.spike * maxHP, jit))
                t = t + math.max(2, Wander(r, tg.spikeEvery, jit))
            end
        end
    end
    local aoe = setup.aoe
    if aoe and (aoe.size or 0) > 0 and (aoe.every or 0) > 0 then
        local t = OPEN + Wander(r, aoe.every, aoe.jitter)
        while t <= dur do
            for ti, tg in ipairs(setup.targets) do
                push(t, ti, Wander(r, aoe.size * (tg.maxHP or 1), (aoe.jitter or 0) * 0.5))
            end
            t = t + math.max(3, Wander(r, aoe.every, aoe.jitter))
        end
    end
    -- other healers: a share of every hit comes back as somebody else's heal,
    -- a second or two later. Written as foreign heals, which the engine lands
    -- (and overheals) like any other.
    local share = setup.otherHealing or 0
    if share > 0 then
        local n = #raw
        for i = 1, n do
            local e = raw[i]
            if e.kind == K.DMG then
                push(e.t + 1 + 2 * r(), e.tgt, e.amt * share, K.FHEAL, 0)
            end
        end
    end
    table.sort(raw, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.tgt < b.tgt
    end)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(raw) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e.t, e.kind, e.tgt, e.amt, e.x
    end
    return ev
end

--------------------------------------------------------------------------------
-- A session
--------------------------------------------------------------------------------
local Session = {}
Session.__index = Session

-- The scenario the engine runs. The healer is THIS character: pool, regen and
-- the spell kit are read live, exactly what a recording made now would carry.
local function BuildScenario(setup, seed, kit)
    local RM = MD.Regen
    local dur = math.min(PR.MAX_DUR, math.max(10, setup.dur or 120))
    setup.dur = dur
    local targets = {}
    for i, tg in ipairs(setup.targets) do
        local maxHP = math.max(1, tg.maxHP or 1)
        targets[i] = { name = tg.name, role = tg.role, maxHP = maxHP,
                       hp0 = math.floor(maxHP * (tg.startHp or setup.startHp or 1) + 0.5), tracked = true }
    end
    local sampleT, hpT = {}, {}
    for t = 0, dur, 2 do sampleT[#sampleT + 1] = t end
    for t = 0, dur, 5 do hpT[#hpT + 1] = t end
    local pool = (UnitPowerMax and UnitPowerMax("player", 0)) or 0
    return {
        dur = dur, pool = pool,
        initial = { mana = pool, apiBase = RM and RM.apiBase or 0, apiCasting = RM and RM.apiCasting or 0,
                    form = (MD.InTreeForm and MD:InTreeForm()) and "tree" or "caster",
                    energize = RM and RM:Unreported() or 0 },
        targets = targets, ev = PR.BuildDamage(setup, seed),
        floor = (MD.db and MD.db.simFloor) or 0.30, grace = 6,
        sampleT = sampleT, hpSampleT = hpT, kit = kit, synthetic = true,
    }
end

-- setup: PR.DefaultSetup's shape. opts.seed (default: the clock), opts.onError
-- (msg, spellID, target), opts.kit (tests)
function PR.New(setup, opts)
    opts = opts or {}
    local SM = MD.SimModel
    local seed = opts.seed or ((time and time()) or 1)
    local kit = opts.kit or MD.RankMath:SpellKit({ live = true })
    -- A player waits through the real cast bar, not the Nature's Grace average
    -- the planner uses for throughput. The session's own copy of the kit, so the
    -- shared one is untouched; a recording replays from its cast SUCCESS times,
    -- so the replay does not depend on this.
    do
        local copy = { crit = kit.crit }
        for form, list in pairs(kit) do
            if type(list) == "table" then
                copy[form] = {}
                for id, e in pairs(list) do
                    local c = {}
                    for k, v in pairs(e) do c[k] = v end
                    if c.castBase and (c.type == "direct" or c.type == "hybrid") then c.cast = c.castBase end
                    copy[form][id] = c
                end
            end
        end
        kit = copy
    end
    local s = setmetatable({
        setup = setup, seed = seed, kit = kit, opts = opts,
        clock = 0, speed = 1, paused = false, state = "ready",
        queue = {}, own = {}, errors = 0, startedAt = (time and time()) or 0,
    }, Session)
    s.scenario = BuildScenario(setup, seed, kit)
    s.pool = s.scenario.pool

    local plan = {
        name = "you", noReaction = true, poll = PR.POLL,
        BindCount = function() return 0 end,
        Decide = function(_, S, t, mana, form) return s:Decide(S, t, mana, form) end,
    }
    s.plan = plan
    local runOpts = {
        critMode = "ev",
        trace = { dt = opts.dt or 0.1 },
        pace = function(nt, S, mana, form, busyUntil)
            s.S, s.mana, s.form, s.busyUntil = S, mana, form, busyUntil
            while s.clock < nt do
                if s.stopping then return false end
                coroutine.yield()
            end
            if s.stopping then return false end
            return true
        end,
        onCast = function(_, t, spellID, ti, mana)
            s:Note(t, SM.K.OWNCAST, ti, s.lastCost or -1, spellID)
        end,
        onHeal = function(t, ti, amount, _, family, spellID, periodic, crit)
            if family == "foreign" or not spellID then return end
            s:Note(t, periodic and SM.K.OWNTICK or SM.K.OWNHEAL, ti, amount,
                spellID + (crit and 100000 or 0))
        end,
    }
    s.runOpts = runOpts
    s.co = coroutine.create(function()
        local r = SM:Run(s.scenario, plan, runOpts)
        s.trace = r.trace
        s.deathsAt = {}
        for i = 1, (r.deaths and r.deaths.n or 0) do s.deathsAt[i] = { r.deaths.tgt[i], r.deaths.t[i] } end
        return r
    end)
    return s
end

-- The trace the engine is writing right now, for the window to paint.
function Session:LiveTrace()
    return self.trace or (self.runOpts.trace and self.runOpts.trace.built)
end

function Session:Note(t, kind, tgt, amt, x)
    local o = self.own
    o[#o + 1] = { t = t, kind = kind, tgt = tgt or -1, amt = amt or 0, x = x or 0, seq = #o + 1 }
end

function Session:Error(msg, spellID, ti)
    self.errors = self.errors + 1
    self.lastError, self.lastErrorAt = msg, self.clock
    if self.opts.onError then self.opts.onError(msg, spellID, ti) end
end

-- The player pressed something. Nothing is decided here: the press waits in
-- the queue for the engine's next decision, where the game's own rules apply.
function Session:Cast(spellID, ti)
    if self.state ~= "running" then return false end
    -- the client answers a press made while a cast or the GCD still has more
    -- than the queue window to run AT ONCE, not when it ends
    if (self.busyUntil or 0) - self.clock > PR.QUEUE then
        self:Error("Another action is in progress", spellID, ti)
        return false
    end
    local q = self.queue
    -- one press at a time, like the client: a newer press replaces a queued one
    for i = #q, 1, -1 do q[i] = nil end
    q[1] = { spellID = spellID, target = ti, at = self.clock }
    return true
end

-- The plan's Decide: the queued press, if the game would allow it now.
function Session:Decide(S, t, mana, form)
    local q = self.queue
    local inp = q[1]
    if not inp then return nil end
    if inp.at > t + 1e-9 then return nil end          -- pressed after this instant: next poll
    q[1] = nil
    if t - inp.at > PR.QUEUE + PR.POLL then
        self:Error("Another action is in progress", inp.spellID, inp.target)
        return nil
    end
    local SM = MD.SimModel
    local e = self.kit[form] and self.kit[form][inp.spellID]
    local ti = inp.target
    if not e then self:Error("You can't cast that here", inp.spellID, ti); return nil end
    if e.dataMissing then self:Error("Not modelled yet", inp.spellID, ti); return nil end
    if not ti or ti < 1 or ti > (S.nT or 0) then self:Error("No target", inp.spellID, ti); return nil end
    if S.dead[ti] then self:Error("Target is dead", inp.spellID, ti); return nil end
    if (e.cost or 0) > mana then self:Error("Not enough mana", inp.spellID, ti); return nil end
    if not SM.Ready(S, inp.spellID, t) then self:Error("Spell is not ready yet", inp.spellID, ti); return nil end
    if e.type == "instant" then
        local row = S.hots[ti]
        local rg = row and row[SM.HOT_INDEX.Regrowth]
        local rj = row and row[SM.HOT_INDEX.Rejuvenation]
        if not ((rg and rg.active) or (rj and rj.active)) then
            self:Error("Nothing to consume", inp.spellID, ti)
            return nil
        end
    end
    self.lastCost = e.cost
    if not (e.type == "hot" or e.type == "lifebloom" or e.type == "instant") then
        self:Note(t, SM.K.CASTSTART, ti, 0, inp.spellID)
    end
    return inp.spellID, ti, 0
end

function Session:Start()
    if self.state ~= "ready" then return end
    self.state = "running"
    self:Resume()
end

function Session:Resume()
    local ok, r = coroutine.resume(self.co)
    if not ok then
        self.state = "failed"
        self.failure = r
        MD:Debug("sim", "practice session failed: %s", tostring(r))
        return
    end
    if coroutine.status(self.co) == "dead" then
        self.result = r
        self:Finish()
    end
end

-- Real time in, engine time out. `elapsed` is wall seconds since the last call.
function Session:Update(elapsed)
    if self.state ~= "running" or self.paused then return end
    if elapsed > 0.25 then elapsed = 0.25 end      -- a hitch is a pause, not a skip
    self.clock = self.clock + elapsed * (self.speed or 1)
    if self.clock > self.scenario.dur then self.clock = self.scenario.dur end
    self:Resume()
end

function Session:SetPaused(on) if self.state == "running" then self.paused = on and true or false end end
function Session:SetSpeed(x) self.speed = math.max(0.25, math.min(1, x or 1)) end

-- End it now; what has happened is kept.
function Session:Stop()
    if self.state ~= "running" then return end
    self.stopping = true
    self:Resume()
end

--------------------------------------------------------------------------------
-- The recording. The stream a dungeon pull would have produced, built from what
-- the engine did: the damage that landed, every cast, cast start and heal as
-- the combat log would have carried it, mana every 2s and health every 5s.
--------------------------------------------------------------------------------
function Session:Finish()
    if self.state == "done" then return self.rec end
    self.state = "done"
    local SM = MD.SimModel
    local K = SM.K
    local sc = self.scenario
    local S = self.S
    local endT = math.min(self.clock, sc.dur)
    if endT <= 0 or not S then return nil end

    local roster, tracked = {}, {}
    for i, tg in ipairs(self.setup.targets) do
        roster[i] = { name = tg.name, class = tg.class, role = tg.role, roleSource = "practice",
                      maxHP = sc.targets[i].maxHP,
                      guid = tg.you and MD.player and MD.player.guid or nil }
        tracked[i] = i
    end

    -- the timeline: what happened TO the group, then what the healer did, in
    -- the engine's own order at equal timestamps (the group's events first)
    local rows = {}
    local sev = sc.ev
    for i = 1, #sev.t do
        if sev.t[i] <= endT then
            rows[#rows + 1] = { t = sev.t[i], kind = sev.kind[i], tgt = sev.tgt[i], amt = sev.amt[i],
                                x = sev.x[i], order = 0, seq = i }
        end
    end
    local deaths = {}
    for i = 1, S.deaths.n do
        local t = S.deaths.t[i]
        if t <= endT then
            rows[#rows + 1] = { t = t, kind = K.DIED, tgt = S.deaths.tgt[i], amt = 0, x = 0, order = 2, seq = i }
            deaths[#deaths + 1] = { S.deaths.tgt[i], t }
        end
    end
    local spent, casts, names = 0, 0, {}
    for _, o in ipairs(self.own) do
        if o.t <= endT then
            rows[#rows + 1] = { t = o.t, kind = o.kind, tgt = o.tgt, amt = o.amt, x = o.x, order = 1, seq = o.seq }
            if o.kind == K.OWNCAST then
                casts = casts + 1
                if o.amt > 0 then spent = spent + o.amt end
                local sd = MD.SpellData.spells[o.x]
                if sd and not names[o.x] then names[o.x] = sd.family .. " r" .. sd.rank end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(rows) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e.t, e.kind, e.tgt, e.amt, e.x
    end

    -- health every 5s from the engine's own samples, plus the moment it ended
    local hp = { t = {}, hp = {}, max = {} }
    for i = 1, #tracked do hp.hp[i], hp.max[i] = {}, {} end
    for k, t in ipairs(sc.hpSampleT) do
        if t <= endT and S.hpCurve[1] and S.hpCurve[1][k] then
            hp.t[#hp.t + 1] = t
            for i = 1, #tracked do
                local n = #hp.t
                hp.hp[i][n] = S.hpCurve[i][k]
                hp.max[i][n] = sc.targets[i].maxHP
            end
        end
    end
    if hp.t[#hp.t] ~= endT then
        local n = #hp.t + 1
        hp.t[n] = endT
        for i = 1, #tracked do
            hp.hp[i][n] = S.dead[i] and 0 or S.hp[i]
            hp.max[i][n] = sc.targets[i].maxHP
        end
    end

    local mana = { t = {}, v = {}, base = {}, cast = {} }
    for k, t in ipairs(sc.sampleT) do
        if t <= endT and S.manaCurve[k] then
            local n = #mana.t + 1
            mana.t[n], mana.v[n] = t, S.manaCurve[k]
            mana.base[n], mana.cast[n] = sc.initial.apiBase, sc.initial.apiCasting
        end
    end

    local known = {}
    for family, id in pairs(MD.SpellData.maxRank or {}) do known[family] = id end
    local initial = {}
    for k, v in pairs(sc.initial) do initial[k] = v end
    initial.known = known
    initial.auras, initial.buffs = {}, {}

    local foreign, own = 0, 0
    for i = 1, #ev.t do
        if ev.kind[i] == K.FHEAL then foreign = foreign + ev.amt[i]
        elseif ev.kind[i] == K.OWNHEAL or ev.kind[i] == K.OWNTICK then own = own + ev.amt[i] end
    end

    local g
    for _, x in ipairs(PR.GROUPS) do if x.id == self.setup.group then g = x end end
    if casts == 0 then
        -- nothing was played: not a fight worth a slot
        self.rec = nil
        MD:Debug("sim", "practice ended after %.0fs with no casts: not kept", endT)
        if self.opts.onFinish then self.opts.onFinish(nil) end
        return nil
    end
    local rec = {
        v = 2, id = self.startedAt, t0 = 0, dur = endT, pool = sc.pool,
        zone = "Practice: " .. (g and g.label or "custom"), encounter = "Practice",
        roster = roster, tracked = tracked, ev = ev, n = #ev.t,
        hp = hp, mana = mana, initial = initial, precasts = {}, deaths = deaths,
        names = names, ownCasts = casts, spent = spent,
        foreignShare = (own + foreign) > 0 and foreign / (own + foreign) or 0,
        truncated = false, pinned = false,
        -- what makes it practice: the setup and seed that reproduce the fight,
        -- and whether it was played to the end
        practice = { seed = self.seed, setup = PR.CopySetup(self.setup), finished = endT >= sc.dur - 1e-6,
                     errors = self.errors },
    }
    self.rec = rec
    if MD.cdb and not self.opts.noStore then PR.Store(rec) end
    MD:Debug("sim", "practice recorded: %.0fs, %d events, %d casts, %d mana, %d dead",
        endT, rec.n, casts, spent, #deaths)
    if self.opts.onFinish then self.opts.onFinish(rec) end
    return rec
end

function PR.CopySetup(setup)
    local out = {}
    for k, v in pairs(setup) do
        if type(v) ~= "table" then out[k] = v end
    end
    out.aoe = {}
    for k, v in pairs(setup.aoe or {}) do out.aoe[k] = v end
    out.targets = {}
    for i, tg in ipairs(setup.targets or {}) do
        local c = {}
        for k, v in pairs(tg) do c[k] = v end
        out.targets[i] = c
    end
    return out
end

--------------------------------------------------------------------------------
-- Keeping them. The newest PR.MAX_KEPT, apart from the ring of real fights so a
-- practice evening never pushes a dungeon pull out.
--------------------------------------------------------------------------------
function PR.Store(rec)
    MD.cdb.practice = MD.cdb.practice or {}
    local list = MD.cdb.practice
    list[#list + 1] = rec
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    while #list > PR.MAX_KEPT do list[#list] = nil end
end

function PR.List()
    local list = {}
    for _, r in ipairs(MD.cdb and MD.cdb.practice or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return list
end

function PR.Get(n) return PR.List()[n or 1] end
