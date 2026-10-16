// Run with: node --test karabiner/hyperdash/tests/height.test.mjs
// Drives the real page in headless Chrome through every interaction and asserts that the page height never
// changes within a page (overview, a layer, Activity, Insights). Skips when Chrome is not installed;
// set HYPERDASH_TEST_CHROME to a Chrome binary to use another one.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const chrome = process.env.HYPERDASH_TEST_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const probe = readFileSync(new URL("./height_probe.js", import.meta.url), "utf8");

test("the page height never changes within a page", { skip: !existsSync(chrome) && "Chrome not found (set HYPERDASH_TEST_CHROME)", timeout: 120000 }, () => {
  const dir = mkdtempSync(join(tmpdir(), "hyperdash-height-"));
  const file = join(dir, "page.html");
  writeFileSync(file, `${html.replace(/<\/body>\s*<\/html>\s*$/, "")}<pre id="probe-out"></pre><script>${probe}</script></body></html>\n`);
  const run = spawnSync(chrome, ["--headless=new", "--disable-gpu", "--virtual-time-budget=20000", "--window-size=408,1000", "--dump-dom", `file://${file}`], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const match = /<pre id="probe-out">([\s\S]*?)<\/pre>/.exec(run.stdout || "");
  assert.ok(match, "the probe wrote no result: " + (run.stderr || "").slice(0, 400));
  const { summary, steps, titles, clipped, fades } = JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"));
  // A native tooltip clips at the card edge, so the card carries none: aria-label and visible text instead.
  assert.deepEqual(titles, [], "native tooltips inside the card");
  // No legend cell may cut off its text, even with five-digit counts in every group.
  assert.deepEqual(clipped, [], "legend cells wider than their box");
  // Edge fades appear only where content continues past that edge, and use a real mask.
  const expected = {
    "list top": ["bottom", true], "list middle": ["both", true], "list bottom": ["top", true], "list fits": [null, false],
    "commands top": ["bottom", true], "commands middle": ["both", true], "commands bottom": ["top", true],
    "insights middle": ["both", true], "insights fits": [null, false],
  };
  for (const [label, want] of Object.entries(expected)) assert.deepEqual(fades[label], want, `fade state for ${label}`);
  assert.deepEqual(fades.sequences?.[0] === null || ["bottom", "top", "both"].includes(fades.sequences?.[0]), true);
  assert.ok(steps > 500, `the probe only ran ${steps} steps`);
  assert.deepEqual(Object.keys(summary).sort(), ["activity", "insights", "layer", "overview"]);
  for (const [page, heights] of Object.entries(summary)) {
    const detail = Object.entries(heights).map(([h, v]) => `${h}px: ${v.count} steps, e.g. ${v.examples.join(" | ")}`).join("\n    ");
    assert.equal(Object.keys(heights).length, 1, `the ${page} page changed height:\n    ${detail}`);
    const ran = Object.values(heights).reduce((n, v) => n + v.count, 0);
    assert.ok(ran >= { overview: 20, layer: 300, activity: 150, insights: 12 }[page], `the probe skipped steps on the ${page} page (${ran})`);
  }
});
