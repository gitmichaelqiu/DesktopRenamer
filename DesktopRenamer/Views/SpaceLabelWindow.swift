import Cocoa
import Combine

// MARK: - Custom Handle View (The "Pill")
class CollapsibleHandleView: NSView {
    private let imageView: NSImageView
    
    var edge: NSRectEdge = .maxX {
        didSet { updateChevron() }
    }
    
    init() {
        imageView = NSImageView()
        super.init(frame: .zero)
        
        self.wantsLayer = true
        // FIX: Removed manual background color to let the parent VisualEffectView (Glass) shine through.
        self.layer?.cornerRadius = 12
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .bold)
        imageView.contentTintColor = .labelColor
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateChevron()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateChevron() {
        // Point inward to indicate "Expand"
        let symbolName: String
        switch edge {
        case .minX: symbolName = "chevron.right"
        case .maxX: symbolName = "chevron.left"
        case .minY: symbolName = "chevron.up"
        case .maxY: symbolName = "chevron.down"
        default:    symbolName = "chevron.left"
        }
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Expand")
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
    private var isDocked: Bool = true
    private var dockEdge: NSRectEdge = .maxX
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    // Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    
    // FIX: Increased handle width to 32 for better clickability
    static let handleSize = NSSize(width: 32, height: 60)
    
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
        
        contentView.addSubview(self.label)
        contentView.addSubview(self.handleView)
        
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
            self?.updateLayout(isCurrentSpace: true)
            self?.updateVisibility(animated: false)
            self?.updateInteractivity()
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
                 self.isDocked = true
             }
        }
        
        if isCurrentSpace {
            self.updateLayout(isCurrentSpace: true)
        } else {
            self.updateLayout(isCurrentSpace: false)
        }
        
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
        
        // Record start position to detect Click vs Drag
        let originalOrigin = self.frame.origin
        
        // Blocks until mouseUp
        self.performDrag(with: event)
        
        let newOrigin = self.frame.origin
        let distance = hypot(newOrigin.x - originalOrigin.x, newOrigin.y - originalOrigin.y)
        
        // Threshold for "Click" (5 points)
        if distance < 5.0 {
            // --- HANDLE CLICK (Toggle) ---
            if self.isDocked {
                // Clicked Handle -> EXPAND
                self.isDocked = false
                animateFrameChange()
            } else {
                // Clicked Label -> COLLAPSE
                // Update dockEdge relative to where the window currently is
                if let screen = self.screen {
                     // We run this just to update `self.dockEdge` before collapsing
                    _ = findNearestEdgePosition(targetScreen: screen, size: SpaceLabelWindow.handleSize)
                }
                self.isDocked = true
                animateFrameChange()
            }
        } else {
            // --- HANDLE DRAG ---
            // If dragging, we ONLY change state if dragging to/from edge
            checkEdgeDocking()
        }
    }
    
    private func checkEdgeDocking() {
        guard let screen = self.screen else { return }
        
        let windowFrame = self.frame
        let screenFrame = screen.visibleFrame
        let threshold: CGFloat = 50.0 // Distance to snap
        
        let distLeft = abs(windowFrame.minX - screenFrame.minX)
        let distRight = abs(windowFrame.maxX - screenFrame.maxX)
        let distTop = abs(windowFrame.maxY - screenFrame.maxY)
        let distBottom = abs(windowFrame.minY - screenFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        let isNearEdge = minDist < threshold
        
        // Determine which edge is closest
        if minDist == distLeft { self.dockEdge = .minX }
        else if minDist == distRight { self.dockEdge = .maxX }
        else if minDist == distTop { self.dockEdge = .maxY }
        else { self.dockEdge = .minY }
        
        if isNearEdge {
            // If near edge, SNAP TO DOCK
            if !self.isDocked {
                self.isDocked = true
                animateFrameChange()
            } else {
                // Already docked, just snap to perfect position
                animateFrameChange()
            }
        } else {
            // If dragged away from edge, EXPAND
            if self.isDocked {
                self.isDocked = false
                animateFrameChange()
            }
        }
    }
    
    private func animateFrameChange() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            updateLayout(isCurrentSpace: true)
        }
    }
    
    private func updateInteractivity() {
        let isInteractive = (labelManager?.showOnDesktop == true) && isActiveMode
        self.ignoresMouseEvents = !isInteractive
        self.isMovableByWindowBackground = false
    }
    
    // MARK: - Layout Logic
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        // --- 1. HANDLE MODE (Interactive & Docked) ---
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        
        if showHandle {
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            
            // Handle Styling
            self.contentView?.layer?.cornerRadius = 12
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
            
            self.handleView.frame = NSRect(origin: .zero, size: newSize)
            newOrigin = findNearestEdgePosition(targetScreen: targetScreen, size: newSize)
            
        } else {
            // --- 2. LABEL MODE (Standard Text) ---
            self.label.isHidden = false
            self.handleView.isHidden = true
            
            // Restore Original Styling
            self.contentView?.layer?.cornerRadius = 20
            
            if isCurrentSpace {
                // ACTIVE MODE
                if labelManager?.showOnDesktop == true {
                     // 2a. Interactive Floating (Large Text)
                     newSize = calculatePreviewLikeSize()
                     
                     // Expand from center of current position
                     let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                     newOrigin = NSPoint(x: currentCenter.x - (newSize.width / 2), y: currentCenter.y - (newSize.height / 2))
                     
                     // Keep on screen
                     newOrigin.x = max(targetScreen.frame.minX, min(newOrigin.x, targetScreen.frame.maxX - newSize.width))
                     newOrigin.y = max(targetScreen.frame.minY, min(newOrigin.y, targetScreen.frame.maxY - newSize.height))
                     
                     updateLabelFont(for: newSize, isSmallMode: false)
                } else {
                    // 2b. Invisible Active (Small Text, Hidden Corner) - PRESERVED
                    newSize = calculateActiveSize()
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                    updateLabelFont(for: newSize, isSmallMode: true)
                }
            } else {
                // 2c. Preview Mode (Mission Control) - PRESERVED
                newSize = previewSize
                newOrigin = NSPoint(
                    x: targetScreen.frame.midX - (newSize.width / 2),
                    y: targetScreen.frame.midY - (newSize.height / 2)
                )
                updateLabelFont(for: newSize, isSmallMode: false)
            }
        }
        
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        self.contentView?.animator().frame = NSRect(origin: .zero, size: newSize)
    }
    
    // MARK: - Calculation Helpers
    
    private func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        return calculateSize(baseFont: SpaceLabelWindow.baseActiveFontSize * scaleF, paddingScale: scaleP, basePadH: 60, basePadV: 40)
    }
    
    private func calculatePreviewLikeSize() -> NSSize {
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
        return NSPoint(x: f.minX - size.width + 1, y: f.maxY - 1)
    }
    
    private func findNearestEdgePosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let currentRect = self.frame
        let sFrame = targetScreen.visibleFrame
        
        let distLeft = abs(currentRect.minX - sFrame.minX)
        let distRight = abs(currentRect.maxX - sFrame.maxX)
        let distTop = abs(currentRect.maxY - sFrame.maxY)
        let distBottom = abs(currentRect.minY - sFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        
        var finalOrigin = currentRect.origin
        
        // FIX: Removed +2 gap to ensure flush docking.
        if minDist == distLeft {
            finalOrigin.x = sFrame.minX
            self.dockEdge = .minX
        } else if minDist == distRight {
            finalOrigin.x = sFrame.maxX - size.width
            self.dockEdge = .maxX
        } else if minDist == distTop {
            finalOrigin.y = sFrame.maxY - size.height
            self.dockEdge = .maxY
        } else {
            finalOrigin.y = sFrame.minY
            self.dockEdge = .minY
        }
        
        if minDist == distLeft || minDist == distRight {
            finalOrigin.y = max(sFrame.minY, min(finalOrigin.y, sFrame.maxY - size.height))
        } else {
            finalOrigin.x = max(sFrame.minX, min(finalOrigin.x, sFrame.maxX - size.width))
        }
        
        return finalOrigin
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
