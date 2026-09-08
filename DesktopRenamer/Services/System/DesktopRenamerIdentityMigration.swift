import Foundation
import ServiceManagement

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
