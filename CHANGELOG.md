# SpellTuner changelog

What changed, for players. `./release.sh --publish` sends the section of the version being
published to CurseForge; the developers' log is `docs/HISTORY.md`.

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
