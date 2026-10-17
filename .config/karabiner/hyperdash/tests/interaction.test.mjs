// Run with: node --test karabiner/hyperdash/tests/interaction.test.mjs
// Drives the real page in headless Chrome with interaction_probe.js: a focused control does what a click on
// it does, focus survives an Activity rebuild, and the Activity footer names what each key really does.
// Skips when Chrome is not installed; set HYPERDASH_TEST_CHROME to a Chrome binary to use another one.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const chrome = process.env.HYPERDASH_TEST_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const probe = readFileSync(new URL("./interaction_probe.js", import.meta.url), "utf8");
// Key handlers read the real clock; freeze it so the fixture's days are "today" and "yesterday".
const clock = `<script>(() => { const fixed = new Date("2026-10-16T22:20:00").getTime(); const Real = Date;
  globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }; })();</script>`;

let result = null;
const run = () => {
  if (result) return result;
  // A busy machine sometimes leaves the headless page without keyboard focus, so :focus-visible never
  // matches. Run again, up to three times, before reporting that.
  for (let attempt = 0; attempt < 3; attempt++) {
    result = once();
    if (result.routing.some((r) => r.focusVisible)) break;
  }
  return result;
};
const once = () => {
  const dir = mkdtempSync(join(tmpdir(), "hyperdash-interaction-"));
  const file = join(dir, "page.html");
  writeFileSync(file, `${html.replace(/<head>/i, `<head>${clock}`).replace(/<\/body>\s*<\/html>\s*$/, "")}<pre id="probe-out"></pre><script>${probe}</script></body></html>\n`);
  const out = spawnSync(chrome, ["--headless=new", "--disable-gpu", "--virtual-time-budget=20000", "--window-size=408,1000", "--dump-dom", `file://${file}`], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const match = /<pre id="probe-out">([\s\S]*?)<\/pre>/.exec(out.stdout || "");
  assert.ok(match, "the probe wrote no result: " + (out.stderr || "").slice(0, 400));
  return JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"));
};
const skip = !existsSync(chrome) && "Chrome not found (set HYPERDASH_TEST_CHROME)";

test("a keyboard-focused button keeps Enter and Space on every page", { skip, timeout: 120000 }, () => {
  const { routing } = run();
  const scenes = new Set(routing.map((r) => r.scene));
  for (const scene of ["overview", "layer", "about", "insights", "day", "yesterday", "interval", "month"]) assert.ok(scenes.has(scene), `no buttons walked on ${scene}`);
  for (const control of [".seg", ".appchip", ".time-chip", ".insight", "#header-icon", "#about-toggle", ".themebtn"]) {
    assert.ok(routing.some((r) => r.control.includes(control.replace(/^[.#]/, ""))), `the walk never reached ${control}`);
  }
  assert.ok(routing.every((r) => r.focusVisible), `the probe's focus did not count as keyboard focus (page focused: ${routing[0]?.hasFocus})`);
  const taken = routing.filter((r) => r.prevented || r.acted).map((r) => `${r.scene} ${r.control} ${JSON.stringify(r.key)}${r.prevented ? " cancelled" : ""}${r.acted ? " acted" : ""}`);
  assert.deepEqual(taken, [], "the page took Enter or Space away from a focused button");
});

test("Enter on a focused Activity bin does what a click does", { skip, timeout: 120000 }, () => {
  for (const { scene, bin, keyed, clicked } of run().bins) assert.equal(keyed, clicked, `${scene}: Enter on bin ${bin} gave ${keyed}, a click ${clicked}`);
});

test("using an Activity control from the keyboard leaves focus on a control", { skip, timeout: 120000 }, () => {
  const { focus } = run();
  assert.ok(focus.some((f) => f.control.includes("appchip")) && focus.some((f) => f.control.includes("seg")), "the walk missed app chips or day buttons");
  // A time chip gives way to its interval's commands, so it has nothing to keep focus on; not checked here.
  const kept = focus.filter((f) => !f.control.includes("time-chip"));
  assert.deepEqual(kept.filter((f) => f.after === "body").map((f) => `${f.scene} ${f.control}`), [], "focus fell to the body");
});

test("the Activity footer names what each key does in every focus state", { skip, timeout: 120000 }, () => {
  const { hints, heights, footerOverflow } = run();
  assert.ok(hints.length >= 80, `only ${hints.length} key presses checked`);
  for (const label of ["day", "month", "bin", "select", "clear", "press", "esc back", "esc clear"]) assert.ok(hints.some((h) => h.label === label), `no state showed "${label}"`);
  assert.deepEqual(hints.filter((h) => !h.ok).map((h) => `${h.scene}, focus ${h.focus}, ${h.key}: footer "${h.footer}"`), [], "the footer named the wrong action");
  assert.deepEqual(footerOverflow, [], "a footer was wider than the card");
  for (const [page, list] of Object.entries(heights)) assert.equal(list.length, 1, `${page} changed height with focus: ${list.join(", ")}`);
});
