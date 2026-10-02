# F2 -- no "instant" GCD sweep after a hard cast

## Symptom (the author, 0.16.6, Practice on Forever)

> there is a bug in simulator, after direct cast it start animating gcd of the cast

The screenshot shows the YOU strip reading `Healing Touch R2 -> Tank  instant`
with a grey bar sweeping, just after the Healing Touch's own cast bar filled.

## Cause

`UI/ReplayWindow.lua`, `MakeOnEvent`, the `TK.CAST` branch (line 623 on
2ffece3): every successful cast set `col.strip.gcdStart, col.strip.gcdUntil =
t, t + GCD`. `PaintStrip` (line 939 on 2ffece3) paints a grey sweep and the
word `instant` whenever `st.t` is inside that window and no cast is in
progress. So a hard cast's success was followed by 1.5 s of an "instant"
sweep -- a GCD that had in fact started with the cast bar and was over by the
cast's success. The line before it (`local c = col.state and
col.state:Casting()`) was meant to tell the two apart, but it was never read,
and by the time `onEvent` runs `ReplayTrace`'s `Apply` has already cleared
`casting`.

The painter is shared, so the same happened in a replay (both columns) and in
practice, on both lines.

## Fix

`UI/ReplayWindow.lua` only:

- `onEvent` remembers a `TK.CAST_START` on the strip (`barSpell`, `barAt`) and
  forgets it on `TK.CANCEL`.
- A `TK.CAST` of the same spell after its cast start is a hard cast: no sweep
  (`gcdStart, gcdUntil = 0, 0`); its name stays, dimmed, with an empty bar
  (the idle look). Any other cast is an instant and sweeps the GCD from the
  cast moment, as before.
- `SeekTo` crosses a cast start silently, so after a seek the strip takes
  `barSpell` from the state's `Casting()`; opening practice clears it.

Not done (kept minimal, as asked): a hard cast shorter than the GCD (a low
Healing Touch with Naturalist) does not show the GCD's remainder after it
lands -- its name stays dimmed at once.

## Tests

- `tools/replayui.lua` (tbc): over the scripted pull, no strip in either
  column ever reads `Regrowth ... instant`; Rejuvenation (an instant) still
  sweeps; after Regrowth lands its name stays with the bar at 0. (The
  existing "cast bar progresses during the Regrowth" check had been passing
  on the bug's sweep -- `0.93 at Regrowth R9 -> Destroyka  instant`; it now
  passes on the real bar, `0.90 at Regrowth R9 -> Destroyka  2.0s`.)
- `tools/practiceui.lua` (tbc): the YOU strip read every frame of the played
  fight -- the Lifebloom press sweeps, the Regrowth press fills its own bar
  (`... 2.0s`), no `Regrowth ... instant` ever, and the landed Regrowth's
  name stays with an empty bar.

| suite | 2ffece3 (tests added, old painter) | F2 |
|---|---|---|
| replayui/tbc | 108 ok, 2 failed | 110 ok |
| practiceui/tbc | 54 ok, 2 failed | 56 ok |

`make check` green (92 runs), apicheck 0 findings, textcheck 0 findings.

## Integrator lines

- `tools/data/expected-counts.json`: `"practiceui/tbc": 56` (was 52),
  `"replayui/tbc": 110` (was 107).
- `CLAUDE.md`, the `UI/ReplayWindow.lua` row: append
  `**F2:** only an instant sweeps the GCD in grey; a hard cast (a CAST_START of the same spell before its success) leaves its name dimmed with an empty bar -- its GCD ran under its own bar`.
- `docs/TESTING.md`: Practice / replay -- a hard cast (Regrowth, Healing
  Touch) lands and the YOU strip shows its name dimmed with no `instant`
  sweep; an instant (Rejuvenation) still sweeps 1.5 s.
