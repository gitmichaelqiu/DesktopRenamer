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

                        if char == "m" && !hasShift {
                            viewModel.batchMoveLastSelectedIndex = viewModel.selectedRowIndex
                            viewModel.stagingWindow = window
                            viewModel.isExecutingRestoreToImmediately = true
                            viewModel.selectedRowIndex = 0
                            return true
                        } else if hasShift {
                            switch char {
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
