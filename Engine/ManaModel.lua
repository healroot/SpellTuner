-- T11 (docs/tasks/T11-clock.md, M2): the modelled mana pool -- the plain
-- maximum, minus the cost of every own cast at the moment it succeeds, plus
-- regen under the five-second rule at the rate last read out of combat.
-- Exists because current mana (UnitPower) is secret always on this client
-- (Facts); the model is never the real pool and every consumer must say so.
--
-- PURE: no client call, no MD.API call, no GetTime -- every timestamp is an
-- argument, so this file cannot be the one that reaches the client (CLAUDE.md:
-- "no client call outside Client/"; this is the file that has NONE at all).
local _, MD = ...

MD.ManaModel = MD.ManaModel or {}
local ManaModel = MD.ManaModel
ManaModel.__index = ManaModel

function ManaModel.New()
    return setmetatable({
        max = 0,           -- plain max, from SetMax
        mana = 0,          -- the modelled pool
        base = nil,        -- GetManaRegen's first return, nil until read
        casting = nil,     -- GetManaRegen's second return, nil until read
        lastSpend = -1e9,  -- long enough ago that nothing starts "in the FSR"
        t = nil,           -- the last Advance()'d timestamp
        fight = nil,       -- { start, spent, casts, fsrTime } while in combat
        anchor = { at = nil, why = nil },
        unpriced = 0,      -- unpriced casts since the last StartFight
    }, ManaModel)
end

-- A plain number; the pool scales with it only when it GROWS (a level-up
-- mid-model should not read as "you just lost most of your mana"), capped at
-- the new max either way.
function ManaModel:SetMax(max)
    if type(max) ~= "number" then return end
    if self.max and self.max > 0 and max > self.max then
        self.mana = self.mana * (max / self.max)
    end
    self.max = max
    if self.mana > max then self.mana = max end
end

-- Plain numbers only -- the multi-return trap means a caller must check both
-- before calling this, not that this function trusts one without the other.
function ManaModel:SetRegen(base, casting)
    if type(base) == "number" then self.base = base end
    if type(casting) == "number" then self.casting = casting end
end

-- Integrates regen from the last Advance to t: the casting rate while
-- t < lastSpend + 5, the base rate after, split exactly at the boundary. A
-- rate that is nil contributes nothing for the portion of dt it would have
-- covered -- never guessed as zero regen from the caller's point of view,
-- only from this integral's (Project's own fields say so explicitly, see
-- below). Clamped to [0, max]; accumulates fight.fsrTime while in combat.
function ManaModel:Advance(t)
    local last = self.t
    if last == nil or t <= last then
        self.t = t
        return
    end
    local dt = t - last
    local fsrEnd = self.lastSpend + 5
    local castingPart = 0
    if last < fsrEnd then
        castingPart = math.min(t, fsrEnd) - last
        if castingPart < 0 then castingPart = 0 end
    end
    local basePart = dt - castingPart

    local gain = 0
    if castingPart > 0 and self.casting then gain = gain + castingPart * self.casting end
    if basePart > 0 and self.base then gain = gain + basePart * self.base end

    self.mana = self.mana + gain
    if self.mana < 0 then self.mana = 0 end
    if self.max and self.mana > self.max then self.mana = self.max end

    if self.fight then
        self.fight.fsrTime = self.fight.fsrTime + castingPart
    end
    self.t = t
end

-- A priced cast: advance, subtract, restart the five-second rule, count it.
function ManaModel:Spend(cost, t)
    self:Advance(t)
    if type(cost) == "number" then
        self.mana = self.mana - cost
        if self.mana < 0 then self.mana = 0 end
    end
    self.lastSpend = t
    if self.fight then
        self.fight.spent = self.fight.spent + (type(cost) == "number" and cost or 0)
        self.fight.casts = self.fight.casts + 1
    end
end

-- A cast whose cost is not known: advance and count it, but never subtract
-- and never restart the five-second rule -- the model does not know this
-- cast spent mana at all, so it must not pretend otherwise in either
-- direction (CLAUDE.md: never guess).
function ManaModel:Unpriced(t)
    self:Advance(t)
    self.unpriced = self.unpriced + 1
end

function ManaModel:Anchor(t, mana, why)
    self.mana = mana
    if self.max and self.max > 0 and self.mana > self.max then self.mana = self.max end
    if self.mana < 0 then self.mana = 0 end
    self.anchor.at = t
    self.anchor.why = why
    self.t = t
end

function ManaModel:StartFight(t)
    self:Advance(t)
    self.fight = { start = t, spent = 0, casts = 0, fsrTime = 0 }
    self.unpriced = 0
end

function ManaModel:EndFight(t)
    self:Advance(t)
    self.fight = nil
end

-- FSR-aware time to fill the deficit at zero spend, from t onward -- used
-- both for "rest" (in combat too) and for the out-of-combat "refill" time.
-- A rate this needs but does not have (nil) makes the whole answer nil,
-- never a guess at zero.
local function RestTime(self, t)
    local deficit = self.max - self.mana
    if deficit <= 0 then return 0 end

    local fsr = (self.lastSpend + 5) - t
    if fsr < 0 then fsr = 0 end

    if fsr > 0 then
        if self.casting == nil then return nil end
        local gained = self.casting * fsr
        if gained >= deficit then
            if self.casting <= 0 then return nil end
            return deficit / self.casting
        end
        if self.base == nil or self.base <= 0 then return nil end
        return fsr + (deficit - gained) / self.base
    end

    if self.base == nil or self.base <= 0 then return nil end
    return deficit / self.base
end

-- The state every renderer (Text below, the dashboard's own numbers) reads.
function ManaModel:Project(t)
    self:Advance(t)
    local out = { mana = self.mana, max = self.max, unpriced = self.unpriced, anchor = self.anchor }

    if self.fight then
        local elapsed = t - self.fight.start
        if elapsed < 0 then elapsed = 0 end
        local spend = 0
        if elapsed > 0 then spend = self.fight.spent / elapsed end

        local regen = nil
        if self.casting ~= nil and self.base ~= nil and elapsed > 0 then
            local fsrTime = self.fight.fsrTime
            if fsrTime > elapsed then fsrTime = elapsed end
            regen = (fsrTime * self.casting + (elapsed - fsrTime) * self.base) / elapsed
        end
        out.spend = spend
        out.regen = regen
        out.rest = RestTime(self, t)

        if self.fight.casts < 3 or elapsed < 10 then
            out.mode = "warmup"
        elseif regen == nil then
            -- No out-of-combat regen reading exists yet to judge a direction
            -- by -- reported as a hold, never guessed.
            out.mode = "hold"
        else
            local net = spend - regen
            if net > 0 then
                out.mode = "oom"
                out.tto = self.mana / net
            elseif net < 0 then
                out.mode = "full"
                out.ttf = (self.max - self.mana) / (-net)
            else
                out.mode = "hold"
            end
        end
    else
        out.rest = RestTime(self, t)
        if self.max > 0 and self.mana >= self.max then
            out.mode = "fullnow"
        else
            out.mode = "ooc"
            out.ttf = RestTime(self, t)
        end
    end

    return out
end

--------------------------------------------------------------------------------
-- Rendering: ASCII only, no bare pipe, a nil time is "--" never 0, every
-- shape marked "~" for modelled. Rounded to the nearest 5s; above 600s
-- (10 minutes) reads ">10m" rather than a long number nobody trusts anyway.
--------------------------------------------------------------------------------
local function Round5(sec)
    return math.floor(sec / 5 + 0.5) * 5
end

local function FmtTime(sec)
    if type(sec) ~= "number" then return "--" end
    if sec > 600 then return ">10m" end
    sec = Round5(sec)
    if sec > 600 then return ">10m" end
    if sec < 0 then sec = 0 end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- T11b (docs/tasks/T11b-clock-modes.md): the "rest <t>" segment, worded and
-- gated exactly as TBC's Engine/TTO.lua GetDisplayString lines 397-403 gate
-- its own rest segment -- shown whenever the primary (v) is missing (nil,
-- TBC's "nothing to compare against"), and otherwise only when it differs
-- from the primary by at least 25% (TBC line 400's
-- abs(r - v) / max(v, 1) >= 0.25). Two-space separator (TBC line 405), never
-- a pipe. Absent entirely when there is no rest reading at all.
local function RestSegment(v, rest)
    if type(rest) ~= "number" then return "" end
    if v == nil or math.abs(rest - v) / math.max(v, 1) >= 0.25 then
        return "  rest " .. FmtTime(rest)
    end
    return ""
end

-- T11b: every mode worded as TBC's Engine/TTO.lua GetDisplayString words the
-- same mode (lines 349-376), with the "~" kept in front (T11 -- the pool is
-- modelled, never the client's own).
--   fullnow -> TBC's "FULL" (line 350)
--   ooc/full -> TBC's "FULL <ttf>" (line 354; TBC uses one word for both the
--     out-of-combat and in-combat "trending toward full" cases)
--   warmup -> TBC's "OOM ..." (line 356), the rest segment allowed the same
--     as every other in-combat mode (TBC line 390)
--   hold -> TBC's rule for a missing value, "OOM --" (line 362; TBC's own
--     "hold" bound at line 357-359 needs sigma/a mana-cooldown table this
--     model does not have, T11 "not adopted")
--   oom -> TBC's "OOM <t>" (line 374), or "OOM --" when tto is nil (line 362,
--     "never fabricate a number")
function ManaModel.Text(state)
    if type(state) ~= "table" or type(state.mode) ~= "string" then return "~OOM --" end
    local m = state.mode

    if m == "fullnow" then return "~FULL" end
    if m == "ooc" then return "~FULL " .. FmtTime(state.ttf) end
    if m == "full" then return "~FULL " .. FmtTime(state.ttf) end
    if m == "warmup" then return "~OOM ..." .. RestSegment(nil, state.rest) end
    if m == "hold" then return "~OOM --" .. RestSegment(nil, state.rest) end
    if m == "oom" then
        local t = FmtTime(state.tto)
        if t == "--" then return "~OOM --" .. RestSegment(nil, state.rest) end
        return "~OOM " .. t .. RestSegment(state.tto, state.rest)
    end
    return "~OOM --"
end
