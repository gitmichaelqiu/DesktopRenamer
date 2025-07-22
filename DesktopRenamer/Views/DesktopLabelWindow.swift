import Cocoa

class DesktopLabelWindow: NSWindow {
    private let label: NSTextField
    private let spaceId: Int
    
    init(spaceId: Int, name: String) {
        self.spaceId = spaceId
        
        // Create the label
        label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 103, height: 31)
        
        // Create a visual effect view for the background
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 103, height: 31))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        
        // Add label to visual effect view
        visualEffect.addSubview(label)
        
        // Initialize window with panel behavior
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 103, height: 31),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true  // Changed to true to prevent automatic display
        )
        
        // Configure window properties
        self.contentView = visualEffect
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .normal
        
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
            let y = screen.frame.maxY - 31 - 5
            self.setFrameOrigin(NSPoint(x: centerX, y: y))
        }
        
        // Additional properties to make window more invisible
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    func updateName(_ name: String) {
        DispatchQueue.main.async {
            self.label.stringValue = name
        }
    }
    
    var currentName: String {
        return label.stringValue
    }
} 
