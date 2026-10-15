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

    public init(layer: String, key: String, label: String) {
        self.layer = layer
        self.key = key
        self.label = label
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
          (1...12).contains(month), (1...31).contains(day),
          hour < 24, minute < 60, second < 60
    else { return nil }
    let components = DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let date = calendar.date(from: components) else { return nil }
    // Reject rolled-over dates such as 2026-02-31.
    guard calendar.component(.day, from: date) == day else { return nil }
    return date
}

/// Formats a date as "YYYY-MM-DDTHH:MM:SS" in `calendar`'s time zone.
public func formatTimestamp(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
}

/// Parses the usage log. Lines that do not have three tab-separated fields
/// with a valid timestamp are skipped. The result is sorted by time.
public func parseLog(_ text: String, calendar: Calendar = .current) -> [PressEvent] {
    var events: [PressEvent] = []
    for line in text.split(whereSeparator: \.isNewline) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 3, !fields[1].isEmpty, !fields[2].isEmpty,
              let date = parseTimestamp(String(fields[0]), calendar: calendar)
        else { continue }
        events.append(
            PressEvent(date: date, combo: Combo(layer: String(fields[1]), key: String(fields[2]))))
    }
    return events.enumerated()
        .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        .map(\.element)
}

public func parseBindings(_ data: Data) throws -> [Binding] {
    try JSONDecoder().decode([Binding].self, from: data)
}
