// Run with: node --test karabiner/hyperdash/tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const block = /<script id="hyperdash-model">([\s\S]*?)<\/script>/.exec(html);
assert.ok(block, "index.html has no #hyperdash-model script");
const context = vm.createContext({});
vm.runInContext(block[1], context);
const M = context.HyperdashModel;

// Values built inside the vm have another realm's prototypes; compare them as plain JSON.
const plain = (value) => JSON.parse(JSON.stringify(value));

const NOW = "2026-10-15T15:00:00";
const line = (time, layer, key) => `${time}\t${layer}\t${key}`;

test("parseLog: shared fixture lines match the Swift ParsingTests", () => {
  // Same lines as InsightsTests.swift skipsMalformedLines.
  const result = M.parseLog([
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
  const result = M.parseLog([
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
  const result = M.parseLog(bad.join("\n"), NOW);
  assert.equal(result.presses.length, 0);
  assert.equal(result.rejected, bad.length);

  const good = M.parseLog([
    line("2024-02-29T12:00:00", "w", "up_arrow"),
    line("2026-10-15T14:36:07", "o", "1"),
  ].join("\n"), NOW);
  assert.equal(good.presses.length, 2);
  assert.equal(good.rejected, 0);
});

test("parseLog: blank lines are skipped, CRLF is accepted", () => {
  const text = `${line("2026-10-15T09:00:00", "w", "u")}\r\n\r\n\n${line("2026-10-15T09:01:00", "w", "u")}\r\n`;
  const result = M.parseLog(text, NOW);
  assert.equal(result.presses.length, 2);
  assert.equal(result.rejected, 0);
});

test("parseLog: events after now are ignored, not rejected", () => {
  const result = M.parseLog([
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
  const result = M.parseLog([
    line("2026-10-15T12:00:00", "w", "u"),
    line("2026-10-10T08:00:00", "w", "u"),
    line("2026-10-15T09:00:00", "o", "t"),
  ].join("\n"), NOW);
  assert.equal(result.lastUsed["w u"], "2026-10-15T12:00:00");
  assert.equal(result.firstEvent, "2026-10-10T08:00:00");
  assert.equal(result.lastEvent, "2026-10-15T12:00:00");
});

test("parseLog: half-hour bins and months", () => {
  const result = M.parseLog([line("2026-10-15T14:29:59", "w", "u"), line("2026-10-15T14:30:00", "w", "u")].join("\n"), NOW);
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
  assert.deepEqual(plain(M.listMonths(presses, NOW)).slice(0, 3), ["2025-11", "2025-12", "2026-01"]);
  assert.equal(M.listMonths(presses, NOW).at(-1), "2026-10");
  assert.deepEqual(plain(M.listMonths([], NOW)), ["2026-10"]);
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
  const counts = M.countCombos(presses, "2026-10");
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
  const a = M.buildActivity(presses, "2026-10", "w", 30);
  assert.equal(a.total, 4);
  assert.equal(a.hitTotal, 2);
  assert.equal(a.peakHour, 14);
  assert.equal(a.perDot, 1);
  assert.equal(M.describeBin(a, 28), "14:00–14:30 · 3 presses · WINDOW 2 · MOVE 1");
  assert.equal(M.describeBin(a, 29), "14:30–15:00 · 1 press · LAUNCH 1");
  const dense = M.buildActivity(Array(95).fill({ month: "2026-10", layer: "w", key: "u", bin: 5 }), "2026-10", null, 30);
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
  const parsed = M.parseLog(line("2026-10-15T09:00:00", "w", "u") + "\njunk", NOW);
  const lines = M.aboutLines({
    health: { log: { status: "ok", bytes: 2048 }, insights: { status: "stale", message: "older than 1h" } },
    insights: { recordingSince: "2026-10-14T13:06:00" },
    parsed,
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
  const counts = M.countCombos(presses, "2026-10");
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
