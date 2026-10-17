// Run with: node --test karabiner/hyperdash/tests/design.test.mjs
// Holds the page's CSS to the scales in DESIGN.md: type sizes, weights, tracking, leading, radii and spacing, colour
// only through tokens, and no motion. A value off the scale needs an EXCEPTIONS line with the arithmetic behind it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const css = html.slice(html.indexOf("<style>") + 7, html.indexOf("</style>"));

// Font sizes are tokens, defined once in :root. --text-* tokens hold Geist steps, --mono-* tokens Geist Mono steps.
const TYPE_SCALE = {
  "--text-": ["26px", "16px", "13px", "12px", "11px"],
  "--mono-": ["11px", "10px"],
};
const SCALE = {
  "font-weight": ["400", "500"],
  "letter-spacing": ["-0.04em", "-0.01em", "0", "0.02em", "0.04em"],
  // Radius and space go through the tokens in the shared :root block (checked below); raw px needs an EXCEPTIONS line.
  "border-radius": ["50%", "999px", "inherit"],
  space: ["0", "auto"],
};
const SPACE = ["gap", "row-gap", "column-gap", "margin", "margin-top", "margin-right", "margin-bottom", "margin-left", "padding",
  "padding-top", "padding-right", "padding-bottom", "padding-left"];

// "selector | property | value": why the value is off the scale. Keep the arithmetic in the reason.
const EXCEPTIONS = {
  ".footer | padding-top | 7px": "1 px rule + 7 = 8 above the 20 px keys; 8 + 20 = 28, on the 4 px rhythm",
  ".card | padding | 14px": "card top inset: the 28 px header row carries its own air; 14 + 28 + 12 puts the totals on the 8 px rhythm",
  ".pill | padding | 2.5px": "wraps two 20 px round buttons in a 28 px pill: (28 - 20) / 2 = 4 = 1.5 px border + 2.5, the same on every side",
  ".heat-legend i | border-radius | 3px": "swatch at 10 px: a third of the size",
  ".groupbar button | border-radius | 3px": "8 px tall bar segment: a third of the height",
  ".swatch.cov-recorded, .swatch.cov-locked, .swatch.cov-asleep, .swatch.cov-none | border-radius | 1.5px": "5 px coverage bar: a third of the height",
  ".icon img | border-radius | 4.5px": "app icon at 18 px: a quarter of the size, like the macOS icon mask",
  ".appchip .icon img | border-radius | 3.5px": "app icon at 14 px: a quarter of the size",
  ".appchip .icon.mono | border-radius | 3.5px": "letter placeholder for a 14 px app icon: a quarter of the size",
  ":root | --mono-monogram | 8px": "letter inside a 14 px icon placeholder: the 18 px slot's 10 px letter scaled by 14 / 18 = 7.8",
  ".list::-webkit-scrollbar-thumb | border-radius | 4px": "4 px scrollbar: fully round",
  ".panel-body::-webkit-scrollbar-thumb | border-radius | 4px": "4 px scrollbar: fully round",
};

// Splits the style block into [selector, declarations] pairs, ignoring @-rule wrappers.
function rules(text) {
  const out = [];
  const clean = text.replace(/\/\*[\s\S]*?\*\//g, "");
  for (const m of clean.matchAll(/([^{}]+)\{([^{}]*)\}/g)) out.push([m[1].trim().replace(/\s+/g, " "), m[2]]);
  return out;
}

function declarations(body) {
  return body.split(";").map((d) => d.trim()).filter(Boolean).map((d) => {
    const cut = d.indexOf(":");
    return [d.slice(0, cut).trim(), d.slice(cut + 1).trim()];
  });
}

test("every type, shape and spacing value is on the DESIGN.md scale or carries a reason", () => {
  const off = [];
  const used = new Set();
  const check = (selector, prop, value, legal) => {
    if (value.startsWith("var(") || value.startsWith("calc(") || legal.includes(value)) return;
    const key = `${selector} | ${prop} | ${value}`;
    if (key in EXCEPTIONS) { used.add(key); return; }
    off.push(key);
  };
  for (const [selector, body] of rules(css)) {
    if (selector.startsWith(":root")) continue;
    for (const [prop, value] of declarations(body)) {
      if (prop in SCALE) check(selector, prop, value, SCALE[prop]);
      if (SPACE.includes(prop) && !value.includes("calc(")) for (const part of value.split(/\s+/)) check(selector, prop, part, SCALE.space);
      if (prop === "font") {
        const weight = value.match(/^(\d{3})\s/)?.[1];
        if (weight) check(selector, "font-weight", weight, SCALE["font-weight"]);
      }
    }
  }
  assert.deepEqual(off, [], `values off the scale (add to the scale, fix, or add an EXCEPTIONS line):\n  ${off.join("\n  ")}`);
  const stale = Object.keys(EXCEPTIONS).filter((key) => !key.startsWith(":root") && !used.has(key));
  assert.deepEqual(stale, [], "EXCEPTIONS lines that no longer match anything");
});

// Sizes that live as tokens in the shared :root: which declarations must name one, the token names, and the values
// a token may hold. Themes change colour only, so no theme block defines one.
const KINDS = {
  "font size": {
    props: ["font-size", "font"], token: /var\((--(?:text|mono)-[a-z-]+)\)/, name: /^--(?:text|mono)-/,
    legal: (name, value) => TYPE_SCALE[name.slice(0, 7)].includes(value),
  },
  "line height": {
    props: ["line-height"], token: /var\((--leading-[a-z-]+)\)/, name: /^--leading-/,
    legal: (name, value) => /^\d+px$/.test(value), // whole pixels, so a block of lines is a whole-pixel sum
  },
};

function checkTokens(kind) {
  const { props, token: TOKEN, name: NAME, legal } = KINDS[kind];
  const off = [];
  const used = new Set();
  for (const [selector, body] of rules(css)) {
    if (selector.startsWith(":root")) continue;
    for (const [prop, value] of declarations(body)) {
      if (!props.includes(prop) || value === "inherit") continue;
      const token = TOKEN.exec(value)?.[1];
      // A shorthand may carry a weight and a family; any length or /line-height left besides the token is by hand.
      const rest = value.replace(TOKEN, "").replace(/^\d{3}\s/, "");
      if (!token || /\d(?:px|em|rem|%)|\/|\b(?:small|medium|large|smaller|larger)\b/.test(rest)) off.push(`${selector} | ${prop} | ${value}`);
      else used.add(token);
    }
  }
  assert.deepEqual(off, [], `${kind}s not written as a token:\n  ${off.join("\n  ")}`);

  const defined = new Map();
  for (const [selector, body] of rules(css)) {
    for (const [prop, value] of declarations(body)) {
      if (!NAME.test(prop)) continue;
      assert.equal(selector, ":root", `${prop} is defined in "${selector}"; size tokens belong in the shared :root block`);
      assert.ok(!defined.has(prop), `${prop} is defined twice`);
      defined.set(prop, value);
    }
  }
  const offScale = [...defined].filter(([name, value]) => !legal(name, value) && !(`:root | ${name} | ${value}` in EXCEPTIONS));
  assert.deepEqual(offScale.map(([name, value]) => `${name}: ${value}`), [], `${kind} tokens off the scale`);
  const stale = Object.keys(EXCEPTIONS).filter((key) => key.startsWith(":root") && NAME.test(key.split(" | ")[1])
    && defined.get(key.split(" | ")[1]) !== key.split(" | ")[2]);
  assert.deepEqual(stale, [], `${kind} token EXCEPTIONS lines that no longer match anything`);
  assert.deepEqual([...used].filter((name) => !defined.has(name)), [], `${kind} tokens used but never defined`);
  assert.deepEqual([...defined.keys()].filter((name) => !used.has(name)), [], `${kind} tokens defined but never used`);
}

test("every font size is a type token, and every type token is on the scale", () => checkTokens("font size"));

test("every line height is a leading token in whole pixels", () => checkTokens("line height"));

test("colours come only from theme tokens", () => {
  const literal = /#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|oklch|oklab)\(/;
  const off = [];
  for (const [selector, body] of rules(css)) {
    if (selector.startsWith(":root")) continue;
    for (const [prop, value] of declarations(body)) if (literal.test(value)) off.push(`${selector} | ${prop} | ${value}`);
  }
  assert.deepEqual(off, [], "literal colours outside the theme blocks");
});

test("nothing moves: no transitions or animations", () => {
  assert.doesNotMatch(css, /\b(transition|animation)\s*:/);
  assert.doesNotMatch(css, /@keyframes/);
});

// The ladders in DESIGN.md, held where they are defined: the shared :root block.
test("size, radius and space tokens hold the native ladder and the 4 px rhythm", () => {
  const shared = /\/\* Type and layout, shared by every theme \*\/\s*:root \{([\s\S]*?)\n  \}/.exec(css)[1];
  const token = (name) => shared.match(new RegExp(`--${name}:\\s*([^;]+);`))?.[1].trim();
  // macOS 27.0.1 NSControl.ControlSize: mini 16, small 20, regular 24, large 28 (native/native_controls.json).
  assert.deepEqual(["xs", "sm", "md", "lg"].map((s) => token(`control-${s}`)), ["16px", "20px", "24px", "28px"]);
  assert.deepEqual([token("row-compact"), token("row")], ["24px", "32px"]);
  // A quarter of the height, as AppKit draws its push buttons, segmented controls and pop-ups (4.2, 5.2, 6.1 measured
  // at 16, 20, 24); 10 for a 32 px row, as it draws a source-list selection (10.2 measured).
  for (const s of ["sm", "md", "lg"]) assert.equal(token(`radius-${s}`), `calc(var(--control-${s}) / 4)`);
  assert.equal(token("radius-row"), "10px");
  assert.equal(token("radius-inset"), "calc(var(--radius-card) - var(--space-xl))");
  assert.deepEqual(["2xs", "xs", "sm", "md", "lg", "xl"].map((s) => token(`space-${s}`)), ["2px", "4px", "6px", "8px", "12px", "20px"]);
});
