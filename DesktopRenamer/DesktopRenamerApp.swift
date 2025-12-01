import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Initialize SpaceManager and StatusBarController
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Reduced delay slightly
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
