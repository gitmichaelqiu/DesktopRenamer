import Foundation
import AppKit
import SwiftUI

struct SpaceGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let num: Int
    let isFullscreen: Bool
    let appPath: String?
    
    // Caching transformed string for performance
    let pinyinName: String
    let pinyinDisplayName: String
    
    init(id: String, name: String, displayName: String, num: Int, isFullscreen: Bool, appPath: String? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.num = num
        self.isFullscreen = isFullscreen
        self.appPath = appPath
        
        let mutableName = NSMutableString(string: name)
        CFStringTransform(mutableName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinName = (mutableName as String).lowercased().replacingOccurrences(of: " ", with: "")
        
        let mutableDisplayName = NSMutableString(string: displayName)
        CFStringTransform(mutableDisplayName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableDisplayName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinDisplayName = (mutableDisplayName as String).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

struct WindowEntry: Identifiable, Equatable {
    let id: Int // WindowID
    let pid: Int32
    let ownerName: String
    let appPath: String
    let title: String
    let space: SpaceGroup
    let isMinimized: Bool
    let isHidden: Bool

    // Caching transformed string for performance
    let pinyinTitle: String
    let pinyinOwnerName: String

    init(id: Int, pid: Int32, ownerName: String, appPath: String, title: String, space: SpaceGroup, isMinimized: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.pid = pid
        self.ownerName = ownerName
        self.appPath = appPath
        self.title = title
        self.space = space
        self.isMinimized = isMinimized
        self.isHidden = isHidden

        let mutableTitle = NSMutableString(string: title)
        CFStringTransform(mutableTitle, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableTitle, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinTitle = (mutableTitle as String).lowercased().replacingOccurrences(of: " ", with: "")
        
        let mutableOwnerName = NSMutableString(string: ownerName)
        CFStringTransform(mutableOwnerName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableOwnerName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinOwnerName = (mutableOwnerName as String).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

enum BatchStagedActionType: Equatable {
    case move(targetSpace: SpaceGroup)
    case close
    case minimize
    case hide
    case enterFullScreen
    case exitFullScreen
    case quit
    case restore
    case restoreTo(targetSpace: SpaceGroup)
    
    var description: String {
        switch self {
        case .move(let space):
            return "→ \(space.name)"
        case .close:
            return "→ Close"
        case .minimize:
            return "→ Minimize"
        case .hide:
            return "→ Hide"
        case .enterFullScreen:
            return "→ Enter Full Screen"
        case .exitFullScreen:
            return "→ Exit Full Screen"
        case .quit:
            return "→ Quit"
        case .restore:
            return "→ Restore"
        case .restoreTo(let space):
            return "→ Restore to \(space.name)"
        }
    }
}

struct BatchStagedAction: Equatable {
    let window: WindowEntry
    let actionType: BatchStagedActionType
}

enum BatchMoveItem: Identifiable, Equatable {
    case staged(action: BatchStagedAction, index: Int)
    case unstaged(window: WindowEntry, index: Int)
    
    var id: String {
        switch self {
        case .staged(let action, _):
            return "staged_\(action.window.id)"
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

struct ListWindowsItem: Identifiable, Equatable {
    let window: WindowEntry
    let index: Int
    
    var id: String { "list_window_\(window.id)" }
    
    static func == (lhs: ListWindowsItem, rhs: ListWindowsItem) -> Bool {
        return lhs.window.id == rhs.window.id && lhs.index == rhs.index
    }
}

struct ListWindowsSection: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let items: [ListWindowsItem]
}

@MainActor class LauncherViewModel: ObservableObject {
    @AppStorage("com.michaelqiu.desktoprenamer.automaticallyRankCommands") var automaticallyRankCommands: Bool = true
    @AppStorage("com.michaelqiu.desktoprenamer.launcherManualCommandOrder") var launcherManualCommandOrder: String = ""

    var manualCommandOrder: [String] {
        if launcherManualCommandOrder.isEmpty {
            return allCommands.map { $0.id }
        }
        let storedIds = launcherManualCommandOrder.components(separatedBy: ",")
        var order = storedIds.filter { id in allCommands.contains(where: { $0.id == id }) }
        for cmd in allCommands {
            if !order.contains(cmd.id) {
                order.append(cmd.id)
            }
        }
        return order
    }

    func moveCommand(at index: Int, direction: Int) {
        var order = manualCommandOrder
        let targetIndex = index + direction
        guard targetIndex >= 0 && targetIndex < order.count else { return }
        order.swapAt(index, targetIndex)
        launcherManualCommandOrder = order.joined(separator: ",")
        objectWillChange.send()
    }

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
    @Published var stagedMoves: [Int: BatchStagedAction] = [:]
    @Published var stagingWindow: WindowEntry? = nil {
        didSet {
            searchQuery = ""
            selectedRowIndex = 0
            isKeyboardSelection = true
            isBottomBarFocused = false
        }
    }
    @Published var isExecutingBatchMove: Bool = false
    
    // Command K Panel Overlay State
    @Published var commandKTargetWindow: WindowEntry? = nil {
        didSet {
            if commandKTargetWindow != nil {
                commandKSelectedIndex = 0
            }
        }
    }
    @Published var commandKSelectedIndex: Int = 0
    @Published var isStagingForRestoreTo: Bool = false
    @Published var isExecutingRestoreToImmediately: Bool = false
    
    // Captured active window before launcher gains focus
    @Published var previouslyActiveWindow: (id: Int, pid: Int32, frame: CGRect)? = nil
    
    // For space renaming
    @Published var renameInputText: String = ""
    var batchMoveLastSelectedIndex: Int = 0
    
    var onClose: (() -> Void)?
    
    let allCommands: [LauncherCommand] = [
        LauncherCommand(type: .switchToDesktop, title: NSLocalizedString("Switch Desktop", comment: ""), subtitle: NSLocalizedString("Select a desktop to switch to", comment: ""), iconName: "desktopcomputer", hasSubpage: true),
        LauncherCommand(type: .moveWindow, title: NSLocalizedString("Move Window", comment: ""), subtitle: NSLocalizedString("Move the active window to a selected space", comment: ""), iconName: "macwindow.and.cursorarrow", hasSubpage: true),
        LauncherCommand(type: .listWindows, title: NSLocalizedString("List Windows", comment: ""), subtitle: NSLocalizedString("Search and manage open application windows", comment: ""), iconName: "macwindow", hasSubpage: true),
        LauncherCommand(type: .batchMoveWindows, title: NSLocalizedString("Manage Windows", comment: ""), subtitle: NSLocalizedString("Stage and execute window operations across desktops", comment: ""), iconName: "macwindow.on.rectangle", hasSubpage: true),
        LauncherCommand(type: .renameCurrentSpace, title: NSLocalizedString("Rename Current Space", comment: ""), subtitle: NSLocalizedString("Rename the current space to a new label", comment: ""), iconName: "pencil", hasSubpage: true),
        LauncherCommand(type: .reloadLabels, title: NSLocalizedString("Reload Space Labels", comment: ""), subtitle: NSLocalizedString("Force refresh all space name labels on displays", comment: ""), iconName: "arrow.clockwise", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabel, title: NSLocalizedString("Toggle Active Space Label", comment: ""), subtitle: NSLocalizedString("Show or hide the active space label overlay", comment: ""), iconName: "rectangle.inset.filled.and.cursorarrow", hasSubpage: false),
        LauncherCommand(type: .togglePreviewLabel, title: NSLocalizedString("Toggle Preview Space Label", comment: ""), subtitle: NSLocalizedString("Show or hide the preview space labels overlay", comment: ""), iconName: "appwindow.swipe.rectangle", hasSubpage: false),
        LauncherCommand(type: .toggleActiveLabelVisibility, title: NSLocalizedString("Toggle Active Space Label Visibility", comment: ""), subtitle: NSLocalizedString("Pin space label on desktop or hide on apps", comment: ""), iconName: "eye", hasSubpage: false)
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

    /// Checks whether `query` matches `target` and its cached `pinyin`, supporting pinyin input for CJK-localized strings.
    /// e.g. typing "qiehuan" or "qie huan" matches "切换桌面" (pinyin: qie huan zhuo mian).
    private func matchesQuery(_ query: String, target: String, pinyin: String) -> Bool {
        let lowerQuery = query.lowercased()
        if target.lowercased().contains(lowerQuery) { return true }
        let squashedQuery = lowerQuery.replacingOccurrences(of: " ", with: "")
        return pinyin.contains(squashedQuery)
    }

    private func sortCommands(_ commands: [LauncherCommand]) -> [LauncherCommand] {
        let order = manualCommandOrder
        if automaticallyRankCommands {
            return commands.sorted {
                let freqA = getCommandFrequency($0.id)
                let freqB = getCommandFrequency($1.id)
                if freqA != freqB {
                    return freqA > freqB
                }
                let idxA = order.firstIndex(of: $0.id) ?? Int.max
                let idxB = order.firstIndex(of: $1.id) ?? Int.max
                return idxA < idxB
            }
        } else {
            return commands.sorted {
                let idxA = order.firstIndex(of: $0.id) ?? Int.max
                let idxB = order.firstIndex(of: $1.id) ?? Int.max
                return idxA < idxB
            }
        }
    }

    var filteredCommands: [LauncherCommand] {
        if searchQuery.isEmpty {
            return sortCommands(allCommands)
        } else {
            let query = searchQuery.lowercased()
            let filtered = allCommands.filter {
                matchesQuery(query, target: $0.title, pinyin: $0.pinyinTitle) ||
                matchesQuery(query, target: $0.subtitle, pinyin: $0.pinyinSubtitle)
            }
            return sortCommands(filtered)
        }
    }
    
    var filteredSpaces: [SpaceGroup] {
        var spaces = currentSpaces
        if let staging = stagingWindow {
            spaces = spaces.filter { $0.id != staging.space.id && !$0.isFullscreen }
        } else if activeCommand?.type == .moveWindow {
            spaces = spaces.filter { !$0.isFullscreen }
        }

        if searchQuery.isEmpty {
            return spaces
        } else {
            let query = searchQuery.lowercased()
            return spaces.filter {
                matchesQuery(query, target: $0.name, pinyin: $0.pinyinName) ||
                matchesQuery(query, target: $0.displayName, pinyin: $0.pinyinDisplayName) ||
                "\($0.num)".contains(query)
            }
        }
    }
    
    var filteredStagedActions: [BatchStagedAction] {
        let allStaged = stagedMoves.values.sorted { $0.window.title < $1.window.title }
        if searchQuery.isEmpty {
            return allStaged
        } else {
            let query = searchQuery.lowercased()
            return allStaged.filter {
                matchesQuery(query, target: $0.window.title, pinyin: $0.window.pinyinTitle) ||
                matchesQuery(query, target: $0.window.ownerName, pinyin: $0.window.pinyinOwnerName) ||
                matchesQuery(query, target: $0.window.space.name, pinyin: $0.window.space.pinyinName)
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
                matchesQuery(query, target: $0.title, pinyin: $0.pinyinTitle) ||
                matchesQuery(query, target: $0.ownerName, pinyin: $0.pinyinOwnerName) ||
                matchesQuery(query, target: $0.space.name, pinyin: $0.space.pinyinName)
            }
        }
    }
    
    var batchMoveSelectableItems: [BatchMoveItem] {
        var items: [BatchMoveItem] = []
        
        // 1. Staged items
        let staged = filteredStagedActions
        for (idx, action) in staged.enumerated() {
            items.append(.staged(action: action, index: idx))
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
                title: String(localized: "Staged Moves (Pending)"),
                subtitle: String(format: String(localized: "%lld items"), stagedItems.count),
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
                    subtitle: String(format: String(localized: "%lld windows"), spaceItems.count),
                    items: spaceItems
                ))
            }
        }
        
        return sections
    }
    
    func isWindowMinimizedOrAppHidden(_ window: WindowEntry) -> (minimized: Bool, hidden: Bool) {
        var isMin = false
        var isHid = false
        
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            isHid = app.isHidden
        }
        
        if let axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid) {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let isMinimized = minimizedRef as? Bool {
                isMin = isMinimized
            }
        }
        
        return (minimized: isMin, hidden: isHid)
    }
    
    func getAvailableCommandKActions(for window: WindowEntry) -> [BatchStagedActionType] {
        let (minimized, hidden) = isWindowMinimizedOrAppHidden(window)
        let isFS = window.space.isFullscreen
        let fullscreenAction: BatchStagedActionType = isFS ? .exitFullScreen : .enterFullScreen
        
        var actions: [BatchStagedActionType] = []
        actions.append(.close)
        if minimized || hidden {
            actions.append(.restore)
        }
        if !minimized {
            actions.append(.minimize)
        }
        if !hidden {
            actions.append(.hide)
        }
        actions.append(fullscreenAction)
        actions.append(.quit)
        
        return actions
    }
    
    var commandKActions: [BatchStagedActionType] {
        guard let window = commandKTargetWindow else { return [] }
        return getAvailableCommandKActions(for: window)
    }
    
    func showCommandKPanel() {
        if activeCommand?.type == .listWindows {
            let windows = filteredWindows
            let index = selectedRowIndex
            guard index >= 0 && index < windows.count else { return }
            commandKTargetWindow = windows[index]
            commandKSelectedIndex = 0
        } else {
            let items = batchMoveSelectableItems
            let index = selectedRowIndex
            guard index >= 0 && index < items.count else { return }
            let selectedItem = items[index]
            
            switch selectedItem {
            case .staged:
                return
            case .unstaged(let window, _):
                commandKTargetWindow = window
                commandKSelectedIndex = 0
            }
        }
    }
    
    func selectPreviousCommandKAction() {
        let count = commandKActions.count
        if count > 0 {
            commandKSelectedIndex = (commandKSelectedIndex - 1 + count) % count
        }
    }
    
    func selectNextCommandKAction() {
        let count = commandKActions.count
        if count > 0 {
            commandKSelectedIndex = (commandKSelectedIndex + 1) % count
        }
    }
    
    func executeCommandKAction() {
        guard let window = commandKTargetWindow else { return }
        let available = commandKActions
        guard commandKSelectedIndex >= 0 && commandKSelectedIndex < available.count else { return }
        let action = available[commandKSelectedIndex]
        
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeCommandKAction: window=\(window.title) (id=\(window.id)), action=\(action.description)")
        commandKTargetWindow = nil
        if activeCommand?.type == .listWindows {
            executeActionImmediately(window: window, actionType: action)
        } else {
            stagedMoves[window.id] = BatchStagedAction(window: window, actionType: action)
        }
    }
    
    func executeActionImmediately(window: WindowEntry, actionType: BatchStagedActionType) {
        let originalSpaceUUID = AppDelegate.shared.spaceManager?.currentSpaceUUID
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: window=\(window.title) (id=\(window.id)), actionType=\(actionType.description), originalSpaceUUID=\(originalSpaceUUID ?? "nil")")
        
        Task {
            let windowSpaceID = window.space.id
            let isFullscreenWindow = window.space.isFullscreen
            let requiresAX = (actionType == .close || actionType == .minimize || actionType == .enterFullScreen || actionType == .exitFullScreen || actionType == .restore || (actionType == .hide && isFullscreenWindow))
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: Task started. requiresAX=\(requiresAX), isFullscreenWindow=\(isFullscreenWindow)")
            
            // If the target window is on a different space, switch to its space first so AX APIs can access it.
            if requiresAX,
               let manager = AppDelegate.shared.spaceManager,
               manager.currentSpaceUUID != windowSpaceID,
               let spaceObj = manager.spaceNameDict.first(where: { $0.id == windowSpaceID }) {
                manager.switchToSpace(spaceObj, forceInstant: true)
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
            }
            
            // Un-fullscreen first if the window is currently fullscreen and the action requires it
            if isFullscreenWindow && (actionType == .close || actionType == .minimize || actionType == .hide) {
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                }
            }
            
            switch actionType {
            case .close:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    var closeButtonRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(targetAXWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                       let closeButton = closeButtonRef,
                       CFGetTypeID(closeButton) == AXUIElementGetTypeID() {
                        AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
                    }
                }
            case .minimize:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                }
            case .hide:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.hide()
                }
            case .enterFullScreen:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, true as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            case .exitFullScreen:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            case .quit:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.terminate()
                }
            case .restore:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.unhide()
                }
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
            case .restoreTo(let space):
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.unhide()
                }
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s restore settle
                
                if window.space.id != space.id {
                    // Focus the window
                    SpaceHelper.focusWindow(id: window.id, pid: window.pid)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    
                    // Un-fullscreen first if the window is currently in a fullscreen space
                    if window.space.isFullscreen {
                        var axFSWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                        if axFSWindow == nil {
                            if let app = NSRunningApplication(processIdentifier: window.pid) {
                                app.activate(options: .activateIgnoringOtherApps)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                axFSWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                            }
                        }
                        if let targetAXFSWindow = axFSWindow {
                            AXUIElementSetAttributeValue(targetAXFSWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                        }
                    }
                    
                    if let manager = AppDelegate.shared.spaceManager {
                        manager.moveActiveWindowToSpace(id: space.id)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            case .move(let space):
                if window.space.id != space.id {
                    // Focus the window
                    SpaceHelper.focusWindow(id: window.id, pid: window.pid)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    
                    // Un-fullscreen first if the window is currently in a fullscreen space
                    if window.space.isFullscreen {
                        var axFSWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                        if axFSWindow == nil {
                            if let app = NSRunningApplication(processIdentifier: window.pid) {
                                app.activate(options: .activateIgnoringOtherApps)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                axFSWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                            }
                        }
                        if let targetAXFSWindow = axFSWindow {
                            AXUIElementSetAttributeValue(targetAXFSWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                        }
                    }
                    
                    if let manager = AppDelegate.shared.spaceManager {
                        manager.moveActiveWindowToSpace(id: space.id)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            default:
                break
            }
            
            // Return to original space
            if let originalUUID = originalSpaceUUID,
               let manager = AppDelegate.shared.spaceManager,
               manager.returnToOriginalAfterBatchMove {
                if manager.currentSpaceUUID != originalUUID,
                   let targetSpace = manager.spaceNameDict.first(where: { $0.id == originalUUID }) {
                    manager.switchToSpace(targetSpace, forceInstant: true)
                }
            }
            
            await MainActor.run {
                self.loadData()
            }
        }
    }

    var filteredWindows: [WindowEntry] {
        if searchQuery.isEmpty {
            return currentWindows
        } else {
            let query = searchQuery.lowercased()
            return currentWindows.filter {
                matchesQuery(query, target: $0.title, pinyin: $0.pinyinTitle) ||
                matchesQuery(query, target: $0.ownerName, pinyin: $0.pinyinOwnerName) ||
                matchesQuery(query, target: $0.space.name, pinyin: $0.space.pinyinName)
            }
        }
    }
    
    var selectedWindowForListWindows: WindowEntry? {
        let windows = filteredWindows
        let index = selectedRowIndex
        guard index >= 0 && index < windows.count else { return nil }
        return windows[index]
    }
    
    var listWindowsSections: [ListWindowsSection] {
        var sections: [ListWindowsSection] = []
        let windows = filteredWindows
        
        var windowToGlobalIndex: [Int: Int] = [:]
        for (idx, w) in windows.enumerated() {
            windowToGlobalIndex[w.id] = idx
        }
        
        for space in currentSpaces {
            let spaceWindows = windows.filter { $0.space.id == space.id }
            if spaceWindows.isEmpty { continue }
            
            let items = spaceWindows.map { w in
                ListWindowsItem(window: w, index: windowToGlobalIndex[w.id] ?? 0)
            }
            
            sections.append(ListWindowsSection(
                title: space.name,
                subtitle: String(format: space.isFullscreen ? String(localized: "Fullscreen") : String(localized: "%lld windows"), items.count),
                items: items
            ))
        }
        return sections
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
        var names: [String: String] = [:]
        for s in spaces {
            names[s.id] = manager.getSpaceName(s.id)
        }
        
        self.currentSpaces = spaces.map { space in
            SpaceGroup(
                id: space.id,
                name: names[space.id] ?? "",
                displayName: getDisplayName(for: space.displayID),
                num: space.num,
                isFullscreen: space.isFullscreen,
                appPath: space.appPath
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
            
            let raw = SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
            let parsed = Self.parseWindowData(raw)
            
            DispatchQueue.main.async {
                self.currentWindows = parsed.windows
                self.isLoadingData = false
            }
        }
    }
    
    func getDisplayName(for uuidString: String) -> String {
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
                    let isFS = parts.count >= 5 ? (parts[4] == "1") : false
                    let appPath = (parts.count >= 6 && !parts[5].isEmpty) ? parts[5] : nil
                    let space = SpaceGroup(
                        id: parts[0],
                        name: parts[1].isEmpty ? "Space \(parts[3])" : parts[1],
                        displayName: parts[2],
                        num: Int(parts[3]) ?? 0,
                        isFullscreen: isFS,
                        appPath: appPath
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
                        // New 7-field format: wid|pid|owner|appPath|title...|isMinimized|isHidden
                        // Legacy 5-field format: wid|pid|owner|appPath|title
                        let title: String
                        let isMinimized: Bool
                        let isHidden: Bool
                        if parts.count >= 7 {
                            title = parts[4..<(parts.count - 2)].joined(separator: "|")
                            isMinimized = parts[parts.count - 2] == "1"
                            isHidden = parts[parts.count - 1] == "1"
                        } else {
                            title = parts[4...].joined(separator: "|")
                            isMinimized = false
                            isHidden = false
                        }
                        let entry = WindowEntry(
                            id: wid,
                            pid: pid,
                            ownerName: ownerName,
                            appPath: appPath,
                            title: title,
                            space: space,
                            isMinimized: isMinimized,
                            isHidden: isHidden
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
                
                let (minimized, hidden) = isWindowMinimizedOrAppHidden(staging)
                let actionType: BatchStagedActionType = (minimized || hidden) ? .restoreTo(targetSpace: space) : .move(targetSpace: space)
                
                if isExecutingRestoreToImmediately {
                    isExecutingRestoreToImmediately = false
                    executeActionImmediately(window: staging, actionType: actionType)
                } else {
                    stagedMoves[staging.id] = BatchStagedAction(window: staging, actionType: actionType)
                }
                
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
                case .staged(let action, _):
                    stagedMoves.removeValue(forKey: action.window.id)
                    if selectedRowIndex >= batchMoveSelectableItems.count {
                        selectedRowIndex = max(0, batchMoveSelectableItems.count - 1)
                    }
                case .unstaged(let window, _):
                    batchMoveLastSelectedIndex = selectedRowIndex
                    isStagingForRestoreTo = false
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
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSimpleCommand: \(type.rawValue)")
        switch type {
        case .reloadLabels:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.reloadAllWindows()
            }
            closeLauncher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                HUDWindowController.shared.show(
                    message: NSLocalizedString("Space Labels Reloaded", comment: ""),
                    systemImage: "arrow.clockwise.circle.fill",
                    iconColor: .blue
                )
            }

        case .toggleActiveLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showActiveLabels.toggle()
                let isEnabled = labelManager.showActiveLabels
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Active Space Label: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        case .togglePreviewLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showPreviewLabels.toggle()
                let isEnabled = labelManager.showPreviewLabels
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Preview Space Labels: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        case .toggleActiveLabelVisibility:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showOnDesktop.toggle()
                let isEnabled = labelManager.showOnDesktop
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Keep visible on desktop: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        default:
            break
        }
    }
    
    func executeSwitchToDesktop(_ space: SpaceGroup) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToDesktop: space=\(space.name) (id=\(space.id))")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == space.id }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeSwitchToSpaceID(_ spaceID: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToSpaceID: spaceID=\(spaceID)")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeMoveWindow(_ space: SpaceGroup) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeMoveWindow: space=\(space.name) (id=\(space.id))")
        incrementCommandFrequency(LauncherCommandType.moveWindow.rawValue)
        let handled = movePreviouslyActiveWindow(toSpaceID: space.id)
        if !handled {
            closeLauncher()
        }
    }
    
    @discardableResult
    func movePreviouslyActiveWindow(toSpaceID spaceID: String) -> Bool {
        guard let prevWindow = previouslyActiveWindow else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: previouslyActiveWindow is nil")
            return false
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: prevWindow.frame) ?? ""
        let fromSpaceIDStr = SpaceHelper.getCurrentSpaceID(for: displayID) ?? "0"
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: window=\(prevWindow.id), fromSpace=\(fromSpaceIDStr), targetSpace=\(spaceID)")
        
        if spaceID == fromSpaceIDStr {
            print("Launcher: Window \(prevWindow.id) is already on space \(spaceID). No move needed.")
            return false
        }
        
        let fromSpaceID = Int(fromSpaceIDStr) ?? 0
        let targetSpaceID = Int(spaceID) ?? 0
        
        guard let manager = AppDelegate.shared.spaceManager,
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: targetSpace object not found for ID \(spaceID)")
            return false
        }
        
        if targetSpace.displayID != displayID {
            // Cross-monitor move
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: Cross-monitor move window \(prevWindow.id) from space \(fromSpaceID) to space \(targetSpaceID)")
            print("Launcher: Cross-monitor move window \(prevWindow.id) from space \(fromSpaceID) to space \(targetSpaceID)")
            SpaceHelper.moveWindowToSpace(windowID: prevWindow.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
            manager.switchToSpace(targetSpace, forceInstant: true)
            return false
        } else {
            // Same-monitor move: MUST use dragActiveWindow!
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: Same-monitor move window \(prevWindow.id) from space \(fromSpaceID) to space \(targetSpaceID) using dragActiveWindow")
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
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeFocusWindow: window=\(window.title) (id=\(window.id), pid=\(window.pid))")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.listWindows.rawValue)
        SpaceHelper.focusWindow(id: window.id, pid: window.pid)
        closeLauncher()
    }
    
    func executeRenameCurrentSpace(_ newName: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeRenameCurrentSpace: newName=\(newName)")
        incrementCommandFrequency(LauncherCommandType.renameCurrentSpace.rawValue)
        if let manager = AppDelegate.shared.spaceManager {
            manager.renameSpace(manager.currentSpaceUUID, to: newName)
        }
        closeLauncher()
    }

    func showRenameDialog(for space: SpaceGroup) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Space")
        alert.informativeText = String(localized: "Enter a new name for \"\(space.name)\":")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = space.name
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty, let manager = AppDelegate.shared.spaceManager {
                manager.renameSpace(space.id, to: newName)
            }
        }
    }

    
    func executeBatchMove() {
        guard !stagedMoves.isEmpty else { return }
        isExecutingBatchMove = true
        incrementCommandFrequency(LauncherCommandType.batchMoveWindows.rawValue)
        
        let actions = Array(stagedMoves.values)
        let originalSpaceUUID = AppDelegate.shared.spaceManager?.currentSpaceUUID
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Starting batch move. Actions count=\(actions.count), originalSpaceUUID=\(originalSpaceUUID ?? "nil")")
        
        Task {
            // 1. Filter space-move actions
            let spaceMoveActions = actions.filter {
                switch $0.actionType {
                case .move, .restoreTo: return true
                default: return false
                }
            }
            
            // 2. Filter static actions
            let staticActions = actions.filter {
                switch $0.actionType {
                case .move, .restoreTo: return false
                default: return true
                }
            }
            
            // 3. Execute space moves grouped by source space
            if !spaceMoveActions.isEmpty {
                let movesBySource = Dictionary(grouping: spaceMoveActions, by: { $0.window.space.id })
                
                for (sourceId, sourceActions) in movesBySource {
                    DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Group sourceID=\(sourceId), sourceActions count=\(sourceActions.count)")
                    if let manager = AppDelegate.shared.spaceManager,
                       let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                        manager.switchToSpace(spaceObj, forceInstant: true)
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
                    
                    for (index, action) in sourceActions.enumerated() {
                        let targetSpaceID: String
                        
                        switch action.actionType {
                        case .move(let space):
                            targetSpaceID = space.id
                        case .restoreTo(let space):
                            targetSpaceID = space.id
                            // Contextual Restore: unhide app and/or unminimize window first
                            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Restore context for window id=\(action.window.id) pid=\(action.window.pid)")
                            if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                                app.unhide()
                            }
                            if let axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid) {
                                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                            }
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s restore settle
                        default:
                            continue
                        }
                        
                        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Move window id=\(action.window.id) from space=\(action.window.space.id) to space=\(targetSpaceID)")
                        if action.window.space.id == targetSpaceID {
                            continue
                        }
                        
                        // Focus the targeted window first
                        SpaceHelper.focusWindow(id: action.window.id, pid: action.window.pid)
                        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s focus settle
                        
                        // Un-fullscreen first if the window is currently in a fullscreen space
                        if action.window.space.isFullscreen {
                            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Un-fullscreen window id=\(action.window.id)")
                            var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                            if axWindow == nil {
                                if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                                    app.activate(options: .activateIgnoringOtherApps)
                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                    axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                                }
                            }
                            if let targetAXWindow = axWindow {
                                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                                try? await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                            }
                        }
                        
                        if let manager = AppDelegate.shared.spaceManager {
                            manager.moveActiveWindowToSpace(id: targetSpaceID)
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s movement settle
                        
                        // Switch back to source space
                        if index < sourceActions.count - 1 {
                            if let manager = AppDelegate.shared.spaceManager,
                               let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                                manager.switchToSpace(spaceObj, forceInstant: true)
                            }
                            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s switch settle
                        }
                    }
                }
            }
            
            // 4. Execute other actions (Close, Minimize, Hide, Fullscreen, Quit, Restore)
            for action in staticActions {
                let windowSpaceID = action.window.space.id
                let isFullscreenWindow = action.window.space.isFullscreen
                let requiresAX = (action.actionType == .close || action.actionType == .minimize || action.actionType == .enterFullScreen || action.actionType == .exitFullScreen || action.actionType == .restore || (action.actionType == .hide && isFullscreenWindow))
                
                DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Static action: type=\(action.actionType.description), window id=\(action.window.id), app=\(action.window.ownerName), requiresAX=\(requiresAX)")
                
                // If the target window is on a different space, switch to its space first so AX APIs can access it.
                if requiresAX,
                   let manager = AppDelegate.shared.spaceManager,
                   manager.currentSpaceUUID != windowSpaceID,
                   let spaceObj = manager.spaceNameDict.first(where: { $0.id == windowSpaceID }) {
                    manager.switchToSpace(spaceObj, forceInstant: true)
                    try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
                }
                
                // Un-fullscreen first if the window is currently fullscreen and the action requires it
                if isFullscreenWindow && (action.actionType == .close || action.actionType == .minimize || action.actionType == .hide) {
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                        try? await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                    }
                }
                
                switch action.actionType {
                case .close:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        var closeButtonRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(targetAXWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                           let closeButton = closeButtonRef {
                            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
                        }
                    }
                case .minimize:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                    }
                case .hide:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.hide()
                    }
                case .enterFullScreen:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, true as CFTypeRef)
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .exitFullScreen:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .quit:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.terminate()
                    }
                case .restore:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.unhide()
                    }
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                    }
                default:
                    break
                }
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms delay between commands
            }
            
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Finished batch move execution.")
            self.isExecutingBatchMove = false
            self.stagedMoves.removeAll()
            LauncherWindowController.shared.shouldRestoreFocus = false
            
            if let manager = AppDelegate.shared.spaceManager {
                if manager.returnToOriginalAfterBatchMove {
                    if let originalUUID = originalSpaceUUID,
                       let targetSpace = manager.spaceNameDict.first(where: { $0.id == originalUUID }) {
                        manager.switchToSpace(targetSpace, forceInstant: true)
                    }
                } else if let lastMoveAction = spaceMoveActions.last {
                    let lastTargetSpaceID: String
                    switch lastMoveAction.actionType {
                    case .move(let space), .restoreTo(let space):
                        lastTargetSpaceID = space.id
                    default:
                        lastTargetSpaceID = ""
                    }
                    if !lastTargetSpaceID.isEmpty,
                       let targetSpace = manager.spaceNameDict.first(where: { $0.id == lastTargetSpaceID }) {
                        manager.switchToSpace(targetSpace, forceInstant: true)
                    }
                }
            }
            
            self.closeLauncher()
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
            isStagingForRestoreTo = false
            isExecutingRestoreToImmediately = false
            selectedRowIndex = batchMoveLastSelectedIndex
        } else if activeCommand != nil {
            activeCommand = nil
        } else if !searchQuery.isEmpty {
            searchQuery = ""
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
