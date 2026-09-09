import AppKit

private final class DesktopRenamerMigrationProgressBar: NSView {
    private var fractionCompleted = 0.0

    override var isFlipped: Bool { true }

    func setFractionCompleted(_ fraction: Double) {
        fractionCompleted = min(max(fraction, 0), 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0, dy: 1)
        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: radius,
            yRadius: radius
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.45).setFill()
        trackPath.fill()

        guard fractionCompleted > 0 else { return }

        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width * fractionCompleted,
            height: trackRect.height
        )
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: radius,
            yRadius: radius
        )
        NSColor.controlAccentColor.setFill()
        fillPath.fill()
    }
}

final class DesktopRenamerMigrationProgressWindowController: NSObject {
    private let window: NSWindow
    private let messageLabel: NSTextField
    private let percentageLabel: NSTextField
    private let progressBar: DesktopRenamerMigrationProgressBar
    private let cancelAction: () -> Void

    init(cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction

        let iconView = NSImageView(
            image: NSImage(named: NSImage.applicationIconName) ?? NSImage()
        )
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let titleLabel = NSTextField(labelWithString: "Downloading DesktopRenamer migration")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(
            labelWithString: "Preparing the new app while keeping your settings safe."
        )
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping

        let headingTextStack = NSStackView(views: [titleLabel, subtitleLabel])
        headingTextStack.orientation = .vertical
        headingTextStack.alignment = .leading
        headingTextStack.spacing = 4

        let headingStack = NSStackView(views: [iconView, headingTextStack])
        headingStack.orientation = .horizontal
        headingStack.alignment = .centerY
        headingStack.spacing = 14

        messageLabel = NSTextField(labelWithString: "Downloading migration package")
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        percentageLabel = NSTextField(labelWithString: "")
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        percentageLabel.alignment = .right
        percentageLabel.textColor = .secondaryLabelColor
        percentageLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let statusStack = NSStackView(views: [messageLabel, percentageLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 12
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressBar = DesktopRenamerMigrationProgressBar()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let cancelButton = NSButton(
            title: "Cancel",
            target: nil,
            action: nil
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .regular
        cancelButton.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let footerSpacer = NSView()
        let footerStack = NSStackView(views: [footerSpacer, cancelButton])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 12

        let stackView = NSStackView(
            views: [headingStack, statusStack, progressBar, footerStack]
        )
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 254)
        )
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 28),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -28),
            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 26),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -24)
        ])

        window = NSWindow(
            contentRect: visualEffectView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = .modalPanel
        window.contentView = visualEffectView

        super.init()
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(message: String, percentage: String, fractionCompleted: Double) {
        messageLabel.stringValue = message
        percentageLabel.stringValue = percentage
        progressBar.setFractionCompleted(fractionCompleted)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    @objc private func cancel() {
        cancelAction()
    }
}
