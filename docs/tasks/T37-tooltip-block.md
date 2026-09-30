# T37 -- the tooltip block redesign

Status: **built** 2026-09-30 on branch `ui/T37` (base 9c2a26e), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T37** | **Tooltip block redesign** (5.1-5.4b, 5.6): `SpellTip:Lines(id, detail, source)` returns `{l, r, lr,lg,lb, rr,rg,rb}`; the spacer, colours as arguments, the plain/detail split (the stale line last in the plain block, the gap line in the detail), `Suggested` first, `~N now` only below max, the Other-kind block and no block for a free one, `- macro` from `source`; `db.spellTooltipDetail`; `MD.API.RefreshTooltip` on `MODIFIER_STATE_CHANGED`; the guard keyed `(id, detail)`; its dropdown in Settings -> General. | `UI/SpellTip_Forever.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `UI/Dashboard_Forever.lua` (the dropdown) | `tools/tipcheck.lua` (existing line assertions rewritten to the new shapes; + ASCII, no bare pipe, at most 5 plain lines when fresh and 6 when stale, the stale line last, the gap line only with the key, no range on the plain block, detail lines only with the key, an Other spell's two lines and no hint, no block for a free Other spell, the macro marker) | T28, T29 |

Spec sections it cites: 5.1 (rules), 5.2 (direct heal), 5.3 (HoT), 5.4 (hybrid damage, a spell
outside the book), 5.4b (Other), 5.6 (the detail key), and through them 4.1 (the `UI.TEXT` tokens,
no Blizzard gold on the block), 5.5 (the `- macro` marker) and decisions 5 and 12 (8.1: Shift; the
marker makes a wrong-rank macro visible).

## What was built

### `UI/SpellTip_Forever.lua`

**`SpellTip:Lines(id, detail, source)`** answers a list of `{l, r, lr,lg,lb, rr,rg,rb}` (`r` nil for
a single line, whose colour is `[3..5]`), or nil for no block. The plain block always; the detail
lines after it when `detail` is true; `source == "macro"` marks the header. Colours are the theme's
`UI.TEXT` tokens (T29), with the spec's own values as a fallback table, so the block never falls
back to the tooltip's gold.

The plain block (at most 5 lines, 6 with the warning):

| Line | Left / right | Colours |
|---|---|---|
| header | `SpellTuner` / `Rank 2 of 2` (`Rank N` outside a family), `- macro` from a macro, then `\|cff4d4d4dShift\|r` when there are detail lines and the mode is a key | accent / text |
| 1 (family only) | `Suggested` / `Rank 1 (1.90 per mana)`; `this rank` on the suggested rank; `Dominated by` / `Rank 2` on a dominated one | label / accent |
| 2 | `Per mana` / `1.86` (`no mana (10 Rage)`, `free`, `N% of base mana`, `cost unknown` as before) | label / text |
| 3 | `Per second` / `51.2`, or `4.0 over 12 s` for a HoT or a channel | label / text |
| 4 (family, mana cost) | `Casts to OOM` / `6 full`, plus `, \|cff4d99ff~5 now\|r` while the clock's modelled pool is below its max | label / text + mana |
| warning | `Text read before combat` (a stale entry), last | bad |

The detail lines: the value by shape -- `Average` / `103 (90 - 115)` and `Crit` / `135 - 173` for a
direct part; `Hit` / `avg 13, crit 17 - 23`, `Over time` / `24 over 12 s`, `Total` / `37` for a
hybrid; `Ticks` for a tick shape the text states; `Absorbs` for an absorb; nothing for a HoT with no
stated tick -- then `Crit multiplier` / `x1.5, not measured` (muted, once, only with a crit range),
the rank rows when two or more known ranks have a value (`Rank 1` / `48   1.90 per mana   14` in
text2, `Rank 2 (this)` in white), and `Not in your book` / `Rank 3` (muted) for a gap.

- **Nothing the game already printed**: no description range and no cast line on the plain block
  (`(1.5 sec cast)`, `sec GCD`, `sec channel` are gone from per second).
- **A spell outside the book** (`Book:ReadSpell`): the header, per mana and per second; its value
  behind the key; no suggestion, no casts, no rank rows.
- **An Other spell** (a book family with no kind, 5.4b): the header (no hint) and `Casts to OOM`,
  counted against the full pool and the modelled one with the interval `max(cast, GCD)`, since
  `Book:Rows` never fills one for a kindless family. **A free one** -- or one whose cost is not mana
  -- gets no block, outcome `no value` for `/st tooltip why`.
- **`SpellTip:Render(tt, lines)`** writes a result into a tooltip with `AddDoubleLine(l, r, lr, lg,
  lb, rr, rg, rb)` / `AddLine(l, r, g, b)`.
- **`SpellTip:DetailMode()`** (`SHIFT` for anything the setting does not name), **`DetailShown()`**
  (`ALWAYS`, `NEVER`, or the key read through `MD.API.IsShiftKeyDown` / `IsAltKeyDown` /
  `IsControlKeyDown`, a plain `true` only) and **`SpellTip.DETAIL_MODES`** (the dropdown's items).

**The hook** (`OnSpell(tt, id, source)`): the spacer `tt:AddLine(" ")` first, then the block. The
once-per-showing guard is keyed by `(id, detail)` and holds while the block is still on the tooltip:
the same showing rebuilds only when its lines were cleared under it (fewer lines than the block
ended at), so a post-call run again without a clear never adds a second block whatever the detail,
and the detail key's refresh rebuilds it once. Without a line count, the key decides (a changed
detail rebuilds). Each tooltip given a block is kept in a weak set.

**The refresh** (5.6): on `MODIFIER_STATE_CHANGED` (registered at `MD_READY` beside the three
tooltip hooks), when the mode is a key and the event's key names it (`LSHIFT` / `RSHIFT` for
`SHIFT`, ...), every tooltip in the set that is shown and still holds `_spellTipId` goes through
`MD.API.RefreshTooltip`. Another key, or `ALWAYS` / `NEVER`, refreshes nothing.

### `Client/API_Forever.lua`

- **`MD.API.RefreshTooltip(tt)`**: `tt:RefreshData()` under `pcall`; a tooltip without the method
  answers `nil, "absent"`, a raise `nil, "error"`. Recorded as `RefreshTooltip` ->
  `GameTooltip.RefreshData` in the capability table. **UNVERIFIED on Forever** that `RefreshData`
  re-runs the post-calls; if it does not, the detail lines show on the next hover, as before.
- **The macro source**: T25/T28's `Offer` hands `fn(tooltip, id, source)`; every step of the Macro
  post-call's chain passes `"macro"`, and the SetAction hook passes it only when the slot holds a
  macro (a plain spell button's block carries no marker).

### `Core_Forever.lua`

`DEFAULTS.spellTooltipDetail = "SHIFT"` (decision 5).

### `UI/Dashboard_Forever.lua`

- **Settings -> General**: a `Detail lines` label and a kit dropdown (`UI.CreateDropdown`, 120 wide)
  under the tooltip checkbox -- `With Shift`, `With Alt`, `With Ctrl`, `Always`, `Never` -- writing
  `db.spellTooltipDetail`, set from `SpellTip:DetailMode()` on every showing of the pane. The clock
  checkbox moves under it. T42 moves it into its titled pane.
- **The Spellbook pane's row hover** renders the block through `SpellTip:Render` (colours passed;
  no spacer, the tooltip is SpellTuner's own) with the detail lines when the key is down. T38
  replaces this hover.

### Test support

- `tools/wowstub.lua` (every hunk tagged `-- T37`): `AddLine` / `AddDoubleLine` keep their colour
  arguments beside the text (`color`, `rcolor`); `MODIFIER_STATE_CHANGED` joins the Forever
  profile's events; `S.ShowSpellTooltip` / `S.ShowMacroTooltip` remember the showing; the Forever
  profile's frames get `RefreshData()` -- the lines cleared and the showing's post-calls run again
  **without** `OnTooltipCleared` (the harder case for the guard), counted per tooltip in
  `tt.refreshes`.
- `tools/adaptercheck.lua`: `RefreshTooltip` in `FOREVER_ONLY_NAMES` (tagged).
- `tools/spellsui.lua`: one assertion reads the tooltip's from-full count out of `N full, ~M now`
  (tagged; its intent -- the pane never rewrites the book's count -- unchanged).

## Tests first

`tools/tipcheck.lua` 27 -> **37**. The line assertions rewritten to the new shapes (the numbers,
the rank rows instead of `vs Rank`, `Suggested` first with `this rank` and `Dominated by`, the gap
behind the key, a spell outside the book, per second, the absorb, casts to OOM, the multiplier, the
Rage cost, and the T25/T28 macro comparisons now expecting the spacer and the `- macro` header),
and ten new ones:

- a spacer, then the block with its colours passed and no gold (every colour an argument, none
  `1, 0.82, 0`, no `ffcc00` / `ffd100` in any text)
- the header says `Rank N of M` and the detail key in the disabled colour
- no range and no cast line on the plain block
- detail lines only with the key (Shift up / down, `ALWAYS`, `NEVER`; no hint under `ALWAYS`)
- a hybrid's detail is the hit, the over-time part and the total (Moonfire R2: `avg 13, crit 17 -
  23`, `24 over 12 s`, `37`; Suggested `Rank 1 (0.90 per mana)`, the spec's own numbers)
- an Other spell gets two lines and no hint (Mark of the Wild, the m2 texts)
- a free Other spell gets no block
- the macro marker (`Rank 1 of 2 - macro  Shift` from the source, on a macro's tooltip, never on a
  spell's)
- the detail key refreshes the tooltip through the adapter and the block is rebuilt once (Shift
  down: the detail block, one header; the post-call again without a clear adds nothing; Shift up:
  the plain block; Alt: no refresh)
- the detail key is a Settings -> General dropdown (default `SHIFT`, Alt picked from its list, the
  hint then `Alt`, Alt shows the detail lines)

Plus the at-most-5 / 6 / stale-last and the gap-only-with-the-key assertions among the rewritten.

Against the base implementation (the four shipped files at 9c2a26e, this stub and these tests):
**12 ok, 25 failed**, e.g. `every number in the block is the book's - avg=nil crit=nil
perMana=1.90 perSec=31.7 (1.5 sec cast) casts=nil`, `T37: at most 5 plain lines when fresh, 6 when
stale, the stale line last - fresh=8 stale=9 last=|cff999999Read before combat|r`, `T37: an Other
spell gets two lines and no hint - kind=nil lines=nil`, `T37: the macro marker - head=Rank 1 of 2
known other=nil`, `T37: the detail key refreshes ... - entry=nil n0=8 n1=8`, `T37: the detail key
is a Settings -> General dropdown - dd=false`. `a free Other spell gets no block` passes on the base
too (it gave no block to any kindless spell); the Other-with-a-cost assertion is the one that fails.

After: **37 ok, 0 failed**.

## The full check

- `luac -p` on every changed Lua file: ok.
- The suite loop (`docs/TOOLS.md` section 1, plus `themecheck` and `tabscheck`): every suite green;
  the only count that changed is `tipcheck` 27 -> 37. The TBC suites keep their counts, and their
  whole output is the same as with the base stub apart from what differs between two runs of the
  same code (the frame-sliced search's `[sim] search N evaluations` in `replayui` / `reviewui`, and
  table addresses in `solvercheck`).
- `python3 tools/apicheck.py`: 0 findings; `--selftest`: 10 of 10; `python3 tools/refcheck.py
  --selftest`: ok.

## Deviations

1. **The guard.** Keyed by `(id, detail)` as the row says, but what lets a showing rebuild is the
   block no longer being on the tooltip (a line count below where the block ended), not the detail
   alone: a post-call that runs again without a clear while the key changed would otherwise add a
   second block under the first. The key alone decides only when the tooltip has no line count.
2. **The handler's home.** The spec says "the adapter calls `tt:RefreshData()`". The adapter gives
   `MD.API.RefreshTooltip`; the `MODIFIER_STATE_CHANGED` handler lives in `UI/SpellTip_Forever.lua`,
   which knows which tooltips carry a block and which key is set. It refreshes only for the key the
   setting names.
3. **No casts line for a non-mana cost.** A Rage / Energy / Focus spell's block drops `Casts to OOM`
   (it read `-`); a kindless spell with such a cost gets no block, like a free one.
4. **Shapes the spec does not show**: a channel's per second reads `over N s` like a HoT's (its
   interval is its duration); an absorb's detail is `Absorbs N`; the rank rows appear only when two
   or more known ranks have a value; `Dominated by` names the suggested rank when it dominates, else
   the dominating rank with the best per mana.
5. **Dropdown wording and place.** `Detail lines` with `With Shift` / `With Alt` / `With Ctrl` /
   `Always` / `Never`, under the tooltip checkbox; T42 moves it into its pane.
6. **`tools/spellsui.lua`** is not in the row's files; one of its assertions read the tooltip's
   casts value whole, so it now reads the from-full count out of the new shape (tagged `-- T37`).
   T36 rewrites that file; the integrator keeps the tag's intent.
