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
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("Menu.About", comment: "")) {
                    UserDefaults.standard.set(2, forKey: "selectedSettingsTab")
                }
            }
            
            CommandGroup(replacing: .appSettings) {
                // Remove default settings
            }
        }
    }
}
