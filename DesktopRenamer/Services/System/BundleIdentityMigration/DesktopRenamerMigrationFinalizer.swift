import AppKit
import Foundation

final class DesktopRenamerMigrationFinalizer {
    static let shared = DesktopRenamerMigrationFinalizer()

    private var manifest: DesktopRenamerMigrationManifest?
    private var backupURL: URL?
    private var targetURL: URL?
    private var temporaryTargetURL: URL?
    private var launchAttempts = 0

    private init() {}

    static var isRequested: Bool {
        if CommandLine.arguments.contains("--desktoprenamer-migration") {
            return true
        }

        guard DesktopRenamerIdentity.isCurrentApplication,
              Bundle.main.bundleURL.standardizedFileURL
                == DesktopRenamerMigrationConfiguration.stagingApplicationURL,
              FileManager.default.fileExists(
                atPath: DesktopRenamerMigrationStorage.manifestURL.path
              ) else {
            return false
        }

        // The bridge may have exited while Installer was running, or macOS may
        // have blocked its automatic launch. Opening the staged app directly
        // should resume the pending handoff from its durable manifest.
        return true
    }

    func startIfRequested() -> Bool {
        guard Self.isRequested else { return false }

        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
        return true
    }

    private func start() {
        NSApp.setActivationPolicy(.accessory)

        do {
            guard DesktopRenamerIdentity.isCurrentApplication else {
                throw DesktopRenamerMigrationError.stagingApplicationInvalid
            }

            let manifestURL = try manifestURLFromArguments()
            let manifest = try DesktopRenamerMigrationStorage.readManifest(from: manifestURL)
            guard manifest.schemaVersion == DesktopRenamerMigrationManifest.currentSchemaVersion,
                  manifest.targetBundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier,
                  manifest.stagingApplicationPath == Bundle.main.bundleURL.standardizedFileURL.path,
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    == manifest.expectedVersion else {
                throw DesktopRenamerMigrationError.manifestInvalid
            }

            self.manifest = manifest
            DesktopRenamerIdentityMigration.migrateLegacyDefaults(
                launchAtLoginEnabled: manifest.launchAtLoginEnabled
            )
            terminateLegacyApplicationIfNeeded()
        } catch {
            failMigration(error)
        }
    }

    private func manifestURLFromArguments() throws -> URL {
        guard let index = CommandLine.arguments.firstIndex(of: "--desktoprenamer-migration-manifest"),
              index + 1 < CommandLine.arguments.count else {
            return DesktopRenamerMigrationStorage.manifestURL
        }

        let path = CommandLine.arguments[index + 1]
        guard path.hasPrefix("/") else {
            throw DesktopRenamerMigrationError.manifestInvalid
        }

        let candidateURL = URL(fileURLWithPath: path).standardizedFileURL
        guard candidateURL == DesktopRenamerMigrationStorage.manifestURL.standardizedFileURL else {
            throw DesktopRenamerMigrationError.manifestInvalid
        }
        return candidateURL
    }

    private func terminateLegacyApplicationIfNeeded() {
        guard let manifest else {
            failMigration(DesktopRenamerMigrationError.manifestInvalid)
            return
        }

        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true)
            .standardizedFileURL
        let legacyApplication = NSWorkspace.shared.runningApplications.first { application in
            application.bundleIdentifier == DesktopRenamerIdentity.legacyBundleIdentifier
                && application.bundleURL?.standardizedFileURL == sourceURL
                && application.processIdentifier == manifest.sourceProcessIdentifier
        } ?? NSWorkspace.shared.runningApplications.first { application in
            application.bundleIdentifier == DesktopRenamerIdentity.legacyBundleIdentifier
                && application.bundleURL?.standardizedFileURL == sourceURL
        }

        guard let legacyApplication, !legacyApplication.isTerminated else {
            performApplicationSwap()
            return
        }

        legacyApplication.terminate()
        waitForLegacyApplicationToTerminate(legacyApplication, attemptsRemaining: 20)
    }

    private func waitForLegacyApplicationToTerminate(
        _ application: NSRunningApplication,
        attemptsRemaining: Int
    ) {
        let isStillRunning = NSWorkspace.shared.runningApplications.contains { runningApplication in
            runningApplication.processIdentifier == application.processIdentifier
        }
        guard !application.isTerminated && isStillRunning else {
            performApplicationSwap()
            return
        }

        guard attemptsRemaining > 0 else {
            guard application.forceTerminate() else {
                failMigration(DesktopRenamerMigrationError.legacyApplicationDidNotTerminate)
                return
            }
            waitForLegacyApplicationToTerminate(application, attemptsRemaining: 20)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak application] in
            guard let self, let application else { return }
            self.waitForLegacyApplicationToTerminate(
                application,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func performApplicationSwap() {
        guard let manifest else {
            failMigration(DesktopRenamerMigrationError.manifestInvalid)
            return
        }

        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true)
            .standardizedFileURL
        let stagingURL = Bundle.main.bundleURL.standardizedFileURL
        let parentURL = sourceURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appendingPathComponent(
            ".DesktopRenamer-new-\(UUID().uuidString).app"
        )
        let backupURL = parentURL.appendingPathComponent(
            ".DesktopRenamer-legacy-\(UUID().uuidString).app"
        )

        do {
            guard sourceURL.pathExtension == "app",
                  sourceURL != stagingURL else {
                throw DesktopRenamerMigrationError.targetApplicationInvalid
            }

            if fileManager.fileExists(atPath: sourceURL.path) {
                guard Bundle(url: sourceURL)?.bundleIdentifier
                    == DesktopRenamerIdentity.legacyBundleIdentifier else {
                    throw DesktopRenamerMigrationError.targetApplicationInvalid
                }
            }

            try fileManager.copyItem(at: stagingURL, to: temporaryURL)
            guard Bundle(url: temporaryURL)?.bundleIdentifier
                == DesktopRenamerIdentity.currentBundleIdentifier else {
                throw DesktopRenamerMigrationError.stagingApplicationInvalid
            }

            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: backupURL)
                self.backupURL = backupURL
            }

            try fileManager.moveItem(at: temporaryURL, to: sourceURL)
            self.temporaryTargetURL = temporaryURL
            self.targetURL = sourceURL

            guard Bundle(url: sourceURL)?.bundleIdentifier
                == DesktopRenamerIdentity.currentBundleIdentifier else {
                throw DesktopRenamerMigrationError.applicationSwapFailed
            }
        } catch {
            restoreAfterFailedSwap(
                targetURL: sourceURL,
                temporaryURL: temporaryURL,
                backupURL: backupURL
            )
            failMigration(error)
            return
        }

        UserDefaults.standard.set(
            stagingURL.path,
            forKey: DesktopRenamerIdentity.migrationCleanupStagedPathKey
        )
        if let backupURL = self.backupURL {
            UserDefaults.standard.set(
                backupURL.path,
                forKey: DesktopRenamerIdentity.migrationCleanupBackupPathKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: DesktopRenamerIdentity.migrationCleanupBackupPathKey
            )
        }
        UserDefaults.standard.synchronize()

        launchAttempts = 0
        launchCanonicalApplication(at: sourceURL)
    }

    private func launchCanonicalApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        UserDefaults.standard.removeObject(
            forKey: DesktopRenamerIdentity.migrationLaunchAcknowledgedKey
        )
        UserDefaults.standard.synchronize()

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.failMigration(error) }
                return
            }
            DispatchQueue.main.async { self.waitForCanonicalApplication(at: url) }
        }
    }

    private func waitForCanonicalApplication(at url: URL) {
        let isRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier
                && application.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }
        let hasAcknowledgedLaunch = UserDefaults.standard.bool(
            forKey: DesktopRenamerIdentity.migrationLaunchAcknowledgedKey
        )

        if isRunning && hasAcknowledgedLaunch {
            completeMigration()
            return
        }

        guard launchAttempts < 40 else {
            failMigration(DesktopRenamerMigrationError.applicationLaunchFailed)
            return
        }

        launchAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForCanonicalApplication(at: url)
        }
    }

    private func completeMigration() {
        if let backupURL,
           FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try FileManager.default.removeItem(at: backupURL)
            } catch {
                print("IdentityMigration: legacy application cleanup deferred: \(error)")
            }
        }

        UserDefaults.standard.set(
            true,
            forKey: DesktopRenamerIdentity.migrationCompletedKey
        )

        UserDefaults.standard.removeObject(
            forKey: DesktopRenamerIdentity.migrationLaunchAcknowledgedKey
        )
        NSApp.terminate(nil)
    }

    private func restoreAfterFailedSwap(targetURL: URL, temporaryURL: URL, backupURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try? fileManager.removeItem(at: temporaryURL)
        }

        if Bundle(url: targetURL)?.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier {
            try? fileManager.removeItem(at: targetURL)
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.moveItem(at: backupURL, to: targetURL)
        }
    }

    private func failMigration(_ error: Error) {
        if let targetURL,
           Bundle(url: targetURL)?.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier {
            NSWorkspace.shared.runningApplications
                .filter {
                    $0.bundleIdentifier == DesktopRenamerIdentity.currentBundleIdentifier
                        && $0.bundleURL?.standardizedFileURL == targetURL.standardizedFileURL
                }
                .forEach { $0.terminate() }
        }

        if let targetURL,
           let backupURL,
           FileManager.default.fileExists(atPath: backupURL.path) {
            restoreAfterFailedSwap(
                targetURL: targetURL,
                temporaryURL: temporaryTargetURL ?? targetURL,
                backupURL: backupURL
            )
        }

        relaunchLegacyApplicationIfNeeded()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DesktopRenamer migration failed"
        alert.informativeText = "\(error.localizedDescription) The previous application was preserved."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func relaunchLegacyApplicationIfNeeded() {
        guard let manifest else { return }

        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              Bundle(url: sourceURL)?.bundleIdentifier
                == DesktopRenamerIdentity.legacyBundleIdentifier else {
            return
        }

        let isRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == DesktopRenamerIdentity.legacyBundleIdentifier
                && application.bundleURL?.standardizedFileURL == sourceURL
        }
        guard !isRunning else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        NSWorkspace.shared.openApplication(
            at: sourceURL,
            configuration: configuration
        ) { _, error in
            if let error {
                print("IdentityMigration: failed to relaunch the legacy application: \(error)")
            }
        }
    }
}
