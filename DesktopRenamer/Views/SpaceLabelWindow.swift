import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    // Config
    private let smallSize = NSSize(width: 400, height: 200)
    private let largeSize = NSSize(width: 1200, height: 800)
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        
        self.label = NSTextField(labelWithString: name)
        
        // 1. Find Target Screen
        let foundScreen = NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == displayID { return true }
            let cleanName = displayID.components(separatedBy: " (").first ?? displayID
            return screen.localizedName == cleanName
        }
        let targetScreen = foundScreen ?? NSScreen.main!
        
        // 2. Start Center (Safe creation)
        let screenFrame = targetScreen.frame
        let startRect = NSRect(
            x: screenFrame.midX - (smallSize.width / 2),
            y: screenFrame.midY - (smallSize.height / 2),
            width: smallSize.width,
            height: smallSize.height
        )
        
        super.init(contentRect: startRect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        // 3. View Setup
        let contentView: NSView
        if #available(macOS 10.14, *) {
            contentView = NSVisualEffectView(frame: NSRect(origin: .zero, size: smallSize))
        } else {
            contentView = NSView(frame: NSRect(origin: .zero, size: smallSize))
        }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        
        self.label.alignment = .center
        self.label.textColor = .labelColor
        contentView.addSubview(self.label)
        self.contentView = contentView
        
        // 4. Attributes
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
        
        // 5. Observers
        self.spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(self, selector: #selector(repositionWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        // Initial Layout
        DispatchQueue.main.async { [weak self] in
            self?.updateLayout(isCurrentSpace: true)
        }
    }
    
    // MARK: - Public API
    
    func setMode(isCurrentSpace: Bool) {
        // OPTIMIZATION: Asymmetric Timing
        // 1. Entering Space (Active): 0.0s (Instant). Snap out of the way immediately.
        // 2. Leaving Space (Inactive): 0.35s (Smooth). Expand nicely for Mission Control preview.
        let duration = isCurrentSpace ? 0.0 : 0.35
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.updateLayout(isCurrentSpace: isCurrentSpace)
        }
    }
    
    // MARK: - Layout Logic
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else {
            self.close()
            return
        }
        
        let targetFrame = targetScreen.frame
        let newSize = isCurrentSpace ? smallSize : largeSize
        var newOrigin: NSPoint
        
        if isCurrentSpace {
            // MODE A: Active Space -> Snap to Safe Anchor Zone
            // It remains opaque (alpha 1.0) but is positioned 99% off-screen.
            newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
        } else {
            // MODE B: Inactive Space -> Center
            newOrigin = NSPoint(
                x: targetFrame.midX - (newSize.width / 2),
                y: targetFrame.midY - (newSize.height / 2)
            )
        }
        
        // Ensure visibility
        self.contentView?.animator().alphaValue = 1.0
        
        // Apply Frame Change
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        
        // Update Content
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        updateLabelFont(for: newSize)
    }
    
    private func updateLabelFont(for size: NSSize) {
        let name = self.label.stringValue
        let padding: CGFloat = size.width * 0.1
        let maxWidth = size.width - (padding * 2)
        let maxHeight = size.height - (padding * 2)
        
        var fontSize: CGFloat = size.width > 500 ? 180 : 50
        
        var attributed = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])
        var sSize = attributed.size()
        
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 20 {
            fontSize -= 10
            attributed = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])
            sSize = attributed.size()
        }
        
        self.label.font = .systemFont(ofSize: fontSize, weight: .bold)
        
        self.label.frame = NSRect(
            x: (size.width - sSize.width) / 2,
            y: (size.height - sSize.height) / 2,
            width: sSize.width,
            height: sSize.height
        )
    }

    // MARK: - Helpers
    
    private func findTargetScreen() -> NSScreen? {
        return NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == self.displayID { return true }
            let cleanTarget = self.displayID.components(separatedBy: " (").first ?? self.displayID
            return screen.localizedName == cleanTarget
        }
    }
    
    private func findBestOffscreenPosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let allScreens = NSScreen.screens
        let f = targetScreen.frame
        let overlap: CGFloat = 1.0
        
        let topLeft = NSPoint(x: f.minX - size.width + overlap, y: f.maxY - overlap)
        let topRight = NSPoint(x: f.maxX - overlap, y: f.maxY - overlap)
        let bottomLeft = NSPoint(x: f.minX - size.width + overlap, y: f.minY - size.height + overlap)
        let bottomRight = NSPoint(x: f.maxX - overlap, y: f.minY - size.height + overlap)
        
        let candidates = [topLeft, topRight, bottomLeft, bottomRight]
        
        for point in candidates {
            let rect = NSRect(origin: point, size: size)
            let touchesNeighbor = allScreens.contains { screen in
                if screen == targetScreen { return false }
                return screen.frame.insetBy(dx: 1, dy: 1).intersects(rect)
            }
            if !touchesNeighbor { return point }
        }
        return topLeft
    }
    
    @objc private func repositionWindow() {
        updateLayout(isCurrentSpace: true)
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        updateLabelFont(for: self.frame.size)
    }
}
