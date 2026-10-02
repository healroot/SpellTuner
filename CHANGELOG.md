# SpellTuner changelog

What changed, for players. `./release.sh --publish` sends the section of the version being
published to CurseForge; the developers' log is `docs/HISTORY.md`.

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
