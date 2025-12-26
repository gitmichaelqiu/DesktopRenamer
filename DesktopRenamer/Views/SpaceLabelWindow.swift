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
    static let handleSize = NSSize(width: 32, height: 60)
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        // 1. Text Label
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor
        
        // 2. Handle View
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
        
        // Initial Sync
        syncFromGlobalState()
        
        DispatchQueue.main.async { [weak self] in
            self?.updateLayout(isCurrentSpace: true)
            self?.updateVisibility(animated: false)
            self?.updateInteractivity()
        }
    }
    
    // MARK: - State Synchronization
    
    private func syncFromGlobalState() {
        guard let manager = labelManager else { return }
        self.isDocked = manager.globalIsDocked
        self.dockEdge = manager.globalDockEdge
        
        // Apply default if needed
        if manager.globalCenterPoint == nil {
            if let screen = self.screen ?? NSScreen.main {
                let frame = screen.visibleFrame
                let defaultCenter = NSPoint(x: frame.maxX, y: frame.midY)
                manager.updateGlobalState(isDocked: true, edge: .maxX, center: defaultCenter)
                self.dockEdge = .maxX
                self.isDocked = true
            }
        }
    }
    
    private func pushToGlobalState() {
        guard let manager = labelManager else { return }
        let center = NSPoint(x: self.frame.midX, y: self.frame.midY)
        manager.updateGlobalState(isDocked: self.isDocked, edge: self.dockEdge, center: center)
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
            syncFromGlobalState()
            if let manager = labelManager, !manager.showOnDesktop {
                 self.isDocked = true
            }
        }
        
        self.updateLayout(isCurrentSpace: isCurrentSpace)
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
        
        var startMouseLocation = NSEvent.mouseLocation
        let startWindowOrigin = self.frame.origin
        var mouseOffset = NSPoint(x: startMouseLocation.x - startWindowOrigin.x,
                                  y: startMouseLocation.y - startWindowOrigin.y)
        var hasDragged = false
        
        while true {
            guard let nextEvent = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                                 until: .distantFuture,
                                                 inMode: .eventTracking,
                                                 dequeue: true) else { break }
            
            if nextEvent.type == .leftMouseUp {
                if !hasDragged {
                    toggleDockState()
                } else {
                    pushToGlobalState()
                }
                break
            }
            else if nextEvent.type == .leftMouseDragged {
                let currentMouseLocation = NSEvent.mouseLocation
                
                if !hasDragged {
                    let dx = currentMouseLocation.x - startMouseLocation.x
                    let dy = currentMouseLocation.y - startMouseLocation.y
                    if hypot(dx, dy) > 5.0 { hasDragged = true }
                }
                
                if hasDragged {
                    var targetOrigin = NSPoint(x: currentMouseLocation.x - mouseOffset.x,
                                               y: currentMouseLocation.y - mouseOffset.y)
                    
                    if let screen = self.screen {
                        let screenFrame = screen.visibleFrame
                        var didStateChange = false
                        
                        let distLeft = abs(currentMouseLocation.x - screenFrame.minX)
                        let distRight = abs(currentMouseLocation.x - screenFrame.maxX)
                        let distTop = abs(currentMouseLocation.y - screenFrame.maxY)
                        let distBottom = abs(currentMouseLocation.y - screenFrame.minY)
                        let minMouseEdgeDist = min(distLeft, distRight, distTop, distBottom)
                        
                        if !isDocked {
                            if minMouseEdgeDist < 15.0 {
                                isDocked = true
                                didStateChange = true
                                if minMouseEdgeDist == distLeft { self.dockEdge = .minX }
                                else if minMouseEdgeDist == distRight { self.dockEdge = .maxX }
                                else if minMouseEdgeDist == distTop { self.dockEdge = .maxY }
                                else { self.dockEdge = .minY }
                            }
                        } else {
                            if minMouseEdgeDist > 50.0 {
                                isDocked = false
                                didStateChange = true
                            }
                        }
                        
                        if didStateChange {
                            updateLayout(isCurrentSpace: true, updateFrame: false)
                            let newSize = self.frame.size
                            
                            let rootedOrigin = calculateCenteredOrigin(
                                forSize: newSize,
                                onEdge: self.dockEdge,
                                centerPoint: NSPoint(x: currentMouseLocation.x, y: currentMouseLocation.y),
                                screenFrame: screenFrame,
                                clampToScreen: !isDocked
                            )
                            targetOrigin = rootedOrigin
                            
                            self.setFrameOrigin(targetOrigin)
                            mouseOffset = NSPoint(x: currentMouseLocation.x - targetOrigin.x,
                                                  y: currentMouseLocation.y - targetOrigin.y)
                            startMouseLocation = currentMouseLocation
                            
                            pushToGlobalState()
                            continue
                        }
                        
                        if isDocked {
                            let rawRect = NSRect(origin: targetOrigin, size: self.frame.size)
                            let snappedOrigin = findNearestEdgePosition(targetScreen: screen, forRect: rawRect)
                            self.setFrameOrigin(snappedOrigin)
                        } else {
                            self.setFrameOrigin(targetOrigin)
                        }
                    }
                }
            }
        }
    }
    
    private func toggleDockState() {
        if self.isDocked {
            self.isDocked = false
            animateFrameChange()
        } else {
            if let screen = self.screen {
                _ = findNearestEdgePosition(targetScreen: screen, forRect: self.frame)
            }
            self.isDocked = true
            animateFrameChange()
        }
        pushToGlobalState()
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
    
    private func updateLayout(isCurrentSpace: Bool, updateFrame: Bool = true) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        var targetCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
        if let globalCenter = labelManager?.globalCenterPoint {
            targetCenter = globalCenter
        }
        
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        // Detect if we are in "Hidden Corner" mode (Active Space, but PiP disabled)
        let isHiddenCornerMode = isCurrentSpace && !showHandle && !(labelManager?.showOnDesktop == true)
        
        if showHandle {
            // --- DOCKED (Handle) ---
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            self.contentView?.layer?.cornerRadius = 12
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
            
            self.handleView.frame = NSRect(origin: .zero, size: newSize)
            newOrigin = calculateCenteredOrigin(
                forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: true
            )
            
        } else {
            // --- EXPANDED (Label) or HIDDEN ---
            self.label.isHidden = false
            self.handleView.isHidden = true
            self.contentView?.layer?.cornerRadius = 20
            
            if isCurrentSpace {
                if labelManager?.showOnDesktop == true {
                     // Interactive PiP
                     // STYLING FIX 1: Use Active Size (same as Hidden)
                     newSize = calculateActiveSize()
                     
                     newOrigin = calculateCenteredOrigin(
                        forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: false
                     )
                     // STYLING FIX 2: Use Active Font Settings
                     updateLabelFont(for: newSize, isSmallMode: true)
                } else {
                    // Legacy Hidden Corner
                    newSize = calculateActiveSize()
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                    updateLabelFont(for: newSize, isSmallMode: true)
                }
            } else {
                // Preview (Mission Control)
                newSize = previewSize
                newOrigin = NSPoint(
                    x: targetScreen.frame.midX - (newSize.width / 2),
                    y: targetScreen.frame.midY - (newSize.height / 2)
                )
                updateLabelFont(for: newSize, isSmallMode: false)
            }
        }
        
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
        
        if updateFrame {
            if isHiddenCornerMode {
                // ANIMATION FIX: Fade Out -> Jump -> Instant Appear
                // This prevents the label from sliding across the screen when disabling PiP
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().alphaValue = 0.0
                } completionHandler: {
                    self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                    self.alphaValue = 1.0 // Make it visible to system (offscreen)
                }
            } else {
                // Standard Animation
                self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                if self.alphaValue < 1.0 {
                    self.animator().alphaValue = 1.0
                }
            }
        } else {
            self.setFrame(NSRect(origin: self.frame.origin, size: newSize), display: true)
        }
    }
    
    // MARK: - Calculation Helpers
    
    private func calculateCenteredOrigin(forSize size: NSSize, onEdge edge: NSRectEdge, centerPoint: NSPoint, screenFrame: NSRect, clampToScreen: Bool) -> NSPoint {
        var origin = NSPoint.zero
        switch edge {
        case .minX: origin = NSPoint(x: screenFrame.minX, y: centerPoint.y - size.height/2)
        case .maxX: origin = NSPoint(x: screenFrame.maxX - size.width, y: centerPoint.y - size.height/2)
        case .minY: origin = NSPoint(x: centerPoint.x - size.width/2, y: screenFrame.minY)
        case .maxY: origin = NSPoint(x: centerPoint.x - size.width/2, y: screenFrame.maxY - size.height)
        @unknown default: origin = NSPoint(x: centerPoint.x - size.width/2, y: centerPoint.y - size.height/2)
        }
        
        if clampToScreen {
            if edge == .minX || edge == .maxX {
                origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
            } else {
                origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
            }
        }
        return origin
    }
    
    private func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        return calculateSize(baseFont: SpaceLabelWindow.baseActiveFontSize * scaleF, paddingScale: scaleP, basePadH: 60, basePadV: 40)
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
        
        // STYLING FIX: Interactive mode now treated as "SmallMode" for font calculation
        // to ensure it matches the Hidden Label settings.
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
    
    private func findNearestEdgePosition(targetScreen: NSScreen, forRect rect: NSRect) -> NSPoint {
        let size = rect.size
        let sFrame = targetScreen.visibleFrame
        let distLeft = abs(rect.minX - sFrame.minX)
        let distRight = abs(rect.maxX - sFrame.maxX)
        let distTop = abs(rect.maxY - sFrame.maxY)
        let distBottom = abs(rect.minY - sFrame.minY)
        let minDist = min(distLeft, distRight, distTop, distBottom)
        
        var finalOrigin = rect.origin
        if minDist == distLeft { finalOrigin.x = sFrame.minX; self.dockEdge = .minX }
        else if minDist == distRight { finalOrigin.x = sFrame.maxX - size.width; self.dockEdge = .maxX }
        else if minDist == distTop { finalOrigin.y = sFrame.maxY - size.height; self.dockEdge = .maxY }
        else { finalOrigin.y = sFrame.minY; self.dockEdge = .minY }
        
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
            if !self.isVisible { self.alphaValue = 0.0; self.orderFront(nil) }
            if animated { self.animator().alphaValue = 1.0 } else { self.alphaValue = 1.0 }
        } else {
            if !self.isVisible { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.animator().alphaValue = 0.0
                } completionHandler: { if !shouldBeVisible { self.orderOut(nil) } }
            } else { self.alphaValue = 0.0; self.orderOut(nil) }
        }
    }
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: isActiveMode) }
}
