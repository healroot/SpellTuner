# T97 -- Brokers and EllesmereUI (6.2-6.3)

Status: **built** 2026-10-01 on branch `next/T97` (base `25748e3`), wave N3 of
`docs/SPEC-next.md`, beside T98, T100, T99 and T101. It awaits the integrator.

**The branch needs its TOC lines (below).** The TOCs are integrator-owned. Without them no TOC
loads the two new files, so `euicheck` 1 fails (the files are loaded by hand for the rest of the
suite) and `surfacecheck/tbc` 8a fails. The lines, and a rebuilt
`tools/data/import-forever-sv.lua`, were applied in the working tree to run every check. They were
reverted before the commit.

## The task (docs/SPEC-next.md section 11, row T97; 6.2, 6.3, 5.5, 6.4; R-ellesmere.md)

> **Brokers + EllesmereUI (6.2-6.3).** `Integrations/Surface_LDB.lua` (both TOCs);
> `Integrations/EllesmereUI_Forever.lua` (Forever TOCs: the mover with whitelisted fields only, the
> unlock listener, `RegisterSkin` storing `MD.EUISkin` and firing `EUI_SKIN_READY`, `TESTED_EUI`,
> the `apiVersion` check); the INTEGRATIONS / dump line through `MD:AddDumpLine`; the
> minimap-collector fixes; apicheck rule 11; `db.feeds` / `db.eui` defaults (reported for
> `defaultscheck`).

Owned files, and what was done to each:

- `Integrations/Surface_LDB.lua` (new)
- `Integrations/EllesmereUI_Forever.lua` (new)
- `UI/MinimapButton.lua`
- `tools/apicheck.py`
- `tools/data/apicheck-fixture-foreign.lua` (new)
- `tools/stub_hosts.lua`
- `tools/euicheck.lua` (new)
- `tools/surfacecheck.lua`
- `tools/minimapcheck.lua`

No other file was edited, apart from this one.

## What was built

### `Integrations/Surface_LDB.lua` (new; both main TOCs, after `UI/Feeds.lua`)

This file publishes two LibDataBroker-1.1 data objects. Any broker display picks them up:
EllesmereUI's DataBars "Broker Plugin" block on Forever, and Titan, ChocolateBar or ElvUI's
"Data Broker" list on TBC.

- **`SpellTuner`** shows the `clock` feed's words with no colour code.
  - The face is cut into its segments and joined (`ClockFace.Segments` / `JoinSegments`). The
    result is LineString's words without colour codes, for example `~OOM 1:20  rest 2:10` on
    Forever and `OOM 1:20 v` on TBC.
  - `db.feeds.compact` drops the secondary segment (rest, or a cooldown). The label and the
    honesty marks stay.
  - Before a face exists, and for a character with no mana pool, the text is the label
    `SpellTuner`.
  - **The tint (`iconR/G/B`)** carries the tone, because DataBars strips colour codes by default:
    - full, out of combat, or full now: the `mana` colour;
    - a bound, a warm-up, no number, or an unstable value: muted;
    - an OOM point value: its band. That is red under 20 s, amber under 60 s, and white (the icon
      as drawn) otherwise.
- **`SpellTuner Regen`** shows the `regen` feed's plain words: `Regen 123`, `Regen 123 (5SR)`,
  `Regen ~123` (the last plain reading, in combat on Forever) and `Regen --`.
  - Its tint is amber inside the five-second rule, white outside it, and muted without a reading.
- **Shared by both objects:**
  - the minimap button's icon;
  - `type = "data source"`;
  - `OnClick(frame, button)`, which goes to `MD.Feeds.Click`: left opens the window, right opens
    Settings, and both are refused in combat;
  - `OnTooltipShow(tt)`, which goes to `MD.Tip:Render`: the feed's tooltip lines, a spacer, then
    `Left-click | open the window`, `Right-click | Settings` and `(not in combat)`.
  - Neither object has an `OnEnter`, so the display anchors and skins its own GameTooltip.
- **The library is borrowed.** The file asks `LibStub:GetLibrary("LibDataBroker-1.1", true)`
  under `pcall`. Nothing is shipped, and without a host nothing is published.
  - The objects are published at `MD_READY`.
  - They are published again on a later `ADDON_LOADED`, for a host that loads on demand.
  - A name that another addon already holds is left to that addon (`GetDataObjectByName` first).
    A second `NewDataObject` is never attempted.
- **Updates.** `MD:OnTick`, registered at `MD_READY` (after the pool and the clock have ticked),
  writes `text` and `iconR/G/B` on every tick. The library drops an equal write, so a display
  repaints only on a real change.
- **The clock's look.** If a file provides `MD.ClockLook()` (the user's clock settings, through
  `MD:Provide("ClockLook", fn)`; T98 / T102), its `show.rest` / `show.cd` are followed. Until then
  every segment the face carries is shown. See deviation 3.
- **`MD.Integrations`** (this file, both TOCs) says what was found:
  - `Lines()` gives the INTEGRATIONS pane's lines, which T102 shows:
    - `EllesmereUI 9.3.4 (tested 9.3.4): brokers SpellTuner + SpellTuner Regen; mover SpellTuner clock`
    - `ElvUI: 2 datatexts`
    - `Broker: 2 objects` (when there is no EllesmereUI)
    - `none found`
  - `DumpLine()` gives `/st dump`'s line, for example:
    `integrations: EllesmereUI 9.3.4 (tested 9.3.4), skin apiVersion 2, brokers SpellTuner + SpellTuner Regen, mover SpellTuner_Clock`.
    When there is no EllesmereUI, it reads `integrations: brokers SpellTuner + SpellTuner Regen`.
    `, ElvUI 2 datatexts` is added when ElvUI is there.
  - `Note()` registers that line through `MD:AddDumpLine("integrations", ...)`, once something was
    found (brokers published, EllesmereUI present, or ElvUI's datatexts). A dump with no host is
    byte-identical, which `consolecheck` holds.
- **Defaults:**
  `MD:RegisterDefaults({ feeds = { ldb = true, elvui = true, compact = false } })`.
  `ldb = false` publishes nothing.
- **`MD.SurfaceLDB`**, for a suite and for T102: `ClockText`, `RegenText`, `ClockTone`,
  `RegenTone`, `State`, `TooltipLines`, `Publish`, `Update`, `Object(key)`, `why`.

### `Integrations/EllesmereUI_Forever.lua` (new; Forever TOCs only, after `Surface_LDB.lua`)

The file does nothing without `EllesmereUI`. Every call into EllesmereUI is guarded with
`type(...) == "function"` and `pcall`.

- **The skin facade.**
  - `EllesmereUI.RegisterSkin("SpellTuner", fn)` is called once, at file load. The TOCs'
    `## OptionalDeps: EllesmereUI` makes the parent's queueing stub exist by then.
  - `fn(S)` keeps `MD.EUISkin = S` and fires `EUI_SKIN_READY` once, whichever addon's
    `PLAYER_LOGIN` comes first (X4).
  - Only `S.apiVersion == 2` is followed. Its `OnLooksChanged` fires `EUI_LOOKS_CHANGED`.
  - Any other version is stored but not hooked, and no getter is read. The lines then say
    `skin apiVersion <n>: not followed`.
  - `EUI.SkinFollowed()` tells T100's style whether to follow.
  - This file reads no getter. The follow itself is `UI/Style_Ellesmere.lua`'s (T100).
  - No SpellTuner frame is handed to `S.Shell` / `S.Panel` / `S.Button` (decision 5, X3).
- **The mover.** At `MD_READY` the file registers one element, `SpellTuner_Clock`, labelled
  `SpellTuner clock` in group `SpellTuner`, order 900.
  - It is built through `EllesmereUI.MakeUnlockElement` with whitelisted fields only (X2):
    - `getFrame` and `getSize`;
    - `savePos`, which writes the clock's own `db.clock.point = { point, nil, relPoint, x, y }`
      (the CENTER/CENTER-on-UIParent shape EllesmereUI hands over) and applies it;
    - `loadPos`;
    - `clearPos`, which calls the clock's `ResetPosition`;
    - `applyPos`, which calls the clock's `ApplyPoint`;
    - `isHidden`, which is true when `db.clock.shown` is off;
    - `noResize`.
  - It is registered with `E:RegisterUnlockElements({ elem }, "SpellTuner")`.
  - The clock is reached through T93's mover seam, `MD.ClockWidget`.
  - **In combat** a saved point is stored but not applied. It is applied on
    `PLAYER_REGEN_ENABLED` (6.4: never move a frame in combat).
  - **The listener** (`RegisterUnlockModeListener`):
    - When `/unlock` opens, it starts the clock's own preview (`Preview(3600)`).
    - When `/unlock` closes, it ends the preview it started (`Preview(0)`).
    - It never calls `Show` / `Hide`.
  - Without the unlock functions the clock keeps its own drag, and the lines say
    `mover: not offered by this EllesmereUI`.
  - `db.eui.unlock = false` gives `mover: off`.
- **The version guard.** `EUI.TESTED = "9.3.4"` (TESTED_EUI).
  - The running version comes from `MD.API.AddOnMetadata("EllesmereUI", "Version")`; it is `?`
    when the client does not answer.
  - Every line prints `(tested 9.3.4)` beside it.
  - Another version runs unchanged.
- **Default:** `MD:RegisterDefaults({ eui = { unlock = true } })`.
- **Never:**
  - reads `_ModuleNS`, `EllesmereUIDataBarsDB` or `EllesmereUIDB`;
  - calls `RegisterModule`;
  - touches `ManaRegenSpark`;
  - registers an event on a frame of its own (it uses `MD:On`).

### `UI/MinimapButton.lua` (the collector fixes, 6.3)

- `Reposition()` returns when the button's parent is no longer `Minimap`, that is, when a
  collector took it. So does the angle drag (`OnDragStart`). Settings -> Windows' toggle
  (`MD:UpdateMinimapButton`) therefore no longer pulls a collected button back to the minimap's
  edge.
- The icon is kept as `btn.icon`, which is what EllesmereUI's collector looks for by name. It is
  anchored `CENTER` at `(1.5, 0.5)`, which is exactly the place `TOPLEFT 7, -5` gave the 20 x 20
  icon in the 31 x 31 button.
- With no collector the parent is always `Minimap`, so nothing changes. Both TBC goldens hold.
- The spec's conditional third fix (create the frame at `ADDON_LOADED` if the button is created
  after EllesmereUI's scans) waits for in-game check 6, as the spec says.

### `tools/apicheck.py`: rule 11

- `FOREIGN = {"EllesmereUI", "LibStub", "ElvUI"}`.
- Under `Integrations/` these globals are allowed (classified `foreign`).
- Anywhere else a read is a finding: `host addon outside Integrations/`.
- The rule is read from luac's `GETGLOBAL`, like rules 1-4. `Client/Probe.lua`'s `== hosts`
  section names these globals as strings through `MD.API.Has`, so the rule does not see them.
- The selftest scans `tools/data/apicheck-fixture-foreign.lua` twice: as itself, which gives one
  finding (line 6), and as `Integrations/apicheck-fixture-foreign.lua`, which gives none. The
  fixture sits beside the fixture folder, so no fixture TOC is touched.
- Selftest: **13 -> 14**. Red first: with the expectation and before the rule, both scans
  reported `EllesmereUI not in baseline 69893`.

### Tests

**`tools/stub_hosts.lua`** (not a suite) gains:

- `H.InstallEllesmere(opts)`: `RegisterSkin`'s queue (the first name wins), `_DispatchSkins(S)`
  (BlizzardSkin's `PLAYER_LOGIN`), `MakeUnlockElement`, `RegisterUnlockElements` and the unlock
  listener. Each one records its calls. Options: `bare`, `noUnlock`, `noListener`, `noSkin`.
  - `MakeUnlockElement` copies only `H.UNLOCK_WHITELIST`, which is EllesmereUI 9.3.4's list
    (`EllesmereUI.lua` 2324-2381), renamed to the long names.
- `H.SkinFacade(opts)`, whose getters count their reads, and `H.LooksChanged(S)`.
- `H.AddOnMeta(MD, map)`.
- The DataBars reader: `H.LdbBlockText`, `H.LdbIcon` and `H.LdbTooltip`. These are
  `Blocks/LDB.lua`'s display rules: text, else value plus suffix; colours stripped; the honoured
  tint; the `OnTooltipShow` route.
- `H.Remove()` also removes `EllesmereUI`.

**`tools/euicheck.lua`** (new, forever). Each block is a fresh session, with its hosts installed
before the TOC loads:

1. **Absent host.** Nothing raises, nothing is published, and no global, `MD.EUISkin` or dump
   line appears. Both Forever TOCs list the two files after `UI/MinimapButton.lua` and carry
   `## OptionalDeps: EllesmereUI`.
2. **A half install** (LibStub without LDB, a bare `EllesmereUI`) stays quiet, and its exact dump
   line is checked.
3. **11b: a late host.** LDB installed after `MD_READY` publishes on `ADDON_LOADED`.
4. **Two objects**, with their shape.
5. **One string.** The block equals the clock's drawn segments on every one of 112 ticks of a
   scripted fight. The fight shows `~FULL`, `~FULL t`, `~OOM ...  rest`, `~OOM t  rest t` and
   back.
6. **Equal writes.** Ten quiet ticks fire nothing; one spend fires exactly one text change.
7. **The tint** for every `ClockFace.SAMPLES` face plus a warn face, and the live object's RGB.
8. **Regen.** `Regen 346`, `Regen 142 (5SR)` with the amber tint, `Regen ~142 (5SR)`,
   `Regen ~346` and `Regen --`. Each N is `floor(rate * 5 + 0.5)` of `MD.Pool:LastRegen()`.
9. **Clicks.** Left and right work out of combat; both are refused in combat.
10. **The tooltip.** It holds the clock's `SummaryLines` and the three hints, and is shown once,
    by the reader.
11. **A late reader** finds the objects by name and hears the next change, with no second
    `NewDataObject`.
12. **The mover.**
    - It is registered under folder `SpellTuner`, with size 180 x 30.
    - save, load and apply work, and clear goes to the default `TOP 0,-120`.
    - In a fight it waits until `PLAYER_REGEN_ENABLED`.
    - `isHidden` follows `db.clock.shown`.
    - The listener previews, then ends the preview.
13. **Settings off** publish and register nothing, and the line is checked.
14. **`RegisterSkin`** is called once.
15. **The whitelist.** Every field passed is on it; what survived holds every required field
    plus `isHidden` and `noResize`; an off-list field is dropped.
16. **9.4.0** runs, and both lines say `(tested 9.3.4)`.
17. **apiVersion 3**, with the facade handed over before SpellTuner registered: it is stored, no
    read is made, nothing is hooked, no `EUI_SKIN_READY` is fired after the stored one, and the
    line says `skin apiVersion 3: not followed`.
18. **`EUI_SKIN_READY`** fires once, and `OnLooksChanged` gives `EUI_LOOKS_CHANGED` with no
    getter read.
19. **5: ASCII**, with no colour code and no bare pipe, across all 167 strings seen.

**`tools/surfacecheck.lua`** (tbc +2):

- 8a: from the TBC TOC, nothing is published before a host. Once a host loads there are two
  objects. The clock text equals `JoinSegments` and the feed's plain text, in TBC words.
- 8b: the regen object reads the feed's plain words; a click works only out of combat; the
  tooltip is shown.

**`tools/minimapcheck.lua`** (+1 per flavour): a collected button is not pulled back. The test
reparents it to a fake flyout, then checks that `MD:UpdateMinimapButton` and the drag leave it
alone, that `btn.icon` is a texture of the button, and that it is repositioned once back on
`Minimap`.

## Counts

| | Parent `25748e3` (suites committed first, `95f79f7`) | After (with the integrator lines) |
|---|---|---|
| `euicheck/forever` (new) | 0 ok, **19 failed** | **19** ok |
| `surfacecheck/tbc` | 32 ok, **2 failed** (8a, 8b) | **34** ok |
| `surfacecheck/forever` | 41 | 41 (unchanged) |
| `minimapcheck/tbc` | 7 ok, **1 failed** | **8** ok |
| `minimapcheck/forever` | 8 ok, **1 failed** | **9** ok |
| `apicheck-selftest` | 13 (red with the new expectation: `not in baseline` twice) | **14** |
| `apicheck` | 66 files, 49 globals, 0 findings | 68 files, 51 globals, **0 findings** |
| `textcheck` | 105 files, 0 findings | 107 files, **0 findings** |
| `defaultscheck` | tbc 49 / forever 52; "every setting read" tbc 44 read, forever 28 read | tbc **49** / forever **52** (assertions unchanged); tbc 45 read (`feeds`), forever 30 read (`feeds`, `eui`) |
| `consolecheck` | forever 22 / tbc 1 | unchanged (no dump line without a host) |
| `tools/check.sh` | 81 runs, all passed, 76 counted | **82 runs, all passed**; the only count notes are the five lines below |

`luac -p` passes on every changed Lua file.

`make check` was run with the TOC lines and the rebuilt fixture applied. Everything else is
unchanged, by name: `slashcheck/tbc`, `verifycheck`, `ttocheck`, `clockcheck`, `stylecheck`,
`reviewui`, `practiceui`, `replayui`, `releasecheck` 21. Without the fixture rebuild,
`importcheck` fails its first check: the new defaults land in `SpellTunerDB`.

## Integrator lines

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical):

- After `## SavedVariables: SpellTunerDB`, add a header line `## OptionalDeps: EllesmereUI`.
- After `UI\MinimapButton.lua` (before `UI\DebugConsole.lua`), add two lines:
  ```
  Integrations\Surface_LDB.lua
  Integrations\EllesmereUI_Forever.lua
  ```
- No module TOC changes.

**`SpellTuner_TBC.toc`**:

- After `Integrations\Surface_ElvUI.lua`, add `Integrations\Surface_LDB.lua`.
- `## OptionalDeps: ElvUI` stays. EllesmereUI never runs on TBC, so it is not listed there.

**`tools/data/import-forever-sv.lua`**: after the TOC lines, rebuild it with
`bash tools/run.sh tools/importfixture.lua`. It gains exactly eight lines, `eui.unlock = true`
and `feeds = { compact = false, elvui = true, ldb = true }`, inserted after line 2102 (the writer
sorts keys).

**`tools/data/expected-counts.json`**:

- add `"euicheck/forever": 19`;
- change `"surfacecheck/tbc": 32` to `34`;
- change `"minimapcheck/tbc": 7` to `8`;
- change `"minimapcheck/forever": 8` to `9`;
- change `"apicheck-selftest": 13` to `14`.

**`tools/check.sh`**: nothing. `euicheck` is discovered by name and declares `forever`, and
`stub_hosts` is already in `NOT_SUITES`.

**`defaultscheck`** (reported, not edited): the assertion counts are unchanged (tbc 49,
forever 52). The scan's read keys go from tbc 44 to 45 (`feeds`) and from forever 28 to 30
(`feeds`, `eui`).

**`CLAUDE.md`**: two new rows after `Integrations/Surface_ElvUI.lua`'s:

> | `Integrations/Surface_LDB.lua` | **The LibDataBroker surface, both lines** (T97, `docs/SPEC-next.md` 6.2): two LDB-1.1 objects on a library BORROWED from a host (LibStub's; EllesmereUI, ElvUI and Titan ship it; nothing shipped) -- `SpellTuner` (the clock's words without colour, `ClockFace.Segments` joined; `db.feeds.compact` drops the secondary; the tone as `iconR/G/B`: FULL mana, bound / warm-up / no number muted, OOM red under 20 s, amber under 60 s) and `SpellTuner Regen` (the regen feed's plain words, amber in the 5SR); clicks through `MD.Feeds.Click` (out of combat only), `OnTooltipShow` through `MD.Tip:Render` (never `OnEnter`); published at `MD_READY` and on a later `ADDON_LOADED`, a taken name left alone, never a second `NewDataObject`; updated from `MD:OnTick` (the library drops equal writes); follows `MD.ClockLook()` when a file provides it. `MD.Integrations` -- `Lines()` (the INTEGRATIONS pane's), `DumpLine()` (`integrations: EllesmereUI 9.3.4 (tested 9.3.4), skin apiVersion 2, brokers SpellTuner + SpellTuner Regen, mover SpellTuner_Clock`), registered through `MD:AddDumpLine` only once something is found. `db.feeds = { ldb, elvui, compact }`. Every main TOC, after `UI/Feeds.lua` (Forever: after `UI/MinimapButton.lua`; TBC: after `Integrations/Surface_ElvUI.lua`) |
> | `Integrations/EllesmereUI_Forever.lua` | **EllesmereUI's public entry points, Forever only** (T97, `docs/SPEC-next.md` 6.3, 5.5; `## OptionalDeps: EllesmereUI`): `RegisterSkin("SpellTuner")` once at file load -- the facade kept as `MD.EUISkin`, `EUI_SKIN_READY` fired once whichever login comes first, only `apiVersion == 2` followed (`OnLooksChanged` -> `EUI_LOOKS_CHANGED`; `EUI.SkinFollowed()`), no getter read here, no frame handed to `S.Shell` / `Panel` / `Button`; the `/unlock` mover `SpellTuner_Clock` through `MakeUnlockElement` with whitelisted fields only, on T93's `MD.ClockWidget` seam (`db.clock.point`, `ApplyPoint`, `ResetPosition`, a point saved in combat applied after it), its listener running the clock's preview while `/unlock` is open; `TESTED_EUI = "9.3.4"` printed beside the running version (`MD.API.AddOnMetadata`); `db.eui.unlock` |

Add to the `UI/MinimapButton.lua` row:

> **T97:** a button a collector reparented (EllesmereUI's flyout, MBB) is never pulled back by `Reposition` or the angle drag; the icon is `btn.icon`, anchored CENTER at its old place.

Add to the `tools/` row, after `tools/surfacecheck.lua`'s sentence:

> **`tools/euicheck.lua`** (T97, forever): the brokers and EllesmereUI over `tools/stub_hosts.lua`'s fake EllesmereUI 9.3.4 (RegisterSkin's queue, `MakeUnlockElement`'s whitelist, the unlock registry and listener), its skin facade and the DataBars reader, each block a fresh session -- absent / half / late host, two objects, the block equal to the clock's drawn words on every tick, equal writes silent, tint, regen, clicks, tooltip, a late reader, the mover, settings off, `RegisterSkin` once, the whitelist, 9.4.0 `(tested 9.3.4)`, apiVersion 3 not followed, `EUI_SKIN_READY` once.

Add to the `tools/apicheck.py` sentence:

> rule 11 (T97): `EllesmereUI` / `LibStub` / `ElvUI` read outside `Integrations/` is a finding.

Add to the "API defensiveness" or "No libraries" convention:

> host libraries (LibStub, LibDataBroker) are borrowed from a host that loaded them, never shipped (T97).

**`docs/TOOLS.md`** section 1:

- A new row:

  > | `euicheck.lua` | **brokers + EllesmereUI** (T97, forever 19): fresh sessions over `tools/stub_hosts.lua`'s fake EllesmereUI 9.3.4, LibStub and LDB-1.1 -- absent host quiet (and the TOC lines), a half install quiet, a late host published on `ADDON_LOADED`, two data objects, the `SpellTuner` block equal to the clock's drawn segments on all 112 ticks of a fight, equal writes silent, the tint per tone, the regen words, clicks refused in combat, the tooltip through `OnTooltipShow`, a late reader, the mover (save / load / apply / clear / combat / hidden / the `/unlock` preview), settings off, `RegisterSkin` once, the unlock whitelist, a 9.4.0 `(tested 9.3.4)`, apiVersion 3 not followed, `EUI_SKIN_READY` once, every string ASCII without colour |

- `surfacecheck.lua`'s row: `tbc 32 -> 34 (8a/8b: the brokers on TBC)`.
- `minimapcheck.lua`'s row: `tbc 7 -> 8, forever 8 -> 9 (a collected button is not pulled back)`.
- The apicheck row: rule 11, selftest 14.

**`docs/TESTING.md`** section 46: spec section 12's items 5, 6 and 7 as written (brokers with
EllesmereUI, the mover and the minimap flyout, brokers on TBC with ElvUI).

**`docs/DECISIONS.md`** (proposed lines):

- *LibDataBroker and LibStub are borrowed, never shipped (T97).* `Integrations/Surface_LDB.lua`
  publishes only through the copy a host loaded (EllesmereUI, ElvUI, Titan). With no host nothing
  is published. `release.sh` ships no library file. Host globals are read only under
  `Integrations/` (apicheck rule 11).
- *Brokers on both lines, on by default even with ElvUI (decision 19, T97).* On TBC with ElvUI,
  its datatext list shows the native `SpellTuner` and the wrapped `LDB: SpellTuner`; Settings
  will say to pick the native one (T102). This is a visible TBC addition (a broker display now
  lists two SpellTuner objects); `db.feeds.ldb = false` removes them after a `/reload`.
- *A collected minimap button stays collected (T97, decision 20).* `Reposition` and the angle
  drag leave a button whose parent is not `Minimap`. On TBC this matters only with a collector
  addon (MBB and the like), which until now had the button pulled back by the Settings toggle.
- *EllesmereUI is Forever-only and followed only at skin apiVersion 2; TESTED_EUI = 9.3.4 is
  printed beside the running version (T97, X1).*

**`docs/HISTORY.md`**: wave N3's entry names T97:

- The two brokers, on both lines.
- EllesmereUI's skin hand-over, mover and version guard.
- The minimap-collector fixes.
- apicheck rule 11.
- `euicheck` 19.

## Deviations

1. **`compact` drops the secondary segment only.** The spec says the `compact` setting "drops the
   label/rest". Dropping the label would drop Forever's `~` (it sits on the label) and the
   `OOM` / `FULL` word. Principle 4 says those cannot be configured away, so compact keeps
   `~OOM 1:20` and drops `  rest 2:10` (or a cooldown).
2. **`db.feeds.elvui` is declared but not read yet.** The spec groups it with `ldb` and `compact`.
   `Integrations/Surface_ElvUI.lua` (T92's, not owned here) registers its datatexts at file load,
   before any setting exists, and does not read the switch. Honouring it needs that file, and a
   `/reload` for the change to show. A later task (or T102 with that file) can wire it.
   `defaultscheck` is green either way.
3. **On Forever the broker shows the rest segment even when `db.clock.showRest` is off.**
   - The Forever face carries its rest segment whatever the switch says, because the renderer
     (`UI/Clock_Forever.lua`, T98's this wave) gates it. TBC's face gates it itself.
   - Reading `db.clock` and `db.showRest` here would make one line read the other line's keys,
     and `defaultscheck` fails on a key with no default on that line.
   - So the broker follows `MD.ClockLook()` when a file provides it (`MD:Provide("ClockLook", fn)`
     answering the resolved look with its `show` table). The natural owner is T98's
     `db.clockLook` resolution, or `UI/Clock_Forever.lua` / `UI/Widget.lua`.
   - With the default settings, the broker and the clock say the same thing on every tick
     (`euicheck` 4).
4. **The dump line is registered lazily**, once something is found. This is `UI/Styles.lua`'s
   pattern, and it keeps `consolecheck`'s "no dump line" dump byte-identical on a client with no
   host. `none found` is therefore the INTEGRATIONS pane's word only.
5. **The EllesmereUI lines always print `(tested 9.3.4)`**, even at 9.3.4. That is the spec's
   dump example. The pane example in 6.3 omits it, but "the INTEGRATIONS line and the dump say
   `(tested 9.3.4)` beside it" asks for it in both.
6. **`euicheck` has 19 assertions, not 18.** R-ellesmere's "late host" (LDB arriving after
   `MD_READY`, published on `ADDON_LOADED`) and the spec's "late reader" are two checks (11b,
   11). R-ellesmere's 15th check (the minimap) is in `minimapcheck`, as the spec puts it.
7. **`minimapcheck` is +1 on each flavour, not +1 in all.** The fix is in a shared file, and a
   collector exists on TBC too.
8. **Two small additions:**
   - a point the mover saves in combat is applied on `PLAYER_REGEN_ENABLED` (6.4 "never moves a
     frame in combat");
   - the brokers retry on `ADDON_LOADED` for a host that loads after `MD_READY`.
9. **The tint's "normal" band is white** (the icon untinted) for an OOM time of 60 s or more. The
   spec's tint sentence is garbled ("warn amber over 60 s... crit red at or under 20 s"). The
   face's own bands are used (decision 16: red under 20 s, amber under 60 s), so the broker and
   the clock agree.
10. **The minimap button's third fix** (moving its creation to `ADDON_LOADED`) is not made. It is
    conditional on in-game check 6.
11. **The TOC lines and the fixture rebuild are not committed** (integrator-owned). Without them,
    `euicheck` 1 and `surfacecheck/tbc` 8a fail. Without the rebuild, `importcheck` fails its
    fixture check.
