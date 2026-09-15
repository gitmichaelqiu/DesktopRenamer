import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    /// Checks whether `query` matches `target` and its cached `pinyin`, supporting pinyin input for CJK-localized strings.
    /// e.g. typing "qiehuan" or "qie huan" matches "切换桌面" (pinyin: qie huan zhuo mian).
    func matchesQuery(_ query: String, target: String, pinyin: String) -> Bool {
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
    
    var unfilteredSwitchSpaces: [SpaceGroup] {
        guard let staging = stagingWindow else { return currentSpaces }
        return currentSpaces.filter { $0.id != staging.space.id }
    }

    var unfilteredMoveWindowSpaces: [SpaceGroup] {
        unfilteredSwitchSpaces.filter { !$0.isFullscreen }
    }

    var unfilteredActiveWindowMoveSpaces: [SpaceGroup] {
        guard let previousWindow = previouslyActiveWindow else {
            return unfilteredMoveWindowSpaces
        }

        let displayID = SpaceHelper.getWindowDisplayID(for: previousWindow.frame)
        let sourceSpaceID = displayID.flatMap { SpaceHelper.getCurrentSpaceID(for: $0) }

        guard let sourceSpaceID else {
            return unfilteredMoveWindowSpaces
        }
        return unfilteredMoveWindowSpaces.filter { $0.id != sourceSpaceID }
    }

    func filterSpaceGroups(_ spaces: [SpaceGroup], query: String) -> [SpaceGroup] {
        guard !query.isEmpty else { return spaces }

        let lowerQuery = query.lowercased()
        return spaces.filter {
            matchesQuery(lowerQuery, target: $0.name, pinyin: $0.pinyinName) ||
            matchesQuery(lowerQuery, target: $0.displayName, pinyin: $0.pinyinDisplayName) ||
            "\($0.num)".contains(lowerQuery)
        }
    }

    var filteredSpaces: [SpaceGroup] {
        filterSpaceGroups(unfilteredSwitchSpaces, query: searchQuery)
    }

    var shouldShowDisplayNameForSpaces: Bool {
        Set(currentSpaces.map(\.displayID)).count > 1
    }

    /// Targets for moving a window must be ordinary desktops. Fullscreen
    /// Spaces belong to the app that owns them and cannot receive an
    /// arbitrary window through the launcher move commands.
    var filteredMoveWindowSpaces: [SpaceGroup] {
        filterSpaceGroups(unfilteredMoveWindowSpaces, query: searchQuery)
    }

    /// The top-level Move Window command operates on the window captured when
    /// the launcher opened, so do not offer its source desktop as a target.
    var filteredActiveWindowMoveSpaces: [SpaceGroup] {
        filterSpaceGroups(unfilteredActiveWindowMoveSpaces, query: searchQuery)
    }
    
    var filteredStagedActions: [BatchStagedAction] {
        let allStaged = stagedMoves.values.sorted {
            if $0.window.title != $1.window.title {
                return $0.window.title < $1.window.title
            }
            return $0.window.id < $1.window.id
        }
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

    func restoreBatchMoveSelection(
        forWindowID windowID: Int,
        staged: Bool,
        preferredIndex: Int
    ) {
        let items = batchMoveSelectableItems
        if let index = items.firstIndex(where: { $0.windowID == windowID && $0.isStaged == staged }) {
            selectedRowIndex = index
            return
        }

        guard !items.isEmpty else {
            selectedRowIndex = 0
            return
        }
        selectedRowIndex = min(max(preferredIndex, 0), items.count - 1)
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
                id: "staged",
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
                    id: "space-\(space.id)",
                    title: space.name,
                    subtitle: String(format: String(localized: "%lld windows"), spaceItems.count),
                    items: spaceItems
                ))
            }
        }
        
        return sections
    }
}
