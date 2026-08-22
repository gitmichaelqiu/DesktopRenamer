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
}

