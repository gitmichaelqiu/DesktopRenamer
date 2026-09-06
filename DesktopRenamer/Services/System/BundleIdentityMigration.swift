import AppKit
import CryptoKit
import Foundation
import ServiceManagement

enum DesktopRenamerIdentity {
    static let legacyBundleIdentifier = "com.michaelqiu.DesktopRenamer"
    static let currentBundleIdentifier = "dev.mqiu.DesktopRenamer"

    static let legacyWidgetBundleIdentifier = "com.michaelqiu.DesktopRenamer.DesktopRenamerWidget"
    static let currentWidgetBundleIdentifier = "dev.mqiu.DesktopRenamer.DesktopRenamerWidget"

    static let migrationPackageURLKey = "DesktopRenamerMigrationPackageURL"
    static let migrationPackageSHA256Key = "DesktopRenamerMigrationPackageSHA256"
    static let migrationPackageVersionKey = "DesktopRenamerMigrationPackageVersion"
    static let migrationStagingPathKey = "DesktopRenamerMigrationStagingPath"
    static let releaseTagKey = "DesktopRenamerReleaseTag"

    static let migrationLaunchAtLoginPendingKey = "DesktopRenamer.IdentityMigration.LaunchAtLoginPending"
    static let migrationCleanupStagedPathKey = "DesktopRenamer.IdentityMigration.CleanupStagedPath"
    static let migrationCleanupBackupPathKey = "DesktopRenamer.IdentityMigration.CleanupBackupPath"
    static let migrationLaunchAcknowledgedKey = "DesktopRenamer.IdentityMigration.LaunchAcknowledged"
    static let migrationCompletedKey = "DesktopRenamer.IdentityMigration.Completed"

    static var isLegacyBridge: Bool {
        Bundle.main.bundleIdentifier == legacyBundleIdentifier
    }

    static var isCurrentApplication: Bool {
        Bundle.main.bundleIdentifier == currentBundleIdentifier
    }
}

private enum DesktopRenamerMigrationStorage {
    static let migrationDirectoryName = "Migration"
    static let manifestFileName = "manifest.json"

    static var applicationSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopRenamer", isDirectory: true)
            .appendingPathComponent(migrationDirectoryName, isDirectory: true)
    }

    static var manifestURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent(manifestFileName)
    }

    static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopRenamer", isDirectory: true)
            .appendingPathComponent(migrationDirectoryName, isDirectory: true)
    }

    static func createApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func writeManifest(_ manifest: DesktopRenamerMigrationManifest) throws {
        try createApplicationSupportDirectory()
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
    }

    static func readManifest(from url: URL = manifestURL) throws -> DesktopRenamerMigrationManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DesktopRenamerMigrationManifest.self, from: data)
    }
}

private struct DesktopRenamerMigrationManifest: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceApplicationPath: String
    let sourceProcessIdentifier: Int32
    let targetBundleIdentifier: String
    let stagingApplicationPath: String
    let launchAtLoginEnabled: Bool
    let expectedVersion: String
    let createdAt: Date
}

private enum DesktopRenamerMigrationError: LocalizedError {
    case invalidConfiguration
    case invalidDownloadResponse
    case invalidPackageHash
    case packageVerificationFailed
    case stagingApplicationNotFound
    case stagingApplicationInvalid
    case manifestInvalid
    case legacyApplicationDidNotTerminate
    case targetApplicationInvalid
    case applicationSwapFailed
    case applicationLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The DesktopRenamer migration is not configured for this build."
        case .invalidDownloadResponse:
            return "The migration package could not be downloaded."
        case .invalidPackageHash:
            return "The migration package checksum did not match the signed release."
        case .packageVerificationFailed:
            return "The migration package did not pass macOS package verification."
        case .stagingApplicationNotFound:
            return "The migration package was installed, but its staged application was not found."
        case .stagingApplicationInvalid:
            return "The staged application has an unexpected identity or version."
        case .manifestInvalid:
            return "The migration manifest is missing or invalid."
        case .legacyApplicationDidNotTerminate:
            return "The previous DesktopRenamer process did not close safely."
        case .targetApplicationInvalid:
            return "The previous application location is not safe to replace."
        case .applicationSwapFailed:
            return "The new DesktopRenamer application could not be installed."
        case .applicationLaunchFailed:
            return "The new DesktopRenamer application could not be launched."
        }
    }
}

private enum DesktopRenamerMigrationConfiguration {
    static var packageURL: URL? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationPackageURLKey
        ) as? String,
        let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
        url.scheme?.lowercased() == "https",
        url.host != nil else {
            return nil
        }
        return url
    }

    static var packageSHA256: String? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationPackageSHA256Key
        ) as? String else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count == 64,
              value.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }) else {
            return nil
        }
        return value
    }

    static var packageVersion: String? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationPackageVersionKey
        ) as? String else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static var stagingApplicationURL: URL {
        if let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationStagingPathKey
        ) as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") && value.hasSuffix(".app") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
        }

        return URL(fileURLWithPath: "/Applications/DesktopRenamer-Migration.app", isDirectory: true)
    }

    static var isConfigured: Bool {
        packageURL != nil && packageSHA256 != nil && packageVersion != nil
    }
}

enum DesktopRenamerIdentityMigration {
    static func migrateLegacyDefaults(launchAtLoginEnabled: Bool) {
        guard DesktopRenamerIdentity.isCurrentApplication else { return }
        guard !UserDefaults.standard.bool(forKey: DesktopRenamerIdentity.migrationCompletedKey) else {
            return
        }

        let legacyDomain = UserDefaults.standard.persistentDomain(
            forName: DesktopRenamerIdentity.legacyBundleIdentifier
        ) ?? [:]
        var currentDomain = UserDefaults.standard.persistentDomain(
            forName: DesktopRenamerIdentity.currentBundleIdentifier
        ) ?? [:]

        for (key, value) in legacyDomain where !isSparkleKey(key) {
            if currentDomain[key] == nil {
                currentDomain[key] = value
            }
        }
        currentDomain["HasInitializedDefaults"] = true

        UserDefaults.standard.setPersistentDomain(
            currentDomain,
            forName: DesktopRenamerIdentity.currentBundleIdentifier
        )
        UserDefaults.standard.set(
            launchAtLoginEnabled,
            forKey: DesktopRenamerIdentity.migrationLaunchAtLoginPendingKey
        )
        UserDefaults.standard.set(
            true,
            forKey: DesktopRenamerIdentity.migrationCompletedKey
        )
    }

    static func prepareNormalLaunch() {
        guard DesktopRenamerIdentity.isCurrentApplication else { return }

        let isCanonicalLaunchAfterMigration = UserDefaults.standard.string(
            forKey: DesktopRenamerIdentity.migrationCleanupStagedPathKey
        ) != nil
        cleanupStagedApplicationIfNeeded()

        if isCanonicalLaunchAfterMigration {
            UserDefaults.standard.set(
                true,
                forKey: DesktopRenamerIdentity.migrationLaunchAcknowledgedKey
            )
            UserDefaults.standard.synchronize()
        }

        guard let launchAtLoginValue = UserDefaults.standard.object(
            forKey: DesktopRenamerIdentity.migrationLaunchAtLoginPendingKey
        ) as? Bool else {
            return
        }

        do {
            if launchAtLoginValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.removeObject(
                forKey: DesktopRenamerIdentity.migrationLaunchAtLoginPendingKey
            )
        } catch {
            print("IdentityMigration: failed to restore launch at login: \(error)")
        }
    }

    private static func cleanupStagedApplicationIfNeeded() {
        guard let stagedPath = UserDefaults.standard.string(
            forKey: DesktopRenamerIdentity.migrationCleanupStagedPathKey
        ) else {
            return
        }

        let stagedURL = URL(fileURLWithPath: stagedPath, isDirectory: true).standardizedFileURL
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        guard stagedURL != currentURL,
              stagedURL.pathExtension == "app" else {
            UserDefaults.standard.removeObject(
                forKey: DesktopRenamerIdentity.migrationCleanupStagedPathKey
            )
            return
        }

        do {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            if let backupPath = UserDefaults.standard.string(
                forKey: DesktopRenamerIdentity.migrationCleanupBackupPathKey
            ) {
                let backupURL = URL(fileURLWithPath: backupPath, isDirectory: true)
                    .standardizedFileURL
                if backupURL.pathExtension == "app",
                   backupURL != currentURL,
                   FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
            }
            try? FileManager.default.removeItem(at: DesktopRenamerMigrationStorage.manifestURL)
            try? FileManager.default.removeItem(at: DesktopRenamerMigrationStorage.cacheDirectoryURL)
            try? SMAppService.loginItem(
                identifier: DesktopRenamerIdentity.legacyBundleIdentifier
            ).unregister()
            UserDefaults.standard.removePersistentDomain(
                forName: DesktopRenamerIdentity.legacyBundleIdentifier
            )
            UserDefaults.standard.removeObject(
                forKey: DesktopRenamerIdentity.migrationCleanupStagedPathKey
            )
            UserDefaults.standard.removeObject(
                forKey: DesktopRenamerIdentity.migrationCleanupBackupPathKey
            )
        } catch {
            print("IdentityMigration: staged application cleanup deferred: \(error)")
        }
    }

    private static func isSparkleKey(_ key: String) -> Bool {
        key.hasPrefix("SU") || key.hasPrefix("SPU") || key.hasPrefix("org.sparkle-project")
    }
}

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
        print("IdentityMigration: failed to run (path): (error)")
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
            launchAtLoginEnabled: SMAppService.mainApp.status == .enabled,
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

final class DesktopRenamerMigrationFinalizer {
    static let shared = DesktopRenamerMigrationFinalizer()

    private var manifest: DesktopRenamerMigrationManifest?
    private var backupURL: URL?
    private var targetURL: URL?
    private var temporaryTargetURL: URL?
    private var launchAttempts = 0

    private init() {}

    static var isRequested: Bool {
        CommandLine.arguments.contains("--desktoprenamer-migration")
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
            failMigration(DesktopRenamerMigrationError.legacyApplicationDidNotTerminate)
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
