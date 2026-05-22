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
    
    private let viewModel = LauncherViewModel()
    
    init() {
        let panel = LauncherNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        
        super.init(window: panel)
        panel.delegate = self
        
        // Setup SwiftUI View
        viewModel.onClose = { [weak self] in
            self?.hide()
        }
        
        let launcherView = LauncherView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: launcherView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 580, height: 380)
        
        panel.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        guard let panel = window as? LauncherNSPanel else { return }
        
        // Center on screen with cursor
        centerOnActiveScreen()
        
        // Reset state
        viewModel.searchQuery = ""
        viewModel.selectedRowIndex = 0
        viewModel.activeCommand = nil
        viewModel.stagingWindow = nil
        
        // Make key and focus
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.orderOut(nil)
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
