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
            // 1. Initialize Properties
            self.spaceId = spaceId
            self.displayID = displayID
            self.spaceManager = spaceManager
            
            let newLabel = NSTextField(labelWithString: name)
            self.label = newLabel
            
            // 2. Define Dimensions
            let kWidth: CGFloat = 400
            let kHeight: CGFloat = 200
            
            // 3. Find Target Screen
            let foundScreen = NSScreen.screens.first { screen in
                let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
                let idString = "\(screen.localizedName) (\(screenID))"
                if idString == displayID { return true }
                let cleanName = displayID.components(separatedBy: " (").first ?? displayID
                return screen.localizedName == cleanName
            }
            let targetScreen = foundScreen ?? NSScreen.main!
            
            // 4. Calculate Center Rect (For initial creation only)
            // We MUST create it here first to ensure macOS assigns it to the correct display.
            let screenFrame = targetScreen.frame
            let initialRect = NSRect(
                x: screenFrame.midX - (kWidth / 2),
                y: screenFrame.midY - (kHeight / 2),
                width: kWidth,
                height: kHeight
            )
            
            // 5. Initialize Window
            super.init(
                contentRect: initialRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false // Create immediately
            )
            
            // 6. Force Screen Association
            self.setFrame(initialRect, display: true)
            
            // 7. View Configuration
            // (Standard view setup code...)
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
            
            // Collection Behaviors
            self.collectionBehavior = [.managed, .stationary, .participatesInCycle, .fullScreenAuxiliary]
            
            self.ignoresMouseEvents = true
            self.titlebarAppearsTransparent = true
            self.titleVisibility = .hidden
            self.standardWindowButton(.closeButton)?.isHidden = true
            self.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.standardWindowButton(.zoomButton)?.isHidden = true
            self.isRestorable = false
            
            // 9. Observers
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
            
            // 10. MOVE OFF-SCREEN (Fix: Do this LAST, and do not reset to center)
            // We use async to allow the window server to digest the initial "Center" placement first.
            DispatchQueue.main.async { [weak self] in
                self?.repositionWindow()
            }
        }
    
    @objc private func repositionWindow() {
        guard let targetScreen = findTargetScreen() else { return }
        
        let bestOrigin = findBestOffscreenPosition(targetScreen: targetScreen)
        self.setFrameOrigin(bestOrigin)
        
        print("Window \(spaceId) repositioned to \(bestOrigin) for screen \(targetScreen.localizedName)")
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

    private func findBestOffscreenPosition(targetScreen: NSScreen) -> NSPoint {
            let allScreens = NSScreen.screens
            let w = self.frame.width
            let h = self.frame.height
            let f = targetScreen.frame
            
            // ANCHOR STRATEGY:
            // Instead of a gap (buffer = 50), we use a negative buffer (overlap = 1.0).
            // This ensures 1 pixel of the window is technically "on screen", preventing
            // macOS from resetting it to the Main Display.
            let overlap: CGFloat = 1.0
            
            // 1. Top-Left Anchor (Hangs off left, 1px on top edge)
            // x: ends at minX + 1 -> origin = minX - w + 1
            // y: starts at maxY - 1
            let topLeft = NSPoint(x: f.minX - w + overlap, y: f.maxY - overlap)
            
            // 2. Top-Right Anchor (Hangs off right, 1px on top edge)
            // x: starts at maxX - 1
            // y: starts at maxY - 1
            let topRight = NSPoint(x: f.maxX - overlap, y: f.maxY - overlap)
            
            // 3. Bottom-Left Anchor (Hangs off left, 1px on bottom edge)
            // x: ends at minX + 1 -> origin = minX - w + 1
            // y: ends at minY + 1 -> origin = minY - h + overlap (wait, y is bottom-left)
            // Let's stick to the corners:
            let bottomLeft = NSPoint(x: f.minX - w + overlap, y: f.minY - h + overlap)
            
            // 4. Bottom-Right Anchor (Hangs off right, 1px on bottom edge)
            let bottomRight = NSPoint(x: f.maxX - overlap, y: f.minY - h + overlap)
            
            let candidates = [topLeft, topRight, bottomLeft, bottomRight]
            
            // Check which candidate DOES NOT touch any *other* screen
            for point in candidates {
                let candidateRect = NSRect(origin: point, size: self.frame.size)
                
                // It WILL intersect the target screen (by design, 1px).
                // We must check if it intersects ANY OTHER screen.
                let touchesNeighbor = allScreens.contains { screen in
                    // Skip the target screen itself
                    if screen == targetScreen { return false }
                    
                    // Check intersection with others (using small inset to avoid false positives on shared edges)
                    return screen.frame.intersects(candidateRect)
                }
                
                if !touchesNeighbor {
                    return point // This corner is free (no monitor attached here)
                }
            }
            
            // Fallback: If all 4 corners touch neighbors (e.g. 3x3 grid middle screen),
            // we default to Top-Left. It's better to overlap a neighbor slightly than
            // to snap to Main Screen (0,0).
            return topLeft
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
