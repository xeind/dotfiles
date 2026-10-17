// Every text and mark colour in index.html, with the surface it sits on in each state, its size and weight.
// `sel` is the CSS rule that sets the colour (or "js: ..." where a script sets it). colour.test.mjs fails if a
// rule that sets color, fill or stroke is missing here, so a new colour rule has to name its surface and role.
// `{g}` expands to the six groups. Surfaces are stacks, bottom first; an alpha layer is composited over the one below.

export const GROUPS = ["navigate", "pointer", "launch", "windows", "capture", "system"];

const ROW = [["rest", "--card"], ["hover", "--raised"], ["selected", "--hover"]];
const GRP_BG = "color-mix(in oklab, var(--g-{g}) 16%, var(--raised))";

// [name, role, fg, [[state, surface], ...], family, px, weight, setter]. `setter` is the rule the colour comes
// from when the element inherits it; it defaults to `name`.
const RAW = [
  // Header
  [".title", "content", "--text", [["rest", "--card"]], "sans", 16, 500, "html, body"],
  [".pill", "value", "--soft", [["rest", "--card"]], "sans", 11, 500],
  [".updated", "caption", "--faint", [["rest", "--card"]], "mono", 10, 500],
  [".pill button", "icon", "--muted", [["rest", "--card"]], "svg", 8, 500],
  [".pill button:hover:not(:disabled)", "icon", "--text", [["hover", "--hover"]], "svg", 8, 500],
  [".header-icon", "icon", "--soft", [["rest", "--card"], ["hover", "--hover"]], "svg", 16, 500],
  ["button.header-icon:active", "icon", "--text", [["active", "--line-strong"]], "svg", 16, 500],
  [".close", "icon", "--soft", [["rest", "--hover"], ["hover", "--line-strong"]], "svg", 11, 500],
  [".close:active", "icon", "--text", [["active", "--line-strong"]], "svg", 11, 500],

  // Total
  [".total-number", "content", "--text", [["rest", "--card"]], "sans", 26, 500, "html, body"],
  [".total-unit", "label", "--muted", [["rest", "--card"]], "sans", 11, 500],
  [".delta.up", "status", "--up", [["rest", "--up-bg"]], "mono", 11, 500],
  [".delta.down", "status", "--down", [["rest", "--down-bg"]], "mono", 11, 500],
  [".delta.peak", "status", "--info", [["rest", "--info-bg"]], "mono", 11, 500],

  // Keyboard
  [".key", "absent", "--ghost", [["unbound", "--raised"]], "mono", 11, 500],
  [".h0", "heat", "--q0t", [["0 presses", "--q0"]], "mono", 11, 500],
  [".h1", "heat", "--q1t", [["step 1", "--q1"]], "mono", 11, 500],
  [".h2", "heat", "--q2t", [["step 2", "--q2"]], "mono", 11, 500],
  [".h3", "heat", "--q3t", [["step 3", "--q3"]], "mono", 11, 500],
  [".h4", "heat", "--q4t", [["step 4", "--q4"]], "mono", 11, 500],
  [".key.selected", "focus", "--accent-soft", [["selected", "--card"]], "ring", 2, 500],
  [".heat-legend", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],

  // Detail strip
  [".detail .chip", "value", "--accent-soft", [["rest", ["--raised", "--accent-bg"]]], "mono", 11, 400],
  [".detail-title", "label", "--muted", [["rest", "--raised"]], "mono", 10, 400],
  [".detail-value", "content", "--text", [["rest", "--raised"]], "sans", 13, 400, "html, body"],
  [".detail.empty .detail-value", "caption", "--faint", [["empty", "--raised"]], "sans", 13, 400],
  [".chip", "value", "--soft", [["rest", "--hover"]], "mono", 10, 400],
  [".empty-list", "label", "--muted", [["rest", "--card"]], "sans", 13, 400],

  // Binding list
  [".item-label", "content", "--text", ROW, "sans", 13, 400, "html, body"],
  [".item .chip.layer", "value", "--soft", [["rest", GRP_BG]], "mono", 10, 400],
  [".item.unused .item-label, .item.unused .item-count", "absent", "--dim", ROW.slice(0, 2), "sans", 13, 400],
  [".item-count", "value", "--soft", ROW, "mono", 11, 400],
  [".icon", "mark", "--g-{g}", ROW, "svg", 16, 500],
  [".icon.mono", "value", "--soft", [["rest", GRP_BG]], "mono", 10, 500],
  [".item-label .note", "caption", "--faint", ROW, "sans", 13, 400],

  // Insights
  [".insight-title", "content", "--text", [["rest", "--raised"], ["hover", "--hover"]], "sans", 13, 400, "html, body"],
  [".insight-detail", "label", "--muted", [["rest", "--raised"], ["hover", "--hover"]], "sans", 12, 400],
  [".insight-heading", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".insight-note", "label", "--muted", [["rest", "--card"]], "sans", 12, 400],
  [".insight-meta", "caption", "--faint", [["rest", "--raised"], ["hover", "--hover"]], "mono", 10, 400],
  [".chip.combo i", "caption", "--faint", [["rest", "--hover"]], "mono", 10, 400],
  [".chip.combo b", "value", "--soft", [["rest", "--hover"]], "mono", 10, 400],
  // Icons are neutral: a rise is not good news and an unused binding is not a warning. Shape carries the kind.
  [".insight-icon, .insight-open", "icon", "--muted", [["rest", "--raised"], ["hover", "--hover"]], "svg", 16, 400],
  [".insight-more", "label", "--muted", [["rest", "--raised"], ["hover", "--hover"]], "sans", 12, 400],

  // Activity
  [".chart text", "label", "--muted", [["rest", "--card"]], "mono", 10, 500],
  [".chart .peak-label", "value", "--soft", [["rest", "--card"]], "mono", 10, 500],
  [".chart .now-label", "value", "--accent-soft", [["rest", "--card"]], "mono", 10, 500],
  [".dots.g-{g}", "dot", "--g-{g}", [["rest", "--card"]], "dot", 3.6, 500],
  [".dots.blue", "dot", "--accent", [["rest", "--card"]], "dot", 3.6, 500],
  [".dots.lit", "dot", "--accent-soft", [["rest", "--card"]], "dot", 3.6, 500],
  [".dots.grey", "absent", "--dim", [["rest", "--card"]], "dot", 3.6, 500],
  ["js: legend swatch {g}", "mark", "--g-{g}", [["rest", "--card"]], "dot", 7, 500],
  ["js: legend swatch highlight", "mark", "--accent-soft", [["rest", "--card"]], "dot", 7, 500],
  ["js: legend swatch other", "absent", "--dim", [["rest", "--card"]], "dot", 7, 500],
  ["js: readout dot {g}", "mark", "--g-{g}", [["rest", "--card"]], "dot", 7, 500],
  [".chart-legend", "label", "--muted", [["rest", "--card"]], "mono", 10, 400],
  [".chart-legend .zero", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".bin-readout", "value", "--soft", [["rest", "--card"]], "mono", 10, 400],
  [".bin-readout .r2", "label", "--muted", [["rest", "--card"]], "mono", 10, 400],
  [".bin-readout.idle", "label", "--muted", [["rest", "--card"]], "mono", 10, 400],
  [".seg", "value", "--soft", [["rest", "--raised"], ["hover", "--hover"]], "mono", 10, 500],
  [".seg:active", "value", "--text", [["active", "--line"]], "mono", 10, 500],
  ['.seg[aria-pressed="true"]', "value", "--accent-soft", [["pressed", "--accent-bg"]], "mono", 10, 500],
  [".controls .note", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".appbar", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".appchip", "value", "--soft", [["rest", "--raised"], ["hover", "--hover"]], "mono", 10, 400],
  [".appchip:active", "value", "--text", [["active", "--line"]], "mono", 10, 400],
  ['.appchip[aria-pressed="true"]', "value", "--accent-soft", [["pressed", "--accent-bg"]], "mono", 10, 400],
  [".appchip b", "caption", "--faint", [["rest", "--raised"], ["hover", "--hover"], ["pressed", "--accent-bg"]], "mono", 10, 400],
  ["js: app monogram", "value", "--soft", [["rest", "--hover"]], "mono", 10, 500],
  [".panel-head", "label", "--muted", [["rest", "--card"]], "mono", 10, 400],
  [".panel-head span:last-child", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".panel-note", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".cmd-label", "content", "--text", [["rest", "--card"], ["focus", "--hover"]], "sans", 13, 400, "html, body"],
  [".seq-title", "content", "--text", [["rest", "--card"]], "sans", 13, 400, "html, body"],
  [".cmd time", "label", "--muted", [["rest", "--card"], ["focus", "--hover"]], "mono", 10, 400],
  [".cmd-app", "caption", "--faint", [["rest", "--card"], ["focus", "--hover"]], "mono", 10, 400],
  [".seq-title span:last-child", "label", "--muted", [["rest", "--card"]], "mono", 11, 400],
  [".time-chip", "value", "--soft", [["rest", "--hover"], ["hover", "--line"]], "mono", 10, 400],
  [".time-chip:active", "value", "--text", [["active", "--line"]], "mono", 10, 400],
  [".seq-more", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],
  [".bin.selected", "focus", "--accent-soft", [["selected", "--card"]], "ring", 1, 500],
  [".bin:focus-visible", "focus", "--accent-soft", [["focus", "--card"]], "ring", 2, 500],

  // Groups
  [".groupbar button", "mark", "--g-{g}", [["rest", "--card"]], "bar", 8, 500],
  [".groupcap", "caption", "--faint", [["rest", "--card"]], "mono", 10, 400],

  // Footer, info, about, status
  [".footer", "caption", "--faint", [["rest", "--card"]], "sans", 11, 500],
  [".footer kbd", "label", "--muted", [["rest", "--hover"]], "mono", 10, 400],
  [".info", "label", "--muted", [["rest", "--card"]], "mono", 10, 500],
  [".info:hover", "content", "--text", [["hover", "--hover"]], "mono", 10, 500],
  ['.info[aria-expanded="true"]', "value", "--accent-soft", [["selected", "--accent-bg"]], "mono", 10, 500],
  [".about", "label", "--muted", [["rest", "--raised"]], "mono", 10, 400],
  [".about p:first-child", "value", "--soft", [["rest", "--raised"]], "mono", 10, 400],
  [".themebtn", "value", "--soft", [["rest", "--hover"], ["hover", "--line"]], "mono", 10, 500],
  [".themebtn:active", "value", "--text", [["active", "--line"]], "mono", 10, 500],
  [".status", "caption", "--faint", [["ok", "--card"]], "mono", 10, 400],
  ['.status[data-level="warn"]', "status", "--warning", [["warn", "--card"]], "mono", 10, 400],
  ['.status[data-level="error"]', "status", "--down", [["error", "--card"]], "mono", 10, 400],
  [".problem", "value", "--soft", [["rest", "--raised"]], "sans", 13, 400],
  ["button:focus-visible, .list:focus-visible", "focus", "--accent-soft", [["focus", "--card"]], "ring", 2, 500],
];

// Rules that set a colour but draw nothing that needs a contrast floor: lines, fills under data, hidden hit areas,
// and selectors whose text inherits a colour already listed above.
export const NOT_TEXT = {
  ".chart .baseline": "axis line", ".chart .peak-line": "dashed guide", ".chart .grid-line": "grid", ".chart .now-line": "guide",
  ".chart .hatch-line": "hatch", ".chart .cov-recorded": "coverage strip", ".chart .cov-locked": "coverage strip",
  ".chart .cov-asleep": "coverage strip", ".chart .cov-off": "coverage strip", ".chart .cov-none": "coverage strip",
  ".dots": "sets no colour", ".swatch.cov-locked": "coverage key outline", ".swatch.cov-asleep": "coverage key outline",
  ".swatch.cov-none": "coverage key outline", ".bin": "transparent hit area", ".bin:hover, .bin:focus": "hover wash",
  ".icon.site svg": "fill: currentColor; the host supplies brand colours", ".cmd": "sets no colour",
  ".appchip .icon.mono": "size only; js: app monogram sets the colour", "button": "inherits",
  ".key:not(:disabled):not(.selected):hover": "hover outline: one line step, like a border; the key fill carries the data",
};

// Every place a script writes a colour: the assigned expression, and the pair (or reason) that covers it.
export const JS_SETTERS = {
  'template.style.color = site.color || "var(--soft)"': "site marks: the host supplies brand colours; the fallback is .icon --soft",
  "if (color) dot.style.background = color": "js: legend swatch *",
  "dot.style.background = `var(--g-${group})`": "js: readout dot *",
  'node.style.background = "var(--hover)"': "js: app monogram",
  'node.style.color = "var(--soft)"': "js: app monogram",
};

// APCA Lc floor per role, as a magnitude, on the worst surface the colour sits on. Levels are APCA's use-case levels
// (apca-w3 0.1.9, docs/APCA_in_a_Nutshell.md): 75 readable text, 60 content text, 45 fine icons and sub-fluent
// labels, 30 spot text and solid marks, 15 the point of invisibility. See REPORT.md for the mapping.
export const FLOORS = { content: 75, value: 60, label: 45, status: 45, heat: 45, icon: 45, focus: 45,
  caption: 30, dot: 30, mark: 30, absent: 15 };

// Colours that may sit below every floor, by design.
export const EXEMPT = {
  ".key": "--ghost: the letter on a key with no binding is decoration; the key face carries the state",
};

// OKLab x100 between any two group colours, in normal vision and in each Machado 2009 simulation (severity 1).
export const GROUP_DISTANCE = 8;
// Equal lightness steps: each q-step's OKLCH L change within this fraction of the mean step.
export const STEP_TOLERANCE = 0.15;
// A zero-press key (--q0) sits at least one surface tone step (OKLab x100) from an unbound key (--raised).
export const Q0_FROM_RAISED = 3;

export const PAIRS = RAW.flatMap(([name, role, fg, surfaces, family, px, weight, setter]) => {
  const groups = fg.includes("{g}") || JSON.stringify(surfaces).includes("{g}") ? GROUPS : [null];
  return groups.flatMap((g) => surfaces.map(([state, bg]) => {
    const sub = (x) => (g ? (Array.isArray(x) ? x.map(sub) : x.replaceAll("{g}", g)) : x);
    return { sel: setter || sub(name), name: sub(name), role, fg: sub(fg), bg: sub(bg), state, family, px, weight, group: g };
  }));
});
