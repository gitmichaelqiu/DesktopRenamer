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
    
    // Use weak to avoid retain cycle (SpaceManager owns API, API shouldn't strongly own SpaceManager)
    private weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()

    /// Whether the DNC listener is active (Combine pipeline has subscriptions).
    var hasActiveListeners: Bool { !cancellables.isEmpty }
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }
    
    func setupListener() {
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "setupListener")
        guard let spaceManager = spaceManager else { return }
        removeListener()
        
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
            .sink { [weak self] _ in self?.broadcastCurrentSpace() }
            .store(in: &cancellables)
            
        spaceManager.$spaceNameDict
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
                self?.broadcastSpaceList()
            }
            .store(in: &cancellables)
            
        print("SpaceAPI: Listener Started")
    }
    
    func removeListener() {
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "removeListener")
        DistributedNotificationCenter.default().removeObserver(self)
        cancellables.removeAll()
        print("SpaceAPI: Listener Stopped")
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
            AppDelegate.shared.statusBarController?.labelManager.reloadAllWindows()
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
            return await fetchWindowsForAPI(spaces: spaces, names: names)
        case "getWindowsSnapshot":
            let spaces = manager.spaceNameDict
            let names = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, manager.getSpaceName($0.id)) })
            let snapshots = await fetchWindowSnapshots(spaces: spaces, names: names)
            guard let data = try? JSONEncoder().encode(snapshots),
                  let result = String(data: data, encoding: .utf8) else {
                throw SpaceAPIError.operationFailed("Could not encode the window snapshot.")
            }
            return result
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
        if let spaceID = SpaceHelper.getWindowSpaceID(id: windowID),
           manager.currentSpaceUUID != spaceID,
           let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(space, forceInstant: true)
            try await Task.sleep(nanoseconds: 600_000_000)
        }

        if action == "quit" {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw SpaceAPIError.operationFailed("Application is no longer running.")
            }
            app.terminate()
            return
        }
        if action == "hide" {
            NSRunningApplication(processIdentifier: pid)?.hide()
            return
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
            guard SpaceHelper.performWindowAction(.close, on: axWindow) else {
                throw SpaceAPIError.operationFailed("Window does not expose a close action.")
            }
        case "minimize", "restore":
            let accessibilityAction: SpaceHelper.WindowAccessibilityAction =
                action == "minimize" ? .minimize : .restore
            guard SpaceHelper.performWindowAction(accessibilityAction, on: axWindow) else {
                throw SpaceAPIError.operationFailed("Window visibility action failed.")
            }
        case "enterFullScreen", "exitFullScreen":
            let accessibilityAction: SpaceHelper.WindowAccessibilityAction =
                action == "enterFullScreen" ? .enterFullScreen : .exitFullScreen
            guard SpaceHelper.performWindowAction(accessibilityAction, on: axWindow) else {
                throw SpaceAPIError.operationFailed("Window full-screen action failed.")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        default:
            throw SpaceAPIError.invalidArgument("Unsupported window action: \(action)")
        }
    }

    private func fetchWindowsForAPI(spaces: [DesktopSpace], names: [String: String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
                continuation.resume(returning: result)
            }
        }
    }

    private func fetchWindowSnapshots(spaces: [DesktopSpace], names: [String: String]) async -> [SpaceWindowSnapshot] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SpaceHelper.getWindowSnapshots(spaces: spaces, spaceNames: names)
                continuation.resume(returning: result)
            }
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
        let requestID = userInfo["requestID"] as? String ?? UUID().uuidString
        let command = userInfo["command"] as? String ?? ""
        let arguments: [String: String]
        if let argumentsJSON = userInfo["argumentsJSON"] as? String,
           let data = argumentsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            arguments = decoded
        } else {
            arguments = userInfo["arguments"] as? [String: String] ?? [:]
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard SpaceManager.isAPIEnabled else {
                self.postCommandResult(requestID: requestID, error: SpaceAPIError.apiDisabled.localizedDescription)
                return
            }
            do {
                let result = try await self.executeCommand(command, arguments: arguments)
                self.postCommandResult(requestID: requestID, result: result)
            } catch {
                self.postCommandResult(requestID: requestID, error: error.localizedDescription)
            }
        }
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
