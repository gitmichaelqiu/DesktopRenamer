import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    private let frameWidth: CGFloat = 400
    private let frameHeight: CGFloat = 200
    
    init(spaceId: String, name: String, spaceManager: SpaceManager) {
        self.spaceId = spaceId
        self.spaceManager = spaceManager
        
        // Create the label
        label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 50, weight: .medium) // Initial font size, will be adjusted
        label.textColor = .labelColor
        label.alignment = .center
        
        // Create a glass effect view for the background
        let contentView: NSView
        if #available(macOS 26.0, *) {
            let glassEffectView = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
            contentView = glassEffectView
        } else {
            // Fallback on earlier versions
            let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
            contentView = visualEffectView
        }
        
        // Calculate and set optimal font size and frame
        let padding: CGFloat = 20
        let maxWidth = frameWidth - (padding * 2)
        let maxHeight = frameHeight - (padding * 2)
        
        // Start with initial font size and adjust down if needed
        var fontSize: CGFloat = 50
        var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
        var stringSize = attributedString.size()
        
        while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            stringSize = attributedString.size()
        }
        
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        
        // Center the label in the glass effect view
        let labelFrame = NSRect(
            x: (frameWidth - stringSize.width) / 2,
            y: (frameHeight - stringSize.height) / 2,
            width: stringSize.width,
            height: stringSize.height
        )
        label.frame = labelFrame
        
        // Add label to glass effect view
        contentView.addSubview(label)
        
        // Initialize window with panel behavior
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true  // Changed to true to prevent automatic display
        )
        
        self.contentView = contentView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 6
        self.contentView?.addSubview(label)
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        
        // Set window to be managed by Mission Control but stay in current space
        self.collectionBehavior = [
            .managed,
            .stationary,
            .participatesInCycle,  // Changed to ensure proper space management
            .fullScreenAuxiliary   // Ensures proper behavior in full screen
        ]
        
        // Make window completely invisible to mouse events
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false
        
        // Position the window at the top center of the screen
        if let screen = NSScreen.main {
            let centerX = screen.frame.midX - (103 / 2)
            let y = 1.5 * screen.frame.maxY
            self.setFrameOrigin(NSPoint(x: centerX, y: y))
        }
        
        // Additional properties to make window more invisible
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Observe space name changes
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
        
        self.isRestorable = false
        
        // In init or a setup method
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    @objc private func handleWake() {
        if let screen = NSScreen.main {
            let centerX = screen.frame.midX - (self.frame.width / 2)
            let y = 1.5 * screen.frame.maxY
            self.setFrameOrigin(NSPoint(x: centerX, y: y))
        }
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
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
