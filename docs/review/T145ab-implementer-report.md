# T145a / T145b implementer report (units U1 and U2 of docs/SPEC-clock-v3.md)

Branch `worktree-forever-talents`. Task files: `docs/tasks/T145a-clock-words.md`,
`docs/tasks/T145b-clock-store.md` (written from the spec's section 5). The author's approval of the spec,
the mockup and D1-D3 (2026-11-08) is recorded in `docs/DECISIONS.md`, "Clock v3: one bar, a dense store,
the moving line back on" (committed with T145a).

Commits: T145a `3c37952`; T145b is the next commit on the branch (message "T145b: ...").

## U1 -- T145a: the words and the quiet pool

- `Engine/ClockWords.lua` (new, all three main TOCs right after `Engine/ClockFace.lua`), pure:
  - `IsFull(face, quietFull)`: quiet signal; `fullnow`; plain `pct >= FULL_PCT` (0.995); `full` / `ooc`
    with a point value under `FULL_UNDER` (5).
  - `Build(face, look, latch, now, out, quietFull)`: `out.time/mana/manaMax/pct/mp5/fsr/rest = { text,
    tone }` (tone `text` / `crit` / `warn` / `muted`), `out.full`, `out.modelled.{mana,manaMax,pct}`.
    `look.timeFmt == "sec"` picks `80s`, else the face's own format. `look.warn == false` turns the
    urgency tones off. Nothing is allocated when `out` is passed (checked: under 1 KB over 1000 calls).
  - Steady moved here: `SteadyValue` (no table) and `Steady` (T144's API). `ManaModel.Steady` and its
    `STEADY_*` constants are now aliases, looked up at call time so that clockcheck's T68 core copy,
    which has no words file, still loads. Entering FULL snaps the latch.
  - `QuietFull(now, lastPowerEvent, lastSpend, base)`, with `QUIET` = 3.0 (VERIFY) and
    `QUIET_POINTS` = 2.
- `Engine/ManaModel.lua`: the Steady body is replaced by the alias.
- `Engine/ManaPool_Forever.lua`:
  - `ST:OnUnit("UNIT_POWER_FREQUENT", "player")` stores `Pool.lastPowerEvent` and counts
    `Pool.powerEvents`. It reads no argument.
  - `Pool:QuietFull(now)`, with the flag `Pool.QUIET_FULL = true`.
  - On the tick, in and out of combat, it anchors at max ("the game's pool stopped moving") and counts
    `Pool.quietAnchors`. This runs before the assume-full rule.
  - The `pool:` dump line.
- `UI/Clock_Forever.lua` is untouched: it already used `ST:OnUnit`.
- `tools/clockwordscheck.lua` (new): 62 checks on Forever, 51 on TBC. Section 9 drives the real pool
  (E7) inside a fight, so that the base rate is the test's own. Out of combat the pool re-reads the
  stub's `GetManaRegen` (bound at load) on every tick.

## U2 -- T145b: the store, the migration, the presets

- `UI/ClockStore.lua` (new, all three main TOCs just before `UI/ClockView.lua`): the schema of spec 1.5,
  `Normalize`, `Valid`, `Migrate`, `MigrateStored`, `Look`, `Get`, `Set`, `SetText`, `ApplyPreset`
  (`opts.fill` for EllesmereUI's host colour), `HasUndo`, `Undo`, `Reset`, `PRESETS` (the mockup's two,
  exact values), `PresetOK` (P2), `Differs`, `DumpLine`, `MigrationNotes`.
  - It is pure apart from `ST.db`, `ST:Fire` and `ST:AddDumpLine`; the suite proves this by loading it in
    an environment that holds only Lua's library.
  - Nothing reads it yet. `db.clockLook` is not rewritten at login, and `MigrateStored` is called only by
    the tests.
- `tools/data/clock-v2-author.lua`: the author's `clockLook` from the 15:31 saved variables, verbatim.
- `tools/clockstorecheck.lua` (new): 43 checks on Forever, 42 on TBC.
  - The author's store migrates to exactly the table in spec 1.5, with these four notes:
    - `after = empty` dropped;
    - `fsr = 2` dropped;
    - `show = mana -> the 5SR line on`;
    - `text.bar.items.label (inside left, 4/0, 10)` dropped.
  - Also covered: a v1 store, `line` with overrides, `compact`, empty / nil, an unchanged v3 store,
    garbage, purity, idempotence, every Set path and refusal, presets / Undo / Reset, P2, and the
    `MigrateStored` dump line.

## Judgment calls the lead may overrule

1. **An OOM value shown as 0 reads `OOM`** (crit tone with Warn colours on), and a TBC bound under 1 s
   reads `--`. The spec's property check, which forbids `0s` / `0:00` for every mode, requires something
   here, and the spec's table has no word for it.
2. **TBC's unstable time** (the face's `unstable`) is drawn muted, without the old `~` prefix (no `~` on
   the Bar since T144). A refill with no number reads `FULL --`, muted.
3. **The rest text below 1 s draws nothing**, so that `rest 0:00` cannot appear.
4. **A v1 store** (no `v`, or `v < 2`) runs the copied `CV.Migrate` rules and then T142's
   `CV.ResetBarLook`, because the T142 build did the same at login. The result is the defaults, with
   every old key named. This matches the spec's "v nil: the defaults".
5. **Kept conversions are not named; only dropped or changed keys are.** For example, colour table to
   hex, `frame.bar.w` to `width`, `text.bar.time = sec`. This keeps the author's notes to the spec's
   four. `show = both` is named as "dropped ... as before".
6. **Palette-name colours and `{ref = "accent"}` are dropped and named**, because the pure store cannot
   resolve them.
7. **The `pool:` dump line is registered at the first power event, not at load.** `consolecheck`'s
   "with no dump line the dump is byte-identical" check stays true. Every player power event is counted,
   whatever its power type: an energy event only delays the anchor, which is the safe direction.
8. **`Set` writes and fires even when the value equals the stored one.** That is one write and one
   event; E1 only cycles values that differ.
9. **`Reset` keeps no undo.** The spec ties Undo to presets only.

## Not done, and why

- `tools/data/import-forever-sv.lua` is not rebuilt. U2 changes nothing that is stored (login does not
  migrate yet), and `importcheck` passes against the committed fixture. U3 must rebuild it when it wires
  `MigrateStored`.
- `docs/SPEC-clock-v3.md` and `docs/review/clock-v3-diagnosis.md` are left untracked for the lead to
  commit.

## For U3

- `ClockWords.Build(...)` and `Pool:QuietFull(now)` are ready for the host tick.
- `ClockStore.MigrateStored()` registers the dump key `clock`, replacing ClockView's. Its line starts
  `clock: v3,`.
- ClockView's own dump keys `clockOld` and `clockReset` leave with ClockView.
- While both files are loaded, ClockView's `StoredRaw` adds `over = {}` to a v3 store when a
  `CLOCK_LOOK` fires. `Normalize` names that and drops it on the next write. Deleting ClockView (U3)
  ends this.
- The EllesmereUI preset expects the pane to pass `{ fill = <hex of ST.Media.EllesmereMana()> }`.

## Checks

- `luac -p` on every touched Lua file (`Engine/ClockWords.lua`, `Engine/ManaModel.lua`,
  `Engine/ManaPool_Forever.lua`, `UI/ClockStore.lua`, both new suites, the fixture): exit 0.
- `tools/clockwordscheck.lua`: forever `62 ok, 0 failed`, tbc `51 ok, 0 failed`.
- `tools/clockstorecheck.lua`: forever `43 ok, 0 failed`, tbc `42 ok, 0 failed`.
- `make check` with both units in the tree: `counted 106 run(s) against 106 expected`,
  `check: 111 run(s), all passed`, exit 0. apicheck had 0 findings, textcheck 0, and importcheck passed
  with the committed fixture.
