# Log retention

The usage log (`~/.local/state/karabiner/usage.log`, about 115 KB a day)
and the context log (`~/.local/state/hyperdash/context.log`) only grow.
Before retention, the page and the insights tool read both whole, so a cold
open grew with all history: 2.1 s in WebKit at 2 million usage lines.

## The scheme

Nothing moves. The logs are never renamed, truncated or rewritten, so
Karabiner's `>>` and the context recorder keep appending as before. A
manifest, `~/.local/state/karabiner/retention.json`, names a cut offset in
each log. Bytes before the cut are the archive; the manifest summarises
them. Bytes from the cut on are the tail, which readers parse as before.

**Tail start.** The first day of the month that holds the day 31 days before
today. It is never later than the first of last month or 30 days ago, so
the current and previous month, and every insight window (trend 14 days,
unused 30, focus 7, dormant last month, burst and peak this month), stay
raw. The usage cut is the start of the first valid line, in file order,
dated on or after the tail start. The context cut is the last `start` line
dated before the tail start that is later than every valid line before it.
From the tail start on, sessions and app attribution match the whole log.

**Manifest, version 2.** Three lines of JSON. The header holds `version`,
`created`, `tailStart`, and the `usage` and `context` cuts (`context` is
absent when there is no usable cut). Each cut holds `dev`, `ino`, `offset`
and `lastLine`, the line that ends at the offset. The summary holds
`tailStart`, the archive's `count`, `rejected`, `firstEvent`, `lastEvent`,
`lastUsed` per combo, and `days`: date, then combo, then pairs of
half-hour bin and count. The host decodes only the header; the page gets
the summary line as it is. Decoding a 2.5 MB summary with `hs.json.decode`
held Hammerspoon for about 75 s. Version 1 had only the first two lines;
readers still accept it, without the day index.

**Day index.** The third line, `{"days": {date: [usageFrom, usageTo,
contextFrom, contextTo]}}`, has an entry for every day from the first
archived day to the day before the tail start. The offsets are absolute and
start or end whole lines:

- Usage: from the first to the end of the last archived line dated that
  day, in file order; `0, 0` when there is none. Lines of other days inside
  the span are skipped by the page.
- Context, with the lines in time order: from the last `start` before the
  day (or the first line), which sets the session and the app at 00:00, to
  the first line after the day and any line in its millisecond. A session's
  end is the last line before the next `start`, so only a line after the day
  shows whether the day's last session ran past midnight. The span covers
  each of those lines wherever it sits in the file. `contextTo` is -1 when
  no line follows the day yet: the reader reads to the last complete line.

The index costs nothing to build: compaction already reads every line. A
search of the file by timestamp would not do: neither log is in time order
(the fixture holds a July press written in October and an August context
line written weeks late), and the `start` that opens a day's session can lie
weeks back, which a search would find only by scanning backwards inside
Hammerspoon. The host reads one day's entry from the line as text and never
decodes it.

**Who and when.** `hyperdash-insights --compact` builds the manifest from
the logs, which it only reads, using the same line parser as the insights
run. It writes the file under a temporary name, flushes it, then renames
it over the old one. hyperdash.lua runs it after the panel closes, when no
sync or insights run is in flight, once a day at most, and only when the
manifest is missing, has no day index (version 1), its tail start has
passed, or its cut no longer fits the log. Afterwards both streams reset
while the panel is closed.

## Readers

A reader uses a cut only when the file still has its `(dev, ino)`, holds
`offset` bytes, and the `offset` ends `lastLine` on a line boundary. A
clock set before the tail start, another version, or a corrupt file make
the reader read the whole log. That is also how logs from before retention
are read. The context cut is used only with the usage cut of the same
manifest. The host reads the manifest once per sync, so both streams agree
on it.

- **Page:** the usage reset carries `archive` (the summary) and the tail
  from the cut; `offset` stays absolute, so appends work as before. Totals,
  bins, last use, first and last press and rejected lines come out the
  same as from the whole log. A day before the tail start first shows its
  chart from the archived counts, keyed `ARCHIVED · COUNTS ONLY`.
- **Archived day:** opening such a day posts `{ action: "day", date, id }`.
  The host reads that day's spans from the index of the manifest the page's
  usage generation came from, after the cut checks above on the usage log,
  and on the context log when the page holds the context from its cut (a
  page that read the context whole gets only the usage lines). It answers
  `hyperdash.loadDay({ id, date, usage, context })` through the call queue,
  at most 4 MB. The page builds the day from those lines, its own raw lines
  of that day and that context, which gives the command list, sequences,
  app chips and coverage strip of the whole-log view, at the same fixed
  height. It ignores an answer whose `id` is not the open request, holds one
  day at a time, and drops it on `open()`, on a reset of either log and on
  its own close.
- **Insights tool:** `--retention <path>` reads both tails. `unbound` and
  `recordingSince` take the archive's per-combo day counts and first press.

## Failure

| Event | Result |
|---|---|
| Compaction killed | The old manifest stays; the next run removes the temporary file. |
| Disk full | The write fails; the old manifest stays; the next try is the next day. |
| Reader during compaction | It sees the old or the new manifest; both give the same numbers. |
| Log replaced, truncated or rewritten | The cut fails its checks; the log is read whole; compaction is due. |
| Page refuses the summary | The host resends the whole log and does not offer that manifest again. |
| Archived day: no index (version 1), a log changed under its cut, a span off a line boundary or past the end, a read error, over 4 MB | The host answers `usage: null`; the day stays counts only until the next open or reset. |
| Archived day: no answer in 5 s, or lines that do not add up to the archived counts | The page keeps the day counts only until the next open or reset; a late answer is ignored. |

Tests: `tests/retention.test.mjs` (page) and `RetentionTests.swift` (tool)
share `tests/retention_cases/`. The page test reads every archived day of
the fixture back through its index and compares it with the whole-log day
for each highlight and app filter; `tests/archive.test.mjs` drives the
request, the answer and each fallback in the real page. The host and core
tests in `hammerspoon/tests` cover cuts, scheduling, fallback and the day
read, on the same fixture.
