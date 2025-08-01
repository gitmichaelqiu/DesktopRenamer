import Cocoa
import Combine

class DesktopLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: Int
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: DesktopSpaceManager
    
    init(spaceId: Int, name: String, spaceManager: DesktopSpaceManager) {
        self.spaceId = spaceId
        self.spaceManager = spaceManager
        
        // Create the label
        label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 50, weight: .medium) // Initial font size, will be adjusted
        label.textColor = .white
        label.alignment = .center
        
        // Create a visual effect view for the background
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Calculate and set optimal font size and frame
        let padding: CGFloat = 20
        let maxWidth = visualEffect.frame.width - (padding * 2)
        let maxHeight = visualEffect.frame.height - (padding * 2)
        
        // Start with initial font size and adjust down if needed
        var fontSize: CGFloat = 50
        var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
        var stringSize = attributedString.size()
        
        // Reduce font size until text fits within bounds with some padding
        while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            stringSize = attributedString.size()
        }
        
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        
        // Center the label in the visual effect view
        let labelFrame = NSRect(
            x: (visualEffect.frame.width - stringSize.width) / 2,
            y: (visualEffect.frame.height - stringSize.height) / 2,
            width: stringSize.width,
            height: stringSize.height
        )
        label.frame = labelFrame
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        
        // Add label to visual effect view
        visualEffect.addSubview(label)
        
        // Initialize window with panel behavior
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
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
        spaceManager.$desktopSpaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
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
            let maxWidth = self.contentView?.frame.width ?? 400 - (padding * 2)
            let maxHeight = self.contentView?.frame.height ?? 300 - (padding * 2)
            
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
            if let visualEffect = self.contentView as? NSVisualEffectView {
                let labelFrame = NSRect(
                    x: (visualEffect.frame.width - stringSize.width) / 2,
                    y: (visualEffect.frame.height - stringSize.height) / 2,
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
