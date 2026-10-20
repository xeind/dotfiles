# What each insight claims, and what backs it

Each card makes one claim about your use. This file ties the claim to the
rule in `insights/Sources/HyperdashInsights/Insights.swift`, the limits of
that rule, and the tests that pin it. It describes report version 3.

The tests named here are Swift Testing cases in
`insights/Tests/HyperdashInsightsTests/InsightsTests.swift`. A case name
alone means that file. Page tests are in `tests/`.

## The report

- The engine runs eleven rules, in this order: `focus`, `trend`, `unused`,
  `dormant`, `unbound`, `burst`, `peak`, `pair`, `double`, `undone`,
  `uptake`. `trend` gives a rising card or a falling card, never both.
- It shows at most five cards (`maxCards`). Rank, highest first: rising,
  falling, focus, burst, pair, double, peak, undone, uptake, dormant, unused,
  unbound. A pair or a double suggests one change (a macro, a binding), so
  both rank with the repeated patterns, after bursts. `undone` and `uptake`
  rank below the changes and patterns, which describe most presses, and above
  the absences, because each names one binding to change or practise.
- Every rule reports a status: `shown`, `held` (found, but five cards rank
  higher), `not-ready` (too little history) or `no-pattern`. The reason
  carries the counts.
- Held findings keep their full text and evidence in `held`. The page puts
  one row after the cards, "N MORE FINDINGS". It shows the held cards in the
  same list, in rank order, until the panel next opens.
- Presses after `now` are ignored by every rule.

Tests: `ReportTests.fullReportOrder`, `pairAndDoubleRankAfterBurst`,
`everyRuleReportsItsStatus`, `everyInsightCarriesDates`,
`fileEncodesVersionThree`; page: `bugs.test.mjs` "held findings: a row after
the cards reveals them...".

## Recorded days

`unused`, `trend` and `uptake` state an absence or a change, so they count only
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
| "N of M Layer shortcuts unused in 30 days" | N of the layer's M bindings had no press in the last 30 days. Detail: how many were never pressed since the first logged day; how many were pressed before, with the latest such day ("Sep 5 or earlier" for several); how many of the 30 days were recorded. | `unused`. Presses from 30 days ago through now count, so today's press is use. Needs 14 recorded days among the last 30, a layer of 4 or more bindings, and 3 or more unused. The highest unused share wins. "Never pressed" means no press in the log or the archive summary. Keys list the never-pressed first. | The engine does not know when a binding was added: a new binding counts as unused until pressed. With 3 recorded days, the old floor, a binding added that week read as unused; 14 gives it two weeks. Presses dropped before the archive existed are not seen, so "never" means since the first logged day, which the detail names. | `UnusedTests.prefersHighestShareOverLargestCount`, `separatesNeverPressedFromLapsed`, `oneLapsedNamesItsDay`, `archivedPressIsNotNeverPressed`, `ignoresLayersWithFewerThanFourBindings`, `needsThreeUnused`, `needsFourteenFullyRecordedDays`, `explainsTooFewRecordedDays`, `pressOlderThan30DaysDoesNotCount`, `keepsEveryUnusedKey` |
| "L not used yet this month" | A shortcut with 3 or more presses on 2 or more days last month has none this month. It says "not yet", never "stopped". | `dormant`. The most pressed one wins. Needs the first press on day 1 of last month or earlier; otherwise the rule is `not-ready`. | It does not check that this month has any recording. The page's month comparison uses a stricter test (`isMonthComplete`: first press at or before the month's first instant). | `DormantTests.reportsComboNotUsedYetThisMonth`, `neverClaimsStoppedTenMinutesIntoMonth`, `needsPreviousMonthRecordedFromItsFirstDay`, `needsThreePresses`, `needsTwoDays`, `notDormantIfUsedThisMonth` |
| "N logged combos no longer bound" | N combos in the log, each pressed 3 or more times on 2 or more days, have no binding in `bindings.json`. | `unbound`. All history up to now, the archive summary included. Combos below the floor are left out of the count and the presses; when only those remain, the rule is `no-pattern` and names how many. Combos ranked by presses. | It trusts `bindings.json` to match `karabiner.json`; both come from one build. Without the floor, one stray press kept the card alive as long as the log kept it. There is no recency window: a combo used for weeks and then unbound stays on the card, since its presses are still in the history the other pages show. | `UnboundTests.reportsLoggedCombosWithoutBinding`, `keepsEveryKeyMostPressedFirst`, `needsThreePressesOnTwoDays`, `countsArchivedPresses`, `absentWhenAllBound`, `ignoresFutureEvents`; page: `bugs.test.mjs` "review data: a logged combo with no binding..." |
| "L repeats in bursts" | One shortcut came in runs of 5 or more presses, each within 3 s of the last, on 2 or more days this month. | `burst`. The log order decides a run: another combo breaks it. A run belongs to the day it started. Needs 2 bursts on 2 days. The combo with the most bursts wins. | The log has a resolution of 1 s. | `BurstTests.reportsComboWithMostBursts`, `needsTwoBursts`, `needsBurstsOnTwoDays`, `gapOverThreeSecondsBreaksRun`, `otherComboBreaksRun` |
| "Most shortcut use: HH:00-HH:00" | The busiest hour of the month recurs: it has presses on 3 or more days. | `peak`. Needs 20 presses this month. Ties go to the earlier hour. If the busiest hour is on fewer than 3 days, the rule gives no card; it does not fall back to the next hour. | The day list is the days that hour had presses. The card opens those days, not filtered to the hour. | `PeakTests.reportsBusiestRepeatedHour`, `needsTwentyPresses`, `busiestHourOnOneDayBlocksPeak`, `lastHourWrapsToMidnight` |
| "A then B: N times" | Shortcut B was the very next press after shortcut A, within 5 s, N times in the last 14 days. A and B are labels; the detail gives both short names and the number of days. | `pair`. Window: today and the 13 days before. Any press between A and B breaks the pair. A and B differ, and neither is in the `pointer` or `text-navigation` category. A pair belongs to the day of A. Needs 5 pairs on 4 or more days, so 3 days remain after dropping the busiest. The most frequent pair wins; ties go to more days, then combo order. | It does not say A caused B or that the user meant them as one step. The day page's sequences use other limits (10 s, 3 times, one day), so the two need not agree. | `PairTests.reportsRecurringPair`, `needsFivePairs`, `needsThreeDaysWithoutTheBusiestDay`, `gapOverFiveSecondsIsNoPair`, `pressBetweenBreaksPair`, `sameComboTwiceIsNoPair`, `ignoresPointerAndTextNavigation`, `countsOnlyTheLastFourteenDays` |
| "L pressed twice in 2 s: N times" | One app, site or capture shortcut came twice in a row, the second within 2 s, N times in the last 14 days. It does not say why. | `double`. Window: today and the 13 days before. Only `app-launch`, `site-open` and `capture` bindings count. Runs chain as in `burst` (same combo, each within 3 s); only a run of exactly 2 counts, so 3 or more in a row, and any burst, do not. Needs 5 doubles on 3 or more days. The combo with the most wins. | The log has a resolution of 1 s, so "2 s" means a timestamp gap of 0, 1 or 2 s. | `DoubleTests.reportsDoubles`, `countsSiteOpen`, `needsFiveDoubles`, `needsThreeDays`, `gapOverTwoSecondsIsNoDouble`, `burstIsNoDouble`, `otherCategoriesAreNotChecked` |
| "L undone N times" | The next press after L was its opposite, within 3 s, N times in the last 14 days. It says "undone", never "mistake". | `undone`. Opposites come from `oppositePairs` (rules.ts: Maximize and Almost maximize with Restore, halves, displays, Larger and Smaller, window moves, volume, brightness, Recording Mode), in either order. A pair counts only while both combos are bound. Any other press in between breaks it. The undoing press is used up, so L, opposite, L counts once. Needs 5 times on 4 or more days, so 3 days remain without the busiest one. The most reversed combo wins. Count: N of L's presses in the window. | The log has a resolution of 1 s, so a logged 3 s can be up to 3.99 s; presses in one second keep file order. The table names combos, not commands: a rebind to another command keeps the pair. Tab, page and text navigation are left out, since going back and forth there is ordinary use. Why 14 days: 7 days would need a reversal on more than half of them; 14 still clears a fixed binding within two weeks. | `UndoneTests.reportsMostUndoneCombo`, `needsFiveTimes`, `needsFourDaysSoTheBusiestDayCanBeDropped`, `threeSecondsCountsFourDoNot`, `pressBetweenBreaksThePair`, `sameSecondFollowsFileOrder`, `eitherOrderOfAPairCounts`, `undoingPressIsUsedOnce`, `skipsPairNoLongerBound`, `onlyCountsLastFourteenDays` |
| "L used on N of M days" | L was first used in the last 21 days and has presses on N of the M recorded days since. Detail: the dates of the first and last use. It says "first used", never "added". | `uptake`. Bound combos only. The first press in the history stands in for when the binding was added, so it must come 7 or more days after recording began; a combo in the archive is not new. M counts recorded days from the first use through yesterday and must be 7 or more; a press today shows as the last use only. Fires only on weak uptake: presses on fewer than half of the M days, or on none of the last 3. A combo used more often is good news with no action, so the rule gives `no-pattern` with its counts. Among weak combos, the one with the most recorded days without a press wins, since that is the habit least taken up. | A binding added but never pressed has no first use and shows only in `unused`. A combo pressed under an earlier command keeps that first date. | `UptakeTests.reportsWeakestNewShortcut`, `strongUptakeGivesNoCard`, `noneInTheLastThreeDaysIsWeak`, `todaysPressIsLastUseButNotADay`, `needsSevenRecordedDaysSinceFirstUse`, `needsSevenDaysOfLogBeforeFirstUse`, `explainsAYoungLog`, `firstUseOlderThanTwentyOneDaysIsNotNew`, `countsOnlyRecordedDays` |

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
| pair, double | today and the 13 days before (today counts; rising and falling leave it out) | none |
| undone | today and the 13 days before | none |
| uptake | first use to today | none |

Tests: `tests/bugs.test.mjs` "insight evidence: Back from a shortcut or a day
it opened..." and "insight evidence: Escape returns to the same card...";
`tests/model.test.mjs` "evidenceFacts: ...", "windowLabel: ..." and
"insights: windows, every date and rule statuses ride along...".

## Not covered here

Each card's example numbers came from private logs and fixtures. This file
cites only named tests, which use synthetic data.
