import Foundation

struct MovedWindowRestoreQueueCoordinator {
    private(set) var pendingWindowIDs: [Int] = []
    private(set) var activeWindowID: Int?
    private(set) var isRunning = false
    private(set) var generation: UInt64 = 0

    /// Adds each window at most once. Returns true when this starts a new run.
    mutating func enqueue(_ windowIDs: [Int]) -> Bool {
        var knownWindowIDs = Set(pendingWindowIDs)
        if let activeWindowID {
            knownWindowIDs.insert(activeWindowID)
        }

        var addedWindow = false
        for windowID in windowIDs where knownWindowIDs.insert(windowID).inserted {
            pendingWindowIDs.append(windowID)
            addedWindow = true
        }

        guard addedWindow else { return false }
        guard !isRunning else { return false }

        isRunning = true
        generation &+= 1
        return true
    }

    mutating func takeNext(generation: UInt64) -> Int? {
        guard isRunning, self.generation == generation, activeWindowID == nil,
              !pendingWindowIDs.isEmpty else {
            return nil
        }

        let windowID = pendingWindowIDs.removeFirst()
        activeWindowID = windowID
        return windowID
    }

    @discardableResult
    mutating func completeActive(windowID: Int, generation: UInt64) -> Bool {
        guard isRunning, self.generation == generation, activeWindowID == windowID else {
            return false
        }

        activeWindowID = nil
        return true
    }

    mutating func finishIfDrained(generation: UInt64) -> Bool {
        guard isRunning, self.generation == generation,
              activeWindowID == nil, pendingWindowIDs.isEmpty else {
            return false
        }

        isRunning = false
        return true
    }

    mutating func clearPending() {
        pendingWindowIDs.removeAll()
    }
}
