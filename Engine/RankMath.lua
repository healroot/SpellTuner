-- Rank math: per-rank effective heal / HPM / HPS with TBC downranking rules.
-- Formulas (per the design debate, confidence noted in docs/DECISIONS.md):
-- the coefficient rules -- direct (the base cast over 3.5 s), HoT (the
-- duration over 15 s), the hybrid's amount-weighted split, the sub-level-20
-- malus, the downrank penalty and the group rule -- are Spells/Coefficients.lua's
-- (T117: moved there, the numbers unchanged, so Forever's book estimates by
-- the same rules); healing crits are 1.5x, HoTs never crit.
-- Penalties apply to the BONUS-healing contribution, not the base heal.
--
-- Structure (docs/DESIGN-v0.5.md §1.3): Context() resolves every input once
-- (simulation overrides are applied THERE and nowhere else), RowFor() turns one
-- spell into one row, Compute() runs every family plus the Pareto/suggestion
-- pass, and Explain() rebuilds a single row with its intermediate terms for the
-- dashboard tooltip. RowFor only allocates row.calc when asked, because the
-- dashboard re-renders every 2s and those tables would be pure garbage.
local _, MD = ...

local RankMath = {}
MD.RankMath = RankMath

local EMPTY = {}

local function BonusHealing()
    if GetSpellBonusHealing then
        local ok, v = pcall(GetSpellBonusHealing)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

local function NatureCrit()
    if GetSpellCritChance then
        local ok, v = pcall(GetSpellCritChance, 4) -- 4 = nature school
        if ok and type(v) == "number" then return v / 100 end
    end
    return 0
end

-- T117: the coefficient rules are Spells/Coefficients.lua's (read at run time:
-- it loads before this file on the TBC TOC, but nothing here needs it at load).
local function Coef() return MD.Coefficients end

-- Chain-casts until the next cast is unaffordable: each cast nets
-- (cost - regen * interval) mana, so floor((mana - cost) / net) + 1 casts.
-- math.huge when regen covers the cost, 0 when mana < cost.
-- T67 (P23, review A13): the rule is Spells/RankRules.lua's, shared with the
-- Forever book; this method stays for its callers (RegenMeasure, SimSelfTest).
function RankMath:CastsToOOM(cost, interval, mana, regen)
    return MD.RankRules.CastsToOOM(cost, interval, mana, regen)
end

-- T67: the dashboard's rows for Spells/RankRules.lua -- heal per mana and per
-- second, the heal the floor is a share of, and only known real ranks (the
-- rolling-stack Lifebloom rows are virtual: a different activity).
local RULE_FIELDS = {
    eff = "hpm", rate = "hps", value = "heal",
    eligible = function(r) return r.known and not r.virtual end,
}
RankMath.RULE_FIELDS = RULE_FIELDS -- read by tools/bookcheck.lua's tbc run

--------------------------------------------------------------------------------
-- Context: every input the rank math reads, resolved once.
--
-- Tree of Life aura: party members (the tree included) receive extra healing
-- equal to 25% of the druid's Spirit. It is a "healing received" aura on the
-- targets, so GetSpellBonusHealing() never shows it, but it goes through the
-- same coefficient/penalty path as +healing (MaNGOS-era SpellHealingBonus:
-- taken advertised benefit * coeff). Counted while in form unless the setting
-- is off; only true for targets in your party.
--
-- Simulation overrides (MD.sim, session-only, set from the dashboard's
-- "Simulate" strip): nil = live value. Only the rank math reads them; the
-- clock, widget and advisor always use real inputs.
--------------------------------------------------------------------------------
-- opts.live: ignore the Simulate strip. Calibration compares REAL heals with
-- the model and must never see a what-if input (the first regression log had
-- it predicting Regrowth at 1488 against a real 1282 -- a simulated +healing
-- was still in the strip).
function RankMath:Context(opts)
    -- T111: a class Data/SpellData.lua does not cover reads its own book
    -- (Spells/Book_TBC.lua) under the class rules (ClassContext, below) --
    -- only once its profile grants the rank table (RankMath:IsClassBook)
    if RankMath:IsClassBook() then return RankMath.ClassContext(opts, RankMath:Source()) end
    return RankMath:DruidContext(opts)
end

-- T111: the druid's context over Data/SpellData.lua, whoever is logged in --
-- what RankMath:Context answered for every class before T111, and what the
-- kit (RankMath:SpellKit) is still built from (decision 8 (b): the TBC engine
-- stays the druid's).
function RankMath:DruidContext(opts)
    local SD = MD.SpellData
    -- opts.healer (v0.7.1): the simulator's own stat overrides, applied exactly
    -- where the Simulate strip's are and nowhere else, so a simulated healer
    -- and a simulated dashboard row go down one code path. `inTree` is the
    -- strip's `tree` under the name the scenario uses.
    local sim
    if opts and opts.healer then
        local h = opts.healer
        sim = { heal = h.heal, crit = h.crit, casting = h.casting, base = h.base,
                mana = h.mana, tree = h.inTree, moonglow = h.moonglow }
        if next(sim) == nil then sim = EMPTY end
    elseif opts and opts.live then
        sim = EMPTY
    else
        sim = MD.sim or EMPTY
    end

    local liveBonus = BonusHealing()
    local statBonus = sim.heal or liveBonus
    local relic = SD:Relic()

    -- A simulated form changes the aura AND the costs; keep the two in step.
    local inTree
    if sim.tree ~= nil then inTree = sim.tree else inTree = MD:InTreeForm() end

    local treeAura = 0
    if inTree and not (MD.db and MD.db.treeAura == false) then
        treeAura = 0.25 * (UnitStat("player", 5) or 0) + (relic and relic.aura or 0)
    end

    local liveCrit = NatureCrit()
    local crit = sim.crit and (sim.crit / 100) or liveCrit

    -- Chain-cast budget: every cast nets (cost - castingRegen * interval);
    -- from the current mana that allows floor((mana - cost) / net) + 1 casts
    -- (interval = cast time, or the 1.5s GCD for instants). Casting regen is
    -- the in-5SR rate (Intensity, gear mp5, Dreamstate) since spamming keeps
    -- you inside the five-second rule the whole time.
    local liveMana = UnitPower("player", 0) or 0
    local liveCasting = MD.Regen and MD.Regen.casting or 0
    local liveBase = MD.Regen and MD.Regen.base or 0

    local ctx = {
        bonus = statBonus + treeAura,
        statBonus = statBonus,
        treeAura = treeAura,
        inTree = inTree,
        relic = relic,
        crit = crit,
        playerLevel = MD.player.level,
        mana = sim.mana or liveMana,
        castingRegen = sim.casting and (sim.casting / 5) or liveCasting,
        baseRegen = sim.base and (sim.base / 5) or liveBase,

        goN = 1 + 0.02 * MD:TalentRank("Gift of Nature"),
        empTouch = 1 + 0.10 * MD:TalentRank("Empowered Touch"),
        empRejuv = 1 + 0.04 * MD:TalentRank("Empowered Rejuvenation"),
        impRejuv = 1 + 0.05 * MD:TalentRank("Improved Rejuvenation"),
        naturalist = 0.1 * MD:TalentRank("Naturalist"), -- -0.1s HT cast per rank

        simulated = next(sim) ~= nil,
        live = { heal = liveBonus, crit = liveCrit * 100, casting = liveCasting * 5,
                 base = liveBase * 5, mana = liveMana },
    }
    ctx.regrowthCrit = math.min(1, crit + 0.10 * MD:TalentRank("Improved Regrowth"))

    -- Nature's Grace: a spell critical takes 0.5s off the NEXT cast, never
    -- below the 1.5s GCD. Chain-casting one spell, the fraction of casts that
    -- follow a crit is the crit chance, so the throughput-correct cast time is
    -- the MIXTURE -- not (cast - 0.5 * crit) floored, which clips the wrong
    -- branch when cast - 0.5 lands on the GCD. Throughput over a chain is
    -- heal / E[T] exactly, so averaging the cast time is right for a sustained
    -- column. HoTs never crit and sit at the GCD anyway, so it is a no-op for
    -- them twice over. Assumed 0.5s until the "cast" debug category confirms
    -- it on this client (docs/DESIGN-v0.5.md F1).
    ctx.naturesGrace = (MD:TalentRank("Nature's Grace") > 0
        and not (MD.db and MD.db.naturesGrace == false)) and 0.5 or 0
    ctx.ExpectedCast = function(T0, p)
        if ctx.naturesGrace <= 0 or p <= 0 then return T0 end
        return (1 - p) * T0 + p * math.max(T0 - ctx.naturesGrace, 1.5)
    end

    -- Cost source. The live client value is exact (it applies talents and form
    -- itself), so it stays the default. It is wrong the moment the dashboard
    -- simulates a form or a talent rank the player does not actually have, and
    -- only then does the static table (with those overrides) take over.
    local costOverride = (sim.tree ~= nil) or (sim.moonglow ~= nil)
    ctx.costCtx = costOverride and { inTree = inTree, moonglow = sim.moonglow } or nil
    ctx.CostFor = function(id)
        if ctx.costCtx then
            return SD:StaticCost(id, ctx.costCtx), "table (simulated)"
        end
        return SD:GetCost(id)
    end

    ctx.CastsToOOM = function(cost, interval)
        return RankMath:CastsToOOM(cost, interval, ctx.mana, ctx.castingRegen)
    end

    return ctx
end

--------------------------------------------------------------------------------
-- One row from one spell.
--   variant  nil for the real rank; 2 or 3 for the rolling Lifebloom stacks
--   explain  fills row.calc with every intermediate term (tooltip only)
-- Row: { id, rank, level, cost, cast, heal, hpm, hps, casts (chain-casts to
-- OOM from current mana, math.huge when regen covers the cost), known, isMax;
-- overheal + effHeal/effHpm/effHps when the combat log has enough samples;
-- dominated/suggested are set by Compute() }
-- HP5 ("sustained healing per 5s") was removed in v0.6.0: chain-casting inside
-- the 5SR it reduces to 5 x castingRegen x HPM, so it ordered every rank
-- exactly like HPM and carried no information of its own.
--------------------------------------------------------------------------------
function RankMath:RowFor(spellID, ctx, variant, explain)
    if ctx.class then return RankMath.ClassRow(spellID, ctx, explain) end
    local SD = MD.SpellData
    local s = SD.spells[spellID]
    if not s then return nil end
    local info = SD.families[s.family]
    if not info then return nil end

    local C = Coef()
    local pen = C.Penalty(s.level, ctx.playerLevel)
    local relic = ctx.relic
    -- relic bonus for this family: flat goes on the BASE heal, perTick on
    -- each Lifebloom tick
    local relicFlat = (relic and relic.family == s.family and relic.flat) or 0
    local relicTick = (relic and relic.family == s.family and relic.perTick) or 0
    local relicCast = (relic and relic.family == s.family and relic.castReduce) or 0
    local bonus = ctx.bonus

    local heal, castTime, calc

    local castBase, ngCrit
    -- Lifebloom's two halves, kept for the overheal weighting below. These
    -- were GLOBALS until v0.7.1 -- harmless by luck (only the lifebloom branch
    -- reads them, and it always writes them first) but a _G write on a path
    -- the dashboard runs every 2s.
    local lbHot, lbBloom

    if info.type == "direct" then
        castBase = math.max(s.cast - ctx.naturalist - relicCast, 1.5)
        ngCrit = ctx.crit
        castTime = ctx.ExpectedCast(castBase, ngCrit)
        -- the coefficient uses the spell's BASE cast time, not the modified one
        local coef = C.Direct(s.cast)
        local base = (s.healMin + s.healMax) / 2 + relicFlat
        local bonusOut = bonus * coef * pen * ctx.empTouch
        local critMult = 1 + 0.5 * ctx.crit
        heal = (base + bonusOut) * ctx.goN * critMult
        if explain then
            calc = { kind = "direct", base = (s.healMin + s.healMax) / 2, relicFlat = relicFlat,
                     bonus = bonus, coef = coef, penalty = pen, bonusMult = ctx.empTouch,
                     bonusMultName = "Empowered Touch", bonusOut = bonusOut,
                     talentMult = ctx.goN, critMult = critMult, crit = ctx.crit,
                     -- v0.14.9: the non-crit roll range, for the spell tooltip
                     min = (s.healMin + relicFlat + bonusOut) * ctx.goN,
                     max = (s.healMax + relicFlat + bonusOut) * ctx.goN }
        end

    elseif info.type == "hot" then
        castTime = 1.5 -- GCD
        local coef = C.Hot(s.hotDuration)
        local bonusOut = bonus * coef * pen * ctx.empRejuv
        heal = (s.hotTotal + relicFlat + bonusOut) * ctx.goN * ctx.impRejuv
        if explain then
            calc = { kind = "hot", base = s.hotTotal, relicFlat = relicFlat,
                     bonus = bonus, coef = coef, penalty = pen, bonusMult = ctx.empRejuv,
                     bonusMultName = "Empowered Rejuvenation", bonusOut = bonusOut,
                     talentMult = ctx.goN * ctx.impRejuv,
                     duration = s.hotDuration, ticks = s.hotDuration / 3 }
        end

    elseif info.type == "hybrid" then
        castBase = math.max(s.cast, 1.5)
        ngCrit = ctx.regrowthCrit
        castTime = ctx.ExpectedCast(castBase, ngCrit)
        -- The hybrid's +healing is split between the direct hit and the HoT in
        -- proportion to their BASE AMOUNTS, each portion then taking its own
        -- coefficient: direct gets c x avg/(avg+hot), the HoT h x hot/(avg+hot)
        -- (T117: Spells/Coefficients.lua's Hybrid).
        -- For Regrowth that is 0.286 / 0.70 -- the widely quoted numbers. The
        -- earlier coefficient-weighted split (c^2/(c+h), h^2/(c+h) = 0.166 /
        -- 0.994) predicted a 232 tick where the first regression log showed
        -- 209; the amount-weighted split predicts 209.3 (docs/DECISIONS.md
        -- v0.6 §15). Calibration confirms or refutes it with the next run.
        local avgBase = (s.healMin + s.healMax) / 2
        local dCoef, hCoef = C.Hybrid(s.cast, s.hotDuration, avgBase, s.hotTotal)
        local base = avgBase + relicFlat
        local dBonus = bonus * dCoef * pen
        local hBonus = bonus * hCoef * pen * ctx.empRejuv
        local critMult = 1 + 0.5 * ctx.regrowthCrit
        local direct = (base + dBonus) * ctx.goN * critMult
        local hot = (s.hotTotal + hBonus) * ctx.goN
        heal = direct + hot
        if explain then
            calc = { kind = "hybrid", base = (s.healMin + s.healMax) / 2, relicFlat = relicFlat,
                     bonus = bonus, penalty = pen, talentMult = ctx.goN,
                     directCoef = dCoef, directBonus = dBonus, direct = direct,
                     hotCoef = hCoef, hotBonus = hBonus, hot = hot, hotBase = s.hotTotal,
                     bonusMult = ctx.empRejuv, bonusMultName = "Empowered Rejuvenation",
                     critMult = critMult, crit = ctx.regrowthCrit,
                     duration = s.hotDuration,
                     -- v0.14.9: the direct hit's non-crit roll range
                     min = (s.healMin + relicFlat + dBonus) * ctx.goN,
                     max = (s.healMax + relicFlat + dBonus) * ctx.goN }
        end

    elseif info.type == "lifebloom" then
        castTime = 1.5 -- GCD
        -- One application ticking to completion plus its bloom.
        -- Verified 2026-09-03 (heal log): tick 87 = (273 + 450*0.5187*1.2)*1.1/7,
        -- bloom 864 = (600 + 450*0.3422*1.2)*1.1 -> Empowered Rejuvenation
        -- applies to the bloom too.
        local hotBonus = bonus * SD.lifebloomHotCoef * pen * ctx.empRejuv
        local bloomBonus = bonus * SD.lifebloomBloomCoef * pen * ctx.empRejuv
        -- Emerald Queen is "+88 to the periodic healing": on the HoT TOTAL,
        -- like any flat, not on the bloom
        local hot = (s.hotTotal + relicFlat + 7 * relicTick + hotBonus) * ctx.goN
        local bloom = (s.bloom + bloomBonus) * ctx.goN
        lbHot, lbBloom = hot, bloom
        if variant then
            -- Rolling stacks: each refresh cast is paid for with 6 ticks at the
            -- stack's multiplier (one tick is lost to the refresh) and never a
            -- bloom (the stack is renewed before it expires).
            heal = (hot / 7) * 6 * variant
        else
            heal = hot + bloom
        end
        if explain then
            calc = { kind = "lifebloom", base = s.hotTotal, relicTick = relicTick, relicFlat = relicFlat,
                     bonus = bonus, penalty = pen, bonusMult = ctx.empRejuv,
                     bonusMultName = "Empowered Rejuvenation", talentMult = ctx.goN,
                     hotCoef = SD.lifebloomHotCoef, hotBonus = hotBonus, hot = hot,
                     bloomCoef = SD.lifebloomBloomCoef, bloomBonus = bloomBonus,
                     bloomBase = s.bloom, bloom = bloom,
                     tick = hot / 7, stacks = variant, duration = s.hotDuration,
                     -- the bloom is a direct heal and can crit (a recorded bloom
                     -- crit is exactly 1.5x); the ticks cannot. Not `crit`:
                     -- Calibration reads that as the whole spell's chance.
                     bloomCrit = ctx.crit }
        end
    end

    if not heal then return nil end

    local cost, costSource = ctx.CostFor(spellID)
    cost = cost or 0

    local row = {
        id = spellID, rank = s.rank, level = s.level,
        cost = cost, cast = castTime, heal = heal,
        hpm = cost > 0 and heal / cost or 0,
        hps = heal / castTime,
        casts = ctx.CastsToOOM(cost, castTime),
        known = SD.knownSet[spellID] or false,
        isMax = (not variant) and SD.maxRank[s.family] == spellID or false,
        ng = castBase ~= nil and castTime < castBase - 0.001 or false,
    }
    if variant then
        row.variant = variant
        row.rankLabel = "x" .. variant
        row.virtual = true
    end

    -- Overheal calibration: what the spell is worth on the targets this player
    -- actually heals. Carried alongside the raw numbers, never instead of them
    -- -- the Pareto filter and the suggested rank stay on raw values so a noisy
    -- measurement can never fire a "rebind?" toast (docs/DESIGN-v0.5.md F3).
    if MD.Overheal then
        local done = false
        -- Lifebloom: ticks and the bloom overheal very differently (38% vs 50%
        -- in the first dungeon log), and a rolling stack has no bloom at all.
        -- So the single cast is weighted portion by portion and the rolling
        -- rows by the tick fraction only -- which is what finally makes the
        -- "roll it or let it bloom" question answerable for THIS player.
        if info.type == "lifebloom" and lbHot then
            local tf, tn, tscope = MD.Overheal:KindFraction(spellID, "tick")
            local bf, bn, bscope = MD.Overheal:KindFraction(spellID, "bloom")
            if tf and tscope == "kind" and (variant or (bf and bscope == "kind")) then
                local eff
                if variant then
                    eff = row.heal * (1 - tf)
                else
                    eff = lbHot * (1 - tf) + lbBloom * (1 - bf)
                end
                row.overheal = { frac = 1 - eff / row.heal, n = math.min(tn, bn or tn), scope = "kind",
                                 tick = tf, bloom = (not variant) and bf or nil }
                row.effHeal = eff
                row.effHpm = row.cost > 0 and eff / row.cost or 0
                row.effHps = eff / castTime
                done = true
            end
        end
        if not done then
            local frac, n, scope = MD.Overheal:Fraction(spellID)
            if frac then
                local k = 1 - frac
                row.overheal = { frac = frac, n = n, scope = scope }
                row.effHeal = row.heal * k
                row.effHpm = row.hpm * k
                row.effHps = row.hps * k
            end
        end
    end

    if calc then
        calc.family = s.family
        calc.label = info.label
        calc.type = info.type
        calc.cost = cost
        calc.costSource = costSource
        calc.castBase = castBase or castTime
        calc.castNG = castTime
        calc.ngCrit = ngCrit
        calc.naturesGrace = ctx.naturesGrace
        calc.mana = ctx.mana
        calc.castingRegen = ctx.castingRegen
        calc.baseRegen = ctx.baseRegen
        calc.netPerCast = cost - ctx.castingRegen * castTime
        calc.overheal = row.overheal
        row.calc = calc
    end
    return row
end

--------------------------------------------------------------------------------
-- SpellKit (v0.7.1): every known rank of every family, priced and valued once
-- per form, in the flat shape the simulator's inner loop reads. The engine must
-- never call RowFor -- it allocates, reads the live client and would be run
-- thousands of times inside a search -- so this is the single boundary between
-- the rank math and the simulation (docs/SPEC-v0.7.md 3.1).
--
-- The entry's shape is Engine/Kit.lua's Kit.FIELDS (T63, P19: this comment
-- was its only statement until then); the builder ends with Kit.Check, so a
-- field this function forgets or misspells fails here, not inside a search.
--
-- Crit is stripped from `direct` on purpose: RowFor bakes E[crit] in for a
-- throughput column, but the engine decides per cast whether to use the
-- expectation or a seeded roll, and it cannot un-bake a multiplier it did not
-- apply.
--------------------------------------------------------------------------------
local KIT_FORMS = { "caster", "tree" }

-- TBC Swiftmend: consumes Regrowth for 18s of its ticks, else Rejuvenation for
-- 12s (Rejuvenation's whole duration). Valued off the highest known rank of
-- each, which is what a healer would actually have out.
local SWIFTMEND_REJUV_SECONDS, SWIFTMEND_REGROWTH_SECONDS = 12, 18

-- T96 (docs/SPEC-next.md 2.1, S1 step 2): this kit is the druid's -- every
-- family it holds is Data/SpellData.lua's, which is the druid's table -- so it
-- is stamped with the druid profile, named, and each family's own cooldown
-- comes from that profile (Swiftmend's 15 s), the engine's per-family
-- cooldown table (SM.CooldownOf reads the entry first). Read by name, never
-- MD.ClassProfile: whoever is logged in, SpellData is the druid's.
local KIT_PROFILE = "DRUID"
local function FamilyCooldown(family)
    local P = MD.Profiles
    local p = P and P.byClass and P.byClass[KIT_PROFILE]
    local def = p and p.families and p.families[family]
    return def and def.cooldown or nil
end

-- T111: the kit is the druid's, from Data/SpellData.lua, for every class
-- (decision 8 (b): tables and tooltips only, the TBC coach stays the
-- druid's) -- a priest's Review validation and replay run on the kit they ran
-- on before T111. RankMath.ClassKit (below) builds a class's own kit; only the
-- offline tools call it.
function RankMath:SpellKit(opts)
    local SD = MD.SpellData
    local kit = { caster = {}, tree = {}, profile = KIT_PROFILE }

    for _, form in ipairs(KIT_FORMS) do
        local healer = { inTree = (form == "tree") }
        if opts and opts.healer then
            for k, v in pairs(opts.healer) do healer[k] = v end
            healer.inTree = (form == "tree")
        end
        local ctx = RankMath:DruidContext({ live = true, healer = healer })
        local out = kit[form]

        for family, list in pairs(SD.known) do
            local info = SD.families[family]
            for _, id in ipairs(list) do
                local s = SD.spells[id]
                local e = { family = family, rank = s.rank, type = info and info.type or "direct",
                            gcd = 1.5 }
                local row = RankMath:RowFor(id, ctx, nil, true)
                local c = row and row.calc
                if c then
                    e.cost, e.cast = row.cost, row.cast
                    -- v0.15.0: the cast bar a player actually waits through. `cast`
                    -- averages Nature's Grace in, which is right for throughput and
                    -- wrong for a bar on screen (Engine/Practice.lua)
                    e.castBase = c.castBase
                    if c.kind == "direct" then
                        e.direct = row.heal / (c.critMult or 1)
                        e.directCrit = c.crit or 0
                    elseif c.kind == "hot" then
                        e.ticks = c.ticks
                        e.tickPeriod, e.duration = 3, c.duration
                        e.tick = row.heal / c.ticks
                    elseif c.kind == "hybrid" then
                        e.direct = c.direct / (c.critMult or 1)
                        e.directCrit = c.crit or 0
                        e.ticks = c.duration / 3
                        e.tickPeriod, e.duration = 3, c.duration
                        e.tick = c.hot / e.ticks
                    elseif c.kind == "lifebloom" then
                        e.tick = c.tick                 -- per stack, at x1
                        e.ticks, e.tickPeriod, e.duration = 7, 1, 7
                        e.bloom = c.bloom
                    end
                else
                    -- Swiftmend and Tranquility have no heal values in
                    -- Data/SpellData.lua, so RowFor returns nothing for them.
                    -- Swiftmend is derived below; Tranquility is carried with
                    -- dataMissing so a planner can see it exists and refuse to
                    -- use a number nobody has measured.
                    e.cost = ctx.CostFor(id) or s.cost or 0
                    e.cast = s.cast or 1.5
                    if family == "Tranquility" then
                        e.channelTicks, e.dataMissing = 4, true
                    end
                end
                -- T96: the family's own cooldown, from the druid profile
                e.cooldown = FamilyCooldown(family)
                out[id] = e
            end
        end

        -- Swiftmend's value is the HoT it eats, so it is priced after the rest.
        local rejuvID, regrowthID = SD.maxRank.Rejuvenation, SD.maxRank.Regrowth
        local rejuv, regrowth = rejuvID and out[rejuvID], regrowthID and out[regrowthID]
        local smID = SD.maxRank.Swiftmend
        local sm = smID and out[smID]
        if sm then
            if rejuv and rejuv.tick then
                sm.swiftmendRejuv = rejuv.tick * math.min(rejuv.ticks,
                    SWIFTMEND_REJUV_SECONDS / rejuv.tickPeriod)
            end
            if regrowth and regrowth.tick then
                sm.swiftmendRegrowth = regrowth.tick * math.min(regrowth.ticks,
                    SWIFTMEND_REGROWTH_SECONDS / regrowth.tickPeriod)
            end
            sm.cast = 1.5
        end
    end

    kit.crit = RankMath:DruidContext({ live = true, healer = opts and opts.healer }).crit
    return MD.Kit.Check(kit, "RankMath:SpellKit")
end

-- One row plus its full breakdown, for the dashboard tooltip. Rebuilt from a
-- fresh context so it always matches what the table is showing.
function RankMath:Explain(spellID, variant, opts)
    return RankMath:RowFor(spellID, RankMath:Context(opts), variant, true)
end

-- What ONE combat-log event should read, for Engine/Calibration.lua:
--   { direct = <non-crit direct heal>, tick = <per tick at x1>, bloom = <bloom>,
--     ticks = <n>, crit = <crit chance the row assumed>, stacked = <Lifebloom> }
-- Crit is stripped here because a single event either crit or did not; the
-- row's (1 + 0.5 x crit) is an expectation and cannot be compared to one hit.
function RankMath:EventPrediction(spellID)
    local row = RankMath:Explain(spellID, nil, { live = true })
    local c = row and row.calc
    if not c then return nil end
    local out = { crit = c.crit or 0, family = c.family, talentMult = c.talentMult }
    if c.kind == "direct" then
        out.direct = (c.base + (c.relicFlat or 0) + c.bonusOut) * c.talentMult
    elseif c.kind == "hot" then
        out.ticks = c.ticks
        out.tick = row.heal / c.ticks
    elseif c.kind == "hybrid" then
        out.direct = c.direct / c.critMult
        out.ticks = c.duration / 3
        out.tick = c.hot / out.ticks
    elseif c.kind == "lifebloom" then
        out.tick, out.bloom, out.ticks, out.stacked = c.tick, c.bloom, 7, true
    end
    return out
end

--------------------------------------------------------------------------------
-- Returns family -> { label, tol, rows = {...}, suggestedID, callout }; the
-- inputs used are left in RankMath.info (the context).
--------------------------------------------------------------------------------
function RankMath:Compute()
    -- T111: the rank table is a capability (Spells/Profiles.lua), and its
    -- ranks come from the logged-in class's source -- Data/SpellData.lua for
    -- the druid, the class's own book (Spells/Book_TBC.lua) otherwise
    local SD = RankMath:Source()
    local results = {}
    local profile = MD.ClassProfile
    if not SD or not (profile and profile:Can("rankTable")) then return results end

    local ctx = RankMath:Context()
    RankMath.info = ctx

    for _, family in ipairs(SD.familyOrder) do
        local info = SD.families[family]
        local allIDs = SD.all[family]
        if info and not info.exclude and allIDs and #allIDs > 0 then
            local rows = {}
            for _, id in ipairs(allIDs) do
                local row = RankMath:RowFor(id, ctx)
                if row then
                    rows[#rows + 1] = row
                    -- Informational rolling-stack rows: excluded from Pareto /
                    -- suggestion because they are a different activity from a
                    -- single application.
                    if info.type == "lifebloom" then
                        for stacks = 2, 3 do
                            rows[#rows + 1] = RankMath:RowFor(id, ctx, stacks)
                        end
                    end
                end
            end

            -- Pareto dominance on (HPM, HPS) — among KNOWN, real ranks only.
            -- Suggested rank: highest-HPM known non-dominated rank that still
            -- heals >= MD.Rules.SUGGESTED_FLOOR (40%) of the max known rank
            -- (assumption: below that, cast-count pressure outweighs
            -- efficiency). T67: both rules are Spells/RankRules.lua's.
            local RR = MD.RankRules
            RR.Pareto(rows, RULE_FIELDS)
            local maxRow
            for i = 1, #rows do
                if rows[i].isMax then maxRow = rows[i] end
            end
            local suggested = RR.Suggested(rows, maxRow, RULE_FIELDS)
            if suggested then suggested.suggested = true end

            local callout
            -- Lifebloom: with tick and bloom overheal measured separately, say
            -- which way of using the max rank is worth more on THIS player's
            -- targets. Kept out of the Pareto filter (a different activity).
            local lbNote
            if info.type == "lifebloom" and maxRow and maxRow.overheal and maxRow.overheal.scope == "kind" then
                local roll
                for i = 1, #rows do
                    if rows[i].id == maxRow.id and rows[i].variant == 3 then roll = rows[i] end
                end
                if roll and roll.effHpm and maxRow.effHpm then
                    local better = roll.effHpm > maxRow.effHpm
                    lbNote = string.format(" Measured overheal (ticks %d%%, bloom %d%%): %s - rolling x3 %.2f vs single cast %.2f effective HPM.",
                        maxRow.overheal.tick * 100 + 0.5, (maxRow.overheal.bloom or 0) * 100 + 0.5,
                        better and "keep the stack rolling" or "let it bloom",
                        roll.effHpm, maxRow.effHpm)
                end
            end
            if suggested and maxRow and suggested ~= maxRow then
                callout = string.format(
                    "R%d: %d heal for %d mana (%.2f HPM). R%d costs %.1fx the mana for %.1fx the heal.",
                    suggested.rank, suggested.heal, suggested.cost, suggested.hpm,
                    maxRow.rank, maxRow.cost / suggested.cost, maxRow.heal / suggested.heal)
            elseif suggested then
                callout = string.format("Max rank (R%d) is also your most efficient usable rank.", suggested.rank)
            end

            results[family] = {
                label = info.label,
                tol = info.tol,
                rows = rows,
                suggestedID = suggested and suggested.id or nil,
                callout = (callout or "") .. (lbNote or ""),
            }
        end
    end

    return results
end

-- Map of family -> suggested rank number, for the gear-change toast diff.
function RankMath:SuggestedRanks()
    local out = {}
    for family, res in pairs(RankMath:Compute()) do
        if res.suggestedID then
            out[family] = RankMath:Source().spells[res.suggestedID].rank
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the TBC rank table and
-- spell tooltip for a priest, shaman or paladin. Their ranks are read from
-- the client by Spells/Book_TBC.lua (each rank's base heal from its own text,
-- its cost and cast from the client); this section puts the TBC rules on top
-- -- the same coefficient rules as the druid's (Spells/Coefficients.lua's
-- Direct for a direct heal, Hot for a HoT), the same downrank penalty, the
-- same 1.5x crit -- plus each class's healing talents. No coach: the TBC
-- coach stays the druid's (decision 8), and the kit built here only has to be
-- one Engine/Kit.lua accepts.
--
-- Reached in the game only once a class's profile grants `rankTable`
-- (RankMath:IsClassBook); the TBC class profiles do not yet, because the TBC
-- files that read Data/SpellData.lua directly -- the Spells view, the spell
-- tooltip, the fight summary's max-rank share, /md profile -- would show a
-- half-working pane or a wrong number for them (docs/tasks/T111 lists each
-- one). Until then this is the offline tools' (tools/tbcclasscheck.lua,
-- tools/wclcheckkit.lua --fit).
--
-- Every rule below is VERIFY: the talents' names are the TBC client's, their
-- size per rank is from the 2.4 talent texts as remembered, and
-- tools/wclcheckkit.lua --fit (the +healing each public parse needs, family
-- by family) is the check before anyone trusts them. A talent whose rank the
-- scan does not find counts 0, so a wrong name costs a bonus, never a number
-- out of nowhere.
--   healMult   x(1 + mult x rank) on the whole heal (base and bonus)
--   coefAdd    + add x rank to the bonus coefficient of the named families
--   castAdd    the talent took add x rank off the cast the client reports;
--              it is added back for the coefficient (which is the BASE
--              cast's), never for the cast bar
--   critAdd    + add x rank to the crit chance of the family
-- `families` limits a talent to those family keys (every heal without it).
--------------------------------------------------------------------------------
RankMath.CLASS_RULES = {
    PRIEST = {
        { name = "Spiritual Healing", healMult = 0.02 },
        { name = "Improved Renew", healMult = 0.05, families = { Renew = true } },
        { name = "Empowered Healing", coefAdd = { GreaterHeal = 0.04, FlashHeal = 0.02, BindingHeal = 0.02 } },
        { name = "Divine Fury", castAdd = 0.1, families = { Heal = true, GreaterHeal = true } },
    },
    SHAMAN = {
        { name = "Purification", healMult = 0.02 },
        { name = "Improved Chain Heal", healMult = 0.10, families = { ChainHeal = true } },
        { name = "Improved Healing Wave", castAdd = 0.1, families = { HealingWave = true } },
        { name = "Tidal Mastery", critAdd = 0.01 },
    },
    PALADIN = {
        { name = "Healing Light", healMult = 0.04, families = { HolyLight = true, FlashOfLight = true } },
        { name = "Sanctified Light", critAdd = 0.02, families = { HolyLight = true } },
    },
}
-- A heal that lands on the whole party carries half the single-target
-- coefficient (Prayer of Healing, Circle of Healing). VERIFY. T117: the rule
-- is Spells/Coefficients.lua's GROUP; this name stays as its alias.
RankMath.GROUP_COEF = MD.Coefficients and MD.Coefficients.GROUP

-- True when the logged-in class reads its own book (built or not): a class
-- other than the one Data/SpellData.lua is written for (the druid,
-- Engine/Kit.lua's default profile) whose profile GRANTS the rank table.
-- The TBC priest, shaman and paladin profiles do not grant it yet
-- (Data/Profile_<Class>_TBC.lua says why), so until they do every class
-- reads exactly what it read before T111 -- the druid's context over
-- Data/SpellData.lua, and no rank table.
function RankMath:IsClassBook()
    local class = MD.player and MD.player.class
    if class == nil or class == KIT_PROFILE or MD.BookTBC == nil then return false end
    local p = MD.ClassProfile
    return type(p) == "table" and p.class == class and type(p.Can) == "function"
        and p:Can("rankTable") == true
end

-- The ranks' source: the class's own book for a class book (nil until it is
-- built), Data/SpellData.lua otherwise.
function RankMath:Source()
    if not RankMath:IsClassBook() then return MD.SpellData end
    return MD.BookTBC:Source()
end

local NO_SOURCE = { spells = {}, families = {}, familyOrder = {}, all = {}, known = {}, knownSet = {},
                    maxRank = {}, GetCost = function() return nil, "unknown" end }

-- The school's crit and the mana, through the adapter (Client/API_TBC.lua's
-- SpellCritChance, the shared UnitPower); an absent or unreadable answer is 0.
local function SchoolCrit(school)
    local fn = MD.API and MD.API.SpellCritChance
    local v = type(fn) == "function" and fn(school or 2) or nil
    if type(v) == "number" then return v / 100 end
    return 0
end

local function PlayerMana()
    local fn = MD.API and MD.API.UnitPower
    local v = type(fn) == "function" and fn("player", 0) or nil
    if type(v) == "number" then return v end
    return 0
end

-- The talents' effect on one family: heal multiplier, coefficient added,
-- cast added back, crit added, and the names that did it.
local function TalentsFor(class, family)
    local out = { mult = 1, coefAdd = 0, castAdd = 0, critAdd = 0 }
    local multNames, coefNames = {}, {}
    for _, t in ipairs(RankMath.CLASS_RULES[class] or EMPTY) do
        if not t.families or t.families[family] then
            local rank = MD:TalentRank(t.name)
            if rank > 0 then
                if t.healMult then
                    out.mult = out.mult * (1 + t.healMult * rank)
                    multNames[#multNames + 1] = t.name
                end
                local add = type(t.coefAdd) == "table" and t.coefAdd[family] or nil
                if add then
                    out.coefAdd = out.coefAdd + add * rank
                    coefNames[#coefNames + 1] = t.name
                end
                if t.castAdd then out.castAdd = out.castAdd + t.castAdd * rank end
                if t.critAdd then out.critAdd = out.critAdd + t.critAdd * rank end
            end
        end
    end
    out.multName = (#multNames > 0) and table.concat(multNames, ", ") or nil
    out.coefName = (#coefNames > 0) and table.concat(coefNames, ", ") or nil
    return out
end
RankMath.TalentsFor = TalentsFor

-- The class's context: the druid's inputs that are not the druid's own (no
-- Tree of Life, relic or Nature's Grace), the crit of the profile's school.
-- The Simulate strip's stats apply as they do for the druid.
function RankMath.ClassContext(opts, src)
    src = src or NO_SOURCE
    local sim
    if opts and opts.healer then
        local h = opts.healer
        sim = { heal = h.heal, crit = h.crit, casting = h.casting, base = h.base, mana = h.mana }
        if next(sim) == nil then sim = EMPTY end
    elseif opts and opts.live then
        sim = EMPTY
    else
        sim = MD.sim or EMPTY
    end
    local profile = MD.ClassProfile
    local liveBonus = BonusHealing()
    local statBonus = sim.heal or liveBonus
    local liveCrit = SchoolCrit(profile and profile.critSchool)
    local liveMana = PlayerMana()
    local liveCasting = MD.Regen and MD.Regen.casting or 0
    local liveBase = MD.Regen and MD.Regen.base or 0
    local ctx = {
        class = (MD.player and MD.player.class) or (profile and profile.class),
        SD = src,
        bonus = statBonus, statBonus = statBonus, treeAura = 0, inTree = false, relic = nil,
        crit = sim.crit and (sim.crit / 100) or liveCrit,
        playerLevel = MD.player.level,
        mana = sim.mana or liveMana,
        castingRegen = sim.casting and (sim.casting / 5) or liveCasting,
        baseRegen = sim.base and (sim.base / 5) or liveBase,
        naturesGrace = 0,
        simulated = next(sim) ~= nil,
        live = { heal = liveBonus, crit = liveCrit * 100, casting = liveCasting * 5,
                 base = liveBase * 5, mana = liveMana },
    }
    ctx.ExpectedCast = function(T0) return T0 end
    ctx.CostFor = function(id)
        if type(src.GetCost) == "function" then return src:GetCost(id) end
        return nil, "unknown"
    end
    ctx.CastsToOOM = function(cost, interval)
        return RankMath:CastsToOOM(cost, interval, ctx.mana, ctx.castingRegen)
    end
    return ctx
end

-- The engine's HoT period when the text gives only the total and the
-- duration: 3 s when the duration is a multiple of it (Renew), else 1 s
-- (Engine/SimModel.lua's uniform ticks). VERIFY per spell.
local function TickPeriod(duration)
    if duration % 3 == 0 then return 3 end
    return 1
end

local DIRECT_KINDS = { direct = true, group = true, chain = true, selfAndTarget = true }

-- One row of a class's rank, in the druid row's shape (Tip_TBC's Row reads
-- the same calc fields). The value is ONE target's (decision 12): a group,
-- chain or self-and-target heal is never multiplied by its reach here.
function RankMath.ClassRow(spellID, ctx, explain)
    local SD = ctx.SD or NO_SOURCE
    local s = SD.spells and SD.spells[spellID]
    if not s then return nil end
    local info = SD.families and SD.families[s.family]
    if not info then return nil end
    -- a rank with no learn level has no downrank penalty to compute and no
    -- level for the table to print: it is not a row (Spells/Book_TBC.lua
    -- refuses it before it gets here)
    if type(s.level) ~= "number" or s.level <= 0 then return nil end
    local tal = TalentsFor(ctx.class, s.family)
    local C = Coef()
    local pen = C.Penalty(s.level, ctx.playerLevel)
    local bonus = ctx.bonus
    local heal, castTime, castBase, calc
    local crit = math.min(1, ctx.crit + tal.critAdd)

    if DIRECT_KINDS[info.type] then
        castBase = math.max(s.cast, 1.5)
        castTime = castBase
        local coefCast = s.cast + tal.castAdd
        local coef = C.Direct(coefCast)
        if info.type == "group" then coef = coef * C.GROUP end
        local bonusMult = 1 + tal.coefAdd / coef
        local base = (s.healMin + s.healMax) / 2
        local bonusOut = bonus * coef * pen * bonusMult
        local critMult = 1 + 0.5 * crit
        heal = (base + bonusOut) * tal.mult * critMult
        if explain then
            calc = { kind = "direct", base = base, relicFlat = 0,
                     bonus = bonus, coef = coef, penalty = pen, bonusMult = bonusMult,
                     bonusMultName = tal.coefName or "", bonusOut = bonusOut,
                     talentMult = tal.mult, talentName = tal.multName or "", critMult = critMult, crit = crit,
                     min = (s.healMin + bonusOut) * tal.mult,
                     max = (s.healMax + bonusOut) * tal.mult }
        end
    elseif info.type == "hot" then
        castTime = 1.5 -- GCD
        local coef = C.Hot(s.hotDuration)
        local bonusMult = 1 + tal.coefAdd / coef
        local bonusOut = bonus * coef * pen * bonusMult
        heal = (s.hotTotal + bonusOut) * tal.mult
        if explain then
            local period = TickPeriod(s.hotDuration)
            calc = { kind = "hot", base = s.hotTotal, relicFlat = 0,
                     bonus = bonus, coef = coef, penalty = pen, bonusMult = bonusMult,
                     bonusMultName = tal.coefName or "", bonusOut = bonusOut,
                     talentMult = tal.mult, talentName = tal.multName or "",
                     duration = s.hotDuration, ticks = s.hotDuration / period, tickPeriod = period }
        end
    end
    if not heal then return nil end

    local cost, costSource = ctx.CostFor(spellID)
    cost = cost or 0
    -- per second over what decides how often it can be cast: the cast, the
    -- GCD, or its own cooldown (Holy Shock; Spells/Book.lua's IntervalFor)
    local interval = math.max(castTime, s.cooldown or 0)
    local row = {
        id = spellID, rank = s.rank, level = s.level,
        cost = cost, cast = castTime, heal = heal,
        hpm = cost > 0 and heal / cost or 0,
        hps = heal / interval,
        casts = ctx.CastsToOOM(cost, castTime),
        known = SD.knownSet[spellID] or false,
        isMax = SD.maxRank[s.family] == spellID or false,
        ng = false,
    }
    if MD.Overheal then
        local frac, n, scope = MD.Overheal:Fraction(spellID)
        if frac then
            local k = 1 - frac
            row.overheal = { frac = frac, n = n, scope = scope }
            row.effHeal = row.heal * k
            row.effHpm = row.hpm * k
            row.effHps = row.hps * k
        end
    end
    if calc then
        calc.family = s.family
        calc.label = info.label
        calc.type = info.type
        calc.cost = cost
        calc.costSource = costSource
        calc.castBase = castBase or castTime
        calc.castNG = castTime
        calc.naturesGrace = 0
        calc.mana = ctx.mana
        calc.castingRegen = ctx.castingRegen
        calc.baseRegen = ctx.baseRegen
        calc.netPerCast = cost - ctx.castingRegen * castTime
        calc.overheal = row.overheal
        calc.cooldown = s.cooldown
        calc.interval = interval
        calc.jumps, calc.falloff = s.jumps, s.falloff
        row.calc = calc
    end
    return row
end

-- The class's kit: every known rank, one form (no Tree of Life), stamped
-- with the logged-in class's profile, in Engine/Kit.lua's shape and checked
-- by it. RankMath:SpellKit never answers it (decision 8 (b)): the offline
-- tools call it by name.
function RankMath.ClassKit(opts, src)
    src = src or NO_SOURCE
    local ctx = RankMath.ClassContext({ live = true, healer = opts and opts.healer }, src)
    local kit = { caster = {}, tree = {}, profile = ctx.class }
    for family, list in pairs(src.known) do
        local info = src.families[family]
        for _, id in ipairs(list) do
            local s = src.spells[id]
            local e = { family = family, rank = s.rank, type = info and info.type or "direct", gcd = 1.5 }
            local row = RankMath.ClassRow(id, ctx, true)
            local c = row and row.calc
            if c then
                e.cost, e.cast, e.castBase = row.cost, row.cast, c.castBase
                if c.kind == "direct" then
                    e.direct = row.heal / (c.critMult or 1)
                    e.directCrit = c.crit or 0
                    if e.type == "chain" then e.jumps, e.falloff = s.jumps, s.falloff end
                else
                    e.ticks, e.tickPeriod, e.duration = c.ticks, c.tickPeriod, c.duration
                    e.tick = row.heal / c.ticks
                end
            else
                e.cost = s.cost or 0
                e.cast = math.max(s.cast or 1.5, 1.5)
                e.dataMissing = true
            end
            e.cooldown = s.cooldown
            kit.caster[id] = e
        end
    end
    kit.crit = ctx.crit
    return MD.Kit.Check(kit, "RankMath:SpellKit")
end
