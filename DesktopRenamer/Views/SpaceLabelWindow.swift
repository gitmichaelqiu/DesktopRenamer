import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private var label: NSTextField
    public let spaceId: String
    let displayID: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    private let frameWidth: CGFloat = 400
    private let frameHeight: CGFloat = 200
    
    init(spaceId: String, name: String, displayID: String, spaceManager: SpaceManager) {
            // 1. Initialize properties
            self.spaceId = spaceId
            self.displayID = displayID
            self.spaceManager = spaceManager
            
            // Initialize Label
            let newLabel = NSTextField(labelWithString: name)
            self.label = newLabel
            
            // 2. Define Dimensions
            let kWidth: CGFloat = 400
            let kHeight: CGFloat = 200
            
            // 3. Find Target Screen
            let foundScreen = NSScreen.screens.first { screen in
                let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
                
                // Exact Match
                let idString = "\(screen.localizedName) (\(screenID))"
                if idString == displayID { return true }
                
                // Fuzzy Match
                let cleanName = displayID.components(separatedBy: " (").first ?? displayID
                return screen.localizedName == cleanName
            }
            
            let targetScreen = foundScreen ?? NSScreen.main!
            
            // 4. Calculate Rect
            let screenFrame = targetScreen.frame
            let initialRect = NSRect(
                x: screenFrame.midX - (kWidth / 2),
                y: screenFrame.midY - (kHeight / 2),
                width: kWidth,
                height: kHeight
            )
            
            // 5. Initialize Window (defer: false to create immediately)
            super.init(
                contentRect: initialRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            // 6. CRITICAL FIX: Force Position BEFORE setting CollectionBehavior
            // We ensure the window is physically on the correct screen before telling
            // Mission Control to treat it as "Stationary" on that screen.
            self.setFrame(initialRect, display: true)
            
            // 7. View Configuration
            let padding: CGFloat = 20
            let maxWidth = kWidth - (padding * 2)
            let maxHeight = kHeight - (padding * 2)
            
            var fontSize: CGFloat = 50
            var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            var stringSize = attributedString.size()
            
            while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
                fontSize -= 2
                attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
                stringSize = attributedString.size()
            }
            
            newLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
            newLabel.textColor = .labelColor
            newLabel.alignment = .center
            newLabel.frame = NSRect(
                x: (kWidth - stringSize.width) / 2,
                y: (kHeight - stringSize.height) / 2,
                width: stringSize.width,
                height: stringSize.height
            )
            
            let mainContentView: NSView
            if #available(macOS 10.14, *) {
                mainContentView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: kWidth, height: kHeight))
            } else {
                mainContentView = NSView(frame: NSRect(x: 0, y: 0, width: kWidth, height: kHeight))
            }
            
            mainContentView.wantsLayer = true
            mainContentView.layer?.cornerRadius = 6
            mainContentView.addSubview(newLabel)
            
            self.contentView = mainContentView
            
            // 8. Window Attributes
            self.backgroundColor = .clear
            self.isOpaque = false
            self.hasShadow = false
            self.level = .floating
            
            // 9. APPLY BEHAVIORS LAST
            // Now that the window is on the correct screen, we lock it down.
            // We also add .canJoinAllSpaces to ensure it doesn't get hidden if the space technically "switches"
            // underneath it (though stationary usually handles this).
            self.collectionBehavior = [
                .managed,
                .stationary,
                .participatesInCycle,
                .fullScreenAuxiliary
            ]
            
            self.ignoresMouseEvents = true
            self.titlebarAppearsTransparent = true
            self.titleVisibility = .hidden
            self.standardWindowButton(.closeButton)?.isHidden = true
            self.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.standardWindowButton(.zoomButton)?.isHidden = true
            self.isRestorable = false
            
            // 10. Async Reinforcement (Just in case)
            // macOS can sometimes be stubborn; a second setFrame on the next run loop ensures it sticks.
            DispatchQueue.main.async { [weak self] in
                self?.setFrame(initialRect, display: true)
            }
            
            // 11. Observers
            self.spaceManager.$spaceNameDict
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.updateName(self.spaceManager.getSpaceName(self.spaceId))
                }
                .store(in: &cancellables)
                
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(repositionWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            center.addObserver(self, selector: #selector(repositionWindow), name: NSWorkspace.didWakeNotification, object: nil)
            
            // Final positioning check
            repositionWindow()
        }
    
    @objc private func repositionWindow() {
        guard let targetScreen = findTargetScreen() else { return }
        
        let bestOrigin = findBestOffscreenPosition(targetScreen: targetScreen)
        self.setFrameOrigin(bestOrigin)
    }
    
    private func findTargetScreen() -> NSScreen? {
        // 1. Try Exact Match (Name + ID)
        if let exactMatch = NSScreen.screens.first(where: { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let idString = "\(screen.localizedName) (\(screenID))"
            return idString == self.displayID
        }) {
            return exactMatch
        }
        
        // 2. FIX: Fuzzy Match (Name only)
        // If the ID changed (e.g. after reboot), try to find a screen with the same Name.
        let cleanName = self.displayID.components(separatedBy: " (").first ?? self.displayID
        if let nameMatch = NSScreen.screens.first(where: { $0.localizedName == cleanName }) {
            return nameMatch
        }
        
        // 3. Fallback
        return NSScreen.main
    }
    
    // NEW: Smart "Safe Zone" Scanner
    private func findBestOffscreenPosition(targetScreen: NSScreen) -> NSPoint {
        let allScreens = NSScreen.screens
        let frame = targetScreen.frame
        let size = self.frame.size
        
        // Distance to push off-screen (small enough to stay associated, large enough to hide)
        let offset: CGFloat = 50
        
        // 1. Define Candidates (Cardinal Directions)
        // Note: AppKit coords (0,0 is bottom-left).
        let top    = NSPoint(x: frame.midX - size.width/2, y: frame.maxY + offset)
        let bottom = NSPoint(x: frame.midX - size.width/2, y: frame.minY - size.height - offset)
        let left   = NSPoint(x: frame.minX - size.width - offset, y: frame.midY - size.height/2)
        let right  = NSPoint(x: frame.maxX + offset, y: frame.midY - size.height/2)
        
        let cardinalCandidates = [top, bottom, left, right]
        
        // 2. Check Intersections (Preferred)
        for point in cardinalCandidates {
            let candidateRect = NSRect(origin: point, size: size)
            
            let intersectsAny = allScreens.contains { screen in
                // We use a slightly smaller rect to avoid false positives on touching edges
                return screen.frame.intersects(candidateRect.insetBy(dx: 5, dy: 5))
            }
            
            if !intersectsAny {
                // Found a clean spot!
                return point
            }
        }
        
        // 3. Fallback: Corners (If cardinal directions blocked)
        let tr = NSPoint(x: frame.maxX + offset, y: frame.maxY + offset)
        let tl = NSPoint(x: frame.minX - size.width - offset, y: frame.maxY + offset)
        let br = NSPoint(x: frame.maxX + offset, y: frame.minY - size.height - offset)
        let bl = NSPoint(x: frame.minX - size.width - offset, y: frame.minY - size.height - offset)
        
        let cornerCandidates = [tr, tl, br, bl]
        
        for point in cornerCandidates {
            let candidateRect = NSRect(origin: point, size: size)
            let intersectsAny = allScreens.contains { screen in
                return screen.frame.intersects(candidateRect.insetBy(dx: 5, dy: 5))
            }
            if !intersectsAny { return point }
        }

        // 4. Worst Case: Surrounded (e.g. Center of 3x3 grid)
        // We pick the cardinal direction with the SMALLEST overlap area
        var bestPoint = top
        var minOverlapArea: CGFloat = .greatestFiniteMagnitude
        
        for point in cardinalCandidates {
            let candidateRect = NSRect(origin: point, size: size)
            var totalOverlap: CGFloat = 0
            
            for screen in allScreens {
                let intersection = screen.frame.intersection(candidateRect)
                if !intersection.isEmpty {
                    totalOverlap += intersection.width * intersection.height
                }
            }
            
            if totalOverlap < minOverlapArea {
                minOverlapArea = totalOverlap
                bestPoint = point
            }
        }
        
        return bestPoint
    }
    
    func updateName(_ name: String) {
        DispatchQueue.main.async {
            // Calculate optimal font size for new name
            let padding: CGFloat = 20
            let maxWidth = (self.frameWidth) - (padding * 2)
            let maxHeight = (self.frameHeight) - (padding * 2)
            
            var fontSize: CGFloat = 50
            var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            var stringSize = attributedString.size()
            
            while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
                fontSize -= 2
                attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
                stringSize = attributedString.size()
            }
            
            self.label.font = .systemFont(ofSize: fontSize, weight: .medium)
            self.label.stringValue = name
            
            // Recenter the label
            if self.contentView != nil {
                let labelFrame = NSRect(
                    x: (self.frameWidth - stringSize.width) / 2,
                    y: (self.frameHeight - stringSize.height) / 2,
                    width: stringSize.width,
                    height: stringSize.height
                )
                self.label.frame = labelFrame
            }
        }
    }
    
    var currentName: String {
        return label.stringValue
    }
}
