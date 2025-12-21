import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    // Configuration for the two states
    private let smallSize = NSSize(width: 400, height: 200)
    private let largeSize = NSSize(width: 1200, height: 800) // Huge size for clear preview
    
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
        
        // 2. Start at Center (Safe creation point)
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
        
        // 4. Window Attributes
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        
        // Stationary behavior is CRITICAL for Mission Control visibility
        self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
        
        // 5. Observers
        self.spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
            
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(repositionWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        // 6. Initial Layout: Default to "Active" (Hidden)
        // We use async to ensure the window is registered on the screen before moving it off.
        DispatchQueue.main.async { [weak self] in
            // Default to true (Active/Hidden) just in case
            self?.updateLayout(isCurrentSpace: true)
        }
    }
    
    // MARK: - Public API
    
    /// Called by SpaceLabelManager to switch modes
    func setMode(isCurrentSpace: Bool) {
        // Animate the transition
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
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
            // MODE A: Active Space -> Hide in "Safe Anchor Zone"
            // This prevents it from blocking your work.
            newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
            
            // Fade out content so it's truly invisible even if it peeks 1px
            self.contentView?.animator().alphaValue = 0.0
        } else {
            // MODE B: Inactive Space -> Center & Giant
            // This makes it visible in Mission Control thumbnails.
            newOrigin = NSPoint(
                x: targetFrame.midX - (newSize.width / 2),
                y: targetFrame.midY - (newSize.height / 2)
            )
            self.contentView?.animator().alphaValue = 1.0
        }
        
        // 1. Resize Window
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        
        // 2. Resize Content View & Font
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        updateLabelFont(for: newSize)
    }
    
    private func updateLabelFont(for size: NSSize) {
        let name = self.label.stringValue
        let padding: CGFloat = size.width * 0.1 // 10% padding
        let maxWidth = size.width - (padding * 2)
        let maxHeight = size.height - (padding * 2)
        
        // Base font size: Huge for preview, small for active
        var fontSize: CGFloat = size.width > 500 ? 180 : 50
        
        var attributed = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])
        var sSize = attributed.size()
        
        // Shrink text to fit container
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 20 {
            fontSize -= 10
            attributed = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])
            sSize = attributed.size()
        }
        
        self.label.font = .systemFont(ofSize: fontSize, weight: .bold)
        
        // Center the label
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
        let overlap: CGFloat = 1.0 // The magic 1-pixel anchor
        
        // Check corners using the current SIZE
        let topLeft = NSPoint(x: f.minX - size.width + overlap, y: f.maxY - overlap)
        let topRight = NSPoint(x: f.maxX - overlap, y: f.maxY - overlap)
        let bottomLeft = NSPoint(x: f.minX - size.width + overlap, y: f.minY - size.height + overlap)
        let bottomRight = NSPoint(x: f.maxX - overlap, y: f.minY - size.height + overlap)
        
        let candidates = [topLeft, topRight, bottomLeft, bottomRight]
        
        for point in candidates {
            let rect = NSRect(origin: point, size: size)
            
            // Does this candidate touch any *neighboring* screen?
            let touchesNeighbor = allScreens.contains { screen in
                if screen == targetScreen { return false }
                // Use small inset to avoid false positives on shared edges
                return screen.frame.insetBy(dx: 1, dy: 1).intersects(rect)
            }
            
            if !touchesNeighbor {
                return point // Found a safe anchor!
            }
        }
        
        return topLeft // Fallback
    }
    
    @objc private func repositionWindow() {
        // If screen config changes, re-evaluate.
        // We default to "Active" mode to be safe and hidden.
        updateLayout(isCurrentSpace: true)
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        // Trigger font resize based on current frame width
        updateLabelFont(for: self.frame.size)
    }
}
