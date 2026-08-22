import SwiftUI
import Combine
import AppKit

extension StatusBarController {

    func createLockedSpaceImage(baseName: String, font: NSFont) -> NSImage {
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
    
    func updateStatusBarTitle() {
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
    
    func lockedMenuTitle(_ base: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let attrStr = NSMutableAttributedString(string: base, attributes: [.font: font])
        let attach = NSTextAttachment()
        attach.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        let h = font.capHeight * 0.85
        attach.bounds = CGRect(x: 0, y: -font.descender * 0.5, width: h, height: h)
        attrStr.append(NSAttributedString(attachment: attach))
        return attrStr
    }

    func rebuildMenu() {
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
            keyEquivalent: "l"
        )
        lockAllItem.target = self
        lockAllItem.image = NSImage(systemSymbolName: allLocked ? "lock.open" : "lock", accessibilityDescription: nil)
        lockAllItem.isAlternate = true
        lockAllItem.keyEquivalentModifierMask = [.command, .option]
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
            title: String(format: NSLocalizedString("Clean Restoration Queues (%d)", comment: ""), movedCount),
            action: #selector(cleanQueues),
            keyEquivalent: ""
        )
        cleanItem.target = self
        cleanItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        cleanItem.isAlternate = true
        cleanItem.keyEquivalentModifierMask = .option
        cleanItem.isEnabled = movedCount > 0
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

        if labelManager.showActiveLabels {
            let showOnDesktop = NSMenuItem(
                title: NSLocalizedString("Show on Desktop", comment: ""),
                action: #selector(toggleShowOnDesktop),
                keyEquivalent: "d"
            )
            showOnDesktop.target = self
            showOnDesktop.state = labelManager.showOnDesktop ? .on : .off
            showOnDesktop.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
            menu.addItem(showOnDesktop)
        }

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

    @objc private func toggleShowOnDesktop() {
        labelManager.toggleShowOnDesktop()
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
        // Don't nil the toolbar — NavigationSplitView on macOS 14+ creates its
        // own internal toolbar, and SwiftUI's toolbar(removing: .sidebarToggle)
        // modifier needs it to exist in order to suppress the toggle.
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
