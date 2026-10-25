import AppKit
import Darwin.sys.sysctl
import Foundation

// MARK: - Diagnostic Event Log

enum DiagnosticText {
    static func singleLine(_ value: String) -> String {
        escaped(value, delimiters: ["[", "]", "\\"])
    }

    static func delimitedField(_ value: String) -> String {
        escaped(value, delimiters: ["|", "~", "\\"])
    }

    private static func escaped(_ value: String, delimiters: Set<String>) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(value.unicodeScalars.count)

        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || scalar.value == 0x2028
                || scalar.value == 0x2029 {
                let escape = "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                result.append(contentsOf: escape.unicodeScalars)
            } else if delimiters.contains(String(scalar)) {
                result.append(contentsOf: "\\".unicodeScalars)
                result.append(scalar)
            } else {
                result.append(scalar)
            }
        }

        return String(result)
    }
}

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
    private var sessionDroppedEventCount = 0

    private var ring: [DiagnosticEvent] = []
    private var nextIndex = 0
    private let capacity = 500
    private let sessionCapacity = 20_000
    private let lock = NSLock()

    private init() {}

    /// Record an event.  Always stored in the ring buffer; when collection
    /// mode is active also appended to the linear session buffer.
    /// Thread-safe — can be called from any thread.
    public func record(subsystem: String, level: String = "info", _ message: String) {
        let ev = makeEvent(subsystem: subsystem, level: level, message: message)

        lock.lock()
        defer { lock.unlock() }

        appendToRing(ev)
        if collecting {
            appendToSession(ev)
        }
    }

    /// Record verbose traces only while the user is reproducing an issue.
    /// This captures otherwise console-only Space tracking details without
    /// continuously filling the always-on ring buffer.
    func recordDuringCollection(
        subsystem: String,
        level: String = "debug",
        _ message: @autoclosure () -> String
    ) {
        guard isCollecting else { return }
        let event = makeEvent(subsystem: subsystem, level: level, message: message())
        lock.lock()
        defer { lock.unlock() }
        guard collecting else { return }

        appendToSession(event)
    }

    private func makeEvent(subsystem: String, level: String, message: String) -> DiagnosticEvent {
        DiagnosticEvent(
            timestamp: Date(),
            subsystem: DiagnosticText.singleLine(subsystem),
            level: DiagnosticText.singleLine(level),
            message: DiagnosticText.singleLine(message)
        )
    }

    private func appendToRing(_ event: DiagnosticEvent) {
        if ring.count < capacity {
            ring.append(event)
        } else {
            ring[nextIndex % capacity] = event
            nextIndex += 1
        }
    }

    private func appendToSession(_ event: DiagnosticEvent) {
        if sessionEventStorage.count >= sessionCapacity {
            let discardedCount = min(1_000, sessionEventStorage.count)
            sessionEventStorage.removeFirst(discardedCount)
            sessionDroppedEventCount += discardedCount
        }
        sessionEventStorage.append(event)
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

    var ringBufferStatus: (eventCount: Int, capacity: Int, overwrittenEventCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (ring.count, capacity, nextIndex)
    }

    var sessionEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessionEventStorage.count
    }

    var sessionDroppedEventCountSnapshot: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessionDroppedEventCount
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
        sessionDroppedEventCount = 0
        appendToSession(makeEvent(subsystem: "System", level: "info", message: "Diagnostic collection started"))
        lock.unlock()
    }

    /// Stop a diagnostic collection session.
    /// Thread-safe.
    public func stopCollection() {
        lock.lock()
        collecting = false
        appendToSession(makeEvent(subsystem: "System", level: "info", message: "Diagnostic collection stopped"))
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
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return events.map { ev in
            "[\(df.string(from: ev.timestamp))] [\(ev.subsystem)] [\(ev.level)] \(ev.message)"
        }.joined(separator: "\n")
    }
}
