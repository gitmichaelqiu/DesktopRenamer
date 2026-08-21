import AppKit
import Combine

/// Reorders spaces through macOS's private SkyLight operation.
final class SpaceRearrangementService: ObservableObject {
    static let shared = SpaceRearrangementService()

    @Published private(set) var debugStatus = "Idle"

    enum Result {
        case success
        case failure(String)
    }

    private init() {}

    func setDebugStatus(_ status: String) {
        if Thread.isMainThread {
            debugStatus = status
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.debugStatus = status
            }
        }
    }

    func rearrange(
        sourceID: String,
        before targetID: String,
        orderedSpaceIDs: [String],
        displayID: String? = nil,
        completion: @escaping (Result) -> Void
    ) {
        guard sourceID != targetID,
              let sourceIndex = orderedSpaceIDs.firstIndex(of: sourceID),
              let targetIndex = orderedSpaceIDs.firstIndex(of: targetID) else {
            finish(.failure(String(localized: "Choose two different spaces.")), completion: completion)
            return
        }

        guard sourceIndex != targetIndex - 1 else {
            finish(.failure(String(localized: "Those spaces are already in that order.")), completion: completion)
            return
        }

        var expectedOrder = orderedSpaceIDs
        expectedOrder.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        expectedOrder.insert(sourceID, at: insertionIndex)

        setDebugStatus("Rearranging spaces…")
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
                    sourceID: sourceID,
                    before: targetID,
                    expectedOrder: expectedOrder,
                    displayID: displayID,
                    attempt: 0,
                    completion: completion
                )
            }
        }
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
        sourceID: String,
        before targetID: String,
        expectedOrder: [String],
        displayID: String?,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard let state = SpaceHelper.getSystemState(onDisplayID: displayID) else {
            retryVerification(
                sourceID: sourceID,
                targetID: targetID,
                expectedOrder: expectedOrder,
                displayID: displayID,
                attempt: attempt,
                completion: completion
            )
            return
        }

        let regularSpaces = state.spaces.filter { !$0.isFullscreen }
        if regularSpaces.map(\.id) == expectedOrder {
            finish(.success, completion: completion)
            return
        }

        retryVerification(
            sourceID: sourceID,
            targetID: targetID,
            expectedOrder: expectedOrder,
            displayID: displayID,
            attempt: attempt,
            completion: completion
        )
    }

    private func retryVerification(
        sourceID: String,
        targetID: String,
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
                sourceID: sourceID,
                before: targetID,
                expectedOrder: expectedOrder,
                displayID: displayID,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func finish(_ result: Result, completion: @escaping (Result) -> Void) {
        setDebugStatus(status(for: result))
        completion(result)
    }

    private func status(for result: Result) -> String {
        switch result {
        case .success:
            return "Debug rearrangement completed."
        case .failure(let error):
            return "Debug rearrangement failed: \(error)"
        }
    }
}
