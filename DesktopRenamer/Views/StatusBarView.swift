import SwiftUI
import Combine
import AppKit

// RenameViewController remains unchanged
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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textField = NSTextField(frame: NSRect(x: 20, y: 40, width: 200, height: 24))
        textField.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
        textField.placeholderString = NSLocalizedString("Rename.Placeholder", comment: "")
        textField.delegate = self
        view.addSubview(textField)
        
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
            handleRename()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
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

class StatusBarController: NSObject, NSMenuDelegate {
    @ObservedObject private var spaceManager: SpaceManager
    static private var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?
    
    private var renameItem: NSMenuItem?
    private var showLabelsMenuItem: NSMenuItem?
    
    static let isStatusBarHiddenKey = "isStatusBarHidden"
    static var isStatusBarHidden: Bool {
        get { UserDefaults.standard.bool(forKey: isStatusBarHiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStatusBarHiddenKey) }
    }
    
    let labelManager: SpaceLabelManager
    let hotkeyManager: HotkeyManager
    let gestureManager: GestureManager
    
    // Updated Init
    init(spaceManager: SpaceManager, hotkeyManager: HotkeyManager, gestureManager: GestureManager) {
        self.spaceManager = spaceManager
        self.labelManager = SpaceLabelManager(spaceManager: spaceManager)
        self.hotkeyManager = hotkeyManager
        self.gestureManager = gestureManager
        
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        // Initialize Menu once, set delegate for dynamic updates
        let menu = NSMenu()
        menu.delegate = self
        StatusBarController.statusItem.menu = menu
        
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
        
        updateStatusBarTitle()
        setupObservers()
    }
    
    deinit {
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupObservers() {
        spaceManager.$currentSpaceUUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaceId in
                self?.updateStatusBarTitle()
                // No need to rebuildMenu, menuNeedsUpdate handles it on click
                if let name = self?.spaceManager.getSpaceName(spaceId) {
                    self?.labelManager.updateLabel(for: spaceId, name: name)
                }
            }
            .store(in: &cancellables)
        
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
        
        labelManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Menu updates dynamically on click
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarTitle() {
        if let button = StatusBarController.statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
            button.title = name
        }
    }
    
    // MARK: - NSMenuDelegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let isOption = NSEvent.modifierFlags.contains(.option)
        
        // 1. Filter spaces to only show those on the current display
        let currentDisplaySpaces = spaceManager.currentDisplaySpaces
        
        if !currentDisplaySpaces.isEmpty {
            
            // Header for Move Mode (Only visible if Option is held initially or swapped)
            // Note: NSMenu alternates work best for 1-to-1 replacements.
            // But we can also add dynamic headers if needed.
            // For true "WiFi style", we want the ITEM itself to change.
            
            for space in currentDisplaySpaces {
                let name = spaceManager.getSpaceName(space.id)
                let moveName = "→ " + name
                
                // 1. Standard Item (Switch)
                let item = NSMenuItem(title: name, action: #selector(selectSpace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = space.id
                item.state = (space.id == spaceManager.currentSpaceUUID) ? .on : .off
                menu.addItem(item)
                
                // 2. Alternate Item (Move Window)
                let altItem = NSMenuItem(title: moveName, action: #selector(moveWindowToSpace(_:)), keyEquivalent: "")
                altItem.target = self
                altItem.representedObject = space.id
                altItem.isAlternate = true
                altItem.keyEquivalentModifierMask = .option
                altItem.state = item.state // Keep same state look? Or none? Usually none.
                menu.addItem(altItem)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Rename (Standard)
        let rename = NSMenuItem(
            title: NSLocalizedString("Menu.RenameCurrentSpace", comment: ""),
            action: nil,
            keyEquivalent: "r"
        )
        rename.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)
        
        if spaceManager.getSpaceNum(spaceManager.currentSpaceUUID) == 0 {
            rename.isEnabled = false
        } else {
            rename.isEnabled = true
            rename.target = self
            rename.action = #selector(renameCurrentSpace)
        }
        menu.addItem(rename)
        
        // 3. Move Window Header (Alternate for Rename?)
        // If we want a completely different menu structure like "WiFi -> Network Settings",
        // we might not map 1:1. But for "Switch -> Move", 1:1 mapping above is best.
        // For the "Move window to..." unclickable header user requested:
        // We can add it as an alternate to the first item or similar, but alternates replace specific items.
        // If the user wants a strict "Move window to..." header appearing at the top ONLY when Option is held,
        // we might need to stick to the previous implementation OR use a hybrid.
        // However, "WiFi settings becoming Network settings" implies 1:1 replacement.
        // The user request "Add unclickable item at top... and -> before name" suggests:
        //  - Item A (Switch Space 1)  --->  Item A' (Move to Space 1)
        //  - Item B (Switch Space 2)  --->  Item B' (Move to Space 2)
        //  - Header (None)            --->  Header (Move window to...)
        
        // To achieve "Header appears only on Option", we can use `menuNeedsUpdate` to Insert it.
        // But `menuNeedsUpdate` is only called ONCE when opening.
        // To support "Press Option while open", we MUST use `isAlternate`.
        
        // IMPLEMENTATION STRATEGY:
        // We will stick to the 1-to-1 replacement for spaces as it's the most robust "WiFi-style" behavior.
        // For the "Header", strictly speaking, NSMenu does not support "Adding a new row when Option is pressed" dynamically while open.
        // The WiFi menu changes "Wi-Fi Settings..." (bottom) to "Network Settings..." (bottom).
        // It updates text.
        // If the user *really* wants the header, we can try to add it as a disabled item that is HIDDEN by default and visible as Alt?
        // No, `isAlternate` checks if the modifier is present.
        // Let's try adding a "Hidden Placeholer" -> "Visible Header".
        
        // Header Logic:
        // Item 1: Hidden/Empty (Normal) -> "Move window to..." (Option)
        let headerPlaceholder = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerPlaceholder.isHidden = true
        menu.insertItem(headerPlaceholder, at: 0)
        
        let headerAlt = NSMenuItem(title: NSLocalizedString("Menu.MoveWindowTo", value: "Move window to...", comment: ""), action: nil, keyEquivalent: "")
        headerAlt.isEnabled = false
        headerAlt.isAlternate = true
        headerAlt.keyEquivalentModifierMask = .option
        menu.insertItem(headerAlt, at: 1) // Alt to the placeholder?
        
        // Correction: Alternates must be adjacent to the item they replace.
        // And if the original is hidden... does it work? Unlikely.
        
        // Let's stick to the 1:1 mapping for spaces which gives the immediate feedback.
        // For the header, since we reconstruct on `menuNeedsUpdate`, if the user opens with Option held, they get the header.
        // If they toggle option *while* open, only the `isAlternate` items switch.
        // This is a known macOS limitation (you can't add/remove rows while menu is open, only swap alternates).
        // So we will focus on the Space Items swapping.
        
        // ... (Remaining items)
        
        let troubleshootItem = NSMenuItem(title: NSLocalizedString("Troubleshoot Space Detection", comment: ""), action: #selector(troubleshootSpaceDetection), keyEquivalent: "")
        troubleshootItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        troubleshootItem.target = self
        menu.addItem(troubleshootItem)
        
        let showLabels = NSMenuItem(title: NSLocalizedString("Menu.ShowLabels", comment: "Toggle labels"), action: #selector(toggleLabelsFromMenu), keyEquivalent: "l")
        showLabels.target = self
        showLabels.state = labelManager.isEnabled ? .on : .off
        showLabels.image = NSImage(systemSymbolName: "appwindow.swipe.rectangle", accessibilityDescription: nil)
        self.showLabelsMenuItem = showLabels
        menu.addItem(showLabels)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: NSLocalizedString("Menu.Settings", comment: ""), action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: NSLocalizedString("Menu.Quit", comment: ""), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc func selectSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? String else { return }
        if spaceID == spaceManager.currentSpaceUUID { return }
        if let space = spaceManager.spaceNameDict.first(where: { $0.id == spaceID }) {
            spaceManager.switchToSpace(space)
        }
    }
    
    @objc func moveWindowToSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? String else { return }
        spaceManager.moveActiveWindowToSpace(id: spaceID)
    }
        
    @objc func renameCurrentSpace() {
        if spaceManager.getSpaceNum(spaceManager.currentSpaceUUID) == 0 { return }
        guard let button = StatusBarController.statusItem.button else { return }
        StatusBarController.statusItem.menu?.cancelTracking()
        let renameVC = RenameViewController(spaceManager: spaceManager) { [weak self] in
            self?.popover.performClose(nil)
            self?.updateStatusBarTitle()
        }
        popover.contentViewController = renameVC
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    @objc private func toggleLabelsFromMenu() {
        labelManager.toggleEnabled()
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
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.center()
        window.minSize = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        window.collectionBehavior = [.participatesInCycle]
        window.level = .normal
        
        // Pass gestureManager here
        let settingsVC = SettingsHostingController(
            spaceManager: spaceManager,
            labelManager: labelManager,
            hotkeyManager: hotkeyManager,
            gestureManager: gestureManager
        )
        window.contentViewController = settingsVC
        
        let windowController = NSWindowController(window: window)
        windowController.window?.delegate = self
        settingsWindowController = windowController
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsWindowWillClose), name: NSWindow.willCloseNotification, object: window)
        
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        settingsWindowController = nil
    }
    
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    
    static func toggleStatusBar() {
        StatusBarController.isStatusBarHidden.toggle()
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
    }
}

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindowController?.window {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
            settingsWindowController = nil
        }
    }
}
