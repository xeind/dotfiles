// RETENTION (hyperdash/docs/RETENTION.md; manifest version 2, version 1 still read)
//
// The logs are never moved, truncated or rewritten. A manifest names a cut offset in each
// log: bytes [0, offset) are the archive, bytes from the offset on are the tail. Readers
// parse only the tail and take the archive from the manifest's summary.
//
// The file is three lines of JSON: the header (version, created, tailStart and the cuts), the
// summary, and the day index. The host decodes only the header; the summary goes to the panel
// as it is, and the host looks one day up in the index without decoding it. Version 1 had no
// index line.
//
// A cut is used only when the file still has the (dev, ino) it was made in, holds at least
// `offset` bytes, and ends the line `lastLine` exactly at `offset`. Otherwise, and for a
// manifest of another version, readers read the whole log.
//
// THE TAIL START. The usage cut is the start of the first valid line, in file order, dated at
// or after the tail start (see `retentionTailStart`); every valid line before it is dated
// earlier. The context cut is the last `start` line dated before the tail start that is later
// than every valid line before it. From the tail start on, sessions and attribution are the
// same as with the whole context log.

import Foundation

public let retentionVersion = 2

/// A cut in one log, and the file it was made in.
public struct LogCut: Codable, Equatable, Sendable {
    public let dev: Int64
    public let ino: UInt64
    /// Bytes [0, offset) are archived. The offset is the start of a line.
    public let offset: Int
    /// The line that ends at `offset`, without its "\n".
    public let lastLine: String
}

/// Everything the panel and the rules need from the bytes before the usage cut.
public struct UsageArchive: Codable, Equatable, Sendable {
    /// The manifest's tail start, for the panel.
    public let tailStart: String
    /// Valid lines before the cut.
    public let count: Int
    /// Non-empty lines before the cut that failed validation.
    public let rejected: Int
    public let firstEvent: String?
    public let lastEvent: String?
    /// "layer key" to its latest timestamp.
    public let lastUsed: [String: String]
    /// "YYYY-MM-DD" to "layer key" to [bin, count, bin, count, ...], bins ascending.
    /// A bin is a half hour of the day, 0 to 47.
    public let days: [String: [String: [Int]]]
}

/// For each day from the first archived day to the day before the tail start, the bytes a
/// reader needs to rebuild that day as the whole logs show it: "YYYY-MM-DD" to
/// [usageFrom, usageTo, contextFrom, contextTo]. Offsets are absolute and start or end lines.
///
/// Usage: from the first to the end of the last archived line dated that day, in file order;
/// 0, 0 for a day with none. Lines of other days inside the span are skipped by the reader.
///
/// Context, in time order: from the last `start` before the day (or the first line), which
/// sets the app and the session at 00:00, to the first line after the day and any line in
/// the same millisecond, which settles whether the day's last session runs past midnight.
/// The span covers each of those lines wherever it sits in the file. contextTo is -1 when no
/// line follows the day yet: the reader reads to the end of the file. 0, 0 without a context log.
public struct DayIndex: Codable, Equatable, Sendable {
    public let days: [String: [Int]]
}

public struct RetentionManifest: Equatable, Sendable {
    public let version: Int
    public let created: String
    /// "YYYY-MM-01T00:00:00": every archived press is dated before it.
    public let tailStart: String
    public let usage: LogCut
    /// Nil when the context log was not given, or has no usable cut.
    public let context: LogCut?
    /// The second line of the file.
    public let archive: UsageArchive
    /// The third line; nil in a version 1 manifest.
    public let index: DayIndex?

    private struct Header: Codable {
        let version: Int
        let created: String
        let tailStart: String
        let usage: LogCut
        let context: LogCut?
    }

    public init(
        version: Int, created: String, tailStart: String, usage: LogCut, context: LogCut?, archive: UsageArchive,
        index: DayIndex?
    ) {
        self.version = version
        self.created = created
        self.tailStart = tailStart
        self.usage = usage
        self.context = context
        self.archive = archive
        self.index = index
    }

    /// Reads the lines of version 1 (header, summary) or version 2 (header, summary, index);
    /// throws when one is not what its version writes.
    public init(fileData data: Data) throws {
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count >= 2 else { throw RetentionError(description: "retention manifest has one line") }
        let header = try JSONDecoder().decode(Header.self, from: lines[0])
        guard lines.count == (header.version >= 2 ? 3 : 2) else {
            throw RetentionError(description: "retention manifest has \(lines.count) lines")
        }
        self.init(
            version: header.version, created: header.created, tailStart: header.tailStart,
            usage: header.usage, context: header.context,
            archive: try JSONDecoder().decode(UsageArchive.self, from: lines[1]),
            index: header.version >= 2 ? try JSONDecoder().decode(DayIndex.self, from: lines[2]) : nil)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let header = Header(version: version, created: created, tailStart: tailStart, usage: usage, context: context)
        var data = try encoder.encode(header) + Data("\n".utf8) + encoder.encode(archive) + Data("\n".utf8)
        if let index { data += try encoder.encode(index) + Data("\n".utf8) }
        return data
    }
}

/// The first day of the month that holds the day 31 days before today. It is never later
/// than the first day of last month nor than 30 days before today, so the current and the
/// previous month and every rule window stay in the tail.
public func retentionTailStart(now: Date, calendar: Calendar) -> Date {
    let day = calendar.date(byAdding: .day, value: -31, to: calendar.startOfDay(for: now))!
    return calendar.dateInterval(of: .month, for: day)!.start
}

public struct RetentionError: Error, CustomStringConvertible {
    public let description: String
}

/// The bytes of a file and the identity of the file they came from.
struct LogFile {
    let bytes: [UInt8]
    let dev: Int64
    let ino: UInt64
}

/// Reads `path` through one descriptor, so the identity belongs to the bytes.
func readLogFile(_ path: String, from offset: Int = 0) throws -> LogFile {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { throw RetentionError(description: "cannot open \(path)") }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw RetentionError(description: "cannot stat \(path)") }
    let size = Int(info.st_size)
    var bytes = [UInt8](repeating: 0, count: max(size - offset, 0))
    let total = bytes.count
    var done = 0
    while done < total {
        let got = bytes.withUnsafeMutableBytes {
            pread(fd, $0.baseAddress! + done, total - done, off_t(offset + done))
        }
        guard got > 0 else { throw RetentionError(description: "short read in \(path)") }
        done += got
    }
    return LogFile(bytes: bytes, dev: Int64(info.st_dev), ino: UInt64(info.st_ino))
}

/// Complete lines: `start` to `end` without the "\n" and one "\r" before it; `next` follows the "\n".
func completeLines(_ bytes: [UInt8]) -> [(start: Int, end: Int, next: Int)] {
    var lines: [(start: Int, end: Int, next: Int)] = []
    var start = 0
    for index in bytes.indices where bytes[index] == 10 {
        var end = index
        if end > start, bytes[end - 1] == 13 { end -= 1 }
        lines.append((start, end, index + 1))
        start = index + 1
    }
    return lines
}

private func text(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Substring {
    Substring(String(decoding: bytes[start..<end], as: UTF8.self))
}

private func lastLine(_ bytes: [UInt8], endingAt offset: Int) -> String {
    var start = offset - 1
    while start > 0, bytes[start - 1] != 10 { start -= 1 }
    return String(decoding: bytes[start..<(offset - 1)], as: UTF8.self)
}

/// Builds the manifest for the logs as they are now, or nil when nothing is old enough to
/// archive. Throws when a log cannot be read or is not UTF-8, as the full reader would fail.
public func compactLogs(
    logPath: String, contextPath: String?, now: Date, calendar: Calendar = .current
) throws -> RetentionManifest? {
    let log = try readLogFile(logPath)
    guard String(validating: log.bytes, as: UTF8.self) != nil else {
        throw RetentionError(description: "\(logPath) is not UTF-8")
    }
    let tailStart = retentionTailStart(now: now, calendar: calendar)
    let lines = completeLines(log.bytes)

    var offset = lines.last?.next ?? 0
    for line in lines where line.end > line.start {
        if let event = parseLogLine(text(log.bytes, line.start, line.end), calendar: calendar),
           event.date >= tailStart
        {
            offset = line.start
            break
        }
    }
    guard offset > 0 else { return nil }

    var count = 0
    var rejected = 0
    var firstEvent: String?
    var lastEvent: String?
    var lastUsed: [String: String] = [:]
    var bins: [String: [String: [Int: Int]]] = [:]
    var usageSpans: [String: (from: Int, to: Int)] = [:]
    for line in lines where line.next <= offset && line.end > line.start {
        let lineText = text(log.bytes, line.start, line.end)
        guard let event = parseLogLine(lineText, calendar: calendar) else {
            rejected += 1
            continue
        }
        // Valid timestamps sort as strings, as the panel compares them.
        let time = String(lineText.prefix(19))
        let id = "\(event.combo.layer) \(event.combo.key)"
        let hour = Int(time.dropFirst(11).prefix(2))!
        let minute = Int(time.dropFirst(14).prefix(2))!
        bins[String(time.prefix(10)), default: [:]][id, default: [:]][hour * 2 + (minute >= 30 ? 1 : 0), default: 0] += 1
        let span = usageSpans[String(time.prefix(10))]
        usageSpans[String(time.prefix(10))] = (span?.from ?? line.start, line.next)
        if lastUsed[id].map({ time > $0 }) ?? true { lastUsed[id] = time }
        if firstEvent.map({ time < $0 }) ?? true { firstEvent = time }
        if lastEvent.map({ time > $0 }) ?? true { lastEvent = time }
        count += 1
    }
    let days = bins.mapValues { combos in
        combos.mapValues { counts in counts.keys.sorted().flatMap { [$0, counts[$0]!] } }
    }

    var contextCut: LogCut?
    var contextLines: [ContextLine]?
    if let contextPath {
        let context = try readLogFile(contextPath)
        guard String(validating: context.bytes, as: UTF8.self) != nil else {
            throw RetentionError(description: "\(contextPath) is not UTF-8")
        }
        var latest: Date?
        var cut = 0
        var valid: [ContextLine] = []
        for line in completeLines(context.bytes) where line.end > line.start {
            let lineText = text(context.bytes, line.start, line.end)
            if let event = parseContextLine(lineText, calendar: calendar) {
                valid.append(ContextLine(time: String(lineText.prefix(23)), start: event.kind == .start, from: line.start, to: line.next))
            }
        }
        contextLines = valid
        for line in completeLines(context.bytes) where line.end > line.start {
            guard let event = parseContextLine(text(context.bytes, line.start, line.end), calendar: calendar)
            else { continue }
            if event.date >= tailStart { break }
            if event.kind == .start, line.start > 0, latest.map({ $0 < event.date }) ?? true {
                cut = line.start
            }
            if latest.map({ event.date > $0 }) ?? true { latest = event.date }
        }
        if cut > 0 {
            contextCut = LogCut(
                dev: context.dev, ino: context.ino, offset: cut,
                lastLine: lastLine(context.bytes, endingAt: cut))
        }
    }

    let start = formatTimestamp(tailStart, calendar: calendar)
    return RetentionManifest(
        version: retentionVersion,
        created: formatTimestamp(now, calendar: calendar),
        tailStart: start,
        usage: LogCut(dev: log.dev, ino: log.ino, offset: offset, lastLine: lastLine(log.bytes, endingAt: offset)),
        context: contextCut,
        archive: UsageArchive(
            tailStart: start, count: count, rejected: rejected, firstEvent: firstEvent, lastEvent: lastEvent,
            lastUsed: lastUsed, days: days),
        index: dayIndex(
            first: days.keys.min(), tailStart: String(start.prefix(10)), usage: usageSpans, context: contextLines))
}

/// A valid context line: its timestamp text, whether it is a `start`, and its bytes.
struct ContextLine {
    let time: String
    let start: Bool
    let from: Int
    let to: Int
}

/// The day after "YYYY-MM-DD", on the proleptic Gregorian calendar.
func nextDay(_ date: String) -> String {
    let parts = date.split(separator: "-").map { Int($0)! }
    var (year, month, day) = (parts[0], parts[1], parts[2] + 1)
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let length = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    if day > length { (month, day) = (month + 1, 1) }
    if month > 12 { (year, month) = (year + 1, 1) }
    return String(format: "%04d-%02d-%02d", year, month, day)
}

/// The day index (see DayIndex) for every day from `first` to the day before `tailStart`.
/// `context` is nil without a context log. Context lines are taken in time order, as the
/// panel sorts them: by timestamp text, then file order.
func dayIndex(
    first: String?, tailStart: String, usage: [String: (from: Int, to: Int)], context: [ContextLine]?
) -> DayIndex {
    let sorted = (context ?? []).enumerated()
        .sorted { $0.element.time != $1.element.time ? $0.element.time < $1.element.time : $0.offset < $1.offset }
        .map(\.element)
    // The first index whose time is not below (or, with `after`, is above) `time`.
    func bound(_ time: String, after: Bool) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if after ? sorted[mid].time <= time : sorted[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
    var lastStart: [Int] = []
    for (index, line) in sorted.enumerated() { lastStart.append(line.start ? index : (lastStart.last ?? -1)) }

    var days: [String: [Int]] = [:]
    var date = first ?? tailStart
    while date < tailStart {
        let span = usage[date] ?? (0, 0)
        var entry = [span.from, span.to, 0, 0]
        if context != nil, !sorted.isEmpty {
            let dayStart = bound("\(date)T00:00:00.000", after: false)
            let lower = dayStart > 0 ? max(lastStart[dayStart - 1], 0) : 0
            let following = bound("\(nextDay(date))T00:00:00.000", after: true)
            let upper = following < sorted.count ? bound(sorted[following].time, after: true) : sorted.count
            let lines = sorted[lower..<upper]
            entry[2] = lines.map(\.from).min()!
            entry[3] = following < sorted.count ? lines.map(\.to).max()! : -1
        }
        days[date] = entry
        date = nextDay(date)
    }
    return DayIndex(days: days)
}

/// Reads a manifest of version 1 or 2. Nil when it is missing, unreadable, of another version, or dated after
/// `now` (a clock set back past the tail start: the whole log is then the safe reading).
public func readManifest(_ path: String, now: Date, calendar: Calendar = .current) -> RetentionManifest? {
    guard let data = FileManager.default.contents(atPath: path),
          let manifest = try? RetentionManifest(fileData: data),
          (1...retentionVersion).contains(manifest.version),
          let tailStart = parseTimestamp(manifest.tailStart, calendar: calendar), tailStart <= now
    else { return nil }
    return manifest
}

/// The log as text from `cut` when the cut belongs to this file, else the whole log.
/// Returns the text and the offset it starts at.
public func readLog(_ path: String, cut: LogCut?) throws -> (text: String, offset: Int) {
    let expected = cut.map { Array($0.lastLine.utf8) + [10] } ?? []
    if let cut, cut.offset >= expected.count {
        // The archived line and the byte before it, which must end the line before.
        let lineStart = cut.offset - expected.count
        let from = max(lineStart - 1, 0)
        let file = try readLogFile(path, from: from)
        let local = cut.offset - from
        if file.dev == cut.dev, file.ino == cut.ino, file.bytes.count >= local,
           Array(file.bytes[(local - expected.count)..<local]) == expected,
           lineStart == 0 || file.bytes[0] == 10
        {
            let tail = Array(file.bytes[local...])
            guard let text = String(validating: tail, as: UTF8.self) else {
                throw RetentionError(description: "\(path) is not UTF-8")
            }
            return (text, cut.offset)
        }
    }
    let file = try readLogFile(path)
    guard let text = String(validating: file.bytes, as: UTF8.self) else {
        throw RetentionError(description: "\(path) is not UTF-8")
    }
    return (text, 0)
}

/// The usage log as the insights run reads it: from the manifest's cut when it applies,
/// with the archive summary; otherwise whole, with no archive.
public func readUsage(
    _ path: String, manifest: RetentionManifest?, calendar: Calendar = .current
) throws -> (log: ParsedLog, archive: ArchivedHistory?) {
    let read = try readLog(path, cut: manifest?.usage)
    let archive = read.offset > 0 ? manifest.map { ArchivedHistory($0.archive, calendar: calendar) } : nil
    return (parseLog(read.text, calendar: calendar), archive)
}

/// The context log from the manifest's cut, but only alongside the usage cut it was made
/// with (`archived`): the tail then covers every press read raw.
public func readContext(
    _ path: String, manifest: RetentionManifest?, archived: Bool, calendar: Calendar = .current
) throws -> ParsedContext {
    parseContextLog(try readLog(path, cut: archived ? manifest?.context : nil).text, calendar: calendar)
}

/// What the rules need from the archive: the first press, the rejected lines, and presses
/// per combo per day (for unbound).
public struct ArchivedHistory: Sendable {
    public let first: Date?
    public let rejected: Int
    public let comboDays: [Combo: [String: Int]]

    public init(first: Date?, rejected: Int, comboDays: [Combo: [String: Int]]) {
        self.first = first
        self.rejected = rejected
        self.comboDays = comboDays
    }

    public init(_ usage: UsageArchive, calendar: Calendar) {
        var comboDays: [Combo: [String: Int]] = [:]
        for (day, combos) in usage.days {
            for (id, bins) in combos {
                let parts = id.split(separator: " ")
                let combo = Combo(layer: String(parts[0]), key: String(parts[1]))
                comboDays[combo, default: [:]][day, default: 0] += stride(from: 1, to: bins.count, by: 2)
                    .reduce(0) { $0 + bins[$1] }
            }
        }
        self.init(
            first: usage.firstEvent.flatMap { parseTimestamp($0, calendar: calendar) },
            rejected: usage.rejected, comboDays: comboDays)
    }
}

/// Writes `data` beside `path` under a temporary name, flushes it to disk, then renames it
/// over `path`. An interrupted run leaves the old manifest and at most a temporary file,
/// which the next run removes.
public func writeDurably(_ data: Data, to path: String) throws {
    let target = URL(fileURLWithPath: path)
    let directory = target.deletingLastPathComponent()
    let prefix = ".\(target.lastPathComponent)."
    for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    where name.hasPrefix(prefix) && name.hasSuffix(".tmp") {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
    let temporary = directory.appendingPathComponent("\(prefix)\(UUID().uuidString).tmp")
    do {
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw RetentionError(description: "cannot create \(temporary.path)")
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard rename(temporary.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    } catch {
        try? FileManager.default.removeItem(at: temporary)
        throw error
    }
}
