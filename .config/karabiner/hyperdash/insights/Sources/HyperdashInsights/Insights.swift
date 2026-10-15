import Foundation

public enum InsightKind: String, Codable, Sendable {
    case rising, falling, dormant, unused, peak, burst
}

public struct Insight: Codable, Equatable, Sendable {
    public let kind: InsightKind
    public let title: String
    public let detail: String
    public let keys: [[String]]
    public let value: Int

    public init(kind: InsightKind, title: String, detail: String, keys: [Combo], value: Int) {
        self.kind = kind
        self.title = truncated(title, to: 40)
        self.detail = truncated(detail, to: 52)
        self.keys = keys.prefix(3).map { [$0.layer, $0.key] }
        self.value = value
    }
}

public struct InsightReport: Sendable {
    public let generated: String
    public let month: String
    public let insights: [Insight]
    /// Presses in the month of `now`.
    public let monthTotal: Int
}

public let layerNames: [String: String] = [
    "b": "Browse", "o": "Open", "w": "Window", "c": "Capture",
    "f": "Finder", "s": "System", "v": "Move", "r": "Launcher",
]

private let monthNames = [
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December",
]

func truncated(_ text: String, to limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
}

public func computeReport(
    events: [PressEvent], bindings: [Binding], now: Date, calendar: Calendar = .current
) -> InsightReport {
    var labels: [Combo: String] = [:]
    for binding in bindings { labels[binding.combo] = binding.label }
    func name(_ combo: Combo) -> String { labels[combo] ?? "Hyper \(combo.shortName)" }

    // Presses after `now` are ignored so every rule sees the same history.
    let history = events.filter { $0.date <= now }
    let monthStart = calendar.dateInterval(of: .month, for: now)!.start
    let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
    let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
    let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!
    let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!

    let thisMonth = history.filter { $0.date >= monthStart }
    var monthCounts: [Combo: Int] = [:]
    for event in thisMonth { monthCounts[event.combo, default: 0] += 1 }

    var insights: [Insight] = []
    insights += trend(history, weekAgo: weekAgo, twoWeeksAgo: twoWeeksAgo, name: name)
    insights += unused(history, bindings: bindings, since: thirtyDaysAgo)
    insights += dormant(
        history, monthStart: monthStart, previousMonthStart: previousMonthStart,
        calendar: calendar, name: name)
    insights += burst(thisMonth, name: name)
    insights += peak(thisMonth, calendar: calendar)

    return InsightReport(
        generated: formatTimestamp(now, calendar: calendar),
        month: String(formatTimestamp(now, calendar: calendar).prefix(7)),
        insights: Array(insights.prefix(5)),
        monthTotal: thisMonth.count)
}

private func trend(
    _ history: [PressEvent], weekAgo: Date, twoWeeksAgo: Date, name: (Combo) -> String
) -> [Insight] {
    var recent: [Combo: Int] = [:]
    var before: [Combo: Int] = [:]
    for event in history {
        if event.date > weekAgo {
            recent[event.combo, default: 0] += 1
        } else if event.date > twoWeeksAgo {
            before[event.combo, default: 0] += 1
        }
    }
    // A combo with no presses in the earlier week has no defined percentage change; skip it.
    var best: (combo: Combo, now: Int, was: Int, percent: Int, magnitude: Double)?
    for combo in Set(recent.keys).union(before.keys).sorted() {
        let now = recent[combo, default: 0]
        let was = before[combo, default: 0]
        guard max(now, was) >= 5, was > 0 else { continue }
        let change = Double(now - was) / Double(was) * 100
        let percent = Int(change.rounded())
        guard percent != 0 else { continue }
        if best == nil || abs(change) > best!.magnitude {
            best = (combo, now, was, percent, abs(change))
        }
    }
    guard let best else { return [] }
    let rising = best.percent > 0
    return [
        Insight(
            kind: rising ? .rising : .falling,
            title: "\(name(best.combo)) \(rising ? "up" : "down") \(abs(best.percent))% this week",
            detail: "\(best.combo.shortName) · \(best.now) presses vs \(best.was) the week before",
            keys: [best.combo],
            value: abs(best.percent))
    ]
}

private func unused(_ history: [PressEvent], bindings: [Binding], since: Date) -> [Insight] {
    let pressed = Set(history.filter { $0.date > since }.map(\.combo))
    var perLayer: [String: [Combo]] = [:]
    var totals: [String: Int] = [:]
    var seen = Set<Combo>()
    for binding in bindings where seen.insert(binding.combo).inserted {
        totals[binding.layer, default: 0] += 1
        if !pressed.contains(binding.combo) { perLayer[binding.layer, default: []].append(binding.combo) }
    }
    guard let layer = perLayer.keys.sorted().max(by: { perLayer[$0]!.count < perLayer[$1]!.count }),
          let combos = perLayer[layer], combos.count >= 3
    else { return [] }
    let layerName = layerNames[layer] ?? "Hyper \(layer.uppercased())"
    return [
        Insight(
            kind: .unused,
            title: "\(combos.count) of \(totals[layer]!) \(layerName) shortcuts unused",
            detail: "No presses in the last 30 days",
            keys: combos,
            value: combos.count)
    ]
}

private func dormant(
    _ history: [PressEvent], monthStart: Date, previousMonthStart: Date, calendar: Calendar,
    name: (Combo) -> String
) -> [Insight] {
    var previous: [Combo: Int] = [:]
    var current = Set<Combo>()
    for event in history {
        if event.date >= monthStart {
            current.insert(event.combo)
        } else if event.date >= previousMonthStart {
            previous[event.combo, default: 0] += 1
        }
    }
    let candidates = previous.filter { $0.value >= 3 && !current.contains($0.key) }
    guard let best = candidates.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else {
        return []
    }
    let previousName = monthNames[calendar.component(.month, from: previousMonthStart) - 1]
    let currentName = monthNames[calendar.component(.month, from: monthStart) - 1]
    return [
        Insight(
            kind: .dormant,
            title: "Stopped using \(name(best.key))",
            detail: "\(best.key.shortName) · \(best.value) presses in \(previousName), none in \(currentName)",
            keys: [best.key],
            value: best.value)
    ]
}

/// A burst is 5 or more presses of one combo in a row, each within 3 s of the last.
private func burst(_ thisMonth: [PressEvent], name: (Combo) -> String) -> [Insight] {
    var bursts: [Combo: Int] = [:]
    var run = 0
    var last: PressEvent?
    func closeRun() {
        if run >= 5, let last { bursts[last.combo, default: 0] += 1 }
    }
    for event in thisMonth {
        if let previous = last, previous.combo == event.combo,
           event.date.timeIntervalSince(previous.date) <= 3 {
            run += 1
        } else {
            closeRun()
            run = 1
        }
        last = event
    }
    closeRun()
    guard let best = bursts.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }), best.value >= 2
    else { return [] }
    return [
        Insight(
            kind: .burst,
            title: "\(name(best.key)) comes in bursts",
            detail: "\(best.key.shortName) pressed 5+ times in a row, \(best.value) times",
            keys: [best.key],
            value: best.value)
    ]
}

private func peak(_ thisMonth: [PressEvent], calendar: Calendar) -> [Insight] {
    guard thisMonth.count >= 20 else { return [] }
    var hours = [Int](repeating: 0, count: 24)
    for event in thisMonth { hours[calendar.component(.hour, from: event.date)] += 1 }
    let top = hours.max()!
    let hour = hours.firstIndex(of: top)!
    let share = Int((Double(top) / Double(thisMonth.count) * 100).rounded())
    return [
        Insight(
            kind: .peak,
            title: String(format: "Most active %02d:00–%02d:00", hour, (hour + 1) % 24),
            detail: "\(share)% of this month's presses",
            keys: [],
            value: hour)
    ]
}
