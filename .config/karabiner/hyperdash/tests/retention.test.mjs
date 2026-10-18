// Run with: node --test karabiner/hyperdash/tests/retention.test.mjs
// Retention (docs/RETENTION.md): the page loaded from the manifest's summary plus the tail must show the
// same numbers as the page loaded from the whole log. The fixture in retention_cases/ is shared with the
// Swift tests (RetentionTests.swift), which check that the tool writes exactly this retention.json.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const block = /<script id="hyperdash-model">([\s\S]*?)<\/script>/.exec(html);
const context = vm.createContext({});
vm.runInContext(block[1], context);
const M = context.HyperdashModel;
const plain = (value) => JSON.parse(JSON.stringify(value));

const NOW = "2026-10-17T18:00:00";
const fixture = (name) => readFileSync(new URL(`./retention_cases/${name}`, import.meta.url));
const usage = fixture("usage.log");
const contextLog = fixture("context.log");
// The manifest is two lines: the header with the cuts, then the summary the page receives as `archive`.
const [header, summary] = fixture("retention.json").toString("utf8").trim().split("\n").map((line) => JSON.parse(line));
const manifest = { ...header, archive: summary };
const bindings = M.normalizeBindings(JSON.parse(fixture("bindings.json").toString("utf8")));
const classify = M.classifier(bindings);
const CAPACITY = 9;

// What the host sends: complete lines only, from `from`, with the absolute offset.
function reset(bytes, from, extra = {}) {
  const end = bytes.lastIndexOf(10) + 1;
  return { generation: 1, text: bytes.subarray(from, end).toString("utf8"), offset: end, ...extra };
}

function load(cut) {
  const usageSession = M.createSession();
  const contextSession = M.createSession(M.createContextStore);
  const a = usageSession.reset(reset(usage, cut ? manifest.usage.offset : 0, cut ? { archive: summary } : {}), NOW);
  const b = contextSession.reset({ stream: "context", ...reset(contextLog, cut ? manifest.context.offset : 0) }, NOW);
  assert.ok(a.ok && b.ok, JSON.stringify([a, b]));
  return { store: usageSession.store, context: contextSession.store, session: usageSession };
}

const full = load(false);
const cut = load(true);
const tailDate = manifest.tailStart.slice(0, 10);

test("retention: the cut load really skips the archived bytes", () => {
  assert.ok(manifest.usage.offset > 0 && manifest.context.offset > 0);
  assert.ok(cut.store.dayEvents("2026-07-20").length === 0 && full.store.dayEvents("2026-07-20").length > 0);
  assert.equal(cut.session.offset, full.session.offset, "the page offset is absolute in both");
});

test("retention: summary, months, layers and days agree", () => {
  assert.deepEqual(plain(cut.store.summary()), plain(full.store.summary()));
  assert.deepEqual(plain(cut.store.months(NOW)), plain(full.store.months(NOW)));
  assert.deepEqual(plain(cut.store.layerList().sort()), plain(full.store.layerList().sort()));
  assert.deepEqual(plain(cut.store.dayList()), plain(full.store.dayList()));
});

test("retention: Overview and Layer views agree for every month and layer", () => {
  const layers = [null, ...full.store.layerList().sort()];
  for (const month of full.store.months(NOW)) {
    assert.deepEqual(plain(cut.store.countsOf(month)), plain(full.store.countsOf(month)), month);
    for (const layer of layers) {
      const rows = (s) => plain(M.buildRows(bindings, s.store.countsOf(month), layer));
      assert.deepEqual(rows(cut), rows(full), `${month} ${layer}`);
      const total = (s) => M.sumCounts(s.store.countsOf(month), layer);
      const previous = (s) => M.sumCounts(s.store.countsOf(M.previousMonth(month)), layer);
      const compare = (s) => plain(M.compareMonths({ month, total: total(s), previousTotal: previous(s), firstEvent: s.store.summary().firstEvent, now: NOW }));
      assert.deepEqual(compare(cut), compare(full), `${month} ${layer} comparison`);
    }
  }
  for (const id of Object.keys(full.store.countsOf("2026-08")).concat(Object.keys(full.store.countsOf("2026-10")))) {
    assert.equal(cut.store.lastUsedOf(id), full.store.lastUsedOf(id), id);
  }
});

test("retention: Activity month agrees for every month and highlight", () => {
  for (const month of full.store.months(NOW)) {
    for (const highlight of [null, ...full.store.layerList().sort()]) {
      const build = (s) => plain(M.buildActivityFromCombos(s.store.binsOf(month), classify, highlight, CAPACITY));
      assert.deepEqual(build(cut), build(full), `${month} ${highlight}`);
    }
  }
});

test("retention: Activity day agrees in full from the tail start, in counts before it", () => {
  const days = full.store.dayList();
  let exact = 0;
  let counted = 0;
  for (let date = days[0]; date <= NOW.slice(0, 10); date = M.addDays(date, 1)) {
    for (const highlight of [null, "w", "o"]) {
      const build = (s, appFilter) => plain(M.buildDay({ usage: s.store, context: s.context, date, now: NOW, appFilter, highlight, classify, capacity: CAPACITY }));
      if (date >= tailDate) {
        for (const app of [null, "com.mitchellh.ghostty", "com.google.Chrome", "com.apple.finder"]) {
          assert.deepEqual(build(cut, app), build(full, app), `${date} ${highlight} ${app}`);
        }
        exact += 1;
      } else {
        const day = build(cut, null);
        assert.equal(day.archived, true, date);
        assert.deepEqual(day.activity, build(full, null).activity, `${date} ${highlight} chart`);
        counted += 1;
      }
    }
  }
  assert.ok(exact > 0 && counted > 0, `${exact} exact, ${counted} counted`);
});

test("retention: an archived day with a raw event counts both", () => {
  // The fixture has a July line written in October, so 2026-07-25 has archived counts and one raw event.
  assert.ok(cut.store.dayEvents("2026-07-25").length === 1);
  const chart = (s) => plain(M.buildDay({ usage: s.store, context: s.context, date: "2026-07-25", now: NOW, appFilter: null, highlight: null, classify, capacity: CAPACITY }).activity);
  assert.deepEqual(chart(cut), chart(full));
});

test("retention: the about lines and a later tick agree", () => {
  const about = (s) => plain(M.aboutLines({ health: null, insights: null, summary: s.store.summary(), now: NOW, statusText: "" }));
  assert.deepEqual(about(cut), about(full));
  const later = "2026-10-21T00:00:00";
  assert.equal(cut.store.tick(later), full.store.tick(later));
  assert.deepEqual(plain(cut.store.countsOf("2026-10")), plain(full.store.countsOf("2026-10")));
});

test("retention: appends after a cut reset go on from the absolute offset", () => {
  const s = M.createSession();
  const data = reset(usage, manifest.usage.offset, { archive: summary });
  s.reset(data, NOW);
  const text = "2026-10-17T17:59:59\tw\tu\n";
  assert.deepEqual(plain(s.append({ generation: 1, from: data.offset, to: data.offset + text.length, text }, NOW)), { ok: true, offset: data.offset + text.length });
  assert.equal(s.append({ generation: 1, from: 0, to: 5, text: "" }, NOW).reason, "duplicate");
});

test("retention: a summary that fails the checks is refused, and the page holds nothing", () => {
  const broken = [
    { ...summary, tailStart: "2026-09-02T00:00:00" },
    { ...summary, tailStart: undefined },
    { ...summary, count: summary.count + 1 },
    { ...summary, days: { "2026-08-01": { "w u": [48, 1] } }, count: 1 },
    { ...summary, days: { "2026-08-01": { "w u": [3, 1, 2, 1] } }, count: 2 },
    { ...summary, days: { "2026-08-01": { "W u": [3, 1] } }, count: 1 },
    { ...summary, lastUsed: { "w u": "yesterday" } },
    { ...summary, rejected: -1 },
    "text",
  ];
  for (const archive of broken) {
    const s = M.createSession();
    const result = s.reset(reset(usage, manifest.usage.offset, { archive }), NOW);
    assert.deepEqual(plain(result), { ok: false, reason: "archive", offset: 0 }, JSON.stringify(archive).slice(0, 80));
    assert.equal(s.store.summary().count, 0);
  }
  const s = M.createSession();
  assert.equal(s.reset(reset(usage, 0, { archive: null }), NOW).ok, true, "null means no summary");
  assert.deepEqual(plain(s.store.summary()), plain(load(false).store.summary()));
});
