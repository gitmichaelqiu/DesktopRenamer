import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    private weak var labelManager: SpaceLabelManager? // Weak ref to read settings
    
    // State
    private var isActiveMode: Bool = true
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    // Base Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    
    // UPDATED Init
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        self.label = NSTextField(labelWithString: name)
        
        // ... (Screen Finding Logic - Same as before) ...
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
        contentView.layer?.cornerRadius = 20
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
        
        // ... (Observers - Same as before) ...
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
    
    // MARK: - Public API
    
    func refreshAppearance() {
        // Called when sliders move
        // Force re-layout in current mode
        updateLayout(isCurrentSpace: self.isActiveMode)
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
            // Preview -> Active (Fade Out -> Snap)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0.0
            } completionHandler: {
                self.updateLayout(isCurrentSpace: true)
                self.alphaValue = 1.0
            }
        } else {
            // Active -> Preview (Instant)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.0
                self.updateLayout(isCurrentSpace: false)
                self.alphaValue = 1.0
            }
        }
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }
    
    // MARK: - Layout Logic
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        let targetFrame = targetScreen.frame
        var newSize: NSSize
        var newOrigin: NSPoint
        
        if isCurrentSpace {
            // MODE A: Active (Small)
            // UPDATED: Calculate using dynamic settings
            newSize = calculateActiveSize()
            newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
        } else {
            // MODE B: Preview (Large)
            newSize = previewSize
            newOrigin = NSPoint(
                x: targetFrame.midX - (newSize.width / 2),
                y: targetFrame.midY - (newSize.height / 2)
            )
        }
        
        self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        
        updateLabelFont(for: newSize, isSmallMode: isCurrentSpace)
    }
    
    // MARK: - Helpers
    
    private func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        
        let fontSize = SpaceLabelWindow.baseActiveFontSize * scaleF
        let basePadH: CGFloat = 60
        let basePadV: CGFloat = 40
        
        let name = self.label.stringValue
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let size = name.size(withAttributes: [.font: font])
        
        return NSSize(width: size.width + (basePadH * scaleP), height: size.height + (basePadV * scaleP))
    }
    
    private func updateLabelFont(for size: NSSize, isSmallMode: Bool) {
        let name = self.label.stringValue
        
        // Dynamic Padding for Shrink Loop
        // We use the same multipliers to determine the safe area
        let paddingScale = CGFloat(isSmallMode ? (labelManager?.activePaddingScale ?? 1.0) : (labelManager?.previewPaddingScale ?? 1.0))
        let fontScale = CGFloat(isSmallMode ? (labelManager?.activeFontScale ?? 1.0) : (labelManager?.previewFontScale ?? 1.0))
        
        // Base padding roughly 10-15% of width, scaled by user pref
        let paddingH: CGFloat = (size.width * 0.1) * paddingScale
        let paddingV: CGFloat = (size.height * 0.15) * paddingScale
        
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV
        
        let baseSize = isSmallMode ? SpaceLabelWindow.baseActiveFontSize : SpaceLabelWindow.basePreviewFontSize
        var fontSize = baseSize * fontScale
        
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
    
    // ... (findTargetScreen, findBestOffscreenPosition, repositionWindow - Same as before) ...
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
