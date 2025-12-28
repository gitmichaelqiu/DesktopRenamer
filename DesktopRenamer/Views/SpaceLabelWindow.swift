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
        
        // [FIX] Ensure tint is set to .labelColor so it adapts to Light/Dark mode correctly
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
    
    private var isHiddenCornerMode: Bool {
        return isActiveMode && !(labelManager?.showOnDesktop == true)
    }
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        // 1. Text Label
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        
        // [FIX] Restore this line.
        // .labelColor is a semantic color that automatically updates when the system appearance changes.
        // Removing it caused the label to stop responding to live theme updates.
        self.label.textColor = .labelColor
        
        // 2. Handle View
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        self.handleView.translatesAutoresizingMaskIntoConstraints = false
        
        // 3. Container View
        // We use a container to satisfy NSGlassEffectView.contentView requirements
        self.contentContainer = NSView(frame: .zero)
        self.contentContainer.wantsLayer = true
        
        self.contentContainer.addSubview(self.label)
        self.contentContainer.addSubview(self.handleView)
        
        // [FIX] Pin HandleView to container edges.
        NSLayoutConstraint.activate([
            self.handleView.leadingAnchor.constraint(equalTo: self.contentContainer.leadingAnchor),
            self.handleView.trailingAnchor.constraint(equalTo: self.contentContainer.trailingAnchor),
            self.handleView.topAnchor.constraint(equalTo: self.contentContainer.topAnchor),
            self.handleView.bottomAnchor.constraint(equalTo: self.contentContainer.bottomAnchor)
        ])
        
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
        
        // 4. Configure Visual/Glass Effect View
        let rootContentView: NSView
        
        if #available(macOS 26.0, *) {
            // NEW DESIGN: NSGlassEffectView
            let glassView = NSGlassEffectView(frame: .zero)
            
            glassView.contentView = self.contentContainer
            
            rootContentView = glassView
        } else {
            // LEGACY: NSVisualEffectView
            let effectView = NSVisualEffectView(frame: .zero)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            
            // [FIX] Force Dark Appearance for HUD so .labelColor resolves to white (legible)
            effectView.appearance = NSAppearance(named: .darkAqua)
            
            effectView.addSubview(self.contentContainer)
            
            // [FIX] Manually constrain container to fill the legacy effect view
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
            self?.updateLayout(isCurrentSpace: true)
            self?.updateVisibility(animated: false)
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
    
    // MARK: - State Synchronization (No Changes)
    
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
    
    // MARK: - Helper: Edge-Aware Positioning (No Changes)
    
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
    
    // MARK: - Interactions (No Changes)
    
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
        if showHandle {
            // DOCKED
            self.label.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            
            // [FIX] Removed manual frame setting for handleView to rely on constraints
            
            self.contentView?.layer?.cornerRadius = 12
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
        } else if isCurrentSpace {
             // EXPANDED / HIDDEN
             self.label.isHidden = false
             self.handleView.isHidden = true
             self.contentView?.layer?.cornerRadius = 20
             
             newSize = calculateActiveSize()
             updateLabelFont(for: newSize, isSmallMode: true)
        } else {
            // PREVIEW
            self.label.isHidden = false
            self.handleView.isHidden = true
            self.contentView?.layer?.cornerRadius = 20
            
            newSize = previewSize
            updateLabelFont(for: newSize, isSmallMode: false)
        }
        
        // 2. Determine Position (Center)
        if isCurrentSpace {
            targetCenter = getAbsoluteTargetCenter(on: targetScreen, forSize: newSize)
        } else {
            targetCenter = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
        }

        // 3. Calculate Final Origin
        if showHandle {
            newOrigin = calculateCenteredOrigin(
                forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: true
            )
        } else if isCurrentSpace {
            if isHiddenCornerMode {
                newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
            } else {
                newOrigin = calculateCenteredOrigin(
                    forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter, screenFrame: targetScreen.visibleFrame, clampToScreen: false
                )
            }
        } else {
            newOrigin = NSPoint(x: targetCenter.x - newSize.width/2, y: targetCenter.y - newSize.height/2)
        }
        
        // [FIX] REMOVED manual setting of contentContainer.frame to allow glass view layout engine to work.
        
        self.contentView?.needsDisplay = true
        self.invalidateShadow()
        
        if updateFrame {
            if isHiddenCornerMode {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().alphaValue = 0.0
                } completionHandler: {
                    self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                    self.alphaValue = 1.0
                }
            } else {
                self.alphaValue = 1.0
                self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                if self.alphaValue < 1.0 { self.animator().alphaValue = 1.0 }
            }
        } else {
            self.setFrame(NSRect(origin: self.frame.origin, size: newSize), display: true)
        }
    }
    
    // MARK: - Calculation Helpers (No Changes)
    
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
            if !isHiddenCornerMode {
                if animated { self.animator().alphaValue = 1.0 } else { self.alphaValue = 1.0 }
            }
        } else {
            if !self.isVisible { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    self.animator().alphaValue = 0.0
                } completionHandler: { if !shouldBeVisible { self.orderOut(nil) } }
            } else { self.alphaValue = 0.0; self.orderOut(nil) }
        }
    }
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: isActiveMode) }
}
