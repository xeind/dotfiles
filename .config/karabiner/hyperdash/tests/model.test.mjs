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

test("normalizeInsights: versions 2 and 3 are accepted, others are not", () => {
  const item = { kind: "rising", title: "t", detail: "d", keys: [["w", "u"], ["bad"]], value: 1 };
  assert.equal(M.normalizeInsights({ version: 1, insights: [item] }), null);
  assert.equal(M.normalizeInsights({ version: 4, insights: [item] }), null);
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
  // Version 2 has no dates or app; version 3 carries them.
  assert.deepEqual(plain(parsed.insights[0].dates), []);
  assert.equal(parsed.insights[0].app, null);
  const v3 = plain(M.normalizeInsights({ version: 3, generated: NOW, month: "2026-10", insights: [
    { ...item, dates: ["2026-10-14", "2026-10-15", "2026-02-30", "x"], app: "com.mitchellh.ghostty" },
    { ...item, dates: "2026-10-14", app: "has space" },
  ] }));
  assert.deepEqual(v3.insights[0].dates, ["2026-10-14", "2026-10-15"]);
  assert.equal(v3.insights[0].app, "com.mitchellh.ghostty");
  assert.deepEqual(v3.insights[1].dates, []);
  assert.equal(v3.insights[1].app, null);
});

test("normalizeHealth: unknown statuses are dropped", () => {
  assert.equal(M.normalizeHealth("x"), null);
  const health = plain(M.normalizeHealth({ log: { status: "ok", bytes: 10, modified: NOW }, insights: { status: "weird" } }));
  assert.deepEqual(health, { log: { status: "ok", bytes: 10, modified: NOW }, bindings: null, insights: null, context: null });
  assert.deepEqual(plain(M.normalizeHealth({ context: { status: "disabled" } })).context, { status: "disabled", bytes: null, modified: null });
  assert.equal(M.normalizeHealth({ context: { status: "weird" } }).context, null);
  assert.deepEqual(plain(M.normalizeHealth({ bindings: { status: "invalid" } })).bindings, { status: "invalid" });
});

test("describeHealth: inactivity is neutral; only the host can say the log failed", () => {
  const quiet = M.describeHealth({ health: null, lastEvent: "2026-10-15T14:02:00", rejected: 0, now: NOW });
  assert.equal(quiet.text, "LAST 14:02", "a healthy line uses short labels");
  assert.equal(quiet.full, "LAST PRESS 14:02", "the tooltip keeps the full wording");
  assert.equal(quiet.compact, true);
  assert.equal(quiet.level, "ok");
  const older = M.describeHealth({ health: null, lastEvent: "2026-10-12T14:02:00", rejected: 0, now: NOW });
  assert.equal(older.text, "LAST OCT 12 14:02");
  assert.equal(M.describeHealth({ health: null, lastEvent: null, rejected: 0, now: NOW }).text, "NO PRESSES RECORDED");

  const health = { log: { status: "ok" }, insights: { status: "ok" } };
  assert.equal(M.describeHealth({ health, lastEvent: "2026-10-15T14:02:00", rejected: 1, now: NOW }).text,
    "LOG OK · LAST PRESS 14:02 · 1 BAD LINE · ANALYSIS OK", "a warning keeps the full wording");
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

test("activity by colour group and describeBin: exact counts with the group split", () => {
  const presses = [
    { month: "2026-10", layer: "w", key: "u", bin: 28 },
    { month: "2026-10", layer: "w", key: "u", bin: 28 },
    { month: "2026-10", layer: "v", key: "q", bin: 28 },
    { month: "2026-10", layer: "o", key: "t", bin: 29 },
    { month: "2026-09", layer: "w", key: "u", bin: 3 },
  ];
  const classify = M.classifier([]);
  const a = R.buildActivity(presses, "2026-10", "w", 30, classify);
  assert.equal(a.total, 4);
  assert.equal(a.hitTotal, 2);
  assert.equal(a.peakHour, 14);
  assert.equal(a.perDot, 1);
  assert.equal(M.describeBin(a, 28), "14:00–14:30 · 3 presses · WINDOWS 2 · NAVIGATE 1");
  assert.equal(M.describeBin(a, 29), "14:30–15:00 · 1 press · LAUNCH 1");
  const dense = R.buildActivity(Array(95).fill({ month: "2026-10", layer: "w", key: "u", bin: 5 }), "2026-10", null, 30, classify);
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
  assert.match(result.text, /BINDINGS INVALID · RUN YARN BUILD/);
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
    ((bins[p.month] ||= {})[`${p.layer} ${p.key}`] ||= new Array(48).fill(0))[p.bin] += 1;
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
    const classify = M.classifier([{ layer: "v", key: "q", category: "pointer" }, { layer: "w", key: "u", category: "tab-navigation" }]);
    for (const highlight of [null, "w"]) {
      assert.deepEqual(
        plain(M.buildActivityFromCombos(incremental.store.binsOf(month), classify, highlight, 30)),
        plain(R.buildActivity(oracle.presses, month, highlight, 30, classify)),
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

// ---------------------------------------------------------------------------------------------
// Round 4: categories, day view, app context, sequences

const ctxLine = (stamp, kind, value = "-") => `${stamp}\t${kind}\t${value}`;
const contextFrom = (lines) => { const store = M.createContextStore(); store.reset(lines.join("\n") + "\n"); return store; };

test("categories: twelve categories fall into at most six colour groups, and the layer is the fallback", () => {
  assert.equal(M.CATEGORIES.length, 12);
  assert.ok(M.GROUPS.length <= 6);
  for (const category of M.CATEGORIES) {
    assert.ok(M.GROUPS.includes(M.CATEGORY_GROUP[category]), category);
    assert.ok(M.CATEGORY_LABELS[category], `label for ${category}`);
  }
  assert.equal(M.groupOf("v", "pointer"), "pointer");
  assert.equal(M.groupOf("v", "tab-navigation"), "navigate");
  assert.equal(M.groupOf("v", undefined), "navigate", "no category: the layer family");
  assert.equal(M.groupOf("o", "site-open"), "launch");
  assert.equal(M.groupOf("zz", null), "system", "unknown layer");
  const classify = M.classifier([{ layer: "w", key: "u", category: "tab-navigation" }, { layer: "w", key: "h", category: "bogus" }, { layer: "w", key: "y" }]);
  assert.equal(classify.categoryOf("w u"), "tab-navigation");
  assert.equal(classify.groupOf("w u"), "navigate");
  assert.equal(classify.categoryOf("w h"), null, "an unknown category is ignored");
  assert.equal(classify.groupOf("w h"), "windows");
  assert.equal(classify.groupOf("w y"), "windows");
  assert.equal(classify.groupOf("x spacebar"), "system");
  assert.equal(M.normalizeBindings([{ layer: "w", key: "u", label: "x", category: "pointer" }, { layer: "w", key: "i", label: "y", category: "nope" }])[1].category, undefined);
});

test("dates: stepping, labels and clamping", () => {
  assert.equal(M.addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(M.addDays("2026-03-01", -1), "2026-02-28");
  assert.equal(M.addDays("2024-03-01", -1), "2024-02-29");
  assert.equal(M.addDays("2026-01-01", -1), "2025-12-31");
  assert.equal(M.dayLabel("2026-10-16", "2026-10-16"), "Today");
  assert.equal(M.dayLabel("2026-10-15", "2026-10-16"), "Yesterday");
  assert.equal(M.dayLabel("2026-10-12", "2026-10-16"), "Mon Oct 12");
  assert.equal(M.clampDay("2026-10-20", "2026-10-10", "2026-10-16"), "2026-10-16");
  assert.equal(M.clampDay("2026-10-01", "2026-10-10", "2026-10-16"), "2026-10-10");
  assert.equal(M.clampDay("2026-10-12", "2026-10-10", "2026-10-16"), "2026-10-12");
  assert.equal(M.clampDay("2026-10-01", null, "2026-10-16"), "2026-10-16");
  assert.equal(M.isValidDate("2026-02-30"), false);
  assert.equal(M.isValidDate("2026-10-16"), true);
  assert.equal(M.isValidDate("2026-10-16T00:00:00"), false);
});

test("context log: valid lines, rejected lines, and the value rules", () => {
  const store = M.createContextStore();
  store.reset([
    ctxLine("2026-10-16T09:00:00.000", "start"),
    ctxLine("2026-10-16T09:00:01.250", "app", "com.mitchellh.ghostty"),
    ctxLine("2026-10-16T09:10:00.500", "lock"),
    ctxLine("2026-10-16T09:20:00.500", "unlock"),
    ctxLine("2026-10-16T09:00:01", "app", "com.x"),             // no milliseconds
    ctxLine("2026-10-16T09:00:01.250", "app", "has space"),     // bad bundle id
    ctxLine("2026-10-16T09:00:01.250", "app", "-"),              // a bare dash (Context.swift rejects it too; "-x" is valid)
    ctxLine("2026-10-16T09:00:01.250", "lock", "extra"),         // value must be "-"
    ctxLine("2026-10-16T09:00:01.250", "focus", "-"),            // unknown kind
    ctxLine("2026-02-30T09:00:01.250", "app", "com.x"),          // impossible date
    ctxLine("2026-10-16T09:00:61.250", "app", "com.x"),          // second 61
    "2026-10-16T09:00:01.250\tapp",                                // two fields
    "",
  ].join("\n"));
  const summary = store.summary();
  assert.equal(summary.count, 4);
  assert.equal(summary.rejected, 8);
  assert.equal(summary.firstEvent, "2026-10-16T09:00:00.000");
  assert.equal(summary.lastEvent, "2026-10-16T09:20:00.500");
  assert.deepEqual(plain(store.bundles()), ["com.mitchellh.ghostty"]);
});

test("attribution: the last app event strictly before the second; same-second changes count later", () => {
  const context = contextFrom([
    ctxLine("2026-10-16T09:00:00.000", "start"),
    ctxLine("2026-10-16T09:59:59.900", "app", "com.a"),
    ctxLine("2026-10-16T10:00:00.000", "app", "com.b"),   // exactly at the second: not before it
    ctxLine("2026-10-16T10:00:07.250", "app", "com.c"),   // same second as the press at 10:00:07
    ctxLine("2026-10-16T10:00:09.999", "app", "com.d"),
  ]);
  assert.equal(context.appAt("2026-10-16T09:59:59"), null, "nothing before the first app event");
  assert.equal(context.appAt("2026-10-16T10:00:00"), "com.a", "an app event at 10:00:00.000 is not strictly before 10:00:00");
  assert.equal(context.appAt("2026-10-16T10:00:01"), "com.b");
  assert.equal(context.appAt("2026-10-16T10:00:07"), "com.b", "an app launched in the same second is attributed to where the press came from");
  assert.equal(context.appAt("2026-10-16T10:00:08"), "com.c");
  assert.equal(context.appAt("2026-10-16T10:00:10"), "com.d");
});

test("attribution agrees with a plain linear scan on random events", () => {
  let seed = 5; const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const stampOf = (sec, ms = null) => `2026-10-16T${String(Math.floor(sec / 3600)).padStart(2, "0")}:${String(Math.floor(sec / 60) % 60).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}${ms === null ? "" : "." + String(ms).padStart(3, "0")}`;
  const events = [{ t: stampOf(0, 0), kind: "start", value: "-" }];
  const lines = [ctxLine(stampOf(0, 0), "start")];
  for (let i = 0; i < 300; i++) {
    const t = stampOf(Math.floor(random() * 3000), Math.floor(random() * 1000));
    const value = `com.app${Math.floor(random() * 6)}`;
    events.push({ t, kind: "app", value });
    lines.push(ctxLine(t, "app", value));
  }
  const context = contextFrom(lines);
  const now = "2026-10-16T12:00:00";
  for (let sec = 0; sec < 3100; sec += 1) {
    const stamp = stampOf(sec);
    assert.equal(context.appAt(stamp, now), R.appAtNaive(events, stamp, M.absSeconds(now)), stamp);
  }
});

test("the day split: events by date, sorted, across midnight and out of order", () => {
  const store = M.createStore();
  store.reset([
    "2026-10-15T23:59:58\tw\tu",
    "2026-10-16T00:00:00\tw\ti",
    "2026-10-16T00:00:02\tv\tq",
    "2026-10-16T00:00:01\tv\tq",     // out of order
    "2026-10-16T00:00:01\to\tt",     // same second, later in the log
    "2026-10-17T00:00:03\tw\tu",     // after now
  ].join("\n") + "\n", "2026-10-16T12:00:00");
  assert.deepEqual(plain(store.dayList()), ["2026-10-15", "2026-10-16"]);
  assert.deepEqual(plain(store.dayEvents("2026-10-15").map((e) => [e.sec, e.combo])), [[86398, "w u"]]);
  assert.deepEqual(plain(store.dayEvents("2026-10-16").map((e) => [e.sec, e.combo])), [[0, "w i"], [1, "v q"], [1, "o t"], [2, "v q"]], "sorted, ties in log order");
  assert.deepEqual(plain(store.dayEvents("2026-10-18")), []);
  store.tick("2026-10-17T12:00:00");
  assert.equal(store.dayEvents("2026-10-17").length, 1, "a future event joins its day when its time comes");
});

test("day split agrees with the reference parser on a synthetic log", () => {
  const text = syntheticLog(800, 17);
  const store = fresh(text, FUTURE_NOW);
  const oracle = R.parseLog(text, FUTURE_NOW);
  const dates = [...new Set(oracle.presses.map((p) => p.date))].sort();
  assert.deepEqual(plain(store.dayList()), dates);
  for (const date of dates) {
    const expected = oracle.presses.filter((p) => p.date === date).map((p) => `${p.sec} ${p.layer} ${p.key}`).sort();
    const actual = plain(store.dayEvents(date).map((e) => `${e.sec} ${e.layer} ${e.key}`).sort());
    assert.deepEqual(actual, expected, date);
    assert.deepEqual(plain(store.dayEvents(date).map((e) => e.sec)), plain(store.dayEvents(date).map((e) => e.sec)).sort((a, b) => a - b), "time order");
  }
  // Incremental delivery gives the same days as a full parse.
  const cut = text.indexOf("\n", Math.floor(text.length / 2)) + 1;
  const session = M.createSession();
  session.reset({ generation: 1, text: text.slice(0, cut), offset: cut }, FUTURE_NOW);
  session.append({ generation: 1, from: cut, to: text.length, text: text.slice(cut) }, FUTURE_NOW);
  assert.deepEqual(session.store.snapshot().days, store.snapshot().days);
});

test("commandsIn: a half-hour bin holds seconds 1800*bin to 1800*bin+1799", () => {
  const events = [0, 1799, 1800, 3599, 3600].map((sec) => ({ sec, combo: "w u" }));
  assert.deepEqual(M.commandsIn(events, 0).map((e) => e.sec), [0, 1799]);
  assert.deepEqual(M.commandsIn(events, 1).map((e) => e.sec), [1800, 3599]);
  assert.deepEqual(M.commandsIn(events, 2).map((e) => e.sec), [3600]);
  assert.equal(M.clock(0), "00:00:00");
  assert.equal(M.clock(86399), "23:59:59");
  assert.equal(M.clock(3725), "01:02:05");
});

function runsOf(segments) { return segments.map((s) => [s.from, s.to, s.state]); }

const SHARED = JSON.parse(readFileSync(new URL("./session_cases.json", import.meta.url), "utf8"));
const linesOf = (rows) => rows.map(([stamp, kind, value]) => ctxLine(stamp, kind, value));
const eventsOf = (rows) => rows.map(([t, kind, value]) => ({ t, kind, value }));
const NOW_END = "2026-10-16T23:59:59";

test("sessions, shared cases: spans and day intervals match the hand-worked values (also checked by Swift)", () => {
  for (const c of SHARED.sessions) {
    const context = contextFrom(linesOf(c.context));
    const spans = plain(context.sessions(c.now)).map((s) => [s.start, s.end]);
    assert.deepEqual(spans, c.spans.map(([a, b]) => [M.absSeconds(a), M.absSeconds(b)]), `${c.name}: spans`);
    for (const [date, expected] of Object.entries(c.days)) {
      assert.deepEqual(plain(runsOf(context.segments(date, c.now))), expected, `${c.name}: ${date}`);
    }
    for (const [stamp, app] of c.presses) assert.equal(context.appAt(stamp, c.now), app, `${c.name}: press ${stamp}`);
  }
});

test("coverage strip, shared cases: each day's runs tile the clipped day, and each half hour is worded by its largest state", () => {
  const notes = { recorded: "", locked: "locked", asleep: "asleep", unknown: "no app context" };
  const kinds = new Set();
  for (const c of SHARED.sessions) {
    const context = contextFrom(linesOf(c.context));
    for (const date of Object.keys(c.days)) {
      const segments = plain(context.segments(date, c.now));
      let at = 0;
      for (const s of segments) {
        assert.equal(s.from, at, `${c.name}: ${date} runs are contiguous`);
        assert.ok(s.to > s.from);
        at = s.to;
        kinds.add(s.state);
      }
      for (let bin = 0; bin < 48; bin++) {
        // Second by second, the independent way.
        const seconds = {};
        for (let t = bin * 1800; t < (bin + 1) * 1800; t++) {
          const run = segments.find((s) => t >= s.from && t < s.to);
          if (run) seconds[run.state] = (seconds[run.state] || 0) + 1;
        }
        const order = ["unknown", "locked", "asleep", "recorded"];
        const winner = order.reduce((best, kind) => ((seconds[kind] || 0) > (seconds[best] || 0) ? kind : best), "recorded");
        const covered = Object.keys(seconds).length > 0;
        assert.equal(M.coverageNote(segments, bin), covered ? notes[winner] : "", `${c.name}: ${date} bin ${bin}`);
      }
    }
  }
  assert.deepEqual([...kinds].sort(), ["asleep", "locked", "recorded", "unknown"], "the shared cases exercise every strip state");
});

test("compactCount: whole numbers below 10,000, then at most five characters", () => {
  const cases = [[0, "0"], [999, "999"], [5632, "5,632"], [9999, "9,999"], [10000, "10K"], [12345, "12.3K"], [99949, "99.9K"], [99950, "100K"], [123456, "123K"], [999499, "999K"], [999500, "1M"], [1234567, "1.2M"]];
  for (const [n, text] of cases) assert.equal(M.compactCount(n), text, String(n));
  for (let n = 0; n < 3e6; n += 997) assert.ok(M.compactCount(n).length <= 5, `${n} -> ${M.compactCount(n)}`);
});

test("coverageNote: no segments (context off, or the month view) gives no note; a hand-worked mixed half hour", () => {
  assert.equal(M.coverageNote(null, 5), "");
  const runs = [{ from: 0, to: 3600, state: "unknown" }, { from: 3600, to: 4000, state: "recorded" }, { from: 4000, to: 5400, state: "locked" }];
  assert.equal(M.coverageNote(runs, 0), "no app context", "00:00-00:30 is all unknown");
  assert.equal(M.coverageNote(runs, 2), "locked", "01:00-01:30: 400 s recorded, 1400 s locked");
  assert.equal(M.coverageNote(runs, 3), "", "after the last run nothing is known, so nothing is said");
});

test("attribution, shared cases ported from the Swift tests", () => {
  for (const c of SHARED.attribution) {
    const context = contextFrom(linesOf(c.context));
    assert.deepEqual(plain(c.presses.map((stamp) => context.appAt(stamp, c.now))), c.expected, c.name);
  }
});

test("the reference session calculation agrees with the hand-worked shared cases", () => {
  for (const c of SHARED.sessions) {
    const events = eventsOf(c.context);
    const nowSeconds = M.absSeconds(c.now);
    assert.deepEqual(R.sessionSpansNaive(events, nowSeconds).map((s) => [s.start, s.end]), c.spans.map(([a, b]) => [M.absSeconds(a), M.absSeconds(b)]), c.name);
    for (const [date, expected] of Object.entries(c.days)) {
      assert.deepEqual(R.segmentsBrute(events, date, nowSeconds).map((r) => [r.from, r.to, r.state]), expected, `${c.name}: ${date}`);
    }
    for (const [stamp, app] of c.presses) assert.equal(R.appAtNaive(events, stamp, nowSeconds), app, `${c.name}: ${stamp}`);
  }
});

test("intervals and attribution agree with the second-by-second calculation on random context logs", () => {
  let seed = 41; const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const stampAt = (sec, ms) => `2026-10-16T${String(Math.floor(sec / 3600)).padStart(2, "0")}:${String(Math.floor(sec / 60) % 60).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}.${String(ms).padStart(3, "0")}`;
  for (let round = 0; round < 25; round++) {
    const rows = [];
    for (let i = 0; i < 40; i++) {
      const kind = ["start", "app", "app", "lock", "unlock", "sleep", "wake"][Math.floor(random() * 7)];
      rows.push([stampAt(Math.floor(random() * 80000), Math.floor(random() * 1000)), kind, kind === "app" ? `com.app${Math.floor(random() * 4)}` : "-"]);
    }
    const now = "2026-10-16T21:00:00";
    const context = contextFrom(linesOf(rows));
    const events = eventsOf(rows);
    const nowSeconds = M.absSeconds(now);
    assert.deepEqual(plain(runsOf(context.segments("2026-10-16", now))), R.segmentsBrute(events, "2026-10-16", nowSeconds).map((r) => [r.from, r.to, r.state]), `round ${round}`);
    for (let k = 0; k < 120; k++) {
      const sec = Math.floor(random() * 75600);
      const stamp = stampAt(sec, 0).slice(0, 19);
      assert.equal(context.appAt(stamp, now), R.appAtNaive(events, stamp, nowSeconds), `round ${round} ${stamp}`);
    }
  }
});

test("sequences: recurring adjacent pairs within 10 s, against a plain calculation", () => {
  const events = [];
  let sec = 100;
  for (let i = 0; i < 40; i++) { events.push({ sec, combo: "v q", app: "com.a" }); sec += 2; events.push({ sec, combo: "v u", app: "com.a" }); sec += 30; }
  for (let i = 0; i < 4; i++) { events.push({ sec, combo: "w i", app: "com.b" }); sec += 3; events.push({ sec, combo: "w u", app: "com.b" }); sec += 20; }
  events.push({ sec, combo: "w i", app: "com.a" }); sec += 11; events.push({ sec, combo: "w u", app: "com.a" }); // 11 s: too far apart
  sec += 5; events.push({ sec, combo: "w u", app: "com.a" }); sec += 2; events.push({ sec, combo: "w u", app: "com.a" }); // same command twice: not a pair
  const found = M.findSequences(events);
  assert.deepEqual(plain(found.map((s) => [`${s.from} > ${s.to}`, s.count])), R.sequencesNaive(events, 10, 3, null).map((s) => [s.key, s.count]));
  assert.deepEqual(plain(found.map((s) => [`${s.from} > ${s.to}`, s.count])), [["v q > v u", 40], ["w i > w u", 4]]);
  assert.equal(found[0].times.length, 40);
  assert.equal(found[0].times[0], 100);
  // Fewer than three occurrences is not recurring.
  assert.deepEqual(plain(M.findSequences(events.slice(0, 4))), []);
  // An app filter keeps pairs whose two commands were both in that app.
  const inB = M.findSequences(events, { app: "com.b" });
  assert.deepEqual(plain(inB.map((s) => [`${s.from} > ${s.to}`, s.count])), R.sequencesNaive(events, 10, 3, "com.b").map((s) => [s.key, s.count]));
  assert.deepEqual(plain(inB.map((s) => s.count)), [4]);
  // A different gap limit.
  assert.equal(M.findSequences(events, { maxGap: 1 }).length, 0);
  // Random days agree with the plain calculation.
  let seed = 3; const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const combos = ["a 1", "a 2", "b 1", "c 1"];
  for (let round = 0; round < 20; round++) {
    const day = []; let t = 0;
    for (let i = 0; i < 300; i++) { t += Math.floor(random() * 14); day.push({ sec: t, combo: combos[Math.floor(random() * 4)], app: random() < 0.5 ? "x" : "y" }); }
    for (const app of [null, "x"]) {
      // Ties in count may order differently (the model breaks them by first time), so compare sorted by count then name.
      const byCountThenName = (x, y) => y[1] - x[1] || (x[0] < y[0] ? -1 : 1);
      assert.deepEqual(plain(M.findSequences(day, { app }).map((s) => [`${s.from} > ${s.to}`, s.count])).sort(byCountThenName), R.sequencesNaive(day, 10, 3, app).map((s) => [s.key, s.count]).sort(byCountThenName));
    }
  }
});

test("a day: events, apps, sequences and shading come together, and the app filter narrows them", () => {
  const usage = fresh([
    "2026-10-16T10:00:00\tv\tq", "2026-10-16T10:00:03\tv\tu", "2026-10-16T10:00:20\tv\tq", "2026-10-16T10:00:22\tv\tu",
    "2026-10-16T10:01:00\tv\tq", "2026-10-16T10:01:02\tv\tu", "2026-10-16T10:40:00\tw\ti",
  ].join("\n") + "\n", "2026-10-16T12:00:00");
  const context = contextFrom([
    ctxLine("2026-10-16T09:00:00.000", "start"),
    ctxLine("2026-10-16T09:59:00.000", "app", "com.firefox"),
    ctxLine("2026-10-16T10:00:21.500", "app", "com.ghostty"),
    ctxLine("2026-10-16T10:30:00.000", "lock"),
    ctxLine("2026-10-16T10:35:00.000", "unlock"),
  ]);
  const classify = M.classifier([{ layer: "v", key: "q", category: "pointer" }, { layer: "v", key: "u", category: "page-navigation" }]);
  const make = (appFilter) => M.buildDay({ usage, context, date: "2026-10-16", now: "2026-10-16T12:00:00", appFilter, highlight: null, classify, capacity: 30 });
  const all = make(null);
  assert.deepEqual(plain(all.events.map((e) => e.app)), ["com.firefox", "com.firefox", "com.firefox", "com.ghostty", "com.ghostty", "com.ghostty", "com.ghostty"]);
  assert.deepEqual(plain(all.apps), [{ app: "com.ghostty", count: 4 }, { app: "com.firefox", count: 3 }]);
  assert.equal(all.activity.total, 7);
  assert.equal(all.activity.groupTotals.pointer, 3);
  assert.equal(all.activity.groupTotals.navigate, 3);
  assert.equal(all.activity.groupTotals.windows, 1);
  assert.deepEqual(plain(all.sequences.map((s) => [s.from, s.to, s.count])), [["v q", "v u", 3]]);
  assert.ok(all.segments.some((s) => s.state === "locked" && s.from === 37800 && s.to === 38100));
  const ghostty = make("com.ghostty");
  assert.equal(ghostty.events.length, 4);
  assert.equal(ghostty.activity.total, 4);
  assert.deepEqual(plain(ghostty.sequences), [], "only two pairs happened in that app: below the threshold");
  assert.deepEqual(plain(ghostty.apps), plain(all.apps), "the app list always shows the whole day");
  // Without context: no apps, no shading.
  const bare = M.buildDay({ usage, context: null, date: "2026-10-16", now: "2026-10-16T12:00:00", appFilter: null, highlight: null, classify, capacity: 30 });
  assert.equal(bare.segments, null);
  assert.deepEqual(plain(bare.apps), []);
  assert.ok(bare.events.every((e) => e.app === null));
});

test("the day view's dot counts agree with the month view's bins for the same events", () => {
  const text = syntheticLog(600, 33);
  const store = fresh(text, FUTURE_NOW);
  const classify = M.classifier([]);
  const month = M.buildActivityFromCombos(store.binsOf("2026-10"), classify, null, 30);
  const days = store.dayList().filter((d) => d.startsWith("2026-10"));
  const sum = new Array(48).fill(0);
  for (const date of days) {
    const day = M.buildDay({ usage: store, context: null, date, now: FUTURE_NOW, appFilter: null, highlight: null, classify, capacity: 30 });
    day.activity.all.forEach((n, bin) => { sum[bin] += n; });
  }
  assert.deepEqual(sum, plain(month.all));
});

test("context stream protocol: its own generation and offset, rejections apply nothing", () => {
  const usage = M.createSession();
  const contextSession = M.createSession(M.createContextStore);
  const first = `${ctxLine("2026-10-16T09:00:00.000", "start")}\n${ctxLine("2026-10-16T09:00:05.000", "app", "com.a")}\n`;
  const second = `${ctxLine("2026-10-16T09:10:00.000", "app", "com.b")}\n`;
  usage.reset({ generation: 7, text: "", offset: 0 }, NOW);
  assert.deepEqual(plain(contextSession.reset({ generation: 1, text: first, offset: first.length }, NOW)), { ok: true, generation: 1, offset: first.length });
  assert.equal(contextSession.generation, 1);
  assert.equal(usage.generation, 7, "the usage stream is untouched");
  const ok = { generation: 1, from: first.length, to: first.length + second.length, text: second };
  assert.equal(contextSession.append({ ...ok, generation: 2 }, NOW).reason, "generation");
  assert.equal(contextSession.append({ ...ok, from: first.length + 3 }, NOW).reason, "gap");
  assert.equal(contextSession.append({ ...ok, from: 0, to: first.length }, NOW).reason, "duplicate");
  assert.equal(contextSession.append({ ...ok, text: 4 }, NOW).reason, "invalid");
  assert.equal(contextSession.store.summary().count, 2, "rejected appends change nothing");
  assert.deepEqual(plain(contextSession.append(ok, NOW)), { ok: true, offset: first.length + second.length });
  assert.equal(contextSession.append(ok, NOW).reason, "duplicate");
  assert.equal(contextSession.store.appAt("2026-10-16T09:11:00"), "com.b");
  // Incremental delivery equals one full load, at every line boundary.
  const full = contextFrom((first + second).trim().split("\n")).snapshot();
  assert.deepEqual(contextSession.store.snapshot(), full);
  for (const cut of [0, first.indexOf("\n") + 1, first.length]) {
    const part = M.createSession(M.createContextStore);
    part.reset({ generation: 1, text: (first + second).slice(0, cut), offset: cut }, NOW);
    part.append({ generation: 1, from: cut, to: (first + second).length, text: (first + second).slice(cut) }, NOW);
    assert.deepEqual(part.store.snapshot(), full, `cut ${cut}`);
  }
  // A reset discards earlier events and takes the new generation.
  assert.equal(contextSession.reset({ generation: 2, text: "", offset: 0 }, NOW).ok, true);
  assert.equal(contextSession.store.summary().count, 0);
  assert.equal(contextSession.append(ok, NOW).reason, "generation");
});

test("health.context: disabled reads as 'App context off'; missing and unreadable warn", () => {
  assert.equal(M.normalizeHealth({ context: { status: "ok", bytes: 10, modified: NOW } }).context.status, "ok");
  const off = M.describeHealth({ health: { log: { status: "ok" }, context: { status: "disabled" } }, lastEvent: "2026-10-15T14:02:00", rejected: 0, now: NOW });
  assert.equal(off.text, "LOG OK · LAST 14:02 · CONTEXT OFF");
  assert.match(off.full, /APP CONTEXT OFF/, "the tooltip says App context off in full");
  assert.equal(off.level, "ok");
  assert.match(M.describeHealth({ health: { context: { status: "ok" } }, lastEvent: null, rejected: 0, now: NOW }).full, /APP CONTEXT OK/);
  const missing = M.describeHealth({ health: { context: { status: "missing" } }, lastEvent: null, rejected: 0, now: NOW });
  assert.match(missing.text, /CONTEXT LOG MISSING/);
  assert.equal(missing.level, "warn");
  assert.equal(M.describeHealth({ health: { context: { status: "unreadable" } }, lastEvent: null, rejected: 0, now: NOW }).level, "warn");
  const store = M.createStore();
  const lines = M.aboutLines({ health: { context: { status: "ok" } }, insights: null, summary: store.summary(), now: NOW });
  assert.ok(lines.some((l) => /1 s resolution/.test(l)), "the resolution limit is stated");
  assert.ok(M.aboutLines({ health: { context: { status: "disabled" } }, insights: null, summary: store.summary(), now: NOW }).includes("App context is off"));
});

test("routeKey: the Activity day view walks days, Enter switches views, Escape clears an interval first", () => {
  const day = { page: "activity", layer: null, highlight: null, selected: null, aboutOpen: false, layers: ["w", "v"], heatHas: () => false, activityMode: "day", interval: null };
  assert.deepEqual(plain(M.routeKey(day, { key: "ArrowLeft" })), { type: "day", step: -1 });
  assert.deepEqual(plain(M.routeKey(day, { key: "ArrowRight" })), { type: "day", step: 1 });
  assert.deepEqual(plain(M.routeKey(day, { key: "ArrowLeft", shiftKey: true })), { type: "day", step: -7 });
  assert.deepEqual(plain(M.routeKey(day, { key: "Enter" })), { type: "toggleMode" });
  assert.deepEqual(plain(M.routeKey(day, { key: "Home" })), { type: "today" });
  assert.deepEqual(plain(M.routeKey(day, { key: "w" })), { type: "highlight", layer: "w" });
  assert.deepEqual(plain(M.routeKey({ ...day, interval: 26 }, { key: "Escape" })), { type: "clearInterval" });
  assert.deepEqual(plain(M.routeKey({ ...day, interval: 26, highlight: "w" }, { key: "Escape" })), { type: "highlight", layer: "w" }, "a highlight clears first");
  assert.deepEqual(plain(M.routeKey(day, { key: "Escape" })), { type: "back" });
  // Month view keeps the old arrows.
  const month = { ...day, activityMode: "month" };
  assert.deepEqual(plain(M.routeKey(month, { key: "ArrowLeft" })), { type: "month", step: -1 });
  assert.deepEqual(plain(M.routeKey(month, { key: "ArrowRight", shiftKey: true })), { type: "month", step: 1 });
  assert.deepEqual(plain(M.routeKey(month, { key: "Enter" })), { type: "toggleMode" });
  // Enter on a focused control still belongs to the control.
  assert.equal(M.routeKey({ ...day, controlFocused: true }, { key: "Enter" }), null);
});

test("insights: version 3 dates and app ride along; version 2 still loads", () => {
  const v3 = plain(M.normalizeInsights({ version: 3, generated: NOW, month: "2026-10", recordingSince: null, rejectedLines: 0,
    insights: [{ kind: "burst", title: "Reading bursts", detail: "d", keys: [], value: 3, dates: ["2026-10-14"], app: "org.mozilla.firefox" }] }));
  assert.deepEqual(v3.insights[0].dates, ["2026-10-14"]);
  assert.equal(v3.insights[0].app, "org.mozilla.firefox");
  assert.equal(M.normalizeInsights({ version: 2, insights: [{ kind: "peak", title: "t", detail: "d" }] }).insights.length, 1);
  assert.equal(M.normalizeInsights({ version: 1, insights: [] }), null);
});

test("describeHealth: the healthy line is short enough for one line; warnings and errors keep every word", () => {
  // The card fits about 55 characters of the status font.
  const worst = M.describeHealth({
    health: { log: { status: "ok" }, bindings: { status: "ok" }, insights: { status: "running" }, context: { status: "disabled" } },
    lastEvent: "2026-10-12T14:02:00", rejected: 0, now: NOW,
  });
  assert.equal(worst.level, "ok");
  assert.ok(worst.text.length <= 55, `${worst.text.length}: ${worst.text}`);
  const stale = M.describeHealth({ health: { log: { status: "ok" }, insights: { status: "stale" }, context: { status: "ok" } }, lastEvent: "2026-10-15T14:02:00", rejected: 0, now: NOW });
  assert.equal(stale.level, "warn");
  assert.equal(stale.compact, false);
  assert.equal(stale.text, "LOG OK · LAST PRESS 14:02 · ANALYSIS STALE · APP CONTEXT OK");
  const broken = M.describeHealth({ health: { log: { status: "unreadable" }, bindings: { status: "invalid" }, insights: { status: "failed" } }, lastEvent: null, rejected: 2, now: NOW });
  assert.equal(broken.level, "error");
  assert.equal(broken.text, "LOG UNREADABLE · 2 BAD LINES · BINDINGS INVALID · RUN YARN BUILD · ANALYSIS FAILED");
  assert.equal(broken.full, broken.text, "an error's tooltip and text are the same full wording");
});

// ---------------------------------------------------------------------------------------------
// Themes

test("themes: the order T cycles through, the fallback, and the wrap-around", () => {
  assert.deepEqual(plain(M.THEMES), ["manila", "kozo", "nightingale", "blueprint"]);
  assert.equal(M.nextTheme("manila"), "kozo");
  assert.equal(M.nextTheme("kozo"), "nightingale");
  assert.equal(M.nextTheme("nightingale"), "blueprint");
  assert.equal(M.nextTheme("blueprint"), "manila", "wraps back to the default");
  assert.equal(M.nextTheme("nonsense"), "kozo", "an unknown name counts as manila");
  assert.equal(M.nextTheme(undefined), "kozo");
  for (const name of M.THEMES) assert.equal(M.normalizeTheme(name), name);
  for (const bad of ["", "Manila", "dark", "light", null, undefined, 3, {}, "kozo "]) assert.equal(M.normalizeTheme(bad), "manila", String(bad));
  // Four steps from any theme return to it.
  for (const start of M.THEMES) { let name = start; for (let i = 0; i < 4; i++) name = M.nextTheme(name); assert.equal(name, start); }
});

test("routeKey: T cycles the theme on the overview only", () => {
  const overview = { page: null, layer: null, highlight: null, selected: null, aboutOpen: false, layers: ["w", "o"], heatHas: (k) => k === "w" || k === "o" };
  assert.deepEqual(plain(M.routeKey(overview, { key: "t" })), { type: "cycleTheme" });
  assert.deepEqual(plain(M.routeKey(overview, { key: "T", shiftKey: true })), { type: "cycleTheme" });
  // Not on a layer page (T selects the T binding), the Activity page or the Insights page.
  assert.deepEqual(plain(M.routeKey({ ...overview, layer: "w" }, { key: "t" })), { type: "select", key: "t" });
  assert.deepEqual(plain(M.routeKey({ ...overview, page: "activity" }, { key: "t" })), { type: "ignore" });
  assert.equal(M.routeKey({ ...overview, page: "insights" }, { key: "t" }), null);
  // A layer called t would win, as with every other letter.
  assert.deepEqual(plain(M.routeKey({ ...overview, heatHas: (k) => k === "t" }, { key: "t" })), { type: "openLayer", layer: "t" });
  // Not with a modifier.
  assert.equal(M.routeKey(overview, { key: "t", metaKey: true }), null);
});

test("every theme defines every colour token, and every colour the page uses exists in all of them", () => {
  const css = /<style>([\s\S]*?)<\/style>/.exec(html)[1];
  const themeBlocks = {};
  for (const m of css.matchAll(/(?::root,\s*)?:root\[data-theme="(\w+)"\]\s*\{([\s\S]*?)\n  \}/g)) themeBlocks[m[1]] = m[2];
  assert.deepEqual(Object.keys(themeBlocks).sort(), [...M.THEMES].sort());
  const defined = (block) => new Set([...block.matchAll(/--([a-z0-9-]+):/g)].map((x) => x[1]));
  const manila = defined(themeBlocks.manila);
  assert.ok(manila.size > 40, `manila defines ${manila.size} tokens`);
  for (const name of M.THEMES) {
    const own = defined(themeBlocks[name]);
    assert.deepEqual([...manila].filter((t) => !own.has(t)), [], `${name} is missing tokens`);
    assert.deepEqual([...own].filter((t) => !manila.has(t)), [], `${name} has extra tokens`);
  }
  // Every var(--x) in the page resolves, either from a theme, the shared :root block (type and layout), or a local variable.
  const shared = defined(/\n  :root \{([\s\S]*?)\n  \}/.exec(css)[1]);
  assert.ok(["sans", "mono", "key", "gap"].every((t) => shared.has(t)), "the shared :root block was not found");
  const local = new Set(["grp", "grp-bg", "tone", "tone-bg"]);
  const used = new Set([...html.matchAll(/var\(--([a-z0-9-]+)/g)].map((x) => x[1]));
  for (const token of used) assert.ok(manila.has(token) || shared.has(token) || local.has(token) || /^g-/.test(token), `--${token} is undefined`);
  // No raw colours outside the theme blocks.
  const rest = css.replace(/:root[^{]*\{[\s\S]*?\n  \}/g, "");
  assert.deepEqual(rest.match(/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|oklch\(/g), null, "raw colours outside the theme blocks");
  assert.deepEqual([...html.slice(html.indexOf("<script>")).matchAll(/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|oklch\(/g)].map((x) => x[0]), [], "raw colours in the page script");
});

test("the status line: up to three problems fit its two reserved lines (about 105 characters at the card width); more are clamped, with the full text in the tooltip", () => {
  const combos = [
    { health: { log: { status: "unreadable" }, bindings: { status: "invalid" }, insights: { status: "failed" }, context: { status: "ok" } }, rejected: 12 },
    { health: { log: { status: "missing" }, bindings: { status: "missing" }, insights: { status: "missing-tool" }, context: { status: "disabled" } }, rejected: 0 },
    { health: { log: { status: "ok" }, bindings: { status: "invalid" }, insights: { status: "stale" }, context: { status: "ok" } }, rejected: 0 },
    { health: { log: { status: "unreadable" }, bindings: { status: "ok" }, insights: { status: "failed" }, context: { status: "missing" } }, rejected: 0 },
  ];
  for (const { health, rejected } of combos) {
    const line = M.describeHealth({ health, lastEvent: "2026-10-12T14:02:00", rejected, now: NOW });
    assert.ok(line.text.length <= 105, `${line.text.length}: ${line.text}`);
  }
});

test("aboutLines ends with the full status text, because the status line is clamped to two lines", () => {
  const store = M.createStore();
  const health = { log: { status: "unreadable" }, bindings: { status: "invalid" }, insights: { status: "failed" }, context: { status: "missing" } };
  const status = M.describeHealth({ health, lastEvent: null, rejected: 3, now: NOW });
  const lines = M.aboutLines({ health, insights: null, summary: store.summary(), now: NOW, statusText: status.full });
  assert.equal(lines.at(-1), `Status: ${status.full}`);
  assert.match(lines.at(-1), /CONTEXT LOG MISSING/, "the part a two-line clamp would cut is present");
  assert.ok(!M.aboutLines({ health: null, insights: null, summary: store.summary(), now: NOW }).some((l) => l.startsWith("Status:")), "no status text, no line");
});

test("fadeState: an edge fades only where content continues past it", () => {
  assert.equal(M.fadeState({ scrollTop: 0, clientHeight: 240, scrollHeight: 240 }), "none", "content that fits");
  assert.equal(M.fadeState({ scrollTop: 0, clientHeight: 240, scrollHeight: 600 }), "bottom", "at the top");
  assert.equal(M.fadeState({ scrollTop: 100, clientHeight: 240, scrollHeight: 600 }), "both", "in the middle");
  assert.equal(M.fadeState({ scrollTop: 360, clientHeight: 240, scrollHeight: 600 }), "top", "at the bottom");
  assert.equal(M.fadeState({ scrollTop: 0.4, clientHeight: 240, scrollHeight: 600 }), "bottom", "sub-pixel scroll counts as the top");
  assert.equal(M.fadeState({ scrollTop: 359.2, clientHeight: 240, scrollHeight: 600 }), "top", "a pixel short of the end counts as the end");
  assert.equal(M.fadeState({ scrollTop: 0, clientHeight: 240, scrollHeight: 241 }), "none", "one pixel of overflow is not worth a fade");
  assert.equal(M.fadeState({ scrollTop: 0, clientHeight: 0, scrollHeight: 0 }), "none", "a hidden area");
});
