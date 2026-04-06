import Foundation
import OSLog

enum EditorDebugTrace {
    private static let logger = Logger(subsystem: "Iris-Main", category: "Editor.Interaction")
    @MainActor private static var marks: [String: TimeInterval] = [:]

    static func log(_ scope: String, _ message: String) {
        logger.notice("[\(timestamp(), privacy: .public)] \(scope, privacy: .public) \(message, privacy: .public)")
    }

    static func mark() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    @MainActor
    static func begin(_ name: String, scope: String, message: String) {
        marks[name] = mark()
        log(scope, "\(message) mark=\(name)")
    }

    @MainActor
    static func end(_ name: String, scope: String, message: String) {
        if let start = marks.removeValue(forKey: name) {
            log(scope, "\(message) \(elapsedMessage(since: start)) mark=\(name)")
        } else {
            log(scope, "\(message) mark=\(name) missing-start")
        }
    }

    static func elapsedMessage(since start: TimeInterval) -> String {
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return String(format: "elapsed=%.1fms", elapsedMs)
    }

    private static func timestamp() -> String {
        String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
    }
}
