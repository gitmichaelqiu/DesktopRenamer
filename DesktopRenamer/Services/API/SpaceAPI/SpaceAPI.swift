import Foundation
import AppKit
import Combine

@MainActor
final class SpaceAPI {
    nonisolated static let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    nonisolated static let getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    nonisolated static let returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    nonisolated static let getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    nonisolated static let returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    nonisolated static let getAPIVersion = Notification.Name("\(apiPrefix).GetAPIVersion")
    nonisolated static let returnAPIVersion = Notification.Name("\(apiPrefix).ReturnAPIVersion")
    nonisolated static let apiToggleNotification = Notification.Name("\(apiPrefix).ReturnAPIState")
    nonisolated static let performCommand = Notification.Name("\(apiPrefix).PerformCommand")
    nonisolated static let commandResult = Notification.Name("\(apiPrefix).CommandResult")
    nonisolated static let rpcRequest = DesktopRenamerAPIContract.rpcRequest
    nonisolated static let rpcResponse = DesktopRenamerAPIContract.rpcResponse
    nonisolated static let rpcEvent = DesktopRenamerAPIContract.rpcEvent
    
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
        dnc.addObserver(self, selector: #selector(handleActiveSpaceRequest), name: SpaceAPI.getActiveSpace, object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(handleSpaceListRequest), name: SpaceAPI.getSpaceList, object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(handleAPIVersionRequest), name: SpaceAPI.getAPIVersion, object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(handleCommandRequest), name: SpaceAPI.performCommand, object: nil, suspensionBehavior: .deliverImmediately)
        
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRPCRequest),
            name: SpaceAPI.rpcRequest,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
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
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": SpaceManager.isAPIEnabled],
            deliverImmediately: true
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
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnActiveSpace, object: nil, userInfo: userInfo, deliverImmediately: true
        )
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
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnSpaceList,
            object: nil,
            userInfo: ["apiVersion": DesktopRenamerAPIVersion.current, "spaces": list],
            deliverImmediately: true
        )
    }

    func broadcastAPIVersion() {
        guard SpaceManager.isAPIEnabled else { return }

        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnAPIVersion,
            object: nil,
            userInfo: ["apiVersion": DesktopRenamerAPIVersion.current],
            deliverImmediately: true
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
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.rpcEvent,
            object: nil,
            userInfo: [DesktopRenamerAPIContract.payloadKey: payload],
            deliverImmediately: true
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

        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.rpcResponse,
            object: nil,
            userInfo: [DesktopRenamerAPIContract.payloadKey: payload],
            deliverImmediately: true
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
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.commandResult,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
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
