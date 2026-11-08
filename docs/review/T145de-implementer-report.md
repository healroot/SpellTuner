# T145d + T145e -- implementer report

Units U4 and U5 of `docs/SPEC-clock-v3.md`. Tasks: `docs/tasks/T145d-clock-pane.md`,
`docs/tasks/T145e-clock-docs-gate.md`. Branch `worktree-forever-talents`.

Commits: **43c247d** (T145d), **2ecbe9e** (T145e). Not installed, pushed or published.

## T145d, file by file

- `UI/ClockSettings.lua` (rewritten, 1281 lines). It is one pane, following section 3 and the mockup.
  - **Preview.** PREVIEW is fixed on top. It is a `ClockBar` of its own, never the clock on screen. Its
    chips are In a fight, Running out, Filling, Full and Live. The 5SR rule loops in the In a fight and
    Running out samples.
  - **Scroll area.** BAR, TEXTS, PRESETS and WHEN sit in a scroll frame under the preview.
  - **The registry.** `CS.CONTROLS` has 68 entries. Each has `id`, `kind`, `values`, `get`, `visible`,
    `affects` and `write`, and every write goes through `ST.ClockStore`.
  - **Refresh.** `CS.Refresh` shows each widget only when `visible(look)` holds.
  - **Texts.** An off text shows only its switch, its name and a sample. Time as and Warn colours show
    only while the time is on. Custom's swatch shows only while the fill is a colour.
  - **Presets.** "Undo preset" shows only while an undo is held.
  - **Missing hosts.** A choice the client cannot draw (EllesmereUI's texture or font, a
    LibSharedMedia texture) keeps its value. Its reason appears beside the control, and the control
    stays clickable.
  - **Unchanged.** The Look controls, INTEGRATIONS and the subcommands (`layout`, `look reset`,
    `preview`) work as before.
  - **Removed.** The `ST.ClockLook` provider is gone.
- `UI/ClockStore.lua`: added `Store.SetMany(map)`, which validates every field and then does one
  write and one `CLOCK_LOOK`. The fill / custom-colour and back + alpha controls need it to stay at
  one write. **This file is outside T145d's listed files.**
- `UI/Dashboard.lua`, `UI/Dashboard_Forever.lua`: the `show` group (the Rest switch) is removed from
  `CLOCK_SWITCHES`. Rest is now a text of its own; on Forever, `/st clock rest` toggles `texts.rest.on`.
- `Engine/ClockFace.lua`:
  - Line's slots are removed: `KINDS`, `TEXT_*`, `ResolveText`, `DefaultSlots`, `Slots`, the piece
    helpers, `TimeFmt` and the labels option.
  - `LineString(face, valueHex)` now always gives the default words.
- `UI/Feeds.lua`, `Integrations/Surface_LDB.lua`: the feeds use the default `LineString`, and compact
  drops the second segment.
- `tools/clocke2e.lua` (new):
  - **E1:** from three base looks, every control is operated through its own widget, and each one
    changes the live clock's `Drawn()` and the preview's (269 operations each, empty inert list, no
    exception list).
  - **E2, E3, E4:** inert controls are hidden; each write fires one `CLOCK_LOOK`; each preset keeps
    the time and the line, and Undo restores exactly.
  - **E5:** a fight on the defaults and on the author's store (`tools/lib/clockdrive.lua`).
  - **E5b, E5c:** the refill out of combat, and E5c also in a fight (Forever).
  - **E6, E6b:** Bar controls changed mid-rule keep the line moving.
  - **E7:** the quiet pool (Forever).
- `tools/clocksettings.lua`: re-based; **no SKIP_U4 is left** (see below).
- `tools/clocktextcheck.lua`: cut to sections 1, 6, 7, 12 and 13, over `ClockWords.Build` and
  `LineString`.
- `tools/surfacecheck.lua` 9a/9b and `tools/euicheck.lua` 19-20: re-based on the default words.
- `tools/data/expected-counts.json` has the new counts: clocke2e 18 / 13, clocksettings 36 / 35,
  clocktextcheck 5 / 5.

### The 36 skipped clocksettings checks (41 names, paired across the two flavours)

**Ported into clocksettings** (each rewritten for v3):
- **Chips:** "(Live) paints the line's own face", "each chip paints its face", and "the chips are the
  eight..." (now five chips).
- **Pane:** "selecting it builds the pane" (now PREVIEW + BAR, TEXTS, PRESETS, WHEN, no tabs).
- **When:** "When: Locked is the line's own lock".
- **Rest:** both "Show: no Show tab; the line's rest switch..." checks. On Forever this is now
  `/st clock rest` toggling the Rest text; on TBC, `/st rest` still drives the feeds' `db.showRest`.
- **Textures:** "T139 colour picker", "T139 LibSharedMedia", "T140/T142 with EllesmereUI" (plus a
  new check without EllesmereUI) and "T144 the Texture list fits".
- **Style:** "picking a style..." and "back to Flat..." (without the old clock-pane style label).
- **Layout:** "every word ... ASCII" and "every titled pane of Settings -> Clock lies inside the view"
  (now: the preview and the scrolling area inside the view).

**Replaced by clocke2e E1-E4** (every control writes and the live clock draws it):
- the T139/T142 Bar look list and "each control writes bars.<layout>.*";
- the T142 texts table;
- the T142 presets;
- Colours: "a tone's swatch" and "Mana colour";
- Frame: "width and height" and "the background alpha".

**Removed** (the control is gone with Line and Compact or the tabs, D1):
- every "Bars:" check (per-layout bars, Order, Mana from, the tick);
- Frame: Scale;
- Reset to style (no style overrides on the clock any more);
- every "Text:" check (slots, Right / Right 2, FORMAT, Labels / ofMax, the footnotes);
- "a layout button saves ...";
- "the rule chips paint the preview's five-second rule" (the rule loops inside the fight samples now,
  and clocke2e E6 covers the line).

## U3's open point 3 (E5): finding

**This is the model's meaning, not a harness artefact and not the author's bug.**
- **Why the refill state is never reached in a fight.** With the model's fight-average spend and
  constant regen, after a burst the net is below zero exactly while the modelled pool is above max.
  So in a fight the clock reads OOM (growing to `>10m`) and then `FULL`; it never shows a refill time.
- **Out of combat, regenerating,** the clock reads `FULL m:ss` (forever `FULL 0:50`, ...; tbc
  `FULL 53s`, ...). At full the frame hides, and its words are `FULL`. Test: E5b, on both lines; only
  ticks where the clock is shown are judged.
- **A fight entered below max with light casting** reads `FULL m:ss` in combat (E5c, Forever).
- **No change was needed** in `ManaModel` or `ClockWords`. The finding is recorded in
  `docs/DECISIONS.md`.

## T145e, file by file

- `CLAUDE.md`:
  - rows added for `Engine/ClockWords.lua`, `UI/ClockStore.lua` and `UI/ClockBar.lua`;
  - the `UI/ClockView.lua` row removed;
  - the `Engine/ClockFace.lua`, `UI/Clock_Forever.lua`, `UI/Widget.lua` and `UI/ClockSettings.lua`
    rows rewritten;
  - the visibility convention now names ClockBar.

  The brief asked for this, and the T145e task records it as the exception.
- `docs/TOOLS.md`:
  - rows added for clockwordscheck, clockstorecheck, clockbarcheck and clocke2e;
  - clockui, clocktextcheck and clocksettings rewritten with their counts;
  - clockfacecheck, surfacecheck and euicheck notes added.
- `docs/DECISIONS.md`, in the Clock v3 section:
  - the pane's rulings (no Reset button, because the SpellTuner preset is the defaults and
    `/st clock look reset` stays; the mockup's "Your look, migrated" and "What v3 removes" are not in
    the game);
  - the refill finding;
  - Line and Compact's open items closed, and Q-clock-2 restated.
- `docs/TESTING.md`: new §66, the spec's five steps, including the 3 s quiet-full VERIFY.
- `CHANGELOG.md`: a "Both: the clock, one bar (clock v3)" section under `## Next`.
- `docs/HISTORY.md`: a dated entry for T145a-e.
- The import fixture is already v3; T145d stores nothing new, so it was not rebuilt.

## Gate

luac -p ok on every touched Lua file. `make check` (run once, in the background, on the T145d code;
the T145e commit touches docs only):

```
  ok    clockbarcheck/tbc 22, /forever 22
  ok    clocke2e/tbc 13, /forever 18
  ok    clockfacecheck/tbc 20, /forever 17
  ok    clocksettings/tbc 35, /forever 36
  ok    clockstorecheck/tbc 42, /forever 43
  ok    clocktextcheck/tbc 5, /forever 5
  ok    clockui/tbc 5, /forever 5
  ok    clockwordscheck/tbc 51, /forever 62
  ok    euicheck/forever 21   surfacecheck/tbc 36, /forever 43
  ok    apicheck: 8 Forever TOCs, 86 files, 50 distinct globals, 0 findings
  ok    textcheck: 9 TOCs, 126 files, 0 findings
  counted 110 run(s) against 110 expected
check: 115 run(s), all passed
EXIT 0
```

## Notes and things not fixed

- **E1's moment seam:** `Hold(tto)` fixes the face (Forever: the model's fight fields; TBC: a fixed
  `GetClockFace`), so a Warn-colours change is visible. E1 runs with the hosts present (EllesmereUI,
  atlases). The fallbacks are covered by clockbarcheck and clocksettings.
- **Preview position:** the preview stays fixed at the top while the rest scrolls. The mockup shows
  the same.
- **TBC latch lag:** TBC shows `FULL` for one tick after the pool drops to 50 % (the TTO latch);
  acceptable, not changed.
- **Stale changelog lines (not changed):** `CHANGELOG.md` `## Next` still has the T137/T139/T140
  lines describing the old Bars / Join / Bar look tabs. The new section says it replaces them; the
  lead may want to fold them together before release.
