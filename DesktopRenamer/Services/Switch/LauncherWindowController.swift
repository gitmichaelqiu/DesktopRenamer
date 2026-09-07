import Foundation
import AppKit
import SwiftUI

class LauncherNSPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

class LauncherWindowController: NSWindowController, NSWindowDelegate {
    static let shared = LauncherWindowController()
    
    let viewModel = LauncherViewModel()
    
    private var isCommandKeyPressed = false
    private var cmdLongPressWorkItem: DispatchWorkItem?
    private var flagsChangedMonitor: Any?
    private var isHiding = false
    
    init() {
        let panel = LauncherNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 570),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 840, height: 570)
        
        panel.contentView = hostingView
        
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            let hasCommand = event.modifierFlags.contains(.command)
            
            if hasCommand {
                if !self.isCommandKeyPressed {
                    self.isCommandKeyPressed = true
                    self.cmdLongPressWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        if self.isCommandKeyPressed {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                self.viewModel.showCommandNumbers = true
                            }
                        }
                    }
                    self.cmdLongPressWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
                }
            } else {
                if self.isCommandKeyPressed {
                    self.isCommandKeyPressed = false
                    self.cmdLongPressWorkItem?.cancel()
                    self.cmdLongPressWorkItem = nil
                    withAnimation(.easeInOut(duration: 0.12)) {
                        self.viewModel.showCommandNumbers = false
                    }
                }
            }
            return event
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func show() {
        guard let panel = window as? LauncherNSPanel else { return }
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
        SpaceHelper.debugTrace(
            traceID,
            "launcher hide begin visible=\(panel?.isVisible ?? false), key=\(panel?.isKeyWindow ?? false), windowSpaces=\(panel.map { SpaceHelper.getWindowCurrentSpaces(windowID: $0.windowNumber).sorted() } ?? []), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        window?.orderOut(nil)
        isCommandKeyPressed = false
        cmdLongPressWorkItem?.cancel()
        cmdLongPressWorkItem = nil
        viewModel.resetForPresentation()
        viewModel.showCommandNumbers = false
        viewModel.previouslyActiveWindow = nil
        SpaceHelper.debugTrace(
            traceID,
            "launcher hide end visible=\(panel?.isVisible ?? false), key=\(panel?.isKeyWindow ?? false), windowSpaces=\(panel.map { SpaceHelper.getWindowCurrentSpaces(windowID: $0.windowNumber).sorted() } ?? []), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
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
