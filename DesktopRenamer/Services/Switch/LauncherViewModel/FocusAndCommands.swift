import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func handlePointerMovement() {
        isKeyboardSelection = false
    }

    func finishPointerAction() {
        isKeyboardSelection = false
    }

    func executeNthRowAction(_ index: Int) {
        guard !isLauncherBusy,
              index >= 0 && index < visibleRowsCount else { return }
        isKeyboardSelection = true
        selectedRowIndex = index
        executeRowAction()
    }
    
    func handleEscapeKey() {
        guard !isLauncherBusy else { return }

        if commandKTargetWindow != nil {
            commandKTargetWindow = nil
        } else if commandKTargetSpace != nil {
            commandKTargetSpace = nil
        } else if isBottomBarFocused {
            leaveSpaceBarFocus()
        } else if isSpaceMenuOpen {
            isSpaceMenuOpen = false
            spaceMenuSelectedIndex = 0
            submenuSearchQuery = ""
            if stagingWindow != nil {
                let stagedWindowID = stagingWindow?.id
                stagingWindow = nil
                isStagingForRestoreTo = false
                isExecutingRestoreToImmediately = false
                if activeCommand?.type == .batchMoveWindows, let stagedWindowID {
                    restoreBatchMoveSelection(
                        toWindowID: stagedWindowID,
                        staged: false,
                        preferredIndex: batchMoveLastSelectedIndex
                    )
                } else {
                    selectedRowIndex = batchMoveLastSelectedIndex
                }
            } else {
                returnToRootCommandList()
            }
        } else if stagingWindow != nil {
            let stagedWindowID = stagingWindow?.id
            stagingWindow = nil
            isStagingForRestoreTo = false
            isExecutingRestoreToImmediately = false
            submenuSearchQuery = ""
            if activeCommand?.type == .batchMoveWindows, let stagedWindowID {
                restoreBatchMoveSelection(
                    toWindowID: stagedWindowID,
                    staged: false,
                    preferredIndex: batchMoveLastSelectedIndex
                )
            } else {
                selectedRowIndex = batchMoveLastSelectedIndex
            }
        } else if activeCommand != nil {
            returnToRootCommandList()
        } else if !searchQuery.isEmpty {
            searchQuery = ""
        } else {
            closeLauncher()
        }
    }

    private func returnToRootCommandList() {
        let commandID = rootCommandSelectionID
        activeCommand = nil

        guard let commandID,
              let index = filteredCommands.firstIndex(where: { $0.id == commandID }) else {
            return
        }
        selectedRowIndex = index
    }
    
    func handleTabKey() {
        guard !isLauncherBusy else { return }

        if isSubmenuOpen {
            requestSubmenuFieldFocus()
        } else if isBottomBarFocused {
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

    func focusSpaceBar(movingBy offset: Int = 0, isKeyboardInitiated: Bool = true) {
        guard !isLauncherBusy else { return }

        spaceBarQuery = ""
        isBottomBarFocused = true
        isKeyboardSelection = isKeyboardInitiated
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
        guard !isLauncherBusy else { return }

        let spaces = filteredDisplaySpaces
        guard !spaces.isEmpty else {
            selectedSpaceIndex = 0
            return
        }

        selectedSpaceIndex = min(max(selectedSpaceIndex + offset, 0), spaces.count - 1)
    }
    
    func executeBottomBarSpaceAction(isOption: Bool, isCommand: Bool) {
        guard !isLauncherBusy,
              AppDelegate.shared.spaceManager != nil else { return }
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
        submenuSearchQuery = ""
        spaceBarQuery = ""
        selectedRowIndex = 0
        activeCommand = nil
        stagingWindow = nil
        commandKTargetWindow = nil
        commandKTargetSpace = nil
        isSpaceMenuOpen = false
        spaceMenuSelectedIndex = 0
        isBottomBarFocused = false
        onClose?()
    }

    func resetForPresentation() {
        cancelPendingFocusRequest()
        searchQuery = ""
        submenuSearchQuery = ""
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
        commandKTargetSpace = nil
        commandKSelectedIndex = 0
    }

    func requestLauncherFieldFocus() {
        requestFocusNotification(named: "FocusLauncherTextField")
    }

    func requestSubmenuFieldFocus() {
        requestFocusNotification(named: "FocusLauncherSubmenuTextField")
    }

    func requestSpaceBarFocus() {
        requestFocusNotification(named: "FocusSpaceBarTextField")
    }

    func requestCurrentFieldFocus() {
        if isSubmenuOpen {
            requestSubmenuFieldFocus()
        } else if isBottomBarFocused {
            requestSpaceBarFocus()
        } else {
            requestLauncherFieldFocus()
        }
    }

    private func requestFocusNotification(named name: String) {
        focusRequestID &+= 1
        let requestID = focusRequestID
        focusRequestWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.postFocusNotification(named: name, requestID: requestID, attempt: 0)
        }
        focusRequestWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func postFocusNotification(named name: String, requestID: Int, attempt: Int) {
        guard focusRequestID == requestID else { return }
        NotificationCenter.default.post(name: NSNotification.Name(name), object: nil)

        guard attempt < 3 else {
            focusRequestWorkItem = nil
            return
        }

        let retry = DispatchWorkItem { [weak self] in
            self?.postFocusNotification(named: name, requestID: requestID, attempt: attempt + 1)
        }
        focusRequestWorkItem = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: retry)
    }

    private func cancelPendingFocusRequest() {
        focusRequestID &+= 1
        focusRequestWorkItem?.cancel()
        focusRequestWorkItem = nil
    }
}
