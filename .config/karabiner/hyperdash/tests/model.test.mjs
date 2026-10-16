// Run with: node --test karabiner/hyperdash/tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createReference } from "./reference_model.mjs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const block = /<script id="hyperdash-model">([\s\S]*?)<\/script>/.exec(html);
assert.ok(block, "index.html has no #hyperdash-model script");
const context = vm.createContext({});
vm.runInContext(block[1], context);
const M = context.HyperdashModel;
const R = createReference(M); // plain full-history reference the store is compared with

// Values built inside the vm have another realm's prototypes; compare them as plain JSON.
const plain = (value) => JSON.parse(JSON.stringify(value));

const NOW = "2026-10-15T15:00:00";
const line = (time, layer, key) => `${time}\t${layer}\t${key}`;

test("parseLog: shared fixture lines match the Swift ParsingTests", () => {
  // Same lines as InsightsTests.swift skipsMalformedLines.
  const result = R.parseLog([
    line("2026-10-15T14:36:07", "w", "u"),
    "garbage",
    line("2026-13-15T14:36:07", "w", "u"),
    line("2026-02-31T14:36:07", "w", "u"),
    "2026-10-15T14:36:07\tw",
    "2026-10-15T14:36:07\tw\t",
    line("2026-10-15T14:36:08", "o", "t"),
  ].join("\n"), NOW);
  assert.equal(result.presses.length, 2);
  assert.equal(result.rejected, 5);
  assert.deepEqual(plain(result.presses.map((p) => [p.layer, p.key])), [["w", "u"], ["o", "t"]]);
});

test("parseLog: shared rejected-line fixtures match the Swift countsRejectedLines test", () => {
  const result = R.parseLog([
    line("2026-10-15T14:36:07", "w", "u"),
    "",
    "garbage",
    line("2026-13-15T14:36:07", "w", "u"),
    line("2026-02-31T14:36:07", "w", "u"),
    line("2026-10-15T24:00:00", "w", "u"),
    line("2026-10-15 14:36:07", "w", "u"),
    line("2026-10-15T14:36", "w", "u"),
    line("2026-10-15T14:36:07", "W", "u"),
    line("2026-10-15T14:36:07", "w", "u v"),
    line("2026-10-15T14:36:07", "w", ";"),
    line("2026-10-15T14:36:07", "", "u"),
    "2026-10-15T14:36:07\tw\tu\textra",
    "2026-10-15T14:36:07\tw",
    line("0099-10-15T14:36:07", "w", "u"),
    line("2026-10-15T14:36:07", "o", "spacebar"),
    line("2026-10-15T14:36:07", "o", "keypad_1"),
  ].join("\n"), NOW);
  assert.equal(result.presses.length, 3);
  assert.equal(result.rejected, 13);
});

test("parseLog: field rules from the contract", () => {
  const bad = [
    "2026-10-15T14:36:07\tw\tu\textra",
    line("2026-10-15T14:36:07", "W", "u"),
    line("2026-10-15T14:36:07", "w", "up arrow"),
    line("2026-10-15T14:36:07", "w-x", "u"),
    line("2026-10-15T14:36:07", "", "u"),
    line("2026-10-15 14:36:07", "w", "u"),
    line("2026-10-15T14:36:07Z", "w", "u"),
    line(" 2026-10-15T14:36:07", "w", "u"),
    line("2026-10-15T24:00:00", "w", "u"),
    line("2026-10-15T14:60:00", "w", "u"),
    line("2026-00-15T14:00:00", "w", "u"),
    line("2026-04-31T14:00:00", "w", "u"),
    line("2025-02-29T14:00:00", "w", "u"),
    line("1969-12-31T14:00:00", "w", "u"),
    line("２０２６-10-15T14:36:07", "w", "u"),
  ];
  const result = R.parseLog(bad.join("\n"), NOW);
  assert.equal(result.presses.length, 0);
  assert.equal(result.rejected, bad.length);

  const good = R.parseLog([
    line("2024-02-29T12:00:00", "w", "up_arrow"),
    line("2026-10-15T14:36:07", "o", "1"),
  ].join("\n"), NOW);
  assert.equal(good.presses.length, 2);
  assert.equal(good.rejected, 0);
});

test("parseLog: blank lines are skipped, CRLF is accepted", () => {
  const text = `${line("2026-10-15T09:00:00", "w", "u")}\r\n\r\n\n${line("2026-10-15T09:01:00", "w", "u")}\r\n`;
  const result = R.parseLog(text, NOW);
  assert.equal(result.presses.length, 2);
  assert.equal(result.rejected, 0);
});

test("parseLog: events after now are ignored, not rejected", () => {
  const result = R.parseLog([
    line("2026-10-15T14:59:59", "w", "u"),
    line("2026-10-15T15:00:00", "w", "u"),
    line("2026-10-15T15:00:01", "w", "u"),
    line("2027-01-01T00:00:00", "w", "u"),
  ].join("\n"), NOW);
  assert.equal(result.presses.length, 2);
  assert.equal(result.future, 2);
  assert.equal(result.rejected, 0);
  assert.equal(result.lastEvent, "2026-10-15T15:00:00");
});

test("parseLog: last used is the maximum timestamp, not the last line", () => {
  const result = R.parseLog([
    line("2026-10-15T12:00:00", "w", "u"),
    line("2026-10-10T08:00:00", "w", "u"),
    line("2026-10-15T09:00:00", "o", "t"),
  ].join("\n"), NOW);
  assert.equal(result.lastUsed["w u"], "2026-10-15T12:00:00");
  assert.equal(result.firstEvent, "2026-10-10T08:00:00");
  assert.equal(result.lastEvent, "2026-10-15T12:00:00");
});

test("parseLog: half-hour bins and months", () => {
  const result = R.parseLog([line("2026-10-15T14:29:59", "w", "u"), line("2026-10-15T14:30:00", "w", "u")].join("\n"), NOW);
  assert.deepEqual(plain(result.presses.map((p) => p.bin)), [28, 29]);
  assert.equal(result.presses[0].month, "2026-10");
});

test("validatePayload: shapes", () => {
  assert.equal(M.validatePayload(null).ok, false);
  assert.equal(M.validatePayload({ bindings: "x", log: "" }).ok, false);
  assert.equal(M.validatePayload({ bindings: [], log: 5 }).ok, false);
  const ok = M.validatePayload({ bindings: [{ layer: "w", key: "u", label: "Tab" }, { layer: 3 }, null], log: "" });
  assert.equal(ok.ok, true);
  assert.equal(ok.bindings.length, 1);
  assert.equal(ok.insights, null);
  assert.equal(ok.health, null);
});

test("normalizeInsights: only version 2 is accepted", () => {
  const item = { kind: "rising", title: "t", detail: "d", keys: [["w", "u"], ["bad"]], value: 1 };
  assert.equal(M.normalizeInsights({ version: 1, insights: [item] }), null);
  assert.equal(M.normalizeInsights({ version: 3, insights: [item] }), null);
  assert.equal(M.normalizeInsights({ version: 2 }), null);
  const parsed = plain(M.normalizeInsights({
    version: 2, generated: NOW, month: "2026-10", recordingSince: "2026-10-14T13:06:00", rejectedLines: 2,
    insights: [item, { title: 1 }, ...Array(6).fill(item)],
  }));
  assert.equal(parsed.month, "2026-10");
  assert.equal(parsed.recordingSince, "2026-10-14T13:06:00");
  assert.equal(parsed.insights.length, 5);
  assert.deepEqual(parsed.insights[0].keys, [["w", "u"]]);
  assert.equal(M.normalizeInsights({ version: 2, generated: "junk", insights: [] }).generated, null);
});

test("normalizeHealth: unknown statuses are dropped", () => {
  assert.equal(M.normalizeHealth("x"), null);
  const health = plain(M.normalizeHealth({ log: { status: "ok", bytes: 10, modified: NOW }, insights: { status: "weird" } }));
  assert.deepEqual(health, { log: { status: "ok", bytes: 10, modified: NOW }, bindings: null, insights: null });
  assert.deepEqual(plain(M.normalizeHealth({ bindings: { status: "invalid" } })).bindings, { status: "invalid" });
});

test("describeHealth: inactivity is neutral; only the host can say the log failed", () => {
  const quiet = M.describeHealth({ health: null, lastEvent: "2026-10-15T14:02:00", rejected: 0, now: NOW });
  assert.equal(quiet.text, "LAST PRESS 14:02");
  assert.equal(quiet.level, "ok");
  const older = M.describeHealth({ health: null, lastEvent: "2026-10-12T14:02:00", rejected: 0, now: NOW });
  assert.equal(older.text, "LAST PRESS OCT 12 14:02");
  assert.equal(M.describeHealth({ health: null, lastEvent: null, rejected: 0, now: NOW }).text, "NO PRESSES RECORDED");

  const health = { log: { status: "ok" }, insights: { status: "ok" } };
  assert.equal(M.describeHealth({ health, lastEvent: "2026-10-15T14:02:00", rejected: 1, now: NOW }).text,
    "LOG OK · LAST PRESS 14:02 · 1 BAD LINE · ANALYSIS OK");
  assert.equal(M.describeHealth({ health, lastEvent: null, rejected: 3, now: NOW }).level, "warn");

  const missing = M.describeHealth({ health: { log: { status: "missing" }, insights: null }, lastEvent: null, rejected: 0, now: NOW });
  assert.equal(missing.text, "LOG MISSING");
  assert.equal(missing.level, "error");
  const failed = M.describeHealth({ health: { log: { status: "ok" }, insights: { status: "failed" } }, lastEvent: null, rejected: 0, now: NOW });
  assert.equal(failed.level, "error");
  assert.match(failed.text, /ANALYSIS FAILED/);
});

test("compareMonths: the percentage needs two complete months", () => {
  const base = { total: 150, previousTotal: 100, now: NOW };
  // Current month is incomplete.
  assert.equal(M.compareMonths({ ...base, month: "2026-10", firstEvent: "2026-08-01T00:00:00" }).comparable, false);
  // Previous month began before recording did.
  assert.equal(M.compareMonths({ ...base, month: "2026-09", firstEvent: "2026-08-20T09:00:00" }).comparable, false);
  // No recorded events at all.
  assert.equal(M.compareMonths({ ...base, month: "2026-09", firstEvent: null }).comparable, false);
  // Nothing to compare against.
  assert.equal(M.compareMonths({ ...base, previousTotal: 0, month: "2026-09", firstEvent: "2026-08-01T00:00:00" }).comparable, false);
  // Both complete.
  const result = M.compareMonths({ ...base, month: "2026-09", firstEvent: "2026-08-01T00:00:00" });
  assert.equal(result.comparable, true);
  assert.equal(result.percent, 50);
});

test("previousMonth and listMonths", () => {
  assert.equal(M.previousMonth("2026-01"), "2025-12");
  assert.equal(M.previousMonth("2026-10"), "2026-09");
  const presses = [{ month: "2025-11" }, { month: "2026-01" }];
  assert.deepEqual(plain(R.listMonths(presses, NOW)).slice(0, 3), ["2025-11", "2025-12", "2026-01"]);
  assert.equal(R.listMonths(presses, NOW).at(-1), "2026-10");
  assert.deepEqual(plain(R.listMonths([], NOW)), ["2026-10"]);
});

test("buildRows: logged combos with no binding become historical rows", () => {
  const bindings = [
    { layer: "w", key: "u", label: "Previous Tab" },
    { layer: "w", key: "i", label: "Next Tab" },
    { layer: "o", key: "t", label: "Ghostty" },
  ];
  const presses = [
    ...Array(5).fill({ month: "2026-10", layer: "w", key: "u" }),
    ...Array(8).fill({ month: "2026-10", layer: "w", key: "y" }),
    ...Array(2).fill({ month: "2026-10", layer: "x", key: "up_arrow" }),
    { month: "2026-09", layer: "w", key: "i" },
  ];
  const counts = R.countCombos(presses, "2026-10");
  const rows = plain(M.buildRows(bindings, counts, null));
  assert.deepEqual(rows.map((r) => [r.layer, r.key, r.count, r.historical]), [
    ["w", "y", 8, true], ["w", "u", 5, false], ["x", "up_arrow", 2, true], ["w", "i", 0, false], ["o", "t", 0, false],
  ]);
  assert.equal(rows[0].label, "W Y");
  assert.equal(rows[2].label, "X up_arrow");
  // Totals agree with the rows.
  assert.equal(M.sumCounts(counts, null), rows.reduce((sum, r) => sum + r.count, 0));
  // A layer page lists its own historical rows only.
  const wRows = plain(M.buildRows(bindings, counts, "w"));
  assert.deepEqual(wRows.map((r) => r.key), ["y", "u", "i"]);
  assert.equal(M.sumCounts(counts, "w"), 13);
});

test("buildActivity and describeBin: exact counts with the family split", () => {
  const presses = [
    { month: "2026-10", layer: "w", key: "u", bin: 28 },
    { month: "2026-10", layer: "w", key: "u", bin: 28 },
    { month: "2026-10", layer: "v", key: "q", bin: 28 },
    { month: "2026-10", layer: "o", key: "t", bin: 29 },
    { month: "2026-09", layer: "w", key: "u", bin: 3 },
  ];
  const a = R.buildActivity(presses, "2026-10", "w", 30);
  assert.equal(a.total, 4);
  assert.equal(a.hitTotal, 2);
  assert.equal(a.peakHour, 14);
  assert.equal(a.perDot, 1);
  assert.equal(M.describeBin(a, 28), "14:00–14:30 · 3 presses · WINDOW 2 · MOVE 1");
  assert.equal(M.describeBin(a, 29), "14:30–15:00 · 1 press · LAUNCH 1");
  const dense = R.buildActivity(Array(95).fill({ month: "2026-10", layer: "w", key: "u", bin: 5 }), "2026-10", null, 30);
  assert.equal(dense.perDot, 4);
});

test("routeKey: overview", () => {
  const ctx = { page: null, layer: null, highlight: null, selected: null, aboutOpen: false, layers: ["w", "o"], heatHas: (k) => k === "w" || k === "o" };
  assert.deepEqual(plain(M.routeKey(ctx, { key: "w" })), { type: "openLayer", layer: "w" });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "W", shiftKey: true })), { type: "openLayer", layer: "w" });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "i" })), { type: "openPage", page: "insights" });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "a" })), { type: "openPage", page: "activity" });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "z" })), { type: "ignore" });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "ArrowLeft" })), { type: "month", step: -1 });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "ArrowRight", shiftKey: true })), { type: "month", step: 1 });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "Escape" })), { type: "close" });
  assert.equal(M.routeKey(ctx, { key: "ArrowDown" }), null, "plain up/down keep scrolling the list");
  assert.equal(M.routeKey(ctx, { key: "Tab" }), null);
  assert.equal(M.routeKey(ctx, { key: "w", metaKey: true }), null);
  assert.deepEqual(plain(M.routeKey(ctx, { key: "?" })), { type: "toggleAbout" });
});

test("routeKey: layer page selects every kind of binding key", () => {
  const ctx = { page: null, layer: "w", highlight: null, selected: null, aboutOpen: false, layers: ["w"], heatHas: () => true };
  const expectations = {
    ArrowUp: "up_arrow", ArrowDown: "down_arrow", ArrowLeft: "left_arrow", ArrowRight: "right_arrow",
    Enter: "return_or_enter", Backspace: "delete_or_backspace", " ": "spacebar",
    ";": "semicolon", "=": "equal_sign", "-": "hyphen", "1": "1", u: "u", I: "i",
  };
  for (const [name, key] of Object.entries(expectations)) {
    assert.deepEqual(plain(M.routeKey(ctx, { key: name })), { type: "select", key }, name);
  }
  // Shift + arrows change the month instead.
  assert.deepEqual(plain(M.routeKey(ctx, { key: "ArrowLeft", shiftKey: true })), { type: "month", step: -1 });
  assert.deepEqual(plain(M.routeKey({ ...ctx, selected: "u" }, { key: "Escape" })), { type: "select", key: null });
  assert.deepEqual(plain(M.routeKey(ctx, { key: "Escape" })), { type: "back" });
});

test("routeKey: activity and insights pages, Escape order", () => {
  const activity = { page: "activity", layer: null, highlight: null, selected: null, aboutOpen: false, layers: ["w", "v"], heatHas: () => false };
  assert.deepEqual(plain(M.routeKey(activity, { key: "w" })), { type: "highlight", layer: "w" });
  assert.deepEqual(plain(M.routeKey(activity, { key: "z" })), { type: "ignore" });
  assert.deepEqual(plain(M.routeKey(activity, { key: "ArrowRight" })), { type: "month", step: 1 });
  assert.deepEqual(plain(M.routeKey({ ...activity, highlight: "w" }, { key: "Escape" })), { type: "highlight", layer: "w" });
  assert.deepEqual(plain(M.routeKey(activity, { key: "Escape" })), { type: "back" });
  assert.deepEqual(plain(M.routeKey({ ...activity, aboutOpen: true, highlight: "w" }, { key: "Escape" })), { type: "closeAbout" });

  const insights = { ...activity, page: "insights" };
  assert.equal(M.routeKey(insights, { key: "w" }), null);
  assert.equal(M.routeKey(insights, { key: "ArrowLeft" }), null);
  assert.deepEqual(plain(M.routeKey(insights, { key: "ArrowLeft", shiftKey: true })), { type: "month", step: -1 });
  assert.deepEqual(plain(M.routeKey(insights, { key: "Escape" })), { type: "back" });
});

test("aboutLines: definition first, then log and analysis detail", () => {
  const store = M.createStore();
  store.reset(line("2026-10-15T09:00:00", "w", "u") + "\njunk", NOW);
  const lines = M.aboutLines({
    health: { log: { status: "ok", bytes: 2048 }, insights: { status: "stale", message: "older than 1h" } },
    insights: { recordingSince: "2026-10-14T13:06:00" },
    summary: store.summary(),
    now: NOW,
  });
  assert.equal(lines[0], "Hyper sublayer activations · repeats and outcomes excluded");
  assert.equal(lines[1], "Log ok · 2 kB · 1 press · 1 rejected line");
  assert.equal(lines[2], "Analysis stale: older than 1h");
  assert.equal(lines[3], "Recording since Oct 14 13:06");
});

test("describeHealth: an invalid bindings file is an error and says how to fix it", () => {
  const result = M.describeHealth({ health: { log: { status: "ok" }, bindings: { status: "invalid" }, insights: null }, lastEvent: null, rejected: 0, now: NOW });
  assert.equal(result.level, "error");
  assert.match(result.text, /BINDINGS FILE INVALID · RUN YARN BUILD/);
});

test("with no bindings every logged combo is historical, and totals still agree", () => {
  const presses = [{ month: "2026-10", layer: "w", key: "u" }, { month: "2026-10", layer: "w", key: "u" }, { month: "2026-10", layer: "o", key: "t" }];
  const counts = R.countCombos(presses, "2026-10");
  const rows = plain(M.buildRows([], counts, null));
  assert.deepEqual(rows.map((r) => [r.label, r.count, r.historical]), [["W U", 2, true], ["O T", 1, true]]);
  assert.equal(M.sumCounts(counts, null), 3);
});

test("routeKey: Enter and Space belong to a control focused from the keyboard", () => {
  const layerPage = { page: null, layer: "w", highlight: null, selected: null, aboutOpen: false, layers: ["w"], heatHas: () => true };
  // A focused header button or list row keeps normal activation.
  assert.equal(M.routeKey({ ...layerPage, controlFocused: true }, { key: "Enter" }), null);
  assert.equal(M.routeKey({ ...layerPage, controlFocused: true }, { key: " " }), null);
  // Other keys still route while a control is focused.
  assert.deepEqual(plain(M.routeKey({ ...layerPage, controlFocused: true }, { key: "u" })), { type: "select", key: "u" });
  assert.deepEqual(plain(M.routeKey({ ...layerPage, controlFocused: true }, { key: "Escape" })), { type: "back" });
  // Without keyboard focus on a control, Space selects the Space binding.
  assert.deepEqual(plain(M.routeKey(layerPage, { key: " " })), { type: "select", key: "spacebar" });
});

// ---------------------------------------------------------------------------------------------
// Incremental store and host protocol (stage B)

import { existsSync } from "node:fs";

const FUTURE_NOW = "2026-10-16T12:00:00";

// Deterministic synthetic log: valid lines, out-of-order stamps, malformed rows, future events.
function syntheticLog(lines, seed = 7) {
  let state = seed;
  const random = () => (state = (state * 1103515245 + 12345) % 2147483648) / 2147483648;
  const layers = ["w", "o", "v", "s", "c", "b", "f", "r"];
  const keys = ["u", "i", "q", "t", "spacebar", "up_arrow", "1", "h"];
  const out = [];
  for (let i = 0; i < lines; i++) {
    const roll = random();
    const day = 1 + Math.floor(random() * 28);
    const month = random() < 0.3 ? "09" : "10";
    const stamp = `2026-${month}-${String(day).padStart(2, "0")}T${String(Math.floor(random() * 24)).padStart(2, "0")}:${String(Math.floor(random() * 60)).padStart(2, "0")}:${String(Math.floor(random() * 60)).padStart(2, "0")}`;
    const layer = layers[Math.floor(random() * layers.length)];
    const key = keys[Math.floor(random() * keys.length)];
    if (roll < 0.03) out.push("garbage line");
    else if (roll < 0.05) out.push(`2026-13-40T00:00:00\t${layer}\t${key}`);
    else if (roll < 0.06) out.push("");
    else if (roll < 0.08) out.push(`2026-10-20T10:00:00\t${layer}\t${key}`); // after FUTURE_NOW
    else out.push(`${stamp}\t${layer}\t${key}`);
  }
  return out.join("\n") + "\n";
}

// What a full parse through the reference parser gives, in the store's snapshot shape.
function reference(text, now) {
  const parsed = R.parseLog(text, now);
  const counts = {};
  const bins = {};
  for (const p of parsed.presses) {
    (counts[p.month] ||= {})[`${p.layer} ${p.key}`] = (counts[p.month][`${p.layer} ${p.key}`] || 0) + 1;
    ((bins[p.month] ||= {})[p.layer] ||= new Array(48).fill(0))[p.bin] += 1;
  }
  return plain({ parsed, counts, bins });
}

function fresh(text, now) {
  const store = M.createStore();
  store.reset(text, now);
  return store;
}

test("store.reset agrees with the reference parser", () => {
  const text = syntheticLog(1500);
  const store = fresh(text, FUTURE_NOW);
  const snapshot = store.snapshot();
  const ref = reference(text, FUTURE_NOW);
  assert.equal(snapshot.count, ref.parsed.presses.length);
  assert.equal(snapshot.rejected, ref.parsed.rejected);
  assert.equal(snapshot.pending.length, ref.parsed.future);
  assert.equal(snapshot.firstEvent, ref.parsed.firstEvent);
  assert.equal(snapshot.lastEvent, ref.parsed.lastEvent);
  assert.deepEqual(plain(snapshot.lastUsed), Object.fromEntries(Object.keys(ref.parsed.lastUsed).sort().map((k) => [k, ref.parsed.lastUsed[k]])));
  for (const month of Object.keys(ref.counts)) {
    assert.deepEqual(plain(store.countsOf(month)), ref.counts[month], `counts ${month}`);
    assert.deepEqual(plain(store.binsOf(month)), ref.bins[month], `bins ${month}`);
  }
  assert.deepEqual(plain(store.countsOf("1999-01")), {});
});

test("the fast timestamp check gives the isValidTimestamp verdict", () => {
  const samples = ["2026-10-15T14:36:07", "2026-10-15T14:36:60", "2026-02-29T10:00:00", "2024-02-29T10:00:00",
    "2026-10-15T24:00:00", "1969-12-31T23:59:59", "2026-10-15T14:36:07 ", "2026-10-15t14:36:07", "２０２６-10-15T14:36:07"];
  for (const text of samples) {
    const store = fresh(`${text}\tw\tu\n`, "2030-01-01T00:00:00");
    assert.equal(store.summary().count === 1, M.isValidTimestamp(text), text);
  }
});

test("lines: CRLF, blank lines, a missing final newline, extra tabs and fields", () => {
  const store = fresh("2026-10-15T09:00:00\tw\tu\r\n\r\n\n2026-10-15T09:01:00\tw\tu\r\n2026-10-15T09:02:00\tw\tu\textra\n2026-10-15T09:03:00\tw\n2026-10-15T09:04:00\tw\tu", NOW);
  assert.equal(store.summary().count, 3);
  assert.equal(store.summary().rejected, 2);
  assert.equal(store.countsOf("2026-10")["w u"], 3);
});

test("incremental equals a full parse at every line boundary", () => {
  const text = syntheticLog(260);
  const full = fresh(text, FUTURE_NOW).snapshot();
  let offset = 0;
  for (let i = 0; i <= text.length; i++) {
    if (i !== text.length && text[i] !== "\n") continue;
    const cut = i === text.length ? text.length : i + 1;
    const session = M.createSession();
    session.reset({ generation: 1, text: text.slice(0, cut), offset: cut }, FUTURE_NOW);
    const result = session.append({ generation: 1, from: cut, to: text.length, text: text.slice(cut) }, FUTURE_NOW);
    assert.equal(result.ok, true);
    assert.deepEqual(session.store.snapshot(), full, `boundary ${cut}`);
    offset = cut;
  }
  assert.equal(offset, text.length);
});

test("incremental equals a full parse when delivered in many small chunks", () => {
  const text = syntheticLog(400, 11);
  const full = fresh(text, FUTURE_NOW).snapshot();
  const lines = text.split("\n").slice(0, -1).map((l) => `${l}\n`);
  for (const size of [1, 2, 3, 7, 50]) {
    const session = M.createSession();
    session.reset({ generation: 1, text: "", offset: 0 }, FUTURE_NOW);
    let from = 0;
    for (let i = 0; i < lines.length; i += size) {
      const chunk = lines.slice(i, i + size).join("");
      const result = session.append({ generation: 1, from, to: from + chunk.length, text: chunk }, FUTURE_NOW);
      assert.equal(result.ok, true);
      from += chunk.length;
    }
    assert.deepEqual(session.store.snapshot(), full, `chunk size ${size}`);
    assert.equal(session.offset, text.length);
  }
});

test("split records: a host that cuts at any byte and keeps the partial line unread matches a full parse", () => {
  const text = syntheticLog(120, 3);
  const full = fresh(text, FUTURE_NOW).snapshot();
  for (let cut = 0; cut <= text.length; cut += 1) {
    // Host rule: deliver up to and including the last newline before the cut; keep the rest unread.
    const delivered = text.slice(0, cut).lastIndexOf("\n") + 1;
    const session = M.createSession();
    session.reset({ generation: 1, text: text.slice(0, delivered), offset: delivered }, FUTURE_NOW);
    assert.equal(session.append({ generation: 1, from: delivered, to: text.length, text: text.slice(delivered) }, FUTURE_NOW).ok, true);
    assert.deepEqual(session.store.snapshot(), full, `cut ${cut}`);
  }
});

test("session: duplicate, gap, generation and invalid appends change nothing", () => {
  const text = syntheticLog(50, 5);
  const session = M.createSession();
  session.reset({ generation: 4, text, offset: text.length }, FUTURE_NOW);
  const before = session.store.snapshot();
  const next = "2026-10-16T01:00:00\tw\tu\n";
  const ok = { generation: 4, from: text.length, to: text.length + next.length, text: next };

  assert.deepEqual(plain(session.append({ ...ok, generation: 3 }, FUTURE_NOW)), { ok: false, reason: "generation", offset: text.length });
  assert.deepEqual(plain(session.append({ ...ok, from: text.length + 5, to: text.length + 5 + next.length }, FUTURE_NOW)), { ok: false, reason: "gap", offset: text.length });
  assert.deepEqual(plain(session.append({ ...ok, from: 0, to: text.length }, FUTURE_NOW)), { ok: false, reason: "duplicate", offset: text.length });
  assert.deepEqual(plain(session.append({ ...ok, text: 5 }, FUTURE_NOW)), { ok: false, reason: "invalid", offset: text.length });
  assert.deepEqual(plain(session.append({ generation: 4, from: 10, to: 5, text: "" }, FUTURE_NOW)), { ok: false, reason: "invalid", offset: text.length });
  assert.deepEqual(session.store.snapshot(), before, "rejected appends apply nothing");

  assert.deepEqual(plain(session.append(ok, FUTURE_NOW)), { ok: true, offset: text.length + next.length });
  // Delivering the same chunk again is now a duplicate.
  assert.equal(session.append(ok, FUTURE_NOW).reason, "duplicate");
  assert.equal(session.store.countsOf("2026-10")["w u"], (before.counts["2026-10"]["w u"] || 0) + 1);
});

test("session: reset after append discards earlier events and takes the new generation", () => {
  const session = M.createSession();
  session.reset({ generation: 1, text: "2026-10-15T09:00:00\tw\tu\n", offset: 25 }, NOW);
  session.append({ generation: 1, from: 25, to: 50, text: "2026-10-15T09:01:00\tw\tu\n" }, NOW);
  assert.equal(session.store.summary().count, 2);

  const replacement = "2026-10-15T10:00:00\to\tt\n";
  assert.deepEqual(plain(session.reset({ generation: 2, text: replacement, offset: replacement.length }, NOW)), { ok: true, generation: 2, offset: replacement.length });
  assert.deepEqual(session.store.snapshot(), fresh(replacement, NOW).snapshot());
  assert.equal(session.append({ generation: 1, from: 25, to: 50, text: "x" }, NOW).reason, "generation");

  // A bad reset leaves an empty store that rejects appends until the next good reset.
  assert.equal(session.reset({ generation: 3, text: 5 }, NOW).ok, false);
  assert.equal(session.store.summary().count, 0);
  assert.equal(session.append({ generation: 3, from: 0, to: 1, text: "x" }, NOW).reason, "generation");
});

test("future events wait in the pending list and tick promotes them", () => {
  const text = [
    "2026-10-15T13:00:00\tw\tu",
    "2026-10-15T15:00:00\tw\tu",
    "2026-10-15T16:30:00\to\tt",
    "2026-10-16T09:00:00\tw\ti",
  ].join("\n") + "\n";
  const store = fresh(text, "2026-10-15T14:00:00");
  assert.equal(store.summary().count, 1);
  assert.equal(store.summary().pending, 3);
  assert.equal(store.summary().lastEvent, "2026-10-15T13:00:00");
  assert.equal(store.tick("2026-10-15T15:00:00"), 1, "an event exactly at now is promoted");
  assert.equal(store.lastUsedOf("w u"), "2026-10-15T15:00:00");
  assert.equal(store.tick("2026-10-15T15:30:00"), 0);
  assert.equal(store.tick("2026-10-16T12:00:00"), 2);
  assert.deepEqual(store.snapshot(), fresh(text, "2026-10-16T12:00:00").snapshot(), "ticking equals loading later");
  assert.equal(store.summary().pending, 0);

  // Events appended while still in the future wait too.
  const session = M.createSession();
  session.reset({ generation: 1, text: "", offset: 0 }, "2026-10-15T14:00:00");
  session.append({ generation: 1, from: 0, to: 25, text: "2026-10-15T14:30:00\tw\tu\n" }, "2026-10-15T14:00:00");
  assert.equal(session.store.summary().count, 0);
  session.store.tick("2026-10-15T14:30:00");
  assert.equal(session.store.summary().count, 1);
});

test("months: the list follows the date even with no new record", () => {
  const store = fresh("2026-08-20T09:00:00\tw\tu\n", "2026-08-21T00:00:00");
  assert.deepEqual(plain(store.months("2026-08-21T00:00:00")), ["2026-08"]);
  assert.deepEqual(plain(store.months("2026-11-02T00:00:00")), ["2026-08", "2026-09", "2026-10", "2026-11"]);
  assert.deepEqual(plain(fresh("", NOW).months("2027-01-01T00:00:00")), ["2027-01"]);
});

test("totals, rankings, last use and Activity agree after reset+append versus a full parse", () => {
  const text = syntheticLog(900, 21);
  const cut = text.indexOf("\n", Math.floor(text.length / 3)) + 1;
  const incremental = M.createSession();
  incremental.reset({ generation: 1, text: text.slice(0, cut), offset: cut }, FUTURE_NOW);
  incremental.append({ generation: 1, from: cut, to: text.length, text: text.slice(cut) }, FUTURE_NOW);
  const full = fresh(text, FUTURE_NOW);
  const oracle = R.parseLog(text, FUTURE_NOW);

  const bindings = [{ layer: "w", key: "u", label: "Previous Tab" }, { layer: "o", key: "t", label: "Ghostty" }, { layer: "v", key: "q", label: "Left click" }];
  for (const month of ["2026-09", "2026-10"]) {
    for (const layer of [null, "w", "o"]) {
      const a = plain(M.buildRows(bindings, incremental.store.countsOf(month), layer));
      const b = plain(M.buildRows(bindings, full.countsOf(month), layer));
      const c = plain(M.buildRows(bindings, R.countCombos(oracle.presses, month), layer));
      assert.deepEqual(a, b);
      assert.deepEqual(a, c);
      assert.equal(M.sumCounts(incremental.store.countsOf(month), layer), M.sumCounts(R.countCombos(oracle.presses, month), layer));
    }
    for (const highlight of [null, "w"]) {
      assert.deepEqual(
        plain(M.buildActivityFromBins(incremental.store.binsOf(month), highlight, 30)),
        plain(R.buildActivity(oracle.presses, month, highlight, 30)),
        `activity ${month} ${highlight}`,
      );
    }
  }
  for (const id of Object.keys(oracle.lastUsed)) assert.equal(incremental.store.lastUsedOf(id), oracle.lastUsed[id], id);
  assert.equal(incremental.store.summary().rejected, oracle.rejected);
});

test("reconcileNavigation: a data update keeps navigation unless its target is gone", () => {
  const nav = { monthId: "2026-09", layer: "w", selected: "u", page: null, highlight: "w", aboutOpen: false };
  const months = ["2026-08", "2026-09", "2026-10"];
  assert.deepEqual(plain(M.reconcileNavigation(nav, months, ["w", "o"])), nav, "an append changes nothing");
  assert.deepEqual(plain(M.reconcileNavigation(nav, [...months, "2026-11"], ["w", "o"])), nav, "a new month keeps the chosen month id");
  assert.equal(M.reconcileNavigation(nav, ["2026-10"], ["w"]).monthId, "2026-10", "a vanished month falls back to the latest");
  const gone = plain(M.reconcileNavigation(nav, months, ["o"]));
  assert.equal(gone.layer, null);
  assert.equal(gone.selected, null);
  assert.equal(gone.highlight, null);
  assert.equal(gone.aboutOpen, false);
  // Another layer going away leaves the current one alone.
  assert.equal(M.reconcileNavigation(nav, months, ["w"]).layer, "w");
});

// Set HYPERDASH_TEST_LOG to a COPY of usage.log. Never point it at the live log while it is being written.
const REAL_LOG = process.env.HYPERDASH_TEST_LOG;
const realLogSkip = !REAL_LOG ? "set HYPERDASH_TEST_LOG to a COPY of usage.log" : !existsSync(REAL_LOG) && `HYPERDASH_TEST_LOG not found: ${REAL_LOG}`;
test("a copy of the real log: incremental equals full at line boundaries", { skip: realLogSkip }, () => {
  const text = readFileSync(REAL_LOG, "utf8");
  const now = "2026-12-31T23:59:59";
  const full = fresh(text, now).snapshot();
  assert.ok(full.count > 1000);
  const boundaries = [];
  for (let i = text.indexOf("\n"); i !== -1; i = text.indexOf("\n", i + 1)) boundaries.push(i + 1);
  for (const cut of boundaries.filter((_, index) => index % 7 === 0 || index < 40)) {
    const session = M.createSession();
    session.reset({ generation: 1, text: text.slice(0, cut), offset: cut }, now);
    assert.equal(session.append({ generation: 1, from: cut, to: text.length, text: text.slice(cut) }, now).ok, true);
    assert.deepEqual(session.store.snapshot(), full, `boundary ${cut}`);
  }
  const oracle = R.parseLog(text, now);
  assert.equal(full.count, oracle.presses.length);
  assert.equal(full.rejected, oracle.rejected);
});

test("stampOrNull: a host `now` is a local ISO string, never epoch milliseconds", () => {
  assert.equal(M.stampOrNull("2026-10-16T12:00:00"), "2026-10-16T12:00:00");
  assert.equal(M.stampOrNull(1792152000000), null);
  assert.equal(M.stampOrNull("1792152000000"), null);
  assert.equal(M.stampOrNull("2026-10-16 12:00:00"), null);
  assert.equal(M.stampOrNull("2026-10-16T12:00:00Z"), null);
  assert.equal(M.stampOrNull("2026-02-31T12:00:00"), null);
  assert.equal(M.stampOrNull(null), null);
  assert.equal(M.stampOrNull(undefined), null);
});

test("tabStopsAfter: tab stops stay off until the user presses Tab", () => {
  assert.equal(M.tabStopsAfter(false, { key: "w" }), false);
  assert.equal(M.tabStopsAfter(false, { key: "Enter" }), false);
  assert.equal(M.tabStopsAfter(false, { key: " " }), false);
  assert.equal(M.tabStopsAfter(false, { key: "Tab" }), true);
  assert.equal(M.tabStopsAfter(true, { key: "w" }), true, "once on, they stay on until the next open");
});
