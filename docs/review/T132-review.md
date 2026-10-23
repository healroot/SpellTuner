# T132 review: Forever's +bonus estimates from talentsforever coefficients

Reviewer: independent (Opus 5.5, high). Diff `758367b..HEAD` (1efe21d, 10340a7, f2493fa, a3c06df,
3519222). Spec: `docs/tasks/T132-forever-coefficients.md` with the lead's level addition.

**Verdict: fail.** 1 blocker, 2 major, 2 minor. B1 is a parser defect in the generator. M1 and M2
come from the spec itself (the 3 s tick fallback and "the group rule stays"), so they contradict
the brief. The lead (or the arbiter) rules on those two before a fix round.

What I checked and found sound:
- `python3 -I tools/buildcoefs.py <tf.json> --out <scratch>` is byte-identical to the committed
  `Data/Coefs_Forever.lua` (557 rows, 1 noted, 7 wording, 0 no id, 0 clash). The header names
  the skips. Ids are the site's `id`. ASCII is enforced at write time.
- TBC is unchanged. `Data/Coefs_Forever.lua` is listed only in `SpellTuner.toc` and
  `SpellTuner_Mainline.toc`, and those two still differ only in the marker line. The only caller
  of `Coef.Estimate` is `Spells/Book.lua`, which is Forever-only. TBC's `Book_Model` never reaches
  `ST.CoefRules`.
- The old fallback in `Coef.Estimate` is untouched for an id with no row.
- `PLAYER_LEVEL_UP` is not new in T132 (`Core.lua:455`, and `Spells/Book.lua:1554` from before).
  `ST:On` checks `CanRegisterEvent` and wraps `RegisterEvent` in a `pcall`, so an unknown or
  forbidden event cannot break load. Core's handler is registered before Book's. That means
  `ST.player.level` is updated before `MarkDirty`, and the next scan sees the new level.
- The fixture changes are sound. In `tools/bookshapecheck.lua` §4, the rows for 5185 and 774 are
  lifted, the book is built, the rows are put back and the book is marked dirty. The old-rule
  assertions now read an old-path book. `tools/talentscheck.lua` lifts 5176 and 5185 for the whole
  process, which is fine because each suite runs in its own process. Both still test T129's path.
- Suites run: coefscheck 20/0, talentscheck 26/0, bookshapecheck 10/0, bookcheck 45/0 (Forever).
- Docs: CHANGELOG 0.17.3 is ASCII. `§` was already used in DECISIONS, REFERENCES and TESTING.
  TESTING §54, the DECISIONS line and REFERENCES §1 match the code as written. They also repeat
  B1's and M2's assumptions, so they change with those fixes.

Probe used for every number below: the real Book on the Forever stub, with the site's beta texts
(`scratchpad/rv_probe.lua`).

## B1 (blocker): `tools/buildcoefs.py:40` adds a spell's damage share and its heal share into one `direct`

**Fixed in 7e1a65f.**

`parse_co` sends both "(direct)" and "(heal)" to the `direct` slot and adds them up. On the site,
"(direct)" is the damage part and "(heal)" is the heal part. The either-or spells show this:
- Holy Shock: "causing 129 to 139 Holy damage to an enemy, or 110 to 118 healing to an ally".
  Its `co` is "42.9% of spell power (direct), 42.9% of spell power (heal)".
- Light's Vigil: 42.9% (direct) + 14.3% (heal).
- Holy Nova: 10.7% (direct) + 10.7% (heal).

The generated rows are therefore wrong:
- Holy Shock R1-R4 (`1311606`, `20473`, `20929`, `20930`): `direct = 0.858`.
- Light's Vigil R1-R3: `0.572`.
- Holy Nova R1-R6: `0.214`.

**Failure scenario:** a Forever paladin opens Spells -> Holy Shock R1. The estimate reads
`85.8% (talentsforever)` (probe: counts 0.858) where the heal's share is 0.429. The +Healing
amount on the card, the What if delta (`Spells/WhatIf_Forever.lua` moves ranks by
`e.bonus.counts`) and the rank marks all take twice the bonus.

This breaks the task's own "never guess" rule: two parts of different kinds are merged without
being recognised.

**Fix:** keep the two kinds apart in the row. Use `direct` for damage and `heal` for heal, or skip
any row that has both. `FromRow` then picks the slot by the `kind` it already receives. Add one
coefscheck case for Holy Shock.

## M1 (major, from the spec): the 3 s tick fallback is wrong for many listed spells, two of them the druid's

**Fixed in ca18c67.**

When the text names no period, `Spells/Coefficients.lua:141,171` assumes 3 s ticks. Many rows in
the table tick faster, and the site's own per-tick share only adds up with the real tick count:

| Spell | Real ticks | Ticks with 3 s | Estimate | Note |
|---|---|---|---|---|
| Wild Growth (druid) | 7 (1 s over 7 s) | 2 | 0.033 after the group rule | Old rule gave 0.233 |
| Insect Swarm (druid) | 6 (2 s over 12 s) | 4 | 0.632 | 15.8% x 6 = 0.95; old rule gave 0.80 |
| Mind Flay | 3 (1 s over 3 s) | 1 | 0.167 | |
| Blizzard | 8 (1 s) | 2 | 0.084 | |
| Consecration | 8 (1 s) | 2 | 0.084 | |
| Holy Fire DoT | 5 (2 s) | 3 | | |
| Flamestrike DoT | 4 (2 s) | 2 | | |

**Failure scenario:** a Forever druid at level 40 opens Wild Growth R1. The card says
`3.3% x 2 ticks, 3 s ticks assumed (talentsforever), group rule`, and the +Healing it shows is
about 1/7 of the site's own number. For these spells the new path is a regression from the old
rule.

The words do say "3 s ticks assumed". But the spec's premise ("3 s, the vanilla HoT/DoT tick")
is false for these spells, so the estimate is a guess, not a rule.

**Options for the lead:**
- (a) When the text names no period, a tick row falls back to the old path.
- (b) A per-spell tick period, generated or VERIFY.
- (c) Restrict the 3 s fallback to the spells known to tick every 3 s (Rejuvenation, Regrowth,
  Renew, Shadow Word: Pain, Moonfire, Entangling Roots, Corruption ...).

This contradicts the brief, so it goes to the lead or the arbiter.

## M2 (major, from the spec): the group rule halves a share the site already gives per target

**Fixed in d325701.**

The site's `co` is already the per-target share. Prayer of Healing's 28.6% is Classic's
3.0 / 3.5 x 1/3, the AoE reduction already applied. Holy Nova's heal share is 10.7%, and Wild
Growth's 3.3% per tick is also per target. `Spells/Coefficients.lua:189` still multiplies the
share by `Coef.GROUP` (0.5).

**Failure scenario:** a Forever priest opens Prayer of Healing R1, whose beta text is "heals the
target and their party". The text parses to `targets = "party"`. The card says
`28.6% (talentsforever), group rule` with counts 0.143 (probe), where the site says 0.286.

The spec says "The group rule stays", and coefscheck's "3 the group rule still halves" makes it a
requirement. The old rule needed the group rule because cast / 3.5 is a single-target number; the
site's share does not need it. This contradicts the brief, so it goes to the lead or the arbiter.
If upheld, drop lines 189-192 on the row path and update the test, TESTING, DECISIONS and
REFERENCES.

## m1 (minor): a level-less entry is never invalidated while its reading repeats, and can bless older-level points

**Fixed in ff61c1d.**

`Spells/Book.lua:503` skips the level test when `m.level` is nil. The only place a level is
written is `Spells/Book.lua:1332`, after the "same reading again" early return at
`Book.lua:1306`.

**Failure scenario:** a pre-T132 (T131) entry exists with points read at levels 24 and 25. The
gear stays the same, so every scan repeats the newest reading, hits the early return and leaves
`m.level` nil. The player levels to 26, and `StoredFit` keeps the entry because its level is nil.
The fit stays `measured` across the level-up, which is what the lead's addition forbids. When a
new bonus is finally read, the entry adopts level 26 and keeps the older-level points in the fit.

Also, if `ST.player.level` is 0 (`UnitLevel` unreadable), `PlayerLevel()` is nil, nothing is
stamped and the rule is off.

Impact is small: T131 was installed on the author's Forever client only, on 2026-10-23.

**Fix:** drop level-less v = 2 entries once, the same way old-shape entries are dropped, or stamp
the level on the early-return path too. The bookcheck oracle covers only the levelled case.

## m2 (minor): coefscheck's channel case cannot fail on channel behaviour

**Fixed in 0682419.**

`tools/coefscheck.lua:162` builds a `castKind = "channeled"` entry with `period = 2`,
`periodDur = 8`. `FromRow` has no channel branch: it reads `periodDur / period` for any entry, so
this case is the same computation as the "parsed tick period" case above it. Removing
`castKind = "channeled"` changes nothing.

The real channels without a period in their text (Mind Flay, "over 3 sec") get the 3 s
assumption (see M1), and no test covers that. Either the assertion is renamed to what it tests,
or the channel rule the spec describes ("duration / interval") is implemented and tested on a
text with no period.
