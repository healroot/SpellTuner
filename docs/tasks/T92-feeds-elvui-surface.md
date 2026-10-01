# T92 -- Feeds and the ElvUI surface (S3 step 1)

Status: **built** 2026-10-01 on branch `next/T92` (base `231525d`), wave N2 batch A of
`docs/SPEC-next.md`, beside T93 and T94. It awaits the integrator.

**The branch needs its TOC lines (below).** The TOCs are integrator-owned. Without the lines:

- `SpellTuner_TBC.toc` still names `Integrations\ElvUIDatatext.lua`, which is gone. The TBC
  harness now loads `Integrations/`, so every TBC suite fails to load.
- No TOC lists `UI\Feeds.lua`, so `surfacecheck/forever` 1a fails.

The lines (and `stub_hosts` in `tools/check.sh`'s `NOT_SUITES`) were applied in the working tree to
run every check, then reverted before the commit.

## The task (docs/SPEC-next.md section 11, row T92; 2.3; 6.2; R-arch.md 5)

> **Feeds + ElvUI surface (S3 step 1).** `MD.Feeds` (`clock`, `regen` from the face);
> `Integrations/ElvUIDatatext.lua` moved to `Integrations/Surface_ElvUI.lua` reading feeds (TBC
> text byte-identical); the harness stops dropping `Integrations/`.

Owned files:

- `UI/Feeds.lua` (new)
- `Integrations/ElvUIDatatext.lua` -> `Integrations/Surface_ElvUI.lua` (`git mv`, then edited)
- `tools/harness.lua`
- `tools/stub_hosts.lua` (new)
- `tools/surfacecheck.lua` (new)

Nothing else was edited, apart from this file.

## What was built

### `UI/Feeds.lua` (new, both main TOCs, after `UI/Tip.lua` / `UI/Tip_TBC.lua`)

`MD.Feeds` is a registry keyed by name.

- **`Register(key, def)`** raises on a second key, on a missing key, and on a def without
  `Text`. A def is `{ label, icon, Text(ctx), Face(), Tooltip(), Click(button) }`.
  - `ctx` is `{ valueHex, plain, compact }`. `compact` is reserved for T97, which owns
    `db.feeds.compact`.
- **`Get(key)`** returns the def. **`List()`** returns a copy of the keys, in registration order.
- **`Text(key, ctx)`** is the def's `Text` under `pcall`.
  - A raise, a non-string or `""` gives the feed's `label`, so the datatext keeps reading
    `SpellTuner` before the clock has a state, as before.
  - `ctx.plain` strips any colour code that is left.
  - A raise is counted in `Feeds.errors[key]` and logged to `MD:Debug("other")`. It never reaches
    the host.
- **`Face(key)`** and **`Tooltip(key)`** use the same guard.
- **`Click(key, button)`** answers `false` in combat (`MD.inCombat`, decision 17) and `true`
  otherwise. Left-click opens the window (`MD:ToggleDashboard`); right-click opens Settings
  (`MD:OpenDashboardSettings`).
- **`FEED_CHANGED`**: `Feeds.Poll` fires `MD:Fire("FEED_CHANGED", key)` once per tick for each
  feed whose text (with `ctx = {}`) differs from the last tick's.
  - It is registered with `MD:OnTick` at `MD_READY`. That puts it after every tick a file
    registers at load, so the clock's state (TTO on TBC, the pool on Forever) has already moved
    when a listener reads the new text.
  - Every read it makes is side-effect free. TBC's `MD:GetClockFace` only reads `disp` / `state`.
    Forever's `ClockFace.Current()` takes no time argument, so it reads the model's last tick and
    never advances the pool.

The two feeds:

- **`clock`** (label `SpellTuner`, icon `Interface\Icons\Spell_Shadow_Manaburn`, the minimap
  button's):
  - Its text is `ClockFace.LineString(MD.ClockFace.Current(), ctx.valueHex)`. On TBC that is
    exactly what `MD:GetDisplayString(hex)` returns (T88).
  - Its tooltip is the minimap tooltip's lines (`MD.MinimapLines()`), on both lines.
- **`regen`** (label `SpellTuner Regen`) shows the *current* regen: the casting rate inside the
  five-second rule, the full rate outside it.
  - Host form (a value colour): `Regen: <hex>123|r`, `Regen: <hex>123|r |cffffaa33(5SR)|r` and
    `Regen: <hex>--|r`. These are TBC's datatext bytes.
  - Plain form: `Regen 123`, `Regen 123 (5SR)` and `Regen --` (spec 6.2's broker words).
  - In combat on Forever the number is marked `~`.
  - **The reading** is `Feeds.RegenReading()`:
    - **On a line with a modelled pool** (`MD.Pool`, which Forever installs): the rates are
      `MD.Pool:LastRegen()`. The rule is the model's own (`model.t < model.lastSpend + 5`). In
      combat the number is marked modelled, because `ManaRegen()` is secret there and the rate
      is the last plain reading. Every number passes `MD.API.IsSecret` and a NaN test first, so a
      secret reads `--`. `MD.Regen` is never read on this line.
    - **Otherwise** (TBC): `Engine/RegenModel.lua`, read live (`RM:Current()`, `RM:InFSR()`),
      exactly as the datatext read it.
    - No mana pool (`MD.player.usesMana` false) reads `--`.
  - Its tooltip is the clock's.

Which line is which comes from a namespace the line installs (`MD.Pool`). Nothing tests the
client (apicheck rule 10).

### `Integrations/Surface_ElvUI.lua` (moved from `Integrations/ElvUIDatatext.lua`)

It still registers the same two datatexts at file load, with the same eleven arguments.

- `OOMUpdate` sets `Feeds.Text("clock", { valueHex = hex })`.
- `RegenUpdate` sets `Feeds.Text("regen", { valueHex = hex })`.
- The throttle and `ApplySettings` are unchanged.
- Differences, none of them visible on TBC:
  - **Host guards.** It returns quietly when `unpack(ElvUI)` is not a table with `GetModule`. It
    asks `E:GetModule("DataTexts", true)` (AceAddon's silent form), so an ElvUI without the
    module answers nil instead of raising. It also returns without `MD.Feeds`.
  - **Shift-click** reads `MD.API.IsShiftKeyDown()` (the adapter) and resets the spend window
    only where there is one (`MD.Spend`). Elsewhere it toggles the window.
  - **Tooltip.** With TBC's builders (`MD.Tip.Mana`), it shows the datatext's own lines byte for
    byte: `SpellTuner`, `Tip:Mana()`, `Tip:Fights(1)`, the spacer and the grey hint. Without
    them, it shows the clock feed's tooltip and the hint `Click: open the window`.
  - **`MD.Surfaces.elvui = { datatexts = { "SpellTuner", "SpellTuner Regen" } }`** records what it
    registered, for T97's INTEGRATIONS / dump line. T97 does not own this file.
- It stays on the TBC TOC only (spec 6.2: ElvUI's native surface waits until ElvUI is seen
  running on Forever).

### `tools/harness.lua`

`KeepForTbc` no longer drops `Integrations/`. With no host the surface returns at its first line.

### `tools/stub_hosts.lua` (new, not a suite)

It is loaded only by suites that ask for it, so no existing count moves. It fakes three hosts:

- **ElvUI**: `_G.ElvUI` (`unpack` gives `E`) and `E:GetModule("DataTexts")`. `noDataTexts` makes
  a half install. `DT:RegisterDatatext` records every call by ElvUI's argument names. `DT.tooltip`
  logs `ClearLines` / `AddLine` / `AddDoubleLine` / `Show`.
- **LibStub**: `NewLibrary` / `GetLibrary` / the call form / `IterateLibraries`.
- **LibDataBroker-1.1**: `NewDataObject` (nil for a taken name), `GetDataObjectByName`,
  `GetNameByDataObject`, `DataObjectIterator`, and CallbackHandler-shaped callbacks. A write to a
  proxy field is dropped when it equals the stored value, as the library does. Otherwise it
  announces the four `AttributeChanged` events, which are also kept in `lib.fired`.

It also provides `H.Panel()`, `H.Tooltip()` and `H.Remove()`.

## The checks

### `tools/surfacecheck.lua` (new, tbc + forever)

**1. No host** (both lines):

- 1a. On TBC the harness loaded `Integrations/Surface_ElvUI.lua` from the TOC; on Forever the
  TOC lists `UI/Feeds.lua`.
- 1b. `MD.Feeds` exists.
- The surface loads, raises nothing and records nothing in each of these cases:
  - 1c. no ElvUI;
  - 1d. only LibStub and LibDataBroker (and no object appears);
  - 1e. a half ElvUI.

**2. ElvUI** (both lines):

- 2a. With ElvUI the surface loads.
- 2b. Exactly two datatexts, in order.
- 2c. ElvUI's argument shape.
- 2d. `MD.Surfaces.elvui`.

**3. tbc: the golden.** It has 89 lines and was captured with `--golden` on `231525d`, against
`Integrations/ElvUIDatatext.lua`, **before the move** (`f80411f`). It holds:

- Both datatexts' text, read with no value colour and with ApplySettings' colour in both shapes
  ElvUI hands it (`16c3f2`, `|cff16c3f2`). The reads run over a scripted fight:
  1. login;
  2. full;
  3. out of combat at 74 %;
  4. the pull;
  5. a Healing Touch every 2 s, then every second into the crit band and an empty pool;
  6. a regen change;
  7. leaving combat;
  8. no mana pool.
- The tooltip (every call, with its colours) at three moments.
- The throttle.
- Both clicks, plain and Shift (window toggles, spend resets, the chat line).

The checks:

- 3a. The golden holds line for line.
- 3b. Every field is ASCII, with no bare pipe.

**3. forever** (ElvUI loaded by hand, to prove the feeds there):

- 3a. The clock datatext is the pool's face.
- 3b. Out of combat it reads `Regen: 346`.
- 3c. After a spend, `142 (5SR)`.
- 3d. In combat: `~142 (5SR)` inside the rule and `~346` after it.
- 3e. The client's own reading is secret meanwhile.
- 3f. The clock datatext in combat is still the face.
- 3g. A secret `LastRegen` reads `--` and raises nothing.
- 3h. No mana pool reads `--`.
- 3i. **`MD.Regen` is never read** (a metatable on `MD` counts the reads).
- 3j. Shift-click raises nothing without a spend window.
- 3k. The tooltip shows the feed's lines.

**4. ApplySettings:**

- 4a. The regen value is in the host's colour, and white without one.
- 4b (tbc). A point value of the clock takes the host's colour.
- 4b (forever). The line stays one colour (mono until T93).

**5. The feeds' contract:**

- 5a. Two feeds, in order.
- 5b. The labels and the icon.
- 5c. A second registration raises.
- 5d. A def with no `Text` raises.
- 5e. `List` returns a copy.
- 5f. For every `ClockFace.SAMPLES` face, the clock feed's text equals `LineString`, with and
  without a value colour.
- 5g. ASCII, no bare pipe.
- 5h. The plain form has the same words and no colour code.
- 5i. With no face, the text is the label.
- 5j. `Face` returns the current face.
- 5k. The regen feed's plain words.
- 5l. `--` in both forms.
- 5m. The clock tooltip equals `MD.MinimapLines()`.
- 5n. The regen tooltip.
- 5o. Left-click opens the window, right-click opens Settings, and both are refused in combat.

**6. FEED_CHANGED:**

- 6a. Eight quiet ticks fire nothing.
- 6b. Over a 20 s fight, the fires equal, per feed, the number of ticks on which its text changed.
- 6c. A listener reads the new text when it fires, so the poll runs after the state moved.

**7.** A feed whose `Text` raises answers its label.

**Counts:**

| | Parent `231525d` (suite committed alone, `f80411f`) | After (with the TOC lines) |
|---|---|---|
| `surfacecheck/tbc` | 11 ok, **5 failed** (1a, 1b, and the feeds blocks raise) | **32** ok, 0 failed |
| `surfacecheck/forever` | 12 ok, **13 failed** | **41** ok, 0 failed |

**Mutations** (each reverted):

| Mutation | Result |
|---|---|
| The regen feed's `(5SR)` loses its colour codes | tbc golden fails at line 17; forever 3c, 3d fail |
| `Feeds.Poll` fires on every tick | 6a, 6b fail on both lines |
| The regen reader asks `MD.Regen` before `MD.Pool` | forever 3i fails (18 reads) |

### Unchanged, with `Integrations/` now loaded on TBC

I ran `tools/check.sh` on the base and on the branch with the TOC lines and `stub_hosts` in
`NOT_SUITES`.

- Base `231525d`: 77 runs, all passed, 72 of 72 counted.
- After: **79 runs, all passed**. 74 counted: the 72 equal, plus `surfacecheck/tbc` 32 and
  `/forever` 41 new.
- The diff of every count line is exactly those two lines.
- By name, these are unchanged:
  - `slashcheck/tbc` 10, `verifycheck/tbc` 14, `minimapcheck` tbc 7 / forever 8, `ttocheck/tbc` 47;
  - `defaultscheck` tbc 49 / forever 52 (no new setting);
  - `reviewui/tbc` 50, `practiceui/tbc` 52, `replayui/tbc` 107.
- `apicheck`: 0 findings, 8 Forever TOCs, **63 -> 64 files** (`UI/Feeds.lua`), 48 globals.
- `textcheck`: 0 findings, 9 TOCs, **102 -> 103 files**.

`luac -p` passes on every changed file.

## Integrator lines

**`SpellTuner_TBC.toc`**: two changes.

- A new line `UI\Feeds.lua` right after `UI\Tip_TBC.lua` (before `UI\SpellTooltip.lua`).
- `Integrations\ElvUIDatatext.lua` becomes `Integrations\Surface_ElvUI.lua`, in the same place
  (after `UI\Summary.lua`). `## OptionalDeps: ElvUI` stays.

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical): a new line `UI\Feeds.lua`
right after `UI\Tip.lua` (before `UI\Dashboard_Rows.lua`). No Integrations line on Forever
(spec 6.2). No module TOC changes.

**`tools/check.sh`**: add `stub_hosts` to `NOT_SUITES`, after `stub_art`. The suite itself is
discovered by name and declares both flavours.

**`tools/data/expected-counts.json`**: add `"surfacecheck/tbc": 32` and
`"surfacecheck/forever": 41`.

**`CLAUDE.md`**:

- A new row after `UI/Tip.lua`'s (or beside the clock rows):

  > | `UI/Feeds.lua` | **The feeds, both lines** (T92, `docs/SPEC-next.md` 2.3, S3 step 1): `MD.Feeds` -- `Register(key, def)` (a second key raises; `def = { label, icon, Text(ctx), Face(), Tooltip(), Click(button) }`, `ctx = { valueHex, plain, compact }`), `Get`, `List`, and the guarded readers a surface calls (`Text` -- a raise or `""` answers the label, `plain` strips colour codes; `Face`, `Tooltip`, `Click` refused in combat); `FEED_CHANGED` from the tick (registered at `MD_READY`, so after the state moved) only when a feed's text changed. Two feeds: `clock` (`ClockFace.LineString` of `ClockFace.Current`, the minimap tooltip's lines) and `regen` (`Regen: 123`, ` (5SR)` in the rule, `~` when it is the last plain reading; plain `Regen 123`; `--` without a reading -- on the line with `MD.Pool` the pool's `LastRegen` and the model's own rule, never `MD.Regen`, never a secret; else `Engine/RegenModel.lua` live). Every main TOC, after `UI/Tip.lua` / `UI/Tip_TBC.lua` |

- `Integrations/ElvUIDatatext.lua`'s row becomes `Integrations/Surface_ElvUI.lua`:

  > | `Integrations/Surface_ElvUI.lua` | ElvUI's native datatexts `SpellTuner` and `SpellTuner Regen` (`DT:RegisterDatatext` at file load, `ApplySettings`' value colour), only when ElvUI is installed (`## OptionalDeps: ElvUI`), TBC TOC only. **T92:** moved from `Integrations/ElvUIDatatext.lua`; each datatext's text is a feed's (`MD.Feeds.Text("clock" / "regen", { valueHex })`), byte-identical on TBC; a half ElvUI (no DataTexts module, `GetModule(..., true)`) registers nothing; shift-click resets the spend window only where there is one; `MD.Surfaces.elvui` records the two names |

- The `tools/` row, after `tools/clockfacecheck.lua`'s sentence:

  > **`tools/surfacecheck.lua`** (T92, tbc + forever): the feeds and the ElvUI surface over `tools/stub_hosts.lua`'s fake hosts -- no host / LDB only / a half ElvUI register nothing; two datatexts; the TBC golden of both datatexts' text, tooltip, throttle and clicks captured on `231525d` before the move; Forever's datatexts from the pool (`~`, `(5SR)`, never `MD.Regen`, never a secret); ApplySettings; the feeds' contract; `FEED_CHANGED` exactly when a text changed. **`tools/stub_hosts.lua`** (T92, not a suite): fake ElvUI DataTexts, LibStub and LibDataBroker-1.1 with equal-write suppression, loaded only by the suites that ask. **The TBC harness loads `Integrations/`** (T92)

**`docs/TOOLS.md`** section 1: a new row after `clockfacecheck.lua`'s:

> | `surfacecheck.lua` | **feeds and the ElvUI surface** (T92, tbc 32 / forever 41): with no host, LibStub / LDB only, or a half ElvUI the surface registers nothing and raises nothing; ElvUI gets exactly two datatexts; tbc: the golden (89 lines: both texts with and without ApplySettings' colour over a scripted fight, the tooltip at three moments, the throttle, both clicks) captured on `231525d` against `Integrations/ElvUIDatatext.lua` before the move; forever: the clock datatext is the pool's face, the regen datatext the pool's last plain reading (`~` in combat, `(5SR)` in the rule), `MD.Regen` never read, a secret reads `--`; ApplySettings; `MD.Feeds`' contract over every `ClockFace.SAMPLES` face; `FEED_CHANGED` once per tick on which a text changed. Uses `tools/stub_hosts.lua` (fake ElvUI DT, LibStub, LDB-1.1). `--golden` prints the block to paste |

The `harness.lua` row (or its sentence) should also say: *T92: the TBC harness no longer drops
`Integrations/`*.

**`docs/HISTORY.md`**: wave N2's entry names T92:

- The ElvUI datatexts read `MD.Feeds` and are byte-identical on TBC (an 89-line golden).
- `Integrations/` now loads in the TBC harness, with every count unchanged.
- `stub_hosts` is ready for T97's brokers and EllesmereUI fakes.

**`docs/DECISIONS.md`**: no line. Nothing visible changes on TBC, and the feeds' click rule
(decision 17) is used by no surface yet. **`docs/TESTING.md`** (optional, section 46): *with
ElvUI on TBC, the `SpellTuner` and `SpellTuner Regen` datatexts read as before (the clock line;
`Regen: N`, `(5SR)` after a cast), the tooltip and Shift-click unchanged.*

## Deviations

1. **The regen feed does not read the face's `mp5` / `fsr`** (spec 2.3: "the regen feed reads
   the face's mp5 / fsr fields"). Neither line's face can carry the current regen:
   - **TBC.** The face's `mp5` is the last tick's `state.regenNow`, while its `fsr` is read live,
     so for up to 0.5 s after a cast they disagree (the full rate shown with `(5SR)`). The
     datatext read `RM:Current()` / `RM:InFSR()` live, and the golden requires that.
   - **Forever.** The face's `mp5` is the fight's averaged effective regen, and in combat only.
     Its `fsr` is nil (T88 deviation 5).

   The feed therefore reads each line's own regen source: `MD.Pool:LastRegen()` plus the model's
   rule on the line that installs `MD.Pool`, else `MD.Regen` live. This keeps the spec's
   guarantees: Forever's regen is the pool's, never `MD.Regen`, never a secret. When T93 or a
   later task gives the face a current-regen field on both lines, the feed can move to it.
2. **The ElvUI tooltip on TBC is not the feed's tooltip.** It keeps its own lines (`Tip:Mana`,
   `Tip:Fights(1)`) byte for byte, because changing them would be a visible TBC change. The
   clock feed's tooltip (the minimap lines) is used where those builders are absent.
3. **The regen feed has two wordings.** The host form keeps TBC's colon (`Regen: 123`), because
   the datatext's bytes are the golden. The plain form takes spec 6.2's broker words
   (`Regen 123`), ready for T97, which owns the broker text and may re-word it.
4. **`ctx.compact` is accepted and ignored.** The compact broker setting and its default
   (`db.feeds`) are T97's. No default was registered here, so `defaultscheck` is unchanged.
5. **Shift-click and the host guards on the surface** (above) are additions. Each is a no-op on
   TBC with ElvUI installed, which the golden's click lines hold.
6. **The TOC lines and the `NOT_SUITES` entry are not committed** (integrator-owned). Without
   them, every TBC suite fails to load (the TBC TOC names the old file) and
   `surfacecheck/forever` 1a fails.
