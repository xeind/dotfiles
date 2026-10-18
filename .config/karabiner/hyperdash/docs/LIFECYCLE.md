# The life of hyperdash data

Two logs hold the history. Everything else the panel shows derives from them
and from `bindings.json`.

## What exists

| File | Written by | Holds | Kept |
|---|---|---|---|
| `~/.local/state/karabiner/usage.log` | Karabiner. Each Hyper command runs `printf ... >> usage.log` (`utils.ts`). | One line per press: local time to the second, layer, key. | Until you delete it. |
| `~/.local/state/hyperdash/context.log` | The Hammerspoon recorder, only when `RECORD_CONTEXT` is true. It is false in the repo. | One line per event: local time to the millisecond, and `app` (a bundle ID), `lock`, `unlock`, `sleep`, `wake` or `start`. No window titles, URLs or keys. | Until you delete it. |
| `~/.local/state/karabiner/insights.json` | `hyperdash-insights`, run by the host in the background. | The report: cards, held findings, rule statuses. | Replaced by each run. Safe to delete. |
| `hyperdash/bindings.json` | `yarn build`. | The layer, key, label and category of each binding. | In git. |

Both logs live outside the repo, so git holds neither. The files are append-only
text. A line the readers cannot parse is counted as rejected and skipped, never
fixed.

## Who reads what

- The host (`hyperdash.lua`) reads each log from a byte offset and sends only
  the new complete lines to the page. A truncated, replaced or rewritten log
  starts a new generation and a full resend. See `RECOVERY.md`.
- The page keeps every line in memory, with aggregates by month, combo and
  half hour, and per-day lists for the day view. It holds the whole history,
  not a window.
- `hyperdash-insights` reads each log in full on every run. A run starts when
  `insights.json` is missing or an hour old, or, with recording on, when the
  context log is newer and the report is 5 minutes old.
- Nothing in `hyperdash.lua`, `hyperdash_core.lua`, `utils.ts` or `rules.ts`
  rotates, trims or caps either log.

## What growth costs

Measured on a synthetic fixture, never on your logs: 500,000 presses over
1,401 days (12.3 MB, 24.5 bytes a line) and 509,533 context lines (23.6 MB,
46.4 bytes a line). WebKit through Playwright, and the installed release
`hyperdash-insights`, on this Mac.

| Cost at that size | Measured |
|---|---|
| Cold load of page and both logs, to an open panel | 1.4 s |
| Full resend (a reset) | 1.1 s median |
| Warm open | 14.5 ms median |
| Page memory after load (WebContent resident size) | about 0.9 GB |
| One `hyperdash-insights` run | 2.7 to 2.9 s, with or without `--context` |
| One context line appended, Activity day view open | 2 ms median |

The fixture is 3.8 years at about 360 presses a day. At fewer presses a day,
the same cost arrives later.

## Rotation

Rotation is in progress. See `RETENTION.md` (being designed).

Until it lands, the logs only grow. Deleting `usage.log` removes the history
for good: nothing else holds a copy.
