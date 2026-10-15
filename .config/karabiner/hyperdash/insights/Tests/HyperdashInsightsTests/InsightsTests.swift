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

/// `count` presses of one combo, one per minute starting at `start`.
private func presses(_ count: Int, _ layer: String, _ key: String, day: String, hour: Int = 9)
    -> [String]
{
    (0..<count).map { line("\(day)T\(String(format: "%02d", hour)):\(String(format: "%02d", $0)):00", layer, key) }
}

private func report(
    _ lines: [String], bindings: [Binding] = [], anchored: Bool = true, at time: Date = now
) -> InsightReport {
    let result = parsed((anchored ? [anchor] : []) + lines)
    return computeReport(
        events: result.events, bindings: bindings, now: time,
        rejectedLines: result.rejectedLines, calendar: calendar)
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

@Suite struct TrendTests {
    let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab")]

    @Test func rising() {
        // 7 presses in the last week, 5 the week before: +40%.
        let lines = presses(7, "w", "u", day: "2026-10-13") + presses(5, "w", "u", day: "2026-10-05")
        let found = insight(.rising, in: report(lines, bindings: bindings))
        #expect(found?.title == "Previous Tab up 40% this week")
        #expect(found?.detail == "W U · 7 presses vs 5 the week before")
        #expect(found?.keys == [["w", "u"]])
        #expect(found?.value == 40)
    }

    @Test func falling() {
        let lines = presses(3, "w", "u", day: "2026-10-13") + presses(6, "w", "u", day: "2026-10-05")
        let result = report(lines, bindings: bindings)
        #expect(insight(.falling, in: result)?.title == "Previous Tab down 50% this week")
        #expect(insight(.rising, in: result) == nil)
    }

    @Test func needsFivePressesInLargerWindow() {
        let lines = presses(4, "w", "u", day: "2026-10-13") + presses(2, "w", "u", day: "2026-10-05")
        let result = report(lines)
        #expect(insight(.rising, in: result) == nil)
        #expect(insight(.falling, in: result) == nil)
    }

    @Test func picksLargestAbsoluteChange() {
        let lines =
            presses(6, "w", "u", day: "2026-10-13") + presses(5, "w", "u", day: "2026-10-05")
            + presses(2, "o", "t", day: "2026-10-13", hour: 10)
            + presses(10, "o", "t", day: "2026-10-05", hour: 10)
        #expect(insight(.falling, in: report(lines))?.title == "Hyper O T down 80% this week")
        #expect(insight(.rising, in: report(lines)) == nil)
    }

    @Test func fallsBackToHyperName() {
        let lines = presses(9, "w", "x", day: "2026-10-13") + presses(6, "w", "x", day: "2026-10-05")
        #expect(insight(.rising, in: report(lines))?.title == "Hyper W X up 50% this week")
    }

    @Test func ignoresComboWithNoEarlierPresses() {
        #expect(insight(.rising, in: report(presses(9, "w", "u", day: "2026-10-13"))) == nil)
    }

    @Test func needsFourteenDaysOfRecording() {
        // Recording began 2026-10-05T09:00, 10 days before now: the earlier week is incomplete.
        let lines = presses(7, "w", "u", day: "2026-10-13") + presses(5, "w", "u", day: "2026-10-05")
        let result = report(lines, anchored: false)
        #expect(insight(.rising, in: result) == nil)
        #expect(insight(.falling, in: result) == nil)
    }

    @Test func allowsTrendExactlyFourteenDaysAfterRecordingBegan() {
        // The first press is at exactly now minus 14 days.
        let lines = ["2026-10-01T15:00:00\tw\tu"] + presses(4, "w", "u", day: "2026-10-05")
            + presses(7, "w", "u", day: "2026-10-13")
        #expect(insight(.rising, in: report(lines, anchored: false)) != nil)
    }
}

@Suite struct UnusedTests {
    let bindings = ["a", "b", "c", "d"].map { Binding(layer: "w", key: $0, label: $0) }
        + ["a", "b"].map { Binding(layer: "o", key: $0, label: $0) }

    @Test func reportsLayerWithMostUnused() {
        let found = insight(.unused, in: report(presses(3, "w", "a", day: "2026-10-14"), bindings: bindings))
        #expect(found?.title == "3 of 4 Window shortcuts unused")
        #expect(found?.keys == [["w", "b"], ["w", "c"], ["w", "d"]])
        #expect(found?.value == 3)
    }

    @Test func shortHistoryNamesRecordingStart() {
        // Recording began 2026-10-14, one day before now.
        let found = insight(
            .unused, in: report(presses(3, "w", "a", day: "2026-10-14"), bindings: bindings, anchored: false))
        #expect(found?.title == "3 of 4 Window shortcuts unused")
        #expect(found?.detail == "Not seen since recording began Oct 14")
    }

    @Test func fullThirtyDaysUsesThirtyDayWording() {
        // The first press is exactly 30 days before now.
        let lines = ["2026-09-15T15:00:00\tw\ta"]
        let found = insight(.unused, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.detail == "No presses in the last 30 days")
    }

    @Test func emptyLogMakesNoClaim() {
        #expect(insight(.unused, in: report([], bindings: bindings, anchored: false)) == nil)
    }

    @Test func needsThreeUnused() {
        let lines = presses(1, "w", "a", day: "2026-10-14") + presses(1, "w", "b", day: "2026-10-14", hour: 10)
        #expect(insight(.unused, in: report(lines, bindings: bindings)) == nil)
    }

    @Test func pressOlderThan30DaysDoesNotCount() {
        let lines = presses(1, "w", "a", day: "2026-09-01") + presses(1, "w", "b", day: "2026-10-14")
        let found = insight(.unused, in: report(lines, bindings: bindings))
        #expect(found?.title == "3 of 4 Window shortcuts unused")
        #expect(found?.keys.first == ["w", "a"])
    }

    @Test func capsKeysAtThree() {
        let many = "abcdefg".map { Binding(layer: "s", key: String($0), label: "x") }
        let found = insight(.unused, in: report([], bindings: many))
        #expect(found?.title == "7 of 7 System shortcuts unused")
        #expect(found?.keys.count == 3)
    }
}

@Suite struct DormantTests {
    let bindings = [Binding(layer: "o", key: "t", label: "Ghostty")]

    @Test func reportsComboStoppedThisMonth() {
        let lines = presses(12, "o", "t", day: "2026-09-20") + presses(4, "w", "u", day: "2026-09-21")
        let found = insight(.dormant, in: report(lines, bindings: bindings))
        #expect(found?.title == "Ghostty not used yet this month")
        #expect(found?.detail == "O T · 12 presses in September · none since Oct 1")
        #expect(found?.value == 12)
    }

    @Test func neverClaimsStoppedTenMinutesIntoMonth() {
        let lines = presses(12, "o", "t", day: "2026-09-20")
        let found = insight(
            .dormant, in: report(lines, bindings: bindings, at: date("2026-10-01T00:10:00")))
        #expect(found?.title == "Ghostty not used yet this month")
        #expect(found?.detail == "O T · 12 presses in September · none since Oct 1")
        #expect(!(found?.title.contains("Stopped") ?? false))
    }

    @Test func sameWordingEightDaysIn() {
        let lines = presses(12, "o", "t", day: "2026-09-20")
        let found = insight(
            .dormant, in: report(lines, bindings: bindings, at: date("2026-10-09T12:00:00")))
        #expect(found?.title == "Ghostty not used yet this month")
        #expect(found?.detail == "O T · 12 presses in September · none since Oct 1")
    }

    @Test func longLabelKeepsSuffix() {
        let long = [Binding(layer: "o", key: "t", label: String(repeating: "L", count: 30))]
        let found = insight(
            .dormant, in: report(presses(12, "o", "t", day: "2026-09-20"), bindings: long))
        #expect(found?.title.hasSuffix(" not used yet this month") == true)
        #expect(found?.title.count == 40)
    }

    @Test func needsPreviousMonthRecordedFromItsFirstDay() {
        // Recording began 2026-09-02, one day after September began.
        let lines = ["2026-09-02T09:00:00\to\tt", "2026-09-02T09:01:00\to\tt", "2026-09-02T09:02:00\to\tt"]
        #expect(insight(.dormant, in: report(lines, bindings: bindings, anchored: false)) == nil)
    }

    @Test func allowsRecordingThatBeganOnFirstDayOfPreviousMonth() {
        let lines = ["2026-09-01T23:00:00\to\tt", "2026-09-01T23:01:00\to\tt", "2026-09-01T23:02:00\to\tt"]
        #expect(insight(.dormant, in: report(lines, bindings: bindings, anchored: false)) != nil)
    }

    @Test func notDormantIfUsedThisMonth() {
        let lines = presses(12, "o", "t", day: "2026-09-20") + presses(1, "o", "t", day: "2026-10-02")
        #expect(insight(.dormant, in: report(lines)) == nil)
    }

    @Test func needsThreePresses() {
        #expect(insight(.dormant, in: report(presses(2, "o", "t", day: "2026-09-20"))) == nil)
    }

    @Test func picksMostPressed() {
        let lines = presses(4, "o", "t", day: "2026-09-20") + presses(9, "o", "f", day: "2026-09-21")
        #expect(insight(.dormant, in: report(lines))?.keys == [["o", "f"]])
    }
}

@Suite struct BurstTests {
    /// A run of `count` presses two seconds apart starting at `startSecond` of minute `minute`.
    func run(_ count: Int, _ layer: String, _ key: String, minute: Int) -> [String] {
        (0..<count).map { line("2026-10-10T08:\(String(format: "%02d", minute)):\(String(format: "%02d", $0 * 2))", layer, key) }
    }

    @Test func reportsComboWithMostBursts() {
        let lines = run(5, "v", "q", minute: 1) + run(6, "v", "q", minute: 3) + run(5, "w", "u", minute: 5)
        let found = insight(.burst, in: report(lines, bindings: [Binding(layer: "v", key: "q", label: "Left Click")]))
        #expect(found?.title == "Left Click comes in bursts")
        #expect(found?.detail == "V Q pressed 5+ times in a row, 2 times")
        #expect(found?.value == 2)
    }

    @Test func needsTwoBursts() {
        #expect(insight(.burst, in: report(run(5, "v", "q", minute: 1))) == nil)
    }

    @Test func gapOverThreeSecondsBreaksRun() {
        let slow = (0..<10).map { line("2026-10-10T08:01:\(String(format: "%02d", $0 * 4))", "v", "q") }
        #expect(insight(.burst, in: report(slow + run(5, "v", "q", minute: 3))) == nil)
    }

    @Test func otherComboBreaksRun() {
        let lines = run(4, "v", "q", minute: 1) + [line("2026-10-10T08:01:08", "w", "u")]
            + run(4, "v", "q", minute: 2)
        #expect(insight(.burst, in: report(lines)) == nil)
    }
}

@Suite struct PeakTests {
    @Test func reportsBusiestHour() {
        let lines = presses(15, "w", "u", day: "2026-10-14", hour: 14) + presses(5, "o", "t", day: "2026-10-14", hour: 9)
        let found = insight(.peak, in: report(lines))
        #expect(found?.title == "Most active 14:00–15:00")
        #expect(found?.detail == "75% of this month's presses")
        #expect(found?.value == 14)
        #expect(found?.keys == [])
    }

    @Test func needsTwentyPresses() {
        #expect(insight(.peak, in: report(presses(19, "w", "u", day: "2026-10-14"))) == nil)
    }

    @Test func lastHourWrapsToMidnight() {
        let found = insight(.peak, in: report(presses(20, "w", "u", day: "2026-10-14", hour: 23)))
        #expect(found?.title == "Most active 23:00–00:00")
    }
}

@Suite struct ReportTests {
    @Test func ordersInsightsAndTruncatesText() {
        let longLabel = String(repeating: "L", count: 60)
        let bindings = [Binding(layer: "w", key: "u", label: longLabel)]
        let lines = presses(30, "w", "u", day: "2026-10-14", hour: 14)
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
        let lines = presses(3, "w", "u", day: "2026-10-14") + ["junk", "2026-10-13T08:15:00\tw\tu"]
        let result = report(lines, anchored: false)
        #expect(result.recordingSince == "2026-10-13T08:15:00")
        #expect(result.rejectedLines == 1)
    }

    @Test func logThatStartedToday() {
        let result = report(presses(25, "w", "u", day: "2026-10-15", hour: 9), anchored: false)
        #expect(result.recordingSince == "2026-10-15T09:00:00")
        #expect(result.insights.map(\.kind) == [.unbound, .peak])
    }

    @Test func monthBoundaryCountsOnlyNewMonth() {
        let first = date("2026-11-01T00:00:00")
        let lines = ["2026-10-31T23:59:59\tw\tu", "2026-11-01T00:00:00\tw\tu"]
        let result = report(lines, anchored: true, at: first)
        #expect(result.month == "2026-11")
        #expect(result.monthTotal == 1)
    }

    @Test func fullReportOrder() {
        let lines =
            presses(12, "o", "t", day: "2026-09-20")
            + presses(7, "w", "u", day: "2026-10-13") + presses(5, "w", "u", day: "2026-10-05")
            + presses(20, "s", "a", day: "2026-10-14", hour: 14)
        let burst = (0..<5).map { line("2026-10-10T08:01:0\($0)", "v", "q") }
            + (0..<5).map { line("2026-10-10T08:03:0\($0)", "v", "q") }
        let bindings = "abc".map { Binding(layer: "w", key: String($0), label: "x") }
        let result = report(lines + burst, bindings: bindings)
        #expect(
            result.insights.map(\.kind) == [.rising, .unused, .dormant, .unbound, .burst, .peak])
    }

    @Test func fileEncodesVersionTwo() throws {
        let data = try InsightsFile(report: report(["bad line"], anchored: false)).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["version"] as? Int == 2)
        #expect(object["recordingSince"] is NSNull)
        #expect(object["rejectedLines"] as? Int == 1)
        #expect(object["summary"] == nil)
        #expect((object["insights"] as? [Any])?.isEmpty == true)
    }

    @Test func fileWritesRecordingSince() throws {
        let data = try InsightsFile(report: report(presses(1, "w", "u", day: "2026-10-14"))).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["recordingSince"] as? String == "2026-08-01T00:00:00")
    }
}

@Suite struct UnboundTests {
    let bindings = [Binding(layer: "w", key: "u", label: "Previous Tab")]

    @Test func reportsLoggedCombosWithoutBinding() {
        let lines = presses(3, "w", "u", day: "2026-10-14") + presses(5, "o", "t", day: "2026-10-14", hour: 10)
            + presses(2, "o", "f", day: "2026-09-01")
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.title == "2 logged combos no longer bound")
        #expect(found?.detail == "7 presses logged with no current binding")
        #expect(found?.keys == [["o", "t"], ["o", "f"]])
        #expect(found?.value == 2)
    }

    @Test func singularTitle() {
        let found = insight(.unbound, in: report(presses(1, "o", "t", day: "2026-10-14"), bindings: bindings, anchored: false))
        #expect(found?.title == "1 logged combo no longer bound")
        #expect(found?.detail == "1 press logged with no current binding")
    }

    @Test func capsKeysAtThreeMostPressedFirst() {
        let lines = presses(1, "o", "a", day: "2026-10-14") + presses(4, "o", "b", day: "2026-10-14", hour: 10)
            + presses(3, "o", "c", day: "2026-10-14", hour: 11) + presses(2, "o", "d", day: "2026-10-14", hour: 12)
        let found = insight(.unbound, in: report(lines, bindings: bindings, anchored: false))
        #expect(found?.keys == [["o", "b"], ["o", "c"], ["o", "d"]])
        #expect(found?.value == 4)
    }

    @Test func absentWhenAllBound() {
        let result = report(presses(3, "w", "u", day: "2026-10-14"), bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
    }

    @Test func ignoresFutureEvents() {
        let result = report(presses(3, "o", "t", day: "2026-10-16"), bindings: bindings, anchored: false)
        #expect(insight(.unbound, in: result) == nil)
    }
}
