# What each insight claims, and what backs it

Each card makes one claim about your use. This file ties the claim to the
rule in `insights/Sources/HyperdashInsights/Insights.swift`, the limits of
that rule, and the tests that pin it. It describes report version 3.

The tests named here are Swift Testing cases in
`insights/Tests/HyperdashInsightsTests/InsightsTests.swift`. A case name
alone means that file. Page tests are in `tests/`.

## The report

- The engine runs seven rules, in this order: `focus`, `trend`, `unused`,
  `dormant`, `unbound`, `burst`, `peak`. `trend` gives a rising card or a
  falling card, never both.
- It shows at most five cards (`maxCards`). Rank, highest first: rising,
  falling, focus, burst, peak, dormant, unused, unbound.
- Every rule reports a status: `shown`, `held` (found, but five cards rank
  higher), `not-ready` (too little history) or `no-pattern`. The reason
  carries the counts.
- Held findings keep their full text and evidence in `held`.
- Presses after `now` are ignored by every rule.

Tests: `ReportTests.fullReportOrder`, `everyRuleReportsItsStatus`,
`everyInsightCarriesDates`, `fileEncodesVersionThree`.

## Recorded days

`unused` and `trend` state an absence or a change, so they count only
recorded days (`recordedDays` in `Context.swift`).

- A day counts if it is after the day of the first valid press and before
  today.
- With a context log, the day must also overlap a recording session, and
  every press that day must lie inside a session.
- Sessions 60 s or less apart count as one. Lock and sleep do not end a
  session.
- A day with no presses and no session is not recorded. Before the rule
  landed (`b81ff85`), one press on 1 October and a first session on
  12 October made 2 to 14 October all count.
- Without a context log, the first rule alone applies.

Limit: any overlap counts. A session of ten minutes qualifies its day.
By the rule, a day with Hammerspoon running and Karabiner stopped also
qualifies, with no presses.

Tests: `RecordedDaysTests.*`, `UnusedTests.unobservedEmptyDaysAreNotCounted`,
`daysWithContextGapsAreNotCounted`.

## Cards

| Card | Claim | Rule | Limits | Tests |
|---|---|---|---|---|
| "X leads shortcut use" | Category X has the most presses in the last 7 days. Detail: share of all presses, and the number of days it led. | `focus`. Window: today and the 6 days before. Share is category presses over all window presses; uncategorised presses stay in the total. Needs 30 presses and 3 days that each have 5 or more presses with X on top. | The category comes from today's `bindings.json` and is applied to all history. | `FocusTests.reportsDominantCategoryWithoutContext`, `needsThirtyPresses`, `needsThreeRepeatDays`, `onlyCountsLastSevenDays`, `needsCategoriesInBindings` |
| "X mostly in App" | Most of X's presses happen in one app. Same rule, with an app named. | Needs 20 attributed presses, at least 60% of X's presses attributed, the top app above 50% of attributed, and 3 days with 3 or more attributed presses and that app on top. The value stays the category share. | The app is the one in front strictly before the press second. An app change in the same second counts later. A press outside every session has no app. | `FocusTests.namesTheAppWhenMostPressesAreInOneApp`, `appShareUsesAttributedPresses`, `noAppWithoutAMajority`, `noAppWhenMostPressesAreUnattributed`, `noAppWhenTopAppRepeatsOnFewerThanThreeDays`; `AttributionTests.*` |
| "L up/down N presses" | One shortcut changed by N presses between the 7 whole days before today and the 7 before those. | `trend`. Needs all 14 days recorded; 10 or more presses in the larger week; a change of 5 or more; 4 of the 7 recent days beating (or trailing) the earlier week's daily mean; and the change must stay 5 or more after dropping the busiest day of the week that carries it (`7f6c48f`). The largest absolute change wins. | Today is in neither week. The label is today's. A rebind inside the 14 days compares two commands under one label. | `TrendTests.rising`, `falling`, `oneDaySpikeDoesNotCount`, `oneDaySpikeOnFewPressesDoesNotCount`, `oneDaySpikeInEarlierWeekDoesNotCountAsFalling`, `needsAtLeastFourRepeatDays`, `needsFourteenFullyRecordedDays`, `gapInContextInsideWindowBlocksTrend`, `todayIsNotPartOfEitherWindow` |
| "N of M Layer shortcuts unused" | N of the layer's M bindings had no press in the last 30 days. | `unused`. Presses from 30 days ago through now count, so today's press is use. Needs 3 recorded days among the last 30, a layer of 4 or more bindings, and 3 or more unused. The highest unused share wins. | The engine does not know when a binding was added: a new binding counts as unused until pressed. | `UnusedTests.prefersHighestShareOverLargestCount`, `ignoresLayersWithFewerThanFourBindings`, `needsThreeUnused`, `needsThreeFullyRecordedDays`, `pressOlderThan30DaysDoesNotCount`, `keepsEveryUnusedKey` |
| "L not used yet this month" | A shortcut with 3 or more presses on 2 or more days last month has none this month. It says "not yet", never "stopped". | `dormant`. The most pressed one wins. Needs the first press on day 1 of last month or earlier; otherwise the rule is `not-ready`. | It does not check that this month has any recording. The page's month comparison uses a stricter test (`isMonthComplete`: first press at or before the month's first instant). | `DormantTests.reportsComboNotUsedYetThisMonth`, `neverClaimsStoppedTenMinutesIntoMonth`, `needsPreviousMonthRecordedFromItsFirstDay`, `needsThreePresses`, `needsTwoDays`, `notDormantIfUsedThisMonth` |
| "N logged combos no longer bound" | N combos in the log have no binding in `bindings.json`. | `unbound`. All history up to now. Combos ranked by presses. | It trusts `bindings.json` to match `karabiner.json`; both come from one build. | `UnboundTests.reportsLoggedCombosWithoutBinding`, `keepsEveryKeyMostPressedFirst`, `absentWhenAllBound`, `ignoresFutureEvents`; page: `bugs.test.mjs` "review data: a logged combo with no binding..." |
| "L repeats in bursts" | One shortcut came in runs of 5 or more presses, each within 3 s of the last, on 2 or more days this month. | `burst`. The log order decides a run: another combo breaks it. A run belongs to the day it started. Needs 2 bursts on 2 days. The combo with the most bursts wins. | The log has a resolution of 1 s. | `BurstTests.reportsComboWithMostBursts`, `needsTwoBursts`, `needsBurstsOnTwoDays`, `gapOverThreeSecondsBreaksRun`, `otherComboBreaksRun` |
| "Most shortcut use: HH:00-HH:00" | The busiest hour of the month recurs: it has presses on 3 or more days. | `peak`. Needs 20 presses this month. Ties go to the earlier hour. If the busiest hour is on fewer than 3 days, the rule gives no card; it does not fall back to the next hour. | The day list is the days that hour had presses. The card opens those days, not filtered to the hour. | `PeakTests.reportsBusiestRepeatedHour`, `needsTwentyPresses`, `busiestHourOnOneDayBlocksPeak`, `lastHourWrapsToMidnight` |

## What a card opens

Every card opens an evidence page. It does not jump straight to a layer.

- Header: the card's title and detail.
- Facts, from the report's own fields (`evidenceFacts` in `index.html`):
  Period; Compared with; Count (for example "12 of 40 presses"); Before;
  App.
- Supporting days: one button per date. Each opens that day in Activity,
  with the card's app as the filter when it has one.
- Shortcuts: one button per combo. Each opens the combo's layer page in the
  report's month, so a combo with no press that month shows its history, not
  "Nothing yet".
- Back from a day or a shortcut returns to the evidence page. Escape and
  "ALL INSIGHTS" return to the card list, with the same card focused and
  the list at its old scroll.

The period each card counts, as the report states it:

| Card | Period | Compared with |
|---|---|---|
| focus | today and the 6 days before | none |
| rising, falling | the 7 days before today | the 7 days before those |
| unused | 30 days before today, through today | none |
| dormant | month to date | last month |
| unbound | first press to today | none |
| burst, peak | month to date | none |

Tests: `tests/bugs.test.mjs` "insight evidence: Back from a shortcut or a day
it opened..." and "insight evidence: Escape returns to the same card...";
`tests/model.test.mjs` "evidenceFacts: ...", "windowLabel: ..." and
"insights: windows, every date and rule statuses ride along...".

## Not covered here

Each card's example numbers came from private logs and fixtures. This file
cites only named tests, which use synthetic data.
