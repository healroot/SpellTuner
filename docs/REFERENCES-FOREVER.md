# Reference sources for spells on WoW: Forever

Written 2026-09-27 by the planner. The author named two sites as the base references for spell
data on Forever: **talentsforever.com** ("more up to date as of now") and **Wowhead**. Three
scouts read them and Blizzard's own statements; a skeptic per scout refetched every cited page.
What follows is what survived. Companion to `docs/FOREVER-PLAN.md` (§1 facts, §6 questions).

**The rule these sit under is unchanged.** A value in code comes from the client or from a
measurement. The sites are for *checking* (does the probe's description dump agree, does a
dashboard row look right), for *planning* (which spells exist, which ranks, which talents), and
for *reading changes between builds*. Nothing from them is typed into `Data/` or `Spells/`.
The two sites disagree with each other on 27 of 49 druid ranks at the same build, which is the
whole argument in one line.

## 1. talentsforever.com

**What it is.** A fan site by Chris Baldwin (X `@baldwinbuilds`; no GitHub, no Discord link) that
reads talents, racials, Legacy perks and the full class spellbooks out of the Forever beta
client's own files, re-reads them on every beta build, and checks spellbooks against a city
trainer in game (Mage only so far; the Druid book is files-only, `spellbooks.Druid.checked` is
null). Not affiliated with Blizzard. Ships its own in-game addon, `TalentsForeverBook`, on
CurseForge. Sources: https://talentsforever.com/about , https://talentsforever.com/ideas .

**What it gives.** Every trainer spell to level 60 with every rank, for all nine classes, plus
466 talents rank by rank with the Classic comparison. Per spell rank: the tooltip's cost / range /
cast / cooldown lines, the description text **as the beta client renders it at level 60 with no
gear**, learn level, spell id, school, a coefficient string ("20% of spell power (per tick)"),
and the Classic text and coefficient beside it.

**Machine access.** Static JSON, CC BY 4.0, attribution string
`Data from talentsforever.com (https://talentsforever.com)`. No API, no repository.

| file | contents | note |
|---|---|---|
| https://talentsforever.com/data.json | everything (1.68 MB): `_readme`, `license`, `attribution`, `generated`, `talents`, `spellbooks`, `spell_desc`, `racials`, `class_racials`, `class_abilities`, `legacy` | **use this one**; `generated` 2026-09-26, every spellbook `build` 1.60.1.70009 |
| https://talentsforever.com/export/<class>.json | one class, current build | named on /about and /terms |
| https://talentsforever.com/data/<class>.json | one class, **a build behind** (69876, generated 2026-09-20) | the path the homepage links; do not use |
| https://talentsforever.com/updates.js | `window.UPDATES`: per-build diff (`talents` / `spells` / `racials` / `legacy` per class, `before` / `after`, `counts`) and the blue post it came from | the machine-readable "what changed this build" |
| https://talentsforever.com/builds | the same as prose | |

Record shape, `spell_desc["Druid|Rejuvenation|Rank 11"]`:

```
l   [["360 Mana","40 yd range"],["Instant",""]]   tooltip lines: [cost, range], [cast, cooldown]
d   "Heals the target for 776 over 12 sec."       description at level 60, no gear
s   "beta" | "demo" | "classic"                   beta client text | read off footage | Wowhead Classic fallback
src "beta client 1.60.1.70009"
lv  "Learned at level 60"
id  25299
co  "20% of spell power (per tick)"               Forever coefficient string
cc  "8% of spell power (per tick)"                Classic coefficient, when it differs
sc  "Nature"
cs  "same" | "changed" | "new" | "note"           vs Classic
ck  "n" (same spell, new numbers) | "r" (reworked)
cd / cl                                           Classic description / lines
nt  1 portal trainer | 2 tome, quest or drop | 3 comes with the talent (rank 1 of a talent-granted spell)
fx / asis / was / cn                              known beta-text slips, former name, a note -- READ before trusting d
```

Keys are `Class|Name|Rank N`, `Class|Name|` (unranked), `Class|Name|Shapeshift`,
`Class|Name|Passive`. `spellbooks[Class].levels[name]` is the learn level per rank for ranked
spells only; `spellbooks[Class].talents` lists the talent-granted spells; `.gone` the removed ones.
**`id` is not a primary key**: 31 rows have none and 8 ids are shared across classes.

**Caveats.**
- Costs come in two shapes: `"1,050 Mana"` (thousands comma) and `"20% of base mana"` (99 rows;
  every druid shapeshift, Innervate, Rebirth, Revive, Swiftmend, the cures). A parser needs both.
- `co` is not sourced: the readme does not say whether it is read from a client table or
  computed, and every value seen matches cast/3.5 and duration/15. Treat as unverified.
- The readme warns "numbers can lag live tuning" and "your in-game tooltip will read a bit
  higher" than the level-60-no-gear text.
- The client files carry retired duplicate talents that still answer in game and can be matched
  by name wrongly (changelog 2026-09-26, Hunter Lightning Reflexes). A warning for anyone reading
  the client's own talent tables by name.
- Terms ask not to hammer the server. A tool fetches `data.json` **once**, caches it, and never
  hits the site per query.

## 2. Wowhead

**What it is.** Wowhead has a Forever database: URL prefix `/forever`, internal data environment
**16** (`classicplus`; aliases `forever`, `classic-plus`), version label 1.60.1, max level 60.
Sources: https://www.wowhead.com/forever , https://wow.zamimg.com/js/tooltips.js .

**Machine access.**

| path | gives | note |
|---|---|---|
| https://nether.wowhead.com/tooltip/spell/<id>?dataEnv=16&locale=0 | JSON `{name, icon, tooltip (HTML), tooltip2, buff, ...}` for one rank | `dataEnv` must be the number 16; `?level=` is ignored; ETag suffix `:70009` is the **only** build stamp Wowhead exposes; CORS `*` |
| https://www.wowhead.com/forever/spell=<id>/<slug> | the page: Spell Details (effect base `Value`, `SP mod` coefficient, duration, cost, GCD, flags), Quick Facts, other ranks, modified-by | HTML plus JS blobs; `?xml` does **not** exist for spells (it does for items) |
| https://www.wowhead.com/forever/spells/abilities/<class> and `/spells/talents/<class>` | `var listviewspells = [...]`: every spell with id, rank, level, training cost, source, and Wowhead's own diff against Classic Era (`envChange`: status, labels, "644 instead of 756") | both listings are needed for a full kit (Wild Growth and Swiftmend sit under talents) |
| https://www.wowhead.com/news/rss/forever | Forever news with full bodies | the datamining posts per build |

**Caveats.**
- **Spell Details `Value` is a base effect point, not the tooltip number** (Regrowth R1 `14 every
  3 seconds` vs tooltip "another 91 over 21 sec"; Healing Touch R11 `Value: 2333` vs tooltip
  "2175 to 2562"). Do not multiply effect values into totals.
- **`envChange` diffs tooltip text, not effect data**: Rejuvenation R1 is "unchanged" although
  its coefficient went from 0.08 to 0.2. "Unchanged" does not mean "same scaling".
- No `SP mod` is printed for every heal (Healing Touch R11 has none), so the coefficient cannot be
  pulled from Wowhead for those ranks.
- Tooltips for level-60 ranks are rendered at a stated level 60 ("Level 60" line); a lower-level
  character's client tooltip will differ.
- The `modified-by` list mixes Season of Discovery leftovers with real Forever talents.
- "Added in patch 1.60.1" quotes the first build a row was seen in (69876), not the data build.
- www.wowhead.com is behind CloudFront and blocks curl's default agent; `nether` answers a plain
  `Mozilla/5.0`. **robots.txt disallows AI crawlers outright** (`anthropic-ai`, `ClaudeBot`,
  `GPTBot`, ...). Policy for this project: Wowhead is read **by a person in a browser** or by a
  single-spell `nether` fetch for a spot check, cached; **no bulk pull**. Bulk data comes from
  talentsforever's licensed JSON.
- No terms-of-service page was found; the tooltips page invites fansite embedding
  (`https://wow.zamimg.com/js/tooltips.js`, `domain=forever`).

## 3. Currency, and how the two disagree

Beta builds: 69876 (2026-09-17, first), 69893 (09-17), 69913 (09-18), 69977 (09-22) -- these
four are one data state -- and **70009 (2026-09-24)**, the first balance pass. Both sites are at
70009 for spells (`data.json` generated 09-26; every `nether` ETag ends `:70009`). Whether Wowhead
includes post-build hotfixes is not knowable from it. Sources: https://talentsforever.com/builds ,
https://foreverchanges.pro/patch-notes .

At the same build the two disagree on 27 of 49 druid heal / damage ranks compared. They agree
exactly on every Rejuvenation rank and on Renew; Wowhead's direct heals run ~1.7-2% higher
(Healing Touch R11 2175-2562 vs 2139-2525) and the brand-new ids differ most (Wild Growth R3 769
vs 679 over 7 s; Riptide R3 HoT 953 vs 805). Neither states what explains it. **Only the client's
own tooltip on the character is authoritative**, and the sites catch gross errors, not 2% ones.

An oddity from the client (2026-09-28, `docs/probe/1.60.1_70009.md`, first report): Healing Touch
R1 reads **"40 to 55" on the level 8-9 client** where talentsforever's level-60 text says "40 to
54" -- *higher* below 60 than at 60, the opposite of a per-level increase. Either the site's text
is not the level-60 client's or the value drops with level; the author's own level-60 tooltip will
say which. Until then the site's R1 numbers are not evidence for any level but its own.

## 4. What the sources say Forever changes about healing

Kept apart: what Blizzard said, what the client data shows, what nobody knows.

**Official (Blizzard).**
- Spell ranks exist and are tuned per rank ("Lightning Bolt: damage on ranks 3 and 4 increased to
  make these spells always upgrades"); the Cooldown Manager does not yet support ranks. Kaivax,
  beta development notes, 2026-09-24:
  https://us.forums.blizzard.com/en/wow/t/2360696
- **Rejuvenation, Tranquility, Wild Growth, Renew and Riptide can crit** ("Corrected an issue and
  now Rejuvenation can land critical hits"). Same post. Bears on RankMath's crit weighting of HoTs.
- Thorns and Retribution Aura now scale with the caster's spell power. Same post.
- **Bonus healing also grants one third as much bonus damage**; caster weapons grant spell damage
  and healing; hit and crit are merged across spell / melee / ranged. Deep Dive recap, 2026-09-13:
  https://news.blizzard.com/en-us/article/24303313/world-of-warcraft-forever-deep-dive-panel-recap
- Paladin Reverence regenerates mana from Spirit while casting; Kris Zierhut at BlizzCon: "all of
  our classes that do damage and healing via mana will have talents or abilities that give them
  mana back based on your spirit". Transcript page 5:
  https://warcraft.blizzplanet.com/blog/comments/blizzcon-2026-world-of-warcraft-forever-deep-dive-panel-transcript/5
- The only "1.12 carries over" statement is about **talents**, not spells. Deep Dive recap.
- Nothing official on downranking penalties, coefficients or heal values. No Blizzard employee has
  posted in any of the eight scaling / downranking forum threads checked (Discourse `.json` staff
  flags, e.g. https://us.forums.blizzard.com/en/wow/t/2358042.json).

**Client data (both sites agree unless said).**
- **Every rank carries the full vanilla coefficient rule** -- cast/3.5 for a direct heal,
  duration/15 for a HoT, spread over ticks -- with **no Classic sub-level-20 cut**: Healing Touch
  R1 0.429 (Classic 0.123), Rejuvenation R1 0.2/tick (Classic 0.08), Regrowth R1 0.286 + 0.071/tick
  (Classic 0.2 + 0.05). A **server-side** rule (TBC's caster-level cut, or a new one) would not
  show in client data; unknown until measured (§6 Q10 in the plan).
- **Base values and costs changed at every rank, in both directions**: rank-1 heals up (Healing
  Touch R1 45 vs 37), level-60 HoT ticks ~12-14% down (Rejuvenation R11 194/tick vs 222), level-60
  direct heals within ~3%, some costs up (HT R11 840 vs 800), some down (Regrowth R1 70 vs 120).
  **A Classic Era table cannot be reused for any rank.**
- **Ids**: Classic ids for the old ranks (Rejuvenation 774..9841, R11 25299; Regrowth 8936..9858;
  Healing Touch 5185..25297; Tranquility 740/8918/9862/9863) plus new 7-digit ids for new ranks
  (Wild Growth 408120 / 1238214 / 1238215). **TBC ids are absent** (26980, 26978/9, 26982) -- the
  TBC table's keys do not map.
- **Druid heals on Forever**: Healing Touch (11 ranks), Regrowth (9), Rejuvenation (11),
  Tranquility (4: levels 30/40/50/60), Swiftmend (talent-granted, 20% of base mana, eats the
  **full remaining** HoT, reworked), Wild Growth (talent-granted rank 1, 3 ranks at 40/50/60,
  party within ~43 yd, 7 s, 1 s ticks). **No Lifebloom, no Tree of Life** -- Lifebloom appears
  nowhere in the Forever spellbooks; Wowhead's only rows are Season of Discovery leftovers.
  Likewise **no Earth Shield, no Circle of Healing**.
- New ranked heals elsewhere: Priest Penance (4), Binding Heal (6), Prayer of Mending (3), Divine
  Grace (7), Lightwell (3); Paladin Holy Shock as a 4-rank spell from level 30 on a 10 s
  cooldown, Light's Vigil (3); Shaman Riptide (3), Mana Tide Totem (3), Water Shield.
- **Talent-granted spells put rank 1 in the book** (`nt = 3`; Wowhead tags "Talent"); higher
  ranks are trainer-sold; some ranks are tome / quest / drop (Rejuvenation R11 has no training
  cost). "Known ranks" must come from the spellbook, never from a trainer list.
- Costs: trained heals print flat `N Mana`; Swiftmend, Innervate and several utilities print
  `N% of base mana`. The live cost API stays the source.
- In-combat Spirit regen talents at 17/33/50% (Classic 5/10/15%); Illumination refunds 50% of
  base cost on a chance; Mana Tide 88 per 3 s. Any vanilla mana model needs these re-read.
- **The spellbook hides lower ranks by default** (a "show all ranks" option under the arrow at the
  top right) and **purchased ranks do not auto-update on action bars** for mana users. Wowhead
  news 2026-09-22 (news 383050). Downranking exists; the spellbook tooltip must work with the
  option on.
- Beta text slips exist and are flagged (`fx`, `asis`): Penance R4 deals less than R3; Holy Shock's
  range disagrees between sources. Do not model from a flagged row.

**Hints about Q1 (dynamic descriptions), not answers.** talentsforever's beta text is explicitly
"at level 60 with no gear", and Wowhead's Prayer of Mending tooltip leaks
`[(172 + (Healing * 0.42899999)) * (1 * 1)]` -- the client text is computed from the player's
Healing. Both point to **dynamic** descriptions; the probe decides.

## 5. How SpellTuner uses them

- **M0 (probe)**: the probe dumps every spell's id, name, rank text and description exactly as the
  client renders them. The planner compares that dump with `data.json` by hand once.
- **M2**: `tools/refcheck.py` -- fetch `https://talentsforever.com/data.json` once into a
  gitignored cache, then compare a probe dump or an exported dashboard against it: same ranks,
  same learn levels, same costs, description numbers within the level / gear explanation.
  Disagreements print with both values and the record's `src`, `fx`, `asis`. Attribution line in
  `docs/TOOLS.md`. Wowhead stays a by-hand cross-check (§2 policy).
- **Per build**: read `updates.js` for the build's spell changes before re-running the probe.
- **Never**: ship either site's numbers in the addon.

Other trackers surfaced, for triangulation only: https://foreverchanges.pro/downrank-calculator
(client data, says plainly the client cannot show a server rule), the MIT
[ElliotWood/Forever](https://github.com/ElliotWood/Forever) simulator (regenerates from the
client `DBCache.bin`, tracks hotfixes), and raidbots' public hotfix cache. woweternity.com applies
the TBC sub-20 rule to Forever and is wrong by construction.
