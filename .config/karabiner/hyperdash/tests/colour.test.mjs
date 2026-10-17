// Run with: node --test karabiner/hyperdash/tests/colour.test.mjs
// Holds the theme tokens to the colour floors in DESIGN.md §3: APCA Lc per role on every surface and state, group
// colours apart under colour-vision-deficiency simulation, an even quantity scale, and a pair list that covers every
// colour rule in the page. The pairs live in colour_pairs.mjs; the maths in colour_model.mjs.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { THEMES, themeTokens, flatten, apca, distance, simulate, oklch } from "./colour_model.mjs";
import { PAIRS, NOT_TEXT, JS_SETTERS, FLOORS, EXEMPT, GROUPS, GROUP_DISTANCE, STEP_TOLERANCE, Q0_FROM_RAISED } from "./colour_pairs.mjs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const css = html.slice(html.indexOf("<style>") + 7, html.indexOf("</style>"));
const script = html.slice(html.indexOf("</style>"));
const themes = themeTokens(html);
const stack = (bg) => (Array.isArray(bg) ? bg : [bg]);

test("every rule that sets a text, fill, stroke or outline colour is in the pair list", () => {
  const known = new Set([...PAIRS.map((p) => p.sel), ...Object.keys(NOT_TEXT)]);
  const missing = [];
  for (const m of css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = m[1].trim().replace(/\s+/g, " ");
    if (selector.startsWith(":root")) continue;
    if (/(?:^|;)\s*(?:color|fill|stroke|outline|outline-color)\s*:[^;]*var\(--/.test(m[2]) && !known.has(selector)) missing.push(selector);
  }
  assert.deepEqual(missing, [], "add each rule to colour_pairs.mjs with its surface and role, or to NOT_TEXT with a reason");
  // The pair list must name the token the rule really sets (--grp stands for each --g-*; --tone is set by script).
  const wrong = [];
  for (const m of css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = m[1].trim().replace(/\s+/g, " ");
    const tokens = [...m[2].matchAll(/(?:^|;)\s*(?:color|fill|stroke|outline|outline-color)\s*:[^;]*?var\((--[\w-]+)/g)].map((x) => x[1]);
    if (!tokens.length || tokens.includes("--tone")) continue;
    for (const p of PAIRS.filter((x) => x.sel === selector)) {
      const expected = tokens.map((token) => (token === "--grp" ? `--g-${p.group}` : token));
      if (!expected.includes(p.fg)) wrong.push(`${selector}: CSS sets ${expected.join(", ")}, pair list says ${p.fg}`);
    }
  }
  assert.deepEqual([...new Set(wrong)], [], "colour_pairs.mjs disagrees with the CSS");
  const writes = [...script.matchAll(/^\s*(.*?(?:\.style\.(?:color|background)\s*=|\.style\.setProperty\("--)[^;]*);/gm)].map((x) => x[1].trim());
  assert.deepEqual(writes.filter((w) => !(w in JS_SETTERS)), [], "a script writes a colour that colour_pairs.mjs does not know");
  assert.deepEqual(Object.keys(JS_SETTERS).filter((w) => !writes.includes(w)), [], "stale JS_SETTERS entries");
});

test("every text and mark meets its APCA floor on every surface, state and theme", () => {
  const misses = [];
  for (const theme of THEMES) for (const p of PAIRS) {
    if (EXEMPT[p.sel]) continue;
    const t = themes[theme];
    const lc = Math.abs(apca(flatten(t, [...stack(p.bg), p.fg]), flatten(t, p.bg)));
    if (lc < FLOORS[p.role]) misses.push([lc - FLOORS[p.role], `${theme} ${p.name} [${p.state}] ${p.fg}: Lc ${lc.toFixed(1)} < ${FLOORS[p.role]} (${p.role})`]);
  }
  misses.sort((a, b) => a[0] - b[0]);
  assert.deepEqual(misses.map((m) => m[1]), []);
});

test("the text ladder stays in order on the card: faint < muted < soft < text", () => {
  for (const theme of THEMES) {
    const t = themes[theme];
    const lc = ["--faint", "--muted", "--soft", "--text"].map((k) => Math.abs(apca(flatten(t, k), flatten(t, "--card"))));
    assert.ok(lc.every((v, i) => i === 0 || v > lc[i - 1]), `${theme}: ${lc.map((v) => v.toFixed(1)).join(" < ")}`);
  }
});

test(`group colours stay ${GROUP_DISTANCE} apart in normal vision and under protan, deutan and tritan simulation`, () => {
  const close = [];
  for (const theme of THEMES) {
    const t = themes[theme];
    for (const kind of ["normal", "protan", "deutan", "tritan"]) for (let i = 0; i < GROUPS.length; i++) for (let j = i + 1; j < GROUPS.length; j++) {
      const d = distance(simulate(flatten(t, `--g-${GROUPS[i]}`), kind), simulate(flatten(t, `--g-${GROUPS[j]}`), kind));
      if (d < GROUP_DISTANCE) close.push(`${theme} ${kind} ${GROUPS[i]}/${GROUPS[j]}: ${d.toFixed(1)}`);
    }
  }
  assert.deepEqual(close, []);
});

test("the quantity scale steps evenly in OKLCH lightness, and a zero-press key differs from an unbound one", () => {
  for (const theme of THEMES) {
    const t = themes[theme];
    const L = [0, 1, 2, 3, 4].map((i) => oklch(flatten(t, `--q${i}`))[0] * 100);
    const steps = L.slice(1).map((v, i) => v - L[i]);
    const mean = (L[4] - L[0]) / 4;
    const uneven = steps.filter((s) => Math.abs(s - mean) > Math.abs(mean) * STEP_TOLERANCE);
    assert.deepEqual(uneven, [], `${theme}: steps ${steps.map((s) => s.toFixed(1)).join(" ")}, mean ${mean.toFixed(1)}`);
    const gap = distance(flatten(t, "--q0"), flatten(t, "--raised"));
    assert.ok(gap >= Q0_FROM_RAISED, `${theme}: --q0 is ${gap.toFixed(1)} from --raised`);
  }
});
