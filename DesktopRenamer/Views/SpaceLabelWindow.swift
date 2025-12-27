import Cocoa
import Combine
import QuartzCore

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
    
    // Position State
    private var savedFloatingCenter: NSPoint? = nil
    
    // Logic Flags
    private var isFirstRun: Bool = true
    private var previousActiveMode: Bool = false
    
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
        self.handleView.autoresizingMask = [.width, .height]
        
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
        
        super.init(contentRect: startRect, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        
        // 3. Configure Visual/Glass Effect View
        let contentView: NSView
        if #available(macOS 26.0, *) {
            contentView = NSGlassEffectView(frame: .zero)
        } else {
            let effectView = NSVisualEffectView(frame: .zero)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            contentView = effectView
        }
        
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        
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
        
        // Initialize
        syncFromGlobalState()
        setupLiveBackgroundUpdate()
        
        DispatchQueue.main.async { [weak self] in
            // Initial layout
            self?.updateState()
            self?.isFirstRun = false
            self?.previousActiveMode = self?.isActiveMode ?? true
            self?.updateInteractivity()
        }
    }
    
    // MARK: - Live Background Hack
    
    private func setupLiveBackgroundUpdate() {
        guard let layer = self.contentView?.layer else { return }
        let key = "forceRedrawLoop"
        if layer.animation(forKey: key) == nil {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.9999
            anim.duration = 1.0
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: key)
        }
    }
    
    // MARK: - State Synchronization
    
    private func syncFromGlobalState() {
        guard let manager = labelManager else { return }
        self.isDocked = manager.globalIsDocked
        self.dockEdge = manager.globalDockEdge
        
        if manager.globalCenterPoint == nil {
            let defaultRelative = NSPoint(x: 1.0, y: 0.5)
            manager.updateGlobalState(isDocked: true, edge: .maxX, center: defaultRelative)
            self.dockEdge = .maxX
            self.isDocked = true
        } else if let point = manager.globalCenterPoint {
            if point.x > 2.0 || point.y > 2.0 {
                let defaultRelative = NSPoint(x: 1.0, y: 0.5)
                manager.updateGlobalState(isDocked: true, edge: .maxX, center: defaultRelative)
                self.dockEdge = .maxX
                self.isDocked = true
            }
        }
    }
    
    private func pushToGlobalState() {
        guard let manager = labelManager, let screen = self.screen else { return }
        let currentAbsCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
        
        let sFrame = screen.visibleFrame
        let relX = (currentAbsCenter.x - sFrame.minX) / sFrame.width
        let relY = (currentAbsCenter.y - sFrame.minY) / sFrame.height
        
        manager.updateGlobalState(isDocked: self.isDocked, edge: self.dockEdge, center: NSPoint(x: relX, y: relY))
    }
    
    // MARK: - Reset Logic
    
    private func resetToCenter() {
        guard let screen = findTargetScreen() else { return }
        
        self.isDocked = false
        self.savedFloatingCenter = nil
        
        // Reset Global State
        labelManager?.updateGlobalState(isDocked: false, edge: self.dockEdge, center: NSPoint(x: 0.5, y: 0.5))
    }
    
    // MARK: - Helper: Position Calculation
    
    private func getNaiveAbsoluteCenter(on screen: NSScreen) -> NSPoint {
        let relativePoint = labelManager?.globalCenterPoint ?? NSPoint(x: 1.0, y: 0.5)
        let sFrame = screen.visibleFrame
        let absX = sFrame.minX + (sFrame.width * relativePoint.x)
        let absY = sFrame.minY + (sFrame.height * relativePoint.y)
        return NSPoint(x: absX, y: absY)
    }
    
    // MARK: - Public API
    
    func refreshAppearance() {
        updateInteractivity()
        updateState()
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
        self.previousActiveMode = self.isActiveMode
        self.isActiveMode = isCurrentSpace
        
        if isCurrentSpace {
            syncFromGlobalState()
            if let manager = labelManager, !manager.showOnDesktop {
                 self.isDocked = true
            }
        }
        
        updateState()
        updateInteractivity()
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        updateState()
    }
    
    // MARK: - Main Pipeline: Layout & Visibility & Animation
    
    private func updateState() {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        // --- 1. Determine Visibility Intent ---
        let showActive = labelManager?.showActiveLabels ?? true
        let showPreview = labelManager?.showPreviewLabels ?? true
        
        // Corner Hidden Mode: Active Space + "Show on Desktop" is OFF
        // (Position is independent of current Show Active Toggle)
        let isCornerHidden = isActiveMode && !(labelManager?.showOnDesktop == true)
        
        // Base visibility
        let shouldBeVisible = isActiveMode ? showActive : showPreview

        // --- 2. Check for Manual Toggle (Center Reset) ---
        // Condition: Active Mode + Not First Run + Not Space Switch + Was Invisible -> Becoming Visible
        if shouldBeVisible && isActiveMode && !isCornerHidden && !isFirstRun {
            let isSpaceSwitch = (isActiveMode != previousActiveMode)
            let wasInvisible = (self.alphaValue == 0 || !self.isVisible)
            
            if !isSpaceSwitch && wasInvisible {
                resetToCenter()
            }
        }
        
        // --- 3. Determine Layout (Size & Position) ---
        var newSize: NSSize
        var newOrigin: NSPoint
        
        let showHandle = isActiveMode && isDocked && (labelManager?.showOnDesktop == true)
        
        // A) Size & Styling
        if showHandle {
            // DOCKED (Pill)
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            self.contentView?.layer?.cornerRadius = 12
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
        } else if isActiveMode {
             // EXPANDED / HIDDEN
             self.label.isHidden = false
             self.handleView.isHidden = true
             self.contentView?.layer?.cornerRadius = 20
             newSize = calculateActiveSize()
             // Note: Label Font update happens in closure below
        } else {
            // PREVIEW
            self.label.isHidden = false
            self.handleView.isHidden = true
            self.contentView?.layer?.cornerRadius = 20
            newSize = previewSize
            // Note: Label Font update happens in closure below
        }
        
        // B) Position Calculation
        let naiveCenter = isActiveMode ? getNaiveAbsoluteCenter(on: targetScreen) : NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
        
        if showHandle {
            // Docked: Strict Snap
            newOrigin = calculateCenteredOrigin(forSize: newSize, onEdge: self.dockEdge, centerPoint: naiveCenter, screenFrame: targetScreen.visibleFrame)
        } else if isActiveMode {
            if isCornerHidden {
                // [RESTORED] Force offscreen position if in Corner Hidden mode.
                newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
            } else {
                // Visible Expanded: Magnetic Snap
                var calculatedOrigin = NSPoint(x: naiveCenter.x - newSize.width/2, y: naiveCenter.y - newSize.height/2)
                let sFrame = targetScreen.visibleFrame
                let snapThreshold: CGFloat = 20.0
                
                if abs(calculatedOrigin.x - sFrame.minX) < snapThreshold { calculatedOrigin.x = sFrame.minX }
                else if abs(calculatedOrigin.x + newSize.width - sFrame.maxX) < snapThreshold { calculatedOrigin.x = sFrame.maxX - newSize.width }
                
                if abs(calculatedOrigin.y - sFrame.minY) < snapThreshold { calculatedOrigin.y = sFrame.minY }
                else if abs(calculatedOrigin.y + newSize.height - sFrame.maxY) < snapThreshold { calculatedOrigin.y = sFrame.maxY - newSize.height }
                
                calculatedOrigin.x = max(sFrame.minX, min(calculatedOrigin.x, sFrame.maxX - newSize.width))
                calculatedOrigin.y = max(sFrame.minY, min(calculatedOrigin.y, sFrame.maxY - newSize.height))
                newOrigin = calculatedOrigin
            }
        } else {
            // Preview: Center
            newOrigin = NSPoint(x: naiveCenter.x - newSize.width/2, y: naiveCenter.y - newSize.height/2)
        }
        
        // Helper to update visual content (Size/Font)
        let applyLayoutUpdates = {
            self.contentView?.frame = NSRect(origin: .zero, size: newSize)
            self.contentView?.needsDisplay = true
            
            if showHandle {
                // Handle handles its own layout via constraints/init
            } else if self.isActiveMode {
                self.updateLabelFont(for: newSize, isSmallMode: true)
            } else {
                self.updateLabelFont(for: newSize, isSmallMode: false)
            }
            self.invalidateShadow()
        }
        
        let targetFrame = NSRect(origin: newOrigin, size: newSize)
        let animDuration = 0.08
        
        // --- 4. Execute Animation & Frame Updates ---
        
        if shouldBeVisible {
            // Handle "Corner Hidden" Special Case: Visible (Alpha 1) but in Corner
            if isCornerHidden {
                if !self.isVisible { self.orderFront(nil) }
                
                // Legacy Logic: Fade out IN PLACE -> Then move/shrink offscreen -> Restore Alpha 1.0
                // We do NOT apply layout updates yet to prevent the window from shrinking/jumping before fading.
                let dist = hypot(self.frame.origin.x - newOrigin.x, self.frame.origin.y - newOrigin.y)
                
                if dist > 1.0 {
                     NSAnimationContext.runAnimationGroup { context in
                        context.duration = animDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        self.animator().alphaValue = 0.0
                    } completionHandler: {
                        // AFTER fade, apply the new small size and position
                        applyLayoutUpdates()
                        self.setFrame(targetFrame, display: true)
                        self.alphaValue = 1.0 // Legacy: It stays "visible" for system, but 1px offscreen
                    }
                } else {
                    // Already in place
                    applyLayoutUpdates()
                    self.setFrame(targetFrame, display: true)
                    self.alphaValue = 1.0
                }
                return
            }

            // Normal Visibility Logic
            applyLayoutUpdates() // Apply new size/font immediately
            
            if !self.isVisible || self.alphaValue == 0 {
                // [Hidden -> Visible]: Snap Frame -> Fade In
                self.setFrame(targetFrame, display: true)
                self.orderFront(nil)
                self.alphaValue = 0.0
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = animDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.animator().alphaValue = 1.0
                }
            } else {
                // [Visible -> Visible]: Move Frame (Animation)
                if self.alphaValue < 1.0 { self.animator().alphaValue = 1.0 }
                
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            // [Visible -> Hidden]: Fade Out -> Then Snap Frame Offscreen
            applyLayoutUpdates()
            
            if self.isVisible && self.alphaValue > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = animDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.animator().alphaValue = 0.0
                } completionHandler: {
                    if self.alphaValue == 0 {
                        self.setFrame(targetFrame, display: false)
                        self.orderOut(nil)
                    }
                }
            } else {
                // [Hidden -> Hidden]: Just update internal state
                self.setFrame(targetFrame, display: false)
                self.alphaValue = 0.0
                self.orderOut(nil)
            }
        }
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
                        
                        // Toggle Logic
                        if !isDocked {
                            if minMouseEdgeDist < 15.0 {
                                isDocked = true
                                didStateChange = true
                                self.savedFloatingCenter = nil // Reset on manual drag dock
                                
                                if minMouseEdgeDist == distLeft { self.dockEdge = .minX }
                                else if minMouseEdgeDist == distRight { self.dockEdge = .maxX }
                                else if minMouseEdgeDist == distTop { self.dockEdge = .maxY }
                                else { self.dockEdge = .minY }
                            }
                        } else {
                            if minMouseEdgeDist > 50.0 {
                                isDocked = false
                                didStateChange = true
                                self.savedFloatingCenter = nil
                            }
                        }
                        
                        if didStateChange {
                            updateState() // Use main pipeline
                            let newSize = self.frame.size
                            
                            // Re-calculate drag offset post-snap
                            if isDocked {
                                let rootedOrigin = calculateCenteredOrigin(
                                    forSize: newSize,
                                    onEdge: self.dockEdge,
                                    centerPoint: NSPoint(x: currentMouseLocation.x, y: currentMouseLocation.y),
                                    screenFrame: screenFrame
                                )
                                targetOrigin = rootedOrigin
                            } else {
                                targetOrigin = NSPoint(x: currentMouseLocation.x - mouseOffset.x,
                                                       y: currentMouseLocation.y - mouseOffset.y)
                            }
                            
                            self.setFrameOrigin(targetOrigin)
                            mouseOffset = NSPoint(x: currentMouseLocation.x - targetOrigin.x,
                                                  y: currentMouseLocation.y - targetOrigin.y)
                            startMouseLocation = currentMouseLocation
                            pushToGlobalState()
                            continue
                        }
                        
                        // Dragging logic
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
            // Undock
            self.isDocked = false
            if let screen = self.screen {
                let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                let targetCenter = self.savedFloatingCenter ?? currentCenter
                
                let sFrame = screen.visibleFrame
                let relX = (targetCenter.x - sFrame.minX) / sFrame.width
                let relY = (targetCenter.y - sFrame.minY) / sFrame.height
                
                labelManager?.updateGlobalState(isDocked: false, edge: self.dockEdge, center: NSPoint(x: relX, y: relY))
            }
        } else {
            // Dock
            if let screen = self.screen {
                self.savedFloatingCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                _ = findNearestEdgePosition(targetScreen: screen, forRect: self.frame)
            }
            self.isDocked = true
            pushToGlobalState()
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            updateState()
        }
    }
    
    private func updateInteractivity() {
        let isInteractive = (labelManager?.showOnDesktop == true) && isActiveMode
        self.ignoresMouseEvents = !isInteractive
        self.isMovableByWindowBackground = false
    }
    
    // MARK: - Calculation Helpers
    
    private func calculateCenteredOrigin(forSize size: NSSize, onEdge edge: NSRectEdge, centerPoint: NSPoint, screenFrame: NSRect) -> NSPoint {
        var origin = NSPoint.zero
        switch edge {
        case .minX: origin = NSPoint(x: screenFrame.minX, y: centerPoint.y - size.height/2)
        case .maxX: origin = NSPoint(x: screenFrame.maxX - size.width, y: centerPoint.y - size.height/2)
        case .minY: origin = NSPoint(x: centerPoint.x - size.width/2, y: screenFrame.minY)
        case .maxY: origin = NSPoint(x: centerPoint.x - size.width/2, y: screenFrame.maxY - size.height)
        @unknown default: origin = NSPoint(x: centerPoint.x - size.width/2, y: centerPoint.y - size.height/2)
        }
        
        if edge == .minX || edge == .maxX {
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
        } else {
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
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
    
    // [RESTORED] Exact logic from original provided code
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
    
    @objc private func repositionWindow() { updateState() }
}
