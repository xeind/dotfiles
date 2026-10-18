# What fails, what you see, and how it recovers

Each row is a failure the panel meets. "Fixed by" names a commit from the
resilience review. A row with no commit worked before it. Host tests are
Lua, run inside Hammerspoon (see `hammerspoon/tests/`); page tests are in
`tests/`. A check name in quotes is the first words of a `check(...)` line.

The host is `hammerspoon/hyperdash.lua`; its pure helpers are in
`hyperdash_core.lua`.

## The page

| State | What you see | Recovery | Fixed by | Tests |
|---|---|---|---|---|
| The page process dies or stops answering (a call errors, or no answer in 5 s) | No panel. The host never shows a blank window. | The host reloads the page with `html()`. The new page gets every stream again, with a reset. After two reloads in a row with no answer, it stops. | | host: "dead page: ..." |
| The page dies twice in a row | One alert, "hyperdash: page failed to load". | The next toggle reloads and opens. | | host: "dead twice: ..." |
| The reload never finishes (5 s) | One alert. | The next toggle reloads again and opens when the page loads. | | host: "reload timeout: ..." |
| The page dies while the panel is open, and you toggle before the reload ends | Before: the panel stayed up, and opened a second time once the page loaded. After: the toggle closes it. | `toggle()` checks `open` before the page state. | `76a0e38` | host: "dead while open: ..." |
| The first load never finishes or fails | Before: no toggle ever opened the panel. After: a toggle made during the failing load gets the alert; the next toggle reloads and opens. | The first load has the same 5 s limit as a reload, and a failed first navigation takes the failed-reload path. | `84ba2a8` | host: "first load fails: ...", "first load hangs: ...", "asked during a failing first load: ..." |
| You toggle while the panel is rendering | Nothing odd. An even number of toggles ends hidden. | `show()` flips `cancelShow`. | | host: "rapid N toggles: parity" |
| The page rejects the data (for example the bindings are not a list) | The line "Cannot show the dashboard." with the reason. The footer offers Escape to close. | The next valid reset clears it. | | page: `model.test.mjs` "validatePayload: shapes"; the line itself has no test |

## The logs

| State | What you see | Recovery | Fixed by | Tests |
|---|---|---|---|---|
| `usage.log` is truncated, replaced or rewritten | The list matches the new file. | The reader sees a new inode, a smaller size, or a byte before its offset that is not a newline. It bumps the generation and sends a reset. | | host: "truncate: ...", "replace: ..."; core: "truncate: ..." |
| `usage.log` is missing | "Usage log missing — nothing to show". | The page empties by a reset. It fills when the file returns. | | host: "missing log: page emptied"; the message has no test |
| The retention manifest is missing, corrupt, of another version, dated after the clock, or its cut no longer fits the log (`RETENTION.md`) | None; the panel shows the same numbers. | Readers read the whole log. A page that refuses the summary gets the whole log, and the host does not offer that manifest again. Compaction becomes due. | | host: "retention, ...", "retention refused: ...", "compact: due when the cut ..."; core: "cut: ..."; page: `retention.test.mjs` |
| A compaction is killed or the disk is full | None. | The old manifest stays. The next run removes the temporary file. | | Swift: `RetentionTests.aFailedWriteKeepsTheOldManifest` |
| An append is rejected, lost or unanswered | None. | The reader resets the stream. A silent page is released by the 5 s watchdog. | | host: "rejected append: ...", "silent: ..." |
| `context.log` is truncated in place (`: > context.log`, copytruncate) | Before: every later press had no app until Hammerspoon restarted, and the file health still read ok. After: attribution continues. | The recorder treats a file smaller than its last write as new, and writes `start` and the front app first. | `9c5fa44` | core: "recorder: truncated file holds start, then the new line" |
| `context.log` is deleted or replaced | Same symptom as above, before `e12e9c8`. | The recorder checks (dev, ino) and writes `start` first. | `e12e9c8` | host: "recorder on: rotated log begins with start and the front app" |
| A context write succeeds but the close fails | Before: the event counted as written. After: it counts as failed and the next event retries. | The recorder checks the close result and forgets the app. | `84ba2a8` | core: "close fails: ..." |
| `context.log` is unreadable | The status line says the context log is unreadable. The offset does not advance. | The next readable sync catches up. | | host: "context unreadable: ...", "context readable again: caught up" |
| Recording is off | "CONTEXT OFF". An old file still reaches the page. | None needed. | | host: "recorder off: ..." |

## The bindings and the insights

| State | What you see | Recovery | Fixed by | Tests |
|---|---|---|---|---|
| `bindings.json` is missing, corrupt or not a list | Status "missing" or "invalid", with an empty list. | Fix the file; the next sync reloads it (it is re-read when its stat changes). | | host: "bindings missing: ...", "bindings corrupt: ...", "bindings object: ..." |
| Some bindings have the wrong field types | The rest show. Status "invalid" with the count dropped. | As above. | | host: "bindings with bad entries: ..." |
| The insights tool hangs | Before: "ANALYSIS RUNNING" for ever, and no later run until Hammerspoon reloaded. After: "ANALYSIS FAILED" with the message "timed out after 120 s". | A timer stops the run after 120 s. It counts as one failure; the next try comes 5 minutes later. A success clears it. | `2d51564` | defects: "hang: ..." |
| The insights tool fails or cannot start | "ANALYSIS FAILED", the reason, and the next try time. | Retry after 5 minutes, then every 30. The open never waits for the run. | | defects: "backoff: ...", "backoff x2: ...", "start failure: ..." |
| The insights tool is missing | "ANALYSIS TOOL MISSING", and "The analysis tool was not found, so there are no insights." | `yarn build:insights`. | | no test of the message; `model.test.mjs` only feeds the status to `describeHealth` |
| `insights.json` is invalid or an unknown version | Health "failed" with the reason. | The next run replaces it. A run starts when the file is missing or an hour old. | | core: `checkInsights` checks |
| The report is over an hour old | Status "stale". | The next open starts a run in the background. | | host: "report over an hour old still reruns" |

## Not recovered

- A recorder restart inside the repeated hour of a daylight saving fall-back
  day can leave a gap in the session strip. Stamps carry no offset.
  Measured in a probe; no test pins it. See `tests/clock.test.mjs` for the
  cases that are pinned.
