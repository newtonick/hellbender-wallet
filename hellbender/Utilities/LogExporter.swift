import Foundation
import OSLog

enum LogExporter {
  /// Collects recent app logs from the unified logging system.
  /// - Parameter hours: How many hours back to look (default 1).
  /// - Returns: A formatted string of log entries, newest last.
  static func collectLogs(hours: Double = 1) throws -> String {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let cutoff = store.position(date: Date().addingTimeInterval(-hours * 3600))
    let subsystem = Bundle.main.bundleIdentifier ?? "hellbender"

    let entries = try store.getEntries(at: cutoff, matching: NSPredicate(format: "subsystem == %@", subsystem))

    var lines: [String] = []
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    for entry in entries {
      guard let logEntry = entry as? OSLogEntryLog else { continue }
      let timestamp = formatter.string(from: logEntry.date)
      let level = levelString(logEntry.level)
      lines.append("[\(timestamp)] [\(level)] [\(logEntry.category)] \(logEntry.composedMessage)")
    }

    if lines.isEmpty {
      return "No log entries found in the last \(Int(hours)) hour(s)."
    }

    let header = "Birch Logs — Exported \(formatter.string(from: Date()))\n"
      + "Entries: \(lines.count) (last \(Int(hours))h)\n"
      + String(repeating: "─", count: 60) + "\n"

    return header + lines.joined(separator: "\n")
  }

  private static func levelString(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .debug: "DEBUG"
    case .info: "INFO"
    case .notice: "NOTICE"
    case .error: "ERROR"
    case .fault: "FAULT"
    default: "UNKNOWN"
    }
  }
}
