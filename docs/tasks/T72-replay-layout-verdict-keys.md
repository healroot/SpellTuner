# T72 -- The replay: stable layout, a readable verdict, the keys it promises (plan P28)

Status: **built** 2026-09-30 on branch `plan/P28` (base `cf9c6ae`), wave 11 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No file was added, so no TOC line is needed.

## The task (docs/PLAN-refactor-ux.md section 5, P28)

Review items (`docs/review/2026-09-30-project-review.md`): **U21** (the replay grows a second column
under the healer's eyes: 492 px at open, 968 and re-centred when the auto-coach ends), **U23** (the
verdict is the faintest text on the window: a 0.5-grey 11-px footer; the header packs six facts in one
11-px line; the v3 caveat is another grey line), **U27** (the play button's tooltip promises Space, and
the keyboard is never enabled for a replay). Approved mockup: M3 in `docs/mockups/refactor-ux.html`
(section 7.1). The author's answer 8.1 item 12: replay keys **only while the pointer is over the
replay, never in combat**.

- Under `UI.THEMED`: both columns laid out when the auto-coach starts, the right one dimmed and titled
  `SUGGESTED  coaching... N plans`, the size never changing for that fight; a status band under the
  header -- the fight left, the verdict right in `good` / `bad`, **Coach anyway** where the slash command
  was quoted; the reconstruction caveat one word in the band and a marker in the bar's tooltip.
- On both lines: Space toggles, Left / Right seek 5 s, every other key propagates; the keyboard is
  enabled only on the pointer entering out of combat, disabled on `PLAYER_REGEN_DISABLED`, on leaving
  and on hide. Practice keeps its own rules.
- Tests: `replayforever` +4, `replayui` +4 (TBC), `practiceforever` unchanged.

Owned files (section 4, wave 11): `UI/ReplayWindow.lua`, `tools/replayforever.lua`,
`tools/replayui.lua`. All three were edited and committed, plus this task file.

## What was built (UI/ReplayWindow.lua)

### The keyboard (both lines)

- `ReplayKey` is the window's `OnKeyDown` from `Build`: `SPACE` plays / pauses (`SetPlaying`, the play
  button's own path), `LEFT` / `RIGHT` move the clock 5 s (`Nudge`: the fight's clock clamped to
  `0..dur`, or the run's clock through `RunSeek` in run mode; playing or paused is kept); both call
  `SetPropagateKeyboardInput(false)`. Every other key -- ESCAPE included, so the ESC stack still closes
  the window -- is propagated. With the keyboard not held (or during practice) every key propagates.
- **The two guards.** `keysOn` (what `EnableKeyboard` was last given) and `pointerIn` (the last answer
  to "is the pointer over the window"). `PointerCheck` runs on the window's `OnEnter` / `OnLeave` (hooked)
  and at the top of every `OnUpdate`: on an *entering* edge (over now, not before) it enables the
  keyboard unless `InCombatLockdown()` or `UnitAffectingCombat("player")` (through `MD.API`); when the
  pointer is not over the window it disables it. It asks `frame:IsMouseOver()` rather than trusting
  `OnLeave`, because the window's `OnLeave` fires whenever the pointer moves onto a unit frame, a button
  or the scrubber, all of which are inside it.
- `PLAYER_REGEN_DISABLED` (the existing `MD:On` handler) disables it and leaves `pointerIn` alone, so a
  pointer that stays over the window through the fight does not get the keys back afterwards: it must
  leave and enter again. The window's `OnHide` disables it and clears `pointerIn`.
- Practice: `LiveControls(true)` enables the keyboard and installs its own handler as before (and
  `PointerCheck` stands aside while `live`); `LiveControls(false)` disables it and puts `ReplayKey`
  back (it was `nil`), clearing `pointerIn` so the replay a practice reopens as takes the keys on the
  next entering edge.
- The play button's tooltip: "Space plays and pauses, Left / Right move 5 s, while / the pointer is over
  this window and you are out of combat." (was "Space also toggles while the window has focus.").

### The status band (under `UI.THEMED`)

- A 28-px band across the top (`UI.PALETTE.pane`, black 1-px edge). `headerFS` moves into it at
  `UI.FONT`: `#n` in the accent, the run and pull if any, the zone, the day (`today HH:MM` or the date)
  and the length in `text2`, and `N targets`. The run strip, on the TBC line only, sits under the band.
- The verdict at the right: `replays` in `good`, `does not replay: <first failing gate>` in `bad`; its
  hover lists every gate with ok / FAIL and the mana gate's fit line (the text the old header carried).
- **Coach anyway** (accent button, 104 x 20) left of the verdict when the fight does not replay, has
  no plan and is not being coached. Its click opens the fight again with `force`, as
  `/md replay N force` did; the open's auto-coach then runs even with `db.replayAutoCoach` off (an
  explicit request, `askedToCoach`), and the misleading "nothing to force - no plan has been coached"
  line is not printed when that open started the search. With another fight's search running it says so
  in one line instead.
- `reconstructed` (the `muted` word with a 1-px underline) beside the fight on a v3 recording; its hover
  is the explanation and, when a party max is estimated, a line saying so. `frame.reconFS` is that word.
- The footer hint is empty when the band carries the verdict; "no plan yet" stays for a fight that
  replays and has none (auto-coach off, or another search running). The key hint sits at the footer's
  right end: `Space play   Left  Right 5 s` with the caps in the accent while the keys are live and grey
  otherwise, plus "keys work while the pointer is over this window" on a two-column window.
- The strategy chooser moves from the header line (where the verdict now is) to the right end of the
  column titles' line.

### The stable layout (under `UI.THEMED`)

`Layout` treats a fight the auto-coach is searching (`MD.replayCoaching == rec.id`, no plan yet, not
practice) as two columns: the window opens at 968. The right column's frames and strip are built,
painted blank (full bars, no icons, the pool on the mana bar, `no plan yet`, a score of dashes) and
dimmed to 0.32 (`Dim`, recorded as `right.dimmed`); its title is `SUGGESTED  coaching... N plans`,
updated every frame from the search handle's `evals` (`CoachProgress`). When the plan arrives,
`RebuildSuggested` reopens the fight at the same width with the dimming lifted and the title the usual
`SUGGESTED (plan, N binds)`.

### The bar's tooltip (under `UI.THEMED`)

On a reconstructed recording the tick's tooltip is mockup M3's: the target's name with `reconstructed`
as a marker, "Health then", "Engine's replay now", "Difference" (within / outside 5% in good / bad) and
one sentence. Hovering a left button outside practice shows the same tooltip (the bar's tooltip), not
only the 8-px tick. The TBC tick tooltip and the Forever-without-theme one are unchanged (moved into one
`TickTip` function).

## Tests first

The assertions were written before any source change and run against the parent's
`UI/ReplayWindow.lua` (`cf9c6ae`):

```
tools/replayui.lua (tbc)                                              exit 1
T72: Space toggles with the pointer over FAIL - kb=false played=false prop=nil
T72: no keyboard with the pointer elsewhere FAIL - nil
T72: combat lets go of the keyboard until re-entry FAIL - before=false combat=true entered=true after=true reentered=false
T72: TBC keeps its header, no band, no key hint ok - |cffffcc00#1|r  Blood Furnace  15:33  0:26.5   |cff99dd99replays|r
104 ok, 3 failed

tools/replayforever.lua (forever)                                     exit 1
15 ok, 10 failed
  FAIL T72: the auto-coach lays out both columns at open, the right one dimmed and titled - coaching=3100000000 width=492 ...
  FAIL T72: the band's verdict reads replays, in good -
  FAIL T72: the plan fills the right column in place: same width, the dimming lifted - done=true width=968 ...
  FAIL T72: a fight that does not replay says so in bad, naming the gate, with Coach anyway -  / hint=does not replay (foreign healing) - |cffffff00/md replay 1 force|r ...
  FAIL T72: Coach anyway coaches it with both columns laid out at once - coaching=nil width=492 lines=
  FAIL T72: ...and the forced plan is drawn at the same width, the verdict still bad -
  FAIL T72: with the pointer over the replay Space plays and pauses, and stays with the window - kb=nil ...
  FAIL T72: Left / Right seek 5 s; an unbound key goes on to the game - t 10.00 -> 10.00 -> 10.00, W propagates=nil
  FAIL T72: the keyboard is let go when the pointer leaves the window - nil
  FAIL T72: the left bar's hover names the target and marks the health reconstructed -
```

(The TBC "keeps its header" line passes on the parent: it is the guard that the theme's band and layout
stay off TBC.) After: `replayui` 107 ok, `replayforever` 25 ok.

The stub (`tools/wowstub.lua`, not this wave's file for P28) answers `IsMouseOver` from `S.mouseFocus`
but treats `EnableKeyboard` / `SetPropagateKeyboardInput` as no-ops and `GetAlpha` as 1, so the suites
record the keyboard calls by overriding the two methods on the replay frame for their block, and the
dimming is read from `right.dimmed`.

**Mutations on the finished branch** (the file copied aside, one `sed`, copied back):

| mutation | result |
|---|---|
| `PLAYER_REGEN_DISABLED` no longer releases the keyboard | replayui 106 / 1 (`combat=false entered=false after=false`) |
| the entering edge enables the keyboard in combat too | replayui 106 / 1 (`entered=false after=false`) |
| `Layout` no longer lays out the right column while coaching | replayforever 21 / 3 (width 492 at open, twice; run before the bar-tooltip assertion was added) |

## Suites

| suite | before | after |
|---|---|---|
| `replayui/tbc` | 103 | 107 (+4) |
| `replayforever/forever` | 15 | 25 (+10) |
| every other suite | as `tools/data/expected-counts.json` | equal |

`tools/check.sh`: 68 runs, all passed (the two notes are the counts above); `apicheck` 0 findings,
`textcheck` 0 findings. `luac -p` on the three files.

TBC byte-identity: `practiceui`, `reviewui`, `practice` and `practiceforever` print the same lines
before and after, apart from the `[sim] ... N ms` timings and table addresses; `replayui` the same
apart from those, the time-sliced search's evaluation counts, and the four new lines.

`replayforever` section 5 still asserts that the window says the health is reconstructed and a party
max estimated; under the theme it reads the band's word and that word's hover (`_state().reconTip`),
where the estimate now lives.

## Integrator lines

- **TOCs**: none (no new file).
- **`tools/data/expected-counts.json`**: `"replayforever/forever": 25,` (was 15) and
  `"replayui/tbc": 107,` (was 103).
- **`docs/DECISIONS.md`** (the TBC behaviour change, section 2 of the plan):

  > ### Replay keys under the pointer (T72, P28, 2026-09-30)
  > The replay window takes the keyboard on both lines: Space plays and pauses, Left / Right move 5 s,
  > and every other key goes on to the game (`SetPropagateKeyboardInput`, practice's pattern). Space
  > and the arrows are jump and turn, and TBC does not hide the replay in combat, so the window holds
  > the keyboard only after the pointer *enters* it out of combat, and lets go when the pointer leaves,
  > when the window hides and on `PLAYER_REGEN_DISABLED`; after a fight it comes back only when the
  > pointer enters again. A failed `SetPropagateKeyboardInput` (only `pcall`'d) can therefore swallow
  > keys at most while the player points at the window out of combat. Practice keeps its own keyboard
  > rules. The author's answer, `docs/PLAN-refactor-ux.md` 8.1 item 12; the play button's tooltip had
  > promised Space since v0.8 without it working (review U27).

- **`CLAUDE.md`**, the `UI/ReplayWindow.lua` row, appended:

  > **T72 (P28):** Space / Left / Right (5 s) on both lines, only while the pointer is over the
  > window and never in combat (released on `PLAYER_REGEN_DISABLED`, back only when the pointer enters
  > again; every other key propagates). Under `UI.THEMED`: a status band (the fight, the verdict in
  > good / bad, **Coach anyway**, `reconstructed` as one word with its hover), both columns laid out
  > while the auto-coach searches (the right one dimmed, `coaching... N plans`), the bar's tooltip
  > marking reconstructed health, a key hint in the footer.

- **`docs/TOOLS.md`** section 1: `replayforever` 25 (was 15), `replayui` 107 (was 103).
- **`docs/TESTING.md`** (section 44, the plan's check 23):

  > **Replay (P28).** On Forever, open a fight that has not been coached: the window opens at full
  > width with the right column dimmed (`coaching... N plans`) and fills in place without moving. The
  > band reads `replays` in green, or `does not replay: <gate>` in red with a **Coach anyway** button;
  > click it and the right column is laid out at once and fills in. Hover `reconstructed` and a left bar.
  > With the pointer over the window Space pauses and plays, Left / Right move 5 s; with the pointer
  > away Space jumps. **On TBC too:** open a replay, keep the pointer over it and pull a mob: you can
  > still jump and turn; after the fight Space plays the replay again only once the pointer has left the
  > window and come back.

## Deviations

1. **More assertions than asked.** `replayforever` +10 where the plan says +4 (the four it names, plus
   the plan arriving at the same width, Coach anyway in two steps, Left / Right, the leave, and the
   bar's tooltip); `replayui` +4 as asked.
2. **The key hint is on the footer row, not the controls row.** Mockup M3 draws it at the right end
   of the controls row, which a one-column window (492 px) fills already; on the footer's right end it
   fits both widths, the sentence "keys work while the pointer is over this window" shown only on a
   two-column window. The ticks checkbox stays where it was.
3. **No progress bar beside the dimmed title.** M3 draws one; the search's maximum is private to
   `Engine/SimPlanner.lua` (P27's file in this wave), so the title carries the plan count only.
4. **The strategy chooser moved** (under the theme) from the header line, where the verdict now is, to
   the right end of the column titles' line -- where M3 draws the progress bar.
5. **Coach anyway runs with `db.replayAutoCoach` off**, and under the theme a forced open that started
   the coach no longer prints "nothing to force - no plan has been coached ... /md coach N force
   first". TBC still prints it (the line is also misleading there when the auto-coach starts; a
   candidate for wave C, not changed here because TBC must not move outside a wave-C task).
6. **The size is stable while a plan is coming.** If the search ends with no plan (cancelled, e.g. by
   `/st coach N` taking over, which cancels the auto-coach), the fight reopens in one column.
7. **The keys' pointer test is polled** (`IsMouseOver` every frame plus `OnEnter` / `OnLeave`), since
   the window's `OnLeave` fires whenever the pointer moves onto one of its own children.
8. Under the theme the tick tooltip drops its "a party max perhaps estimated" line; the band word's
   hover says it (only when a max was estimated).
9. After a practice ends, the window's `OnKeyDown` is the replay's handler instead of `nil`.
