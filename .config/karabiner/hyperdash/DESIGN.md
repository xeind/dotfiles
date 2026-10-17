# hyperdash design rules

The rules for `index.html`. Tests hold most of them (see §0 and Checks); the
rest is held by review.

Where a table has a "Migrate" column, it records the values the page used
before these rules (v1, 2026-10-17) and where each one went.

## 0. Who owns what

| Concern | Owner |
|---|---|
| Colour values | The four `:root[data-theme=…]` blocks in `index.html`. |
| Theme sources | Manila and the other three come from `~/dev/xeind.net/src/styles/global.css`; hue and role follow that file, the panel's own steps (`raised`, `hover`, `q0`–`q4`, groups) live here. |
| Size, space, radius and type tokens | The shared `:root` block in `index.html`, the only place a size is written. |
| Type, shape and space scales, colour literals, motion | `tests/design.test.mjs` |
| Colour floors, group distance, quantity steps | `tests/colour.test.mjs`, with the pair list in `tests/colour_pairs.mjs` |
| The 4 px rhythm and the 2x pixel grid, in WebKit | `tests/grid.test.mjs` |
| A rule for every state of every control | `tests/states.test.mjs` |
| Keyboard and pointer do the same thing; footer hints | `tests/interaction.test.mjs` |
| One height per page, fades, tooltips | `tests/height.test.mjs` with `height_probe.js` |
| Token parity across themes | `tests/model.test.mjs` ("every theme defines every colour token") |

The site's design system is the parent. The panel departs from it in two
places, on purpose: rounded corners (a floating panel, which the user asked
for) and a soft shadow on the card and the about overlay (they float over
other windows). Everything else follows the site: Geist and Geist Mono with
one job each, tokens only, no motion.

## 1. The look

A dark rounded card, 368 px wide, floating over whatever is on screen. One
large numeral, a keyboard drawn as a heatmap, and dense rows of mono labels
and keycap chips. Quantity reads as brightness, groups as hue. Nothing moves
and nothing changes size: the panel is a fixed instrument, not a page.

## 2. Themes

Manila (default, dark), Kozo (light), Nightingale (dark), Blueprint (blue).
A theme changes colour only; it never changes size, type or layout. `T` on the
overview cycles them; the host saves the choice.

Blueprint draws in blue ink only, with cyan as its single hue. Its six group
colours sit between OKLCH hue 190 and 275. The semantic colours (`--up`,
`--down`, `--warning` and their backgrounds) are the exception: they keep
their green, red and amber.

## 3. Colour

### Never write a colour

Every colour is `var(--token)`. A token exists in all four themes or in none.
In CSS this is checked: the checker fails any `#hex`, `rgb()`, `hsl()` or
`okl*()` outside the theme blocks. In markup and JS it holds by inspection
(SVGs use `currentColor`, scripts set `var(--…)`); `colour.test.mjs` lists
every script line that writes a colour.

### The text ladder

From brightest to dimmest. Use the step for its job, not for its look.

| Token | Job | Used by |
|---|---|---|
| `--text` | Primary content: list labels, the numeral, titles | `body`, hover and pressed states |
| `--soft` | Values and controls at rest | counts, chips, pill, seg, close, header icon, theme button, time chips, problem text |
| `--muted` | Mono labels and second lines | legends, chart text, times, detail title, insight detail, footer keys, the pill arrows, the idle readout |
| `--faint` | Captions and status | status line, footer labels, group caption, app names, zero-count cells |
| `--dim` | Data that is absent or not chosen | unused bindings, grey dots in highlight mode |
| `--ghost` | Keys with no presses | the heatmap keyboard |

Most of the panel is apparatus around a few numbers, so `--faint` is common.
Running content never goes below `--muted`, and `--faint` never goes below
APCA's Lc 30, the minimum for any text.

### Surfaces and edges

`--card` → `--raised` (inset surfaces, chips) → `--hover` → `--line` →
`--line-strong`. A surface is set apart by one tone step plus
`1px solid var(--line)`. `--edge` and `--edge-soft` are the card's own rim.
The date box in the header (`.pill`) is the one dashed edge: square, with a
1.5 px dashed `--line-strong` border, the site's own border style.
It sits at the same place on every page: the title takes the free space, so
the box and Close share one right edge, and the label has a fixed minimum width
(10ch) so the box is the same size for every month and day label.

Steps are about 3 OKLab points apart in Manila and Nightingale. Two are
short: Kozo's `--card` to `--raised` is 2.1, and Blueprint's `--raised` is
darker than its card (L 36.1 against 41.3), so a row hover there darkens.

### Data colour

- Quantity: `--q0`…`--q4`, more is brighter (Kozo: darker). Text on a step uses
  `--q0t`…`--q4t`.
- Groups: six tokens, `--g-navigate`, `--g-pointer`, `--g-launch`,
  `--g-windows`, `--g-capture`, `--g-system`. Used for dots, swatches, the
  group bar, row glyphs and the tint behind layer chips. Never for text.
- Semantic: `--up`, `--down`, `--warning`, `--info`, each with a `-bg`.
- Coverage: `--cov-recorded`, `--cov-locked`, `--cov-asleep`, `--hatch`.

### Floors

`tests/colour.test.mjs` checks these on every surface and state a colour
sits on (card, raised, hover, line, accent-bg, the quantity steps, the badge
backgrounds, the group-tinted chips), in all four themes. The test fails if a
CSS rule sets a colour that `tests/colour_pairs.mjs` does not name, or names
the wrong token.

Contrast is APCA Lc (APCA-W3 0.1.9), as a magnitude, on the worst surface.
APCA's font table asks Lc 113 for 13 px text and Lc 125 for 10 px. No colour
reaches that, so the floors are APCA's use-case levels, one per job.

| Role | Floor | Who |
|---|---|---|
| Content | Lc 75 | `--text`: labels, numeral, titles |
| Values and controls | Lc 60 | `--soft`, `--accent-soft`, pressed states |
| Labels, status, key letters, icons, focus rings | Lc 45 | `--muted`, `--up`, `--down`, `--warning`, `--info`, `--q*t`, line icons |
| Captions | Lc 30 | `--faint`; also group marks (dots, swatches, bars, row glyphs) |
| Absent data | Lc 15 | `--dim` |

`--ghost` (the letter on a key with no binding) is exempt: it is decoration.
Each text step owns a 15-Lc band, so the ladder holds its order by
construction.

Text never sits on `--line-strong`. Kozo's `--text` there is Lc 56 and its
`--soft` Lc 47, both under the value floor of 60. Icons may (floor 45).

Groups: every pair of group colours at least 8 apart (OKLab × 100) in normal
vision and under protan, deutan and tritan simulation (Machado 2009,
severity 1). The tritan case also stands in for every viewer at dot size: a
3.6 px dot is too small for blue-yellow vision. Group colours are never text:
layer chips and monograms write `--soft` on the group tint. As group-coloured
text they reached only Lc 29.3 to 58.8.

Quantity: `--q0`…`--q4` take equal OKLCH lightness steps (within 15 % of the
mean step), and `--q0` sits at least 3 from `--raised`, one surface tone
step, so a zero-press key never looks unbound.

APCA reads 0 for surface-on-surface pairs in the dark themes; surfaces are
held by the OKLab tone step instead.

## 4. Type

### Families

| Face | Job |
|---|---|
| Geist (`--sans`) | Content: names of things, titles, the numeral, sentences, footer labels |
| Geist Mono (`--mono`) | Apparatus: keycaps, counts, times, labels, legends, status, axis text |

The page loads no `@font-face`; it relies on Geist being installed and falls
back to the system face.

### Sizes

Six sizes (before: 13, from 8 to 26 px), written only as tokens. The tokens
live once in the shared `:root` block; a rule names a token, never a size.

Geist and Geist Mono share their vertical metrics (ascender 1.005 em,
descender 0.295 em, x-height 0.53 em, cap height 0.71 em), so one size gives
one x-height in either face. Mono beside Geist on one row is a step down the
scale, not a match: 11 beside 13 is 85 % of the x-height. At 13 px Geist's
x-height (6.89 px) is within 0.05 px of the system font's (6.84 px), so the
macOS sizes read at native size.

| Token | Voice | Size | macOS | Job | Before, also | Migrate |
|---|---|---|---|---|---|---|
| `--text-numeral` | Geist | 26 | large title | The numeral | | |
| `--text-title` | Geist | 16 | | Page title | | |
| `--text-content` | Geist | 13 | `systemFontSize` | Content rows: list labels, commands, sequences, insight titles, detail value, problem | 12.5 (`.cmd`, `.seq-title`), 13.5 (`.insight-title`) | → 13 |
| `--text-secondary` | Geist | 12 | callout | Second line of content: insight detail | | |
| `--text-label` | Geist | 11 | `smallSystemFontSize` | Uppercase labels beside Geist: pill, unit beside the numeral, footer | 11.5 (`.total-unit`) | → 11 |
| `--mono-key` | Mono | 11 | `smallSystemFontSize` | Keycaps, delta, list and sequence counts, detail chip | 11.5 (`.delta`, `.item-count`, `.delta.peak`), 12 (`.detail .chip`) | → 11 |
| `--mono-label` | Mono | 10 | `labelFontSize` | Labels, legends, chips, buttons, times, the 18 px monogram | 10.5 (`.detail-title`, `.chip`, `.appchip`, `.cmd time`) | → 10 |
| `--mono-caption` | Mono | 10 | `labelFontSize` | Status line, axis text, captions, notes | 9 (`.heat-legend`, `.info`), 9.5 (all of these) | → 10 |
| `--mono-monogram` | Mono | 8 | | Letter in a 14 px app-icon slot: 10 × 14 / 18 | | |

Moving to 13 widens command and sequence labels by about 4 %; long labels
already end in an ellipsis.

Captions moved from 9.5 to 10 px, the smallest macOS text size
(`labelFontSize`, caption and footnote styles). At 9.5 px the cap height
ends half way through a device pixel at 2x (13.49 px), the softest top edge
on the scale; at 10 px it ends at 14.2. The status line keeps its budget of
about 105 characters in two lines (`model.test.mjs` pins it) by dropping its
tracking to 0: 54 characters a line at 10 px, against 55 at 9.5 px and
0.02em.

### Weight

400 and 500, nothing else. 500 for the title, the numeral, keycaps, pills and
mono labels; 400 for content and running text.

### Tracking

| Value | Job | Migrate |
|---|---|---|
| −0.04em | The numeral | |
| −0.01em | Geist titles and list labels | |
| 0 | The status line, to hold 105 characters in two lines at 10 px | 0.02em → 0 |
| 0.02em | Mono in mixed case: notes | |
| 0.04em | All uppercase, mono or Geist | 0.06em (8 selectors), 0.08em (`.heat-legend`) → 0.04em |

Narrowing caps can never clip; widening can (the height probe tests
five-digit legend cells). Hence 0.04, not 0.06.

### Leading

Line boxes are tokens in whole pixels, so a block of lines is a whole-pixel
sum and lands on the 4 px rhythm.

| Token | px | Job | Geist's own line | SF's line |
|---|---|---|---|---|
| `--leading-numeral` | 26 | The numeral, in a 28 px row | 34 | 30 |
| `--leading-content` | 16 | Content lines at 13 px: insight titles, sequence titles | 17 | 16 |
| `--leading-secondary` | 16 | Two-line content at 12 px: insight detail | 16 | 15 |
| `--leading-prose` | 18 | Prose at 13 px: problem | 17 | 16 |
| `--leading-note` | 14 | Prose at 10 px: about | 13 | 12 |
| `--leading-readout` | 14 | Two fixed lines in a 28 px box: status, bin readout | 13 | 12 |

13/16 is the macOS body pair (AppKit gives SF 13 px a 16 px line). Geist is
taller than SF (1.3 em from ascender to descender, against 1.18), so its own
line at 13 px is 17; two lines of 16 keep the 32 px pitch the 4 px rhythm
needs. The status line and readout boxes are 28 px, so two lines of 14 fill
them. Before: 1.3 (16.9 and 15.6 px, so insight cards were 85.078 px tall
and the next one started at 166.078), 1.4 (13.3, 18.2 and 14 px) and 13.5 px
in a 27 px box.

### Baselines

Text of two sizes on one line shares a baseline. Centring each box instead
puts the baselines 0.355 × the size difference apart, since the baseline sits
(ascender − descender) / 2 below a line's centre. Flex rows set
`align-items: baseline` (`.total`, `.seq-title`). Open: `.item` (13 / 11,
1 device px apart) and `.cmd` (13 / 10, 2 device px) are centred grids.

### Case

- Uppercase: mono labels, legends, captions, status, pill text, footer labels.
- Sentence or title case: names of things (bindings, apps, sequences), insight
  text, problem text.
- Mono carries labels and figures, not sentences. Two notes break this today:
  `Pick a day (Enter) for its commands and sequences` and `App = front app
  before that second (1 s resolution)`. The second now fits one line at
  10 px. Open: set both in Geist at 12 px `--muted`.

### Numbers

Counts use `compactCount` in legends and `toLocaleString("en-US")` elsewhere.
Mono figures align by themselves. The Geist numeral carries
`font-variant-numeric: tabular-nums` so it does not shift as it counts; the
mono list counts carry it too, where it does nothing: Geist Mono has no
`tnum` feature, and every glyph is 0.6 em wide.

## 5. Shape

### Controls, radius and hit areas: one ladder

Control heights follow macOS's control sizes (mini, small, regular, large:
16, 20, 24, 28). Radius is a quarter of the height, as AppKit draws its
buttons, segments and pop-ups. All of them are tokens.

| Token | Height | Radius | Who |
|---|---|---|---|
| `--control-xs` | 16 | 50 % | The "i" button |
| `--control-sm` | 20 | `--radius-sm` 5 | Chips, delta, time chips, theme button, footer keys; pill arrows (round) |
| `--control-md` | 24 | `--radius-md` 6 | Seg, app chips, header icon, insight marker, keys (`--key`) |
| `--control-lg` | 28 | `--radius-lg` 7 | Header row, close (round), detail chip; the date box is square (0) |
| `--row-compact` | 24 | `--radius-md` 6 | Command row |
| `--row` | 32 | `--radius-row` 10 | List row; sequences use the same radius |

Other radii: card `--radius-card` 30; inset surfaces (detail, insight,
problem, about) `--radius-inset` 10 = 30 − 20 card padding, so they share
the card's centre; bar 999; round buttons and dots 50 %; app icons a
quarter of the size (3.5 at 14, 4.5 at 18); swatches and bar segments a
third (1.5, 3).

Migrate: 18 → 20 (chips, time chip, theme button, pill arrows, footer
keys), 22 → 24 (seg, app chip, header icon), 26 → 24 (marker), 26 → 28
(pill), 14 → 16 (`.info`), 30 → 32 (list row), key 25 → 24. Radius 7 → 6
(24 px controls), 8 → 7 (detail chip), 8 → 10 (rows).

Keys are 24 with a 4 px gap: a 28 px pitch, so the keyboard rows sit on the
rhythm. The keyboard is the US layout's number, top, home and bottom rows
plus Space; rows are named (`.row-home`), never numbered, so adding one
cannot shift another's offset. No control a user clicks is under 16 px,
with two old exceptions still open: the group bar segments (8 px tall) and the chart bins (6.8 px
wide). Both are also reachable from the keyboard.

### Depth

Two shadows: the card, and the about overlay that floats over it. Everything
else is flat: a tone step plus a 1 px `--line` border.

### States

Every control answers the pointer and the keyboard. `tests/states.test.mjs`
checks that each state below has its own rule.

| State | Looks like | Tokens |
|---|---|---|
| Rest | Its surface, ink `--soft` (names of things: `--text`) | `--card`, `--raised` or `--hover` fill |
| Hover | One fill step up | `--raised` → `--hover`; `--hover` → `--line` for text controls, `--line-strong` for icons; a row on the card → `--raised` |
| Pressed | Hover, plus ink to `--text`, or one more fill step | seg and app chips → `--line`; header icon and pill arrows → `--line-strong`; a row → `--hover` |
| Focus | A 2 px ring, never cut off | `outline: 2px solid var(--accent-soft)`; offset 1 px, or −2 px inside a box that clips (list, Insights, app bar); a bin draws a 2 px stroke |
| Selected | The accent set, not a hover look-alike | `--accent-bg` fill, `--accent-soft` ink, `--accent-edge` border (seg, app chip, open "i"); a row: `--hover`; a key or bin: the `--accent-soft` ring |
| Disabled | Takes its space, draws nothing, or shows absent data | `visibility: hidden` (pill arrows); `--ghost` on `--raised` (unbound keys) |

- Pressed never changes size: no `transform`, no scale.
- The "i" button and the insight cards have no pressed look. Their ink is
  already `--text`, and one more fill step puts it under the content floor
  (Kozo: Lc 69.7 on `--line`, 56.0 on `--line-strong`, floor 75).
- Keys, group segments and bins carry data colour in their fill, so their
  hover, focus and selection use the ring or the caption, never the fill. A
  key's hover ring is `--line-strong`.
- `--accent-soft` ink at rest marks only what is selected or now (the NOW
  line, the chosen key chip). Controls at rest use `--soft`.
- A hint is a legend: `--muted` or dimmer. Data the user asked for (a bin's
  counts) may use `--soft`. The idle bin readout is `--muted`.
- Hover should differ from rest by at least 3 OKLab points. Kozo's row hover
  (2.1) and Blueprint's `--raised` (darker than the card) still miss this.

## 6. Space

### The ladder

Six steps, as tokens (before v1: 12 gap values, 6 margins, 17 paddings).

| Token | px | Job |
|---|---|---|
| `--space-2xs` | 2 | A value under its label |
| `--space-xs` | 4 | Inline neighbours: icon and label, keycap and keycap, swatch and label; insight cards |
| `--space-sm` | 6 | Controls in a row: chips, buttons |
| `--space-md` | 8 | Inside a section: rows, blocks, columns; control padding |
| `--space-lg` | 12 | Between sections; inset padding |
| `--space-xl` | 20 | Card side padding; the window's shadow margin |

2 and 6 never stack vertically except as a pair that sums to the rhythm.
`tests/design.test.mjs` fails a raw px gap, margin, padding or radius; 13
exceptions, each with its arithmetic, are listed there (card top 14, pill
2.5, footer rule 7, the square date box, eight radii and the 8 px monogram
token).

### The 4 px rhythm

Every page height, and every section's top (from the card's content box)
and height, is a multiple of 4. Every box edge, line box and 1 px SVG line
falls on a whole device pixel at 2x. `tests/grid.test.mjs` measures this in
WebKit, the engine `hs.webview` uses. Charts draw at their viewBox size, and
1 px SVG lines are centred on device pixels, since WebKit does not snap SVG
strokes.

Page heights in WebKit, the same in all four themes:

| Page | v0 | v1 | v2 | Now |
|---|---|---|---|---|
| Overview | 627 | 634 | 632 | 660 |
| Layer | 683 | 692 | 688 | 716 |
| Activity | 774 | 718 | 720 | 720 |
| Insights | 499 | 500 | 500 | 500 |

The number row (1–0, above Q) added one 28 px key row to Overview and
Layer.

## 7. Layout

- Window 408 px; card 368 px plus 20 px shadow margin each side; content 328
  px.
- Card padding 14 top, 20 sides, 12 bottom.
- One fixed height per page. Reserve a row, never remove it: `visibility:
  hidden` on the app bar in month view, an empty legend row, two status lines
  always.
- Scroll areas have fixed heights (list 240, insights 328, panel body 132) and
  carry `data-fade`, a 26 px mask on the edge where content continues.
- Overlays (the about panel) sit over the card and never change its height.
- Stack order per page: header 28 → totals → page body → status (two lines)
  → footer.
- The footer holds at most four hints in one line, `--space-sm` (6) apart,
  the step for items in a row. A key that stands for any letter shows as
  `KEY`, never as one example letter: Overview reads `KEY OPEN`, a layer
  `KEY SELECT`, Activity `KEY MARK` (it marks that layer's dots). The widest,
  Overview, is 323.3 px of its 326 (Chrome). `KEY LAYER` (327.2) and, on
  Activity, `KEY HIGHLIGHT` (328 in month view) do not fit.

## 8. Behaviour invariants

- No `title` attributes or SVG `<title>`; native tooltips clip at the card
  edge. Use `aria-label` and visible text.
- No transitions, animations or keyframes.
- Only `open()` resets navigation; `tick`, `append` and data updates never do.
- A rebuilt control keeps keyboard focus.
- A button focused from the keyboard keeps Enter and Space; the footer names
  what Enter and the arrows do for the focused control.
- The host never calls `webview:hswindow():focus()` (a 3.2 s block).

## 9. What not to do

| Don't | Do |
|---|---|
| A new size, radius or gap "just here" | A token from the ladder, or an EXCEPTIONS line with arithmetic |
| A colour literal, or a token in one theme only | A token in all four blocks |
| A colour rule missing from `colour_pairs.mjs` | Name its surface and role there |
| Text on `--line-strong` | `--line`, or ink change only |
| Hide a row when it is empty | Keep the row, empty |
| A sentence in mono | Geist at 12 px |
| Widen tracked caps | 0.04em; narrowing is the only safe direction |
| A shadow on a control | A tone step and a 1 px line |
| A hover that fades something in or resizes it | Hover steps a tone: background or ink |

## Checks

```sh
cd ~/.config/karabiner
node --test hyperdash/tests/design.test.mjs        # scales, tokens, colour literals, motion
node --test hyperdash/tests/colour.test.mjs        # APCA floors, group distance, quantity steps
node --test hyperdash/tests/states.test.mjs        # a rule for every control state
HYPERDASH_TEST_LOG=<log copy> node --test hyperdash/tests/*.test.mjs
```

`grid.test.mjs` needs Playwright WebKit (`npx -y playwright@latest install
webkit`); `interaction.test.mjs` and `bugs.test.mjs` need Google Chrome. Each
skips when its browser is missing.
