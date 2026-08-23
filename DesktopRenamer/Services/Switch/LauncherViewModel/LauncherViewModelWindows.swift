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
                id: "space_\(space.id)",
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
        windowLoadGeneration &+= 1
        let loadGeneration = windowLoadGeneration
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
            
            let snapshots = SpaceHelper.getWindowSnapshots(spaces: spaces, spaceNames: names)
            let parsed = Self.makeWindowData(from: snapshots)
            
            DispatchQueue.main.async {
                guard loadGeneration == self.windowLoadGeneration else { return }

                let terminatingPIDs = self.terminatingApplicationPIDs
                self.currentWindows = parsed.windows.filter { !terminatingPIDs.contains($0.pid) }
                let observedPIDs = Set(parsed.windows.map(\.pid))
                self.terminatingApplicationPIDs = terminatingPIDs.filter { pid in
                    NSRunningApplication(processIdentifier: pid) != nil || observedPIDs.contains(pid)
                }
                self.isLoadingData = false
            }
        }
    }

    func removeApplicationWindowsFromList(pid: Int32) {
        terminatingApplicationPIDs.insert(pid)
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

    private nonisolated static func makeWindowData(from snapshots: [SpaceWindowSnapshot]) -> (spaces: [SpaceGroup], windows: [WindowEntry]) {
        var spaces: [SpaceGroup] = []
        var windows: [WindowEntry] = []

        for snapshot in snapshots {
            let space = SpaceGroup(
                id: snapshot.id,
                name: snapshot.name.isEmpty ? "Space \(snapshot.num)" : snapshot.name,
                displayName: snapshot.displayName,
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
