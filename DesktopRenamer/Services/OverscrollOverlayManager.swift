import AppKit
import SwiftUI

class OverscrollOverlayManager {
    static let shared = OverscrollOverlayManager()
    
    private var overlayWindow: NSWindow?
    private var rootHost: NSHostingView<OverscrollIndicatorView>?
    
    private init() {}
    
    func update(progress: Double, edge: OverscrollIndicatorView.Edge) {
        // Find the screen containing the cursor (since gesture override usually targets cursor display)
        // Or we could pass the display explicitly. For now, cursor screen is safe default for gesture.
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) else { return }
        
        ensureWindow(for: screen)
        
        // Update Content
        let rootView = OverscrollIndicatorView(edge: edge, progress: progress)
        if let host = rootHost {
            host.rootView = rootView
        } else {
            rootHost = NSHostingView(rootView: rootView)
            overlayWindow?.contentView = rootHost
        }
        
        // Ensure frame matches screen (in case screen changed)
        if overlayWindow?.frame != screen.frame {
            overlayWindow?.setFrame(screen.frame, display: true)
        }
        
        // Show Window if not visible
        if let window = overlayWindow, !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func hide() {
        // Animate out? Or just hide?
        // For responsiveness, just hide immediately or let the View handle fade out?
        // View handles opacity based on progress. If progress is 0, it's invisible.
        // But we should remove the window to save resources/interaction.
        overlayWindow?.orderOut(nil)
    }
    
    private func ensureWindow(for screen: NSScreen) {
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
//            window.level = .statusWindow // High level to sit above most things
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            
            self.overlayWindow = window
        }
    }
}
