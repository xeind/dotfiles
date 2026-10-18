import Foundation
import HyperdashInsights

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

struct Options {
    var log = ""
    var bindings = ""
    var output = ""
    var context: String?
    var now: Date?
    /// Retention manifest to read the logs through (insights) or to write (compact).
    var retention: String?
    var compact = false
}

func parseArguments(_ arguments: [String], calendar: Calendar) throws -> Options {
    var options = Options()
    var index = 0
    func value(for flag: String) throws -> String {
        index += 1
        guard index < arguments.count else { throw UsageError(description: "\(flag) needs a value") }
        return arguments[index]
    }
    while index < arguments.count {
        let flag = arguments[index]
        switch flag {
        case "--log": options.log = try value(for: flag)
        case "--bindings": options.bindings = try value(for: flag)
        case "--output": options.output = try value(for: flag)
        case "--context": options.context = try value(for: flag)
        case "--retention": options.retention = try value(for: flag)
        case "--compact": options.compact = true
        case "--now":
            let text = try value(for: flag)
            guard let date = parseTimestamp(text, calendar: calendar) else {
                throw UsageError(description: "--now must look like 2026-10-15T15:00:00")
            }
            options.now = date
        default: throw UsageError(description: "unknown argument \(flag)")
        }
        index += 1
    }
    let complete = options.compact
        ? !options.log.isEmpty && options.retention != nil
        : !options.log.isEmpty && !options.bindings.isEmpty && !options.output.isEmpty
    guard complete else {
        throw UsageError(
            description:
                "usage: hyperdash-insights --log <path> --bindings <path> --output <path> [--context <path>] [--retention <path>] [--now YYYY-MM-DDTHH:MM:SS]\n"
                + "       hyperdash-insights --compact --log <path> [--context <path>] --retention <path> [--now YYYY-MM-DDTHH:MM:SS]"
        )
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("hyperdash-insights: \(message)\n".utf8))
    exit(1)
}

let calendar = Calendar.current
let options: Options
do {
    options = try parseArguments(Array(CommandLine.arguments.dropFirst()), calendar: calendar)
} catch {
    fail("\(error)")
}

let now = options.now ?? Date()

// Compact: write the retention manifest for the logs as they are now. The logs are only read.
if options.compact, let path = options.retention {
    do {
        if let manifest = try compactLogs(
            logPath: options.log, contextPath: options.context, now: now, calendar: calendar)
        {
            try writeDurably(manifest.jsonData(), to: path)
        }
    } catch {
        fail("cannot compact: \(error)")
    }
    exit(0)
}

let logText: String
do {
    logText = try String(contentsOfFile: options.log, encoding: .utf8)
} catch {
    fail("cannot read log \(options.log): \(error.localizedDescription)")
}

let bindings: [Binding]
do {
    bindings = try parseBindings(Data(contentsOf: URL(fileURLWithPath: options.bindings)))
} catch {
    fail("cannot read bindings \(options.bindings): \(error)")
}

var contextEvents: [ContextEvent]?
if let path = options.context {
    do {
        let parsedContext = parseContextLog(
            try String(contentsOfFile: path, encoding: .utf8), calendar: calendar)
        if parsedContext.rejectedLines > 0 {
            FileHandle.standardError.write(
                Data("hyperdash-insights: \(parsedContext.rejectedLines) context lines rejected\n".utf8))
        }
        contextEvents = parsedContext.events
    } catch {
        fail("cannot read context \(path): \(error.localizedDescription)")
    }
}

let parsedLog = parseLog(logText, calendar: calendar)
let report = computeReport(
    events: parsedLog.events, bindings: bindings, now: now,
    rejectedLines: parsedLog.rejectedLines, context: contextEvents, calendar: calendar)

do {
    try writeAtomically(InsightsFile(report: report).jsonData(), to: options.output)
} catch {
    fail("cannot write \(options.output): \(error.localizedDescription)")
}
