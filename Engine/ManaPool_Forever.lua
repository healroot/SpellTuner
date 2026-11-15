-- T68 (P24 of docs/PLAN-refactor-ux.md, review A29): the modelled mana pool
-- the Forever line reads -- ONE instance of Engine/ManaModel.lua, the events
-- that move it and the rule that re-anchors it, owned by no widget.
--
-- Until T68 all of this lived in UI/Clock_Forever.lua, so a v3 recording's
-- mana track (Recorder_Forever.lua) and the book's "last regen reading"
-- (Spells/Book.lua) depended on a widget's private fields. Now:
--   * this file keeps the model (ST.Pool.model), prices every own cast from
--     the book (ST.Pool.CostFor), starts and ends its fight, reads max mana and
--     the out-of-combat regen rates each tick and applies the assume-full rule;
--   * UI/Clock_Forever.lua paints what it holds (ST.Pool:Project, the fields
--     the hover shows) and nothing else;
--   * the recorder samples ST.Pool:Sample() every 2 s and at the pull;
--   * Book:DefaultPool reads ST.Pool:LastRegen() when ManaRegen() is secret.
--
-- Reaches the client only through ST.API (current mana is secret always on
-- this client, ManaRegen() in combat -- Facts). Forever only; the TBC line
-- reads UnitPower directly and has no modelled pool.
local _, ST = ...

ST.Pool = ST.Pool or {}
local Pool = ST.Pool

-- The model, nil until MD_READY (a login or /reload makes a fresh one).
Pool.model = nil

-- T145a (docs/SPEC-clock-v3.md 2.4): the quiet pool. The client fires
-- UNIT_POWER_FREQUENT while the player's pool changes and stops when it is
-- full; the event's ARRIVAL is plain (its arguments are never read here), so
-- a silence outside the five-second rule, at a base rate that would have
-- moved the pool, means the real pool is full -- the one correction for what
-- the model cannot see (drinks, Innervate, potions, Clearcasting). The rule is
-- ST.ClockWords.QuietFull (pure); QUIET is VERIFY there. Ships on.
Pool.QUIET_FULL = true
Pool.lastPowerEvent = nil -- GetTime() of the last player power event, nil before the first
Pool.powerEvents = 0      -- counted for /st dump
Pool.quietAnchors = 0     -- anchors made by the quiet-pool rule, for /st dump

-- T146: mana gains the model can see. UNIT_COMBAT's amounts read plain on
-- this client (docs/FOREVER-PLAN.md, the probe: WOUND and HEAL); an ENERGIZE
-- on the player with a plain amount is added to the model (ManaModel:Gain).
-- Whether drinks and potions arrive as ENERGIZE here is VERIFY
-- (docs/TESTING.md section 66): counted for /st dump. While the player's power
-- is plainly not mana (a druid's bear or cat form) an ENERGIZE is rage or
-- energy: counted as seen, never added.
Pool.energizeEvents = 0   -- ENERGIZE events on the player with a plain amount, added
Pool.energizeMana = 0     -- the mana those added (the amounts as read)
Pool.energizeSecret = 0   -- ENERGIZE events whose amount was secret: ignored
Pool.energizeOther = 0    -- ENERGIZE events while the power was not mana: ignored

--------------------------------------------------------------------------------
-- Cost lookup: ST.Book's own entry.cost.amount (a family's known rank, or a
-- standalone ReadSpell for anything else the book does not list -- both
-- already reach the client only through ST.API). A percentage-of-base-mana
-- cost, or nothing readable at all, is never priced -- the caller counts it
-- as unpriced instead of guessing an amount. A cost in Rage / Energy / Focus
-- is a known free cast for mana (review R13: Book's costState "free").
-- The caller has already checked the id is a plain number (IsSecret first):
-- a secret id never reaches the book as a key (T45).
--------------------------------------------------------------------------------
-- Perf P1 (docs/review/perf-0.18.1.md): one id's cost, read now, never a
-- book scan from this event handler.
function Pool.CostFor(id)
    if not ST.Book then return nil end
    local cost, state
    if ST.Book.CostOf then
        local ok
        ok, cost, state = pcall(ST.Book.CostOf, ST.Book, id)
        if not ok then cost, state = nil, nil end
    else
        local book = ST.Book:Get()
        local entry = book and book.spells[id]
        if entry then cost, state = entry.cost, entry.costState end
    end
    if state == "free" then return 0 end
    if type(cost) == "table" and type(cost.amount) == "number" then return cost.amount end
    return nil
end

--------------------------------------------------------------------------------
-- Readers. Every one answers plain numbers or nil, never a client value.
--------------------------------------------------------------------------------

-- The recorder's sample: the modelled mana, the two regen rates last read out
-- of combat, and the max. Four returns; nothing at all before MD_READY.
-- (Callers that want only the mana wrap the call in parentheses -- the
-- multi-return trap, CLAUDE.md.)
function Pool:Sample()
    local m = self.model
    if not m then return nil end
    return m.mana, m.base, m.casting, m.max
end

-- The pool Book:CastsFor counts against (the Spellbook pane's "casts to OOM"
-- and the tooltip's "from here"): max, the modelled mana, the casting-rate
-- regen. An empty table before MD_READY, as ST.Clock:Pool() answered.
function Pool:Pool()
    local m = self.model
    if not m then return {} end
    return { max = m.max, mana = m.mana, regenCasting = m.casting }
end

-- The projection at `now` (Engine/ManaModel.lua Project), nil before MD_READY.
function Pool:Project(now)
    local m = self.model
    if not m then return nil end
    return m:Project(now)
end

-- T146: the measured periodic gain (ManaModel:GainRate), mana per second;
-- 0 before MD_READY.
function Pool:GainRate(now)
    local m = self.model
    if not m then return 0 end
    return m:GainRate(now)
end

-- Pool:QuietFull(now) -> true when the game's pool has gone quiet (full), by
-- ClockWords.QuietFull on this pool's own fields; false before MD_READY,
-- with the flag off, or without the words file.
function Pool:QuietFull(now)
    local m = self.model
    local CW = ST.ClockWords
    if not m or not Pool.QUIET_FULL or not (CW and CW.QuietFull) then return false end
    -- T145 review N5: a dead or ghost player's pool is quiet too, and not
    -- full; the adapter answers a plain boolean or nil (anything else: alive)
    if ST.API.UnitIsDeadOrGhost("player") == true then return false end
    return CW.QuietFull(now, self.lastPowerEvent, m.lastSpend, m.base)
end

-- The dump's line: how often the event came and how often the rule anchored.
-- Added at the first power event (as the clock's own line waits for a look),
-- so a session that never saw one dumps what it did before T145a.
-- T146: and the model beside them, so the author can hold it against the
-- game's bar -- mana / max, the two regen rates (mana per second, base then
-- casting), the last anchor's reason and age, the ENERGIZE counts. `now` is
-- the caller's time, GetTime() when none.
local function Num(x, fmt)
    if type(x) == "number" and x == x then return string.format(fmt, x) end
    return "--"
end
function Pool.DumpLine(now)
    local line = string.format("pool: power events %d, quiet-full anchors %d", Pool.powerEvents, Pool.quietAnchors)
    local m = Pool.model
    if m then
        if type(now) ~= "number" then now = GetTime() end
        local why = m.anchor and m.anchor.why
        local at = m.anchor and m.anchor.at
        local age = "--"
        if type(at) == "number" and type(now) == "number" then age = Num(now - at, "%.0f") .. "s ago" end
        line = line .. string.format(", model %s/%s, regen per s base %s casting %s, anchor %s %s",
            Num(m.mana, "%.0f"), Num(m.max, "%.0f"), Num(m.base, "%.2f"), Num(m.casting, "%.2f"),
            type(why) == "string" and ("'" .. why .. "'") or "--", age)
    end
    local rate = 0
    if m and type(now) == "number" then rate = m:GainRate(now) end
    return line .. string.format(", energize %d (+%d mana, %d secret, %d not mana), gain rate %.2f per s",
        Pool.energizeEvents, Pool.energizeMana, Pool.energizeSecret, Pool.energizeOther, rate)
end
local dumpAdded = false
local function AddDump()
    if dumpAdded then return end
    dumpAdded = true
    ST:AddDumpLine("pool", Pool.DumpLine)
end

-- The regen rates last read plain (out of combat): base, casting. ManaRegen()
-- goes secret in combat, so this is what a reader falls back on for the whole
-- fight (Book:DefaultPool). nil before the first plain reading.
function Pool:LastRegen()
    local m = self.model
    if not m then return nil end
    return m.base, m.casting
end

--------------------------------------------------------------------------------
-- Wiring. Registered in the position UI/Clock_Forever.lua's own handlers had
-- (this file loads just before it), so every other handler of the same event
-- sees the pool exactly as it saw the clock's model before T68.
--------------------------------------------------------------------------------
local function ReadRegen(model)
    local base, casting = ST.API.ManaRegen()
    if type(base) == "number" and type(casting) == "number" then
        model:SetRegen(base, casting)
    end
end

ST:RegisterCallback("MD_READY", function()
    local model = ST.ManaModel.New()
    Pool.model = model

    local max = ST.API.UnitPowerMax("player", 0)
    if type(max) == "number" then model:SetMax(max) end

    ReadRegen(model)

    model:Anchor(GetTime(), model.max, "assumed full at login")

    -- Review R36/R37: a login or /reload in the middle of a fight gets no
    -- PLAYER_REGEN_DISABLED (it already fired). Core.lua's own MD_READY
    -- handler, registered before this one, has already seeded ST.inCombat
    -- through the adapter (an unreadable answer -- absent, raised, secret --
    -- leaves it out of combat, as before), so the fight starts here (T58).
    if ST.inCombat then model:StartFight(GetTime()) end
end)

ST:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    local model = Pool.model
    if not model then return end
    -- Facts/T9 Review: IsSecret before the comparison, every time -- type()
    -- of a secret does not raise and may answer the underlying type.
    if ST.API.IsSecret(unit) or unit ~= "player" then return end

    local now = GetTime()
    if not ST.API.IsSecret(spellID) and type(spellID) == "number" then
        local cost = Pool.CostFor(spellID)
        if cost ~= nil then
            if cost > 0 then model:Spend(cost, now) end -- a free cast spends nothing and restarts no five-second rule
            return
        end
    end
    model:Unpriced(now)
end)

-- T145a: the player's power events, only their arrival (time and count).
-- Registered before UI/Clock_Forever.lua's handler of the same event.
ST:OnUnit("UNIT_POWER_FREQUENT", "player", function()
    Pool.lastPowerEvent = GetTime()
    Pool.powerEvents = Pool.powerEvents + 1
    AddDump()
end)

-- T146: an ENERGIZE on the player, its amount plain, into the model. Every
-- argument tested with IsSecret before any comparison (the
-- UNIT_SPELLCAST_SUCCEEDED handler's rule).
ST:OnUnit("UNIT_COMBAT", "player", function(unit, action, descriptor, amount)
    local model = Pool.model
    if not model then return end
    if ST.API.IsSecret(unit) or unit ~= "player" then return end
    if ST.API.IsSecret(action) or action ~= "ENERGIZE" then return end
    AddDump()
    if ST.API.IsSecret(amount) or type(amount) ~= "number" or amount ~= amount then
        Pool.energizeSecret = Pool.energizeSecret + 1
        return
    end
    local power = ST.API.UnitPowerType("player")
    if type(power) == "number" and power ~= 0 then
        Pool.energizeOther = Pool.energizeOther + 1
        return
    end
    model:Gain(amount, GetTime())
    Pool.energizeEvents = Pool.energizeEvents + 1
    if amount > 0 then Pool.energizeMana = Pool.energizeMana + amount end
end)

-- T145 review N5: a death forgets the last power event, and so does coming
-- back (a res, a release, the spirit healer): the quiet rule waits for a
-- fresh event, so a pool that has not moved since cannot be read as full.
local function ForgetPowerEvent() Pool.lastPowerEvent = nil end
ST:On("PLAYER_DEAD", ForgetPowerEvent)
ST:On("PLAYER_ALIVE", ForgetPowerEvent)
ST:On("PLAYER_UNGHOST", ForgetPowerEvent)

ST:On("PLAYER_REGEN_DISABLED", function()
    -- Review B19: an opener that succeeded up to 0.5 s before this flag is
    -- folded into the fight by the model itself (ManaModel:StartFight).
    if Pool.model then Pool.model:StartFight(GetTime()) end
end)

ST:On("PLAYER_REGEN_ENABLED", function()
    if Pool.model then Pool.model:EndFight(GetTime()) end
end)

ST:OnTick(function()
    local model = Pool.model
    if not model then return end
    local now = GetTime()

    local max = ST.API.UnitPowerMax("player", 0)
    if type(max) == "number" then model:SetMax(max) end

    if not ST.inCombat then ReadRegen(model) end

    model:Advance(now)

    -- T145a: the quiet pool -- in and out of combat, the game's pool has
    -- stopped moving, so it is full whatever the model counted.
    if model.max and model.max > 0 and model.mana < model.max and Pool:QuietFull(now) then
        model:Anchor(now, model.max, "the game's pool stopped moving")
        Pool.quietAnchors = Pool.quietAnchors + 1
    end

    -- The assume-full rule. Out of combat, once regen alone (at the base rate,
    -- the faster of the two -- Facts) would have had time to refill the whole
    -- pool from empty, the real pool is assumed full even if the model's own
    -- integral (which spent part of that time at the slower casting rate,
    -- Engine/ManaModel.lua Advance) has not quite caught up -- the drift the
    -- plan accepts (FOREVER-PLAN.md sec2.5): drinks, potions, other heals are
    -- invisible to this model, so "assume full after long enough" is the only
    -- correction it gets.
    if not ST.inCombat and model.max and model.max > 0 and model.base and model.base > 0
       and (now - model.lastSpend) >= (model.max / model.base) and model.mana < model.max then
        model:Anchor(now, model.max, "regen had time to fill it")
    end
end)
