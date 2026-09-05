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
    private weak var spaceManager: SpaceManager?
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
    
    private func broadcastCurrentSpace() {
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
    
    private func broadcastSpaceList() {
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

    private func broadcastAPIVersion() {
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

    private func postRPCResponse(_ response: SpaceAPIJSONRPCResponse) {
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

    private func postCommandResult(requestID: String, result: String? = nil, error: String? = nil) {
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

    private func executeRPCMethod(_ request: SpaceAPIJSONRPCRequest) async throws -> SpaceAPIJSONValue {
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

    private func executeCommand(_ command: String, arguments: [String: String]) async throws -> String {
        guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }

        switch command {
        case "getAPIVersion":
            return DesktopRenamerAPIVersion.current
        case "getSpaceSnapshot":
            return try makeSpaceSnapshot(manager)
        case "getCurrentSpaceName":
            return manager.getSpaceName(manager.currentSpaceUUID)
        case "getCurrentSpaceID":
            return SpaceHelper.getCurrentSpaceIDs().joined(separator: ",")
        case "getAllSpaces":
            return manager.spaceNameDict.sorted {
                if $0.displayID != $1.displayID {
                    return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
                }
                return $0.num < $1.num
            }.map { space in
                let name = manager.getSpaceName(space.id)
                return "\(space.id)~\(name)~\(space.displayID)~\(space.num)~\(space.isFullscreen ? "1" : "0")~\(space.appPath ?? "")"
            }.joined(separator: "\n")
        case "switchToSpace":
            guard let spaceID = arguments["spaceID"],
                  let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
                throw SpaceAPIError.invalidArgument("Invalid space ID.")
            }
            manager.switchToSpace(space, forceInstant: true)
            return ""
        case "renameCurrentSpace":
            guard let name = arguments["name"] else { throw SpaceAPIError.invalidArgument("Missing space name.") }
            manager.renameSpace(manager.currentSpaceUUID, to: name)
            return ""
        case "renameSpace":
            guard let spaceID = arguments["spaceID"], let name = arguments["name"] else {
                throw SpaceAPIError.invalidArgument("Missing space ID or name.")
            }
            manager.renameSpace(spaceID, to: name)
            return ""
        case "rearrangeSpace":
            guard let spaceID = arguments["spaceID"], let direction = arguments["direction"] else {
                throw SpaceAPIError.invalidArgument("Missing space ID or direction.")
            }
            return try await rearrangeSpace(spaceID: spaceID, direction: direction, manager: manager)
        case "moveWindowNext":
            manager.moveActiveWindowToNextSpace()
            return ""
        case "moveWindowPrevious":
            manager.moveActiveWindowToPreviousSpace()
            return ""
        case "moveWindowToSpace":
            guard let spaceID = arguments["spaceID"] else { throw SpaceAPIError.invalidArgument("Missing space ID.") }
            manager.moveActiveWindowToSpace(id: spaceID)
            return ""
        case "reloadSpaceLabels":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.reloadAllWindows()
            return ""
        case "toggleMenubar":
            StatusBarController.toggleStatusBar()
            return StatusBarController.isStatusBarHidden ? "false" : "true"
        case "toggleLauncher":
            LauncherWindowController.shared.toggle()
            return LauncherWindowController.shared.window?.isVisible == true ? "true" : "false"
        case "toggleLabels":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showActiveLabels.toggle()
            labelManager.showPreviewLabels.toggle()
            return labelManager.showActiveLabels && labelManager.showPreviewLabels ? "true" : "false"
        case "toggleActiveLabel":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showActiveLabels.toggle()
            return labelManager.showActiveLabels ? "true" : "false"
        case "togglePreviewLabel":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showPreviewLabels.toggle()
            return labelManager.showPreviewLabels ? "true" : "false"
        case "toggleDesktopVisibility":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showOnDesktop.toggle()
            return labelManager.showOnDesktop ? "true" : "false"
        case "getWindows":
            let spaces = manager.spaceNameDict
            let names = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, manager.getSpaceName($0.id)) })
            return SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
        case "focusWindow":
            guard let windowID = Int(arguments["windowID"] ?? ""), let pid = Int32(arguments["pid"] ?? "") else {
                throw SpaceAPIError.invalidArgument("Missing window ID or process ID.")
            }
            SpaceHelper.focusWindow(id: windowID, pid: pid)
            return ""
        case "executeWindowAction":
            guard let windowID = Int(arguments["windowID"] ?? ""),
                  let pid = Int32(arguments["pid"] ?? ""),
                  let action = arguments["action"] else {
                throw SpaceAPIError.invalidArgument("Missing window action arguments.")
            }
            try await executeWindowAction(windowID: windowID, pid: pid, action: action, manager: manager)
            return ""
        case "moveSpecificWindow":
            guard let windowID = Int(arguments["windowID"] ?? ""),
                  let fromSpaceID = arguments["fromSpaceID"],
                  let targetSpaceID = arguments["targetSpaceID"] else {
                throw SpaceAPIError.invalidArgument("Missing window move arguments.")
            }
            let moved: Bool
            if let pid = Int32(arguments["pid"] ?? "") {
                moved = await WindowActionCoordinator.moveWindow(
                    windowID: windowID,
                    pid: pid,
                    fromSpaceID: fromSpaceID,
                    targetSpaceID: targetSpaceID
                )
            } else if let fromSpaceID = Int(fromSpaceID), let targetSpaceID = Int(targetSpaceID) {
                SpaceHelper.moveWindowToSpace(
                    windowID: windowID,
                    fromSpaceID: fromSpaceID,
                    targetSpaceID: targetSpaceID
                )
                moved = true
            } else {
                throw SpaceAPIError.invalidArgument("A process ID or numeric space IDs are required.")
            }
            guard moved else { throw SpaceAPIError.operationFailed("Window move failed.") }
            return ""
        default:
            throw SpaceAPIError.unsupportedCommand(command)
        }
    }

    private func executeWindowAction(windowID: Int, pid: Int32, action: String, manager: SpaceManager) async throws {
        // Quitting an app is process-scoped and does not require its window to
        // be made frontmost. Avoid moving the user's desktop just to terminate
        // an application in another space.
        if action == "quit" {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw SpaceAPIError.operationFailed("Application is no longer running.")
            }
            app.terminate()
            return
        }

        if let spaceID = SpaceHelper.getWindowSpaceID(id: windowID),
           manager.currentSpaceUUID != spaceID,
           let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(space, forceInstant: true)
            try await Task.sleep(nanoseconds: 600_000_000)
        }

        await exitFullscreenWindowIfNeeded(
            windowID: windowID,
            pid: pid,
            action: action,
            manager: manager
        )

        if action == "hide" {
            NSRunningApplication(processIdentifier: pid)?.hide()
            return
        }

        if action == "restore" {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }

        var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        if axWindow == nil, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            try await Task.sleep(nanoseconds: 400_000_000)
            axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        }
        guard let axWindow else { throw SpaceAPIError.operationFailed("Window is no longer accessible.") }

        switch action {
        case "close":
            var closeButtonRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                  let closeButton = closeButtonRef,
                  CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
                throw SpaceAPIError.operationFailed("Window does not expose a close action.")
            }
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        case "minimize", "restore":
            AXUIElementSetAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                (action == "minimize") as CFTypeRef
            )
        case "enterFullScreen", "exitFullScreen":
            AXUIElementSetAttributeValue(
                axWindow,
                "AXFullScreen" as CFString,
                (action == "enterFullScreen") as CFTypeRef
            )
            try await Task.sleep(nanoseconds: 1_000_000_000)
        default:
            throw SpaceAPIError.invalidArgument("Unsupported window action: \(action)")
        }
    }

    private func exitFullscreenWindowIfNeeded(
        windowID: Int,
        pid: Int32,
        action: String,
        manager: SpaceManager
    ) async {
        guard action == "close" || action == "minimize" || action == "hide",
              let spaceID = SpaceHelper.getWindowSpaceID(id: windowID),
              let space = manager.spaceNameDict.first(where: { $0.id == spaceID }),
              space.isFullscreen else {
            return
        }

        var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        if axWindow == nil, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(nanoseconds: 400_000_000)
            axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        }

        if let axWindow {
            AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private func rearrangeSpace(spaceID: String, direction: String, manager: SpaceManager) async throws -> String {
        guard let sourceSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            throw SpaceAPIError.invalidArgument("Invalid space ID.")
        }
        let orderedSpaces = manager.spaceNameDict
            .filter { $0.displayID == sourceSpace.displayID && (sourceSpace.isFullscreen || !$0.isFullscreen) }
            .sorted { $0.num < $1.num }
        guard let sourceIndex = orderedSpaces.firstIndex(where: { $0.id == sourceSpace.id }) else {
            throw SpaceAPIError.invalidArgument("Invalid space ID.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion: (SpaceRearrangementService.Result) -> Void = { result in
                switch result {
                case .success:
                    manager.refreshSpaceState()
                    continuation.resume(returning: "")
                case .failure(let message):
                    continuation.resume(throwing: SpaceAPIError.operationFailed(message))
                }
            }

            switch direction.lowercased() {
            case "up":
                guard sourceIndex > 0 else {
                    continuation.resume(throwing: SpaceAPIError.invalidArgument("Space is already first."))
                    return
                }
                SpaceRearrangementService.shared.rearrange(
                    sourceID: spaceID,
                    before: orderedSpaces[sourceIndex - 1].id,
                    orderedSpaceIDs: orderedSpaces.map(\.id),
                    displayID: sourceSpace.displayID,
                    completion: completion
                )
            case "down":
                guard sourceIndex < orderedSpaces.count - 1 else {
                    continuation.resume(throwing: SpaceAPIError.invalidArgument("Space is already last."))
                    return
                }
                if sourceIndex + 2 < orderedSpaces.count {
                    SpaceRearrangementService.shared.rearrange(
                        sourceID: spaceID,
                        before: orderedSpaces[sourceIndex + 2].id,
                        orderedSpaceIDs: orderedSpaces.map(\.id),
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                } else {
                    SpaceRearrangementService.shared.rearrangeToEnd(
                        sourceID: spaceID,
                        orderedSpaceIDs: orderedSpaces.map(\.id),
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                }
            default:
                continuation.resume(throwing: SpaceAPIError.invalidArgument("Direction must be up or down."))
            }
        }
    }
    
    @objc nonisolated private func handleActiveSpaceRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleActiveSpaceRequest")
            self.broadcastCurrentSpace()
        }
    }
    @objc nonisolated private func handleSpaceListRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleSpaceListRequest")
            self.broadcastSpaceList()
        }
    }

    @objc nonisolated private func handleAPIVersionRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleAPIVersionRequest")
            self.broadcastAPIVersion()
        }
    }

    @objc nonisolated private func handleCommandRequest(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let requestID = (userInfo["requestID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let command = userInfo["command"] as? String ?? ""
        var arguments: [String: String] = [:]
        var argumentError: String?
        if let argumentsJSON = userInfo["argumentsJSON"] as? String {
            if let data = argumentsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                arguments = decoded
            } else {
                argumentError = "Arguments must be a JSON object containing only string values."
            }
        } else if let rawArguments = userInfo["arguments"] {
            if let decoded = rawArguments as? [String: String] {
                arguments = decoded
            } else {
                argumentError = "Arguments must be a dictionary containing only string values."
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard SpaceManager.isAPIEnabled else {
                self.postCommandResult(requestID: requestID, error: SpaceAPIError.apiDisabled.localizedDescription)
                return
            }
            if let argumentError {
                self.postCommandResult(requestID: requestID, error: argumentError)
                return
            }
            do {
                let validatedArguments = try SpaceAPIArgumentValidator.stringArguments(
                    from: .object(arguments.mapValues { .string($0) }),
                    method: command
                )
                let result = try await self.executeCommand(command, arguments: validatedArguments)
                self.postCommandResult(requestID: requestID, result: result)
            } catch {
                self.postCommandResult(requestID: requestID, error: error.localizedDescription)
            }
        }
    }

    @objc nonisolated private func handleRPCRequest(_ notification: Notification) {
        let payload = notification.userInfo?[DesktopRenamerAPIContract.payloadKey] as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processRPCRequest(payload)
        }
    }

    private func processRPCRequest(_ payload: String?) async {
        guard let payload else {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: nil,
                code: SpaceAPIJSONRPCCode.invalidRequest,
                message: "A JSON-RPC payload is required."
            ))
            return
        }

        let recoverableRequestID = Self.recoverableRequestID(from: payload)

        let request: SpaceAPIJSONRPCRequest
        do {
            request = try SpaceAPIJSONRPCCodec.decodeRequest(payload)
        } catch let error as SpaceAPIContractError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: recoverableRequestID,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData
            ))
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Rejected structured request: \(error.localizedDescription)"
            )
            return
        } catch {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: recoverableRequestID,
                code: SpaceAPIJSONRPCCode.invalidRequest,
                message: "Request could not be validated."
            ))
            return
        }

        guard SpaceManager.isAPIEnabled else {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: SpaceAPIError.apiDisabled.jsonRPCCode,
                message: SpaceAPIError.apiDisabled.localizedDescription
            ))
            return
        }

        do {
            let result = try await executeRPCMethod(request)
            postRPCResponse(SpaceAPIJSONRPCResponse(id: request.id, result: result))
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "info",
                "Completed structured request method=\(request.method) id=\(request.id)"
            )
        } catch let error as SpaceAPIContractError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData(command: request.method)
            ))
        } catch let error as SpaceAPIError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData(command: request.method)
            ))
        } catch {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: SpaceAPIJSONRPCCode.internalError,
                message: "DesktopRenamer could not complete the request."
            ))
        }
    }

    private static func recoverableRequestID(from payload: String) -> String? {
        guard payload.utf8.count <= DesktopRenamerAPIContract.maxPayloadBytes,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dictionary = object as? [String: Any],
              let id = dictionary["id"] as? String,
              !id.isEmpty else {
            return nil
        }
        return id
    }
}

private enum SpaceAPIError: LocalizedError {
    case apiDisabled
    case appUnavailable
    case invalidArgument(String)
    case operationFailed(String)
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .apiDisabled: return "SpaceAPI Disabled"
        case .appUnavailable: return "DesktopRenamer is not ready."
        case .invalidArgument(let message), .operationFailed(let message): return message
        case .unsupportedCommand(let command): return "Unsupported SpaceAPI command: \(command)"
        }
    }
}

private extension SpaceAPIError {
    var jsonRPCCode: Int {
        switch self {
        case .apiDisabled:
            return SpaceAPIJSONRPCCode.apiDisabled
        case .appUnavailable:
            return SpaceAPIJSONRPCCode.appUnavailable
        case .invalidArgument:
            return SpaceAPIJSONRPCCode.invalidParams
        case .operationFailed:
            return SpaceAPIJSONRPCCode.operationFailed
        case .unsupportedCommand:
            return SpaceAPIJSONRPCCode.methodNotFound
        }
    }

    func jsonRPCData(command: String? = nil) -> SpaceAPIErrorData? {
        switch self {
        case .invalidArgument:
            return SpaceAPIErrorData(expected: "valid command parameters", command: command)
        case .operationFailed:
            return command.map { SpaceAPIErrorData(command: $0) }
        case .unsupportedCommand(let command):
            return SpaceAPIErrorData(command: command)
        default:
            return nil
        }
    }
}
