// Reference implementations for the tests: a plain full-history parse, month list, count scan and
// Activity scan. The page uses the incremental store instead; the tests compare the two.
// Takes the production model for the shared pieces (timestamp rule, families, month helpers).
export function createReference(M) {
  const { isValidTimestamp, FAMILIES, familyOf, monthOf } = M;
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
      presses.push({ month: time.slice(0, 7), layer, key, bin });
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

  function buildActivity(presses, month, highlight, capacity) {
    const all = new Array(48).fill(0);
    const hit = new Array(48).fill(0);
    const byFamily = {};
    const familyTotals = {};
    for (const family of FAMILIES) { byFamily[family] = new Array(48).fill(0); familyTotals[family] = 0; }
    let total = 0;
    let hitTotal = 0;
    for (const p of presses) {
      if (p.month !== month || !(p.bin >= 0 && p.bin < 48)) continue;
      all[p.bin] += 1;
      total += 1;
      const family = familyOf(p.layer);
      byFamily[family][p.bin] += 1;
      familyTotals[family] += 1;
      if (p.layer === highlight) { hit[p.bin] += 1; hitTotal += 1; }
    }
    let peakHour = 0;
    let peakCount = -1;
    for (let hour = 0; hour < 24; hour++) {
      const count = all[2 * hour] + all[2 * hour + 1];
      if (count > peakCount) { peakHour = hour; peakCount = count; }
    }
    const perDot = Math.max(1, Math.ceil(Math.max(...all) / capacity));
    return { all, hit, byFamily, familyTotals, total, hitTotal, peakHour, perDot };
  }

  return { parseLog, listMonths, countCombos, buildActivity };
}
