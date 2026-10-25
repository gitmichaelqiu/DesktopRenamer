import Foundation
import AppKit
import SwiftUI

struct HUDView: View {
    let message: String
    let appIcon: NSImage?
    let systemImage: String?
    let iconColor: Color
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void
    let forceHover: Bool

    @State private var isHovered = false

    private var showsDismissButton: Bool {
        isHovered || forceHover
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if showsDismissButton {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Dismiss"))
                    .accessibilityLabel(String(localized: "Dismiss"))
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28, height: 28)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 420, alignment: .leading)
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(buttonTitle) {
                    buttonAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

class HUDNSPanel: NSPanel {
    var isInteractive: Bool = false
    override var canBecomeKey: Bool { isInteractive }
    override var canBecomeMain: Bool { isInteractive }
}

enum HUDPresentationStyle {
    case success
    case info
    case warning
    case failure

    var iconColor: Color {
        switch self {
        case .success:
            return .green
        case .info:
            return .blue
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }
}

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private var hideTimer: Timer?
    private var hostingView: NSHostingView<HUDView>?
    private var hideDuration: TimeInterval?
    private var isHoveringHUD = false
    #if DEBUG
    private var forceHoverPreview = false
    #endif

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
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // HUD feedback must survive a command that temporarily switches the
        // active Space while moving or operating on a window.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        message: String,
        style: HUDPresentationStyle,
        appIcon: NSImage? = nil,
        systemImage: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil,
        autoHide: Bool = true
    ) {
        show(
            message: message,
            systemImage: systemImage,
            iconColor: style.iconColor,
            appIcon: appIcon ?? (systemImage == nil ? NSApp.applicationIconImage : nil),
            buttonTitle: buttonTitle,
            buttonAction: buttonAction,
            autoHide: autoHide
        )
    }

    func showProgress(
        message: String,
        style: HUDPresentationStyle = .info,
        appIcon: NSImage? = nil,
        systemImage: String? = nil
    ) {
        show(
            message: message,
            style: style,
            appIcon: appIcon,
            systemImage: systemImage,
            autoHide: false
        )
    }

    func showAfterLauncherDismissal(
        message: String,
        style: HUDPresentationStyle,
        appIcon: NSImage? = nil,
        systemImage: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.show(
                message: message,
                style: style,
                appIcon: appIcon,
                systemImage: systemImage,
                buttonTitle: buttonTitle,
                buttonAction: buttonAction
            )
        }
    }

    func show(
        message: String,
        systemImage: String? = nil,
        iconColor: Color,
        appIcon: NSImage? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil,
        autoHide: Bool = true
    ) {
        guard let panel = window as? HUDNSPanel else { return }

        panel.appearance = NSApp.effectiveAppearance
        hideTimer?.invalidate()
        hideTimer = nil
        hideDuration = nil
        isHoveringHUD = false
        
        panel.isInteractive = (buttonTitle != nil)
        panel.becomesKeyOnlyIfNeeded = (buttonTitle != nil)

        let hudView = HUDView(
            message: message,
            appIcon: appIcon ?? (systemImage == nil ? NSApp.applicationIconImage : nil),
            systemImage: systemImage,
            iconColor: iconColor,
            buttonTitle: buttonTitle,
            buttonAction: {
                buttonAction?()
                self.hideWithAnimation()
            },
            onDismiss: { [weak self] in self?.hideWithAnimation() },
            onHoverChanged: { [weak self] hovering in self?.handleHoverChange(hovering) },
            forceHover: {
                #if DEBUG
                self.forceHoverPreview
                #else
                false
                #endif
            }()
        )

        if let existing = hostingView {
            existing.rootView = hudView
        } else {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let newView = NSHostingView(rootView: hudView)
            newView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(newView)
            NSLayoutConstraint.activate([
                newView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                newView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                newView.topAnchor.constraint(equalTo: container.topAnchor),
                newView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            let surfaceView: NSView
            if #available(macOS 26.0, *) {
                let glassView = NSGlassEffectView(frame: .zero)
                glassView.cornerRadius = 26
                glassView.contentView = container
                surfaceView = glassView
            } else {
                let visualEffectView = NSVisualEffectView(frame: .zero)
                visualEffectView.material = .hudWindow
                visualEffectView.blendingMode = .withinWindow
                visualEffectView.state = .active
                visualEffectView.wantsLayer = true
                visualEffectView.layer?.cornerRadius = 26
                visualEffectView.layer?.masksToBounds = true
                visualEffectView.addSubview(container)
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                    container.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                    container.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
                ])
                surfaceView = visualEffectView
            }

            panel.contentView = surfaceView
            self.hostingView = newView
        }

        // Force layout, then size panel to fit the SwiftUI content.
        hostingView?.layout()
        let idealSize = hostingView?.intrinsicContentSize ?? NSSize(width: 300, height: 44)
        let size = idealSize.width > 0 && idealSize.height > 0
            ? idealSize
            : NSSize(width: 300, height: 44)
        panel.setContentSize(size)
        if #available(macOS 26.0, *), let glassView = panel.contentView as? NSGlassEffectView {
            glassView.cornerRadius = size.height / 2
        } else if let visualEffectView = panel.contentView as? NSVisualEffectView {
            visualEffectView.layer?.cornerRadius = size.height / 2
        }

        positionPanel(panel)

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        if autoHide {
            let duration = (buttonTitle != nil) ? 5.0 : 1.8
            hideDuration = duration
            scheduleHide(after: duration)
        }
    }

    private func handleHoverChange(_ hovering: Bool) {
        isHoveringHUD = hovering
        guard let hideDuration else { return }

        if hovering {
            hideTimer?.invalidate()
            hideTimer = nil
        } else {
            scheduleHide(after: hideDuration)
        }
    }

    private func scheduleHide(after duration: TimeInterval) {
        hideTimer?.invalidate()
        guard !isHoveringHUD else { return }
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
        hideTimer?.invalidate()
        hideTimer = nil
        hideDuration = nil

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    #if DEBUG
    func showDebugPreview(hovered: Bool = false) {
        forceHoverPreview = hovered
        show(
            message: "Klack enabled",
            style: .success,
            appIcon: NSApp.applicationIconImage,
            autoHide: false
        )
    }

    func hideDebugPreview() {
        forceHoverPreview = false
        hideWithAnimation()
    }
    #endif
}
