import Foundation
import AppKit

class UpdateManager {
    static let shared = UpdateManager()
    private init() {}

    private let repo = "gitmichaelqiu/DesktopRenamer"
    private let latestReleaseURL = "https://api.github.com/repos/gitmichaelqiu/DesktopRenamer/releases/latest"

    func checkForUpdate(from window: NSWindow?) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let url = URL(string: latestReleaseURL)!
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                self.showAlert("Update Check Failed", "Could not check for updates.", window: window)
                return
            }
            let latestVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if self.isNewerVersion(latestVersion, than: currentVersion) {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "Version \(latestVersion) is available. Download and install now?"
                    alert.addButton(withTitle: "Update")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .informational
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let assets = json["assets"] as? [[String: Any]],
                           let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                           let dmgURL = dmgAsset["browser_download_url"] as? String {
                            self.downloadAndInstallDMG(from: dmgURL, window: window)
                        } else {
                            self.showAlert("No DMG Found", "Could not find a DMG asset in the latest release.", window: window)
                        }
                    }
                }
            } else {
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

    private func downloadAndInstallDMG(from urlString: String, window: NSWindow?) {
        guard let url = URL(string: urlString) else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let dmgPath = tempDir.appendingPathComponent("DesktopRenamer_latest.dmg")
        let task = URLSession.shared.downloadTask(with: url) { location, _, error in
            guard let location = location, error == nil else {
                self.showAlert("Download Failed", "Could not download the update.", window: window)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: dmgPath.path) {
                    try FileManager.default.removeItem(at: dmgPath)
                }
                try FileManager.default.moveItem(at: location, to: dmgPath)
                self.mountAndReplaceApp(dmgPath: dmgPath, window: window)
            } catch {
                self.showAlert("Update Failed", "Could not save the downloaded update.", window: window)
            }
        }
        task.resume()
    }

    private func mountAndReplaceApp(dmgPath: URL, window: NSWindow?) {
        // Mount DMG
        let hdiutil = Process()
        hdiutil.launchPath = "/usr/bin/hdiutil"
        hdiutil.arguments = ["attach", dmgPath.path, "-nobrowse", "-quiet"]
        let pipe = Pipe()
        hdiutil.standardOutput = pipe
        hdiutil.launch()
        hdiutil.waitUntilExit()

        // Find mount point
        let diskutil = Process()
        diskutil.launchPath = "/usr/sbin/diskutil"
        diskutil.arguments = ["info", "-plist", dmgPath.path]
        let outPipe = Pipe()
        diskutil.standardOutput = outPipe
        diskutil.launch()
        diskutil.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let mountPoints = plist["MountPoint"] as? String else {
            self.showAlert("Update Failed", "Could not find the mounted DMG.", window: window)
            return
        }
        let mountPoint = mountPoints

        // Find .app in DMG
        let appPath = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint).first(where: { $0.hasSuffix(".app") })) ?? ""
        guard !appPath.isEmpty else {
            self.showAlert("Update Failed", "Could not find the app in the DMG.", window: window)
            return
        }
        let newAppURL = URL(fileURLWithPath: mountPoint).appendingPathComponent(appPath)
        let currentAppURL = Bundle.main.bundleURL

        // Replace app
        do {
            let backupURL = currentAppURL.deletingLastPathComponent().appendingPathComponent("DesktopRenamer_backup.app")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: currentAppURL, to: backupURL)
            try FileManager.default.copyItem(at: newAppURL, to: currentAppURL)
            self.showAlert("Update Installed", "The app will now restart to complete the update.", window: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [currentAppURL.path]
                task.launch()
                NSApp.terminate(nil)
            }
        } catch {
            self.showAlert("Update Failed", "Could not replace the app. Please update manually.", window: window)
        }
    }
}
