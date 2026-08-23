import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func executeNthRowAction(_ index: Int) {
        guard index >= 0 && index < visibleRowsCount else { return }
        isKeyboardSelection = true
        selectedRowIndex = index
        executeRowAction()
    }
    
    func handleEscapeKey() {
        if isBottomBarFocused {
            leaveSpaceBarFocus()
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
        if isBottomBarFocused {
            leaveSpaceBarFocus()
        } else if activeCommand == nil {
            focusSpaceBar()
        }
    }

    private func leaveSpaceBarFocus() {
        isBottomBarFocused = false
        spaceBarQuery = ""

        DispatchQueue.main.async {
            guard !self.isBottomBarFocused else { return }
            NotificationCenter.default.post(
                name: NSNotification.Name("FocusLauncherTextField"),
                object: nil
            )
        }
    }

    func focusSpaceBar(movingBy offset: Int = 0) {
        spaceBarQuery = ""
        isBottomBarFocused = true
        isKeyboardSelection = true

        DispatchQueue.main.async {
            guard self.isBottomBarFocused else { return }
            NotificationCenter.default.post(
                name: NSNotification.Name("FocusSpaceBarTextField"),
                object: nil
            )
        }

        guard let manager = AppDelegate.shared.spaceManager else { return }
        let spaces = manager.currentDisplaySpaces
        guard !spaces.isEmpty else {
            selectedSpaceIndex = 0
            return
        }

        let currentIndex = spaces.firstIndex(where: { $0.id == manager.currentSpaceUUID }) ?? 0
        selectedSpaceIndex = min(max(currentIndex + offset, 0), spaces.count - 1)
    }

    func moveSpaceSelection(by offset: Int) {
        let spaces = filteredDisplaySpaces
        guard !spaces.isEmpty else {
            selectedSpaceIndex = 0
            return
        }

        selectedSpaceIndex = min(max(selectedSpaceIndex + offset, 0), spaces.count - 1)
    }
    
    func executeBottomBarSpaceAction(isOption: Bool, isCommand: Bool) {
        guard AppDelegate.shared.spaceManager != nil else { return }
        let spaces = filteredDisplaySpaces
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
        batchExecutionTask?.cancel()
        invalidateWindowLoads()
        searchQuery = ""
        spaceBarQuery = ""
        selectedRowIndex = 0
        activeCommand = nil
        stagingWindow = nil
        isBottomBarFocused = false
        onClose?()
    }
}
