// LOG LINE VALIDITY (contract section 1; the JavaScript parser must match exactly)
//
// The usage log is split into lines on "\n" or "\r\n". A zero-length line is ignored and
// not counted. Every other line is valid only if all of these hold:
//   1. It has exactly 3 fields separated by single tab characters.
//   2. Field 1 is a local timestamp "YYYY-MM-DDTHH:MM:SS": ASCII digits and the fixed
//      separators only, 19 characters, no zone, no fraction, no surrounding space.
//   3. The timestamp is a real local time: year >= 1970, month 1-12, hour 0-23, minute and
//      second 0-59, and a day that exists in that month. It must also survive a round trip
//      through the local calendar, so a time skipped by a daylight saving change is invalid.
//   4. Field 2 (layer) and field 3 (key) are non-empty and match ^[a-z0-9_]+$.
// Every other non-empty line is rejected and counted in `rejectedLines`.
//
// A valid line dated after `now` is not rejected. Analysis ignores it, and it does not set
// `recordingSince`. "Last used" is the maximum valid timestamp, not the last line.

import Foundation

public struct Combo: Hashable, Comparable, Sendable {
    public let layer: String
    public let key: String

    public init(layer: String, key: String) {
        self.layer = layer
        self.key = key
    }

    public static func < (lhs: Combo, rhs: Combo) -> Bool {
        (lhs.layer, lhs.key) < (rhs.layer, rhs.key)
    }

    /// "W U", the short form used in detail lines.
    public var shortName: String { "\(layer.uppercased()) \(key.uppercased())" }
}

public struct PressEvent: Equatable, Sendable {
    public let date: Date
    public let combo: Combo

    public init(date: Date, combo: Combo) {
        self.date = date
        self.combo = combo
    }
}

public struct Binding: Decodable, Equatable, Sendable {
    public let layer: String
    public let key: String
    public let label: String
    /// Activity category such as "tab-navigation"; nil when bindings.json has none.
    public let category: String?

    public init(layer: String, key: String, label: String, category: String? = nil) {
        self.layer = layer
        self.key = key
        self.label = label
        self.category = category
    }

    public var combo: Combo { Combo(layer: layer, key: key) }
}

/// Parses "YYYY-MM-DDTHH:MM:SS" as local time in `calendar`. Returns nil when malformed.
public func parseTimestamp(_ text: String, calendar: Calendar) -> Date? {
    let bytes = Array(text.utf8)
    guard bytes.count == 19 else { return nil }
    let separators: [Int: UInt8] = [4: 45, 7: 45, 10: 84, 13: 58, 16: 58]
    for (index, byte) in separators where bytes[index] != byte { return nil }
    func number(_ range: Range<Int>) -> Int? {
        var value = 0
        for byte in bytes[range] {
            guard byte >= 48, byte <= 57 else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        return value
    }
    guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
          let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
          year >= 1970, (1...12).contains(month), (1...31).contains(day),
          hour < 24, minute < 60, second < 60
    else { return nil }
    let components = DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let date = calendar.date(from: components) else { return nil }
    // Reject rolled-over dates such as 2026-02-31.
    let round = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    guard round.year == year, round.month == month, round.day == day, round.hour == hour
    else { return nil }
    return date
}

/// Formats a date as "YYYY-MM-DDTHH:MM:SS" in `calendar`'s time zone.
public func formatTimestamp(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
}

public struct ParsedLog: Sendable {
    /// Valid events, sorted by time.
    public let events: [PressEvent]
    /// Non-empty lines that failed validation.
    public let rejectedLines: Int
}

private func isIdentifier(_ text: Substring) -> Bool {
    !text.isEmpty && text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
}

/// One non-empty line without its line break, by the rules at the top of this file.
/// Returns nil for a line that is rejected.
func parseLogLine(_ line: Substring, calendar: Calendar) -> PressEvent? {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
    guard fields.count == 3, isIdentifier(fields[1]), isIdentifier(fields[2]),
          let date = parseTimestamp(String(fields[0]), calendar: calendar)
    else { return nil }
    return PressEvent(date: date, combo: Combo(layer: String(fields[1]), key: String(fields[2])))
}

/// Parses the usage log by the rules at the top of this file.
public func parseLog(_ text: String, calendar: Calendar = .current) -> ParsedLog {
    var events: [PressEvent] = []
    var rejected = 0
    for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
        guard let event = parseLogLine(line, calendar: calendar) else {
            rejected += 1
            continue
        }
        events.append(event)
    }
    let sorted = events.enumerated()
        .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        .map(\.element)
    return ParsedLog(events: sorted, rejectedLines: rejected)
}

public func parseBindings(_ data: Data) throws -> [Binding] {
    try JSONDecoder().decode([Binding].self, from: data)
}
