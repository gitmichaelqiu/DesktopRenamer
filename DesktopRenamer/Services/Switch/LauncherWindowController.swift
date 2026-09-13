import Foundation
import AppKit
import SwiftUI

class LauncherNSPanel: NSPanel {
    weak var focusedTextField: FocusTextField?

    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

private final class LauncherMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }
}

@MainActor
private final class LauncherMenuPanelController {
    private let panel = LauncherMenuPanel()
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?

    func show(content: AnyView, parent: NSWindow) {
        if parentWindow !== parent {
            if let previousParent = parentWindow {
                previousParent.removeChildWindow(panel)
            }
            parentWindow = parent
        }

        if let hostingView {
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()
        } else {
            let hostingView = NSHostingView(rootView: content)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.sizingOptions = [.intrinsicContentSize]
            self.hostingView = hostingView
            panel.contentView = hostingView
        }

        layout(relativeTo: parent)
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        if let parentWindow {
            parentWindow.removeChildWindow(panel)
        }
        parentWindow = nil
        panel.orderOut(nil)
    }

    private func layout(relativeTo parent: NSWindow) {
        guard let hostingView else { return }

        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        let intrinsicSize = hostingView.intrinsicContentSize
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return }
        let size = NSSize(width: 380, height: intrinsicSize.height)

        let contentFrame = parent.contentRect(forFrameRect: parent.frame)
        let origin = NSPoint(
            x: contentFrame.maxX - size.width - 8,
            y: contentFrame.minY + 8
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

class LauncherWindowController: NSWindowController, NSWindowDelegate {
    static let shared = LauncherWindowController()
    
    let viewModel = LauncherViewModel()
    
    private var flagsChangedMonitor: Any?
    private var keyDownMonitor: Any?
    private var isHiding = false
    private let actionMenuController = LauncherMenuPanelController()
    
    init() {
        let panel = LauncherNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // The launcher follows the Space that is active when it is presented.
        // It must not remain attached to the Space where the panel was first
        // created, because activating it there can switch the user's Space.
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        
        super.init(window: panel)
        panel.delegate = self
        
        // Setup SwiftUI View
        self.viewModel.onClose = { [weak self] in
            self?.hide()
        }
        
        let launcherView = LauncherView(viewModel: self.viewModel)
        let hostingView = NSHostingView(rootView: launcherView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 750, height: 475)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 26
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.sizingOptions = []
        
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            let hasCommand = event.modifierFlags.contains(.command)

            self.viewModel.showCommandNumbers = hasCommand
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.window as? LauncherNSPanel,
                  panel.isKeyWindow
            else {
                return event
            }

            if self.handleLauncherShortcut(event) {
                return nil
            }

            guard let focusedTextField = panel.focusedTextField,
                  focusedTextField.window === panel,
                  panel.firstResponder === focusedTextField || panel.firstResponder === focusedTextField.currentEditor()
            else {
                return event
            }

            return focusedTextField.handleKeyEquivalent(event) ? nil : event
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func show() {
        guard let panel = window as? LauncherNSPanel else { return }
        actionMenuController.hide()
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "launcher show begin visible=\(panel.isVisible), key=\(panel.isKeyWindow), windowSpaces=\(SpaceHelper.getWindowCurrentSpaces(windowID: panel.windowNumber).sorted()), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay())), collectionBehavior=\(panel.collectionBehavior.rawValue)"
        )
        
        // Capture previously active window before we activate the launcher and take focus
        viewModel.previouslyActiveWindow = SpaceHelper.getActiveWindowInfo()
        
        // Center on screen with cursor
        centerOnActiveScreen()
        
        // Reset state
        viewModel.resetForPresentation()
        
        // A nonactivating panel can become key for text input without making
        // DesktopRenamer the active application. Activating the app here can
        // make WindowServer select the Space where this panel was last shown.
        panel.makeKeyAndOrderFront(nil)
        SpaceHelper.debugTrace(
            traceID,
            "launcher show end visible=\(panel.isVisible), key=\(panel.isKeyWindow), windowSpaces=\(SpaceHelper.getWindowCurrentSpaces(windowID: panel.windowNumber).sorted()), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        
        // Post a notification to force focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherTextField"), object: nil)
        }
    }
    
    func hide() {
        guard !isHiding else { return }
        isHiding = true
        defer { isHiding = false }

        let traceID = SpaceHelper.debugTraceID()
        let panel = window
        actionMenuController.hide()
        SpaceHelper.debugTrace(
            traceID,
            "launcher hide begin visible=\(panel?.isVisible ?? false), key=\(panel?.isKeyWindow ?? false), windowSpaces=\(panel.map { SpaceHelper.getWindowCurrentSpaces(windowID: $0.windowNumber).sorted() } ?? []), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        window?.orderOut(nil)
        viewModel.resetForPresentation()
        viewModel.showCommandNumbers = false
        viewModel.previouslyActiveWindow = nil
        SpaceHelper.debugTrace(
            traceID,
            "launcher hide end visible=\(panel?.isVisible ?? false), key=\(panel?.isKeyWindow ?? false), windowSpaces=\(panel.map { SpaceHelper.getWindowCurrentSpaces(windowID: $0.windowNumber).sorted() } ?? []), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
    }

    func updateCommandKMenu(for targetWindow: WindowEntry?) {
        guard let parent = window, let targetWindow else {
            actionMenuController.hide()
            return
        }

        actionMenuController.show(
            content: AnyView(LauncherActionMenuView(viewModel: viewModel, window: targetWindow)),
            parent: parent
        )
    }

    func updateSpaceMenu() {
        guard let parent = window,
              viewModel.commandKTargetWindow == nil,
              viewModel.isSpaceMenuOpen else {
            actionMenuController.hide()
            return
        }

        actionMenuController.show(
            content: AnyView(LauncherSpaceMenuView(viewModel: viewModel)),
            parent: parent
        )
    }

    private func handleLauncherShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              modifiers.subtracting([.command, .numericPad, .function]).isEmpty else {
            return false
        }
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 40 || characters == "k" {
            if viewModel.commandKTargetWindow != nil {
                viewModel.commandKTargetWindow = nil
                return true
            }

            guard (viewModel.activeCommand?.type == .batchMoveWindows || viewModel.activeCommand?.type == .listWindows),
                  viewModel.stagingWindow == nil else {
                return false
            }
            viewModel.showCommandKPanel()
            return true
        }

        let numberByKeyCode: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
            22: 6, 26: 7, 28: 8, 25: 9,
        ]
        guard let number = numberByKeyCode[event.keyCode]
                ?? (characters.count == 1 ? Int(characters) : nil),
              (1...9).contains(number) else {
            return false
        }

        if viewModel.commandKTargetWindow != nil {
            let index = number - 1
            guard viewModel.commandKActions.indices.contains(index) else { return true }
            viewModel.commandKSelectedIndex = index
            viewModel.executeCommandKAction()
        } else if viewModel.isSpaceMenuOpen {
            let index = number - 1
            guard viewModel.spaceMenuSpaces.indices.contains(index) else { return true }
            viewModel.spaceMenuSelectedIndex = index
            viewModel.executeSpaceMenuSelection()
        } else {
            viewModel.executeNthRowAction(number - 1)
        }
        return true
    }
    
    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
    
    private func centerOnActiveScreen() {
        guard let panel = window else { return }
        
        // Find screen with cursor
        let cursorPoint = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let mouseScreen = screens.first(where: { NSMouseInRect(cursorPoint, $0.frame, false) }) ?? NSScreen.main ?? screens.first
        
        guard let screen = mouseScreen else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = panel.frame
        
        let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
        // Spotlight placement: 65% up the screen height
        let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) * 0.65
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // NSWindowDelegate method: Auto-hide when focus is lost
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
