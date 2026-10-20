import Foundation

public enum InsightKind: String, Codable, Sendable {
    case focus, rising, falling, unused, dormant, unbound, burst, peak, pair, double, undone, uptake
}

/// The number a card rests on, with what it is part of and what it is compared with.
public struct Measure: Codable, Equatable, Sendable {
    public let count: Int
    /// The whole `count` is part of (presses in the window, bindings in the layer); nil when none.
    public let total: Int?
    /// The same count in the comparison period; nil without one.
    public let baseline: Int?
    /// "presses", "bindings", "bursts", "pairs", "doubles" or "days".
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

/// Card order, highest first: changes, repeated patterns, timing, reversals and uptake,
/// absences, then combos no longer bound. Each rule gives at most one card and rising never
/// appears with falling, so the order is total: the same input always gives the same cards.
/// A pair or a double is a repeated pattern that one macro or binding could change, so both
/// rank after bursts.
let cardPriority: [InsightKind] = [
    .rising, .falling, .focus, .burst, .pair, .double, .peak, .undone, .uptake, .dormant, .unused, .unbound,
]
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
        ("pair", pair(analysis)),
        ("double", double(analysis)),
        ("undone", undone(analysis)),
        ("uptake", uptake(analysis)),
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

/// "2026-09-05" becomes "Sep 5".
private func shortDay(_ key: String) -> String {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    return "\(shortMonthNames[parts[1] - 1]) \(parts[2])"
}

/// The layer with the highest share of unused bindings over the last 30 days. Needs at
/// least 14 fully recorded days in that window, a layer of 4 or more bindings, and 3 or
/// more unused. A just-added binding has had no time to be pressed, so a few days of
/// history would call it unused.
private func unused(_ a: Analysis) -> Outcome {
    let windowDays = (1...30).map { a.keyDaysAgo($0) }.filter { a.recorded.contains($0) }
    guard windowDays.count >= 14 else {
        return .notReady("The unused check needs 14 recorded days in the last 30; \(windowDays.count) qualify.")
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

    // The last day each unused binding was pressed, in the archive or the log; none means
    // never pressed since recording began.
    var lastDay: [Combo: String] = [:]
    for (combo, perDay) in a.archive?.comboDays ?? [:] { lastDay[combo] = perDay.keys.max() }
    for press in a.history { lastDay[press.combo] = a.key(press.date) }
    let never = best.unused.filter { lastDay[$0] == nil }
    let lapsed = best.unused.filter { lastDay[$0] != nil }
    var parts: [String] = []
    if !never.isEmpty {
        let first = ([a.archive?.first].compactMap { $0 } + a.history.prefix(1).map(\.date)).min()!
        parts.append("\(never.count) never pressed since \(shortDay(a.key(first)))")
    }
    if let latest = lapsed.compactMap({ lastDay[$0] }).max() {
        parts.append("\(lapsed.count) last pressed \(shortDay(latest))\(lapsed.count > 1 ? " or earlier" : "")")
    }
    parts.append("\(windowDays.count) of 30 days recorded")
    return .found(
        Insight(
            kind: .unused,
            title: "\(best.unused.count) of \(best.total) \(layerName) shortcuts unused in 30 days",
            detail: parts.joined(separator: " · "),
            keys: never + lapsed, value: best.unused.count, dates: windowDays,
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

/// Combos in the log with no binding now. A combo counts only with 3 or more presses on 2
/// or more days, so one stray press does not keep the card alive for as long as the log
/// keeps it.
private func unbound(_ a: Analysis) -> Outcome {
    let bound = Set(a.bindings.map(\.combo))
    var perCombo: [Combo: [String: Int]] = [:]
    for event in a.history where !bound.contains(event.combo) {
        perCombo[event.combo, default: [:]][a.key(event.date), default: 0] += 1
    }
    for (combo, perDay) in a.archive?.comboDays ?? [:] where !bound.contains(combo) {
        perCombo[combo, default: [:]].merge(perDay, uniquingKeysWith: +)
    }
    guard !perCombo.isEmpty else { return .noPattern("Every logged shortcut is still bound.") }
    let counts = perCombo.compactMapValues { days -> Int? in
        let total = days.values.reduce(0, +)
        return total >= 3 && days.count >= 2 ? total : nil
    }
    guard !counts.isEmpty else {
        return .noPattern(
            "\(perCombo.count) logged \(perCombo.count == 1 ? "combo has" : "combos have") no binding, "
                + "none pressed 3+ times on 2+ days.")
    }
    let days = Set(counts.keys.flatMap { perCombo[$0]!.keys })
    let first = ([a.archive?.first].compactMap { $0 } + a.history.prefix(1).map(\.date)).min()!
    let ranked = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
    let presses = counts.values.reduce(0, +)
    return .found(
        Insight(
            kind: .unbound,
            title: "\(counts.count) logged \(counts.count == 1 ? "combo" : "combos") no longer bound",
            detail: "\(grouped(presses)) presses logged with no current binding",
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

// MARK: - pair

/// Categories whose shortcuts come in runs by nature, so a pair there is no habit.
private let runCategories: Set<String> = ["pointer", "text-navigation"]

/// One combo, then a different one as the very next press within 5 s, over today and the 13
/// days before. A pair belongs to the day of its first press. Reports the most frequent pair
/// with 5 or more on 4 or more days, so 3 days remain after dropping its busiest.
private func pair(_ a: Analysis) -> Outcome {
    var categoryOf: [Combo: String] = [:]
    for binding in a.bindings { if let category = binding.category { categoryOf[binding.combo] = category } }
    let windowStart = a.day(13)
    let window = a.history.filter { $0.date >= windowStart }
    var perDay: [[Combo]: [String: Int]] = [:]
    for (first, second) in zip(window, window.dropFirst())
    where first.combo != second.combo && second.date.timeIntervalSince(first.date) <= 5
        && !runCategories.contains(categoryOf[first.combo] ?? "")
        && !runCategories.contains(categoryOf[second.combo] ?? "")
    {
        perDay[[first.combo, second.combo], default: [:]][a.key(first.date), default: 0] += 1
    }
    var best: (combos: [Combo], count: Int, days: [String: Int])?
    for (combos, days) in perDay.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
        let count = days.values.reduce(0, +)
        guard count >= 5, days.count - 1 >= 3 else { continue }
        if let current = best, (count, days.count) <= (current.count, current.days.count) { continue }
        best = (combos, count, days)
    }
    guard let best else {
        return .noPattern(
            "No two shortcuts came one right after the other (within 5 s) 5+ times on 4+ of the last 14 days.")
    }
    let (first, second) = (best.combos[0], best.combos[1])
    return .found(
        Insight(
            kind: .pair,
            title: "\(a.name(first)) then \(a.name(second)): \(grouped(best.count)) times",
            detail: "\(first.shortName) · then \(second.shortName) within 5 s · on \(best.days.count) of the last 14 days",
            keys: best.combos, value: best.count, dates: Array(best.days.keys),
            window: (a.key(windowStart), a.key(a.today)),
            measure: Measure(count: best.count, unit: "pairs")))
}

// MARK: - double

/// Categories where a second press opens or captures the same thing again.
private let doubleCategories: Set<String> = ["app-launch", "site-open", "capture"]

/// Two presses of one combo in a row, the second within 2 s, over today and the 13 days
/// before. Runs chain as in `burst` (each press within 3 s of the last); only a run of
/// exactly 2 counts, so a burst never does. Reports the combo with the most doubles, if it
/// has 5 or more on 3 or more days. It makes no claim about why the second press came.
private func double(_ a: Analysis) -> Outcome {
    var categoryOf: [Combo: String] = [:]
    for binding in a.bindings { if let category = binding.category { categoryOf[binding.combo] = category } }
    guard !categoryOf.isEmpty else { return .notReady("The pressed-twice check needs bindings with categories.") }
    let windowStart = a.day(13)
    var perDay: [Combo: [String: Int]] = [:]
    var run: [PressEvent] = []
    func closeRun() {
        if run.count == 2, run[1].date.timeIntervalSince(run[0].date) <= 2,
           doubleCategories.contains(categoryOf[run[0].combo] ?? "")
        {
            perDay[run[0].combo, default: [:]][a.key(run[0].date), default: 0] += 1
        }
    }
    for event in a.history where event.date >= windowStart {
        if let previous = run.last, previous.combo == event.combo,
           event.date.timeIntervalSince(previous.date) <= 3 {
            run.append(event)
        } else {
            closeRun()
            run = [event]
        }
    }
    closeRun()
    let counts = perDay.compactMapValues { days -> Int? in
        let total = days.values.reduce(0, +)
        return total >= 5 && days.count >= 3 ? total : nil
    }
    guard let best = counts.min(by: { ($1.value, $0.key) < ($0.value, $1.key) }) else {
        return .noPattern(
            "No app, site or capture shortcut was pressed twice within 2 s 5+ times on 3+ of the last 14 days.")
    }
    let days = perDay[best.key]!
    return .found(
        Insight(
            kind: .double,
            title: "\(a.name(best.key)) pressed twice in 2 s: \(grouped(best.value)) times",
            detail: "\(best.key.shortName) · on \(days.count) of the last 14 days",
            keys: [best.key], value: best.value, dates: Array(days.keys),
            window: (a.key(windowStart), a.key(a.today)),
            measure: Measure(count: best.value, unit: "doubles")))
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

// MARK: - undone

/// Bindings in rules.ts whose commands reverse each other. Either order counts. Tab, page and
/// text navigation are left out: going back and forth there is ordinary use.
let oppositePairs: [(Combo, Combo)] = [
    // Maximize, Restore
    (Combo(layer: "w", key: "f"), Combo(layer: "w", key: "delete_or_backspace")),
    // Almost maximize, Restore
    (Combo(layer: "w", key: "return_or_enter"), Combo(layer: "w", key: "delete_or_backspace")),
    // Left half, Right half
    (Combo(layer: "w", key: "h"), Combo(layer: "w", key: "l")),
    // Top half, Bottom half
    (Combo(layer: "w", key: "k"), Combo(layer: "w", key: "j")),
    // Previous display, Next display
    (Combo(layer: "w", key: "y"), Combo(layer: "w", key: "o")),
    // Larger, Smaller
    (Combo(layer: "w", key: "equal_sign"), Combo(layer: "w", key: "hyphen")),
    // Move left, Move right
    (Combo(layer: "w", key: "left_arrow"), Combo(layer: "w", key: "right_arrow")),
    // Move up, Move down
    (Combo(layer: "w", key: "up_arrow"), Combo(layer: "w", key: "down_arrow")),
    // Volume increment, Volume decrement
    (Combo(layer: "s", key: "u"), Combo(layer: "s", key: "j")),
    // Display brightness increment, Display brightness decrement
    (Combo(layer: "s", key: "i"), Combo(layer: "s", key: "k")),
    // Recording Mode, Undo Recording Mode
    (Combo(layer: "s", key: "r"), Combo(layer: "s", key: "t")),
]

/// A press reversed by the very next press, its opposite in `oppositePairs`, within 3 s.
/// Counts today and the 13 days before. Needs 5 reversals of one combo on 4 or more days,
/// so 3 days remain without the busiest one. The most reversed combo wins.
private func undone(_ a: Analysis) -> Outcome {
    // A pair counts only while both of its combos are bound.
    let bound = Set(a.bindings.map(\.combo))
    var opposites: [Combo: Set<Combo>] = [:]
    for (first, second) in oppositePairs where bound.contains(first) && bound.contains(second) {
        opposites[first, default: []].insert(second)
        opposites[second, default: []].insert(first)
    }
    guard !opposites.isEmpty else { return .noPattern("No pair of opposite shortcuts is bound.") }

    let windowStart = a.day(13)
    let window = a.history.filter { $0.date >= windowStart }
    // Per reversed combo and the combo that reversed it, reversals per day.
    var reversals: [[Combo]: [String: Int]] = [:]
    var index = 0
    while index + 1 < window.count {
        let press = window[index]
        let next = window[index + 1]
        if opposites[press.combo]?.contains(next.combo) == true, next.date.timeIntervalSince(press.date) <= 3 {
            reversals[[press.combo, next.combo], default: [:]][a.key(press.date), default: 0] += 1
            // The undoing press is used up: it does not start a reversal of its own.
            index += 2
        } else {
            index += 1
        }
    }

    var top: (pair: [Combo], count: Int, days: Int)?
    var best: (pair: [Combo], count: Int, days: Int)?
    for pair in reversals.keys.sorted(by: { ($0[0], $0[1]) < ($1[0], $1[1]) }) {
        let days = reversals[pair]!
        let candidate = (pair: pair, count: days.values.reduce(0, +), days: days.count)
        if top.map({ (candidate.count, candidate.days) > ($0.count, $0.days) }) ?? true { top = candidate }
        guard candidate.count >= 5, candidate.days >= 4 else { continue }
        if best.map({ candidate.count > $0.count }) ?? true { best = candidate }
    }
    guard let best else {
        guard let top else {
            return .noPattern("No shortcut was undone by its opposite within 3 s in the last 14 days.")
        }
        return .noPattern(
            "\(a.name(top.pair[0])) was undone \(top.count) \(top.count == 1 ? "time" : "times") "
                + "on \(top.days) \(top.days == 1 ? "day" : "days") in the last 14; "
                + "the card needs 5 times on 4+ days.")
    }
    let (combo, inverse) = (best.pair[0], best.pair[1])
    let pressed = window.filter { $0.combo == combo }.count
    return .found(
        Insight(
            kind: .undone,
            title: "\(a.name(combo)) undone \(grouped(best.count)) times",
            detail: "\(combo.shortName) · then \(a.name(inverse)) within 3 s · on \(best.days) of the last 14 days",
            keys: [combo, inverse], value: best.count, dates: Array(reversals[best.pair]!.keys),
            window: (a.key(windowStart), a.key(a.today)),
            measure: Measure(count: best.count, total: pressed, unit: "presses")))
}

// MARK: - uptake

/// A shortcut first used in the last 21 days, and how many recorded days since have a press.
/// The engine does not know when a binding was added, so the first press in the history
/// stands in, and the log must have run 7 days before it. Counts recorded days from the
/// first use through yesterday and needs 7. Reports only weak uptake: presses on fewer than
/// half of those days, or on none of the last 3. The combo with the most days without a
/// press wins.
private func uptake(_ a: Analysis) -> Outcome {
    func shortDate(_ date: Date) -> String {
        "\(shortMonthNames[a.calendar.component(.month, from: date) - 1]) \(a.calendar.component(.day, from: date))"
    }
    guard let start = ([a.archive?.first].compactMap { $0 } + a.history.prefix(1).map(\.date)).min() else {
        return .notReady("The uptake check needs a log; nothing is recorded yet.")
    }
    // 7 days of log before a first use, and 7 recorded days after it.
    let startDay = a.calendar.startOfDay(for: start)
    guard startDay <= a.day(14) else {
        return .notReady(
            "The uptake check needs 14 days of log, 7 before a first use and 7 after; "
                + "recording began \(shortDate(start)).")
    }
    let earliest = max(a.day(21), a.calendar.date(byAdding: .day, value: 7, to: startDay)!)

    var first: [Combo: Date] = [:]
    var last: [Combo: Date] = [:]
    var pressDays: [Combo: Set<String>] = [:]
    for press in a.history {
        if first[press.combo] == nil { first[press.combo] = press.date }
        last[press.combo] = press.date
        pressDays[press.combo, default: []].insert(a.key(press.date))
    }
    // A combo in the archive was first used before the retention cut, so it is not new.
    let archived = Set((a.archive?.comboDays ?? [:]).keys)

    var longest: (combo: Combo, days: Int)?
    var weakest: (combo: Combo, days: [String], used: Int, recent: Int)?
    var best: (combo: Combo, days: [String], used: Int)?
    for combo in Set(a.bindings.map(\.combo)).sorted() {
        guard !archived.contains(combo), let date = first[combo] else { continue }
        let firstDay = a.calendar.startOfDay(for: date)
        guard firstDay >= earliest else { continue }
        let offset = a.calendar.dateComponents([.day], from: firstDay, to: a.today).day!
        let days = stride(from: offset, through: 1, by: -1).map { a.keyDaysAgo($0) }.filter { a.recorded.contains($0) }
        if longest.map({ days.count > $0.days }) ?? true { longest = (combo, days.count) }
        guard days.count >= 7 else { continue }
        let used = days.filter { pressDays[combo]!.contains($0) }.count
        let recent = days.suffix(3).filter { pressDays[combo]!.contains($0) }.count
        if weakest.map({ days.count - used > $0.days.count - $0.used }) ?? true {
            weakest = (combo, days, used, recent)
        }
        // Uptake is weak when fewer than half the days have a press, or none of the last 3.
        guard used * 2 < days.count || recent == 0 else { continue }
        if best.map({ days.count - used > $0.days.count - $0.used }) ?? true { best = (combo, days, used) }
    }
    guard let best else {
        if let weakest {
            return .noPattern(
                "\(a.name(weakest.combo)) was used on \(weakest.used) of \(weakest.days.count) days since its "
                    + "first use, \(weakest.recent) of the last 3; the card needs fewer than half, or none in the last 3.")
        }
        guard let longest else {
            return .noPattern("No shortcut was first used in the last 21 days, 7+ days after recording began.")
        }
        return .notReady(
            "The uptake check needs 7 recorded days since a first use; \(a.name(longest.combo)) has \(longest.days).")
    }
    let combo = best.combo
    return .found(
        Insight(
            kind: .uptake,
            title: "\(a.name(combo)) used on \(best.used) of \(best.days.count) days",
            detail: "\(combo.shortName) · first used \(shortDate(first[combo]!)) · last used \(shortDate(last[combo]!))",
            keys: [combo], value: best.used, dates: Array(pressDays[combo]!),
            window: (a.key(first[combo]!), a.key(a.today)),
            measure: Measure(count: best.used, total: best.days.count, unit: "days")))
}
