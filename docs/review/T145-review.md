# T145a-e review (clock v3, commits 3c37952..2ecbe9e, branch claude/clockview-fixes-1059a4)

Reviewer: independent adversarial review (Opus), 2026-11-08. First review of this unit.
Scope: `git diff 132da97..2ecbe9e` against `docs/SPEC-clock-v3.md` (sections 0-4 and 6), the
diagnosis `docs/review/clock-v3-diagnosis.md`, the task files T145a-e and the three implementer
reports. Suites run, single files only: `clocke2e` (forever 18 ok, tbc 13 ok), `clockbarcheck`
(22 / 22), `clockwordscheck` (62 / 51), `clockstorecheck` (43 / 42). `make check` was not rerun.
One throwaway script in the scratchpad (the live clock's drawn words at E1's moment).

**Verdict: pass-with-minors.** 0 blockers, 3 should-fix, 6 nits.

The three in-game bugs are fixed on the code paths the author uses. Bug 1 (inert settings) is
mostly fixed. One TBC control is still inert in a reachable state (S1), and E1 can pass for a
text that draws nothing (S2).

## What was checked and holds

- **Bug 2 (FULL, never `0s`).** `ClockWords.IsFull` (`Engine/ClockWords.lua:75-86`) catches all
  of these, in this order:
  - the quiet signal;
  - `fullnow`;
  - a plain `pct >= 0.995`;
  - `full` / `ooc` with a point value under 5.

  The diagnosis case (in combat, mode `full`, ttf 0) gives `FULL`. On Forever,
  `ManaModel.Face` sets `pct = mana / max`, so a model clamped at max is `FULL` in any mode.
  - A filling time always gets the `FULL ` prefix (`TimeWords`, line 191).
  - An OOM value under 1 reads `OOM` (line 199).
  - A bound under 1 reads `--`.
  - The rest text needs `value >= 1`.
  - Entering FULL snaps the latch (`SnapFull`), so a step can never walk down to 0.

  TBC's face carries the real `pct` (`Engine/TTO.lua:349`), so the same rule covers TBC.
  - `Put(t, TimeWords(...))` is the last argument, so both returns arrive (no multi-return
    truncation).
- **Bug 3 (the line).** The line is drawn by one driver.
  - The driver is a plain 1x1 frame created in `ClockBar.New` (`UI/ClockBar.lua:335-340`). Its
    `OnUpdate` is set once, and no `SetScript` on it exists anywhere else (grep).
  - `Apply` writes only `barW` / `lineOn`. `Message`, `PaintPower`, the preview and the regen
    events never touch the driver.
  - Forever's `fsrEnd` is `model.lastSpend + 5` (`UI/Clock_Forever.lua:255-259`). TBC's is
    `ST.Regen.fsrEnd` (`UI/Widget.lua:36-40`). Both are plain.
  - A `/reload` makes a new renderer with a new driver.
  - In combat the host is always shown (`Visibility.Want`), so the line cannot stop mid-fight.
  - E6 runs on the real hosts. It covers 22 disturbances plus every Bar control operated from the
    pane mid-rule, and checks that the line hides within one frame of the rule's end. Both
    flavours pass.
- **Bug 1, the main path.** Every control writes through `ClockStore` and fires exactly one
  `CLOCK_LOOK`: `Set`, `SetText`, `SetMany`, `ApplyPreset`, `Undo` and `Reset`.
  - `Stored()` normalizes without firing an event.
  - Each host's `NewLook` re-reads `Store.Look()` (a copy, so `look.notes` never reaches the
    store), then calls `Apply` and repaints.
  - The pane hides an off text's fields (`visible`), Custom's swatch, Time as / Warn colours, and
    Undo while no undo is held.
  - The presets satisfy P2. `PresetOK` refuses a preset that turns off the time or the line.
- **Migration.**
  - The live saved variables' `clockLook` is identical to `tools/data/clock-v2-author.lua`
    (diffed).
  - `V2_ITEMS` equals the old `CV.ITEMS_DEFAULT` field for field (checked against 132da97).
  - The golden migrates to the exact table of spec 1.5 with the four notes.
  - `MigrateStored` writes v3 only (no `over`, no `layout`) and runs once a session.
  - On a second login the store is v3, `Normalize` changes nothing, and nothing is lost.
  - Other inputs:
    - empty / nil: the defaults;
    - garbage: the defaults, named;
    - v1: `MigrateV1`, then the T142 reset, then the v2 path;
    - junk keys: named.
- **Secrets / adapter.**
  - The power values reach the renderer only through `ST.API.DrawUnitPower` /
    `DrawUnitPowerMax` / `DrawPowerText`. Each passes the client's return straight into the
    setter inside a pcall.
  - Nothing reads a power text or the bar back: no `GetText`, `GetStringWidth` or `GetValue`.
    `Drawn()` reads the renderer's own cache.
  - Nothing is anchored to a power text or to the fill texture. The line and its back are anchored
    to `bar`'s LEFT, whose rect is plain.
  - `Pool.lastPowerEvent` records only the event's arrival time. No `==`, `#` or table key touches
    a client return in the new files.
- **Efficiency.**
  - `Paint` writes only changed strings and changes the time's colour only on a tone change.
  - `PaintPower()` from the frequent event calls `SetValue` only.
  - The idle driver does one pcall and one compare per frame. While the rule runs it makes 4
    region calls a frame, as the spec allows.
  - The only layout outside `Apply` is `Snap`, which re-runs `Apply` only when the pixel size
    changes.
  - Visibility stays with each host's `UpdateVisibility`. ClockBar never shows or hides the host
    frame.
- **Lua / TBC.**
  - No `a and f() or b` on a multi-return.
  - `#` is used only on dense lists. Forever's point table has a hole at index 2, but it is read
    by index only, never with `#`.
  - Every styled frame (preview, swatches, both hosts) uses `"BackdropTemplate"`.
  - TBC's `DrawPowerText` (`Client/API_TBC.lua:175-197`) uses the same kinds and formats as
    Forever's.
  - The TBC host keeps its legacy 3-element `db.pos` path in `NewLook`.
- **TOCs.** `ClockWords` comes after `ClockFace`. `ClockStore` and `ClockBar` come before each
  host and `ClockSettings` in all three main TOCs. `ClockView` is gone.

## Findings

### S1 (should-fix) -- TBC: the Rest text is still gated by `db.showRest` / `db.showCooldown`, and the pane no longer offers those switches

**Fixed in <sha>.** `Engine/TTO.lua` gives the face `clockSecond`, the same segment rule without `db.showRest` / `db.showCooldown`; `ClockWords.Build` draws the Rest text from it (Forever's face has none and keeps `second`). `second` stays gated for the feeds. Test: `tools/clockfacecheck.lua` 3i (real `GetClockFace`, both switches off). Not as an E1 base: E1's TBC moment is a hand-made face, which would not reach `GetClockFace`.
`Engine/TTO.lua:404-406` builds `face.second` only when `db.showCooldown ~= false` (for the
`inn` kind) or `db.showRest ~= false` (for the `rest` kind). `ClockWords.Build` takes the Rest
text's words only from `face.second` (`Engine/ClockWords.lua:266-271`). T145d removed the `show`
group (the Rest time and Mana cooldown switches) from TBC's `CLOCK_SWITCHES`
(`UI/Dashboard.lua:234-237`). Spec 1.3 says "the clock no longer reads them", but on TBC it still
does, through the face.

**Failure scenario:**
1. A TBC player once typed `/st rest` (`Core_TBC.lua:319`, `db.showRest = false`) to clean up a
   datatext.
2. In Settings -> Clock they tick the Rest text on and change its place, size and colour.
3. Nothing is ever drawn. There is no note, and no control on the pane to undo it.

This is bug 1's exact shape, a P1 violation in a reachable state. The same happens to the `inn`
cooldown words with `showCooldown = false`.

E1 cannot see it: it holds a hand-made TBC face that always carries `second`
(`tools/clocke2e.lua:120-124`).

**Fix:** pick one.
- (a) Give TBC's face the raw secondary (for example `face.secondRaw`, without the feed gates),
  and have the clock's Rest text read it, leaving `face.second` gated for the feeds.
- (b) Have `TbcFace` / `ST:GetClockFace` take a `forClock` flag.

Then add an E1 base with `db.showRest = false` on TBC.

### S2 (should-fix) -- E1 counts an empty text as "visibly changed" (Forever's Rest text)

**Fixed in <sha>.** `tools/clocke2e.lua`'s `Differs` counts a `text.<kind>` change only when that text is shown with non-empty words in the snapshots that show it. Forever's held moment is at 60 % mana, so the rest (about 45 s) is drawn beside the 80 s time. It failed with 16 inert Rest operations before the moment moved.
`tools/clocke2e.lua:259-272` (`Differs`) compares `Drawn()`'s font, point and colour cache. It never
checks that the text has anything to draw.

At E1's moment on Forever (`Hold(80)`: the fight fields, mana at 40 %), the live clock's Rest text
is shown with the words `""`. RestSegment hides it when rest is within 25 % of the primary.
A scratch run with every text on printed `rest true ""`.

So the seven Rest-row controls under base 3 (place, align, x, y, size, colour, outline) pass E1's
"visibly changes the live clock" with nothing on screen. The test reports what it cannot know,
which is the gap bug 1 slipped through. The same applies to any text whose words are nil at the
moment held (the 5SR text outside the rule).

**Fix:** in E1, for an `affects` path under `text.<kind>`, also require that `s1.text[kind].words`
is a non-empty string, and hold a moment where it is. On Forever, a rest more than 25 % away from
the time to OOM, for example a shorter `tto` with a slow regen. Otherwise, list such a control as
inert so that the empty-list pass condition means what it says.

### S3 (should-fix) -- CHANGELOG `## Next` contradicts itself about the clock

**Fixed in <sha>.** `CHANGELOG.md`'s `## Next` has one clock section (clock v3): the moving line and the texture list folded in; Join, Bars, Thin, Gradient, the six colour pickers, the old presets and the 6-px pill default dropped.
`CHANGELOG.md:25-39`: "Both: a moving line" (Settings -> Clock -> Bars -> Join -> Moving line;
"Stacked, One bar and Swipe chip stay") and "Both: the clock's bar look":
- Thin and Gradient;
- six colour pickers;
- presets Default / Like EllesmereUI / Soft pill / Thin line;
- "The new default: a 6-px blue pill ... Your own settings are kept".

These describe controls that no longer exist. The new section at line 41 says the opposite (one
page, two presets, the look moved once, the line turned on) and only adds "This replaces the tabs
and the Bar look above".

**Failure scenario:** `release.sh --publish` sends this section as the CurseForge changelog, so a
beta user reads about controls that are gone and a default that is not the default.

**Fix:** fold the two old sections into the clock v3 section: keep the moving line and the
EllesmereUI texture list, drop Join, Bars, Thin, Gradient, the colour pickers and the old presets.

### N1 (nit) -- the tick still hands the bar its range twice a second (review W1, half-closed)

**Fixed in <sha>.** `UI/Clock_Forever.lua`'s tick passes `withMax` only when the model's plain max moved, else every `Clock.RANGE_EVERY` (10 s); Apply and `UNIT_MAXPOWER` still set it. Test: E7 (range calls over 9 s steady at most 1, one after the max moves). TESTING 66 step 6.
`UI/Clock_Forever.lua:341` calls `renderer:PaintPower(true)` on every 0.5 s tick, so
`DrawUnitPowerMax` calls `SetMinMaxValues` every tick. W1's concern is that the 12.x client snaps
or restarts the eased `SetValue` on each `SetMinMaxValues`. The frequent event is now value only,
but the tick still triggers this twice a second, so a stutter at 2 Hz would remain.

This follows the spec (2.5). Still:
- `UnitPowerMax` reads plain on this client (the pool's tick uses it as a number), so the adapter
  could skip an unchanged max;
- or the range could be set only on `Apply` and `UNIT_MAXPOWER`.

At minimum, add "the bar fills smoothly, no twice-a-second hitch" to TESTING §66.

### N2 (nit) -- Font is always visible, and inert when every text is off

**Fixed in <sha>.** Font is `visible` only while a text is on. E1 has a fourth base, every text off (it failed with `font = st` inert before the fix).
`UI/ClockSettings.lua:568`: `font` has no `visible`, so it defaults to Always. Unticking all
seven texts is reachable (P2 binds only presets), and then Font changes nothing drawn (`Drawn()`'s
`text.*.face` stays nil). It is a small P1 hole.

**Fix:** `visible = any text on`. E1's bases never have every text off, so add that state if
the rule stays total.

### N3 (nit) -- a v3 store repaired at login is not named in the dump; a future `v > 3` loses the look

**Fixed in <sha>.** the dump line says `repaired v3, N notes: ...` for a v3 store Normalize changed at login (and registers itself for it); `Migrate` reads a store with `v` above 3 as from `v<n>`, normalized, every valid field kept. Tests: two checks in `tools/clockstorecheck.lua` section 6.
- **The repair is not named.** `MigrateStored` writes the normalized v3 store, but `DumpLine`
  prints the notes only when `migratedFrom ~= "v3"` (`UI/ClockStore.lua:838`). `NoteDump` also
  ignores a v3 migration with notes (line 664). So a hand-edited or older-build field that
  `Normalize` put back is fixed silently, while spec 2.6 says "the dump names it".
- **A future version loses the look.** `Migrate` treats any `v >= 2` that is not 3 as v2
  (line 585). A store from a later build (v 4) loses every field (each one "not a clock look
  setting"), so a downgrade resets the look.

**Fix:** name the v3 notes in the dump. Treat `v > VERSION` as "normalize, keep what validates".

### N4 (nit) -- the Live preview chip draws the model's mana numbers

**Fixed in <sha>.** the preview's draw table forwards `powerText` to the live host's on the Live chip (false otherwise: the sample's words). Test: clocke2e `E1 (preview, Live)`.
`UI/ClockSettings.lua:405-433`: `SampleDraw` has `pool`, `poolMax` and `fsrEnd` but no
`powerText`. In Live, the preview's bar is the real pool, but its Mana / Mana % texts are the
model's words, unmarked. The clock on screen shows the game's numbers. So on Forever the two can
disagree side by side, in the one place meant to be "the real check".

**Fix:** forward `powerText` from `LiveDraw()` when the chip is Live.

### N5 (nit) -- the quiet-pool rule anchors whatever stops the events, including (VERIFY) a dead player

**Fixed in <sha>.** `Pool:QuietFull` answers false while `ST.API.UnitIsDeadOrGhost("player") == true` (the adapter's plain boolean), and `PLAYER_DEAD` / `PLAYER_ALIVE` / `PLAYER_UNGHOST` clear `lastPowerEvent`, so the rule waits for a fresh event. The stub's Forever event list gained the three events (retail events, assumed present; `ST:On`'s pcall covers a refusal). Test: E7 dead / alive / fresh event. TESTING 66 step 7 (VERIFY).
`Engine/ManaPool_Forever.lua:203-208` anchors the model at max after 3 s with no
`UNIT_POWER_FREQUENT`, outside the rule, while `base * 3 >= 2`. While dead or a ghost the pool
does not move, out of combat.
- If `GetManaRegen` still answers the old base there, the model is set to full.
- After a wipe and a res at 35 %, the model says full and the clock stays down (over 95 %).
- The next pull starts its TTO from max.

Before T145a, only the assume-full rule did this, after `max / base` seconds.

**Fix:** reset `Pool.lastPowerEvent` on `PLAYER_DEAD` and require a fresh event after
`PLAYER_ALIVE` / `PLAYER_UNGHOST`, or check `UnitIsDeadOrGhost` through the adapter. Add a line to
TESTING §66.

### N6 (nit) -- docs: the CLAUDE.md row for `Engine/ManaPool_Forever.lua` omits the quiet pool

**Partly fixed in <sha>.** TESTING 66 step 8 (Rectangle vs Rounded under the game frame). The CLAUDE.md row is not edited: the implementer rules leave CLAUDE.md to the lead; the proposed row text is in the implementer's report.
`CLAUDE.md:73` still describes the file as T68's owner. It does not say that it registers
`UNIT_POWER_FREQUENT`, keeps `lastPowerEvent`, makes the quiet-full anchor (`Pool.QUIET_FULL`
ships on) or adds the `pool:` dump line. Those facts appear only in the ClockWords row.

Also unverifiable offline, for TESTING §66 step 4: with Frame = Game frame, both the game atlas
mask and the shape mask clip the fill. Whether Rectangle and Rounded look different in game is
unknown, while `Drawn()` only compares the mask file name.
