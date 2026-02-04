import AppKit
import SwiftUI

class OverscrollOverlayManager {
    static let shared = OverscrollOverlayManager()
    
    private var overlayWindow: NSWindow?
    private var rootHost: NSHostingView<AnyView>?
    private var hideWorkItem: DispatchWorkItem?
    
    private init() {}
    
    private var lastEdge: OverscrollIndicatorView.Edge = .leading
    private var lastProgress: Double = 0.0
    
    func update(progress: Double, edge: OverscrollIndicatorView.Edge) {
        // Cancel any pending hide animation
        hideWorkItem?.cancel()
        hideWorkItem = nil
        
        // Save state for dismissal
        self.lastEdge = edge
        self.lastProgress = progress
        
        // Find the screen containing the cursor (since gesture override usually targets cursor display)
        // Or we could pass the display explicitly. For now, cursor screen is safe default for gesture.
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) else { return }
        
        ensureWindow(for: screen)
        
        // Update Content
        // We use an ID combining screen frame and edge to force a hard view reset 
        // when switching context. This prevents SwiftUI from animating/interpolating 
        // the indicator position from Left to Right or jumping between screens.
        let viewId = "\(screen.frame)-\(edge)"
        let rootView = OverscrollIndicatorView(edge: edge, progress: progress)
            .id(viewId)
            
        if let host = rootHost {
            host.rootView = AnyView(rootView)
        } else {
            rootHost = NSHostingView(rootView: AnyView(rootView))
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
        guard let window = overlayWindow, window.isVisible else { return }
        guard hideWorkItem == nil else { return } // Already hiding
        
        // 1. Hold Phase (wait before fading)
        let fadeTriggerItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 2. Trigger Fade Out
            // Reconstruct view with isFadingOut = true
            // We use the same ID to ensure we ARE animating the opacity change, not replacing the view
            if let host = self.rootHost, let screen = self.overlayWindow?.screen {
                 let viewId = "\(screen.frame)-\(self.lastEdge)"
                 var fadingView = OverscrollIndicatorView(edge: self.lastEdge, progress: self.lastProgress)
                 fadingView.isFadingOut = true
                 
                 let finalView = fadingView.id(viewId)
                 host.rootView = AnyView(finalView)
            }
            
            // 3. Cleanup Phase (wait for animation)
            let cleanupItem = DispatchWorkItem { [weak self] in
                self?.overlayWindow?.orderOut(nil)
                self?.hideWorkItem = nil
            }
            
            // Update reference so it can be cancelled if update() happens during fade
            self.hideWorkItem = cleanupItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: cleanupItem)
        }
        
        hideWorkItem = fadeTriggerItem
        // Hold for 0.3s before starting fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: fadeTriggerItem)
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
            window.level = .statusBar // High level to sit above most things
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            
            self.overlayWindow = window
        }
    }
}
