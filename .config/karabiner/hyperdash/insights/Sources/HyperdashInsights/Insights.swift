import Foundation

public enum InsightKind: String, Codable, Sendable {
    case focus, rising, falling, unused, dormant, unbound, burst, peak
}

public struct Insight: Codable, Equatable, Sendable {
    public let kind: InsightKind
    public let title: String
    public let detail: String
    public let keys: [[String]]
    public let value: Int
    /// Days ("YYYY-MM-DD", ascending, at most 31) whose events support the finding.
    public let dates: [String]
    /// Bundle ID when the finding concerns one app.
    public let app: String?

    public init(
        kind: InsightKind, title: String, detail: String, keys: [Combo], value: Int,
        dates: [String] = [], app: String? = nil
    ) {
        self.kind = kind
        self.title = truncated(title, to: 40)
        self.detail = truncated(detail, to: 52)
        self.keys = keys.prefix(3).map { [$0.layer, $0.key] }
        self.value = value
        self.dates = Array(Set(dates).sorted().suffix(31))
        self.app = app
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, detail, keys, value, dates, app
    }

    // Always write `app`, as null when absent.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(keys, forKey: .keys)
        try container.encode(value, forKey: .value)
        try container.encode(dates, forKey: .dates)
        try container.encode(app, forKey: .app)
    }
}

public struct InsightReport: Sendable {
    public let generated: String
    public let month: String
    public let insights: [Insight]
    /// Presses in the month of `now`.
    public let monthTotal: Int
    /// Earliest valid event at or before `now`, or nil when there is none.
    public let recordingSince: String?
    public let rejectedLines: Int
}

public let layerNames: [String: String] = [
    "b": "Browse", "o": "Open", "w": "Window", "c": "Capture",
    "f": "Finder", "s": "System", "v": "Move", "r": "Launcher",
]

private let shortMonthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

private let monthNames = [
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December",
]

func truncated(_ text: String, to limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
}

/// "tab-navigation" becomes "Tab navigation".
func categoryName(_ category: String) -> String {
    let words = category.replacingOccurrences(of: "-", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
}

/// A display name guessed from a bundle ID: "org.mozilla.firefox" becomes "Firefox".
/// The panel replaces it with the real name from the host.
func appName(_ bundleIdentifier: String) -> String {
    let last = bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    return last.prefix(1).uppercased() + last.dropFirst()
}

/// Everything the rules share. Built once by `computeReport`.
private struct Analysis {
    let history: [PressEvent]
    let bindings: [Binding]
    let now: Date
    let today: Date
    let calendar: Calendar
    let recorded: Set<String>
    let labels: [Combo: String]

    func name(_ combo: Combo) -> String { labels[combo] ?? "Hyper \(combo.shortName)" }
    func key(_ date: Date) -> String { dayKey(date, calendar: calendar) }

    /// The day `offset` days before today.
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }
    func keyDaysAgo(_ offset: Int) -> String { key(day(offset)) }
}

/// `events` must be sorted by time, as `parseLog` returns them.
public func computeReport(
    events: [PressEvent], bindings: [Binding], now: Date, rejectedLines: Int = 0,
    context: [ContextEvent]? = nil, calendar: Calendar = .current
) -> InsightReport {
    var labels: [Combo: String] = [:]
    for binding in bindings { labels[binding.combo] = binding.label }

    // Presses after `now` are ignored so every rule sees the same history.
    let history = events.filter { $0.date <= now }
    let analysis = Analysis(
        history: history, bindings: bindings, now: now, today: calendar.startOfDay(for: now),
        calendar: calendar,
        recorded: recordedDays(events: history, context: context, now: now, calendar: calendar),
        labels: labels)
    let monthStart = calendar.dateInterval(of: .month, for: now)!.start
    let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
    let thisMonth = history.filter { $0.date >= monthStart }

    // Claims about absence or change need recorded history to back them up.
    let recordingStart = history.map(\.date).min()

    var insights: [Insight] = []
    insights += focus(analysis, context: context)
    insights += trend(analysis)
    insights += unused(analysis)
    if let recordingStart,
       recordingStart < calendar.date(byAdding: .day, value: 1, to: previousMonthStart)!
    {
        insights += dormant(analysis, monthStart: monthStart, previousMonthStart: previousMonthStart)
    }
    insights += unbound(analysis)
    insights += burst(thisMonth, analysis)
    insights += peak(thisMonth, analysis)

    return InsightReport(
        generated: formatTimestamp(now, calendar: calendar),
        month: String(formatTimestamp(now, calendar: calendar).prefix(7)),
        insights: insights,
        monthTotal: thisMonth.count,
        recordingSince: recordingStart.map { formatTimestamp($0, calendar: calendar) },
        rejectedLines: rejectedLines)
}

// MARK: - focus

/// The category with the most presses over the last 7 days, and the app it mostly happens in.
private func focus(_ a: Analysis, context: [ContextEvent]?) -> [Insight] {
    var categoryOf: [Combo: String] = [:]
    for binding in a.bindings { if let category = binding.category { categoryOf[binding.combo] = category } }
    guard !categoryOf.isEmpty else { return [] }

    let windowDays = Set((0...6).map { a.keyDaysAgo($0) })
    let apps: [String?]? = context.map {
        attributeApps(events: a.history, context: $0, now: a.now, calendar: a.calendar)
    }
    // Presses in the window, with the app each one is attributed to.
    var window: [(day: String, combo: Combo, app: String?)] = []
    for (index, press) in a.history.enumerated() where windowDays.contains(a.key(press.date)) {
        window.append((a.key(press.date), press.combo, apps?[index] ?? nil))
    }
    guard window.count >= 30 else { return [] }

    func top(_ counts: [String: Int]) -> String? {
        counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.first?.key
    }
    var categoryCounts: [String: Int] = [:]
    var dayCategoryCounts: [String: [String: Int]] = [:]
    var dayTotals: [String: Int] = [:]
    for press in window {
        dayTotals[press.day, default: 0] += 1
        if let category = categoryOf[press.combo] {
            categoryCounts[category, default: 0] += 1
            dayCategoryCounts[press.day, default: [:]][category, default: 0] += 1
        }
    }
    guard let category = top(categoryCounts) else { return [] }
    let repeatDays = dayTotals.keys.filter {
        dayTotals[$0]! >= 5 && top(dayCategoryCounts[$0] ?? [:]) == category
    }
    guard repeatDays.count >= 3 else { return [] }

    let share = Int((Double(categoryCounts[category]!) / Double(window.count) * 100).rounded())
    var combos: [Combo: Int] = [:]
    for press in window where categoryOf[press.combo] == category { combos[press.combo, default: 0] += 1 }
    let keys = combos.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    let display = categoryName(category)

    // Name an app only when most attributed presses and several days agree on it.
    let inCategory = window.filter { categoryOf[$0.combo] == category }
    var appCounts: [String: Int] = [:]
    for press in inCategory { if let app = press.app { appCounts[app, default: 0] += 1 } }
    let attributed = appCounts.values.reduce(0, +)
    if attributed >= 20, attributed * 10 >= inCategory.count * 6, let app = top(appCounts),
       appCounts[app]! * 2 > attributed
    {
        var dayAppCounts: [String: [String: Int]] = [:]
        for press in inCategory { if let app = press.app { dayAppCounts[press.day, default: [:]][app, default: 0] += 1 } }
        let appDays = dayAppCounts.filter {
            $0.value.values.reduce(0, +) >= 3 && top($0.value) == app
        }.keys
        if appDays.count >= 3 {
            let appShare = Int((Double(appCounts[app]!) / Double(attributed) * 100).rounded())
            let head = "\(display) mostly in "
            return [
                Insight(
                    kind: .focus, title: head + truncated(appName(app), to: 40 - head.count),
                    detail: "\(appShare)% of \(attributed) attributed presses · \(appDays.count) days",
                    keys: keys, value: share, dates: Array(appDays), app: app)
            ]
        }
    }
    return [
        Insight(
            kind: .focus, title: "\(display) leads your Hyper use",
            detail: "\(share)% of \(window.count) presses · top on \(repeatDays.count) days",
            keys: keys, value: share, dates: repeatDays)
    ]
}

// MARK: - rising and falling

/// Compares the 7 whole days before today with the 7 before those. Needs all 14 days
/// recorded, at least 10 presses in the larger week, a change of at least 5 presses, and
/// the change repeated on at least 4 of the 7 recent days. Ranks by absolute change.
private func trend(_ a: Analysis) -> [Insight] {
    let recentDays = (1...7).map { a.keyDaysAgo($0) }
    let previousDays = (8...14).map { a.keyDaysAgo($0) }
    guard Set(recentDays + previousDays).isSubset(of: a.recorded) else { return [] }
    let recentSet = Set(recentDays)
    let previousSet = Set(previousDays)

    var perDay: [Combo: [String: Int]] = [:]
    for press in a.history {
        let day = a.key(press.date)
        if recentSet.contains(day) || previousSet.contains(day) {
            perDay[press.combo, default: [:]][day, default: 0] += 1
        }
    }

    var best: (combo: Combo, now: Int, was: Int, repeats: [String])?
    for combo in perDay.keys.sorted() {
        let days = perDay[combo]!
        let now = recentDays.reduce(0) { $0 + days[$1, default: 0] }
        let was = previousDays.reduce(0) { $0 + days[$1, default: 0] }
        let change = now - was
        guard max(now, was) >= 10, abs(change) >= 5 else { continue }
        // The recent day beats (or trails) an average day of the earlier week.
        let repeats = recentDays.filter {
            let count = days[$0, default: 0] * 7
            return change > 0 ? count > was : count < was
        }
        guard repeats.count >= 4 else { continue }
        if let current = best {
            let currentChange = abs(current.now - current.was)
            if (abs(change), repeats.count) <= (currentChange, current.repeats.count) { continue }
        }
        best = (combo, now, was, repeats)
    }
    guard let best else { return [] }
    let change = best.now - best.was
    let rising = change > 0
    let suffix = " \(rising ? "up" : "down") \(abs(change)) presses this week"
    return [
        Insight(
            kind: rising ? .rising : .falling,
            title: truncated(a.name(best.combo), to: 40 - suffix.count) + suffix,
            detail: "\(best.combo.shortName) · \(best.now) vs \(best.was) the week before · "
                + "\(rising ? "up" : "down") on \(best.repeats.count) days",
            keys: [best.combo], value: abs(change), dates: best.repeats)
    ]
}

// MARK: - unused

/// The layer with the highest share of unused bindings over the last 30 days. Needs at
/// least 3 fully recorded days in that window, a layer of 4 or more bindings, and 3 or
/// more unused.
private func unused(_ a: Analysis) -> [Insight] {
    let windowDays = (1...30).map { a.keyDaysAgo($0) }.filter { a.recorded.contains($0) }
    guard windowDays.count >= 3 else { return [] }
    let windowStart = a.day(30)
    let pressed = Set(a.history.filter { $0.date >= windowStart }.map(\.combo))

    var perLayer: [String: [Combo]] = [:]
    var totals: [String: Int] = [:]
    var seen = Set<Combo>()
    for binding in a.bindings where seen.insert(binding.combo).inserted {
        totals[binding.layer, default: 0] += 1
        if !pressed.contains(binding.combo) { perLayer[binding.layer, default: []].append(binding.combo) }
    }
    var best: (layer: String, unused: [Combo], total: Int)?
    for layer in perLayer.keys.sorted() {
        let list = perLayer[layer]!
        let total = totals[layer]!
        guard total >= 4, list.count >= 3 else { continue }
        if let current = best {
            // Compare list.count / total with current.unused.count / current.total.
            let left = list.count * current.total
            let right = current.unused.count * total
            if (left, list.count) <= (right, current.unused.count) { continue }
        }
        best = (layer, list, total)
    }
    guard let best else { return [] }
    let layerName = layerNames[best.layer] ?? "Hyper \(best.layer.uppercased())"
    return [
        Insight(
            kind: .unused,
            title: "\(best.unused.count) of \(best.total) \(layerName) shortcuts unused",
            detail: "No presses on \(windowDays.count) recorded days",
            keys: best.unused, value: best.unused.count, dates: windowDays)
    ]
}

// MARK: - dormant

/// A combo with 3 or more presses on 2 or more days last month and none this month.
private func dormant(_ a: Analysis, monthStart: Date, previousMonthStart: Date) -> [Insight] {
    var previous: [Combo: [String: Int]] = [:]
    var current = Set<Combo>()
    for event in a.history {
        if event.date >= monthStart {
            current.insert(event.combo)
        } else if event.date >= previousMonthStart {
            previous[event.combo, default: [:]][a.key(event.date), default: 0] += 1
        }
    }
    let totals = previous.compactMapValues { days -> Int? in
        let total = days.values.reduce(0, +)
        return total >= 3 && days.count >= 2 ? total : nil
    }.filter { !current.contains($0.key) }
    guard let best = totals.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else { return [] }
    let previousName = monthNames[a.calendar.component(.month, from: previousMonthStart) - 1]
    let currentShort = shortMonthNames[a.calendar.component(.month, from: monthStart) - 1]
    // "Not used yet" is true at any point in the month; it makes no claim about stopping.
    let suffix = " not used yet this month"
    return [
        Insight(
            kind: .dormant,
            title: truncated(a.name(best.key), to: 40 - suffix.count) + suffix,
            detail: "\(best.key.shortName) · \(best.value) presses in \(previousName) · none since \(currentShort) 1",
            keys: [best.key], value: best.value, dates: Array(previous[best.key]!.keys))
    ]
}

// MARK: - unbound

private func unbound(_ a: Analysis) -> [Insight] {
    let bound = Set(a.bindings.map(\.combo))
    var counts: [Combo: Int] = [:]
    var days = Set<String>()
    for event in a.history where !bound.contains(event.combo) {
        counts[event.combo, default: 0] += 1
        days.insert(a.key(event.date))
    }
    guard !counts.isEmpty else { return [] }
    let ranked = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
    let presses = counts.values.reduce(0, +)
    return [
        Insight(
            kind: .unbound,
            title: "\(counts.count) logged \(counts.count == 1 ? "combo" : "combos") no longer bound",
            detail: "\(presses) \(presses == 1 ? "press" : "presses") logged with no current binding",
            keys: ranked.map(\.key), value: counts.count, dates: Array(days))
    ]
}

// MARK: - burst

/// A burst is 5 or more presses of one combo in a row, each within 3 s of the last.
/// Reports the combo with the most bursts this month, if it has 2 or more on 2 or more days.
private func burst(_ thisMonth: [PressEvent], _ a: Analysis) -> [Insight] {
    var counts: [Combo: Int] = [:]
    var days: [Combo: Set<String>] = [:]
    var run = 0
    var runStart: PressEvent?
    var last: PressEvent?
    func closeRun() {
        if run >= 5, let runStart {
            counts[runStart.combo, default: 0] += 1
            days[runStart.combo, default: []].insert(a.key(runStart.date))
        }
    }
    for event in thisMonth {
        if let previous = last, previous.combo == event.combo,
           event.date.timeIntervalSince(previous.date) <= 3 {
            run += 1
        } else {
            closeRun()
            run = 1
            runStart = event
        }
        last = event
    }
    closeRun()
    let eligible = counts.filter { $0.value >= 2 && days[$0.key]!.count >= 2 }
    guard let best = eligible.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else { return [] }
    let dayCount = days[best.key]!.count
    return [
        Insight(
            kind: .burst,
            title: "\(a.name(best.key)) comes in bursts",
            detail: "\(best.key.shortName) pressed 5+ times in a row, \(best.value) times on \(dayCount) days",
            keys: [best.key], value: best.value, dates: Array(days[best.key]!))
    ]
}

// MARK: - peak

/// The hour with the most presses this month among hours with presses on 3 or more days.
private func peak(_ thisMonth: [PressEvent], _ a: Analysis) -> [Insight] {
    guard thisMonth.count >= 20 else { return [] }
    var counts = [Int](repeating: 0, count: 24)
    var days = [Set<String>](repeating: [], count: 24)
    for event in thisMonth {
        let hour = a.calendar.component(.hour, from: event.date)
        counts[hour] += 1
        days[hour].insert(a.key(event.date))
    }
    let eligible = (0..<24).filter { days[$0].count >= 3 }
    guard let hour = eligible.max(by: { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) })
    else { return [] }
    let share = Int((Double(counts[hour]) / Double(thisMonth.count) * 100).rounded())
    return [
        Insight(
            kind: .peak,
            title: String(format: "Most active %02d:00–%02d:00", hour, (hour + 1) % 24),
            detail: "\(share)% of this month's presses",
            keys: [], value: hour, dates: Array(days[hour]))
    ]
}
