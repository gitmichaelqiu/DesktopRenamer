import AppKit
import SwiftUI

class OverscrollOverlayManager {
    static let shared = OverscrollOverlayManager()
    
    private var overlayWindow: NSWindow?
    private var rootHost: NSHostingView<OverscrollIndicatorView>?
    private var hideWorkItem: DispatchWorkItem?
    
    private init() {}
    
    func update(progress: Double, edge: OverscrollIndicatorView.Edge) {
        // Cancel any pending hide animation
        hideWorkItem?.cancel()
        hideWorkItem = nil
        
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
        guard let window = overlayWindow, window.isVisible else { return }
        guard hideWorkItem == nil else { return } // Already hiding
        
        // Trigger fade out in View
        if let host = rootHost {
            // We need to keep the last state but set fadingOut.
            // Since we can't easily extract state, we rely on the fact that hide() is called 
            // after the last update(). Ideally pass a flag.
            
            // Actually, simply telling the view to update with isFadingOut might reset animations.
            // A better way for this imperative-to-declarative bridge:
            // Update with same parameters but `isFadingOut: true`
            // But we don't have the last parameters easily here.
            
            // Simplified approach: Set progress to 1.0 (or last known?) and let it fade opacity.
            // To make it "fly out" or "fade out", we need support in the View.
            
            // Let's modify parameters: use the View's internal animation by setting isFadingOut
            // We'll update the view one last time with a special flag.
            var currentRoot = host.rootView
            currentRoot.isFadingOut = true
            host.rootView = currentRoot
        }
        
        let item = DispatchWorkItem { [weak self] in
            self?.overlayWindow?.orderOut(nil)
            self?.hideWorkItem = nil
        }
        
        hideWorkItem = item
        // Match the animation duration in the View
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
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
