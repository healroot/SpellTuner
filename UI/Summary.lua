-- End-of-combat summary: one chat line per fight (>=15s) plus a ring of the
-- last 200 fights, persisted per character in ST.cdb.fights so the pull-time
-- spend seed and the "last time here" reference survive a /reload. The zone is
-- recorded with each fight; Engine/SpendTracker.lua prefers same-zone fights
-- when it seeds the estimator.
--
-- v0.7.0 adds the raw material for replay and coaching (docs/SPEC-v0.7.md §2):
-- every own cast is captured with its cost, target, HP-at-cast and form into a
-- 20s ring (so the pre-pull HoTs are known at the pull) and into the live
-- fight; at the end of combat each cast gets exactly one plan-free label and
-- the fight gets one extra chat line saying where the mana went.
local _, ST = ...

local SD = ST.SpellData

ST.fightHistory = {}
local MAX_HISTORY = 200

-- ST.cdb is not there until PLAYER_LOGIN, so bind (and adopt whatever was
-- saved) at MD_READY. ST.fightHistory keeps its name and shape: everything
-- else that reads it is unchanged.
ST:RegisterCallback("MD_READY", function()
    ST.cdb.fights = ST.cdb.fights or {}
    ST.fightHistory = ST.cdb.fights
    while #ST.fightHistory > MAX_HISTORY do
        table.remove(ST.fightHistory, 1)
    end
    if #ST.fightHistory > 0 then
        ST:Debug("combat", "loaded %d recorded fight(s) from this character's history", #ST.fightHistory)
    end
end)

-- Recent fights in a zone, newest last. Used for the pull-time seed.
function ST:FightsInZone(zone, n)
    local out = {}
    if not zone then return out end
    for i = #ST.fightHistory, 1, -1 do
        local f = ST.fightHistory[i]
        if f.zone == zone then
            table.insert(out, 1, f)
            if #out >= (n or 5) then break end
        end
    end
    return out
end

local fight = nil -- active fight state

--------------------------------------------------------------------------------
-- Own-cast capture (SPEC-v0.7 §2.1)
--
-- One record per cast the player lands, appended to ST.Recorder.ring (always,
-- last 20s) and to the live fight (in combat). The record is the unit both the
-- labels below and the v0.7.1 replay engine read, so it carries everything the
-- combat log cannot reconstruct afterwards: what the target's health was at the
-- moment of the cast, what the cast cost, and whether the player was in Tree
-- form. Anything unavailable is -1, never 0 -- a fabricated zero reads like a
-- measurement (the OOM 0s bug in Engine/TTO.lua was exactly that).
--------------------------------------------------------------------------------
local RING_WINDOW = 20   -- seconds of own casts kept before the pull
local HOT_TICK_TTL = 60  -- seconds before a stale HoT record is dropped

ST.Recorder = {
    ring = {},        -- own casts, last RING_WINDOW seconds
    roster = {},      -- index -> { guid, name, class, role }; stable for the session
    rosterIndex = {}, -- guid -> index
    hots = {},        -- "<guid>\029<family>" -> the cast record that applied it
}
local Rec = ST.Recorder

local SHIFT_SPELLS = {
    [33891] = true,  -- Tree of Life
    [5487]  = true, [9634] = true, -- Bear / Dire Bear
    [768]   = true,  -- Cat
    [783]   = true,  -- Travel
    [1066]  = true,  -- Aquatic
    [24858] = true,  -- Moonkin
}

-- Families whose ticks are tracked (prehot needs Lifebloom too) and the
-- subset where a refresh with ticks left over is genuinely early. Refreshing
-- Lifebloom before it blooms is the play, not a mistake, so it is not here.
local TICKED_FAMILIES = { Rejuvenation = true, Regrowth = true, Lifebloom = true }
local EARLY_FAMILIES = { Rejuvenation = true, Regrowth = true }
local TICK_INTERVAL = { Lifebloom = 1 } -- default 3

-- Utility casts worth naming in the summary: buffs the player put up while the
-- pull was already running. enUS only, like the drink names in UI/Advisor.lua.
local BUFF_NAMES = {
    ["Mark of the Wild"] = true, ["Gift of the Wild"] = true,
    ["Thorns"] = true, ["Omen of Clarity"] = true,
}

local function HotKey(guid, family) return guid .. "\029" .. family end

-- Roster index for a combat-log destination: a small integer the replay engine
-- can key on, assigned on first sight and stable for the session. -1 for
-- anything outside the group.
function Rec:Index(guid, name)
    if not guid or guid == "" then return -1 end
    local i = Rec.rosterIndex[guid]
    if i then return i end
    local e = ST.Targets and ST.Targets:Lookup(guid, name)
    if not e then return -1 end
    i = #Rec.roster + 1
    Rec.roster[i] = { guid = guid, name = e.name, class = e.class, role = e.role }
    Rec.rosterIndex[guid] = i
    return i
end

-- Health fraction of a combat-log destination, or -1 when it cannot be read.
-- The unit token from the roster is only trusted while it still points at the
-- same GUID (party slots shuffle).
local function HpFraction(guid, name)
    if not guid or guid == "" then return -1 end
    local e = ST.Targets and ST.Targets:Lookup(guid, name)
    local unit = e and e.unit
    if not unit or UnitGUID(unit) ~= guid then return -1 end
    local maxHp = UnitHealthMax(unit)
    if not maxHp or maxHp <= 0 then return -1 end
    return UnitHealth(unit) / maxHp
end

local function NoteOwnCast(spellID, destGUID, destName)
    if type(spellID) ~= "number" then return end
    local now = GetTime()
    local sd = SD.spells[spellID]

    local kind = "utility"
    if SHIFT_SPELLS[spellID] then
        kind = "shift"
    elseif sd and SD.families[sd.family] then
        kind = "heal"
    end

    local cost = SD:GetCost(spellID)
    local c = {
        t = now,
        spellID = spellID,
        cost = cost or -1,
        tgt = Rec:Index(destGUID, destName),
        hpAtCast = HpFraction(destGUID, destName),
        form = ST:InTreeForm() and 1 or 0,
        kind = kind,
    }

    -- HoT bookkeeping: the record that applied the HoT owns the ticks that
    -- follow it, which is what makes both "early" (ticks still pending when the
    -- next one went out) and "prehot" (how much of a pre-pull HoT was overheal)
    -- measurements rather than guesses.
    if kind == "heal" and sd and TICKED_FAMILIES[sd.family] and destGUID and destGUID ~= "" then
        local key = HotKey(destGUID, sd.family)
        local prev = Rec.hots[key]
        if prev and EARLY_FAMILIES[sd.family]
           and (prev.ticksTotal - prev.ticksSeen) >= 2 then
            c.early = true
        end
        local interval = TICK_INTERVAL[sd.family] or 3
        c.ticksTotal = sd.hotDuration and math.floor(sd.hotDuration / interval + 0.5) or 4
        c.ticksSeen, c.tickGross, c.tickOver = 0, 0, 0
        Rec.hots[key] = c
    end

    Rec.ring[#Rec.ring + 1] = c
    while Rec.ring[1] and now - Rec.ring[1].t > RING_WINDOW do
        table.remove(Rec.ring, 1)
    end

    if fight then
        fight.casts[#fight.casts + 1] = c
        fight.ownCasts = fight.ownCasts + 1
    end
end

local function PruneHots(now)
    for key, c in pairs(Rec.hots) do
        if now - c.t > HOT_TICK_TTL then Rec.hots[key] = nil end
    end
end

-- 2026-10-12: whose bloom is it? The log credits Lifebloom's bloom
-- (SD.bloomID) to the player it LANDS ON, never the druid who cast it -- the
-- author's 8 recordings held 105 "own" blooms, every one on the druid herself,
-- and none on the targets carrying 1362 of her ticks. The aura events name the
-- real caster, so a bloom is the player's exactly when the player's own
-- Lifebloom on that target ends with it: removed within BLOOM_WINDOW of the
-- heal, or still up and due to expire (the heal may come first). A dispelled
-- Lifebloom blooms early and is missed: it counts as somebody else's.
local BLOOM_WINDOW = 1.0
local Blooms = { mine = {} }   -- destGUID -> { applied = t, removed = t }
ST.Blooms = Blooms

local BLOOM_UP = { SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true }

function Blooms.Aura(subevent, sourceGUID, destGUID, spellID, now)
    if sourceGUID ~= ST.player.guid or not destGUID then return end
    local row = spellID and SD.spells[spellID]
    if not (row and row.family == "Lifebloom") then return end
    if BLOOM_UP[subevent] then
        Blooms.mine[destGUID] = { applied = now, duration = row.hotDuration or 7 }
    elseif subevent == "SPELL_AURA_REMOVED" then
        Blooms.mine[destGUID] = { removed = now }
    end
end

function Blooms.IsMine(destGUID, now)
    local m = destGUID and Blooms.mine[destGUID]
    if not m then return false end
    if m.removed then return now - m.removed <= BLOOM_WINDOW end
    return m.applied ~= nil and now >= m.applied + m.duration - BLOOM_WINDOW
end

-- Combat log, one handler and one CombatLogGetCurrentEventInfo() call: the
-- player's own heals feed the fight totals, the per-spell overheal stats and
-- the "heal" debug category; the player's own casts feed the ring above.
-- Overheal is recorded in AND out of combat -- rolling Lifebloom on a tank
-- between pulls is exactly the sort of casting whose overheal belongs in the
-- average.
ST:On("COMBAT_LOG_EVENT_UNFILTERED", function()
    -- One unpack for the whole addon. The 11-field prefix is fixed; what p1..p10
    -- mean depends on the subevent (docs/SPEC-v0.7.md 1), so they are named
    -- generically here and interpreted by whoever needs them. For the heal
    -- events this file cares about: p1 spellID, p2 spellName, p4 amount,
    -- p5 overheal, p7 critical.
    local _, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _,
        p1, p2, p3, p4, p5, p6, p7, p8, p9, p10 = CombatLogGetCurrentEventInfo()
    local spellID, spellName, amount, overheal, critical = p1, p2, p4, p5, p7
    -- a bloom's logged source is its receiver: give it its real owner before
    -- the recorder or the player-only gate below reads the source
    if subevent == "SPELL_HEAL" and spellID == SD.bloomID then
        sourceGUID = Blooms.IsMine(destGUID, GetTime()) and ST.player.guid or nil
    elseif BLOOM_UP[subevent] or subevent == "SPELL_AURA_REMOVED" then
        Blooms.Aura(subevent, sourceGUID, destGUID, spellID, GetTime())
    end
    -- group members' own casts (Life Tap) before the player-only gate
    if subevent == "SPELL_CAST_SUCCESS" and ST.Targets then
        ST.Targets:NoteCast(sourceGUID, spellName)
    end
    -- The recorder sees everything, including other people's damage and heals;
    -- it decides for itself what is worth keeping (Engine/FightRecorder.lua).
    if ST.FightRecorder and ST.FightRecorder.active then
        if subevent == "UNIT_DIED" then
            ST.FightRecorder:Died(destGUID, destName)
        else
            ST.FightRecorder:Event(subevent, sourceGUID, destGUID, destName,
                p1, p2, p3, p4, p5, p6, p7, p8, p9, p10)
            -- v0.12.0: a hostile cast aimed at somebody we are healing. Not
            -- handled inside FR:Event because that one is written around "is
            -- this the player's own event"; this is the opposite question.
            if sourceGUID ~= ST.player.guid then
                ST.FightRecorder:EnemyCast(subevent, sourceGUID, destGUID, destName, p1)
            end
        end
    end
    if sourceGUID ~= ST.player.guid then return end
    -- SPELL_CAST_SUCCESS carries the cast's target in the prefix destGUID /
    -- destName (verified against Details!, SPEC-v0.7 §1) -- no cast-to-heal
    -- matching is needed.
    if subevent == "SPELL_CAST_SUCCESS" then
        NoteOwnCast(spellID, destGUID, destName)
        return
    end
    if subevent ~= "SPELL_HEAL" and subevent ~= "SPELL_PERIODIC_HEAL" then return end
    -- the log names some heals' receiver as their source (Earth Shield,
    -- Judgement of Light; a bloom's owner is settled above): only a spell in
    -- the player's own book is the player's heal
    if ST.BookTBC and not ST.BookTBC.IsOwnSpell(spellName) then return end
    amount, overheal = amount or 0, overheal or 0

    -- Event kind for calibration and (v0.6.3) the overheal buckets: a periodic
    -- event is a tick; a non-periodic Lifebloom event is its bloom; the rest
    -- are direct heals.
    --
    -- T48 (review B10): the bloom arrives under 33778, an ALIAS and not a row,
    -- so it used to stay "direct" under its own id -- calibration never saw it,
    -- the kind-scoped bloom fraction RankMath reads never existed, and waste
    -- charged a fully overhealed bloom the whole cast. The resolved id is used
    -- ONLY when the raw id is not a row and resolves to Lifebloom: then the
    -- event is a bloom of the Lifebloom that bloomed (33763). Every other id,
    -- Tranquility's 44208 / 44207 included, reaches both calls unchanged.
    local kind = "direct"
    local attrID = spellID
    if subevent == "SPELL_PERIODIC_HEAL" then
        kind = "tick"
    elseif spellID and SD.spells[spellID] then
        if SD.spells[spellID].family == "Lifebloom" then kind = "bloom" end
    elseif spellID then
        local resolved = SD:Resolve(spellID)
        local row = SD.spells[resolved]
        if resolved ~= spellID and row and row.family == "Lifebloom" then
            attrID, kind = resolved, "bloom"
        end
    end

    local wasted = 0
    if ST.Overheal then wasted = ST.Overheal:Record(attrID, kind, amount, overheal, destGUID, destName) end

    -- one convention for the whole addon (Engine/Overheal.lua): whether the
    -- log's "amount" already includes the overheal is a client property,
    -- latched from the first full overheal seen. (A function call inside
    -- "a and f() or b" is truncated to ONE value -- the bug v0.5.3 already
    -- fixed once in this file; write the if out.)
    local effective, gross
    if ST.Overheal then
        effective, gross = ST.Overheal:Split(amount, overheal)
    else
        effective, gross = amount, amount + overheal
    end

    if ST.Calibration then
        ST.Calibration:Observe(attrID, kind, gross, critical, destGUID)
    end

    -- Ticks are credited to the cast record that applied the HoT.
    if kind == "tick" and destGUID and destGUID ~= "" then
        local sd = SD.spells[spellID]
        local h = sd and Rec.hots[HotKey(destGUID, sd.family)]
        if h then
            h.ticksSeen = h.ticksSeen + 1
            h.tickGross = h.tickGross + gross
            h.tickOver = h.tickOver + (gross - effective)
        end
    end

    if fight then
        fight.healed = fight.healed + effective
        fight.overhealed = fight.overhealed + (gross - effective)
        fight.wastedMana = (fight.wastedMana or 0) + wasted
    end

    -- Debug "heal": every heal and HoT tick the player lands, exactly as the
    -- combat log reported it (whether "amount" already includes the overheal
    -- is the client property Engine/Overheal.lua latches). This is how heal
    -- formulas get verified in-game (Tree aura, Lifebloom bloom, relics).
    if ST.db and ST.db.debug and ST.db.debug.enabled and ST.db.debug.categories.heal then
        ST:Debug("heal", "%s (%d)%s on %s: %d%s%s%s", spellName or "?", spellID or 0,
            subevent == "SPELL_PERIODIC_HEAL" and " tick" or "", destName or "?", amount,
            overheal > 0 and string.format(" (%d overheal)", overheal) or "",
            critical and " CRIT" or "", ST:InTreeForm() and " [tree]" or "")
    end
end)

ST:On("PLAYER_REGEN_DISABLED", function()
    local now = GetTime()
    PruneHots(now)
    fight = {
        start = now,
        startMana = UnitPower("player", 0),
        healed = 0,
        overhealed = 0,
        oomAt = nil,
        casts = {},
        ownCasts = 0,
        precasts = {},
        lowestMana = 1,
    }
    -- Freeze each pre-pull HoT's tick accounting at the pull: what those HoTs
    -- overhealed BEFORE the fight started is the prehot measurement; whatever
    -- they tick for afterwards belongs to the fight.
    for i = 1, #Rec.ring do
        local c = Rec.ring[i]
        c.preGross, c.preOver = c.tickGross or 0, c.tickOver or 0
        fight.precasts[i] = c
    end
    ST:Debug("combat", "pull: mana %d/%d, regen base %.2f casting %.2f, zone %s",
        fight.startMana, UnitPowerMax("player", 0), ST.Regen.base, ST.Regen.casting,
        GetRealZoneText and GetRealZoneText() or "?")
    ST:Debug("sim", "pull: %d cast(s) in the last %ds carried into the fight", #fight.precasts, RING_WINDOW)
    if ST.FightRecorder then ST.FightRecorder:Start(now) end
    if ST.Targets then ST:Debug("combat", "roster: %s", ST.Targets:RosterLine()) end
end)

-- OOM detection (below 2% counts as dry) and the fight's mana low-water mark.
ST:OnTick(function()
    if not fight then return end
    if ST.FightRecorder then ST.FightRecorder:Tick() end
    local manaMax = UnitPowerMax("player", 0)
    if manaMax <= 0 then return end
    local frac = UnitPower("player", 0) / manaMax
    if frac < fight.lowestMana then fight.lowestMana = frac end
    if not fight.oomAt and frac <= 0.02 then
        fight.oomAt = GetTime() - fight.start
    end
end)

local function FmtClock(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function FmtMana(v)
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return string.format("%d", v + 0.5)
end

local function FamilyLabel(fam)
    local f = SD.families[fam]
    return (f and f.label) or fam
end

-- Family counts as "Lifebloom 9, Rejuvenation 4, Regrowth 1", descending by
-- count, at most `top` entries.
local function FamilyList(counts, top)
    local list = {}
    for fam, n in pairs(counts) do list[#list + 1] = { fam, n } end
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    local out = {}
    for i = 1, math.min(top or 3, #list) do
        out[#out + 1] = string.format("%s %d", FamilyLabel(list[i][1]), list[i][2])
    end
    return table.concat(out, ", ")
end

--------------------------------------------------------------------------------
-- Plan-free labels (SPEC-v0.7 §2.2): exactly one per own cast, in this
-- precedence -- utility, shift, early, overheal, ok -- and none of it needs a
-- simulator. Their mana must add up to what the fight spent; the identity is
-- checked in the "sim" debug category, because a label set that does not
-- account for every point of mana would quietly mislead the Review tab.
--------------------------------------------------------------------------------
local LABEL_KEYS = { "utility", "shift", "early", "overheal", "ok" }

local function LabelFight(f, fullHp)
    local labels, labelCasts = {}, {}
    for _, k in ipairs(LABEL_KEYS) do labels[k], labelCasts[k] = 0, 0 end
    local hpBuckets = { 0, 0, 0, 0 }
    local aboveCount, aboveMana, healCasts = 0, 0, 0
    local aboveFams, buffs = {}, {}

    for _, c in ipairs(f.casts) do
        local mana = c.cost > 0 and c.cost or 0
        local label
        if c.kind == "utility" then
            label = "utility"
            local name = GetSpellInfo(c.spellID)
            if name and BUFF_NAMES[name] then
                buffs[#buffs + 1] = { name = name, at = c.t - f.start }
            end
        elseif c.kind == "shift" then
            label = "shift"
        elseif c.early then
            label = "early"
        elseif c.hpAtCast >= fullHp then
            label = "overheal"
        else
            label = "ok"
        end
        labels[label] = labels[label] + mana
        labelCasts[label] = labelCasts[label] + 1

        -- HP buckets and the "above full" clause are a fact about the target's
        -- health, independent of which label won the precedence: a Rejuvenation
        -- refreshed early on a full-health tank is both.
        if c.kind == "heal" then
            healCasts = healCasts + 1
            local hp = c.hpAtCast
            local b
            if hp < 0 then b = 4 elseif hp < 0.5 then b = 1 elseif hp < fullHp then b = 2 else b = 3 end
            hpBuckets[b] = hpBuckets[b] + 1
            if b == 3 then
                aboveCount, aboveMana = aboveCount + 1, aboveMana + mana
                local sd = SD.spells[c.spellID]
                local fam = sd and sd.family or "other"
                aboveFams[fam] = (aboveFams[fam] or 0) + 1
            end
        end
    end

    return labels, labelCasts, hpBuckets, aboveCount, aboveMana, healCasts, aboveFams, buffs
end

-- prehot: HoTs put on an already-full target before the pull, whose ticks
-- landed before the fight even started and mostly went nowhere. Its mana sits
-- outside the fight's spend, which is exactly why it is reported separately.
local function PreHot(f, fullHp)
    local mana, gross, over, fams = 0, 0, 0, {}
    for _, c in ipairs(f.precasts) do
        if c.kind == "heal" and c.hpAtCast >= 0.95 and (c.preGross or 0) > 0
           and c.preOver / c.preGross >= 0.5 then
            mana = mana + (c.cost > 0 and c.cost or 0)
            gross, over = gross + c.preGross, over + c.preOver
            local sd = SD.spells[c.spellID]
            local fam = sd and sd.family or "other"
            fams[fam] = (fams[fam] or 0) + 1
        end
    end
    return mana, gross, over, fams
end

ST:On("PLAYER_REGEN_ENABLED", function()
    if not fight then return end
    local f = fight
    fight = nil
    PruneHots(GetTime())

    local duration = GetTime() - f.start
    local SPEND = ST.Spend
    if duration < 15 or SPEND.combat.spent <= 0 then
        ST:Debug("combat", "end: %.0fs, spent %d - too short to record", duration, SPEND.combat.spent)
        if ST.FightRecorder then ST.FightRecorder:Finish(duration) end
        return
    end

    local endMana = UnitPower("player", 0)
    local netMp5 = (endMana - f.startMana) / duration * 5
    local avgSpendRate = SPEND.combat.spent / duration

    -- spend by family, biggest first, for the "where did it go" clause
    local SHORT = { Lifebloom = "LB", Rejuvenation = "RJ", Regrowth = "RG", HealingTouch = "HT",
                    Swiftmend = "SM", Tranquility = "TQ", other = "other" }
    local fams = {}
    for fam, mana in pairs(SPEND.combat.byFamily) do fams[#fams + 1] = { fam, mana } end
    table.sort(fams, function(a, b) return a[2] > b[2] end)
    local breakdown = {}
    for i = 1, math.min(4, #fams) do
        breakdown[#breakdown + 1] = string.format("%s %d%%", SHORT[fams[i][1]] or fams[i][1],
            fams[i][2] / SPEND.combat.spent * 100 + 0.5)
    end

    local parts = {
        FmtClock(duration),
        string.format("net %+d mp5", netMp5),
        string.format("spent %.1fk%s", SPEND.combat.spent / 1000,
            #breakdown > 0 and (" (" .. table.concat(breakdown, ", ") .. ")") or ""),
    }
    if (f.wastedMana or 0) > 0 then
        parts[#parts + 1] = string.format("~%.1fk into full health", f.wastedMana / 1000)
    end
    if f.healed + f.overhealed > 0 then
        parts[#parts + 1] = string.format("overheal %d%%",
            f.overhealed / (f.healed + f.overhealed) * 100)
    end
    local realized = ST.Regen:CombatSpiritRealized()
    if realized then
        parts[#parts + 1] = string.format("spirit regen realized %d%%", realized * 100)
    end
    -- T99 (docs/SPEC-next.md 4.4): "max rank" is the rank table's, the class
    -- profile's `rankTable` capability (T123: the druid's, and a priest's,
    -- shaman's or paladin's on TBC); Engine/SpendTracker.lua counts it
    -- through RankMath:Source(), so it is the class's own book's max rank
    if ST.ClassProfile:Can("rankTable") and SPEND.combat.casts > 0 then
        parts[#parts + 1] = string.format("max-rank casts %d%%",
            SPEND.combat.maxRankCasts / SPEND.combat.casts * 100)
    end
    if f.oomAt then
        parts[#parts + 1] = "|cffff4444OOM at " .. FmtClock(f.oomAt) .. "|r"
    end

    local summary = table.concat(parts, " || ") -- ASCII only; default WoW fonts lack many glyphs
    ST:Debug("combat", "end: %s (casts %d, healed %d, overhealed %d)", summary, SPEND.combat.casts, f.healed, f.overhealed)
    if ST.Overheal then
        for _, line in ipairs(ST.Overheal:Summary()) do
            ST:Debug("combat", "  overheal %s", line)
        end
    end
    ST:Print(summary)

    ----------------------------------------------------------------------------
    -- The v0.7.0 line: where the casts went, not just where the mana went.
    ----------------------------------------------------------------------------
    local fullHp = (ST.db and ST.db.simFullHp) or 0.85
    local labels, labelCasts, hpBuckets, aboveCount, aboveMana, healCasts, aboveFams, buffs
        = LabelFight(f, fullHp)
    local prehotMana, prehotGross, prehotOver, prehotFams = PreHot(f, fullHp)

    local labelled = 0
    for _, k in ipairs(LABEL_KEYS) do labelled = labelled + labels[k] end
    ST:Debug("sim", "labels: %s = %d (fight spend %d, delta %+d)",
        (function()
            local t = {}
            for _, k in ipairs(LABEL_KEYS) do
                t[#t + 1] = string.format("%s %d/%d", k, labels[k], labelCasts[k])
            end
            return table.concat(t, ", ")
        end)(), labelled, SPEND.combat.spent, labelled - SPEND.combat.spent)
    if math.abs(labelled - SPEND.combat.spent) > math.max(50, SPEND.combat.spent * 0.02) then
        ST:Debug("sim", "label identity BROKEN: %d labelled vs %d spent over %d own cast(s)",
            labelled, SPEND.combat.spent, f.ownCasts)
    end

    if f.ownCasts >= 4 then
        local extra = ""
        local support = labels.utility + labels.shift
        if support > 0 then
            extra = extra .. " - utility/shifts " .. FmtMana(support)
        end
        if #buffs > 0 then
            local shown = {}
            for i = 1, math.min(2, #buffs) do
                shown[#shown + 1] = string.format("%s at %s", buffs[i].name, FmtClock(buffs[i].at))
            end
            extra = extra .. " - buffed in combat: " .. table.concat(shown, ", ")
            if #buffs > 2 then extra = extra .. string.format(" (+%d more)", #buffs - 2) end
        end
        -- With nothing above the line the mana and family clauses would render
        -- as "(0): " -- say the good news plainly instead.
        local head
        if aboveCount > 0 then
            head = string.format("%d of %d casts on targets above %d%% (%s): %s",
                aboveCount, healCasts, fullHp * 100 + 0.5, FmtMana(aboveMana),
                FamilyList(aboveFams, 3))
        else
            head = string.format("no casts on targets above %d%% (%d heal casts)",
                fullHp * 100 + 0.5, healCasts)
        end
        ST:Print(head .. extra)
        if prehotMana > 0 then
            ST:Print(string.format("pre-pull HoTs on full targets: %s (%d%% overheal)",
                FmtMana(prehotMana) .. " in " .. FamilyList(prehotFams, 3),
                prehotOver / prehotGross * 100 + 0.5))
        end
    end

    local stream
    if ST.FightRecorder then stream = ST.FightRecorder:Finish(duration, labels) end

    -- Fights with almost no casting say nothing about how the healer played and
    -- would poison both the spend seed and the habit counts, so they are not
    -- kept at all (SPEC-v0.7 §2.3).
    if f.ownCasts < 4 then
        ST:Debug("combat", "end: %.0fs but only %d own cast(s) - not recorded", duration, f.ownCasts)
        return
    end

    ST.fightHistory[#ST.fightHistory + 1] = {
        t = time(),
        duration = duration,
        avgSpendRate = avgSpendRate,
        netMp5 = netMp5,
        oomAt = f.oomAt,
        healed = f.healed,
        overhealed = f.overhealed,
        wastedMana = f.wastedMana,
        byFamily = (function() local t = {} for k, v in pairs(SPEND.combat.byFamily) do t[k] = v end return t end)(),
        zone = GetRealZoneText and GetRealZoneText() or nil,
        summary = summary,
        -- v0.7.0
        labels = labels,
        labelCasts = labelCasts,
        hpBuckets = hpBuckets,
        prehot = prehotMana,
        foreignShare = stream and stream.foreignShare or nil,
        lowestMana = f.lowestMana,
        ownCasts = f.ownCasts,
        streamID = stream and stream.id or nil,
    }
    if #ST.fightHistory > MAX_HISTORY then
        table.remove(ST.fightHistory, 1)
    end
    ST:Fire("FIGHT_RECORDED")
end)
