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
    
    // MARK: - Interactions (Mouse-Proximity Logic)
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }
        
        // 1. Initial State
        var startMouseLocation = NSEvent.mouseLocation // Global Screen Coords
        var startWindowOrigin = self.frame.origin
        
        // Initial offset to keep window attached to mouse properly
        var mouseOffset = NSPoint(x: startMouseLocation.x - startWindowOrigin.x,
                                  y: startMouseLocation.y - startWindowOrigin.y)
        
        var hasDragged = false
        
        // 2. Manual Event Loop
        while true {
            guard let nextEvent = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                                 until: .distantFuture,
                                                 inMode: .eventTracking,
                                                 dequeue: true) else { break }
            
            if nextEvent.type == .leftMouseUp {
                if !hasDragged {
                    toggleDockState()
                }
                break
            }
            else if nextEvent.type == .leftMouseDragged {
                let currentMouseLocation = NSEvent.mouseLocation
                
                // Hysteresis
                if !hasDragged {
                    let dx = currentMouseLocation.x - startMouseLocation.x
                    let dy = currentMouseLocation.y - startMouseLocation.y
                    if hypot(dx, dy) > 5.0 {
                        hasDragged = true
                    }
                }
                
                if hasDragged {
                    // Calculate basic target position based on mouse offset
                    var targetOrigin = NSPoint(x: currentMouseLocation.x - mouseOffset.x,
                                               y: currentMouseLocation.y - mouseOffset.y)
                    
                    if let screen = self.screen {
                        let screenFrame = screen.visibleFrame
                        var didStateChange = false
                        
                        // Calculate Mouse Distance to Edges (Crucial for Trigger)
                        let distLeft = abs(currentMouseLocation.x - screenFrame.minX)
                        let distRight = abs(currentMouseLocation.x - screenFrame.maxX)
                        let distTop = abs(currentMouseLocation.y - screenFrame.maxY)
                        let distBottom = abs(currentMouseLocation.y - screenFrame.minY)
                        let minMouseEdgeDist = min(distLeft, distRight, distTop, distBottom)
                        
                        // --- CHECK TRANSITIONS ---
                        if !isDocked {
                            // EXPANDED -> COLLAPSED
                            // Trigger: If MOUSE is very close to an edge (< 15pt)
                            // This ensures docking works even if you hold the window by the "far" side.
                            if minMouseEdgeDist < 15.0 {
                                isDocked = true
                                didStateChange = true
                                
                                // Set the dock edge immediately to where the mouse is
                                if minMouseEdgeDist == distLeft { self.dockEdge = .minX }
                                else if minMouseEdgeDist == distRight { self.dockEdge = .maxX }
                                else if minMouseEdgeDist == distTop { self.dockEdge = .maxY }
                                else { self.dockEdge = .minY }
                            }
                            
                        } else {
                            // COLLAPSED -> EXPANDED
                            // Trigger: If MOUSE is dragged away from the edge (> 50pt)
                            if minMouseEdgeDist > 50.0 {
                                isDocked = false
                                didStateChange = true
                            }
                        }
                        
                        // --- APPLY TRANSITION & RE-ANCHOR ---
                        if didStateChange {
                            updateLayout(isCurrentSpace: true) // Updates self.frame.size
                            let newSize = self.frame.size
                            
                            if isDocked {
                                // Transitioning to HANDLE
                                // Force snap to the detected `dockEdge`
                                // We construct a fake rect at the exact mouse position, but `findNearest` logic is robust.
                                // Just center handle on mouse initially...
                                let mouseRect = NSRect(x: currentMouseLocation.x - (newSize.width/2),
                                                       y: currentMouseLocation.y - (newSize.height/2),
                                                       width: newSize.width, height: newSize.height)
                                
                                // ...then snap it to the edge.
                                targetOrigin = findNearestEdgePosition(targetScreen: screen, forRect: mouseRect)
                                
                                // Re-calculate offset so dragging feels natural (Handle slides under mouse)
                                mouseOffset = NSPoint(x: currentMouseLocation.x - targetOrigin.x,
                                                      y: currentMouseLocation.y - targetOrigin.y)
                                
                            } else {
                                // Transitioning to LABEL
                                // Center the big label directly under the MOUSE
                                targetOrigin = NSPoint(x: currentMouseLocation.x - (newSize.width/2),
                                                       y: currentMouseLocation.y - (newSize.height/2))
                                
                                // Reset offset to be exactly center
                                mouseOffset = NSPoint(x: newSize.width / 2, y: newSize.height / 2)
                            }
                            
                            self.setFrameOrigin(targetOrigin)
                            
                            // RESET ANCHORS
                            startMouseLocation = currentMouseLocation
                            startWindowOrigin = targetOrigin
                            
                            continue // Skip normal drag logic this frame
                        }
                        
                        // --- NORMAL DRAG ---
                        if isDocked {
                            // Sliding Logic (Clamp Perpendicular)
                            let targetRect = NSRect(origin: targetOrigin, size: self.frame.size)
                            let snappedOrigin = findNearestEdgePosition(targetScreen: screen, forRect: targetRect)
                            self.setFrameOrigin(snappedOrigin)
                        } else {
                            // Free Drag
                            self.setFrameOrigin(targetOrigin)
                        }
                    }
                }
            }
        }
    }
    
    private func toggleDockState() {
        if self.isDocked {
            // Expand
            self.isDocked = false
            animateFrameChange()
        } else {
            // Collapse
            if let screen = self.screen {
                // Determine best edge based on current position
                _ = findNearestEdgePosition(targetScreen: screen, forRect: self.frame)
            }
            self.isDocked = true
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
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        
        if showHandle {
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
            // Use current frame to maintain position if we are just switching modes
            newOrigin = findNearestEdgePosition(targetScreen: targetScreen, forRect: self.frame)
            
        } else {
            self.label.isHidden = false
            self.handleView.isHidden = true
            
            self.contentView?.layer?.cornerRadius = 20
            
            if isCurrentSpace {
                if labelManager?.showOnDesktop == true {
                     // Floating Interactive
                     newSize = calculatePreviewLikeSize()
                     
                     // Keep center
                     let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                     newOrigin = NSPoint(x: currentCenter.x - (newSize.width / 2), y: currentCenter.y - (newSize.height / 2))
                     
                     // Constrain
                     newOrigin.x = max(targetScreen.frame.minX, min(newOrigin.x, targetScreen.frame.maxX - newSize.width))
                     newOrigin.y = max(targetScreen.frame.minY, min(newOrigin.y, targetScreen.frame.maxY - newSize.height))
                     
                     updateLabelFont(for: newSize, isSmallMode: false)
                } else {
                    // Invisible Corner (Legacy Active Mode)
                    newSize = calculateActiveSize()
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                    updateLabelFont(for: newSize, isSmallMode: true)
                }
            } else {
                // Mission Control Preview
                newSize = previewSize
                newOrigin = NSPoint(
                    x: targetScreen.frame.midX - (newSize.width / 2),
                    y: targetScreen.frame.midY - (newSize.height / 2)
                )
                updateLabelFont(for: newSize, isSmallMode: false)
            }
        }
        
        // Note: Using animator() here handles smooth frame interpolation for toggles,
        // but during drag we override this by setting frame manually.
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
    
    private func findNearestEdgePosition(targetScreen: NSScreen, forRect rect: NSRect) -> NSPoint {
        let size = rect.size
        let sFrame = targetScreen.visibleFrame
        
        let distLeft = abs(rect.minX - sFrame.minX)
        let distRight = abs(rect.maxX - sFrame.maxX)
        let distTop = abs(rect.maxY - sFrame.maxY)
        let distBottom = abs(rect.minY - sFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        
        var finalOrigin = rect.origin
        
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
