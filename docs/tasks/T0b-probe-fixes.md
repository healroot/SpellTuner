# T0b — probe fixes before the author's run

Status: **final (lead, 2026-09-27)** — ready for the implementer. Follows T0
(`docs/tasks/T0-probe.md`, commits a23b641, 27db2dc, 3699b3d). An independent review of those
commits confirmed five defects and a set of nits in the probe. The author's run on the beta is
the expensive step, so they are fixed first.

## Goal

The probe the author runs on the beta tells the truth in every line. It never reports a
description as changed when one run could not read it. It never counts Q1 as answered from an
unreadable bonus. It escapes every client string it prints, never hands a secret out of the
adapter, and reports a secret table as secret. The copy box holds the whole report, and the
to-do list only declares a question answered on the evidence its rule names. The spell dump shows
how many ranks it found per spell. `tools/probecheck.lua` proves each of these with an assertion
that fails on today's code, and it now tests the talent branch that will actually run on the
client. It is for the planner, who reads the report, and for the author, who should not have to
run the probe twice.

## Facts

Review lines are the planner's independent review of T0, 2026-09-27 (in the message that ordered
this task). EllesmereUI paths are relative to
`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/`, the working Forever addon
plan §1 names as a reference.

- **Q1 compares unreadable text.** `AgainstPreviousLines` (`Client/Probe.lua:513`) compares the
  stored description strings verbatim. A spell counts as changed when either run holds `""`,
  `nil`, `<secret>`, `<absent>` or `<error: ...>`. `Run` (`:832`) declares Q1 answered whenever
  the two bonus strings differ, including `<secret>` or `<error: ...>` against a number. The
  review reproduced a false "changed" under the stub.
- **Unescaped client strings.** `ActionOf` (`Client/Probe.lua:168-172`) returns the raw
  UNIT_COMBAT action string, which becomes a table key (`BumpCombat`, `:209`) and a report line
  without `Esc`. The `C_Secrets` key names are rendered unescaped too (`SecretsLines`, `:353`).
- **A comparison in the adapter.** `Client/API.lua:30` evaluates `result == nil` outside the
  `pcall`, on the walked value. `Has` also returns a table as is (`:33`), so a secret table would
  leave the adapter raw. Neither is reachable with T0's 65 names, but the adapter is shared and
  the rule is categorical (T0 Rules; the planner's line: "client calls live in `Client/` only;
  every shared file calls the client through `MD.API`").
- **The stub's secret stand-in overstates itself.** The comment at `tools/wowstub.lua:389-394`
  says every operation the plan names raises. Measured under Lua 5.1 (lead, 2026-09-27):
  - raises: arithmetic, unary minus, `<` `<=` (against anything), secret-vs-secret `==`, index,
    newindex, call, `..`, `tostring`;
  - passes silently: `==` or `~=` against a non-secret, `#`, truthiness (`if v then`), use as a
    table key, `type()`.

  A table metatable cannot trap the second group in Lua 5.1, but the client raises on them
  (plan §1.2).
- **A test that asserts nothing.** In `tools/probecheck.lua:109-114`, "the report is keyed by
  build" reads `report1` from `reports["70009"].text` and asserts that field equals itself.
  `Do()` discards `Run()`'s return.
- `issecrettable` exists beside `issecretvalue`: EllesmereUI tests both before touching a value
  (`EllesmereUI/EllesmereUI.lua:2469-2470`). What it covers that `issecretvalue` does not is
  **UNKNOWN**; the probe asks both.
- An EditBox's default letter cap is **UNKNOWN** on Forever. The TBC addon lifts it on every edit
  box it creates, both copy boxes included (`UI/Style.lua:814`, `eb:SetMaxLetters(0)` in
  `UI.CreateEditBox`, which `UI.CreateScrollEditBox` uses at `:978`).
- **The spellbook hides lower ranks by default.** A "show all ranks" option sits under the arrow
  at the top right — Wowhead news 383050 (2026-09-22), `docs/REFERENCES-FOREVER.md` §4 lines
  181-184, `docs/FOREVER-PLAN.md` §1 table. Whether the option changes what
  `C_SpellBook.GetSpellBookItemInfo` enumerates is **UNKNOWN**. So the author turns it on before
  running the probe, and the dump says how many ranks it found per name.
- **Q6's real branch is untested.** The beta baseline has `C_ClassTalents` and `C_Traits`
  present (plan §1.3). The stub's forever profile leaves them undefined, so probecheck only tests
  the absent branch. The call shapes are in EllesmereUI: `C_ClassTalents.GetActiveConfigID()`,
  `C_Traits.GetConfigInfo(configID)` (T0 Facts).
- **Q4, Q8, the chat line and the character line** (review nits). The Q4 latch
  (`Client/Probe.lua:618`, `:668`) is set by any read of the Current session, in combat or not.
  T0's rule says out of combat. Q8 (`:874`) is answered from the SENT counter alone, but
  `GetShapeshiftFormID` in combat lives in the snapshot. The chat line (`:906`) says "saved" even
  when nothing was saved. `Show("UnitName", "player")` (`:292`, `:891`) joins every return, so
  the client's `name, realm` answer reads `Healroot, nil`.
- `SpellWalk` (`:403-406`): a row whose `spellID` read raised is counted nowhere.

## Files

| file | change |
|---|---|
| `Client/API.lua` | `Has`: no comparison operator on the walked value, and a secret is answered `true` |
| `Client/Probe.lua` | the fixes below |
| `tools/wowstub.lua` | the secret comment and header; `S.SecretTable`, `issecrettable`, `S.AddTraits`, `S.meterSecretInCombat`, stand-ins listed below; `FrameMT:SetMaxLetters` stores its argument |
| `tools/probecheck.lua` | the new and corrected assertions, a fourth step |
| `docs/tasks/T0b-probe-fixes.md` | Report section only |

### `Client/API.lua`

- Inside the one `pcall` that walks the name, classify the result there:
  - `type(result) == "nil"` means absent;
  - a value for which `issecretvalue` or `issecrettable` (each reached with a raw `_G` lookup
    inside that `pcall`, and only if it is a function) says `true` is answered `true`;
  - a function or table is returned;
  - any other value is answered `true`.

  No `==`/`~=` on the walked value anywhere. The cache and the `client` detection are unchanged.

### `Client/Probe.lua`

1. **`IsSecret(v)`**: true when `issecretvalue(v)` or `issecrettable(v)` returns `true`. Each is
   reached through `MD.API.Has` and called under its own `pcall`; an absent one counts as `false`.
2. **`Readable(s)`**, a new local: true only for a string that is not `""`, `"nil"` or
   `"nothing"` and does not start with `<`. It is applied to our own stored strings only.
3. **Against the previous run.**
   - A spell present in both runs is **comparable** when both descriptions pass `Readable`. Only
     comparable spells are compared, listed as `changed <id> <name>` and counted.
   - When one or more spells are present in both runs but not comparable, add one line after the
     changed lines (or after `no description changed`):
     `<k> not comparable (unreadable on one run)`.
   - Q1 is answered only when there is a previous run, both bonus strings pass `Readable`, and
     they differ. The line reads
     `Q1 answered: <c> of <m> spell descriptions changed when bonus healing went <old> -> <new>`,
     where `<m>` is the comparable count.
4. **Escaping.** `ActionOf` returns `Esc(a)` for a plain string. `SecretsLines` renders each key
   name through `Esc`.
5. **`First(name, ...)`**, a new local: like `Show`, but it renders only the first return (through
   `Describe`), `nothing` when there is none, and `<absent>` / `<error: ...>` as `Show` does. Use
   it for `UnitName` and `GetRealmName` in the `character:` line and in the saved record's `char`.
6. **Spells.**
   - A row whose `spellID` read raised (`Field` status `"error"`) counts under a new `error`
     tally. The slots line becomes
     `slots 1-500: <n> with a spell, <h> healing, <e> empty description, <s> secret, <x> error`.
     Slots where `GetSpellBookItemInfo` itself raised are not counted; past the last item that is
     expected.
   - Directly after the slots line, print
     `ranks per name: <name> <count>; <name> <count>; ...`, counting the dumped (healing) spells
     by their rendered name, names sorted. When there are none, print `ranks per name: none`.
7. **Q1 to do** reads exactly:
   `Q1 to do: turn on show all ranks in the spellbook (the arrow at its top right), then change your bonus healing (put on or take off a +healing item, or take a buff that changes the number in the spells header), then type /st probe again in the same session`
8. **Q4.** `DamageMeterLines` reads `First("UnitAffectingCombat", "player")` once. The latch is set
   only when that read gives `false` and the Current session gave at least one source.
9. **Q8** is answered only when a combat snapshot exists **and** `UNIT_SPELLCAST_SENT combat`
   counted at least one cast.
10. **The chat line** after a run says `saved` only when the save ran. Otherwise it reads
    `SpellTuner probe: build <build>, <n> lines, not saved (no SavedVariables table). Click the box, Ctrl+A, Ctrl+C.`
11. **Copy box.** `eb:SetMaxLetters(0)` when the edit box is created, inside the existing `pcall`.

### `tools/wowstub.lua`

- **The secret comment** (`:389-394`) is rewritten to the measured list in Facts: what raises and
  what passes silently. Say that the second group raises on the client and that the stub cannot
  trap it, so probecheck cannot catch a `==`, `#`, truthiness test or table-key use on a secret.
  Add two lines saying the same to the stub's header comment (after the "Rules it deliberately
  keeps" list).
- In `UseProfile("forever")`:
  - `S.SecretTable()`: a table with the same raising metatable behaviour but its own marker.
    `issecrettable(v)` is true exactly for those; `issecretvalue` stays false for them. The
    comment says it is a stand-in, since the client's split between the two is UNKNOWN.
  - `C_DamageMeter.GetCombatSessionFromType` and `GetCombatSessionSourceFromType` return
    `S.SecretTable()` (not `S.Secret()`) when `S.inCombat and S.meterSecretInCombat ~= false`,
    and read normally otherwise.
  - `C_Spell.GetSpellDescription(5185)` returns `S.Secret()` while `S.inCombat`; the other ids
    are unchanged.
  - Spellbook slots become 1 = 774, 2 = 5185, 3 = 5176, 4 = a row whose index raises
    (`setmetatable({}, { __index = function() error("spellbook row unreadable (stub)") end })`,
    not secret), 5 = 1058.
    - 1058: name `Rejuvenation`, subtext `Rank 2`, description
      `"Heals the target for 56 over 12 sec."`.
    - The subtexts become per id: 774, 5185 and 5176 `Rank 1`; 1058 `Rank 2`.
  - `UnitName(u)` returns two values, the name and `nil`, as the client does.
  - `C_Secrets` gains `["ShouldStub|Piped"] = function() return false end`, a stand-in key that
    exercises the escaping.
- `function S.AddTraits()` installs `C_ClassTalents = { GetActiveConfigID = function() return 7 end }`
  and `C_Traits = { GetConfigInfo = function(id) if id == 7 then return { ID = 7, name = "Stub loadout", type = 1 } end return nil end }`.
  `UseProfile` still leaves both undefined.
- `FrameMT:SetMaxLetters(n)` stores `self.maxLetters = n`. It was a no-op through the fallback, and
  no TBC suite reads the field.

### `tools/probecheck.lua`

- **A chat capture.** Wrap `DEFAULT_CHAT_FRAME.AddMessage` so each step's messages are also
  appended to a table the checks read (still printed).
- **Step 2.**
  - Run 1 is `local ok1, r1 = pcall(MD2.Probe.Run)`, and `report1 = r1`. Runs 2 and 3 keep the
    slash path and read the saved text.
  - Before `PLAYER_REGEN_DISABLED`, also fire `UNIT_COMBAT("party1", "BLOCK|X", "", 5, 1)`.
- **Step 3.**
  - Call `S3.AddTraits()` before loading.
  - Seed a second report beside `69893`:
    `["70009"] = { char = "Healroot-Test", at = "2026-09-26 10:06:00", text = "old", bonus = "<error: stub>", desc = { ["774"] = "Heals the target for 32 over 12 sec.", ["5185"] = "<secret>" } }`.
- **Step 4 (new).** Load a fresh stub the same way, then in order:
  1. `UseProfile("forever")`, then `S4.meterSecretInCombat = false`.
  2. Set `_G.T0B_SECRET = S4.Secret()` and `_G.T0B_SECRET_TABLE = S4.SecretTable()`.
  3. Load the three files into a new table and fire `ADDON_LOADED "SpellTuner"`.
  4. Fire `PLAYER_REGEN_DISABLED`. Do **not** run `S4.timers`, so no snapshot is taken.
  5. Set `S4.inCombat = true` and fire `UNIT_SPELLCAST_SENT("player", "Tankname", "Cast-2", 774)`.
  6. Set `SpellTunerDB = nil`, then `local ok5, report5 = pcall(MD4.Probe.Run)`.

  Every call in steps 3 and 4 counts toward "the probe never raises".

## Rules

T0's Rules stand unchanged: client calls in `Client/` only; no arithmetic or comparison on a
client value; everything from the client under `pcall`; ASCII only, never a bare `|`;
`BackdropTemplate`; the multi-return trap; no new globals beyond T0's list; comments say why.
Two more:

- **Tests first.** Write each new or corrected assertion, run probecheck, and see it **fail on
  the current code**, then fix. The exceptions are the step-3 talent assertion, which can pass as
  soon as `S.AddTraits` exists, and "the copy box has no letter cap", which needs the stub field
  first. Say in the report which assertions you saw fail.
- Build large edits in pieces: no single tool call above ~150 lines of new text, and short prose
  between calls. The first T0 attempt died on the 64k output limit.

## Acceptance

1. `tools/run.sh tools/probecheck.lua` ends with `N ok, 0 failed`, N >= 41. The 27 T0 names stay
   verbatim, with these corrections:
   - "the report is keyed by build": `ok1` is true, `report1` is a string, and it equals
     `reports["70009"].text` right after run 1. Also, the chat capture of run 1 contains
     `lines, saved.`
   - "the combat snapshot is taken in combat": `taken ` and `in combat: true` are searched only
     in run 2's text between `\n== combat snapshot\n` and `\n== events seen this session\n`.
   - "the probe never raises": now covers steps 3 and 4 as well.
   - "the report is ASCII with no bare pipe": now covers report5 as well.
   - "healing spells are dumped ...", "a spell that does not heal is not dumped", "the damage
     meter in combat is reported secret, not walked" and the others keep their conditions; they
     must still pass with the new stub.

   And these 14 new names, verbatim:
   - "an unreadable description is not counted as changed": run 3 has `changed 774 Rejuvenation`
     and `1 not comparable (unreadable on one run)`, and no `changed 5185`.
   - "the Q1 count covers comparable descriptions only": run 3 has
     `Q1 answered: 1 of 3 spell descriptions changed when bonus healing went 0 -> 50`.
   - "Q1 is answered only when both bonus readings are readable": step 3 has `Q1 to do` and
     `1 not comparable (unreadable on one run)`.
   - "event and secret names are escaped": run 3 has `UNIT_COMBAT ooc party BLOCK||X n=1` and
     `ShouldStub||Piped = false`.
   - "MD.API.Has never hands back a secret": `MD4.API.Has("T0B_SECRET") == true` and
     `MD4.API.Has("T0B_SECRET_TABLE") == true`.
   - "a secret table is reported secret": run 2 has `session Current HealingDone = <secret>` with
     the session now an `S.SecretTable()`. It fails today because `IsSecret` does not ask
     `issecrettable`.
   - "the copy box has no letter cap": the last `EditBox` in step 2's `S.allFrames` has
     `maxLetters == 0`.
   - "an in-combat damage meter read does not answer Q4": report5 has
     `session Current HealingDone = sources=1` and `Q4 to do`.
   - "Q8 needs the combat snapshot": report5 has `none this session` and `Q8 to do`.
   - "a spellbook row that raises is counted as an error": run 1 has
     `slots 1-500: 4 with a spell, 3 healing, 0 empty description, 0 secret, 1 error`.
   - "the chat line says saved only when it saved": step 4's chat capture contains
     `not saved (no SavedVariables table)`.
   - "the character line shows the first return only": run 1 has
     `character: Penek Anniversary DRUID level 64`, and `reports["70009"].char == "Penek-Anniversary"`
     after run 1.
   - "the dump counts ranks per spell name": run 1 has
     `ranks per name: Healing Touch 1; Rejuvenation 2`.
   - "the talent APIs that exist are called and shown": step 3 has
     `C_ClassTalents.GetActiveConfigID() = 7` and
     `C_Traits.GetConfigInfo(<first return above>) = {ID=7, name=Stub loadout, type=1}`.
2. The sixteen TBC suites print exactly their T0 tails (the baseline in `docs/tasks/T0-probe.md`
   Acceptance 2). Run the loop given there.
3. `tools/.lua/lua-5.1.5/src/luac -p` is clean on every `.lua` file you touched.
4. `git status --short` lists only the files in the Files table.
5. Paste into the Report:
   - the full probecheck output;
   - which assertions you saw fail before the fix;
   - the sixteen tail lines;
   - the `luac` command;
   - run 3's report text between `== spells (` and `== talents`, plus its `== to do` section;
   - `git status --short`.

## Out of scope

- The load-time `loadedName ~= ADDON_NAME` and `HANDLERS[event]` comparisons on event payloads
  (addon and event names are never secret — planner's call).
- The double-escaped previous bonus string in the `previous:` line (cosmetic — planner's call).
- Making Lua 5.1 trap `==`, `#`, truthiness or table keys on the stand-in; documenting it is the
  fix.
- The TOCs, the markers, `release.sh`, `tools/harness.lua`, the TBC addon's files.
- `CLAUDE.md`, `docs/FOREVER-PLAN.md`, `docs/HISTORY.md`, `docs/REFERENCES-FOREVER.md`,
  `docs/TOOLS.md`, `docs/TESTING.md`, `docs/ROADMAP-FOREVER.md`, `docs/tasks/T0-probe.md`.
- Commits. Do not commit.

## Report

Tests were written first: all 27 T0 assertion names were kept (a few conditions corrected) and 14
new ones added to `tools/probecheck.lua`, matching the Acceptance list verbatim, before any fix
landed in `Client/API.lua` or `Client/Probe.lua`. `tools/wowstub.lua`'s scaffolding (the new
spellbook slots, `S.SecretTable`, `S.AddTraits`, `FrameMT:SetMaxLetters`, the `meterSecretInCombat`
gate) had to exist first for the script to run to completion at all (two of the new assertions --
the step-3 talent one and "the copy box has no letter cap" -- are the ones the task names as
passing as soon as their stub piece exists, so they were not expected to fail). To see the other 14
plus the corrected ones genuinely fail, `Client/API.lua` was temporarily reverted to its pre-task
content (saved and restored via the scratchpad, not committed) and the suite run once against
unfixed `Client/API.lua` + unfixed `Client/Probe.lua` + the finished `tools/wowstub.lua` +
finished `tools/probecheck.lua`. That run produced 25 ok, 16 failed (below). `Client/API.lua` was
then restored to the fix and `Client/Probe.lua`'s ten items applied one at a time, re-running after
each; the suite reached 41 ok, 0 failed with no assertion ever weakened.

### `Client/API.lua`

`Has` now classifies the walked value *inside* the one `pcall`, and never runs `==`/`~=` on it
outside that pcall. The walk's own early exit (`type(obj) ~= "table"`) now sets `obj = nil` and
`break`s instead of returning early, so the SAME classify block (absent / secret / function-or-
table / other) always runs on whatever `obj` ended up being. `issecretvalue` and `issecrettable`
are each looked up with `rawget(_G, ...)`, checked for `type(...) == "function"`, and called under
their own `pcall`; either saying `true` makes `Has` answer `true` rather than handing back the raw
secret. `MD.API.client`'s detection block is untouched, as the task says.

### `Client/Probe.lua`

- `IsSecret(v)`: now asks both `issecretvalue` and `issecrettable` (each through `MD.API.Has`,
  each under its own `pcall`, an absent one counting as `false`), so a secret TABLE (the damage
  meter's session, once the stub marks it that way) is caught, not just a secret scalar.
- New local `Readable(s)`: false for `""`, `"nil"`, `"nothing"`, anything starting with `"<"`, or
  a non-string; true otherwise. Applied only to our own already-rendered strings.
- New local `First(name, ...)`: like `Show`, but renders only `packed[2]` through `Describe` (or
  `<absent>` / `<error: ...>` / `"nothing"` the same way `Show` does) -- the multi-return trap fix.
  Used in `ClientLines`'s `character:` line (`First("UnitName","player")`, `First("GetRealmName")`)
  and in `Run()`'s saved `char` field.
- `ActionOf` now returns `Esc(a)` instead of the raw string; `SecretsLines` renders each `C_Secrets`
  key through `Esc` before the `=`. Both feed `BumpCombat`'s key and the report line from the same
  escaped string, so a literal `|` in an action or a secret-predicate name becomes `||` everywhere
  it appears, not just where it happened to be escaped before.
- `SpellWalk` now also returns `errorN`: a new `elseif idStatus == "error"` branch counts a row
  whose `spellID` read raised (via `Field`) that was previously counted nowhere. `Run()`'s slots
  line gained the `, %d error` field and, directly after it, a new `ranks per name: <name> <count>;
  ...` line (sorted by name, `none` when there are no healing spells), built from `order` filtered
  to `sp.healing`.
- `AgainstPreviousLines` rewritten: a spell present in both runs is now "comparable" only when
  `Readable(prevDesc) and Readable(curDesc)`; only comparable spells are compared and can appear as
  `changed <id> <name>`; a spell present in both but not comparable increments `notComparable`,
  rendered as one `<k> not comparable (unreadable on one run)` line after the changed lines (or
  after `no description changed`). `info.totalCount` is now the comparable count, used by Q1.
- Q1's to-do text is the exact new wording (mentions turning on "show all ranks" first). Q1 is
  answered only when `q1Info.compared and Readable(q1Info.oldBonus) and Readable(q1Info.newBonus)
  and q1Info.oldBonus ~= q1Info.newBonus`.
- Q4: `DamageMeterLines` now reads `First("UnitAffectingCombat", "player") == "false"` once into
  `outOfCombat`, and `MarkSeen` only sets the session-wide latch `if outOfCombat`, so a Current
  session read while in combat (even one the stub happens not to have secreted) can no longer
  answer Q4.
- Q8: the `if` guard gained `combatSnapshot ~= nil and` before the existing `sentCombat and
  sentCombat.n >= 1`, so a `UNIT_SPELLCAST_SENT` seen with no snapshot ever taken no longer answers
  Q8.
- The chat line: `Run()`'s save block now sets a local `saved` flag (true only when the
  `SpellTunerDB.probe.reports` table existed), and the final chat message branches on it -- the
  exact `not saved (no SavedVariables table)` wording when it did not save.
- The copy box: `eb:SetMaxLetters(0)` added right after `eb:SetWidth(520)`, inside the box's
  existing outer `pcall`.

### `tools/wowstub.lua`

- Header comment gained two lines (after "Rules it deliberately keeps") naming the secret stand-in
  as stricter than the client on `==`/`~=`, `#`, truthiness and table-key use, and that nothing here
  can make Lua 5.1 trap those four.
- The `SECRET_MT` comment rewritten to the measured raises/passes-silently split from Facts, ending
  in the same "cannot trap the second group" sentence.
- New `SECRETTABLE_MT` (same raising methods, its own table identity), `S.SecretTable()` and
  `issecrettable(v)` (`rawequal(getmetatable(v), SECRETTABLE_MT)`), right after `S.Secret()` /
  `issecretvalue`.
- `UnitName(u)` inside `UseProfile("forever")` now returns `x.name, nil` (two values) instead of
  falling through to the top-level single-return `UnitName`.
- Spellbook: `SPELL_SLOTS` gained `[5] = 1058`; slot 4 is handled directly in
  `GetSpellBookItemInfo` and returns a shared `ERROR_ROW` (`setmetatable({}, {__index = function()
  error(...) end})`, not secret). `SPELL_NAMES`/`SPELL_SUBTEXT`/`SPELL_DESC` gained 1058
  (`"Rejuvenation"`, `"Rank 2"`, the fixed `"Heals the target for 56 over 12 sec."`); `SPELL_SUBTEXT`
  replaces the old "Rank 1 for every named spell" `GetSpellSubtext` with an explicit per-id table.
  `GetSpellDescription(5185)` returns `S.Secret()` while `S.inCombat`; the other three ids are
  unaffected by combat.
- `C_Secrets` gained `["ShouldStub|Piped"] = function() return false end`.
- `C_DamageMeter.GetCombatSessionFromType` / `GetCombatSessionSourceFromType` now return
  `S.SecretTable()` (not `S.Secret()`) when `S.inCombat and S.meterSecretInCombat ~= false`, else
  read normally, via a shared local `meterSecretNow()`.
- New top-level `function S.AddTraits()` installs `C_ClassTalents.GetActiveConfigID` (`7`) and
  `C_Traits.GetConfigInfo` (`7 -> {ID=7, name="Stub loadout", type=1}`, else `nil`).
  `UseProfile("forever")` itself still leaves both undefined, as the task says.
- `FrameMT:SetMaxLetters(n)` stores `self.maxLetters = n` (was the no-op fallback).

### `tools/probecheck.lua`

- New `ChatCapture()` helper wraps the CURRENT `DEFAULT_CHAT_FRAME.AddMessage` and returns a table
  every message is also appended to (still printed); called fresh after each `dofile(wowstub.lua)`
  as `chat2`, `chat3`, `chat4`.
- New `Between(s, startMarker, endMarker)` helper (plain substring search both ends) for scoping a
  search to one report section.
- Step 2: run 1 is now `local ok1, r1 = pcall(MD2.Probe.Run)` (pushed onto `raises` too), with
  `report1Char` captured right after it; "the report is keyed by build" now also asserts `ok1 ==
  true`, `type(report1) == "string"`, and that `chat2` contains `lines, saved.`. A
  `UNIT_COMBAT("party1", "BLOCK|X", "", 5, 1)` fire was added before `PLAYER_REGEN_DISABLED`.
- Step 3: `S3.AddTraits()` called right after `S3.UseProfile("forever")`, before `S3.Load(...)`. The
  seeded `SpellTunerDB.probe.reports` gained a `"70009"` entry (`bonus = "<error: stub>"`, `desc`
  holding a readable 774 and a `"<secret>"` 5185) beside the existing `"69893"` one.
- New Step 4 block: fresh stub, `UseProfile("forever")`, `S4.meterSecretInCombat = false`,
  `_G.T0B_SECRET` / `_G.T0B_SECRET_TABLE` set, `chat4` captured, the three files loaded into `MD4`,
  `ADDON_LOADED` fired, `PLAYER_REGEN_DISABLED` fired (its `S4.timers` deliberately never run, so no
  snapshot is taken), `S4.inCombat = true` then `UNIT_SPELLCAST_SENT("player","Tankname","Cast-2",
  774)` fired, `SpellTunerDB = nil`, then `local ok5, report5 = pcall(MD4.Probe.Run)`. Right after,
  `hasSecretScalar`/`hasSecretTable` are computed via `MD4.API.Has(...)` and the two globals are
  then set back to `nil` so "the probe adds no global but its own" (which runs later, over all of
  `_G`) sees a clean state -- they are test fixtures, not something the probe itself creates.
- "the probe never raises" extended to require `step4LoadOk`, `step4AddonLoadedOk`,
  `step4RegenDisabledOk`, `step4SentOk` and `ok5` all true, on top of the existing step-3 and
  `raises` checks.
- "the combat snapshot is taken in combat" rewritten to search only inside
  `Between(report2, "\n== combat snapshot\n", "\n== events seen this session\n")`.
- "the report is ASCII with no bare pipe" extended to include `report5`.
- 14 new `check(...)` calls added verbatim by name (listed in Acceptance and below).

### Which assertions failed before the fix

Run against unfixed `Client/API.lua` (temporarily reverted) + unfixed `Client/Probe.lua` + the
finished `tools/wowstub.lua`/`tools/probecheck.lua`: **25 ok, 16 failed**. The 16 that failed:

```
the report is ASCII with no bare pipe
a change in bonus healing is reported against the previous run
the damage meter in combat is reported secret, not walked
an unreadable description is not counted as changed
the Q1 count covers comparable descriptions only
Q1 is answered only when both bonus readings are readable
event and secret names are escaped
MD.API.Has never hands back a secret
a secret table is reported secret
the copy box has no letter cap
an in-combat damage meter read does not answer Q4
Q8 needs the combat snapshot
a spellbook row that raises is counted as an error
the chat line says saved only when it saved
the character line shows the first return only
the dump counts ranks per spell name
```

The two exceptions the task names ("the talent APIs that exist are called and shown" and "the copy
box has no letter cap") behaved as expected: the talent one passed as soon as `S.AddTraits` existed
(it is not in the fail list above); "the copy box has no letter cap" **did** fail here because
`Client/Probe.lua` had not yet been given the `eb:SetMaxLetters(0)` call -- the stub field existing
is necessary but not sufficient, so it is correctly in the list. `a change in bonus healing is
reported against the previous run` (one of the 27 T0 names, condition unchanged) also failed here
because the naive `~=` comparison the old code used treated `"<secret>"` against readable text as a
change, reproducing exactly the false "changed 5185" the Facts describe.

### Full `tools/run.sh tools/probecheck.lua` output (after all fixes)

```
|cff9966ffSpellTuner:|r first run — the widget is unlocked for 60s so you can drag it. |cffffff00/md lock|r when done, |cffffff00/md help|r for commands.
the TBC line reads its version from SpellTuner_TBC.toc                   ok
Client/API.lua loads under the TBC line                                  ok
MD.API.client is forever on interface 16001                              ok
MD.API.Has walks dotted names and says false for a missing one           ok
SpellTuner probe: build 70009, 164 lines, saved. Click the box, Ctrl+A, Ctrl+C.
the report is keyed by build                                             ok
SpellTuner probe: build 70009, 170 lines, saved. Click the box, Ctrl+A, Ctrl+C.
SpellTuner probe: build 70009, 182 lines, saved. Click the box, Ctrl+A, Ctrl+C.
SpellTuner probe: build 70009, 166 lines, saved. Click the box, Ctrl+A, Ctrl+C.
SpellTuner probe: build 70009, 160 lines, not saved (no SavedVariables table). Click the box, Ctrl+A, Ctrl+C.
the probe never raises                                                   ok
a missing function is reported absent, not raised                        ok
registering a bad event is caught                                        ok
a secret value is reported secret, not summed                            ok
a client error is reported as a string                                   ok
the report is ASCII with no bare pipe                                    ok
the report reaches the copy box                                          ok
the report sections are in order                                         ok
the header names build 70009 and interface 16001                         ok
healing spells are dumped with id, name, rank and the whole description  ok
a spell that does not heal is not dumped                                 ok
a change in bonus healing is reported against the previous run           ok
the combat snapshot is taken in combat                                   ok
UNIT_COMBAT and UNIT_SPELLCAST_SENT are counted by phase                 ok
the damage meter in combat is reported secret, not walked                ok
the damage meter after combat lists sources and spells                   ok
SavedVariables that did not come back are reported as such               ok
SavedVariables that came back are reported with their stamp              ok
the report prints the TOC that loaded                                    ok
the probe adds no global but its own                                     ok - SPELLTUNER_TOC, SLASH_SPELLTUNER1, SpellTunerProbeFrame, SLASH_SPELLTUNER3, SLASH_SPELLTUNER2
/st and /md both reach the probe                                         ok
the to-do list names what is left                                        ok
an unreadable description is not counted as changed                      ok
the Q1 count covers comparable descriptions only                         ok
Q1 is answered only when both bonus readings are readable                ok
event and secret names are escaped                                       ok
MD.API.Has never hands back a secret                                     ok
a secret table is reported secret                                        ok
the copy box has no letter cap                                           ok
an in-combat damage meter read does not answer Q4                        ok
Q8 needs the combat snapshot                                             ok
a spellbook row that raises is counted as an error                       ok
the chat line says saved only when it saved                              ok
the character line shows the first return only                           ok
the dump counts ranks per spell name                                     ok
the talent APIs that exist are called and shown                          ok

41 ok, 0 failed
```

### The sixteen TBC suites (matches the T0 baseline exactly)

```
for s in simcheck reccheck replaycheck replayui runcheck reviewui navui dashui regencheck simwindow solvercheck timeline spelltip practice practiceui migrate; do tools/run.sh tools/$s.lua | tail -1; done
```
```
|cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
54 ok, 0 failed
80 ok, 0 failed
98 ok, 0 failed
78 ok, 0 failed
44 ok, 0 failed
25 ok, 0 failed
56 ok, 0 failed
27 ok, 0 failed
8 ok, 0 failed
70 ok, 0 failed
27 ok, 0 failed
48 ok, 0 failed
74 ok, 0 failed
49 ok, 0 failed
7 ok, 0 failed
```

### `luac`

```
tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Client/Probe.lua tools/wowstub.lua tools/probecheck.lua
```
Output: empty (clean) on all four files.

### Run 3's report, `== spells (` through `== talents`, plus its `== to do` section

```
== spells (bonus healing 50)
slots 1-500: 4 with a spell, 3 healing, 0 empty description, 0 secret, 1 error
ranks per name: Healing Touch 1; Rejuvenation 2
spell 774
  name: Rejuvenation
  rank: Rank 1
  desc: Heals the target for 82 over 12 sec.
spell 5185
  name: Healing Touch
  rank: Rank 1
  desc: Heals a friendly target for 40 to 55.||nIt is \226\128\156quoted\226\128\157.
spell 1058
  name: Rejuvenation
  rank: Rank 2
  desc: Heals the target for 56 over 12 sec.
== spells against the previous run
previous: this session at 2025-09-04 15:33:20, bonus healing 0 -> 50
changed 774 Rejuvenation
1 not comparable (unreadable on one run)
== talents
```

```
== to do
Q1 answered: 1 of 3 spell descriptions changed when bonus healing went 0 -> 50
Q2 answered: UnitExists(party1) read true in the combat snapshot
Q5 answered: UnitExists(party1) read true in the combat snapshot
Q3 answered: a UNIT_COMBAT combat party counter was seen
Q4 answered: the damage meter listed at least one source out of combat
Q6 answered: see == talents
Q7 to do: type /reload, then /st probe; if this line still says to do, SavedVariables did not come back
Q8 answered: a UNIT_SPELLCAST_SENT combat counter was seen
Q9 answered: SPELLTUNER_TOC = Forever
```

(`previous: this session at 2025-09-04 15:33:20` -- the date comes from the stub's fixed `date()`;
irrelevant to what is being tested here.)

### `git status --short`

```
 M Client/API.lua
 M Client/Probe.lua
 M tools/probecheck.lua
 M tools/wowstub.lua
?? docs/tasks/T0b-probe-fixes.md
```
Matches the Files table exactly (the task file itself is new/untracked, as expected -- only its
Report section was written).

### Skipped / not touched

Everything the Out of scope section names: the load-time `loadedName ~= ADDON_NAME` and
`HANDLERS[event]` comparisons, the double-escaped previous-bonus string in the `previous:` line,
making Lua 5.1 trap `==`/`#`/truthiness/table-key on the stand-in, the TOCs, `release.sh`,
`tools/harness.lua`, the TBC addon's files, and `CLAUDE.md` / `docs/FOREVER-PLAN.md` /
`docs/HISTORY.md` / `docs/PLAN.md`. No commit was made.

### Nothing to flag

No Fact in the task turned out false in the code, and no point needed a guess -- the Files/Acceptance
text and the existing code matched closely enough (down to line numbers) that every fix and every
new assertion could be written and verified as specified. No question.

### Lead review, round 1 (2026-09-27) — rejected on one line, re-issued

Everything passes (41 ok, sixteen suites unchanged, luac clean) and the code changes are
accepted. Rejected on **Files, `tools/wowstub.lua`, "The secret comment"**: both new comments
state the direction backwards. The header says the stand-in "also raises on ==/~= against a
non-secret, #, truthiness and table-key use, which the client does NOT". The measurement is the
opposite: the stub lets those through silently. The `SECRET_MT` comment says it "fails fast on
all of it", which contradicts its own next clause. My Facts were also loose here: on the client,
`type()` works on a secret (EllesmereUI, T0 Facts) and truthiness is UNKNOWN. So the text below is
the corrected one. Replace, verbatim:

1. `tools/wowstub.lua`, the five header lines starting `-- The stub's secret stand-in is stricter`
   become:
   ```
   -- The forever profile's secret stand-in (S.Secret, S.SecretTable) raises on arithmetic, < <=,
   -- secret-vs-secret ==, index, newindex, call, .. and tostring. It CANNOT raise on == or ~=
   -- against a plain value, #, truthiness or use as a table key (Lua 5.1 gives a table no hook
   -- for them), yet the client raises on ==, #, and table keys -- so a suite passing here does
   -- not prove the code never does one of those to a secret. See the comment on SECRET_MT.
   ```
2. `tools/wowstub.lua`, the comment block above `local function secretRaise()` (from
   `-- A secret value, measured under Lua 5.1` to `-- ==, #, truthiness test or table-key use on a secret.`)
   becomes:
   ```
   -- A secret value, measured under Lua 5.1 (lead, 2026-09-27):
   --   raises here: arithmetic, unary minus, < <= (against anything), secret-vs-secret ==,
   --   index, newindex, call, .., tostring;
   --   passes silently here: == or ~= against a plain value, #, truthiness (if v then), use as a
   --   table key, type().
   -- On the client (plan 1.2): comparison, #, table key and call raise; type() works
   -- (EllesmereUI); truthiness is UNKNOWN. So the stub is LOOSER than the client on ==, ~=, #
   -- and table keys, and nothing a metatable can do in Lua 5.1 closes that gap. __concat and
   -- __tostring are stricter than the client, which yields a secret string that raises later.
   ```
3. `Client/Probe.lua`, the four comment lines above `local function First(name, ...)` become:
   ```
   -- Like Show, but renders only the FIRST return through Describe. UnitName answers name,
   -- realm (realm nil on your own realm) and Show joins every return, so the character line
   -- read "Healroot, nil"; First keeps the one value the line means.
   ```
4. `Client/Probe.lua`, the first three comment lines above `local function IsSecret(v)` (from
   `-- True when either issecretvalue` to `-- EllesmereUI checks both before touching anything (Facts).`)
   become:
   ```
   -- True when either issecretvalue or issecrettable says so. EllesmereUI checks both before
   -- touching a value; which of the two the client's damage meter session or aura tables
   -- answer is UNKNOWN (Facts), so a table either one flags is reported <secret>.
   ```
   Keep the two lines after them ("Each is reached through Has ..." / "never raises ...").

No code changes. After the edits: probecheck still 41 ok, the sixteen suites unchanged, `luac -p`
clean on both files. Append a one-paragraph "Round 2" note under your Report saying it was done.

### Round 2 (2026-09-27)

Replaced exactly the four comment blocks the lead named, verbatim, in `tools/wowstub.lua` (the
header lines above `local S = {}`, and the `SECRET_MT` block above `local function secretRaise()`)
and `Client/Probe.lua` (above `local function First(name, ...)` and above `local function
IsSecret(v)`); no other line in any file was touched. `tools/run.sh tools/probecheck.lua` still
ends `41 ok, 0 failed`; the sixteen TBC suites print the same tails as round 1 (unchanged); `tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua` is clean.

### Lead review, round 2 (2026-09-27) — accepted

The four comments now read as specified. probecheck 41 ok, 0 failed; the sixteen suites print
their T0 tails; `luac -p` clean on every touched file. No client call outside `Client/`, no
comparison on a walked value in the adapter, no new global, and no non-ASCII outside comments.
One deviation accepted: "the probe adds no global but its own" is evaluated after steps 3 and 4,
not right after step 2 (as in T0). Step 4 resets the talent fakes and the test fixtures are
cleared by hand, so a probe leak would still show.
