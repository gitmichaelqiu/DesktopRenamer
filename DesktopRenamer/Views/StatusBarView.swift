import SwiftUI
import Combine
import AppKit

// View controller for the space renaming popover.
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
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "~", with: "")
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
    
    private var renameItem: NSMenuItem?
    private var showActiveLabelsMenuItem: NSMenuItem?
    private var showPreviewLabelsMenuItem: NSMenuItem?
    
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
    }
    
    private func createLockedSpaceImage(baseName: String, font: NSFont) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = baseName.size(withAttributes: attributes)
        
        let lockSize = NSSize(width: 9, height: 9)
        let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        
        let height: CGFloat = 22
        let textY = (height - textSize.height) / 2
        let textRect = NSRect(x: 0, y: textY, width: textSize.width, height: textSize.height)
        
        // Position the lock partially overlapping the text on the top right
        let lockX = textRect.maxX - 4
        let lockY = textRect.maxY - 7
        let lockRect = NSRect(x: lockX, y: lockY, width: lockSize.width, height: lockSize.height)
        
        let width = max(textSize.width, lockRect.maxX + 1)
        let imageSize = NSSize(width: width, height: height)
        
        let combinedImage = NSImage(size: imageSize, flipped: false) { rect in
            // Step 1: Draw the space name text
            baseName.draw(in: textRect, withAttributes: attributes)
            
            // Step 2: Erase a circular boundary around where the lock will be
            let erasePadding: CGFloat = 1.5
            let eraseRect = lockRect.insetBy(dx: -erasePadding, dy: -erasePadding)
            let erasePath = NSBezierPath(ovalIn: eraseRect)
            
            if let context = NSGraphicsContext.current {
                let originalOp = context.compositingOperation
                context.compositingOperation = .destinationOut
                NSColor.white.set()
                erasePath.fill()
                context.compositingOperation = originalOp
            }
            
            // Step 3: Draw the lock SF symbol on top
            if let lockImg = lockImage {
                lockImg.draw(in: lockRect, from: NSRect(origin: .zero, size: lockImg.size), operation: .sourceOver, fraction: 1.0)
            }
            
            return true
        }
        
        combinedImage.isTemplate = true
        return combinedImage
    }
    
    private func updateStatusBarTitle() {
        if let button = StatusBarController.statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
            let baseName = name.isEmpty ? " " : name
            
            if spaceManager.lockedSpaceIDs.contains(spaceManager.currentSpaceUUID) {
                let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
                let lockedImage = createLockedSpaceImage(baseName: baseName, font: font)
                button.attributedTitle = NSAttributedString(string: "")
                button.title = ""
                button.image = lockedImage
            } else {
                button.image = nil
                button.attributedTitle = NSAttributedString(string: "")
                button.title = baseName
            }
        }
    }
    
    private func lockedMenuTitle(_ base: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let attrStr = NSMutableAttributedString(string: base, attributes: [.font: font])
        let attach = NSTextAttachment()
        attach.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        let h = font.capHeight * 0.85
        attach.bounds = CGRect(x: 0, y: -font.descender * 0.5, width: h, height: h)
        attrStr.append(NSAttributedString(attachment: attach))
        return attrStr
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        
        // Display-scoped space list for the menu.
        let currentDisplaySpaces = spaceManager.currentDisplaySpaces
        
        if !currentDisplaySpaces.isEmpty {
            let item = NSMenuItem(title: NSLocalizedString("Switch to... (press ⌥ for more)", comment: ""), action: nil, keyEquivalent: "")
            menu.addItem(item)

            // Alternate menu items for window movement.
            let altItem = NSMenuItem(title: NSLocalizedString("Move window to...", comment: ""), action: nil, keyEquivalent: "")
            altItem.isAlternate = true
            altItem.keyEquivalentModifierMask = .option
            menu.addItem(altItem)

            for space in currentDisplaySpaces {
                let name = spaceManager.getSpaceName(space.id)
                let locked = spaceManager.lockedSpaceIDs.contains(space.id)
                let label = locked ? lockedMenuTitle(name) : NSAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                let moveLabel = locked ? lockedMenuTitle("\u{2192} \(name)") : NSAttributedString(string: "\u{2192} \(name)", attributes: [.font: NSFont.menuFont(ofSize: 0)])

                let item = NSMenuItem(title: "", action: #selector(selectSpace(_:)), keyEquivalent: "")
                item.attributedTitle = label
                item.target = self
                item.representedObject = space.id

                if space.id == spaceManager.currentSpaceUUID {
                    item.state = .on
                } else {
                    item.state = .off
                }

                menu.addItem(item)

                // Alternate item for window movement.
                let altItem = NSMenuItem(title: "", action: #selector(moveWindowToSpace(_:)), keyEquivalent: "")
                altItem.attributedTitle = moveLabel
                altItem.target = self
                altItem.representedObject = space.id
                altItem.isAlternate = true
                altItem.keyEquivalentModifierMask = .option
                altItem.state = item.state
                menu.addItem(altItem)
            }
            menu.addItem(NSMenuItem.separator())
        }

        let isCurrentFullscreen = spaceManager.spaceNameDict.first(where: { $0.id == spaceManager.currentSpaceUUID })?.isFullscreen ?? false

        let rename = NSMenuItem(
            title: NSLocalizedString("Menu.RenameCurrentSpace", comment: ""),
            action: nil,
            keyEquivalent: "r"
        )
        rename.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil)

        if spaceManager.getSpaceNum(spaceManager.currentSpaceUUID) == 0 || isCurrentFullscreen {
            rename.isEnabled = false
        } else {
            rename.isEnabled = true
            rename.target = self
            rename.action = #selector(renameCurrentSpace)
        }
        self.renameItem = rename
        menu.addItem(rename)
        
        let allLocked = spaceManager.spaceNameDict.allSatisfy { $0.isFullscreen || spaceManager.lockedSpaceIDs.contains($0.id) }
        let isLocked = spaceManager.lockedSpaceIDs.contains(spaceManager.currentSpaceUUID)

        let lockItem = NSMenuItem(
            title: isLocked ? NSLocalizedString("Unlock Current Space", comment: "") : NSLocalizedString("Lock Current Space", comment: ""),
            action: isCurrentFullscreen ? nil : #selector(toggleLockCurrentSpace),
            keyEquivalent: "l"
        )
        lockItem.target = self
        lockItem.state = isLocked ? .on : .off
        lockItem.image = NSImage(systemSymbolName: isLocked ? "lock" : "lock.open", accessibilityDescription: nil)
        lockItem.isEnabled = !isCurrentFullscreen
        menu.addItem(lockItem)

        let lockAllItem = NSMenuItem(
            title: allLocked ? NSLocalizedString("Unlock All", comment: "") : NSLocalizedString("Lock All", comment: ""),
            action: #selector(toggleLockAllSpaces),
            keyEquivalent: ""
        )
        lockAllItem.target = self
        lockAllItem.image = NSImage(systemSymbolName: allLocked ? "lock.open" : "lock", accessibilityDescription: nil)
        lockAllItem.isAlternate = true
        lockAllItem.keyEquivalentModifierMask = .option
        menu.addItem(lockAllItem)

        let movedCount = spaceManager.movedWindowsOriginalSpaces.count
        let restoreItem = NSMenuItem(
            title: String(format: NSLocalizedString("Restore Windows Moved by Lock (%d)", comment: ""), movedCount),
            action: #selector(restoreAllMovedWindows),
            keyEquivalent: ""
        )
        restoreItem.target = self
        restoreItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        restoreItem.isEnabled = movedCount > 0
        menu.addItem(restoreItem)

        let cleanItem = NSMenuItem(
            title: NSLocalizedString("Clean Queues", comment: ""),
            action: #selector(cleanQueues),
            keyEquivalent: ""
        )
        cleanItem.target = self
        cleanItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        cleanItem.isAlternate = true
        cleanItem.keyEquivalentModifierMask = .option
        menu.addItem(cleanItem)

        menu.addItem(NSMenuItem.separator())
    
        let showPreviewLabels = NSMenuItem(title: NSLocalizedString("Menu.ShowPreviewLabels", comment: "Toggle preview labels"), action: #selector(togglePreviewLabelsFromMenu), keyEquivalent: "p")
        showPreviewLabels.target = self
        showPreviewLabels.state = labelManager.showPreviewLabels ? .on : .off
        showPreviewLabels.image = NSImage(systemSymbolName: "appwindow.swipe.rectangle", accessibilityDescription: nil)
        self.showPreviewLabelsMenuItem = showPreviewLabels
        menu.addItem(showPreviewLabels)
        
        let showActiveLabels = NSMenuItem(title: NSLocalizedString("Menu.ShowActiveLabels", comment: "Toggle active labels"), action: #selector(toggleActiveLabelsFromMenu), keyEquivalent: "a")
        showActiveLabels.target = self
        showActiveLabels.state = labelManager.showActiveLabels ? .on : .off
        showActiveLabels.image = NSImage(systemSymbolName: "rectangle.inset.filled.and.cursorarrow", accessibilityDescription: nil)
        self.showActiveLabelsMenuItem = showActiveLabels
        menu.addItem(showActiveLabels)

        let reloadLabels = NSMenuItem(title: NSLocalizedString("Reload Space Labels", comment: "Reload Space Label Windows to fix glitches"), action: #selector(reloadLabelsFromMenu), keyEquivalent: "")
        reloadLabels.target = self
        reloadLabels.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(reloadLabels)
        
        menu.addItem(NSMenuItem.separator())
        
        let launcherItem = NSMenuItem(title: NSLocalizedString("Launcher...", comment: ""), action: #selector(openLauncher), keyEquivalent: "")
        launcherItem.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        launcherItem.target = self
        menu.addItem(launcherItem)
        
        let settingsItem = NSMenuItem(title: NSLocalizedString("Menu.Settings", comment: ""), action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: NSLocalizedString("Menu.Quit", comment: ""), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        StatusBarController.statusItem.menu = menu
    }
    
    @objc private func openLauncher() {
        LauncherWindowController.shared.show()
    }
    
    @objc func selectSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? String else { return }
        if spaceID == spaceManager.currentSpaceUUID { return }
        if let space = spaceManager.spaceNameDict.first(where: { $0.id == spaceID }) {
            spaceManager.switchToSpace(space, forceInstant: gestureManager.switchDuration <= 0)
        }
    }
    
    @objc func moveWindowToSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? String else { return }
        // Double check we are not in fullscreen
        if let current = spaceManager.spaceNameDict.first(where: { $0.id == spaceManager.currentSpaceUUID }),
           current.isFullscreen {
            return
        }
        spaceManager.moveActiveWindowToSpace(id: spaceID)
    }
    
    @objc private func toggleLockCurrentSpace() {
        spaceManager.toggleLockSpace(spaceManager.currentSpaceUUID)
        rebuildMenu()
    }

    @objc private func toggleLockAllSpaces() {
        spaceManager.toggleLockAllSpaces()
        rebuildMenu()
    }

    @objc private func restoreAllMovedWindows() {
        spaceManager.restoreAllMovedWindows()
    }

    @objc private func cleanQueues() {
        spaceManager.cleanMovedWindows()
        rebuildMenu()
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
    
    @objc private func toggleActiveLabelsFromMenu() {
        labelManager.toggleActiveLabels()
        rebuildMenu()
    }

    @objc private func togglePreviewLabelsFromMenu() {
        labelManager.togglePreviewLabels()
        rebuildMenu()
    }

    @objc private func reloadLabelsFromMenu() {
        labelManager.reloadAllWindows()
    }
        
    @objc func openSettingsWindow() {
        openSettingsWindow(tab: .general)
    }

    func openSettingsWindow(tab: SettingsTab? = nil) {
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
        
        // Initialize host controller with required managers and optional tab.
        let settingsVC = SettingsHostingController(
            spaceManager: spaceManager,
            labelManager: labelManager,
            hotkeyManager: hotkeyManager,
            gestureManager: gestureManager,
            initialTab: tab
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

extension StatusBarController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(moveWindowToSpace(_:)) {
            // Check if current space is fullscreen
            if let current = spaceManager.spaceNameDict.first(where: { $0.id == spaceManager.currentSpaceUUID }),
               current.isFullscreen {
                return false
            }
            
            guard let spaceID = menuItem.representedObject as? String else { return true }
            if let space = spaceManager.spaceNameDict.first(where: { $0.id == spaceID }) {
                return !space.isFullscreen
            }
        }
        return true
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
