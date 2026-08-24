import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

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
        let windowsBySpaceID = Dictionary(grouping: windows, by: \.space.id)
        
        var windowToGlobalIndex: [Int: Int] = [:]
        for (idx, w) in windows.enumerated() {
            windowToGlobalIndex[w.id] = idx
        }
        
        for space in currentSpaces {
            let spaceWindows = windowsBySpaceID[space.id] ?? []
            if spaceWindows.isEmpty { continue }
            
            let items = spaceWindows.map { w in
                ListWindowsItem(window: w, index: windowToGlobalIndex[w.id] ?? 0)
            }
            
            sections.append(ListWindowsSection(
                id: "space_\(SpaceReconciliationSupport.normalizedDisplayID(space.displayID))_\(space.id)",
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
        let loadGeneration = windowLoadGeneration.begin()
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
                displayID: space.displayID,
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
            
            let snapshots = SpaceHelper.getWindowSnapshots(spaces: spaces, spaceNames: names)
            let parsed = Self.makeWindowData(from: snapshots)
            
            DispatchQueue.main.async {
                guard self.windowLoadGeneration.accepts(loadGeneration) else { return }

                let terminatingPIDs = self.terminatingApplicationPIDs
                self.currentWindows = parsed.windows.filter { !terminatingPIDs.contains($0.pid) }
                let observedPIDs = Set(parsed.windows.map(\.pid))
                self.terminatingApplicationPIDs = terminatingPIDs.filter { pid in
                    NSRunningApplication(processIdentifier: pid) != nil && observedPIDs.contains(pid)
                }
                self.isLoadingData = false
            }
        }
    }

    func removeApplicationWindowsFromList(pid: Int32) {
        terminatingApplicationPIDs.insert(pid)
        scheduleQuitRecovery(for: pid)
        currentWindows.removeAll { $0.pid == pid }
        stagedMoves = stagedMoves.filter { $0.value.window.pid != pid }
        selectedRowIndex = min(selectedRowIndex, max(filteredWindows.count - 1, 0))
    }
    
    func getDisplayName(for uuidString: String) -> String {
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            let uuidStr = CFUUIDCreateString(nil, uuid) as String
            if SpaceReconciliationSupport.normalizedDisplayID(uuidStr)
                == SpaceReconciliationSupport.normalizedDisplayID(uuidString) {
                return screen.localizedName
            }
        }
        return "Display"
    }
    
    private nonisolated static func makeWindowData(from snapshots: [SpaceWindowSnapshot]) -> (spaces: [SpaceGroup], windows: [WindowEntry]) {
        var spaces: [SpaceGroup] = []
        var windows: [WindowEntry] = []

        for snapshot in snapshots {
            let space = SpaceGroup(
                id: snapshot.id,
                name: snapshot.name.isEmpty ? "Space \(snapshot.num)" : snapshot.name,
                displayName: snapshot.displayName,
                displayID: snapshot.displayID ?? "",
                num: snapshot.num,
                isFullscreen: snapshot.isFullscreen,
                appPath: snapshot.appPath
            )
            spaces.append(space)

            windows.append(contentsOf: snapshot.windows.map { window in
                WindowEntry(
                    id: window.id,
                    pid: window.pid,
                    ownerName: window.ownerName,
                    appPath: window.appPath,
                    title: window.title,
                    space: space,
                    isMinimized: window.isMinimized,
                    isHidden: window.isHidden
                )
            })
        }

        return (spaces, windows)
    }
}
