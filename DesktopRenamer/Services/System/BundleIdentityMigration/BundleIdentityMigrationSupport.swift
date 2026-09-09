import Foundation

enum DesktopRenamerMigrationStorage {
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

struct DesktopRenamerMigrationManifest: Codable {
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

enum DesktopRenamerMigrationVersion {
    static func isAtLeast(_ candidate: String, _ expected: String) -> Bool {
        guard let candidateComponents = numericComponents(candidate),
              let expectedComponents = numericComponents(expected) else {
            return false
        }

        let componentCount = max(candidateComponents.count, expectedComponents.count)
        for index in 0..<componentCount {
            let candidateComponent = index < candidateComponents.count
                ? candidateComponents[index]
                : 0
            let expectedComponent = index < expectedComponents.count
                ? expectedComponents[index]
                : 0

            if candidateComponent != expectedComponent {
                return candidateComponent > expectedComponent
            }
        }

        return true
    }

    private static func numericComponents(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.count <= 4,
              components.allSatisfy({ component in
                  !component.isEmpty
                      && component.unicodeScalars.allSatisfy { scalar in
                          scalar.value >= 48 && scalar.value <= 57
                      }
              }) else {
            return nil
        }

        let values = components.compactMap { Int($0) }
        return values.count == components.count ? values : nil
    }
}

enum DesktopRenamerMigrationError: LocalizedError {
    case invalidConfiguration
    case invalidDownloadResponse
    case invalidPackageHash
    case packageVerificationFailed
    case installerClosed
    case stagingApplicationNotFound
    case stagingApplicationInvalid
    case stagingApplicationDidNotTerminate
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
        case .installerClosed:
            return "The migration installer was closed before the new application was installed."
        case .stagingApplicationNotFound:
            return "The migration package was installed, but its staged application was not found."
        case .stagingApplicationInvalid:
            return "The staged application has an unexpected identity or version."
        case .stagingApplicationDidNotTerminate:
            return "The previous staged DesktopRenamer process did not close safely."
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

enum DesktopRenamerMigrationConfiguration {
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

    static var allowsManualApproval: Bool {
        let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationAllowManualApprovalKey
        )

        if let value = rawValue as? Bool {
            return value
        }

        guard let value = rawValue as? String else {
            return false
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1", "yes", "true"].contains(normalizedValue)
    }

    static var stagingApplicationURL: URL {
        if let rawValue = Bundle.main.object(
            forInfoDictionaryKey: DesktopRenamerIdentity.migrationStagingPathKey
        ) as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") && value.hasSuffix(".app") {
                return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            }
        }

        return URL(fileURLWithPath: "/Applications/DesktopRenamer-Migration.app", isDirectory: true)
    }

    static var isConfigured: Bool {
        packageURL != nil && packageSHA256 != nil && packageVersion != nil
    }
}
