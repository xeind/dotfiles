// Run with: node --test karabiner/hyperdash/tests/design.test.mjs
// Holds the page's CSS to the scales in DESIGN.md: type sizes, weights, tracking, leading, radii and spacing, colour
// only through tokens, and no motion. A value off the scale needs an EXCEPTIONS line with the arithmetic behind it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const css = html.slice(html.indexOf("<style>") + 7, html.indexOf("</style>"));

const SCALE = {
  "font-size": ["26px", "16px", "13px", "12px", "11px", "10px", "9.5px"],
  "font-weight": ["400", "500"],
  "letter-spacing": ["-0.04em", "-0.01em", "0", "0.02em", "0.04em"],
  "line-height": ["1", "1.3", "1.4"],
  "border-radius": ["5px", "7px", "8px", "10px", "30px", "50%", "999px", "inherit"],
  space: ["0", "2px", "4px", "6px", "8px", "12px", "20px", "auto"],
};
const SPACE = ["gap", "row-gap", "column-gap", "margin", "margin-top", "margin-right", "margin-bottom", "margin-left", "padding",
  "padding-top", "padding-right", "padding-bottom", "padding-left"];

// "selector | property | value": why the value is off the scale. Keep the arithmetic in the reason.
const EXCEPTIONS = {
  ".card | padding | 14px": "card top inset: the 28 px header row carries its own air; 14 + 28 + 12 puts the totals on the 8 px rhythm",
  ".pill | padding | 3px": "wraps two 18 px round buttons in a 26 px pill: (26 - 18) / 2 = 4, less the 1 px border",
  ".delta | padding | 3px": "a 21 px badge on the numeral's baseline: 3 + 15 line + 3",
  ".heat-legend i | border-radius | 3px": "swatch at 10 px: a third of the size",
  ".groupbar button | border-radius | 3px": "8 px tall bar segment: a third of the height",
  ".swatch.cov-recorded, .swatch.cov-locked, .swatch.cov-asleep, .swatch.cov-none | border-radius | 1.5px": "5 px coverage bar: a third of the height",
  ".icon img | border-radius | 4.5px": "app icon at 18 px: a quarter of the size, like the macOS icon mask",
  ".appchip .icon img | border-radius | 3.5px": "app icon at 14 px: a quarter of the size",
  ".appchip .icon.mono | border-radius | 3.5px": "letter placeholder for a 14 px app icon: a quarter of the size",
  ".appchip .icon.mono | font-size | 8px": "letter inside a 14 px icon placeholder, about 55 % of the icon",
  ".list::-webkit-scrollbar-thumb | border-radius | 4px": "4 px scrollbar: fully round",
  ".panel-body::-webkit-scrollbar-thumb | border-radius | 4px": "4 px scrollbar: fully round",
  ".bin-readout | line-height | 13.5px": "two fixed readout lines in a 27 px box",
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
        const size = value.match(/(\d+(?:\.\d+)?px)/)?.[1];
        if (weight) check(selector, "font-weight", weight, SCALE["font-weight"]);
        if (size) check(selector, "font-size", size, SCALE["font-size"]);
      }
    }
  }
  assert.deepEqual(off, [], `values off the scale (add to the scale, fix, or add an EXCEPTIONS line):\n  ${off.join("\n  ")}`);
  const stale = Object.keys(EXCEPTIONS).filter((key) => !used.has(key));
  assert.deepEqual(stale, [], "EXCEPTIONS lines that no longer match anything");
});

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
