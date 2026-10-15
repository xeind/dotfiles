import Foundation

/// The version 1 file read by the hyperdash panel.
public struct InsightsFile: Encodable, Sendable {
    public let version = 1
    public let generated: String
    public let month: String
    public let insights: [Insight]

    public init(report: InsightReport) {
        generated = report.generated
        month = report.month
        insights = report.insights
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
