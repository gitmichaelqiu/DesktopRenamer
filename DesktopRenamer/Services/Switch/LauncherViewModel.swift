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

enum BatchMoveItem: Identifiable, Equatable {
    case staged(move: (window: WindowEntry, targetSpace: SpaceGroup), index: Int)
    case unstaged(window: WindowEntry, index: Int)
    
    var id: String {
        switch self {
        case .staged(let move, _):
            return "staged_\(move.window.id)"
        case .unstaged(let window, _):
            return "unstaged_\(window.id)"
        }
    }
    
    var index: Int {
        switch self {
        case .staged(_, let index):
            return index
        case .unstaged(_, let index):
            return index
        }
    }
    
    static func == (lhs: BatchMoveItem, rhs: BatchMoveItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct BatchMoveSection: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let items: [BatchMoveItem]
}

@MainActor class LauncherViewModel: ObservableObject {
    @Published var searchQuery: String = "" {
        didSet {
            selectedRowIndex = 0
            isKeyboardSelection = true
            isBottomBarFocused = false
        }
    }
    @Published var selectedRowIndex: Int = 0
    @Published var activeCommand: LauncherCommand? = nil {
        willSet {
            if activeCommand?.type == .batchMoveWindows && newValue?.type != .batchMoveWindows {
                stagedMoves.removeAll()
            }
        }
        didSet {
            searchQuery = ""
            selectedRowIndex = 0
            isKeyboardSelection = true
            isBottomBarFocused = false
            if activeCommand != nil {
                loadData()
            }
        }
    }
    
    @Published var currentSpaces: [SpaceGroup] = []
    @Published var currentWindows: [WindowEntry] = []
    @Published var isLoadingData: Bool = false
    @Published var isKeyboardSelection: Bool = false
    
    @Published var showCommandNumbers: Bool = false
    @Published var isBottomBarFocused: Bool = false
    @Published var selectedSpaceIndex: Int = 0
    
    // For batch window moves
    @Published var stagedMoves: [Int: (window: WindowEntry, targetSpace: SpaceGroup)] = [:]
    @Published var stagingWindow: WindowEntry? = nil {
        didSet {
            searchQuery = ""
            selectedRowIndex = 0
            isKeyboardSelection = true
            isBottomBarFocused = false
        }
    }
    @Published var isExecutingBatchMove: Bool = false
    
    // Captured active window before launcher gains focus
    @Published var previouslyActiveWindow: (id: Int, pid: Int32, frame: CGRect)? = nil
    
    // For space renaming
    @Published var renameInputText: String = ""
    private var batchMoveLastSelectedIndex: Int = 0
    
    var onClose: (() -> Void)?
    
    let allCommands: [LauncherCommand] = [
        LauncherCommand(type: .switchToDesktop, title: NSLocalizedString("Switch Desktop", comment: ""), subtitle: NSLocalizedString("Select a desktop to switch to", comment: ""), iconName: "desktopcomputer", hasSubpage: true),
        LauncherCommand(type: .moveWindow, title: NSLocalizedString("Move Window to Desktop", comment: ""), subtitle: NSLocalizedString("Move the active window to a selected space", comment: ""), iconName: "macwindow.on.rectangle", hasSubpage: true),
        LauncherCommand(type: .listWindows, title: NSLocalizedString("Focus Window", comment: ""), subtitle: NSLocalizedString("Search and focus open application windows", comment: ""), iconName: "macwindow", hasSubpage: true),
        LauncherCommand(type: .batchMoveWindows, title: NSLocalizedString("Batch Move Windows", comment: ""), subtitle: NSLocalizedString("Select and move multiple windows to a space", comment: ""), iconName: "macwindow.badge.plus", hasSubpage: true),
        LauncherCommand(type: .renameCurrentSpace, title: NSLocalizedString("Rename Current Space", comment: ""), subtitle: NSLocalizedString("Rename the current space to a new label", comment: ""), iconName: "pencil", hasSubpage: true),
        LauncherCommand(type: .reloadLabels, title: NSLocalizedString("Reload Space Labels", comment: ""), subtitle: NSLocalizedString("Force refresh all space name labels on displays", comment: ""), iconName: "arrow.clockwise", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabel, title: NSLocalizedString("Toggle Active Space Label", comment: ""), subtitle: NSLocalizedString("Show or hide the active space label overlay", comment: ""), iconName: "switch.2", hasSubpage: false),
        LauncherCommand(type: .togglePreviewLabel, title: NSLocalizedString("Toggle Preview Space Label", comment: ""), subtitle: NSLocalizedString("Show or hide the preview space labels overlay", comment: ""), iconName: "eye", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabelVisibility, title: NSLocalizedString("Toggle Active Space Label Visibility", comment: ""), subtitle: NSLocalizedString("Pin space label on desktop or hide on apps", comment: ""), iconName: "square.dashed", hasSubpage: false)
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
        var spaces = currentSpaces
        if let staging = stagingWindow {
            spaces = spaces.filter { $0.id != staging.space.id }
        }
        
        if searchQuery.isEmpty {
            return spaces
        } else {
            let query = searchQuery.lowercased()
            return spaces.filter {
                $0.name.lowercased().contains(query) ||
                $0.displayName.lowercased().contains(query) ||
                "\($0.num)".contains(query)
            }
        }
    }
    
    var filteredStagedMoves: [(window: WindowEntry, targetSpace: SpaceGroup)] {
        let allStaged = stagedMoves.values.sorted { $0.window.title < $1.window.title }
        if searchQuery.isEmpty {
            return allStaged
        } else {
            let query = searchQuery.lowercased()
            return allStaged.filter {
                $0.window.title.lowercased().contains(query) ||
                $0.window.ownerName.lowercased().contains(query) ||
                $0.window.space.name.lowercased().contains(query)
            }
        }
    }
    
    var filteredUnstagedWindows: [WindowEntry] {
        let allUnstaged = currentWindows.filter { stagedMoves[$0.id] == nil }
        if searchQuery.isEmpty {
            return allUnstaged
        } else {
            let query = searchQuery.lowercased()
            return allUnstaged.filter {
                $0.title.lowercased().contains(query) ||
                $0.ownerName.lowercased().contains(query) ||
                $0.space.name.lowercased().contains(query)
            }
        }
    }
    
    var batchMoveSelectableItems: [BatchMoveItem] {
        var items: [BatchMoveItem] = []
        
        // 1. Staged items
        let staged = filteredStagedMoves
        for (idx, move) in staged.enumerated() {
            items.append(.staged(move: move, index: idx))
        }
        
        // 2. Unstaged items grouped by space
        let unstaged = filteredUnstagedWindows
        var itemIndex = staged.count
        for space in currentSpaces {
            let spaceWindows = unstaged.filter { $0.space.id == space.id }
            if spaceWindows.isEmpty { continue }
            for window in spaceWindows {
                items.append(.unstaged(window: window, index: itemIndex))
                itemIndex += 1
            }
        }
        
        return items
    }
    
    var batchMoveSections: [BatchMoveSection] {
        var sections: [BatchMoveSection] = []
        let selectable = batchMoveSelectableItems
        
        // Group staged
        let stagedItems = selectable.filter {
            if case .staged = $0 { return true }
            return false
        }
        if !stagedItems.isEmpty {
            sections.append(BatchMoveSection(
                title: "Staged Moves (Pending)",
                subtitle: "\(stagedItems.count) items",
                items: stagedItems
            ))
        }
        
        // Group unstaged by space
        let unstagedItems = selectable.filter {
            if case .unstaged = $0 { return true }
            return false
        }
        
        for space in currentSpaces {
            let spaceItems = unstagedItems.filter {
                if case .unstaged(let window, _) = $0, window.space.id == space.id {
                    return true
                }
                return false
            }
            if !spaceItems.isEmpty {
                sections.append(BatchMoveSection(
                    title: space.name,
                    subtitle: "\(spaceItems.count) windows",
                    items: spaceItems
                ))
            }
        }
        
        return sections
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
                return batchMoveSelectableItems.count
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
                if let mgr = AppDelegate.shared.spaceManager {
                    for s in spaces {
                        names[s.id] = mgr.getSpaceName(s.id)
                    }
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
    
    private nonisolated static func parseWindowData(_ raw: String) -> (spaces: [SpaceGroup], windows: [WindowEntry]) {
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
                selectedRowIndex = batchMoveLastSelectedIndex
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
                let items = batchMoveSelectableItems
                guard index >= 0 && index < items.count else { return }
                let selectedItem = items[index]
                
                switch selectedItem {
                case .staged(let move, _):
                    stagedMoves.removeValue(forKey: move.window.id)
                    if selectedRowIndex >= batchMoveSelectableItems.count {
                        selectedRowIndex = max(0, batchMoveSelectableItems.count - 1)
                    }
                case .unstaged(let window, _):
                    batchMoveLastSelectedIndex = selectedRowIndex
                    stagingWindow = window
                    selectedRowIndex = 0
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
            HUDWindowController.shared.show(
                message: NSLocalizedString("Space Labels Reloaded", comment: ""),
                systemImage: "arrow.clockwise.circle.fill",
                iconColor: .blue
            )
            
        case .toggleActiveLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showActiveLabels.toggle()
                let isEnabled = labelManager.showActiveLabels
                closeLauncher()
                
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Active Space Label: %@"), status)
                HUDWindowController.shared.show(
                    message: msg,
                    systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: isEnabled ? .green : .red
                )
            } else {
                closeLauncher()
            }
            
        case .togglePreviewLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showPreviewLabels.toggle()
                let isEnabled = labelManager.showPreviewLabels
                closeLauncher()
                
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Preview Space Labels: %@"), status)
                HUDWindowController.shared.show(
                    message: msg,
                    systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: isEnabled ? .green : .red
                )
            } else {
                closeLauncher()
            }
            
        case .toggleActiveLabelVisibility:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showOnDesktop.toggle()
                let isEnabled = labelManager.showOnDesktop
                closeLauncher()
                
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Keep visible on desktop: %@"), status)
                HUDWindowController.shared.show(
                    message: msg,
                    systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: isEnabled ? .green : .red
                )
            } else {
                closeLauncher()
            }
            
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
    
    func executeNthRowAction(_ index: Int) {
        guard index >= 0 && index < visibleRowsCount else { return }
        isKeyboardSelection = true
        selectedRowIndex = index
        executeRowAction()
    }
    
    func handleEscapeKey() {
        if isBottomBarFocused {
            isBottomBarFocused = false
        } else if stagingWindow != nil {
            stagingWindow = nil
            selectedRowIndex = batchMoveLastSelectedIndex
        } else if activeCommand != nil {
            activeCommand = nil
        } else {
            closeLauncher()
        }
    }
    
    func handleTabKey() {
        guard activeCommand == nil else { return }
        isBottomBarFocused.toggle()
        if isBottomBarFocused {
            if let manager = AppDelegate.shared.spaceManager {
                let spaces = manager.currentDisplaySpaces
                if let currentIndex = spaces.firstIndex(where: { $0.id == manager.currentSpaceUUID }) {
                    selectedSpaceIndex = currentIndex
                } else {
                    selectedSpaceIndex = 0
                }
            }
        }
    }
    
    func executeBottomBarSpaceAction(isOption: Bool, isCommand: Bool) {
        guard let manager = AppDelegate.shared.spaceManager else { return }
        let spaces = manager.currentDisplaySpaces
        guard selectedSpaceIndex >= 0 && selectedSpaceIndex < spaces.count else { return }
        let space = spaces[selectedSpaceIndex]
        
        if isOption || isCommand {
            let handled = movePreviouslyActiveWindow(toSpaceID: space.id)
            if !handled {
                closeLauncher()
            }
        } else {
            executeSwitchToSpaceID(space.id)
        }
    }
    
    func closeLauncher() {
        searchQuery = ""
        selectedRowIndex = 0
        activeCommand = nil
        stagingWindow = nil
        isBottomBarFocused = false
        onClose?()
    }
}
