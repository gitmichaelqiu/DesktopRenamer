import Foundation
import AppKit
import SwiftUI

struct HUDView: View {
    let message: String
    let systemImage: String
    let iconColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 22, height: 22)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())
            
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

class HUDNSPanel: NSPanel {
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()
    
    private var hideTimer: Timer?
    
    init() {
        let panel = HUDNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
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
        panel.becomesKeyOnlyIfNeeded = false
        
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(message: String, systemImage: String, iconColor: Color) {
        guard let panel = window as? HUDNSPanel else { return }
        
        // Cancel existing timer
        hideTimer?.invalidate()
        
        // Set SwiftUI content view
        let hudView = HUDView(message: message, systemImage: systemImage, iconColor: iconColor)
        let hostingView = NSHostingView(rootView: hudView)
        
        // Size to fit content
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)
        panel.contentView = hostingView
        
        // Position at bottom center of active screen
        positionPanel(panel)
        
        // Anim fade in
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1.0
        } completionHandler: {
            // Auto hide after delay
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
                self?.hideWithAnimation()
            }
        }
    }
    
    private func positionPanel(_ panel: NSWindow) {
        let cursorPoint = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let activeScreen = screens.first(where: { NSMouseInRect(cursorPoint, $0.frame, false) }) ?? NSScreen.main ?? screens.first
        
        guard let screen = activeScreen else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        
        let x = screenFrame.origin.x + (screenFrame.width - panelFrame.width) / 2
        // Position at bottom center of screen (e.g. 140pt above screen bottom)
        let y = screenFrame.origin.y + 140
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func hideWithAnimation() {
        guard let panel = window else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
