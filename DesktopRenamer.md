# DesktopRenamer

.
├── DesktopRenamerApp.swift
├── Models
│   ├── SettingsComponents.swift
│   └── DesktopSpace.swift
├── Views
│   ├── StatusBarView.swift
│   ├── SpaceLabelWindow.swift
│   ├── SettingsViewController.swift
│   └── SettingsView
│       ├── AboutView.swift
│       ├── SpaceEditView.swift
│       └── GeneralSettingsView.swift
└── Services
    ├── SpaceLabelManager.swift
    ├── UpdateManager.swift
    ├── SpaceManager.swift
    └── SpaceHelper.swift

---

## DesktopRenamerApp.swift

```swift
//
//  DesktopRenamerApp.swift
//  DesktopRenamer
//
//  Created by Michael Qiu on 2025/7/20.
//

import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize SpaceManager and StatusBarController
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.spaceManager = SpaceManager()
            self.statusBarController = StatusBarController(spaceManager: self.spaceManager)
        }

        // Automatically check for updates on launch if enabled
        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
            }
        }
    }
}

@main
struct DesktopRenamerApp: App {
    // Attach the AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
    }
}

```

## Models/SettingsComponents.swift

```swift
// Supporting components (in case they're not already defined elsewhere)

import SwiftUI
struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            content
                .frame(alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
            )
        }
    }

    private var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
}

```

## Models/DesktopSpace.swift

```swift
import Foundation

struct DesktopSpace: Identifiable, Codable {
    var id: String
    var customName: String
    var num: Int
}

```

## Views/StatusBarView.swift

```swift
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
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    @ObservedObject private var spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?
    private var renameItem: NSMenuItem!
    private var showLabelsMenuItem: NSMenuItem!
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.labelManager = SpaceLabelManager(spaceManager: spaceManager)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        
        super.init()
        
        setupMenuBar()
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
                // 只有当当前空间的名称改变时才更新
                if let currentSpaceUUID = self?.spaceManager.currentSpaceUUID,
                   let newName = self?.spaceManager.getSpaceName(currentSpaceUUID),
                   let button = self?.statusItem.button,
                   button.title != newName {
                    self?.updateStatusBarTitle()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarTitle() {
        if let button = statusItem.button {
            let name = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
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
        self.renameItem = NSMenuItem(
            title: NSLocalizedString("Menu.RenameCurrentSpace", comment: ""),
            action: nil, // Temporarily
            keyEquivalent: "r"
        )
        
        menu.addItem(self.renameItem)
        
        // Add show labels option
        self.showLabelsMenuItem = NSMenuItem(
            title: NSLocalizedString("Menu.ShowLabels", comment: "Toggle desktop labels visibility"),
            action: #selector(toggleLabelsFromMenu),
            keyEquivalent: "l"
        )
        self.showLabelsMenuItem.target = self
        self.showLabelsMenuItem.state = labelManager.isEnabled ? .on : .off
        menu.addItem(self.showLabelsMenuItem)
        
        // Add a separator
        menu.addItem(NSMenuItem.separator())
        
        // Add settings option
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Menu.Settings", comment: ""),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add quit option
        let quitItem = NSMenuItem(
            title: NSLocalizedString("Menu.Quit", comment: ""),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
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
    
    @objc private func toggleLabelsFromMenu() {
        labelManager.toggleEnabled()
        
        self.showLabelsMenuItem.state = labelManager.isEnabled ? .on : .off
    }
    
    @objc private func showSettings() {
        // Show dock icon when opening settings
        NSApp.setActivationPolicy(.regular)
        
        if let windowController = settingsWindowController {
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Window.SettingsTitle", comment: "")
        window.center()
        
        // Create and set the settings view controller
        let settingsVC = SettingsHostingController(spaceManager: spaceManager, labelManager: labelManager)
        window.contentViewController = settingsVC
        
        // Create window controller
        let windowController = NSWindowController(window: window)
        windowController.window?.delegate = self
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
            // Hide dock icon when closing settings
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
            settingsWindowController = nil
        }
    }
}

```

## Views/SpaceLabelWindow.swift

```swift
import Cocoa
import Combine

class SpaceLabelWindow: NSWindow {
    private let label: NSTextField
    public let spaceId: String
    private var cancellables = Set<AnyCancellable>()
    private let spaceManager: SpaceManager
    
    private let frameWidth: CGFloat = 400
    private let frameHeight: CGFloat = 200
    
    init(spaceId: String, name: String, spaceManager: SpaceManager) {
        self.spaceId = spaceId
        self.spaceManager = spaceManager
        
        // Create the label
        label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 50, weight: .medium) // Initial font size, will be adjusted
        label.textColor = .labelColor
        label.alignment = .center
        
        // Create a glass effect view for the background
        let contentView: NSView
        if #available(macOS 26.0, *) {
            let glassEffectView = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
            contentView = glassEffectView
        } else {
            // Fallback on earlier versions
            let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
            contentView = visualEffectView
        }
        
        // Calculate and set optimal font size and frame
        let padding: CGFloat = 20
        let maxWidth = frameWidth - (padding * 2)
        let maxHeight = frameHeight - (padding * 2)
        
        // Start with initial font size and adjust down if needed
        var fontSize: CGFloat = 50
        var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
        var stringSize = attributedString.size()
        
        while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            stringSize = attributedString.size()
        }
        
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        
        // Center the label in the glass effect view
        let labelFrame = NSRect(
            x: (frameWidth - stringSize.width) / 2,
            y: (frameHeight - stringSize.height) / 2,
            width: stringSize.width,
            height: stringSize.height
        )
        label.frame = labelFrame
        
        // Add label to glass effect view
        contentView.addSubview(label)
        
        // Initialize window with panel behavior
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true  // Changed to true to prevent automatic display
        )
        
        self.contentView = contentView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 6
        self.contentView?.addSubview(label)
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        
        // Set window to be managed by Mission Control but stay in current space
        self.collectionBehavior = [
            .managed,
            .stationary,
            .participatesInCycle,  // Changed to ensure proper space management
            .fullScreenAuxiliary   // Ensures proper behavior in full screen
        ]
        
        // Make window completely invisible to mouse events
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false
        
        // Position the window at the top center of the screen
        if let screen = NSScreen.main {
            let centerX = screen.frame.midX - (103 / 2)
            let y = 1.5 * screen.frame.maxY
            self.setFrameOrigin(NSPoint(x: centerX, y: y))
        }
        
        // Additional properties to make window more invisible
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Observe space name changes
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    func updateName(_ name: String) {
        DispatchQueue.main.async {
            // Calculate optimal font size for new name
            let padding: CGFloat = 20
            let maxWidth = (self.frameWidth) - (padding * 2)
            let maxHeight = (self.frameHeight) - (padding * 2)
            
            var fontSize: CGFloat = 50
            var attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
            var stringSize = attributedString.size()
            
            while (stringSize.width > maxWidth || stringSize.height > maxHeight) && fontSize > 10 {
                fontSize -= 2
                attributedString = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
                stringSize = attributedString.size()
            }
            
            self.label.font = .systemFont(ofSize: fontSize, weight: .medium)
            self.label.stringValue = name
            
            // Recenter the label
            if self.contentView != nil {
                let labelFrame = NSRect(
                    x: (self.frameWidth - stringSize.width) / 2,
                    y: (self.frameHeight - stringSize.height) / 2,
                    width: stringSize.width,
                    height: stringSize.height
                )
                self.label.frame = labelFrame
            }
        }
    }
    
    var currentName: String {
        return label.stringValue
    }
}

```

## Views/SettingsViewController.swift

```swift
import SwiftUI
import ServiceManagement
import Combine

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(NSLocalizedString("Settings.Tab.General", comment: ""))
                }
                .tag(0)
            
            SpaceEditView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "macwindow.stack")
                    Text(NSLocalizedString("Settings.Tab.Space", comment: ""))
                }
                .tag(1)
            
            AboutView()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text(NSLocalizedString("Settings.Tab.About", comment: ""))
                }
                .tag(2)
        }
        .frame(width: 600, height: 400)
        .padding()
    }
}

// MARK: - SwiftUI Hosting Controller
class SettingsHostingController: NSHostingController<SettingsView> {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        super.init(rootView: SettingsView(spaceManager: spaceManager, labelManager: labelManager))
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSSize(width: 600, height: 400)
    }
}

```

## Views/SettingsView/AboutView.swift

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            // App icon
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .cornerRadius(10)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
            
            // App name
            Text(NSLocalizedString("About.AppName", comment: ""))
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
            
            // Version
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("v\(version)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            // Description
            Text(NSLocalizedString("About.Description", comment: ""))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // GitHub link
            Button(action: openGitHub) {
                Text(NSLocalizedString("About.GithubLink", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Copyright
            let year = Calendar.current.component(.year, from: Date())
            let copyrightString = String(format: NSLocalizedString("About.Copyright", comment: ""), year)
            Text(copyrightString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func openGitHub() {
        if let url = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer") {
            NSWorkspace.shared.open(url)
        }
    }
}

```

## Views/SettingsView/SpaceEditView.swift

```swift
import SwiftUI

// MARK: - Space Edit View
struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var desktopSpaces: [DesktopSpace] = []
    
    var body: some View {
        VStack {
            if desktopSpaces.isEmpty {
                Text("No spaces available")
                    .foregroundColor(.secondary)
            } else {
                Table(desktopSpaces) {
                    TableColumn("#") { space in
                        Text(spaceManager.currentSpaceUUID == space.id ? "[\(space.num)]" : "\(space.num)")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .width(30)
                    
                    TableColumn(NSLocalizedString("Settings.Space.CustomName", comment: "")) { space in
                        TextField(
                            String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num),
                            text: Binding(
                                get: { space.customName },
                                set: { newValue in
                                    updateSpaceName(space, newValue)
                                }
                            )
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .width(240)
                    
                    TableColumn(NSLocalizedString("Settings.Space.Actions", comment: "")) { space in
                        HStack(spacing: 4) {
                            Button("↑") {
                                moveRowUp(space)
                            }
                            .disabled(isFirstRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("↓") {
                                moveRowDown(space)
                            }
                            .disabled(isLastRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("⌫") {
                                deleteRow(space)
                            }
                            .disabled(space.id == spaceManager.currentSpaceUUID)
                            .help(space.id == spaceManager.currentSpaceUUID ?
                                  NSLocalizedString("settings.space.cannot_delete_current", comment: "Cannot delete current space") : "")
                        }
                        .buttonStyle(.bordered)
                    }
                    .width(85)
                }
                .tableStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            refreshData()
        }
        .onReceive(spaceManager.$spaceNameDict) { _ in
            refreshData()
        }
        .onReceive(spaceManager.$currentSpaceUUID) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
    }
    
    private func isFirstRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == 0
    }
    
    private func isLastRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == desktopSpaces.count - 1
    }
    
    private func moveRowUp(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index > 0 else { return }
        
        desktopSpaces.swapAt(index, index - 1)
        updateNumbersAndSave()
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index < desktopSpaces.count - 1 else { return }
        
        desktopSpaces.swapAt(index, index + 1)
        updateNumbersAndSave()
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              space.id != spaceManager.currentSpaceUUID else { return }
        
        desktopSpaces.remove(at: index)
        updateNumbersAndSave()
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return }
        
        var updatedSpace = desktopSpaces[index]
        updatedSpace.customName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        desktopSpaces[index] = updatedSpace
        
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.saveSpaces()
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
    }
}

```

## Views/SettingsView/GeneralSettingsView.swift

```swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var launchAtLogin: Bool = false
    @State private var showLabels: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General.General") {
                    SettingsRow("Settings.LaunchAtLogin") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in
                                toggleLaunchAtLogin(value)
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.ShowLabels") {
                        Toggle("", isOn: $showLabels)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showLabels) { value in
                                labelManager.isEnabled = value
                            }
                    }
                }
                
                SettingsSection("Settings.General.Updates") {
                    SettingsRow("Settings.AutoCheckUpdate") {
                        Toggle("", isOn: $autoCheckUpdate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.isAutoCheckEnabled = value
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.Update.ManualCheck") {
                        Button(NSLocalizedString("Settings.CheckUpdateButton", comment: "")) {
                            checkForUpdate()
                        }
                    }
                }
                
                SettingsSection("Settings.General.Reset") {
                    SettingsRow("Settings.ResetButton") {
                        Button(NSLocalizedString("Settings.ResetButton", comment: "")) {
                            resetNames()
                        }
                        .disabled(isResetting)
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLogin = getLaunchAtLoginState()
            showLabels = labelManager.isEnabled
        }
    }
    
    private func getLaunchAtLoginState() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            return SMLoginItemSetEnabled(bundleId as CFString, true)
        }
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
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
                launchAtLogin = getLaunchAtLoginState()
                
                // Show error alert
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Settings.LaunchAtLogin.Error", comment: "Failed to toggle launch at login")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("Common.OK", comment: "OK"))
                alert.runModal()
            }
        } else {
            if let bundleId = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleId as CFString, enabled)
                if !success {
                    launchAtLogin = getLaunchAtLoginState()
                    
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Settings.LaunchAtLogin.Error", comment: "Failed to toggle launch at login")
                    alert.informativeText = NSLocalizedString("Settings.LaunchAtLogin.ErrorLegacy", comment: "Could not update login items")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("Common.OK", comment: "OK"))
                    alert.runModal()
                }
            }
        }
    }
    
    private func checkForUpdate() {
        UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: false)
    }
    
    private func resetNames() {
        isResetting = true
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.ResetAlertMsg", comment: "")
        alert.informativeText = NSLocalizedString("Settings.ResetAlertInfo", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Settings.ResetAlertButtonReset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Settings.ResetAlertButtonCancel", comment: ""))
        
        guard let window = NSApp.keyWindow else {
            isResetting = false
            return
        }
        
        alert.beginSheetModal(for: window) { response in
            DispatchQueue.main.async {
                self.isResetting = false
                
                if response == .alertFirstButtonReturn {
                    self.spaceManager.resetAllNames()
                    
                    // Show success feedback
                    let successAlert = NSAlert()
                    successAlert.messageText = NSLocalizedString("Settings.ResetSuccess", comment: "Reset successful")
                    successAlert.informativeText = NSLocalizedString("Settings.ResetSuccessInfo", comment: "All space names have been reset to their default values")
                    successAlert.alertStyle = .informational
                    successAlert.addButton(withTitle: NSLocalizedString("Common.OK", comment: "OK"))
                    successAlert.runModal()
                }
            }
        }
    }
}

```

## Services/SpaceLabelManager.swift

```swift
import Foundation
import AppKit

class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.gitmichaelqiu.desktoprenamer.slw"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
        }
    }
    
    private var currentWindow: SpaceLabelWindow?
    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
    }
    
    deinit {
        removeAllWindows()
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        
        if isEnabled {
            let spaceId = self.spaceManager?.currentSpaceUUID
            let name = self.spaceManager?.getSpaceName(spaceId ?? "")
            self.updateLabel(for: spaceId ?? "", name: name ?? "")
        }
    }
    
    func updateLabel(for spaceId: String, name: String) {
        guard isEnabled, spaceId != "FULLSCREEN" else { return }
        if createdWindows[spaceId] != nil { return }
        
        // Double check before creating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Get UUID again
            SpaceHelper.getSpaceUUID { confirmedSpaceId in
                // Create window only if two are identical
                if confirmedSpaceId == spaceId {
                    // Make sure not creating a duplicated window
                    if self.createdWindows[spaceId] == nil {
                        self.createWindow(for: spaceId, name: name)
                    }
                }
            }
        }
    }
    
    private func createWindow(for spaceId: String, name: String) {
        guard let spaceManager = spaceManager else { return }
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, spaceManager: spaceManager)
        createdWindows[spaceId] = window
        window.orderFront(nil)
    }
    
    private func removeAllWindows() {
        for (_, window) in createdWindows {
            window.orderOut(nil)
        }
        createdWindows.removeAll()
    }
    
    private func updateLabelsVisibility() {
        if !isEnabled {
            removeAllWindows()
        }
    }
}

```

## Services/UpdateManager.swift

```swift
import Foundation
import AppKit

class UpdateManager {
    static let shared = UpdateManager()
    private init() {}

    private let repo = "gitmichaelqiu/DesktopRenamer"
    private let latestReleaseURL = "https://api.github.com/repos/gitmichaelqiu/DesktopRenamer/releases/latest"

    // UserDefaults key for auto update check
    static let autoCheckKey = "AutoCheckForUpdate"
    static var isAutoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoCheckKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    func checkForUpdate(from window: NSWindow?, suppressUpToDateAlert: Bool = false) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let url = URL(string: latestReleaseURL)!
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if !suppressUpToDateAlert {
                    self.showAlert(
                        NSLocalizedString("Update.CheckFailedTitle", comment: ""),
                        NSLocalizedString("Update.CheckFailedMsg", comment: ""),
                        window: window
                    )
                }
                return
            }
            let latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if self.isNewerVersion(latestVersion, than: currentVersion) {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Update.AvailableTitle", comment: "")
                    alert.informativeText = String(format: NSLocalizedString("Update.AvailableMsg", comment: ""), latestVersion)
                    alert.addButton(withTitle: NSLocalizedString("Update.AvailableButtonUpdate", comment: ""))
                    alert.addButton(withTitle: NSLocalizedString("Update.AvailableButtonCancel", comment: ""))
                    alert.alertStyle = .informational
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let releasesURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest") {
                            NSWorkspace.shared.open(releasesURL)
                        }
                    }
                }
            } else if !suppressUpToDateAlert {
                self.showAlert(
                    NSLocalizedString("Update.UpToDateTitle", comment: ""),
                    String(format: NSLocalizedString("Update.UpToDateMsg", comment: ""), currentVersion),
                    window: window
                )
            }
        }
        task.resume()
    }

    private func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        for (l, c) in zip(latestParts, currentParts) {
            if l > c { return true }
            if l < c { return false }
        }
        return latestParts.count > currentParts.count
    }

    private func showAlert(_ title: String, _ message: String, window: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            if let window = window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}

```

## Services/SpaceManager.swift

```swift
import Foundation
import AppKit

class SpaceManager: ObservableObject {
    @Published private(set) var currentSpaceUUID: String = ""
    @Published var spaceNameDict: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "com.gitmichaelqiu.desktoprenamer.spaces"
    
    public var currentTotalSpace = 0
    
    init() {
        loadSavedSpaces()
        
        // Start monitoring
        SpaceHelper.startMonitoring { [weak self] newSpaceUUID in
            self?.handleSpaceChange(newSpaceUUID)
        }
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
    }
    
    private func handleSpaceChange(_ newSpaceUUID: String) {
        // Handle on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleSpaceChange(newSpaceUUID)
            }
            return
        }
        
        currentSpaceUUID = newSpaceUUID
        
        // Check if the space was handled before
        if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
            currentTotalSpace += 1
            spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
            saveSpaces()
        }
        
        objectWillChange.send()
    }
    
    private func loadSavedSpaces() {
        if let data = userDefaults.data(forKey: spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
            currentTotalSpace = spaceNameDict.count
        }
    }
    
    public func saveSpaces() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            userDefaults.set(data, forKey: spacesKey)
            userDefaults.synchronize()
        }
    }
    
    private func isValidUUID(_ spaceUUID: String) -> Bool {
        if spaceUUID == "FULLSCREEN" {
            return true
        }
        
        // Check if the space is removed
        if spaceNameDict.contains(where: { $0.id == spaceUUID }) { // Still exist
            return true
        }
        
        // Remove space
        spaceNameDict.removeAll(where: {$0.id == spaceUUID})
        return false
    }
    
    func getSpaceNum(_ spaceUUID: String) -> Int {
        guard isValidUUID(spaceUUID) else { return -1 }
        if spaceUUID == "FULLSCREEN" {
            return 0
        }
        return spaceNameDict.first(where: { $0.id == spaceUUID })?.num ?? -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        guard isValidUUID(spaceUUID) else { return "" }
        
        if spaceUUID == "FULLSCREEN" {
            return "Fullscreen"
        }
        
        var ret = spaceNameDict.first(where: {$0.id == spaceUUID})?.customName
        if ret == "" {
            ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
        }
        
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Clear userDefaults
            userDefaults.removeObject(forKey: spacesKey)
            
            // Clear all custom names
            currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            
            // Force refresh current space
            SpaceHelper.getSpaceUUID { spaceUUID in
                self.currentSpaceUUID = spaceUUID
                self.handleSpaceChange(spaceUUID)
            }
            
            // Notify observers
            self.objectWillChange.send()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        guard isValidUUID(spaceUUID) else { return }
        
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = newName
            saveSpaces()
        } else {
            print("Debug: Services/SM renameSpace failed")
        }
        
        objectWillChange.send()
    }
}

```

## Services/SpaceHelper.swift

```swift
import Foundation
import AppKit

class SpaceHelper {
    private static var onSpaceChange: ((String) -> Void)?
    
    static func startMonitoring(onChange: @escaping (String) -> Void) {
        onSpaceChange = onChange
        
        // Monitor space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // Initial detection
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    static func getSpaceUUID(completion: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { // Wait the system to update
            // Get all windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            var uuid = ""
            var inFullscreen = true
            
            // Look for the wallpaper window
            for window in windowList {
                if let owner = window[kCGWindowOwnerName as String] as? String,
                        owner == "Notification Center" {
                    inFullscreen = false
                } else if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Dock",
                   let name = window[kCGWindowName as String] as? String,
                   name.starts(with: "Wallpaper-"),
                   let layer = window[kCGWindowLayer as String] as? Int32,
                   layer == -2147483624 { // This is the wallpaper layer
                    
                    // Extract UUID from wallpaper name
                    uuid = String(name.dropFirst("Wallpaper-".count))

                    if uuid == "" {
                        uuid = "MAIN"
                    }
                }
                
//                if let owner = window[kCGWindowOwnerName as String] as? String {
//                    print(owner)
//                }
            }
            
            if inFullscreen {
                uuid = "FULLSCREEN"
            }
            
            // Return
            completion(uuid)
        }
    }
    
    private static func detectSpaceChange() {
        getSpaceUUID {
            spaceUUID in onSpaceChange?(spaceUUID)
        }
    }
}


```
