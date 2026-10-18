// Run with: node --test karabiner/hyperdash/tests/states.test.mjs
// Holds every control to the state set in DESIGN.md: each required state has its own rule, pressed never changes
// size, selected is not the hover rule, focus draws a ring, and a ring inside a clipping box sits inside the control.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(process.env.HYPERDASH_HTML || new URL("../index.html", import.meta.url), "utf8");
const css = html.slice(html.indexOf("<style>") + 7, html.indexOf("</style>")).replace(/\/\*[\s\S]*?\*\//g, "");

// Control selector -> required states. button: a <button>, so the shared button:focus-visible ring counts.
// clipped: it sits in a box that clips (overflow or the edge-fade mask), so its ring must be inset.
// Exempt from pressed: keys, group segments and bins carry data colour in their fill, and a click selects them.
// Also exempt: the "i" button and the insight cards. Their ink is already --text on --hover, and one more fill
// step drops it under the 75 content floor in colour.test.mjs (Kozo: Lc 69.7 on --line, 56.0 on --line-strong).
const CONTROLS = {
  ".close": { button: true, states: ["hover", "focus", "pressed"] },
  ".pill button": { button: true, states: ["hover", "focus", "pressed", "disabled"] },
  "button.header-icon": { button: true, states: ["hover", "focus", "pressed"] },
  ".info": { button: true, states: ["hover", "focus", "selected"], selected: '[aria-expanded="true"]' },
  ".themebtn": { button: true, states: ["hover", "focus", "pressed"] },
  ".seg": { button: true, states: ["hover", "focus", "pressed", "selected"], selected: '[aria-pressed="true"]' },
  ".appchip": { button: true, clipped: true, states: ["hover", "focus", "pressed", "selected"], selected: '[aria-pressed="true"]' },
  ".footer button": { button: true, states: ["hover", "focus", "pressed"] },
  ".groupclear": { button: true, clipped: true, states: ["hover", "focus", "pressed"] },
  ".time-chip": { button: true, states: ["hover", "focus", "pressed"] },
  "button.insight": { button: true, clipped: true, states: ["hover", "focus"] },
  ".evidence-back": { button: true, clipped: true, states: ["hover", "focus", "pressed"] },
  ".evidence-link": { button: true, clipped: true, states: ["hover", "focus", "pressed"] },
  ".item": { button: true, clipped: true, states: ["hover", "focus", "pressed", "selected"], selected: ".selected" },
  ".list": { clipped: true, states: ["focus"] },
  ".key": { button: true, states: ["hover", "selected", "disabled"], selected: ".selected" },
  ".bin": { states: ["hover", "focus", "selected"], selected: ".selected" },
};
const MARK = { hover: [":hover"], focus: [":focus-visible", ":focus"], pressed: [":active"], disabled: [":disabled"] };

const rules = [...css.matchAll(/([^{}@]+)\{([^{}]*)\}/g)].map((m) => ({
  selectors: m[1].split(",").map((s) => s.trim().replace(/\s+/g, " ")),
  body: m[2],
}));

// The part of a selector that follows the control in the same compound, or null when the selector is not about it.
function tail(selector, control) {
  const at = selector.indexOf(control);
  if (at < 0 || (at > 0 && selector[at - 1] !== " ")) return null;
  const rest = selector.slice(at + control.length);
  return rest === "" || /^[.:[]/.test(rest) ? (rest.includes(" ") ? null : rest) : null;
}

function rulesFor(control, marks) {
  // A mark inside :not(…) excludes the state, so it does not count.
  return rules.filter((r) => r.selectors.some((s) => { const t = tail(s, control)?.replace(/:not\([^)]*\)/g, ""); return t != null && marks.some((m) => t.includes(m)); }));
}

const rings = (body) => /outline\s*:\s*(?!none)[^;]*solid/.test(body) || /\bstroke\s*:/.test(body);

test("every control has its own rule for each required state", () => {
  const missing = [];
  for (const [control, spec] of Object.entries(CONTROLS)) {
    for (const state of spec.states) {
      if (state === "selected") { if (!rulesFor(control, [spec.selected]).length) missing.push(`${control} selected (${spec.selected})`); continue; }
      if (state === "focus") {
        const own = rulesFor(control, MARK.focus).filter((r) => rings(r.body));
        const shared = spec.button && rules.some((r) => r.selectors.includes("button:focus-visible") && rings(r.body));
        if (!own.length && !shared) missing.push(`${control} focus (no ring)`);
        continue;
      }
      if (!rulesFor(control, MARK[state]).length) missing.push(`${control} ${state}`);
    }
  }
  assert.deepEqual(missing, [], `controls without a required state rule:\n  ${missing.join("\n  ")}`);
});

test("pressed never changes size", () => {
  const off = [];
  for (const control of Object.keys(CONTROLS)) for (const r of rulesFor(control, MARK.pressed)) if (/\b(transform|scale|zoom|width|height|padding)\s*:/.test(r.body)) off.push(`${control}: ${r.body.trim()}`);
  assert.deepEqual(off, [], "pressed rules that resize");
});

test("selected is never the same rule as hover", () => {
  const shared = [];
  for (const [control, spec] of Object.entries(CONTROLS)) {
    if (!spec.selected) continue;
    for (const r of rulesFor(control, [spec.selected])) if (rulesFor(control, MARK.hover).includes(r)) shared.push(`${control}: ${r.selectors.join(", ")}`);
  }
  assert.deepEqual(shared, [], "selected looks exactly like hover");
});

test("focus is never the same rule as hover", () => {
  const shared = [];
  for (const control of Object.keys(CONTROLS)) for (const r of rulesFor(control, MARK.focus)) if (rulesFor(control, MARK.hover).includes(r) && !rules.some((x) => x !== r && rulesFor(control, MARK.focus).includes(x) && rings(x.body))) shared.push(`${control}: ${r.selectors.join(", ")}`);
  assert.deepEqual(shared, [], "focus looks exactly like hover");
});

test("a focus ring inside a clipping box is inset", () => {
  const off = [];
  for (const [control, spec] of Object.entries(CONTROLS)) {
    if (!spec.clipped) continue;
    const inset = rulesFor(control, [":focus-visible"]).some((r) => /outline-offset\s*:\s*-\d/.test(r.body));
    if (!inset) off.push(control);
  }
  assert.deepEqual(off, [], "rings that the scroll box or fade mask cuts off");
});
