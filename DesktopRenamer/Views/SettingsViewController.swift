import Cocoa
import ServiceManagement
import Combine

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
//        showLabelsButton = NSButton(
//            checkboxWithTitle: NSLocalizedString("settings.show_labels", comment: ""),
//            target: self,
//            action: #selector(toggleLabels)
//        )
//        showLabelsButton.frame = NSRect(x: 20, y: 230, width: 200, height: 20)
//        showLabelsButton.state = labelManager.isEnabled ? .on : .off
//        view.addSubview(showLabelsButton)
        
        // Auto Check for Update toggle
        autoCheckUpdateButton = NSButton(
            checkboxWithTitle: NSLocalizedString("settings.auto_check_update", comment: ""),
            target: self,
            action: #selector(toggleAutoCheckUpdate)
        )
        autoCheckUpdateButton.frame = NSRect(x: 20, y: 230, width: 250, height: 20)
        autoCheckUpdateButton.state = UpdateManager.isAutoCheckEnabled ? .on : .off
        view.addSubview(autoCheckUpdateButton)

        // Reset names button
        resetButton = NSButton(frame: NSRect(x: 20, y: 185, width: 200, height: 32))
        resetButton.title = NSLocalizedString("settings.reset_button", comment: "")
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetNames)
        view.addSubview(resetButton)

        // Check for Update button
        checkUpdateButton = NSButton(frame: NSRect(x: 20, y: 150, width: 200, height: 32))
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

class spaceEditViewController: NSViewController {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    
    private var tableView: NSTableView!
    private var desktopSpaces: [DesktopSpace] = []
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        // Create root view
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        self.view = view
        
        setupTableView()
        loadData()
    }
    
    private func setupTableView() {
        // Scroll view
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        
        // Create table
        tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsColumnReordering = false
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        
        let numColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("num"))
        numColumn.title = "#"
        numColumn.width = 20
        numColumn.resizingMask = []
        tableView.addTableColumn(numColumn)
        
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("customName"))
        nameColumn.title = NSLocalizedString("settings.space.custom_name", comment: "")
        nameColumn.width = 250
        nameColumn.resizingMask = []
        tableView.addTableColumn(nameColumn)
        
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        actionColumn.title = NSLocalizedString("settings.space.actions", comment: "")
        actionColumn.width = 85
        actionColumn.resizingMask = []
        tableView.addTableColumn(actionColumn)
        
        // Add to scrollView
        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }
    
    private func loadData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
        
        tableView.reloadData()
    }
    
    public func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
        tableView.reloadData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    @objc private func moveRowUp(_ sender: NSButton) {
        let row = sender.tag
        guard row > 0 && row < desktopSpaces.count else { return }
        
        desktopSpaces.swapAt(row, row - 1)
        updateNumbersAndSave()
    }

    @objc private func moveRowDown(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < desktopSpaces.count - 1 else { return }
        
        desktopSpaces.swapAt(row, row + 1)
        updateNumbersAndSave()
    }

    @objc private func deleteRow(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < desktopSpaces.count else { return }
        
        let space = desktopSpaces[row]
        
        // Check again
        if space.id == spaceManager.currentSpaceUUID {
            return
        }
        
        desktopSpaces.remove(at: row)
        updateNumbersAndSave()
    }
    
    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        guard sender.clickedColumn >= 0,
              sender.clickedRow >= 0,
              sender.tableColumns[sender.clickedColumn].identifier == NSUserInterfaceItemIdentifier("customName") else {
            return
        }
        
        sender.editColumn(sender.clickedColumn, row: sender.clickedRow, with: nil, select: true)
    }

    private func updateNumbersAndSave() {
        // Reindex
        for (index, _) in desktopSpaces.enumerated() {
            desktopSpaces[index].num = index + 1
        }
        
        // Sync back to spaceManager
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.currentTotalSpace = desktopSpaces.count
        spaceManager.saveSpaces()
        
        tableView.reloadData()
    }
}

extension spaceEditViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return desktopSpaces.count
    }
}

extension spaceEditViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let space = desktopSpaces[row]
        
        // Handle num and name
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("customName") {
            let identifier = NSUserInterfaceItemIdentifier("customName")
            
            var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                
                let textField = NSTextField()
                textField.isBezeled = true
                textField.drawsBackground = true
                textField.isEditable = true
                textField.isSelectable = true
                textField.backgroundColor = .textBackgroundColor
                textField.delegate = self

                cellView?.textField = textField
                
                textField.translatesAutoresizingMaskIntoConstraints = false
                cellView?.addSubview(textField)
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.topAnchor.constraint(equalTo: cellView!.topAnchor, constant: 2),
                    textField.bottomAnchor.constraint(equalTo: cellView!.bottomAnchor, constant: -2)
                ])
            }
            
            cellView?.textField?.stringValue = space.customName == "" ?  String(format: NSLocalizedString("space.default_name", comment: ""), space.num): space.customName
            return cellView
        }
        else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("num") {
            let identifier = NSUserInterfaceItemIdentifier("num")
            let text = String(space.num)
            
            var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                let textField = NSTextField()
                textField.isBezeled = false
                textField.drawsBackground = false
                textField.isEditable = false
                textField.isSelectable = false
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                textField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            cellView?.textField?.stringValue = spaceManager.currentSpaceUUID == space.id ? "[\(text)]" : text
            return cellView
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("actions") {
            let identifier = NSUserInterfaceItemIdentifier("actions")
            
            // Reuse view
            var actionView = tableView.makeView(withIdentifier: identifier, owner: self)
            if actionView == nil {
                actionView = NSView()
                actionView?.identifier = identifier
                
                // Control buttons
                let upButton = NSButton(title: "↑", target: self, action: #selector(moveRowUp(_:)))
                upButton.bezelStyle = .texturedRounded
                upButton.font = .systemFont(ofSize: 11)
                upButton.sizeToFit()
                upButton.tag = row
                upButton.translatesAutoresizingMaskIntoConstraints = false
                
                let downButton = NSButton(title: "↓", target: self, action: #selector(moveRowDown(_:)))
                downButton.bezelStyle = .texturedRounded
                downButton.font = .systemFont(ofSize: 11)
                downButton.sizeToFit()
                downButton.tag = row
                downButton.translatesAutoresizingMaskIntoConstraints = false
                
                let deleteButton = NSButton(title: "⌫", target: self, action: #selector(deleteRow(_:)))
                deleteButton.bezelStyle = .texturedRounded
                deleteButton.font = .systemFont(ofSize: 11)
                deleteButton.sizeToFit()
                deleteButton.tag = row
                deleteButton.translatesAutoresizingMaskIntoConstraints = false
                
                // Add subview
                actionView?.addSubview(upButton)
                actionView?.addSubview(downButton)
                actionView?.addSubview(deleteButton)
                
                // Set view restrains
                let buttons = [upButton, downButton, deleteButton]
                for (index, button) in buttons.enumerated() {
                    if index > 0 {
                        button.leadingAnchor.constraint(equalTo: buttons[index-1].trailingAnchor, constant: 4).isActive = true
                    } else {
                        button.leadingAnchor.constraint(equalTo: actionView!.leadingAnchor, constant: 4).isActive = true
                    }
                    button.centerYAnchor.constraint(equalTo: actionView!.centerYAnchor).isActive = true
                }
                deleteButton.trailingAnchor.constraint(equalTo: actionView!.trailingAnchor, constant: -4).isActive = true
            }
            
            // Get buttons
            let buttons = actionView!.subviews.compactMap { $0 as? NSButton }
            let upButton = buttons.first { $0.action == #selector(moveRowUp(_:)) }
            let downButton = buttons.first { $0.action == #selector(moveRowDown(_:)) }
            let deleteButton = buttons.first { $0.action == #selector(deleteRow(_:)) }
            
            // Set tags
            upButton?.tag = row
            downButton?.tag = row
            deleteButton?.tag = row
            
            // Ban moves
            upButton?.isEnabled = row > 0
            downButton?.isEnabled = row < desktopSpaces.count - 1
            
            // Ban delete
            let isCurrentSpace = space.id == spaceManager.currentSpaceUUID
            deleteButton?.isEnabled = !isCurrentSpace
            if isCurrentSpace {
                deleteButton?.toolTip = NSLocalizedString("settings.space.cannot_delete_current", comment: "Cannot delete current space")
            } else {
                deleteButton?.toolTip = nil
            }
            
            return actionView
        }
        
        return nil
    }
    
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableColumn?.identifier == NSUserInterfaceItemIdentifier("customName")
    }

//    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
//        guard let tableColumn = tableColumn,
//              tableColumn.identifier == NSUserInterfaceItemIdentifier("customName"),
//              row >= 0 && row < desktopSpaces.count else { return }
//        
//        let newValue = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
//        
//        var space = desktopSpaces[row]
//        space.customName = newValue
//        
//        desktopSpaces[row] = space
//        
//        spaceManager.spaceNameDict = desktopSpaces
//        spaceManager.saveSpaces()
//        
//        print(newValue)
//        print("Update")
//        
//        tableView.reloadData()
//    }
}

extension spaceEditViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              let cellView = textField.superview as? NSTableCellView,
              let rowView = cellView.superview as? NSTableRowView,
              let tableView = rowView.superview as? NSTableView,
              let _ = tableView.tableColumns.firstIndex(where: { $0.identifier == NSUserInterfaceItemIdentifier("customName") }) else {
            return
        }
        
        let row = tableView.row(for: rowView)
        guard row >= 0 && row < desktopSpaces.count else { return }
        
        let newValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var space = desktopSpaces[row]
        space.customName = newValue
        desktopSpaces[row] = space
        
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.saveSpaces()
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
        
        let spaceTab = NSTabViewItem(viewController: spaceEditViewController(spaceManager: spaceManager, labelManager: labelManager))
        spaceTab.label = NSLocalizedString("settings.tab.space", comment: "")
        if let image = NSImage(systemSymbolName: "macwindow.stack", accessibilityDescription: "Edit Space") {
            image.isTemplate = true
            spaceTab.image = image
        }
        
        let aboutTab = NSTabViewItem(viewController: AboutViewController())
        aboutTab.label = NSLocalizedString("settings.tab.about", comment: "")
        if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About") {
            image.isTemplate = true
            aboutTab.image = image
        }
        
        // Add tabs
        self.addTabViewItem(generalTab)
        self.addTabViewItem(spaceTab)
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

