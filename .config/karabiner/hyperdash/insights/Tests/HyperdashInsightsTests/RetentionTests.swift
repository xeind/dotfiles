import Foundation
import Testing

@testable import HyperdashInsights

// Retention (Retention.swift): the manifest the tool writes for the shared fixture in
// hyperdash/tests/retention_cases, and the report read through it against the whole log.

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date { parseTimestamp(text, calendar: calendar)! }

private let now = date("2026-10-17T18:00:00")

private let cases = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("../tests/retention_cases").standardized

/// A fresh folder holding copies of the fixture logs.
private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hyperdash-retention-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["usage.log", "context.log", "bindings.json"] {
        try FileManager.default.copyItem(
            at: cases.appendingPathComponent(name), to: folder.appendingPathComponent(name))
    }
    return folder
}

private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
}

/// The report JSON as the insights run makes it, with or without a manifest.
private func reportJSON(_ folder: URL, manifest: RetentionManifest?) throws -> Data {
    let usage = try readUsage(folder.appendingPathComponent("usage.log").path, manifest: manifest, calendar: calendar)
    let context = try readContext(
        folder.appendingPathComponent("context.log").path, manifest: manifest,
        archived: usage.archive != nil, calendar: calendar)
    let bindings = try parseBindings(Data(contentsOf: folder.appendingPathComponent("bindings.json")))
    let report = computeReport(
        events: usage.log.events, bindings: bindings, now: now, rejectedLines: usage.log.rejectedLines,
        context: context.events, archive: usage.archive, calendar: calendar)
    return try InsightsFile(report: report).jsonData()
}

private func compact(_ folder: URL, at time: Date = now) throws -> RetentionManifest? {
    try compactLogs(
        logPath: folder.appendingPathComponent("usage.log").path,
        contextPath: folder.appendingPathComponent("context.log").path, now: time, calendar: calendar)
}

/// The manifest with the file identity cleared, as the committed fixture stores it.
private func anonymous(_ m: RetentionManifest) -> RetentionManifest {
    let clear = { (cut: LogCut) in LogCut(dev: 0, ino: 0, offset: cut.offset, lastLine: cut.lastLine) }
    return RetentionManifest(
        version: m.version, created: m.created, tailStart: m.tailStart, usage: clear(m.usage),
        context: m.context.map(clear), archive: m.archive, index: m.index)
}

@Suite struct RetentionTests {
    @Test func tailStartKeepsLastMonthAndThirtyDays() {
        let expected = [
            ("2026-10-17T18:00:00", "2026-09-01T00:00:00"), ("2026-03-01T00:00:00", "2026-01-01T00:00:00"),
            ("2026-03-31T23:59:59", "2026-02-01T00:00:00"), ("2026-01-15T12:00:00", "2025-12-01T00:00:00"),
            ("2026-11-01T00:00:00", "2026-10-01T00:00:00"),
        ]
        for (time, start) in expected {
            let tail = retentionTailStart(now: date(time), calendar: calendar)
            #expect(formatTimestamp(tail, calendar: calendar) == start, "\(time)")
            let today = calendar.startOfDay(for: date(time))
            #expect(tail <= calendar.date(byAdding: .day, value: -30, to: today)!)
            #expect(tail <= calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: today)!.start)!)
        }
    }

    @Test func fixtureManifestMatchesTheCommittedOne() throws {
        let folder = try scratch()
        let made = try #require(try compact(folder))
        let committed = try RetentionManifest(
            fileData: Data(contentsOf: cases.appendingPathComponent("retention.json")))
        #expect(anonymous(made) == committed)
    }

    @Test func reportThroughTheManifestEqualsTheWholeLog() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let full = try reportJSON(folder, manifest: nil)
        let cut = try reportJSON(folder, manifest: manifest)
        #expect(String(decoding: cut, as: UTF8.self) == String(decoding: full, as: UTF8.self))
        // The fixture makes every rule find something, so the equality covers each of them.
        let decoded = try JSONSerialization.jsonObject(with: full) as! [String: Any]
        let statuses = (decoded["rules"] as! [[String: Any]]).map { $0["status"] as! String }
        #expect(statuses.allSatisfy { $0 == "shown" || $0 == "held" }, "\(statuses)")
    }

    @Test func theCutReallyShortensTheRead() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let path = folder.appendingPathComponent("usage.log").path
        let read = try readLog(path, cut: manifest.usage)
        #expect(read.offset == manifest.usage.offset && read.offset > 0)
        #expect(manifest.context != nil)
        #expect(manifest.archive.count > 0 && manifest.archive.rejected == 1)
    }

    @Test func appendedLinesAfterTheCutStillCount() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let log = try FileHandle(forWritingTo: folder.appendingPathComponent("usage.log"))
        try log.seekToEnd()
        try log.write(contentsOf: Data("00\tw\tu\n2026-10-17T17:59:30\to\tt\n".utf8))
        try log.close()
        #expect(try reportJSON(folder, manifest: manifest) == reportJSON(folder, manifest: nil))
    }

    @Test func aCutThatNoLongerFitsReadsTheWholeLog() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let url = folder.appendingPathComponent("usage.log")
        let original = try Data(contentsOf: url)

        // Rewritten in place, same inode and size: the archived line changed.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(manifest.usage.offset - 3))
        try handle.write(contentsOf: Data("x".utf8))
        try handle.close()
        #expect(try readLog(url.path, cut: manifest.usage).offset == 0)

        // Replaced by a copy: same bytes, another inode.
        try FileManager.default.removeItem(at: url)
        try original.write(to: url)
        #expect(try readLog(url.path, cut: manifest.usage).offset == 0)
        #expect(try reportJSON(folder, manifest: manifest) == reportJSON(folder, manifest: nil))

        // Truncated below the cut.
        let fresh = try #require(try compact(folder))
        let truncate = try FileHandle(forWritingTo: url)
        try truncate.truncate(atOffset: UInt64(fresh.usage.offset - 1))
        try truncate.close()
        #expect(try readLog(url.path, cut: fresh.usage).offset == 0)
    }

    @Test func manifestOfAnotherVersionOrFromTheFutureIsIgnored() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let path = folder.appendingPathComponent("retention.json").path
        try writeDurably(manifest.jsonData(), to: path)
        #expect(readManifest(path, now: now, calendar: calendar) == manifest)
        #expect(readManifest(path, now: date("2026-08-31T23:59:59"), calendar: calendar) == nil)
        let text = String(decoding: try manifest.jsonData(), as: UTF8.self)
            .replacingOccurrences(of: "\"version\":2", with: "\"version\":3")
        try write(text, to: URL(fileURLWithPath: path))
        #expect(readManifest(path, now: now, calendar: calendar) == nil)
        // Version 1 had no index line and is still read; version 2 needs its index line.
        let lines = String(decoding: try manifest.jsonData(), as: UTF8.self).split(separator: "\n")
        try write(lines[0].replacingOccurrences(of: "\"version\":2", with: "\"version\":1") + "\n" + lines[1] + "\n", to: URL(fileURLWithPath: path))
        let old = try #require(readManifest(path, now: now, calendar: calendar))
        #expect(old.version == 1 && old.index == nil && old.archive == manifest.archive)
        try write(lines[0] + "\n" + lines[1] + "\n", to: URL(fileURLWithPath: path))
        #expect(readManifest(path, now: now, calendar: calendar) == nil)
        try write("{\"version\":1,", to: URL(fileURLWithPath: path))
        #expect(readManifest(path, now: now, calendar: calendar) == nil)
        #expect(readManifest(folder.appendingPathComponent("missing.json").path, now: now) == nil)
    }

    @Test func nothingOldEnoughGivesNoManifest() throws {
        let folder = try scratch()
        try write("2026-09-02T10:00:00\tw\tu\n", to: folder.appendingPathComponent("usage.log"))
        #expect(try compact(folder) == nil)
        try write("", to: folder.appendingPathComponent("usage.log"))
        #expect(try compact(folder) == nil)
    }

    @Test func everyArchivedLineIsDatedBeforeTheTailStart() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let bytes = try Data(contentsOf: folder.appendingPathComponent("usage.log"))
        let head = String(decoding: bytes.prefix(manifest.usage.offset), as: UTF8.self)
        let parsed = parseLog(head, calendar: calendar)
        let tailStart = date(manifest.tailStart)
        #expect(parsed.events.allSatisfy { $0.date < tailStart })
        #expect(parsed.events.count == manifest.archive.count && parsed.rejectedLines == manifest.archive.rejected)
        // The September line among the August ones stops the cut, so later August lines stay raw.
        let tail = parseLog(String(decoding: bytes.dropFirst(manifest.usage.offset), as: UTF8.self), calendar: calendar)
        #expect(tail.events.contains { $0.date < tailStart })
    }

    @Test func contextCutNeedsAStartLaterThanEverythingBefore() throws {
        let folder = try scratch()
        try write(
            "2026-08-01T08:00:00.000\tstart\t-\n2026-08-20T09:00:00.000\tapp\tcom.a\n"
                + "2026-08-10T08:00:00.000\tstart\t-\n2026-09-02T08:00:00.000\tstart\t-\n",
            to: folder.appendingPathComponent("context.log"))
        // The second start is earlier than the app line before it: no usable cut.
        #expect(try compact(folder)?.context == nil)
        try write(
            "2026-08-01T08:00:00.000\tstart\t-\n2026-08-20T09:00:00.000\tapp\tcom.a\n"
                + "2026-08-21T08:00:00.000\tstart\t-\n2026-09-02T08:00:00.000\tstart\t-\n",
            to: folder.appendingPathComponent("context.log"))
        let cut = try #require(try compact(folder)?.context)
        #expect(cut.lastLine == "2026-08-20T09:00:00.000\tapp\tcom.a")
    }

    @Test func theDayIndexSpansEveryArchivedLineOfEachDay() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let days = try #require(manifest.index).days
        // Every day from the first archived day to the day before the tail start, gaps included.
        var expected: [String] = []
        var day = "2026-07-20"
        while day < "2026-09-01" { expected.append(day); day = nextDay(day) }
        #expect(days.keys.sorted() == expected)
        let bytes = [UInt8](try Data(contentsOf: folder.appendingPathComponent("usage.log")))
        for (date, entry) in days {
            var archived = 0
            for pairs in manifest.archive.days[date]?.values ?? [:].values {
                for i in stride(from: 1, to: pairs.count, by: 2) { archived += pairs[i] }
            }
            // The span holds every archived line of the day: as many as the summary counts.
            let span = String(decoding: bytes[entry[0]..<entry[1]], as: UTF8.self)
            let lines = parseLog(span, calendar: calendar).events.filter { formatTimestamp($0.date, calendar: calendar).hasPrefix(date) }
            #expect(entry[1] <= manifest.usage.offset && lines.count == archived, "\(date)")
            #expect(entry[0] == 0 || bytes[entry[0] - 1] == 10, "\(date)")
        }
        // The first day, the day at the cut, a day with no presses, and days whose presses
        // all sit after the cut (the September line among the August ones).
        #expect(days["2026-07-20"]![0] == 0)
        #expect(days["2026-08-25"]![1] == manifest.usage.offset)
        #expect(days["2026-08-13"]![0...1] == [0, 0] && manifest.archive.days["2026-08-13"] == nil)
        #expect(days["2026-08-26"]![0...1] == [0, 0])
    }

    @Test func theDayIndexContextSpanStartsAtTheSessionBeforeTheDay() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let days = try #require(manifest.index).days
        let context = try #require(manifest.context)
        // Until the 08-10 start, every day continues the session of the 07-20 start at byte 0.
        #expect(days["2026-07-21"]![2] == 0 && days["2026-08-10"]![2] == 0)
        // From 08-28 the session is the one of the 08-27 start, which is the context cut.
        #expect(days["2026-08-28"]![2] == context.offset && days["2026-08-31"]![2] == context.offset)
        // The 08-05 line written on 08-26 sits far from its day; the span reaches it.
        let log = try String(contentsOf: folder.appendingPathComponent("context.log"), encoding: .utf8)
        let late = try #require(log.range(of: "2026-08-05T10:00:00.000"))
        #expect(days["2026-08-05"]![3] > log.utf8.distance(from: log.startIndex, to: late.lowerBound))

        // A session that ends in the evening and the next start days later: the span reaches
        // the first line after the day and every line in its millisecond.
        try write(
            "2026-08-01T08:00:00.000\tstart\t-\n2026-08-01T09:00:00.000\tapp\tcom.a\n"
                + "2026-08-03T09:00:00.000\tapp\tcom.b\n2026-08-03T09:00:00.000\tstart\t-\n"
                + "2026-08-03T10:00:00.000\tapp\tcom.c\n",
            to: folder.appendingPathComponent("context.log"))
        try write("2026-08-01T09:30:00\tw\tu\n2026-09-02T10:00:00\tw\tu\n", to: folder.appendingPathComponent("usage.log"))
        let small = try #require(try compact(folder)?.index).days
        // 08-01 and 08-02 end with the app line of 08-03 and the start in the same millisecond.
        #expect(small["2026-08-01"] == [0, 24, 0, 132])
        #expect(small["2026-08-02"] == [0, 0, 0, 132])
        // No line after the day yet: read to the end of the file.
        #expect(small["2026-08-03"] == [0, 0, 0, -1])
        #expect(small["2026-08-04"] == [0, 0, 100, -1])
    }

    @Test func aLogThatIsNotUTF8IsNotCompacted() throws {
        let folder = try scratch()
        try Data([0x32, 0x30, 0xFF, 0x0A]).write(to: folder.appendingPathComponent("usage.log"))
        #expect(throws: RetentionError.self) { try compact(folder) }
    }

    @Test func aFailedWriteKeepsTheOldManifest() throws {
        let folder = try scratch()
        let manifest = try #require(try compact(folder))
        let path = folder.appendingPathComponent("retention.json").path
        try writeDurably(manifest.jsonData(), to: path)
        // A temporary file from an interrupted run is removed by the next write.
        let stale = folder.appendingPathComponent(".retention.json.0000.tmp")
        try write("{\"partial\":", to: stale)
        try writeDurably(manifest.jsonData(), to: path)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        // A folder that refuses new files: the write fails and the manifest stays as it was.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(throws: (any Error).self) { try writeDurably(Data("{}".utf8), to: path) }
        #expect(readManifest(path, now: now, calendar: calendar) == manifest)
    }
}
