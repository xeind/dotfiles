// Run with: node --test karabiner/hyperdash/tests/archive.test.mjs
// An archived day read back on demand (docs/RETENTION.md): the real page in headless Chrome, loaded from the
// retention fixture's summary and tail, asks the host for a day before the tail start, shows it in full when the
// answer comes, and stays counts only when it does not. retention.test.mjs proves the day equals the whole-log day;
// this file checks the page around it: requests, stale answers, failures, the timeout and the height. Skips when
// Chrome is not installed; set HYPERDASH_TEST_CHROME to a Chrome binary to use another one.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import test, { after, before } from "node:test";

const chrome = process.env.HYPERDASH_TEST_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const skip = !existsSync(chrome) && "Chrome not found (set HYPERDASH_TEST_CHROME)";
const options = { skip, timeout: 120000 };

const NOW = "2026-10-17T18:00:00";
const fixture = (name) => readFileSync(new URL(`./retention_cases/${name}`, import.meta.url));
const usage = fixture("usage.log");
const contextLog = fixture("context.log");
const [header, summary, { days: index }] = fixture("retention.json").toString("utf8").trim().split("\n").map((line) => JSON.parse(line));
const bindings = JSON.parse(fixture("bindings.json").toString("utf8"));

// The host's answer for one day, as hyperdash.lua builds it from the index.
function answer(id, date) {
  const [u0, u1, c0, c1] = index[date];
  const end = c1 === -1 ? contextLog.lastIndexOf(10) + 1 : c1;
  return { id, date, usage: usage.subarray(u0, u1).toString("utf8"), context: contextLog.subarray(c0, end).toString("utf8") };
}

let dir = null;
let browser = null;
let socket = null;
let lastId = 0;
const pending = new Map();

function send(method, params = {}, sessionId) {
  const id = ++lastId;
  socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject, method }));
}

before(async () => {
  if (skip) return;
  dir = mkdtempSync(join(tmpdir(), "hyperdash-archive-"));
  browser = spawn(chrome, ["--headless=new", "--disable-gpu", "--remote-debugging-port=0", `--user-data-dir=${join(dir, "profile")}`, "--window-size=408,1000", "about:blank"]);
  const url = await new Promise((resolve, reject) => {
    let err = "";
    browser.stderr.on("data", (chunk) => {
      err += chunk;
      const match = /DevTools listening on (ws:\S+)/.exec(err);
      if (match) resolve(match[1]);
    });
    browser.on("exit", () => reject(new Error(`Chrome exited: ${err.slice(0, 400)}`)));
  });
  socket = new WebSocket(url);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    const call = pending.get(message.id);
    if (!call) return;
    pending.delete(message.id);
    if (message.error) call.reject(new Error(`${call.method}: ${message.error.message}`));
    else call.resolve(message.result);
  };
});

after(async () => {
  socket?.close();
  if (browser && browser.exitCode === null) await new Promise((resolve) => { browser.on("exit", resolve); browser.kill(); });
  if (dir) rmSync(dir, { recursive: true, force: true });
});

// A fresh tab with the clock frozen at NOW, the messages the page posts collected in window.posts, and the
// fixture loaded from the cut with its summary, as the host sends it.
async function openPage() {
  const clock = `<script>(() => { const fixed = new Date(${JSON.stringify(NOW)}).getTime(); const Real = Date;
    globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } };
    globalThis.posts = []; globalThis.webkit = { messageHandlers: { dashboard: { postMessage: (m) => posts.push(m) } } }; })();</script>`;
  const file = join(dir, `page-${++lastId}.html`);
  writeFileSync(file, html.replace("<head>", `<head>${clock}`));
  const { targetId } = await send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
  const call = (method, params) => send(method, params, sessionId);
  await call("Page.navigate", { url: pathToFileURL(file).href });
  const page = {
    async eval(expression) {
      const { result, exceptionDetails } = await call("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      if (exceptionDetails) throw new Error(`${exceptionDetails.exception?.description || exceptionDetails.text}\n  in: ${expression.slice(0, 200)}`);
      return result.value;
    },
    height: () => page.eval("document.getAnimations().forEach((a) => a.finish()), document.body.scrollHeight"),
    // The day requests posted so far.
    requests: () => page.eval(`posts.filter((m) => m.action === "day")`),
    // What the day view shows: the strip key, the panel head, the app bar and the number of command rows.
    view: () => page.eval(`({
      key: document.querySelector(".chart-legend .row:last-child")?.textContent,
      head: document.querySelector("#panel .panel-head")?.textContent,
      apps: document.querySelectorAll("#appbar .appchip").length,
      appbar: document.querySelector("#appbar")?.textContent,
    })`),
    close: () => send("Target.closeTarget", { targetId }),
  };
  for (let i = 0; i < 100 && !(await page.eval("document.readyState === 'complete' && typeof hyperdash === 'object'").catch(() => false)); i++) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const tail = (bytes, from) => bytes.subarray(from, bytes.lastIndexOf(10) + 1).toString("utf8");
  const health = { log: { status: "ok", bytes: usage.length, modified: NOW }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" } };
  const result = await page.eval(`(() => {
    const a = hyperdash.reset({ now: ${JSON.stringify(NOW)}, generation: 1, bindings: ${JSON.stringify(bindings)}, text: ${JSON.stringify(tail(usage, header.usage.offset))},
      offset: ${usage.lastIndexOf(10) + 1}, archive: ${JSON.stringify(summary)}, insights: null, health: ${JSON.stringify(health)} });
    const b = hyperdash.reset({ now: ${JSON.stringify(NOW)}, stream: "context", generation: 1, text: ${JSON.stringify(tail(contextLog, header.context.offset))}, offset: ${contextLog.lastIndexOf(10) + 1} });
    hyperdash.open({ now: ${JSON.stringify(NOW)} });
    return [a.ok, b.ok];
  })()`);
  assert.deepEqual(result, [true, true]);
  return page;
}

const showDay = (page, date) => page.eval(`openDay(${JSON.stringify(date)})`);
const loadDay = (page, data) => page.eval(`hyperdash.loadDay(${JSON.stringify(data)})`);

test("archive: an archived day asks once, keeps its counts until the answer, then shows its detail at the same height", options, async () => {
  const page = await openPage();
  try {
    await showDay(page, "2026-09-02");
    assert.deepEqual(await page.requests(), [], "a tail day needs no read");
    const tailHeight = await page.height();

    await showDay(page, "2026-08-18");
    assert.deepEqual(await page.requests(), [{ action: "day", date: "2026-08-18", id: 1 }]);
    const waiting = await page.view();
    assert.match(waiting.key, /ARCHIVED · COUNTS ONLY/);
    assert.equal(waiting.apps, 0);
    assert.equal(await page.height(), tailHeight, "the archived day has a tail day's height");
    // Renders while the read is out ask nothing more.
    await page.eval(`hyperdash.setHealth(${JSON.stringify({ log: { status: "ok", bytes: 1, modified: NOW }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" } })})`);
    assert.equal((await page.requests()).length, 1);

    const result = await loadDay(page, answer(1, "2026-08-18"));
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.height, tailHeight, "the answer reports the same height");
    const shown = await page.view();
    assert.match(shown.key, /RECORDED/);
    assert.doesNotMatch(shown.key, /ARCHIVED/);
    assert.match(shown.head, /Observed sequences/);
    assert.ok(shown.apps > 0, JSON.stringify(shown));
    assert.equal(await page.height(), tailHeight);

    // The same answer again, or one for another request, changes nothing.
    assert.equal((await loadDay(page, answer(1, "2026-08-18"))).reason, "stale");
    assert.equal((await loadDay(page, answer(7, "2026-08-18"))).reason, "stale");
    assert.match((await page.view()).key, /RECORDED/);

    // An interval of the loaded day lists its commands.
    await page.eval(`selectInterval(18)`);
    assert.ok(await page.eval(`document.querySelectorAll("#panel .cmd").length`) > 0);
  } finally {
    await page.close();
  }
});

test("archive: a failed read, a refused answer and a late answer leave the day counts only", options, async () => {
  const page = await openPage();
  try {
    await showDay(page, "2026-08-10");
    const height = await page.height();
    // The host could not read the day.
    assert.deepEqual(await loadDay(page, { id: 1, date: "2026-08-10", usage: null, context: null }), { ok: false, reason: "day", height });
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    await page.eval(`render()`);
    assert.equal((await page.requests()).length, 1, "a failed day is not asked again before the next open");

    // Lines that do not add up to the archived counts: another day's.
    await showDay(page, "2026-08-11");
    assert.equal((await loadDay(page, { ...answer(2, "2026-08-10"), date: "2026-08-11" })).reason, "day");
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    assert.equal(await page.height(), height);

    // No answer within the timeout: counts only, and the late answer is ignored.
    await showDay(page, "2026-08-12");
    const before = await page.requests();
    assert.deepEqual(before.at(-1), { action: "day", date: "2026-08-12", id: 3 });
    await new Promise((resolve) => setTimeout(resolve, 5300));
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    assert.equal((await loadDay(page, answer(3, "2026-08-12"))).reason, "stale");
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    assert.equal(await page.height(), height);

    // The next open asks again.
    await page.eval(`hyperdash.open({ now: ${JSON.stringify(NOW)} })`);
    await showDay(page, "2026-08-10");
    assert.deepEqual((await page.requests()).at(-1), { action: "day", date: "2026-08-10", id: 4 });
    assert.equal((await loadDay(page, answer(4, "2026-08-10"))).ok, true);
  } finally {
    await page.close();
  }
});

test("archive: the loaded day is dropped by a reset of either log and by the next open", options, async () => {
  const page = await openPage();
  try {
    await showDay(page, "2026-08-13");
    assert.equal((await loadDay(page, answer(1, "2026-08-13"))).ok, true);
    // A day with no presses still shows its coverage strip once loaded.
    assert.match((await page.view()).key, /RECORDED/);
    // Moving to another day and back keeps the one loaded day.
    await showDay(page, "2026-09-03");
    await showDay(page, "2026-08-13");
    assert.equal((await page.requests()).length, 1);
    assert.match((await page.view()).key, /RECORDED/);

    // A reset of the context stream drops it; the page asks again for the day it shows.
    const ctx = contextLog.subarray(header.context.offset, contextLog.lastIndexOf(10) + 1).toString("utf8");
    await page.eval(`hyperdash.reset({ now: ${JSON.stringify(NOW)}, stream: "context", generation: 2, text: ${JSON.stringify(ctx)}, offset: ${contextLog.lastIndexOf(10) + 1} })`);
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    assert.deepEqual((await page.requests()).at(-1), { action: "day", date: "2026-08-13", id: 2 });
    assert.equal((await loadDay(page, answer(1, "2026-08-13"))).reason, "stale", "an answer from before the reset");
    assert.equal((await loadDay(page, answer(2, "2026-08-13"))).ok, true);

    // open() drops it: the same day asks again.
    await page.eval(`hyperdash.open({ now: ${JSON.stringify(NOW)} })`);
    await showDay(page, "2026-08-13");
    assert.match((await page.view()).key, /ARCHIVED · COUNTS ONLY/);
    assert.deepEqual((await page.requests()).at(-1), { action: "day", date: "2026-08-13", id: 3 });
  } finally {
    await page.close();
  }
});
