import Foundation
import AppKit

class DesktopLabelManager: ObservableObject {
    @Published private(set) var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "DesktopLabelEnabled")
            updateLabelsVisibility()
        }
    }
    
    private var currentWindow: DesktopLabelWindow?
    private weak var spaceManager: DesktopSpaceManager?
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: "DesktopLabelEnabled")

        // Monitor space changes using distributed notifications
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.spaces.switchedSpaces"),
            object: nil,
            queue: .main
        ) { _ in
            self?.handleSpaceChange()
        }
        
        // Also monitor window layout changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self?.handleScreenChange()
        }
        
        // Initial setup
        if isEnabled {
            handleSpaceChange()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        removeWindow()
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
    }
    
    func updateLabel(for spaceId: Int, name: String) {
        DispatchQueue.main.async {
            if self.isEnabled {
                if let window = self.currentWindow {
                    window.updateName(name)
                } else {
                    self.createWindow(for: spaceId, name: name)
                }
            }
        }
    }
    
    private func createWindow(for spaceId: Int, name: String) {
        // Remove existing window if any
        removeWindow()
        
        // Create new window
        let window = DesktopLabelWindow(spaceId: spaceId, name: name)
        currentWindow = window
        window.orderFront(nil)
    }
    
    private func removeWindow() {
        currentWindow?.close()
        currentWindow = nil
    }
    
    private func updateLabelsVisibility() {
        if isEnabled {
            handleSpaceChange()
        } else {
            removeWindow()
        }
    }
    
    @objc private func handleSpaceChange() {
        guard let spaceManager = spaceManager,
              let currentSpace = SpaceHelper.getCurrentSpaceNumber() else {
            return
        }
        
        let name = spaceManager.getSpaceName(currentSpace)
        updateLabel(for: currentSpace, name: name)
    }
    
    @objc private func handleScreenChange() {
        // Update window position if needed
        if let window = currentWindow,
           let screen = NSScreen.main {
            let centerX = screen.frame.midX - (103 / 2)
            let y = screen.frame.maxY - 31 - 5
            window.setFrameOrigin(NSPoint(x: centerX, y: y))
        }
    }
} 