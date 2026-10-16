// CONTEXT LOG (contract section 2; written by Hammerspoon)
//
// One event per line, "YYYY-MM-DDTHH:MM:SS.mmm<TAB>kind<TAB>value", in local time.
//   - The timestamp is a usage-log timestamp (see Parsing.swift) plus exactly three
//     digits of milliseconds.
//   - kind is one of: app, lock, unlock, sleep, wake, start.
//   - For app the value is a bundle ID: ASCII letters, digits, ".", "_" and "-", and not
//     just "-". For every other kind the value is exactly "-".
// Other non-empty lines are rejected. Zero-length lines are ignored.
//
// SESSIONS. A session begins at a `start` event. It ends at the last context event before
// the next `start`, or at `now` for the last session. Two sessions with 60 s or less
// between them count as one, which bridges a Hammerspoon reload. Everything outside a
// session is unknown. Lock and sleep inside a session do not end it.
//
// ATTRIBUTION. A Hyper press at second t belongs to the app of the last `app` event whose
// timestamp, floored to the second, is strictly before t. Events in the same second as the
// press count as later, so an app-launch shortcut stays attributed to the app it left.
// A `start` clears the current app. A press outside every session has no app (nil).

import Foundation

public enum ContextKind: String, Sendable {
    case app, lock, unlock, sleep, wake, start
}

public struct ContextEvent: Equatable, Sendable {
    public let date: Date
    public let kind: ContextKind
    public let value: String

    public init(date: Date, kind: ContextKind, value: String) {
        self.date = date
        self.kind = kind
        self.value = value
    }
}

public struct ParsedContext: Sendable {
    /// Valid events, sorted by time.
    public let events: [ContextEvent]
    /// Non-empty lines that failed validation.
    public let rejectedLines: Int
}

/// Parses "YYYY-MM-DDTHH:MM:SS.mmm" as local time in `calendar`.
func parseContextTimestamp(_ text: String, calendar: Calendar) -> Date? {
    let bytes = Array(text.utf8)
    guard bytes.count == 23, bytes[19] == 46,
          bytes[20...22].allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let base = parseTimestamp(String(text.prefix(19)), calendar: calendar)
    else { return nil }
    let milliseconds = bytes[20...22].reduce(0) { $0 * 10 + Int($1 - 48) }
    return base.addingTimeInterval(Double(milliseconds) / 1000)
}

private func isBundleIdentifier(_ text: Substring) -> Bool {
    text != "-" && !text.isEmpty
        && text.utf8.allSatisfy {
            ($0 >= 97 && $0 <= 122) || ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57)
                || $0 == 46 || $0 == 95 || $0 == 45
        }
}

public func parseContextLog(_ text: String, calendar: Calendar = .current) -> ParsedContext {
    var events: [ContextEvent] = []
    var rejected = 0
    for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 3, let kind = ContextKind(rawValue: String(fields[1])),
              kind == .app ? isBundleIdentifier(fields[2]) : fields[2] == "-",
              let date = parseContextTimestamp(String(fields[0]), calendar: calendar)
        else {
            rejected += 1
            continue
        }
        events.append(ContextEvent(date: date, kind: kind, value: String(fields[2])))
    }
    let sorted = events.enumerated()
        .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        .map(\.element)
    return ParsedContext(events: sorted, rejectedLines: rejected)
}

/// Spans of time the context recorder is known to have been running.
struct Sessions {
    static let bridgedGap: TimeInterval = 60
    private(set) var spans: [(start: Date, end: Date)] = []

    init(context: [ContextEvent], now: Date) {
        let known = context.filter { $0.date <= now }
        let starts = known.filter { $0.kind == .start }.map(\.date)
        for (index, start) in starts.enumerated() {
            var end = now
            if index + 1 < starts.count {
                let next = starts[index + 1]
                end = max(start, known.last { $0.date < next }?.date ?? start)
            }
            if let last = spans.last, start.timeIntervalSince(last.end) <= Sessions.bridgedGap {
                spans[spans.count - 1].end = max(last.end, end)
            } else {
                spans.append((start, end))
            }
        }
    }

    func contains(_ date: Date) -> Bool {
        spans.contains { $0.start <= date && date <= $0.end }
    }
}

/// The app each press belongs to, in the order of `events`, or nil when unknown.
/// `events` must be sorted by time.
public func attributeApps(
    events: [PressEvent], context: [ContextEvent], now: Date, calendar: Calendar
) -> [String?] {
    let known = context.filter { $0.date <= now }
    let sessions = Sessions(context: known, now: now)
    var current: String?
    var index = 0
    return events.map { press in
        while index < known.count,
              Date(timeIntervalSince1970: known[index].date.timeIntervalSince1970.rounded(.down))
                < press.date
        {
            switch known[index].kind {
            case .start: current = nil
            case .app: current = known[index].value
            default: break
            }
            index += 1
        }
        return sessions.contains(press.date) ? current : nil
    }
}

func dayKey(_ date: Date, calendar: Calendar) -> String {
    String(formatTimestamp(date, calendar: calendar).prefix(10))
}

/// Days whose recording is complete enough to state an absence or a change.
///
/// A day qualifies when it falls after the day of the first valid event and before the day
/// of `now`. With a context log, every press on that day must also lie inside a session.
public func recordedDays(
    events: [PressEvent], context: [ContextEvent]?, now: Date, calendar: Calendar
) -> Set<String> {
    let history = events.filter { $0.date <= now }
    guard let first = history.map(\.date).min() else { return [] }
    let sessions = context.map { Sessions(context: $0, now: now) }
    var unrecorded = Set<String>()
    if let sessions {
        for press in history where !sessions.contains(press.date) {
            unrecorded.insert(dayKey(press.date, calendar: calendar))
        }
    }
    let today = calendar.startOfDay(for: now)
    var day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: first))!
    var result = Set<String>()
    while day < today {
        let key = dayKey(day, calendar: calendar)
        if !unrecorded.contains(key) { result.insert(key) }
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return result
}
