// Run with: node --test karabiner/hyperdash/tests/picker.test.mjs
// The Activity date picker in the real page, driven in headless Chrome with real key and mouse events: it opens
// over Activity at the same height, Escape and Close change nothing, a typed or picked day opens through the
// normal day path (archived days included), keys never reach the page behind it, and data updates keep the
// draft. Loads the retention fixture (archived days before 2026-09-01). Skips when Chrome is not installed;
// set HYPERDASH_TEST_CHROME to a Chrome binary to use another one.
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
const FIRST = "2026-07-20"; // the fixture's first recorded day
const fixture = (name) => readFileSync(new URL(`./retention_cases/${name}`, import.meta.url));
const usage = fixture("usage.log");
const contextLog = fixture("context.log");
const [header, summary, { days: index }] = fixture("retention.json").toString("utf8").trim().split("\n").map((line) => JSON.parse(line));
const bindings = JSON.parse(fixture("bindings.json").toString("utf8"));

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
  dir = mkdtempSync(join(tmpdir(), "hyperdash-picker-"));
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

const KEYS = { Escape: 27, Enter: 13, Tab: 9, " ": 32, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, PageUp: 33, PageDown: 34, Home: 36, End: 35, Backspace: 8 };

// A fresh tab with the clock frozen at NOW, posts collected in window.posts, the fixture loaded as the host sends
// it, and Activity open on today.
async function openPage() {
  // The clock is frozen at NOW; a test moves it through globalThis.clockNow.
  const clock = `<script>(() => { globalThis.clockNow = new Date(${JSON.stringify(NOW)}).getTime(); const Real = Date;
    globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [clockNow])); } static now() { return clockNow; } };
    globalThis.posts = []; globalThis.webkit = { messageHandlers: { dashboard: { postMessage: (m) => posts.push(m) } } }; })();</script>`;
  const file = join(dir, `page-${++lastId}.html`);
  writeFileSync(file, html.replace("<head>", `<head>${clock}`));
  const { targetId } = await send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
  const call = (method, params) => send(method, params, sessionId);
  await call("Emulation.setFocusEmulationEnabled", { enabled: true });
  await call("Page.navigate", { url: pathToFileURL(file).href });
  const page = {
    async eval(expression) {
      const { result, exceptionDetails } = await call("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      if (exceptionDetails) throw new Error(`${exceptionDetails.exception?.description || exceptionDetails.text}\n  in: ${expression.slice(0, 200)}`);
      return result.value;
    },
    // Keys that type a character (Enter types "\r") send it, so a focused button activates as it does natively.
    async key(key, { shift = false } = {}) {
      const base = { key, code: key.length === 1 ? `Key${key.toUpperCase()}` : key, windowsVirtualKeyCode: KEYS[key] ?? key.toUpperCase().charCodeAt(0), modifiers: shift ? 8 : 0 };
      const text = key === "Enter" ? "\r" : key.length === 1 ? key : null;
      await call("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...base, ...(text ? { text } : {}) });
      await call("Input.dispatchKeyEvent", { type: "keyUp", ...base });
    },
    async type(text) { for (const ch of text) await page.key(ch); },
    async click(selector) {
      const box = await page.eval(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
      await page.clickAt(box.x, box.y);
    },
    async clickAt(x, y) {
      for (const type of ["mousePressed", "mouseReleased"]) await call("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
    },
    height: () => page.eval("document.getAnimations().forEach((a) => a.finish()), document.body.scrollHeight"),
    requests: () => page.eval(`posts.filter((m) => m.action === "day")`),
    // Everything the picker must leave alone, and what it shows.
    activity: () => page.eval(`({ day: state.day, mode: state.activityMode, monthId: state.monthId, highlight: state.highlight, interval: state.interval,
      focusSec: state.focusSec, appFilter: state.appFilter, page: state.page, label: document.getElementById("date-trigger").textContent.trim() })`),
    picker: () => page.eval(`(() => {
      const root = document.getElementById("picker");
      const focus = document.activeElement;
      return { open: !root.hidden, focus: focus?.id || focus?.dataset?.date || focus?.tagName, inside: root.contains(focus),
        month: document.getElementById("picker-month").textContent, text: document.getElementById("picker-input").value,
        help: document.getElementById("picker-help").textContent, expanded: document.getElementById("date-trigger").getAttribute("aria-expanded"),
        inert: [...document.getElementById("card").children].filter((n) => n !== root && n.inert).length };
    })()`),
    footer: () => page.eval(`document.getElementById("footer").textContent`),
    close: () => send("Target.closeTarget", { targetId }),
  };
  for (let i = 0; i < 100 && !(await page.eval("document.readyState === 'complete' && typeof hyperdash === 'object'").catch(() => false)); i++) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  await call("Page.bringToFront");
  const tail = (bytes, from) => bytes.subarray(from, bytes.lastIndexOf(10) + 1).toString("utf8");
  const health = { log: { status: "ok", bytes: usage.length, modified: NOW }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" } };
  await page.eval(`(() => {
    hyperdash.reset({ now: ${JSON.stringify(NOW)}, generation: 1, bindings: ${JSON.stringify(bindings)}, text: ${JSON.stringify(tail(usage, header.usage.offset))},
      offset: ${usage.lastIndexOf(10) + 1}, archive: ${JSON.stringify(summary)}, insights: null, health: ${JSON.stringify(health)} });
    hyperdash.reset({ now: ${JSON.stringify(NOW)}, stream: "context", generation: 1, text: ${JSON.stringify(tail(contextLog, header.context.offset))}, offset: ${contextLog.lastIndexOf(10) + 1} });
    hyperdash.open({ now: ${JSON.stringify(NOW)} });
  })()`);
  await page.key("a"); // the A key opens Activity, as a user would
  return page;
}

test("picker: the date box opens a dialog over Activity at the same height; Escape and Close change nothing", options, async () => {
  const page = await openPage();
  try {
    await page.eval(`openDay("2026-10-12")`);
    await page.key("w"); // a highlight, which Escape would clear if it reached the page
    const height = await page.height();
    const before = await page.activity();
    assert.equal(before.highlight, "w");
    assert.equal(await page.eval(`document.getElementById("date-trigger").getAttribute("aria-haspopup")`), "dialog");
    assert.equal(await page.eval(`document.getElementById("date-trigger").getAttribute("aria-label")`), "Choose activity date, Monday, October 12, 2026");

    await page.click("#date-trigger");
    let shown = await page.picker();
    assert.equal(shown.open, true);
    assert.equal(shown.expanded, "true");
    assert.equal(shown.focus, "2026-10-12", "focus starts on the Activity day");
    assert.equal(shown.text, "2026-10-12");
    assert.equal(shown.month, "OCTOBER 2026");
    assert.ok(shown.inert > 0, "the page behind is inert");
    assert.equal(await page.height(), height, "the picker never changes the page height");
    assert.equal(await page.eval(`document.querySelector('.picker-day[data-date="2026-10-12"]').getAttribute("aria-selected")`), "true");
    assert.match(await page.eval(`document.querySelector('.picker-day[data-date="2026-10-17"]').getAttribute("aria-label")`), /^Saturday, October 17, 2026, today/);
    assert.equal(await page.eval(`document.querySelector('.picker-day[data-date="2026-10-18"]').disabled`), true, "tomorrow is unavailable");
    assert.equal(shown.help, "AVAILABLE JUL 20, 2026 – OCT 17, 2026", "the bottom line shows the range until there is a reason");

    // One reserved line, at the bottom: the field sits one section gap (12) above the month row.
    const gap = await page.eval(`document.querySelector(".picker-month").getBoundingClientRect().top - document.querySelector(".picker-entry").getBoundingClientRect().bottom`);
    assert.equal(gap, 12, "an empty line still sits between the field and the calendar");
    // The month arrows centre on the Sunday and Saturday tiles.
    const centre = (selector) => page.eval(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return r.left + r.width / 2; })()`);
    const sunday = await centre(".picker-row:nth-child(2) .picker-day:first-child");
    const saturday = await centre(".picker-row:nth-child(2) .picker-day:last-child");
    assert.ok(Math.abs((await centre("#picker-previous")) - sunday) < 0.5, "the previous-month arrow is off the Sunday column");
    assert.ok(Math.abs((await centre("#picker-next")) - saturday) < 0.5, "the next-month arrow is off the Saturday column");

    // Browse and edit, then cancel: nothing behind it moved.
    await page.key("ArrowLeft");
    await page.key("PageUp");
    shown = await page.picker();
    assert.equal(shown.focus, "2026-09-11");
    assert.equal(shown.month, "SEPTEMBER 2026");
    assert.deepEqual(await page.activity(), before, "grid keys reached the page");
    await page.key("Escape");
    shown = await page.picker();
    assert.equal(shown.open, false);
    assert.equal(shown.expanded, "false");
    assert.equal(shown.focus, "date-trigger", "focus goes back to the date box");
    assert.equal(shown.inert, 0);
    assert.deepEqual(await page.activity(), before, "Escape closed more than the picker");

    // Six fixed rows: a five-week month (October 2026), a six-week one (August 2026) and a reason in the reserved
    // line all give the dialog one height.
    const dialog = () => page.eval(`document.querySelector(".picker-dialog").getBoundingClientRect().height`);
    await page.click("#date-trigger");
    // A day is a square 28 px tile centred in its column, not a bar as wide as the column.
    const tile = await page.eval(`(() => { const r = document.querySelector('.picker-day[data-date="2026-10-12"]').getBoundingClientRect(); return [r.width, r.height]; })()`);
    assert.deepEqual(tile, [28, 28], "day tiles are not square");
    const five = await dialog();
    for (let i = 0; i < 2; i++) await page.click("#picker-previous");
    assert.equal((await page.picker()).month, "AUGUST 2026");
    assert.equal(await dialog(), five, "a six-week month changed the dialog's height");
    await page.eval(`document.getElementById("picker-input").value = "x"`);
    await page.click("#picker-open");
    assert.equal((await page.picker()).help, "Use YYYY-MM-DD");
    assert.equal(await dialog(), five, "a reason changed the dialog's height");
    await page.key("Escape");

    // Close, and a click on the card outside the dialog, also cancel. The next open starts from the Activity day again.
    await page.click("#date-trigger");
    assert.equal((await page.picker()).month, "OCTOBER 2026");
    await page.click("#picker-close");
    assert.equal((await page.picker()).open, false);
    await page.click("#date-trigger");
    const footer = await page.eval(`(() => { const r = document.getElementById("footer").getBoundingClientRect(); return { x: r.left + 40, y: r.top + r.height / 2 }; })()`);
    await page.clickAt(footer.x, footer.y);
    assert.equal((await page.picker()).open, false, "a click on the card outside the dialog closes it");
    assert.deepEqual(await page.activity(), before);
    assert.equal(await page.height(), height);
  } finally {
    await page.close();
  }
});

test("picker: a typed date opens; bad text stays with its reason; Enter in the field never switches views", options, async () => {
  const page = await openPage();
  try {
    await page.click("#date-trigger");
    await page.click("#picker-input");
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type("2026-02-30");
    await page.key("Enter");
    let shown = await page.picker();
    assert.equal(shown.open, true);
    assert.equal(shown.help, "That date does not exist");
    assert.equal(shown.text, "2026-02-30", "the text is kept");
    assert.equal(await page.eval(`document.getElementById("picker-input").getAttribute("aria-invalid")`), "true");
    assert.equal((await page.activity()).mode, "day", "Enter in the field switched views");

    for (const [text, help] of [["2026-9-14", "Use YYYY-MM-DD"], ["2026-07-19", "Choose a date from Jul 20, 2026 through Oct 17, 2026"], ["2026-10-18", "Choose a date from Jul 20, 2026 through Oct 17, 2026"]]) {
      await page.eval(`document.getElementById("picker-input").select()`);
      await page.type(text);
      await page.key("Enter");
      assert.equal((await page.picker()).help, help, text);
    }
    // Typing alone never opens a day.
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type("2026-09-14");
    assert.equal((await page.picker()).open, true);
    assert.match((await page.picker()).help, /^AVAILABLE /, "a new edit clears the old reason");
    await page.key("Enter");
    shown = await page.picker();
    assert.equal(shown.open, false);
    assert.equal(shown.focus, "date-trigger");
    const now = await page.activity();
    assert.equal(now.day, "2026-09-14");
    assert.equal(now.mode, "day");
    assert.equal(now.monthId, "2026-09");
    assert.equal(now.label, "MON SEP 14");

    // Open, by the button, the first recorded day.
    await page.click("#date-trigger");
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type(FIRST);
    await page.click("#picker-open");
    assert.equal((await page.activity()).day, FIRST);
  } finally {
    await page.close();
  }
});

test("picker: grid keys and clicks open the same day, from the day view and the month view", options, async () => {
  const page = await openPage();
  try {
    // Keyboard: Down, Right, Enter.
    await page.eval(`openDay("2026-09-14")`);
    await page.click("#date-trigger");
    await page.key("ArrowDown");
    await page.key("ArrowRight");
    assert.equal((await page.picker()).focus, "2026-09-22");
    assert.equal((await page.activity()).day, "2026-09-14");
    await page.key("Enter");
    const keyed = await page.activity();
    assert.equal(keyed.day, "2026-09-22");
    assert.equal((await page.picker()).open, false);

    // Pointer: the same cell.
    await page.eval(`openDay("2026-09-14")`);
    await page.click("#date-trigger");
    await page.click('.picker-day[data-date="2026-09-22"]');
    assert.deepEqual(await page.activity(), keyed, "a click and Enter opened different states");

    // Space commits too, and the month buttons stop at the range.
    await page.click("#date-trigger");
    await page.key(" ");
    assert.equal((await page.activity()).day, "2026-09-22");

    // From the month view: the browsed month, on the same day number; the mode changes only on commit.
    // The keyboard commit left focus on the date box, where Enter would reopen the picker; let the page have it.
    await page.eval(`openDay("2026-10-12"), document.activeElement.blur()`);
    await page.key("Enter"); // the month view
    await page.key("ArrowLeft"); // browse to September
    const month = await page.activity();
    assert.equal(month.mode, "month");
    assert.equal(month.monthId, "2026-09");
    assert.equal(month.label, "SEPTEMBER");
    assert.equal(await page.eval(`document.getElementById("date-trigger").getAttribute("aria-label")`), "Choose activity date, September 2026");
    await page.click("#date-trigger");
    let shown = await page.picker();
    assert.equal(shown.month, "SEPTEMBER 2026");
    assert.equal(shown.focus, "2026-09-12");
    assert.equal(await page.eval(`document.querySelectorAll('.picker-day[aria-selected="true"]').length`), 0, "the month view has no selected day");
    await page.key("Escape");
    assert.deepEqual(await page.activity(), month, "cancel from the month view changed it");
    await page.click("#date-trigger");
    await page.click('.picker-day[data-date="2026-09-03"]');
    const opened = await page.activity();
    assert.equal(opened.mode, "day");
    assert.equal(opened.day, "2026-09-03");

    // The month buttons hide at the ends of the range; PageUp stops at the first day.
    await page.click("#date-trigger");
    for (let i = 0; i < 5; i++) await page.key("PageUp");
    shown = await page.picker();
    assert.equal(shown.month, "JULY 2026");
    assert.equal(shown.focus, FIRST);
    assert.equal(await page.eval(`getComputedStyle(document.getElementById("picker-previous")).visibility`), "hidden");
    assert.equal(await page.eval(`document.querySelector('.picker-day[data-date="2026-07-19"]').disabled`), true);
    await page.click("#picker-next");
    assert.equal((await page.picker()).month, "AUGUST 2026");
    await page.key("Escape");

    // The date box keeps its size and its label's place from Activity to the overview, for the same label.
    const box = () => page.eval(`(() => { const p = document.getElementById("month-pill").getBoundingClientRect(); const l = document.getElementById("month-label").getBoundingClientRect();
      return { width: p.width, left: p.left, label: l.left, text: document.getElementById("month-label").textContent }; })()`);
    await page.eval(`document.activeElement.blur()`);
    await page.key("Enter"); // the month view of September
    const activity = await box();
    await page.key("Escape");
    assert.equal(await page.eval(`state.page`), null);
    assert.deepEqual(await box(), activity);
  } finally {
    await page.close();
  }
});

test("picker: Tab stays inside it, the footer names its keys, and keys never reach the page behind", options, async () => {
  const page = await openPage();
  try {
    await page.eval(`openDay("2026-10-12")`);
    await page.click("#date-trigger");
    assert.match(await page.footer(), /←→day.*↑↓week.*↵open.*esccancel/);
    const seen = [];
    for (let i = 0; i < 9; i++) {
      await page.key("Tab");
      const shown = await page.picker();
      assert.equal(shown.inside, true, `Tab ${i + 1} left the picker for ${shown.focus}`);
      seen.push(shown.focus);
    }
    for (const id of ["picker-close", "picker-input", "picker-open", "picker-previous", "2026-10-12"]) assert.ok(seen.includes(id), `Tab never reached ${id}: ${seen.join(", ")}`);
    await page.key("Tab", { shift: true });
    assert.equal((await page.picker()).inside, true);

    // A digit on the calendar starts a typed date: focus moves to the field, which holds just that digit.
    await page.click("#picker-close");
    await page.click("#date-trigger");
    await page.key("2");
    let typed = await page.picker();
    assert.equal(typed.focus, "picker-input", "a digit on the calendar did not reach the field");
    assert.equal(typed.text, "2");
    await page.type("026-10-05");
    await page.key("Enter");
    assert.equal((await page.activity()).day, "2026-10-05");
    await page.click("#date-trigger");

    // In the field: the arrows, Home, letters and ? are text editing, not page keys.
    await page.click("#picker-input");
    assert.match(await page.footer(), /↵open.*esccancel/);
    const before = await page.activity();
    for (const key of ["ArrowLeft", "Home", "End", "w", "?", "Backspace"]) await page.key(key);
    assert.deepEqual(await page.activity(), before);
    assert.equal(await page.eval(`state.aboutOpen`), false);
    assert.equal(await page.eval(`document.getElementById("picker-input").value`), "2026-10-05w", "the field lost a key (End, w, ?, then Backspace)");
    await page.key("Escape");
    assert.equal((await page.picker()).open, false);
  } finally {
    await page.close();
  }
});

test("picker: About closes when it opens, and the next panel open closes it", options, async () => {
  const page = await openPage();
  try {
    await page.key("?");
    assert.equal(await page.eval(`state.aboutOpen`), true);
    await page.eval(`openPicker()`);
    assert.equal(await page.eval(`state.aboutOpen`), false, "two overlays at once");
    assert.equal((await page.picker()).open, true);
    await page.eval(`hyperdash.open({ now: ${JSON.stringify(NOW)} })`);
    const shown = await page.picker();
    assert.equal(shown.open, false);
    assert.equal(shown.inert, 0, "an invisible modal still holds the page");
  } finally {
    await page.close();
  }
});

test("picker: updates keep the draft; midnight widens the range; an archived day loads only after it opens", options, async () => {
  const page = await openPage();
  try {
    await page.eval(`openDay("2026-10-12")`);
    await page.click("#date-trigger");
    await page.click("#picker-input");
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type("2026-08-1");
    await page.eval(`document.getElementById("picker-input").setSelectionRange(5, 7)`);
    // Data and status updates while typing.
    await page.eval(`hyperdash.setHealth(${JSON.stringify({ log: { status: "ok", bytes: 1, modified: NOW }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" } })})`);
    await page.eval(`hyperdash.tick({ now: ${JSON.stringify(NOW)} })`);
    await page.eval(`render()`);
    const field = await page.eval(`(() => { const f = document.getElementById("picker-input"); return [f.value, f.selectionStart, f.selectionEnd, document.activeElement === f]; })()`);
    assert.deepEqual(field, ["2026-08-1", 5, 7, true], "an update reset the field");
    assert.equal((await page.picker()).open, true);

    // Midnight: tomorrow opens; the draft stays.
    await page.eval(`clockNow = new Date("2026-10-18T00:01:00").getTime(), hyperdash.tick({ now: "2026-10-18T00:01:00" })`);
    assert.equal(await page.eval(`document.querySelector('.picker-day[data-date="2026-10-18"]').disabled`), false);
    assert.equal((await page.picker()).text, "2026-08-1");

    // Browsing archived months asks nothing; opening A, then B before A's answer, keeps B.
    await page.key("Escape");
    await page.click("#date-trigger");
    for (let i = 0; i < 3; i++) await page.key("PageUp");
    assert.deepEqual(await page.requests(), [], "browsing read archived days");
    await page.key("Enter");
    assert.equal((await page.activity()).day, FIRST, "PageUp stopped at the first day");
    const a = (await page.requests()).at(-1);
    assert.equal(a.date, FIRST);
    await page.click("#date-trigger");
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type("2026-08-18");
    await page.key("Enter");
    const b = (await page.requests()).at(-1);
    assert.equal(b.date, "2026-08-18");
    assert.equal((await page.eval(`hyperdash.loadDay(${JSON.stringify(answer(a.id, a.date))})`)).reason, "stale");
    assert.equal((await page.activity()).day, "2026-08-18");
    assert.equal((await page.eval(`hyperdash.loadDay(${JSON.stringify(answer(b.id, b.date))})`)).ok, true);
    assert.equal((await page.activity()).day, "2026-08-18");
  } finally {
    await page.close();
  }
});

test("picker: a commit keeps the app filter visible and the way back to Insights", options, async () => {
  const page = await openPage();
  try {
    await page.eval(`openDay("2026-10-12")`);
    const app = await page.eval(`document.querySelector("#appbar .appchip")?.dataset.app`);
    assert.ok(app, "the fixture day has app chips");
    await page.click(`#appbar .appchip[data-app="${app}"]`);
    await page.eval(`insightsReturn = { evidence: "probe", monthId: state.monthId, list: 0, link: null, keyboard: false }`);
    await page.click("#date-trigger");
    await page.eval(`document.getElementById("picker-input").select()`);
    await page.type("2026-09-02");
    await page.key("Enter");
    assert.equal((await page.activity()).appFilter, app);
    assert.equal(await page.eval(`document.querySelector(\`#appbar .appchip[data-app="${app}"]\`)?.getAttribute("aria-pressed")`), "true", "the filter chip is gone");
    assert.equal(await page.eval(`insightsReturn?.evidence`), "probe");
  } finally {
    await page.close();
  }
});
