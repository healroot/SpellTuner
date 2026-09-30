# T69 -- Colour tokens always present, one theme flag (plan P25)

Status: **built** 2026-09-30 on branch `plan/P25` (base `e0454fc`), wave 10 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No TOC line is needed: no file was added.

## The task (docs/PLAN-refactor-ux.md section 5, P25)

Review items (`docs/review/2026-09-30-project-review.md`): **A20** (the tokens and helpers half -- "the
theme is a half-seam": nine private copies of "read `UI.TEXT` if there, else a literal", with
disagreeing literals) and the palette fallbacks of **U31**; A6 (b) names the same change ("tokens always
present remove the `UI.TEXT and` gates").

- (a) `UI/Style.lua` defines `UI.THEMED = false`, `UI.PALETTE` and `UI.TEXT` with today's TBC literals;
  `UI/Theme_Forever.lua` sets `UI.THEMED = true` and overwrites the tables.
- (b) Every existing "is the theme on" test becomes `UI.THEMED`, because `UI.TEXT` is no longer nil on
  TBC.
- (c) A `UI.TEXT and` that only picks a colour becomes a token read (`UI.Hex` / `UI.RGB` /
  `UI.Fill`), TBC's token holding the old literal; where TBC files disagree the default table keeps
  each value under a named legacy token (unifying them is P34's question to the author).
- Tests: `themecheck` +4 (THEMED false on TBC / true on Forever; TBC's tokens equal the old literals;
  Review's small font on TBC is `GameFontHighlightSmall`; no `UI.TEXT and` left in a UI file, by
  scanning); equal counts in `dashui`, `navui`, `reviewui`, `replayui`, `practiceui`, `spellsui`,
  `practiceforever`, `replayforever`.
- TBC: shared files, no visible change.

Owned files (section 4, wave 10): `UI/Style.lua`, `UI/Theme_Forever.lua`, `UI/Dashboard_Rows.lua`,
`UI/Tooltip.lua`, `UI/BindingsWindow.lua`, `UI/PracticePanel.lua`, `UI/SpellsPane_Forever.lua`,
`UI/ReplayWindow.lua`, `UI/Dashboard_Review.lua`, `UI/SpellTip_Forever.lua`, `tools/themecheck.lua`.
All eleven were edited and committed, plus this task file.

## What was built

### The tokens (UI/Style.lua)

`UI.THEMED = false`. `UI.TEXT.<token> = { r, g, b, hex = "|cffrrggbb" }` right after the accent, so
every later file (and the theme) finds it; `UI.Token(hex[, r, g, b])` builds one (the theme uses it
too, so there is one parser).

| token | TBC value | who read it on TBC before | Forever (theme) |
|---|---|---|---|
| `accent` | `ffcc00` (1, 0.8, 0) | Review's run line, the replay's header / run strip / "paused", the bindings' waiting key -- each `... or "\|cffffcc00"` | the class colour (unchanged) |
| `text` | `ffffff` | the rank table's plain row | `ffffff` |
| `muted` | `888888` | the rank table's header, practice's grey, the bindings hint | `7a7a7a` |
| `disabled` | `555555` | the rank table's not-learned row | `4d4d4d` |
| `text2`, `label`, `mana`, `good`, `bad` | 4.1's values (`b3b3b3`, `9d9d9d`, `4d99ff`, `5ccb6e`, `e0605a`) | nothing on TBC reads them | 4.1's values |
| **`dominated`** (legacy) | `8a8a8a` | the rank table's dominated row (`muted` is `888888`) | = `muted` |
| **`note`** (legacy) | `ffcc00` | the bindings import's notes, practice's "every <role>" rows (text2 under the theme, gold on TBC) | = `text2` |
| **`tipGold`** (legacy) | `ffd100` (1, 0.82, 0) | `MD.Tip`'s suggested-rank value (the accent is `ffcc00`) | = `accent` |

`UI.PALETTE` (already always present) gains the rank table's option fills with the literals
`UI/Dashboard_Rows.lua` carried: `rowAlt` (1, 1, 1, 0.03), `hover` / `selected` / `suggested` (accent
at 0.12 / 0.28 / 0.10), `line` (0x2A grey). The window's own four (`frame`, `header`, `pane`, `border`)
are unchanged.

`UI.Hex(token)`, `UI.RGB(token)` (r, g, b), `UI.Fill(key)` (r, g, b, a). An unknown name paints white
rather than raising into a paint; `themecheck` scans the tree so no unknown name ships (below).

### The theme (UI/Theme_Forever.lua)

Writes its 4.1 text tokens **into** `UI.TEXT` (in place, like the palette already was), maps the three
legacy tokens onto `muted`, `text2`, `accent`, and sets `UI.THEMED = true`. The header comment now says
what TBC keeps. Values are unchanged (the accent token is built from the same `accentHex` and `A`).

### (b) the gates, now `UI.THEMED`

| site | what the branch decides |
|---|---|
| `UI/Dashboard_Review.lua` `SMALL` | the pane's small font (`UI.FONT_SMALL` themed, `GameFontHighlightSmall` on TBC) |
| `UI/PracticePanel.lua` `themed` | the panel's layout (the wrapping fight row, the summary line, "you" tag, `OnSizeChanged`) |
| `UI/PracticePanel.lua` / `UI/BindingsWindow.lua` `Title` | whether a tooltip's first line is coloured at all (TBC: the text as is, the client's gold) |
| `UI/SpellTip_Forever.lua` `C` | the block's colours: the theme's, else its own spec values -- **not** TBC's tokens (the gold would reach the block) |
| `UI/Style.lua` `TextRGB` (the rail, sheets) | each call's own literal without the theme, as before |

### (c) the colour picks, now token reads

- `UI/Dashboard_Rows.lua`: `FillColor` and `TextHex` gone -> `MD.UI.Fill(key)`, `MD.UI.Hex("muted" /
  "disabled" / "dominated" / "text")`. `AccentHex` stays (the class colour on both lines, formatted by
  this file; `UI.accentHex` rounds differently, so replacing it would move TBC's header by a digit).
- `UI/PracticePanel.lua`: `Hex` gone; `GREY = UI.Hex("muted")`, the role rows `UI.Hex("note")`, "you"
  and the summary `UI.Hex("accent")` / `UI.Hex("text")`.
- `UI/BindingsWindow.lua`: `Hex` gone; the waiting key `UI.Hex("accent")`, the notes `UI.Hex("note")`,
  the hint `UI.Hex("muted")`.
- `UI/ReplayWindow.lua`: `Hi()` is `UI.Hex("accent")`.
- `UI/Dashboard_Review.lua`: `RUN_HI = UI.Hex("accent")`.
- `UI/Tooltip.lua`: `GOLD = { UI.RGB("tipGold") }`.
- `UI/SpellsPane_Forever.lua` (Forever only; the theme always precedes it): `Hex`, `SetColor`, `Tok`
  gone -- 16 `UI.Hex(...)`, 20 `fs:SetTextColor(UI.RGB(...))`, 5 `UI.RGB(...)` -- and the section title
  reads `UI.TEXT.accent`. Its `UI.PALETTE and ...` / `UI.PALETTE or {}` reads are left (the palette was
  always present; they gate nothing).
- `UI/Style.lua`: the two dropdown lists' `UI.PALETTE and UI.PALETTE.header or {0.115...}` are
  `UI.PALETTE.header` (the same value on both lines).

### tools/themecheck.lua

`HARNESS_FLAVOUR = { "forever", "tbc" }`. **New tbc run (7)** -- the harness does not load UI files on
TBC, so the run loads `UI/Style.lua`, `UI/Tooltip.lua`, `UI/Dashboard_Review.lua` itself (as
`reviewui` does) and wraps the stub's `CreateFontString` to record the template:

1. `UI.THEMED` is false with `UI/Style.lua` alone.
2. `UI.TEXT` is present, every 4.1 and legacy token shaped.
3. The tokens hold the literals the shared files carried (accent `ffcc00` at 1 / 0.8 / 0, text, muted
   `888888`, disabled `555555`, dominated `8a8a8a`, note `ffcc00`, tipGold 1 / 0.82 / 0).
4. `UI.Hex` / `UI.RGB` / `UI.Fill` read them.
5. The palette keeps its window fills and carries the table's old ones.
6. Review's small text is `GameFontHighlightSmall`, never `UI.FONT_SMALL` (3 font strings at build).
7. Every `UI.Hex("x")` / `UI.RGB("x")` / `UI.Fill("x")` literal under `UI/` and `Modules/` names a
   token TBC's tables carry (59 reads).

**Forever +5 (23 -> 28)**: `UI.THEMED` is true; `dominated`, `note`, `tipGold` read `muted`, `text2`,
`accent`; `UI.Hex` / `UI.RGB` / `UI.Fill` read the theme; **no UI file gates on `UI.TEXT`** (a scan of
every `UI/*.lua` and module file, comments stripped, for `UI.TEXT and`, `UI.TEXT ~= nil`, `== nil`,
`if UI.TEXT then`, `not UI.TEXT`, `UI.TEXT or`); every token literal in the tree is in the theme's
tables. The existing "Blizzard gold is absent from UI.TEXT" check now also covers the legacy keys.

The plan asked for +4; this is +5 on Forever and 7 on the new tbc run (the token-name scan under both
flavours is the addition -- `UI.Hex` with a typo paints white silently, so the scan is its guard).

## Tests first

`tools/themecheck.lua` was written before any source change and run on the parent's files
(`e0454fc`):

```
tbc: UI.THEMED is false with UI/Style.lua alone                          FAIL - nil
tbc: UI.TEXT is present, every 4.1 and legacy token shaped               FAIL
tbc: the tokens hold the literals the shared files carried               FAIL - accent=nil muted=nil disabled=nil dominated=nil note=nil
tbc: UI.Hex / UI.RGB / UI.Fill read the tokens                           FAIL
tbc: the palette keeps its window fills and carries the table's old ones FAIL
tbc: Review's small text is GameFontHighlightSmall, never the kit's      ok - 3 GameFontHighlightSmall, 0 UI.FONT_SMALL
tbc: every UI.Hex / UI.RGB / UI.Fill token in the tree is in TBC's tables FAIL - 0 reads
1 ok, 6 failed                                                            (exit 1)

forever: the theme sets UI.THEMED                                        FAIL - nil
forever: dominated, note and tipGold read muted, text2 and accent        FAIL
forever: UI.Hex / UI.RGB / UI.Fill read the theme                        FAIL
forever: no UI file gates on UI.TEXT (UI.THEMED is the switch)           FAIL - UI/BindingsWindow.lua:43 UI/BindingsWindow.lua:50 UI/Dashboard_Review.lua:28 UI/Dashboard_Review.lua:29 UI/PracticePanel.lua:27 UI/PracticePanel.lua:33 UI/PracticePanel.lua:102 UI/ReplayWindow.lua:33 UI/SpellsPane_Forever.lua:54 UI/SpellsPane_Forever.lua:58 UI/SpellsPane_Forever.lua:234 UI/SpellsPane_Forever.lua:1766 UI/Style.lua:772 UI/Tooltip.lua:26
forever: every UI.Hex / UI.RGB / UI.Fill token in the tree is in the theme's tables FAIL - 0 reads
23 ok, 5 failed                                                           (exit 1)
```

(The Review-font line passes on the parent: it is the guard for this task's conversion, which is where
it would break -- see the first mutation.) After: tbc `7 ok, 0 failed`, forever `28 ok, 0 failed`.

**Mutations on the finished branch** (one `sed` each, reverted by the reverse `sed`):

| mutation | result |
|---|---|
| Review's `SMALL` gated on `UI.TEXT and` again (the gate this task converts, now that the tokens are on TBC) | themecheck tbc 6 / 1 (`0 GameFontHighlightSmall, 3 UI.FONT_SMALL`), forever 27 / 1 (`UI/Dashboard_Review.lua:29`); **reviewui 49 and dashui 64 green** |
| practice panel's `themed = UI.TEXT ~= nil` again | practiceui 51 / 1 (`the panel lists what your presses cast`: TBC got the Forever summary); themecheck forever 27 / 1 (`UI/PracticePanel.lua:99`); dashui 64 green |
| TBC's `muted` token `888888` -> `7a7a7a` | themecheck tbc 6 / 1; **practiceui 52, dashui 64, reviewui 49, navui 35 all green** |

The first and third rows are why the tbc run exists: no existing TBC suite sees a TBC font or grey move.

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

| suite | before (`e0454fc`) | after |
|---|---|---|
| `themecheck` (forever / tbc) | 23 / -- | **28 / 7** |
| every other suite | adaptercheck 23 / 16, bindscheck 6, bookcheck 22 / 2, clockcheck 23, coachforever 21, consolecheck 20 / 1, corecheck 24 / 24, costcheck 3, dashui 64, defaultscheck 48 / 52, forevercheck 16, gatecheck 11, importcheck 21, kitcheck 11 / 3, measurecheck 30, migrate 7, modulecheck 19, navui 35, parsecheck 15, practice 84, practiceforever 28, practiceui 52, probecheck 88, reccheck 63, recordcheck 31, recordingscheck 32 / 32, regencheck 27, releasecheck 21, replaycheck 82, replayforever 15, replayui 103, restcheck 51, reviewforever 13, reviewui 49, runcheck 81, scenariocheck 14, simcheck 13, simwindow 8, slashcheck 8, solvercheck 84, spellsui 48, spelltip 48, svcheck 6 / 1, tabscheck 24, timeline 27, tipcheck 38, ttocheck 45, verifycheck 14, wincheck 55, lib/t 12 | all equal, all passing |
| harness-skip, reproduce-smoke, strategies-smoke | ok | ok |
| `apicheck.py` / `--selftest` | 0 findings, 54 files / 13 | 0 findings, 54 files / 13 |
| `textcheck.py` / `--selftest` | 0 findings, 90 files / 2 | 0 findings, 90 files / 2 |
| `refcheck.py --selftest` | 2 | 2 |

`tools/check.sh`: 68 runs, all passed, rc 0; its notes are `themecheck/forever: 28 assertion(s), 23
expected` and `themecheck/tbc: 7 assertion(s), not in the expected counts`.

**Every suite's saved output was compared with the parent's** (`tools/.lua/check/*.out`, 67 files),
with table addresses, `N ms` timings and `N frames` normalised: identical except `themecheck` and two
lines that move between runs of the same tree (the frame-sliced search: `coachforever`'s `frames=3` vs
`2`, and the order of `replayui`'s `[sim] search N evaluations` lines -- three runs of the branch's
`replayui` gave 17/19/33/39, 16/19/33/40 and 19/17/37/37). So the TBC suites the plan names (`dashui`,
`navui`, `reviewui`, `replayui`, `practiceui`) and the Forever ones (`spellsui`, `practiceforever`,
`replayforever`, `tipcheck`) print byte for byte what they printed -- every colour code and font they
read, on both lines.

`luac -p` on all eleven changed files: clean.

## Integrator lines

- **TOCs:** none (no new file).
- **`tools/data/expected-counts.json`:** `"themecheck/forever": 28` (was 23), and a new
  `"themecheck/tbc": 7`.
- **`docs/TOOLS.md`** section 1, the `themecheck.lua` row, replace with:
  `| themecheck.lua | **the theme and its switch** (T29, T69; forever 28, tbc 7): no gold in UI.TEXT, the fonts built, a font offset of +4 clamped to +2, UI.Pitch(20) at -2 / 0 / +2, UI.px at scales 0.64 / 0.71 / 1, UI.RestylePixels giving a registered frame the new edge; UI.THEMED true, the legacy tokens on 4.1's, no UI file gating on UI.TEXT (a scan). Under tbc: UI.THEMED false, TBC's tokens equal to the literals the shared files carried, Review's small font GameFontHighlightSmall, every UI.Hex / UI.RGB / UI.Fill name in the tree present |`
- **`CLAUDE.md`**, the `UI/Style.lua` row, append:
  `**T69 (P25):** UI.THEMED (false here, true once UI/Theme_Forever.lua runs) is the one "is the Forever look on" test; UI.TEXT and UI.PALETTE are always present with TBC's literals (legacy tokens dominated / note / tipGold where TBC's files disagreed), the theme overwrites them in place; UI.Hex / UI.RGB / UI.Fill read a token -- a colour is a token read, never a gate.`
  and in "Conventions and constraints" (or the Forever rule in "Verifying changes"), one line:
  `- **Forever-only look gates on UI.THEMED** (T69), never on a token being set; a token read (UI.Hex("muted")) is a colour. tools/themecheck.lua fails on a UI.TEXT gate in any UI file.`
- **`docs/DECISIONS.md`:** no TBC behaviour changed, so no entry is required. If the integrator wants
  the legacy tokens on record for P34: `T69 (P25): TBC's three disagreeing literals kept as named tokens
  -- dominated 8a8a8a (muted is 888888), note ffcc00 (text2's TBC stand-in), tipGold ffd100 (accent is
  ffcc00). Unifying them moves TBC and is P34's question to the author (plan section 8).`
- **`docs/HISTORY.md` / `docs/TESTING.md`:** nothing in-game to test beyond "TBC looks as before"
  (plan section 9's kit items already say so).

## Deviations

- **themecheck grew by 5 on Forever and gained a 7-assertion tbc run**, not +4 in one run: the plan's
  "UI.THEMED false on TBC", "TBC's tokens equal the old literals" and "Review's small font on TBC" can
  only be asserted without the theme, and the forever harness always loads it; so the suite declares
  both flavours and the TBC half runs the kit on the tbc harness. The token-name scan (both runs) is
  extra: `UI.Hex` of a misspelt token would paint white silently.
- **SpellTip's block keeps its own fallback values without the theme** (gated on `UI.THEMED`) rather
  than falling to TBC's tokens: TBC's `accent` is gold, which the block's comment forbids, and the file
  is Forever-only anyway.
- **`UI/Style.lua`'s private `Fill` (the rail, sheets, the mask) was left as it was**: gating it on
  `UI.THEMED` would change what it returns on TBC for `pane` (the TBC palette's 0.13 against the
  call's 0.11). Nothing on TBC builds those widgets; with `line` now in TBC's palette the rail's
  separator would read 0x2A/255 (0.1647) instead of its call's 0.165 there -- unreachable on TBC.
- **The kit's primitives still carry literals** (`CreateButton`, `CreateCheckButton`, ... -- A20's
  other half): P25's scope is the tokens and helpers; the primitives are P30/P31's (waves 13-14).
- `UI/Dashboard_Rows.lua`'s `AccentHex` and the non-bar header's `|cff888888`, the replay's
  `|cff888888space to go on`, and `SpellsPane`'s `UI.PALETTE or {}` reads are unchanged: none is a
  theme test, and replacing `AccentHex` with `UI.accentHex` would round TBC's header colour
  differently.
