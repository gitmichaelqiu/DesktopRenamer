import SwiftUI
import Combine
import AppKit

class StatusBarController: NSObject {
    @ObservedObject var spaceManager: SpaceManager
    static var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var popover: NSPopover
    var cancellables = Set<AnyCancellable>()
    var settingsWindowController: NSWindowController?
    private var isPresentingSpaceAPIAccessRequest = false
    
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
        observeSpaceAPIAccessRequests()
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

    private func observeSpaceAPIAccessRequests() {
        guard let accessController = spaceManager.spaceAPI?.accessController else { return }
        accessController.accessRequestDidArrive = { [weak self] in
            Task { @MainActor [weak self] in
                self?.presentSpaceAPIAccessRequest()
            }
        }
        if accessController.pendingApprovalRequest != nil {
            presentSpaceAPIAccessRequest()
        }
    }

    @MainActor
    private func presentSpaceAPIAccessRequest() {
        guard !isPresentingSpaceAPIAccessRequest else { return }
        guard let accessController = spaceManager.spaceAPI?.accessController,
              let requestingApplication = accessController.pendingApprovalRequest else { return }
        isPresentingSpaceAPIAccessRequest = true
        defer { isPresentingSpaceAPIAccessRequest = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(
            format: NSLocalizedString("%@ would like to use SpaceAPI.", comment: ""),
            requestingApplication.name
        )
        alert.informativeText = NSLocalizedString("Choose the access level to grant.", comment: "")
        alert.icon = spaceAPIAccessRequestIcon(for: requestingApplication.applicationPath)
        alert.addButton(withTitle: NSLocalizedString("Read Only", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Read & Write", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Don't Allow", comment: ""))
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let accessLevel: SpaceAPIClientAccessLevel?
        switch response {
        case .alertFirstButtonReturn:
            accessLevel = .readOnly
        case .alertSecondButtonReturn:
            accessLevel = .fullAccess
        case .alertThirdButtonReturn:
            accessLevel = .noAccess
        default:
            accessLevel = nil
        }
        accessController.resolvePendingApproval(with: accessLevel)
    }

    private func spaceAPIAccessRequestIcon(for applicationPath: String) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let icon = NSWorkspace.shared.icon(forFile: applicationPath)
        let image = NSImage(size: size)
        image.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)

        if let desktopRenamerIcon = NSApp.applicationIconImage {
            let badgeSize: CGFloat = 24
            let badgeFrame = NSRect(x: size.width - badgeSize - 1, y: 1, width: badgeSize, height: badgeSize)
            let badgeBackground = NSBezierPath(ovalIn: badgeFrame.insetBy(dx: -2, dy: -2))
            NSColor.windowBackgroundColor.setFill()
            badgeBackground.fill()
            NSColor.separatorColor.setStroke()
            badgeBackground.lineWidth = 0.75
            badgeBackground.stroke()
            desktopRenamerIcon.draw(
                in: badgeFrame.insetBy(dx: 4, dy: 4),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        image.unlockFocus()
        return image
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
    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow == settingsWindowController?.window else { return }
        labelManager.completeSettingsWindowActivation()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindowController?.window {
            DispatchQueue.main.async { [weak self] in
                self?.labelManager.endSettingsWindowPresentation()
                self?.spaceManager.resumeDeferredScreenParameterRefreshIfNeeded()
            }
            settingsWindowController = nil
        }
    }
}
