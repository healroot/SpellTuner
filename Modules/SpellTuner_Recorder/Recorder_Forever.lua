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
    -- Review R24/R25: a member who has left keeps their roster index (a
    -- stream already recorded may name it), but not their token -- party
    -- tokens compact when someone leaves, so the old one now names somebody
    -- else. Every entry loses its token here; only the live ones below get
    -- one back, so the aura scan and the death poll never read a departed
    -- member through a token that belongs to another.
    for _, e in ipairs(self.roster) do e.token = nil end
    for _, token in ipairs(tokens) do
        if MD.API.UnitExists(token) == true then
            local guid = MD.API.UnitGUID(token)
            -- T49 (P5), B15: UnitName's second return is the realm of a
            -- member from another realm (nil, or "" on some clients, for
            -- one's own). The name stays bare -- it is what other recordings
            -- are matched on (SM.PartyMaxFromOthers, SM.DangerHitFromOthers),
            -- old ones included -- and the realm is kept beside it. A failed
            -- read answers nil and the adapter's status word ("secret" /
            -- "absent" / "error"), which is not a realm: no plain name, no realm.
            local name, realm = MD.API.UnitName(token)
            if type(name) ~= "string" or type(realm) ~= "string" or realm == "" then realm = nil end
            local loc, class = MD.API.UnitClass(token)
            if not loc then class = nil end
            local level = MD.API.UnitLevel(token)
            local role = MD.API.UnitGroupRolesAssigned(token)
            if type(role) ~= "string" then role = nil end

            -- Party members' current and max health are secret; the
            -- player's max is plain (Facts). -1/maxSecret=true is Planner
            -- ruling 1's stand-in -- this task only records it.
            local maxHP, maxSecret, maxVia = -1, true, nil
            if token == "player" then
                local hp = MD.API.UnitHealthMax(token)
                if type(hp) == "number" then maxHP, maxSecret = hp, false end
            else
                -- T17c: a status bar's read-back of the party member's max,
                -- only when the adapter's BAR_READS_MAX is on and the bar
                -- hands it back plain; otherwise the stand-in as before.
                local hp = MD.API.HealthMax(token)
                if type(hp) == "number" then maxHP, maxSecret, maxVia = hp, false, "bar" end
            end

            -- a session-only key (never stored): the full name, so two
            -- same-name members of different realms with no plain GUID stay two
            local key = RosterKey(guid, (type(name) == "string" and realm) and (name .. "-" .. realm) or name, token)
            local idx = self.index[key]
            if not idx then
                idx = #self.roster + 1
                self.index[key] = idx
            end
            self.roster[idx] = {
                name = (type(name) == "string") and name or nil,
                realm = realm,
                guid = (type(guid) == "string") and guid or nil,
                class = class, role = role,
                level = (type(level) == "number") and level or nil,
                maxHP = maxHP, maxSecret = maxSecret, maxVia = maxVia,
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
        out[i] = { name = e.name, realm = e.realm, guid = e.guid, class = e.class, role = e.role,
                   level = e.level, maxHP = e.maxHP, maxSecret = e.maxSecret, maxVia = e.maxVia }
    end
    return out
end

-- T49 (P5), B15: UNIT_SPELLCAST_SENT names a member from another realm
-- "Name-Realm" (the retail convention; unverified on the beta, whose probe
-- only ever saw same-realm names). First the full name exactly -- a
-- same-realm member's full name is the bare one -- then the bare name (the
-- target's own, or the part before its realm) when exactly one roster entry
-- carries it. Two members of one name and no realm to tell them apart are
-- nobody's rather than a guess.
local function FullName(e)
    if e.realm then return e.name .. "-" .. e.realm end
    return e.name
end
local function ResolveTargetIndex(target)
    if type(target) ~= "string" or target == "" then return -1 end
    for i, e in ipairs(R.roster) do
        if e.name and FullName(e) == target then return i end
    end
    local bare = target:match("^([^%-]+)%-.") or target
    local found = -1
    for i, e in ipairs(R.roster) do
        if e.name == bare then
            if found ~= -1 then return -1 end
            found = i
        end
    end
    return found
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
        -- Review R24/R25: a departed member has no token (R:Refresh), and is
        -- skipped rather than read through a token that is somebody else's.
        local token = e.token
        for j = 1, token and 40 or 0 do
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
    R.lastScanTime = now -- T13f: PLAYER_REGEN_DISABLED reads this to age the scan up to t0
end

-- T13f (lead review 3 of T13d): the scan that fed `list` can be up to 2s
-- stale by the time the pull actually starts -- `elapsed` (t0 - scan time)
-- is subtracted from every timed remaining so the stream carries "time left
-- at the pull", not "time left when we happened to look". An entry that has
-- run out in the meantime is dropped rather than stored negative.
local function CopyAuraList(list, elapsed)
    local out = {}
    local n = 0
    for _, e in ipairs(list) do
        local remaining = e.remaining
        if type(remaining) == "number" then remaining = remaining - elapsed end
        if remaining == nil or remaining > 0 then
            n = n + 1
            out[n] = { token = e.token, spellId = e.spellId, remaining = remaining, stacks = e.stacks,
                       tgt = e.tgt }
        end
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
local sentAt = {}      -- castGUID -> GetTime() of its SENT (Review R8: pruned by age, not wiped at the pull)
local deadState = {}   -- roster index -> true while recorded dead (not stored)
local preCasts = {}    -- Review R8: own casts that succeeded with no pull active, { t, sid, tgt, amt }
local tickCount = 0

-- Review R8: a SENT whose cast never went further (out of range, refused)
-- would otherwise stay in sentTarget for the session. Ten seconds is longer
-- than any cast bar.
local SENT_MAX_AGE = 10
-- Review R8: how long before PLAYER_REGEN_DISABLED an own cast may have
-- succeeded and still be the pull's opener -- the heal that put the healer
-- into combat arrives in the same frame as the combat flag or the next.
-- Within it, the cast is recorded at t = 0; older ones landed before the
-- pull, and their HoTs are the aura scan's (kept current by UNIT_AURA).
local OPENER_WINDOW = 0.5
local PRECAST_KEEP = 8

local function PruneSent(now)
    for castGUID, at in pairs(sentAt) do
        if now - at > SENT_MAX_AGE then
            sentAt[castGUID] = nil
            sentTarget[castGUID] = nil
        end
    end
end

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

-- One own cast into a stream: the event, the shared readers' two summary
-- numbers (T13f Facts: rec.ownCasts, rec.spent -- amt of -1, cost unknown,
-- adds nothing) and the spell's name for offline reading.
local function RecordOwnCast(s, t, sid, tgt, amt)
    Push(s, t, K.OWNCAST, tgt, amt, sid)
    s.ownCasts = (s.ownCasts or 0) + 1
    if amt and amt > 0 then s.spent = (s.spent or 0) + amt end

    if sid ~= -1 and not s.names[sid] then
        local name = MD.API.SpellName(sid)
        if type(name) == "string" then
            local sub = MD.API.SpellSubtext(sid)
            s.names[sid] = (type(sub) == "string") and (name .. " " .. sub) or name
        end
    end
end

-- Every tracked index polled once through UnitIsDeadOrGhost: a new death is
-- recorded at `t`, a res clears the mark (no event, per Facts). Called from
-- the ticker and (Review R10) once more as the pull ends, because the
-- healer's own death takes them out of combat in the same frame.
local function CheckDeaths(s, t)
    for _, idx in ipairs(s.tracked) do
        local e = R.roster[idx]
        local token = e and e.token
        if token then
            local dead = MD.API.UnitIsDeadOrGhost(token)
            if dead == true and not deadState[idx] then
                deadState[idx] = true
                Push(s, t, K.DIED, idx, 0, 0)
                s.deaths[#s.deaths + 1] = { t, idx }
            elseif dead == false and deadState[idx] then
                deadState[idx] = false -- a res: no event, per Facts
            end
        end
    end
end

-- Review R7: whoever is already dead or a ghost when they come under the
-- recorder's eye (the pull's start, or joining mid-pull) did not die in this
-- pull -- marked, never recorded, so the first poll does not take them for a
-- death at t = 0.5.
local function SeedDead(indices)
    for _, idx in ipairs(indices) do
        local e = R.roster[idx]
        local token = e and e.token
        if token and deadState[idx] == nil and MD.API.UnitIsDeadOrGhost(token) == true then
            deadState[idx] = true
        end
    end
end

-- Review R8: did the last out-of-combat aura scan run after this pre-pull
-- cast and find its aura? Then the HoT is already in initial.auras, with its
-- own cadence, and the cast is not recorded a second time.
local function SeenByScan(c)
    if not R.lastScanTime or R.lastScanTime < c.t then return false end
    for _, a in ipairs(R.lastAuras) do
        if a.spellId == c.sid and a.tgt == c.tgt then return true end
    end
    return false
end

MD:On("PLAYER_REGEN_DISABLED", function()
    R:Refresh()
    -- Review R8: sentTarget is NOT wiped here -- a cast-time opener was SENT
    -- out of combat and SUCCEEDS inside the pull, and needs its target.
    pending, deadState = {}, {}
    PruneSent(GetTime())

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
    -- T13f: age the last out-of-combat scan up to this moment rather than
    -- storing it as read (see CopyAuraList above). Never negative -- a scan
    -- that happens to land at t0 itself (or the module having no scan yet)
    -- ages by nothing.
    local elapsed = t0 - (R.lastScanTime or t0)
    if elapsed < 0 then elapsed = 0 end
    local clockMana = MD.Clock and MD.Clock.model and MD.Clock.model.mana
    active = {
        v = 3, client = "forever", id = time(), zone = MD.API.RealZoneText(),
        t0 = t0, dur = 0, pool = MD.API.UnitPowerMax("player", 0) or 0,
        roster = CopyRoster(), tracked = { unpack(R.tracked) },
        ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }, n = 0,
        mana = { t = {}, v = {}, base = {}, cast = {} }, manaModelled = true,
        deaths = {}, restriction = {}, names = {},
        ownCasts = 0, spent = 0, -- T13f: the shared Review/replay/card readers
        initial = {
            mana = clockMana or 0,
            form = "caster", -- Forever: no Tree of Life (T15 Kit_Forever.lua Facts)
            known = known,
            auras = CopyAuraList(R.lastAuras, elapsed),
        },
        meter = nil, unreadable = 0, truncated = false, raid = R.raid, pinned = false,
    }

    -- Review R7: nobody already dead at the pull dies in it.
    SeedDead(active.tracked)

    -- Review R8: the opener. An own cast that succeeded in the moment before
    -- the combat flag (healing a tank already in combat is what puts the
    -- healer into it) is the pull's first cast, recorded at t = 0 -- unless
    -- the last aura scan already carries its HoT. The clock charged its cost
    -- before t0, so the stream's starting mana is lifted by that cost and
    -- the cast pays it again at t = 0: the replay spends it once.
    local lifted = 0
    for _, c in ipairs(preCasts) do
        local age = t0 - c.t
        if age >= 0 and age <= OPENER_WINDOW and not SeenByScan(c) then
            RecordOwnCast(active, 0, c.sid, c.tgt, c.amt)
            if c.amt > 0 then lifted = lifted + c.amt end
        end
    end
    preCasts = {}
    if lifted > 0 and clockMana then
        local m = clockMana + lifted
        if active.pool > 0 and m > active.pool then m = active.pool end
        active.initial.mana = m
    end

    MD:Debug("sim", "forever pull started: %d tracked, %d initial aura(s), %d opener cast(s)",
        #active.tracked, #active.initial.auras, active.ownCasts)
end)

MD:On("GROUP_ROSTER_UPDATE", function()
    -- R:Refresh() already ran above; mirror the live roster/tracked list into
    -- the active stream so a newcomer (added at the end, Facts) is not lost
    -- and an existing member's fields (e.g. a role change) stay current.
    -- Indices never move: R.index keys by GUID/name, so a token swap changes
    -- WHICH token an index answers to, never the index itself.
    if not active then return end
    active.roster = CopyRoster()
    local seen, added = {}, {}
    for _, idx in ipairs(active.tracked) do seen[idx] = true end
    for _, idx in ipairs(R.tracked) do
        if not seen[idx] then
            active.tracked[#active.tracked + 1] = idx; seen[idx] = true
            added[#added + 1] = idx
        end
    end
    table.sort(active.tracked)
    SeedDead(added) -- Review R7: a newcomer who joins dead did not die here
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
-- Review R8: SENT is kept with or without a pull -- a cast-time opener is
-- SENT before the combat flag and SUCCEEDS after it.
MD:On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end
    if MD.API.IsSecret(target) or type(target) ~= "string" then return end
    sentTarget[castGUID] = target
    sentAt[castGUID] = GetTime()
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
    if MD.API.IsSecret(unit) or unit ~= "player" then return end
    if MD.API.IsSecret(castGUID) or type(castGUID) ~= "string" then return end

    local sid = spellID
    if MD.API.IsSecret(sid) or type(sid) ~= "number" then sid = -1 end

    local tgt = ResolveTargetIndex(sentTarget[castGUID])
    local amt = -1
    if sid ~= -1 then
        local cost = CostFor(sid)
        if cost ~= nil then amt = cost end
    end
    sentTarget[castGUID] = nil
    sentAt[castGUID] = nil

    if not active then
        -- Review R8: no pull yet -- kept for PLAYER_REGEN_DISABLED, which
        -- takes the one that opened the pull (OPENER_WINDOW).
        preCasts[#preCasts + 1] = { t = GetTime(), sid = sid, tgt = tgt, amt = amt }
        if #preCasts > PRECAST_KEEP then table.remove(preCasts, 1) end
        return
    end

    -- T13f: the shared Review tab / replay window / card read rec.ownCasts
    -- and rec.spent (Facts) -- RecordOwnCast keeps both.
    RecordOwnCast(active, GetTime() - active.t0, sid, tgt, amt)
    pending[castGUID] = nil
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
            sentAt[castGUID] = nil
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
        if tickCount % 4 == 0 then
            PruneSent(GetTime())
            if not InCombat() then ScanAuras() end
        end
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
    CheckDeaths(active, GetTime() - active.t0)
end)

-- Review R8: a HoT that lands out of combat between two 2 s scans is read at
-- once, so a pre-cast in the last seconds before the pull is in the pull's
-- initial auras. Only the tracked tokens, never in combat (Facts: reading
-- auras in combat raises), never during a pull.
MD:On("UNIT_AURA", function(unit)
    if active then return end
    if MD.API.IsSecret(unit) or type(unit) ~= "string" then return end
    if not R.tokenIndex[unit] then return end
    if InCombat() then return end
    ScanAuras()
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
    local sawLocal, unreadableRows = false, 0
    if type(session.combatSources) == "table" then
        for _, row in ipairs(session.combatSources) do
            if type(row) == "table" and type(row.totalAmount) == "number" then
                local isLocal = row.isLocalPlayer == true
                bySource[#bySource + 1] = {
                    name = (type(row.name) == "string") and row.name or nil,
                    amount = row.totalAmount, isLocal = isLocal,
                }
                if isLocal then
                    sawLocal = true
                    own = own + row.totalAmount
                    if type(row.sourceGUID) == "string" then ownGUID = row.sourceGUID end
                else
                    others = others + row.totalAmount
                end
            else
                unreadableRows = unreadableRows + 1
            end
        end
    end

    -- Review R9: a session with nothing in it (build 70009 read Current as
    -- sources=0 out of combat), rows whose amount did not come back plain
    -- (the copy drops a secret field, so the totals would be partial), or no
    -- row for the player is not a reading of this pull -- stored as none,
    -- so the gates say "no damage meter reading" instead of passing on zeros.
    local notRead
    if unreadableRows > 0 then
        notRead = "unreadable rows"
    elseif #bySource == 0 or own + others <= 0 then
        notRead = "empty"
    elseif not sawLocal then
        notRead = "no own row"
    end
    if notRead then
        s.meter = { read = "none", why = notRead }
        return
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

    -- T13f Facts: the Forever foreign share is the meter's, only when the
    -- meter itself was actually read (nil otherwise, matching the shared
    -- readers' `rec.foreignShare` being absent on a v2/no-meter stream).
    s.foreignShare = others / (own + others) -- own + others > 0, checked above
end

-- The single fights, newest first, as TBC's Engine/FightRecorder.lua answers
-- them. T62 (P18): this file is Forever's fight recorder, so it defines
-- MD.FightRecorder's List / Get / Pin outright -- the `if ... == nil` patches
-- are gone (Engine/FightRecorder.lua is on the TBC TOC only) -- and answers
-- bare N through the one router (Engine/Recordings.lua), which also owns the
-- address grammar and the pin cap ("pN" is Practice's; "a:b" answers nil:
-- Forever records no runs).
local FR = {}
MD.FightRecorder = FR

function FR:List()
    local list = {}
    for _, r in ipairs(MD.cdb and MD.cdb.recordings or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return list
end

function FR:Get(n)
    return FR:List()[n or 1]
end

-- T49 (P5), B14: a refusal says why, in a line the Review tab prints.
function FR:Pin(n, on)
    local rec = FR:Get(n)
    if not rec then return false, "no recording " .. tostring(n or 1) end
    return MD.Recordings.PinRecord("", rec, on and true or false)
end

MD.Recordings.Register("", {
    Get = function(n) return FR:Get(n) end,
    List = function() return FR:List() end,
    pinCap = MD.Recordings.MAX_PINNED,
    noun = "fights",
})

-- 8 kept; past that, the oldest unprotected one is dropped (Facts). T49 (P5),
-- B14: only the first MAX_PINNED pinned streams (in list order) are protected
-- (the router's MD.Recordings.MAX_PINNED since T62, shared with TBC),
-- as TBC's Engine/FightRecorder.lua does -- a list with more pins than that
-- (an old file, or the Review tab's toggle before T49) still takes the new
-- pull, and a debug line says a pinned one had to go.
local function StoreOrDrop(s)
    local casts = CountKind(s, K.OWNCAST)
    -- T62 (P18): the gate is MD.Util.RECORD_GATE (Core.lua), one for both lines
    local gate = MD.Util.RECORD_GATE
    if s.dur < gate.sec or casts < gate.casts then
        MD:Debug("sim", "forever stream discarded: %.0fs, %d own cast(s) (needs %ds / %d)", s.dur, casts,
            gate.sec, gate.casts)
        return
    end

    -- The spell kit at this pull, for the offline tools (tools/import.lua):
    -- built from the live spellbook, so nothing offline can rebuild it. Only
    -- with the Replay module on (Kit_Forever.lua is its file); without it the
    -- tools fall back to the last kit built (cdb.kit) and say so.
    if MD.RankMath and MD.RankMath.KitSnapshot then
        local okKit, snap = pcall(MD.RankMath.KitSnapshot)
        if okKit then s.kit = snap end
    end

    MD.cdb.recordings = MD.cdb.recordings or {}
    local list = MD.cdb.recordings
    if #list < MAX_STREAMS then
        list[#list + 1] = s
        return
    end

    local MAX_PINNED = MD.Recordings.MAX_PINNED
    local protected, pinnedCount = {}, 0
    for i, r in ipairs(list) do
        if r.pinned and pinnedCount < MAX_PINNED then
            protected[i] = true
            pinnedCount = pinnedCount + 1
        end
    end
    local victim
    for i, r in ipairs(list) do
        if not protected[i] and (not victim or (r.id or 0) < (list[victim].id or 0)) then victim = i end
    end
    -- MAX_PINNED < MAX_STREAMS, so there is always a victim
    if list[victim].pinned then
        MD:Debug("sim", "forever stream stored over a pinned one: more than %d pinned, only the first %d are kept",
            MAX_PINNED, MAX_PINNED)
    end
    list[victim] = s
end

MD:On("PLAYER_REGEN_ENABLED", function()
    local s = active
    if not s then return end
    -- Any cast marked ended but never SUCCEEDED by the time combat drops is
    -- a genuine cancel (Lead review 1) -- flushed before `active` is cleared,
    -- since Push/FlushCancels need it.
    FlushCancels(s, GetTime() - s.t0)
    -- Review R10: one last death poll -- the healer's own death is what
    -- ended combat, usually before the ticker could see it.
    CheckDeaths(s, GetTime() - s.t0)
    active = nil
    s.dur = GetTime() - s.t0
    MD.API.After(1, function()
        -- Review R10: and once more a second later, for the player only, in
        -- case the dead flag trailed the combat flag. Nothing out of combat
        -- kills in that second in practice (damage keeps a healer in
        -- combat), and a chain pull means the player is alive. PLAYER_DEAD
        -- would say it directly, but the probe has never measured it on
        -- this client; UnitIsDeadOrGhost it has.
        local pidx = R.tokenIndex.player
        if not active and pidx and not deadState[pidx]
            and MD.API.UnitIsDeadOrGhost("player") == true then
            deadState[pidx] = true
            Push(s, s.dur, K.DIED, pidx, 0, 0)
            s.deaths[#s.deaths + 1] = { s.dur, pidx }
        end
        -- Review R11: a chain pull may have started within the second. The
        -- meter is secret in combat, and "Current" is by then the new
        -- fight's session -- this pull's reading is missing, not the new
        -- fight's totals.
        if active or InCombat() then
            s.meter = { read = "none", why = "combat" }
        else
            ReadMeter(s)
        end
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
