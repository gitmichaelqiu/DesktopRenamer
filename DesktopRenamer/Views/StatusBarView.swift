import SwiftUI
import Combine
import AppKit

class StatusBarController: NSObject {
    @ObservedObject var spaceManager: SpaceManager
    static var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var popover: NSPopover
    var cancellables = Set<AnyCancellable>()
    var settingsWindowController: NSWindowController?
    
    var renameItem: NSMenuItem?
    var showActiveLabelsMenuItem: NSMenuItem?
    var showPreviewLabelsMenuItem: NSMenuItem?
    
    static let isStatusBarHiddenKey = "isStatusBarHidden"
    static var isStatusBarHidden: Bool {
        get { UserDefaults.standard.bool(forKey: isStatusBarHiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStatusBarHiddenKey) }
    }
    
    let labelManager: SpaceLabelManager
    let hotkeyManager: HotkeyManager
    let gestureManager: GestureManager
    
    // Initialization and configuration.
    init(spaceManager: SpaceManager, hotkeyManager: HotkeyManager, gestureManager: GestureManager) {
        self.spaceManager = spaceManager
        self.labelManager = SpaceLabelManager(spaceManager: spaceManager)
        self.hotkeyManager = hotkeyManager
        self.gestureManager = gestureManager
        
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        rebuildMenu()
        updateStatusBarTitle()
        StatusBarController.statusItem.isVisible = !StatusBarController.isStatusBarHidden
        
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
                self?.rebuildMenu()
                if let name = self?.spaceManager.getSpaceName(spaceId) {
                    self?.labelManager.updateLabel(for: spaceId, name: name)
                }
            }
            .store(in: &cancellables)
        
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
        
        labelManager.$showActiveLabels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        labelManager.$showPreviewLabels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
            
        spaceManager.$movedWindowsOriginalSpaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
            
        spaceManager.$lockedSpaceIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        labelManager.$showOnDesktop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }
}

extension StatusBarController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(moveWindowToSpace(_:)) {
            // Fullscreen source and target spaces are intentionally left enabled.
            // SpaceManager performs the safe no-op for fullscreen targets and exits
            // fullscreen before moving from a fullscreen source.
            return true
        }

        if menuItem.action == #selector(restoreAllMovedWindows) ||
           menuItem.action == #selector(cleanQueues) {
            return spaceManager.movedWindowsOriginalSpaces.count > 0
        }

        return true
    }
}

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindowController?.window {
            DispatchQueue.main.async { [weak self] in
                NSApp.setActivationPolicy(.accessory)
                self?.labelManager.endSettingsWindowPresentation()
            }
            settingsWindowController = nil
        }
    }
}
