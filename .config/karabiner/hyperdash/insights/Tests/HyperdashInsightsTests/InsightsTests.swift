import Foundation
import Testing

@testable import HyperdashInsights

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date { parseTimestamp(text, calendar: calendar)! }

private let now = date("2026-10-15T15:00:00")

private func parsed(_ lines: [String]) -> ParsedLog {
    parseLog(lines.joined(separator: "\n"), calendar: calendar)
}

private func log(_ lines: [String]) -> [PressEvent] { parsed(lines).events }

/// An unbound press 75 days before `now`. It gives every test a long recording history
/// unless the test passes `anchored: false`.
private let anchor = "2026-08-01T00:00:00\tz\tz"

private func line(_ time: String, _ layer: String, _ key: String) -> String {
    "\(time)\t\(layer)\t\(key)"
}

/// `count` presses of one combo, one per minute starting at `hour`:00 on `day`.
private func presses(_ count: Int, _ layer: String, _ key: String, day: String, hour: Int = 9)
    -> [String]
{
    (0..<count).map {
        line(
            "\(day)T\(String(format: "%02d", hour + $0 / 60)):\(String(format: "%02d", $0 % 60)):00",
            layer, key)
    }
}

/// October 2026 day, as "2026-10-DD".
private func oct(_ day: Int) -> String { String(format: "2026-10-%02d", day) }

/// One count per consecutive October day starting at `first`.
private func daily(
    _ layer: String, _ key: String, from first: Int, _ counts: [Int], hour: Int = 9
) -> [String] {
    counts.enumerated().flatMap {
        presses($0.element, layer, key, day: oct(first + $0.offset), hour: hour)
    }
}

private func context(_ time: String, _ kind: String, _ value: String = "-") -> String {
    "\(time)\t\(kind)\t\(value)"
}

private func parsedContext(_ lines: [String]) -> ParsedContext {
    parseContextLog(lines.joined(separator: "\n"), calendar: calendar)
}

private func report(
    _ lines: [String], bindings: [Binding] = [], anchored: Bool = true, at time: Date = now,
    context contextLines: [String]? = nil
) -> InsightReport {
    let result = parsed((anchored ? [anchor] : []) + lines)
    return computeReport(
        events: result.events, bindings: bindings, now: time,
        rejectedLines: result.rejectedLines,
        context: contextLines.map { parsedContext($0).events }, calendar: calendar)
}

private func insight(_ kind: InsightKind, in report: InsightReport) -> Insight? {
    report.insights.first { $0.kind == kind }
}

@Suite struct ParsingTests {
    @Test func skipsMalformedLines() {
        let events = log([
            line("2026-10-15T14:36:07", "w", "u"),
            "garbage",
            line("2026-13-15T14:36:07", "w", "u"),
            line("2026-02-31T14:36:07", "w", "u"),
            "2026-10-15T14:36:07\tw",
            "2026-10-15T14:36:07\tw\t",
            line("2026-10-15T14:36:08", "o", "t"),
        ])
        #expect(events.count == 2)
        #expect(events[1].combo == Combo(layer: "o", key: "t"))
    }

    // These fixtures are shared with the JavaScript tests (contract section 1).
    @Test func countsRejectedLines() {
        let result = parsed([
            line("2026-10-15T14:36:07", "w", "u"),  // valid
            "",  // blank lines are ignored, not rejected
            "garbage",  // 1
            line("2026-13-15T14:36:07", "w", "u"),  // 2 month 13
            line("2026-02-31T14:36:07", "w", "u"),  // 3 day does not exist
            line("2026-10-15T24:00:00", "w", "u"),  // 4 hour 24
            line("2026-10-15 14:36:07", "w", "u"),  // 5 space instead of T
            line("2026-10-15T14:36", "w", "u"),  // 6 no seconds
            line("2026-10-15T14:36:07", "W", "u"),  // 7 uppercase layer
            line("2026-10-15T14:36:07", "w", "u v"),  // 8 space in key
            line("2026-10-15T14:36:07", "w", ";"),  // 9 punctuation key
            line("2026-10-15T14:36:07", "", "u"),  // 10 empty layer
            "2026-10-15T14:36:07\tw\tu\textra",  // 11 four fields
            "2026-10-15T14:36:07\tw",  // 12 two fields
            line("0099-10-15T14:36:07", "w", "u"),  // 13 year before 1970
            line("2026-10-15T14:36:07", "o", "spacebar"),  // valid
            line("2026-10-15T14:36:07", "o", "keypad_1"),  // valid
        ])
        #expect(result.events.count == 3)
        #expect(result.rejectedLines == 13)
    }

    @Test func acceptsWindowsLineEndings() {
        let result = parseLog("2026-10-15T14:36:07\tw\tu\r\n2026-10-15T14:36:08\tw\tu\r\n", calendar: calendar)
        #expect(result.events.count == 2)
        #expect(result.rejectedLines == 0)
    }

    @Test func futureEventsAreValidButIgnoredByAnalysis() {
        let lines = presses(30, "w", "u", day: "2026-10-16")
        let result = report(lines, anchored: false)
        #expect(parsed(lines).rejectedLines == 0)
        #expect(result.monthTotal == 0)
        #expect(result.recordingSince == nil)
        #expect(result.insights.isEmpty)
    }

    @Test func formatsTimestamp() {
        #expect(formatTimestamp(now, calendar: calendar) == "2026-10-15T15:00:00")
    }
}


// MARK: - Context log parsing

@Suite struct ContextParsingTests {
    @Test func parsesAllKinds() {
        let result = parsedContext([
            context("2026-10-15T14:36:07.123", "start"),
            context("2026-10-15T14:36:08.000", "app", "com.mitchellh.ghostty"),
            context("2026-10-15T14:40:00.999", "lock"),
            context("2026-10-15T14:41:00.000", "unlock"),
            context("2026-10-15T14:42:00.000", "sleep"),
            context("2026-10-15T14:43:00.000", "wake"),
        ])
        #expect(result.events.count == 6)
        #expect(result.rejectedLines == 0)
        #expect(result.events[1].kind == .app)
        #expect(result.events[1].value == "com.mitchellh.ghostty")
    }

    @Test func keepsMilliseconds() {
        let event = parsedContext([context("2026-10-15T14:36:07.500", "start")]).events[0]
        #expect(event.date.timeIntervalSince(date("2026-10-15T14:36:07")) == 0.5)
    }

    @Test func rejectsMalformedLines() {
        let result = parsedContext([
            context("2026-10-15T14:36:07.123", "start"),  // valid
            "",  // ignored
            context("2026-10-15T14:36:07", "start"),  // 1 no milliseconds
            context("2026-10-15T14:36:07.12", "start"),  // 2 two-digit milliseconds
            context("2026-10-15T14:36:07.1x3", "start"),  // 3 non-digit milliseconds
            context("2026-13-15T14:36:07.123", "start"),  // 4 bad date
            context("2026-10-15T14:36:07.123", "focus"),  // 5 unknown kind
            context("2026-10-15T14:36:07.123", "lock", "x"),  // 6 value must be -
            context("2026-10-15T14:36:07.123", "app", "-"),  // 7 app needs a bundle ID
            context("2026-10-15T14:36:07.123", "app", "com.a b"),  // 8 space in value
            context("2026-10-15T14:36:07.123", "app", ""),  // 9 empty value
            "2026-10-15T14:36:07.123\tapp\tcom.a\textra",  // 10 four fields
            "2026-10-15T14:36:07.123\tapp",  // 11 two fields
            "garbage",  // 12
        ])
        #expect(result.events.count == 1)
        #expect(result.rejectedLines == 12)
    }

    @Test func sortsByTime() {
        let result = parsedContext([
            context("2026-10-15T14:36:09.000", "wake"),
            context("2026-10-15T14:36:07.000", "sleep"),
        ])
        #expect(result.events.map(\.kind) == [.sleep, .wake])
    }
}

// MARK: - Recorded days and attribution

@Suite struct RecordedDaysTests {
    let lines = (10...15).map { line("\(oct($0))T12:00:00", "w", "u") }
    var events: [PressEvent] { log(lines) }

    func days(_ contextLines: [String]?) -> Set<String> {
        recordedDays(
            events: events, context: contextLines.map { parsedContext($0).events }, now: now,
            calendar: calendar)
    }

    @Test func withoutContextUsesDaysAfterFirstEventAndBeforeToday() {
        #expect(days(nil) == [oct(11), oct(12), oct(13), oct(14)])
    }

    @Test func emptyLogHasNoRecordedDays() {
        #expect(recordedDays(events: [], context: nil, now: now, calendar: calendar).isEmpty)
    }

    @Test func pressBeforeFirstStartMarksDayUnknown() {
        let result = days([context("\(oct(12))T00:00:00.000", "start")])
        #expect(result == [oct(12), oct(13), oct(14)])
    }

    @Test func pressInsideGapBetweenSessionsMarksDayUnknown() {
        let result = days([
            context("2026-08-01T00:00:00.000", "start"),
            context("\(oct(13))T10:00:00.000", "app", "com.a.one"),
            context("\(oct(13))T14:00:00.000", "start"),
        ])
        #expect(result == [oct(11), oct(12), oct(14)])
    }

    @Test func emptyDayOutsideEverySessionIsNotRecorded() {
        // One press on 1 October; recording starts on 12 October. 2 to 11 October have no
        // presses and no session, so nothing shows that the recorder saw them.
        let result = recordedDays(
            events: log([line("\(oct(1))T12:00:00", "w", "u")]),
            context: parsedContext([context("\(oct(12))T00:00:00.000", "start")]).events,
            now: now, calendar: calendar)
        #expect(result == [oct(12), oct(13), oct(14)])
    }

    @Test func lockAndSleepInsideSessionDoNotBreakIt() {
        let result = days([
            context("2026-08-01T00:00:00.000", "start"),
            context("\(oct(13))T11:00:00.000", "lock"),
            context("\(oct(13))T13:00:00.000", "unlock"),
        ])
        #expect(result == [oct(11), oct(12), oct(13), oct(14)])
    }

    @Test func gapOfSixtySecondsOrLessIsBridged() {
        let result = days([
            context("2026-08-01T00:00:00.000", "start"),
            context("\(oct(13))T11:59:50.000", "app", "com.a.one"),
            context("\(oct(13))T12:00:50.000", "start"),  // 60 s gap
        ])
        #expect(result.contains(oct(13)))
    }

    @Test func gapOverSixtySecondsIsNotBridged() {
        let result = days([
            context("2026-08-01T00:00:00.000", "start"),
            context("\(oct(13))T11:59:50.000", "app", "com.a.one"),
            context("\(oct(13))T12:00:51.000", "start"),  // 61 s gap
        ])
        #expect(!result.contains(oct(13)))
    }

    @Test func eventsAfterNowAreIgnored() {
        // The only session would start after now, so no press is covered.
        let result = days([context("2026-10-16T00:00:00.000", "start")])
        #expect(result.isEmpty)
    }
}

@Suite struct AttributionTests {
    let one = "com.a.one"
    let two = "com.b.two"

    func attribute(_ pressTimes: [String], _ contextLines: [String]) -> [String?] {
        attributeApps(
            events: log(pressTimes.map { line($0, "w", "u") }),
            context: parsedContext(contextLines).events, now: now, calendar: calendar)
    }

    @Test func appEventInSameSecondIsLater() {
        let result = attribute(
            ["2026-10-14T14:36:07"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T14:36:07.500", "app", two),
            ])
        #expect(result == [one])
    }

    @Test func appEventExactlyAtPressSecondIsLater() {
        let result = attribute(
            ["2026-10-14T14:36:07"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T14:36:07.000", "app", two),
            ])
        #expect(result == [one])
    }

    @Test func appEventInEarlierSecondIsBefore() {
        let result = attribute(
            ["2026-10-14T14:36:07", "2026-10-14T14:36:08"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T14:36:06.999", "app", two),
            ])
        #expect(result == [two, two])
    }

    @Test func pressBeforeAnyAppEventIsUnknown() {
        let result = attribute(
            ["2026-10-14T14:05:00"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
            ])
        #expect(result == [nil])
    }

    @Test func pressBeforeFirstStartIsUnknown() {
        let result = attribute(
            ["2026-10-14T13:00:00"],
            [
                context("2026-10-14T12:00:00.000", "app", one),
                context("2026-10-14T14:00:00.000", "start"),
            ])
        #expect(result == [nil])
    }

    @Test func startForgetsPreviousApp() {
        let result = attribute(
            ["2026-10-14T14:25:00", "2026-10-14T14:35:00"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T14:20:00.000", "start"),
                context("2026-10-14T14:30:00.000", "app", two),
            ])
        #expect(result == [nil, two])
    }

    @Test func pressInGapBetweenSessionsIsUnknown() {
        let result = attribute(
            ["2026-10-14T14:30:00"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T15:00:00.000", "start"),
            ])
        #expect(result == [nil])
    }

    @Test func lockDoesNotChangeApp() {
        let result = attribute(
            ["2026-10-14T14:30:00"],
            [
                context("2026-10-14T14:00:00.000", "start"),
                context("2026-10-14T14:10:00.000", "app", one),
                context("2026-10-14T14:20:00.000", "lock"),
                context("2026-10-14T14:25:00.000", "unlock"),
            ])
        #expect(result == [one])
    }

    @Test func noContextEventsMeansUnknown() {
        #expect(attribute(["2026-10-14T14:30:00"], []) == [nil])
    }
}

// MARK: - Trend

@Suite struct TrendTests {
    let bindings = [
        Binding(layer: "w", key: "u", label: "Previous Tab"),
        Binding(layer: "o", key: "t", label: "Ghostty"),
        Binding(layer: "s", key: "a", label: "Volume"),
        Binding(layer: "s", key: "b", label: "Mute"),
    ]
    // The two weeks before 2026-10-15 are 1-7 (previous) and 8-14 (recent).
    let steady100: [Int] = [14, 14, 14, 14, 14, 15, 15]
    let steady300: [Int] = [43, 43, 43, 43, 43, 43, 42]

    func week(_ layer: String, _ key: String, previous: [Int], recent: [Int]) -> [String] {
        daily(layer, key, from: 1, previous) + daily(layer, key, from: 8, recent)
    }

    @Test func rising() {
        let found = insight(
            .rising, in: report(week("w", "u", previous: steady100, recent: steady300), bindings: bindings))
        #expect(found?.title == "Previous Tab up 200 presses")
        #expect(found?.detail == "W U · 300 vs 100 the week before · up on 7 days")
        #expect(found?.measure == Measure(count: 300, total: nil, baseline: 100, unit: "presses"))
        #expect(found?.keys == [["w", "u"]])
        #expect(found?.value == 200)
        #expect(found?.dates == (8...14).map(oct))
        #expect(found?.windowStart == oct(8))
        #expect(found?.windowEnd == oct(14))
        #expect(found?.comparisonStart == oct(1))
        #expect(found?.comparisonEnd == oct(7))
    }

    @Test func falling() {
        let found = insight(
            .falling, in: report(week("w", "u", previous: steady300, recent: steady100), bindings: bindings))
        #expect(found?.title == "Previous Tab down 200 presses")
        #expect(found?.detail == "W U · 100 vs 300 the week before · down on 7 days")
        #expect(found?.value == 200)
    }

    @Test func oneToFiveDoesNotBeatHundredToThreeHundred() {
        let lines =
            week("o", "t", previous: [1, 0, 0, 0, 0, 0, 0], recent: [1, 1, 1, 1, 1, 0, 0])
            + week("w", "u", previous: steady100, recent: steady300)
        let found = insight(.rising, in: report(lines, bindings: bindings))
        #expect(found?.keys == [["w", "u"]])
        #expect(found?.value == 200)
    }

    @Test func smallChangesBelowMinimumCountsAreIgnored() {
        let lines = week("o", "t", previous: [1, 0, 0, 0, 0, 0, 0], recent: [1, 1, 1, 1, 1, 0, 0])
        let result = report(lines, bindings: bindings)
        #expect(insight(.rising, in: result) == nil)
        #expect(insight(.falling, in: result) == nil)
    }

    @Test func absoluteChangeBeatsPercentageChange() {
        // 6 to 30 is +400% but +24 presses. 100 to 160 is +60% but +60 presses.
        let lines =
            week("s", "a", previous: [1, 1, 1, 1, 1, 1, 0], recent: [5, 5, 5, 5, 5, 5, 0])
            + week("s", "b", previous: steady100, recent: [23, 23, 23, 23, 23, 23, 22])
        let found = insight(.rising, in: report(lines, bindings: bindings))
        #expect(found?.keys == [["s", "b"]])
        #expect(found?.value == 60)
    }

    @Test func oneDaySpikeDoesNotCount() {
        // +50 presses, all on one day. It is not repeated across days.
        let lines = week("o", "t", previous: [10, 10, 10, 10, 10, 10, 10], recent: [0, 0, 0, 0, 0, 0, 120])
        #expect(insight(.rising, in: report(lines, bindings: bindings)) == nil)
    }

    @Test func oneDaySpikeOnFewPressesDoesNotCount() {
        // 2 to 73: +71 presses, 70 of them on one day. The other three days beat a weekly
        // mean of 2/7 with a single press each.
        let lines = week("w", "u", previous: [2, 0, 0, 0, 0, 0, 0], recent: [1, 1, 1, 0, 0, 0, 70])
        #expect(insight(.rising, in: report(lines, bindings: bindings)) == nil)
    }

    @Test func oneDaySpikeInEarlierWeekDoesNotCountAsFalling() {
        // 70 to 35: the earlier week is one day of 70. Without it nothing fell.
        let lines = week("w", "u", previous: [70, 0, 0, 0, 0, 0, 0], recent: [5, 5, 5, 5, 5, 5, 5])
        #expect(insight(.falling, in: report(lines, bindings: bindings)) == nil)
    }

    @Test func steadyChangeBeatsLargerSpike() {
        let lines =
            week("o", "t", previous: [10, 10, 10, 10, 10, 10, 10], recent: [0, 0, 0, 0, 0, 0, 120])
            + week("s", "a", previous: [5, 5, 5, 5, 5, 5, 5], recent: [10, 10, 10, 10, 10, 10, 10])
        let found = insight(.rising, in: report(lines, bindings: bindings))
        #expect(found?.keys == [["s", "a"]])
        #expect(found?.value == 35)
    }

    @Test func needsAtLeastFourRepeatDays() {
        // 70 to 105: +35 presses, higher than the weekly mean on only 3 days.
        let lines = week("s", "a", previous: [10, 10, 10, 10, 10, 10, 10], recent: [0, 0, 0, 0, 35, 35, 35])
        #expect(insight(.rising, in: report(lines, bindings: bindings)) == nil)
    }

    @Test func todayIsNotPartOfEitherWindow() {
        let lines = presses(300, "w", "u", day: oct(15), hour: 8)
        let result = report(lines, bindings: bindings)
        #expect(insight(.rising, in: result) == nil)
        #expect(insight(.falling, in: result) == nil)
    }

    @Test func needsFourteenFullyRecordedDays() {
        // Recording began on 2026-10-01, so that day is not fully recorded.
        let lines = week("w", "u", previous: steady100, recent: steady300)
        let result = report(lines, bindings: bindings, anchored: false)
        #expect(insight(.rising, in: result) == nil)
        #expect(
            result.rules.first { $0.rule == "trend" }
                == RuleStatus(
                    rule: "trend", status: .notReady,
                    reason: "Week comparisons need 14 recorded days; 13 qualify."))
    }

    @Test func explainsWhenNoShortcutChanged() {
        let lines = week("w", "u", previous: steady100, recent: steady100)
        let status = report(lines, bindings: bindings).rules.first { $0.rule == "trend" }
        #expect(status?.status == .noPattern)
        #expect(status?.reason == "No shortcut changed by 5+ presses on 4+ of the last 7 days.")
    }

    @Test func allowsTrendWhenRecordingBeganTheDayBeforeTheWindow() {
        let lines = presses(1, "w", "u", day: "2026-09-30") + week("w", "u", previous: steady100, recent: steady300)
        #expect(insight(.rising, in: report(lines, bindings: bindings, anchored: false)) != nil)
    }

    @Test func gapInContextInsideWindowBlocksTrend() {
        let lines = week("w", "u", previous: steady100, recent: steady300)
        let withGap = report(
            lines, bindings: bindings,
            context: [
                context("2026-08-01T00:00:00.000", "start"),
                context("\(oct(3))T12:00:00.000", "app", "com.a.one"),
                context("\(oct(5))T00:00:00.000", "start"),
            ])
        #expect(insight(.rising, in: withGap) == nil)
        let withoutGap = report(lines, bindings: bindings, context: [context("2026-08-01T00:00:00.000", "start")])
        #expect(insight(.rising, in: withoutGap) != nil)
    }

    @Test func groupsThousands() {
        let found = insight(
            .rising,
            in: report(week("w", "u", previous: [150, 150, 150, 150, 150, 150, 150], recent: [300, 300, 300, 300, 300, 300, 300]),
                       bindings: bindings))
        #expect(found?.title == "Previous Tab up 1,050 presses")
        #expect(found?.detail == "W U · 2,100 vs 1,050 the week before · up on 7 days")
    }

    @Test func longLabelIsKeptWhole() {
        let label = String(repeating: "L", count: 60)
        let long = [Binding(layer: "w", key: "u", label: label)]
        let found = insight(
            .rising, in: report(week("w", "u", previous: steady100, recent: steady300), bindings: long))
        #expect(found?.title == label + " up 200 presses")
    }

    @Test func fallsBackToHyperName() {
        let found = insight(
            .rising, in: report(week("w", "x", previous: steady100, recent: steady300)))
        #expect(found?.title == "Hyper W X up 200 presses")
    }
}

// MARK: - Unused

@Suite struct UnusedTests {
    func layer(_ name: String, _ count: Int) -> [Binding] {
        (0..<count).map { Binding(layer: name, key: "k\($0)", label: "x") }
    }

    /// Presses on 2026-10-10 to 2026-10-14 for the first `used` keys of a layer.
    func used(_ name: String, _ used: Int) -> [String] {
        (0..<used).flatMap { daily(name, "k\($0)", from: 10, [1, 1, 1, 1, 1], hour: 8 + $0 / 10) }
    }

    @Test func prefersHighestShareOverLargestCount() {
        // Window: 10 of 32 unused (31%). System: 3 of 4 unused (75%).
        let bindings = layer("w", 32) + layer("s", 4)
        let found = insight(.unused, in: report(used("w", 22) + used("s", 1), bindings: bindings))
        #expect(found?.title == "3 of 4 System shortcuts unused in 30 days")
        #expect(found?.value == 3)
        #expect(found?.keys == [["s", "k1"], ["s", "k2"], ["s", "k3"]])
    }

    @Test func reportsRecordedDays() {
        let bindings = layer("w", 5)
        let found = insight(.unused, in: report(used("w", 1), bindings: bindings))
        #expect(found?.title == "4 of 5 Window shortcuts unused in 30 days")
        #expect(found?.detail == "4 never pressed since Aug 1 · 30 of 30 days recorded")
        #expect(found?.measure == Measure(count: 4, total: 5, baseline: nil, unit: "bindings"))
        #expect(found?.dates.count == 30)
        #expect(found?.dates.last == oct(14))
    }

    @Test func separatesNeverPressedFromLapsed() {
        let bindings = layer("w", 5)
        let lines = used("w", 1) + presses(1, "w", "k1", day: "2026-09-01") + presses(1, "w", "k2", day: "2026-09-05")
        let found = insight(.unused, in: report(lines, bindings: bindings))
        #expect(found?.title == "4 of 5 Window shortcuts unused in 30 days")
        #expect(found?.detail == "2 never pressed since Aug 1 · 2 last pressed Sep 5 or earlier · 30 of 30 days recorded")
        // Never pressed first, then lapsed, each in binding order.
        #expect(found?.keys == [["w", "k3"], ["w", "k4"], ["w", "k1"], ["w", "k2"]])
    }

    @Test func oneLapsedNamesItsDay() {
        let lines = used("w", 4) + presses(1, "w", "k4", day: "2026-09-05")
        let found = insight(.unused, in: report(lines, bindings: layer("w", 8)))
        #expect(found?.detail == "3 never pressed since Aug 1 · 1 last pressed Sep 5 · 30 of 30 days recorded")
    }

    @Test func archivedPressIsNotNeverPressed() {
        let bindings = layer("w", 5)
        let archive = ArchivedHistory(
            first: date("2026-07-01T00:00:00"), rejected: 0,
            comboDays: [Combo(layer: "w", key: "k1"): ["2026-07-10": 2]])
        let result = computeReport(
            events: log(used("w", 1)), bindings: bindings, now: now, archive: archive, calendar: calendar)
        let found = insight(.unused, in: result)
        #expect(found?.detail == "3 never pressed since Jul 1 · 1 last pressed Jul 10 · 30 of 30 days recorded")
        #expect(found?.keys.last == ["w", "k1"])
    }

    @Test func ignoresLayersWithFewerThanFourBindings() {
        let bindings = layer("r", 3)
        #expect(insight(.unused, in: report([], bindings: bindings)) == nil)
    }

    @Test func needsThreeUnused() {
        let bindings = layer("w", 5)
        #expect(insight(.unused, in: report(used("w", 3), bindings: bindings)) == nil)
    }

    @Test func needsFourteenFullyRecordedDays() {
        let bindings = layer("w", 5)
        // First press on 2026-10-01: 2 to 14 October, 13 days, are fully recorded.
        let thirteen = presses(1, "w", "k0", day: oct(1))
        #expect(insight(.unused, in: report(thirteen, bindings: bindings, anchored: false)) == nil)
        // First press on 2026-09-30: 1 to 14 October.
        let fourteen = presses(1, "w", "k0", day: "2026-09-30")
        let found = insight(.unused, in: report(fourteen, bindings: bindings, anchored: false))
        #expect(found?.detail == "4 never pressed since Sep 30 · 14 of 30 days recorded")
        #expect(found?.dates.count == 14)
        #expect(found?.dates.first == oct(1))
    }

    @Test func emptyLogMakesNoClaim() {
        #expect(insight(.unused, in: report([], bindings: layer("w", 5), anchored: false)) == nil)
    }

    @Test func daysWithContextGapsAreNotCounted() {
        let bindings = layer("w", 5)
        let lines = presses(1, "w", "k0", day: "2026-09-30", hour: 8) + daily("w", "k0", from: 1, Array(repeating: 1, count: 14), hour: 8)
        #expect(insight(.unused, in: report(lines, bindings: bindings, anchored: false)) != nil)
        let result = report(
            lines, bindings: bindings, anchored: false,
            context: [
                context("2026-09-30T00:00:00.000", "start"),
                context("\(oct(12))T07:00:00.000", "app", "com.a.one"),
                context("\(oct(14))T00:00:00.000", "start"),
            ])
        // Presses on 12 and 13 fall in the gap, leaving 1 to 11 October and 14 October.
        #expect(insight(.unused, in: result) == nil)
        #expect(result.rules.first { $0.rule == "unused" }?.reason
                == "The unused check needs 14 recorded days in the last 30; 12 qualify.")
    }

    @Test func unobservedEmptyDaysAreNotCounted() {
        let bindings = layer("w", 5)
        let result = report(
            presses(1, "w", "k0", day: "2026-09-20"), bindings: bindings, anchored: false,
            context: [context("\(oct(1))T00:00:00.000", "start")])
        // 21 to 30 September have no session, so only 1 to 14 October count.
        let found = insight(.unused, in: result)
        #expect(found?.detail == "4 never pressed since Sep 20 · 14 of 30 days recorded")
        #expect(found?.dates.first == oct(1))
    }

    @Test func pressOlderThan30DaysDoesNotCount() {
        let bindings = layer("w", 5)
        let lines = presses(1, "w", "k0", day: "2026-09-01")
        let found = insight(.unused, in: report(lines, bindings: bindings))
        #expect(found?.title == "5 of 5 Window shortcuts unused in 30 days")
    }

    @Test func keepsEveryUnusedKey() {
        let found = insight(.unused, in: report([], bindings: layer("s", 7)))
        #expect(found?.title == "7 of 7 System shortcuts unused in 30 days")
        #expect(found?.keys.count == 7)
        #expect(found?.windowStart == "2026-09-15")
        #expect(found?.windowEnd == oct(15))
    }

    @Test func explainsTooFewRecordedDays() {
        let thirteen = presses(1, "w", "k0", day: oct(1))
        let status = report(thirteen, bindings: layer("w", 5), anchored: false).rules.first { $0.rule == "unused" }
        #expect(status?.status == .notReady)
        #expect(status?.reason == "The unused check needs 14 recorded days in the last 30; 13 qualify.")
    }
}

// MARK: - Dormant

@Suite struct DormantTests {
    let bindings = [Binding(layer: "o", key: "t", label: "Ghostty")]
    let detail = "O T · 12 presses in September · none since Oct 1"

    var september: [String] {
        presses(6, "o", "t", day: "2026-09-20") + presses(6, "o", "t", day: "2026-09-21")
    }

    @Test func reportsComboNotUsedYetThisMonth() {
        let found = insight(.dormant, in: report(september, bindings: bindings))
        #expect(found?.title == "Ghostty not used yet this month")
        #expect(found?.detail == detail)
        #expect(found?.value == 12)
        #expect(found?.measure == Measure(count: 0, total: nil, baseline: 12, unit: "presses"))
        #expect(found?.dates == ["2026-09-20", "2026-09-21"])
    }

    @Test func neverClaimsStoppedTenMinutesIntoMonth() {
        let found = insight(
            .dormant, in: report(september, bindings: bindings, at: date("2026-10-01T00:10:00")))
        #expect(found?.title == "Ghostty not used yet this month")
        #expect(found?.detail == detail)
    }

    @Test func sameWordingEightDaysIn() {
        let found = insight(
            .dormant, in: report(september, bindings: bindings, at: date("2026-10-09T12:00:00")))
        #expect(found?.title == "Ghostty not used yet this month")
    }

    @Test func longLabelIsKeptWhole() {
        let label = String(repeating: "L", count: 60)
        let found = insight(.dormant, in: report(september, bindings: [Binding(layer: "o", key: "t", label: label)]))
        #expect(found?.title == label + " not used yet this month")
    }

    @Test func comparesThisMonthWithLastMonth() {
        let found = insight(.dormant, in: report(september, bindings: bindings))
        #expect(found?.windowStart == oct(1))
        #expect(found?.windowEnd == oct(15))
        #expect(found?.comparisonStart == "2026-09-01")
        #expect(found?.comparisonEnd == "2026-09-30")
    }

    @Test func needsPreviousMonthRecordedFromItsFirstDay() {
        // Recording began 2026-09-02, one day after September began.
        let lines = presses(3, "o", "t", day: "2026-09-02") + presses(3, "o", "t", day: "2026-09-03")
        let result = report(lines, bindings: bindings, anchored: false)
        #expect(insight(.dormant, in: result) == nil)
        #expect(
            result.rules.first { $0.rule == "dormant" }?.reason
                == "The not-used-yet check needs all of September recorded; recording began Sep 2.")
    }

    @Test func allowsRecordingThatBeganOnFirstDayOfPreviousMonth() {
        let lines = presses(3, "o", "t", day: "2026-09-01", hour: 23) + presses(3, "o", "t", day: "2026-09-02")
        #expect(insight(.dormant, in: report(lines, bindings: bindings, anchored: false)) != nil)
    }

    @Test func notDormantIfUsedThisMonth() {
        let lines = september + presses(1, "o", "t", day: oct(2))
        #expect(insight(.dormant, in: report(lines)) == nil)
    }

    @Test func needsThreePresses() {
        let lines = presses(1, "o", "t", day: "2026-09-20") + presses(1, "o", "t", day: "2026-09-21")
        #expect(insight(.dormant, in: report(lines)) == nil)
    }

    @Test func needsTwoDays() {
        #expect(insight(.dormant, in: report(presses(12, "o", "t", day: "2026-09-20"))) == nil)
    }

    @Test func picksMostPressed() {
        let lines = september + presses(8, "o", "f", day: "2026-09-20", hour: 10) + presses(8, "o", "f", day: "2026-09-21", hour: 10)
        #expect(insight(.dormant, in: report(lines))?.keys == [["o", "f"]])
        #expect(insight(.dormant, in: report(lines))?.value == 16)
    }
}

// MARK: - Burst

@Suite struct BurstTests {
    /// A run of `count` presses two seconds apart in minute `minute` of 08:00 on `day`.
    func run(_ count: Int, _ layer: String, _ key: String, minute: Int, day: Int = 10) -> [String] {
        (0..<count).map {
            line("\(oct(day))T08:\(String(format: "%02d", minute)):\(String(format: "%02d", $0 * 2))", layer, key)
        }
    }

    @Test func reportsComboWithMostBursts() {
        let lines = run(5, "v", "q", minute: 1) + run(6, "v", "q", minute: 3, day: 11)
            + run(5, "w", "u", minute: 5)
        let found = insight(.burst, in: report(lines, bindings: [Binding(layer: "v", key: "q", label: "Left Click")]))
        #expect(found?.title == "Left Click repeats in bursts")
        #expect(found?.detail == "2 bursts on 2 days · each 5+ presses in a row")
        #expect(found?.measure == Measure(count: 2, total: nil, baseline: nil, unit: "bursts"))
        #expect(found?.value == 2)
        #expect(found?.dates == [oct(10), oct(11)])
    }

    @Test func needsTwoBursts() {
        #expect(insight(.burst, in: report(run(5, "v", "q", minute: 1))) == nil)
    }

    @Test func needsBurstsOnTwoDays() {
        let lines = run(5, "v", "q", minute: 1) + run(5, "v", "q", minute: 3)
        #expect(insight(.burst, in: report(lines)) == nil)
    }

    @Test func gapOverThreeSecondsBreaksRun() {
        let slow = (0..<10).map { line("\(oct(10))T08:01:\(String(format: "%02d", $0 * 4))", "v", "q") }
        #expect(insight(.burst, in: report(slow + run(5, "v", "q", minute: 3, day: 11))) == nil)
    }

    @Test func otherComboBreaksRun() {
        let lines = run(4, "v", "q", minute: 1) + [line("\(oct(10))T08:01:08", "w", "u")]
            + run(4, "v", "q", minute: 2)
        #expect(insight(.burst, in: report(lines)) == nil)
    }
}

// MARK: - Pair

@Suite struct PairTests {
    let bindings = [
        Binding(layer: "o", key: "t", label: "Ghostty", category: "app-launch"),
        Binding(layer: "w", key: "h", label: "Left half", category: "window-arrangement"),
        Binding(layer: "s", key: "a", label: "Lock", category: "system"),
        Binding(layer: "v", key: "q", label: "Left Click", category: "pointer"),
        Binding(layer: "t", key: "j", label: "Word left", category: "text-navigation"),
        Binding(layer: "t", key: "k", label: "Word right", category: "text-navigation"),
    ]

    /// One press of `first`, then one of `second` `gap` seconds later, at 10:`minute` on `day`.
    func pair(
        day: Int, minute: Int = 0, gap: Int = 5, _ first: (String, String) = ("o", "t"),
        _ second: (String, String) = ("w", "h")
    ) -> [String] {
        let time = "\(oct(day))T10:\(String(format: "%02d", minute))"
        return [
            line("\(time):00", first.0, first.1),
            line("\(time):\(String(format: "%02d", gap))", second.0, second.1),
        ]
    }

    /// 5 pairs on 4 days, 2 on the busiest: the smallest set the rule accepts.
    func threshold(gap: Int = 5) -> [String] {
        pair(day: 3, gap: gap) + pair(day: 3, minute: 30, gap: gap) + pair(day: 4, gap: gap)
            + pair(day: 5, gap: gap) + pair(day: 6, gap: gap)
    }

    @Test func reportsRecurringPair() {
        let found = insight(.pair, in: report(threshold(), bindings: bindings))
        #expect(found?.title == "Ghostty then Left half: 5 times")
        #expect(found?.detail == "O T · then W H within 5 s · on 4 of the last 14 days")
        #expect(found?.keys == [["o", "t"], ["w", "h"]])
        #expect(found?.value == 5)
        #expect(found?.dates == [oct(3), oct(4), oct(5), oct(6)])
        #expect(found?.windowStart == oct(2))
        #expect(found?.windowEnd == oct(15))
        #expect(found?.comparisonStart == nil)
        #expect(found?.measure == Measure(count: 5, total: nil, baseline: nil, unit: "pairs"))
    }

    @Test func needsFivePairs() {
        let lines = pair(day: 3) + pair(day: 4) + pair(day: 5) + pair(day: 6)
        let result = report(lines, bindings: bindings)
        #expect(insight(.pair, in: result) == nil)
        let status = result.rules.first { $0.rule == "pair" }
        #expect(status?.status == .noPattern)
        #expect(
            status?.reason
                == "No two shortcuts came one right after the other (within 5 s) 5+ times on 4+ of the last 14 days.")
    }

    @Test func needsThreeDaysWithoutTheBusiestDay() {
        // 6 pairs on 3 days: dropping the busiest leaves 2 days.
        let lines = pair(day: 3) + pair(day: 3, minute: 30) + pair(day: 3, minute: 40) + pair(day: 4)
            + pair(day: 5) + pair(day: 5, minute: 30)
        #expect(insight(.pair, in: report(lines, bindings: bindings)) == nil)
        #expect(insight(.pair, in: report(lines + pair(day: 6), bindings: bindings)) != nil)
    }

    @Test func gapOverFiveSecondsIsNoPair() {
        #expect(insight(.pair, in: report(threshold(gap: 5), bindings: bindings)) != nil)
        #expect(insight(.pair, in: report(threshold(gap: 6), bindings: bindings)) == nil)
    }

    @Test func pressBetweenBreaksPair() {
        let lines = threshold().enumerated().flatMap { index, text in
            // A Lock press one second after each Ghostty press.
            index % 2 == 0 ? [text, line(String(text.prefix(17)) + "01", "s", "a")] : [text]
        }
        // Ghostty then Lock, and Lock then Left half, take its place; the first sorts first.
        #expect(insight(.pair, in: report(lines, bindings: bindings))?.keys == [["o", "t"], ["s", "a"]])
    }

    @Test func sameComboTwiceIsNoPair() {
        let lines = [3, 4, 5, 6, 7].flatMap { pair(day: $0, ("o", "t"), ("o", "t")) }
        let result = report(lines, bindings: bindings)
        #expect(insight(.pair, in: result) == nil)
        #expect(result.rules.first { $0.rule == "pair" }?.status == .noPattern)
    }

    @Test func ignoresPointerAndTextNavigation() {
        let days = [3, 4, 5, 6, 7]
        let pointer = days.flatMap { pair(day: $0, ("o", "t"), ("v", "q")) }
        #expect(insight(.pair, in: report(pointer, bindings: bindings)) == nil)
        let text = days.flatMap { pair(day: $0, ("t", "j"), ("t", "k")) }
        #expect(insight(.pair, in: report(text, bindings: bindings)) == nil)
        let window = days.flatMap { pair(day: $0, ("o", "t"), ("w", "h")) }
        #expect(insight(.pair, in: report(window, bindings: bindings)) != nil)
    }

    @Test func countsOnlyTheLastFourteenDays() {
        // October 1 is 14 days before today, one day out.
        let lines = pair(day: 3) + pair(day: 3, minute: 30) + pair(day: 4) + pair(day: 5)
        #expect(insight(.pair, in: report(pair(day: 1) + lines, bindings: bindings)) == nil)
        #expect(insight(.pair, in: report(pair(day: 2) + lines, bindings: bindings)) != nil)
    }
}

// MARK: - Double

@Suite struct DoubleTests {
    let bindings = [
        Binding(layer: "o", key: "d", label: "Discord", category: "app-launch"),
        Binding(layer: "b", key: "y", label: "youtube.com", category: "site-open"),
        Binding(layer: "w", key: "h", label: "Left half", category: "window-arrangement"),
        Binding(layer: "s", key: "a", label: "Lock", category: "system"),
    ]

    /// `count` presses of one combo, each `gap` seconds after the last, at `hour`:00 on `day`.
    func run(
        _ count: Int, _ layer: String = "o", _ key: String = "d", day: Int, hour: Int = 11, gap: Int = 2
    ) -> [String] {
        (0..<count).map {
            line("\(oct(day))T\(hour):00:\(String(format: "%02d", $0 * gap))", layer, key)
        }
    }

    /// One double on each of `days`.
    func doubles(_ days: [Int], _ layer: String = "o", _ key: String = "d", gap: Int = 2) -> [String] {
        days.flatMap { run(2, layer, key, day: $0, gap: gap) }
    }

    @Test func reportsDoubles() {
        let found = insight(.double, in: report(doubles([3, 4, 5, 6, 7]), bindings: bindings))
        #expect(found?.title == "Discord pressed twice in 2 s: 5 times")
        #expect(found?.detail == "O D · on 5 of the last 14 days")
        #expect(found?.keys == [["o", "d"]])
        #expect(found?.value == 5)
        #expect(found?.dates == [oct(3), oct(4), oct(5), oct(6), oct(7)])
        #expect(found?.windowStart == oct(2))
        #expect(found?.windowEnd == oct(15))
        #expect(found?.measure == Measure(count: 5, total: nil, baseline: nil, unit: "doubles"))
    }

    @Test func countsSiteOpen() {
        #expect(insight(.double, in: report(doubles([3, 4, 5, 6, 7], "b", "y"), bindings: bindings)) != nil)
    }

    @Test func needsFiveDoubles() {
        let result = report(doubles([3, 4, 5, 6]), bindings: bindings)
        #expect(insight(.double, in: result) == nil)
        let status = result.rules.first { $0.rule == "double" }
        #expect(status?.status == .noPattern)
        #expect(
            status?.reason
                == "No app, site or capture shortcut was pressed twice within 2 s 5+ times on 3+ of the last 14 days.")
    }

    @Test func needsThreeDays() {
        // 6 doubles on 2 days.
        let lines = [11, 12, 13].flatMap { hour in [3, 4].flatMap { run(2, day: $0, hour: hour) } }
        #expect(insight(.double, in: report(lines, bindings: bindings)) == nil)
        #expect(insight(.double, in: report(lines + run(2, day: 5), bindings: bindings)) != nil)
    }

    @Test func gapOverTwoSecondsIsNoDouble() {
        #expect(insight(.double, in: report(doubles([3, 4, 5, 6, 7], gap: 2), bindings: bindings)) != nil)
        #expect(insight(.double, in: report(doubles([3, 4, 5, 6, 7], gap: 3), bindings: bindings)) == nil)
    }

    @Test func burstIsNoDouble() {
        let days = [3, 4, 5, 6, 7]
        #expect(insight(.double, in: report(days.flatMap { run(2, day: $0, gap: 1) }, bindings: bindings)) != nil)
        #expect(insight(.double, in: report(days.flatMap { run(5, day: $0, gap: 1) }, bindings: bindings)) == nil)
        // Three or four in a row are not "twice" either.
        #expect(insight(.double, in: report(days.flatMap { run(3, day: $0, gap: 1) }, bindings: bindings)) == nil)
        // A third press 3 s after a double joins the run, as a burst would count it.
        let joined = days.flatMap {
            run(2, day: $0, gap: 1) + [line("\(oct($0))T11:00:04", "o", "d")]
        }
        #expect(insight(.double, in: report(joined, bindings: bindings)) == nil)
    }

    @Test func otherCategoriesAreNotChecked() {
        #expect(insight(.double, in: report(doubles([3, 4, 5, 6, 7], "w", "h"), bindings: bindings)) == nil)
        let result = report(doubles([3, 4, 5, 6, 7], "s", "a"), bindings: bindings)
        #expect(insight(.double, in: result) == nil)
        #expect(result.rules.first { $0.rule == "double" }?.status == .noPattern)
    }
}

// MARK: - Peak

@Suite struct PeakTests {
    @Test func reportsBusiestRepeatedHour() {
        let lines =
            presses(8, "w", "u", day: oct(10), hour: 14) + presses(8, "w", "u", day: oct(11), hour: 14)
            + presses(8, "w", "u", day: oct(12), hour: 14) + presses(5, "o", "t", day: oct(12), hour: 9)
        let found = insight(.peak, in: report(lines))
        #expect(found?.title == "Most shortcut use: 14:00–15:00")
        #expect(found?.detail == "83% of this month's presses · on 3 days")
        #expect(found?.measure == Measure(count: 24, total: 29, baseline: nil, unit: "presses"))
        #expect(found?.value == 14)
        #expect(found?.windowStart == oct(1))
        #expect(found?.windowEnd == oct(15))
        #expect(found?.comparisonStart == nil)
        #expect(found?.keys == [])
        #expect(found?.dates == [oct(10), oct(11), oct(12)])
    }

    @Test func hourOnOneDayDoesNotQualify() {
        let result = report(presses(30, "w", "u", day: oct(14), hour: 14))
        #expect(insight(.peak, in: result) == nil)
        let status = result.rules.first { $0.rule == "peak" }
        #expect(status?.status == .noPattern)
        #expect(status?.reason == "The busiest hour, 14:00, had presses on 1 day; it needs 3.")
    }

    @Test func busiestHourOnOneDayBlocksPeak() {
        // 100 presses at 09:00 on one day outweigh one press at 15:00 on each of three days.
        let busy = (0..<100).map {
            line("\(oct(10))T09:\(String(format: "%02d:%02d", $0 / 2, $0 % 2 * 30))", "w", "u")
        }
        let lines = busy + [11, 12, 13].flatMap { presses(1, "w", "u", day: oct($0), hour: 15) }
        #expect(insight(.peak, in: report(lines)) == nil)
    }

    @Test func needsTwentyPresses() {
        let lines = presses(6, "w", "u", day: oct(10)) + presses(6, "w", "u", day: oct(11))
            + presses(6, "w", "u", day: oct(12))
        let result = report(lines)
        #expect(insight(.peak, in: result) == nil)
        #expect(
            result.rules.first { $0.rule == "peak" }
                == RuleStatus(
                    rule: "peak", status: .notReady,
                    reason: "The busiest hour needs 20 presses this month; 18 so far."))
    }

    @Test func lastHourWrapsToMidnight() {
        let lines = [10, 11, 12].flatMap { presses(8, "w", "u", day: oct($0), hour: 23) }
        #expect(insight(.peak, in: report(lines))?.title == "Most shortcut use: 23:00–00:00")
    }
}

// MARK: - Unbound

@Suite struct UnboundTests {
    let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab")]

    @Test func reportsLoggedCombosWithoutBinding() {
        let lines = presses(3, "w", "u", day: oct(14)) + presses(4, "o", "t", day: oct(13))
            + presses(1, "o", "t", day: oct(14), hour: 10)
            + presses(2, "o", "f", day: "2026-09-01") + presses(1, "o", "f", day: "2026-09-02")
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.title == "2 logged combos no longer bound")
        #expect(found?.detail == "8 presses logged with no current binding")
        #expect(found?.measure == Measure(count: 8, total: nil, baseline: nil, unit: "presses"))
        #expect(found?.keys == [["o", "t"], ["o", "f"]])
        #expect(found?.value == 2)
        #expect(found?.dates == ["2026-09-01", "2026-09-02", oct(13), oct(14)])
    }

    @Test func singularTitle() {
        let lines = presses(2, "o", "t", day: oct(13)) + presses(1, "o", "t", day: oct(14))
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.title == "1 logged combo no longer bound")
        #expect(found?.detail == "3 presses logged with no current binding")
    }

    @Test func keepsEveryKeyMostPressedFirst() {
        let lines = ["a", "b", "c", "d"].enumerated().flatMap { index, key in
            presses([1, 4, 3, 2][index] + 1, "o", key, day: oct(13), hour: 9 + index)
                + presses(1, "o", key, day: oct(14), hour: 9 + index)
        }
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.keys == [["o", "b"], ["o", "c"], ["o", "d"], ["o", "a"]])
        #expect(found?.value == 4)
        #expect(found?.windowStart == oct(13))
        #expect(found?.windowEnd == oct(15))
    }

    @Test func needsThreePressesOnTwoDays() {
        // Two presses on two days, and five on one day: neither is past a stray.
        let lines = presses(1, "o", "t", day: oct(13)) + presses(1, "o", "t", day: oct(14))
            + presses(5, "o", "f", day: oct(14), hour: 10)
        let result = report(lines, bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
        let status = result.rules.first { $0.rule == "unbound" }
        #expect(status?.status == .noPattern)
        #expect(status?.reason == "2 logged combos have no binding, none pressed 3+ times on 2+ days.")
    }

    @Test func countsArchivedPresses() {
        let archive = ArchivedHistory(
            first: date("2026-09-01T00:00:00"), rejected: 0,
            comboDays: [Combo(layer: "o", key: "t"): ["2026-09-01": 2]])
        let result = computeReport(
            events: log(presses(1, "o", "t", day: oct(14))), bindings: bindings, now: now,
            archive: archive, calendar: calendar)
        let found = insight(.unbound, in: result)
        #expect(found?.detail == "3 presses logged with no current binding")
        #expect(found?.dates == ["2026-09-01", oct(14)])
    }

    @Test func absentWhenAllBound() {
        let result = report(presses(3, "w", "u", day: oct(14)), bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
        #expect(result.rules.first { $0.rule == "unbound" }?.reason == "Every logged shortcut is still bound.")
    }

    @Test func ignoresFutureEvents() {
        let lines = presses(3, "o", "t", day: oct(14)) + presses(3, "o", "t", day: oct(16))
        let result = report(lines, bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
    }
}

// MARK: - Focus (categories and app context)

@Suite struct FocusTests {
    let bindings = [
        Binding(layer: "w", key: "u", label: "Next Tab", category: "tab-navigation"),
        Binding(layer: "w", key: "i", label: "Previous Tab", category: "tab-navigation"),
        Binding(layer: "v", key: "q", label: "Left Click", category: "pointer"),
    ]
    let firefox = "org.mozilla.firefox"
    let chrome = "com.google.Chrome"

    /// For each day in `days`: `u` presses of W U at 09:xx, `i` of W I at 10:xx, 5 of V Q at 11:xx.
    func lines(days: ClosedRange<Int> = 9...14, u: Int = 20, i: Int = 10) -> [String] {
        days.flatMap { day in
            presses(u, "w", "u", day: oct(day), hour: 9) + presses(i, "w", "i", day: oct(day), hour: 10)
                + presses(5, "v", "q", day: oct(day), hour: 11)
        }
    }

    func firefoxEveryDay(_ days: ClosedRange<Int> = 9...14) -> [String] {
        [context("2026-08-01T00:00:00.000", "start")]
            + days.map { context("\(oct($0))T08:00:00.000", "app", firefox) }
    }

    @Test func reportsDominantCategoryWithoutContext() {
        let found = insight(.focus, in: report(lines(), bindings: bindings))
        #expect(found?.title == "Tab navigation leads shortcut use")
        #expect(found?.detail == "86% of 210 presses · top on 6 days")
        #expect(found?.measure == Measure(count: 180, total: 210, baseline: nil, unit: "presses"))
        #expect(found?.value == 86)
        #expect(found?.keys == [["w", "u"], ["w", "i"]])
        #expect(found?.dates == (9...14).map(oct))
        #expect(found?.app == nil)
        #expect(found?.windowStart == oct(9))
        #expect(found?.windowEnd == oct(15))
    }

    @Test func needsCategoriesInBindings() {
        let plain = bindings.map { Binding(layer: $0.layer, key: $0.key, label: $0.label) }
        #expect(insight(.focus, in: report(lines(), bindings: plain)) == nil)
    }

    @Test func needsThreeRepeatDays() {
        #expect(insight(.focus, in: report(lines(days: 13...14), bindings: bindings)) == nil)
    }

    @Test func needsThirtyPresses() {
        let result = report(lines(days: 12...14, u: 2, i: 2), bindings: bindings)
        #expect(insight(.focus, in: result) == nil)
        #expect(
            result.rules.first { $0.rule == "focus" }?.reason
                == "The category summary needs 30 presses in the last 7 days; 27 so far.")
    }

    @Test func onlyCountsLastSevenDays() {
        // Heavy tab use on days 1-5 is outside the window 9-15.
        let old = lines(days: 1...5, u: 40, i: 40)
        let recent = (9...14).flatMap { presses(30, "v", "q", day: oct($0), hour: 11) }
        let found = insight(.focus, in: report(old + recent, bindings: bindings))
        #expect(found?.title == "Pointer leads shortcut use")
    }

    @Test func namesTheAppWhenMostPressesAreInOneApp() {
        let found = insight(
            .focus, in: report(lines(), bindings: bindings, context: firefoxEveryDay()))
        #expect(found?.title == "Tab navigation mostly in Firefox")
        #expect(found?.detail == "100% of 180 attributed presses · 6 days")
        #expect(found?.measure == Measure(count: 180, total: 180, baseline: nil, unit: "presses"))
        #expect(found?.app == firefox)
        #expect(found?.value == 86)
        #expect(found?.dates == (9...14).map(oct))
    }

    @Test func appShareUsesAttributedPresses() {
        // Chrome takes over at 09:59:59, so W U (120) is in Firefox and W I (60) in Chrome.
        let switchToChrome = (9...14).map { context("\(oct($0))T09:59:59.000", "app", chrome) }
        let found = insight(
            .focus, in: report(lines(), bindings: bindings, context: firefoxEveryDay() + switchToChrome))
        #expect(found?.app == firefox)
        #expect(found?.detail == "67% of 180 attributed presses · 6 days")
    }

    @Test func noAppWithoutAMajority() {
        // 60 presses in each app: exactly half is not a majority.
        let switchToChrome = (9...14).map { context("\(oct($0))T09:59:59.000", "app", chrome) }
        let found = insight(
            .focus,
            in: report(lines(u: 10, i: 10), bindings: bindings, context: firefoxEveryDay() + switchToChrome))
        #expect(found?.app == nil)
        #expect(found?.title == "Tab navigation leads shortcut use")
    }

    @Test func noAppWhenMostPressesAreUnattributed() {
        // App events exist only on days 13 and 14. Days 9-12 have no app yet.
        let found = insight(
            .focus,
            in: report(lines(), bindings: bindings, context: firefoxEveryDay(13...14)))
        #expect(found?.app == nil)
        #expect(found?.title == "Tab navigation leads shortcut use")
    }

    @Test func noAppWhenTopAppRepeatsOnFewerThanThreeDays() {
        // Firefox has 100 presses on day 9 only. Chrome has 10 on each of days 10-14.
        let bigDay = presses(100, "w", "u", day: oct(9), hour: 9)
        let smallDays = (10...14).flatMap { presses(10, "w", "u", day: oct($0), hour: 9) }
        let events =
            [context("2026-08-01T00:00:00.000", "start"), context("\(oct(9))T08:00:00.000", "app", firefox)]
            + (10...14).map { context("\(oct($0))T08:00:00.000", "app", chrome) }
        let found = insight(.focus, in: report(bigDay + smallDays, bindings: bindings, context: events))
        #expect(found?.title == "Tab navigation leads shortcut use")
        #expect(found?.app == nil)
    }
}

// MARK: - Undone

@Suite struct UndoneTests {
    let bindings = [
        Binding(layer: "w", key: "f", label: "Maximize"),
        Binding(layer: "w", key: "delete_or_backspace", label: "Restore"),
        Binding(layer: "w", key: "h", label: "Left half"),
        Binding(layer: "w", key: "l", label: "Right half"),
    ]

    /// `first` at 10:`minute`:00 on `day`, then `second` `gap` seconds later, both in layer w.
    func pair(_ first: String, _ second: String, day: Int, minute: Int = 0, gap: Int = 2) -> [String] {
        let time = "\(oct(day))T10:\(String(format: "%02d", minute))"
        return [line("\(time):00", "w", first), line("\(time):\(String(format: "%02d", gap))", "w", second)]
    }

    /// Maximize then Restore on 10 to 13 October, twice on the 13th: 5 times on 4 days.
    func fiveOnFourDays(gap: Int = 2, days: [Int] = [10, 11, 12, 13, 13]) -> [String] {
        days.enumerated().flatMap { pair("f", "delete_or_backspace", day: $0.element, minute: $0.offset, gap: gap) }
    }

    @Test func reportsMostUndoneCombo() {
        let lines = fiveOnFourDays(gap: 3) + presses(3, "w", "f", day: oct(14)) + pair("l", "h", day: 10, minute: 20)
        let found = insight(.undone, in: report(lines, bindings: bindings))
        #expect(found?.title == "Maximize undone 5 times")
        #expect(found?.detail == "W F · then Restore within 3 s · on 4 of the last 14 days")
        #expect(found?.keys == [["w", "f"], ["w", "delete_or_backspace"]])
        #expect(found?.value == 5)
        #expect(found?.dates == [oct(10), oct(11), oct(12), oct(13)])
        #expect(found?.measure == Measure(count: 5, total: 8, baseline: nil, unit: "presses"))
        #expect(found?.windowStart == oct(2))
        #expect(found?.windowEnd == oct(15))
    }

    @Test func needsFiveTimes() {
        let result = report(fiveOnFourDays(days: [10, 11, 12, 13]), bindings: bindings)
        #expect(insight(.undone, in: result) == nil)
        #expect(result.rules.first { $0.rule == "undone" }?.reason
                == "Maximize was undone 4 times on 4 days in the last 14; the card needs 5 times on 4+ days.")
    }

    @Test func needsFourDaysSoTheBusiestDayCanBeDropped() {
        // 5 times on 3 days leaves 2 days without the busiest one.
        let lines = fiveOnFourDays(days: [11, 12, 13, 13, 13])
        #expect(insight(.undone, in: report(lines, bindings: bindings)) == nil)
        // One of the 13th's moved to the 10th makes 4 days.
        let fourDays = fiveOnFourDays(days: [10, 11, 12, 13, 13])
        #expect(insight(.undone, in: report(fourDays, bindings: bindings)) != nil)
    }

    @Test func threeSecondsCountsFourDoNot() {
        #expect(insight(.undone, in: report(fiveOnFourDays(gap: 3), bindings: bindings)) != nil)
        #expect(insight(.undone, in: report(fiveOnFourDays(gap: 4), bindings: bindings)) == nil)
    }

    @Test func pressBetweenBreaksThePair() {
        let lines = fiveOnFourDays() + [line("\(oct(10))T10:00:01", "w", "s")]
        #expect(insight(.undone, in: report(lines, bindings: bindings)) == nil)
        // The same press after the pair leaves it whole.
        let after = fiveOnFourDays() + [line("\(oct(10))T10:00:03", "w", "s")]
        #expect(insight(.undone, in: report(after, bindings: bindings)) != nil)
    }

    @Test func sameSecondFollowsFileOrder() {
        let forward = insight(.undone, in: report(fiveOnFourDays(gap: 0), bindings: bindings))
        #expect(forward?.title == "Maximize undone 5 times")
        let backward = [10, 11, 12, 13, 13].enumerated().flatMap {
            pair("delete_or_backspace", "f", day: $0.element, minute: $0.offset, gap: 0)
        }
        #expect(insight(.undone, in: report(backward, bindings: bindings))?.title == "Restore undone 5 times")
    }

    @Test func eitherOrderOfAPairCounts() {
        let lines = [10, 11, 12, 13, 13].enumerated().flatMap { pair("l", "h", day: $0.element, minute: $0.offset) }
        let found = insight(.undone, in: report(lines, bindings: bindings))
        #expect(found?.title == "Right half undone 5 times")
        #expect(found?.detail == "W L · then Left half within 3 s · on 4 of the last 14 days")
    }

    @Test func undoingPressIsUsedOnce() {
        // Maximize, Restore, Maximize: one Maximize undone, not also one Restore.
        let lines = fiveOnFourDays() + [10, 11, 12, 13, 13].enumerated().map {
            line("\(oct($0.element))T10:\(String(format: "%02d", $0.offset)):04", "w", "f")
        }
        #expect(insight(.undone, in: report(lines, bindings: bindings))?.title == "Maximize undone 5 times")
    }

    @Test func skipsPairNoLongerBound() {
        let result = report(fiveOnFourDays(), bindings: bindings.filter { $0.label != "Restore" })
        #expect(insight(.undone, in: result) == nil)
        #expect(insight(.undone, in: report(fiveOnFourDays(), bindings: bindings)) != nil)
    }

    @Test func onlyCountsLastFourteenDays() {
        // Window: 2 to 15 October. The 1 October pair falls outside it, leaving 4.
        let lines = fiveOnFourDays(days: [1, 10, 11, 12, 13])
        #expect(insight(.undone, in: report(lines, bindings: bindings)) == nil)
        // On the 2nd, the first day of the window, it counts.
        let inside = fiveOnFourDays(days: [2, 10, 11, 12, 13])
        #expect(insight(.undone, in: report(inside, bindings: bindings)) != nil)
    }
}

// MARK: - Uptake

@Suite struct UptakeTests {
    let bindings = [
        Binding(layer: "f", key: "p", label: "Copy Path"),
        Binding(layer: "f", key: "o", label: "Open in Finder"),
    ]

    /// One press of the combo at 09:00 on each listed October day.
    func on(_ layer: String, _ key: String, _ days: [Int]) -> [String] {
        days.flatMap { presses(1, layer, key, day: oct($0)) }
    }

    @Test func reportsWeakestNewShortcut() {
        // Copy Path misses 5 of 9 days; Open in Finder misses none; z q is unbound.
        let lines = on("f", "p", [6, 7, 9, 11]) + on("f", "o", Array(5...14)) + on("z", "q", [6])
        let found = insight(.uptake, in: report(lines, bindings: bindings))
        #expect(found?.title == "Copy Path used on 4 of 9 days")
        #expect(found?.detail == "F P · first used Oct 6 · last used Oct 11")
        #expect(found?.keys == [["f", "p"]])
        #expect(found?.value == 4)
        #expect(found?.dates == [oct(6), oct(7), oct(9), oct(11)])
        #expect(found?.measure == Measure(count: 4, total: 9, baseline: nil, unit: "days"))
        #expect(found?.windowStart == oct(6))
        #expect(found?.windowEnd == oct(15))
    }

    @Test func strongUptakeGivesNoCard() {
        // Used on 5 of 9 days, 2 of them among 12 to 14 October: half or more, and used in the last 3.
        let result = report(on("f", "p", [6, 8, 10, 12, 14]), bindings: bindings)
        #expect(insight(.uptake, in: result) == nil)
        let status = result.rules.first { $0.rule == "uptake" }
        #expect(status?.status == .noPattern)
        #expect(status?.reason
                == "Copy Path was used on 5 of 9 days since its first use, 2 of the last 3; "
                + "the card needs fewer than half, or none in the last 3.")
    }

    @Test func noneInTheLastThreeDaysIsWeak() {
        // Used on 6 of 9 days, but none on 12, 13 and 14 October.
        let found = insight(.uptake, in: report(on("f", "p", [6, 7, 8, 9, 10, 11]), bindings: bindings))
        #expect(found?.title == "Copy Path used on 6 of 9 days")
    }

    @Test func todaysPressIsLastUseButNotADay() {
        let found = insight(.uptake, in: report(on("f", "p", [6, 15]), bindings: bindings))
        #expect(found?.title == "Copy Path used on 1 of 9 days")
        #expect(found?.detail == "F P · first used Oct 6 · last used Oct 15")
    }

    @Test func needsSevenRecordedDaysSinceFirstUse() {
        let six = report(on("f", "p", [9]), bindings: bindings)
        #expect(insight(.uptake, in: six) == nil)
        let status = six.rules.first { $0.rule == "uptake" }
        #expect(status?.status == .notReady)
        #expect(status?.reason == "The uptake check needs 7 recorded days since a first use; Copy Path has 6.")
        #expect(insight(.uptake, in: report(on("f", "p", [8]), bindings: bindings))?.title
                == "Copy Path used on 1 of 7 days")
    }

    @Test func needsSevenDaysOfLogBeforeFirstUse() {
        // The log begins on 1 October, so a first use before the 8th may only be the start of logging.
        let start = presses(1, "w", "u", day: oct(1))
        #expect(insight(.uptake, in: report(start + on("f", "p", [7]), bindings: bindings, anchored: false)) == nil)
        #expect(insight(.uptake, in: report(start + on("f", "p", [8]), bindings: bindings, anchored: false))?.title
                == "Copy Path used on 1 of 7 days")
    }

    @Test func explainsAYoungLog() {
        let result = report(on("f", "p", [10, 11]), bindings: bindings, anchored: false)
        let status = result.rules.first { $0.rule == "uptake" }
        #expect(status?.status == .notReady)
        #expect(status?.reason
                == "The uptake check needs 14 days of log, 7 before a first use and 7 after; recording began Oct 10.")
    }

    @Test func firstUseOlderThanTwentyOneDaysIsNotNew() {
        // 21 days before 15 October is 24 September.
        #expect(insight(.uptake, in: report(presses(1, "f", "p", day: "2026-09-23"), bindings: bindings)) == nil)
        #expect(insight(.uptake, in: report(presses(1, "f", "p", day: "2026-09-24"), bindings: bindings))?.title
                == "Copy Path used on 1 of 21 days")
    }

    @Test func countsOnlyRecordedDays() {
        // One session to 9 October 23:00 and one from 11 October: the 10th is not recorded.
        let result = report(
            on("f", "p", [6, 7, 8, 9, 11]), bindings: bindings,
            context: [
                context("2026-09-01T00:00:00.000", "start"),
                context("\(oct(9))T23:00:00.000", "app", "com.a.one"),
                context("\(oct(11))T00:00:00.000", "start"),
            ])
        #expect(insight(.uptake, in: result)?.title == "Copy Path used on 5 of 8 days")
    }
}

// MARK: - Report

@Suite struct ReportTests {
    @Test func keepsFullText() {
        let longLabel = String(repeating: "L", count: 60)
        let bindings = [Binding(layer: "w", key: "u", label: longLabel)]
        let lines = daily("w", "u", from: 1, [14, 14, 14, 14, 14, 15, 15])
            + daily("w", "u", from: 8, [43, 43, 43, 43, 43, 43, 42])
        let result = report(lines, bindings: bindings)
        #expect(result.generated == "2026-10-15T15:00:00")
        #expect(result.month == "2026-10")
        #expect(result.insights.first { $0.kind == .rising }?.title == longLabel + " up 200 presses")
    }

    @Test func everyRuleReportsItsStatus() {
        let result = report([], bindings: [Binding(layer: "w", key: "u", label: "x")], anchored: false)
        #expect(
            result.rules.map(\.rule)
                == ["focus", "trend", "unused", "dormant", "unbound", "burst", "peak", "pair", "double", "undone", "uptake"])
        #expect(result.rules.allSatisfy { $0.status != .shown && $0.reason != nil })
    }

    @Test func emptyLogYieldsNoInsights() {
        let result = report([], bindings: [Binding(layer: "w", key: "u", label: "x")], anchored: false)
        #expect(result.insights.isEmpty)
        #expect(result.recordingSince == nil)
        #expect(result.rejectedLines == 0)
    }

    @Test func recordingSinceIsEarliestValidEvent() {
        let lines = presses(3, "w", "u", day: oct(14)) + ["junk", "2026-10-13T08:15:00\tw\tu"]
        let result = report(lines, anchored: false)
        #expect(result.recordingSince == "2026-10-13T08:15:00")
        #expect(result.rejectedLines == 1)
    }

    @Test func monthBoundaryCountsOnlyNewMonth() {
        let first = date("2026-11-01T00:00:00")
        let lines = ["2026-10-31T23:59:59\tw\tu", "2026-11-01T00:00:00\tw\tu"]
        let result = report(lines, anchored: true, at: first)
        #expect(result.month == "2026-11")
        #expect(result.monthTotal == 1)
    }

    @Test func fullReportOrder() {
        let bindings = [
            Binding(layer: "w", key: "u", label: "Previous Tab", category: "tab-navigation"),
            Binding(layer: "v", key: "q", label: "Left Click", category: "pointer"),
            Binding(layer: "o", key: "t", label: "Ghostty", category: "app-launch"),
        ] + "abcd".map { Binding(layer: "s", key: String($0), label: "x", category: "system") }
        let lines =
            daily("w", "u", from: 1, [14, 14, 14, 14, 14, 15, 15])
            + daily("w", "u", from: 8, [43, 43, 43, 43, 43, 43, 42])
            + presses(6, "o", "t", day: "2026-09-20") + presses(6, "o", "t", day: "2026-09-21")
            + (0..<5).map { line("\(oct(10))T08:01:0\($0)", "v", "q") }
            + (0..<5).map { line("\(oct(11))T08:01:0\($0)", "v", "q") }
            + presses(2, "x", "q", day: "2026-08-02") + presses(1, "x", "q", day: "2026-08-03")
        let result = report(lines, bindings: bindings)
        // Seven of eleven rules fire: this log has no pairs, doubles or reversals, and Previous Tab
        // is used every day, so uptake does not. Changes come first, then patterns, timing and
        // absences; five are shown.
        #expect(result.insights.map(\.kind) == [.rising, .focus, .burst, .peak, .dormant])
        #expect(
            result.rules.map(\.status)
                == [.shown, .shown, .held, .shown, .held, .shown, .shown, .noPattern, .noPattern, .noPattern, .noPattern])
        #expect(result.rules.first { $0.rule == "unused" }?.reason
                == "4 of 4 System shortcuts unused in 30 days. Held back: 5 cards rank higher.")
        // Held findings keep their full text and evidence.
        #expect(result.held.map(\.kind) == [.unused, .unbound])
        #expect(result.held[0].keys.count == 4)
        // The same input gives the same cards in the same order.
        #expect(report(lines, bindings: bindings).insights == result.insights)
    }

    @Test func pairAndDoubleRankAfterBurst() {
        let pairs = PairTests()
        let doubles = DoubleTests()
        let lines = pairs.threshold() + doubles.doubles([3, 4, 5, 6, 7])
            + (0..<5).map { line("\(oct(10))T08:01:0\($0)", "v", "q") }
            + (0..<5).map { line("\(oct(11))T08:01:0\($0)", "v", "q") }
            + [7, 8, 9].flatMap { presses(3, "s", "a", day: oct($0), hour: 10) }
        let result = report(lines, bindings: pairs.bindings + doubles.bindings)
        #expect(result.insights.map(\.kind) == [.falling, .burst, .pair, .double, .peak])
        // The stray unbound combo has presses on one day only, so unbound gives no card; Ghostty
        // (O T, used on 4 of 12 days since its first use) is held as weak uptake.
        #expect(result.held.map(\.kind) == [.uptake])
    }

    @Test func everyInsightCarriesDates() {
        let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab", category: "tab-navigation")]
        let lines = daily("w", "u", from: 1, [14, 14, 14, 14, 14, 15, 15]) + daily("w", "u", from: 8, [43, 43, 43, 43, 43, 43, 42])
        let result = report(lines, bindings: bindings)
        #expect(!result.insights.isEmpty)
        #expect(result.insights.allSatisfy { !$0.dates.isEmpty })
    }

    @Test func fileEncodesVersionThree() throws {
        let data = try InsightsFile(report: report(["bad line"], anchored: false)).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["version"] as? Int == 3)
        #expect(object["recordingSince"] is NSNull)
        #expect(object["rejectedLines"] as? Int == 1)
        #expect((object["insights"] as? [Any])?.isEmpty == true)
    }

    @Test func fileWritesDatesAndNullApp() throws {
        let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab", category: "tab-navigation")]
        let lines = daily("w", "u", from: 1, [14, 14, 14, 14, 14, 15, 15]) + daily("w", "u", from: 8, [43, 43, 43, 43, 43, 43, 42])
        let data = try InsightsFile(report: report(lines, bindings: bindings)).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let insights = object["insights"] as! [[String: Any]]
        let rising = insights.first { $0["kind"] as? String == "rising" }!
        #expect(rising["app"] is NSNull)
        #expect((rising["dates"] as? [String])?.count == 7)
        #expect(rising["windowStart"] as? String == oct(8))
        #expect(rising["comparisonEnd"] as? String == oct(7))
        let measure = rising["measure"] as! [String: Any]
        #expect(measure["count"] as? Int == 300)
        #expect(measure["baseline"] as? Int == 100)
        #expect(measure["total"] is NSNull)
        #expect(measure["unit"] as? String == "presses")
        #expect(object["recordingSince"] as? String == "2026-08-01T00:00:00")
        let rules = object["rules"] as! [[String: Any]]
        #expect(rules.first { $0["rule"] as? String == "trend" }?["status"] as? String == "shown")
        #expect(rules.first { $0["rule"] as? String == "trend" }?["reason"] is NSNull)
        let burst = rules.first { $0["rule"] as? String == "burst" }!
        #expect(burst["status"] as? String == "no-pattern")
        #expect(burst["reason"] as? String == "No shortcut came in bursts (5+ presses, each within 3 s) on 2+ days this month.")
        #expect((object["held"] as? [Any])?.isEmpty == true)
        let focus = insights.first { $0["kind"] as? String == "focus" }
        #expect(focus?["comparisonStart"] is NSNull)
    }

    @Test func fileWritesAppBundleIdentifier() throws {
        let bindings = [Binding(layer: "w", key: "u", label: "Next Tab", category: "tab-navigation")]
        let focus = FocusTests()
        let result = report(
            focus.lines(), bindings: bindings, context: focus.firefoxEveryDay())
        let data = try InsightsFile(report: result).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let insights = object["insights"] as! [[String: Any]]
        #expect(insights.first { $0["kind"] as? String == "focus" }?["app"] as? String == "org.mozilla.firefox")
    }

    @Test func categoryDecodesFromBindingsJSON() throws {
        let json = Data(#"[{"layer":"w","key":"u","label":"Previous Tab","category":"tab-navigation","site":"x"},{"layer":"w","key":"i","label":"Next"}]"#.utf8)
        let decoded = try parseBindings(json)
        #expect(decoded[0].category == "tab-navigation")
        #expect(decoded[1].category == nil)
    }
}
