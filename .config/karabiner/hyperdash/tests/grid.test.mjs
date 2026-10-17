// Run with: node --test karabiner/hyperdash/tests/grid.test.mjs
// Holds the panel to the 4 px rhythm and the 2x device-pixel grid in WebKit, the engine hs.webview uses.
// Drives the real page with height_probe.js, then opens every page in every theme and measures it at 2x:
//  - every page height, and every section's top (from the card's content box) and height, is a multiple of 4;
//  - every box has top and bottom edges on whole device pixels (CSS px x 2 is an integer), and every element with
//    text has a line-height that keeps its line boxes on whole device pixels: a px value whose double is whole, or
//    `normal`, which WebKit rounds to whole px (13 px Geist -> 17). WebKit also rounds each baseline to a device
//    pixel, so the glyphs need no check of their own; their content area, 1.3 em, is fractional by design.
//  - every SVG line at least 1 px wide has both edges on whole device pixels (SVG strokes are not snapped).
// Skips when Playwright WebKit is not available: run it under `npx -y -p playwright@latest node --test ...`, or set
// HYPERDASH_PLAYWRIGHT to a playwright package directory (after `npx -y playwright@latest install webkit`).
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const probe = readFileSync(new URL("./height_probe.js", import.meta.url), "utf8");
// As in height.test.mjs: freeze the page's clock at 15:00 today, so the probe's fixture has presses today.
const clock = `<script>(() => { const real = new Date(); real.setHours(15, 0, 0, 0); const fixed = real.getTime(); const Real = Date;
  globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }; })();</script>`;

// "parent > selector" -> why its box may sit off the device-pixel grid. Keep the arithmetic in the reason.
// Baseline alignment of two sizes puts the smaller box 0.355 x the size difference off the larger's grid
// (Type, DESIGN.md "Baselines"); WebKit rounds each baseline to a device pixel, so only the box is fractional.
const GRID_EXCEPTIONS = {
  "div.seq-title > span": "the 11 px count on the 13 px sequence title's baseline",
  "section#totals.total > span#total-unit.total-unit": "on the numeral's baseline, 22.23 px below the row top (26 px line, Geist ascent 1.005 em); WebKit rounds the glyphs to whole device px",
};

async function webkit() {
  const npx = join(homedir(), ".npm", "_npx");
  const candidates = [process.env.HYPERDASH_PLAYWRIGHT,
    ...(process.env.PATH || "").split(":").filter((p) => p.endsWith("node_modules/.bin")).map((p) => join(p, "..", "playwright")),
    ...(existsSync(npx) ? readdirSync(npx).map((d) => join(npx, d, "node_modules", "playwright")) : [])];
  for (const dir of candidates) {
    if (!dir || !existsSync(join(dir, "index.mjs"))) continue;
    try {
      const pw = await import(pathToFileURL(join(dir, "index.mjs")).href);
      return await pw.webkit.launch();
    } catch { /* this copy has no WebKit build installed; try the next */ }
  }
  return null;
}

// Runs inside the page: the census for the page on screen.
function measure() {
  const EPS = 1e-3;
  const whole = (v) => Math.abs(v * devicePixelRatio - Math.round(v * devicePixelRatio)) < EPS;
  const on4 = (v) => Math.abs(v / 4 - Math.round(v / 4)) < EPS;
  const sel = (el) => el.tagName.toLowerCase() + (el.id ? `#${el.id}` : "") + [...el.classList].map((c) => `.${c}`).join("");
  const card = document.getElementById("card");
  const cs = getComputedStyle(card);
  const contentTop = card.getBoundingClientRect().top + parseFloat(cs.borderTopWidth) + parseFloat(cs.paddingTop);
  const rhythm = []; const boxes = []; const texts = []; const lines = [];
  const visible = (el) => el.getClientRects().length && getComputedStyle(el).visibility !== "hidden";
  for (const parent of ["#card", "#activity", "#chart", "#panel"]) {
    for (const el of document.querySelectorAll(`${parent} > *`)) {
      if (!visible(el) || getComputedStyle(el).position === "absolute") continue;
      const r = el.getBoundingClientRect();
      if (!on4(r.top - contentTop) || !on4(r.height)) rhythm.push(`${sel(el)} top ${+(r.top - contentTop).toFixed(3)} height ${+r.height.toFixed(3)}`);
    }
  }
  for (const el of card.querySelectorAll("*")) {
    if (!visible(el) || el.closest("defs, svg")) continue;
    const r = el.getBoundingClientRect();
    if (!whole(r.top) || !whole(r.bottom)) boxes.push(`${sel(el.parentElement)} > ${sel(el)} ${+r.top.toFixed(3)}..${+r.bottom.toFixed(3)}`);
    if ([...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) {
      const lh = getComputedStyle(el).lineHeight;
      if (lh !== "normal" && !whole(parseFloat(lh))) texts.push(`${sel(el)} line-height ${lh} ("${el.textContent.trim().slice(0, 20)}")`);
    }
  }
  for (const el of card.querySelectorAll("svg line")) {
    if (el.closest("defs") || !visible(el)) continue;
    const w = parseFloat(getComputedStyle(el).strokeWidth);
    if (w < 1) continue;
    const m = el.getScreenCTM();
    const a = new DOMPoint(el.x1.baseVal.value, el.y1.baseVal.value).matrixTransform(m);
    const b = new DOMPoint(el.x2.baseVal.value, el.y2.baseVal.value).matrixTransform(m);
    const edges = a.x === b.x ? [a.x - w / 2, a.x + w / 2] : a.y === b.y ? [a.y - w / 2, a.y + w / 2] : [];
    if (!edges.every(whole)) lines.push(`${sel(el)} at ${a.x === b.x ? `x ${+a.x.toFixed(3)}` : `y ${+a.y.toFixed(3)}`} width ${w}`);
  }
  return { page: document.body.scrollHeight, rhythm, boxes, texts, lines };
}

test("rows and pages sit on the 4 px rhythm, and boxes, text and lines on the 2x pixel grid (WebKit)", { timeout: 300000 }, async (t) => {
  const browser = await webkit();
  if (!browser) { t.skip("Playwright WebKit not found (run under npx -y -p playwright@latest, or set HYPERDASH_PLAYWRIGHT)"); return; }
  try {
    const dir = mkdtempSync(join(tmpdir(), "hyperdash-grid-"));
    const file = join(dir, "page.html");
    writeFileSync(file, `${html.replace("<head>", `<head>${clock}`).replace(/<\/body>\s*<\/html>\s*$/, "")}<pre id="probe-out" hidden></pre><script>${probe}</script></body></html>\n`);
    const page = await browser.newPage({ viewport: { width: 408, height: 1000 }, deviceScaleFactor: 2 });
    await page.goto(pathToFileURL(file).href);
    await page.evaluate(() => document.fonts.ready);
    const { summary } = JSON.parse(await page.textContent("#probe-out"));

    // Every height the probe saw, on every page, through every interaction.
    const off = [];
    for (const [name, heights] of Object.entries(summary)) {
      for (const h of Object.keys(heights)) if (Number(h) % 4) off.push(`probe/${name}: page ${h} px`);
    }

    // The fixture the probe leaves loaded, opened on every page and state in every theme.
    const scenes = { overview: [], layer: ["v"], layer_selected: ["v", "j"], activity: ["a"], activity_bin: ["a", "bin"], activity_month: ["a", "Enter"], insights: ["i"] };
    for (const theme of ["manila", "kozo", "nightingale", "blueprint"]) {
      for (const [scene, steps] of Object.entries(scenes)) {
        await page.evaluate(({ theme, steps }) => {
          hyperdash.setTheme(theme); hyperdash.open({});
          for (const step of steps) {
            if (step === "bin") {
              const n = (b) => Number((b.getAttribute("aria-label") || "").split(" · ")[1]?.split(" ")[0]) || 0;
              [...document.querySelectorAll(".bin")].sort((x, y) => n(y) - n(x))[0]?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
            } else document.dispatchEvent(new KeyboardEvent("keydown", { key: step, bubbles: true }));
          }
        }, { theme, steps });
        const m = await page.evaluate(measure);
        const tag = `${scene}/${theme}`;
        if (m.page % 4) off.push(`${tag}: page ${m.page}`);
        for (const r of m.rhythm) off.push(`${tag}: rhythm ${r}`);
        for (const b of m.boxes) if (!(b.split(" ").slice(0, 3).join(" ") in GRID_EXCEPTIONS)) off.push(`${tag}: box ${b}`);
        for (const x of m.texts) if (!(x.split(" ")[0] in GRID_EXCEPTIONS)) off.push(`${tag}: text ${x}`);
        for (const l of m.lines) off.push(`${tag}: line ${l}`);
      }
    }
    // One line per kind and selector, with a count and the first example.
    const grouped = {};
    for (const o of off) {
      const [, where, kind, rest] = /^([^:]+): (\w+) ?(.*)$/.exec(o);
      const key = `${kind} ${rest.split(" ")[0]}`;
      (grouped[key] ||= { count: 0, example: `${where}: ${rest}` }).count++;
    }
    const lines = Object.entries(grouped).map(([key, g]) => `${key} x${g.count}, e.g. ${g.example}`);
    assert.ok(lines.length === 0, `${off.length} findings:\n  ${lines.join("\n  ")}`);
  } finally {
    await browser.close();
  }
});
