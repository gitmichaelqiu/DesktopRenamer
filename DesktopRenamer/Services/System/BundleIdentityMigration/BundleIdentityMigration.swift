import Foundation

enum DesktopRenamerIdentity {
    static let legacyBundleIdentifier = "com.michaelqiu.DesktopRenamer"
    static let currentBundleIdentifier = "dev.mqiu.DesktopRenamer"

    static let legacyWidgetBundleIdentifier = "com.michaelqiu.DesktopRenamer.DesktopRenamerWidget"
    static let currentWidgetBundleIdentifier = "dev.mqiu.DesktopRenamer.DesktopRenamerWidget"

    static let currentUpdateChannel = "dev-mqiu"
    static let appcastTargetBundleIdentifierKey = "desktoprenamer:targetBundleIdentifier"

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
