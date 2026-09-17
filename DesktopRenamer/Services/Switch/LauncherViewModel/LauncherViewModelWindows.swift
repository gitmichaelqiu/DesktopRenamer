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
                id: "space-\(space.id)",
                title: space.name,
                subtitle: String(format: space.isFullscreen ? String(localized: "Fullscreen") : String(localized: "%lld windows"), items.count),
                items: items
            ))
        }
        return sections
    }
    
    var visibleRowsCount: Int {
        if isSpaceMenuOpen {
            return spaceMenuSpaces.count
        }

        if activeCommand == nil {
            return filteredCommands.count
        } else {
            if stagingWindow != nil {
                return filteredMoveWindowSpaces.count
            }
            switch activeCommand?.type {
            case .switchToDesktop:
                return filteredSpaces.count
            case .moveWindow:
                return filteredActiveWindowMoveSpaces.count
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

    var spaceMenuSpaces: [SpaceGroup] {
        let candidates: [SpaceGroup]
        if stagingWindow != nil {
            candidates = unfilteredMoveWindowSpaces
        } else {
            switch activeCommand?.type {
            case .moveWindow:
                candidates = unfilteredActiveWindowMoveSpaces
            case .switchToDesktop:
                candidates = unfilteredSwitchSpaces
            default:
                candidates = []
            }
        }

        return filterSpaceGroups(candidates, query: submenuSearchQuery)
    }

    func executeSpaceMenuSelection() {
        let spaces = spaceMenuSpaces
        guard spaces.indices.contains(spaceMenuSelectedIndex) else { return }
        selectedRowIndex = spaceMenuSelectedIndex
        executeRowAction()
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
                appPath: space.appPath,
                displayID: space.displayID
            )
        }

        let spaceGroupsByID = Dictionary(uniqueKeysWithValues: currentSpaces.map { ($0.id, $0) })
        
        // If we are renaming space, pre-fill text
        if activeCommand?.type == .renameCurrentSpace {
            renameInputText = manager.getSpaceName(manager.currentSpaceUUID)
            isLoadingData = false
            return
        }
        
        // Query windows in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let records = SpaceHelper.getWindowRecordsForAllSpaces(spaces: spaces)
            let windows = Self.makeWindowEntries(records, spacesByID: spaceGroupsByID)
            
            DispatchQueue.main.async {
                let terminatingPIDs = self.terminatingApplicationPIDs
                self.currentWindows = windows.filter { !terminatingPIDs.contains($0.pid) }
                if self.activeCommand?.type == .listWindows {
                    // A close or quit can remove the selected window while a
                    // refresh is in flight. Keeping the old index naturally
                    // selects the next window, while clamping selects the
                    // final remaining window when the old one was last.
                    self.selectedRowIndex = min(
                        max(self.selectedRowIndex, 0),
                        max(self.filteredWindows.count - 1, 0)
                    )
                }
                self.terminatingApplicationPIDs = terminatingPIDs.filter {
                    NSRunningApplication(processIdentifier: $0) != nil
                }
                self.isLoadingData = false
            }
        }
    }

    func removeApplicationWindowsFromList(pid: Int32) {
        terminatingApplicationPIDs.insert(pid)
        currentWindows.removeAll { $0.pid == pid }
        selectedRowIndex = min(selectedRowIndex, max(filteredWindows.count - 1, 0))
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
    
    private nonisolated static func makeWindowEntries(
        _ records: [SpaceAPIWindow],
        spacesByID: [String: SpaceGroup]
    ) -> [WindowEntry] {
        records.compactMap { record in
            guard let space = spacesByID[record.spaceID] else { return nil }
            return WindowEntry(
                id: record.id,
                pid: record.pid,
                ownerName: record.ownerName,
                appPath: record.appPath ?? "",
                title: record.title ?? "",
                space: space,
                spaceIDs: record.spaceIDs,
                isMinimized: record.isMinimized,
                isHidden: record.isHidden
            )
        }
    }
}
