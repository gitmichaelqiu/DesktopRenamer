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
                        NSLocalizedString("update.check_failed_title", comment: ""),
                        NSLocalizedString("update.check_failed_message", comment: ""),
                        window: window
                    )
                }
                return
            }
            let latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if self.isNewerVersion(latestVersion, than: currentVersion) {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("update.available_title", comment: "")
                    alert.informativeText = String(format: NSLocalizedString("update.available_message", comment: ""), latestVersion)
                    alert.addButton(withTitle: NSLocalizedString("update.available_button_update", comment: ""))
                    alert.addButton(withTitle: NSLocalizedString("update.available_button_cancel", comment: ""))
                    alert.alertStyle = .informational
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let releasesURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest") {
                            NSWorkspace.shared.open(releasesURL)
                        }
                    }
                }
            } else if !suppressUpToDateAlert {
                self.showAlert(
                    NSLocalizedString("update.up_to_date_title", comment: ""),
                    String(format: NSLocalizedString("update.up_to_date_message", comment: ""), currentVersion),
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
