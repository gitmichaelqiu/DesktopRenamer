import AppKit
import CryptoKit
import Foundation
import ServiceManagement

@discardableResult
private func runTool(_ path: String, arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    } catch {
        print("IdentityMigration: failed to run \(path): \(error)")
        return false
    }
}

final class DesktopRenamerBridgeMigrationManager {
    static let shared = DesktopRenamerBridgeMigrationManager()

    private var hasPresentedPrompt = false
    private var completion: (() -> Void)?
    private var stageMonitor: Timer?
    private var stageMonitorDeadline: Date?
    private var stageLaunchStarted = false
    private var manifestURL: URL?

    private init() {}

    /// Returns true when the caller must pause normal application startup while
    /// the legacy bridge offers or performs the migration.
    func beginIfNeeded(completion: @escaping () -> Void) -> Bool {
        guard DesktopRenamerIdentity.isLegacyBridge,
              DesktopRenamerMigrationConfiguration.isConfigured else {
            return false
        }

        self.completion = completion
        guard !hasPresentedPrompt else { return true }
        hasPresentedPrompt = true

        DispatchQueue.main.async { [weak self] in
            self?.presentMigrationPrompt()
        }
        return true
    }

    private func presentMigrationPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "DesktopRenamer needs a one-time update"
        alert.informativeText = "This update changes DesktopRenamer's application identity. Your settings will be preserved, and the previous application will be removed only after the new one starts successfully."
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            startMigration()
        } else {
            continueNormalApplication()
        }
    }

    private func startMigration() {
        guard let packageURL = DesktopRenamerMigrationConfiguration.packageURL,
              let expectedHash = DesktopRenamerMigrationConfiguration.packageSHA256,
              let expectedVersion = DesktopRenamerMigrationConfiguration.packageVersion else {
            showFailure(DesktopRenamerMigrationError.invalidConfiguration)
            return
        }

        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let manifest = DesktopRenamerMigrationManifest(
            schemaVersion: DesktopRenamerMigrationManifest.currentSchemaVersion,
            sourceApplicationPath: sourceURL.path,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            targetBundleIdentifier: DesktopRenamerIdentity.currentBundleIdentifier,
            stagingApplicationPath: DesktopRenamerMigrationConfiguration.stagingApplicationURL.path,
            launchAtLoginEnabled: SMAppService.mainApp.status == .enabled
                || SMAppService.mainApp.status == .requiresApproval,
            expectedVersion: expectedVersion,
            createdAt: Date()
        )

        do {
            try DesktopRenamerMigrationStorage.writeManifest(manifest)
            manifestURL = DesktopRenamerMigrationStorage.manifestURL
        } catch {
            showFailure(error)
            return
        }

        let task = URLSession.shared.downloadTask(with: packageURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async { self.showFailure(error) }
                return
            }

            guard let temporaryURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                DispatchQueue.main.async {
                    self.showFailure(DesktopRenamerMigrationError.invalidDownloadResponse)
                }
                return
            }

            do {
                let packageURL = try self.cacheDownloadedPackage(
                    at: temporaryURL
                )
                try self.validatePackage(
                    at: packageURL,
                    expectedSHA256: expectedHash
                )
                DispatchQueue.main.async {
                    self.installPackage(at: packageURL)
                }
            } catch {
                DispatchQueue.main.async { self.showFailure(error) }
            }
        }
        task.resume()
    }

    private func cacheDownloadedPackage(at temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = DesktopRenamerMigrationStorage.cacheDirectoryURL
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let packageURL = directoryURL.appendingPathComponent("DesktopRenamer-Migration.pkg")
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: packageURL)
        return packageURL
    }

    private func validatePackage(at packageURL: URL, expectedSHA256: String) throws {
        let packageData = try Data(contentsOf: packageURL)
        let actualHash = SHA256.hash(data: packageData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedSHA256 else {
            throw DesktopRenamerMigrationError.invalidPackageHash
        }

        guard runTool(
            "/usr/sbin/pkgutil",
            arguments: ["--check-signature", packageURL.path]
        ), runTool(
            "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "install", packageURL.path]
        ) else {
            throw DesktopRenamerMigrationError.packageVerificationFailed
        }
    }

    private func installPackage(at packageURL: URL) {
        guard NSWorkspace.shared.open(packageURL) else {
            showFailure(DesktopRenamerMigrationError.packageVerificationFailed)
            return
        }

        stageMonitorDeadline = Date().addingTimeInterval(10 * 60)
        stageMonitor?.invalidate()
        stageMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkForInstalledStagingApplication()
        }
    }

    private func checkForInstalledStagingApplication() {
        guard !stageLaunchStarted else { return }

        if let deadline = stageMonitorDeadline, Date() > deadline {
            stopStageMonitoring()
            showFailure(DesktopRenamerMigrationError.stagingApplicationNotFound)
            return
        }

        let stagingURL = DesktopRenamerMigrationConfiguration.stagingApplicationURL
        guard let bundle = Bundle(url: stagingURL),
              bundle.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == DesktopRenamerMigrationConfiguration.packageVersion else {
            return
        }

        stageLaunchStarted = true
        stopStageMonitoring()

        guard let manifestURL else {
            showFailure(DesktopRenamerMigrationError.manifestInvalid)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--desktoprenamer-migration",
            "--desktoprenamer-migration-manifest",
            manifestURL.path
        ]

        NSWorkspace.shared.openApplication(at: stagingURL, configuration: configuration) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.showFailure(error) }
            }
        }
    }

    private func stopStageMonitoring() {
        stageMonitor?.invalidate()
        stageMonitor = nil
        stageMonitorDeadline = nil
    }

    private func continueNormalApplication() {
        stopStageMonitoring()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    private func showFailure(_ error: Error) {
        stopStageMonitoring()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DesktopRenamer migration was not completed"
        alert.informativeText = "\(error.localizedDescription) The current application was left available so you can retry the migration later."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            stageLaunchStarted = false
            startMigration()
        } else {
            continueNormalApplication()
        }
    }
}
