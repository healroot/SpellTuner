# T120 -- One UI, W3: one Spells pane on both lines

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave C, beside T121.** Starts on the integrated wave B (T117,
T118, T119). T122 (What if) and T123 (classes) build on it.

## The task (docs/SPEC-one-ui.md 2's rows Rail / Picker / Drag / Overview / Family view / card, 3.3, 10 W3; mockup M1, M3, M4)

> **W3, one pane.** `UI/SpellsPane.lua` on both lines, with `MD.SpellsLine`; the TBC rail, picker,
> drop (`CursorInfo`), Overview with Whole book and Export; delete `UI/SpellsView_TBC.lua`'s view
> and overview.

T117 renamed Forever's pane to `UI/SpellsPane.lua` and T118 gave TBC an `MD.Book` in the same
contract. This task puts the pane on the TBC TOC, teaches it the few things TBC's book sends that
Forever's does not (the model's crit, the cast note, After overheal, Lifebloom's rolled rows, the
`+Healing` pair from the model), takes everything else from the book's fields rather than from the
client, and deletes TBC's own view.

Owned files (the only files edited, apart from this one):

- `UI/SpellsPane.lua`
- `UI/SpellsView_TBC.lua` (deleted)
- `UI/SpellRail.lua`
- `UI/Dashboard.lua` (the Spells group, its size, the line's `MD.SpellsLine`)
- `UI/Dashboard_Forever.lua` (Forever's `MD.SpellsLine`; nothing in Settings)
- `Client/API_TBC.lua` (two bindings)
- `Spells/Words.lua` (the words below)
- `SpellTuner_TBC.toc`: **one line**, `UI\SpellsView_TBC.lua` -> `UI\SpellsPane.lua` in place
- `tools/spellsui.lua` (both flavours), `tools/dashui.lua`, `tools/navui.lua`,
  `tools/adaptercheck.lua`, `tools/restylecheck.lua`, `tools/wowstub.lua`

T121 (the same wave) owns `UI/SpellTip.lua`, `UI/SpellTooltip.lua`, `UI/Tip_TBC.lua` and their
suites. The pane calls `MD.SpellTip:Lines` / `Render` / `DetailShown` with today's signatures and
reads the guard field `tt._spellTipId`; T121 keeps both, so neither task waits on the other. Its
TOC line (`UI\SpellTip.lua` before `UI\SpellTooltip.lua`) is twelve lines above this task's.

## What to build

### `MD.SpellsLine` (installed by each dashboard before the pane is built)

What differs by line, as values (apicheck rule 10; spec 3.3 with Lead's correction 6):

```lua
MD.SpellsLine = {
  footer        = "Values come from the spell's own text. ~ = modelled.",
                  -- TBC: "Values from the model: your gear, talents and the downrank rules."
  ranksNote     = function(fam) end,     -- RANKS' title-row note; TBC: "live: gear, talents,
                                         -- downrank rules" (heal) / "live: gear, talents" (damage);
                                         -- Forever: nil (the footer says it)
  critNote      = "x1.5, unverified",    -- the card's Crit pair suffix; TBC: nil (its crit is the model's)
  afterOverheal = nil,                   -- TBC: { get, set, word(fam) }  (below); Forever: nil (D2)
  overviewNote  = function() end,        -- a muted line on Overview, or nil; TBC: the rankTable
                                         -- refusal for a class without it
  whatIf        = nil,                   -- T122
}
```

The spec's `poolWord` (the `~` follows `Book:Pool().modelled`, T117), `gaps` (a book that has no
gap rows sends no `family.gaps`) and `export` (one function, the pane's) are dropped (Lead's
correction 6).

### `UI/SpellsPane.lua`: what moves from the client to the book

| Today (Forever only) | After (both lines) |
|---|---|
| local `Pool()` (`MD.Clock:Pool()`, else `DefaultPool`) | `MD.Book:Pool()` |
| the `~` on the header's pool and on `Now` | only when `pool.modelled` |
| `SpellsPane:` header's bonus read (`MD.API.SpellBonusHealing`, `self.lastBonus`) | `MD.Book:Bonus(fam.kind, fam.school)`; a stale answer is drawn in `muted` with the hover `read before combat` |
| `book.families[e.name]` (row hover, `RailTip`, `Find`) | `book.families[e.family]` |
| `FOOTER_TEXT` | `MD.SpellsLine.footer` |

The header's right side is two lines on both clients (spec 3.3): the pool (`6500 / 6500 mana`,
`~364 / 364 mana`), then the bonus (`+700 healing`, `+300 Nature damage`; nothing on an Other
family or when `Bonus` answers nil).

### What the pane draws from TBC's fields (and any line that sends them)

- **The header's cast part**: `2.9 s cast with Nature's Grace averaged` when the representative
  entry has `castNote` (`Words.Cast(e, "header")`).
- **The `Heals` / `Hits` pair**: `min - max`, then `Words.ValueSource(e)`: `(4046 with 15% crit)`
  when `e.crit` is set (the value is crit-averaged, D1), `from the text` when it is not. A damage
  family says `Hits`. A `bonus` with `amount` and `of` adds `(+171 of your 300)` on damage (M4).
- **The `Crit` pair**: `min x 1.5 - max x 1.5`, then `MD.SpellsLine.critNote` (Forever's `x1.5,
  unverified` stays Forever's words) or `e.crit`'s percentage.
- **The `Cast` pair**: `Words.Cast(e, "card")` plus the `castNote`.
- **`+Healing` / `+Damage`** (`Words.BonusLabel(kind)`): `Words.Bonus(e, "card")` when
  `e.bonus`; it replaces TBC's old `Downrank 70%` (M1). Placed after `Per sec`, before `Reach`.
- **`After oh.`** (the card's short label, 70 px): `3035  25% overheal, measured` when
  `e.afterOverheal` (`scope` `family` reads `family average`), after `+Healing`.
- **The strip's After overheal check** when `MD.SpellsLine.afterOverheal` is set: TBC's provider
  is `{ get = db.effectiveMode, set = function(on) db.effectiveMode = on end, word = the family's
  measured share ("25% measured") }`, the same setting C3's view used. While it is on, RANKS'
  value / per mana / per sec cells and the card's pairs read `e.afterOverheal`'s numbers where an
  entry has them (the Pareto marks and the suggestion stay the raw ones: RankMath's rule, unchanged).
- **Lifebloom's rolled rows**: under the rank they belong to, one row per `e.variants` item, the
  rank cell `x2` / `x3` in `muted`, Value / Per mana / Per sec / Cast / Casts from the item, no tag,
  not selectable; the hover `Rolled at 2 stacks: refreshed every 6 s, 6 ticks a cast, no bloom`.
- **Unlearned ranks** (`known = false`) as Forever draws them: `learn at N` in the tag, the numbers
  in `disabled`.
- **RANKS' note**: `MD.SpellsLine.ranksNote(fam)` on the title row (M1 `live: gear, talents,
  downrank rules`).
- **The column header** `Heal` / `Dmg` / `Value` by `fam.kind` (Forever's rule, unchanged).

`Words.lua` gains `W.Cast(e, "header")`, `W.ValueSource(e)`, `W.CastNote(e)` (pure; ASCII).

### The TBC side

- **TOC:** `UI\SpellsView_TBC.lua` -> `UI\SpellsPane.lua` (after `UI\SpellRail.lua` and the
  `UI\Dashboard_*` parts, before `UI\Dashboard.lua`, which builds it).
- **`UI/Dashboard.lua`'s Spells group**: `MD.SpellsTBC`, `SuggestedRows`, `RailRow`,
  `SpellsGroup`, `RefreshSpellRail`'s body, the `spellsView` / `spellsOverview` / `spellsHost`
  code and the `spells` branch of `Refresh` are deleted. The group is `MD.SpellsPane:Group()`,
  `onCreate` -> `MD.SpellsPane:Create(content)`, `onShow` -> `MD.SpellsPane:Show(view)`,
  `MD.SpellsPane:Attach(nav)` after the frame -- Forever's wiring, line for line. `OpenMainWindow`
  keeps the bare-key compatibility (`SpellsViewId`: `"Regrowth"` -> `"fam:Regrowth"`, now through
  `MD.Book:Get().families`).
- **Size**: `SIZES.spells = { w = 860, h = 560, minW = 860, minH = 560 }` (D4; moved from T119,
  Lead's correction).
- **`MD.SpellsLine`** (TBC): the footer, `ranksNote`, `critNote = nil`, `afterOverheal` above,
  `overviewNote` = `MD.Profiles.Refusal("rankTable", why, "Rank analysis") .. " - the OOM widget,
  datatext and advisor still work for your class."` when `Can("rankTable")` is false (today's
  message, now on Overview; Overview still lists Other).
- **Refresh**: the pane's own 2-s tick and `BOOK_CHANGED` (T118 fires it on TBC). The
  `SPELLS_REBUILT` / `TALENTS_CHANGED` / `FORM_CHANGED` / `PLAYER_EQUIPMENT_CHANGED` rail
  refreshes become `MD.SpellsPane:RefreshRail()`.
- **`Client/API_TBC.lua`**: `CursorInfo` (`GetCursorInfo`; the TBC client's shape for a spell is
  `("spell", slot, "spell", id)` as on classic -- the binding reads the id from the fourth return
  and, when absent, the slot through `GetSpellBookItemInfo`; UNVERIFIED until the author drags one,
  `docs/TESTING.md` 49 asks) and `SetTooltipSpell` (`GameTooltip:SetSpellByID`, the 2.5.x client
  has it). Each name joins `tools/adaptercheck.lua`'s TBC list. With them the drop works on TBC
  (`UI/SpellRail.lua`'s `CanDrop` asks `MD.API.CursorInfo`).
- **The rank row's hover** on TBC: the game's tooltip through `SetTooltipSpell`, which fires the
  TBC `OnTooltipSetSpell` hook; until T121 that hook appends the old `Tip:Spell` lines, after T121
  the shared block (and its `_spellTipId` guard keeps the pane from adding a second).

### `UI/SpellRail.lua`

- `FamilyOfSpell` reads `e.family or e.name` (line 237).
- The picker lists a `noSeed` family (Tranquility, Swiftmend) under its kind, as M3 draws it.
- Nothing else: the rail is already shared.

### `UI/Dashboard_Forever.lua`

Installs Forever's `MD.SpellsLine` (`footer` today's text, `critNote = "x1.5, unverified"`, the
rest nil) before `MD.SpellsPane:Create`. Nothing else changes.

### Deleted

`UI/SpellsView_TBC.lua` (`CreateSpellsView`, `CreateSpellsOverview`, `CreateRankTable` -- the
pane's table already takes C2's options). `UI/Dashboard_Simulate.lua` stays on the TOC, unplaced
(nothing opens it), until T122 deletes it: **between this task and T122 TBC has no What if**, and
`MD.sim` stays empty because nothing writes it (Lead's correction: the interim is one wave).

## The checks (fail first on the parent, then green)

**`tools/spellsui.lua`** runs under **both** flavours (`HARNESS_FLAVOUR = { "forever", "tbc" }`).

Forever: today's 53 checks. Re-based, and listed in the suite's comment, only:
the header's second line (the bonus) on the family view goldens, and the card's `+Healing` pair
(`Words.Bonus(e, "card")`, `estimated`) between Per sec and Reach. Nothing else moves.

TBC (new, the stub druid at level 64, `S.Geometry(true)`):

1. The Spells group is a rail with Overview first and the druid's families as rows; the window is
   860 x 560 with no grip.
2. Healing Touch's view: the header `Direct heal - Rank 12 of 12 known - 2.9 s cast with Nature's
   Grace averaged` (the stub's numbers), the pool without `~`, `+700 healing`.
3. RANKS: one row per rank, Value / Per mana / Per sec / Cast / Casts equal to the book's entries
   (T118 made those RankMath's), the tag `best` / `beaten` / `max` / `learn at N`, the note `live:
   gear, talents, downrank rules`.
4. The card: the quoted text (the stub's scan tooltip), `Heals min - max (V with C% crit)`,
   `Crit` with no `unverified`, `+Healing 840 of your 700 (x1.20 Empowered Touch)`, `After oh.`
   with overheal seeded, `Casts`, `Now` without `~`.
5. After overheal on: the cells read the effective numbers, the suggested row unchanged.
6. Lifebloom: rows `x2` / `x3` under the max rank, not selectable, their hover.
7. Overview -> Whole book lists HEALS (Tranquility and Swiftmend with `+`), DAMAGE (Wrath ...) and
   OTHER (Innervate); Export's block parses with the probe dump's reader (the suite's) and names
   the TBC client.
8. The picker's three sections fill; adding Tranquility puts it on the rail.
9. A drop: `MD.API.CursorInfo` stubbed to a Wrath rank inserts Wrath at the row.
10. A priest without the rank table: Overview shows the refusal line, Whole book lists Other only;
    nothing raises.
11. Font offsets -2..+2 and a style switch re-render without overlap (the Forever checks' twins).

**`tools/dashui.lua`, tbc** (84 today): the C3 / T84 Spells checks (the sections from line 384 to
the end of the T84 block, and the T81 rank-table checks that build `CreateRankTable`) are deleted,
not ported -- `spellsui/tbc` holds the pane; the window and Reports / Simulate / Settings checks
stay. Record the new count.

**`tools/navui.lua`**: only if a check builds `UI/SpellsView_TBC.lua`'s view.
**`tools/adaptercheck.lua`, tbc**: the two bindings (17 -> 19).
**`tools/restylecheck.lua`**: the `OWNED` list loses `UI/SpellsView_TBC.lua`; the TBC Spells
views are the shared pane's.
**`tools/wowstub.lua`**: `GetCursorInfo` on the tbc profile if it is forever-only today;
`GameTooltip:SetSpellByID` on both.

**Unchanged**: `tipcheck/forever`, `spelltip/tbc` (T121's), `tabscheck`, `bookshapecheck`,
`settingscheck`, `wincheck` (T119 moved its Settings size; this task's Spells size is checked in
`spellsui/tbc` 1, and `wincheck/tbc`'s Spells check is re-based here if it holds 1036 x 646),
`apicheck` 0, `textcheck` 0. `make check` green.

### Counts

| Suite | Before | After |
|---|---|---|
| `spellsui/forever` | 53 | 53 (re-based lines listed) |
| `spellsui/tbc` | -- | **11** |
| `dashui/tbc` | 84 | measured |
| `adaptercheck/tbc` | 17 | **19** |

## Integrator lines

- **TOC:** the task's line; `releasecheck`.
- **`tools/data/expected-counts.json`:** `spellsui/tbc`, `dashui/tbc`, `adaptercheck/tbc`, and
  `wincheck/tbc` if re-based.
- **`CLAUDE.md`:** the `UI/SpellsPane.lua` row (renamed by T117) gets `**T120:**` (every main
  TOC; `MD.SpellsLine`; the pool, the bonus and the family through the book; TBC's fields drawn --
  crit, castNote, +Healing, After oh., the rolled rows, the After overheal check). Delete the
  `UI/SpellsView_TBC.lua` row. `UI/Dashboard.lua`: `**T120:**` (the Spells group is the shared
  pane's, 860 x 560; `MD.SpellsTBC` gone). `Client/API_TBC.lua`'s line in the adapter row:
  `CursorInfo`, `SetTooltipSpell`. `Spells/Words.lua`: the three words. `UI/SpellRail.lua`:
  `e.family`, `noSeed` in the picker.
- **`docs/TOOLS.md`**: `spellsui` under both flavours.
- **`docs/TESTING.md`** section 49: the TBC Spells pane (the card on Healing Touch, Lifebloom's
  rolled rows, After overheal, Whole book and Export, the picker's DAMAGE, **drag a spell from the
  spellbook onto the rail** -- the `CursorInfo` shape is unverified on TBC).
- **`docs/DECISIONS.md`**: nothing new (D1, D2, D4, D6 are in the spec's section 9).

## Deviations allowed

- The card's pair order may follow what fits 262 px at offset +2; `+Healing` stays before
  `Reach` and `Casts` / `Now` stay last.
- If the TBC `GetCursorInfo` shape differs in the stub's research, the binding follows the research
  and says so in its comment.

## Out of scope

- The What if pane (T122); the tooltip block (T121); class damage (T123).

## Result (2026-10-03, branch `oneui/T120`)

### Counts measured

| Suite | On the parent (tests first) | After |
|---|---|---|
| `spellsui/forever` | 51 ok / 2 failed (53) | **53** ok |
| `spellsui/tbc` | 0 ok / 11 failed | **11** ok (new) |
| `dashui/tbc` | 61 ok / 6 failed (67; 84 before the C3 / T84 Spells checks were deleted) | **67** ok |
| `adaptercheck/tbc` | 16 ok / 3 failed (19) | **19** ok |
| `adaptercheck/forever` | 26 | 26 |
| `wincheck/tbc` | 3 ok / 1 failed (4) | **4** ok (count unchanged, re-based) |
| `wincheck/forever` | 66 | 66 |
| `restylecheck/tbc` | 49 ok / 1 failed (50) | **50** ok |
| `restylecheck/forever` | 45 | 45 |
| `settingscheck/tbc` | 12 | **12** ok (one check re-based, below) |

`make check`: 99 runs, all passed once `expected-counts.json` carries `spellsui/tbc` 11,
`dashui/tbc` 67 and `adaptercheck/tbc` 19 (checked locally and reverted: the file is the
integrator's). apicheck 0 findings, textcheck 0 findings.

### Deviations

1. **The stub's numbers, not the spec's**: the TBC checks read `+450 healing` and `540 of your 450
   (x1.20 Empowered Touch)` (the stub druid's bonus is 450), not 700 / 840.
2. **`settingscheck/tbc` 11 re-based** (not on the owned list; it asserted T119's "Spells is still
   1036 x 646", which this task's D4 makes false): it now asserts Settings 860 x 560 fixed and
   Reports still 1036 x 646.
3. **`adaptercheck/tbc`'s CursorInfo check** (this task's own failing test) asked
   `MD.API.Has("CursorInfo")`, which walks `_G` for a client name; it now asserts
   `MD.API._bindings.CursorInfo == "GetCursorInfo"`.
4. **`dashui/tbc` 84 -> 67**: the C3 / T84 Spells checks are deleted as the task says, and their
   subjects are now held by `spellsui/tbc`'s 11. The count check flags any lost assertions until
   the integrator records 67.
5. **The TBC Export** names the client on its character line (`character: <name> <realm> DRUID level 64`),
   and a family row's name field is the family's name (`Healing Touch`), not its key.
6. **Forever's parsed card** keeps `(x1.5 assumed)` from `Words.Value`, and the crit note
   (`MD.SpellsLine.critNote`) is read only on the model path (an entry with no parsed text). On
   Forever's card nothing else changed.
7. **A wide card pair takes the whole row**: when a value is wider than its column, e.g. `+Healing`, `After oh.` or
   a cast with its note at a large font offset, it spans both columns. The header's name and sub
   line stop short of the pool / bonus column.
8. **The After overheal check sits in the strip's right column**, inside the strip, so it is
   hidden where the strip is (Lifebloom, whose one rank has no comparison). It shows whenever the
   line installs `afterOverheal` and the family has a kind.
9. **The Forever pool with no clock** shows plain mana with no `~`, because `Book:Pool()` answers
   `modelled = false` there. Before this task it read `mana not modelled yet`.
10. **A mana cost** on the card's Casts / Now pairs is a cost whose `power` is not a word: either
    no power (Forever's book) or TBC's power type `0` (T118's `Cost`). It was "no power" only.
11. **For T118 to look at, not changed here**: `Book:Bonus("damage", school)` on TBC hands
    `GetSpellBonusDamage` a school name, not the client's school number.
12. `UI/Dashboard.lua`'s `messageFS` (only the rankTable refusal used it) is gone: the refusal is
    `MD.SpellsLine.overviewNote`, on Overview.
13. `UI/Dashboard_Simulate.lua` stays on the TOC unplaced, as the task says: between this task and
    T122, TBC has no What if.

