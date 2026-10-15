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

private func log(_ lines: [String]) -> [PressEvent] {
    parseLog(lines.joined(separator: "\n"), calendar: calendar)
}

private func line(_ time: String, _ layer: String, _ key: String) -> String {
    "\(time)\t\(layer)\t\(key)"
}

/// `count` presses of one combo, one per minute starting at `start`.
private func presses(_ count: Int, _ layer: String, _ key: String, day: String, hour: Int = 9)
    -> [String]
{
    (0..<count).map { line("\(day)T\(String(format: "%02d", hour)):\(String(format: "%02d", $0)):00", layer, key) }
}

private func report(_ lines: [String], bindings: [Binding] = []) -> InsightReport {
    computeReport(events: log(lines), bindings: bindings, now: now, calendar: calendar)
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
        #expect(found?.title == "Stopped using Ghostty")
        #expect(found?.detail == "O T · 12 presses in September, none in October")
        #expect(found?.value == 12)
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
        #expect(report([]).insights.isEmpty)
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
        #expect(result.insights.map(\.kind) == [.rising, .unused, .dormant, .burst, .peak])
    }

    @Test func fileEncodesVersionAndInsights() throws {
        let data = try InsightsFile(report: report([])).jsonData()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["version"] as? Int == 1)
        #expect((object["insights"] as? [Any])?.isEmpty == true)
    }
}
