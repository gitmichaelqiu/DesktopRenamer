import AppKit
import Darwin.sys.sysctl
import Foundation

// MARK: - Diagnostic Event Log

/// A single event recorded by the diagnostic system.
public struct DiagnosticEvent: Codable {
    public let timestamp: Date
    public let subsystem: String  // e.g. "SpaceHelper", "GestureManager"
    public let level: String      // "info", "warning", "error"
    public let message: String
}

/// Thread-safe circular buffer of diagnostic events.
/// The last `capacity` events are kept in memory and included in diagnostic
/// reports.  When collection mode is active, events are also logged in
/// real-time for reproduction workflows.
public class DiagnosticEventLog {
    public static let shared = DiagnosticEventLog()

    private var collecting = false
    private var startTime: Date?
    private var sessionEventStorage: [DiagnosticEvent] = []

    private var ring: [DiagnosticEvent] = []
    private var nextIndex = 0
    private let capacity = 500
    private let lock = NSLock()

    private init() {}

    /// Record an event.  Always stored in the ring buffer; when collection
    /// mode is active also appended to the linear session buffer.
    /// Thread-safe — can be called from any thread.
    public func record(subsystem: String, level: String = "info", _ message: String) {
        let ev = DiagnosticEvent(timestamp: Date(), subsystem: subsystem, level: level, message: message)

        lock.lock()
        defer { lock.unlock() }
        
        if ring.count < capacity {
            ring.append(ev)
        } else {
            ring[nextIndex % capacity] = ev
            nextIndex += 1
        }
        if collecting {
            sessionEventStorage.append(ev)
        }
    }

    public var isCollecting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return collecting
    }

    public var collectionStartTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return startTime
    }

    public var sessionEvents: [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return sessionEventStorage
    }

    /// Start a diagnostic collection session.
    /// Thread-safe.
    public func startCollection() {
        lock.lock()
        collecting = true
        startTime = Date()
        sessionEventStorage.removeAll()
        sessionEventStorage.append(DiagnosticEvent(timestamp: Date(), subsystem: "System", level: "info", message: "Diagnostic collection started"))
        lock.unlock()
    }

    /// Stop a diagnostic collection session.
    /// Thread-safe.
    public func stopCollection() {
        lock.lock()
        collecting = false
        sessionEventStorage.append(DiagnosticEvent(timestamp: Date(), subsystem: "System", level: "info", message: "Diagnostic collection stopped"))
        lock.unlock()
    }

    /// Format all ring events for inclusion in a report.
    /// Thread-safe.
    public func formattedRing() -> String {
        lock.lock()
        let copy = ring
        lock.unlock()
        let sorted = copy.sorted { $0.timestamp < $1.timestamp }
        return format(sorted)
    }

    /// Format session events for inclusion in a report.
    /// Thread-safe.
    public func formattedSession() -> String {
        lock.lock()
        let copy = sessionEventStorage
        lock.unlock()
        return format(copy)
    }

    private func format(_ events: [DiagnosticEvent]) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return events.map { ev in
            "[\(df.string(from: ev.timestamp))] [\(ev.subsystem)] [\(ev.level)] \(ev.message)"
        }.joined(separator: "\n")
    }
}
