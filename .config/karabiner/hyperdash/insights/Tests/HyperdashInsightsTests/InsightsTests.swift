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
        #expect(found?.title == "Previous Tab up 200 presses this week")
        #expect(found?.detail == "W U · 300 vs 100 the week before · up on 7 days")
        #expect(found?.keys == [["w", "u"]])
        #expect(found?.value == 200)
        #expect(found?.dates == (8...14).map(oct))
    }

    @Test func falling() {
        let found = insight(
            .falling, in: report(week("w", "u", previous: steady300, recent: steady100), bindings: bindings))
        #expect(found?.title == "Previous Tab down 200 presses this week")
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

    @Test func longLabelKeepsSuffix() {
        let long = [Binding(layer: "w", key: "u", label: String(repeating: "L", count: 30))]
        let found = insight(
            .rising, in: report(week("w", "u", previous: steady100, recent: steady300), bindings: long))
        #expect(found?.title.hasSuffix(" up 200 presses this week") == true)
        #expect(found?.title.count == 40)
    }

    @Test func fallsBackToHyperName() {
        let found = insight(
            .rising, in: report(week("w", "x", previous: steady100, recent: steady300)))
        #expect(found?.title == "Hyper W X up 200 presses this week")
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
        #expect(found?.title == "3 of 4 System shortcuts unused")
        #expect(found?.value == 3)
        #expect(found?.keys == [["s", "k1"], ["s", "k2"], ["s", "k3"]])
    }

    @Test func reportsRecordedDays() {
        let bindings = layer("w", 5)
        let found = insight(.unused, in: report(used("w", 1), bindings: bindings))
        #expect(found?.title == "4 of 5 Window shortcuts unused")
        #expect(found?.detail == "No presses on 30 recorded days")
        #expect(found?.dates.count == 30)
        #expect(found?.dates.last == oct(14))
    }

    @Test func ignoresLayersWithFewerThanFourBindings() {
        let bindings = layer("r", 3)
        #expect(insight(.unused, in: report([], bindings: bindings)) == nil)
    }

    @Test func needsThreeUnused() {
        let bindings = layer("w", 5)
        #expect(insight(.unused, in: report(used("w", 3), bindings: bindings)) == nil)
    }

    @Test func needsThreeFullyRecordedDays() {
        let bindings = layer("w", 5)
        // First press on 2026-10-12: days 13 and 14 are fully recorded.
        let two = daily("w", "k0", from: 12, [1, 1, 1], hour: 8)
        #expect(insight(.unused, in: report(two, bindings: bindings, anchored: false)) == nil)
        // First press on 2026-10-11: days 12, 13 and 14.
        let three = daily("w", "k0", from: 11, [1, 1, 1, 1], hour: 8)
        let found = insight(.unused, in: report(three, bindings: bindings, anchored: false))
        #expect(found?.detail == "No presses on 3 recorded days")
        #expect(found?.dates == [oct(12), oct(13), oct(14)])
    }

    @Test func emptyLogMakesNoClaim() {
        #expect(insight(.unused, in: report([], bindings: layer("w", 5), anchored: false)) == nil)
    }

    @Test func daysWithContextGapsAreNotCounted() {
        let bindings = layer("w", 5)
        let lines = daily("w", "k0", from: 10, [1, 1, 1, 1, 1], hour: 8)
        let result = report(
            lines, bindings: bindings, anchored: false,
            context: [
                context("\(oct(10))T00:00:00.000", "start"),
                context("\(oct(12))T07:00:00.000", "app", "com.a.one"),
                context("\(oct(14))T00:00:00.000", "start"),
            ])
        // Presses on 12 and 13 fall in the gap, leaving only day 11 and day 14.
        #expect(insight(.unused, in: result) == nil)
    }

    @Test func unobservedEmptyDaysAreNotCounted() {
        let bindings = layer("w", 5)
        let result = report(
            presses(1, "w", "k0", day: oct(1)), bindings: bindings, anchored: false,
            context: [context("\(oct(12))T00:00:00.000", "start")])
        // 2 to 11 October have no session, so only 12, 13 and 14 October count.
        let found = insight(.unused, in: result)
        #expect(found?.detail == "No presses on 3 recorded days")
        #expect(found?.dates == [oct(12), oct(13), oct(14)])
    }

    @Test func pressOlderThan30DaysDoesNotCount() {
        let bindings = layer("w", 5)
        let lines = presses(1, "w", "k0", day: "2026-09-01")
        let found = insight(.unused, in: report(lines, bindings: bindings))
        #expect(found?.title == "5 of 5 Window shortcuts unused")
    }

    @Test func capsKeysAtThree() {
        let found = insight(.unused, in: report([], bindings: layer("s", 7)))
        #expect(found?.title == "7 of 7 System shortcuts unused")
        #expect(found?.keys.count == 3)
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

    @Test func longLabelKeepsSuffix() {
        let long = [Binding(layer: "o", key: "t", label: String(repeating: "L", count: 30))]
        let found = insight(.dormant, in: report(september, bindings: long))
        #expect(found?.title.hasSuffix(" not used yet this month") == true)
        #expect(found?.title.count == 40)
    }

    @Test func needsPreviousMonthRecordedFromItsFirstDay() {
        // Recording began 2026-09-02, one day after September began.
        let lines = presses(3, "o", "t", day: "2026-09-02") + presses(3, "o", "t", day: "2026-09-03")
        #expect(insight(.dormant, in: report(lines, bindings: bindings, anchored: false)) == nil)
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
        #expect(found?.title == "Left Click comes in bursts")
        #expect(found?.detail == "V Q pressed 5+ times in a row, 2 times on 2 days")
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

// MARK: - Peak

@Suite struct PeakTests {
    @Test func reportsBusiestRepeatedHour() {
        let lines =
            presses(8, "w", "u", day: oct(10), hour: 14) + presses(8, "w", "u", day: oct(11), hour: 14)
            + presses(8, "w", "u", day: oct(12), hour: 14) + presses(5, "o", "t", day: oct(12), hour: 9)
        let found = insight(.peak, in: report(lines))
        #expect(found?.title == "Most active 14:00–15:00")
        #expect(found?.detail == "83% of this month's presses")
        #expect(found?.value == 14)
        #expect(found?.keys == [])
        #expect(found?.dates == [oct(10), oct(11), oct(12)])
    }

    @Test func hourOnOneDayDoesNotQualify() {
        #expect(insight(.peak, in: report(presses(30, "w", "u", day: oct(14), hour: 14))) == nil)
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
        #expect(insight(.peak, in: report(lines)) == nil)
    }

    @Test func lastHourWrapsToMidnight() {
        let lines = [10, 11, 12].flatMap { presses(8, "w", "u", day: oct($0), hour: 23) }
        #expect(insight(.peak, in: report(lines))?.title == "Most active 23:00–00:00")
    }
}

// MARK: - Unbound

@Suite struct UnboundTests {
    let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab")]

    @Test func reportsLoggedCombosWithoutBinding() {
        let lines = presses(3, "w", "u", day: oct(14)) + presses(5, "o", "t", day: oct(14), hour: 10)
            + presses(2, "o", "f", day: "2026-09-01")
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.title == "2 logged combos no longer bound")
        #expect(found?.detail == "7 presses logged with no current binding")
        #expect(found?.keys == [["o", "t"], ["o", "f"]])
        #expect(found?.value == 2)
        #expect(found?.dates == ["2026-09-01", oct(14)])
    }

    @Test func singularTitle() {
        let found = insight(.unbound, in: report(presses(1, "o", "t", day: oct(14)), bindings: bindings, anchored: false))
        #expect(found?.title == "1 logged combo no longer bound")
        #expect(found?.detail == "1 press logged with no current binding")
    }

    @Test func capsKeysAtThreeMostPressedFirst() {
        let lines = presses(1, "o", "a", day: oct(14)) + presses(4, "o", "b", day: oct(14), hour: 10)
            + presses(3, "o", "c", day: oct(14), hour: 11) + presses(2, "o", "d", day: oct(14), hour: 12)
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.keys == [["o", "b"], ["o", "c"], ["o", "d"]])
        #expect(found?.value == 4)
    }

    @Test func absentWhenAllBound() {
        let result = report(presses(3, "w", "u", day: oct(14)), bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
    }

    @Test func ignoresFutureEvents() {
        let result = report(presses(3, "o", "t", day: oct(16)), bindings: bindings, anchored: false)
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
        #expect(found?.title == "Tab navigation leads your Hyper use")
        #expect(found?.detail == "86% of 210 presses · top on 6 days")
        #expect(found?.value == 86)
        #expect(found?.keys == [["w", "u"], ["w", "i"]])
        #expect(found?.dates == (9...14).map(oct))
        #expect(found?.app == nil)
    }

    @Test func needsCategoriesInBindings() {
        let plain = bindings.map { Binding(layer: $0.layer, key: $0.key, label: $0.label) }
        #expect(insight(.focus, in: report(lines(), bindings: plain)) == nil)
    }

    @Test func needsThreeRepeatDays() {
        #expect(insight(.focus, in: report(lines(days: 13...14), bindings: bindings)) == nil)
    }

    @Test func needsThirtyPresses() {
        #expect(insight(.focus, in: report(lines(days: 12...14, u: 2, i: 2), bindings: bindings)) == nil)
    }

    @Test func onlyCountsLastSevenDays() {
        // Heavy tab use on days 1-5 is outside the window 9-15.
        let old = lines(days: 1...5, u: 40, i: 40)
        let recent = (9...14).flatMap { presses(30, "v", "q", day: oct($0), hour: 11) }
        let found = insight(.focus, in: report(old + recent, bindings: bindings))
        #expect(found?.title == "Pointer leads your Hyper use")
    }

    @Test func namesTheAppWhenMostPressesAreInOneApp() {
        let found = insight(
            .focus, in: report(lines(), bindings: bindings, context: firefoxEveryDay()))
        #expect(found?.title == "Tab navigation mostly in Firefox")
        #expect(found?.detail == "100% of 180 attributed presses · 6 days")
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
        #expect(found?.title == "Tab navigation leads your Hyper use")
    }

    @Test func noAppWhenMostPressesAreUnattributed() {
        // App events exist only on days 13 and 14. Days 9-12 have no app yet.
        let found = insight(
            .focus,
            in: report(lines(), bindings: bindings, context: firefoxEveryDay(13...14)))
        #expect(found?.app == nil)
        #expect(found?.title == "Tab navigation leads your Hyper use")
    }

    @Test func noAppWhenTopAppRepeatsOnFewerThanThreeDays() {
        // Firefox has 100 presses on day 9 only. Chrome has 10 on each of days 10-14.
        let bigDay = presses(100, "w", "u", day: oct(9), hour: 9)
        let smallDays = (10...14).flatMap { presses(10, "w", "u", day: oct($0), hour: 9) }
        let events =
            [context("2026-08-01T00:00:00.000", "start"), context("\(oct(9))T08:00:00.000", "app", firefox)]
            + (10...14).map { context("\(oct($0))T08:00:00.000", "app", chrome) }
        let found = insight(.focus, in: report(bigDay + smallDays, bindings: bindings, context: events))
        #expect(found?.title == "Tab navigation leads your Hyper use")
        #expect(found?.app == nil)
    }
}

// MARK: - Report

@Suite struct ReportTests {
    @Test func ordersInsightsAndTruncatesText() {
        let longLabel = String(repeating: "L", count: 60)
        let bindings = [Binding(layer: "w", key: "u", label: longLabel)]
        let lines = presses(30, "w", "u", day: oct(14), hour: 14)
        let result = report(lines, bindings: bindings)
        #expect(result.generated == "2026-10-15T15:00:00")
        #expect(result.month == "2026-10")
        #expect(result.monthTotal == 30)
        #expect(result.insights.allSatisfy { $0.title.count <= 40 && $0.detail.count <= 52 })
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
        let result = report(lines, bindings: bindings)
        #expect(
            result.insights.map(\.kind)
                == [.focus, .rising, .unused, .dormant, .unbound, .burst, .peak])
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
        #expect(object["recordingSince"] as? String == "2026-08-01T00:00:00")
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
