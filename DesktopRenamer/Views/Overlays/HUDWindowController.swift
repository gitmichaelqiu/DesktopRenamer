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
    let statusTint: HUDStatusTint?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var foregroundColor: Color {
        colorScheme == .light ? .black : .white
    }

    private var showsDismissButton: Bool {
        isHovered || forceHover
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            hudContent.background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
                    .overlay {
                        // Glass tint fades on non-key panels; this wash stays visible without focus.
                        if let statusTint {
                            Capsule().fill(statusTint.surfaceTintColor)
                        }
                    }
            }
        } else {
            hudContent
        }
    }

    private var hudContent: some View {
        HStack(spacing: 12) {
            ZStack {
                if showsDismissButton {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(foregroundColor)
                            .frame(width: 28, height: 28)
                            .background(
                                foregroundColor.opacity(0.14),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Dismiss"))
                    .accessibilityLabel(String(localized: "Dismiss"))
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
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
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 420, alignment: .leading)
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(buttonTitle) {
                    buttonAction()
                }
                .buttonStyle(HUDActionButtonStyle(foregroundColor: foregroundColor))
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

private struct HUDActionButtonStyle: ButtonStyle {
    let foregroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                foregroundColor.opacity(configuration.isPressed ? 0.22 : 0.14),
                in: Capsule()
            )
            .contentShape(Capsule())
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

enum HUDStatusTint: Equatable {
    case success
    case failure

    var nsColor: NSColor {
        switch self {
        case .success: return .systemGreen
        case .failure: return .systemRed
        }
    }

    var surfaceTintColor: Color {
        Color(nsColor: nsColor).opacity(0.30)
    }

    var legacyOverlayColor: NSColor {
        nsColor.withAlphaComponent(0.20)
    }
}

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private var hideTimer: Timer?
    private var hostingView: NSHostingView<HUDView>?
    private var legacyVisualEffectView: NSVisualEffectView?
    private var legacyTintOverlayView: NSView?
    private var hideDuration: TimeInterval?
    private var isHoveringHUD = false
    private var presentationID = UUID()
    private var hideAnimationID: UUID?
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
        autoHide: Bool = true,
        statusTint: HUDStatusTint? = nil
    ) {
        present(
            message: message,
            systemImage: systemImage,
            iconColor: style.iconColor,
            appIcon: appIcon ?? (systemImage == nil ? NSApp.applicationIconImage : nil),
            buttonTitle: buttonTitle,
            buttonAction: buttonAction,
            autoHide: autoHide,
            statusTint: statusTint
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
        buttonAction: (() -> Void)? = nil,
        statusTint: HUDStatusTint? = nil
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.show(
                message: message,
                style: style,
                appIcon: appIcon,
                systemImage: systemImage,
                buttonTitle: buttonTitle,
                buttonAction: buttonAction,
                statusTint: statusTint
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
        autoHide: Bool = true,
        statusTint: HUDStatusTint? = nil
    ) {
        present(
            message: message,
            systemImage: systemImage,
            iconColor: iconColor,
            appIcon: appIcon,
            buttonTitle: buttonTitle,
            buttonAction: buttonAction,
            autoHide: autoHide,
            statusTint: statusTint
        )
    }

    private func present(
        message: String,
        systemImage: String?,
        iconColor: Color,
        appIcon: NSImage?,
        buttonTitle: String?,
        buttonAction: (() -> Void)?,
        autoHide: Bool,
        statusTint: HUDStatusTint?
    ) {
        guard let panel = window as? HUDNSPanel else { return }

        presentationID = UUID()
        hideAnimationID = nil
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
            }(),
            statusTint: statusTint
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

            let surfaceRoot = NSView()
            surfaceRoot.translatesAutoresizingMaskIntoConstraints = false
            let surfaceInset: CGFloat = 2

            if #available(macOS 26.0, *) {
                surfaceRoot.addSubview(container)
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: surfaceRoot.leadingAnchor, constant: surfaceInset),
                    container.trailingAnchor.constraint(equalTo: surfaceRoot.trailingAnchor, constant: -surfaceInset),
                    container.topAnchor.constraint(equalTo: surfaceRoot.topAnchor, constant: surfaceInset),
                    container.bottomAnchor.constraint(equalTo: surfaceRoot.bottomAnchor, constant: -surfaceInset),
                ])
            } else {
                let visualEffectView = NSVisualEffectView(frame: .zero)
                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                visualEffectView.material = .hudWindow
                visualEffectView.blendingMode = .withinWindow
                visualEffectView.state = .active
                visualEffectView.wantsLayer = true
                visualEffectView.layer?.cornerRadius = 26
                visualEffectView.layer?.masksToBounds = true

                let tintOverlayView = NSView(frame: .zero)
                tintOverlayView.translatesAutoresizingMaskIntoConstraints = false
                tintOverlayView.wantsLayer = true
                tintOverlayView.layer?.cornerRadius = 26
                tintOverlayView.layer?.masksToBounds = true
                surfaceRoot.addSubview(visualEffectView)
                visualEffectView.addSubview(container)
                visualEffectView.addSubview(tintOverlayView, positioned: .below, relativeTo: container)
                NSLayoutConstraint.activate([
                    visualEffectView.leadingAnchor.constraint(equalTo: surfaceRoot.leadingAnchor, constant: surfaceInset),
                    visualEffectView.trailingAnchor.constraint(equalTo: surfaceRoot.trailingAnchor, constant: -surfaceInset),
                    visualEffectView.topAnchor.constraint(equalTo: surfaceRoot.topAnchor, constant: surfaceInset),
                    visualEffectView.bottomAnchor.constraint(equalTo: surfaceRoot.bottomAnchor, constant: -surfaceInset),
                    container.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                    container.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                    container.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
                    tintOverlayView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                    tintOverlayView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                    tintOverlayView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                    tintOverlayView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
                ])
                self.legacyVisualEffectView = visualEffectView
                self.legacyTintOverlayView = tintOverlayView
            }

            panel.contentView = surfaceRoot
            self.hostingView = newView
        }

        // Force layout, then size panel to fit the SwiftUI content.
        hostingView?.layout()
        let idealSize = hostingView?.intrinsicContentSize ?? NSSize(width: 300, height: 44)
        let contentSize = idealSize.width > 0 && idealSize.height > 0
            ? idealSize
            : NSSize(width: 300, height: 44)
        let surfaceInset: CGFloat = 2
        panel.setContentSize(
            NSSize(
                width: contentSize.width + surfaceInset * 2,
                height: contentSize.height + surfaceInset * 2
            )
        )
        legacyVisualEffectView?.layer?.cornerRadius = contentSize.height / 2
        legacyTintOverlayView?.layer?.cornerRadius = contentSize.height / 2
        applyLegacyTint(statusTint)

        positionPanel(panel)

        panel.orderFrontRegardless()
        animateAlpha(1.0, on: panel, duration: 0.08)

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

    private func applyLegacyTint(_ statusTint: HUDStatusTint?) {
        legacyTintOverlayView?.layer?.backgroundColor =
            statusTint?.legacyOverlayColor.cgColor ?? NSColor.clear.cgColor
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

        let currentPresentationID = presentationID
        let currentHideAnimationID = UUID()
        hideAnimationID = currentHideAnimationID

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            guard self.presentationID == currentPresentationID,
                  self.hideAnimationID == currentHideAnimationID else { return }
            self.hideAnimationID = nil
            panel.orderOut(nil)
        }
    }

    private func animateAlpha(_ alpha: CGFloat, on panel: NSWindow, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = alpha
        }
    }

    #if DEBUG
    func showDebugPreview(hovered: Bool = false, statusTint: HUDStatusTint? = nil) {
        forceHoverPreview = hovered
        if let statusTint {
            show(
                message: statusTint == .success
                    ? "Batch actions completed"
                    : "Moving window failed for WeChat",
                systemImage: nil,
                iconColor: .clear,
                appIcon: NSApp.applicationIconImage,
                buttonTitle: nil,
                buttonAction: nil,
                autoHide: false,
                statusTint: statusTint
            )
        } else {
            show(
                message: "Klack enabled",
                style: .success,
                appIcon: NSApp.applicationIconImage,
                autoHide: false
            )
        }
    }

    func hideDebugPreview() {
        forceHoverPreview = false
        hideWithAnimation()
    }
    #endif
}
