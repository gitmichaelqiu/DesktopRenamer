import SwiftUI
import Combine
import AppKit

class RenameViewController: NSViewController {
    private var spaceManager: SpaceManager
    private var completion: () -> Void
    private var textField: NSTextField!
    
    init(spaceManager: SpaceManager, completion: @escaping () -> Void) {
        self.spaceManager = spaceManager
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        // Create the main view
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        
        // Create and configure the text field
        textField = NSTextField(frame: NSRect(x: 20, y: 40, width: 200, height: 24))
        textField.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
        textField.placeholderString = NSLocalizedString("Rename.Placeholder", comment: "")
        textField.delegate = self
        view.addSubview(textField)
        
        // Create the label
        let labelString = String(format: NSLocalizedString("Rename.Label", comment: ""), spaceManager.getSpaceNum(spaceManager.currentSpaceUUID))
        let label = NSTextField(labelWithString: labelString)
        label.frame = NSRect(x: 20, y: 15, width: 200, height: 17)
        label.textColor = .secondaryLabelColor
        view.addSubview(label)
        
        self.view = view
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textField)
    }
}

extension RenameViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Handle Enter key
            handleRename()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Handle Escape key
            dismiss(nil)
            return true
        }
        return false
    }
    
    private func handleRename() {
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            spaceManager.renameSpace(spaceManager.currentSpaceUUID, to: newName)
        }
        dismiss(nil)
        completion()
    }
}

class StatusBarController: NSObject {
    @ObservedObject private var spaceManager: SpaceManager
    static private var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?
    
    // Kept for direct access, though menu is now rebuilt
    private var renameItem: NSMenuItem?
    private var showLabelsMenuItem: NSMenuItem?
    
    static let isStatusBarHiddenKey = "isStatusBarHidden"
    static var isStatusBarHidden: Bool {
        get { UserDefaults.standard.bool(forKey: isStatusBarHiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStatusBarHiddenKey) }
    }
    
    let labelManager: SpaceLabelManager
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.labelManager = SpaceLabelManager(spaceManager: spaceManager)
        
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        // Build initial menu
        rebuildMenu()
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
        
        updateStatusBarTitle()
        setupObservers()
    }
    
    deinit {
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupObservers() {
        // Observe current space ID changes
        spaceManager.$currentSpaceUUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaceId in
                self?.updateStatusBarTitle()
                self?.rebuildMenu() // Rebuild menu to update ticks and logic
                
                // Update label for current space
                if let name = self?.spaceManager.getSpaceName(spaceId) {
                    self?.labelManager.updateLabel(for: spaceId, name: name)
                }
            }
            .store(in: &cancellables)
        
        // Observe space name/count changes
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
                self?.rebuildMenu() // Rebuild to show new spaces/names
            }
            .store(in: &cancellables)
        
        // Observe labelManager.isEnabled
        labelManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Just toggle state in existing item if possible, or rebuild
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarTitle() {
        if let button = StatusBarController.statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
            button.title = name
        }
    }
    
    private func rebuildMenu() {
        let menu = NSMenu()
        
        // 1. Desktop List Section
        let sortedSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
        if !sortedSpaces.isEmpty {
            // Optional Header
            // let header = NSMenuItem(title: "Switch to Desktop", action: nil, keyEquivalent: "")
            // header.isEnabled = false
            // menu.addItem(header)
            
            for space in sortedSpaces {
                let name = spaceManager.getSpaceName(space.id)
                let item = NSMenuItem(title: name, action: #selector(selectSpace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = space.id // Store ID to switch
                
                // Tick the current space
                if space.id == spaceManager.currentSpaceUUID {
                    item.state = .on
                } else {
                    item.state = .off
                }
                
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Rename Option
        let rename = NSMenuItem(
            title: NSLocalizedString("Menu.RenameCurrentSpace", comment: ""),
            action: nil, // Set dynamically below
            keyEquivalent: "r"
        )
        rename.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)
        
        // Configure Rename State
        let currentSpaceNum = spaceManager.getSpaceNum(spaceManager.currentSpaceUUID)
        if currentSpaceNum == 0 { // Fullscreen
            rename.isEnabled = false
        } else {
            rename.isEnabled = true
            rename.target = self
            rename.action = #selector(renameCurrentSpace)
        }
        
        self.renameItem = rename
        menu.addItem(rename)
        
        // 3. Troubleshoot
        let troubleshootItem = NSMenuItem(
            title: NSLocalizedString("Troubleshoot Space Detection", comment: ""),
            action: #selector(troubleshootSpaceDetection),
            keyEquivalent: ""
        )
        troubleshootItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        troubleshootItem.target = self
        menu.addItem(troubleshootItem)
        
        // 4. Show Labels
        let showLabels = NSMenuItem(
            title: NSLocalizedString("Menu.ShowLabels", comment: "Toggle desktop labels visibility"),
            action: #selector(toggleLabelsFromMenu),
            keyEquivalent: "l"
        )
        showLabels.target = self
        showLabels.state = labelManager.isEnabled ? .on : .off
        showLabels.image = NSImage(systemSymbolName: "appwindow.swipe.rectangle", accessibilityDescription: nil)
        self.showLabelsMenuItem = showLabels
        menu.addItem(showLabels)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Settings
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Menu.Settings", comment: ""),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 6. Quit
        let quitItem = NSMenuItem(
            title: NSLocalizedString("Menu.Quit", comment: ""),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
        
        StatusBarController.statusItem.menu = menu
    }
    
    @objc func selectSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? String else { return }
        
        // If we are already on that space, do nothing.
        if spaceID == spaceManager.currentSpaceUUID { return }
        
        // Use the new helper to switch
        if let space = spaceManager.spaceNameDict.first(where: { $0.id == spaceID }) {
            spaceManager.switchToSpace(space)
        }
    }
    
    @objc func renameCurrentSpace() {
        if spaceManager.getSpaceNum(spaceManager.currentSpaceUUID) == 0 {
            return // Fullscreen
        }
        
        guard let button = StatusBarController.statusItem.button else { return }
        
        // Close the menu
        StatusBarController.statusItem.menu?.cancelTracking()
        
        // Configure the popover
        let renameVC = RenameViewController(spaceManager: spaceManager) { [weak self] in
            self?.popover.performClose(nil)
            self?.updateStatusBarTitle()
        }
        popover.contentViewController = renameVC
        
        // Show the popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    @objc private func toggleLabelsFromMenu() {
        labelManager.toggleEnabled()
        // Rebuild menu to update checkmark state immediately
        rebuildMenu()
    }
        
    @objc private func troubleshootSpaceDetection() {
        openSettingsWindow()
    
        var alertTitle = ""
        var alertMessage = ""
        
        switch spaceManager.detectionMethod {
        case .automatic:
            if spaceManager.currentSpaceUUID == "FULLSCREEN" {
                 alertTitle = NSLocalizedString("Not a fullscreen?", comment: "")
                 alertMessage = NSLocalizedString("There are no parameters to adjust for Automatic detection.\nIf the issue still happens, switch to other methods.", comment: "")
            } else {
                 alertTitle = NSLocalizedString("Not a space?", comment: "")
                 alertMessage = NSLocalizedString("There are no parameters to adjust for Automatic detection.\nIf the issue still happens, switch to other methods.", comment: "")
            }
            
        case .metric:
            if spaceManager.currentSpaceUUID == "FULLSCREEN" {
                alertTitle = NSLocalizedString("Not a fullscreen?", comment: "")
                alertMessage = NSLocalizedString("Fix this issue in\nSettings → General → Fix automatic space detection", comment: "")
            } else {
                alertTitle = NSLocalizedString("Not a space?", comment: "")
                alertMessage = NSLocalizedString("Fix this issue in\nSettings → General → Fix automatic space detection", comment: "")
            }
            
        case .manual:
            if spaceManager.currentSpaceUUID == "FULLSCREEN" {
                alertTitle = NSLocalizedString("Not a fullscreen?", comment: "")
                alertMessage = NSLocalizedString("Add it as a space in\nSettings → General → Add spaces", comment: "")
            } else {
                alertTitle = NSLocalizedString("Not a space?", comment: "")
                alertMessage = NSLocalizedString("Remove it in\nSettings → Spaces\n(Switch to other space first)", comment: "")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let window = self.settingsWindowController?.window else { return }
            
            let alert = NSAlert()
            alert.messageText = alertTitle
            alert.informativeText = alertMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        
        if let windowController = settingsWindowController {
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 1. STYLE: .fullSizeContentView is critical for "Ice" style
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        
        // 2. CONFIG: Hide the native title bar elements
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        
        // 3. REMOVE TOOLBAR: Ensures no extra space is reserved at the top
        window.toolbar = nil
        
        window.center()
        window.minSize = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        window.collectionBehavior = [.participatesInCycle]
        window.level = .normal
        
        let settingsVC = SettingsHostingController(spaceManager: spaceManager, labelManager: labelManager)
        window.contentViewController = settingsVC
        
        let windowController = NSWindowController(window: window)
        windowController.window?.delegate = self
        settingsWindowController = windowController
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        // Hide dock icon
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        settingsWindowController = nil
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    static func toggleStatusBar() {
        StatusBarController.isStatusBarHidden.toggle()
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
    }
}

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindowController?.window {
            // Hide dock icon when closing settings
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
            settingsWindowController = nil
        }
    }
}
