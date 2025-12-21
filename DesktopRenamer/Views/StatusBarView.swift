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
    static private var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popover: NSPopover
    @ObservedObject private var spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?
    private var renameItem: NSMenuItem!
    private var showLabelsMenuItem: NSMenuItem!
    
    static let isStatusBarHiddenKey = "isStatusBarHidden"
    static var isStatusBarHidden: Bool {
        get { UserDefaults.standard.bool(forKey: isStatusBarHiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStatusBarHiddenKey) }
    }
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.labelManager = SpaceLabelManager(spaceManager: spaceManager)
        
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        setupMenuBar()
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
        
        updateStatusBarTitle()
        setupObservers()
        
        updateRenameMenuItemState()
    }
    
    deinit {
        // Ensure dock icon is hidden when app quits
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupObservers() {
        // Observe current space ID changes
        spaceManager.$currentSpaceUUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaceId in
                self?.updateStatusBarTitle()
                // Update label for current space
                if let name = self?.spaceManager.getSpaceName(spaceId) {
                    self?.labelManager.updateLabel(for: spaceId, name: name)
                }
                
                self?.updateRenameMenuItemState()
            }
            .store(in: &cancellables)
        
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let currentSpaceUUID = self?.spaceManager.currentSpaceUUID,
                   let newName = self?.spaceManager.getSpaceName(currentSpaceUUID),
                   let button = StatusBarController.statusItem.button,
                   button.title != newName {
                    self?.updateStatusBarTitle()
                }
            }
            .store(in: &cancellables)
        
        // Observe labelManager.isEnabled
        labelManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateShowLabelsMenuItemState()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarTitle() {
        if let button = StatusBarController.statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
            button.title = name
        }
    }
    
    private func setupMenuBar() {
        if let button = StatusBarController.statusItem.button {
            button.title = "Loading..."
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Add rename option for current space
        self.renameItem = NSMenuItem(
            title: NSLocalizedString("Menu.RenameCurrentSpace", comment: ""),
            action: nil, // Temporarily
            keyEquivalent: "r"
        )
        renameItem.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)
        menu.addItem(self.renameItem)
        
        // Add troubleshoot helper
        let troubleshootItem = NSMenuItem(
            title: NSLocalizedString("Troubleshoot Space Detection", comment: ""),
            action: #selector(troubleshootSpaceDetection),
            keyEquivalent: ""
        )
        troubleshootItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        troubleshootItem.target = self
        menu.addItem(troubleshootItem)
        
        // Add show labels option
        self.showLabelsMenuItem = NSMenuItem(
            title: NSLocalizedString("Menu.ShowLabels", comment: "Toggle desktop labels visibility"),
            action: #selector(toggleLabelsFromMenu),
            keyEquivalent: "l"
        )
        self.showLabelsMenuItem.target = self
        self.showLabelsMenuItem.state = labelManager.isEnabled ? .on : .off
        self.showLabelsMenuItem.image = NSImage(systemSymbolName: "appwindow.swipe.rectangle", accessibilityDescription: nil)
        menu.addItem(self.showLabelsMenuItem)
        
        // Add a separator
        menu.addItem(NSMenuItem.separator())
        
        // Add settings option
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Menu.Settings", comment: ""),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add quit option
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
    
    private func updateRenameMenuItemState() {
        let currentSpaceNum = spaceManager.getSpaceNum(spaceManager.currentSpaceUUID)
        
        if currentSpaceNum == 0 {
            // Fullscreen
            self.renameItem?.isEnabled = false
            self.renameItem?.target = nil
            self.renameItem?.action = nil
        } else {
            self.renameItem?.isEnabled = true
            self.renameItem?.target = self
            self.renameItem?.action = #selector(renameCurrentSpace)
        }
    }
    
    @objc private func renameCurrentSpace() {
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
        
        self.showLabelsMenuItem.state = labelManager.isEnabled ? .on : .off
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 2. CONFIG: Hide the native title bar elements
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        
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
    
    private func updateShowLabelsMenuItemState() {
        self.showLabelsMenuItem.state = labelManager.isEnabled ? .on : .off
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
