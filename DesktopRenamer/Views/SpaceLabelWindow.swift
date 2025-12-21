import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    // State Tracking
    private var isActiveMode: Bool = true
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    // Config
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
        let startRect = NSRect(x: screenFrame.midX - 100, y: screenFrame.midY - 50, width: 200, height: 100)
        
        super.init(contentRect: startRect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        let contentView: NSView
        if #available(macOS 26.0, *) {
            contentView = NSGlassEffectView(frame: .zero)
        } else {
            contentView = NSVisualEffectView(frame: .zero)
        }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        
        self.label.alignment = .center
        self.label.textColor = .labelColor
        contentView.addSubview(self.label)
        self.contentView = contentView
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
        
        self.spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(self, selector: #selector(repositionWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        DispatchQueue.main.async { [weak self] in
            self?.updateLayout(isCurrentSpace: true)
        }
    }
    
    func setPreviewSize(_ size: NSSize) {
        if self.previewSize != size {
            self.previewSize = size
            if !isActiveMode {
                setMode(isCurrentSpace: false)
            }
        }
    }
    
    func setMode(isCurrentSpace: Bool) {
        self.isActiveMode = isCurrentSpace
        
        if isCurrentSpace {
            // Preview (Large) -> Active (Small)
            // ACTION: Ease Out (Fade Out) then Secretly Put in Corner
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                
                // 1. Fade out the large window in place
                self.animator().alphaValue = 0.0
                
            } completionHandler: {
                // 2. Secretly snap to the corner (Instant)
                self.updateLayout(isCurrentSpace: true)
                
                // 3. Restore opacity so it's visible to Mission Control
                self.alphaValue = 1.0
            }
            
        } else {
            // Active (Small) -> Preview (Large)
            // ACTION: No Animation (Instant Snap)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.0
                
                // 1. Snap to Center Immediately
                self.updateLayout(isCurrentSpace: false)
                self.alphaValue = 1.0
            }
        }
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        // Instant update for name changes
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        let targetFrame = targetScreen.frame
        var newSize: NSSize
        var newOrigin: NSPoint
        
        if isCurrentSpace {
            // MODE A: Active (Small & Dynamic)
            // Calculate size based on text length to ensure it fits (Font 45)
            newSize = calculateSizeForText(fontSize: 45, paddingH: 60, paddingV: 40)
            
            // Anchor off-screen (Safe Zone)
            newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
        } else {
            // MODE B: Preview (Large & Unified)
            newSize = previewSize
            
            // Center on screen
            newOrigin = NSPoint(
                x: targetFrame.midX - (newSize.width / 2),
                y: targetFrame.midY - (newSize.height / 2)
            )
        }
        
        // FRAME UPDATE:
        // We do NOT use animator() here. setMode handles the animation strategy.
        // This ensures the snap is instant when called.
        self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        
        updateLabelFont(for: newSize, isSmallMode: isCurrentSpace)
    }
    
    // MARK: - Helpers
    
    private func calculateSizeForText(fontSize: CGFloat, paddingH: CGFloat, paddingV: CGFloat) -> NSSize {
        let name = self.label.stringValue
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let size = name.size(withAttributes: [.font: font])
        return NSSize(width: size.width + paddingH, height: size.height + paddingV)
    }
    
    private func updateLabelFont(for size: NSSize, isSmallMode: Bool) {
        let name = self.label.stringValue
        
        let paddingH: CGFloat = size.width * 0.1
        let paddingV: CGFloat = size.height * 0.15
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV
        
        var fontSize: CGFloat = isSmallMode ? 45 : SpaceLabelWindow.referenceFontSize
        
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var attributed = NSAttributedString(string: name, attributes: [.font: font])
        var sSize = attributed.size()
        
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            attributed = NSAttributedString(string: name, attributes: [.font: font])
            sSize = attributed.size()
        }
        
        self.label.font = font
        
        self.label.frame = NSRect(
            x: (size.width - sSize.width) / 2,
            y: (size.height - sSize.height) / 2,
            width: sSize.width,
            height: sSize.height
        )
    }
    
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
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: isActiveMode) }
}
