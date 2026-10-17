// Run with: node --test karabiner/hyperdash/tests/bugs.test.mjs
// Drives the real page in headless Chrome over the DevTools protocol, with real key presses, for bugs
// found in review. The clock is frozen per page. Skips when Chrome is not installed; set
// HYPERDASH_TEST_CHROME to a Chrome binary to use another one.
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
  dir = mkdtempSync(join(tmpdir(), "hyperdash-bugs-"));
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

const KEYS = {
  Tab: [9, "Tab"], Enter: [13, "Enter", "\r"], Escape: [27, "Escape"],
  ArrowLeft: [37, "ArrowLeft"], ArrowRight: [39, "ArrowRight"],
};

// A fresh tab on the page with the clock frozen at `now`, so key handlers and protocol calls agree on today.
async function open(now) {
  const clock = `<script>(() => { const fixed = new Date(${JSON.stringify(now)}).getTime(); const Real = Date;
    globalThis.Date = class extends Real { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }; })();</script>`;
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
    async press(key) {
      const [code, name, text] = KEYS[key] || [key.toUpperCase().charCodeAt(0), `Key${key.toUpperCase()}`, key];
      await call("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", key, code: name, windowsVirtualKeyCode: code, text });
      await call("Input.dispatchKeyEvent", { type: "keyUp", key, code: name, windowsVirtualKeyCode: code });
    },
    // Tab until `selector` matches the focused element; returns how many presses it took.
    async tabTo(selector, limit = 80) {
      for (let n = 1; n <= limit; n++) {
        await page.press("Tab");
        if (await page.eval(`Boolean(document.activeElement?.matches(${JSON.stringify(selector)}))`)) return n;
      }
      throw new Error(`Tab never reached ${selector}`);
    },
    height: () => page.eval("document.body.scrollHeight"),
    close: () => send("Target.closeTarget", { targetId }),
  };
  for (let i = 0; i < 100 && !(await page.eval("document.readyState === 'complete' && typeof hyperdash === 'object'").catch(() => false)); i++) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return page;
}

// Loads presses (`[stamp, layer, key]`), app context lines and insights, then opens the panel.
function load(page, { now, bindings, presses, context = [], insights = null, apps = {} }) {
  const text = presses.map((p) => p.join("\t")).join("\n") + "\n";
  const health = { log: { status: "ok", bytes: text.length, modified: now }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: context.length ? "ok" : "disabled" } };
  return page.eval(`(() => {
    const health = ${JSON.stringify(health)};
    window.fixture = { text: ${JSON.stringify(text)}, health };
    hyperdash.reset({ now: ${JSON.stringify(now)}, generation: 1, bindings: ${JSON.stringify(bindings)}, text: fixture.text, offset: fixture.text.length, insights: ${JSON.stringify(insights)}, health });
    ${context.length ? `hyperdash.reset({ now: ${JSON.stringify(now)}, stream: "context", generation: 1, text: ${JSON.stringify(context.join("\n") + "\n")}, offset: 0 });` : ""}
    hyperdash.setApps(${JSON.stringify(apps)});
    hyperdash.open({ now: ${JSON.stringify(now)} });
  })()`);
}

const binding = (layer, key, label, category) => ({ layer, key, label, category });
const BINDINGS = [binding("v", "j", "Down arrow", "text-navigation"), binding("s", "d", "Toggle Do Not Disturb", "system"), binding("w", "u", "Previous Tab", "tab-navigation")];
const ALPHA = "com.example.alpha";
const BETA = "com.example.beta";

// The legend as { GROUP: count } and the readout's second line for one bin, in legend order.
const chartState = (page, bin) => page.eval(`(() => {
  const legend = {};
  for (const cell of document.querySelectorAll(".chart-legend > span")) {
    const [label, count] = cell.textContent.split(" ");
    legend[label] = Number(count);
  }
  document.querySelector('.bin[data-bin="${bin}"]').focus();
  const readout = [...document.querySelector(".bin-readout .r2").children].map((cell) => cell.textContent);
  document.activeElement.blur();
  return { legend, readout };
})()`);

test("bug 1: the chart follows the app filter when both apps have the same half-hour totals", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    // One navigation press in A at 09:00 and one system press in B at 09:10: both fall in bin 18.
    await load(page, {
      now: "2026-10-17T12:00:00", bindings: BINDINGS, apps: { [ALPHA]: "Alpha", [BETA]: "Beta" },
      presses: [["2026-10-17T09:00:00", "v", "j"], ["2026-10-17T09:10:00", "s", "d"]],
      context: ["2026-10-17T08:00:00.100\tstart\t-", `2026-10-17T08:59:00.250\tapp\t${ALPHA}`, `2026-10-17T09:05:00.250\tapp\t${BETA}`],
    });
    await page.press("a");
    const height = await page.height();
    await page.eval(`document.querySelector('.appchip[data-app="${ALPHA}"]').click()`);
    const alpha = await chartState(page, 18);
    assert.equal(alpha.legend.NAVIGATE, 1);
    assert.equal(alpha.legend.SYSTEM, 0);
    await page.eval(`document.querySelector('.appchip[data-app="${BETA}"]').click()`);
    assert.equal(await page.eval(`document.querySelector('.appchip[aria-pressed="true"]').dataset.app`), BETA);
    const beta = await chartState(page, 18);
    // Legend order is windows, launch, system, navigate, capture, pointer.
    assert.deepEqual(beta, {
      legend: { WINDOWS: 0, LAUNCH: 0, SYSTEM: 1, NAVIGATE: 0, CAPTURE: 0, POINTER: 0 },
      readout: ["–", "–", "1", "–", "–", "–"],
    }, "B is selected but the chart still shows A's groups");
    assert.equal(await page.eval(`document.querySelectorAll(".dots.g-system").length && document.querySelector(".dots.g-system").getAttribute("d") !== ""`), true, "B's dot is not drawn in the system colour");
    assert.equal(await page.height(), height);
  } finally {
    await page.close();
  }
});

test("bug 1: the chart follows a category change that keeps every total", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, presses: [["2026-10-17T09:00:00", "v", "j"], ["2026-10-17T09:10:00", "s", "d"]] });
    await page.press("a");
    assert.deepEqual((await chartState(page, 18)).legend, { WINDOWS: 0, LAUNCH: 0, SYSTEM: 1, NAVIGATE: 1, CAPTURE: 0, POINTER: 0 });
    // V J becomes a pointer command: the same presses at the same times, in another group.
    await page.eval(`hyperdash.setBindings(${JSON.stringify([binding("v", "j", "Left click", "pointer"), ...BINDINGS.slice(1)])}, fixture.health)`);
    assert.deepEqual(await chartState(page, 18), {
      legend: { WINDOWS: 0, LAUNCH: 0, SYSTEM: 1, NAVIGATE: 0, CAPTURE: 0, POINTER: 1 },
      readout: ["–", "–", "1", "–", "–", "1"],
    }, "the chart still shows the old category");
  } finally {
    await page.close();
  }
});
