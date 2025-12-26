import Cocoa
import Combine

// MARK: - Custom Handle View (The "Pill")
class CollapsibleHandleView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let imageView: NSImageView
    
    var edge: NSRectEdge = .maxX {
        didSet { updateChevron() }
    }
    
    init() {
        // 1. Background: Visual Effect View (Glassy Pill)
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow // Darker, floating UI style
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true
        
        // 2. Icon: Chevron
        imageView = NSImageView()
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .bold)
        imageView.contentTintColor = .white.withAlphaComponent(0.9)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: .zero)
        
        // Layout
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            // Fill background
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Center icon
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        // Tracking Area for Hover effect
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        
        updateChevron()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateChevron() {
        // Point inward to indicate "Click to Expand" or "Pull to Expand"
        let symbolName: String
        switch edge {
        case .minX: symbolName = "chevron.right" // Left Edge -> Point Right
        case .maxX: symbolName = "chevron.left"  // Right Edge -> Point Left
        case .minY: symbolName = "chevron.up"    // Bottom Edge -> Point Up
        case .maxY: symbolName = "chevron.down"  // Top Edge -> Point Down
        default:    symbolName = "chevron.left"
        }
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Expand")
    }
    
    // MARK: - Hover Effects
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.visualEffectView.animator().material = .popover // Lighter on hover
            self.imageView.animator().contentTintColor = .white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.visualEffectView.animator().material = .hudWindow // Back to dark
            self.imageView.animator().contentTintColor = .white.withAlphaComponent(0.9)
        }
    }
}

// MARK: - Main Window Class
class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    private let handleView: CollapsibleHandleView
    
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    private weak var labelManager: SpaceLabelManager?
    
    // State
    private var isActiveMode: Bool = true
    private var isDocked: Bool = false // Changed default to false to prevent premature docking
    private var dockEdge: NSRectEdge = .maxX
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    // Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    static let handleSize = NSSize(width: 24, height: 60)
    static let dockSnapThreshold: CGFloat = 60.0
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        // 1. Text Label (Standard)
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor
        
        // 2. Handle View (Collapsed)
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        
        // Screen Logic
        let foundScreen = NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == displayID { return true }
            let cleanName = displayID.components(separatedBy: " (").first ?? displayID
            return screen.localizedName == cleanName
        }
        let targetScreen = foundScreen ?? NSScreen.main!
        let screenFrame = targetScreen.frame
        
        // Start centered initially
        let startRect = NSRect(x: screenFrame.midX - 100, y: screenFrame.midY - 50, width: 200, height: 100)
        
        super.init(contentRect: startRect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        // Main Container
        let contentView = NSView(frame: .zero)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        
        // Visual Effect for the main Label (Glassy background for text)
        // We add a visual effect view backing for the label mode to ensure contrast
        let bgView = NSVisualEffectView()
        bgView.blendingMode = .behindWindow
        bgView.material = .popover
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 20
        bgView.autoresizingMask = [.width, .height]
        
        contentView.addSubview(bgView) // Background
        contentView.addSubview(self.label)
        contentView.addSubview(self.handleView)
        
        // Handle Layout
        self.handleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.handleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            self.handleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            self.handleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            self.handleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        self.contentView = contentView
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateLayout(isCurrentSpace: self.isActiveMode)
            self.updateVisibility(animated: false)
            self.updateInteractivity()
        }
    }
    
    // MARK: - Public API
    
    func refreshAppearance() {
        updateInteractivity()
        updateLayout(isCurrentSpace: self.isActiveMode)
        updateVisibility(animated: true)
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
            if let manager = labelManager, !manager.showOnDesktop {
                // If "Show on Desktop" is OFF, we force docked-like state (invisible/corner)
                // But specifically for the invisible style logic.
                // The prompt says "Do not modify the style of the invisible space label".
                // Our logic below in updateLayout handles the "Invisible" case via `showOnDesktop` check.
            }
        } else {
            // Reset docking when going to preview mode
            self.isDocked = false
        }
        
        updateLayout(isCurrentSpace: isCurrentSpace)
        updateVisibility(animated: true)
        updateInteractivity()
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }
    
    // MARK: - Interactions
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }
        
        let startOrigin = self.frame.origin
        
        // Perform system window drag
        self.performDrag(with: event)
        
        // Logic runs AFTER drag is released
        let endOrigin = self.frame.origin
        
        // Check if it was a click (little to no movement)
        let movedX = abs(endOrigin.x - startOrigin.x)
        let movedY = abs(endOrigin.y - startOrigin.y)
        let wasClick = (movedX < 2 && movedY < 2)
        
        if wasClick && isDocked {
            // Click on docked handle -> Expand
            self.isDocked = false
            animateFrameChange()
        } else {
            // End of Drag -> Check if we should snap to edge
            checkEdgeDocking()
        }
    }
    
    private func checkEdgeDocking() {
        guard let screen = self.screen else { return }
        
        let windowFrame = self.frame
        let screenFrame = screen.visibleFrame
        
        // Calculate distances to edges
        let distLeft = abs(windowFrame.minX - screenFrame.minX)
        let distRight = abs(windowFrame.maxX - screenFrame.maxX)
        let distTop = abs(windowFrame.maxY - screenFrame.maxY)
        let distBottom = abs(windowFrame.minY - screenFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        let isNearEdge = minDist < SpaceLabelWindow.dockSnapThreshold
        
        // Determine closest edge
        if minDist == distLeft { self.dockEdge = .minX }
        else if minDist == distRight { self.dockEdge = .maxX }
        else if minDist == distTop { self.dockEdge = .maxY }
        else { self.dockEdge = .minY }
        
        if isNearEdge {
            if !self.isDocked {
                self.isDocked = true
                animateFrameChange()
            } else {
                // Already docked, but drag might have offset it slightly. Snap it back tight.
                animateFrameChange()
            }
        } else {
            if self.isDocked {
                // Dragged away from edge -> Undock
                self.isDocked = false
                animateFrameChange()
            }
        }
    }
    
    private func animateFrameChange() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction()
            updateLayout(isCurrentSpace: true)
        }
    }
    
    private func updateInteractivity() {
        // If we are on desktop and active, we want to catch mouse events
        let isInteractive = (labelManager?.showOnDesktop == true) && isActiveMode
        self.ignoresMouseEvents = !isInteractive
        self.isMovableByWindowBackground = false // We handle drag manually in mouseDown
    }
    
    // MARK: - Layout Logic
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        // --- 1. DOCKED MODE (Interactive Pill) ---
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        
        if showHandle {
            // Style: Pill
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            
            // Hide the background glass of the content view, rely on HandleView's visual effect
            if let bgView = self.contentView?.subviews.first(where: { $0 is NSVisualEffectView }) {
                bgView.isHidden = true
            }
            
            // Size based on orientation
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize // Vertical Pill
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width) // Horizontal Pill
            }
            
            // Initial positioning logic
            // We set frame to size 0 first to prevent visual glitches? No, calculate target.
            self.contentView?.layer?.cornerRadius = 12
            
            let tempFrame = NSRect(origin: self.frame.origin, size: newSize)
            newOrigin = findSnappedEdgePosition(for: tempFrame, screen: targetScreen)
            
        } else {
            // --- 2. LABEL MODE (Standard Text) ---
            self.label.isHidden = false
            self.handleView.isHidden = true
            
            // Show background glass
            if let bgView = self.contentView?.subviews.first(where: { $0 is NSVisualEffectView }) {
                bgView.isHidden = false
            }
            
            self.contentView?.layer?.cornerRadius = 20
            
            if isCurrentSpace {
                if labelManager?.showOnDesktop == true {
                     // 2a. Interactive Floating (Large Text)
                     newSize = calculatePreviewLikeSize()
                     
                     // Expand from center of current window position
                     let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                     newOrigin = NSPoint(x: currentCenter.x - (newSize.width / 2), y: currentCenter.y - (newSize.height / 2))
                     
                     // Keep on screen
                     newOrigin.x = max(targetScreen.frame.minX, min(newOrigin.x, targetScreen.frame.maxX - newSize.width))
                     newOrigin.y = max(targetScreen.frame.minY, min(newOrigin.y, targetScreen.frame.maxY - newSize.height))
                     
                     updateLabelFont(for: newSize, isSmallMode: false)
                } else {
                    // 2b. Invisible Active (Small Text, Hidden Corner) - PRESERVED STYLE
                    // Note: User said "Do not modify the style of the invisible space label"
                    // This branch handles the "Classic" invisible behavior.
                    newSize = calculateActiveSize()
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                    updateLabelFont(for: newSize, isSmallMode: true)
                }
            } else {
                // 2c. Preview Mode (Mission Control) - PRESERVED STYLE
                newSize = previewSize
                newOrigin = NSPoint(
                    x: targetScreen.frame.midX - (newSize.width / 2),
                    y: targetScreen.frame.midY - (newSize.height / 2)
                )
                updateLabelFont(for: newSize, isSmallMode: false)
            }
        }
        
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }
    
    // MARK: - Calculation Helpers
    
    private func findSnappedEdgePosition(for rect: NSRect, screen: NSScreen) -> NSPoint {
        let sFrame = screen.visibleFrame
        var origin = rect.origin
        let size = rect.size
        
        switch self.dockEdge {
        case .minX: // Left
            origin.x = sFrame.minX
            // Clamp Y
            origin.y = max(sFrame.minY, min(origin.y, sFrame.maxY - size.height))
        case .maxX: // Right
            origin.x = sFrame.maxX - size.width
            // Clamp Y
            origin.y = max(sFrame.minY, min(origin.y, sFrame.maxY - size.height))
        case .minY: // Bottom
            origin.y = sFrame.minY
            // Clamp X
            origin.x = max(sFrame.minX, min(origin.x, sFrame.maxX - size.width))
        case .maxY: // Top
            origin.y = sFrame.maxY - size.height
            // Clamp X
            origin.x = max(sFrame.minX, min(origin.x, sFrame.maxX - size.width))
        @unknown default:
            break
        }
        
        return origin
    }
    
    private func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        return calculateSize(baseFont: SpaceLabelWindow.baseActiveFontSize * scaleF, paddingScale: scaleP, basePadH: 60, basePadV: 40)
    }
    
    private func calculatePreviewLikeSize() -> NSSize {
        // Floating interactive uses a slightly smaller scale than Mission Control Preview
        let scaleF = CGFloat(labelManager?.previewFontScale ?? 1.0) * 0.5
        let scaleP = CGFloat(labelManager?.previewPaddingScale ?? 1.0) * 0.5
        return calculateSize(baseFont: SpaceLabelWindow.basePreviewFontSize * scaleF, paddingScale: scaleP, basePadH: 100, basePadV: 80)
    }
    
    private func calculateSize(baseFont: CGFloat, paddingScale: CGFloat, basePadH: CGFloat, basePadV: CGFloat) -> NSSize {
        let name = self.label.stringValue
        let font = NSFont.systemFont(ofSize: baseFont, weight: .bold)
        let size = name.size(withAttributes: [.font: font])
        return NSSize(width: size.width + (basePadH * paddingScale), height: size.height + (basePadV * paddingScale))
    }
    
    private func updateLabelFont(for size: NSSize, isSmallMode: Bool) {
        let name = self.label.stringValue
        let paddingScale: CGFloat
        let fontScale: CGFloat
        let baseSize: CGFloat
        
        if isSmallMode {
            paddingScale = CGFloat(labelManager?.activePaddingScale ?? 1.0)
            fontScale = CGFloat(labelManager?.activeFontScale ?? 1.0)
            baseSize = SpaceLabelWindow.baseActiveFontSize
        } else {
            paddingScale = CGFloat(labelManager?.previewPaddingScale ?? 1.0)
            fontScale = CGFloat(labelManager?.previewFontScale ?? 1.0)
            baseSize = SpaceLabelWindow.basePreviewFontSize
        }
        
        let paddingH: CGFloat = (size.width * 0.1) * paddingScale
        let paddingV: CGFloat = (size.height * 0.15) * paddingScale
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV
        
        var fontSize = baseSize * fontScale
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var sSize = name.size(withAttributes: [.font: font])
        
        // Iteratively shrink font if it doesn't fit
        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            sSize = name.size(withAttributes: [.font: font])
        }
        
        self.label.font = font
        let displayHeight = sSize.height + 4
        self.label.frame = NSRect(x: 0, y: (size.height - displayHeight) / 2, width: size.width, height: displayHeight)
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
        let f = targetScreen.frame
        // Position just offscreen bottom-right, used for the "Hidden" Active Mode
        return NSPoint(x: f.minX - size.width + 1, y: f.maxY - 1)
    }
    
    private func updateVisibility(animated: Bool) {
        let showActive = labelManager?.showActiveLabels ?? true
        let showPreview = labelManager?.showPreviewLabels ?? true
        let shouldBeVisible = isActiveMode ? showActive : showPreview
        
        if shouldBeVisible {
            if !self.isVisible {
                self.alphaValue = 0.0
                self.orderFront(nil)
            }
            if animated {
                self.animator().alphaValue = 1.0
            } else {
                self.alphaValue = 1.0
            }
        } else {
            if !self.isVisible { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.animator().alphaValue = 0.0
                } completionHandler: {
                    if !shouldBeVisible { self.orderOut(nil) }
                }
            } else {
                self.alphaValue = 0.0
                self.orderOut(nil)
            }
        }
    }
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: isActiveMode) }
}
