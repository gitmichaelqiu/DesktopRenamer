import Foundation
import AppKit
import UserNotifications

extension NSApplication {
    // Return main window for sheet
    var suitableSheetWindow: NSWindow? {
        suitableSheetWindow(nil)
    }

    func suitableSheetWindow(_ preferred: NSWindow?) -> NSWindow? {
        if let w = preferred, w.isVisible { return w }

        return keyWindow
            ?? mainWindow
            ?? windows.first { $0.isVisible && $0.isKeyWindow }
            ?? windows.first { $0.isVisible }
            ?? windows.first
    }
}

class UpdateManager {
    static let shared = UpdateManager()
    private init() {}
    
    let latestReleaseAPI = "https://api.github.com/repos/gitmichaelqiu/DesktopRenamer/releases/latest"
    let latestReleaseURL = "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest"
    
    // UserDefaults key for auto update check
    static let autoCheckKey = "AutoCheckForUpdate"
    static var isAutoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoCheckKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }
    
    @MainActor
    func checkForUpdate(from window: NSWindow?, suppressUpToDateAlert: Bool = false) async {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        
        let url = URL(string: latestReleaseAPI.trimmingCharacters(in: .whitespacesAndNewlines))!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if !suppressUpToDateAlert {
                    await showAlert(
                        NSLocalizedString("Settings.General.Update.Failed.Title", comment: ""),
                        NSLocalizedString("Settings.General.Update.Failed.Msg", comment: ""),
                        in: window
                    )
                }
                sendCheckFailedNotification()
                return
            }
            
            let latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if isNewerVersion(latestVersion, than: currentVersion) {
                if suppressUpToDateAlert {
                    self.sendUpdateAvailableNotification(latestVersion: latestVersion, currentVersion: currentVersion)
                    return
                }
                
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Settings.General.Update.Available.Title", comment: "")
                alert.informativeText = String(format: NSLocalizedString("Settings.General.Update.Available.Msg", comment: ""), currentVersion, latestVersion)
                alert.addButton(withTitle: NSLocalizedString("Settings.General.Update.Available.Button.Update", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Settings.General.Update.Available.Button.Cancel", comment: ""))
                alert.alertStyle = .informational
                
                let response = await alert.beginSheetModal(
                    for: NSApp.suitableSheetWindow(window)!
                )
                if response == .alertFirstButtonReturn {
                    if let releaseURL = URL(string: latestReleaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        NSWorkspace.shared.open(releaseURL)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                }
            } else if !suppressUpToDateAlert {
                await showAlert(
                    NSLocalizedString("Settings.General.Update.UpToDate.Title", comment: ""),
                    String(format: NSLocalizedString("Settings.General.Update.UpToDate.Msg", comment: ""), currentVersion),
                    in: window
                )
            }
        } catch {
            if !suppressUpToDateAlert {
                await showAlert(
                    NSLocalizedString("Settings.General.Update.Failed.Title", comment: ""),
                    NSLocalizedString("Settings.General.Update.Failed.Msg", comment: ""),
                    in: window
                )
            } else {
                self.sendCheckFailedNotification()
            }
        }
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
    
    @MainActor
    private func showAlert(_ title: String, _ message: String, in window: NSWindow?) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational

        if let targetWindow = NSApp.suitableSheetWindow(window) {
            _ = await alert.beginSheetModal(for: targetWindow)
        } else {
            alert.runModal()
        }
    }
    
    private func sendNotification(title: String, body: String, actionTitle: String? = nil, actionHandlerID: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        var actions: [UNNotificationAction] = []
        var categoryID = "generic"
        
        if let actionTitle = actionTitle, let handlerID = actionHandlerID {
            let action = UNNotificationAction(
                identifier: handlerID,
                title: actionTitle,
                options: [.foreground]
            )
            actions = [action]
            categoryID = handlerID + "-category"
            let category = UNNotificationCategory(
                identifier: categoryID,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
        }
        
        content.categoryIdentifier = categoryID
        
        let request = UNNotificationRequest(
            identifier: "Notify-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().requestAuthorization { granted, _ in
            if granted {
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
    
    private func sendCheckFailedNotification() {
        let title = NSLocalizedString("Settings.General.Update.Failed.Notif.Title", comment: "")
        let body = NSLocalizedString("Settings.General.Update.Failed.Notif.Msg", comment: "")
        sendNotification(title: title, body: body)
    }
    
    private func sendUpdateAvailableNotification(latestVersion: String, currentVersion: String) {
        let title = NSLocalizedString("Settings.General.Update.Available.Notif.Title", comment: "")
        let body = String(
            format: NSLocalizedString("Settings.General.Update.Available.Notif.Msg", comment: ""),
            currentVersion, latestVersion
        )
        sendNotification(
            title: title,
            body: body,
            actionTitle: NSLocalizedString("Settings.General.Update.Available.Button.Update", comment: ""),
            actionHandlerID: "openRelease"
        )
    }
}
