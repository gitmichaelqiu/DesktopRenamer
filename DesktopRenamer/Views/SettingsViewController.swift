import Cocoa
import ServiceManagement

class AboutViewController: NSViewController {
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Add app icon
        let iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        if let icon = NSImage(named: "AppIcon") {
            iconImageView.image = icon
            iconImageView.imageScaling = .scaleProportionallyUpOrDown
            iconImageView.wantsLayer = true
            iconImageView.layer?.cornerRadius = 10
            iconImageView.layer?.masksToBounds = true
        } else {
            iconImageView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: "App Icon")
            iconImageView.imageScaling = .scaleProportionallyUpOrDown
            iconImageView.wantsLayer = true
            iconImageView.layer?.cornerRadius = 10
            iconImageView.layer?.masksToBounds = true
        }
        view.addSubview(iconImageView)

        // App name
        let nameLabel = NSTextField(labelWithString: "DesktopRenamer")
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)
        
        // Version
        var versionLabel: NSTextField?
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let vLabel = NSTextField(labelWithString: "Version \(version)")
            vLabel.font = .systemFont(ofSize: 13)
            vLabel.textColor = .secondaryLabelColor
            vLabel.alignment = .center
            vLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(vLabel)
            versionLabel = vLabel
        }

        // GitHub text link
        let githubLink = NSTextField(labelWithString: "GitHub Repository")
        githubLink.font = .systemFont(ofSize: 13)
        githubLink.textColor = .systemBlue
        githubLink.alignment = .center
        githubLink.isEditable = false
        githubLink.isSelectable = true
        githubLink.isBezeled = false
        githubLink.translatesAutoresizingMaskIntoConstraints = false
        githubLink.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openGitHub)))
        view.addSubview(githubLink)
        
        // Description
        let descriptionLabel = NSTextField(wrappingLabelWithString: "DesktopRenamer allows you to give custom names to your macOS desktop spaces, making it easier to identify and organize your workspaces.")
        descriptionLabel.alignment = .center
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        
        // Copyright
        let year = Calendar.current.component(.year, from: Date())
        let copyrightLabel = NSTextField(labelWithString: "© \(year) Michael Yicheng Qiu")
        copyrightLabel.font = .systemFont(ofSize: 12)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyrightLabel)
        
        // Auto Layout constraints
        // Add githubLink below the iconImageView
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 100),
            iconImageView.heightAnchor.constraint(equalToConstant: 100),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),

            versionLabel?.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2) ?? nameLabel.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            versionLabel?.centerXAnchor.constraint(equalTo: view.centerXAnchor) ?? nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: (versionLabel ?? nameLabel).bottomAnchor, constant: 16),
            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),

            githubLink.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 12),
            githubLink.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            githubLink.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),

            copyrightLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            copyrightLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ].compactMap { $0 })
        
        self.view = view
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer") {
            NSWorkspace.shared.open(url)
        }
    }
}

class GeneralSettingsViewController: NSViewController {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    private var launchAtLoginButton: NSButton!
    private var showLabelsButton: NSButton!
    private var resetButton: NSButton!
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
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
        
        // Show labels checkbox
        showLabelsButton = NSButton(checkboxWithTitle: "Show desktop labels", target: self, action: #selector(toggleLabels))
        showLabelsButton.frame = NSRect(x: 20, y: 230, width: 200, height: 20)
        showLabelsButton.state = labelManager.isEnabled ? .on : .off
        view.addSubview(showLabelsButton)
        
        // Reset names button
        resetButton = NSButton(frame: NSRect(x: 20, y: 180, width: 200, height: 32)) // Change back to 180 when adding back SLW
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
    
    @objc private func toggleLabels() {
        labelManager.toggleEnabled()
        showLabelsButton.state = labelManager.isEnabled ? .on : .off
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
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        super.init(nibName: nil, bundle: nil)
        
        // Set tab style
        self.tabStyle = .toolbar
        
        // Create tab view items
        let generalTab = NSTabViewItem(viewController: GeneralSettingsViewController(spaceManager: spaceManager, labelManager: labelManager))
        generalTab.label = "General"
        if let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General Settings") {
            image.isTemplate = true
            generalTab.image = image
        }
        
        let aboutTab = NSTabViewItem(viewController: AboutViewController())
        aboutTab.label = "About"
        if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About") {
            image.isTemplate = true
            aboutTab.image = image
        }
        
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

