import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func executeRowAction() {
        let index = selectedRowIndex
        
        if activeCommand == nil {
            // Main menu selection
            let commands = filteredCommands
            guard index >= 0 && index < commands.count else { return }
            let command = commands[index]
            
            if command.hasSubpage {
                activeCommand = command
                submenuSearchQuery = ""
                // Space selection commands use the same full-page layout as
                // the other launcher commands. The overlay is reserved for
                // nested target selection, such as staging a window move.
                isSpaceMenuOpen = false
                selectedRowIndex = 0
                spaceMenuSelectedIndex = 0
            } else {
                executeSimpleCommand(command.type)
            }
        } else {
            // Subpage selection
            if let staging = stagingWindow {
                // Staging a window to target space
                let spaces = isSpaceMenuOpen ? spaceMenuSpaces : filteredMoveWindowSpaces
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
                isSpaceMenuOpen = false
                spaceMenuSelectedIndex = 0
                selectedRowIndex = batchMoveLastSelectedIndex
                return
            }
            
            switch activeCommand?.type {
            case .switchToDesktop:
                let spaces = isSpaceMenuOpen ? spaceMenuSpaces : filteredSpaces
                guard index >= 0 && index < spaces.count else { return }
                executeSwitchToDesktop(spaces[index])
                
            case .moveWindow:
                let spaces = isSpaceMenuOpen ? spaceMenuSpaces : filteredActiveWindowMoveSpaces
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
                    let previousRowIndex = selectedRowIndex
                    batchMoveLastSelectedIndex = previousRowIndex
                    isStagingForRestoreTo = false
                    stagingWindow = window
                    isSpaceMenuOpen = true
                    spaceMenuSelectedIndex = 0
                    selectedRowIndex = previousRowIndex
                }
                
            case .renameCurrentSpace:
                executeRenameCurrentSpace(renameInputText)
                
            default:
                break
            }
        }
    }
}
