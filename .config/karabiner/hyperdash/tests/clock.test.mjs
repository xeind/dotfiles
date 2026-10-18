// Run with: node --test karabiner/hyperdash/tests/clock.test.mjs
// Daylight saving time and the model's clock. Log stamps are local wall-clock strings with no offset, and
// the model counts them as UTC seconds (absSeconds), so a day is always 24 hours on its axis. These tests
// set TZ in the test process; page-level rollover and DST tests are in bugs.test.mjs.
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
const plain = (value) => JSON.parse(JSON.stringify(value));

// Runs `body` with the process in `zone`, then restores the earlier zone.
function inZone(zone, body) {
  const before = process.env.TZ;
  process.env.TZ = zone;
  try { return body(); } finally { if (before === undefined) delete process.env.TZ; else process.env.TZ = before; }
}

const press = (stamp) => `${stamp}\tw\tu`;
const ctx = (stamp, kind, value = "-") => `${stamp}\t${kind}\t${value}`;
const contextFrom = (lines) => { const store = M.createContextStore(); store.reset(lines.join("\n") + "\n"); return store; };

// [zone, fall-back day, spring-forward day, first wall-clock minute that does not exist on the spring day]
const ZONES = [
  ["America/New_York", "2026-11-01", "2026-03-08", "02:30"],
  ["Europe/London", "2026-10-25", "2026-03-29", "01:30"],
  ["Australia/Sydney", "2026-04-05", "2026-10-04", "02:30"],
  ["Australia/Lord_Howe", "2026-04-05", "2026-10-04", "02:15"],
];

test("zones: the test process really changes zone", () => {
  const offset = (zone) => inZone(zone, () => new Date(2026, 6, 1, 12).getTimezoneOffset());
  assert.equal(offset("America/New_York"), 240);
  assert.equal(offset("Europe/London"), -60);
  assert.equal(offset("Australia/Lord_Howe"), -630);
});

test("daylight saving: a day is 86400 s on the model's axis, and date steps ignore the zone", () => {
  for (const [zone, fall, spring] of ZONES) {
    inZone(zone, () => {
      for (const day of [fall, spring]) {
        const next = M.addDays(day, 1);
        assert.equal(M.absSeconds(`${next}T00:00:00`) - M.absSeconds(`${day}T00:00:00`), 86400, `${zone} ${day}`);
        assert.equal(M.addDays(next, -1), day, `${zone} ${day}`);
        assert.equal(M.dateOf(`${day}T23:59:59`), day, `${zone} ${day}`);
      }
      // localStamp reads the wall clock, whatever the offset.
      assert.equal(M.localStamp(new Date(2026, 6, 1, 0, 0, 1)), "2026-07-01T00:00:01", zone);
    });
  }
});

test("daylight saving: a wall-clock time the spring jump skips is rejected, its neighbours are not", () => {
  for (const [zone, , spring, skipped] of ZONES) {
    inZone(zone, () => {
      assert.equal(M.isValidTimestamp(`${spring}T${skipped}:00`), false, `${zone} ${spring} ${skipped}`);
      assert.equal(M.isValidTimestamp(`${spring}T00:00:00`), true, zone);
      assert.equal(M.isValidTimestamp(`${spring}T23:59:59`), true, zone);
    });
  }
  inZone("America/New_York", () => {
    assert.equal(M.isValidTimestamp("2026-03-08T01:59:59"), true);
    assert.equal(M.isValidTimestamp("2026-03-08T03:00:00"), true);
    const store = M.createStore();
    store.reset([press("2026-03-08T01:59:59"), press("2026-03-08T02:30:00"), press("2026-03-08T03:00:00")].join("\n") + "\n", "2026-03-08T12:00:00");
    assert.deepEqual(plain({ count: store.summary().count, rejected: store.summary().rejected }), { count: 2, rejected: 1 });
    assert.deepEqual(plain(store.dayEvents("2026-03-08").map((e) => e.sec)), [7199, 10800]);
    const bins = store.binsOf("2026-03")["w u"];
    assert.equal(bins[2] + bins[3], 1, "01:59 is in the 01:30 bin");
    assert.equal(bins[4] + bins[5], 0, "the skipped hour has no bin entries");
    assert.equal(bins[6], 1, "03:00 is in the 03:00 bin");
    const recorder = contextFrom([ctx("2026-03-08T01:30:00.000", "start"), ctx("2026-03-08T02:30:00.000", "app", "com.x"), ctx("2026-03-08T03:10:00.500", "app", "com.y")]);
    assert.equal(recorder.summary().rejected, 1);
  });
});

test("daylight saving, spring: a session across the jump stays one recorded stretch, and the strip ends at 24 h", () => {
  inZone("America/New_York", () => {
    const store = contextFrom([
      ctx("2026-03-08T01:30:00.000", "start"),
      ctx("2026-03-08T03:10:00.500", "app", "com.y"),
      ctx("2026-03-08T12:00:00.000", "app", "com.z"),
    ]);
    const spans = plain(store.sessions("2026-03-09T00:00:00")).map((s) => [s.start, s.end]);
    assert.deepEqual(spans, [[M.absSeconds("2026-03-08T01:30:00"), M.absSeconds("2026-03-09T00:00:00")]]);
    const day = plain(store.segments("2026-03-08", "2026-03-09T00:00:00"));
    assert.deepEqual(day, [{ from: 0, to: 5400, state: "unknown" }, { from: 5400, to: 86400, state: "recorded" }]);
  });
});

test("daylight saving, fall back: both passes of the repeated hour count, in wall-clock order", () => {
  inZone("America/New_York", () => {
    // 01:10 and 01:50 are EDT (first pass); 01:05 and 01:20 are EST (second pass). The log is in arrival order.
    const store = M.createStore();
    const lines = ["2026-11-01T00:30:00", "2026-11-01T01:10:00", "2026-11-01T01:50:00", "2026-11-01T01:05:00", "2026-11-01T01:20:00", "2026-11-01T02:10:00"].map(press);
    store.reset(lines.join("\n") + "\n", "2026-11-01T12:00:00");
    assert.equal(store.summary().count, 6);
    assert.equal(store.summary().rejected, 0);
    assert.deepEqual(plain(store.dayEvents("2026-11-01").map((e) => e.sec / 60)), [30, 65, 70, 80, 110, 130]);
    const bins = store.binsOf("2026-11")["w u"];
    assert.deepEqual(plain([bins[0], bins[1], bins[2], bins[3], bins[4]]), [0, 1, 3, 1, 1], "01:00 to 01:59 holds both passes");
    assert.equal(M.dateOf("2026-11-01T01:20:00"), "2026-11-01", "today stays the same date through the repeat");
    assert.deepEqual(plain(store.months("2026-11-01T01:20:00")), ["2026-11"]);
  });
});

test("daylight saving, fall back: a first-pass press that the second-pass clock has not reached waits, then shows", () => {
  inZone("America/New_York", () => {
    // At 01:20 EST the 01:50 EDT press is stamped later than now: it waits, as any future-dated line does.
    const store = M.createStore();
    store.reset([press("2026-11-01T01:10:00"), press("2026-11-01T01:50:00")].join("\n") + "\n", "2026-11-01T01:20:00");
    assert.deepEqual(plain({ count: store.summary().count, pending: store.summary().pending }), { count: 1, pending: 1 });
    assert.equal(store.tick("2026-11-01T01:49:59"), 0);
    assert.equal(store.tick("2026-11-01T01:50:00"), 1);
    assert.deepEqual(plain({ count: store.summary().count, pending: store.summary().pending }), { count: 2, pending: 0 });
    assert.equal(store.dayEvents("2026-11-01").length, 2);
  });
});

test("daylight saving, fall back: a session that runs through the repeated hour has no hole in the strip", () => {
  inZone("America/New_York", () => {
    const store = contextFrom([
      ctx("2026-11-01T00:00:00.000", "start"),
      ctx("2026-11-01T01:00:00.500", "app", "com.a"),
      ctx("2026-11-01T01:40:00.500", "app", "com.b"),
      ctx("2026-11-01T01:10:00.500", "app", "com.c"), // second pass
      ctx("2026-11-01T01:50:00.500", "app", "com.a"),
      ctx("2026-11-01T02:20:00.500", "app", "com.b"),
      ctx("2026-11-01T03:00:00.500", "lock"),
      ctx("2026-11-01T03:10:00.500", "unlock"),
    ]);
    const now = "2026-11-01T12:00:00";
    assert.deepEqual(plain(store.sessions(now)).map((s) => [s.start, s.end]), [[M.absSeconds("2026-11-01T00:00:00"), M.absSeconds(now)]]);
    assert.deepEqual(plain(store.segments("2026-11-01", now)), [
      { from: 0, to: 10801, state: "recorded" },
      { from: 10801, to: 11401, state: "locked" },
      { from: 11401, to: 43200, state: "recorded" },
    ]);
    // Append the second pass after the first: the same answer as loading the whole log at once.
    const grown = contextFrom([ctx("2026-11-01T00:00:00.000", "start"), ctx("2026-11-01T01:40:00.500", "app", "com.b")]);
    grown.append([ctx("2026-11-01T01:10:00.500", "app", "com.c"), ctx("2026-11-01T02:20:00.500", "app", "com.b"), ""].join("\n"));
    const whole = contextFrom([ctx("2026-11-01T00:00:00.000", "start"), ctx("2026-11-01T01:40:00.500", "app", "com.b"), ctx("2026-11-01T01:10:00.500", "app", "com.c"), ctx("2026-11-01T02:20:00.500", "app", "com.b")]);
    assert.deepEqual(plain(grown.sessions(now)), plain(whole.sessions(now)));
    assert.deepEqual(plain(grown.segments("2026-11-01", now)), plain(whole.segments("2026-11-01", now)));
  });
});

test("clock: a tick across midnight promotes a line stamped just after it, and the new day and month appear", () => {
  const store = M.createStore();
  store.reset([press("2026-10-31T23:58:00"), press("2026-11-01T00:00:10")].join("\n") + "\n", "2026-10-31T23:59:58");
  assert.deepEqual(plain(store.months("2026-10-31T23:59:58")), ["2026-10"]);
  assert.equal(store.summary().pending, 1);
  assert.equal(store.tick("2026-11-01T00:00:09"), 0);
  assert.equal(store.tick("2026-11-01T00:00:10"), 1);
  assert.deepEqual(plain(store.months("2026-11-01T00:00:10")), ["2026-10", "2026-11"]);
  assert.deepEqual(plain(store.dayList()), ["2026-10-31", "2026-11-01"]);
  assert.equal(M.clampDay("2026-10-31", "2026-10-31", M.dateOf("2026-11-01T00:00:10")), "2026-10-31", "a view on the old day stays there");
});

test("clock: the recording session grows with the clock and its strip follows past midnight", () => {
  const store = contextFrom([ctx("2026-10-31T23:00:00.000", "start"), ctx("2026-10-31T23:58:00.500", "app", "com.a")]);
  const before = "2026-10-31T23:59:30";
  const after = "2026-11-01T00:00:30";
  assert.deepEqual(plain(store.segments("2026-10-31", before)), [{ from: 0, to: 82800, state: "unknown" }, { from: 82800, to: 86370, state: "recorded" }]);
  assert.deepEqual(plain(store.segments("2026-10-31", after)), [{ from: 0, to: 82800, state: "unknown" }, { from: 82800, to: 86400, state: "recorded" }]);
  assert.deepEqual(plain(store.segments("2026-11-01", after)), [{ from: 0, to: 30, state: "recorded" }]);
});
