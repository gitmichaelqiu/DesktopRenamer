import SwiftUI
import ServiceManagement
import Combine
import Cocoa

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalSelector = #selector(getter: canCollapse)
        let swizzledSelector = #selector(getter: swizzledCanCollapse)

        guard
            let originalMethod = class_getInstanceMethod(NSSplitViewItem.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledSelector)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        // If this split view item belongs to our specific Settings Window, return false
        if let window = viewController.view.window,
           window.identifier?.rawValue == "SettingsWindow" {
            return false
        }
        // Otherwise, return the original value (which is now stored in the 'swizzled' selector name due to the swap)
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        _ = swizzler
    }
}

@available(macOS 14.0, *)
extension View {
    /// Removes the sidebar toggle button from the toolbar.
    func removeSidebarToggle() -> some View {
        toolbar(removing: .sidebarToggle)
            .toolbar {
                Color.clear
            }
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager!
    
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        NSApp.setActivationPolicy(.accessory)
        
        let hasInitialized = UserDefaults.standard.bool(forKey: "HasInitializedDefaults")
        if !hasInitialized {
            try? SMAppService.mainApp.register()
            
            UserDefaults.standard.set(true, forKey: "HasInitializedDefaults")
        }
        
        // Initialize Hotkey Manager
        self.hotkeyManager = HotkeyManager()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.spaceManager = SpaceManager()
            
            // Pass hotkeyManager to StatusBarController so it can pass it to Settings
            self.statusBarController = StatusBarController(spaceManager: self.spaceManager, hotkeyManager: self.hotkeyManager)
            
            // Setup Bindings between Hotkeys and SpaceManager
            self.setupHotkeyBindings()
        }

        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
                }
            }
        }
    }
    
    private func setupHotkeyBindings() {
        // Switch Left
        hotkeyManager.switchLeftTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.spaceManager.switchToPreviousSpace()
            }
            .store(in: &cancellables)
            
        // Switch Right
        hotkeyManager.switchRightTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.spaceManager.switchToNextSpace()
            }
            .store(in: &cancellables)
            
        // Main Shortcut (Optional: if used for opening Rename or similar)
        // You can add logic here if the main shortcut is intended to perform a global action
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Notify external apps that API is going down
        spaceManager?.prepareForTermination()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.openSettingsWindow()
        return true
    }
    
    // MARK: - URL Handling (Widget Support)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "desktoprenamer",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host == "switch",
              let queryItems = components.queryItems,
              let numString = queryItems.first(where: { $0.name == "num" })?.value,
              let spaceNum = Int(numString)
        else { return }

        // Delay slightly to ensure SpaceManager is ready if app just launched
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let manager = self.spaceManager else { return }
            
            // Find space with matching number
            if let space = manager.spaceNameDict.first(where: { $0.num == spaceNum }) {
                manager.switchToSpace(space)
            }
        }
    }
}

// NOTE: StatusBarController needs to be updated to accept HotkeyManager.
// Since StatusBarController was in a separate file (StatusBarView.swift) that I'm not regenerating entirely here,
// I am including the relevant updated init in this thought process, but the user didn't ask me to edit StatusBarView.
// HOWEVER, AppDelegate creates it. If I don't update StatusBarController, the code won't compile.
// I WILL add an extension or modify StatusBarController if it was in the files provided.
// It WAS in DesktopRenamer.md (under Views/StatusBarView.swift).
// I MUST generate StatusBarView.swift updates as well to pass the dependency.

@main
struct DesktopRenamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        NSSplitViewItem.swizzle()
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
