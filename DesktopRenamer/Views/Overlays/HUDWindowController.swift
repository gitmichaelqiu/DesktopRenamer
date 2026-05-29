import Foundation
import AppKit
import SwiftUI

struct HUDView: View {
    let message: String
    let systemImage: String
    let iconColor: Color
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(iconColor)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14))
                .lineLimit(1)
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(buttonTitle) {
                    buttonAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .hudBackground(colorScheme: colorScheme)
    }
}

extension View {
    @ViewBuilder
    fileprivate func hudBackground(colorScheme: ColorScheme) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

class HUDNSPanel: NSPanel {
    var isInteractive: Bool = false
    override var canBecomeKey: Bool { isInteractive }
    override var canBecomeMain: Bool { isInteractive }
}

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private var hideTimer: Timer?
    private var hostingView: NSHostingView<HUDView>?

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

    func show(
        message: String,
        systemImage: String,
        iconColor: Color,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        guard let panel = window as? HUDNSPanel else { return }

        hideTimer?.invalidate()
        
        panel.isInteractive = (buttonTitle != nil)
        panel.becomesKeyOnlyIfNeeded = (buttonTitle != nil)

        let hudView = HUDView(
            message: message,
            systemImage: systemImage,
            iconColor: iconColor,
            buttonTitle: buttonTitle,
            buttonAction: {
                buttonAction?()
                self.hideWithAnimation()
            }
        )

        if let existing = hostingView {
            existing.rootView = hudView
        } else {
            // Wrap in a container to break the autolayout feedback loop.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
            container.autoresizingMask = [.width, .height]

            let newView = NSHostingView(rootView: hudView)
            newView.translatesAutoresizingMaskIntoConstraints = true
            newView.autoresizingMask = [.width, .height]
            newView.frame = container.bounds

            container.addSubview(newView)
            panel.contentView = container
            self.hostingView = newView
        }

        // Force layout, then size panel to fit the SwiftUI content.
        hostingView?.layout()
        let idealSize = hostingView?.intrinsicContentSize ?? NSSize(width: 300, height: 44)
        let size = idealSize.width > 0 && idealSize.height > 0
            ? idealSize
            : NSSize(width: 300, height: 44)
        panel.setContentSize(size)

        positionPanel(panel)

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        let duration = (buttonTitle != nil) ? 5.0 : 1.8
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hideWithAnimation()
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
        let y = screenFrame.origin.y + 140

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideWithAnimation() {
        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
