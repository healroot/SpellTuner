# T121 -- One UI, W5: one tooltip block on both lines

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave C, beside T120.** Starts on the integrated wave B (T117,
T118, T119): the block reads T118's TBC book.

## The task (docs/SPEC-one-ui.md 3.4, 6, 10 W5; mockup M5, all four panels and its caption)

> **W5, one tooltip block.** On TBC, deleting `Tip:Spell` / `Tip:Damage`.

TBC's spell tooltip is `UI/SpellTooltip.lua` hooking `OnTooltipSetSpell` and appending
`MD.Tip:Spell` (druid heals, "HPM / HPS" words, Shift for the derivation) or `MD.Tip:Damage`
(the druid's damage spells, VERIFY lines). Forever's is `UI/SpellTip.lua` (T117's name for
`UI/SpellTip_Forever.lua`): `SpellTip:Lines` over `MD.Book`, any class, a detail key. After this
task both lines draw **Forever's block** from their own book, with TBC's derivation behind the
detail key (now offered on TBC too, Shift by default), and the two TBC builders are gone.

Owned files (the only files edited, apart from this one):

- `UI/SpellTip.lua`
- `UI/SpellTooltip.lua`
- `UI/Tip_TBC.lua` (delete `Tip:Spell`, `Tip:Damage`, `Tip:Columns` and what only they use)
- `SpellTuner_TBC.toc`: **one line**, `UI\SpellTip.lua` inserted right before
  `UI\SpellTooltip.lua`
- `tools/spelltip.lua` (tbc), `tools/tipcheck.lua` (forever), `tools/tbcclasscheck.lua`,
  `tools/bookshapecheck.lua` (checks 19-20 only)

T120 (the same wave) calls `MD.SpellTip:Lines(id, detail, source)`, `Render(tt, lines)`,
`DetailShown()` and reads `tt._spellTipId`. **Keep all four as they are.** This task edits no
`Spells/Words.lua` line (T120 owns that file this wave): a word the block needs that Words lacks is
a local function in `UI/SpellTip.lua`, named so the integrator can fold it into Words later.

## What to build

### `UI/SpellTip.lua` on both lines

- **The book, not the client.** `book.families[e.family]` (not `e.name`); the pool is
  `MD.Book:Pool()` (`PoolBelowMax` goes; `~N now` only when `pool.modelled`, plain `N now` on
  TBC); every read through `MD.Book`, `MD.Words`, `MD.Tip`. No `MD.Clock`, no `MD.API` read but
  the key reads (`IsShiftKeyDown` / `IsAltKeyDown` / `IsControlKeyDown`, shared bindings,
  `Client/API.lua:427`) and the Forever hooks below.
- **Defaults** registered here with `MD:RegisterDefaults`: `spellTooltip = true`,
  `spellTooltipDamage = true`, `spellTooltipDetail = "SHIFT"` (the same values both cores carry:
  `RegisterDefaults` refuses only a different second default). Forever's `Core_Forever.lua` keeps
  its two keys; TBC's `Core_TBC.lua` keeps its two (the duplicates go when each core is next
  touched).
- **`spellTooltipDamage`** gates a damage family's block on both lines (spec 6; Forever read no
  such key before: its default is on, so nothing changes for a Forever player).
- **`MD.ClassProfile:Can("tooltip")`** gates the block on both lines (TBC's rule since T99; on
  Forever every class's profile grants it through `LineCaps`).

**The plain block** (both lines, Forever's, M5 "TBC after, plain"):

```
SpellTuner  Rank 12 of 12                                  Shift: detail
Suggested   this rank
Per mana    6.09
Per sec     1383
Casts to OOM  11 from full
```

TBC loses `HPM / HPS`, `Heal` / `Average`, `Downranked` and `After your overheal` from the plain
block (After overheal moves behind the key) and gains Rank N of M, Suggested and Casts to OOM.

**Behind the detail key** (M5 "TBC after, Shift held", "Forever after, Shift held"), in this
order, each only when the entry has it:

1. `Heals` / `Hits` `min - max` (`e.min`, `e.max`; Forever's `ValueLines` as today).
2. `Crit` `min x 1.5 - max x 1.5`, then `e.crit`'s percentage (`15%`) when set, else `x1.5
   assumed` (Forever's words).
3. `After overheal` `3035  25% measured` (`e.afterOverheal`; `family average` for that scope).
4. `vs Rank N` (Forever's comparison line, unchanged).
5. `Reaches` / `Cooldown` / `Lockout` / `Only` (Forever's T95 lines, unchanged).
6. **`How`**: `e.calc[1]` on the `How` line, `e.calc[2..]` under it indented as they are; then
   `Words.Bonus(e, "how")` when the bonus is `measured` or `estimated` (`  +Healing counts 31%,
   measured 2 Oct`). A `model` bonus adds no line (its factors are in `calc`, M5's TBC panel).
   Forever's `calc` is `{ "read from the spell's text" }` (T117), so Forever gains the How lines.
7. The stale line last (Forever's, unchanged).

**Swiftmend and other valueless heals.** An entry with a `kind`, no `value` and a `calc` (T118's
Swiftmend: the two `Eats` lines) draws the header and its `calc` lines in the plain block, as
`Tip:Spell` did. One with neither stays `no value` (Tranquility, as today on TBC).

**Damage on TBC** (the druid's, T118): the same block with damage words (Forever's `kind ==
"damage"` path); `Tip:Damage`'s VERIFY notes are the entry's `calc` (T118), so they become its How
lines.

- **`SpellTip.OnSpell(tt, id, source)`** is exported (today a local): the once-per-showing guard
  (`_spellTipId`, `_spellTipEnd`), the `pcall`, `Render`, `tt:Show()`. Both lines' hooks call it.
- **Forever's hooks** (`MD.API.OnSpellTooltip`, `OnMacroTooltip`, `OnActionTooltip`,
  `RefreshTooltip` on `MODIFIER_STATE_CHANGED`) are registered at `MD_READY` **only where the
  adapter has them** (`if MD.API.OnSpellTooltip then`): the presence of an adapter function, the
  pattern `UI/SpellRail.lua`'s drop uses for `CursorInfo`, never the client's name (apicheck rule
  10). TBC's adapter has none of them, so nothing registers there.

### `UI/SpellTooltip.lua` (TBC's hook, TBC TOC only)

It keeps what is TBC's -- the `OnTooltipSetSpell` / `OnTooltipCleared` hooks on `GameTooltip` and
`ItemRefTooltip`, `SpellIDOf(tt)` -- and hands the id to `MD.SpellTip.OnSpell(tt, id, "spell")`.
`MD:SpellTooltipAppend`, `DamageLines`, `Description` and `mdSpellID` go (the guard is the
block's). The modifier watcher re-runs the owner's `OnEnter` when **the detail mode's key**
changes (`SpellTip:DetailMode()`: `LSHIFT` / `RSHIFT` for SHIFT, `LALT` / `RALT`, `LCTRL` /
`RCTRL`; nothing for ALWAYS / NEVER) and the tooltip shows a block (`tt._spellTipId`). (Moving this
hook into `Client/API_TBC.lua` as `MD.API.OnSpellTooltip` is a follow-up: that file is T120's this
wave.)

### `UI/Tip_TBC.lua`

Delete `Tip:Spell`, `Tip:Damage`, `Tip:Columns` (no caller since T83) and the locals only they
use (`R`, `Range`, `Pct`, `SHORT` if T118 moved it). `Tip:Row` stays (its last game caller,
`UI/SpellsView_TBC.lua`, goes with T120; `tools/tbcclasscheck.lua` still calls it -- T123 deletes
it). `Tip:Mana`, `Tip:Fights`, `Tip:Clock*` untouched.

## The checks (fail first on the parent, then green)

**`tools/spelltip.lua`, tbc** (49 today). Its plumbing checks stay and now drive the block:
druid with the tooltip cap, once per showing (OnTooltipSetSpell fired twice), off means off,
`spellTooltipDamage = false` drops the damage block only, never a bare pipe, a raising builder
never breaks the game's tooltip. Its arithmetic checks are re-based on the block's lines:

1. Healing Touch R12: `Per mana` / `Per sec` equal the book's entry (T118 holds those equal to
   RankMath's row and to the SpellKit value the simulator heals with -- the suite's old chain).
2. `Casts to OOM N from full` equals `RankMath:CastsToOOM` for the entry.
3. The plain block has no `HPM` and no `Average`; the detail block has `Heals`, `Crit ... 15%`,
   `After overheal` (seeded), `vs Rank 11`, and the How lines equal to the parent's `Tip:Spell`
   Shift derivation (a golden captured on the parent with `--golden` before the deletion).
4. Swiftmend: the two `Eats` lines, equal to the parent's `Tip:Spell` golden.
5. Wrath: the block's numbers equal `DM.Compute`'s; its How lines equal the parent's `Tip:Damage`
   VERIFY lines (golden).
6. Every detail mode: ALT shows the detail only with Alt; ALWAYS always; NEVER never; the
   watcher re-runs `OnEnter` for the mode's key only.
7. A priest with the cap granted in the suite (T111's fixture): the block draws from the class
   book.

**`tools/tipcheck.lua`, forever** (52): unchanged but for the How lines (`read from the spell's
text`, then `+Healing counts ~N%, estimated` from T117's bonus) behind the key, and the pool from
`Book:Pool()` -- each re-based line listed in the suite's comment. Plus one check:
`spellTooltipDamage = false` drops a damage spell's block on Forever.

**`tools/tbcclasscheck.lua`** (52): the `Tip:Spell` half of check 506 reads `SpellTip:Lines`
instead (the `Tip:Row` half stays until T123).

**`tools/bookshapecheck.lua`**, checks 19-20: compare `calc` with the goldens of `Tip:Spell`'s
lines captured before the deletion (the comparison was live while `Tip:Spell` existed).

**Unchanged**: `spellsui` (T120's), `dashui`, `capscheck`, `profilecheck`, `apicheck` 0 (the
hook guard reads an adapter function's presence, not `MD.API.client`), `textcheck` 0. `make check`
green.

### Counts

| Suite | Before | After |
|---|---|---|
| `spelltip/tbc` | 49 | measured (the arithmetic checks re-based, 6 and 7 new) |
| `tipcheck/forever` | 52 | **53** |
| `tbcclasscheck/tbc` | 52 | 52 |

## Integrator lines

- **TOC:** the task's line (`UI\SpellTip.lua` before `UI\SpellTooltip.lua` on TBC); the Forever
  TOCs list it already. `releasecheck`.
- **`tools/data/expected-counts.json`:** `spelltip/tbc`, `tipcheck/forever`.
- **`CLAUDE.md`:** the `UI/SpellTip.lua` row (T117's name) gets `**T121:**` (both main TOCs; the
  book's family, pool and bonus; defaults registered here; the damage half and the tooltip cap on
  both lines; How from `entry.calc`; `SpellTip.OnSpell` exported; Forever's hooks where the adapter
  has them). `UI/SpellTooltip.lua`: `**T121:**` (the TBC hook only, into `SpellTip.OnSpell`; the
  detail mode's key re-runs `OnEnter`). `UI/Tip_TBC.lua`: `Spell`, `Damage`, `Columns` deleted.
- **`docs/TOOLS.md`**: `spelltip` / `tipcheck` rows: one block.
- **`docs/TESTING.md`** section 49: hover a heal, a damage spell and Swiftmend on TBC, with and
  without Shift; set Detail lines to Alt.
- **`docs/DECISIONS.md`**: nothing new (spec 6 is the record).

## Deviations allowed

- The How lines' indentation may follow what `MD.Tip:Render` draws best in a GameTooltip, as long
  as each `calc` string is one line in order.
- If `Engine/DamageMath.lua`'s VERIFY lines need a field T118's `calc` did not copy, take it from
  T118's damage entry rather than calling `DM.Compute` from the block.

## Out of scope

- Moving the TBC hook into `Client/API_TBC.lua` (a follow-up); `Tip:Row` (T123); the What if
  (the block keeps the live numbers, spec 4.1).
