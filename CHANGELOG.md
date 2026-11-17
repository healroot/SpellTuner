# SpellTuner changelog

What changed, for players. `./release.sh --publish` sends the section of the version being
published to CurseForge; the developers' log is `docs/HISTORY.md`.

## 0.18.2

### Faster, lighter (players reported a freeze every few seconds)
- **Forever: no more freeze when you cast.** Every cast used to re-read the whole spell book
  (and, since 0.18.1, every rank you have not learned yet). A cast now reads only its own
  cost; the book is read again only when your spells, talents, level or gear change, and out of
  combat after a buff or a spell's text changed. A light background check catches anything
  missed, a few spells at a time, never in combat.
- Ranks not learned yet are read only for the Spells window and the What if.
- Forever keeps only your own class's talent, rank and coefficient data (about 0.6 MB less).
- Less garbage every half second from the clock, and none from the feeds when nothing shows them.
- **TBC: fight recording is off by default.** It recorded the full combat log of every pull for
  replay and coach and kept the last 8 (over 1 MB on a played character). Your kept recordings
  stay; Settings -> Review -> Record fights turns it back on. A one-time chat line says so.
- `/st dump` has a `perf:` line (book reads, the last read's time, the addon's memory) for bug
  reports.
- **No stutter when you hover a spell or open the Spells window.** Reading the spell book
  (40-70 ms on a real character) is now spread over several frames, a few ms each, in and out
  of combat; until it is done the numbers you saw stay up. Hovering a spell after a buff
  changed re-reads only that spell's ranks, not the whole book. A buff that changes none of
  your numbers (healing, spell damage, crit, Spirit, mana, cast times) re-reads nothing.
  With the Spells window open on Overview in a fight, the table no longer redraws itself
  when your spells change -- the To OOM column keeps moving and the rest updates when the
  fight ends.
- **What if and the talent plan: much less work per click.** The What if numbers are worked
  out once per change instead of once per row and per hover, and the talent plan no longer
  rebuilds its talent list for every talent (about 1 MB less garbage per click).
- **`/st perf on`** times SpellTuner's own code while you play: each part's time, its worst
  call, what it allocates, every frame where the game hitched and how much of it was ours, and
  how often the garbage collector ran. `/st perf report` gives one block to paste into a bug
  report; `/st perf off` stops. Off by default and costs nothing off.

## 0.18.1

### The clock can stay on screen
- Settings -> Clock -> WHEN -> **Always visible** (or `/st clock always`): the mana clock stays up
  out of combat too, at any mana. Off (the default) keeps today's rule: in combat always, out of
  combat under 90% mana, hidden over 95%. Both lines.

### Forever: ranks you have not learned yet
- The Spells pane lists each spell's later ranks too, greyed and tagged `learn at N`, with their
  value, per mana and per second read from the game's own text for them. Hover one for the game's
  tooltip. They never take the best / max / eff marks while you cannot cast them.
- What if -> Level lets them compete: at a typed level every rank learned by then counts (and a rank
  learned above it does not). A rank learned above the level it is priced at has no +healing penalty;
  once the typed level passes its penalty start it has the usual one.
- Settings -> Model -> Show ranks not learned yet turns them off.

### Forever: crit in the numbers
- Value, per mana and per second now include your crit chance -- direct heals, heals over time and
  damage over time alike, since everything can crit on Forever. The card says `with crit` beside the
  average or total, and a HoT (Rejuvenation, Regrowth's over-time part) gets its own Crit line
  (`each tick x1.5`, with your chance). The crit size is assumed 1.5x until measured.
- Crit talents count: Improved Regrowth, Improved Moonfire, Holy Specialization, Tidal Mastery and the
  like are added to the spells they name (the card says `incl. Improved Regrowth 5 +50%`); Vengeance and
  Holy Power make crits bigger. Talents for every spell (Nature's Majesty) are already in your sheet.
- What if -> Crit % moves those numbers now, not just the card's Crit line. The talent plan moves crit
  too: crit talents, Intellect talents (Heart of the Wild: more Intellect, so more crit, assumed at 60
  Intellect per 1%) and Intellect into +healing (Natural Instinct, Mental Quickness).

## 0.18.0

### Forever: launch talents
- Numbers follow the launch talents and spell coefficients (preliminary, from talentsforever).
- Bloom counts: Rejuvenation and Regrowth show its heal, and per mana and the best rank include it,
  assuming the spell runs its full duration.
- What if -> Talents: try a talent build without respeccing. Rank steppers for the talents that touch
  the spell on screen, and Spirit where Bloom reads it.
- What if -> Talents moves durations too: Nature's Splendor makes Rejuvenation and Moonfire 3 s
  longer and Regrowth's over-time part 6 s longer, so more healing for the same mana.

- What if -> Level: price your spells at another level -- each heal rank's +healing share at that
  level's downrank penalty. The talent plan may spend all 51 points; past your level's points it says
  the level the plan needs. The What if's talent +/- rows are gone: the talent plan is the one place
  to change talents.
- Talent plan: What if -> Talent plan... opens your class's three talent trees with their icons. Plan
  a build with clicks (left adds, right removes, the game's tier rules): the spells' numbers follow the planned talents SpellTuner models (a blue dot);
  the others count for points and tiers only.

### Both: the clock, one bar (clock v3)
- The clock is one bar on both lines: the mana bar with its texts around it. **Line and Compact are
  gone**; a clock saved as Line or Compact becomes the bar with its default texts. For a text-only
  clock use the datatext or broker (ElvUI, EllesmereUI's DataBars, Titan Panel), which keep the words.
- A moving line for the five-second rule: an amber line crosses the bar during the five seconds after
  a cast. It is turned **on** for everyone; one click turns it off.
- **Your clock's look is moved once** to the new store, keeping what still applies (size, texture,
  colours, each text's place), and `/st dump` names what was dropped.
- The time at full now reads `FULL`, a refill always `FULL 0:45`, and a time never reads `0s`.
- Forever: when the game stops sending mana changes for about 3 s outside the five-second rule, the
  clock takes your mana as full (a guess to be checked in game).
- Forever: the refill time out of combat counts down to the second under a minute, and mana the game
  reports as gained (drinks and potions, to be checked in game) moves the clock at once; a gain that
  repeats (Mana Well) counts in the mp5 and the time, inside the five-second rule too.
- Settings -> Clock is one page: a live preview on top (In a fight, Running out, Filling, Full, Live),
  then Bar (width, height, shape, frame, texture, font, fill, background, the 5SR line), Texts (each
  text on or off with its place, size and colour; an off text shows only its switch), Presets
  (SpellTuner, EllesmereUI, with Undo) and When. Every control changes the clock on screen; one that
  would do nothing is hidden.
- Textures on both lines: SpellTuner's Soft, Flat, Smooth, Gloss, Striped, Minimal, the game's two,
  EllesmereUI's own bar textures (Pixels Dark, Atrocity, ...) when it is loaded, and your UI's bars
  through LibSharedMedia when an addon provides it.

### Forever: the talent plan, live
- The talent plan opens beside the What if (or the SpellTuner window) instead of over it, and every click changes the
  numbers at once -- no Use button. Closing it keeps the plan; What if -> Clear puts your talents back.

## 0.17.3

### TBC: every healing class
- Priests, shamans and paladins now get Practice, Coach, Simulate and the advisor on their own
  spells, as the druid does. Their plans are found by the solver; the druid's hand-written rules
  stay the druid's.
- Recordings keep the whole raid, not only your party, and the replay lays the frames out by
  subgroup.
- Overheal is counted by your own spell and rank. A heal the combat log credits to its receiver
  (another druid's Lifebloom bloom on you) is no longer counted as yours; your own blooms are,
  when your Lifebloom on that target has just ended.

### Mana clock
- The Bar layout (the time on a mana bar) is now the default for a new install, or after the
  clock's look is reset. An existing clock keeps Line, because the old default was saved with it;
  switch it in Settings -> Clock.

### Spells
- Forever: the share of +Healing (and of spell damage) each rank gets is now fitted from every
  gear change out of combat, not only the last one, and the card shows the range it is sure of
  (`80% measured (0.79-0.81, 4 readings, +0..+212)`). Until the range is narrow the rank keeps its
  estimate and the card says how much more bonus to swap. A small swap no longer overwrites a good
  measurement, so two ranks of one spell no longer show shares that cannot both be right.
- Shares measured by an earlier version are dropped: re-measure: swap gear out of combat.
- Forever: until a rank is measured, its share of +Healing and spell damage now comes from the
  coefficients talentsforever.com lists for Forever (preliminary until checked in game), not from
  Classic's rules. Its HoTs and Healing Touch get much more
  than in Classic: Rejuvenation 80%, Healing Touch Rank 2 57%, Wrath Rank 1 43%. The card says
  `20% x 4 ticks, 3 s ticks (measured 2026-10-23) (talentsforever)`. A spell the site does not
  list keeps the old estimate, and so does a spell over time whose tick period is neither in
  its text nor measured (Wild Growth, Insect Swarm, Mind Flay and others: `tick period unknown
  -- old rule`). A party heal takes the site's share, already per target (Prayer of Healing
  29%), not halved again.
- Forever: a measured share is kept with the level it was read at; after a level up it is
  measured again (the estimate shows meanwhile), in case a low rank's share moves with your level.
- Forever: the estimate now names each factor and is a prediction: the rank's share, a low
  heal rank's level penalty (5% of its share per level once you are 17 levels past learning it;
  `42.9% x 0.55 level 26 (from 17, -5%/level)`), and talents that multiply a spell (Naturalist's
  damage: `x1.05 Naturalist 5`). Damage ranks have no level penalty. A measured share still wins,
  and its card says whether the prediction agreed (`-- as predicted (80% x 0.75 level)`) or how
  far it was off (`unexplained x0.91`).

## 0.17.2

### Fixes
- TBC: no more freeze when you change gear or apply an enchant. The game announces a spellbook
  change several times on every swap, and SpellTuner re-read every spell's tooltip each time; it
  now does that only when your spells or talents really changed.

## 0.17.1

### What if
- A spell with only one known rank (Lifebloom on TBC, Starfall) keeps its strip, and with it the
  What if... button: the What if no longer disappears there.
- The line under What if... now compares the old and the new best rank with the same stats
  (`Best: Rank X -> Rank Y. With these stats Rank Y gives P per mana, Rank X Q (+n%).`), and
  says why when the new one gives less per mana (it is beaten, or under 40% of your best rank's
  heal, or the trade against max no longer pays). When the suggestion does not move it says `No change to the suggestion.`
- A new `+Spell damage` row, on both clients: a damage spell's Value and Per mana follow it, and
  its header shows `+N <School> damage what if`.
- Forever now reads your spell damage per school, so a damage spell's header shows it beside your
  mana.
- Forever now measures how much of your spell damage each damage rank gets, as it already did for
  heals: out of combat, change your spell damage (swap an item) and the What if uses the measured
  share for those ranks, and the RANKS note counts them as measured.
- What if opens as a drawer beside the window instead of a block above RANKS, so every rank stays
  in view while you change the stats. It opens on the window's left when the right would leave
  the screen; ESC closes the drawer first, then the window.

### Rank marks
- A spell's ranks now carry three marks instead of one "best": `eff` (the most per mana), `max`
  (the most per second) and `best` (the trade between them). A lower rank is best only when the
  mana it saves is worth what it loses per second: by default 1% more per mana for at most 4% less
  per second on damage, 6.7% on heals (heals also keep the 40% of your highest rank's heal).
- The RANKS tags, the card's Marks lines, the line beside the BEST chip and the spell tooltip's
  `Best` line say which rank holds which mark and why. Lifebloom shows `best` on the way to cast
  it that wins (one cast, or rolled x3).
- Settings -> Review -> MODEL: `Trade-off: damage` and `Trade-off: heals` set the two trades.
- The trade now multiplies: a rank scores its per mana against max's times its per second
  against max's to the power of the trade-off, and is best when that beats max's 1.000. A small
  loss per second still trades at the slider's rate; a big one costs far more, so Starfire with
  +550 spell damage marks Rank 6 best instead of Rank 1. The words say the score (`score 1.075
  vs max 1.000`).
- Hovering any rank in RANKS ends with a `TRADE` block against max: per mana, per second, the
  score and the verdict (holds best, beaten by Rank N, under 40% of Rank N's heal, Rank N trades
  better, or the trade does not pay). Lifebloom's rolled rows say the same against their stack.
- With What if on, a rank's hover shows the What if numbers, as its cells do (it showed the live
  ones), and the line beside the WHAT IF chip shortens instead of being cut off at large fonts.

### Cast-time talents (Forever)
- Forever now reads your talent ranks. A talent that shortens a cast (Improved Wrath, Naturalist,
  Divine Fury, Bane and the rest) no longer lowers the estimated +healing / +damage share of the
  spells it touches: the estimate uses the cast before the talent, and says so
  (`cast 1.7 / 3.5 (1.5 + 0.2 Improved Wrath 2)`). When the ranks cannot be read it says
  `talents not read`. What each talent does comes from talentsforever.com until checked in game.
- `/st dump` has a `talents:` line.

### Commands
- /md is gone: use /st (or /spelltuner).

## 0.17.0

One Spells window and one spell tooltip on both clients: what TBC had, Forever now has, and the
other way round.

### The Spells window, the same on both clients
- TBC gets Forever's Spells window: your spell list down the left (add, remove, reorder, drag a
  spell in from the spellbook), Overview with My spells and Whole book, Export, and one page per
  spell with its ranks and a card for the selected rank (cost, cast, per mana, per second, casts
  to out of mana, reach, cooldown).
- The card says how much of your +healing each rank gets (`+Healing counts 70%`), on TBC from the
  model, on Forever measured from the spell's own text after a gear change, else estimated and
  marked so.
- The header shows your mana and your +healing (or +damage on a damage spell).
- TBC keeps what only it can do: After overheal (your measured overheal, now a check on the spell
  page) and Lifebloom's rolled x2 / x3 rows.
- The window is 860 x 560 on TBC too.

### What if..., on both clients
- What if... on a spell's page opens a small panel: type +healing, crit, mana or regen (and on a
  TBC druid, a form or Moonglow) and the ranks, the suggested rank and casts to out of mana
  follow. The changed numbers are drawn in your accent colour, a hover shows the live number
  beside it, and one line says what changed (`Suggested: Rank 12 -> Rank 6`).
- It is a lens on the Spells window only: the clock, the tooltips, the coach and practice keep
  your real numbers. Nothing is saved; Clear or a reload puts it back.
- Forever gets What if for the first time.

### One spell tooltip
- TBC's spell tooltips use Forever's block: Rank N of M, the suggested rank, per mana, per second
  and casts to out of mana. Hold Shift (or the key you choose in Settings) for the detail: the
  range, crit, After overheal, the comparison with your best rank, reach and cooldown, and how
  the number was worked out.
- The "Detail lines" key is now a setting on TBC too.

### More classes on TBC
- Priest, Shaman and Paladin get the Spells window and spell tooltips on TBC, with their heals and
  their damage spells (Smite, Holy Fire, Mind Blast, Shadow Word: Pain, Lightning Bolt, Chain
  Lightning, the shocks, Exorcism, Holy Wrath, Consecration). A druid's damage spells are listed
  too. Damage numbers are read from the spell's own tooltip; talents are not modelled for these
  classes yet, and the card says so.
- Fight review, coaching and practice on TBC stay the druid's.

### Settings
- Settings is two columns on both clients, with the same pages: General, Clock, Review (recording
  and the coach's model), About (and Modules on Forever). On TBC it is 860 x 560 like Forever's.

## 0.16.8

First release on CurseForge, in two packages of the same version: **TBC Anniversary** and
**WoW: Forever** (beta).

### The mana clock, rebuilt
- Mana and the five-second rule are shown together by default, on both clients.
- Three ways to show them: two bars (the default), one bar with a five-second overlay, or a
  mana bar with a small countdown.
- A new Text tab picks what each place on the clock shows -- the label, time to out of mana,
  time to full, mana %, mana, mp5, the five-second countdown, or (TBC) your mana cooldown --
  plus the time format, size, outline and shadow.
- Width, height and scale for each layout (Line, Compact, Bar); Height now works on every one.
- The five-second-rule bar fills smoothly; on TBC it can also sweep with each regen tick.
- On Forever, mana numbers on the clock are modelled and marked `~`.

### Settings and looks
- Settings -> Clock, with a live preview.
- Two styles, Flat and Ellesmere (which follows EllesmereUI's accent and font when it is
  installed), and "Use my class colour". A style change applies at once, without a reload.
- Integrations: the clock and your regen as LibDataBroker feeds (Titan Panel, ChocolateBar,
  EllesmereUI's data bars) and as ElvUI datatexts; move the clock with EllesmereUI's `/unlock`.

### More classes on WoW: Forever
- Paladin, Shaman and Priest get spell tooltips, rank tables, fight review with coaching, and
  practice. Group heals, Chain Heal and Binding Heal are modelled.
- Spell tooltips show a spell's cooldown, how many targets it can reach and any lockout, read
  from the spell's own text.
- A damage dealer's spell list starts with damage spells.
- On TBC the full toolkit stays the druid's; other classes get the mana clock.

### Fixes
- Practice and replay: a hard cast no longer shows a grey "instant" global cooldown sweep after
  it lands.
- Spells -> Overview -> Whole book shows its rows as soon as it opens.
