import AppKit

extension LauncherView {
    func handleTextFieldKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard !viewModel.isRearrangingSpace else { return true }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)

        if viewModel.activeCommand?.type == .switchToDesktop,
           viewModel.commandKTargetWindow == nil,
           !hasOption && !hasControl && hasCommand && hasShift {
            switch event.keyCode {
            case 126:
                viewModel.rearrangeSelectedDesktop(direction: .up)
                return true
            case 125:
                viewModel.rearrangeSelectedDesktop(direction: .down)
                return true
            default:
                break
            }
        }

        if viewModel.activeCommand?.type == .listWindows,
           viewModel.commandKTargetWindow == nil,
           viewModel.stagingWindow == nil {
            let windows = viewModel.filteredWindows
            let index = viewModel.selectedRowIndex
            if index >= 0 && index < windows.count {
                let window = windows[index]

                if hasCommand && !hasOption && !hasControl {
                    if let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 {
                        let char = chars.first!

                        if char == "t" {
                            if hasShift {
                                viewModel.stageSelectedListWindowForMove()
                            } else {
                                viewModel.moveSelectedListWindowToCurrentDesktop()
                            }
                            return true
                        }
                    }
                }

                // Keep direct window actions in sync with the Raycast
                // command: Control+Shift is reserved for window operations,
                // while Command+T/Command+Shift+T handle window moves.
                if hasControl && hasShift && !hasCommand && !hasOption {
                    if let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 {
                        switch chars.first! {
                        case "w": viewModel.executeActionImmediately(window: window, actionType: .close); return true
                        case "m": viewModel.executeActionImmediately(window: window, actionType: .minimize); return true
                        case "r": viewModel.executeActionImmediately(window: window, actionType: .restore); return true
                        case "f":
                            let isFS = window.space.isFullscreen
                            viewModel.executeActionImmediately(window: window, actionType: isFS ? .exitFullScreen : .enterFullScreen)
                            return true
                        case "h": viewModel.executeActionImmediately(window: window, actionType: .hide); return true
                        case "q": viewModel.executeActionImmediately(window: window, actionType: .quit); return true
                        default: break
                        }
                    }
                }
            }
        }

        if viewModel.activeCommand?.type == .batchMoveWindows,
           viewModel.commandKTargetWindow == nil,
           viewModel.stagingWindow == nil,
           hasControl && hasShift && !hasCommand && !hasOption,
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars.count == 1 {
            let items = viewModel.batchMoveSelectableItems
            let index = viewModel.selectedRowIndex
            guard index >= 0, index < items.count,
                  case .unstaged(let window, _) = items[index] else {
                return false
            }

            switch chars.first! {
            case "w":
                viewModel.stageSelectedBatchWindowAction(.close)
            case "r":
                let state = viewModel.isWindowMinimizedOrAppHidden(window)
                guard state.minimized || state.hidden else { return true }
                viewModel.stageSelectedBatchWindowAction(.restore)
            case "m":
                let state = viewModel.isWindowMinimizedOrAppHidden(window)
                guard !state.minimized else { return true }
                viewModel.stageSelectedBatchWindowAction(.minimize)
            case "h":
                let state = viewModel.isWindowMinimizedOrAppHidden(window)
                guard !state.hidden else { return true }
                viewModel.stageSelectedBatchWindowAction(.hide)
            case "f":
                let action: BatchStagedActionType = window.space.isFullscreen ? .exitFullScreen : .enterFullScreen
                viewModel.stageSelectedBatchWindowAction(action)
            case "q":
                viewModel.stageSelectedBatchWindowAction(.quit)
            default:
                return false
            }
            return true
        }

        if viewModel.activeCommand?.type == .switchToDesktop,
           hasCommand && !hasShift && !hasOption && !hasControl,
           let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "r" {
            let spaces = viewModel.filteredSpaces
            let index = viewModel.selectedRowIndex
            if index >= 0 && index < spaces.count {
                let space = spaces[index]
                if !space.isFullscreen {
                    viewModel.showRenameDialog(for: space)
                }
            }
            return true
        }

        return false
    }
}
