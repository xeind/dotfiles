import Foundation

public enum InsightKind: String, Codable, Sendable {
    case focus, rising, falling, unused, dormant, unbound, burst, peak
}

/// The number a card rests on, with what it is part of and what it is compared with.
public struct Measure: Codable, Equatable, Sendable {
    public let count: Int
    /// The whole `count` is part of (presses in the window, bindings in the layer); nil when none.
    public let total: Int?
    /// The same count in the comparison period; nil without one.
    public let baseline: Int?
    /// "presses", "bindings" or "bursts".
    public let unit: String

    public init(count: Int, total: Int? = nil, baseline: Int? = nil, unit: String) {
        self.count = count
        self.total = total
        self.baseline = baseline
        self.unit = unit
    }

    // Always write `total` and `baseline`, as null when absent.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        try container.encode(total, forKey: .total)
        try container.encode(baseline, forKey: .baseline)
        try container.encode(unit, forKey: .unit)
    }
}

public struct Insight: Codable, Equatable, Sendable {
    public let kind: InsightKind
    /// Full text. The panel clips only what it draws.
    public let title: String
    public let detail: String
    /// Every combo the finding concerns, most relevant first.
    public let keys: [[String]]
    public let value: Int
    /// Days ("YYYY-MM-DD", ascending) whose events support the finding.
    public let dates: [String]
    /// Bundle ID when the finding concerns one app.
    public let app: String?
    /// First and last day ("YYYY-MM-DD") of the period the finding counts.
    public let windowStart: String
    public let windowEnd: String
    /// The period it is compared with, or nil when it compares none.
    public let comparisonStart: String?
    public let comparisonEnd: String?
    public let measure: Measure

    public init(
        kind: InsightKind, title: String, detail: String, keys: [Combo], value: Int,
        dates: [String] = [], app: String? = nil, window: (start: String, end: String),
        comparison: (start: String, end: String)? = nil, measure: Measure
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.keys = keys.map { [$0.layer, $0.key] }
        self.value = value
        self.dates = Set(dates).sorted()
        self.app = app
        windowStart = window.start
        windowEnd = window.end
        comparisonStart = comparison?.start
        comparisonEnd = comparison?.end
        self.measure = measure
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, detail, keys, value, dates, app
        case windowStart, windowEnd, comparisonStart, comparisonEnd, measure
    }

    // Always write `app` and the comparison, as null when absent.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(keys, forKey: .keys)
        try container.encode(value, forKey: .value)
        try container.encode(dates, forKey: .dates)
        try container.encode(app, forKey: .app)
        try container.encode(windowStart, forKey: .windowStart)
        try container.encode(windowEnd, forKey: .windowEnd)
        try container.encode(comparisonStart, forKey: .comparisonStart)
        try container.encode(comparisonEnd, forKey: .comparisonEnd)
        try container.encode(measure, forKey: .measure)
    }
}

/// What one rule did in a report, and why when it produced no card.
public struct RuleStatus: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Its card is in `insights`.
        case shown
        /// It found something, but `maxCards` cards rank higher.
        case held
        /// Too little recorded history or coverage to apply the rule.
        case notReady = "not-ready"
        /// Enough data, but nothing met the rule.
        case noPattern = "no-pattern"
    }

    public let rule: String
    public let status: Status
    /// A sentence with the counts behind the status; nil when shown.
    public let reason: String?

    public init(rule: String, status: Status, reason: String?) {
        self.rule = rule
        self.status = status
        self.reason = reason
    }

    // Always write `reason`, as null when absent.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rule, forKey: .rule)
        try container.encode(status, forKey: .status)
        try container.encode(reason, forKey: .reason)
    }
}

/// Card order, highest first: changes, repeated patterns, timing, absences, then combos no
/// longer bound. Each rule gives at most one card and rising never appears with falling, so
/// the order is total: the same input always gives the same cards.
let cardPriority: [InsightKind] = [.rising, .falling, .focus, .burst, .peak, .dormant, .unused, .unbound]
public let maxCards = 5

public struct InsightReport: Sendable {
    public let generated: String
    public let month: String
    /// At most `maxCards`, in `cardPriority` order.
    public let insights: [Insight]
    /// Findings past `maxCards`, in the same order, kept whole for inspection.
    public let held: [Insight]
    /// Every rule, in the order the engine runs them.
    public let rules: [RuleStatus]
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

/// 14301 becomes "14,301", as the panel writes counts.
func grouped(_ number: Int) -> String {
    number.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
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

/// What one rule found: a card, or why there is none.
private enum Outcome {
    case found(Insight)
    case notReady(String)
    case noPattern(String)
}

/// Everything the rules share. Built once by `computeReport`.
private struct Analysis {
    let history: [PressEvent]
    let bindings: [Binding]
    let now: Date
    let today: Date
    let monthStart: Date
    let calendar: Calendar
    let recorded: Set<String>
    let labels: [Combo: String]
    /// Presses before the retention cut; nil when the whole log was read.
    let archive: ArchivedHistory?

    func name(_ combo: Combo) -> String { labels[combo] ?? "Hyper \(combo.shortName)" }
    func key(_ date: Date) -> String { dayKey(date, calendar: calendar) }

    /// The day `offset` days before today.
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }
    func keyDaysAgo(_ offset: Int) -> String { key(day(offset)) }
    /// From the first day of this month through today.
    var monthToDate: (start: String, end: String) { (key(monthStart), key(today)) }
}

/// `events` must be sorted by time, as `parseLog` returns them. With `archive`, `events` are
/// the tail after a retention cut (Retention.swift) and `rejectedLines` counts the tail only.
public func computeReport(
    events: [PressEvent], bindings: [Binding], now: Date, rejectedLines: Int = 0,
    context: [ContextEvent]? = nil, archive: ArchivedHistory? = nil, calendar: Calendar = .current
) -> InsightReport {
    var labels: [Combo: String] = [:]
    for binding in bindings { labels[binding.combo] = binding.label }

    // Presses after `now` are ignored so every rule sees the same history.
    let history = events.filter { $0.date <= now }
    let monthStart = calendar.dateInterval(of: .month, for: now)!.start
    // Claims about absence or change need recorded history to back them up.
    let recordingStart = (history.map(\.date) + [archive?.first].compactMap { $0 }).min()
    let analysis = Analysis(
        history: history, bindings: bindings, now: now, today: calendar.startOfDay(for: now),
        monthStart: monthStart, calendar: calendar,
        recorded: recordedDays(
            events: history, context: context, now: now, calendar: calendar, firstEvent: archive?.first),
        labels: labels, archive: archive)
    let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
    let thisMonth = history.filter { $0.date >= monthStart }

    let dormantOutcome: Outcome
    if let recordingStart,
       recordingStart < calendar.date(byAdding: .day, value: 1, to: previousMonthStart)!
    {
        dormantOutcome = dormant(analysis, monthStart: monthStart, previousMonthStart: previousMonthStart)
    } else {
        let previousName = monthNames[calendar.component(.month, from: previousMonthStart) - 1]
        let began = recordingStart.map {
            "recording began \(shortMonthNames[calendar.component(.month, from: $0) - 1]) "
                + "\(calendar.component(.day, from: $0))"
        }
        dormantOutcome = .notReady(
            "The not-used-yet check needs all of \(previousName) recorded; \(began ?? "nothing is recorded yet").")
    }
    let outcomes: [(rule: String, outcome: Outcome)] = [
        ("focus", focus(analysis, context: context)),
        ("trend", trend(analysis)),
        ("unused", unused(analysis)),
        ("dormant", dormantOutcome),
        ("unbound", unbound(analysis)),
        ("burst", burst(thisMonth, analysis)),
        ("peak", peak(thisMonth, analysis)),
    ]

    var found: [Insight] = []
    for (_, outcome) in outcomes { if case .found(let insight) = outcome { found.append(insight) } }
    let ranked = found.sorted { cardPriority.firstIndex(of: $0.kind)! < cardPriority.firstIndex(of: $1.kind)! }
    let insights = Array(ranked.prefix(maxCards))
    let rules = outcomes.map { rule, outcome in
        switch outcome {
        case .found(let insight):
            insights.contains(insight)
                ? RuleStatus(rule: rule, status: .shown, reason: nil)
                : RuleStatus(
                    rule: rule, status: .held,
                    reason: "\(insight.title). Held back: \(maxCards) cards rank higher.")
        case .notReady(let reason): RuleStatus(rule: rule, status: .notReady, reason: reason)
        case .noPattern(let reason): RuleStatus(rule: rule, status: .noPattern, reason: reason)
        }
    }

    return InsightReport(
        generated: formatTimestamp(now, calendar: calendar),
        month: String(formatTimestamp(now, calendar: calendar).prefix(7)),
        insights: insights,
        held: Array(ranked.dropFirst(maxCards)),
        rules: rules,
        monthTotal: thisMonth.count,
        recordingSince: recordingStart.map { formatTimestamp($0, calendar: calendar) },
        rejectedLines: rejectedLines + (archive?.rejected ?? 0))
}

// MARK: - focus

/// The category with the most presses over the last 7 days, and the app it mostly happens in.
private func focus(_ a: Analysis, context: [ContextEvent]?) -> Outcome {
    var categoryOf: [Combo: String] = [:]
    for binding in a.bindings { if let category = binding.category { categoryOf[binding.combo] = category } }
    guard !categoryOf.isEmpty else { return .notReady("The category summary needs bindings with categories.") }

    let windowDays = Set((0...6).map { a.keyDaysAgo($0) })
    let apps: [String?]? = context.map {
        attributeApps(events: a.history, context: $0, now: a.now, calendar: a.calendar)
    }
    // Presses in the window, with the app each one is attributed to.
    var window: [(day: String, combo: Combo, app: String?)] = []
    for (index, press) in a.history.enumerated() where windowDays.contains(a.key(press.date)) {
        window.append((a.key(press.date), press.combo, apps?[index] ?? nil))
    }
    guard window.count >= 30 else {
        return .notReady("The category summary needs 30 presses in the last 7 days; \(window.count) so far.")
    }

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
    guard let category = top(categoryCounts) else {
        return .noPattern("No press in the last 7 days has a category.")
    }
    let repeatDays = dayTotals.keys.filter {
        dayTotals[$0]! >= 5 && top(dayCategoryCounts[$0] ?? [:]) == category
    }
    guard repeatDays.count >= 3 else {
        return .noPattern(
            "\(categoryName(category)) led on \(repeatDays.count) \(repeatDays.count == 1 ? "day" : "days") "
                + "of 5+ presses; the summary needs 3.")
    }

    let share = Int((Double(categoryCounts[category]!) / Double(window.count) * 100).rounded())
    let span = (a.keyDaysAgo(6), a.key(a.today))
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
            return .found(
                Insight(
                    kind: .focus, title: "\(display) mostly in \(appName(app))",
                    detail: "\(appShare)% of \(grouped(attributed)) attributed presses · \(appDays.count) days",
                    keys: keys, value: share, dates: Array(appDays), app: app, window: span,
                    measure: Measure(count: appCounts[app]!, total: attributed, unit: "presses")))
        }
    }
    return .found(
        Insight(
            kind: .focus, title: "\(display) leads shortcut use",
            detail: "\(share)% of \(grouped(window.count)) presses · top on \(repeatDays.count) days",
            keys: keys, value: share, dates: repeatDays, window: span,
            measure: Measure(count: categoryCounts[category]!, total: window.count, unit: "presses")))
}

// MARK: - rising and falling

/// Compares the 7 whole days before today with the 7 before those. Needs all 14 days
/// recorded, at least 10 presses in the larger week, a change of at least 5 presses, the
/// change repeated on at least 4 of the 7 recent days, and a change of at least 5 still
/// left without the busiest day of the larger week. Ranks by absolute change.
private func trend(_ a: Analysis) -> Outcome {
    let recentDays = (1...7).map { a.keyDaysAgo($0) }
    let previousDays = (8...14).map { a.keyDaysAgo($0) }
    let qualifying = Set(recentDays + previousDays).intersection(a.recorded).count
    guard qualifying == 14 else {
        return .notReady("Week comparisons need 14 recorded days; \(qualifying) qualify.")
    }
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
        // The change must survive dropping the busiest day of the week that carries it,
        // scaled back to 7 days: (rest * 7 / 6) - other >= 5, in whole presses.
        let carrier = change > 0 ? recentDays : previousDays
        let busiest = carrier.map { days[$0, default: 0] }.max()!
        let rest = (change > 0 ? now : was) - busiest
        guard rest * 7 - (change > 0 ? was : now) * 6 >= 30 else { continue }
        if let current = best {
            let currentChange = abs(current.now - current.was)
            if (abs(change), repeats.count) <= (currentChange, current.repeats.count) { continue }
        }
        best = (combo, now, was, repeats)
    }
    guard let best else { return .noPattern("No shortcut changed by 5+ presses on 4+ of the last 7 days.") }
    let change = best.now - best.was
    let rising = change > 0
    return .found(
        Insight(
            kind: rising ? .rising : .falling,
            title: "\(a.name(best.combo)) \(rising ? "up" : "down") \(grouped(abs(change))) presses",
            detail: "\(best.combo.shortName) · \(grouped(best.now)) vs \(grouped(best.was)) the week before · "
                + "\(rising ? "up" : "down") on \(best.repeats.count) days",
            keys: [best.combo], value: abs(change), dates: best.repeats,
            window: (a.keyDaysAgo(7), a.keyDaysAgo(1)), comparison: (a.keyDaysAgo(14), a.keyDaysAgo(8)),
            measure: Measure(count: best.now, baseline: best.was, unit: "presses")))
}

// MARK: - unused

/// The layer with the highest share of unused bindings over the last 30 days. Needs at
/// least 3 fully recorded days in that window, a layer of 4 or more bindings, and 3 or
/// more unused.
private func unused(_ a: Analysis) -> Outcome {
    let windowDays = (1...30).map { a.keyDaysAgo($0) }.filter { a.recorded.contains($0) }
    guard windowDays.count >= 3 else {
        return .notReady("The unused check needs 3 recorded days in the last 30; \(windowDays.count) qualify.")
    }
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
    guard let best else { return .noPattern("No layer of 4+ bindings has 3+ unused in the last 30 days.") }
    let layerName = layerNames[best.layer] ?? "Hyper \(best.layer.uppercased())"
    return .found(
        Insight(
            kind: .unused,
            title: "\(best.unused.count) of \(best.total) \(layerName) shortcuts unused",
            detail: "No presses on \(windowDays.count) recorded days",
            keys: best.unused, value: best.unused.count, dates: windowDays,
            window: (a.key(windowStart), a.key(a.today)),
            measure: Measure(count: best.unused.count, total: best.total, unit: "bindings")))
}

// MARK: - dormant

/// A combo with 3 or more presses on 2 or more days last month and none this month.
private func dormant(_ a: Analysis, monthStart: Date, previousMonthStart: Date) -> Outcome {
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
    let previousName = monthNames[a.calendar.component(.month, from: previousMonthStart) - 1]
    guard let best = totals.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else {
        return .noPattern("Every shortcut pressed 3+ times on 2+ days in \(previousName) has been used this month.")
    }
    let currentShort = shortMonthNames[a.calendar.component(.month, from: monthStart) - 1]
    // "Not used yet" is true at any point in the month; it makes no claim about stopping.
    let previousEnd = a.calendar.date(byAdding: .day, value: -1, to: monthStart)!
    return .found(
        Insight(
            kind: .dormant,
            title: "\(a.name(best.key)) not used yet this month",
            detail: "\(best.key.shortName) · \(grouped(best.value)) presses in \(previousName) · none since \(currentShort) 1",
            keys: [best.key], value: best.value, dates: Array(previous[best.key]!.keys),
            window: a.monthToDate, comparison: (a.key(previousMonthStart), a.key(previousEnd)),
            measure: Measure(count: 0, baseline: best.value, unit: "presses")))
}

// MARK: - unbound

private func unbound(_ a: Analysis) -> Outcome {
    let bound = Set(a.bindings.map(\.combo))
    var counts: [Combo: Int] = [:]
    var days = Set<String>()
    for event in a.history where !bound.contains(event.combo) {
        counts[event.combo, default: 0] += 1
        days.insert(a.key(event.date))
    }
    for (combo, perDay) in a.archive?.comboDays ?? [:] where !bound.contains(combo) {
        counts[combo, default: 0] += perDay.values.reduce(0, +)
        days.formUnion(perDay.keys)
    }
    guard !counts.isEmpty else { return .noPattern("Every logged shortcut is still bound.") }
    let first = ([a.archive?.first].compactMap { $0 } + a.history.prefix(1).map(\.date)).min()!
    let ranked = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
    let presses = counts.values.reduce(0, +)
    return .found(
        Insight(
            kind: .unbound,
            title: "\(counts.count) logged \(counts.count == 1 ? "combo" : "combos") no longer bound",
            detail: "\(grouped(presses)) \(presses == 1 ? "press" : "presses") logged with no current binding",
            keys: ranked.map(\.key), value: counts.count, dates: Array(days),
            window: (a.key(first), a.key(a.today)),
            measure: Measure(count: presses, unit: "presses")))
}

// MARK: - burst

/// A burst is 5 or more presses of one combo in a row, each within 3 s of the last.
/// Reports the combo with the most bursts this month, if it has 2 or more on 2 or more days.
private func burst(_ thisMonth: [PressEvent], _ a: Analysis) -> Outcome {
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
    guard let best = eligible.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else {
        return .noPattern("No shortcut came in bursts (5+ presses, each within 3 s) on 2+ days this month.")
    }
    let dayCount = days[best.key]!.count
    return .found(
        Insight(
            kind: .burst,
            title: "\(a.name(best.key)) repeats in bursts",
            detail: "\(grouped(best.value)) \(best.value == 1 ? "burst" : "bursts") on \(dayCount) days · each 5+ presses in a row",
            keys: [best.key], value: best.value, dates: Array(days[best.key]!), window: a.monthToDate,
            measure: Measure(count: best.value, unit: "bursts")))
}

// MARK: - peak

/// The hour with the most presses this month, if it has presses on 3 or more days.
private func peak(_ thisMonth: [PressEvent], _ a: Analysis) -> Outcome {
    guard thisMonth.count >= 20 else {
        return .notReady("The busiest hour needs 20 presses this month; \(thisMonth.count) so far.")
    }
    var counts = [Int](repeating: 0, count: 24)
    var days = [Set<String>](repeating: [], count: 24)
    for event in thisMonth {
        let hour = a.calendar.component(.hour, from: event.date)
        counts[hour] += 1
        days[hour].insert(a.key(event.date))
    }
    let hour = (0..<24).max(by: { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) })!
    guard days[hour].count >= 3 else {
        let count = days[hour].count
        return .noPattern(
            String(format: "The busiest hour, %02d:00, had presses on ", hour)
                + "\(count) \(count == 1 ? "day" : "days"); it needs 3.")
    }
    let share = Int((Double(counts[hour]) / Double(thisMonth.count) * 100).rounded())
    return .found(
        Insight(
            kind: .peak,
            title: String(format: "Most shortcut use: %02d:00–%02d:00", hour, (hour + 1) % 24),
            detail: "\(share)% of this month's presses · on \(days[hour].count) days",
            keys: [], value: hour, dates: Array(days[hour]), window: a.monthToDate,
            measure: Measure(count: counts[hour], total: thisMonth.count, unit: "presses")))
}
