// Reference implementations for the tests: a plain full-history parse, month list, count scan and
// Activity scan. The page uses the incremental store instead; the tests compare the two.
// Takes the production model for the shared pieces (timestamp rule, families, month helpers).
export function createReference(M) {
  const { isValidTimestamp, GROUPS, monthOf } = M;
  const NAME = /^[a-z0-9_]+$/;
  const LINE_BREAK = /\r?\n/;
  const pad = (n, width = 2) => String(n).padStart(width, "0");

  // Valid timestamps sort as strings, so the latest use is a string maximum.
  function parseLog(text, now) {
    const presses = [];
    const lastUsed = {};
    let rejected = 0;
    let future = 0;
    let firstEvent = null;
    let lastEvent = null;
    for (const line of text.split(LINE_BREAK)) {
      if (line === "") continue;
      const fields = line.split("\t");
      if (fields.length !== 3 || !isValidTimestamp(fields[0]) || !NAME.test(fields[1]) || !NAME.test(fields[2])) {
        rejected += 1;
        continue;
      }
      const [time, layer, key] = fields;
      if (time > now) { future += 1; continue; }
      const bin = Number(time.slice(11, 13)) * 2 + (Number(time.slice(14, 16)) >= 30 ? 1 : 0);
      presses.push({ month: time.slice(0, 7), date: time.slice(0, 10), layer, key, bin, sec: Number(time.slice(11, 13)) * 3600 + Number(time.slice(14, 16)) * 60 + Number(time.slice(17, 19)) });
      const id = `${layer} ${key}`;
      if (!(id in lastUsed) || time > lastUsed[id]) lastUsed[id] = time;
      if (firstEvent === null || time < firstEvent) firstEvent = time;
      if (lastEvent === null || time > lastEvent) lastEvent = time;
    }
    return { presses, rejected, future, lastUsed, firstEvent, lastEvent };
  }

  function listMonths(presses, now) {
    const current = monthOf(now);
    const first = presses.reduce((min, p) => (p.month < min ? p.month : min), current);
    const result = [];
    let [year, month] = first.split("-").map(Number);
    while (true) {
      const id = `${pad(year, 4)}-${pad(month)}`;
      result.push(id);
      if (id >= current) break;
      month += 1;
      if (month > 12) { month = 1; year += 1; }
    }
    return result;
  }

  function countCombos(presses, month) {
    const counts = {};
    for (const p of presses) {
      if (p.month !== month) continue;
      const id = `${p.layer} ${p.key}`;
      counts[id] = (counts[id] || 0) + 1;
    }
    return counts;
  }

  // Month activity by colour group, from a plain scan of every press. `classify.groupOf(combo)` gives the group.
  function buildActivity(presses, month, highlight, capacity, classify) {
    return activityOf(presses.filter((p) => p.month === month), highlight, capacity, classify);
  }

  function activityOf(presses, highlight, capacity, classify) {
    const all = new Array(48).fill(0);
    const hit = new Array(48).fill(0);
    const byGroup = {};
    const groupTotals = {};
    for (const group of GROUPS) { byGroup[group] = new Array(48).fill(0); groupTotals[group] = 0; }
    let total = 0;
    let hitTotal = 0;
    for (const p of presses) {
      if (!(p.bin >= 0 && p.bin < 48)) continue;
      all[p.bin] += 1;
      total += 1;
      const group = classify.groupOf(`${p.layer} ${p.key}`);
      byGroup[group][p.bin] += 1;
      groupTotals[group] += 1;
      if (p.layer === highlight) { hit[p.bin] += 1; hitTotal += 1; }
    }
    let peakHour = 0;
    let peakCount = -1;
    for (let hour = 0; hour < 24; hour++) {
      const count = all[2 * hour] + all[2 * hour + 1];
      if (count > peakCount) { peakHour = hour; peakCount = count; }
    }
    const perDot = Math.max(1, Math.ceil(Math.max(...all) / capacity));
    return { all, hit, byGroup, groupTotals, total, hitTotal, peakHour, perDot };
  }

  const toSeconds = (text) => {
    const [d, t] = text.split("T");
    const [y, mo, da] = d.split("-").map(Number);
    const [h, mi, rest] = t.split(":");
    const [se, fraction = "0"] = rest.split(".");
    return Date.UTC(y, mo - 1, da, +h, +mi, +se) / 1000 + Number(fraction.padEnd(3, "0")) / 1000;
  };

  // Sessions as the insights tool defines them (Context.swift), written as a literal loop: a session
  // starts at a `start`, ends at the last event before the next `start` (the last one at now), and
  // sessions 60 s or less apart merge. `events` is [{ t, kind }]; events after now are ignored.
  function sessionSpansNaive(events, nowSeconds) {
    const known = events.map((e) => ({ ...e, at: toSeconds(e.t) })).filter((e) => e.at <= nowSeconds).sort((x, y) => x.at - y.at);
    const starts = known.filter((e) => e.kind === "start");
    const spans = [];
    for (let i = 0; i < starts.length; i++) {
      const start = starts[i].at;
      let end = nowSeconds;
      if (i + 1 < starts.length) {
        const next = starts[i + 1].at;
        let latest = start;
        for (const e of known) if (e.at < next && e.at > latest) latest = e.at;
        end = latest;
      }
      const last = spans[spans.length - 1];
      if (last && start - last.end <= 60) last.end = Math.max(last.end, end); else spans.push({ start, end });
    }
    return spans;
  }

  // The app of a press, by a plain scan: the last `app` or `start` event whose whole second is strictly
  // before the press's second, only when a session covers the press. A `start` leaves no app.
  function appAtNaive(events, stamp, nowSeconds) {
    const at = toSeconds(stamp);
    if (!sessionSpansNaive(events, nowSeconds).some((span) => span.start <= at && at <= span.end)) return null;
    let found = null;
    let foundAt = -Infinity;
    for (const e of events) {
      if (e.kind !== "app" && e.kind !== "start") continue;
      const when = toSeconds(e.t);
      if (Math.floor(when) < at && when >= foundAt) { found = e.kind === "app" ? e.value : null; foundAt = when; }
    }
    return found;
  }

  // Recurring pairs by a plain double loop over every candidate pair, without the single pass the model uses.
  function sequencesNaive(events, maxGap, min, app) {
    const counts = new Map();
    for (let i = 0; i < events.length - 1; i++) {
      const a = events[i];
      const b = events[i + 1];
      const gap = b.sec - a.sec;
      if (gap < 0 || gap > maxGap || a.combo === b.combo) continue;
      if (app !== null && !(a.app === app && b.app === app)) continue;
      const key = `${a.combo} > ${b.combo}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    return [...counts].filter(([, n]) => n >= min).map(([key, count]) => ({ key, count })).sort((x, y) => y.count - x.count || (x.key < y.key ? -1 : 1));
  }

  // The day second by second. A second is unknown outside every session; inside one it is asleep or locked
  // between a sleep/lock and its wake/unlock (a `start` clears both), else recorded.
  function segmentsBrute(contextEvents, date, nowSeconds) {
    const dayStart = toSeconds(`${date}T00:00:00`);
    const spans = sessionSpansNaive(contextEvents, nowSeconds);
    const events = contextEvents.map((e) => ({ at: toSeconds(e.t), kind: e.kind })).filter((e) => e.at <= nowSeconds).sort((a, b) => a.at - b.at);
    const limit = Math.min(86400, nowSeconds - dayStart);
    let locked = false, asleep = false, index = 0;
    const apply = (kind) => { if (kind === "start") { locked = false; asleep = false; } else if (kind === "lock") locked = true; else if (kind === "unlock") locked = false; else if (kind === "sleep") asleep = true; else if (kind === "wake") asleep = false; };
    const runs = [];
    for (let second = 0; second < limit; second++) {
      const t = dayStart + second;
      while (index < events.length && events[index].at <= t) apply(events[index++].kind);
      const inside = spans.some((span) => span.start <= t && t <= span.end);
      const state = !inside ? "unknown" : asleep ? "asleep" : locked ? "locked" : "recorded";
      const last = runs[runs.length - 1];
      if (last && last.state === state) last.to = second + 1; else runs.push({ from: second, to: second + 1, state });
    }
    return runs;
  }

  return { parseLog, listMonths, countCombos, buildActivity, activityOf, sessionSpansNaive, appAtNaive, sequencesNaive, segmentsBrute };
}
