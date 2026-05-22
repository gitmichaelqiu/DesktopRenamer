import Foundation
import AppKit
import SwiftUI

struct SpaceGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let num: Int
}

struct WindowEntry: Identifiable, Equatable {
    let id: Int // WindowID
    let pid: Int32
    let ownerName: String
    let appPath: String
    let title: String
    let space: SpaceGroup
}

@MainActor class LauncherViewModel: ObservableObject {
    @Published var searchQuery: String = "" {
        didSet {
            selectedRowIndex = 0
        }
    }
    @Published var selectedRowIndex: Int = 0
    @Published var activeCommand: LauncherCommand? = nil {
        didSet {
            searchQuery = ""
            selectedRowIndex = 0
            if activeCommand != nil {
                loadData()
            }
        }
    }
    
    @Published var currentSpaces: [SpaceGroup] = []
    @Published var currentWindows: [WindowEntry] = []
    @Published var isLoadingData: Bool = false
    
    // For batch window moves
    @Published var stagedMoves: [Int: (window: WindowEntry, targetSpace: SpaceGroup)] = [:]
    @Published var stagingWindow: WindowEntry? = nil {
        didSet {
            searchQuery = ""
            selectedRowIndex = 0
        }
    }
    @Published var isExecutingBatchMove: Bool = false
    
    // Captured active window before launcher gains focus
    @Published var previouslyActiveWindow: (id: Int, pid: Int32, frame: CGRect)? = nil
    
    // For space renaming
    @Published var renameInputText: String = ""
    
    var onClose: (() -> Void)?
    
    let allCommands: [LauncherCommand] = [
        LauncherCommand(type: .switchToDesktop, title: "Switch Desktop", subtitle: "Select a desktop to switch to", iconName: "desktopcomputer", hasSubpage: true),
        LauncherCommand(type: .moveWindow, title: "Move Window to Desktop", subtitle: "Move the active window to a selected space", iconName: "macwindow.on.rectangle", hasSubpage: true),
        LauncherCommand(type: .listWindows, title: "Focus Window", subtitle: "Search and focus open application windows", iconName: "macwindow", hasSubpage: true),
        LauncherCommand(type: .batchMoveWindows, title: "Batch Move Windows", subtitle: "Select and move multiple windows to a space", iconName: "macwindow.badge.plus", hasSubpage: true),
        LauncherCommand(type: .renameCurrentSpace, title: "Rename Current Space", subtitle: "Rename the current space to a new label", iconName: "pencil", hasSubpage: true),
        LauncherCommand(type: .reloadLabels, title: "Reload Space Labels", subtitle: "Force refresh all space name labels on displays", iconName: "arrow.clockwise", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabel, title: "Toggle Active Space Label", subtitle: "Show or hide the active space label overlay", iconName: "switch.2", hasSubpage: false),
        LauncherCommand(type: .togglePreviewLabel, title: "Toggle Preview Space Label", subtitle: "Show or hide the preview space labels overlay", iconName: "eye", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabelVisibility, title: "Toggle Active Space Label Visibility", subtitle: "Pin space label on desktop or hide on apps", iconName: "square.dashed", hasSubpage: false)
    ]
    
    func getCommandFrequency(_ id: String) -> Int {
        let frequencies = UserDefaults.standard.dictionary(forKey: "LauncherCommandFrequency") as? [String: Int] ?? [:]
        return frequencies[id] ?? 0
    }
    
    func incrementCommandFrequency(_ id: String) {
        var frequencies = UserDefaults.standard.dictionary(forKey: "LauncherCommandFrequency") as? [String: Int] ?? [:]
        frequencies[id] = (frequencies[id] ?? 0) + 1
        UserDefaults.standard.set(frequencies, forKey: "LauncherCommandFrequency")
        objectWillChange.send()
    }
    
    var filteredCommands: [LauncherCommand] {
        if searchQuery.isEmpty {
            return allCommands.sorted {
                let freqA = getCommandFrequency($0.id)
                let freqB = getCommandFrequency($1.id)
                if freqA != freqB {
                    return freqA > freqB
                }
                return $0.title < $1.title
            }
        } else {
            let query = searchQuery.lowercased()
            return allCommands.filter {
                $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
            }.sorted {
                let freqA = getCommandFrequency($0.id)
                let freqB = getCommandFrequency($1.id)
                if freqA != freqB {
                    return freqA > freqB
                }
                return $0.title < $1.title
            }
        }
    }
    
    var filteredSpaces: [SpaceGroup] {
        if searchQuery.isEmpty {
            return currentSpaces
        } else {
            let query = searchQuery.lowercased()
            return currentSpaces.filter {
                $0.name.lowercased().contains(query) ||
                $0.displayName.lowercased().contains(query) ||
                "\($0.num)".contains(query)
            }
        }
    }
    
    var filteredWindows: [WindowEntry] {
        if searchQuery.isEmpty {
            return currentWindows
        } else {
            let query = searchQuery.lowercased()
            return currentWindows.filter {
                $0.title.lowercased().contains(query) ||
                $0.ownerName.lowercased().contains(query) ||
                $0.space.name.lowercased().contains(query)
            }
        }
    }
    
    var visibleRowsCount: Int {
        if activeCommand == nil {
            return filteredCommands.count
        } else {
            if stagingWindow != nil {
                return filteredSpaces.count
            }
            switch activeCommand?.type {
            case .switchToDesktop, .moveWindow:
                return filteredSpaces.count
            case .listWindows:
                return filteredWindows.count
            case .batchMoveWindows:
                let extra = stagedMoves.isEmpty ? 0 : 1
                return extra + filteredWindows.count
            case .renameCurrentSpace:
                return 1
            default:
                return 0
            }
        }
    }
    
    func loadData() {
        guard let manager = AppDelegate.shared.spaceManager else { return }
        isLoadingData = true
        
        let spaces = manager.spaceNameDict
        self.currentSpaces = spaces.map { space in
            SpaceGroup(
                id: space.id,
                name: manager.getSpaceName(space.id),
                displayName: getDisplayName(for: space.displayID),
                num: space.num
            )
        }
        
        // If we are renaming space, pre-fill text
        if activeCommand?.type == .renameCurrentSpace {
            renameInputText = manager.getSpaceName(manager.currentSpaceUUID)
            isLoadingData = false
            return
        }
        
        // Query windows in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var names: [String: String] = [:]
            DispatchQueue.main.sync {
                for s in spaces {
                    names[s.id] = manager.getSpaceName(s.id)
                }
            }
            
            let raw = SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
            let parsed = Self.parseWindowData(raw)
            
            DispatchQueue.main.async {
                self.currentWindows = parsed.windows
                self.isLoadingData = false
            }
        }
    }
    
    private func getDisplayName(for uuidString: String) -> String {
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            let uuidStr = CFUUIDCreateString(nil, uuid) as String
            if uuidStr == uuidString {
                return screen.localizedName
            }
        }
        return "Display"
    }
    
    private static func parseWindowData(_ raw: String) -> (spaces: [SpaceGroup], windows: [WindowEntry]) {
        var spaces: [SpaceGroup] = []
        var windows: [WindowEntry] = []
        var currentSpace: SpaceGroup? = nil
        
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(">") {
                let parts = line.dropFirst().components(separatedBy: "~")
                if parts.count >= 4 {
                    let space = SpaceGroup(
                        id: parts[0],
                        name: parts[1].isEmpty ? "Space \(parts[3])" : parts[1],
                        displayName: parts[2],
                        num: Int(parts[3]) ?? 0
                    )
                    currentSpace = space
                    spaces.append(space)
                }
            } else if line.hasPrefix("  "), let space = currentSpace {
                let content = line.trimmingCharacters(in: .whitespaces)
                let parts = content.components(separatedBy: "|")
                if parts.count >= 5 {
                    if let wid = Int(parts[0]), let pid = Int32(parts[1]) {
                        let ownerName = parts[2]
                        let appPath = parts[3]
                        let title = parts[4...].joined(separator: "|")
                        let entry = WindowEntry(
                            id: wid,
                            pid: pid,
                            ownerName: ownerName,
                            appPath: appPath,
                            title: title,
                            space: space
                        )
                        windows.append(entry)
                    }
                }
            }
        }
        return (spaces, windows)
    }
    
    func executeRowAction() {
        let index = selectedRowIndex
        
        if activeCommand == nil {
            // Main menu selection
            let commands = filteredCommands
            guard index >= 0 && index < commands.count else { return }
            let command = commands[index]
            
            if command.hasSubpage {
                activeCommand = command
            } else {
                executeSimpleCommand(command.type)
            }
        } else {
            // Subpage selection
            if let staging = stagingWindow {
                // Staging a window to target space
                let spaces = filteredSpaces
                guard index >= 0 && index < spaces.count else { return }
                let space = spaces[index]
                stagedMoves[staging.id] = (window: staging, targetSpace: space)
                stagingWindow = nil
                return
            }
            
            switch activeCommand?.type {
            case .switchToDesktop:
                let spaces = filteredSpaces
                guard index >= 0 && index < spaces.count else { return }
                executeSwitchToDesktop(spaces[index])
                
            case .moveWindow:
                let spaces = filteredSpaces
                guard index >= 0 && index < spaces.count else { return }
                executeMoveWindow(spaces[index])
                
            case .listWindows:
                let windows = filteredWindows
                guard index >= 0 && index < windows.count else { return }
                executeFocusWindow(windows[index])
                
            case .batchMoveWindows:
                let hasStaged = !stagedMoves.isEmpty
                if hasStaged && index == 0 {
                    // Confirm & Execute batch move
                    executeBatchMove()
                } else {
                    // Stage this window
                    let wIndex = hasStaged ? index - 1 : index
                    let windows = filteredWindows
                    guard wIndex >= 0 && wIndex < windows.count else { return }
                    stagingWindow = windows[wIndex]
                }
                
            case .renameCurrentSpace:
                executeRenameCurrentSpace(renameInputText)
                
            default:
                break
            }
        }
    }
    
    private func executeSimpleCommand(_ type: LauncherCommandType) {
        switch type {
        case .reloadLabels:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.reloadAllWindows()
            }
            closeLauncher()
            
        case .toggleActiveLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showActiveLabels.toggle()
            }
            closeLauncher()
            
        case .togglePreviewLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showPreviewLabels.toggle()
            }
            closeLauncher()
            
        case .toggleActiveLabelVisibility:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showOnDesktop.toggle()
            }
            closeLauncher()
            
        default:
            break
        }
    }
    
    func executeSwitchToDesktop(_ space: SpaceGroup) {
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == space.id }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeSwitchToSpaceID(_ spaceID: String) {
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeMoveWindow(_ space: SpaceGroup) {
        incrementCommandFrequency(LauncherCommandType.moveWindow.rawValue)
        let handled = movePreviouslyActiveWindow(toSpaceID: space.id)
        if !handled {
            closeLauncher()
        }
    }
    
    @discardableResult
    func movePreviouslyActiveWindow(toSpaceID spaceID: String) -> Bool {
        guard let prevWindow = previouslyActiveWindow else { return false }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: prevWindow.frame) ?? ""
        let fromSpaceIDStr = SpaceHelper.getCurrentSpaceID(for: displayID) ?? "0"
        
        if spaceID == fromSpaceIDStr {
            print("Launcher: Window \(prevWindow.id) is already on space \(spaceID). No move needed.")
            return false
        }
        
        let fromSpaceID = Int(fromSpaceIDStr) ?? 0
        let targetSpaceID = Int(spaceID) ?? 0
        
        guard let manager = AppDelegate.shared.spaceManager,
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            return false
        }
        
        if targetSpace.displayID != displayID {
            // Cross-monitor move
            print("Launcher: Cross-monitor move window \(prevWindow.id) from space \(fromSpaceID) to space \(targetSpaceID)")
            SpaceHelper.moveWindowToSpace(windowID: prevWindow.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
            manager.switchToSpace(targetSpace, forceInstant: true)
            return false
        } else {
            // Same-monitor move: MUST use dragActiveWindow!
            print("Launcher: Same-monitor move window \(prevWindow.id) from space \(fromSpaceID) to space \(targetSpaceID) using dragActiveWindow")
            
            // 1. Hide the launcher so focus goes back to the window
            LauncherWindowController.shared.shouldRestoreFocus = true
            closeLauncher()
            
            // 2. Perform the drag switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                SpaceHelper.dragActiveWindow(to: spaceID, forceInstant: true)
            }
            return true
        }
    }
    
    func executeFocusWindow(_ window: WindowEntry) {
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.listWindows.rawValue)
        SpaceHelper.focusWindow(id: window.id, pid: window.pid)
        closeLauncher()
    }
    
    func executeRenameCurrentSpace(_ newName: String) {
        incrementCommandFrequency(LauncherCommandType.renameCurrentSpace.rawValue)
        if let manager = AppDelegate.shared.spaceManager {
            manager.renameSpace(manager.currentSpaceUUID, to: newName)
        }
        closeLauncher()
    }
    
    func executeBatchMove() {
        guard !stagedMoves.isEmpty else { return }
        isExecutingBatchMove = true
        incrementCommandFrequency(LauncherCommandType.batchMoveWindows.rawValue)
        
        let moves = Array(stagedMoves.values)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let movesBySource = Dictionary(grouping: moves, by: { $0.window.space.id })
            
            for (sourceId, sourceMoves) in movesBySource {
                DispatchQueue.main.sync {
                    if let manager = AppDelegate.shared.spaceManager,
                       let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                        manager.switchToSpace(spaceObj, forceInstant: true)
                    }
                }
                Thread.sleep(forTimeInterval: 0.6)
                
                for move in sourceMoves {
                    if move.window.space.id == move.targetSpace.id {
                        continue
                    }
                    DispatchQueue.main.sync {
                        SpaceHelper.focusWindow(id: move.window.id, pid: move.window.pid)
                    }
                    Thread.sleep(forTimeInterval: 0.25)
                    
                    DispatchQueue.main.sync {
                        if let manager = AppDelegate.shared.spaceManager,
                           let sourceSpace = manager.spaceNameDict.first(where: { $0.id == move.window.space.id }),
                           let targetSpace = manager.spaceNameDict.first(where: { $0.id == move.targetSpace.id }) {
                            
                            if sourceSpace.displayID != targetSpace.displayID {
                                // Cross-monitor move
                                if let fromSpaceID = Int(move.window.space.id),
                                   let targetSpaceID = Int(move.targetSpace.id) {
                                    SpaceHelper.moveWindowToSpace(windowID: move.window.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
                                }
                            } else {
                                // Same-monitor move
                                SpaceHelper.dragActiveWindow(to: move.targetSpace.id, forceInstant: true)
                            }
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            
            DispatchQueue.main.async {
                self.isExecutingBatchMove = false
                self.stagedMoves.removeAll()
                LauncherWindowController.shared.shouldRestoreFocus = false
                self.closeLauncher()
            }
        }
    }
    
    func handleEscapeKey() {
        if stagingWindow != nil {
            stagingWindow = nil
        } else if activeCommand != nil {
            activeCommand = nil
        } else {
            closeLauncher()
        }
    }
    
    func closeLauncher() {
        searchQuery = ""
        selectedRowIndex = 0
        activeCommand = nil
        stagingWindow = nil
        onClose?()
    }
}
