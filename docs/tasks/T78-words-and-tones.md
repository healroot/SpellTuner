# T78 -- Words and tones (plan P34)

Status: **built** 2026-10-01 on branch `plan/P34` (base `7fd71b3`), wave 17 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No TOC line is needed: the four shipped files
are already listed where they have to be.

## The task (docs/PLAN-refactor-ux.md section 5, P34)

Review items (`docs/review/2026-09-30-project-review.md`): **U7** (`disabled` grey #4D4D4D carries
information -- the gap row's explanation, `learn at 14`, the tooltip's Shift hint; `text2` and
`label` cannot be told apart), **U9** (two vocabularies: `Per s` in the table, `Per second` in the
tooltip, `To OOM` / `Casts to OOM` / `casts from full`; `dominated` a statistician's word), **U10**
(the words: no column glossary on Forever, tags unexplained -- T76 built the `col.tooltip`
mechanism, this task writes the sentences), **U1** (the rank table: the selected row and the
suggested row are two strengths of one orange).

Mockup: `docs/mockups/refactor-ux.html` **M5**, approved 2026-09-30, with the author's choices
(section 7.1): **the selected rank row is a white 2-px bar** (the suggested row keeps its fill and
its accent bar); and (section 8.1 item 7) **`dominated` -> `beaten`, with a tooltip naming the rank
that beats it**. M5's "after": headers 12 px in the merged grey, each with one sentence on hover;
`Per sec`; `Casts` with `Casts in a row from a full pool.`; the beaten row's numbers in `text`, its
tag in the merged grey, the tag's hover `Beaten by Rank 3` / `Per mana 1.99 vs 1.90` / `Per sec 87.6
vs 31.7` / `Rank 3 is better on both, and you know it.`; a gap row's `R2` in `disabled` and its
explanation in `muted`; a not-learned row's numbers `disabled` and its `learn at 20` in the merged
grey; the tooltip block `Suggested  Rank 1 (+2% per mana)`, `Per sec`, `Casts to OOM  6 from full,
~5 now`, the Shift hint in `muted`; the merged grey is text2's #B3B3B3.

## What was built

| File | Change |
|---|---|
| `UI/Theme_Forever.lua` | **One grey for labels.** `label` is #B3B3B3 (was #9D9D9D) and `text2` is the same token (`T.text2 = T.label`, one table, kept as a name for the files that read it): labels, headers, tags, secondary lines. `muted` is explanations, hints, footers; `disabled` inert controls and the numbers of a rank you do not have. The legacy token `dominated` reads `text`: a beaten rank's numbers are numbers like any other rank's (M5). |
| `UI/Dashboard_Rows.lua` | Three generic-path options, each off unless asked for (TBC's table and every other caller unchanged): **`opts.selection = "bar"`** under `marker = "bar"` -- the selected row is a white 2-px bar at its left (`row.pick`, drawn above the accent bar) and no `selected` fill, so the fill and the accent bar stay the suggested row's alone; **`opts.headerFont`** -- the header labels' font object, a pooled row getting its data fonts back when it serves as a data row again; **`col.cellTooltip(r, row)`** -- a data cell that explains itself: asked when the row is drawn, a hit frame over that cell only when it answers lines (so a row with nothing to say there keeps its hover, its click and any button the render puts there -- Whole book's `+`), the lines beside the cell on hover (`MD.Tip:Show`, `anchor = "beside"`), a click on the cell forwarded to the row, and the row's own hover if the answer turned nil meanwhile. **`col.tooltip` may be a function(label)**, called with the label the header actually shows (an `opts.header` override included), which is also the tooltip's title. |
| `UI/SpellsPane_Forever.lua` | **One vocabulary and the glossary (U9, U10).** RANKS: `Per s` -> `Per sec`, `To OOM` -> `Casts`; every header but Rank has one sentence on hover (`Lvl` "The level you learn this rank at.", `Mana` "What one cast costs.", the value column by its label -- `Heal` / `Dmg` / `Total` / Whole book's `Value` --, `Per mana` "Healing for each point of mana." and `Per sec` "Healing per second of casting." with `Damage` for a damage family and `Healing or damage` on Whole book, `Cast` "Cast time; inst for an instant, chan for a channel.", `Casts` "Casts in a row from a full pool."); the Other-kind table's Lvl / Mana / Cast the same; My spells' `To OOM` -> `Casts` and a sentence on each of its headers. **Tags (U7, U10, the author's word):** `dominated` -> `beaten`; every tag but `best` (accent) in `label`, `learn at N` included; each tag explains itself on hover (`TagTip`): `Best` "The rank SpellTuner suggests.", `Max` "Your highest known rank.", `Learn at N` "Not learned yet.", and a beaten rank `Beaten by Rank N` with `Per mana  B vs A`, `Per sec  B vs A` and the muted `Rank N is better on both, and you know it.` (the rank from Book's `entry.dominatedBy`; with none, `Beaten` / `Another rank wins on both per mana and per sec.`). **Tones (U7):** a gap row's `R3` in `disabled` and its explanation in `muted`; a beaten row's numbers `text` (the token); headers 12 px (`UI.FONT_SPECIAL`) in `label` on RANKS, the Other-kind table, My spells and Whole book. **Selection (U1):** the RANKS tables pass `selection = "bar"`: the selected rank is a white bar, the fill reserved for the suggested one. **The card:** `Per s` -> `Per sec`, `To OOM` -> `Casts` (its value keeps Spells/Words.lua's `N casts from full` -- Deviation 2). `SpellsPane.headKind` (the family's kind while its view is drawn, nil on Whole book) picks the headers' amount word. |
| `UI/SpellTip_Forever.lua` | **The block in the same words (U9; mockup M5).** `Per second` -> `Per sec`; `Casts to OOM  6 from full, ~5 now` (was `6 full, ...`; an Other spell's line too); the suggested rank against this one in percent, `Rank 1 (+2% per mana)` (`-5% per mana` when it is lower, `same per mana` at 0; just `Rank 1` when a number is missing); `Dominated by` -> `Beaten by`; the detail key's hint (`Shift`) in `muted`, not `disabled`, since it tells you something (U7). The no-theme fallback `label` is #B3B3B3 too. |
| `tools/spellsui.lua` | The expected strings changed (below); assertions folded into existing checks, count unchanged. Helpers `TipText`, `TagHover`, `HeadHover`. |
| `tools/tipcheck.lua` | The expected strings changed (below); count unchanged. |
| `tools/themecheck.lua` | The token values and the legacy map changed (below); count unchanged. |

## What the suites now expect (a string change is the point: counts stay)

- `spellsui` (forever, 50): Whole book's and RANKS' tag `beaten` (was `dominated`); the tooltip's
  `N from full` read back for the pane-never-rewrites check; My spells' headers
  `Spell,Suggested,Value,Per mana,Casts,Highest,Value,Per mana`; **T38 the ranks table** also holds:
  row 1 (suggested and selected) has the white 2-px `pick` bar, row 2 none; the fill on row 1 is the
  suggested `0.10`, not `selected` 0.28; the gap's `R3` in `disabled` and its explanation in `muted`;
  `learn at 20` and `max` in `label`; the header `Per sec` in `label`; the header labels `Per sec`,
  `Casts`; hovering the headers gives `Casts / Casts in a row from a full pool.`, `Per sec / Healing
  per second of casting.`, `Heal / The average heal of one cast, from the spell's own text.`; the
  `best` tag's hover `Best / The rank SpellTuner suggests.`; the gap row has no tag hit (its row hover
  covers it). **T38 the rank card**: `Per sec` and `Casts` pairs; after selecting rank 2, rank 2 has
  the white bar and its zebra (0.03), not a `selected` fill, and rank 1 keeps the suggested fill and
  accent bar. **T38 a HoT ...**: Rejuvenation R1's tag `beaten`, its level in `text` (was `muted`),
  and its tag's hover `Beaten by Rank 2 / Per mana|<R2> vs <R1> / Per sec|<R2> vs <R1> / Rank 2 is
  better on both, and you know it.` with `dominatedBy` = R2's id. **T38 the refresh split**: the
  card's `Casts` pair.
- `tipcheck` (forever, 45): `Per sec` (was `Per second`) in seven per-second checks and the
  not-in-book shape; `N from full` (was `N full`) in the numbers check, the from-full / `~N now`
  check and the Other spell's line; `Rank 1 (+N% per mana)` for the suggested rank on another rank
  (was `Rank 1 (1.90 per mana)`); `Beaten by` (was `Dominated by`); the header's hint in `muted` (was
  `disabled`) in the header, macro-marker and dropdown checks.
- `themecheck` (forever, 37): `label` is `b3b3b3` and is the same table as `text2`; the legacy
  `dominated` reads `text` (was `muted`). The tbc half (9) is untouched.

The header's 12-px font is not asserted: the stub keeps `SetFontObject` only under `S.Geometry`
(`tools/wowstub.lua`, not this task's), so the check would only test the stub. It is in the
in-game list below.

## Failing first

The parent `7fd71b3` (extracted with `git archive`) with the three updated suites dropped in:

```
=== spellsui (forever)            43 ok, 7 failed
  FAIL each rank row shows the book's own numbers - id=774 col=tag got="dominated" want="beaten"
  FAIL the pane never rewrites the book's own casts to OOM - book entry=27 tooltip=nil from full=27
  FAIL T38 the ranks table: ... t78=nil ... fill1=0.28 heads=" //  // " best="" gapTip="no tag hit"
  FAIL T38 the rank card: ... Per s=51.2 over a 2.0 s cast; To OOM=never - regen keeps up; ...
  FAIL T38 a HoT, a hybrid and a spell with no value: ... hot=false(...)
  FAIL T38 the refresh split: ... full="nil" ...
  FAIL T39 My spells: ... labels=Spell,Suggested,Value,Per mana,To OOM,Highest,Value,Per mana ...
=== tipcheck (forever)            35 ok, 10 failed
  FAIL every number in the block is the book's - ... perSec=nil casts=inf
  FAIL the suggested rank comes first: on itself, on the others, and a dominated rank - ...
  FAIL a spell not in the book gets the header, per mana and per second - ...
  FAIL per second: plain for a cast, the GCD or a hybrid, over N s for a HoT or channel - cast=nil ...
  FAIL an absorb's per-second line is a plain number, never over - instant=nil cast=nil ...
  FAIL T37: casts to OOM from full, and ~N now only below max - full=33 full ... want=33 from full ...
  FAIL T37: the header says Rank N of M and the detail key in the muted colour (T78) - head=Rank 1 of 2  |cff4d4d4dShift|r ...
  FAIL T37: an Other spell gets two lines and no hint - ... casts=928 full want=928 from full ...
  FAIL T37: the macro marker - head=Rank 1 of 2 - macro  |cff4d4d4dShift|r ...
  FAIL T37: the detail key is a Settings -> General dropdown - ... hint=Rank 1 of 2  |cff4d4d4dAlt|r ...
=== themecheck (forever)          35 ok, 2 failed
  FAIL the text tokens' values (label = text2 b3b3b3, muted 7a7a7a, mana 4d99ff, bad e0605a)
  FAIL forever: dominated, note and tipGold read text, text2 and accent (T78)
=== themecheck (tbc)              9 ok, 0 failed
```

Mutations, on the branch (scratch copy):
- the white bar switched off (`pickBar = false`, the `selected` fill back): `spellsui` 48 ok, 2
  failed (`T38 the ranks table`, `T38 the rank card`).
- the tag back to `dominated` and the block's `Beaten by` line skipped: `spellsui` 48 ok, 2 failed
  (`each rank row shows the book's own numbers`, `T38 a HoT ...`); `tipcheck` 44 ok, 1 failed (`the
  suggested rank comes first ...`).

## Suite counts

Before: `7fd71b3`, `make check` 68 runs, all passed, 63 counted against 63 expected. After: this
branch, `make check` 68 runs, all passed, 63 counted against 63 expected; apicheck 0 findings
(8 Forever TOCs, 57 files, 47 globals), textcheck 0 findings (9 TOCs, 94 files). `luac -p` passes
on the four shipped files.

| Run | Before | After |
|---|---|---|
| `spellsui/forever` | 50 | 50 (strings changed) |
| `tipcheck/forever` | 45 | 45 (strings changed) |
| `themecheck/forever` | 37 | 37 (values changed) |
| `themecheck/tbc` | 9 | 9 |
| every other run | | equal |

Outputs compared with the parent's, run by run (`tools/.lua/check/*.out`, the parent's from a
`git archive` copy of `7fd71b3`): apart from table addresses, millisecond timings, the time-sliced
searches' evaluation counts (`replayui`, `reviewui` -- they move run to run) and `releasecheck`'s
paths (the scratch tree's name), the only differences are the three suites above and one line of
`themecheck` under both flavours (`131 reads` -> `132`: the token scan finds one more `UI.Hex` read,
the tags' `label`). **Every other suite's output is identical**, `dashui`, `navui`, `reviewui`,
`replayui`, `practiceui`, `spelltip`, `consolecheck`, `wincheck`, `reviewforever`, `clockcheck` and
`importcheck` included.

## Integrator lines

**TOCs**: none.

**`tools/data/expected-counts.json`**: no change.

**`CLAUDE.md`**, the files table:
- `UI/Theme_Forever.lua` row, append: ` **T78 (P34, review U7; mockup M5):** `label` and `text2` are one grey, #B3B3B3 (`T.text2 = T.label`); `muted` explanations and hints, `disabled` inert controls and the numbers of a rank you do not have; the legacy `dominated` reads `text` (a beaten rank's numbers are not greyed)`
- `UI/Dashboard_Rows.lua` row, append: ` **T78** (P34, review U1 / U10): generic-path options, off unless asked for -- `opts.selection = "bar"` (the selected row a white 2-px bar and no fill; the fill and accent bar the suggested row's alone), `opts.headerFont`, `col.cellTooltip(r, row)` (a cell that explains itself: a hit frame only when it has lines at draw time, the lines beside the cell, a click forwarded to the row), `col.tooltip` as a function of the label shown`
- `UI/SpellsPane_Forever.lua` row, append: ` **T78 (P34, review U1 / U7 / U9 / U10; mockup M5):** one vocabulary -- `Per sec`, `Casts` (`To OOM` and `Per s` gone from the table, My spells and the card); a sentence on every header's hover; the author's `beaten` for `dominated`, every tag explaining itself (a beaten rank: `Beaten by Rank N`, both numbers, `... is better on both, and you know it.`); tags in `label`, a gap's explanation in `muted`, a beaten row's numbers in `text`, headers 12 px in `label`; the selected rank a white bar, the fill the suggested one's alone`
- `UI/SpellTip_Forever.lua` row, append: ` **T78 (P34, review U9; mockup M5):** `Per sec`; `Casts to OOM  N from full, ~M now`; `Suggested  Rank 1 (+2% per mana)` against the hovered rank; `Beaten by Rank N`; the detail key's hint in `muted``

**`docs/TOOLS.md`** section 1:
- `spellsui.lua` row, append: ` Since **T78** (50, strings changed): `beaten`, `Per sec`, `Casts`; the selected rank's white bar with the fill the suggested row's; the gap's explanation `muted` and the tags `label`; the header sentences on hover; a tag's hover (`Best ...`, `Beaten by Rank 2` with both numbers)`
- `tipcheck.lua` row, append: ` Since **T78** (45, strings changed): `Per sec`, `N from full`, `Rank 1 (+N% per mana)`, `Beaten by`, the hint in `muted``
- `themecheck.lua` row, append: ` Since **T78**: `label` = `text2` = #B3B3B3, the legacy `dominated` on `text``

**`docs/TESTING.md`** section 44, a new item after 24 (Forever; needs a build with wave 17):

> **Words and tones (P34).** Spells -> Healing Touch (or any heal with three or more ranks): the
> RANKS headers read `Per mana  Per sec  Cast  Casts`, smaller than the numbers and in one light
> grey; hover each header: one sentence (Casts: `Casts in a row from a full pool.`). A rank another
> rank beats is tagged `beaten`, its numbers white; hover the tag: `Beaten by Rank N` with both per
> mana and per sec numbers. Click a rank that is not the suggested one: a white bar on its left, no
> orange fill; the suggested row keeps its fill and orange bar. A missing rank's line (`not in your
> spellbook ...`) and `learn at N` are readable. Hover a rank on an action bar: `Per sec`,
> `Casts to OOM  N from full`, on a rank that is not the suggested one `Suggested  Rank N (+M% per
> mana)`, on a beaten one `Beaten by Rank N`; the `Shift` hint is readable. Report if a header's
> sentence or a tag's tooltip overlaps the rank row's own tooltip, or if the header text looks
> larger than the numbers.

**`docs/DECISIONS.md`**, one line under the refactor plan's entries:

> **`beaten`, one label grey and a white selection bar on Forever (T78, P34, review U1 / U7 / U9,
> 2026-10-01; the author's answer 8.1 item 7, mockup M5).** The rank a rank beats on both per mana
> and per sec is tagged `beaten`, never `dominated`, and its tag names the rank that beats it; the
> table, the card and the tooltip say `Per sec` and count `Casts` (`N from full`); `label` and
> `text2` are one grey (#B3B3B3), `muted` is for explanations, `disabled` for inert controls and the
> numbers of a rank you do not have; the selected rank is a white bar so the fill means "suggested"
> alone. TBC keeps its words and its three greys until wave C gives it the theme (decision 10).

## Deviations

1. **The TBC grey unification is not in this task.** Section 8.1 item 7 says TBC's three greys
   "unify with the theme (follows from decision 10)", and the computed task says the TBC line must
   not change before wave C. TBC's greys live in `UI/Style.lua`'s `UI.TEXT` (the legacy tokens
   `dominated` #8A8A8A, `note`, `tipGold`) and in TBC's own files, none of which this task owns in
   wave 17; they unify when C1 turns `UI.THEMED` on for TBC and its tables read this theme. TBC's
   `dominated` note in its rank table (`UI/Dashboard_Rows.lua`'s `opts == nil` path) is unchanged;
   every TBC suite's output is identical (themecheck's tree scan counts one more token read).
2. **`Spells/Words.lua` is not in the wave table**, so the card's `Casts` value keeps its words
   (`19 casts from full`, `never - regen keeps up`) under the new label, and the table cell keeps
   `Words.Casts(n, "short")`. The tooltip's `N from full` is built in `UI/SpellTip_Forever.lua`, as
   its `N full` was. A later task that owns Words.lua can shorten the card's value to `19 from full`.
3. **Counts unchanged**, as the plan says ("the counts stay and the expected strings change"): the
   new behaviours (the white bar, the header sentences, the tag tooltips) are assertions folded into
   the existing T38 checks rather than new checks.
4. **The beaten row's numbers are `text`**, not `muted` as before: M5's "after" draws the beaten row
   in `text` (and M6 draws every beaten row so); the plan's own sentence lists only where `disabled`
   and `muted` go. The legacy token `dominated` carries it, so `UI/Dashboard_Rows.lua`'s colour
   choice is unchanged. The per-mana bar on a beaten row stays at 0.25 alpha (T30, held by `dashui`).
5. **The header's 12-px font is not asserted** offline (above).
6. **The rank table only.** The white selection bar is an option (`opts.selection = "bar"`), passed
   by the RANKS tables; Review's list (T71) keeps its `selected` fill, since nothing there is
   "suggested" and P34 names the rank table. `dashui`'s T30 check of the fill is untouched.
7. **SPEC-forever-ui.md** still says `Per s`, `To OOM` and `dominated` in 3.5 / 5.1; it is not an
   integrator-owned file nor this task's. The integrator may add a note there, or leave the spec as
   the record of the approved first design with M5 superseding it.
