// Run with: npx -y -p playwright@latest node --test karabiner/hyperdash/tests/motion.test.mjs
// The page-size motion (DESIGN.md §8), in WebKit, the engine hs.webview uses. A page change made with the
// pointer moves the card's bottom edge; a keyboard page change is instant; nothing else moves. The page reports the window height the host must hold: before the card
// grows past the window it asks for the taller window and waits for hostReady(id), at most 100 ms; while the
// card shrinks the window keeps its height, and shrinks after. Data updates, themes, open() and reduced
// motion never animate. Skips when Playwright WebKit is not available (see grid.test.mjs).
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const probe = readFileSync(new URL("./height_probe.js", import.meta.url), "utf8");
// The probe's fixture without its walk: everything before the first page, which ends with hyperdash.open({}).
const fixture = `${probe.slice(0, probe.indexOf("  // Overview"))}\n  window.fixture = { text, healths };\n})();\n`;
const clock = `<script>(() => { const real = new Date(); real.setHours(15, 0, 0, 0); const fixed = real.getTime(); const Real = Date;
  globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }; })();</script>`;
// Stands in for the host: records what the page posts.
const host = `<script>window.posted = []; window.webkit = { messageHandlers: { dashboard: { postMessage: (m) => window.posted.push(m) } } };</script>`;

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

const file = (() => {
  const dir = mkdtempSync(join(tmpdir(), "hyperdash-motion-"));
  const path = join(dir, "page.html");
  writeFileSync(path, `${html.replace("<head>", `<head>${clock}${host}`).replace(/<\/body>\s*<\/html>\s*$/, "")}<script>${fixture}</script></body></html>\n`);
  return pathToFileURL(path).href;
})();

// Opens the fixture on the overview with the window at the overview's height. Page functions used in `run`:
// key(k), tap(node), layerKey(letter), back(), card() (the card's height now), last() (the last resize posted), moving() (running animations).
async function scene(browser, run, arg, { reducedMotion = "no-preference" } = {}) {
  const context = await browser.newContext({ viewport: { width: 408, height: 1000 }, deviceScaleFactor: 2, reducedMotion });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(file);
  await page.evaluate(() => {
    window.key = (k) => document.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
    // A real pointer click (detail 1): on a heatmap key (opens its layer on the overview) or the header Back.
    window.tap = (node) => node.dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 1 }));
    window.layerKey = (letter) => [...document.querySelectorAll(".key")].find((n) => n.textContent === letter);
    window.back = () => document.getElementById("header-icon");
    window.card = () => document.getElementById("card").getBoundingClientRect().height;
    window.last = () => window.posted.filter((m) => m.action === "resize").at(-1);
    window.moving = () => document.getAnimations().filter((a) => a.playState !== "finished");
    window.sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    hyperdash.open({});
    window.posted.length = 0;
  });
  try {
    return await page.evaluate(run, arg);
  } finally {
    await context.close();
    assert.deepEqual(errors, []);
  }
}

// Window heights (body padding included) on the fixture: overview 660, a layer 716, insights 500, activity 720.
const OVERVIEW = 660, LAYER = 716, INSIGHTS = 500, ACTIVITY = 720;

test("page-size motion (WebKit)", { timeout: 120000 }, async (t) => {
  const browser = await webkit();
  if (!browser) { t.skip("Playwright WebKit not found (run under npx -y -p playwright@latest, or set HYPERDASH_PLAYWRIGHT)"); return; }
  try {
    await t.test("a keyboard page change is instant: no motion, the window takes the new height at once", async () => {
      const r = await scene(browser, async () => {
        const seen = [];
        for (const k of ["i", "Escape", "a", "Escape", "v", "Escape"]) { key(k); seen.push([card(), last().height, last().transition ?? null, moving().length]); }
        return seen;
      });
      assert.deepEqual(r, [
        [INSIGHTS - 40, INSIGHTS, null, 0], [OVERVIEW - 40, OVERVIEW, null, 0], [ACTIVITY - 40, ACTIVITY, null, 0],
        [OVERVIEW - 40, OVERVIEW, null, 0], [LAYER - 40, LAYER, null, 0], [OVERVIEW - 40, OVERVIEW, null, 0],
      ]);
    });

    await t.test("Enter on a focused button counts as a key: no motion", async () => {
      const r = await scene(browser, async () => {
        key("v"); // to a layer, instant
        back().dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 0 })); // what Enter on a button fires
        return { card: card(), left: moving().length };
      });
      assert.deepEqual(r, { card: OVERVIEW - 40, left: 0 });
    });

    await t.test("pointer growth asks for the window first and waits for hostReady", async () => {
      const r = await scene(browser, async () => {
        tap(layerKey("V"));
        const asked = last();
        const held = card();
        hyperdash.hostReady(asked.transition + 1); // a stale or foreign id changes nothing
        await sleep(30);
        const stillHeld = card();
        hyperdash.hostReady(asked.transition);
        await sleep(40);
        const midway = card();
        await sleep(200);
        return { asked, held, stillHeld, midway, end: card(), scroll: document.body.scrollHeight, left: moving().length, title: document.getElementById("title").textContent };
      });
      assert.notEqual(r.title, "hyperdash", "the destination renders at once");
      assert.equal(r.asked.height, LAYER);
      assert.ok(Number.isInteger(r.asked.transition), "the resize carries a transition id");
      assert.equal(r.held, OVERVIEW - 40, "the card keeps its height until the window is ready");
      assert.equal(r.stillHeld, OVERVIEW - 40, "a stale hostReady does not start the motion");
      assert.ok(r.midway > OVERVIEW - 40 && r.midway < LAYER - 40, `the card moves after hostReady (${r.midway})`);
      assert.equal(r.end, LAYER - 40);
      assert.equal(r.scroll, LAYER);
      assert.equal(r.left, 0, "no animation is left behind");
    });

    await t.test("pointer growth without an answer settles at once after 100 ms", async () => {
      const r = await scene(browser, async () => {
        tap(layerKey("V"));
        await sleep(160);
        return { end: card(), left: moving().length, resizing: document.getElementById("card").classList.contains("resizing") };
      });
      assert.deepEqual(r, { end: LAYER - 40, left: 0, resizing: false });
    });

    await t.test("pointer shrink keeps the window until the card is done, then reports the smaller height", async () => {
      const r = await scene(browser, async () => {
        const { text, healths } = window.fixture;
        key("v"); // to the layer, instant
        tap(back());
        const during = last();
        const append = hyperdash.append({ generation: 1, from: text.length, to: text.length + 1, text: "\n" });
        const health = hyperdash.setHealth(healths.ok);
        hyperdash.setTheme("kozo");
        const running = moving().length;
        await sleep(300);
        return { during, append: append.height, health: health.height, running, after: last(), end: card(), left: moving().length };
      });
      assert.equal(r.during.height, LAYER, "the window keeps its height while the card shrinks");
      assert.equal(r.during.transition, undefined, "a shrink does not wait for the host");
      assert.equal(r.append, LAYER, "a data update mid-motion reports the window, not the card's passing height");
      assert.equal(r.health, LAYER);
      assert.equal(r.running, 1, "a data update or a theme neither stops nor restarts the motion");
      assert.deepEqual(r.after, { action: "resize", height: OVERVIEW });
      assert.equal(r.end, OVERVIEW - 40);
      assert.equal(r.left, 0);
    });

    await t.test("the latest page wins: a key mid-motion settles at once on its page", async () => {
      const r = await scene(browser, async () => {
        key("v");
        tap(back());
        await sleep(50);
        const at = card();
        key("i"); // a key mid-motion: instant
        return { at, card: card(), left: moving().length, title: document.getElementById("title").textContent, last: last() };
      });
      assert.ok(r.at < LAYER - 40 && r.at > OVERVIEW - 40, `mid-motion height ${r.at}`);
      assert.equal(r.title, "Insights", "the key goes to its page at once");
      assert.equal(r.card, INSIGHTS - 40);
      assert.equal(r.left, 0, "the motion stops");
      assert.equal(r.last.height, INSIGHTS);
    });

    await t.test("the latest page wins: a pointer change mid-motion starts from the card's current height", async () => {
      const r = await scene(browser, async () => {
        key("v");
        tap(back());
        await sleep(50);
        const at = card();
        tap(layerKey("V")); // back into the layer, mid-motion
        const from = card();
        const count = moving().length;
        const ask = last();
        if (ask.transition) hyperdash.hostReady(ask.transition);
        await sleep(300);
        return { at, from, count, end: card(), left: moving().length };
      });
      assert.ok(Math.abs(r.from - r.at) < 1, "the new motion starts where the card is");
      assert.ok(r.count <= 1, "one motion at most");
      assert.equal(r.end, LAYER - 40);
      assert.equal(r.left, 0);
    });

    await t.test("Escape on the overview still closes the panel mid-motion", async () => {
      const r = await scene(browser, async () => {
        key("v"); tap(back()); await sleep(40); key("Escape");
        return posted.filter((m) => m.action === "close").length;
      });
      assert.equal(r, 1);
    });

    await t.test("open() mid-motion settles at once on the overview", async () => {
      const r = await scene(browser, async () => {
        tap(layerKey("V")); hyperdash.hostReady(last().transition); await sleep(40);
        const result = hyperdash.open({});
        return { height: result.height, card: card(), left: moving().length };
      });
      assert.deepEqual(r, { height: OVERVIEW, card: OVERVIEW - 40, left: 0 });
    });

    await t.test("data updates, themes and non-page interactions never animate", async () => {
      const r = await scene(browser, async () => {
        const { text, healths } = window.fixture;
        hyperdash.setTheme("kozo"); key("t");
        hyperdash.append({ generation: 1, from: text.length, to: text.length + 1, text: "\n" });
        hyperdash.setHealth(healths.error); hyperdash.setHealth(healths.ok);
        hyperdash.setInsights(null); hyperdash.tick({});
        key("ArrowLeft"); key("ArrowRight"); key("?"); key("?");
        key("v"); await sleep(300); key("j"); key("k"); // selections within a layer
        return { within: moving().length };
      });
      assert.equal(r.within, 0);
    });

    await t.test("reduced motion: a pointer page change is instant too", async () => {
      const r = await scene(browser, async () => {
        tap(layerKey("V"));
        const there = [card(), last().height, last().transition ?? null, moving().length];
        tap(back());
        return [there, [card(), last().height, last().transition ?? null, moving().length]];
      }, {}, { reducedMotion: "reduce" });
      assert.deepEqual(r, [[LAYER - 40, LAYER, null, 0], [OVERVIEW - 40, OVERVIEW, null, 0]]);
    });

    await t.test("the one animation is the card's height, strong ease-out in 160 ms", async () => {
      const r = await scene(browser, async () => {
        key("v");
        tap(back());
        return moving().map((a) => ({ target: a.effect.target.id, properties: a.effect.getKeyframes().flatMap((f) => Object.keys(f).filter((k) => !["offset", "easing", "composite", "computedOffset"].includes(k))),
          duration: a.effect.getTiming().duration, easing: a.effect.getTiming().easing }));
      });
      assert.deepEqual(r, [{ target: "card", properties: ["height", "height"], duration: 160, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }]);
    });
  } finally {
    await browser.close();
  }
});
