# T0c — the probe measures the secret question and names a blocked action

Status: **done — lead-accepted 2026-09-28** (implemented 2026-09-27; see the Review at the end). Follows T0 and T0b
(`docs/tasks/T0-probe.md`, `docs/tasks/T0b-probe-fixes.md`) and the author's first two reports
from the beta, `docs/probe/1.60.1_70009.md`. Every decision below is the planner's; none is
reopened here.

## Goal

The probe the author runs next on the beta (build 70009, Healroot) answers what the first two
reports raised, and ships under the TOC names the client actually loads. When this task is done:
(1) a blocked action (`ADDON_ACTION_FORBIDDEN` / `ADDON_ACTION_BLOCKED`) that names SpellTuner is
recorded from the first registration the file makes, together with what the probe was doing at
that moment, and printed in a new `== blocked actions` section; (2) `COMBAT_LOG_EVENT_UNFILTERED`
is no longer registered at load: `/st probe clog` registers it on demand, so the load path cannot
trip the dialog on its own, and the next report shows whether that registration is what trips it;
(3) `== readings now`, and therefore the combat snapshot, reads the `C_Secrets` predicates and the
percent / missing / incoming / dead readings the kit lists, so the planner can see whether health
and power are secret always or only under a restriction, and `ADDON_RESTRICTION_STATE_CHANGED` is
counted with its payload; (4) the damage meter's per-spell rows show `combatSpellDetails` one level
deep; (5) the spells section prints bonus damage per school beside bonus healing, the saved record
keeps bonus damage and level, every changed description prints what it was and what it is now,
and Q1 is answered by a change in bonus healing, bonus damage or level; (6) Q6 waits for level 10;
(7) the Forever flavour is two TOCs, `SpellTuner_Mainline.toc` and its plain fallback
`SpellTuner.toc`, at version `1.0.0-alpha.1`. It is for the planner, who reads the next report, and
for the author, who runs it.

## Facts

Report lines are from `docs/probe/1.60.1_70009.md`: the **first report** (2026-09-27 23:28:30,
Healroot level 8, "Classic Beta PvP", out of combat, solo, no party, no target) and the **second
report** appended below it (23:40:55, after two `/reload`). EllesmereUI paths are relative to
`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/` (read-only reference, the
working Forever addon plan §1 names). The kit baseline is
`/tmp/claude-1000/-home-penek-projects-addons-ManaDemon--claude-worktrees-combat-log-design-arch-ffb907/febe8f34-418e-46fe-83b7-324d44e06666/scratchpad/forever_api.json`
(build 69893, 6,045 globals).

The TOCs (item 7)
- Q9 is answered: the first report prints `SPELLTUNER_TOC = Mainline`. With all four Forever TOCs
  installed, the client loaded `SpellTuner_Mainline.toc` ahead of the plain, `_Forever` and
  `_Vanilla` copies.
- `release.sh` packages every `SpellTuner*.toc` in the source root and the union of their load
  entries (`release.sh:124`, `:139-148`), so deleting two TOCs and their markers needs no change there.

The blocked-action dialog (items 1 and 2)
- At load the author saw "SpellTuner has been blocked from an action only available to the
  Blizzard UI" (the `ADDON_ACTION_FORBIDDEN` dialog, buttons Disable / Ignore) — the author, via the
  planner, 2026-09-27.
- The first report's `== events` lists all twenty registrations `ok`, `COMBAT_LOG_EVENT_UNFILTERED`
  included. A forbidden action does not raise a Lua error into `pcall`; the client fires
  `ADDON_ACTION_FORBIDDEN` with `(addonName, functionName)` and shows the dialog — the planner.
  `ADDON_ACTION_BLOCKED` carries the same two arguments. Whether the event reaches our frame while
  the offending call is still on the stack (so that "what the probe was doing" names it) is
  **UNKNOWN** — the `during=` field below measures it.
- EllesmereUI's comments tie the event to protected calls made from tainted code
  (`EllesmereUI/EllesmereUI_Kick.lua:90-95`, `EllesmereUIActionBars/EllesmereUIActionBars.lua:17744-17749`).
  EllesmereUI never registers `COMBAT_LOG_EVENT_UNFILTERED`: no `RegisterEvent` names it; its one
  mention is a handler branch that returns at once (`EllesmereUICooldownManager/EllesmereUICooldownManager.lua:10837`).
  Grep finds no use of `C_CombatLog.IsCombatLogRestricted` either. That registration at load is
  the prime suspect — the planner — and must be proven, not assumed.
- What `functionName` reads for a blocked `RegisterEvent`: **UNKNOWN**. The stub's
  `"Frame:RegisterEvent()"` below is a stand-in.

The secret question (item 3)
- Out of combat, solo, `UnitHealth(player)`, `UnitHealth(party1)`, `UnitHealthMax(party1)`,
  `UnitHealth(target)` and `UnitPower(player, 0)` all read `<secret>`, while `GetManaRegen()`,
  `C_ClassTalents.GetActiveConfigID()`, the damage meter's numbers and the aura table read plain
  values — first report, `== readings now`, `== talents`, `== damage meter`. So `IsSecret` is not
  misfiring on numbers.
- `C_Secrets.ShouldUnitStatsBeSecret`, `ShouldAurasBeSecret` and `ShouldCooldownsBeSecret` read
  `false`; every predicate that takes an argument raised with its usage string, among them
  `ShouldUnitHealthMaxBeSecret(unit)`, `ShouldUnitPowerBeSecret(unit [, powerType])` and
  `ShouldUnitPowerMaxBeSecret(unit [, powerType])` — first report, `== secrets now`.
- The kit baseline's `C_Secrets` also has `HasSecretRestrictions`, `GetPowerTypeSecrecy` and
  `CanCompareUnitTokens`, and its globals include `UnitHealthPercent`, `UnitHealthMissing`,
  `UnitPowerPercent`, `UnitGetIncomingHeals` and `UnitIsDeadOrGhost`. The argument shapes of the
  first three are **UNKNOWN**; a wrong shape prints the client's usage string, which is itself an
  answer.
- EllesmereUI reads health as a percentage through `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`,
  which its comment calls "secret-value safe" (`EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua:1413-1436`);
  mana through `UnitPowerPercent("player", Enum.PowerType.Mana, false, curve)`
  (`EllesmereUIAuraBuffReminders/EllesmereUIAuraBuffReminders.lua:5662`). Whether the percent
  functions return a plain number or a secret to addon code: **UNKNOWN** — the probe prints it.
- Whether health and power are secret for addon code **always** on this build, or only under a
  restriction state (the realm is PvP): **UNKNOWN** — the question this run exists to answer.
- `ADDON_RESTRICTION_STATE_CHANGED` carries `(restrictionType, state)`; LibSpecialization reads
  type 5 as the chat restriction and state 0 as inactive
  (`EllesmereUI/Libs/LibSpecialization/LibSpecialization.lua:654`). The probe registers it at load
  already (first report `ok ADDON_RESTRICTION_STATE_CHANGED`) but has no handler.

The damage meter (item 4)
- Out of combat the local source's per-spell rows carry `amountPerSecond`, `combatSpellDetails`
  (printed `<table>`), `creatureName`, `isAvoidable`, `isDeadly`, `overkillAmount`, `spellID` and
  `totalAmount`; the Overall session had three spells — first report, `== damage meter`.
- `combatSpellDetails` is one flat table with `unitName`, `unitClassFilename` and `specIconID`
  (`EllesmereUIDamageMeters/EllesmereUIDamageMeters.lua:1955-1962`, `:2022-2023`).

Q1, bonus damage, level (item 5)
- In the second report, after `/reload`, with bonus healing `0 -> 0`, the same level and no gear
  change, four spells were reported changed against the saved run: `339 Entangling Roots`,
  `8921 Moonfire`, `5176 Wrath`, `5177 Wrath`. The report prints only ids. The texts survive in the
  beta's SavedVariables (`WTF/Account/124250034#1/SavedVariables/`, read by the lead):
  `SpellTuner.lua.bak` holds the 23:28:30 record, `SpellTuner.lua` the 23:40:55 one:
  - 5176: `Causes 15 to 18 Nature damage` -> `Causes 17 to 20 Nature damage`
  - 5177: `Causes 22 to 27 Nature damage` -> `Causes 24 to 29 Nature damage`
  - 8921: `Burns the enemy for 9 to 11 Arcane damage and then an additional 12 Arcane damage over 9 sec.`
    -> `... 9 to 12 ... additional 13 ...`
  - 339: `causes 20 Nature damage over 12 sec.` -> `causes 21 Nature damage over 12 sec.`
  The heals (5185, 5186, 774) did not change.
- The author drank a +5 spell power elixir between the two runs and changed nothing else — the
  author, via the planner. So descriptions are dynamic: the elixir moved spell damage, which is why
  only damage spells changed. A bonus-damage line in the spells header would have shown it.
- `GetSpellBonusDamage` is present (first report `== functions`). The school argument, 2 Holy,
  3 Fire, 4 Nature, 5 Frost, 6 Shadow, 7 Arcane — the planner (the classic API's school numbering).
- Healroot is level 8 and has no +healing item — the planner. A level-up with no gear change is as
  good a test as a +healing item — the planner.

Q6 (item 6)
- At level 8 `C_SpecializationInfo.GetTalentInfo({tier=1, column=1})` returned `nil`, while
  `C_ClassTalents.GetActiveConfigID() = 5562168` and `C_Traits.GetConfigInfo(id)` returned a config
  with `treeIDs` — first report, `== talents`. Talents start at level 10 — the planner.

Q7
- Q7 is answered on 70009: SavedVariables came back after `/reload` (second report: `SpellTunerDB
  at load: table`, `previous session stamp: 2026-09-27 23:40:15`, `reports at load: 70009 (...)`,
  `Q7 answered`). That contradicts the kit's bug report (plan §1.4). The guard stays; it costs
  nothing.

The stub
- The forever stub keeps player health plain and party health secret only in combat (T0's stand-in).
  It does **not** mirror the first report's always-secret health: that is the open question, and
  both the plain and the secret path are already exercised.

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | changed, items 1-6 below | the probe |
| `SpellTuner_Mainline.toc` | `## Version: 1.0.0-alpha.1`, nothing else | the Forever TOC (Q9) |
| `SpellTuner.toc` | `## Version: 1.0.0-alpha.1`, nothing else | the plain fallback, identical to `_Mainline` apart from its marker line `Client\TOC_Plain.lua` |
| `SpellTuner_Forever.toc`, `SpellTuner_Vanilla.toc`, `Client/TOC_Forever.lua`, `Client/TOC_Vanilla.lua` | **`git rm`** | Q9 answered; they are dead |
| `tools/wowstub.lua` | changed, below | the forever profile |
| `tools/probecheck.lua` | changed, below | the probe's suite |
| `docs/tasks/T0c-probe-secrets.md` | Report section only | your report |

Unchanged, and checked: `Client/API.lua`, `Client/TOC_Mainline.lua`, `Client/TOC_Plain.lua`,
`release.sh`, `tools/harness.lua`, `SpellTuner_TBC.toc`.

### `Client/Probe.lua`

**1. Blocked actions are recorded.**
- A new local `doing`, a string that says what the probe is doing. Its values, exactly:
  - `load` — from the frame's creation to the end of the file, whenever no registration is in flight;
  - `register:<EVENT>` — while `pcall(frame.RegisterEvent, frame, <EVENT>)` runs, for every
    registration made at load (the two listeners, `ADDON_LOADED` and every `EVENTS` entry);
  - `ADDON_LOADED` — inside our ADDON_LOADED handler;
  - `clog` — while `/st probe clog` registers the combat log event (item 2);
  - `run` — inside `Run()`;
  - `snapshot` — inside the timed combat snapshot;
  - `idle` — otherwise. The file's last statement sets it.
  Each place that sets it restores the value it replaced when it is done.
- At file scope, in this order: create the frame and set its `OnEvent` script (as today); register
  `ADDON_ACTION_FORBIDDEN`, then `ADDON_ACTION_BLOCKED`, each under `pcall`, recording `ok` or
  `throws <error: ...>` for each. **These are the first two `RegisterEvent` calls the file makes.**
  Then `ADDON_LOADED`, then `EVENTS`, as today.
- Both events get a handler that knows which event it is handling (for example two small closures
  in `HANDLERS`; the dispatcher stays `pcall(handler, ...)`). The handler keeps the event only when
  `Fmt(addonName) == Esc(ADDON_NAME)`: never a raw comparison, and nothing at all for another
  addon. It counts per `(event, phase, doing, Fmt(functionName))`, first-seen order kept.
  `addonName` is printed through `Fmt`.
- A new section `== blocked actions`, **right after `== events`**:
  ```
  == blocked actions
  listening: ADDON_ACTION_FORBIDDEN <ok | throws <error: ...>>, ADDON_ACTION_BLOCKED <ok | throws <error: ...>>
  <EVENT> phase=<phase> during=<doing> addon=<Fmt(addonName)> function=<Fmt(functionName)> n=<count>
  ```
  One record line per key, in first-seen order. When there are none, the single line `none` stands
  in their place.

**2. The combat log event moves off the load path.**
- `COMBAT_LOG_EVENT_UNFILTERED` leaves `EVENTS`, which keeps its other nineteen entries in their order.
- The slash handler reads the first two words. `probe clog` (case-insensitive) calls a new local
  `RegisterClog()`; `probe` followed by anything else, or by nothing, calls `Run()` as today;
  anything else prints `SpellTuner probe: type /st probe (or /st probe clog)`.
- `RegisterClog()` sets `doing = "clog"`, calls
  `pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")`, restores `doing`, keeps the
  outcome (an `ok` flag and, when it raised, `"<error: " .. Fmt(err) .. ">"`) and overwrites any
  earlier one. It prints exactly one chat line:
  - `SpellTuner probe: COMBAT_LOG_EVENT_UNFILTERED registered without a Lua error. If the blocked-action dialog appeared, click Ignore (not Disable), then type /st probe.`
  - or `SpellTuner probe: registering COMBAT_LOG_EVENT_UNFILTERED raised <error: ...>. Type /st probe.`
  It does not run the probe: the forbidden event may arrive after the call returns.
- `== events` prints one line for the combat log event after the nineteen `EVENTS` lines:
  - before any `clog`: `COMBAT_LOG_EVENT_UNFILTERED not registered at load (type /st probe clog)`
  - after it: `ok COMBAT_LOG_EVENT_UNFILTERED (by /st probe clog)`, or
    `throws COMBAT_LOG_EVENT_UNFILTERED <error: ...> (by /st probe clog)`.
- The combat log event gets no handler.

**3. The secret question is measured.**
- `ReadingsLines` appends these eighteen lines after its ten, in this order, each
  `<label> = <Show(...)>`. The labels are exact:
  ```
  C_Secrets.HasSecretRestrictions() =                Show("C_Secrets.HasSecretRestrictions")
  C_Secrets.ShouldUnitHealthMaxBeSecret(player) =    Show("C_Secrets.ShouldUnitHealthMaxBeSecret", "player")
  C_Secrets.ShouldUnitPowerBeSecret(player) =        Show("C_Secrets.ShouldUnitPowerBeSecret", "player")
  C_Secrets.ShouldUnitPowerMaxBeSecret(player) =     Show("C_Secrets.ShouldUnitPowerMaxBeSecret", "player")
  C_Secrets.GetPowerTypeSecrecy(0) =                 Show("C_Secrets.GetPowerTypeSecrecy", 0)
  C_Secrets.CanCompareUnitTokens(player, player) =   Show("C_Secrets.CanCompareUnitTokens", "player", "player")
  UnitHealthMax(player) =                            Show("UnitHealthMax", "player")
  UnitPowerMax(player, 0) =                          Show("UnitPowerMax", "player", 0)
  UnitHealth(player, true) =                         Show("UnitHealth", "player", true)
  UnitHealthPercent(player) =                        Show("UnitHealthPercent", "player")
  UnitHealthPercent(player, true) =                  Show("UnitHealthPercent", "player", true)
  UnitHealthMissing(player) =                        Show("UnitHealthMissing", "player")
  UnitPowerPercent(player, 0) =                      Show("UnitPowerPercent", "player", 0)
  UnitGetIncomingHeals(player) =                     Show("UnitGetIncomingHeals", "player")
  UnitIsDeadOrGhost(player) =                        Show("UnitIsDeadOrGhost", "player")
  UnitHealth(party1, true) =                         Show("UnitHealth", "party1", true)
  UnitHealthPercent(party1) =                        Show("UnitHealthPercent", "party1")
  UnitHealthPercent(party1, true) =                  Show("UnitHealthPercent", "party1", true)
  ```
  `UnitHealth(party1)` and `UnitHealthMax(party1)` are in the section already and are not
  repeated. With the last three lines, party1 has the same UnitHealth / UnitHealthMax /
  UnitHealthPercent trio as the player.
- `TakeCombatSnapshot` copies `ReadingsLines`, so the snapshot carries the same eighteen and the
  in-combat and out-of-combat lines can be read side by side. Nothing else changes there.
- `ADDON_RESTRICTION_STATE_CHANGED` (already registered) gets a handler. The payload is every
  argument (`select("#", ...)`), each through `Fmt`, joined with `", "`, or `nothing` when there
  are none. It counts per `<phase> <payload>`, first-seen order kept. The counts print in
  `== events seen this session` after the `UNIT_SPELLCAST_SENT` lines:
  `ADDON_RESTRICTION_STATE_CHANGED <phase> payload=<payload> n=<count>`. That section prints `none`
  only when all three kinds are empty.

**4. The damage meter goes one level deeper.**
- `Describe(v, depth)`: `depth` is optional, and `nil` or `1` behaves exactly as today. At depth
  above 1, a field whose value is a non-secret table renders as `Describe(value, depth - 1)`; every
  other field renders through `Fmt` as today. The 24-key cap applies at every level, and the whole
  walk stays inside the one `pcall`.
- In `SessionBlock` the local source's spell rows render with `Describe(sp, 2)`. The local source
  row and every other `Describe` call keep depth 1.
- The literal `5` that caps the spell rows becomes one file-level constant (for example
  `SPELL_ROWS = 5`), used by both sessions. The source-row cap is not touched.

**5. Spells, the previous run and Q1.**
- **Bonus damage.** One string built from `Show("GetSpellBonusDamage", school)` for schools 2 to 7
  in that order, named Holy, Fire, Nature, Frost, Shadow, Arcane:
  `Holy=<2> Fire=<3> Nature=<4> Frost=<5> Shadow=<6> Arcane=<7>`. The spells header becomes
  `== spells (bonus healing <Show("GetSpellBonusHealing")>, bonus damage <that string>)`.
- **Level.** `First("UnitLevel", "player")`.
- The saved record gains `damage = <the bonus damage string>` and `level = <the level string>`,
  beside `bonus`.
- The `previous:` line becomes
  `previous: <this session|saved> at <stamp>, bonus healing <old> -> <new>, bonus damage <old> -> <new>, level <old> -> <new>`.
  Each old value goes through `Fmt` as the old bonus does today, so a record written before T0c
  prints `nil`.
- **What changed.** Every changed spell still prints `changed <id> <name>`. The first 12 changed
  spells, in the order found, each print two more lines directly under it:
  ```
  changed <id> <name>
    was: <the previous run's stored text>
    now: <this run's text>
  ```
  When more than 12 changed, one line follows the changed block:
  `was/now shown for the first 12 of <c> changed spells`. Then come `no description changed`
  (when none did) and `<k> not comparable (unreadable on one run)`, as today.
  **Escape once.** Both texts are printed exactly as stored. They went through `Esc` once, when
  they were read from the client (`SpellWalk` stores `Esc(desc)` and the save writes that same
  string). A second `Esc` would print `||` as `||||` and `\226` as `\\226`.
  `<c>` in Q1 counts every changed spell, with or without was/now.
- **Q1.** Answered exactly when there is a previous run, at least one comparable description
  changed, and at least one of the three pairs (bonus healing, bonus damage, level) reads on both
  runs and differs. For bonus healing and level, "reads" means `Readable`. For the bonus damage
  string it means `Readable` and containing none of `<`, `=nil`, `=nothing`, so one unreadable
  school makes the pair unreadable. The line is exactly:
  `Q1 answered: <c> of <m> spell descriptions changed when bonus healing went <old> -> <new>, bonus damage <old> -> <new>, level <old> -> <new>`
  Otherwise the to-do line reads exactly:
  `Q1 to do: turn on show all ranks in the spellbook (the arrow at its top right), then change your bonus healing or bonus damage (put on or take off a +healing item, drink a spell power elixir, or take a buff that changes a number in the spells header) or gain a level with no gear change (as good a test when you have no +healing item), then type /st probe again in the same session`

**6. Q6.** `TalentsLines` also returns the rendered result of the `{tier=1, column=1}` call. Q6
is answered when that string starts with `{`, and the line stays `Q6 answered: see == talents`.
Otherwise it reads exactly:
`Q6 to do: talents start at level 10, so C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) is answered at level 10 or above; type /st probe again then`

### The TOCs

- `SpellTuner_Mainline.toc` and `SpellTuner.toc`: `## Version: 1.0.0-alpha.0` becomes
  `## Version: 1.0.0-alpha.1`. No other line changes. The two stay identical apart from their
  marker line.
- `git rm SpellTuner_Forever.toc SpellTuner_Vanilla.toc Client/TOC_Forever.lua Client/TOC_Vanilla.lua`
  — those four paths, by name, and nothing else.

### `tools/wowstub.lua`

1. `UseProfile("forever")` sets `S.toc = "SpellTuner_Mainline.toc"`. The comment above the
   top-level `S.toc` says so.
2. `FOREVER_EVENTS` gains `ADDON_ACTION_FORBIDDEN` and `ADDON_ACTION_BLOCKED`.
   `COMBAT_LOG_EVENT_UNFILTERED` stays out, so registering it keeps raising in the stub (T0's
   stand-in). Its comment gains one line: on 70009 the client accepted the registration (the first
   report's `ok`), and whether it trips the blocked dialog is what `clog` measures.
3. `FrameMT:RegisterEvent(e)`:
   - it first appends `e` to `self.attempts`, a list created on first use. It does this in every
     profile, and no TBC suite reads the field;
   - under the forever profile, when `S.forbidOnRegister` is a table holding a string for `e`, it
     does not register `e`, does not raise, and fires
     `S.Fire("ADDON_ACTION_FORBIDDEN", S.addonName, <that string>)` at once. This is a stand-in for
     the suspicion in Facts, not a fact, and the comment says so;
   - otherwise it behaves as today. The forbid test comes before the unknown-event raise, so a
     forbidden `COMBAT_LOG_EVENT_UNFILTERED` does not raise.
4. `S.Load(files, addonName, MD)` sets `S.addonName = addonName` before loading.
5. In `UseProfile("forever")`:
   - `S.bonusDamage = {}`; `GetSpellBonusDamage(school)` returns `S.bonusDamage[school] or 0`.
   - `S.descShift = 0`. 774's description amount becomes `32 + S.bonusHealing + S.descShift`. This
     is a stand-in for a description that moved with a level-up, not a claim about the client.
   - 5176's description becomes `"Causes " .. (13 + n) .. " to " .. (16 + n) .. " Nature damage to the target."`
     with `n = S.bonusDamage[4] or 0`. At 0 it reads exactly as today.
   - `function S.AddSpell(id, name, rank, descFn)` puts `id` in the first free spellbook slot from 6
     on, with that name, subtext and description function.
   - `C_SpecializationInfo.GetTalentInfo(<table>)` returns `nil` while `S.level < 10` (what the
     client answered at level 8) and the table otherwise. The number-argument error is unchanged.
   - New globals, with exactly these answers:
     - `UnitHealthPercent(u, usePredicted, curve)`: `S.Secret()` when `S.inCombat and u ~= "player"`;
       `nil` for an unknown unit; else `hp / hpMax * 100`.
     - `UnitHealthMissing(u)`: the same gate; else `hpMax - hp`.
     - `UnitPowerPercent(u, powerType)`: `S.mana / S.manaMax * 100` for `"player"`, `nil` otherwise.
     - `UnitGetIncomingHeals(u, healer)`: `0` for a known unit, `nil` otherwise.
     - `UnitIsDeadOrGhost(u)`: `false`.
   - `C_Secrets` keeps its three entries and gains six. Each raises `"bad argument #1"` when its
     first argument is `nil`, as the client does:
     `HasSecretRestrictions()` -> `S.inCombat` (no argument, never raises);
     `ShouldUnitHealthMaxBeSecret(u)` -> `S.inCombat and u ~= "player"`;
     `ShouldUnitPowerBeSecret(u, pt)` -> `false`; `ShouldUnitPowerMaxBeSecret(u, pt)` -> `false`;
     `GetPowerTypeSecrecy(pt)` -> `0`; `CanCompareUnitTokens(a, b)` -> `true` (raises when either is `nil`).
   - `C_DamageMeter`: every `combatSpells` row carries
     `combatSpellDetails = { unitName = "Tankname", unitClassFilename = "WARRIOR", specIconID = 0 }`.
     `GetCombatSessionSourceFromType(st, ...)` returns today's one row (774, 1000) for the Current
     session and six rows when `st == Enum.DamageMeterSessionType.Overall`: spellIDs 774, 5185, 1058,
     5186, 8936, 740 with `totalAmount` 1000, 900, 800, 700, 600, 500.
6. Nothing a TBC suite can observe changes. The sixteen tails stay identical.

### `tools/probecheck.lua`

- Steps 2, 3 and 4 load `{ "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }`
  (`Client/TOC_Forever.lua` is gone).
- A helper that counts the `COMBAT_LOG_EVENT_UNFILTERED` entries across every frame's `attempts`
  in the current stub's `S.allFrames`, and one that finds the probe's frame (the frame whose
  `attempts` contain `ADDON_LOADED`).
- **Step 2**, added to the existing script in this order:
  - right after run 1: fire `ADDON_RESTRICTION_STATE_CHANGED(5, 1)` twice;
  - after the timers run (in combat): fire `ADDON_RESTRICTION_STATE_CHANGED(5, 0)` and
    `ADDON_ACTION_BLOCKED("SpellTuner", "Frame:Show()")`;
  - after `S.bonusHealing = 50` (out of combat): fire `ADDON_ACTION_FORBIDDEN("SpellTuner", "UNKNOWN()")`
    twice and `ADDON_ACTION_FORBIDDEN("EllesmereUI", "CastSpellByName()")` once; count the combat
    log attempts (`clogBefore2`); `Do(SlashCmdList.SPELLTUNER, "probe clog")`; count again
    (`clogAfter2`); then run 3 as today.
  Every fire goes through `Do`.
- **Step 5 (new): Healroot levels up and tries the combat log.** Fresh stub, `UseProfile("forever")`,
  `S5.level = 9`,
  `S5.forbidOnRegister = { UNIT_FLAGS = "Frame:RegisterEvent()", COMBAT_LOG_EVENT_UNFILTERED = "Frame:RegisterEvent()" }`,
  `SpellTunerDB = nil`, a chat capture (`chat5`), load into `MD5`, fire `ADDON_LOADED "SpellTuner"`,
  count the combat log attempts (`clogBefore5`), `local okA, reportA = pcall(MD5.Probe.Run)`,
  `pcall(SlashCmdList.SPELLTUNER, "probe clog")`, `S5.level = 10`, `S5.descShift = 3`,
  `local okB, reportB = pcall(MD5.Probe.Run)`. Do **not** call `AddTraits` here, because
  "the probe adds no global but its own" runs after this step.
- **Step 6 (new): a spell power elixir.** Fresh stub, `UseProfile("forever")`; for `i = 1, 13`,
  `S6.AddSpell(900000 + i, "Stub Bolt", "Rank " .. i, function() return "Causes " .. (10 + i + (S6.bonusDamage[4] or 0)) .. " Nature damage to the target." end)`;
  `SpellTunerDB = nil`; load into `MD6`; fire `ADDON_LOADED "SpellTuner"`;
  `local okC, reportC = pcall(MD6.Probe.Run)`; `S6.bonusDamage[4] = 5`;
  `local okD, reportD = pcall(MD6.Probe.Run)`; keep `SpellTunerDB.probe.reports["70009"]` as `recD`.
- **The release** (for "the build ships three TOCs"): run
  `bash "<ROOT>/release.sh" --out "<ROOT>/tools/.lua/probecheck-release" 2>&1` through `io.popen`,
  keep its output, then list `<out>/SpellTuner/*.toc` (through `io.popen("ls ...")`) and test file
  existence with `io.open`. `tools/.lua/` is gitignored.

## Rules

T0's and T0b's rules stand unchanged: client calls in `Client/` only; no arithmetic, comparison, `#`
or table key on a client value before `IsSecret` (and after it only `type()`, `Fmt`, `== <literal>`
and string functions on a string); everything from the client under `pcall`, the event handlers
through `pcall`; every rendered string ASCII with no bare `|`, every client string through `Esc`;
`BackdropTemplate` on the copy box; the multi-return trap (pack `pcall` returns with
`select("#", ...)`, assign `gsub` to a local, never `a and f() or b`); no new globals beyond T0's
list; comments say why. The ones that bite here:

- **The addon-name test** goes through `Fmt(addonName) == Esc(ADDON_NAME)`. **Q6** reads the
  rendered string's first character, never `UnitLevel` as a number. The **level** is compared as
  rendered strings. The **restriction payload** is only ever passed to `Fmt`.
- **Escape once**: `was:` / `now:` print stored text as stored (item 5).
- **Tests first.** Write the stub pieces and the new assertions, run probecheck against today's
  `Client/Probe.lua` and TOCs, and see each new assertion **fail**. Only then change the probe and
  the TOCs. One exception: "the damage meter prints at most 5 spells a session" passes on today's
  probe once the stub has six rows, because the cap already exists and this task only names it.
  Say in the report which assertions you saw fail. Never weaken an assertion to make it pass.
- Build large edits in pieces: no single tool call above about 150 lines of new text.
- **Git.** The planner is editing `docs/FOREVER-PLAN.md`, `docs/ROADMAP-FOREVER.md`,
  `docs/HISTORY.md`, `docs/TESTING.md`, `CLAUDE.md` and `docs/probe/` in this same tree. Do not
  open them for writing. The only git command that changes anything is the one `git rm` above,
  with the four paths named. Never `git add -A` or `git add .`, never `git stash`, never
  `git checkout -- <path>` or `git reset`. Do not commit.

## Acceptance

1. `tools/run.sh tools/probecheck.lua` ends with `57 ok, 0 failed`: the 41 existing names
   verbatim and the 16 new ones below.

   **Existing assertions whose conditions change** (names verbatim, nothing else weakened):
   - "registering a bad event is caught": report1 has
     `COMBAT_LOG_EVENT_UNFILTERED not registered at load (type /st probe clog)` and `ok UNIT_COMBAT`,
     and report3 has `throws COMBAT_LOG_EVENT_UNFILTERED <error:` and `(by /st probe clog)`. The
     stub still refuses the event, and it is now `clog` that tries it.
   - "the report sections are in order": `HEADERS_IN_ORDER` gains `"== blocked actions\n"` right
     after `"== events\n"`, fifteen headers in all, checked on report1 **and** reportB.
   - "the report prints the TOC that loaded": `SPELLTUNER_TOC = Mainline` in report1 and report3.
   - "the to-do list names what is left": `Q9 answered: SPELLTUNER_TOC = Mainline` in place of
     `Forever`; the rest unchanged.
   - "the probe never raises": also every call in steps 5 and 6 (the loads, the ADDON_LOADED fires,
     `okA`, the clog `pcall`, `okB`, `okC`, `okD`).
   - "the report is ASCII with no bare pipe": also reportA, reportB, reportC, reportD.

   **New assertions** (names verbatim):
   1. "blocked and forbidden actions naming us are recorded": the text of report1 between
      `\n== blocked actions\n` and `\n== secrets now\n` is exactly
      `listening: ADDON_ACTION_FORBIDDEN ok, ADDON_ACTION_BLOCKED ok\nnone`. report3 has
      `ADDON_ACTION_BLOCKED phase=combat during=idle addon=SpellTuner function=Frame:Show() n=1` and
      `ADDON_ACTION_FORBIDDEN phase=ooc during=idle addon=SpellTuner function=UNKNOWN() n=2`.
   2. "a blocked action naming another addon is ignored": report3's text between
      `\n== blocked actions\n` and `\n== secrets now\n` exists and contains neither `EllesmereUI`
      nor `CastSpellByName`.
   3. "COMBAT_LOG_EVENT_UNFILTERED is not registered at load, only by clog": `clogBefore2 == 0`,
      `clogAfter2 == 1`, `clogBefore5 == 0`; chat2 contains
      `registering COMBAT_LOG_EVENT_UNFILTERED raised`.
   4. "a blocked action at load names the registration that caused it": reportB has
      `ADDON_ACTION_FORBIDDEN phase=ooc during=register:UNIT_FLAGS addon=SpellTuner function=Frame:RegisterEvent() n=1`,
      `ADDON_ACTION_FORBIDDEN phase=ooc during=clog addon=SpellTuner function=Frame:RegisterEvent() n=1`
      and `ok COMBAT_LOG_EVENT_UNFILTERED (by /st probe clog)`. The step-5 probe frame's
      `attempts[1] == "ADDON_ACTION_FORBIDDEN"` and `attempts[2] == "ADDON_ACTION_BLOCKED"`. chat5
      contains `registered without a Lua error`.
   5. "the secret readings are taken out of combat and in the snapshot": the eighteen labels of
      item 3 appear in order in report1 between `\n== readings now\n` and `\n== combat snapshot\n`,
      and in report2 between `\n== combat snapshot\n` and `\n== events seen this session\n`. The
      first segment has `C_Secrets.HasSecretRestrictions() = false` and
      `UnitHealthPercent(party1) = 100`. The second has `C_Secrets.HasSecretRestrictions() = true`
      and `UnitHealthPercent(party1) = <secret>`.
   6. "the restriction state event is counted with its payload": report3 has
      `ADDON_RESTRICTION_STATE_CHANGED ooc payload=5, 1 n=2` and
      `ADDON_RESTRICTION_STATE_CHANGED combat payload=5, 0 n=1`.
   7. "the damage meter expands combatSpellDetails one level": report3 has
      `spell 1 = {combatSpellDetails={specIconID=0, unitClassFilename=WARRIOR, unitName=Tankname}, spellID=774, totalAmount=1000}`
      and still `local source = {amountPerSecond=41, isLocalPlayer=true, sourceGUID=Player-1, totalAmount=1234}`.
   8. "the damage meter prints at most 5 spells a session": report3's text from
      `session Overall HealingDone` to `\n== saved variables\n` has `combatSpells=6` and
      `  spell 5 = `, and no `  spell 6 = `. (It passes before the probe change; see Rules.)
   9. "Q1 is answered by a level change": reportA has `Q1 to do`. reportB has `, level 9 -> 10` on
      its `previous:` line and
      `Q1 answered: 1 of 4 spell descriptions changed when bonus healing went 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0, level 9 -> 10`.
   10. "Q6 waits for level 10": reportA has `Q6 to do: talents start at level 10`; reportB has
       `Q6 answered: see == talents`.
   11. "the build ships three TOCs": the release output contains `Built `. The `.toc` files in
       `<out>/SpellTuner/` are exactly `SpellTuner.toc`, `SpellTuner_Mainline.toc` and
       `SpellTuner_TBC.toc`. `<out>/SpellTuner/Client/TOC_Mainline.lua` and `TOC_Plain.lua` exist;
       `TOC_Forever.lua` and `TOC_Vanilla.lua` do not; neither do `<ROOT>/SpellTuner_Forever.toc`
       and `<ROOT>/SpellTuner_Vanilla.toc`.
   12. "the Forever TOCs are 1.0.0-alpha.1 and differ only in their marker": `SpellTuner.toc` and
       `SpellTuner_Mainline.toc` both carry `## Version: 1.0.0-alpha.1`. Read line by line with CR
       stripped, they have the same number of lines and differ on exactly one, which is
       `Client\TOC_Plain.lua` in the first and `Client\TOC_Mainline.lua` in the second. report1
       starts with `SpellTuner probe 1.0.0-alpha.1 -- `.
   13. "a changed description prints what it was and what it is now": report3 has
       `changed 774 Rejuvenation\n  was: Heals the target for 32 over 12 sec.\n  now: Heals the target for 82 over 12 sec.`
   14. "was and now are shown for the first 12 changed spells, the rest counted": in reportD, the
       text between `\n== spells against the previous run\n` and `\n== talents\n` holds exactly 14
       lines starting `changed `, exactly 12 starting `  was: ` and 12 starting `  now: `, the line
       `was/now shown for the first 12 of 14 changed spells`, and
       `changed 5176 Wrath\n  was: Causes 13 to 16 Nature damage to the target.\n  now: Causes 18 to 21 Nature damage to the target.`
   15. "the spells header shows bonus damage per school": reportD has
       `== spells (bonus healing 0, bonus damage Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0)`
       and `bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0`.
       `recD.damage == "Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0"` and `recD.level == "64"`.
   16. "Q1 is answered by a change in bonus damage": reportC has `Q1 to do`; reportD has
       `Q1 answered: 14 of 17 spell descriptions changed when bonus healing went 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0, level 64 -> 64`.

2. The sixteen TBC suites print exactly these tails:
   ```
   for s in simcheck reccheck replaycheck replayui runcheck reviewui navui dashui regencheck simwindow solvercheck timeline spelltip practice practiceui migrate; do tools/run.sh tools/$s.lua | tail -1; done
   ```
   simcheck `... -> PASS`; reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
   navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48,
   practice 74, practiceui 49, migrate 7, each `ok, 0 failed`.
3. `tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua tools/probecheck.lua` is clean.
4. `git status --short` shows your changes as exactly `M Client/Probe.lua`, `M SpellTuner.toc`,
   `M SpellTuner_Mainline.toc`, `D SpellTuner_Forever.toc`, `D SpellTuner_Vanilla.toc`,
   `D Client/TOC_Forever.lua`, `D Client/TOC_Vanilla.lua`, `M tools/wowstub.lua`,
   `M tools/probecheck.lua` and the task file. Lines for the planner's files (see Rules) are theirs;
   leave them alone and list them.
5. Paste into the Report: the full probecheck output; the assertions you saw fail before the
   probe and TOC change; the sixteen tails; the `luac` command and its output;
   `find tools/.lua/probecheck-release/SpellTuner -name '*.toc' | sort`; from report3 the text from
   `== events` to `== secrets now`; report1's `== readings now` and report2's `== combat snapshot`;
   reportB's `== blocked actions` and `== to do`; reportD from `== spells (` to `== talents`; and
   `git status --short`.

## Out of scope

- `CLAUDE.md`, and every `docs/*.md` other than this task file's Report section, including
  `docs/probe/`, `docs/FOREVER-PLAN.md`, `docs/ROADMAP-FOREVER.md`, `docs/HISTORY.md`,
  `docs/TESTING.md`, `docs/TOOLS.md` and `docs/REFERENCES-FOREVER.md`. Where they still name the
  deleted TOCs, list them in the report.
- The TBC addon: `Core.lua`, `Engine/`, `UI/`, `Data/`, `Verify.lua`, `Integrations/`,
  `SpellTuner_TBC.toc`, `tools/harness.lua`.
- `Client/API.lua`, `release.sh`, the `Makefile`.
- Any attempt to read health or power through arithmetic, or to derive a number from a secret.
- A handler that counts combat log deliveries; `C_RestrictedActions.*` and `canaccesssecrets` (in
  the baseline, not asked for); new `FUNCTIONS` entries.
- Cosmetics T0b left alone: the double-escaped old bonus string in the `previous:` line, and the
  trailing `, ` after `IsDamageMeterAvailable() = true`.
- Any existing suite's assertions other than the six condition changes above.
- Commits.

## Report

Tests were written first: `tools/wowstub.lua` and `tools/probecheck.lua` were changed to their
finished T0c shape (new stub pieces, the 16 new assertions, the six condition changes, steps 5/6,
the release step) before `Client/Probe.lua` or the TOCs were touched, then `tools/run.sh
tools/probecheck.lua` was run against the **unmodified** `Client/Probe.lua` and TOCs. That run
produced 36 ok, 21 failed (list below) — matching the task's expectation that the new/changed
assertions fail on today's code except "the damage meter prints at most 5 spells a session" and
the talent-branch one, which the task itself says can pass immediately. `Client/Probe.lua` was
then written to the spec, the TOC versions bumped, and the four dead files removed with `git rm`,
after which the suite reached 57 ok, 0 failed, with every existing assertion name kept verbatim.

**`Client/Probe.lua`.**
- New session-state local `doing` (`"load"` initially), plus `blockedCounters`/`blockedOrder`,
  `restrictionCounters`/`restrictionOrder`, `actionForbiddenOutcome`/`actionBlockedOutcome`,
  `clogOutcome`.
- `Describe(v, depth)` gained the optional depth parameter (default 1): above depth 1, a field
  whose value is a non-secret table renders via `Describe(value, depth - 1)` instead of `Fmt`. The
  24-key cap and the one `pcall` are unchanged. `SessionBlock`'s spell-row line now calls
  `Describe(sp, 2)`; the source-row cap and every other `Describe` call stay at depth 1. The spell
  row cap became the file-level `SPELL_ROWS = 5` constant, used by both sessions; the source-row
  cap's literal `5` is untouched, per the task.
- `BumpRestriction(currentPhase, ...)` and `BumpBlocked(event, addonName, functionName)` added
  beside `BumpCombat`/`BumpSent`. `BumpBlocked` keeps a record only when `Fmt(addonName) ==
  Esc(ADDON_NAME)` (never a raw comparison) and counts by `(event, phase, doing, function)`,
  first-seen order.
- `EVENTS` lost `COMBAT_LOG_EVENT_UNFILTERED` (19 entries now, comment says why). A new
  `EventsSummaryLines()` tail line reports the combat log's own status from `clogOutcome`: "not
  registered at load (type /st probe clog)" before any `clog`, else `ok`/`throws ... (by /st probe
  clog)`.
- New `BlockedActionsLines()` — the `listening:` line from the two outcome locals, then one
  formatted line per blocked/forbidden record in first-seen order, or `none`. Printed as a new `==
  blocked actions` section in `Run()`, immediately after `== events`.
- `ReadingsLines()` gained the 18 lines of item 3, in the exact order and with the exact labels
  specified, appended after the existing 10; `TakeCombatSnapshot` needed no change since it already
  copies whichever lines `ReadingsLines()` returns.
- `HANDLERS` gained three closures: `OnRestrictionStateChanged` (packs every argument through `Fmt`
  and joins with `", "`, or `nothing`), `OnAddonActionForbidden` and `OnAddonActionBlocked` (each
  calls `BumpBlocked` with its own event name literal). `EventsSeenLines()` prints the restriction
  counters after the `UNIT_SPELLCAST_SENT` lines.
- New `BonusDamageString()` (schools 2-7, `Show("GetSpellBonusDamage", n)`, space-joined
  `Holy=... Fire=... ...`) and `BonusDamageReadable(s)` (`Readable` plus none of `<`, `=nil`,
  `=nothing`). The spells header became `== spells (bonus healing <bonus>, bonus damage <string>)`;
  `First("UnitLevel", "player")` is read into `levelStr`. Both are threaded into
  `AgainstPreviousLines` and the saved record (`damage = damageStr, level = levelStr`, beside
  `bonus`).
- `AgainstPreviousLines` rewritten: the `previous:` line now reports all three pairs (bonus
  healing, bonus damage, level), each old value through `Fmt` as before (so a pre-T0c record prints
  `nil` for the two new fields). Each changed spell keeps its stored `was`/`now` text; the first 12
  print two extra lines (`  was: ...` / `  now: ...`, no re-`Esc`, since the stored strings were
  already escaped once on read/save); past 12 a summary line `was/now shown for the first 12 of <c>
  changed spells` is added. `no description changed` / the not-comparable line are unchanged.
- `TalentsLines()` now also returns the rendered `{tier=1, column=1}` result string, so `Run()` can
  test it directly (`tierColumnShow:sub(1,1) == "{"`) for Q6 without re-deriving it from the lines.
- Q1's condition became: a previous run exists, at least one comparable description changed, and
  at least one of the three pairs (bonus healing / level via `Readable`, bonus damage via
  `BonusDamageReadable`) reads on both runs and differs. The answered/to-do wordings are the exact
  strings the task specifies.
- Q6 now reads `Q6 answered: see == talents` only when the tier/column call rendered a table
  (starts with `{`); otherwise the exact `Q6 to do: talents start at level 10, ...` line.
- Load-time block rewritten: the frame and its `OnEvent` script are created first; then
  `ADDON_ACTION_FORBIDDEN` and `ADDON_ACTION_BLOCKED` are registered under their own `pcall`s (the
  file's first two `RegisterEvent` calls), each recording `ok` / `throws <error: ...>` into the two
  outcome locals; then `ADDON_LOADED` under `doing = "register:ADDON_LOADED"`; then the `EVENTS`
  loop under `doing = "register:" .. event` per iteration, each save/restored. A new local
  `RegisterClog()` sets `doing = "clog"`, `pcall`s the combat-log registration, restores `doing`,
  overwrites `clogOutcome`, and prints exactly one of the two specified chat lines — it never calls
  `Run()`. The slash handler now reads the first two words: `probe clog` (case-insensitive) calls
  `RegisterClog()`, `probe` alone or followed by anything else calls `Run()`, anything else prints
  the two-line usage message. `OnAddonLoaded` was restructured from an early return into an `if
  loadedName == ADDON_NAME then ... end` block wrapped in `doing = "ADDON_LOADED"` / restore, so the
  no-op path for another addon's load is covered too. `Run()` itself is wrapped in `doing = "run"` /
  restore (a plain save-and-restore, since `Run()` never raises and has a single exit). The file's
  very last statement is `doing = "idle"`.
- **A bug caught by the suite before it ran clean**: the first draft of `Run()`'s `doing = "run"`
  wrap set `doing` at the top but never restored it before `return report`, so every direct-fired
  event after the first `Run()` call read `during=run` instead of `during=idle`. Caught by "blocked
  and forbidden actions naming us are recorded" (56 ok / 1 failed on that run); fixed by adding
  `doing = savedDoing` right before `return report`.

**`SpellTuner.toc` / `SpellTuner_Mainline.toc`.** `## Version: 1.0.0-alpha.0` -> `1.0.0-alpha.1`,
no other line changed; they still differ only in their marker line
(`Client\TOC_Plain.lua` vs `Client\TOC_Mainline.lua`).

**`git rm SpellTuner_Forever.toc SpellTuner_Vanilla.toc Client/TOC_Forever.lua
Client/TOC_Vanilla.lua`** — those four paths only, nothing else staged.

**`tools/wowstub.lua`.** `S.toc` inside `UseProfile("forever")` now points at
`SpellTuner_Mainline.toc` (comment on the top-level default updated to match). `FOREVER_EVENTS`
gained `ADDON_ACTION_FORBIDDEN`/`ADDON_ACTION_BLOCKED`; `COMBAT_LOG_EVENT_UNFILTERED` stays out.
`FrameMT:RegisterEvent` now appends every attempted event name to `self.attempts` (created on first
use, in every profile) before anything else, then — under the forever profile, when
`S.forbidOnRegister[e]` holds a string — skips registering, fires
`S.Fire("ADDON_ACTION_FORBIDDEN", S.addonName, thatString)` and returns, before the existing
unknown-event raise. `S.Load` now sets `S.addonName` before loading. Inside `UseProfile("forever")`:
`S.bonusDamage = {}` / `GetSpellBonusDamage(school)` returns `S.bonusDamage[school] or 0`;
`S.descShift = 0`; 774's description gained `+ S.descShift`; 5176's description now reads
`S.bonusDamage[4]`; `S.AddSpell(id, name, rank, descFn)` (a closure over the existing
`SPELL_SLOTS`/`SPELL_NAMES`/`SPELL_SUBTEXT`/`SPELL_DESC` locals) fills the first free slot from 6
on; `C_SpecializationInfo.GetTalentInfo`'s table branch returns `nil` while `S.level < 10`; five new
globals (`UnitHealthPercent`, `UnitHealthMissing`, `UnitPowerPercent`, `UnitGetIncomingHeals`,
`UnitIsDeadOrGhost`) with the exact behaviours specified; `C_Secrets` gained six entries
(`HasSecretRestrictions`, `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`,
`ShouldUnitPowerMaxBeSecret`, `GetPowerTypeSecrecy`, `CanCompareUnitTokens`), each raising `"bad
argument #1"` on a nil first argument except the no-argument `HasSecretRestrictions`;
`C_DamageMeter.GetCombatSessionSourceFromType` now returns one row (774/1000) with
`combatSpellDetails` for the Current session and six rows (774, 5185, 1058, 5186, 8936, 740 /
1000..500) for Overall, each carrying the same `combatSpellDetails` table.

**`tools/probecheck.lua`.** Two new helpers: `ClogAttempts(stub)` (counts
`COMBAT_LOG_EVENT_UNFILTERED` across every frame's `attempts`) and `ProbeFrame(stub)` (the frame
whose `attempts` contain `ADDON_LOADED`). `HEADERS_IN_ORDER` gained `"== blocked actions\n"` after
`"== events\n"` (fifteen headers). Steps 2, 3 and 4 now load `Client/TOC_Mainline.lua` in place of
the removed `Client/TOC_Forever.lua`. Step 2 gained the restriction/blocked/forbidden fires and the
`clogBefore2`/`clogAfter2` count around a `probe clog` call, all exactly where the task places them
(every fire through `Do`). New **Step 5** (fresh stub, level 9, `forbidOnRegister` for `UNIT_FLAGS`
and the combat log, no `AddTraits`) produces `reportA`/`reportB` across a level-9-to-10 change with
`descShift = 3`. New **Step 6** (fresh stub, 13 `AddSpell` "Stub Bolt" rows) produces
`reportC`/`reportD` across a `bonusDamage[4]` change from 0 to 5, with `recD` kept from
`SpellTunerDB.probe.reports["70009"]`. A new release block runs `release.sh --out
tools/.lua/probecheck-release` through `io.popen`, lists the package's `*.toc` files and checks
`Client/TOC_*.lua` presence/absence with `io.open`. Six existing assertions had their conditions
corrected in place (names unchanged): "registering a bad event is caught", "the report sections are
in order" (now also checks `reportB`), "the report prints the TOC that loaded" and "the to-do list
names what is left" (both now expect `Mainline`), "the probe never raises" (extended to steps 5/6),
"the report is ASCII with no bare pipe" (extended to `reportA..reportD`). Sixteen new `check(...)`
calls added verbatim by the names in Acceptance.

### Assertions seen failing before the probe/TOC change (21)

```
FAIL registering a bad event is caught
FAIL the report sections are in order
FAIL a change in bonus healing is reported against the previous run
FAIL the to-do list names what is left
FAIL an unreadable description is not counted as changed
FAIL the Q1 count covers comparable descriptions only
FAIL blocked and forbidden actions naming us are recorded
FAIL a blocked action naming another addon is ignored
FAIL COMBAT_LOG_EVENT_UNFILTERED is not registered at load, only by clog
FAIL a blocked action at load names the registration that caused it
FAIL the secret readings are taken out of combat and in the snapshot
FAIL the restriction state event is counted with its payload
FAIL the damage meter expands combatSpellDetails one level
FAIL Q1 is answered by a level change
FAIL Q6 waits for level 10
FAIL the build ships three TOCs
FAIL the Forever TOCs are 1.0.0-alpha.1 and differ only in their marker
FAIL a changed description prints what it was and what it is now
FAIL was and now are shown for the first 12 changed spells, the rest counted
FAIL the spells header shows bonus damage per school
FAIL Q1 is answered by a change in bonus damage
```
(36 ok, 21 failed on that run.) "the damage meter prints at most 5 spells a session" and "the
talent APIs that exist are called and shown" / "Q1 is answered only when both bonus readings are
readable" already passed on unmodified code, matching what the task says to expect (the five-row
cap already existed; the T0b-era talent/Q1 behaviour was untouched by this task).

Also caught mid-implementation (not a "before" failure list item, but worth recording): after
writing the full `Client/Probe.lua` diff the first full run was 56 ok / 1 failed
("blocked and forbidden actions naming us are recorded") — the `Run()` doing="run" restore bug
described above. Fixed, then 57 ok / 0 failed.

### Full `tools/run.sh tools/probecheck.lua` output

```
the TBC line reads its version from SpellTuner_TBC.toc                   ok
Client/API.lua loads under the TBC line                                  ok
MD.API.client is forever on interface 16001                              ok
MD.API.Has walks dotted names and says false for a missing one           ok
the report is keyed by build                                             ok
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
the probe adds no global but its own                                     ok - SpellTunerDB, SPELLTUNER_TOC, SLASH_SPELLTUNER1, SpellTunerProbeFrame, SLASH_SPELLTUNER3, SLASH_SPELLTUNER2
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
blocked and forbidden actions naming us are recorded                     ok
a blocked action naming another addon is ignored                         ok
COMBAT_LOG_EVENT_UNFILTERED is not registered at load, only by clog      ok
a blocked action at load names the registration that caused it           ok
the secret readings are taken out of combat and in the snapshot          ok
the restriction state event is counted with its payload                  ok
the damage meter expands combatSpellDetails one level                    ok
the damage meter prints at most 5 spells a session                       ok
Q1 is answered by a level change                                         ok
Q6 waits for level 10                                                    ok
the build ships three TOCs                                               ok
the Forever TOCs are 1.0.0-alpha.1 and differ only in their marker       ok
a changed description prints what it was and what it is now              ok
was and now are shown for the first 12 changed spells, the rest counted  ok
the spells header shows bonus damage per school                          ok
Q1 is answered by a change in bonus damage                               ok

57 ok, 0 failed
```
(the interleaved `SpellTuner probe: build 70009, N lines, ...` and one "registering ...raised"
chat lines that print between checks are omitted above for readability; none are assertion output.)

### The sixteen TBC suite tails

```
simcheck: |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck: 54 ok, 0 failed
replaycheck: 80 ok, 0 failed
replayui: 98 ok, 0 failed
runcheck: 78 ok, 0 failed
reviewui: 44 ok, 0 failed
navui: 25 ok, 0 failed
dashui: 56 ok, 0 failed
regencheck: 27 ok, 0 failed
simwindow: 8 ok, 0 failed
solvercheck: 70 ok, 0 failed
timeline: 27 ok, 0 failed
spelltip: 48 ok, 0 failed
practice: 74 ok, 0 failed
practiceui: 49 ok, 0 failed
migrate: 7 ok, 0 failed
```
All sixteen match the baseline exactly (unchanged from before this task).

### `luac -p`

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua tools/probecheck.lua
```
No output — clean on all three.

### `find tools/.lua/probecheck-release/SpellTuner -name '*.toc' | sort`

```
tools/.lua/probecheck-release/SpellTuner/SpellTuner.toc
tools/.lua/probecheck-release/SpellTuner/SpellTuner_Mainline.toc
tools/.lua/probecheck-release/SpellTuner/SpellTuner_TBC.toc
```

### Report excerpts

**report3, `== events` to `== secrets now`:**
```
ok UNIT_SPELLCAST_SENT
ok UNIT_SPELLCAST_START
ok UNIT_SPELLCAST_SUCCEEDED
ok UNIT_SPELLCAST_STOP
ok UNIT_SPELLCAST_FAILED
ok UNIT_HEALTH
ok UNIT_MAXHEALTH
ok UNIT_POWER_UPDATE
ok UNIT_AURA
ok UNIT_FLAGS
ok UNIT_COMBAT
ok GROUP_ROSTER_UPDATE
ok PLAYER_REGEN_DISABLED
ok PLAYER_REGEN_ENABLED
ok SPELLS_CHANGED
ok PLAYER_TALENT_UPDATE
ok TRAIT_CONFIG_UPDATED
ok DAMAGE_METER_COMBAT_SESSION_UPDATED
ok ADDON_RESTRICTION_STATE_CHANGED
throws COMBAT_LOG_EVENT_UNFILTERED <error: tools/wowstub.lua:244: unknown event "COMBAT_LOG_EVENT_UNFILTERED"> (by /st probe clog)
== blocked actions
listening: ADDON_ACTION_FORBIDDEN ok, ADDON_ACTION_BLOCKED ok
ADDON_ACTION_BLOCKED phase=combat during=idle addon=SpellTuner function=Frame:Show() n=1
ADDON_ACTION_FORBIDDEN phase=ooc during=idle addon=SpellTuner function=UNKNOWN() n=2
```

**report1, `== readings now`:**
```
UnitExists(party1) = true
UnitHealth(player) = 5000
UnitHealth(party1) = 4000
UnitHealthMax(party1) = 4000
UnitHealth(target) = 0
UnitPower(player, 0) = 7009
GetManaRegen() = 69.24, 28.33
GetShapeshiftFormID() = nil
C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = {duration=1800, name=Mark of the Wild, spellId=1126}
C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = nil
C_Secrets.HasSecretRestrictions() = false
C_Secrets.ShouldUnitHealthMaxBeSecret(player) = false
C_Secrets.ShouldUnitPowerBeSecret(player) = false
C_Secrets.ShouldUnitPowerMaxBeSecret(player) = false
C_Secrets.GetPowerTypeSecrecy(0) = 0
C_Secrets.CanCompareUnitTokens(player, player) = true
UnitHealthMax(player) = 5000
UnitPowerMax(player, 0) = 7009
UnitHealth(player, true) = 5000
UnitHealthPercent(player) = 100
UnitHealthPercent(player, true) = 100
UnitHealthMissing(player) = 0
UnitPowerPercent(player, 0) = 100
UnitGetIncomingHeals(player) = 0
UnitIsDeadOrGhost(player) = false
UnitHealth(party1, true) = 4000
UnitHealthPercent(party1) = 100
UnitHealthPercent(party1, true) = 100
```

**report2, `== combat snapshot`:**
```
taken 2025-09-04 15:33:20, in combat: true
ShouldAurasBeSecret = true
ShouldStub||Piped = false
ShouldUnitHealthMaxBeSecret = <error: tools/wowstub.lua:578: bad argument #1>
ShouldUnitIdentityBeSecret = <error: tools/wowstub.lua:569: bad argument #1>
ShouldUnitPowerBeSecret = <error: tools/wowstub.lua:582: bad argument #1>
ShouldUnitPowerMaxBeSecret = <error: tools/wowstub.lua:586: bad argument #1>
UnitExists(party1) = true
UnitHealth(player) = 5000
UnitHealth(party1) = <secret>
UnitHealthMax(party1) = <secret>
UnitHealth(target) = <secret>
UnitPower(player, 0) = 7009
GetManaRegen() = 69.24, 28.33
GetShapeshiftFormID() = nil
C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <error: tools/wowstub.lua:601: Auras cannot be accessed when secret while tainted>
C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = <error: tools/wowstub.lua:601: Auras cannot be accessed when secret while tainted>
C_Secrets.HasSecretRestrictions() = true
C_Secrets.ShouldUnitHealthMaxBeSecret(player) = false
C_Secrets.ShouldUnitPowerBeSecret(player) = false
C_Secrets.ShouldUnitPowerMaxBeSecret(player) = false
C_Secrets.GetPowerTypeSecrecy(0) = 0
C_Secrets.CanCompareUnitTokens(player, player) = true
UnitHealthMax(player) = 5000
UnitPowerMax(player, 0) = 7009
UnitHealth(player, true) = 5000
UnitHealthPercent(player) = 100
UnitHealthPercent(player, true) = 100
UnitHealthMissing(player) = 0
UnitPowerPercent(player, 0) = 100
UnitGetIncomingHeals(player) = 0
UnitIsDeadOrGhost(player) = false
UnitHealth(party1, true) = <secret>
UnitHealthPercent(party1) = <secret>
UnitHealthPercent(party1, true) = <secret>
```

**reportB, `== blocked actions`:**
```
listening: ADDON_ACTION_FORBIDDEN ok, ADDON_ACTION_BLOCKED ok
ADDON_ACTION_FORBIDDEN phase=ooc during=register:UNIT_FLAGS addon=SpellTuner function=Frame:RegisterEvent() n=1
ADDON_ACTION_FORBIDDEN phase=ooc during=clog addon=SpellTuner function=Frame:RegisterEvent() n=1
```

**reportB, `== to do`:**
```
== to do
Q1 answered: 1 of 4 spell descriptions changed when bonus healing went 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0, level 9 -> 10
Q2 to do: in a party, pull a mob; the probe reads itself 2 seconds into the fight; type /st probe after the fight
Q5 to do: in a party, pull a mob; the probe reads itself 2 seconds into the fight; type /st probe after the fight
Q3 to do: in the same fight, let the party member take damage and be healed, then type /st probe after the fight
Q4 answered: the damage meter listed at least one source out of combat
Q6 answered: see == talents
Q7 to do: type /reload, then /st probe; if this line still says to do, SavedVariables did not come back
Q8 to do: cast a heal on the party member during the fight, then type /st probe after the fight
Q9 answered: SPELLTUNER_TOC = Mainline
```

**reportD, from `== spells (` to `== talents`** (talents header itself not included):
```
== spells (bonus healing 0, bonus damage Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0)
slots 1-500: 17 with a spell, 3 healing, 0 empty description, 0 secret, 1 error
ranks per name: Healing Touch 1; Rejuvenation 2
spell 774
  name: Rejuvenation
  rank: Rank 1
  desc: Heals the target for 32 over 12 sec.
spell 5185
  name: Healing Touch
  rank: Rank 1
  desc: Heals a friendly target for 40 to 55.||nIt is \226\128\156quoted\226\128\157.
spell 1058
  name: Rejuvenation
  rank: Rank 2
  desc: Heals the target for 56 over 12 sec.
== spells against the previous run
previous: this session at 2025-09-04 15:33:20, bonus healing 0 -> 0, bonus damage Holy=0 Fire=0 Nature=0 Frost=0 Shadow=0 Arcane=0 -> Holy=0 Fire=0 Nature=5 Frost=0 Shadow=0 Arcane=0, level 64 -> 64
changed 5176 Wrath
  was: Causes 13 to 16 Nature damage to the target.
  now: Causes 18 to 21 Nature damage to the target.
changed 900001 Stub Bolt
  was: Causes 11 Nature damage to the target.
  now: Causes 16 Nature damage to the target.
changed 900002 Stub Bolt
  was: Causes 12 Nature damage to the target.
  now: Causes 17 Nature damage to the target.
changed 900003 Stub Bolt
  was: Causes 13 Nature damage to the target.
  now: Causes 18 Nature damage to the target.
changed 900004 Stub Bolt
  was: Causes 14 Nature damage to the target.
  now: Causes 19 Nature damage to the target.
changed 900005 Stub Bolt
  was: Causes 15 Nature damage to the target.
  now: Causes 20 Nature damage to the target.
changed 900006 Stub Bolt
  was: Causes 16 Nature damage to the target.
  now: Causes 21 Nature damage to the target.
changed 900007 Stub Bolt
  was: Causes 17 Nature damage to the target.
  now: Causes 22 Nature damage to the target.
changed 900008 Stub Bolt
  was: Causes 18 Nature damage to the target.
  now: Causes 23 Nature damage to the target.
changed 900009 Stub Bolt
  was: Causes 19 Nature damage to the target.
  now: Causes 24 Nature damage to the target.
changed 900010 Stub Bolt
  was: Causes 20 Nature damage to the target.
  now: Causes 25 Nature damage to the target.
changed 900011 Stub Bolt
  was: Causes 21 Nature damage to the target.
  now: Causes 26 Nature damage to the target.
changed 900012 Stub Bolt
changed 900013 Stub Bolt
was/now shown for the first 12 of 14 changed spells
```

### `git status --short`

```
 M Client/Probe.lua
D  Client/TOC_Forever.lua
D  Client/TOC_Vanilla.lua
 M SpellTuner.toc
D  SpellTuner_Forever.toc
 M SpellTuner_Mainline.toc
D  SpellTuner_Vanilla.toc
 M tools/probecheck.lua
 M tools/wowstub.lua
?? docs/tasks/T0c-probe-secrets.md
```
Matches the Files table exactly; no planner file was opened for writing.

### Skipped / out of scope, as instructed

- `Client/API.lua`, `Client/TOC_Mainline.lua`, `Client/TOC_Plain.lua`, `release.sh`,
  `tools/harness.lua`, `SpellTuner_TBC.toc` — read and checked, not touched.
- `CLAUDE.md`, `docs/PLAN.md`, `docs/HISTORY.md`, `docs/FOREVER-PLAN.md`, `docs/ROADMAP-FOREVER.md`,
  `docs/TESTING.md`, `docs/TOOLS.md`, `docs/REFERENCES-FOREVER.md`, `docs/probe/` — not opened for
  writing. Two of them still name the deleted TOCs and will need the planner's own update:
  - `CLAUDE.md:40` — "`SpellTuner.toc`, with its `_Forever` / `_Vanilla` / `_Mainline` copies that
    differ only in a marker line, for Forever".
  - `docs/TESTING.md:763-764` — the by-hand install list still says to copy `SpellTuner_Forever.toc`
    and `SpellTuner_Vanilla.toc`, and TESTING.md:766 still says "SpellTuner (1.0.0-alpha.0)".
  - `docs/tasks/T0-probe.md` also names them throughout, but that is a historical report of what T0
    built at the time and is not, itself, stale documentation of the current tree.
- No commits were made.

### Question

None. Every Fact the task rests on matched what was in the code (T0/T0b's `Client/Probe.lua`,
`Client/API.lua`, the TOCs, `tools/wowstub.lua`, `tools/probecheck.lua`, `release.sh` all read
before writing), and the spec's exact strings/conditions were followed literally rather than
reinterpreted.

## Review (lead, 2026-09-28)

**Verdict: accepted**, with one four-line fix made by the lead (below). The session that wrote this
task was cut off before review; the working files were recovered into this worktree and reviewed
against `git diff HEAD`.

**Acceptance, checked line by line.**
1. `tools/run.sh tools/probecheck.lua`: `57 ok, 0 failed`, rerun by the lead before and after the fix.
   The 41 existing names are verbatim. Only the six named assertions changed their conditions, and
   each changed exactly as specified. The 16 new names are verbatim and assert what the task says.
   The fail-first claim was **reproduced**: the new `tools/` against HEAD's `Client/Probe.lua` and
   TOCs (copied to a scratch tree) gives `36 ok, 21 failed`, the same 21 names as the Report. Three
   of them are unmodified T0b assertions ("a change in bonus healing...", "an unreadable
   description...", "the Q1 count covers..."). That is legitimate: HEAD's slash handler reads
   `probe clog` as `probe`, runs an extra report at bonus 50, and so run 3 compares 50 -> 50.
2. The sixteen TBC tails match exactly: simcheck PASS, 54/80/98/78/44/25/56/27/8/70/27/48/74/49/7
   ok, 0 failed each.
3. `luac -p` passes on `Client/*.lua`, `tools/wowstub.lua` and `tools/probecheck.lua`.
4. `git status --short` shows exactly the ten expected entries. No planner file was touched.
5. The Report has every paste the task asked for.

**Rules, read against the diff.**
- No client value is compared, used in arithmetic, indexed or used as a table key before
  `IsSecret`. `Describe`'s depth walk tests `IsSecret(val)` before `type(val)`. The addon-name test
  is `Fmt(addonName) ~= Esc(ADDON_NAME)`. The restriction payload and `functionName` only reach
  `Fmt`. Level and bonus damage are compared only as rendered strings (`First` / `Show`), and Q6
  reads the first character of the rendered string.
- None of the added code lines contain a pipe or a non-ASCII byte (checked by grep). The two chat
  lines match the spec. `clogOutcome.err` goes through `Fmt`.
- `was:` / `now:` print the stored text with no second `Esc`, as specified.
- No new global (the "adds no global but its own" check passes). The multi-return trap is not hit:
  every `x and "lit" or y` has a truthy literal in the middle.
- The stub's forbid stand-in is limited to the forever profile, says in its comment that it is a
  stand-in, and runs before the unknown-event raise. `attempts` is written in every profile and no
  TBC suite reads it.

**Defect, fixed by the lead (4 lines, `Client/Probe.lua`, the two listener `do` blocks).** Item 1
says `register:<EVENT>` covers "every registration made at load (**the two listeners**,
ADDON_LOADED and every EVENTS entry)". The implementation left `doing = "load"` around
`ADDON_ACTION_FORBIDDEN` and `ADDON_ACTION_BLOCKED`. This matters: FORBIDDEN is already being
listened for when BLOCKED is registered, so a forbidden action tripped by that second registration
would have read `during=load` and not named its cause. Each block now saves `doing`, sets it to
`register:<EVENT>` around its `pcall`, and restores it. No assertion covers this, and none was
added (that would widen the task). probecheck is still 57 ok and `luac` is still clean after the
fix.

**Notes, not defects.**
- `doing = "run"` is restored only on `Run()`'s normal exit. The slash handler calls `Run()`
  without `pcall`, so if a future bug makes `Run()` raise, `doing` stays at `run` and every later
  record is misattributed. `Run()` is built not to raise, and nothing in the task asks for more,
  but a later probe task should wrap the body.
- The Report says the fallback prints a "two-line usage message". The code prints one line,
  `SpellTuner probe: type /st probe (or /st probe clog)`, which is what the spec asks for. The
  mistake is in the Report's wording, not in the code.
- As the Report says, the stub's `HasSecretRestrictions` just mirrors `S.inCombat`. It is a stand-in,
  and the next report from the beta decides what the real one does.

**Docs the planner must update (not touched here):**
- `CLAUDE.md:40`: remove "`_Forever` / `_Vanilla` /". Only `SpellTuner_Mainline.toc` and the plain
  `SpellTuner.toc` remain.
- `CLAUDE.md:46` (the `Client/Probe.lua` row): "(41 assertions)" -> 57. Add T0c: blocked-action
  recording, `/st probe clog`, the secret readings, bonus damage and level in Q1, Q6 at level 10.
- `docs/TESTING.md:763`: the install list still names `SpellTuner_Forever.toc` and
  `SpellTuner_Vanilla.toc`. `docs/TESTING.md:767`: `1.0.0-alpha.0` -> `1.0.0-alpha.1`.
- `docs/TOOLS.md:42`: the probecheck row should mention T0c's coverage (blocked actions, clog,
  secret readings, the release's three TOCs).
- `docs/ROADMAP-FOREVER.md:116`: "`probecheck` 41 ok" is historical for T0b. Add T0c's 57 in a new
  line; do not overwrite the old one.
- `docs/HISTORY.md`: the session entry (state: Forever line `1.0.0-alpha.1`).
