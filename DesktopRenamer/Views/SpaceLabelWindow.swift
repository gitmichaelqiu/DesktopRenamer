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
        visualEffectView.material = .hudWindow
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
        
        self.wantsLayer = true
        // FIX: Removed manual background color to let the parent VisualEffectView (Glass) shine through.
        self.layer?.cornerRadius = 12
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .bold)
        imageView.contentTintColor = .labelColor
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
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
    // UI Elements
    private let containerView: NSView
    private let backgroundEffectView: NSVisualEffectView // The "Label" Background
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
        
        // 1. Root Container (Transparent)
        self.containerView = NSView()
        self.containerView.wantsLayer = true
        self.containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 2. Label Background (Visual Effect)
        self.backgroundEffectView = NSVisualEffectView()
        self.backgroundEffectView.material = .hudWindow
        self.backgroundEffectView.state = .active
        self.backgroundEffectView.blendingMode = .behindWindow
        self.backgroundEffectView.wantsLayer = true
        self.backgroundEffectView.layer?.cornerRadius = 16
        self.backgroundEffectView.layer?.masksToBounds = true
        
        // 3. Label Text
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor
        self.label.translatesAutoresizingMaskIntoConstraints = false
        
        // 4. Handle View
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        
        // ... (Screen Finding Logic) ...
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
        
        // Hierarchy Setup
        // Background View holds the Label
        self.backgroundEffectView.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.centerXAnchor.constraint(equalTo: self.backgroundEffectView.centerXAnchor),
            self.label.centerYAnchor.constraint(equalTo: self.backgroundEffectView.centerYAnchor),
            self.label.leadingAnchor.constraint(equalTo: self.backgroundEffectView.leadingAnchor, constant: 10),
            self.label.trailingAnchor.constraint(equalTo: self.backgroundEffectView.trailingAnchor, constant: -10)
        ])
        
        // Container holds Background AND Handle (Siblings)
        self.containerView.addSubview(self.backgroundEffectView)
        self.containerView.addSubview(self.handleView)
        
        self.contentView = self.containerView
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
        
        updateLayout(isCurrentSpace: isCurrentSpace)
        updateVisibility(animated: true)
        updateInteractivity()
    }
    
    func updateName(_ name: String) {
        self.label.stringValue = name
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }
    
    // MARK: - Interactions (Corrected Manual Loop)
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }
        
        // 1. Initial State for Delta Calculation
        let startMouseLocation = NSEvent.mouseLocation // Screen coordinates
        let startWindowOrigin = self.frame.origin
        
        // Mouse offset within the window to keep the drag locked to cursor
        let initialClickInWindow = event.locationInWindow
        
        var hasDragged = false
        
        // 2. Manual Event Loop
        while true {
            guard let nextEvent = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                                 until: .distantFuture,
                                                 inMode: .eventTracking,
                                                 dequeue: true) else { break }
            
            if nextEvent.type == .leftMouseUp {
                if !hasDragged {
                    // Clean Click -> Toggle
                    toggleDockState()
                }
                break
            }
            else if nextEvent.type == .leftMouseDragged {
                let currentMouseLocation = NSEvent.mouseLocation
                let dx = currentMouseLocation.x - startMouseLocation.x
                let dy = currentMouseLocation.y - startMouseLocation.y
                let dist = hypot(dx, dy)
                
                // Hysteresis: Only start dragging if moved > 5 pixels
                if !hasDragged && dist > 5.0 {
                    hasDragged = true
                }
                
                if hasDragged {
                    // Update Window Position
                    // Note: We don't simple add delta to origin, we recalculate based on screen alignment
                    // But simpler is: NewOrigin = StartOrigin + Delta
                    var newOrigin = NSPoint(x: startWindowOrigin.x + dx, y: startWindowOrigin.y + dy)
                    
                    // --- REAL TIME DOCKING LOGIC ---
                    // While dragging, we check if we should snap to edge or undock
                    if let screen = self.screen {
                        let snapThreshold: CGFloat = 50.0
                        let screenFrame = screen.visibleFrame
                        
                        // Check distance to edges based on CURRENT mouse pointer (approximated via window center)
                        let windowCenter = NSPoint(x: newOrigin.x + (self.frame.width / 2),
                                                   y: newOrigin.y + (self.frame.height / 2))
                        
                        let distLeft = abs(windowCenter.x - screenFrame.minX)
                        let distRight = abs(windowCenter.x - screenFrame.maxX)
                        let distTop = abs(windowCenter.y - screenFrame.maxY)
                        let distBottom = abs(windowCenter.y - screenFrame.minY)
                        
                        let minDist = min(distLeft, distRight, distTop, distBottom)
                        
                        if minDist < snapThreshold {
                            // SNAP TO EDGE
                            if !isDocked {
                                isDocked = true
                                updateLayout(isCurrentSpace: true)
                                // Adjust newOrigin to align with the edge we just snapped to
                                // This prevents "jumping" visual artifacts
                                // For simplicity in this logic, updateLayout snaps it to edge.
                                // We just need to stop overriding it with the mouse for one frame?
                                // Actually, updateLayout sets the frame.
                                continue
                            }
                        } else {
                            // DRAG AWAY
                            if isDocked {
                                isDocked = false
                                updateLayout(isCurrentSpace: true)
                                // Recalculate origin so the window centers on mouse (approximately)
                                let newSize = self.frame.size
                                newOrigin.x = currentMouseLocation.x - (newSize.width / 2)
                                newOrigin.y = currentMouseLocation.y - (newSize.height / 2)
                            }
                        }
                    }
                    
                    if !isDocked {
                        self.setFrameOrigin(newOrigin)
                    } else {
                        // If docked, recalculate edge snap dynamically so it slides along edge?
                        // For now, let's let updateLayout handle positioning or allow sliding:
                        // A simpler "Edge Slide" requires knowing which edge.
                        // We re-run edge logic:
                        if let screen = self.screen {
                           let fixedOrigin = findNearestEdgePosition(targetScreen: screen, size: self.frame.size)
                           // But we want to allow sliding along the edge (e.g. up/down on left edge)
                           // Overriding findNearestEdgePosition logic for dragging is complex.
                           // Let's stick to simple snapping for now.
                           self.setFrameOrigin(fixedOrigin)
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
            // Find nearest edge first to know where to go
            if let screen = self.screen {
                // Determine edge based on current center
                let center = NSPoint(x: self.frame.midX, y: self.frame.midY)
                let sFrame = screen.visibleFrame
                
                let dists = [
                    (abs(center.x - sFrame.minX), NSRectEdge.minX),
                    (abs(center.x - sFrame.maxX), NSRectEdge.maxX),
                    (abs(center.y - sFrame.maxY), NSRectEdge.maxY),
                    (abs(center.y - sFrame.minY), NSRectEdge.minY)
                ]
                
                if let min = dists.min(by: { $0.0 < $1.0 }) {
                    self.dockEdge = min.1
                }
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
    
    // MARK: - Layout Logic (FIXED HIERARCHY)
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        
        if showHandle {
            // --- HANDLE MODE ---
            // Hide Background Label, Show Handle
            self.backgroundEffectView.isHidden = true
            self.handleView.isHidden = false
            self.handleView.edge = self.dockEdge
            
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(width: SpaceLabelWindow.handleSize.height, height: SpaceLabelWindow.handleSize.width)
            }
            
            // Handle fills the window frame
            self.handleView.frame = NSRect(origin: .zero, size: newSize)
            
            newOrigin = findNearestEdgePosition(targetScreen: targetScreen, size: newSize)
            
        } else {
            // --- LABEL MODE ---
            // Show Background Label, Hide Handle
            self.backgroundEffectView.isHidden = false
            self.handleView.isHidden = true
            
            if isCurrentSpace {
                if labelManager?.showOnDesktop == true {
                     // Interactive Floating
                     newSize = calculatePreviewLikeSize()
                     
                     // Keep current center if possible, else default calculation
                     let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                     newOrigin = NSPoint(x: currentCenter.x - (newSize.width / 2), y: currentCenter.y - (newSize.height / 2))
                     
                     // Constrain
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
            
            // Background View fills window
            self.backgroundEffectView.frame = NSRect(origin: .zero, size: newSize)
        }
        
        // Use animator only if valid target
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        // Note: contentView frame doesn't need animation if subviews are sized above,
        // but ensuring it matches bounds is good practice.
        self.contentView?.frame = NSRect(origin: .zero, size: newSize)
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
        let padding: CGFloat = 4.0
        
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
