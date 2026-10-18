// Run with: npx -y -p playwright@latest node --test karabiner/hyperdash/tests/motion.test.mjs
// The page-size motion (DESIGN.md §8), in WebKit, the engine hs.webview uses. A page change moves the card's
// bottom edge; nothing else moves. The page reports the window height the host must hold: before the card
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
// key(k), card() (the card's height now), last() (the last resize posted), moving() (running animations).
async function scene(browser, run, arg, { reducedMotion = "no-preference" } = {}) {
  const context = await browser.newContext({ viewport: { width: 408, height: 1000 }, deviceScaleFactor: 2, reducedMotion });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(file);
  await page.evaluate(() => {
    window.key = (k) => document.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
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

// Window heights (body padding included) on the fixture: overview 660, insights 500, activity 720.
const OVERVIEW = 660, INSIGHTS = 500, ACTIVITY = 720;

test("page-size motion (WebKit)", { timeout: 120000 }, async (t) => {
  const browser = await webkit();
  if (!browser) { t.skip("Playwright WebKit not found (run under npx -y -p playwright@latest, or set HYPERDASH_PLAYWRIGHT)"); return; }
  try {
    await t.test("growth asks for the window first and waits for hostReady", async () => {
      const r = await scene(browser, async () => {
        key("a");
        const asked = last();
        const held = card();
        hyperdash.hostReady(asked.transition + 1); // a stale or foreign id changes nothing
        await sleep(30);
        const stillHeld = card();
        hyperdash.hostReady(asked.transition);
        await sleep(90);
        const midway = card();
        await sleep(200);
        return { asked, held, stillHeld, midway, end: card(), scroll: document.body.scrollHeight, left: moving().length, title: document.getElementById("title").textContent };
      });
      assert.equal(r.title, "Activity", "the destination renders at once");
      assert.equal(r.asked.height, ACTIVITY);
      assert.ok(Number.isInteger(r.asked.transition), "the resize carries a transition id");
      assert.equal(r.held, OVERVIEW - 40, "the card keeps its height until the window is ready");
      assert.equal(r.stillHeld, OVERVIEW - 40, "a stale hostReady does not start the motion");
      assert.ok(r.midway > OVERVIEW - 40 && r.midway < ACTIVITY - 40, `the card moves after hostReady (${r.midway})`);
      assert.equal(r.end, ACTIVITY - 40);
      assert.equal(r.scroll, ACTIVITY);
      assert.equal(r.left, 0, "no animation is left behind");
    });

    await t.test("growth without an answer settles at once after 100 ms", async () => {
      const r = await scene(browser, async () => {
        key("a");
        await sleep(160);
        return { end: card(), left: moving().length, resizing: document.getElementById("card").classList.contains("resizing") };
      });
      assert.deepEqual(r, { end: ACTIVITY - 40, left: 0, resizing: false });
    });

    await t.test("shrink keeps the window until the card is done, then reports the smaller height", async () => {
      const r = await scene(browser, async () => {
        const { text, healths } = window.fixture;
        key("i");
        const during = last();
        const append = hyperdash.append({ generation: 1, from: text.length, to: text.length + 1, text: "\n" });
        const health = hyperdash.setHealth(healths.ok);
        hyperdash.setTheme("kozo");
        const running = moving().length;
        await sleep(300);
        return { during, append: append.height, health: health.height, running, after: last(), end: card(), left: moving().length };
      });
      assert.equal(r.during.height, OVERVIEW, "the window keeps its height while the card shrinks");
      assert.equal(r.during.transition, undefined, "a shrink does not wait for the host");
      assert.equal(r.append, OVERVIEW, "a data update mid-motion reports the window, not the card's passing height");
      assert.equal(r.health, OVERVIEW);
      assert.equal(r.running, 1, "a data update or a theme neither stops nor restarts the motion");
      assert.deepEqual(r.after, { action: "resize", height: INSIGHTS });
      assert.equal(r.end, INSIGHTS - 40);
      assert.equal(r.left, 0);
    });

    await t.test("the latest page wins: a new page change starts from the card's current height", async () => {
      const r = await scene(browser, async () => {
        key("i");
        await sleep(90);
        const at = card();
        key("Escape"); // back to the overview, mid-motion
        const from = card();
        const count = moving().length;
        const title = document.getElementById("title").textContent;
        key("a"); key("Escape"); key("i"); key("Escape"); key("a"); // rapid keys queue nothing
        const rapid = moving().length;
        const ask = last();
        if (ask.transition) hyperdash.hostReady(ask.transition);
        await sleep(400);
        return { at, from, count, title, rapid, end: card(), finalTitle: document.getElementById("title").textContent, last: last(), left: moving().length };
      });
      assert.ok(r.at < OVERVIEW - 40 && r.at > INSIGHTS - 40, `mid-motion height ${r.at}`);
      assert.ok(Math.abs(r.from - r.at) < 1, "the new motion starts where the card is");
      assert.equal(r.title, "hyperdash", "Escape goes back at once");
      assert.equal(r.count, 1);
      assert.equal(r.rapid, 1, "one motion at most");
      assert.equal(r.finalTitle, "Activity");
      assert.equal(r.end, ACTIVITY - 40);
      assert.equal(r.last.height, ACTIVITY);
      assert.equal(r.left, 0);
    });

    await t.test("Escape on the overview still closes the panel mid-motion", async () => {
      const r = await scene(browser, async () => {
        key("i"); await sleep(60); key("Escape"); key("Escape");
        return posted.filter((m) => m.action === "close").length;
      });
      assert.equal(r, 1);
    });

    await t.test("open() mid-motion settles at once on the overview", async () => {
      const r = await scene(browser, async () => {
        key("i"); await sleep(60);
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
        key("v"); await sleep(400); key("j"); key("k"); // selections within a layer
        const within = moving().length;
        return { within };
      });
      assert.equal(r.within, 0);
    });

    await t.test("reduced motion: every page change is instant", async () => {
      const r = await scene(browser, async () => {
        const seen = [];
        for (const k of ["i", "Escape", "a", "Escape", "v", "Escape"]) { key(k); seen.push([card(), last().height, last().transition ?? null, moving().length]); }
        return seen;
      }, {}, { reducedMotion: "reduce" });
      assert.deepEqual(r, [
        [INSIGHTS - 40, INSIGHTS, null, 0], [OVERVIEW - 40, OVERVIEW, null, 0], [ACTIVITY - 40, ACTIVITY, null, 0],
        [OVERVIEW - 40, OVERVIEW, null, 0], [676, 716, null, 0], [OVERVIEW - 40, OVERVIEW, null, 0],
      ]);
    });

    await t.test("the one animation is the card's height", async () => {
      const r = await scene(browser, async () => {
        key("i");
        return moving().map((a) => ({ target: a.effect.target.id, properties: a.effect.getKeyframes().flatMap((f) => Object.keys(f).filter((k) => !["offset", "easing", "composite", "computedOffset"].includes(k))),
          duration: a.effect.getTiming().duration, easing: a.effect.getTiming().easing }));
      });
      assert.deepEqual(r, [{ target: "card", properties: ["height", "height"], duration: 180, easing: "cubic-bezier(0.455, 0.03, 0.515, 0.955)" }]);
    });
  } finally {
    await browser.close();
  }
});
