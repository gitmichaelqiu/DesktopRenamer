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
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        NSApp.setActivationPolicy(.accessory)
        
        let hasInitialized = UserDefaults.standard.bool(forKey: "HasInitializedDefaults")
        if !hasInitialized {
            try? SMAppService.mainApp.register()
            
            UserDefaults.standard.set(true, forKey: "HasInitializedDefaults")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.spaceManager = SpaceManager()
            self.statusBarController = StatusBarController(spaceManager: self.spaceManager)
        }

        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Notify external apps that API is going down
        spaceManager?.prepareForTermination()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.openSettingsWindow()
        return true
    }
}

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
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("Menu.About", comment: "")) {
                    UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
                }
            }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
