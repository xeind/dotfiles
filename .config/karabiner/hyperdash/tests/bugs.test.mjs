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

const GAMMA = "com.example.gamma";
const DELTA = "com.example.delta";
// The pressed app chip, if any: [app, count shown].
const pressedChip = (page) => page.eval(`(() => { const c = document.querySelector('.appchip[aria-pressed="true"]'); return c ? [c.dataset.app, c.querySelector("b").textContent] : null; })()`);

test("bug 2: the selected app stays visible and removable on days where it ranks fourth or is absent", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    const at = (day, clock) => `2026-10-${day}T${clock}`;
    await load(page, {
      now: "2026-10-17T12:00:00", bindings: BINDINGS, apps: { [ALPHA]: "Alpha", [BETA]: "Beta", [GAMMA]: "Gamma", [DELTA]: "Delta" },
      presses: [
        // Oct 15: only B. Oct 16: B 4, C 3, D 2, A 1 (fourth). Oct 17: only A.
        [at(15, "09:01:00"), "v", "j"], [at(15, "09:02:00"), "v", "j"],
        ...["09:01", "09:02", "09:03", "09:04"].map((t) => [at(16, `${t}:00`), "v", "j"]),
        ...["09:11", "09:12", "09:13"].map((t) => [at(16, `${t}:00`), "s", "d"]),
        ...["09:21", "09:22"].map((t) => [at(16, `${t}:00`), "w", "u"]),
        [at(16, "09:31:00"), "v", "j"],
        ...["09:01", "09:02", "09:03"].map((t) => [at(17, `${t}:00`), "v", "j"]),
      ],
      context: [
        "2026-10-15T08:00:00.100\tstart\t-", `${at(15, "09:00:00")}.250\tapp\t${BETA}`,
        `${at(16, "09:00:00")}.250\tapp\t${BETA}`, `${at(16, "09:10:00")}.250\tapp\t${GAMMA}`,
        `${at(16, "09:20:00")}.250\tapp\t${DELTA}`, `${at(16, "09:30:00")}.250\tapp\t${ALPHA}`,
        `${at(17, "09:00:00")}.250\tapp\t${ALPHA}`,
      ],
    });
    await page.press("a");
    const height = await page.height();
    await page.eval(`document.querySelector('.appchip[data-app="${ALPHA}"]').click()`);
    assert.deepEqual(await pressedChip(page), [ALPHA, "3"]);
    await page.press("ArrowLeft");
    assert.equal(await page.eval(`$("month-label").textContent`), "YESTERDAY");
    assert.deepEqual(await pressedChip(page), [ALPHA, "1"], "A ranks fourth on Oct 16 and its selected chip is gone");
    assert.equal(await page.eval(`document.querySelectorAll(".appchip").length`), 3);
    await page.press("ArrowLeft");
    assert.deepEqual(await pressedChip(page), [ALPHA, "0"], "A is absent on Oct 15 and its selected chip is gone");
    assert.equal(await page.height(), height);
    // The chip removes the filter: the day's presses come back.
    await page.eval(`document.querySelector('.appchip[aria-pressed="true"]').click()`);
    assert.equal(await pressedChip(page), null);
    assert.equal(await page.eval(`$("total").textContent`), "2");
    assert.equal(await page.height(), height);
  } finally {
    await page.close();
  }
});

// Five findings, each with one combo, long enough that the list scrolls.
const INSIGHTS = {
  version: 3, generated: "2026-10-17T06:00:00", month: "2026-10", recordingSince: "2026-10-01T08:00:00", rejectedLines: 0,
  insights: Array.from({ length: 5 }, (_, i) => ({
    kind: "peak", title: `Finding ${i + 1} with a title long enough to run on to a second line`,
    detail: "A detail line that explains the finding in more words than fit on one single line of the card",
    keys: [[BINDINGS[i % 3].layer, BINDINGS[i % 3].key]], value: i, dates: [], app: null,
  })),
};
// Appends one press line through the host protocol, as the log watcher does.
const appendPress = (page, stamp) => page.eval(`(() => {
  const line = ${JSON.stringify(`${stamp}\tv\tj\n`)};
  const result = hyperdash.append({ generation: 1, from: fixture.text.length, to: fixture.text.length + line.length, text: line });
  fixture.text += line;
  return result.ok;
})()`);
const focused = (page) => page.eval(`(() => { const n = document.activeElement; return n === document.body ? "body" : n.id || n.querySelector(".insight-title")?.textContent || n.className; })()`);

test("bug 3: an insight card keeps keyboard focus and scroll through a log append and a tick", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, insights: INSIGHTS, presses: [["2026-10-17T09:00:00", "v", "j"]] });
    await page.press("i");
    await page.tabTo(".insight:nth-child(2)");
    const card = await focused(page);
    assert.match(card, /^Finding 2 /);
    const scroll = await page.eval(`$("insights").scrollTop = 40, $("insights").scrollTop`);
    assert.ok(scroll > 0, "the insight list does not scroll");
    assert.equal(await appendPress(page, "2026-10-17T11:59:00"), true);
    assert.equal(await focused(page), card, "the append dropped focus from the card");
    assert.equal(await page.eval(`$("insights").scrollTop`), scroll, "the append reset the insight list's scroll");
    await page.eval(`hyperdash.tick({})`);
    assert.equal(await focused(page), card, "the tick dropped focus from the card");
    // Enter opens the card's evidence; its shortcut button opens the combo: S D, in the System layer.
    await page.press("Enter");
    assert.equal(await page.eval(`document.querySelector(".evidence-title")?.textContent`), card);
    await page.tabTo('.evidence-link[data-evidence="key s d"]');
    await page.press("Enter");
    assert.equal(await page.eval(`$("title").textContent`), "System");
  } finally {
    await page.close();
  }
});

test("insight evidence: Back from a shortcut or a day it opened returns to Insights, the same card and the month in view", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  // The report month is October; the overview is showing September when Insights opens.
  const insights = { ...INSIGHTS, insights: INSIGHTS.insights.map((item) => ({ ...item, dates: ["2026-10-05"] })) };
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, insights, presses: [["2026-09-10T09:00:00", "v", "j"], ["2026-10-17T09:00:00", "v", "j"]] });
    await page.press("ArrowLeft");
    assert.equal(await page.eval(`state.monthId`), "2026-09");
    await page.press("i");
    // Keyboard: card, evidence, shortcut, then Escape until Insights shows again.
    await page.tabTo(".insight:nth-child(3)");
    const card = await focused(page);
    await page.press("Enter");
    await page.tabTo(".evidence-link[data-evidence^='key ']");
    await page.press("Enter");
    assert.equal(await page.eval(`state.layer !== null && state.monthId`), "2026-10", "the shortcut did not open in the report month");
    for (let i = 0; i < 3 && (await page.eval(`state.page`)) !== "insights"; i++) await page.press("Escape");
    assert.equal(await page.eval(`state.page`), "insights", "Back left Insights for the overview");
    assert.equal(await page.eval(`document.activeElement.dataset.evidence`), (await page.eval(`document.querySelector(".evidence-link[data-evidence^='key ']").dataset.evidence`)), "focus did not return to the shortcut button");
    await page.press("Escape");
    assert.equal(await focused(page), card, "focus did not return to the card");
    assert.equal(await page.eval(`state.monthId`), "2026-09", "the month in view changed");
    // Pointer: card, then a supporting day in Activity, then the header Back button.
    await page.eval(`document.querySelector(".insight:nth-child(2)").click()`);
    await page.eval(`document.querySelector(".evidence-link[data-evidence^='day ']").click()`);
    assert.equal(await page.eval(`state.page`), "activity");
    await page.eval(`$("header-icon").click()`);
    assert.equal(await page.eval(`state.page`), "insights", "the Back button left Insights for the overview");
    assert.equal(await page.eval(`document.querySelector(".evidence-title")?.textContent`), INSIGHTS.insights[1].title, "Back did not return to the finding");
    await page.eval(`document.querySelector(".evidence-back").click()`);
    assert.equal(await page.eval(`document.querySelectorAll(".insight").length`), 5);
    assert.equal(await page.eval(`state.monthId`), "2026-09", "the month in view changed");
    // Leaving Insights itself still goes to the overview.
    await page.eval(`$("header-icon").click()`);
    assert.equal(await page.eval(`state.page`), null);
  } finally {
    await page.close();
  }
});

test("insight evidence: Escape returns to the same card and scroll; a live update keeps it open; a refresh that drops it shows the list", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, insights: INSIGHTS, presses: [["2026-10-17T09:00:00", "v", "j"]] });
    await page.press("i");
    await page.tabTo(".insight:nth-child(4)");
    const card = await focused(page);
    const scroll = await page.eval(`$("insights").scrollTop`);
    const height = await page.height();
    await page.press("Enter");
    assert.equal(await page.eval(`document.activeElement.className`), "evidence-back", "focus did not move into the evidence");
    assert.equal(await page.height(), height, "the evidence changed the page height");
    assert.equal(await appendPress(page, "2026-10-17T11:59:00"), true);
    assert.equal(await page.eval(`document.querySelector(".evidence-title")?.textContent`), card, "the append closed the evidence");
    assert.equal(await page.eval(`document.activeElement.className`), "evidence-back", "the append dropped focus");
    await page.press("Escape");
    assert.equal(await page.eval(`$("title").textContent`), "Insights", "Escape left the page instead of the evidence");
    assert.equal(await focused(page), card, "focus did not return to the card");
    assert.equal(await page.eval(`$("insights").scrollTop`), scroll, "the list did not return to its scroll");
    // A refresh without the open finding brings the list back.
    await page.press("Enter");
    await page.eval(`hyperdash.setInsights({ ...${JSON.stringify(INSIGHTS)}, insights: ${JSON.stringify(INSIGHTS.insights.slice(0, 2))} }, fixture.health)`);
    assert.equal(await page.eval(`document.querySelectorAll(".evidence").length`), 0);
    assert.equal(await page.eval(`document.querySelectorAll(".insight").length`), 2);
  } finally {
    await page.close();
  }
});

test("bug 3: the About theme button keeps keyboard focus through a health update and a log append", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, insights: INSIGHTS, presses: [["2026-10-17T09:00:00", "v", "j"]] });
    await page.eval(`$("about-toggle").click()`);
    await page.tabTo("#theme-button");
    await page.eval(`hyperdash.setHealth({ ...fixture.health, insights: { status: "stale", message: null } })`);
    assert.equal(await focused(page), "theme-button", "the health update dropped focus from the theme button");
    assert.equal(await appendPress(page, "2026-10-17T11:59:00"), true);
    assert.equal(await focused(page), "theme-button", "the append dropped focus from the theme button");
    // Enter routing reads :focus-visible, so the restored button must still match it.
    assert.equal(await page.eval(`document.activeElement.matches(":focus-visible")`), true);
    await page.press("Enter");
    assert.equal(await page.eval(`document.documentElement.dataset.theme`), "kozo");
  } finally {
    await page.close();
  }
});

// V J then S D, 5 s apart, four times: one sequence with four timestamps.
const SEQUENCE = ["10:00", "10:10", "10:20", "10:30"].flatMap((clock) => [[`2026-10-17T${clock}:00`, "v", "j"], [`2026-10-17T${clock}:05`, "s", "d"]]);

test("bug 4: the arrows reach every visible timestamp of a sequence", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, presses: SEQUENCE });
    await page.press("a");
    const chips = await page.eval(`[...document.querySelectorAll(".seq .time-chip")].map((chip) => chip.textContent)`);
    assert.deepEqual(chips, ["10:00:00", "10:10:00", "10:20:00", "10:30:00"]);
    await page.tabTo(".time-chip");
    const visited = [await page.eval("document.activeElement.textContent")];
    for (let i = 1; i < chips.length; i++) {
      await page.press("ArrowRight");
      visited.push(await page.eval(`document.activeElement.matches(".time-chip") ? document.activeElement.textContent : document.activeElement.className || "body"`));
    }
    assert.deepEqual(visited, chips, "the later timestamps cannot be reached from the keyboard");
    assert.equal(await page.eval(`$("month-label").textContent`), "TODAY", "the arrows changed the day");
    await page.press("ArrowLeft");
    assert.equal(await page.eval("document.activeElement.textContent"), "10:20:00");
    // One Tab stop per sequence: Tab leaves the sequence from any of its timestamps.
    await page.press("Tab");
    assert.equal(await page.eval(`document.activeElement.matches(".time-chip")`), false);
  } finally {
    await page.close();
  }
});

test("bug 4: Enter on a later timestamp opens its interval and hands focus to that bin", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, presses: SEQUENCE });
    await page.press("a");
    await page.tabTo(".time-chip");
    await page.press("ArrowRight");
    await page.press("Enter");
    assert.equal(await page.eval(`document.querySelector(".panel-head span").textContent`), "10:00–10:30 · 6 commands", "Enter did not open the timestamp's interval");
    // The timestamps give way to the commands: focus moves to the selected bin, so the next Enter clears it.
    assert.equal(await page.eval(`document.activeElement.matches(".bin.selected")`), true, "focus fell to the body");
    await page.press("Enter");
    assert.equal(await page.eval(`document.querySelector(".panel-head span").textContent`), "Observed sequences");
    assert.equal(await page.eval(`$("month-label").textContent`), "TODAY");
  } finally {
    await page.close();
  }
});

// Activity on `now`, Enter for the month, `back` months back with ←, Enter for the day: the pill's label.
async function monthThenDay(page, now, presses, back) {
  await load(page, { now, bindings: BINDINGS, presses: presses.map((stamp) => [stamp, "v", "j"]) });
  await page.press("a");
  await page.press("Enter");
  for (let i = 0; i < back; i++) await page.press("ArrowLeft");
  const month = await page.eval(`$("month-label").textContent`);
  await page.press("Enter");
  return [month, await page.eval(`$("month-label").textContent`)];
}

test("bug 5: Enter from a browsed month opens the same day of that month, within the month and the record", options, async () => {
  const cases = [
    // [now, presses, months back, month shown, day shown]
    ["2026-10-17T12:00:00", ["2026-09-03T09:00:00", "2026-09-17T09:00:00", "2026-10-17T09:00:00"], 1, "SEPTEMBER", "THU SEP 17"],
    // October 31 has no September twin: the month's last day.
    ["2026-10-31T12:00:00", ["2026-09-03T09:00:00", "2026-10-31T09:00:00"], 1, "SEPTEMBER", "WED SEP 30"],
    // Before the first recorded day: the first recorded day.
    ["2026-10-17T12:00:00", ["2026-09-20T09:00:00", "2026-10-17T09:00:00"], 1, "SEPTEMBER", "SUN SEP 20"],
    // Not browsed: back to the same day.
    ["2026-10-17T12:00:00", ["2026-09-03T09:00:00", "2026-10-17T09:00:00"], 0, "OCTOBER", "TODAY"],
  ];
  for (const [now, presses, back, month, day] of cases) {
    const page = await open(now);
    try {
      assert.deepEqual(await monthThenDay(page, now, presses, back), [month, day], `from ${now.slice(0, 10)}, ${back} month(s) back`);
    } finally {
      await page.close();
    }
  }
});

test("review A: a context reset with the same number of events does not reuse the old recording spans", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    const spans = await page.eval(`(() => {
      const store = HyperdashModel.createContextStore();
      store.reset("2026-10-17T09:00:00.000\\tstart\\t-\\n");
      const first = store.sessions("2026-10-17T12:00:00");
      store.reset("2026-10-17T11:00:00.000\\tstart\\t-\\n");
      const second = store.sessions("2026-10-17T12:00:00");
      const fresh = HyperdashModel.createContextStore();
      fresh.reset("2026-10-17T11:00:00.000\\tstart\\t-\\n");
      const clock = (s) => new Date(s * 1000).toISOString().slice(11, 16);
      return [first, second, fresh.sessions("2026-10-17T12:00:00")].map((list) => list.map((s) => clock(s.start) + "-" + clock(s.end)));
    })()`);
    assert.deepEqual(spans[0], ["09:00-12:00"]);
    assert.deepEqual(spans[1], spans[2], "the reset store kept the old 09:00 session");
    assert.deepEqual(spans[1], ["11:00-12:00"]);
  } finally {
    await page.close();
  }
});

test("review B: commands show the new app after the context log changes their attribution", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  const contextWith = (app) => ["2026-10-17T08:00:00.100\tstart\t-", `2026-10-17T08:59:00.250\tapp\t${app}`].join("\n") + "\n";
  try {
    await load(page, {
      now: "2026-10-17T12:00:00", bindings: BINDINGS, apps: { [ALPHA]: "Alpha", [BETA]: "Beta" },
      presses: [["2026-10-17T09:00:00", "v", "j"], ["2026-10-17T09:10:00", "s", "d"]],
      context: contextWith(ALPHA).trim().split("\n"),
    });
    await page.press("a");
    const height = await page.height();
    await page.eval(`document.querySelector('.bin[data-bin="18"]').dispatchEvent(new MouseEvent("click", { bubbles: true }))`);
    const apps = () => page.eval(`[...document.querySelectorAll(".cmd .cmd-app")].map((n) => n.textContent)`);
    assert.deepEqual(await apps(), ["Alpha", "Alpha"]);
    // The same number of context events, now naming Beta: the attribution changes, the usage events do not.
    await page.eval(`hyperdash.reset({ now: "2026-10-17T12:00:00", stream: "context", generation: 2, text: ${JSON.stringify(contextWith(BETA))}, offset: 0 })`);
    assert.deepEqual(await apps(), ["Beta", "Beta"], "the commands kept the old app names");
    assert.equal(await page.height(), height);
  } finally {
    await page.close();
  }
});

test("review D: the group caption returns to the summary after hover ends, and never keeps old counts", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, {
      now: "2026-10-17T12:00:00", bindings: BINDINGS,
      presses: [["2026-10-17T09:00:00", "v", "j"], ["2026-10-17T09:10:00", "s", "d"], ["2026-10-17T09:20:00", "v", "j"]],
    });
    const caption = () => page.eval(`$("groupcap").textContent`);
    const summary = await caption();
    assert.match(summary, /^BY GROUP/);
    const hover = (group) => page.eval(`document.querySelector('#groupbar button[data-group="${group}"]').dispatchEvent(new MouseEvent("mouseover", { bubbles: true }))`);
    const leave = (group) => page.eval(`document.querySelector('#groupbar button[data-group="${group}"]').dispatchEvent(new MouseEvent("mouseout", { bubbles: true, relatedTarget: document.body }))`);
    // Hover names the segment; leaving the bar restores the summary.
    await hover("navigate");
    assert.equal(await caption(), "NAVIGATE · 2 · 67%");
    await leave("navigate");
    assert.equal(await caption(), summary, "the caption stayed on the segment after the pointer left");
    // A hovered segment's caption follows new counts.
    await hover("navigate");
    await page.eval(`(() => {
      const line = "2026-10-17T09:30:00\\tv\\tj\\n";
      hyperdash.append({ now: "2026-10-17T12:00:00", generation: 1, from: fixture.text.length, to: fixture.text.length + line.length, text: line });
    })()`);
    assert.equal(await caption(), "NAVIGATE · 3 · 75%", "the caption kept the old count");
    // Reopening starts from the summary, not from a stale hover.
    await page.eval(`hyperdash.open({ now: "2026-10-17T12:00:00" })`);
    assert.match(await caption(), /^BY GROUP/, "the hover caption survived a reopen");
  } finally {
    await page.close();
  }
});

test("review 4: a group filter with no presses in the new month stays visible and Escape clears it", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    // October has navigation and system presses; September has system presses only.
    await load(page, {
      now: "2026-10-17T12:00:00", bindings: BINDINGS,
      presses: [["2026-09-10T09:00:00", "s", "d"], ["2026-10-10T09:00:00", "v", "j"], ["2026-10-10T09:10:00", "s", "d"]],
    });
    const caption = () => page.eval(`$("groupcap").textContent`);
    const height = await page.height();
    await page.eval(`document.querySelector('#groupbar button[data-group="navigate"]').click()`);
    assert.match(await caption(), /^NAVIGATE ONLY/);
    await page.press("ArrowLeft");
    assert.equal(await page.eval(`$("month-label").textContent`), "SEPTEMBER");
    assert.match(await caption(), /NONE THIS MONTH/, "the caption hides that the filter has nothing in this month");
    assert.match(await caption(), /ESC TO CLEAR/, "the caption names a way to clear the filter");
    await page.press("Escape");
    assert.match(await caption(), /^BY GROUP/, "Escape did not clear the group filter");
    assert.equal(await page.eval(`$("title").textContent`), "hyperdash", "Escape left the overview");
    assert.equal(await page.height(), height);
  } finally {
    await page.close();
  }
});

test("review 5: a focused timestamp keeps focus through a live update", options, async () => {
  const page = await open("2026-10-17T12:00:00");
  try {
    await load(page, { now: "2026-10-17T12:00:00", bindings: BINDINGS, presses: SEQUENCE });
    await page.press("a");
    await page.tabTo(".time-chip");
    await page.press("ArrowRight");
    assert.equal(await page.eval("document.activeElement.textContent"), "10:10:00");
    // A usage append that changes the day's events rebuilds the panel.
    await page.eval(`(() => {
      const line = "2026-10-17T11:50:00\\tv\\tj\\n";
      hyperdash.append({ now: "2026-10-17T12:00:00", generation: 1, from: fixture.text.length, to: fixture.text.length + line.length, text: line });
    })()`);
    assert.equal(await page.eval(`document.activeElement.matches(".time-chip") ? document.activeElement.textContent : document.activeElement.tagName`), "10:10:00", "the update dropped focus from the timestamp");
  } finally {
    await page.close();
  }
});

test("review data: a logged combo with no binding and no presses this month shows its history, not 'Nothing yet'", options, async () => {
  const now = "2026-10-15T15:00:00";
  const unbound = { kind: "unbound", title: "1 logged combo no longer bound", detail: "1 press logged with no current binding", keys: [["z", "z"]], value: 1, dates: ["2026-08-01"], app: null };
  const page = await open(now);
  try {
    await load(page, {
      now, bindings: BINDINGS, insights: { version: 3, generated: now, month: "2026-10", recordingSince: "2026-08-01T00:00:00", rejectedLines: 0, insights: [unbound] },
      presses: [["2026-08-01T00:00:00", "z", "z"], ["2026-10-15T09:00:00", "w", "u"]],
    });
    await page.press("i");
    await page.tabTo(".insight");
    // The card opens its evidence; the shortcut button there opens the combo.
    await page.press("Enter");
    await page.tabTo('.evidence-link[data-evidence="key z z"]');
    await page.press("Enter");
    const detail = await page.eval(`$("detail").textContent`);
    assert.doesNotMatch(detail, /Nothing on/, "the card says the combo was logged; its page says it never was");
    assert.match(detail, /no longer bound/);
    assert.match(detail, /Not used in October · last 75d ago/);
  } finally {
    await page.close();
  }
});
