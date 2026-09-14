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
        } else if isSpaceMenuOpen {
            isSpaceMenuOpen = false
            spaceMenuSelectedIndex = 0
            if stagingWindow != nil {
                stagingWindow = nil
                isStagingForRestoreTo = false
                isExecutingRestoreToImmediately = false
                selectedRowIndex = batchMoveLastSelectedIndex
            } else {
                activeCommand = nil
            }
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
        requestFocusNotification(named: "FocusLauncherTextField")
    }

    func focusSpaceBar(movingBy offset: Int = 0) {
        spaceBarQuery = ""
        isBottomBarFocused = true
        isKeyboardSelection = true
        requestFocusNotification(named: "FocusSpaceBarTextField")

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
        cancelPendingFocusRequest()
        batchExecutionTask?.cancel()
        searchQuery = ""
        spaceBarQuery = ""
        selectedRowIndex = 0
        activeCommand = nil
        stagingWindow = nil
        isSpaceMenuOpen = false
        spaceMenuSelectedIndex = 0
        isBottomBarFocused = false
        onClose?()
    }

    func resetForPresentation() {
        cancelPendingFocusRequest()
        searchQuery = ""
        spaceBarQuery = ""
        selectedRowIndex = 0
        selectedSpaceIndex = 0
        activeCommand = nil
        stagingWindow = nil
        isSpaceMenuOpen = false
        spaceMenuSelectedIndex = 0
        isBottomBarFocused = false
        isStagingForRestoreTo = false
        isExecutingRestoreToImmediately = false
        commandKTargetWindow = nil
        commandKSelectedIndex = 0
    }

    func requestLauncherFieldFocus() {
        requestFocusNotification(named: "FocusLauncherTextField")
    }

    private func requestFocusNotification(named name: String) {
        focusRequestID &+= 1
        let requestID = focusRequestID
        focusRequestWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.focusRequestID == requestID else { return }
            NotificationCenter.default.post(name: NSNotification.Name(name), object: nil)
            self.focusRequestWorkItem = nil
        }
        focusRequestWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func cancelPendingFocusRequest() {
        focusRequestID &+= 1
        focusRequestWorkItem?.cancel()
        focusRequestWorkItem = nil
    }
}
