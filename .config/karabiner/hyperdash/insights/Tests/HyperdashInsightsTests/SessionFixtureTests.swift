import Foundation
import Testing

@testable import HyperdashInsights

// Runs the hand-computed cases shared with the page (hyperdash/tests/session_cases.json).
// Day intervals in that file are the page's display model; this package computes spans
// and per-press apps only, so those are what is compared.

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("../tests/session_cases.json").standardized

private func fixture() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
}

private func events(_ lines: [[String]]) -> [ContextEvent] {
    parseContextLog(lines.map { $0.joined(separator: "\t") }.joined(separator: "\n"), calendar: calendar)
        .events
}

private func stamp(_ date: Date) -> String {
    let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded()) % 1000
    return formatTimestamp(date, calendar: calendar) + String(format: ".%03d", milliseconds)
}

@Suite struct SessionFixtureTests {
    @Test func sessionSpansAndAttributionMatchFixture() throws {
        let cases = try fixture()["sessions"] as! [[String: Any]]
        var mismatches: [String] = []
        for item in cases {
            let name = item["name"] as! String
            let now = parseTimestamp(item["now"] as! String, calendar: calendar)!
            let context = events(item["context"] as! [[String]])
            let spans = Sessions(context: context, now: now).spans.map { [stamp($0.start), stamp($0.end)] }
            let expected = item["spans"] as! [[String]]
            if spans != expected { mismatches.append("\(name): spans \(spans) expected \(expected)") }

            let presses = item["presses"] as! [[Any]]
            let pressEvents = presses.map {
                PressEvent(
                    date: parseTimestamp($0[0] as! String, calendar: calendar)!,
                    combo: Combo(layer: "w", key: "u"))
            }
            let apps = attributeApps(events: pressEvents, context: context, now: now, calendar: calendar)
            let want = presses.map { $0[1] as? String }
            if apps != want { mismatches.append("\(name): apps \(apps) expected \(want)") }
        }
        #expect(cases.count == 10)
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
    }

    @Test func attributionCasesMatchFixture() throws {
        let cases = try fixture()["attribution"] as! [[String: Any]]
        var mismatches: [String] = []
        for item in cases {
            let name = item["name"] as! String
            let now = parseTimestamp(item["now"] as! String, calendar: calendar)!
            let pressEvents = (item["presses"] as! [String]).map {
                PressEvent(
                    date: parseTimestamp($0, calendar: calendar)!, combo: Combo(layer: "w", key: "u"))
            }
            let apps = attributeApps(
                events: pressEvents, context: events(item["context"] as! [[String]]), now: now,
                calendar: calendar)
            let want = (item["expected"] as! [Any]).map { $0 as? String }
            if apps != want { mismatches.append("\(name): apps \(apps) expected \(want)") }
        }
        #expect(cases.count == 9)
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
    }
}
