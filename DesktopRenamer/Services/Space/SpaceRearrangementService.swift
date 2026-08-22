import AppKit
import Foundation

/// Reorders spaces through macOS's private SkyLight operation.
final class SpaceRearrangementService {
    static let shared = SpaceRearrangementService()

    enum Result {
        case success
        case failure(String)
    }

    private init() {}

    private let stateLock = NSLock()
    private var operationInFlight = false

    func rearrange(
        sourceID: String,
        before targetID: String,
        orderedSpaceIDs: [String],
        displayID: String? = nil,
        completion: @escaping (Result) -> Void
    ) {
        guard beginOperation() else {
            completion(.failure(String(localized: "A space rearrangement is already in progress.")))
            return
        }

        guard sourceID != targetID,
              let targetIndex = orderedSpaceIDs.firstIndex(of: targetID) else {
            finish(.failure(String(localized: "Choose two different spaces.")), completion: completion)
            return
        }

        performMove(
            sourceID: sourceID,
            targetIndex: targetIndex,
            orderedSpaceIDs: orderedSpaceIDs,
            displayID: displayID,
            completion: completion
        )
    }

    func rearrangeToEnd(
        sourceID: String,
        orderedSpaceIDs: [String],
        displayID: String? = nil,
        completion: @escaping (Result) -> Void
    ) {
        guard beginOperation() else {
            completion(.failure(String(localized: "A space rearrangement is already in progress.")))
            return
        }

        performMove(
            sourceID: sourceID,
            targetIndex: orderedSpaceIDs.count,
            orderedSpaceIDs: orderedSpaceIDs,
            displayID: displayID,
            completion: completion
        )
    }

    private func performMove(
        sourceID: String,
        targetIndex: Int,
        orderedSpaceIDs: [String],
        displayID: String?,
        completion: @escaping (Result) -> Void
    ) {
        guard let sourceIndex = orderedSpaceIDs.firstIndex(of: sourceID) else {
            finish(.failure(String(localized: "Choose a valid space.")), completion: completion)
            return
        }

        guard sourceIndex != targetIndex - 1 else {
            finish(.success, completion: completion)
            return
        }

        var expectedOrder = orderedSpaceIDs
        expectedOrder.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        expectedOrder.insert(sourceID, at: insertionIndex)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runMove(
                sourceID: sourceID,
                displayID: displayID,
                sourceIndex: sourceIndex,
                targetIndex: targetIndex
            ) ?? .failure(String(localized: "Space rearrangement was cancelled."))

            DispatchQueue.main.async {
                guard case .success = result else {
                    self?.finish(result, completion: completion)
                    return
                }

                self?.verify(
                    expectedOrder: expectedOrder,
                    displayID: displayID,
                    attempt: 0,
                    completion: completion
                )
            }
        }
    }

    private func beginOperation() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !operationInFlight else { return false }
        operationInFlight = true
        return true
    }

    private func runMove(sourceID: String, displayID: String?, sourceIndex: Int, targetIndex: Int) -> Result {
        guard let sourceSpaceID = UInt64(sourceID),
              let displayID,
              let operationClass = NSClassFromString("SLSBridgedMoveManagedSpaceToDisplayIndexOperation") as? NSObject.Type else {
            return .failure(String(localized: "This macOS version does not expose the native space rearrangement operation."))
        }

        let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        let allocationSelector = NSSelectorFromString("alloc")
        guard let operation = operationClass.perform(allocationSelector)?.takeUnretainedValue() as? NSObject else {
            return .failure(String(localized: "Could not create the native space rearrangement operation."))
        }

        let initializerSelector = NSSelectorFromString("initWithSpaceID:displayIdentifier:index:")
        guard let method = class_getInstanceMethod(operationClass, initializerSelector) else {
            return .failure(String(localized: "The native space rearrangement operation is unavailable on this macOS version."))
        }

        typealias Initializer = @convention(c) (NSObject, Selector, UInt64, NSString, UInt32) -> Unmanaged<NSObject>?
        let initializer = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
        guard let initializedOperation = initializer(
            operation,
            initializerSelector,
            sourceSpaceID,
            displayID as NSString,
            UInt32(destinationIndex)
        )?.takeUnretainedValue() else {
            return .failure(String(localized: "Could not initialize the native space rearrangement operation."))
        }

        guard let bridgeClass = NSClassFromString("SLSWindowManagementFallbackBridge") as? NSObject.Type,
              let bridge = bridgeClass.perform(allocationSelector)?.takeUnretainedValue() as? NSObject,
              let initializedBridge = bridge.perform(NSSelectorFromString("init"))?.takeUnretainedValue() as? NSObject else {
            return .failure(String(localized: "The native space rearrangement bridge is unavailable."))
        }

        let performSelector = NSSelectorFromString("performAsynchronousBridgedWindowManagementOperation:")
        guard initializedBridge.responds(to: performSelector) else {
            return .failure(String(localized: "The native space rearrangement bridge is unavailable."))
        }

        initializedBridge.perform(performSelector, with: initializedOperation)
        return .success
    }

    private func verify(
        expectedOrder: [String],
        displayID: String?,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard let state = SpaceHelper.getSystemState(onDisplayID: displayID) else {
            retryVerification(
                expectedOrder: expectedOrder,
                displayID: displayID,
                attempt: attempt,
                completion: completion
            )
            return
        }

        let spacesOnDisplay = state.spaces.filter { space in
            displayID == nil || space.displayID == displayID
        }
        let includesFullscreenSpace = expectedOrder.contains { spaceID in
            spacesOnDisplay.first(where: { $0.id == spaceID })?.isFullscreen == true
        }
        let actualOrder = includesFullscreenSpace
            ? spacesOnDisplay.map(\.id)
            : spacesOnDisplay.filter { !$0.isFullscreen }.map(\.id)
        if actualOrder == expectedOrder {
            finish(.success, completion: completion)
            return
        }

        retryVerification(
            expectedOrder: expectedOrder,
            displayID: displayID,
            attempt: attempt,
            completion: completion
        )
    }

    private func retryVerification(
        expectedOrder: [String],
        displayID: String?,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard attempt < 8 else {
            finish(.failure(String(localized: "The backend completed without producing the requested space order.")), completion: completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.verify(
                expectedOrder: expectedOrder,
                displayID: displayID,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func finish(_ result: Result, completion: @escaping (Result) -> Void) {
        stateLock.lock()
        operationInFlight = false
        stateLock.unlock()

        completion(result)
        if case .success = result {
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceRearrangementCompleted"),
                object: nil
            )
        }
    }
}
