import Foundation

enum SpaceSwitchRequestDisposition: Equatable {
    case started
    case queued
    case alreadyCurrent
    case unavailable
}

/// Main-queue state machine for non-instant space-switch requests.
///
/// The coordinator deliberately has no AppKit or WindowServer dependencies so
/// request coalescing and generation checks can be exercised independently of
/// the operating system's space state.
struct SpaceSwitchTransactionCoordinator {
    struct Request: Equatable {
        let spaceID: String
        let isManual: Bool
    }

    struct ActiveTransaction {
        let generation: UInt64
        let request: Request
    }

    enum PendingUpdate: Equatable {
        case queued
        case replaced(previous: Request)
        case coalesced
        case cleared
    }

    private(set) var active: ActiveTransaction?
    private(set) var pending: Request?
    private var nextGeneration: UInt64 = 0

    mutating func begin(spaceID: String, isManual: Bool) -> UInt64 {
        nextGeneration += 1
        let request = Request(spaceID: spaceID, isManual: isManual)
        let transaction = ActiveTransaction(generation: nextGeneration, request: request)
        active = transaction
        pending = nil
        return transaction.generation
    }

    mutating func enqueue(spaceID: String, isManual: Bool) -> PendingUpdate {
        guard let active else {
            return .queued
        }

        let request = Request(spaceID: spaceID, isManual: isManual)
        if active.request.spaceID == spaceID {
            if pending != nil {
                pending = nil
                return .cleared
            }
            return .coalesced
        }

        if pending?.spaceID == spaceID {
            // Keep manual attribution if either coalesced request came from a
            // user gesture, while still treating the destination as one
            // duplicate pending request.
            if isManual && pending?.isManual == false {
                pending = Request(spaceID: spaceID, isManual: true)
            }
            return .coalesced
        }

        let previous = pending
        pending = request
        if let previous {
            return .replaced(previous: previous)
        }
        return .queued
    }

    mutating func endActive() -> Request? {
        let pendingRequest = pending
        active = nil
        pending = nil
        return pendingRequest
    }

    mutating func cancelActive(dropPending: Bool) {
        active = nil
        if dropPending {
            pending = nil
        }
    }

    mutating func reset() {
        active = nil
        pending = nil
    }
}
