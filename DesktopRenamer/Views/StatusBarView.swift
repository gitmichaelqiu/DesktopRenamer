import SwiftUI
import Combine
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    @ObservedObject private var spaceManager: DesktopSpaceManager
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
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
        let renameItem = NSMenuItem(title: "Rename Current Space", action: #selector(renameCurrentSpace), keyEquivalent: "r")
        renameItem.target = self
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add refresh option
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshSpaces), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
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
        let alert = NSAlert()
        alert.messageText = "Rename Space"
        alert.informativeText = "Enter a new name for Desktop \(spaceManager.currentSpaceId):"
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceId)
        alert.accessoryView = input
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        NSApp.activate(ignoringOtherApps: true)
        input.becomeFirstResponder()
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue
            spaceManager.renameSpace(spaceManager.currentSpaceId, to: newName)
            updateStatusBarTitle()  // Force update the title
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
} 
