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
        let nameLabel = NSTextField(labelWithString: NSLocalizedString("about.app_name", comment: ""))
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)
        
        // Version
        var versionLabel: NSTextField?
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let vLabel = NSTextField(labelWithString: "v\(version)")
            vLabel.font = .systemFont(ofSize: 13)
            vLabel.textColor = .secondaryLabelColor
            vLabel.alignment = .center
            vLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(vLabel)
            versionLabel = vLabel
        }

        // GitHub text link
        let githubLink = NSTextField(labelWithString: NSLocalizedString("about.github_link", comment: ""))
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
        let descriptionLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("about.description", comment: ""))
        descriptionLabel.alignment = .center
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        
        // Copyright
        let year = Calendar.current.component(.year, from: Date())
        let copyrightString = String(format: NSLocalizedString("about.copyright", comment: ""), year)
        let copyrightLabel = NSTextField(labelWithString: copyrightString)
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
    private var checkUpdateButton: NSButton!
    private var autoCheckUpdateButton: NSButton!
    
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
        launchAtLoginButton = NSButton(
            checkboxWithTitle: NSLocalizedString("settings.launch_at_login", comment: ""),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        launchAtLoginButton.frame = NSRect(x: 20, y: 260, width: 200, height: 20)
        launchAtLoginButton.state = getLaunchAtLoginState()
        view.addSubview(launchAtLoginButton)

        // Show labels checkbox
        showLabelsButton = NSButton(
            checkboxWithTitle: NSLocalizedString("settings.show_labels", comment: ""),
            target: self,
            action: #selector(toggleLabels)
        )
        showLabelsButton.frame = NSRect(x: 20, y: 230, width: 200, height: 20)
        showLabelsButton.state = labelManager.isEnabled ? .on : .off
        view.addSubview(showLabelsButton)
        
        // Auto Check for Update toggle
        autoCheckUpdateButton = NSButton(
            checkboxWithTitle: NSLocalizedString("settings.auto_check_update", comment: ""),
            target: self,
            action: #selector(toggleAutoCheckUpdate)
        )
        autoCheckUpdateButton.frame = NSRect(x: 20, y: 200, width: 250, height: 20)
        autoCheckUpdateButton.state = UpdateManager.isAutoCheckEnabled ? .on : .off
        view.addSubview(autoCheckUpdateButton)

        // Reset names button
        resetButton = NSButton(frame: NSRect(x: 20, y: 155, width: 200, height: 32))
        resetButton.title = NSLocalizedString("settings.reset_button", comment: "")
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetNames)
        view.addSubview(resetButton)

        // Check for Update button
        checkUpdateButton = NSButton(frame: NSRect(x: 20, y: 120, width: 200, height: 32))
        checkUpdateButton.title = NSLocalizedString("settings.check_update_button", comment: "")
        checkUpdateButton.bezelStyle = .rounded
        checkUpdateButton.target = self
        checkUpdateButton.action = #selector(checkForUpdate)
        view.addSubview(checkUpdateButton)

        self.view = view
    }
    @objc private func checkForUpdate() {
        UpdateManager.shared.checkForUpdate(from: self.view.window, suppressUpToDateAlert: false)
    }

    @objc private func toggleAutoCheckUpdate() {
        let enabled = autoCheckUpdateButton.state == .on
        UpdateManager.isAutoCheckEnabled = enabled
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
        alert.messageText = NSLocalizedString("settings.reset_alert_message", comment: "")
        alert.informativeText = NSLocalizedString("settings.reset_alert_informative", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("settings.reset_alert_button_reset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("settings.reset_alert_button_cancel", comment: ""))
        
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
        generalTab.label = NSLocalizedString("settings.tab.general", comment: "")
        if let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General Settings") {
            image.isTemplate = true
            generalTab.image = image
        }
        
        let aboutTab = NSTabViewItem(viewController: AboutViewController())
        aboutTab.label = NSLocalizedString("settings.tab.about", comment: "")
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

