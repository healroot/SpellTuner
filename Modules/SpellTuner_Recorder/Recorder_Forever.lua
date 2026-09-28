-- T13 (docs/tasks/T13-recorder-v3.md): the Forever recorder -- a v3 stream of
-- one pull into the same per-character ring the TBC recorder uses
-- (MD.cdb.recordings, 8 kept). Reaches the client only through MD.API; no
-- flavour check needed (this file is Forever-only, LoadOnDemand). Runs only
-- while the SpellTuner_Recorder module is on -- this file is that module's
-- own TOC entry, so it registers nothing until then.
local _, MD = ...

--------------------------------------------------------------------------------
-- Event kinds. Numbers borrowed from Engine/SimModel.lua's SM.K (T13d turns a
-- v3 stream into a scenario against that same engine) -- copied here, not
-- read off SM.K, because the Replay module that defines it is not guaranteed
-- loaded while the Recorder module runs alone. HEAL (15) is new: a heal of
-- unknown source, never entered into the engine directly (T13d's job).
--------------------------------------------------------------------------------
local K = { DMG = 1, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9, HEAL = 15 }

--------------------------------------------------------------------------------
-- Reversible ASCII escaping, Client/Probe.lua's own rule (Rules: "ASCII-only
-- printed lines (names escaped)") -- Spells/Measure.lua's own Esc, duplicated
-- rather than imported for the same reasoning that file gives: no public Esc
-- is exposed, and the only client string here (a zone name) is already read
-- through MD.API, never a client table directly.
--------------------------------------------------------------------------------
local function Esc(s)
    if type(s) ~= "string" then return "" end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

local MAX_EV = 4000
local MAX_STREAMS = 8
local MAX_PINNED = 2

-- The book's own English family name -> the engine's family key (T15's own
-- table, Modules/SpellTuner_Replay/Kit_Forever.lua) -- duplicated rather than
-- shared, because the Replay module that owns that file is not guaranteed
-- loaded while the Recorder module runs alone.
local FAMILY_KEY = {
    ["Healing Touch"] = "HealingTouch",
    ["Regrowth"]       = "Regrowth",
    ["Rejuvenation"]   = "Rejuvenation",
    ["Swiftmend"]      = "Swiftmend",
    ["Tranquility"]    = "Tranquility",
}

--------------------------------------------------------------------------------
-- Roster: player, party1..party4 that exist -- indexed by GUID (by name when
-- the GUID is not plain), so a roster change mid-pull maps the new tokens
-- onto the same indices and adds a newcomer at the end. Persists for the
-- whole module session (not reset per pull) so the out-of-combat aura scan
-- always has somewhere to read from, pull or no pull.
--------------------------------------------------------------------------------
local R = { roster = {}, index = {}, tokenIndex = {}, tracked = {}, raid = false, lastAuras = {} }

local function RosterKey(guid, name, token)
    if type(guid) == "string" then return "g:" .. guid end
    if type(name) == "string" then return "n:" .. name end
    return "t:" .. token
end

function R:Refresh()
    -- Raid detection with no new binding: UnitExists is already generic, and
    -- a raid roster shows up as raid1.. existing -- v1 is party (Facts), so
    -- this is only ever asked to decide whether to go party-only.
    local raid = MD.API.UnitExists("raid1") == true
    self.raid = raid
    local tokens = { "player" }
    if not raid then
        for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
    end

    self.tokenIndex = {}
    for _, token in ipairs(tokens) do
        if MD.API.UnitExists(token) == true then
            local guid = MD.API.UnitGUID(token)
            local name = MD.API.UnitName(token)
            local loc, class = MD.API.UnitClass(token)
            if not loc then class = nil end
            local level = MD.API.UnitLevel(token)
            local role = MD.API.UnitGroupRolesAssigned(token)
            if type(role) ~= "string" then role = nil end

            -- Party members' current and max health are secret; the
            -- player's max is plain (Facts). -1/maxSecret=true is Planner
            -- ruling 1's stand-in -- this task only records it.
            local maxHP, maxSecret = -1, true
            if token == "player" then
                local hp = MD.API.UnitHealthMax(token)
                if type(hp) == "number" then maxHP, maxSecret = hp, false end
            end

            local key = RosterKey(guid, name, token)
            local idx = self.index[key]
            if not idx then
                idx = #self.roster + 1
                self.index[key] = idx
            end
            self.roster[idx] = {
                name = (type(name) == "string") and name or nil,
                guid = (type(guid) == "string") and guid or nil,
                class = class, role = role,
                level = (type(level) == "number") and level or nil,
                maxHP = maxHP, maxSecret = maxSecret,
                token = token, -- kept on the LIVE entry only; never copied into a stored stream
            }
            self.tokenIndex[token] = idx
        end
    end

    self.tracked = {}
    for _, idx in pairs(self.tokenIndex) do self.tracked[#self.tracked + 1] = idx end
    table.sort(self.tracked)
end

-- A plain copy of the roster's own recorded fields, for a stream (rule:
-- nothing but numbers/strings/booleans/tables of them, and never the live
-- `token` field, which is a bookkeeping detail, not a client value).
local function CopyRoster()
    local out = {}
    for i, e in ipairs(R.roster) do
        out[i] = { name = e.name, guid = e.guid, class = e.class, role = e.role,
                   level = e.level, maxHP = e.maxHP, maxSecret = e.maxSecret }
    end
    return out
end

local function ResolveTargetIndex(name)
    if type(name) ~= "string" then return -1 end
    for i, e in ipairs(R.roster) do
        if e.name == name then return i end
    end
    return -1
end

MD:On("GROUP_ROSTER_UPDATE", function() R:Refresh() end)
R:Refresh() -- the module may load mid-session, already in a group

--------------------------------------------------------------------------------
-- Pre-pull HoTs: read only out of combat (Facts: reading auras in combat
-- raises), every 2s, kept as "the last out-of-combat read" so a pull that
-- starts mid-scan still has something to snapshot.
--------------------------------------------------------------------------------

-- Lead review 1: the module can be switched on, or loaded at login, while the
-- player is already in combat -- the ticker below must not scan in that case
-- even though no pull is active. UnitAffectingCombat is already bound
-- (Client/API.lua:344). Anything but a plain `false` (secret, nil, an error
-- from the bound call) is treated as "in combat", so a doubtful answer never
-- risks the raise Facts describes.
local function InCombat()
    local v = MD.API.UnitAffectingCombat("player")
    if MD.API.IsSecret(v) then return true end
    return v ~= false
end

-- T13d (docs/tasks/T13d-scenario-v3.md), lead's hand-out amendment: each
-- entry also carries `tgt`, the roster index -- ScanAuras already iterates
-- R.roster by ipairs, so `i` IS that index; without it a stream cannot say
-- which target a pre-pull HoT sits on (the roster itself carries no token,
-- and a token can move between roster indices across a roster change).
local function ScanAuras()
    local now = GetTime()
    local list = {}
    for i, e in ipairs(R.roster) do
        local token = e.token
        for j = 1, 40 do
            local row = MD.API.AuraByIndex(token, j, "HELPFUL|PLAYER")
            if row == nil then break end
            if type(row) == "table" and type(row.spellId) == "number" then
                local remaining
                if type(row.expirationTime) == "number" then remaining = row.expirationTime - now end
                local stacks = 1
                if type(row.applications) == "number" and row.applications > 0 then
                    stacks = row.applications
                end
                list[#list + 1] = { token = token, spellId = row.spellId, remaining = remaining,
                                     stacks = stacks, tgt = i }
            end
        end
    end
    R.lastAuras = list
end

local function CopyAuraList(list)
    local out = {}
    for i, e in ipairs(list) do
        out[i] = { token = e.token, spellId = e.spellId, remaining = e.remaining, stacks = e.stacks,
                   tgt = e.tgt }
    end
    return out
end

--------------------------------------------------------------------------------
-- Cost lookup, T11's UI/Clock_Forever.lua's own CostFor -- duplicated rather
-- than shared, same reasoning as FAMILY_KEY above.
--------------------------------------------------------------------------------
local function CostFor(id)
    if not MD.Book then return nil end
    local book = MD.Book:Get()
    local entry = book and book.spells[id]
    if not entry then
        local ok
        ok, entry = pcall(MD.Book.ReadSpell, MD.Book, id)
        if not ok then entry = nil end
    end
    if not entry then return nil end
    if entry.costState == "free" then return 0 end
    if entry.cost and type(entry.cost.amount) == "number" then return entry.cost.amount end
    return nil
end

--------------------------------------------------------------------------------
-- The active pull. Nil outside combat.
--------------------------------------------------------------------------------
local active = nil
local pending = {}     -- castGUID -> { spellID, t }
local sentTarget = {}  -- castGUID -> target name
local deadState = {}   -- roster index -> true while recorded dead (not stored)
local tickCount = 0

local function Push(s, t, kind, tgt, amt, x)
    if not s or s.truncated then return end
    if s.n >= MAX_EV then
        s.truncated = true
        return
    end
    local n = s.n + 1
    s.n = n
    s.ev.t[n], s.ev.kind[n], s.ev.tgt[n], s.ev.amt[n], s.ev.x[n] = t, kind, tgt, amt, x
end

MD:On("PLAYER_REGEN_DISABLED", function()
    R:Refresh()
    pending, sentTarget, deadState = {}, {}, {}

    local known = {}
    if MD.Book then
        local book = MD.Book:Get()
        for bookName, key in pairs(FAMILY_KEY) do
            local fam = book and book.families[bookName]
            if fam and fam.maxKnown and type(fam.maxKnown.id) == "number" then
                known[key] = fam.maxKnown.id
            end
        end
    end

    local t0 = GetTime()
    active = {
        v = 3, client = "forever", id = time(), zone = MD.API.RealZoneText(),
        t0 = t0, dur = 0, pool = MD.API.UnitPowerMax("player", 0) or 0,
        roster = CopyRoster(), tracked = { unpack(R.tracked) },
        ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }, n = 0,
        mana = { t = {}, v = {}, base = {}, cast = {} }, manaModelled = true,
        deaths = {}, restriction = {}, names = {},
        initial = {
            mana = (MD.Clock and MD.Clock.model and MD.Clock.model.mana) or 0,
            form = "caster", -- Forever: no Tree of Life (T15 Kit_Forever.lua Facts)
            known = known,
            auras = CopyAuraList(R.lastAuras),
        },
        meter = nil, unreadable = 0, truncated = false, raid = R.raid, pinned = false,
    }
    MD:Debug("sim", "forever pull started: %d tracked, %d initial aura(s)",
        #active.tracked, #active.initial.auras)
end)

MD:On("GROUP_ROSTER_UPDATE", function()
    -- R:Refresh() already ran above; mirror the live roster/tracked list into
    -- the active stream so a newcomer (added at the end, Facts) is not lost
    -- and an existing member's fields (e.g. a role change) stay current.
    -- Indices never move: R.index keys by GUID/name, so a token swap changes
    -- WHICH token an index answers to, never the index itself.
    if not active then return end
    active.roster = CopyRoster()
    local seen = {}
    for _, idx in ipairs(active.tracked) do seen[idx] = true end
    for _, idx in ipairs(R.tracked) do
        if not seen[idx] then active.tracked[#active.tracked + 1] = idx; seen[idx] = true end
    end
    table.sort(active.tracked)
end)

--------------------------------------------------------------------------------
-- UNIT_COMBAT: the same hit arrives once per unit token that points at the
-- unit (Facts) -- only the tracked tokens (player, party1..4) are listened
-- to, so a mirror under target/focus/nameplateN/mouseover is simply never
-- matched by R.tokenIndex and drops out here.
--------------------------------------------------------------------------------
MD:On("UNIT_COMBAT", function(unit, action, descriptor, amount, school)
    if not active then return end
    if MD.API.IsSecret(unit) or type(unit) ~= "string" then return end
    if MD.API.IsSecret(action) or type(action) ~= "string" then return end

    local idx = R.tokenIndex[unit]
    if not idx then return end -- an untracked token: ignored, not unreadable

    local kind
    if action == "WOUND" then kind = K.DMG
    elseif action == "HEAL" then kind = K.HEAL
    else return end -- MISS/RESIST/anything else: not kept

    if MD.API.IsSecret(amount) or type(amount) ~= "number" then
        active.unreadable = active.unreadable + 1
        return
    end

    Push(active, GetTime() - active.t0, kind, idx, amount, 0)
end)

--------------------------------------------------------------------------------
-- Own casts.
--------------------------------------------------------------------------------
MD:On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if not active then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end
    if MD.API.IsSecret(target) or type(target) ~= "string" then return end
    sentTarget[castGUID] = target
end)

MD:On("UNIT_SPELLCAST_START", function(unit, castGUID, spellID)
    if not active then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end

    local sid = spellID
    if MD.API.IsSecret(sid) or type(sid) ~= "number" then sid = -1 end

    local t = GetTime() - active.t0
    local tgt = ResolveTargetIndex(sentTarget[castGUID])
    pending[castGUID] = { sid = sid, startT = t }
    Push(active, t, K.CASTSTART, tgt, 0, sid)
end)

MD:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if not active then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end

    local sid = spellID
    if MD.API.IsSecret(sid) or type(sid) ~= "number" then sid = -1 end

    local t = GetTime() - active.t0
    local tgt = ResolveTargetIndex(sentTarget[castGUID])
    local amt = -1
    if sid ~= -1 then
        local cost = CostFor(sid)
        if cost ~= nil then amt = cost end
    end
    Push(active, t, K.OWNCAST, tgt, amt, sid)

    if sid ~= -1 and not active.names[sid] then
        local name = MD.API.SpellName(sid)
        if type(name) == "string" then
            local sub = MD.API.SpellSubtext(sid)
            active.names[sid] = (type(sub) == "string") and (name .. " " .. sub) or name
        end
    end

    pending[castGUID] = nil
    sentTarget[castGUID] = nil
end)

-- Lead review 1: whether UNIT_SPELLCAST_STOP fires before or after
-- UNIT_SPELLCAST_SUCCEEDED for a cast that lands is UNKNOWN (the probe
-- reports the event present, docs/probe/1.60.1_70009.md 78, never its
-- order) -- STOP fires at the end of EVERY cast-time spell, successful ones
-- included. So STOP/FAILED/INTERRUPTED only MARK a pending cast ended; only
-- a cast still pending at the next tick or at PLAYER_REGEN_ENABLED (neither
-- of which a SUCCEEDED for the same castGUID could still beat) is a genuine
-- CANCEL. sentTarget is deliberately left alone here -- if STOP arrives
-- first, SUCCEEDED still needs it to resolve the cast's target.
local function OnCastEnd(unit, castGUID)
    if not active then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end

    local p = pending[castGUID]
    if p and not p.endT then
        p.endT = GetTime() - active.t0
    end
end
MD:On("UNIT_SPELLCAST_STOP", OnCastEnd)
MD:On("UNIT_SPELLCAST_FAILED", OnCastEnd)
MD:On("UNIT_SPELLCAST_INTERRUPTED", OnCastEnd)

-- Turns every pending cast marked ended (a STOP/FAILED/INTERRUPTED that
-- SUCCEEDED never followed) into a CANCEL, at `t` (the caller's own moment --
-- the next tick, or PLAYER_REGEN_ENABLED), amt the time the cast occupied.
local function FlushCancels(s, t)
    if not s then return end
    for castGUID, p in pairs(pending) do
        if p.endT then
            Push(s, t, K.CANCEL, -1, p.endT - p.startT, p.sid)
            pending[castGUID] = nil
            sentTarget[castGUID] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Add-on restriction brackets: recorded, never relied on for start/stop
-- (Facts -- PLAYER_REGEN_DISABLED/ENABLED are).
--------------------------------------------------------------------------------
MD:On("ADDON_RESTRICTION_STATE_CHANGED", function(a, b)
    if not active then return end
    if MD.API.IsSecret(a) or type(a) ~= "number" then return end
    if MD.API.IsSecret(b) or type(b) ~= "number" then return end
    active.restriction[#active.restriction + 1] = { GetTime() - active.t0, a, b }
end)

--------------------------------------------------------------------------------
-- Ticker: out-of-combat aura scan every 2s while there is no pull; in a pull,
-- mana samples every 2s and a death check every tick.
--------------------------------------------------------------------------------
MD:OnTick(function()
    tickCount = tickCount + 1

    if not active then
        if tickCount % 4 == 0 and not InCombat() then ScanAuras() end
        return
    end

    if tickCount % 4 == 0 then
        local m = MD.Clock and MD.Clock.model
        if m then
            local ms = active.mana
            local n = #ms.t + 1
            ms.t[n], ms.v[n] = GetTime() - active.t0, m.mana
            ms.base[n], ms.cast[n] = m.base, m.casting
        end
    end

    FlushCancels(active, GetTime() - active.t0)

    for _, idx in ipairs(active.tracked) do
        local e = R.roster[idx]
        local token = e and e.token
        if token then
            local dead = MD.API.UnitIsDeadOrGhost(token)
            if dead == true and not deadState[idx] then
                deadState[idx] = true
                local t = GetTime() - active.t0
                Push(active, t, K.DIED, idx, 0, 0)
                active.deaths[#active.deaths + 1] = { t, idx }
            elseif dead == false and deadState[idx] then
                deadState[idx] = false -- a res: no event, per Facts
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- End of pull: the damage meter is secret in combat, plain after (Facts) --
-- read one second later, through MD.API.After, never inside the handler
-- itself.
--------------------------------------------------------------------------------
local function CountKind(s, kind)
    local n = 0
    for i = 1, s.n do
        if s.ev.kind[i] == kind then n = n + 1 end
    end
    return n
end

local function ReadMeter(s)
    local sessionCurrent = MD.API.Constant("Enum.DamageMeterSessionType.Current")
    local typeHealing = MD.API.Constant("Enum.DamageMeterType.HealingDone")
    if sessionCurrent == nil or typeHealing == nil then
        s.meter = { read = "none", why = "absent" }
        return
    end

    local session, why = MD.API.MeterSession(sessionCurrent, typeHealing)
    if type(session) ~= "table" then
        s.meter = { read = "none", why = (type(why) == "string" and why) or "absent" }
        return
    end

    local own, others, bySource, ownGUID = 0, 0, {}, nil
    if type(session.combatSources) == "table" then
        for _, row in ipairs(session.combatSources) do
            if type(row) == "table" and type(row.totalAmount) == "number" then
                local isLocal = row.isLocalPlayer == true
                bySource[#bySource + 1] = {
                    name = (type(row.name) == "string") and row.name or nil,
                    amount = row.totalAmount, isLocal = isLocal,
                }
                if isLocal then
                    own = own + row.totalAmount
                    if type(row.sourceGUID) == "string" then ownGUID = row.sourceGUID end
                else
                    others = others + row.totalAmount
                end
            end
        end
    end

    local bySpell, overkillBySpell = {}, {}
    if ownGUID then
        local source = MD.API.MeterSource(sessionCurrent, typeHealing, ownGUID)
        if type(source) == "table" and type(source.combatSpells) == "table" then
            for _, row in ipairs(source.combatSpells) do
                if type(row) == "table" and type(row.spellID) == "number"
                    and type(row.totalAmount) == "number" then
                    bySpell[row.spellID] = row.totalAmount
                    if type(row.overkillAmount) == "number" then
                        overkillBySpell[row.spellID] = row.overkillAmount
                    end
                end
            end
        end
    end

    s.meter = { own = own, others = others, bySource = bySource,
                bySpell = bySpell, overkillBySpell = overkillBySpell, read = "current" }
end

-- Newest first, matching TBC's Engine/FightRecorder.lua:622-627.
MD.FightRecorder = MD.FightRecorder or {}
if MD.FightRecorder.List == nil then
    function MD.FightRecorder:List()
        local list = {}
        for _, r in ipairs(MD.cdb and MD.cdb.recordings or {}) do list[#list + 1] = r end
        table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
        return list
    end
end
if MD.FightRecorder.Get == nil then
    function MD.FightRecorder:Get(n)
        return MD.FightRecorder:List()[n or 1]
    end
end
if MD.FightRecorder.Pin == nil then
    -- At most MAX_PINNED pinned (TBC's own constant, Engine/FightRecorder.lua:25).
    function MD.FightRecorder:Pin(n, on)
        local list = MD.FightRecorder:List()
        local rec = list[n or 1]
        if not rec then return false end
        if on then
            local count = 0
            for _, r in ipairs(list) do
                if r.pinned and r ~= rec then count = count + 1 end
            end
            if count >= MAX_PINNED then return false end
            rec.pinned = true
        else
            rec.pinned = false
        end
        return true
    end
end
if MD.GetRecording == nil then
    -- TBC's own address scheme (Engine/FightRecorder.lua:640-655): "N" a
    -- single fight, "pN" a practice fight, "a:b" a run's pull -- runs are not
    -- recorded on Forever yet (out of scope), so that shape answers nil.
    function MD:GetRecording(spec)
        spec = tostring(spec or 1)
        local p = spec:match("^[pP](%d+)$")
        if p then return MD.Practice and MD.Practice.Get(tonumber(p)) or nil, "p" .. p end
        if spec:match("^%d+:%d+$") then return nil, spec end
        local n = tonumber(spec) or 1
        return MD.FightRecorder:Get(n), tostring(n)
    end
end

-- 8 kept; past that, the oldest unpinned one is dropped (Facts).
local function StoreOrDrop(s)
    local casts = CountKind(s, K.OWNCAST)
    if s.dur < 20 or casts < 5 then
        MD:Debug("sim", "forever stream discarded: %.0fs, %d own cast(s) (needs 20s / 5)", s.dur, casts)
        return
    end

    MD.cdb.recordings = MD.cdb.recordings or {}
    local list = MD.cdb.recordings
    if #list < MAX_STREAMS then
        list[#list + 1] = s
        return
    end

    local victim
    for i, r in ipairs(list) do
        if not r.pinned and (not victim or (r.id or 0) < (list[victim].id or 0)) then victim = i end
    end
    if not victim then return end -- everything pinned (MAX_PINNED < MAX_STREAMS, so this should not happen)
    list[victim] = s
end

MD:On("PLAYER_REGEN_ENABLED", function()
    local s = active
    if not s then return end
    -- Any cast marked ended but never SUCCEEDED by the time combat drops is
    -- a genuine cancel (Lead review 1) -- flushed before `active` is cleared,
    -- since Push/FlushCancels need it.
    FlushCancels(s, GetTime() - s.t0)
    active = nil
    s.dur = GetTime() - s.t0
    MD.API.After(1, function()
        ReadMeter(s)
        StoreOrDrop(s)
    end)
end)

--------------------------------------------------------------------------------
-- /st rec [clear]
--------------------------------------------------------------------------------
MD:AddCommand("rec", function(arg)
    if arg == "clear" then
        local kept = {}
        for _, r in ipairs(MD.cdb.recordings or {}) do
            if r.pinned then kept[#kept + 1] = r end
        end
        MD.cdb.recordings = kept
        MD:Print("recordings cleared")
        return
    end

    local list = MD.FightRecorder:List()
    if #list == 0 then
        MD:Print("no recordings")
        return
    end
    for i, r in ipairs(list) do
        local casts = CountKind(r, K.OWNCAST)
        local mOwn = (r.meter and type(r.meter.own) == "number") and tostring(math.floor(r.meter.own + 0.5)) or "-"
        local mOthers = (r.meter and type(r.meter.others) == "number")
            and tostring(math.floor(r.meter.others + 0.5)) or "-"
        MD:Print(string.format("%d. %s %ds %d casts %d events meter own %s others %s",
            i, Esc(r.zone or "-"), math.floor((r.dur or 0) + 0.5), casts, r.n or 0, mOwn, mOthers))
    end
end, "/st rec [clear]", "list recorded pulls, or clear the ring (pinned ones kept)")
