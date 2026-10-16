import Foundation

/// The version 3 file read by the hyperdash panel.
///
/// Changes from version 2:
///   - Every insight has `dates` and `app` (null when no single app applies).
///   - New kind `focus`. Rising and falling `value` is an absolute change in presses.
///   - Fewer cards while history is short. Rising and falling need 14 fully recorded days
///     (the 14 days before today), and unused needs 3 fully recorded days. Today never
///     counts. A day is fully recorded when it is after the first logged day, and, with a
///     context log, when every Hyper press that day lies inside a recording session.
///     The live log is new, so these cards stay absent until enough days exist.
public struct InsightsFile: Encodable, Sendable {
    public let version = 3
    public let generated: String
    public let month: String
    public let recordingSince: String?
    public let rejectedLines: Int
    public let insights: [Insight]

    public init(report: InsightReport) {
        generated = report.generated
        month = report.month
        recordingSince = report.recordingSince
        rejectedLines = report.rejectedLines
        insights = report.insights
    }

    enum CodingKeys: String, CodingKey {
        case version, generated, month, recordingSince, rejectedLines, insights
    }

    // Always write `recordingSince`, as null when absent.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(generated, forKey: .generated)
        try container.encode(month, forKey: .month)
        try container.encode(recordingSince, forKey: .recordingSince)
        try container.encode(rejectedLines, forKey: .rejectedLines)
        try container.encode(insights, forKey: .insights)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

/// Writes `data` to a temporary file beside `path`, then renames it over `path`.
public func writeAtomically(_ data: Data, to path: String) throws {
    let target = URL(fileURLWithPath: path)
    let temporary = target.deletingLastPathComponent()
        .appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).tmp")
    do {
        try data.write(to: temporary)
        guard rename(temporary.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    } catch {
        try? FileManager.default.removeItem(at: temporary)
        throw error
    }
}
