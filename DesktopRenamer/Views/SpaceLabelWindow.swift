import Cocoa
import Combine

// MARK: - Native "Glass" Handle View
class CollapsibleHandleView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let imageView: NSImageView
    
    var edge: NSRectEdge = .maxX {
        didSet { updateChevron() }
    }
    
    init() {
        // 1. Native Blur Background
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow // Native dark/glass look
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true
        
        // 2. Icon
        imageView = NSImageView()
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: .zero)
        
        // Layout
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            // Background fills view
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Icon centered
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateChevron()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateChevron() {
        let symbolName: String
        switch edge {
        case .minX: symbolName = "chevron.compact.right"
        case .maxX: symbolName = "chevron.compact.left"
        case .minY: symbolName = "chevron.compact.up"
        case .maxY: symbolName = "chevron.compact.down"
        default:    symbolName = "chevron.compact.left"
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
    static let handleSize = NSSize(width: 28, height: 64) // Polished native dimensions
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        // 1. Label
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor
        
        // 2. Handle
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        
        // Screen Finding
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
        
        // Use Glass Effect for Main Background too
        let contentView = NSVisualEffectView(frame: .zero)
        contentView.material = .hudWindow
        contentView.state = .active
        contentView.blendingMode = .behindWindow
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true
        
        contentView.addSubview(self.label)
        contentView.addSubview(self.handleView)
        
        self.contentView = contentView
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false // Shadow handled by effect view or disable for cleaner look
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
        
        updateLayout(isCurrentSpace: isCurrentSpace)
        updateVisibility(animated: true)
        updateInteractivity()
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }
    
    // MARK: - Interaction Logic (Click vs Drag)
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }
        
        let startOrigin = self.frame.origin
        
        // 1. Perform Drag (Blocks until release)
        self.performDrag(with: event)
        
        let endOrigin = self.frame.origin
        
        // 2. Calculate Movement
        let movedX = abs(endOrigin.x - startOrigin.x)
        let movedY = abs(endOrigin.y - startOrigin.y)
        let distance = sqrt(movedX*movedX + movedY*movedY)
        
        // 3. Logic: Click (< 5px move) vs Drag
        if distance < 5 {
            // It was a click!
            if self.isDocked {
                // Clicked handle -> Expand
                self.isDocked = false
                animateFrameChange()
            }
        } else {
            // It was a drag!
            checkEdgeDocking()
        }
    }
    
    private func checkEdgeDocking() {
        guard let screen = self.screen else { return }
        
        let windowFrame = self.frame
        let screenFrame = screen.visibleFrame
        let threshold: CGFloat = 50.0
        
        let distLeft = abs(windowFrame.minX - screenFrame.minX)
        let distRight = abs(windowFrame.maxX - screenFrame.maxX)
        let distTop = abs(windowFrame.maxY - screenFrame.maxY)
        let distBottom = abs(windowFrame.minY - screenFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        let isNearEdge = minDist < threshold
        
        if minDist == distLeft { self.dockEdge = .minX }
        else if minDist == distRight { self.dockEdge = .maxX }
        else if minDist == distTop { self.dockEdge = .maxY }
        else { self.dockEdge = .minY }
        
        if isNearEdge {
            if !self.isDocked {
                self.isDocked = true
                animateFrameChange()
            } else {
                animateFrameChange() // Snap to edge
            }
        } else {
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
        
        // Is this the "Interactive Handle" Mode?
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        
        // Access visual effect view
        let visualView = self.contentView as? NSVisualEffectView
        
        if showHandle {
            // --- HANDLE MODE ---
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            
            // Hide main background, let handle view draw its own background
            visualView?.material = .titlebar // Transparent-ish
            visualView?.state = .inactive
            visualView?.alphaValue = 0.0 // Hide main container background
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
            
            // Position handle inside window (fill)
            self.handleView.frame = NSRect(origin: .zero, size: newSize)
            
            newOrigin = findNearestEdgePosition(targetScreen: targetScreen, size: newSize)
            
        } else {
            // --- TEXT LABEL MODE ---
            self.label.isHidden = false
            self.handleView.isHidden = true
            
            // Restore main background
            visualView?.alphaValue = 1.0
            visualView?.state = .active
            visualView?.material = .hudWindow
            visualView?.layer?.cornerRadius = 16
            
            if isCurrentSpace {
                if labelManager?.showOnDesktop == true {
                     // Interactive Floating
                     newSize = calculatePreviewLikeSize()
                     
                     let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                     newOrigin = NSPoint(x: currentCenter.x - (newSize.width / 2), y: currentCenter.y - (newSize.height / 2))
                     newOrigin.x = max(targetScreen.frame.minX, min(newOrigin.x, targetScreen.frame.maxX - newSize.width))
                     newOrigin.y = max(targetScreen.frame.minY, min(newOrigin.y, targetScreen.frame.maxY - newSize.height))
                     
                     updateLabelFont(for: newSize, isSmallMode: false)
                } else {
                    // Non-Interactive Active (Hidden corner)
                    newSize = calculateActiveSize()
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                    updateLabelFont(for: newSize, isSmallMode: true)
                }
            } else {
                // Preview Mode
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
            paddingScale = CGFloat(labelManager?.previewPaddingScale ?? 1.0) * 0.5
            fontScale = CGFloat(labelManager?.previewFontScale ?? 1.0) * 0.5
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
        
        // Add padding (4pts) for a nice floating look
        let padding: CGFloat = 4.0
        
        if minDist == distLeft {
            finalOrigin.x = sFrame.minX + padding
            self.dockEdge = .minX
        } else if minDist == distRight {
            finalOrigin.x = sFrame.maxX - size.width - padding
            self.dockEdge = .maxX
        } else if minDist == distTop {
            finalOrigin.y = sFrame.maxY - size.height - padding
            self.dockEdge = .maxY
        } else {
            finalOrigin.y = sFrame.minY + padding
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
