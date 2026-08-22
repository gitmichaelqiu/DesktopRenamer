import Foundation
import AppKit
import SwiftUI

enum DesktopRearrangementDirection {
    case up
    case down
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
    @Published var spaceBarQuery: String = "" {
        didSet {
            selectedSpaceIndex = 0
            isKeyboardSelection = true
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
    @Published private(set) var isRearrangingSpace: Bool = false
    var rearrangementRecoveryWorkItem: DispatchWorkItem?
    
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

    var filteredDisplaySpaces: [DesktopSpace] {
        guard let manager = AppDelegate.shared.spaceManager else { return [] }
        guard !spaceBarQuery.isEmpty else { return manager.currentDisplaySpaces }

        return manager.currentDisplaySpaces.filter { space in
            manager.getSpaceName(space.id).localizedCaseInsensitiveContains(spaceBarQuery)
        }
    }
    
    var onClose: (() -> Void)?

    var terminatingApplicationPIDs = Set<Int32>()
    
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
}
