import Foundation
import AppKit
import Combine

@MainActor
final class SpaceAPI {
    nonisolated static let apiPrefix = DesktopRenamerAPIContract.preferredAPIPrefix
    nonisolated static let legacyAPIPrefix = DesktopRenamerAPIContract.legacyAPIPrefix
    
    nonisolated static let getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    nonisolated static let legacyGetActiveSpace = Notification.Name("\(legacyAPIPrefix).GetActiveSpace")
    nonisolated static let getActiveSpaceNotifications = [getActiveSpace, legacyGetActiveSpace]
    nonisolated static let returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    nonisolated static let legacyReturnActiveSpace = Notification.Name("\(legacyAPIPrefix).ReturnActiveSpace")
    nonisolated static let returnActiveSpaceNotifications = [returnActiveSpace, legacyReturnActiveSpace]
    nonisolated static let getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    nonisolated static let legacyGetSpaceList = Notification.Name("\(legacyAPIPrefix).GetSpaceList")
    nonisolated static let getSpaceListNotifications = [getSpaceList, legacyGetSpaceList]
    nonisolated static let returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    nonisolated static let legacyReturnSpaceList = Notification.Name("\(legacyAPIPrefix).ReturnSpaceList")
    nonisolated static let returnSpaceListNotifications = [returnSpaceList, legacyReturnSpaceList]
    nonisolated static let getAPIVersion = Notification.Name("\(apiPrefix).GetAPIVersion")
    nonisolated static let legacyGetAPIVersion = Notification.Name("\(legacyAPIPrefix).GetAPIVersion")
    nonisolated static let getAPIVersionNotifications = [getAPIVersion, legacyGetAPIVersion]
    nonisolated static let returnAPIVersion = Notification.Name("\(apiPrefix).ReturnAPIVersion")
    nonisolated static let legacyReturnAPIVersion = Notification.Name("\(legacyAPIPrefix).ReturnAPIVersion")
    nonisolated static let returnAPIVersionNotifications = [returnAPIVersion, legacyReturnAPIVersion]
    nonisolated static let apiToggleNotification = Notification.Name("\(apiPrefix).ReturnAPIState")
    nonisolated static let legacyAPIToggleNotification = Notification.Name("\(legacyAPIPrefix).ReturnAPIState")
    nonisolated static let apiToggleNotifications = [apiToggleNotification, legacyAPIToggleNotification]
    nonisolated static let performCommand = Notification.Name("\(apiPrefix).PerformCommand")
    nonisolated static let legacyPerformCommand = Notification.Name("\(legacyAPIPrefix).PerformCommand")
    nonisolated static let performCommandNotifications = [performCommand, legacyPerformCommand]
    nonisolated static let commandResult = Notification.Name("\(apiPrefix).CommandResult")
    nonisolated static let legacyCommandResult = Notification.Name("\(legacyAPIPrefix).CommandResult")
    nonisolated static let commandResultNotifications = [commandResult, legacyCommandResult]
    nonisolated static let rpcRequest = DesktopRenamerAPIContract.rpcRequest
    nonisolated static let rpcResponse = DesktopRenamerAPIContract.rpcResponse
    nonisolated static let rpcEvent = DesktopRenamerAPIContract.rpcEvent
    nonisolated static let rpcRequestNotifications = DesktopRenamerAPIContract.rpcRequestNotifications
    nonisolated static let rpcResponseNotifications = DesktopRenamerAPIContract.rpcResponseNotifications
    nonisolated static let rpcEventNotifications = DesktopRenamerAPIContract.rpcEventNotifications
    
    // Use weak to avoid retain cycle (SpaceManager owns API, API shouldn't strongly own SpaceManager)
    weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()
    private var snapshotRevision: UInt64 = 0
    private var rpcListenerInstalled = false

    /// Whether the DNC listener is active (Combine pipeline has subscriptions).
    var hasActiveListeners: Bool { rpcListenerInstalled || !cancellables.isEmpty }

    /// The revision clients should use when comparing structured snapshots.
    var currentSnapshotRevision: UInt64 { snapshotRevision }
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }
    
    func setupListener() {
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "setupListener")
        removeListener()
        installRPCListener()

        guard SpaceManager.isAPIEnabled, let spaceManager = spaceManager else {
            print("SpaceAPI: Structured listener Started (API disabled)")
            return
        }
        
        let dnc = DistributedNotificationCenter.default()
        
        // Register observers for external requests.
        for name in SpaceAPI.getActiveSpaceNotifications {
            dnc.addObserver(self, selector: #selector(handleActiveSpaceRequest), name: name, object: nil, suspensionBehavior: .deliverImmediately)
        }
        for name in SpaceAPI.getSpaceListNotifications {
            dnc.addObserver(self, selector: #selector(handleSpaceListRequest), name: name, object: nil, suspensionBehavior: .deliverImmediately)
        }
        for name in SpaceAPI.getAPIVersionNotifications {
            dnc.addObserver(self, selector: #selector(handleAPIVersionRequest), name: name, object: nil, suspensionBehavior: .deliverImmediately)
        }
        for name in SpaceAPI.performCommandNotifications {
            dnc.addObserver(self, selector: #selector(handleCommandRequest), name: name, object: nil, suspensionBehavior: .deliverImmediately)
        }
        
        // Broadcast space state changes to observers.
        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
                self?.broadcastRPCEvent(reason: "activeSpaceChanged")
            }
            .store(in: &cancellables)
            
        spaceManager.$spaceNameDict
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
                self?.broadcastSpaceList()
                self?.broadcastRPCEvent(reason: "spaceListChanged")
            }
            .store(in: &cancellables)

        spaceManager.$lockedSpaceIDs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastRPCEvent(reason: "lockStateChanged")
            }
            .store(in: &cancellables)

        spaceManager.$movedWindowsOriginalSpaces
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastRPCEvent(reason: "movedWindowsChanged")
            }
            .store(in: &cancellables)
            
        print("SpaceAPI: Listener Started")
    }
    
    func removeListener() {
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "removeListener")
        DistributedNotificationCenter.default().removeObserver(self)
        rpcListenerInstalled = false
        cancellables.removeAll()
        if !SpaceManager.isAPIEnabled {
            installRPCListener()
        }
        print("SpaceAPI: Listener Stopped")
    }

    private func installRPCListener() {
        guard !rpcListenerInstalled else { return }
        let dnc = DistributedNotificationCenter.default()
        for name in SpaceAPI.rpcRequestNotifications {
            dnc.addObserver(
                self,
                selector: #selector(handleRPCRequest),
                name: name,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        rpcListenerInstalled = true
    }
    
    // API status management.
    
    func toggleAPIState() {
        SpaceManager.isAPIEnabled.toggle()
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "toggleAPIState -> \(SpaceManager.isAPIEnabled)")
        
        if SpaceManager.isAPIEnabled {
            setupListener()
        } else {
            removeListener()
        }
        
        // Broadcast API availability updates.
        postToChannels(
            SpaceAPI.apiToggleNotifications,
            userInfo: ["isEnabled": SpaceManager.isAPIEnabled]
        )
        print("SpaceAPI: Sent Toggle Notification -> \(SpaceManager.isAPIEnabled)")
    }
    
    // Broadcast updates to observers.
    
    func broadcastCurrentSpace() {
        guard let sm = spaceManager, SpaceManager.isAPIEnabled else { return }
        
        let spaceUUID = sm.currentSpaceUUID
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "broadcastCurrentSpace: spaceUUID=\(spaceUUID)")
        let userInfo: [String: Any] = [
            "apiVersion": DesktopRenamerAPIVersion.current,
            "spaceUUID": (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID,
            "spaceName": sm.getSpaceName(spaceUUID),
            "spaceNumber": NSNumber(value: sm.getSpaceNum(spaceUUID))
        ]
        
        postToChannels(SpaceAPI.returnActiveSpaceNotifications, userInfo: userInfo)
    }
    
    func broadcastSpaceList() {
        guard let sm = spaceManager, SpaceManager.isAPIEnabled else { return }
        
        let list = sm.spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
            }
            return $0.num < $1.num
        }.map { space -> [String: Any] in
            [
                "spaceUUID": space.id,
                "spaceName": sm.getSpaceName(space.id),
                "spaceNumber": NSNumber(value: space.num),
                "displayID": space.displayID
            ]
        }
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "broadcastSpaceList: count=\(list.count)")
        
        postToChannels(
            SpaceAPI.returnSpaceListNotifications,
            userInfo: ["apiVersion": DesktopRenamerAPIVersion.current, "spaces": list]
        )
    }

    func broadcastAPIVersion() {
        guard SpaceManager.isAPIEnabled else { return }

        postToChannels(
            SpaceAPI.returnAPIVersionNotifications,
            userInfo: ["apiVersion": DesktopRenamerAPIVersion.current]
        )
    }

    private func broadcastRPCEvent(reason: String) {
        guard let manager = spaceManager, SpaceManager.isAPIEnabled else { return }

        snapshotRevision &+= 1
        let snapshot = makeSpaceSnapshotPayload(manager, revision: snapshotRevision)
        guard let snapshotValue = try? SpaceAPIJSONValue.from(snapshot) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Could not encode structured event snapshot."
            )
            return
        }

        let event = SpaceAPIJSONRPCEvent(
            method: "stateChanged",
            params: .object([
                "reason": .string(reason),
                "snapshot": snapshotValue
            ])
        )
        do {
            let payload = try SpaceAPIJSONRPCCodec.encode(event)
            postRPCPayload(payload)
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "info",
                "broadcastRPCEvent(reason: \(reason), revision: \(snapshotRevision))"
            )
        } catch {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Could not encode structured event: \(error.localizedDescription)"
            )
        }
    }

    private func postRPCPayload(_ payload: String) {
        postToChannels(
            SpaceAPI.rpcEventNotifications,
            userInfo: [DesktopRenamerAPIContract.payloadKey: payload]
        )
    }

    func postRPCResponse(_ response: SpaceAPIJSONRPCResponse) {
        let payload: String
        do {
            payload = try SpaceAPIJSONRPCCodec.encode(response)
        } catch let error as SpaceAPIContractError {
            let fallback = SpaceAPIJSONRPCCodec.errorResponse(
                id: response.id,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData
            )
            guard let fallbackPayload = try? SpaceAPIJSONRPCCodec.encode(fallback) else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceAPI",
                    level: "warning",
                    "Could not encode structured error response: \(error.localizedDescription)"
                )
                return
            }
            payload = fallbackPayload
        } catch {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Could not encode structured response: \(error.localizedDescription)"
            )
            return
        }

        postToChannels(
            SpaceAPI.rpcResponseNotifications,
            userInfo: [DesktopRenamerAPIContract.payloadKey: payload]
        )
    }

    func postCommandResult(requestID: String, result: String? = nil, error: String? = nil) {
        var userInfo: [String: Any] = [
            "requestID": requestID,
            "apiVersion": DesktopRenamerAPIVersion.current,
            "success": error == nil
        ]
        if let result { userInfo["result"] = result }
        if let error { userInfo["error"] = error }
        postToChannels(SpaceAPI.commandResultNotifications, userInfo: userInfo)
    }

    private func postToChannels(_ names: [Notification.Name], userInfo: [String: Any]) {
        let dnc = DistributedNotificationCenter.default()
        for name in names {
            dnc.postNotificationName(name, object: nil, userInfo: userInfo, deliverImmediately: true)
        }
    }

    func executeRPCMethod(_ request: SpaceAPIJSONRPCRequest) async throws -> SpaceAPIJSONValue {
        guard let definition = DesktopRenamerAPIContract.definition(for: request.method) else {
            throw SpaceAPIContractError.unsupportedMethod(request.method)
        }

        let arguments = try SpaceAPIArgumentValidator.stringArguments(from: request.params, method: request.method)
        switch request.method {
        case "getAPIInfo":
            return try SpaceAPIJSONValue.from(makeAPIInfo())
        case "getAPIVersion":
            return .string(DesktopRenamerAPIVersion.current)
        case "getSpaceSnapshot":
            guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }
            return try SpaceAPIJSONValue.from(makeSpaceSnapshotPayload(manager, revision: snapshotRevision))
        case "getAllSpaces":
            guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }
            let spaces = makeSpaceRecords(manager)
            return try SpaceAPIJSONValue.from(spaces)
        case "getWindows":
            guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }
            let snapshot = await makeWindowsSnapshotPayloadAsync(manager, revision: snapshotRevision)
            return try SpaceAPIJSONValue.from(snapshot)
        case "getCurrentSpaceName":
            guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }
            return .string(manager.getSpaceName(manager.currentSpaceUUID))
        case "getCurrentSpaceID":
            return .array(SpaceHelper.getCurrentSpaceIDs().map(SpaceAPIJSONValue.string))
        default:
            let result = try await executeCommand(request.method, arguments: arguments)
            if definition.resultKind == .boolean {
                guard result == "true" || result == "false" else {
                    throw SpaceAPIError.operationFailed("The command returned an invalid Boolean result.")
                }
                return .bool(result == "true")
            }
            return try SpaceAPIJSONValue.from(SpaceAPIOperationResult(accepted: true))
        }
    }

}
