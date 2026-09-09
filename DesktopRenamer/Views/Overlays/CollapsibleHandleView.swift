import Cocoa

// Handle view displayed when the window is docked to a screen edge.
class CollapsibleHandleView: NSView {
    private let imageView: NSImageView

    var edge: NSRectEdge = .maxX {
        didSet { updateChevron() }
    }

    init() {
        imageView = NSImageView()
        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.cornerRadius = 12

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .bold)

        // Ensure tint is set to .labelColor so it adapts to Light/Dark mode correctly
        imageView.contentTintColor = .labelColor

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateChevron()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateChevron() {
        let symbolName: String
        switch edge {
        case .minX: symbolName = "chevron.right"
        case .maxX: symbolName = "chevron.left"
        case .minY: symbolName = "chevron.up"
        case .maxY: symbolName = "chevron.down"
        default: symbolName = "chevron.left"
        }
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Expand")
    }
}

