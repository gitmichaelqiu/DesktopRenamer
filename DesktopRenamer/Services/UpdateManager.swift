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

    // Do not show alert if already up to date for auto-check)
    func checkForUpdate(from window: NSWindow?, suppressUpToDateAlert: Bool = false) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let url = URL(string: latestReleaseURL)!
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if !suppressUpToDateAlert {
                    self.showAlert("Update Check Failed", "Could not check for updates.", window: window)
                }
                return
            }
            let latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if self.isNewerVersion(latestVersion, than: currentVersion) {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "Version \(latestVersion) is available. Open the releases page to download and install?"
                    alert.addButton(withTitle: "Update")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .informational
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let releasesURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest") {
                            NSWorkspace.shared.open(releasesURL)
                        }
                    }
                }
            } else if !suppressUpToDateAlert {
                self.showAlert("Up To Date", "You are running the latest version (\(currentVersion)).", window: window)
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
