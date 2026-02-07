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
        
        // Ensure tint is set to .labelColor so it adapts to Light/Dark mode correctly
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
    private let contentContainer: NSView
    
    public let spaceId: String
    public let displayID: String
    public let isFullscreenSpace: Bool
    
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    private weak var labelManager: SpaceLabelManager?
    
    // State
    private var isActiveMode: Bool = true
    private var isDocked: Bool = true
    private var dockEdge: NSRectEdge = .maxX
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    private var isInvisibleAnchorMode: Bool = false
    
    // Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    static let handleSize = NSSize(width: 32, height: 60)
    
    private var isHiddenCornerMode: Bool {
        return isActiveMode && !(labelManager?.showOnDesktop == true)
    }
    
    init(spaceId: String, name: String, displayID: String, isFullscreen: Bool, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.isFullscreenSpace = isFullscreen
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        // 1. Text Label
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor
        
        // 2. Handle View
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        self.handleView.translatesAutoresizingMaskIntoConstraints = false
        
        // 3. Container View
        self.contentContainer = NSView(frame: .zero)
        self.contentContainer.wantsLayer = true
        
        self.contentContainer.addSubview(self.label)
        self.contentContainer.addSubview(self.handleView)
        
        // Pin HandleView to container edges.
        NSLayoutConstraint.activate([
            self.handleView.leadingAnchor.constraint(equalTo: self.contentContainer.leadingAnchor),
            self.handleView.trailingAnchor.constraint(equalTo: self.contentContainer.trailingAnchor),
            self.handleView.topAnchor.constraint(equalTo: self.contentContainer.topAnchor),
            self.handleView.bottomAnchor.constraint(equalTo: self.contentContainer.bottomAnchor)
        ])
        
        // Screen Logic
        let foundScreen = NSScreen.screens.first(where: { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == displayID { return true }
            let cleanName = displayID.components(separatedBy: " (").first ?? displayID
            return screen.localizedName == cleanName
        })
        
        let targetScreen = foundScreen ?? NSScreen.main ?? NSScreen.screens.first
        
        let startRect: NSRect
        if let targetScreen = targetScreen {
            let screenFrame = targetScreen.frame
            startRect = NSRect(x: screenFrame.midX - 100, y: screenFrame.midY - 50, width: 200, height: 100)
        } else {
            startRect = NSRect(x: 0, y: 0, width: 200, height: 100)
        }
        
        super.init(contentRect: startRect, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        
        self.isReleasedWhenClosed = false
        
        if targetScreen == nil {
            self.close()
            return
        }
        
        // 4. Configure Visual/Glass Effect View
        let rootContentView: NSView
        
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView(frame: .zero)
            glassView.contentView = self.contentContainer
            rootContentView = glassView
        } else {
            let effectView = NSVisualEffectView(frame: .zero)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.appearance = NSAppearance(named: .darkAqua)
            effectView.addSubview(self.contentContainer)
            
            self.contentContainer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.contentContainer.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                self.contentContainer.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
                self.contentContainer.topAnchor.constraint(equalTo: effectView.topAnchor),
                self.contentContainer.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
            ])
            
            rootContentView = effectView
        }
        
        rootContentView.wantsLayer = true
        rootContentView.layer?.cornerRadius = 20
        rootContentView.layer?.masksToBounds = true
        
        self.contentView = rootContentView
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        
        // Collection Behavior
        // Reverted: .canJoinAllSpaces removed as it broke switching.
        // We keep .fullScreenAuxiliary so it can theoretically appear over fullscreen apps.
        self.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Observers
        self.spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(self, selector: #selector(repositionWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        syncFromGlobalState()
        setupLiveBackgroundUpdate()
        
        DispatchQueue.main.async { [weak self] in
            self?.updateLayout(isCurrentSpace: true)
            self?.updateVisibility(animated: false)
            self?.updateInteractivity()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Window Overrides (CRITICAL FOR SWITCHING)
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
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
    
    // MARK: - Helper: Edge-Aware Positioning
    private func getAbsoluteTargetCenter(on screen: NSScreen, forSize size: NSSize) -> NSPoint {
        let relativePoint = labelManager?.globalCenterPoint ?? NSPoint(x: 1.0, y: 0.5)
        let sFrame = screen.visibleFrame
        
        var absX = sFrame.minX + (sFrame.width * relativePoint.x)
        var absY = sFrame.minY + (sFrame.height * relativePoint.y)
        
        switch self.dockEdge {
        case .minX: absX = sFrame.minX + (size.width / 2)
        case .maxX: absX = sFrame.maxX - (size.width / 2)
        case .minY: absY = sFrame.minY + (size.height / 2)
        case .maxY: absY = sFrame.maxY - (size.height / 2)
        default: break
        }
        
        return NSPoint(x: absX, y: absY)
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
                        
                        // Toggle Logic
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
                                clampToScreen: isDocked
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
            
            if let screen = self.screen {
                let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                let newSize = calculateActiveSize()
                let rootedOrigin = calculateCenteredOrigin(
                    forSize: newSize,
                    onEdge: self.dockEdge,
                    centerPoint: currentCenter,
                    screenFrame: screen.visibleFrame,
                    clampToScreen: false
                )
                let newCenter = NSPoint(x: rootedOrigin.x + newSize.width/2, y: rootedOrigin.y + newSize.height/2)
                
                let sFrame = screen.visibleFrame
                let relX = (newCenter.x - sFrame.minX) / sFrame.width
                let relY = (newCenter.y - sFrame.minY) / sFrame.height
                
                if let manager = labelManager {
                    manager.updateGlobalState(isDocked: false, edge: self.dockEdge, center: NSPoint(x: relX, y: relY))
                }
            }
            animateFrameChange()
            
        } else {
            if let screen = self.screen {
                _ = findNearestEdgePosition(targetScreen: screen, forRect: self.frame)
            }
            self.isDocked = true
            pushToGlobalState()
            animateFrameChange()
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
    
    private func updateLayout(isCurrentSpace: Bool, updateFrame: Bool = true) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        var targetCenter = NSPoint.zero
        
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        let isHiddenCornerMode = isCurrentSpace && !showHandle && !(labelManager?.showOnDesktop == true)
        
        // 1. Determine Dimensions
        var isSmallModeForFont = false
        var shouldUseHandle = false
        
        if self.isInvisibleAnchorMode {
            // Anchor Mode: 1x1 Pixel
            newSize = NSSize(width: 1, height: 1)
        } else if showHandle {
            shouldUseHandle = true
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
        } else if isCurrentSpace {
             isSmallModeForFont = true
             newSize = calculateActiveSize()
        } else {
            isSmallModeForFont = false
            newSize = previewSize
        }
        
        // 2. Determine Position
        if self.isInvisibleAnchorMode {
            // Anchor Mode: Center of Screen
            newOrigin = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
        } else if isCurrentSpace {
            targetCenter = getAbsoluteTargetCenter(on: targetScreen, forSize: newSize)
            
            if showHandle {
                newOrigin = calculateCenteredOrigin(
                    forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: true
                )
            } else if isHiddenCornerMode {
                newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
            } else {
                newOrigin = calculateCenteredOrigin(
                    forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: false
                )
            }
        } else {
            // Preview Mode
            targetCenter = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
            newOrigin = NSPoint(x: targetCenter.x - newSize.width/2, y: targetCenter.y - newSize.height/2)
        }
        
        // 3. Execution Phase
        let updateVisuals = {
            self.backgroundColor = .clear // RE-ASSERT TRANSPARENCY
            
            if self.isInvisibleAnchorMode {
                self.level = .normal // CRITICAL: Floating windows don't switch spaces. Normal windows do.
                self.label.isHidden = true
                self.handleView.isHidden = true
                self.contentView?.layer?.cornerRadius = 0
                self.contentView?.isHidden = true // EXPLICITLY HIDE CONTENT
            } else if shouldUseHandle {
                self.level = .floating // Restore for visibility
                self.label.isHidden = true
                self.handleView.isHidden = false
                self.handleView.edge = self.dockEdge
                self.contentView?.layer?.cornerRadius = 12
                self.contentView?.isHidden = false
            } else {
                self.level = .floating // Restore for visibility
                self.label.isHidden = false
                self.handleView.isHidden = true
                self.contentView?.layer?.cornerRadius = 20
                self.updateLabelFont(for: newSize, isSmallMode: isSmallModeForFont)
                self.contentView?.isHidden = false
            }
            self.contentView?.needsDisplay = true
            self.invalidateShadow()
        }

        if updateFrame {
            if isHiddenCornerMode && !self.isInvisibleAnchorMode {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.contentView?.animator().alphaValue = 0.0
                } completionHandler: {
                    updateVisuals()
                    self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                    self.contentView?.alphaValue = 1.0
                }
            } else {
                updateVisuals()
                self.alphaValue = 1.0
                self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                if (self.contentView?.alphaValue ?? 0) < 1.0 { self.contentView?.animator().alphaValue = 1.0 }
            }
        } else {
            updateVisuals()
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
        return NSScreen.screens.first(where: { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            
            // 1. Name check (Default)
            let idString = "\(screen.localizedName) (\(screenID))"
            if idString == self.displayID { return true }
            
            let cleanTarget = self.displayID.components(separatedBy: " (").first ?? self.displayID
            if screen.localizedName == cleanTarget { return true }
            
            // 2. UUID Check
            let cgsID = screenID.uint32Value
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(cgsID) {
                let uuid = uuidRef.takeRetainedValue()
                let uuidString = CFUUIDCreateString(nil, uuid) as String
                if uuidString.caseInsensitiveCompare(self.displayID) == .orderedSame { return true }
            }
            return false
        })
    }
    
    private func findBestOffscreenPosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let f = targetScreen.frame
        let allScreens = NSScreen.screens
        
        let candidates: [NSPoint] = [
            NSPoint(x: f.minX - size.width + 1, y: f.maxY - 1),             // Top-Left
            NSPoint(x: f.maxX - 1, y: f.maxY - 1),                          // Top-Right
            NSPoint(x: f.minX - size.width + 1, y: f.minY - size.height + 1), // Bottom-Left
            NSPoint(x: f.maxX - 1, y: f.minY - size.height + 1)             // Bottom-Right
        ]
        
        var bestCandidate: NSPoint = candidates[0]
        var maxMinDist: CGFloat = -2.0
        
        for origin in candidates {
            let rect = NSRect(origin: origin, size: size)
            var minDist: CGFloat = 100000.0
            var intersects = false
            
            for other in allScreens {
                if other == targetScreen { continue }
                let otherFrame = other.frame
                if otherFrame.intersects(rect) {
                    intersects = true
                    break
                }
                let dx = max(otherFrame.minX - rect.maxX, rect.minX - otherFrame.maxX, 0)
                let dy = max(otherFrame.minY - rect.maxY, rect.minY - otherFrame.maxY, 0)
                let dist = sqrt(dx*dx + dy*dy)
                if dist < minDist { minDist = dist }
            }
            
            if intersects { minDist = -1.0 }
            if minDist > maxMinDist {
                maxMinDist = minDist
                bestCandidate = origin
            }
        }
        return bestCandidate
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
        guard findTargetScreen() != nil else {
            self.alphaValue = 0.0
            self.orderOut(nil)
            return
        }
        
        let masterEnabled = labelManager?.isEnabled ?? true
        let showActive = labelManager?.showActiveLabels ?? true
        let showPreview = labelManager?.showPreviewLabels ?? true
        
        var isVisuallyVisible = false
        
        if masterEnabled {
            if isActiveMode {
                isVisuallyVisible = showActive
            } else {
                if showPreview {
                    isVisuallyVisible = !self.isOnActiveSpace
                } else {
                    isVisuallyVisible = false
                }
            }
        }
        
        let shouldBeAnchor = !isVisuallyVisible
        if self.isInvisibleAnchorMode != shouldBeAnchor {
            self.isInvisibleAnchorMode = shouldBeAnchor
            updateLayout(isCurrentSpace: self.isActiveMode, updateFrame: animated)
        }
        
        if !self.isVisible {
            self.orderFront(nil)
        }
        
        self.alphaValue = 1.0
        let targetContentAlpha: CGFloat = isVisuallyVisible ? 1.0 : 0.0
        
        if animated {
            self.contentView?.animator().alphaValue = targetContentAlpha
        } else {
            self.contentView?.alphaValue = targetContentAlpha
        }
        
        if isVisuallyVisible {
            updateInteractivity()
        } else {
            self.ignoresMouseEvents = true
        }
    }
    
    @objc private func repositionWindow() {
        updateLayout(isCurrentSpace: isActiveMode)
        updateVisibility(animated: false)
    }
}
