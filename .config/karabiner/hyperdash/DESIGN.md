# hyperdash design rules

The rules for `index.html`. `tests/design.test.mjs` checks the type, shape
and space scales, colour literals and motion; the rest is held by review.

Where a table has a "Migrate" column, it records the values the page used
before these rules (2026-10-17) and where each one went.

## 0. Who owns what

| Concern | Owner |
|---|---|
| Colour values | The four `:root[data-theme=…]` blocks in `index.html` (see §3 for what is checked). |
| Theme sources | Manila and the other three come from `~/dev/xeind.net/src/styles/global.css`; hue and role follow that file, the panel's own steps (`raised`, `hover`, `q0`–`q4`, groups) live here. |
| Type, shape, space scales | This file. `tests/design.test.mjs` checks them. |
| One height per page, fades, tooltips | `tests/height.test.mjs` with `height_probe.js`. |
| Token parity across themes | `tests/model.test.mjs` ("every theme defines every colour token"). |

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

Blueprint draws in blue ink only, with cyan as its single hue.

## 3. Colour

### Never write a colour

Every colour is `var(--token)`. A token exists in all four themes or in none.
In CSS this is checked: the checker fails any `#hex`, `rgb()`, `hsl()` or
`okl*()` outside the theme blocks. In markup and JS it holds by inspection
(SVGs use `currentColor`, scripts set `var(--…)`), unchecked.

### The text ladder

From brightest to dimmest. Use the step for its job, not for its look.

| Token | Job | Used by |
|---|---|---|
| `--text` | Primary content: list labels, the numeral, titles | `body`, hover states |
| `--soft` | Values and controls at rest | counts, chips, pill, seg, close, problem text |
| `--muted` | Mono labels and second lines | legends, chart text, times, detail title, insight detail, footer keys |
| `--faint` | Captions and status | status line, footer labels, group caption, app names, zero-count cells |
| `--dim` | Data that is absent or not chosen | unused bindings, grey dots in highlight mode |
| `--ghost` | Keys with no presses | the heatmap keyboard |

`--faint` is the most used step (19 uses) because most of the panel is
apparatus around a few numbers. Running content never goes below `--muted`.

### Surfaces and edges

`--card` → `--raised` (inset surfaces, chips) → `--hover`. A surface is set
apart by one tone step plus `1px solid var(--line)`. `--line-strong` is for
tracks and scrollbars. `--edge` and `--edge-soft` are the card's own rim.

### Data colour

- Quantity: `--q0`…`--q4`, more is brighter (Kozo: darker). Text on a step uses
  `--q0t`…`--q4t`.
- Groups: six tokens, `--g-navigate`, `--g-pointer`, `--g-launch`,
  `--g-windows`, `--g-capture`, `--g-system`. Used for dots, swatches, the
  group bar and layer chips. Never for text.
- Semantic: `--up`, `--down`, `--warning`, `--info`, each with a `-bg`.
- Coverage: `--cov-recorded`, `--cov-locked`, `--cov-asleep`, `--hatch`.

### Thresholds

Distance is OKLab × 100; contrast is WCAG on `--card`. Not in the checker;
measure any token change by hand.

| Check | Rule | Manila | Kozo | Nightingale | Blueprint |
|---|---|---|---|---|---|
| Closest two group colours | ≥ 8 | 12.3 | 9.1 | 10.3 | 8.6 |
| `--down` vs `--warning` | ≥ 8 | 12.6 | 8.2 | 15.5 | 12.2 |
| Warning text (`--warning`) | ≥ 4.5:1 | 7.26 | 5.25 | 7.17 | 5.62 |
| Error text (`--down`) | ≥ 4.5:1 | 4.64 | 5.00 | 4.62 | 4.65 |
| Second lines (`--muted`) | ≥ 4.5:1 | 4.81 | 5.64 | 5.24 | 4.90 |
| Captions and healthy status (`--faint`) | ≥ 3:1 | 3.01 | 3.25 | 3.10 | 3.58 |

Before these rules, Kozo's warning sat 3.3 from its destructive red at 4.48:1,
and error text missed 4.5:1 in Manila (4.15), Nightingale (3.98) and
Blueprint (4.38). A status line that reports a broken log is the one line
that must be read, at 9.5 px.

`--faint` sits near 3:1 on purpose: a healthy status line and the captions
are apparatus, meant to recede. That is the floor for the step, and no
running content uses it.

Blueprint passes the group number but launch and capture both read as white
at 3.6 px dots (audit item 6). Treat 8 as the floor, not the goal.

## 4. Type

### Families

| Face | Job |
|---|---|
| Geist (`--sans`) | Content: names of things, titles, the numeral, sentences, footer labels |
| Geist Mono (`--mono`) | Apparatus: keycaps, counts, times, labels, legends, status, axis text |

The page loads no `@font-face`; it relies on Geist being installed and falls
back to the system face.

### Sizes

Seven sizes (before: 13, from 8 to 26 px).

| Voice | Size | Job | Before, also | Migrate |
|---|---|---|---|---|
| Geist | 26 | The numeral | | |
| Geist | 16 | Page title | | |
| Geist | 13 | Content rows: list labels, commands, sequences, insight titles, detail value, problem | 12.5 (`.cmd`, `.seq-title`), 13.5 (`.insight-title`) | → 13 |
| Geist | 12 | Second line of content: insight detail | | |
| Mono | 11 | Keycaps, pill, figures beside the numeral, list counts; footer (Geist caps) | 11.5 (`.total-unit`, `.delta`, `.item-count`, `.delta.peak`), 12 (`.detail .chip`) | → 11 |
| Mono | 10 | Labels, legends, chips, buttons, times | 10.5 (`.detail-title`, `.chip`, `.appchip`, `.cmd time`) | → 10 |
| Mono | 9.5 | Status line, axis text, captions, notes | 9 (`.heat-legend`, `.info`) | → 9.5 |

Risk: none of these changes moves a page height on its own (the
heights below come from spacing). Moving to 13 widens command and sequence
labels by about 4 %; long labels already end in an ellipsis.

The status line stays at 9.5 px: its two lines hold about 105 characters,
and `model.test.mjs` pins that number.

### Weight

400 and 500, nothing else. 500 for the title, the numeral, keycaps, pills and
mono labels; 400 for content and running text.

### Tracking

| Value | Job | Migrate |
|---|---|---|
| −0.04em | The numeral | |
| −0.01em | Geist titles and list labels | |
| 0.02em | Mono in mixed case: status, notes | |
| 0.04em | All uppercase, mono or Geist | 0.06em (8 selectors), 0.08em (`.heat-legend`) → 0.04em |

Risk: narrowing caps can never clip; widening can (the height probe tests
five-digit legend cells). Hence 0.04, not 0.06.

### Leading

1 for the numeral, 1.3 for two-line content (titles, insight lines), 1.4 for
prose (status, problem, about). Before: also 1.25 (`.insight-title`) and 1.5
(`.about`). Fixed readout lines may set a px line box (`.bin-readout`, 13.5
px, two lines in 27).

### Case

- Uppercase: mono labels, legends, captions, status, pill text, footer labels.
- Sentence or title case: names of things (bindings, apps, sequences), insight
  text, problem text.
- Mono carries labels and figures, not sentences. Two notes break this today:
  `Pick a day (Enter) for its commands and sequences` and `App = last app
  before that second (the usage log has 1 s resolution)`, which also ends in
  an ellipsis. Open: set them in Geist at 12 px `--muted`, and shorten the
  second to fit one line.

### Numbers

Counts use `compactCount` in legends and `toLocaleString("en-US")` elsewhere.
Mono figures align by themselves. The Geist numeral carries
`font-variant-numeric: tabular-nums` so it does not shift as it counts; the
mono list counts carry it too, which costs nothing.

## 5. Shape

### Radius follows height

Radius follows height (before: 16 values).

| Thing | Height | Radius | Migrate |
|---|---|---|---|
| Card | | 30 | |
| Inset surface (detail, insight, problem, about) | | 10 = 30 − 20 card padding | 12, 14 → 10 |
| Row (list item, sequence) and large keycap | 27–30 | 8 | |
| Control | 21–26 (seg, appchip, delta, key, header icon, marker, command row) | 7 | 6, 8 → 7 |
| Small control (chip, keycap, time chip, theme button, footer key) | ≤ 20 | 5 | 6 → 5 |
| Pill, bar | any | 999 | |
| Round button, dot | any | 50 % | |
| App icon | 14, 18 | a quarter of the size: 3.5, 4.5 | 4 → 3.5 |
| Swatch, segment | ≤ 10 | a third of the size: 1.5, 3 | |

### Control heights

Icons 14 / 16 / 18. Controls 18 / 22 / 26 / 28. Rows 24 (commands) / 30
(list). Migrate: `.time-chip` 17 → 18, `.chip` and `.themebtn` 20 → 18.

### Hit areas

Keys 25, close 28, rows 24–30, controls 18–22. Two are small on purpose and
stay, because each has a key: `.info` (14 px, `?`) and the pill arrows (18
px, ← →). No new control below 18.

### Depth

Two shadows: the card, and the about overlay that floats over it. Everything
else is flat: a tone step plus a 1 px `--line` border. Focus is
`2px solid var(--accent-soft)` with a 1 px offset.

## 6. Space

### The ladder

Before: 12 gap values, 6 margins, 17 paddings. Now: 2 / 4 / 6 / 8 / 12 /
20.

| Step | Job | Migrate |
|---|---|---|
| 2 | A value under its label | |
| 4 | Inline neighbours: icon and label, keycap and keycap, swatch and label | 3 → 4; 5 → 4 inside a chip or footer item |
| 6 | Controls in a row: chips, buttons; items in a list | 5 → 6 between controls |
| 8 | Inside a section: rows, blocks, columns; control padding | 7 → 8; 10 → 8 inside rows (header, detail) |
| 12 | Between sections; inset padding | 10 → 12 between sections; 10, 11 → 12 inset padding |
| 20 | Card side padding; the window's shadow margin | |

Exceptions, each with its arithmetic, are listed in the checker: card top
14, pill 3, delta 3.

Page heights, the same in all four themes:

| Page | Before the rules | Now |
|---|---|---|
| Overview | 627 | 634 |
| Layer | 683 | 692 |
| Activity | 774 | 718 |
| Insights | 499 | 500 |

The section margins (10 → 12) added 1–9 px. Activity also lost 63 px: the
dot scale moved into the idle readout line, the coverage key took the
legend's caption row, and the sequence panel shows three sequences, with the
fourth under the fade.

## 7. Layout

- Window 408 px; card 368 px plus 20 px shadow margin each side; content 328
  px.
- Card padding 14 top, 20 sides, 12 bottom.
- One fixed height per page. Reserve a row, never remove it: `visibility:
  hidden` on the app bar in month view, an empty legend row, two status lines
  always.
- Scroll areas have fixed heights (list 240, insights 330, panel body 138) and
  carry `data-fade`, a 26 px mask on the edge where content continues.
- Overlays (the about panel) sit over the card and never change its height.
- Stack order per page: header 28 → totals → page body → status (two lines)
  → footer.

## 8. Behaviour invariants

- No `title` attributes or SVG `<title>`; native tooltips clip at the card
  edge. Use `aria-label` and visible text.
- No transitions, animations or keyframes.
- Only `open()` resets navigation; `tick`, `append` and data updates never do.
- The host never calls `webview:hswindow():focus()` (a 3.2 s block).

## 9. What not to do

| Don't | Do |
|---|---|
| A new size, radius or gap "just here" | A step from the ladder, or an EXCEPTIONS line with arithmetic |
| A colour literal, or a token in one theme only | A token in all four blocks |
| Hide a row when it is empty | Keep the row, empty |
| A sentence in mono | Geist at 12 px |
| Widen tracked caps | 0.04em; narrowing is the only safe direction |
| A shadow on a control | A tone step and a 1 px line |
| A hover that fades something in or resizes it | Hover steps a tone: background or ink |

## Checks

```sh
cd ~/.config/karabiner
node --test hyperdash/tests/design.test.mjs        # scales, colour literals, motion
HYPERDASH_TEST_LOG=<log copy> node --test hyperdash/tests/*.test.mjs
```

The scale test passes with 13 exceptions, each with its arithmetic. Before
these rules it would have reported 63 values off the scale.
