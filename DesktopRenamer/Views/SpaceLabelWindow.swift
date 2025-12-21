import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    // Config
    private let smallSize = NSSize(width: 200, height: 100) // Keep anchor small/unobtrusive
    private var previewSize = NSSize(width: 800, height: 500) // Dynamic (Unified)
    
    // Default Font Config for measurement
    static let referenceFontSize: CGFloat = 180
    static let referenceFont = NSFont.systemFont(ofSize: referenceFontSize, weight: .bold)
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        
        self.label = NSTextField(labelWithString: name)
        
        let foundScreen = NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == displayID { return true }
            let cleanName = displayID.components(separatedBy: " (").first ?? displayID
            return screen.localizedName == cleanName
        }
        let targetScreen = foundScreen ?? NSScreen.main!
        
        let screenFrame = targetScreen.frame
        let startRect = NSRect(
            x: screenFrame.midX - (smallSize.width / 2),
            y: screenFrame.midY - (smallSize.height / 2),
            width: smallSize.width,
            height: smallSize.height
        )
        
        super.init(contentRect: startRect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        // Setup View
        let contentView: NSView
        if #available(macOS 10.14, *) {
            contentView = NSVisualEffectView(frame: NSRect(origin: .zero, size: smallSize))
        } else {
            contentView = NSView(frame: NSRect(origin: .zero, size: smallSize))
        }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 24 // Slightly rounder for large windows
        
        self.label.alignment = .center
        self.label.textColor = .labelColor
        contentView.addSubview(self.label)
        self.contentView = contentView
        
        // Attributes
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
        
        // Observers
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
    
    func setPreviewSize(_ size: NSSize) {
        // Only update if changed
        if self.previewSize != size {
            self.previewSize = size
            // If currently in preview mode, animate to new size
            if self.frame.width > smallSize.width + 10 {
                setMode(isCurrentSpace: false)
            }
        }
    }
    
    func setMode(isCurrentSpace: Bool) {
        let duration = isCurrentSpace ? 0.0 : 0.35
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.updateLayout(isCurrentSpace: isCurrentSpace)
        }
    }
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        let targetFrame = targetScreen.frame
        var newSize: NSSize
        var newOrigin: NSPoint
        
        if isCurrentSpace {
            // MODE A: Active Space (Small/Hidden)
            // FIX: Calculate exact size needed for the text at a readable small size (e.g., 45pt)
            // This ensures text NEVER exceeds the window, because the window grows to fit the text.
            newSize = calculateSizeForText(fontSize: 45, paddingH: 60, paddingV: 40)
            
            // Anchor off-screen (Safe Zone)
            newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
        } else {
            // MODE B: Inactive Space (Preview/Large)
            // Use the unified preview size calculated by the Manager
            newSize = previewSize
            
            // Center on screen
            newOrigin = NSPoint(
                x: targetFrame.midX - (newSize.width / 2),
                y: targetFrame.midY - (newSize.height / 2)
            )
        }
        
        self.contentView?.animator().alphaValue = 1.0
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        
        // Update Font based on the new size
        updateLabelFont(for: newSize, isSmallMode: isCurrentSpace)
    }
    
    // Helper to calculate ideal window dimensions
    private func calculateSizeForText(fontSize: CGFloat, paddingH: CGFloat, paddingV: CGFloat) -> NSSize {
        let name = self.label.stringValue
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let size = name.size(withAttributes: [.font: font])
        return NSSize(width: size.width + paddingH, height: size.height + paddingV)
    }
    
    private func updateLabelFont(for size: NSSize, isSmallMode: Bool) {
        let name = self.label.stringValue
        
        // Padding configuration
        let paddingH: CGFloat = size.width * 0.1
        let paddingV: CGFloat = size.height * 0.15
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV
        
        // Starting Font Size
        // If Small Mode: We know 45 fits (because we just calculated the window size for it),
        // but we run the check just to be safe.
        // If Large Mode: Start at Reference (180).
        var fontSize: CGFloat = isSmallMode ? 45 : SpaceLabelWindow.referenceFontSize
        
        // Setup font
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var attributed = NSAttributedString(string: name, attributes: [.font: font])
        var sSize = attributed.size()
        
        // Shrink Loop (Safety mechanism)
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            attributed = NSAttributedString(string: name, attributes: [.font: font])
            sSize = attributed.size()
        }
        
        self.label.font = font
        
        // Center text
        self.label.frame = NSRect(
            x: (size.width - sSize.width) / 2,
            y: (size.height - sSize.height) / 2,
            width: sSize.width,
            height: sSize.height
        )
    }
    
    private func updateLabelFont(for size: NSSize) {
        let name = self.label.stringValue
        
        // Define available area with padding
        // Increase horizontal padding slightly to prevent edge touching
        let paddingH: CGFloat = size.width * 0.15
        let paddingV: CGFloat = size.height * 0.2
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV
        
        // Determine starting font size
        // If small mode (Active), use 40. If Preview mode, start at Reference (180).
        let isSmall = size.width <= 210 // smallSize is 200, add buffer
        var fontSize: CGFloat = isSmall ? 40 : SpaceLabelWindow.referenceFontSize
        
        // Setup initial font
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var attributed = NSAttributedString(string: name, attributes: [.font: font])
        var sSize = attributed.size()
        
        // SHRINK LOOP: Reduce font size until it fits inside maxWidth/maxHeight
        // We set a minimum limit (e.g. 10pt) to prevent infinite loops on empty strings
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2 // Decrease in steps
            font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            attributed = NSAttributedString(string: name, attributes: [.font: font])
            sSize = attributed.size()
        }
        
        // Apply final font
        self.label.font = font
        
        // Center text in the window
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
        
        let candidates = [
            NSPoint(x: f.minX - size.width + overlap, y: f.maxY - overlap),
            NSPoint(x: f.maxX - overlap, y: f.maxY - overlap),
            NSPoint(x: f.minX - size.width + overlap, y: f.minY - size.height + overlap),
            NSPoint(x: f.maxX - overlap, y: f.minY - size.height + overlap)
        ]
        
        for point in candidates {
            let rect = NSRect(origin: point, size: size)
            let touchesNeighbor = allScreens.contains { screen in
                if screen == targetScreen { return false }
                return screen.frame.insetBy(dx: 1, dy: 1).intersects(rect)
            }
            if !touchesNeighbor { return point }
        }
        return candidates[0]
    }
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: true) }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        // Font update happens in layout loop or setMode usually, but we can force it here
        if self.frame.width > smallSize.width + 10 {
            updateLabelFont(for: self.frame.size)
        }
    }
}
