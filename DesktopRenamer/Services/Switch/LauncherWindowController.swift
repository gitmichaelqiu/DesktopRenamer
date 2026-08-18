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
    var shouldRestoreFocus = true
    
    private var isCommandKeyPressed = false
    private var cmdLongPressWorkItem: DispatchWorkItem?
    private var flagsChangedMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var hasInstalledContent = false
    
    init() {
        let panel = LauncherNSPanel(
            contentRect: NSRect(origin: .zero, size: LauncherLayout.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        // Allow the launcher to appear above apps using a native fullscreen
        // Space without making it join every Space.
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        
        super.init(window: panel)
        panel.delegate = self
        
        self.viewModel.onClose = { [weak self] in
            self?.hide()
        }
        
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleCommandFlagsChanged(event)
            return event
        }
        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleCommandFlagsChanged(event)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalFlagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleCommandFlagsChanged(_ event: NSEvent) {
        guard window?.isVisible == true else { return }

        let hasCommand = event.modifierFlags.contains(.command)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if hasCommand {
                guard !self.isCommandKeyPressed else { return }
                self.isCommandKeyPressed = true
                self.cmdLongPressWorkItem?.cancel()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isCommandKeyPressed else { return }
                    self.viewModel.showCommandNumbers = true
                }
                self.cmdLongPressWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
            } else {
                guard self.isCommandKeyPressed else { return }
                self.isCommandKeyPressed = false
                self.cmdLongPressWorkItem?.cancel()
                self.cmdLongPressWorkItem = nil
                self.viewModel.showCommandNumbers = false
            }
        }
    }
    
    func show() {
        guard let panel = window as? LauncherNSPanel else { return }
        guard installContentIfNeeded() else { return }

        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        
        shouldRestoreFocus = true
        
        // Capture previously active window before we activate the launcher and take focus
        viewModel.previouslyActiveWindow = SpaceHelper.getActiveWindowInfo()
        
        // Center on screen with cursor
        centerOnActiveScreen()
        // Reset state
        viewModel.searchQuery = ""
        viewModel.selectedRowIndex = 0
        viewModel.activeCommand = nil
        viewModel.stagingWindow = nil
        viewModel.isRootSpacePickerPresented = false
        
        // Make key and focus
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        
        // Post a notification to force focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherTextField"), object: nil)
        }
    }
    
    func hide() {
        guard let panel = window as? LauncherNSPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        isCommandKeyPressed = false
        cmdLongPressWorkItem?.cancel()
        cmdLongPressWorkItem = nil
        viewModel.showCommandNumbers = false
        
        if shouldRestoreFocus, let prev = viewModel.previouslyActiveWindow {
            DispatchQueue.main.async {
                SpaceHelper.focusWindow(id: prev.id, pid: prev.pid)
            }
        }
    }
    
    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    private func installContentIfNeeded() -> Bool {
        guard !hasInstalledContent,
              let appDelegate = AppDelegate.shared,
              let spaceManager = appDelegate.spaceManager,
              let panel = window as? LauncherNSPanel else {
            return hasInstalledContent
        }

        let launcherView = LauncherView(viewModel: viewModel, spaceManager: spaceManager)
        let hostingView = NSHostingView(rootView: launcherView)
        hostingView.frame = NSRect(origin: .zero, size: LauncherLayout.windowSize)
        panel.contentView = hostingView
        hasInstalledContent = true
        return true
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
        let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // NSWindowDelegate method: Auto-hide when focus is lost
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
