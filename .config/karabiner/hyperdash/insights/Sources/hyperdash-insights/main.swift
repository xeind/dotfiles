import Foundation
import HyperdashInsights

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

struct Options {
    var log = ""
    var bindings = ""
    var output = ""
    var now: Date?
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
    guard !options.log.isEmpty, !options.bindings.isEmpty, !options.output.isEmpty else {
        throw UsageError(
            description:
                "usage: hyperdash-insights --log <path> --bindings <path> --output <path> [--now YYYY-MM-DDTHH:MM:SS]"
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

let report = computeReport(
    events: parseLog(logText, calendar: calendar), bindings: bindings,
    now: options.now ?? Date(), calendar: calendar)

do {
    try writeAtomically(InsightsFile(report: report).jsonData(), to: options.output)
} catch {
    fail("cannot write \(options.output): \(error.localizedDescription)")
}
