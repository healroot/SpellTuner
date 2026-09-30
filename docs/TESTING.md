# SpellTuner — what to test now (v0.7.0)

**Status 2026-09-05 (evening), v0.6.8:** the author ran `/md verify`, a `/reload`, `/md
profile` and `/md spamtest` on v0.6.7 (`.logs/regression/`). Results: **§2 verify passed**
(0 cost mismatches; the 13 CAST lines were all Naturalist and the harness now knows that);
**§6 spamtest passed** (13 predicted, 13 measured); **§8 Nature's Grace CONFIRMED** — two
casts after a crit read `live 1.50s`, the rest 2.00s; **§11 calibration caught a real
model error on its first run** (Regrowth's +healing split, fixed — see DECISIONS §15) and
exposed a sim leak (fixed). Also found: a false "cooldown used: Innervate" on every cast
(the GCD; fixed) and the `/md profile` paste came out **empty** (see §2b).

**Still to do, in this order:** §0b · §2b · **§12 roster in a group** (the biggest unknown)
· **§15 (new in v0.7.0, and it depends on §12 working)** · **§16 (new in v0.7.1)** · §17 · §18 · §19 · §20 · §21 · §5 (needs a hard pull) · §9
(needs one Innervate) · §11 again after a dungeon night · §13 · §14. §1, §3, §4, §4b, §7
are regression-only.

Everything below is done on the druid, in-game, with the Debug Console open
(`/md options` → General → Misc → Debug Console → tick **Enable Debug Logging**).
After each test: **Copy** in the console, paste into a file under `.logs/`
(gitignored) named like the test. Three to five files per session is plenty. The console
keeps 1000 lines by default — the **keep lines** box (top right, saved) raises it to 20000;
a fight with the Mana category on produces roughly 3 lines per second.

Install the TBC package (since T23 the TBC and the Forever lines are two packages from one tree):
`./release.sh --install-tbc "/mnt/e/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns"`
(or `make install WOW_ADDONS=".../_anniversary_/Interface/AddOns" FLAVOUR=tbc`, or copy
`dist/<name>/tbc/SpellTuner`), then `/reload`. It replaces `AddOns/SpellTuner` whole and removes
the Forever-only module folders if an older install left them there.

> **v0.5 and v0.6 both changed a lot of plumbing.** §0 and §0b are ten minutes of "did
> anything break"; do them first, because everything after is worthless if something is
> broken underneath.

## 0. v0.5 regression pass (5 min) — DO THIS FIRST
The v0.5.0 architecture pass rewrote four tooltips and the rank math's internals with no
intended change to any number. What to confirm:
- **`/md verify`** — output must be **identical to before** (0 COST mismatches, no CAST
  lines but Naturalist). Paste it.
- **Dashboard numbers** — Heal/cast, HPM, HPS, HP5 and To OOM unchanged from v0.4.9 for
  the ranks you know by heart. The **Cast** column is the one exception: Healing Touch and
  Regrowth now read e.g. `2.9s*` instead of `3.0s` (§8).
- **Tooltips** — ElvUI datatext, minimap button and the **widget** (new: hover it) all show
  the same mana block. The widget now takes mouse input; if that gets in your way,
  Options → OOM Widget → untick **Tooltip on hover**.
- **Widget left-click** opens the dashboard (new).
- Watch for Lua errors throughout (`/console scriptErrors 1`).

## 0b. v0.6 regression pass (5 min) — NEW, DO THIS TOO
- **No red `OOM 0s`.** In the BF log it appeared nine times at 72–97% mana. It must never
  appear again; if it does, Copy the log around it.
- **`OOM >2:00 =` on quiet pulls.** When the projection's error is above 70% of its value
  the clock now shows a bound instead of digits (Options → Model → *OOM digits below
  error*). On an easy pull expect mostly `OOM >N:NN =  rest Ns`; on a hard one the digits
  come back and count down as before. Tell me if a pull you *felt* was hard showed only the
  bound — that is the 0.7 needing retuning.
- **HP5 column is gone**; Cast / To OOM / note shifted left. Nothing overlaps.
- **Dashboard opens on your most-cast spell** (Lifebloom), not Healing Touch, until you
  click a tab.
- **A fifth tab, `Waste`**, renders with four `by:` buttons and two `scope:` buttons.
  Before any healing it says "No heals recorded this session yet".
- The **advisor**, when it fires for the potion, now adds *"Innervate is ready too but worth
  ~N: hold it until you're down that far."*
- Debug Console: **ten** categories in two rows (new: `Calib`); nothing overlaps the "keep
  lines" box.

## 1. Smoke test of the UI (5 min)
- `/md options`: tabs switch, frame drags by the tab strip, position survives `/reload`,
  ESC closes. The General tab grew — check **nothing overlaps** at the bottom of the
  Model and Misc panes (new: *Average in Nature's Grace*, *Reset overheal data*,
  *Copy profile*, *Show mana cooldown*, *Tooltip on hover*).
- Half-life slider: drag, type a value in the box + Enter, value clamps to 5–60.
- `/md`: spell tabs highlight, Settings opens the options, the **two-row** Simulate strip
  fits inside the frame, the header/callout/hint lines above the table do **not** wrap onto
  the rows (this is the layout risk in this build — say so if any of them does).
- Debug Console: category checkboxes filter (there is a new **Cast** one), Clear empties,
  Copy popup selects all, Ctrl+C works, ESC closes it.
- Minimap button: left = dashboard, right = options, hover shows the clock.

## 2. Data checks (2 min)
- `/md verify` — expect **0 COST mismatches** (Innervate is skipped). Any CAST line other
  than Naturalist is a bug. Paste the output.
- **`/md profile`** (new) — opens a copy box with every model input, the max ranks'
  live-vs-static costs, the clock state and all settings. Paste it once so the baseline is
  on record; from now on this is the thing to attach to any "this number looks wrong".

## 2b. `/md profile` came out empty — NEW, 30s
The regression paste of `/md profile` was a 0-byte file. Either the copy box was empty (a
bug — was there a Lua error? `/console scriptErrors 1`), or the paste failed. Run it again;
if the box is empty, tell me what the chat line said. `/md verify`'s snapshot section is the
same content, so nothing is lost meanwhile.

## 3. Tree of Life aura on heals — DONE 2026-09-03 (confirmed; keep for regression)
Tooltips on this client show BASE values only (932 in and out of form), so use the
**Heal** log category: every heal / HoT tick you land is logged with amount, overheal and
`[tree]` when in form. Being at full health is fine (overheal is still reported).
1. Out of form: cast Rejuvenation R12 on yourself, wait for 2 ticks.
2. Shift to Tree of Life, cast it again on yourself, wait for 2 ticks.
3. Copy. Expected tick out of form = `(932 + 450 × 0.8 × 1.20) × 1.10 × 1.15 / 4`; in form,
   if the aura counts, +healing becomes 450 + 0.25 × Spirit for the same formula.

## 4. Empowered Rejuvenation on the Lifebloom bloom — DONE 2026-09-03 (confirmed)
1. Cast **one** Lifebloom on yourself out of combat, let it expire (7s). The log shows
   7 ticks and one non-tick "Lifebloom" line = the bloom.
2. Expected tick = `(273 + 450 × 0.5187 × 1.20) × 1.10 / 7`; bloom with EmpRejuv =
   `(600 + 450 × 0.3422 × 1.20) × 1.10`.

## 4b. Relic slot (1 min)
`/md verify` prints the equipped relic and whether the table knows it. If it says NOT in
the relic table, paste the idol's name and tooltip text.

## 5. One real fight with logging on (the clock's constants) — STILL OUTSTANDING
- Any dungeon boss or a long trash pull (≥ 90s) where you actually heal.
- Keep the widget visible; do not read it during the pull, just heal.
- Afterwards: Copy the log (all categories on). The `[tto]` lines every 5s show what was
  displayed vs the model's T. What I will check: was `OOM` roughly honest at the end, how
  often the shown number jumped, how long the `~` / warm-up state lasted. Your one-line
  impression next to the paste helps: "too jumpy", "too pessimistic", "fine".
- **New in this build:** the same log now also answers §9 and §10, so one good fight
  covers three tests. Use Innervate during it.

## 6. To OOM sanity (repeat only if something looks off)
- `/md spamtest`, then chain-cast one spell to OOM. Prediction vs measured on one line.

## 7. Simulate strip (2 min, partly new)
- Put next tier's +healing into **+heal** and see whether the gold row moves for Healing
  Touch and Regrowth. Set **mana** to 2000 and read To OOM. Clear.
- **New second row.** Set **form** to `Tree` while standing in caster form: HoT costs
  should drop ~20% and the stats line should say *costs from the static table while
  simulating form/talents*. Set **Moonglow** to 3 (or to 0 if you have 3): Healing Touch,
  Regrowth and Rejuvenation costs move 3% per rank. `Live` and `Clear` put everything back.
- The interesting question this answers: **does a Moonglow respec change your efficient
  rank?** Tell me if it does.

## 8. Nature's Grace cast times — CONFIRMED 2026-09-05 (Regrowth); Healing Touch still worth one look
The spam test settled it: casts right after a CRIT read `live 1.50s`, all others `2.00s`
(`.logs/regression/spam-test`). The 0.5s and the GCD floor are real on this client. What is
left is only Healing Touch in caster form — Naturalist 5 makes R1 read 1.0s live, under the
model's 1.5s GCD floor, which is expected but worth seeing once.
The model now assumes a spell crit takes **0.5s** off your next cast (floor 1.5s) and
averages that into the Cast column, HPS, HP5 and To OOM. Neither the 0.5s nor Naturalist's
effect is visible in a spellbook tooltip, so:
1. Debug Console → tick the new **Cast** category.
2. Stand still and cast **six Healing Touch R11** in a row on yourself.
3. Copy. Each line reads `live X.XXs - model base Y.YYs, after a crit Z.ZZs (table 3.5s)`.
4. What I check: do the non-crit casts match `model base` (that confirms Naturalist), and
   do the casts right after a crit match `after a crit` (that confirms the 0.5s)?
- Repeat with two or three **Regrowth** casts — with Improved Regrowth those crit almost
  every time, so nearly every cast should show the reduced time.
- If the numbers disagree: Options → Model → untick **Average in Nature's Grace** puts the
  Cast column back to the old behaviour while I fix it.

## 9. Innervate's value (1 min inside §5) — NEW, settles an assumption
The clock now shows `inn 2:10` when you are under 90s to OOM with Innervate ready, and the
advisor quotes the same number. Both assume the 400% multiplies **only the Spirit share**
of your regen, not flat mp5 or Dreamstate.
1. With the **Regen** category on, use Innervate mid-fight (§5 is the natural place).
2. The log prints one line as the buff goes up and one as it fades:
   `mana cooldown UP: GetManaRegen base X casting Y; model expects Z/s while up (...)`.
3. What I check: does the client's `casting` value while the buff is up match the model's
   `Z`? If it is higher, flat mp5 is being multiplied too and the value model is low.
- Also worth one sentence: **did `inn 2:10` replacing `rest 2:10` help or annoy you?**
  Options → OOM Widget → **Show mana cooldown** turns it off. This is the one call in this
  build I am least sure about.

## 10. Overheal-calibrated numbers (needs one real raid/dungeon night) — NEW
The dashboard learns your overheal per spell from the combat log and can apply it.
1. Play normally for a night. Nothing to do — it records in and out of combat.
2. Open `/md`, tick **Effective** (top right, next to Settings). Heal, HPM, HPS and HP5
   become overheal-adjusted and their headers turn your class colour. A grey `?` means
   that rank has no measurement of its own yet and is showing the raw number.
3. Hover a row: the tooltip says the fraction, how many events it is from, and whether it
   is *measured on this rank* or a *family average*.
4. Copy `/md profile` — it lists every family and rank with its fraction and sample count.
5. What I check: are the counts growing sensibly, and does the family-vs-rank split ever
   have enough per-rank data to be interesting? **Deliberately not applied** to the gold
   "efficient rank" or the "rebind?" toast — a noisy measurement should not move those.
- **Also worth a look:** the fight-summary line's `overheal N%`. If it looks obviously
  wrong (say, doubled or halved), the combat log's `amount` convention was latched the
  wrong way — `/md profile` prints which one it picked under *combat log 'amount'
  convention*. Tell me what it says.

## 11. Calibration — the model against your heals (one night, then 1 min) — NEW
The addon now compares every heal you land with what the model predicted for it, per
spell and event kind (tick / direct / bloom), non-crit only, and keeps the ratio.
1. Play a night. Nothing to do.
2. `/md calibrate` (or Options → Misc → *Copy profile*, which includes it). Paste it.
3. What I check: every row with n ≥ 30 should read **ratio 1.000 ± 0.03**. A `HIGH` or
   `LOW` row is a real finding — a relic the table does not know, a wrong coefficient, an
   unmodelled buff — and you will also have seen one yellow *calibration:* chat line about
   it during play (Options → Model → *Calibration drift alerts* turns those off).
4. The two skip counters at the bottom matter: *Lifebloom ticks with no clean stack fit*
   should be a small fraction of Lifebloom ticks; if it is large, tell me — that is the one
   weak spot in this design, on your most-cast spell.
5. **Relics.** If a drift alert fires on the family your idol affects, it now names the idol
   and says what value the data implies — e.g. *"You are wearing Harold's Rejuvenating
   Broach (table: +87, unverified); the data says about +50."* That number is the table
   correction; paste the line. Seven of the eight idols in the table are unverified.
6. The `crit` rows: observed crit rate vs what the model assumed. Regrowth with Improved
   Regrowth should sit near 25% + crit; a big gap there is a talent-model bug.

## 12. The Waste view and the roster (one dungeon, then 2 min) — NEW
1. After a run, `/md` → **Waste**. Try all four `by:` modes and both scopes.
2. **The question that matters:** in `by: Role`, are your party's roles TANK / HEALER /
   DAMAGER, or mostly `UNKNOWN`? And in `by: Target`, do names show a grey `?` after the
   role? The design assumes `UnitGroupRolesAssigned` returns the role people picked in the
   group finder. In a guild premade it may return nothing — the `roster:` line at each pull
   in the debug log (Combat category) says `NAME CLASS ROLE(source)` for everyone; paste one.
   If `(unknown)` is common, the fallback needs work and I want to know now.
3. Sanity: the tank should overheal ~40%, a mage's Water Elemental ~100% (Lifebloom on a
   pet), you yourself around 45%. A warlock who taps shows *Life Tap xN* next to the name.
4. The footer: *"X spent this session, ~Y (Z%) into targets at full health"* — the BF log
   was 24%. Your number, and whether it changes how you cast, is the whole point.
5. The fight summary line now carries *(LB 52%, RG 22%, RJ 14%, other 12%)* and *~1.5k into
   full health*. Check it reads sensibly against one pull you remember.

## 13. Pull budget (between two pulls, 30s) — NEW
Out of combat, hover the widget: two new lines, *Pull budget: N more, M after a drink* and
*a pull in <zone> costs ~X (median of n)*. The drink reminder now reads *"Drink? 62% --
recent pulls here cost ~2.3k -- 2 more, or 4 after a drink."* Does the count match what you
would have guessed? Too optimistic is the failure mode to report.

## 14. Export (1 min) — NEW
`/md export` opens a copy box of tab-separated fights, overheal buckets, roster and
calibration. Paste it once alongside the debug log; from now on I analyse this rather than
regexing prose. Also: **Copy in the Debug Console now prepends the full input snapshot**, so
a pasted log is self-describing — no need to add your talents by hand.

## 15. Cast labels and the new summary line (one pull, v0.7.0) — NEW
Turn on the **Sim** category in the Debug Console, then do one normal pull of 15 s or more
with at least four casts. Three chat lines now arrive at the end instead of one:

1. the usual fight line (`0:40 || net -85 mp5 || spent 3.8k (LB 52%, ...)`),
2. `N of M casts on targets above 85% (2.9k): Lifebloom 9, Rejuvenation 4, Regrowth 1 -
   utility/shifts 1.6k - buffed in combat: Mark of the Wild at 0:39`,
3. only if you pre-HoTted somebody at full health before the pull:
   `pre-pull HoTs on full targets: 0.4k in Lifebloom 2 (78% overheal)`.

What to check, and this is the whole test — **does line 2 match what you remember doing?**
If you rolled Lifebloom on a healthy tank the whole fight, most of your casts should be in
the "above 85%" count and Lifebloom should lead the list. If the count looks far too low,
health is not being read at cast time (see the `unknown` bucket below).

In the debug log, the **Sim** category prints one line per fight:
`labels: utility 300/2, shift 0/0, early 220/1, overheal 2900/14, ok 380/2 = 3800 (fight
spend 3800, delta +0)`. Two failure modes to report:
- a `label identity BROKEN` line — the labelled mana and the spend tracker disagree by more
  than 2%, which means casts are being missed or double counted;
- a large `unknown` HP bucket, visible as line 2 counting far fewer casts than you made —
  that is `UnitHealth` failing to resolve group members and it breaks everything in v0.7.

Also: history now keeps **200** fights instead of 20, and a fight with fewer than 4 of your
own casts is no longer recorded at all. After a dungeon night, `/md export` should list
many more fights than before.

## 16. The 116 mp5 the regen API does not report (5 min, v0.7.1) — NEW, and the most interesting
Replaying the BF-1 hard pull through the new engine turned up something the model does not
know about. Over those 40 seconds, continuously inside the five-second rule, you gained
**2072 mana**. `GetManaRegen` accounts for 1140 of it. The other **931 (23 mana/s, 116 mp5)**
is real, and taking the whole log apart on 2026-09-06 showed it is **two different things**:

| | cadence | size | where it appears | what it is |
|---|---|---|---|---|
| **A** | exactly **2.00 s**, 497 times, never varying | **17** (8.45/s = **42 mp5**) | in combat *and* out of it, all 28 minutes | a property of **your character**: the mp5 bucket — gear, an idol, or a paladin's Blessing of Wisdom |
| **B** | **3.00 s** (55% of its events have a partner exactly 3.00 s later; the baseline at 3.5/4/5 s is 9%), one to four phases overlapping | 13–15 each, ~14.7/s here | **373 of 378 events in combat**, and **0.0 to 17.6 mana/s** depending on the pull — exactly zero in two of the thirty | a property of **the group**: a party-wide periodic energize |

Stream B is very likely the **shadow priest** — 5% of a shadow DoT that ticks every 3 s is
precisely this shape (Vampiric Touch), and you remember one being in the party. The log
records no classes, so that is corroboration rather than proof, and Vampiric Touch is a
level-70 spell.

Neither is Dreamstate (no points in it). **Nothing is being added to the model on a guess** —
and note that A and B want opposite treatment: A is a constant of your character that the
clock could add once it is confirmed, while B is *not yours* and must never be modelled, only
measured per fight by the recorder.

What settles it, in this order:

1. **Solo, out of a group, no buffs, out of combat.** `/md regentest 30` standing still. The
   report now prints a **tick histogram** that does this decomposition for you — every gain
   size (clustered within ±1) with its count and its beat:

   ```
   regentest: tick histogram (size x count, cadence) -
         138 x 14   the reported spirit tick
          17 x 14   a 2s beat - 43 mp5 the API does not report
       13-15 x 36   a 3s beat - a party energize, not yours
   ```

   Solo, you should see the spirit tick and possibly one 2 s line. If a 2 s line appears, that
   is stream A and it is **yours** — check the mp5 it prints against the mp5 on your character
   sheet. If only the spirit tick appears, A is a buff rather than your gear, and step 2 says
   which.
2. **Same character, in a party with a paladin, Blessing of Wisdom on you.** Repeat. If A
   only appears here, it is the blessing.
3. **In a dungeon with a shadow priest, then one without.** Stream B should appear and vanish
   with them. This is the cheap version of the test; `/md export` on two recorded fights is
   the thorough one.

Copy the log either way. If a stream shows up in step 1 it is worth 116 mp5 on your own
character, which is more than most gear upgrades.

Also, for reference: `/md simrun` should print **10 tests, all ok**, and `/md simreplay
fixture` should print `spend ... (exact)` and a `measured ... -> PASS` line. Those two run
anywhere, including right after login, and are worth doing once after this update just to
confirm nothing about your talents breaks the engine.

## 17. Fight recording (one dungeon, v0.7.2) — NEW
Nothing to do but play. After a few pulls, `/md export` should carry `# recording 1` ..
`# recording 8` blocks, each with a roster, the initial auras, the pre-pull casts and the raw
event stream. Paste one export after a dungeon night.

What to look at yourself, in the Debug Console with **Sim** on:

- `recording started: N tracked, M initial aura(s), K precast(s)` at each pull. In a 5-man
  N should be 5. **If M is 0 while you had HoTs rolling, say so** — the aura scan is the one
  part of this that could not be tested offline.
- `stream <id> recorded: 40s, 312 events, 19 casts, 6169 mana, foreign 22%` at the end.
  *foreign* is how much of the healing on your group was somebody else's; in a 5-man with one
  healer it should be small. If it is over ~50%, replay of that fight will be fiction and the
  Review tab will say so.
- `stream discarded` for short pulls is normal (under 20 s or under 5 casts).

Size: eight streams is the cap and the cheapest non-recent, non-pinned pull is the one that
gets replaced. If your `SpellTunerDB` starts feeling large, tell me the file size — the budget
was ~180 KB for the streams and that is worth checking against reality. `db.recordFights =
false` turns recording off entirely; summaries keep working.

## 18. Does a real fight replay? (after §17, v0.7.3) — NEW
`/md simreplay 1` takes your most recent recorded pull, runs it back through the engine and
prints eight gates with a verdict. `/md simreplay 2` .. `8` for the older ones.

This is the question the whole Coach idea rests on: **can the model reproduce a fight you
actually played?** If it cannot, nothing will be suggested from that fight — by design.

Paste the output. The interesting failures, in order of what they would teach:

- **mana mean / max** over 2% / 5% of pool. On the BF-1 fixture this fails by exactly the
  116 mp5 from §16, so if it fails here too, §16 is the cause and the fix is there.
- **health curves**. Only targets that actually took damage are scored, and a target that
  misses is excluded rather than failing the fight. If every target is excluded, the model's
  heal values are wrong for the people you heal — which is what `/md calibrate` is for.
- **model calibrated**. Says "not yet calibrated" until a spell has 30 events; that is
  printed, not failed.
- **spend coverage** under 90% means mana went on spells the model does not price — in BF-1
  that was 12.6% of buffs, shifts and dispels.

A pull with a death, or with more than 25% of the healing coming from somebody else, is
rejected outright and that is correct: the log truncates damage after a death, and a fight
somebody else healed is not your fight to learn from.

## 19. The card (after a dungeon, v0.7.4) — NEW
`/md coach 1` on a recorded pull. If the fight did not pass §18's gates it **refuses and says
which gate failed** — that is the intended behaviour, not a bug; `/md coach 1 force` shows a
card anyway with the failures listed in its caveat line.

The card names the binds, the five rules with their thresholds, a mana comparison against
"max rank" and "HoTs only", and where your casts went relative to the plan (`early`, `rank`,
`spell`, `stack`, `late`, `overheal`, `unclassified`, plus `idle` moments).

Two things to judge, and they are the whole point:

1. **Is the advice followable?** If a rule reads like something you could not do while
   watching health bars, say so — a suggestion nobody can execute is worse than none.
2. **Is it right?** In particular the verdict line: *"you had 2.1k headroom — nothing here
   needed to change"* should appear on the easy pulls. If every card finds something to fix,
   the card is wrong, not you.

Also check the debug `sim` line `classifier: N labelled vs M spent` — those two must match.

**v0.7.5:** `/md coach` now searches for a better plan before drawing the card. It runs across
frames; `/md coach cancel` stops it. **Watch for a freeze** — if the client hitches at all when
you run it, say so: the slicing uses `debugprofilestop()` and if that behaves differently on
this client the whole search would land in one frame. The debug `sim` category prints
`search done: N evaluation(s)` with the winning tuple, and a physical-floor line that must
never say `IMPOSSIBLE` (that would mean the engine is healing for free).

## 20. The Review tab (v0.7.6) — NEW
`/md` → **Review** (sixth tab, after Waste). One row per recorded fight; click one to select it.

- The **validate** column is blank until you press **Validate** (replaying is not free). After
  that it says `ok` or names the first gate that failed, and a failed fight goes grey.
- Hover a row: the full gate list, foreign share, and which targets were excluded.
- **Coach** is disabled on a fight that failed, with the reason in its tooltip. That is
  deliberate.
- **Pin** protects a recording from being replaced (at most two).
- The bottom two lines are the habits over your summaries and, once you have three fights in a
  zone after a card, the since-your-last-card comparison.

Also new: `/md options` → General → **Fight recording** (left column, under Alerts) with the
record toggle, "let Coach change ranks", and the two thresholds. The options window is taller
now — check it still fits your screen.

Report anything that overlaps, overflows or reads wrong. This is the first new tab since v0.5
and none of it can be checked outside the game.

## 21. The Simulation window (v0.7.7) — NEW
`/md sim`. Pick a party size, a damage pattern and a starting state, set a length, press
**Run**. It runs the max-rank and HoTs-only baselines, then searches for a better plan, then
runs 30 randomised replicates of the winner.

**The damage numbers are made up.** The window says so in grey until you press **From
recordings**, which replaces them with what actually happened in your recorded fights, per
role, and prints how many fights and seconds it measured. Please do that once you have a few
recordings and tell me how far the placeholders were off — the presets are one healer's guess
written down so the window had something to run, and they are meant to be replaced.

What to judge:
1. Does the suggested plan look like something you would do?
2. The replicate line — *"someone below the floor 40% of the time"* — is the interesting one.
   A plan that is mana-optimal but only holds on average crits is a bad plan, and this is the
   only place that shows it.
3. Does the search freeze anything? (Same concern as §19.)

## 22. The trace (v0.8.0) — nothing to test in-game yet
v0.8.0 is engine-side only: the replay window arrives in v0.8.1. What exists is verified
offline by `tools/run.sh tools/replaycheck.lua` (27 assertions). The one thing worth doing
after this update is the usual `/md simrun` (10 tests, all ok) and `/md coach 1` on a
recorded fight, because `Plan:Decide` now returns a third value and Coach caches its plan
for the window — both are invisible if they work and loud if they do not.

## 23. The replay window (v0.8.1; Cell-shaped since v0.8.6) — one recorded pull, 5 min
The frames are your Cell `default` layout, copied from your saved settings (66 × 46, five per
column, your icon slots) — if anything sits differently from your raid frames, say what: the
whole layout is one table at the top of `UI/ReplayWindow.lua`. The one thing Cell has no slot
for is the **cast target**: the spell in flight appears in the top-centre icon slot with its
cast-time sweep and the button's border in the family colour; it holds a moment after landing.
Review tab → select a recorded fight → **Play** (or `/md replay 1`). Two columns if you have
pressed Coach on that fight, one if not — the header says which and why.

1. **Press play at 1×** (1/4× and 1/2× exist for the busy moments). A Healing Touch is a
   *jump*; a Rejuvenation is four steps 3 s apart; Lifebloom ticks every second. Nothing
   glides. If a bar slides smoothly, that is a bug.
   The cast bar: a real cast fills over its **recorded** time in the family colour; an instant
   sweeps the 1.5 s GCD in grey; the name stays, dimmed, until the next cast.
2. **The white tick on the left bars** is the recorder's real HP snapshot, fading over the 5 s
   until the next one. It should sit *inside* the bar's reconstruction most of the time; when
   it does not, note the target and the time — that is the health gate's number, seen.
3. **Scrub.** Drag back and forth; the frames must follow instantly and nothing must flash
   during a drag (flashes belong to events *crossed while playing*).
4. **4× to the end.** The strip's `spent` must equal the summary line's for that fight; a death
   greys the frame at the right moment and the scrubber shows it red.
5. **The right column** (after Coach): its damage pulses land at the same instants as the
   left's — the same red flashes, different green — and `waiting 1.2s` shows while the plan
   holds. Its `spent` should be below the left's; if it is not, the card said so too.
6. Close, reopen with `/md replay 2` (an older fight, no Coach yet): a single narrower column.

Report: the fight number, anything that glided, any tick that sat outside its bar for more
than one snapshot, and whether the window felt readable at 1× — that is the design question.

## 24. Indicators and labels in the replay (v0.8.2) — a coached pull, 5 min
Coach a fight, then Play it.

1. **HoT icons** under the role letter: Rejuvenation, Regrowth, Lifebloom, as their spell
   icons, dimming **from the top down** as they run out (Cell's vertical sweep). Lifebloom
   shows its stacks bottom-right and its border turns **white in its last second** — the bloom
   is coming. Watch one Lifebloom roll 1-2-3 and whiten; watch one Rejuvenation dim to the
   bottom and go. Defensives and debuffs sweep the same way, for exactly as long as they were
   up.
2. **The orange dot** after the squares: Swiftmend is ready *and* has something to eat. It
   should vanish for 15 s after every Swiftmend you cast.
3. **Labels** under the cast text on the left, in the card's colours: `late` red, `overheal`
   orange, `early` / `stack` yellow, `spell` / `rank` grey. The scrubber's cast ticks carry the
   same colours, so before pressing play you can see where the yellow and red are. Find the one
   `overheal` you remember and check it lands on that cast.
4. **The right column's waits**: a grey band over its cast bar and `waiting 1.2s` while the
   plan holds. **Hover the right cast bar**: it names the rule behind the current cast
   (`rule 3: keep Lifebloom rolling on the anchor`) or says why it is waiting.

Report: whether a label ever seemed wrong (say which cast and what you would call it — this
is how the classifier gets corrected), and whether the squares are readable at the frame's
size.

## 25. Defensive cooldowns and debuffs in the replay (v0.8.3) — one dungeon
The recorder now keeps two more things on tracked targets: **defensive cooldowns** from the
whitelist in `Data/AuraList.lua` (Shield Wall, Last Stand, Barkskin, Evasion, Divine Shield,
Pain Suppression, Power Word: Shield, ...) and **every debuff**, capped at 4 per target and
10% of the stream's event budget. Neither changes a number anywhere — the damage a Shield Wall
prevented was recorded as prevented — they *explain* the dips.

1. Record a pull where the tank presses something (or ask them to). Play it: the defensive
   shows as an icon with the accent border in front of the tank's name, for exactly as long
   as it was up; hover it for the name and the time.
2. A boss or caster debuff shows as a small icon on the right end of the bar, with its stack
   count. Hover it.
3. `/md export` → the `# recording` line now ends with `N auras`; a long raid-style fight
   says `(debuffs truncated)` rather than silently dropping anything.
4. **Every id in `Data/AuraList.lua` is from memory and marked VERIFY.** If a defensive you
   *saw* pressed does not show, note the class and the ability: the id is wrong or missing,
   and a wrong id costs an icon, never a number. If an icon appears without a texture (a grey
   square with a letter), the id resolved but `GetSpellTexture` did not — say so too.

Report: which defensives showed, which did not, and — the design question from the reserved
list — whether seeing the tank's cooldown up would have changed what you cast.

## 26. Nothing to do in-game: the import tool reads your recordings
`tools/run.sh tools/import.lua list` finds your SavedVariables (your install path is the
default), lists every recording with its validate verdict, and `validate N` / `replay N` /
`coach N force` / `export N` run the same engine on them offline. **Every recording you make
now reaches the engine without a paste.** The one thing that still needs you: `/reload` (or
logout) after a fight, because the client writes the file only then.

## 27. Measure what the API does not report (v0.9.0, corrected in v0.9.5)
**Solo** — out of a group, no buffs from anyone else, standing still, out of combat, and not at
full mana (spend a few hundred first):

```
/md regentest 30
```

The test now prints its arithmetic on one line:

```
regentest: observed 55.77/s = API 48.76 + Dreamstate 6.52 + unreported +0.49 (+2 mp5)
```

**Only the leftover is stored.** On a druid with Dreamstate the talent rides inside the same
server regen tick as spirit and gear, so there is normally one tick and nothing left over —
`nothing to store - the model already accounts for everything the client regenerates` is the
*correct* result, not a failure. Something is stored only when a genuinely separate stream shows
up in the histogram, above a 5 mp5 floor (the test cannot resolve less than that).

If it does store, the line reads `stored NN mp5 (x.xx/s left over after the API and Dreamstate)`.
It refuses, and says why, when mana was spent, a drink was up, part of the window was inside the
five-second rule, fewer than 6 ticks were seen, or **you were in a group** — somebody's blessing
would land in your own bucket.

`/md regentest clear` forgets a stored measurement.

Then `/reload` and, on the machine, `tools/run.sh tools/import.lua validate 2`. Two things to
check in the header and the gates:

1. `kit: the character's (profile of ...)` — the offline engine is using your stats, not a
   stand-in.
2. The 87 s Hellfire fight's **mana mean** should be around 1%, inside the 2% limit. It was 3.3%
   before v0.9.0, and the term that closed the gap is Dreamstate, which replays never added.

Report the `observed = ...` line and the `mana mean` line.

**If you are reading a regen number that looks too big**, that is the v0.9.0 bug: the first
version of this test stored the size of the whole tick rather than the leftover, so a character
regenerating 279 mp5 was modelled at 556. v0.9.5 refuses such a value, says so once, and a clean
re-run clears it.

## 28. Record a whole dungeon as one run (v0.9.1)
A boss is a pull; a five-man is thirty pulls and the gaps between them, and the gaps are where
the mana goes. Runs are **manual**, so at the instance door:

```
/md run start
```

It names itself after the zone and the time (`/md run start Ramparts fast` names it yourself).
Then play the dungeon normally. At the end, `/md run stop` — or just walk out and keep going:
the run stops itself 30 seconds after you leave the instance, and says so. `/md run status` at
any point prints the elapsed time, the pulls so far, the drinks and how much of the event
budget is spent.

What it records that a single fight does not: every pull including the short ones, the mana
every 2 seconds for the whole run, each drink with the mana either side of it, your deaths and
the time you spent dead, zone changes, Innervates and potions.

Report the stop line verbatim. It looks like:

```
run Blood Furnace 21:14: 30 pull(s), 28:50, combat 57%, drank 4x (3:10, 143 mana/s), mana at pull p50 71%, 1 death(s) (1:35 dead), 41200 mana spent
```

The three numbers worth checking against your memory of the run: **how many drinks**, **roughly
how long**, and **mana at pull p50** (the mana you typically opened a pack with). If the drink
count is wrong, say what the drink buff was called — the recorder watches for `Drink`,
`Refreshment` and `Food & Drink` by name.

Two things to try deliberately, once:
1. **Die**, release and run back. The dead time should appear in the stop line.
2. **Leave and come back** (a corpse run, or a quick step outside). The run should NOT stop —
   there are 30 seconds of grace, and returning cancels it.

Then `/reload` and, on the machine, `tools/run.sh tools/import.lua list` still lists your
single fights; the run itself reaches the tools in v0.9.2. `/md export` already carries it as a
`# run` section.

Limits worth knowing: two runs are kept (pin one on the Review tab from v0.9.2 to protect it),
a run stops itself after 90 minutes, and a very long run stops *recording* new pulls at 30 000
events while still counting them — the stop line says `STREAM FULL` if that happened.

## 29. Review a run: the tab, and the tools (v0.9.2)
After §28's dungeon, open `/md` → **Review**. Above the list there is now a row of buttons:
**Fights** (the eight single pulls, as before) and one button per stored run.

1. Click the run. The list becomes **its pulls, in order**, and the `when` column shows how far
   into the run each one started (`+12:41`). The run's line is printed above the list.
2. A pull under the recording gate is greyed and reads `short - under the recording gate`, with
   **Coach** disabled. It is *kept on purpose*: a dungeon is mostly those. Hover Coach to see it
   say so.
3. **Validate**, **Play** and **Coach** work on the selected pull exactly as they do on a single
   fight. Play should open the replay with the run's name and the pull number in its header.
4. **Pin** reads **Pin run** while a run is shown: a run is kept or dropped whole. Two runs are
   kept; pin the one you want to keep before the next dungeon.
5. **Start run / Stop run** is at the left of the button row, the same as the slash command.

The same address works from chat: `/md replay 1:3` plays the third pull of the first run, and
`/md coach 1:3` coaches it.

Then `/reload` and, on the machine:

```bash
tools/run.sh tools/import.lua runs
```

It lists the stored runs with their stats; `tools/run.sh tools/import.lua list --run 1` lists
that run's pulls, `validate 3 --run 1` is its third pull, and `export --run 1` writes the whole
run to `.logs/runs/<id>.txt`.

Report: whether the pulls in the tab match the pulls you remember (count and rough order),
anything greyed that you think should not be, and the `runs` output.

## 30. Coach a run (v0.9.3)
With a run recorded (§28), open `/md` → Review, select the run and press **Coach run** — or
`/md coachrun 1`. It searches one plan *and one drink policy* for the whole dungeon, with the
pulls chained (mana carried from each pull into the next) and the gaps simulated. It runs across
frames; `/md coachrun cancel` stops it.

The card's two rows are the point:

```
  you       drank 4x (3:10)        never forced      41.2k spent   lowest 18% (pull 12)
  best      drank 2x (1:20)        never forced      33.9k spent   lowest 31% (pull 7)
```

Report:
1. **The two `drank` lines.** Is the plan's drink count one you would believe of yourself? A
   plan that claims you never need to drink in a Ramparts run is telling you something is wrong
   with the model, not with your play.
2. **`where it differs`** names the pulls with the biggest gap between what you spent and what
   the plan would have. Open one with Play (`/md replay 1:7`) and say whether the difference is
   real — whether you would actually have made that call at that moment.
3. **`yours was: under X%, up to Y%`** is the drink policy read back out of your own run. If it
   looks nothing like how you play, the drink detection is off, so say what the buff was called.
4. Anything on the two "pulls not to trust" / "pulls that do not replay" lines that surprises
   you.

The score puts **added time first, then drinks, then mana**: a plan that saves mana but forces
the group to sit is worse than one that spends more and never does. If you disagree with that
order after seeing a card, say so — it is a decision, not a fact (`docs/DECISIONS.md` §v0.9).

Offline, the same thing without the game: `tools/run.sh tools/import.lua coach --run 1`.

## 31. Play a dungeon pull by pull (v0.9.4)
`/md replay run 1` (or Play on a run in the Review tab) opens the run's first pull with a new
**run strip** under the header: the whole dungeon on one line, each pull a block as wide as it
was long, the one you are watching bright, short pulls grey, drinks in blue, deaths as red
marks, and the gaps left as gaps.

1. Hover a block: pull number, length, where it sits in the run, casts and mana.
2. Click one: the window re-opens on that pull, same controls, same speed.
3. Let a pull play to the end. **The next pull opens and keeps playing** — that is the intended
   way through a dungeon. There is no "play the whole run": half an hour at 1x is not review.
4. A single fight (the Fights list) has no strip at all, and the window is the same height it
   was in v0.8.

Report: whether the strip's shape matches the run you remember (long boss pull in the right
place, drinks where you sat down), and whether auto-advance is welcome or annoying. It is one
setting (`db.replayNextPull`) either way.

## 32. Force the suggested column (v0.9.6, shift-click added in v0.9.8)
A fight that fails its gates has its Coach button disabled, and until now the replay window
would not draw the suggested column for it either — even after a forced coach. Now:

```
/md coach 2 force
```

**or shift-click Coach on the Review tab** — a fight that does not replay now keeps a clickable
Coach button marked with a star, and a plain click on it still refuses and names the failing
gate. Either way it prints the card anyway *and remembers* that you asked, so Play on that fight shows both columns
from then on, with `FORCED - this fight does not replay` next to the column's title. Two other
ways in: `/md replay 2 force`, and shift-clicking **Play** on the Review tab. If nothing has
been coached for the fight, forcing says so and tells you to coach it first — the replay window
never searches.

Report whether the second column on a forced fight looks like it is describing the same fight
you played, or obviously not.

## 33. Heal values on your spell tooltips (v0.14.9)
Hover any healing spell on your action bars or in the spellbook. Under the game's own text
there is now a **SpellTuner** block for *that exact rank*, at your current +healing and talents:

- **Rejuvenation:** each tick and how many, and the total over 12s.
- **Regrowth:** the direct heal's range and its crit range, each HoT tick, the HoT total, and
  the whole cast (with and without crits).
- **Lifebloom:** each tick at 1 stack and at 2 / 3, the HoT total, the bloom (and its crit),
  the total if you let it bloom, and what one refresh is worth when you roll it at 3 stacks.
- **Healing Touch:** the range, the crit range, the average.
- **Swiftmend:** how much it gives by eating your Rejuvenation or your Regrowth.
- A downranked spell says so and by how much its +healing is cut.
- If your overheal on that spell has been measured, what it heals after it.

**Hold Shift** while hovering for how each number is built (base heal, +healing times
coefficient, talents). Turn it off with `/md spelltip` or Settings -> General -> Misc.

Report: (1) any number that disagrees with what the spell actually does on a target that is
missing health (a Lifebloom tick at 1 stack and a non-crit Regrowth are the easiest to read
off the combat text); (2) any tooltip where the block appears twice or not at all -- action
bar, spellbook, a spell linked in chat, and with ElvUI's tooltip skin if you use it;
(3) whether Shift updates the tooltip without moving the mouse.

## 33b. Damage spells on the tooltip (v0.15.3)
Hover Wrath, Starfire, Moonfire, Insect Swarm and Hurricane on your bars or in the spellbook. The
SpellTuner block reads the rank's base damage out of the game's own description and adds your
spell damage, talents and crit: the hit and its crit range, each DoT tick, the totals, DPM and
DPS. Shift shows the working.

Report: (1) **the one thing this rests on** -- does the game's own tooltip text still show the
BASE damage (the same number at any gear), or does it already include your spell damage? If it
changes when you put on a spell-damage item, every number here is double-counted; (2) a
non-crit Wrath or Starfire on a target dummy against the "Hit" range, and a Moonfire / Insect
Swarm tick against "DoT tick" (the coefficients and the Balance talents are the parts marked
VERIFY); (3) any damage spell where the block is missing (a description it could not read
adds nothing, on purpose). Settings -> General -> Misc has "...and on damage spells".

## 34. Practice: heal a fight you play (v0.15.0)
`/md practice` (or Simulate -> Practice). Out of combat.

1. **Set up.** Pick Party. Leave the damage at the defaults for the first go. Check the right
   side: the bindings should be your Cell click-casting -- Button5 Lifebloom, Alt-Button5
   Rejuvenation, Shift-Button5 Rejuvenation Rank 5 -- plus left click Regrowth, right click
   Swiftmend, Shift-left Healing Touch. Change one: click its key box, press something.
1b. **Bindings.** Press **Edit bindings** (or `/md binds`). **Import from Keybindings** is the
   one that should fit you: it follows every bound key to its action-bar slot and reads the
   macro there, so your mouseover macros on ElvUI's bars should arrive with the right spell and
   rank. Then press **Cell**: your
   click-castings should come in -- Button5 Lifebloom, Shift-Button5 Rejuvenation Rank 5 -- with
   a line each for the ones it would not guess (target, the unit menu, Innervate). Rebind one by
   clicking its key box and pressing something, including a mouse button with a modifier.
2. **Play.** Start practice. Hover a frame and press. Press something deep in a GCD (it should
   say "Another action is in progress" at once) and right before a GCD ends (it should go off
   when it ends). Space pauses. Play the whole two minutes once, and once press End halfway.
3. **Afterwards.** It opens as a replay with the suggested column filling in. Reports ->
   Review -> Practice lists it.

Report: (0a) whether **Import from Keybindings** got your real bars right -- every heal key,
the right rank, and nothing invented; anything it skipped that it should not have; (0) whether
the Cell import got the bindings you actually play with, and what it
skipped that it should not have; (1) does a press on a frame feel like your Cell frames -- mouse buttons 4/5 with
modifiers especially; (2) any press that did nothing and said nothing; (3) whether keys you did
NOT bind still work while the window is open (they should); (4) the damage defaults -- too easy,
too hard, the wrong shape -- with the numbers you changed them to; (5) anything on the frames
that does not match what happened.

## 35. WoW: Forever -- run the capability probe (T0, 2026-09-27)

This is on the **beta client**, not TBC: `/mnt/e/Blizzard/World of Warcraft/_classic_beta_`,
character Healroot, build 70009 or whatever is current. Everything in the Forever port waits on
this report (`docs/FOREVER-PLAN.md` §6, nine questions), so it comes before anything else on
Forever. The probe cannot break anything: every check is under `pcall`, and it never does
arithmetic on what the client returns.

**Install.** From this checkout (master's older `release.sh` does not know the suffixed TOCs):

```bash
./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"
```

This replaces `AddOns/SpellTuner` and the module folders whole (any `SpellTuner_TBC.toc` an older
mixed package left there goes with it). By hand instead: copy `dist/<name>/forever/SpellTuner` and
its sibling folders; the Forever package carries no `SpellTuner_TBC.toc`. Leave EllesmereUI as it is.

**Run.**
1. Start the beta. At character select, open AddOns and check that SpellTuner (1.0.0-alpha.1) is
   enabled. Log in as Healroot and type `/console scriptErrors 1` once, so a load error shows.
2. **Show all ranks.** Open the spellbook, hover the arrow at its top right and turn on the option
   to show all ranks of spells. The default view hides lower ranks, and the probe dumps what the
   book lists; the report prints how many ranks it found per spell so this can be checked.
3. **First report.** `/st probe` (or `/md probe`; if both are taken by something else,
   `/spelltuner probe`). A dark box opens: click into it, Ctrl+A, Ctrl+C, paste into a new file
   `docs/probe/<build>.md` (the build is on the report's `build:` line). If the box never opens,
   the report went to chat.
4. **Q1, dynamic descriptions.** Change your bonus healing -- put on or take off a +healing item,
   or take a buff that changes it -- and type `/st probe` again in the same session. The report
   compares this run's spell descriptions with the previous one's.
5. **Q2, Q3, Q4, Q5, Q8, the combat snapshot.** Join a party with at least one other player and
   pull a mob that lives longer than a few seconds. Let the party member take damage and cast a
   heal on them. The probe records itself 2 seconds into the fight. After combat ends, `/st probe`.
6. **Q7, SavedVariables.** `/reload`, then `/st probe`.
7. **Paste everything back.** Append every report of the session to `docs/probe/<build>.md` in
   order. The last report's `== to do` section should read "answered" for Q1 to Q9; a line still
   saying "to do" names the missing step. Then tell me the file is there.

**Second round (T0c, after your first report of 2026-09-27).** Reinstall with the same command;
the probe is now 1.0.0-alpha.1. What changed for you:
- The "blocked from an action only available to the Blizzard UI" dialog should not appear at
  load any more. If it does, press **Ignore** and run `/st probe`: the new `== blocked actions`
  section names the function. Then, once, type `/st probe clog` and `/st probe` again: that
  registers the combat log event on demand, and the same section says whether that was it.
- The readings section now asks the client directly whether your own health and mana are secret
  and under what state; nothing for you to do but run it once out of combat and once after a
  fight (the snapshot takes the same readings).
- Q1 has a second path: gain a level with no gear change and run `/st probe` again; if the spell
  descriptions changed, they are computed. Q6 needs level 10 or above (talents start there).

**If it does not even load:** copy the Lua error text, or what the AddOns list says about
SpellTuner, into the report instead. Each build's last report is also kept in
`_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/SpellTuner.lua` -- if the beta saved it,
which is exactly question 7.

**The downrank measurement** (`docs/FOREVER-PLAN.md` §6 Q10) is now §37, step 5 and step 7.

## 36. WoW: Forever -- the M1 frame (1.0.0-alpha.2, 2026-09-28)

On the **beta client** again (Healroot, build 70009 or current). This is M1's exit check
(`docs/ROADMAP-FOREVER.md` §2): the core loads with zero errors, `/st` opens the window, the three
module switches load their addons, errors are counted instead of flooding, and `/st dump` gives one
paste. Nothing here reads your health or mana; nothing registers the combat log.

**Install.** From this checkout -- the release now builds four folders, `SpellTuner` and the
three modules beside it:

```bash
./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"
```

Check that `AddOns/` now holds `SpellTuner`, `SpellTuner_Recorder`, `SpellTuner_Replay` and
`SpellTuner_Practice`. By hand instead: copy the four folders under `dist/<name>/forever/`.

**Run.**
1. At character select, open AddOns: SpellTuner shows `1.0.0-alpha.2`; the three modules are listed
   (they may say "load on demand"). Leave all four enabled. Log in as Healroot and type
   `/console scriptErrors 1` once.
2. **Zero errors at login.** No Lua error box, no "blocked from an action" dialog. If either
   appears, note its text, then go on -- step 6 will copy it.
3. **The window.** `/st`. A dark window titled SpellTuner opens with **Spells** and **Settings**
   down the left. Spells shows one line saying the spells arrive in the next build. `/st` again or
   Esc closes it. Drag it by the title; `/reload` and `/st`: it reopens on the view you left.
4. **The module switches.** `/st modules` (or Settings -> Modules). Three rows, all **off**.
   - Tick **Recorder**: chat says `Recorder: loaded`, the row says `loaded`.
   - Tick **Practice**: Replay and Practice switch on and load too (chat, one line each), because
     Practice needs Replay and Replay needs Recorder.
   - `/reload`. All three come back `loaded` without touching anything.
   - Untick **Recorder**: all three go `off - unloads at your next /reload`. `/reload`: all three
     `off`, and the AddOns list at character select still shows them enabled (SpellTuner never
     disables an addon; it just does not load it).
   - Tell me if any row said `could not load: <WORD>` and the word.
5. **The debug console.** `/st debug`. The console opens and, under its buttons, a line
   `Errors this session: none` (or a count). There is no "Regen test" button on Forever.
6. **The dump.** `/st dump`. A copy box opens: Ctrl+A, Ctrl+C, and paste it into
   `docs/probe/<build>-m1.md`. It has `== client`, `== capabilities`, `== saved variables`,
   `== modules`, `== errors`, `== debug log`. Two lines matter most: `error handler: installed`
   (if it says `not installed`, the client refused our error handler -- say so) and
   `forbidden events: COMBAT_LOG_EVENT_UNFILTERED`.
7. **The probe still answers.** `/st probe`: the report opens as before (the probe now answers
   through the new core). `/st probe clog` only prints that clog is gone.
8. Paste the dump back and tell me: any error or dialog at step 2, anything that did not happen as
   written in steps 3-7.

**If it does not load:** the dump cannot run either -- copy the error text instead, and whether
`/st probe` still works (the probe keeps its own slash command when the core fails).

## 37. WoW: Forever -- M2: spell tooltips, the Spellbook pane, the clock, and the measurements (1.0.0-alpha.3, 2026-09-28)

On the **beta client** (Healroot, build 70009 or current). This is M2's exit check
(`docs/ROADMAP-FOREVER.md` §2): the SpellTuner block on every spell tooltip, the Spellbook pane
listing every spell with its numbers, the mana clock, and **the numbers checked against real
casts** -- three spells of two classes, within the crit spread. It also answers what M2 was built on
without seeing: the return shapes (the probe's new `== shapes`), where tooltips fire, and whether a
low rank is penalised by the server (`FOREVER-PLAN.md` §6 Q10). Run §36 first if you have not.

**Install.** The same command as §36; the AddOns list should now show SpellTuner **1.0.0-alpha.3**
(and the three modules at alpha.3):

```bash
./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"
```

Log in as Healroot, `/console scriptErrors 1`. Any error box or "blocked" dialog at any step: note
it, carry on, and `/st dump` at the end.

**1. The probe, with the new shapes section (do this first -- it checks what everything else
assumes).**
1. Open the spellbook and turn **show all ranks off** (the arrow at the top right). `/st probe`,
   copy the report into `docs/probe/<build>-m2.md`.
2. Turn **show all ranks on**. `/st probe` again, paste it under the first. (The `book <id> ...`
   lines and `lowrank=` say whether the API lists the lower ranks either way.)
3. Pull a mob, cast one heal and one Wrath during the fight, finish it, then `/st probe` a third
   time and paste. (`in combat (...)` and the `UNIT_SPELLCAST_SUCCEEDED` lines say what reads
   secret mid-fight.)

**2. Tooltips (show all ranks on).** Hover **Healing Touch Rank 1** in the spellbook. Under the
game's text a grey `SpellTuner` block: `Heals 40 - 55 / avg 48`, `Crit 60 - 83`, `Per mana`,
`Per second (1.5 sec cast)`, `Casts to OOM`, `vs Rank 2 / 0.47x the heal for ...x the mana`, and a
`Suggested` line. Then:
- the same spell **on an action bar** (drag it there if it is not);
- the same spell **as a chat link** (shift-click it into chat, send it to yourself or a channel,
  click the link);
- **Rejuvenation** (`Heals 32 over 12 sec`, `Per second (over 12 sec)`) and **Wrath** (`Damage ...`);
- in combat once: the block should still appear (it may say `Read before combat`).
Tell me which of the three places show the block and which do not. `/st tooltip` switches it off
and on (also Settings -> General).

**3. The Spellbook pane.** `/st`. Spells -> Spellbook: a mana line, then **Heals**, **Damage** and
**Other** sections; every family with its ranks and Lvl / Mana / Value / Per mana / Per sec / Cast
/ To OOM; the suggested rank starred and named on its family's line. Hover a row: the same block
as the tooltip. Check against your own spellbook: **is any spell missing, or listed twice?** Press
**Export**, Ctrl+A, Ctrl+C, paste into `docs/probe/<build>-book.md` -- I run it through
`tools/refcheck.py` against talentsforever's data.

**4. The mana clock.** Out of combat at full mana it is hidden. Pull a mob and heal: a small frame
appears (top of the screen unless moved) reading `~OOM --` for the first few casts, then `~OOM 1:20
rest 2:10` or `~FULL 0:45`. The `~` means **modelled**: the game will not tell an addon your
current mana, so the clock adds up your casts' costs and your regen. The thin bar under it is the
**real** mana, drawn by the game. After the fight, hover it and read `Mana X / Y (modelled ...)`,
then compare with the real bar by eye: **tell me roughly how far apart they are** (for example
"bar about 40%, model says 55%"), and whether you drank. Drag it where you like; `/st clock lock`
locks it, `/st clock` hides it (also Settings -> General). If the bar stays empty or never moves,
say so -- that is a fact about the client (a secret handed to a status bar), not a bug to work
around.

**5. The measurements -- the M2 exit.** `/st measure` (chat: `measure: on - cast on yourself for
heals, on a target dummy for damage; one spell at a time`). One spell at a time: cast, wait for its
line in chat, then the next.
- **Heals, on yourself, with health missing.** Lose more health than the heal's top first (a fall
  from a height, or let a mob hit you and kill it). Then **Healing Touch Rank 1** (from the
  spellbook, show all ranks on), again for **Rank 2**, and **Rejuvenation Rank 1** (wait the full
  12 s). Each prints a line such as
  `Healing Touch R1 (learned 1, you 9, +heal 0): landed 48 [text 40-55, crit 60-83] in range` or
  `Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches`.
  Cast each heal **three times** if you have the patience -- one landing proves little.
- **Once at full health**, cast Healing Touch Rank 1 on yourself. If the line says `nothing landed`
  or a small number, the game counts **effective** healing (overheal left out); if it lands inside
  the text's range, it counts **gross**. (That settles the open half of Q3.)
- **Damage, on a target:** a target dummy if the beta has one, else a low-level mob you can kill
  slowly: **Wrath Rank 1**, **Wrath Rank 2**, and **Moonfire Rank 1** (let the damage over time run
  out). Lines read `Wrath R1 (learned 1, you 9): landed 15 [text 13-16, crit 20-24] in range`.
- **A second class** (the exit needs two): make or log in an alt of any mana class and do the same
  with its first heal or damage spells -- a priest's Lesser Heal and Smite, a mage's Fireball, a
  shaman's Healing Wave and Lightning Bolt, a paladin's Holy Light. Three spells is enough.
- `/st measure dump` gives every line in one copy box (kept across `/reload`, last 100): paste it
  into `docs/probe/<build>-measure.md`.
What the verdicts mean: `in range` and `crit range` are the model agreeing with the game;
**`BELOW range`** (a landed heal under the text's minimum, repeatedly) is the thing to report
first -- it is what a server-side downrank penalty would look like (Q10); `above` is a crit bigger
than 1.5x or a talent the text does not show.

**6. When you reach level 10 (talents, Q6).** Before spending the first talent point, hover the heal
the talent would change (for example Healing Touch or Rejuvenation) and note its text and our
`avg`. Spend the point on that talent. Hover again: **did the game's own text change?** If yes,
SpellTuner needs nothing more; if the talent says it changes the heal and the text did not move,
tell me -- that is the one case the code keeps a place for. Then `/st probe` (`== talents` now
answers Q6).

**7. Later, at level 20 (Q10 in full).** Healing Touch Rank 4 is learned at 20. Repeat step 5's
heals with **Rank 1, Rank 4 and your highest rank**, three casts each, and again after the next
level-up. Equal to the text within the crit spread -> no server rule; a shortfall that grows as the
rank falls further below your level -> a rule, and the numbers let me fit it.

**Paste back:** the three probe reports (step 1), the export (step 3), the measure dump (step 5),
`/st dump` if anything errored, and in words: which tooltip places showed the block, anything
missing from the pane, the clock's drift after a fight, and anything that did not happen as written.

## 38. WoW: Forever -- the next round: the M2 re-check, Q10, a talent, an alt, the M3 probe (1.0.0-alpha.4, 2026-09-28)

> **First, on the new beta build 70058 (2026-09-29): re-run the probe before anything else.** The
> client moved from 70009 to 70058, so every fact the port rests on is dated until the probe says
> otherwise. Out of combat, with **show all ranks** on in the spellbook and a macro that casts a
> spell on one of your bars (hover it once first -- 0.16.1's probe records what the client hands a
> macro tooltip), type `/st probe`, copy the whole box and paste it into
> **`docs/probe/1.60.1_70058.md`** (if the probe prints a different `<version>_<build>`, use that).
> Then do the sessions below on 70058; wherever they say 70009, read "the build you are on".

On the **beta client** (Healroot, build 70009 or current). Everything still to check in game,
in the order you meet it while playing, cut into sessions of 20-30 minutes. **Do the sessions in
order, but each one stands alone**: stop after any of them, paste what it asks for, and the next
round starts where you stopped. §37's results are in `docs/probe/1.60.1_70009-m2.md`; this build
fixes what that run found:

- the Spellbook pane's names no longer wrap over the rows, and Other lists only spells you cast for
  mana (T10c);
- the clock words its states as the TBC clock does -- `~FULL 0:45` out of combat only below 90%,
  hidden again above 95%, and `~OOM ...  rest 0:20` while it is still gathering, instead of a bare
  `--` (T11b);
- `/st measure` pairs each amount with the cast that caused it, keeps several spells open at once,
  and never says BELOW on an amount it cannot pin to one cast (T12b);
- the book reader stands on the shapes your probe returned (a free spell is free, the `|4` grammar
  escape expanded, Thorns' reflect not counted as a cast's damage) (T7b);
- the probe dumps the tooltip lines of a real heal, HoT and damage spell (last time it picked two
  passives), reads a party member's GUID, name, level, class, role and max-health secrecy, counts
  every `UNIT_COMBAT` token separately, and asks whether a status bar hands a secret back (T13b,
  T13e).

In each paste file below, `<build>` is the build number the probe prints (`1.60.1_70009` if it has
not moved).

**Install** (once, before session 1):

```bash
./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"
```

At character select the AddOns list shows SpellTuner and the three modules at the newest build --
**0.16.3** as of 2026-09-30 (§43; 0.16.2 the Forever UI, §42; 0.16.1 was build 70058's, §41), which carries everything 1.0.0-alpha.8 did (the numbering changed that
day: one version for both lines, Forever beta builds 0.16.x, 1.0.0 at the Forever launch --
`docs/DECISIONS.md` "One version, two installations"). Install it for every session of §38-§40;
the steps below are written for it. Log in as Healroot, `/console scriptErrors 1`. Any
error box or "blocked" dialog at any step: note
it, carry on, and `/st dump` at the end of that session (paste it under the session's other text).

### 38.1 Session 1 -- the M2 re-check, solo (20 min)

1. **The pane** (`/st`, Spells -> Spellbook; since 0.16.2 Spells -> Overview -> Whole book, §42). Every spell name on **one line** (a long one cut with
   `...`, the whole name on hover), no text over the rows, section titles `Heals` / `Damage` /
   `Other` readable. Other lists only spells you cast for mana (Mark of the Wild, Nature's Grasp,
   Teleport: Moonglade, and whatever you learned since), then one grey line counting the rest.
   **Screenshot it.** Is any spell you can cast missing, or any listed twice?
2. **Export** from the pane, Ctrl+A, Ctrl+C -- paste into `docs/probe/<build>-alpha4-book.md`.
3. **The clock, out of combat.** Stand at full mana: nothing drawn. Cast heals on yourself until
   the mana bar is well under 90%: `~FULL 0:30` (a time to full) appears. Wait: it disappears
   again once mana passes 95% (not before). Tell me if it ever said `refill`.
4. **The clock, in combat.** Pull a mob and heal yourself through it. The first seconds read
   `~OOM ...  rest ...` (still gathering), then digits, e.g. `~OOM 0:45  rest 0:20`. Tell me if it
   ever showed `~OOM --` on its own. After the fight hover it and compare its `Mana X / Y
   (modelled)` with the real bar by eye, as in §37 step 4.
5. **Tooltips**: hover Healing Touch in the spellbook, on a bar and as a chat link again -- which
   of the three show the grey SpellTuner block? (§37 step 2; a quick yes/no each.)

**Paste back** into `docs/probe/<build>-alpha4-s1.md`: the screenshot's description (or the file),
the answers to 1, 3, 4, 5 in words.

### 38.2 Session 2 -- the measurements again, and gross or effective (25 min)

`/st measure` (chat: `measure: on - ... several watches stay open at once`). A line now prints
when a spell's window has **closed** -- about a second after a direct heal lands, 12-13 s after a
HoT or DoT is applied -- not when the first number lands. Several can be open together; that is
the point.

**Since alpha.7 the measure only knows missing health inside a fight.** Out of combat the game
gives health back with no event it can see (regeneration, food), so it forgets what you lost when
the fight ends. Every "while hurt" below therefore means **in combat, with the mob still on you**:
pull something weak, let it hit you, and heal yourself while it is still fighting. A heal cast
after the fight reads `below range, missing health not known (0 known)` when it falls short --
not a fault, just the wrong moment. Heal **yourself** (target yourself or self-cast): a heal cast
at someone else is not judged at all, and the dump counts it.

1. **Get hurt first, in combat.** Switch the measure on, pull a weak mob and let it take more
   health off you than your biggest heal's top; keep it alive (and on you) while you do steps 2
   and 3. A fall does not count any more (it happens out of combat).
2. **The case that went wrong last time:** Rejuvenation (your top rank) on yourself, then at once
   Healing Touch (top rank) while the Rejuvenation is still ticking. Expected: a Healing Touch line
   `landed <n> ... in range` (or `crit range`), and 12 s later a Rejuvenation line
   `4 ticks 12+12+12+12 = 48 every 3.0 s ... matches` (the numbers of Rank 2; a higher rank has its own). Do it **three times**.
3. **Healing Touch Rank 1 and Rank 2 alone**, three casts each, while hurt.
4. **Gross or effective (Q3's open half):** heal to full (or wait), then **one Healing Touch Rank 1
   on yourself at full health**. The line says `nothing landed` or `capped at missing health 0
   (amount looks effective)` if the game counts only the healing that took; `landed 48 ... in
   range` if it counts the whole heal. Then **the same once more with a little health missing, in
   combat** (a weak mob has taken about 10-20 off you and is still fighting): `capped at missing
   health <d>` means effective.
5. **Damage on a mob** (a slow one, or a dummy): Moonfire, then Wrath **while Moonfire is still
   ticking**, then let Moonfire run out. Expected: Moonfire `landed ... in range; ... 4 ticks
   6+6+6+6 = 24 every 3.0 s ... matches` (numbers for your rank), Wrath `landed ... in range`. A
   Wrath hit that fits a Moonfire tick reads `ambiguous: 6 also fit Moonfire` -- correct, not a
   fault. A Wrath well under its range reads `below range: partial resist 50%?` or `below range
   (resist?)` -- tell me how often.
6. **In combat once**: a Healing Touch in a fight. The parenthesis should read `+heal <n> before
   combat` (the last reading from out of combat), not `+heal ?`.
7. `/st measure dump` -> copy.

**Paste back** into `docs/probe/<build>-alpha4-measure.md`: the dump, and in words anything that
read `BELOW` (it should now only appear when the heal really fell short on a target the measure
knew was missing that much).

### 38.3 Session 3 -- the M3 probe, in a party (20-30 min)

This one needs **a party with one other player** (anyone; a second account works; if the beta has
follower dungeons, a follower party also answers most of it -- say which you used). It answers
what the recorder (M3) is built on: which party readings are secret, which unit names a hit
arrives under, and whether a status bar gives a secret back.

1. In the party, out of combat, `/st probe`. Copy the report.
2. Pull a mob **with the party member fighting it too**, heal both of you and cast one Wrath,
   finish the fight, then `/st probe` again. Copy the report. (The probe snapshots the readings 2 s
   into the fight on its own -- **only if the fight is still on then**: a fight over in under 2 s is
   counted as `skipped` and answers nothing, so make it last.)
3. Things to read in the reports (you do not need to interpret them, just paste): `== shapes` now
   has three `tooltip` blocks (Healing Touch, Rejuvenation, Wrath); `== readings now` ends with
   `UnitGUID(party1)`, `UnitName(party1)`, `UnitLevel(party1)`, `UnitClass(party1)`,
   `UnitGroupRolesAssigned(party1)`, `C_Secrets.ShouldUnitHealthMaxBeSecret(party1)` and three `bar
   ...` lines; a new `== unit combat tokens` section lists every unit name a hit arrived under and
   a `mirrored: <m> of <n>` line.
4. Open the game's own damage meter on the Healing tab after the fight and **write down your own
   healing done** for that fight. (M3 checks its own count of your healing against the meter.)

**Paste back** into `docs/probe/<build>-alpha4-party.md`: both reports, the meter's number, what
kind of party it was.

### 38.4 Session 4 -- a talent that changes a value (the open half of Q6; at your next talent point)

Last time a talent lowered Wrath's cost and the tooltip followed. Still unseen: a talent that
changes a spell's **amount** (heal or damage), not its cost or cast time.

1. Before spending the point, look at the talent tree and pick a talent whose text says it
   increases the healing or damage of a spell you have (for example an "Improved Rejuvenation",
   "Improved Moonfire", "Gift of Nature" -- whatever your tree offers at that point; if none is
   reachable yet, wait for the level where one is and do this then).
2. Hover the spell it changes in the spellbook: note the game's own text (e.g. `Heals the target
   for 48 over 12 sec.`) and our block's `avg` / `Heals` line.
3. Spend the point. Hover again. **Did the game's own text change?** Did our numbers change?
4. `/st probe` -- paste its `== talents` and `== spells against the previous run` sections.

**Paste back** into `docs/probe/<build>-alpha4-talent.md`: the talent's name and text, the spell's
text before and after, our numbers before and after, the two probe sections. If the game's text did
**not** change but the talent says it should, that is the one case SpellTuner keeps a place for.

### 38.5 Session 5 -- Q10: a low rank at level 20, and again after a level-up (20 min, twice)

Healing Touch Rank 4 is learned at 20. This is the measurement for a server-side downrank
penalty (`FOREVER-PLAN.md` §6 Q10).

1. At level 20 (or the first level at which you have Rank 4), `/st measure` on, hurt **in combat**:
   **Healing Touch Rank 1, Rank 4 and your highest rank, three casts each** (session 2's rules: hurt
   first by a mob that is still fighting you, heal yourself, one cast at a time, wait for its
   line).
2. `/st measure dump` -> copy.
3. **After the next level-up**, the same nine casts again and the dump again.

**Paste back** into `docs/probe/<build>-alpha4-q10.md`: both dumps, each with the level it was taken
at. What I look for: Rank 1 and Rank 4 landing inside their text's range at both levels means no
server rule; a shortfall that grows as the rank falls further below your level is a rule, and the
two dumps let me fit it. (A `below range, missing health not known` line means you were not hurt
enough, or the fight had ended -- redo that cast in combat.)

### 38.6 Session 6 -- the second class (20 min; the M2 exit needs two)

An alt of any mana class (priest, mage, shaman, paladin, warlock). At level 1-10 is fine.

1. Log in, `/console scriptErrors 1`. `/st`: the Spellbook pane (since 0.16.2 Spells -> Overview -> Whole book) lists that class's spells --
   screenshot it; anything missing or wrong? Export -> copy.
2. Hover the class's first heal or nuke: the block appears?
3. `/st measure` on: three spells, three casts each -- a priest's Lesser Heal, Smite and Power
   Word: Shield (a shield's absorb has no landing line -- say what it printed); a mage's Fireball,
   Frostbolt, Arcane Missiles; a shaman's Healing Wave, Lightning Bolt, Earth Shock; a paladin's
   Holy Light and Judgement. Heals on yourself while hurt; damage on a mob.
4. `/st measure dump` -> copy. `/st probe` once -> copy.

**Paste back** into `docs/probe/<build>-alpha4-<class>.md`: the export, the dump, the probe, and
the answers to 1 and 2.

**If you only have time for one session:** do 38.3 (the party probe) -- it is the one M3 cannot
start without.

## 39. WoW: Forever -- the recorder, the replay and the coach in game (1.0.0-alpha.5, 2026-09-28)

On the **beta client**, after §38 (or instead of any §38 session you have not done -- §38.2 step 4,
gross or effective, is still the one that decides whether gate 8 checks both sides). This build
adds M3: the **Recorder** and **Replay** modules now do something. Nothing here has run on a real
client yet; every step is the first time.

**Install** as in §38 (`./release.sh --install-forever ...`). At character select SpellTuner and the
three modules read the newest build (**0.16.3** as of 2026-09-30; it carries everything 1.0.0-alpha.5 and
later did).
`/console scriptErrors 1`; any error box: note it, carry on,
`/st dump` at the end of the session.

### 39.1 Session 1 -- record a pull (20 min, in a party)

A party with at least one other player (a follower dungeon counts -- say which).

1. `/st` -> Settings -> Modules: switch **Recorder** on, then **Replay** on. Chat says each loaded.
   Any error box here is the first thing to report.
2. Out of combat, cast Rejuvenation on the tank (or the other player) and wait 3-4 s.
3. Pull and heal a real pull of **at least 20 seconds with at least five of your own casts**. Cast
   one Healing Touch and **cancel it on purpose** (move, or press Escape) somewhere in the middle;
   remember how many you cancelled in total.
4. After combat wait two seconds, then `/st rec`. Expected: one line `1. <zone> <n>s <c> casts
   <e> events meter own <x> others <y>`. Write down `<c>` next to how many casts you think you
   made (the cast that started the pull counts too), and open the game's damage meter on Healing:
   is `own` your healing done for that pull? `own - others -` means the meter could not be read for
   that pull (empty, only part of it, or the next pull had already started) -- say which it was.
5. Two more pulls the same way (so three are kept); `/st rec` again.

**Paste back** into `docs/probe/<build>-alpha5-rec.md`: the `/st rec` lines, the meter's numbers
for each pull, how many casts you cancelled.

### 39.2 Session 2 -- validate, replay, coach (15 min, anywhere out of combat)

1. `/st validate 1` -- copy every line. Eight gates; the mana ones say `(modelled pool)`, the
   health one may say `max estimated` (on an excluded member's line too), the last one is `heals
   attributed ... only a shortfall is checked ...`. Where the meter was not read, the meter gates
   fail with `no damage meter reading after the fight (<why>)`. Which failed?
2. `/st replay 1`. The window opens with a row per party member; a grey line under the title says
   `health reconstructed from UNIT_COMBAT; party max estimated`. Press play at 1x for 20 s: do the
   bars move when you remember them moving? Does a cast you cancelled show as cancelled? Hover a
   health tick: it should say `Reconstructed health`, not recorded. **Screenshot** once mid-fight.
   After a few seconds the right column (suggested) fills in -- or a
   hint names the gate that failed and says `force`.
3. `/st coach 1` (or `/st coach 1 force` if it refused) -- copy the card. Its grey lines are grey
   (not `|cff888888...` as text). The card offers `safe / health / cheap / regen`: try
   `/st coach 1 safe` -- no new search; the replay's suggested column then draws that plan.
   (Since alpha.8 a solver plan decides only on the hits already taken, so it may differ from what
   an older build suggested for the same pull.)
4. `/st` -> Reports -> Review: three rows; hover each; press Play on one. The low-mana column reads
   `~N%` (modelled, the tooltip says so), and there is no Export button on this client.

**Paste back** into `docs/probe/<build>-alpha5-replay.md`: the validate lines, the screenshot, the
card, anything the Review tab showed that looked wrong (a `0 casts` row, an empty tooltip).

**If you only have time for one:** 39.1 -- without a real recording nothing else can be checked.

## 40. WoW: Forever -- practice and the binding imports (1.0.0-alpha.6, 2026-09-29)

On the **beta client**, after §39 (or instead of any §38/§39 session you have not done -- §38.3's
party probe and §38.2 step 4 still decide two things the code is waiting on). This build adds M4's
offline part: the **Practice** module works on Forever, and `/st binds check` reports what the three
import sources look like on this client. Nothing here has run on a real client yet.

Two changes you may meet in §39's steps:
- A coach card may now carry, as its second line, `NOT causal - sees this fight: max health of
  <name> estimated from this fight (no other recording of them)`. That is expected while only one
  recording of that party member exists: their max health is secret, so it is taken from **other**
  recordings of the same name and level, and with none the card says the plan saw this fight. After
  two or more pulls with the same person the line should go away.
- Whether the addon may read a party member's real max through a status bar is decided by §38.3's
  report (the line `bar UnitHealthMax(party1): ...`). Nothing to do here; it ships off.

**Install** as in §38 (`./release.sh --install-forever ...`). At character select SpellTuner and the
three modules read the newest build (**0.16.3** as of 2026-09-30; it carries everything 1.0.0-alpha.6 and
later did).
`/console scriptErrors 1`; any error box: note it, carry on,
`/st dump` at the end of the session.

### 40.1 Session 1 -- the imports on this client (10 min, anywhere, out of combat)

1. `/st` -> Settings -> Modules: switch **Practice** on (it loads Recorder and Replay first, which it
   needs). Chat says each loaded.
2. `/st binds check`. A copy box titled `SpellTuner binds check` opens with three sections --
   `== keybindings`, `== Cell`, `== Clique` -- each ending in an `importer:` line. Copy it whole.
3. Write down which of Cell and Clique are installed **and enabled** in the beta's AddOns folder
   (the report says `absent` for one that is not loaded) and which bars you use (Blizzard's,
   ElvUI / EllesmereUI, Bartender, Dominos).
4. `/st binds` opens the bindings window (since 0.16.2 a sheet over Simulate -> Practice). Press **Import from Keybindings**, then **Cell**, then
   **Clique** (the ones you have). Each prints what it took, a note per binding that casts on your
   target, and a line per binding it would not guess at -- copy those chat lines. An import adds on
   top of what is there; **Defaults** is the one reset.
5. For each key or mouse button you really heal with: does the window now show the right spell and
   rank? Anything invented, anything missing?

**Paste back** into `docs/probe/<build>-alpha6-binds.md`: the report, the chat lines of each import,
which add-ons and bars you have, and the answer to step 5. An importer is changed from this paste
only, never from memory.

### 40.2 Session 2 -- a practice fight (20 min, solo, out of combat)

1. `/st practice` (or `/st` -> Simulate -> Practice). Pick Party; leave the damage at its defaults
   for the first go. The spells offered should be the ones your book has (Healing Touch,
   Rejuvenation, Regrowth from level 12). Look at the bindings summary: since 0.16.1 nothing is
   bound until you import or add a binding (§41 item 1) -- do 40.1's imports first; note any
   binding that names a spell you do not have and what it shows for it.
2. Press **Start practice**. Hover a frame and press. Press deep in a GCD (it should say "Another
   action is in progress" at once) and right before a GCD ends (it should go off when it ends).
   Space pauses. Play the whole fight once. Your mana should regenerate between casts (since
   alpha.7; before, practice on Forever never gave any back).
3. When it ends the replay opens and the suggested column fills in after a few seconds.
   **Screenshot** once. Then `/st` -> Reports -> Review -> Practice: is it listed? Hover it; press
   Play.
4. A second fight: press **End** halfway. Does it reopen as a replay too?
5. While a practice window is open, press a key you did **not** bind: does it still do what it
   normally does?

**Paste back** into `docs/probe/<build>-alpha6-practice.md`: the screenshot, any chat lines, any
press that did nothing and said nothing, the answer to step 5, the damage defaults (too easy or
too hard at your level, with the numbers you changed them to), anything on the frames that does not
match what happened, and `/st dump` if an error box appeared.

**If you only have time for one:** 40.1 -- M4's exit needs the imports re-checked against the
Forever builds, and its paste is what an importer is fixed from.

## 41. WoW: Forever -- 0.16.1: your report of 2026-09-29 on build 70058 (10 min, out of combat)

On the **beta client**, build 70058. 0.16.1 answers the four points of your 2026-09-29 report.
**Install** as in §38 (`./release.sh --install-forever ...`); at character select SpellTuner and
the three modules read **0.16.1**. First do §38's opening step on this build (the probe into
`docs/probe/1.60.1_70058.md`, with a macro hovered first). Then:

1. **Practice offers only your own spells** (T24). `/st` -> Settings -> Modules: Practice on. Open
   Simulate -> Practice. The bindings summary no longer lists Lifebloom, Swiftmend or any TBC
   Cell default: 0.16.0 wrote those into your saved settings, and 0.16.1 drops that exact list once.
   With nothing bound it says `Nothing is bound - Import your keybindings, Cell or Clique, or add
   one, in Edit bindings.`, and **Start practice** says nothing is bound instead of opening a fight.
   Press **Edit bindings**: there is no **Defaults** button; the spell picker lists only families
   your spellbook has (Healing Touch, Rejuvenation, Regrowth as you train them); **+ binding** gives a
   row with a spell you have. Import from Keybindings (and Cell / Clique if you use them), then start
   a fight and heal with what was imported. Anything named that you do not have: note it.
2. **The block on a macro's tooltip** (T25). Put a macro that casts a heal (`/cast Healing Touch`,
   or `/cast [@mouseover] Rejuvenation`) on an action bar and hover it: the SpellTuner block should
   appear under it, the same as on the spell itself, once. Try a Blizzard bar and, if you use one,
   an ElvUI / Bartender bar. The shapes this rests on are the retail engine's, not yet seen on
   Forever: if no block appears, the probe's `macro` lines (in `== shapes`, after you hovered the
   macro) say why -- paste them.
3. **`/st measure dump` shows this version's lines** (T26). `/st measure dump`: the lines older
   versions left are gone from the box, replaced by one line `N older line(s) from earlier versions
   not shown - /st measure dump all`. `/st measure dump all` shows every line with its stamp
   (`[before 0.16.1] ...` for the old ones, `[0.16.1 70058] ...` for new ones). `/st measure clear`
   says how many it cleared, and a dump afterwards is empty. Then one measurement
   (`/st measure`, a Healing Touch on yourself, `/st measure`) and a dump: one line, current.

**Paste back** into `docs/probe/1.60.1_70058-0.16.1.md`: the probe report (as §38's opening step
says), in words what the practice summary and the picker showed before and after the import, which
bars showed the macro block (and the probe's `macro` lines if one did not), and the measure dump.

## 42. WoW: Forever -- 0.16.2: the new UI (three sessions, 20-30 min each)

On the **beta client** (build 70058 or whatever it is now; §38's opening step first if the build
changed). 0.16.2 is your UI request of 2026-09-29 built from `docs/SPEC-forever-ui.md` with every
recommendation you took (its section 8.1): the Spells group as a rail with one view per spell,
the flat look with no gold, the tooltip block redesigned, and windows that take turns (the replay
and practice take the main window's place, one ESC closes one thing, the main window hides in
combat). Everything in the spec's task list landed (T27-T43); nothing here has run on a real client
yet, and the shapes the tooltip's macro path rests on are still the retail engine's.

**Install**: `./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"`.
At character select SpellTuner and the three modules read **0.16.2** (or **0.16.3**, which carries it with §43's changes). `/console scriptErrors 1`;
any error box: note it and carry on, `/st dump` at the end of the session. Out of combat unless a
step says otherwise.

Where things moved (for §38-§41 on this build): the Spellbook pane is now **Spells -> Overview ->
Whole book**, with Export on its title row; the practice bindings window is a **sheet** over
Simulate -> Practice (**Edit bindings**, or `/st binds`); the tooltip and window settings are under
**Settings -> General**.

### 42.1 Session 1 -- practice, the macro block and the tooltip (20 min, solo)

1. **Practice (T27).** `/st` -> Settings -> Modules: Practice on. Simulate -> Practice. Lifebloom
   (from a Cell import) is not listed and not counted in `N bindings`. Press **Edit bindings**: the
   sheet's footer reads `1 binding kept for a spell you have not learned  [Forget]`, and its hover
   names Lifebloom. Import from Cell again: the chat report names Lifebloom as `skipped (not in
   your spellbook)`. Start a fight and press Lifebloom's key: nothing is cast. (The step before the
   install that section 10 asks for, the 0.16.1 wording beside Lifebloom, cannot be done any more:
   0.16.2 replaced 0.16.1.)
2. **Macro block (T28).** Hover a macro that casts Healing Touch on a Blizzard bar, then on an ElvUI
   bar. The block appears **once**, and its header reads `Rank N of M - macro`. Whatever happens, type
   `/st tooltip why` and copy the line (it names both paths and each step of the last macro hover).
   Then try a macro `/cast Healing Touch(Rank 1)`: note which rank the header names.
3. **Tooltip (T37).** Hover Healing Touch R2 on your bar: a blank line, `SpellTuner` with
   `Rank 2 of 2  Shift` at the right, then 4 lines. Hold Shift **without moving the mouse**: the detail
   lines appear (say so if they only appear on the next hover). Hover Mark of the Wild: two lines,
   no Shift hint. Settings -> General -> SPELL TOOLTIPS -> Detail lines -> With Alt: the hint now
   says Alt. Put it back to With Shift.

**Paste back** into `docs/probe/<build>-0.16.2-s1.md`: the `/st tooltip why` line from each bar, the
rank the `(Rank 1)` macro showed, in words whether each check held (and what you saw where one did
not), and a screenshot of one tooltip with and one without Shift.

### 42.2 Session 2 -- the look, Settings, the rail and one spell (25-30 min, solo)

1. **The look (T29, T30, T41, T43).** Nameplates no longer show through the window. No gold text in
   Spells, Practice, the bindings sheet, Review, the replay's header and run strip, or their hover
   tooltips (the debug console keeps its category colours). Borders are one crisp pixel at your UI
   scale; change the game's UI scale (Esc -> Options): still one pixel, without a `/reload`. The
   mana clock has a dark fill and a thin edge.
2. **Settings (T42).** Settings -> General -> APPEARANCE -> font offset **+2**: every SpellTuner text
   grows; in Spells the rail rows, the table rows and the card lines move apart and nothing overlaps.
   The slider stops at +2. Window scale **90 %**: the main window shrinks and stays where it was.
   Put both back (0, 100 %).
3. **The rail (T31, T35, T36).** Spells shows `MY SPELLS` with Healing Touch and Rejuvenation. Add
   Wrath with **+ Add**; with the picker still open, drag Moonfire from your spellbook onto the rail
   (say so if nothing happens), then right-click Moonfire off the cursor. Drag Wrath above
   Rejuvenation; remove it with the hover `x`; press **Undo**. `/reload`: the order is kept. If you
   train a new heal this session (Regrowth at 12), it appears with a dot; a new damage spell does not.
4. **One spell (T38, T39).** Healing Touch: the chip says Rank 1, the line under it compares it with
   Rank 2, and the R1 row has the orange bar and `best`. Click R2: the card shows 90 - 115 and crit
   135 - 173 (at +0 healing). Hover a row: the game's own Healing Touch tooltip with the SpellTuner
   block under it, beside the row. Cast a heal: the header's `~` mana changes within 2 s and the
   table does not flicker. Overview -> **Whole book**: every rank of every family has its own row;
   **Export** from its title row, Ctrl+A, Ctrl+C.

**Paste back** into `docs/probe/<build>-0.16.2-s2.md`: a screenshot of Spells at offset 0 and one at
+2, one of Healing Touch's view with R2 selected, the Export whole, whether the drop from the
spellbook worked, and anything that overlapped, flickered or showed gold.

### 42.3 Session 3 -- windows, ESC, combat and size (20 min; one short pull at the end)

Needs one recorded pull in Review (Recorder and Replay on; any pull from §39 will do).

1. **Takeover (T34).** Reports -> Review -> Play: the main window hides and the replay opens in its
   place with `< SpellTuner` in its header. Type `/st`: the replay closes and the main window opens.
   Play again and press **ESC once**: only the replay closes, and the main window is back on Review.
   Drag the replay, close it, reopen: it is where you left it.
2. **Practice takeover.** Start a practice fight: the main window hides; type `/st`: one chat line
   refuses. **ESC** pauses the fight; **ESC** again ends it and opens its replay without the main
   window flashing. The replay's back returns to Simulate -> Practice.
3. **ESC and strata (T33).** Open the debug console (`/st debug`) and a replay together: neither
   draws through the other; each ESC closes one of them. After one ESC test type `/st probe` and copy
   the `esc=` line from its `== windows` section.
4. **Resize (T32).** Drag the corner of Spells narrower: it stops at 860. Switch to Reports: it keeps
   its own width and the left nav stays where it was. `/st ui reset` puts every window back.
5. **Combat (T33).** With the main window open, pull something: it hides, and it comes back on the
   same view when the fight ends. (Settings -> General -> WINDOWS -> In combat -> Keep them open leaves it.)

**Paste back** into `docs/probe/<build>-0.16.2-s3.md`: the `esc=` line, in words each check that did
not hold (which window, what it did), a screenshot of any two windows drawn through each other, and
`/st dump` if an error box appeared.

**If you only have time for one:** 42.1 -- the macro block and practice are the two bugs of your
build-70058 report, and `/st tooltip why` is what the macro path is fixed from.

## 43. WoW: Forever -- 0.16.3: the coach and regen, practice recordings (branches `work/regen` and `work/recordings`, 2026-09-30; 15 min, solo, out of combat)

(§42 is the Forever UI build's.) On the **beta client**, with the Replay and Practice modules on.
This answers your 2026-09-29 report: "it does not tolerate non casting window to regen", and
"practice recordings so we can improve the code from such reports". The fights you play are the
report now: the planner reads them straight out of your beta SavedVariables with
`tools/import.lua` (docs/TOOLS.md §2), replays them on the same engine and changes the code against
the numbers.

1. **Play the same fight again.** Simulate -> Practice, the Party setup you played at 20:08
   (or anything at your level), about 45 s, healing the way you did. Press **End**.
2. **The replay.** In the replay window, pick **Solver: frugal** in the chooser. The score line
   now starts with **`used N`**: the pool at the pull less the pool now. It is the number the
   coach ranks on, and `spent` / `regen` follow it. Scrub to about 0:44 and compare the two
   columns' `used`. The suggested column should now have gaps where it waits outside the
   five-second rule. While it waits, the reason line under the column should say `resting is
   worth more` (counting the regen a cast would stop). It should end with noticeably more mana
   than it did (it had 24 at 0:43.9 on your fight). It must not let anybody fall lower than before
   for it. Note anything it does that you would not.
3. **Keep the fight.** `/st` -> Reports -> Review -> **Practice**, select the fight, press **Pin**
   (at most four stay pinned; the next eight fights no longer push it out). Every fight -- a
   practice fight, or a pull with the Recorder and Replay modules on -- is now stored with the
   spells it was played with (`kit`), and opening a replay also keeps your current ones.
4. **`/reload`** (or log out). SavedVariables reach the disk only then: until you do, the fight is
   in the game's memory and not in
   `E:\Blizzard\World of Warcraft\_classic_beta_\WTF\Account\124250034#1\SavedVariables\SpellTuner.lua`.
5. **Tell the planner** which fight and what you saw, in one line: "p1, the coach will not stop
   casting to regenerate" -- `p1` is the newest practice fight, `1` the newest pull, as in the
   Review list. A screenshot of the replay helps as before. The planner then runs
   `bash tools/run.sh tools/import.lua list`, `report p1` (your replay beside every strategy),
   `replay p1 --strategy solver-frugal`, `coach p1` and the rest. Your 20:08 fight is already a
   fixture the suites run on: `tools/data/practice/1790701698.lua`. Practice fights stored by
   0.16.1 or earlier, before fights carried their spells, still work: their spells are read back
   off the fight's own heals, exactly for every spell the fight cast. A pull stored before then is
   replayed with your last spells and says so.
6. **TBC** (only if you play the anniversary client): the coach card's first line now reads
   `used: you N   best N   diff N`, and its rows read `N used (N spent)`.

**Paste back**: the `pN` you pinned, and in words what the suggested column did differently.

## 44. The refactor plan's checks (`docs/PLAN-refactor-ux.md` section 9; waves 1-8, the next build)

Paste back as in section 41. Out of combat unless a step says otherwise. The items keep the plan's
numbers; wave 1 (T45-T47) needs items 3 and 15, wave 2 (T48-T50) adds 4, 6, 8, 10 and 14, and wave 3
(T51-T53) adds 1, 2, 7, 9, 11 and 12, wave 4 (T54-T56) adds 5 and the TBC load-list smoke line
(W4), wave 5 (T57-T58) adds 16, and wave 6 (T59-T61) adds 17's TBC half, and wave 7 (T62-T63) adds 18 and the kit line (W7), and wave 8 (T64-T65) adds 17's Forever half and the settings line (W8). Item 13 waits for P35's pass over this section.

**TBC.**

1. **Cat form reload (B1).** Shift to Cat, `/reload`. The clock and the Advisor work in caster form
   afterwards; `/md profile` says `usesMana true`. Also paste
   `/run print(UnitPowerMax("player", 0))` while in Cat form (expected: your mana max, not 0).
2. **Tree aura (B2).** With a second resto druid in Tree of Life in your party, stay in caster form and
   open `/md`: no Tree label in the header, the numbers do not flip when they shift or leave range.
3. **Text (B3).** `/md verify`, `/md unlock`, `/md window 99`, and a gear change that moves an efficient
   rank: no boxes; paste the verify block.
4. **Casts under a rolling HoT (B9).** Keep Lifebloom rolling on the tank and hard-cast Healing Touch
   three times in one pull, **pressing the Healing Touch button again two or three times during one of
   the casts**; then move to cancel one cast. `/md replay 1`: three full cast bars, one cut. Also paste
   `/run local f=CreateFrame("Frame") f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED") f:SetScript("OnEvent",function(_,e,...) print(e,...) end)`
   and then move during a cast: the line shows `player`, a cast GUID and the spell id.
5. **`xpcall` passes arguments (P11).** `/run print(xpcall(function(a, b) return a + b end, print, 2, 3))`
   on TBC and on Forever: expected `true 5` on both. Paste both lines.
6. **Bloom (B10).** After a dungeon with Lifebloom, `/md calibrate` lists a bloom line; the Waste view
   has a Lifebloom bloom row.
7. **Run replay (B21, B22).** `/md replay run 1`, let it cross into pull 2, drag the scrubber to the
   middle: the run jumps there. Pull a mob while the run is playing: at most one chat line, and the
   replay pauses.
8. **Two runs (B12).** Stop a run, drink a potion, start a run: `/md run status` shows no potion.
9. **Long lists (P9).** Open `/md` -> Reports -> Review on a run with more than 30 pulls: the list ends
   with `... and N more (scroll: not yet)`, and N plus the rows shown is the run's pull count.
10. **Pins (B14).** Pin three fights in `/md` -> Reports -> Review: the third is refused with a line.
W4. **The split load list (T56).** With the new TOC installed, `/md verify`, `/md simrun`,
   `/md regentest` (it answers "you are at full mana" or starts) and `/md coach` each answer in chat;
   a silent command means its file is missing from the TOC.
16. **Reload mid-fight (P14).** `/reload` mid-fight on TBC: the clock shows the in-combat projection at
   once.
17. **Commands (P17, the TBC half).** `/md help` lists the same 27 rows as before and the About tab the
   same commands; `/md config`, `/md settings`, `/md bindings`, `/md tip` and `/md calib` still do what
   `/md options`, `binds`, `tooltip` and `calibrate` do.
18. **An unreadable address (P18).** `/md replay foo`: `replay: no recording foo.` and no window (it used
   to open your newest fight). `/md replay 1` and `/md replay p1` still open.
W8. **Settings defaults (P20).** On a profile that never moved them, `/md` -> Settings -> General still
   shows 85 and 30 on its two sliders (a regression check: the defaults moved to `Engine/SimModel.lua`).

**Forever.**

5. **`xpcall` passes arguments (P11).** The same line as TBC's item 5, on Forever: expected `true 5`.

10. **Pins (B14).** Pin three fights in Review: the third is refused with a line. Pull nine times: the
    ninth is listed.
11. **Scale before replay (B17, B18).** `/reload`, set Window size to 80 % before opening a replay, then
    `/st replay 1`: it opens where you last left it; the window borders are one crisp pixel.
12. **Practice icons (B23).** In practice, point at a tank's Swiftmend icon and press a bound key: it
    heals the tank.
14. **Coach address (B16).** `/st coach 2:7`: a refusal, no card.
15. **Client (P3).** `/st dump`: the first line says `forever`.
17. **Commands (P21, the Forever half).** On Forever, with Replay on: `/st validate 1` and `/st coach 1`
    answer as before; `/st help` lists replay, validate, coach and no coachrun.
W7. **The kit (P19).** With the Replay module on, `/st replay`, `/st coach N` and a practice fight behave
    as before; after `/reload` the character's `SpellTunerDB` still carries `kit` (written when the kit
    was first built this session and again only when the spellbook or crit changed). TBC: `/md coach N`
    and `/md practice start` as before.

## Reporting
Paste the `.logs/*.txt` files (or their names if committed locally) and, for §3/§4, the
raw numbers. `/md profile` output is welcome with any report. I turn them into
`Data/SpellData.lua` / `Engine/*.lua` changes and record the outcome in
`docs/DECISIONS.md` + `docs/HISTORY.md`.
