# SPEC v0.15 — Practice: heal a fight you play

## 1. Why

The Simulate group built a fight and let a *planner* play it. That answers "what would the
rules do here", which nobody was asking (the author: "our current simulation does not really
provide much value"). What a healer wants is to rehearse: set up the group and the damage,
**heal it themselves in real time**, and then get the same review a dungeon pull gets —
replay, validate, coach.

## 2. The shape

| part | file | frames? |
|---|---|---|
| setup, damage generator, session, recording, store, bindings | `Engine/Practice.lua` | no |
| the setup panel (Simulate → Practice) | `UI/PracticePanel.lua` | yes |
| playing it: practice mode in the replay window | `UI/ReplayWindow.lua` | yes |
| the list (Reports → Review → Practice) | `UI/Dashboard_Review.lua` | yes |

**One engine.** A session is `Engine/SimModel.lua`'s own loop run inside a coroutine. The
loop calls `opts.pace(nt, …)` before applying anything at `nt`; the session yields there until
the wall clock (its own, pausable, 1/4x–1x) reaches `nt`, and returns false to end early. The
plan is not rules: its `Decide` reads the player's queued press. Everything else — mana, the
five-second rule, HoT ticks, Lifebloom stacks, Swiftmend, overheal, deaths — is the code every
replay and every search already runs. So a practice recording **replays to exactly the health
and mana the player saw**, and `tools/practice.lua` asserts that no gate fails.

The replay window paints the session off the trace the engine is writing
(`opts.trace.built`). Two things make a trace readable while it grows: `trace.filled`
(`Engine/ReplayTrace.lua` never reads a grid point past it) and `trace.expires` (when each HoT
application runs out, which a finished trace reads from its HOT_END and a live one cannot).

## 3. The setup

Per character (`cdb.practiceSetup`), because health depends on level.

- **Group:** Solo, Duo, Party (tank, you, melee, two ranged), Raid 10, Raid 25. The first
  healer slot is you.
- **Per target:** name, max health, steady damage (% of max health per second) delivered as
  hits every *n* seconds, a spike (% of max health) every *n* seconds on average, and a
  randomness % that moves both sizes and timings. An "every tank / healer / melee / ranged" row
  sets all of a kind at once.
- **Fight-wide:** length (10–600s), starting health, AoE (% of each target's max health every
  *n* seconds, with its own randomness), and **other healers** — a share of every hit healed
  back 1–3s later as a foreign heal.
- **Same fight again:** a fixed seed. The generator is a seeded LCG, so a seed is a fight.

Every default in `PR.ROLES` is a placeholder written as a fraction of max health, and the
panel says so.

## 4. Playing

Hover a frame and press a binding — the mouseover healing the author plays with. A binding is
a key or mouse button with its modifiers in the client's spelling (`ALT-BUTTON5`, `SHIFT-1`)
and a spell family with an optional rank (nil = your highest, so it follows a new rank).

**The defaults are the author's own Cell click-casting**, read from their SavedVariables on
2026-09-17: Button5 → Lifebloom ("Main overtime"), Alt-Button5 → Rejuvenation ("rej/moofire"),
Shift-Button5 → Rejuvenation Rank 5 ("efficient Rej"). Left and right click target and open
the menu in Cell, so here they carry Regrowth and Swiftmend; Shift-left is Healing Touch.
Bindings are account-wide (`db.practiceBinds`) and edited in their own window
(`UI/BindingsWindow.lua`, `/md binds`, or **Edit bindings** on the panel), in the shape Cell's
Click Castings and Clique use: a row per binding, click its key box and press what you want,
pick the spell beside it. One press, one spell -- taking a key takes it from whoever had it.

### 4.1 Importing from Cell and Clique (v0.15.1)

Cell and Clique already hold "this press casts that spell", so the window reads them rather
than making the author retype it. Neither is a dependency and neither is read while a fight
runs: the import happens when the button is pressed.

- **Cell** (`CellCharacterDB.clickCastings`, the common set or this spec's, exactly as Cell
  chooses): `{"alt-type5", "macro", "Main overtime"}`. The key is decoded the way
  `Cell/Modules/ClickCastings/ClickCastings.lua` encodes it -- `type<N>` for mouse buttons,
  `type-altR` for a keyboard binding with its modifiers glued to the key. A **spell** binding
  is a spell id; a **macro** binding is resolved by reading the macro and taking **the first
  heal it casts**, rank included -- which is what makes the author's own mouseover macros
  import as Lifebloom, Rejuvenation and Rejuvenation Rank 5.
- **Clique** (`Clique.db.profile.binds`, else `CliqueDB3` / `CliqueDB` profiles): its keys are
  already the client's spelling.

Everything that cannot be imported is **reported, never guessed**: a press bound to targeting
or the unit menu, the mouse wheel (practice has no wheel binding), a spell this addon does not
model (Rebirth, Innervate), a macro with no heal in it. The window prints one line per skip.

The game's rules, enforced where the game enforces them:

| rule | where |
|---|---|
| a press with more than 0.4s of cast or GCD left is refused at once | `Session:Cast` |
| a press inside the 0.4s queue window goes off when the cast / GCD ends | `Session:Decide` |
| not enough mana, dead target, Swiftmend on cooldown or with nothing to eat | `Session:Decide` |
| the cast bar is the spell's real cast time, not the Nature's Grace average | the session's own kit copy (`castBase`) |
| no 0.5s reaction delay (a player's is already spent) | `plan.noReaction` |

A refused press names its reason on the hint line and on the frame. Space pauses. **End**
keeps what was played and opens it as a replay; closing the window keeps it without reopening;
entering combat ends it. A session with no casts is not kept.

## 5. The recording

Written in `Engine/FightRecorder.lua`'s v2 stream format from what the engine did: the damage
and foreign heals up to the end, every cast (`OWNCAST` at its success time, with its cost),
every cast start, every heal as the combat log would carry it (`OWNTICK` for ticks, `OWNHEAL`
for direct heals and Swiftmend, the bloom under 33778), deaths, health every 5s plus the
moment it ended, mana every 2s. Kept apart from real fights in `cdb.practice` (newest 8) so a
practice evening never pushes a dungeon pull out; addressed as **`p1`** everywhere a fight is
(`/md replay p1`, `/md coach p1`, the Review tab).

**What makes it practice** is `rec.practice = { seed, setup, finished, errors }`, and two
gates read it:

- **no tracked death** passes. Its reason — damage after a death is truncated in a real log —
  does not hold: a practice fight's damage timeline was generated before anyone died and is
  recorded whole, so the coach can show how to keep them alive.
- **foreign healing** passes. Scripted other healers are events the engine replays exactly;
  they cannot make a plan fiction the way a real healer reacting to yours can.

## 6. Deliberately not in v0.15.0

- **Crits are expectations**, as in every replay: a rolled crit in the session would make the
  replay disagree with what was played. So Nature's Grace never shortens a cast either.
- No cancelling a cast, no movement, no line of sight.
- **No Innervate, potions or Tranquility.** Innervate and potions are recorded events, not
  engine decisions, and Tranquility has no heal values (`dataMissing`).
- No enemy cast bars and no aggro (the v0.12 indicators) in the generated fight.
- Other healers do not react to you; they heal a fixed share of the damage.
- The mana pool and regen are your character's, read live when Start is pressed.

## 7. Harness

- `tools/practice.lua` (45): the generator (deterministic in its seed, delivers what the setup
  asks within 10%, other healers give back their share); the session under a fake clock (GCD
  refusal, the queue window, a cast landing when its bar ends, Swiftmend with nothing to eat, no
  mana, a dead target); the live trace readable mid-fight; the recording **replaying to the
  same health and mana with every gate passing**; the coach answering it; a death not blocking
  the coach and the damage after it kept; stopping early keeping nothing after the end; a
  session with no casts not kept; retention; the default bindings.
- `tools/practice.lua` also holds the import (13 of the 58): the author's own Cell click-castings
  and macros as they are on disk import to three bindings with the ranks intact, and targeting,
  the menu, the wheel, Innervate and Rebirth are each skipped by name; Clique's shapes likewise;
  no Cell means no pretence.
- `tools/practiceui.lua` (40): the panel (group sizes, bindings listed, no bare pipe), Start
  opening practice mode, Button5 on a frame casting Lifebloom, a bound key over a hovered frame,
  a refused press naming its reason, Space pausing and resuming, End keeping the fight and
  opening it as a replay that validates, Review listing it, closing the window and entering
  combat both ending practice.
- `tools/dashui.lua` (54 → 56): Simulate opens on Practice.
