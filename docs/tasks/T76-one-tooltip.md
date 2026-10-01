# T76 -- One tooltip (plan P32)

Status: **built** 2026-10-01 on branch `plan/P32` (base `19ffac6`), wave 15 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its TOC lines (below)**:
`UI/Tooltip.lua` is gone (split into the new `UI/Tip.lua` and `UI/Tip_TBC.lua`), and every TOC that
listed it, or must now list the new files, is integrator-owned. Without the lines 15 runs fail on the
committed tree (`clockcheck`, `coachforever`, `defaultscheck/tbc`, `importcheck`, `modulecheck`,
`practiceforever`, `probecheck/tbc`, `releasecheck`, `replayforever`, `reviewforever`, `spellsui`,
`tipcheck`, `wincheck`, `apicheck`, `textcheck`, and so the counts -- checked). The lines were **not** applied in the
worktree, not even temporarily: the session's permission layer refused an edit to the TOCs
(integrator-owned). Every suite was run instead in a scratch copy of the worktree with the lines
below applied to the copy's TOCs (`tools/check.sh` of that copy), and against the parent commit
`19ffac6` extracted with `git archive` for the failing-first runs.

## The task (docs/PLAN-refactor-ux.md section 5, P32)

Review items (`docs/review/2026-09-30-project-review.md`): **A21** (four tooltip line formats, three
tooltip frames, placement living in a pane, `UI/Tooltip.lua` on the wrong TOC), **U2** (two tooltip
skins in one window), **U13** (`UI.SetTooltips`: anchor frozen at the first call, lines 2+ forced
white, disabled buttons silent), **U28** (Review's wide rows put the tooltip at the far edge), **U10**
(the mechanism: a header hover on the generic table), **U9** (the Forever clock hover). Mockups:
`docs/mockups/refactor-ux.html` M1 (the kit tooltip, `.gt`: a title, then a wrapped `text2` line), M2
("Row hover: the gate tooltip opens beside the cursor and flips at the edge (P32)") and M6 (the clock
lines as label/value pairs, `Out of mana in` / `Full again in ... if you stop`).

## What was built

| File | Change |
|---|---|
| `UI/Tip.lua` (new; both main TOCs) | `MD.Tip`: the one line model `{ l, r, c, rc, wrap }` where a colour is an `{r, g, b}` array or a **token name** read through `UI.RGB` at render time (`Tip.Color`); `Tip:Render(tt, lines)` (the old renderer, plus token names and bare strings); `Tip.Simple(list)` (the kit's shape: title in `text`, later strings in `text2` and wrapped, a later table a line of its own); `Tip:Place(tt, owner, "beside" \| "cursor")` -- "beside" is SpellsPane's old `Place` moved in unchanged (TOPLEFT at the owner's TOPRIGHT + `Tip.GAP` 6, flipped to TOPRIGHT at its TOPLEFT - 6 at the screen's right edge), "cursor" places beside the **pointer** for an owner wider than `Tip.WIDE` (300) and flips the same way, beside the owner otherwise; `Tip:Show(owner, lines, { anchor, x, y })` (new shape, anchor "beside" by default, or any `ANCHOR_*`) and `Tip:Show(owner, anchor, lines...)` (the old shape, every existing caller's: on TBC exactly what it did; under `UI.THEMED` an `ANCHOR_RIGHT` / `ANCHOR_CURSOR` / nil anchor is placed "cursor"); `Tip:ShowAt`, `Tip:Hide` as before; **`Tip:Skin(tt, owner)` / `Unskin` / `Skinned`** -- under `UI.THEMED` only, the kit tooltip's look laid on a game tooltip SpellTuner owns: a `tip` fill and four `UI.px(1)` `border` edges as textures in the tooltip's BACKGROUND layer, the game's NineSlice faded to 0 and given its alpha back when the skin comes off (on `OnHide`, or `OnTooltipCleared` for another owner); `Tip:Kit(owner, lines, opts)` -- the same lines into the kit tooltip (`UI.tooltip`), placed the same ways. |
| `UI/Tip_TBC.lua` (new; TBC TOC) | The RankMath-bound builders moved out of `UI/Tooltip.lua` **unchanged** (`Mana`, `Fights`, `Row`, `Spell`, `Damage`, `Columns`, `Clock`; a `diff` of everything from `-- Mana state` to the end of the old file against the new one is empty), with the colour locals they read. |
| `UI/Tooltip.lua` | **Deleted** (the two files above). The Replay module no longer lists it; `MD.Tip` (renderer, Show / Hide, placement) is on the Forever main TOC now, so Review and the replay keep their hovers with no TBC content on Forever. |
| `UI/Style.lua` | `UI.PALETTE.tip = { 0.1, 0.1, 0.1, 0.9 }` (the kit tooltip's TBC literal, now a token). Under `UI.THEMED`: the kit tooltip (`SpellTunerTooltip`) is drawn with the `tip` fill and a 1-px `border` edge at the physical pixel (the same skin `Tip:Skin` lays on GameTooltip; TBC keeps its accent edge); `UI.SetTooltips` is sugar over `MD.Tip:Kit` -- `Tip.Simple`'s shape (no more forced white: a table line keeps its own tone) and the anchor of the **latest** call (stored as `widget._tipAnchor`); `UI.CreateButton` sets `SetMotionScriptsWhileDisabled(true)`, so a disabled button's tooltip still shows, and its hover colour is skipped while it is disabled. TBC: every one of these paths is the old code, byte for byte. |
| `UI/SpellsPane_Forever.lua` | `Place` asks `MD.Tip:Place(tt, row, "beside")`; `KitTip` is `MD.Tip:Kit(owner, Tip.Simple({ title, ... }), { anchor = "beside" })`; the rank row's game tooltip stays **GameTooltip** (decision 7, its content kept) and gets `MD.Tip:Skin(tt, row)` before it shows. |
| `UI/SpellTip_Forever.lua` | Each line `Pair` / `Single` builds also carries the line model's named fields (`l`, `r`, `c`, `rc`, the same text and colours); `SpellTip:Render` takes a line with only named fields through `MD.Tip:Render`, and the positional arrays as before (one release). |
| `UI/Clock_Forever.lua` | The hover is `Clock:HoverLines(now)` through `MD.Tip:Show(self, lines, { anchor = "ANCHOR_TOP" })`: a title, then label / value pairs -- `Mana ~N of M`, `Out of mana in ~m:ss` (oom), `Full again in ~m:ss` (full / out of combat), `a few more casts first` (warm-up), `not at this pace` / `--` (hold), `Full now`; in combat `Full again in ~m:ss if you stop`, `Spending ~N a sec over N casts`, `Regen ~N a sec`; `Unpriced casts N` when any; then a muted, wrapped `~ = modelled from your casts. The bar under the clock is your real mana, drawn by the game.` and `Left-click | open the window (out of combat)`. Times are the clock's own rounding (5 s, `>10m`, `--`). No "secret", no "Anchored". `OnLeave` is `MD.Tip:Hide()`. |
| `UI/Dashboard_Rows.lua` | Generic path only: a column's `col.tooltip` (a sentence, or a list of line-model lines) shows on its header label -- a hit frame per such column on the header row (hidden when the row is released, since a pooled row also serves as a data row), the label in `text` and the sentence in `text2`, through `MD.Tip:Show(..., { anchor = "ANCHOR_TOPLEFT", y = 3 })`. A column without one has no hover; the TBC rank table's columns carry none (its whole-row `Tip:Columns` glossary is unchanged). The words are P34's. Two comments now say the TBC-only reads are `MD.Tip:Row / :Columns`. |

What `MD.Tip:Show` renders into, by line: **TBC** -- GameTooltip, unskinned, exactly as before.
**Forever** -- GameTooltip in the kit skin (see Deviations 1 for why not the kit frame). The kit's
own controls render into `UI.tooltip`, which under the theme wears the same skin.

## Failing first

The parent `19ffac6` (from `git archive`) with T76's five owned suites dropped in (dashui and
spelltip pointed back at the parent's `UI/Tooltip.lua`):

```
=== tipcheck (forever)            38 ok, 6 failed
  FAIL T76: MD.Tip is on the Forever main TOC, without the TBC builders - tip=false has=false none=false
  FAIL T76: one line model -- token names or arrays, a spacer, wrap, a bare string - ok=nil calls=0
  FAIL T76: Tip:Show renders into GameTooltip in the kit skin, off again when it hides - no MD.Tip
  FAIL T76: beside a row, beside the pointer on a wide one, flipped at the right edge - no MD.Tip
  FAIL T76: a disabled kit button still explains itself; its tooltip takes the latest anchor and tones - motion=nil enter=false anchor=ANCHOR_TOPLEFT lines=2 first=|cffffffffThis fight does not replay.
  FAIL T76: SpellTip:Render takes the shared line shape; Lines carries it beside the arrays - render=false named=false calls=2
=== clockcheck (forever)          24 ok, 5 failed
  FAIL every projection is marked modelled, in the text and the hover - textHalf=true hoverHalf=false
  FAIL T76: in a fight the hover says when mana runs out and when it is full again, as pairs - clock="~OOM 9:40  rest 0:05" out=nil full=nil spend=nil mana=nil
  FAIL T76: out of combat the hover says when it is full again, with no fight lines - clock="~FULL 0:05" full=nil
  FAIL T76: the hover is MD.Tip's, in the kit skin while it shows and out of it after - skinned=false after=false
  FAIL an unpriced opener stays in the hover's unpriced count - ... "Anchored 0:25 ago: assumed full at login" ...
=== reviewforever (forever)       20 ok, 2 failed
  FAIL T76: a Review row's tooltip opens beside the pointer, top-aligned with the row - w=840 point=CENTER CENTER false x=0 y=0 lines=14
  FAIL T76: at the screen's right edge it flips to the pointer's left - point=CENTER CENTER x=0 want 794
=== dashui (tbc)                  66 ok, 1 failed
  FAIL T76: a header label shows its column's tooltip - header=true hit=false lines=0 plain=false
=== spelltip (tbc)                48 ok, 1 failed
  FAIL T76: TBC's Tip:Show is GameTooltip, unskinned - lines=2 builders=true
```

(`dashui`'s second new check, "a disabled TBC button has no motion scripts", is a TBC-unchanged
guard and passes on the parent by design.) The two clockcheck assertions that existed before T76
("every projection is marked modelled", "an unpriced opener ...") were rewritten to the new words:
they now ask for `~ =` / `modelled` and the absence of `secret` / `anchored`, and for the pair
`Unpriced casts 1`.

Mutations, on the branch (scratch copy):
- `Tip:Place`'s cursor flip forced off: `tipcheck` 43 ok, 1 failed (`cursorFlip=TOPLEFT`), and
  `reviewforever` 21 ok, 1 failed (`x=806 want 794`).
- `Tip:Skin` returning at once: `tipcheck` 43 ok, 1 failed (`skinned=false ... legacy=false`), and
  `clockcheck` 28 ok, 1 failed (`skinned=false after=false`).

## Review fix (first review)

The reviewer found `Tip:Place`'s "cursor" branch handing the pointer's offset to `tt:SetPoint` in the
**owner's** units (`x = cx / Scale(owner) - left`), while a point's offset is applied in the
**tooltip's** own effective scale. They agree only when the two scales are equal: a Review row sits
in the main window, which `MD.Win` scales by `db.ui.scale` (70-120 %), and GameTooltip does not take
that scale. At 80 %, owner left edge 0, pointer at 480 physical px, the tooltip's TOPLEFT landed at
606 px (126 px right of the pointer); flipped, its TOPRIGHT covered the pointer. Fixed: the offset
is converted, `local off = x * rs / ts`, then `TOPLEFT ... off + gap` / `TOPRIGHT ... off - gap` -- the
tooltip lands `Tip.GAP` beside the pointer at any window scale. The flip test already read `cx` in
physical pixels and is unchanged; the "beside" branch's `gap` stays a constant in the tooltip's units.

New `tipcheck` assertion ("beside the pointer in the tooltip's units when the owner is scaled (80
%)"): an owner at `GetEffectiveScale() = 0.8`, 1200 wide from x 0, a tooltip at 1 and 200 wide, the
screen 1000 wide. Pointer at 480 -> TOPLEFT at 486; pointer at 900 -> flipped, TOPRIGHT at 894.
On the branch before the fix (scratch copy, TOC lines applied): `44 ok, 1 failed` --
`pointer 480 -> TOPLEFT/606 (want TOPLEFT/486); pointer 900 -> TOPRIGHT/1119 (want TOPRIGHT/894)`;
after: `45 ok, 0 failed`. `tools/check.sh` of that copy (TOC lines and the counts below applied): 68
runs, all passed, 63 counted against 63 expected; apicheck 0 findings (8 TOCs, 57 files), textcheck
0 findings (9 TOCs, 94 files). `luac -p` passes on `UI/Tip.lua` and `tools/tipcheck.lua`.

## Suite counts

Before: `19ffac6`, `tools/check.sh` 68 runs, all passed (63 counted). After: this branch with the TOC
lines applied (scratch copy), 68 runs, all passed (63 counted):

| Run | Before | After |
|---|---|---|
| `tipcheck/forever` | 38 | **45** (44 before the review fix) |
| `clockcheck/forever` | 26 | **29** |
| `reviewforever/forever` | 20 | **22** |
| `dashui/tbc` | 65 | **67** |
| `spelltip/tbc` | 48 | **49** |
| every other run | | equal |
| `apicheck` | 0 findings, 8 Forever TOCs, 57 files, 47 globals | the same (one file in, `UI/Tooltip.lua` out of the module) |
| `textcheck` | 0 findings, 9 TOCs, 93 files | 0 findings, 9 TOCs, **94** files |
| `releasecheck` | TBC package 63 files, Forever 31 | TBC **64**, Forever **32** (counts unchanged, 21) |

Outputs compared with the parent's, run by run (`tools/.lua/check/*.out`): apart from table
addresses, millisecond timings and the time-sliced searches' evaluation counts (`reviewui` 39/37,
`simwindow` 6/5 frames -- they move run to run), the only differences are the five suites above,
`replayforever`'s T43 detail (`row=nil ...`, Deviations 3), `themecheck`'s token-read count (129 ->
131: `UI.Fill("tip")` read twice), `practiceforever`'s printed summary hover (the kit tooltip's
lines 2+ no longer carry the forced `|cffffffff` prefix -- U13) and the build line counts above.
**Every TBC UI suite's output is otherwise identical** (`navui`, `reviewui`, `replayui`,
`practiceui`, `spelltip`, `consolecheck`, `simwindow`, `ttocheck`, `importcheck`, `dashui`'s old 65).

## Integrator lines

**`SpellTuner_TBC.toc`** -- `UI\Tooltip.lua` replaced by two lines, same place:

```
UI\ContextMenu.lua
UI\Tip.lua
UI\Tip_TBC.lua
UI\SpellTooltip.lua
```

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical) -- one new line after
`UI\ContextMenu.lua`:

```
UI\ContextMenu.lua
UI\Tip.lua
UI\Dashboard_Rows.lua
```

**`Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc`** and **`SpellTuner_Replay.toc`** --
delete the line `UI\Tooltip.lua` (between `Engine\ReplayTrace.lua` and `UI\ReplayWindow.lua`).

**`tools/data/expected-counts.json`**: `"tipcheck/forever": 45,` (was 38), `"clockcheck/forever":
29,` (was 26), `"reviewforever/forever": 22,` (was 20), `"dashui/tbc": 67,` (was 65),
`"spelltip/tbc": 49,` (was 48). Every other count unchanged.

**`CLAUDE.md`**, the files table:
- The `UI/Tooltip.lua` row is replaced by two rows:
  - `| `UI/Tip.lua` | **The one tooltip** (T76, P32, review A21 / U2 / U13 / U28; both main TOCs): `MD.Tip` -- the line model `{ l, r, c, rc, wrap }` (a colour an `{r, g, b}` or a token name), `Render`, `Tip.Simple` (title in `text`, the rest `text2` wrapped), `Place(tt, owner, "beside" \| "cursor")` (beside the row, or beside the pointer on an owner wider than `Tip.WIDE`, flipped at the screen's right edge), `Show(owner, lines, { anchor })` and the old `Show(owner, anchor, lines...)`, `ShowAt`, `Hide`, `Kit` (the kit tooltip), and under `UI.THEMED` `Skin` / `Unskin` / `Skinned` -- the kit's flat fill and 1-px edges on a GameTooltip SpellTuner owns, off again when it hides or another owner clears it. `Show` renders into GameTooltip on both lines (skinned on Forever) |`
  - `| `UI/Tip_TBC.lua` | **The TBC tooltip builders** (T76, P32; TBC TOC, right after `UI/Tip.lua`): `MD.Tip`'s `Mana`, `Fights`, `Row`, `Spell` (v0.14.9), `Damage` (v0.15.3), `Columns`, `Clock` -- moved out of `UI/Tooltip.lua` unchanged; they read RankMath / SpellData / the TBC regen model. Every TBC hover surface goes through them |`
- `UI/Style.lua` row, append: ` **T76 (P32, review U2 / U13):** `UI.PALETTE.tip` (the kit tooltip's fill); under `UI.THEMED` the kit tooltip has a 1-px `border` edge (TBC: its accent edge), `UI.SetTooltips` is sugar over `MD.Tip:Kit` (a later line may be a line-model table with its own tone; the latest call's anchor), and `CreateButton` sets `SetMotionScriptsWhileDisabled` so a disabled button still explains itself (its hover colour skipped while disabled). TBC unchanged`
- `UI/SpellsPane_Forever.lua` row, append: ` **T76 (P32):** the row placement is `MD.Tip:Place(.., "beside")` and the reasons `MD.Tip:Kit`; the rank row keeps GameTooltip (decision 7) in the kit skin (`MD.Tip:Skin`)`
- `UI/SpellTip_Forever.lua` row, append: ` **T76 (P32, review A21):** each line also carries the line model's named fields (`l`, `r`, `c`, `rc`); `SpellTip:Render` takes a named-only line through `MD.Tip:Render`, the positional arrays for one release`
- `UI/Clock_Forever.lua` row, append: ` **T76 (P32, review U9):** the hover is `Clock:HoverLines(now)` through `MD.Tip:Show` -- label / value pairs (`Mana ~N of M`, `Out of mana in ~1:20`, `Full again in ~2:10 if you stop`, `Spending`, `Regen`, `Unpriced casts`), one muted line for what `~` means; no "secret", no "anchored"`
- `UI/Dashboard_Rows.lua` row, append: ` **T76 (P32, review U10 -- the mechanism):** generic path: a column's `col.tooltip` shows on its header label (a hit frame per such column, through `MD.Tip:Show`); the TBC rank table's columns have none`
- `Modules/<Name>/` row: in the T16a sentence, `UI/Tooltip.lua, UI/ReplayWindow.lua` becomes `UI/ReplayWindow.lua` and append ` **T76 (P32):** the Replay module no longer lists `UI/Tooltip.lua`; `MD.Tip` is the main TOC's `UI/Tip.lua``
- The `UI/MinimapButton.lua` / `UI/Widget.lua` / `Engine/DamageMath.lua` / `UI/SpellTooltip.lua` / `UI/ReplayWindow.lua` comments that still say `UI/Tooltip.lua` are the next owner's to fix (no code reads the name).

**`docs/TOOLS.md`** section 1:
- `tipcheck.lua` row, append: ` Since **T76** (45): `MD.Tip` on the main TOC without the TBC builders; the line model with token names, a spacer, wrap and a bare string; `Tip:Show` into GameTooltip in the kit skin and out of it on hide, the old shape kept; `Tip:Place` beside / beside the pointer / flipped, and beside the pointer in the tooltip's units when the owner is scaled (80 % against 1); a disabled kit button's tooltip (motion while disabled, the latest anchor, a muted line); `SpellTip:Render` on the shared shape`
- `clockcheck.lua` row, append: ` Since **T76** (29): the hover as pairs -- `Out of mana in` equal to the clock's own time, `Full again in ... if you stop`, `Spending`, `Mana`; out of combat no fight lines; skinned while shown; no "secret", no "anchored"`
- `reviewforever.lua` row, append: ` Since **T76** (22): under `S.Geometry` and a pointer the suite sets, a row's tooltip opens beside the pointer, top-aligned, and flips at the screen's right edge`
- `dashui.lua` row, append: ` Since **T76** (67): a generic table's header label shows `col.tooltip` (a column without one none; the rank table's columns none); a TBC kit button is never set to take the pointer while disabled`
- `spelltip.lua` row, append: ` Since **T76** (49): on TBC `MD.Tip:Show` is GameTooltip, unskinned, the kit tooltip untouched, the builders `UI/Tip_TBC.lua`'s`
- The suites that load `UI/Tooltip.lua` by hand now load `UI/Tip.lua` and `UI/Tip_TBC.lua` (import, ttocheck, reviewui, practiceui, replayui, themecheck, dashui, spelltip); no row text needed.

**`docs/TESTING.md`** section 44, a check for the author (Forever unless said):

> **One tooltip (P32).** These need a build newer than the 0.16.4 install. `/st`: hover a Settings
> checkbox, a Review row, a replay icon, the clock and a rank row in Spells -- every tooltip has the
> same flat dark fill and one crisp black edge (no Blizzard border); the rank row still shows the
> game's own spell text with the SpellTuner block under it (report if the block is missing or shows
> twice, and whether holding Shift keeps the flat look). Hover a Review row near its left end, then
> near its right end: the tooltip opens beside the pointer, level with the row, and near the screen's
> right edge it opens to the pointer's left. Do the same with Settings -> General -> window scale at
> 80 % and at 120 %: the tooltip still opens just beside the pointer (not far right of it, not over
> it). Select a fight that does not replay and hover the greyed
> Coach button: it says why. Hover the clock in a fight: `Out of mana in ~1:20`, `Full again in ~2:10
> if you stop`, no word about secrets. Hover any other addon's tooltip (a bag item, a unit frame)
> straight after: it has its normal Blizzard border. **TBC:** `/md` -- every tooltip looks exactly as
> before.

**`docs/DECISIONS.md`**: none. TBC shows and records nothing different; the Forever changes are the
approved mockups' (M1's kit tooltip, M2's row hover, M6's clock words) and P32's text.

## Deviations

1. **`MD.Tip:Show` renders into GameTooltip on Forever too, in the kit skin, not into the kit
   frame.** The plan says "`MD.Tip:Show` renders into the kit tooltip" and names the fallback "the
   rank row keeps `GameTooltip`, restyled while a SpellTuner frame owns it". The rank row has to keep
   GameTooltip (whether the Spell post-call fires for `SetSpellByID` on another tooltip is unverified,
   and the stub's `SetSpellByID` exists on GameTooltip only), and so do the hovers four suites not
   owned in this wave read back from `GameTooltip.lines` (`replayforever`, `spellsui`, and the
   reviewforever / clockcheck checks that predate T76). So U2's "one skin" is reached the other way
   round: every GameTooltip SpellTuner shows on Forever wears the kit skin (`Tip:Skin`), and the kit
   tooltip wears the same skin. Moving `Show` onto `UI.tooltip` later is one line in `UI/Tip.lua`
   plus those suites' reads.
2. **Eight suites' hand-written load lists changed** (`"UI/Tooltip.lua"` -> `"UI/Tip.lua",
   "UI/Tip_TBC.lua"`): `dashui` and `spelltip` (owned) and, outside the wave table, `tools/import.lua`,
   `ttocheck`, `reviewui`, `practiceui`, `replayui`, `themecheck` -- one line each, forced by the
   file split the table itself names. Wave 15 has one task, so no collision; their counts and outputs
   are unchanged (the T68 precedent, its deviation 2).
3. **`tools/replayforever.lua`'s T43 assertion rewritten** (outside the table): it called
   `MD.Tip:Row` on Forever, which A21 / P32 move to the TBC TOC. It now reads the same colour from the
   `tipGold` token (what `Row` painted) and asserts `MD.Tip.Row` is absent on Forever; same label,
   count unchanged (28).
4. **The TOC lines were not applied in the worktree** (above): the suites ran in a scratch copy.
5. **`SpellTip:Lines` keeps its positional arrays** and adds the named fields beside them, rather than
   switching shape: `tools/bookcheck.lua` and `tools/spellsui.lua` (not owned) read the positional
   fields. P34 (which owns `SpellTip_Forever.lua`, `tipcheck` and `spellsui` in wave 17) can drop them.
6. **The `tip` fill is TBC's literal (0.1, 0.9) on both lines for now.** The mockup's `.gt` is
   `#0C0C0C` at 0.94; the theme file is not owned here. One line for P34 in `UI/Theme_Forever.lua`:
   `P.tip = Grey(0x0C, 0.94)`.
7. **`UI.SetTooltips` is sugar over `MD.Tip:Kit` under the theme only**; TBC keeps its old body, byte
   for byte (its first line in the client's default colour, later lines forced white, the first
   call's anchor), as "TBC's disabled buttons stay silent, as today" and the TBC suites require.
8. **The old `Show` shape's `ANCHOR_RIGHT` / `ANCHOR_CURSOR` mean "cursor" placement under the
   theme** -- the way Review's rows (`ANCHOR_CURSOR`) and the replay's icons and bars (`ANCHOR_RIGHT`)
   get "beside, flipped at the edge" without touching `UI/Dashboard_Review.lua` or
   `UI/ReplayWindow.lua` (not owned). A narrow owner (an icon) is placed beside itself, a wide one (a
   row) beside the pointer.
9. **`Clock:HoverLines(now)`** is published (the hover's lines); P36's `SummaryLines` can share it.
10. **A header column tooltip anchors `ANCHOR_TOPLEFT`** (the kit buttons' anchor), the label as its
    title; the placement of the words is P34's to change.

## In-game check needed

The plan's: whether the Spell post-call fires for `SetSpellByID` on the kit tooltip -- moot here,
since the rank row keeps GameTooltip (Deviation 1). What to watch instead: that the skin shows on
the rank-row tooltip (the NineSlice faded, our fill visible) and survives Shift's refresh
(`RefreshData` clears the tooltip; the skin stays only while the same row owns it), and that other
addons' and Blizzard's tooltips never keep it (TESTING item above).
