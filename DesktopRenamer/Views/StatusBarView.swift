import SwiftUI
import Combine
import AppKit

class RenameViewController: NSViewController {
    private var spaceManager: DesktopSpaceManager
    private var completion: () -> Void
    private var textField: NSTextField!
    
    init(spaceManager: DesktopSpaceManager, completion: @escaping () -> Void) {
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
        textField.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceId)
        textField.placeholderString = "Enter space name"
        textField.delegate = self
        view.addSubview(textField)
        
        // Create the label
        let label = NSTextField(labelWithString: "Rename Desktop \(spaceManager.currentSpaceId)")
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
            spaceManager.renameSpace(spaceManager.currentSpaceId, to: newName)
        }
        dismiss(nil)
        completion()
    }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    @ObservedObject private var spaceManager: DesktopSpaceManager
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?  // Changed to window controller
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        setupMenuBar()
        
        // Initial update
        updateStatusBarTitle()
        
        // Subscribe to changes
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe current space ID changes
        spaceManager.$currentSpaceId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
        
        // Observe desktop spaces array changes
        spaceManager.$desktopSpaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarTitle() {
        if let button = statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceId)
            button.title = name
        }
    }
    
    private func setupMenuBar() {
        if let button = statusItem.button {
            button.title = "Loading..."  // Initial state
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Add rename option for current space
        let renameItem = NSMenuItem(title: "Rename Current Space", action: #selector(renameCurrentSpace), keyEquivalent: "e")
        renameItem.target = self
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add refresh option
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshSpaces), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add settings option
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add quit option
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func refreshSpaces() {
        spaceManager.refreshCurrentSpace()
    }
    
    @objc private func renameCurrentSpace() {
        guard let button = statusItem.button else { return }
        
        // Close the menu
        statusItem.menu?.cancelTracking()
        
        // Configure the popover
        let renameVC = RenameViewController(spaceManager: spaceManager) { [weak self] in
            self?.popover.performClose(nil)
            self?.updateStatusBarTitle()
        }
        popover.contentViewController = renameVC
        
        // Show the popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    @objc private func showSettings() {
        if let windowController = settingsWindowController {
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desktop Renamer Settings"
        window.center()
        
        // Create and set the settings view controller
        let settingsVC = SettingsViewController(spaceManager: spaceManager)
        window.contentViewController = settingsVC
        
        // Create window controller
        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        
        // Show the window
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindowController?.window {
            settingsWindowController = nil
        }
    }
} 
