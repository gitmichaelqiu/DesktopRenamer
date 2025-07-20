import Cocoa
import ServiceManagement

class SettingsViewController: NSViewController {
    private let spaceManager: DesktopSpaceManager  // Changed to let to ensure strong reference
    private var launchAtLoginButton: NSButton!
    private var resetButton: NSButton!  // Keep reference to the button
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        
        // Launch at login checkbox
        launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginButton.frame = NSRect(x: 20, y: 110, width: 200, height: 20)
        launchAtLoginButton.state = getLaunchAtLoginState()
        view.addSubview(launchAtLoginButton)
        
        // Reset names button
        resetButton = NSButton(frame: NSRect(x: 20, y: 70, width: 200, height: 32))
        resetButton.title = "Reset All Desktop Names"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetNames)
        view.addSubview(resetButton)
        
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure the view controller is retained while the window is open
        if let window = view.window {
            window.delegate = self
        }
    }
    
    private func getLaunchAtLoginState() -> NSControl.StateValue {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            // For older macOS versions
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            return SMLoginItemSetEnabled(bundleId as CFString, true) ? .on : .off
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
                // Reset the button state
                launchAtLoginButton.state = getLaunchAtLoginState()
            }
        } else {
            // For older macOS versions
            if let bundleId = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleId as CFString, launchAtLoginButton.state == .on)
                if !success {
                    // Reset the button state if failed
                    launchAtLoginButton.state = getLaunchAtLoginState()
                }
            }
        }
    }
    
    @objc private func resetNames() {
        // Disable the button while alert is showing
        resetButton.isEnabled = false
        
        let alert = NSAlert()
        alert.messageText = "Reset Desktop Names"
        alert.informativeText = "Are you sure you want to reset all desktop names to their defaults?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        guard let window = view.window else {
            resetButton.isEnabled = true
            return
        }
        
        // Create a strong reference to self for the completion block
        let strongSelf = self
        
        alert.beginSheetModal(for: window) { response in
            // Re-enable the button
            DispatchQueue.main.async {
                strongSelf.resetButton.isEnabled = true
                
                if response == .alertFirstButtonReturn {
                    strongSelf.spaceManager.resetAllNames()
                }
            }
        }
    }
}

// Add window delegate to ensure proper retention
extension SettingsViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clean up any resources if needed
    }
} 