# T128: the trade score multiplies; every rank explains itself

Author's report (2026-10-04, two screenshots, TBC Starfire, What if +550 spell
damage = 1010): `best` lands on Rank 1 (6.13 per mana, 166.5 per sec) against max Rank 8
(4.59, 484.8). The author's own reading: R7 is +6% efficiency for -3.5% damage
and should beat R1, which is +34% for -66%. (Corrected 2026-10-04 by the
implementer, ruled by the lead: under the score below at k 0.25 Rank 6 -- +9.4%
per mana for -6.8% per sec, the author's own earlier pick -- scores 1.075, above
R7's 1.054 and R1's 1.022, so the oracle at 1010 is R6.)

## 1. The score (Spells/RankRules.lua `RR.Score`)

T127's additive score `(eff_r/eff_max - 1) - k*(1 - rate_r/rate_max)` lets a
large efficiency gain outweigh any loss (R1 +0.17 > R7 +0.055). Replace it with
the multiplicative form:

    score(r) = (eff_r / eff_max) * (rate_r / rate_max) ^ k

`max` scores exactly 1; the highest score **> 1** wins, else `max` (ties and
exactly 1 go to max, as T127 Q6). Same k settings and defaults (damage 0.25, heal
0.15), same heal floor, same non-dominated pool. At the margin it still reads
"1% per mana is worth 1/k % per second"; a big loss costs far more.

Oracles (put the author's numbers in `tools/rankmarkscheck.lua` verbatim):
- Starfire at 1010 (rows R1..R8 per mana / per sec: 6.13/166.5, 5.43/209.6,
  5.17/265.8, 4.98/327.1, 4.95/389.3, 5.02/451.7, 4.87/472.8, 4.59/484.8)
  -> best R6 (1.075; R7 1.054, R1 1.022), max R8, eff R1.
- Starfire at 460 (3.43/93.1, 3.16/122.0, 3.10/159.2, 3.07/201.6, 3.12/244.9,
  3.20/288.3, 3.16/307.0, 3.02/319.0) -> best R7 (1.036; R6 1.033), max R8, eff R1.
- +5% / -50% -> max; x3 / x0.6 -> that rank. k = 0 -> eff (heals: within floor).

Words follow (card Marks line, strip, tooltip, settings tip): say the score as
a ratio against max ("score 1.075 vs max 1.000"), not "+0.055".

## 2. Every rank row explains itself

Hovering any rank row (RANKS table, both lines) shows, besides what it shows
today, a TRADE block against max: per mana +x%, per sec -y%, score, and the
verdict:
- holds best / max / eff (as today's mark lines),
- "beaten by Rank N" (dominated),
- "under 40% of Rank N's heal" (heal floor),
- "Rank 6 trades better (1.075 vs 1.054)" (scored lower than best; R7 at 1010),
- "trade does not pay (0.98)" (score <= 1).
The numbers come from the same book the row shows: **the what-if book when What
if is active** (today unmarked rows' tips show live numbers while What if is on
-- a bug; fix it for every column tip). Lifebloom stack rows likewise.

## 3. The strip still truncates with What if on

First screenshot: chip "WHAT IF / Rank 1 / live: R7", the strip reads
"vs R8: +34%/mana, 34% damage, same c..." -- the two-line fit (692572d) fails
in the what-if state (likely the room is measured for the other chip). Fix so it
picks a wording that fits; add a spellsui case with the what-if chip at offsets
-2..+2.

## Tests / docs

rankmarkscheck, spellsui (tips under What if, strip in what-if state),
whatifcheck as needed; goldens re-based only where the new score moves a mark
(list every moved family in the commit message). Expected counts. CHANGELOG
0.17.1 line; TESTING §50 step for the rank tips. CLAUDE.md RankRules row
(orchestrator writes it).
