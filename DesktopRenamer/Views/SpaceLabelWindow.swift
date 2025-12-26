import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    public let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    private weak var labelManager: SpaceLabelManager?
    
    // State
    private var isActiveMode: Bool = true
    private var isDocked: Bool = true // Default to docked (classic behavior)
    private var previewSize: NSSize = NSSize(width: 800, height: 500)
    
    // Base Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        
        self.label = NSTextField(labelWithString: name)
        
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
        
        // Update level: If visible on desktop, act like a normal floating window.
        // If not, keep it strictly as floating (above normal apps) but below menus.
        self.level = .floating
        
        self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
        
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
        
        // Reset dock state when leaving preview mode to ensure correct active appearance
        if isCurrentSpace {
             // If we enter Active Mode, and "Show on Desktop" is OFF, we force Docked (Standard)
             if let manager = labelManager, !manager.showOnDesktop {
                 self.isDocked = true
             }
             // If "Show on Desktop" is ON, we keep the previous state (Floating or Docked)
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
    
    // MARK: - Mouse / Dragging Logic
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }
        // Allow dragging by background
        self.performDrag(with: event)
    }
    
    // Check for edge snapping after drag
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else { return }
        checkEdgeDocking()
    }
    
    private func checkEdgeDocking() {
        guard let screen = self.screen else { return }
        
        let windowFrame = self.frame
        let screenFrame = screen.visibleFrame
        let threshold: CGFloat = 50.0 // Distance to edge to trigger shrink
        
        // Check proximity
        let nearLeft = abs(windowFrame.minX - screenFrame.minX) < threshold
        let nearRight = abs(windowFrame.maxX - screenFrame.maxX) < threshold
        let nearTop = abs(windowFrame.maxY - screenFrame.maxY) < threshold
        let nearBottom = abs(windowFrame.minY - screenFrame.minY) < threshold
        
        let isNearEdge = nearLeft || nearRight || nearTop || nearBottom
        
        if isNearEdge {
            if !self.isDocked {
                // SHRINK (Float -> Dock)
                self.isDocked = true
                animateFrameChange()
            } else {
                // Already docked, just snap to nearest edge
                animateFrameChange()
            }
        } else {
            if self.isDocked {
                // EXPAND (Dock -> Float)
                self.isDocked = false
                animateFrameChange()
            }
        }
    }
    
    private func animateFrameChange() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            updateLayout(isCurrentSpace: true) // Recalculates based on new isDocked state
        }
    }
    
    private func updateInteractivity() {
        let isInteractive = (labelManager?.showOnDesktop == true) && isActiveMode
        self.ignoresMouseEvents = !isInteractive
        self.isMovableByWindowBackground = isInteractive
    }
    
    // MARK: - Visibility
    
    private func updateVisibility(animated: Bool) {
        let showActive = labelManager?.showActiveLabels ?? true
        let showPreview = labelManager?.showPreviewLabels ?? true
        
        // Determine if we *should* be visible right now
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
    
    // MARK: - Layout Logic
    
    private func updateLayout(isCurrentSpace: Bool) {
        guard let targetScreen = findTargetScreen() else { self.close(); return }
        
        var newSize: NSSize
        var newOrigin: NSPoint
        
        if isCurrentSpace {
            // Check if we are in "Docked" (Small) or "Floating" (Large/Visible) state
            if isDocked {
                // MODE A1: Docked (Small, Corner/Edge)
                // Uses 'activeFontScale'
                newSize = calculateActiveSize()
                
                // If the window is already on screen (interactive mode), snap to nearest edge
                // If not interactive, find best offscreen/corner position (classic behavior)
                if labelManager?.showOnDesktop == true {
                    newOrigin = findNearestEdgePosition(targetScreen: targetScreen, size: newSize)
                } else {
                    newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
                }
            } else {
                // MODE A2: Floating (Large, Interactive)
                // Uses 'previewFontScale' (repurposed for readability)
                // We keep the center point stable when expanding
                newSize = calculatePreviewLikeSize()
                
                let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                newOrigin = NSPoint(
                    x: currentCenter.x - (newSize.width / 2),
                    y: currentCenter.y - (newSize.height / 2)
                )
                
                // Keep onscreen
                newOrigin.x = max(targetScreen.frame.minX, min(newOrigin.x, targetScreen.frame.maxX - newSize.width))
                newOrigin.y = max(targetScreen.frame.minY, min(newOrigin.y, targetScreen.frame.maxY - newSize.height))
            }
        } else {
            // MODE B: Preview (Mission Control)
            newSize = previewSize
            newOrigin = NSPoint(
                x: targetScreen.frame.midX - (newSize.width / 2),
                y: targetScreen.frame.midY - (newSize.height / 2)
            )
        }
        
        // Use animator() if this call is inside an animation block
        self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        self.contentView?.animator().frame = NSRect(origin: .zero, size: newSize)
        
        updateLabelFont(for: newSize, isSmallMode: isCurrentSpace && isDocked)
    }
    
    // MARK: - Calculation Helpers
    
    private func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        return calculateSize(baseFont: SpaceLabelWindow.baseActiveFontSize * scaleF, paddingScale: scaleP, basePadH: 60, basePadV: 40)
    }
    
    private func calculatePreviewLikeSize() -> NSSize {
        // Reuse Preview scales for "Floating" mode readability
        let scaleF = CGFloat(labelManager?.previewFontScale ?? 1.0) * 0.5 // Slightly smaller than massive MC preview
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
        // ... (Font resizing logic remains similar, adjusting based on isSmallMode) ...
        let name = self.label.stringValue
        
        // If docked, use active scales. If floating, use preview scales (scaled down slightly)
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
    
    // Classic Corner Logic
    private func findBestOffscreenPosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let f = targetScreen.frame
        let overlap: CGFloat = 1.0
        // ... (Existing logic to check 4 corners) ...
        // Default to Top Left for now or keep existing sophisticated check
        return NSPoint(x: f.minX - size.width + overlap, y: f.maxY - overlap)
    }
    
    // NEW: Interactive Edge Snap Logic
    private func findNearestEdgePosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let currentRect = self.frame
        let sFrame = targetScreen.visibleFrame
        
        // Distances to edges
        let distLeft = abs(currentRect.minX - sFrame.minX)
        let distRight = abs(currentRect.maxX - sFrame.maxX)
        let distTop = abs(currentRect.maxY - sFrame.maxY)
        let distBottom = abs(currentRect.minY - sFrame.minY)
        
        let minDist = min(distLeft, distRight, distTop, distBottom)
        
        var finalOrigin = currentRect.origin
        
        // Snap to closest edge
        if minDist == distLeft {
            finalOrigin.x = sFrame.minX
        } else if minDist == distRight {
            finalOrigin.x = sFrame.maxX - size.width
        } else if minDist == distTop {
            finalOrigin.y = sFrame.maxY - size.height
        } else {
            finalOrigin.y = sFrame.minY
        }
        
        // Clamp to stay within screen bounds (orthogonal axis)
        if minDist == distLeft || minDist == distRight {
            finalOrigin.y = max(sFrame.minY, min(finalOrigin.y, sFrame.maxY - size.height))
        } else {
            finalOrigin.x = max(sFrame.minX, min(finalOrigin.x, sFrame.maxX - size.width))
        }
        
        return finalOrigin
    }
    
    @objc private func repositionWindow() { updateLayout(isCurrentSpace: isActiveMode) }
}
