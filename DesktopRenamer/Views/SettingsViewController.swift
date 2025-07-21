import Cocoa
import ServiceManagement

class AboutViewController: NSViewController {
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // App name
        let nameLabel = NSTextField(labelWithString: "Desktop Renamer")
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        nameLabel.frame = NSRect(x: 20, y: 260, width: 360, height: 24)
        nameLabel.alignment = .center
        view.addSubview(nameLabel)
        
        // Version
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let versionLabel = NSTextField(labelWithString: "Version \(version)")
            versionLabel.font = .systemFont(ofSize: 13)
            versionLabel.textColor = .secondaryLabelColor
            versionLabel.frame = NSRect(x: 20, y: 240, width: 360, height: 17)
            versionLabel.alignment = .center
            view.addSubview(versionLabel)
        }
        
        // Description
        let descriptionLabel = NSTextField(wrappingLabelWithString: "Desktop Renamer allows you to give custom names to your macOS desktop spaces, making it easier to identify and organize your workspaces.")
        descriptionLabel.frame = NSRect(x: 20, y: 160, width: 360, height: 60)
        descriptionLabel.alignment = .center
        view.addSubview(descriptionLabel)
        
        // Copyright
        let year = Calendar.current.component(.year, from: Date())
        let copyrightLabel = NSTextField(labelWithString: "© \(year) Desktop Renamer")
        copyrightLabel.font = .systemFont(ofSize: 12)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.frame = NSRect(x: 20, y: 20, width: 360, height: 17)
        copyrightLabel.alignment = .center
        view.addSubview(copyrightLabel)
        
        self.view = view
    }
}

class GeneralSettingsViewController: NSViewController {
    private let spaceManager: DesktopSpaceManager
    private var launchAtLoginButton: NSButton!
    private var resetButton: NSButton!
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Launch at login checkbox
        launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginButton.frame = NSRect(x: 20, y: 260, width: 200, height: 20)
        launchAtLoginButton.state = getLaunchAtLoginState()
        view.addSubview(launchAtLoginButton)
        
        // Reset names button
        resetButton = NSButton(frame: NSRect(x: 20, y: 220, width: 200, height: 32))
        resetButton.title = "Reset All Desktop Names"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetNames)
        view.addSubview(resetButton)
        
        self.view = view
    }
    
    private func getLaunchAtLoginState() -> NSControl.StateValue {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
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
                launchAtLoginButton.state = getLaunchAtLoginState()
            }
        } else {
            if let bundleId = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleId as CFString, launchAtLoginButton.state == .on)
                if !success {
                    launchAtLoginButton.state = getLaunchAtLoginState()
                }
            }
        }
    }
    
    @objc private func resetNames() {
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
        
        let strongSelf = self
        
        alert.beginSheetModal(for: window) { response in
            DispatchQueue.main.async {
                strongSelf.resetButton.isEnabled = true
                
                if response == .alertFirstButtonReturn {
                    strongSelf.spaceManager.resetAllNames()
                }
            }
        }
    }
}

class SettingsViewController: NSTabViewController {
    private let spaceManager: DesktopSpaceManager
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        super.init(nibName: nil, bundle: nil)
        
        // Set tab style
        self.tabStyle = .toolbar
        
        // Create tab view items
        let generalTab = NSTabViewItem(viewController: GeneralSettingsViewController(spaceManager: spaceManager))
        generalTab.label = "General"
        
        let aboutTab = NSTabViewItem(viewController: AboutViewController())
        aboutTab.label = "About"
        
        // Add tabs
        self.addTabViewItem(generalTab)
        self.addTabViewItem(aboutTab)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the preferred content size
        self.preferredContentSize = NSSize(width: 400, height: 300)
    }
} 