# SpellTuner changelog

What changed, for players. `./release.sh --publish` sends the section of the version being
published to CurseForge; the developers' log is `docs/HISTORY.md`.

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
