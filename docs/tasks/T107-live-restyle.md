# T107 -- Live restyle conversions

Status: **built** 2026-10-02 on branch `next/T107`, base `7da7943` (0.16.6). Wave N4 of
`docs/SPEC-next.md`, batch B, alongside T103 and T106. Waiting for the integrator.

Rebuilt from the stopped attempt on `saved/T107-partial-2026-10-01` (857f2d2 the failing test,
9c1d7c3 the implementation, both on `319f6cb`). Between `319f6cb` and `7da7943` only the version
lines, docs and `R-classicui.md` moved, so both commits were cherry-picked unchanged. Every
claim in their messages was checked again on this base (counts below). This file is new. That
branch can be deleted once this one is merged.

## The task (docs/SPEC-next.md section 11, row T107; 2.2, decision 4; R-styles.md 1.3, 6)

> **Live restyle conversions.** The ~36 creation-time accent reads and the high-traffic panes'
> text colours become registered regions or `STYLE_CHANGED` re-renders; the "Reload to finish"
> line counts what is left.

The files the task owns, and the only ones edited apart from this one:

- `UI/Style.lua`, `UI/Dashboard_Rows.lua`, `UI/SpellsPane_Forever.lua`, `UI/SpellsView_TBC.lua`,
  `UI/SpellRail.lua`, `UI/ReplayWindow.lua`, `UI/Dashboard_Simulate.lua`, `UI/Options_About.lua`,
  `UI/DebugConsole.lua`, `UI/Tip_TBC.lua`
- `tools/restylecheck.lua` (new)

No TOC line, no setting (`MD:RegisterDefaults` is not called, so `defaultscheck` keeps its
counts on both flavours), no slash verb and no client call.

## What was built

### The kit (`UI/Style.lua`)

A style switch (`UI.SetStyle`, T94) rewrites the palette and the tokens in place, repaints every
`UI.skinned` region and fires `STYLE_CHANGED`. It did not reach a colour **copied** out of a
token when a region was made. Two mechanisms now carry the switch to those regions. Both run in
one `STYLE_CHANGED` handler, registered at the end of `UI/Style.lua` so it runs before every
pane's own re-render.

1. **`UI.Tint(region, how, name, alpha)`.** A region whose colour is a **name** is painted
   through it:
   - The name is `"accent"`, a `UI.PALETTE` fill or a `UI.TEXT` token.
   - `how` is the setter: `text` (`SetTextColor`), `texture` (`SetColorTexture`), `vertex`,
     `border`, `backdrop` or `bar`.
   - `alpha` nil passes what the replaced call passed: a fill's own alpha, or r, g, b only for a
     token or the accent.

   It paints now and records the name in `UI.tinted`, a weak-keyed table, so the registry never
   keeps a region alive. `UI.RepaintTints()` repaints every record from its name.

   A text tint whose font string now shows a colour it did not paint (someone painted it by hand
   since) is forgotten, not repainted. A texture's colour cannot be read back in the client, so
   its record is trusted. Every site that paints a tinted texture by hand afterwards calls
   `UI.Untint` first: the rail's row fill, the table's rows, `TintText` / `TintFill` and the
   slider's ends. `UI.TintColour(name)` gives a name's colour now.
2. **The follow, `UI.FollowTokens()`.** It covers every font string under a SpellTuner window,
   meaning the top frame of any `UI.skinned` region, that is **not** tinted:
   - If its colour is a token's colour in the style just left, it gets that token's colour in
     the new one.
   - Every colour code of such a token in its text is swapped the same way (`UI.SwapCodes`). An
     escaped `||c` is text and is left alone.

   It never guesses:
   - A colour two tokens shared that now differ is left alone, because which token it was cannot
     be told.
   - A subtree marked `restyleExempt` is never entered.
   - A secret text (`MD.API.IsSecret`) is never read.

   This is what reaches the font strings of the panes T107 does not own: Settings, Review's
   notes, Waste, the Sim window and the bindings sheet.

3. **What is left: `UI.Restyle`.** It covers what neither mechanism reaches: a fill copied into
   a texture, or a code captured in a local, in a file outside this row.
   - `UI.Restyle.LEFT` is `{ { pane, label, file, what } }`.
   - `UI.Restyle.Left()` gives `n, labels`.
   - `UI.Restyle.Line()` gives `"N windows finish changing after a reload: A, B"`, or nil when
     nothing is left. This is Settings' reload line (decision 4).

   `restylecheck` measures every entry as left and finds nothing undeclared. Two entries remain,
   both one edit away in files outside the row. **Integrator lines** below remove both and empty
   the list (Deviation 1).

Also in the kit:
- `UI.AccentSpec(a)` gives `{ ref = "accent", a = a }`, a colour spec `UI.StylizeFrame` /
  `UI.Skin` keep as a name.
- `UI.StylizeFrame`'s unthemed path now resolves a spec through `UI.SkinColour`.

The kit's creation-time reads became tints:
- separators, a titled pane's rule, its shadow and its title;
- a button's background and edge;
- the selection hover and bar;
- the rail: its title, rule, empty line, drag line, thumb, row fill, bar, tag, dot and name;
- the mask and its text, and the sheet's accent edge and title bar;
- the check box: its fill, highlight and enable / disable colours;
- the edit box's enable / disable colours;
- the slider's thumb, label and ends;
- the grip's lines;
- the kit tooltip's backdrop and edge.

**One visible change under Ellesmere, from the kit, intended** (spec 5.1's button / field edges):
under `UI.PIXEL`, `CreateButton` and `CreateCheckButton` no longer paint the `border` fill over
the edge the skin just gave the role.
- Under Flat that edge **is** `border`, so Flat is byte-identical (`stylecheck` and the Flat ->
  Ellesmere -> Flat round trip below).
- Under Ellesmere, a button built while Ellesmere was active used to keep Flat's `border` edge
  forever. T94's capture saw it as a recolour. It now shows Ellesmere's white 0.30 / 0.20 edge,
  the same edge a button built under Flat gets after a switch.

### The panes

- **`UI/Dashboard_Rows.lua`.** These are now tints: the per-mana bar, the row fills (`rowAlt`,
  `suggested`, `selected`), the accent mark, the hover, the scroll thumb and the header rule.
  `opts.headerColor` also takes a **token name** (`"label"`), read at each render; a colour code
  is kept as given.
- **`UI/SpellsPane_Forever.lua` (Forever) and `UI/SpellsView_TBC.lua` (TBC).**
  - Every `SetTextColor(UI.RGB(..))` and accent read at creation is now a tint: the header, the
    strip, the chip, the card, the footers, the separators and the overview's title and hints.
  - The tables pass `headerColor = "label"`.
  - Each re-renders what is shown on `STYLE_CHANGED`: `SpellsPane:StyleChanged()`, and the TBC
    view through its `onChange`, the host's `Refresh`. Their rows are token codes built at
    render, so a re-render is the conversion.
- **`UI/SpellRail.lua`:** the Undo line, the picker's section titles and rules, the range column,
  the placeholder and the tip.
- **`UI/Dashboard_Simulate.lua`:** the "What if:" title, labels and placeholders.
- **`UI/Options_About.lua`:** the command column.
- **`UI/Tip_TBC.lua`:** `GOLD` is the `tipGold` token's own table, an alias of `accent` that a
  style rewrites in place. `Accent()` is `UI.TEXT.accent`, read at each call.
- **`UI/ReplayWindow.lua`:** the scrubber's thumb, the defensive icon's edge and the band's word
  are tints. **The unit frames are `restyleExempt`**: they are the author's Cell layout, the same
  under every style (5.1).
- **`UI/DebugConsole.lua`:** the copy box's accent edge is an `AccentSpec`. **The log is
  `restyleExempt`**: its category colours are the legend (5.1).

## The checks

### `tools/restylecheck.lua` (new; forever, tbc): forever 44, tbc 49

On the parent `7da7943`, with this suite: **forever 21 ok, 23 failed; tbc 22 ok, 27 failed.**
After: **forever 44 ok, 0 failed; tbc 49 ok, 0 failed.**

The suite loads the flavour's whole TOC, logs in, turns the three modules on (Forever), and opens
the window the way a player does. The stub's frame metatable gets `GetChildren` / `GetRegions` /
`GetObjectType` / `GetTextColor` for this suite only.

1. **The source scan:** the ten files carry no colour copied out of the accent or a token into a
   setter (the kit's own palette definitions excepted, by line).
2. **`UI.Tint`:** paints now, r, g, b only for a token, a fill with its own alpha.
3. **Flat, every view twice:**
   - Forever: Spells Overview and a family, Review, Practice, the bindings sheet, Settings
     General / Modules / About, the debug console and its copy box.
   - TBC: the same, plus Waste and Build a fight.

   Each view opens and shows regions.
4. **Flat -> Ellesmere:**
   - Every region that showed Flat's accent shows Ellesmere's at an alpha the view showed it at,
     or Ellesmere's value of the fill it was (`selected`). This holds per pane: spells, review,
     practice, bindings, settings, debug, copy, and on TBC waste and simulate.
   - The window's chrome follows.
   - The check is not vacuous: at least 30 accent regions are seen.
5. **What is left:**
   - Window, Spells and Settings: **nothing**.
   - Every other pane: exactly the files `UI.Restyle.LEFT` declares, both ways.
   - Every LEFT entry is outside the row and ASCII.
   - `Left()` and `Line()` are correct.
6. **The follow:**
   - It ran: tints repainted, font strings moved, frames walked.
   - An untinted string follows its colour and its code.
   - A `restyleExempt` subtree is untouched.
7. **Ellesmere -> Flat:** every region the window had is **byte-identical** to the first Flat
   paint.
8. A colour two tokens shared, that now differ, is left as it was. An escaped pipe is text.

### `make check`

`tools/check.sh`: **88 runs, all passed**.
- apicheck: 0 findings. textcheck: 0 findings.
- Every suite's count equals `tools/data/expected-counts.json`: 81 runs, nothing fewer and
  nothing more.
- The only notes are the two new `restylecheck` runs.

`luac -p` passes on all eleven files.

**The integrator variant was run too:** the three edits in Integrator lines 1 (Review's rule,
Practice's grey, `LEFT = {}`), applied in the working tree and then reverted. With them,
`restylecheck` is forever 44 / tbc 49 green with `UI.Restyle.Left() == 0` on both. `practiceui`
52, `practiceforever` 31, `reviewui` 50, `reviewforever` 22, `stylecheck` 34 + 34 and
`themecheck` 38 + 9 are unchanged.

## Integrator lines

1. **Bring the left-over count to 0** (the row's last clause). These files are outside T107's row
   and no N4 task owns them:
   - `UI/Dashboard_Review.lua:451`: replace
     `T.resultRule:SetColorTexture(UI.Fill("line"))` with
     `UI.Tint(T.resultRule, "texture", "line") -- T107`.
   - `UI/PracticePanel.lua`: delete line 100 (`local GREY = UI.Hex("muted") ...`), then replace
     each of the five `GREY .. ` with `UI.Hex("muted") .. ` (lines 114, 209, 396, 493, 527 before
     the deletion).
   - `UI/Style.lua`: replace the two-entry `LEFT = { ... }` inside `UI.Restyle` with
     `LEFT = {},`. Leave its comment, or reword it to "nothing is left since the wave N4
     integration".

   Then `UI.Restyle.Line()` is nil, and decision 4's reload line has nothing to show.
2. **T102's reload line**, when T102 is merged. `UI/ClockSettings.lua` shows the fixed text
   `Some windows finish changing after a reload` after any pick.
   - Show `c.reload` only while `UI.Restyle.Line()` is non-nil, with that line as its text.
   - With line 1 applied it never shows, so `tools/clocksettings.lua`'s "the reload line shows"
     clause must be re-based. The re-based clause: the line is hidden when `UI.Restyle.Left()` is
     0, and shows `UI.Restyle.Line()` otherwise.
   - If line 1 is not applied, T102's line can stay. The fixed text is the spec's wording, and
     `Line()` adds the count and the panes.
3. **`tools/data/expected-counts.json`:** `"restylecheck/forever": 44`, `"restylecheck/tbc": 49`.
4. **`tools/check.sh`:** nothing (a new `tools/*.lua` is a suite by default).
5. **`CLAUDE.md`, repo table:**
   - `UI/Style.lua`'s row: "**T107:** `UI.Tint(region, how, name, alpha)` / `UI.Untint` /
     `UI.RepaintTints` (a region painted from a name -- the accent, a fill, a token -- repainted
     on `STYLE_CHANGED`; a hand-painted text forgotten), `UI.FollowTokens` (every untinted font
     string under a SpellTuner window moves from the style left to the new one, colour and codes;
     a shared colour and a `restyleExempt` subtree left alone), `UI.AccentSpec`, `UI.Restyle`
     (`LEFT`, `Left`, `Line`: what finishes after a reload); under `UI.PIXEL` a button's and a
     check box's edge is the role's (the skin's)".
   - `UI/Dashboard_Rows.lua`'s row: "**T107:** the bar, fills, mark, hover, thumb and header rule
     are tints; `opts.headerColor` a token name read at render (or a code)".
   - `UI/SpellsPane_Forever.lua` and `UI/SpellsView_TBC.lua`'s rows: "**T107:** tints; re-renders
     on `STYLE_CHANGED`".
   - `UI/ReplayWindow.lua` / `UI/DebugConsole.lua`: "**T107:** the unit frames / the log are
     `restyleExempt`".
   - `tools/`: "**`tools/restylecheck.lua`** (T107, forever / tbc 44 / 49): the source scan of
     T107's files, `UI.Tint`, Flat -> Ellesmere over every view (every accent region follows,
     nothing left in the window, Spells and Settings, the rest exactly `UI.Restyle.LEFT`), the
     follow, Ellesmere -> Flat byte-identical".
   - The Conventions list could gain: "**A colour a style can change is a name** (T107):
     `UI.Tint` or a token read at paint, never a copy at creation (`tools/restylecheck.lua`)."
6. **`docs/TOOLS.md` section 1:** `restylecheck` (forever, tbc) 44 + 49, with the eight sections
   above.
7. **`docs/TESTING.md` section 46 (styles):** both clients.
   - With the window open on Spells -> a family, run `/st ui style ellesmere` (TBC:
     `/md ui style ellesmere`). The rail, the rank table's suggested row and bar, the chip, the
     card and the headers take Ellesmere's accent and greys at once, with no reload.
   - Do the same on Reports -> Review, Simulate -> Practice and Settings.
   - The replay's unit frames and the debug console's log colours do not change.
   - `/st ui style flat` returns exactly to today's look.
8. **`docs/DECISIONS.md`:** "T107: decision 4 is live. A style switch repaints every region whose
   colour is a name (`UI.Tint`) and moves untinted font strings that show a token's colour
   (`UI.FollowTokens`). The replay's unit frames and the debug log are exempt. Under `UI.PIXEL` a
   button's and a check box's edge is the role's, so a button built while Ellesmere is active
   shows Ellesmere's edge (it showed Flat's `border`). Flat is unchanged, byte for byte."

## Deviations

1. **The left-over count is 0 for the window, the Spells view and Settings, but not yet for
   Review and Practice.** Their remaining sites are in `UI/Dashboard_Review.lua` (the result
   area's rule, a `line` fill copied at build) and `UI/PracticePanel.lua` (its `muted` code kept
   as `GREY` at build and used at every paint). Neither file is in the row's owned files.
   - The follow already repaints Practice's grey text at the moment of the switch. A later
     re-render brings Flat's grey back.
   - Neither can be reached from an owned file: a client texture's colour cannot be read back, and
     a captured string cannot be changed.
   - They are therefore declared in `UI.Restyle.LEFT`, which the suite measures as exact.
     Integrator line 1 gives the three edits that make the count 0, already run green in the
     working tree.
2. **What the row calls "STYLE_CHANGED re-renders" are mostly tints and the follow.** Only the two
   Spells views re-render, because their rows are codes built at render. Elsewhere a region
   carries its name (`UI.Tint`), or the follow moves a font string already painted. Settings,
   Review and Practice are reached this way without editing their files.
3. **The stopped attempt's commits were cherry-picked, not rewritten.** Their messages name
   `319f6cb`'s counts. Those counts are the same on `7da7943` (above).
