import AppKit
import Combine
import Foundation
import Security

private struct SpaceAPIAccessPolicy: Codable {
    var isRestricted: Bool
    var approvedClients: [SpaceAPIApprovedClient]
}

/// Keeps the allowlist in the app's private Data Protection Keychain access group.
/// Authentication reads a lock-protected in-memory snapshot and never trusts peer-supplied
/// process IDs, bundle identifiers, or paths.
final class SpaceAPIAccessController: ObservableObject {
    @Published private(set) var isRestrictedForSettings = false
    @Published private(set) var approvedClients: [SpaceAPIApprovedClient] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var canRepairPolicy = false

    @MainActor var policyDidChange: (@MainActor () -> Void)?

    private let lock = NSLock()
    private var policy = SpaceAPIAccessPolicy(isRestricted: false, approvedClients: [])
    private var isStoreUsable = true

    private static let keychainService = "dev.mqiu.DesktopRenamer.SpaceAPI"
    private static let keychainAccount = "access-policy-v1"

    init() {
        do {
            if let storedPolicy = try Self.readPolicy() {
                policy = storedPolicy
                isRestrictedForSettings = storedPolicy.isRestricted
                approvedClients = storedPolicy.approvedClients
            }
        } catch {
            isStoreUsable = false
            policy = SpaceAPIAccessPolicy(isRestricted: true, approvedClients: [])
            isRestrictedForSettings = true
            canRepairPolicy = true
            errorMessage = error.localizedDescription
            Self.recordPolicyFailure(error, operation: "read")
        }
    }

    var isRestricted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return policy.isRestricted
    }

    func isAuthorized(_ identity: SpaceAPIPeerIdentity?) -> Bool {
        let snapshot = policySnapshot()
        return SpaceAPIAuthorization.isAuthorized(identity, restricted: snapshot.policy.isRestricted,
                                                   approvedClients: snapshot.policy.approvedClients,
                                                   storeAvailable: snapshot.storeAvailable)
    }

    func accessLevel(for identity: SpaceAPIPeerIdentity?) -> SpaceAPIClientAccessLevel {
        let snapshot = policySnapshot()
        return SpaceAPIAuthorization.accessLevel(
            for: identity,
            restricted: snapshot.policy.isRestricted,
            approvedClients: snapshot.policy.approvedClients,
            storeAvailable: snapshot.storeAvailable
        )
    }

    func authorizedRecipients<Client>(
        from clients: [Client],
        identity: (Client) -> SpaceAPIPeerIdentity?
    ) -> [Client] {
        let snapshot = policySnapshot()
        return SpaceAPIAuthorization.authorizedRecipients(
            from: clients,
            identity: identity,
            restricted: snapshot.policy.isRestricted,
            approvedClients: snapshot.policy.approvedClients,
            storeAvailable: snapshot.storeAvailable
        )
    }

    @MainActor
    func setRestricted(_ isRestricted: Bool) {
        var updated = currentPolicy()
        updated.isRestricted = isRestricted
        persistAndApply(updated)
    }

    @MainActor
    func approveApplication(at url: URL) {
        do {
            var client = try Self.approvedClient(at: url)
            var updated = currentPolicy()
            if let existing = updated.approvedClients.first(where: { $0.id == client.id }) {
                client.accessLevel = existing.accessLevel
            }
            updated.approvedClients.removeAll { $0.id == client.id }
            updated.approvedClients.append(client)
            updated.approvedClients.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            persistAndApply(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func revokeClient(id: String) {
        var updated = currentPolicy()
        updated.approvedClients.removeAll { $0.id == id }
        persistAndApply(updated)
    }

    @MainActor
    func setAccessLevel(forClientID id: String, to accessLevel: SpaceAPIClientAccessLevel) {
        var updated = currentPolicy()
        guard let index = updated.approvedClients.firstIndex(where: { $0.id == id }) else { return }
        updated.approvedClients[index].accessLevel = accessLevel
        persistAndApply(updated)
    }

    @MainActor
    func repairUnreadablePolicy() {
        let replacement = SpaceAPIAccessPolicy(isRestricted: true, approvedClients: [])
        do {
            try Self.deleteStoredPolicy()
            try Self.writePolicy(replacement)
            lock.lock()
            policy = replacement
            isStoreUsable = true
            lock.unlock()
            isRestrictedForSettings = true
            approvedClients = []
            canRepairPolicy = false
            errorMessage = nil
            policyDidChange?()
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Replaced an unreadable access policy with a restricted policy and no approved clients."
            )
        } catch {
            failClosed(after: error)
        }
    }

    private func currentPolicy() -> SpaceAPIAccessPolicy {
        lock.lock()
        defer { lock.unlock() }
        return policy
    }

    private func policySnapshot() -> (policy: SpaceAPIAccessPolicy, storeAvailable: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (policy, isStoreUsable)
    }

    @MainActor
    private func persistAndApply(_ updated: SpaceAPIAccessPolicy) {
        do {
            try Self.writePolicy(updated)
            lock.lock()
            policy = updated
            isStoreUsable = true
            lock.unlock()
            isRestrictedForSettings = updated.isRestricted
            approvedClients = updated.approvedClients
            canRepairPolicy = false
            errorMessage = nil
            policyDidChange?()
        } catch {
            failClosed(after: error)
        }
    }

    @MainActor
    private func failClosed(after error: Error) {
        lock.lock()
        policy = SpaceAPIAccessPolicy(isRestricted: true, approvedClients: [])
        isStoreUsable = false
        lock.unlock()
        isRestrictedForSettings = true
        approvedClients = []
        canRepairPolicy = true
        errorMessage = error.localizedDescription
        Self.recordPolicyFailure(error, operation: "write")
        policyDidChange?()
    }

    private static func recordPolicyFailure(_ error: Error, operation: String) {
        let underlyingError = error as NSError
        let verificationDetail = (error as? SpaceAPIAccessError)?.diagnosticDetail
            .map { "; detail: \($0)" } ?? ""
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceAPI",
            level: "error",
            "Could not \(operation) access policy (\(underlyingError.domain), \(underlyingError.code)): \(error.localizedDescription)\(verificationDetail)"
        )
    }

    private static func approvedClient(at url: URL) throws -> SpaceAPIApprovedClient {
        var staticCode: SecStaticCode?
        try checkStatus(
            SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode),
            "Could not inspect the selected application."
        )
        guard let staticCode else { throw SpaceAPIAccessError.invalidApplication }
        try checkStatus(
            SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil),
            "The selected app does not have a valid code signature."
        )

        guard let identity = SpaceAPICodeIdentity.identity(for: staticCode) else {
            throw SpaceAPIAccessError.invalidApplication
        }

        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier
        let path = url.standardizedFileURL.path

        if let encodedHash = identity.codeHash {
            return SpaceAPIApprovedClient(
                id: "hash:\(encodedHash)",
                name: name,
                bundleIdentifier: bundleIdentifier,
                applicationPath: path,
                designatedRequirement: nil,
                codeHash: encodedHash,
                accessLevel: .readOnly
            )
        }

        guard let requirementText = identity.designatedRequirement else {
            throw SpaceAPIAccessError.invalidApplication
        }
        return SpaceAPIApprovedClient(
            id: "requirement:\(requirementText)",
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationPath: path,
            designatedRequirement: requirementText,
            codeHash: nil,
            accessLevel: .readOnly
        )
    }

    static func identity(forAuditToken tokenData: Data) -> SpaceAPIPeerIdentity? {
        SpaceAPICodeIdentity.identity(forAuditToken: tokenData)
    }

    private static func readPolicy() throws -> SpaceAPIAccessPolicy? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery(returnData: true) as CFDictionary, &result)
        if status == errSecSuccess {
            return try decodePolicy(from: result)
        }
        guard status == errSecItemNotFound else {
            try checkStatus(status, "Could not read the SpaceAPI access policy from Keychain.")
            return nil
        }

        // Policies written by earlier versions live in the file-based login keychain.
        // Read them through its existing ACL, then move them into this app's private
        // Data Protection Keychain group before removing the legacy item.
        var legacyResult: CFTypeRef?
        let legacyStatus = SecItemCopyMatching(legacyItemQuery(returnData: true) as CFDictionary, &legacyResult)
        guard legacyStatus != errSecItemNotFound else { return nil }
        try checkStatus(legacyStatus, "Could not read the previous SpaceAPI access policy from Keychain.")

        let legacyPolicy = try decodePolicy(from: legacyResult)
        try writePolicy(legacyPolicy)
        removeLegacyPolicyIfPresent()
        return legacyPolicy
    }

    private static func deleteStoredPolicy() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try checkStatus(status, "Could not replace the unreadable SpaceAPI access policy in Keychain.")
            return
        }
        removeLegacyPolicyIfPresent()
    }

    private static func writePolicy(_ policy: SpaceAPIAccessPolicy) throws {
        let data = try JSONEncoder().encode(policy)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            try checkStatus(updateStatus, "Could not update the SpaceAPI access policy in Keychain.")
            return
        }

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            try writePolicy(policy)
            return
        }
        try checkStatus(addStatus, "Could not save the SpaceAPI access policy in Keychain.")

        do {
            var savedResult: CFTypeRef?
            try checkStatus(
                SecItemCopyMatching(itemQuery(returnData: true) as CFDictionary, &savedResult),
                "Could not verify the SpaceAPI access policy in Keychain."
            )
            guard let savedData = savedResult as? Data, savedData == data else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "The newly saved policy data could not be verified."
                )
            }
        } catch {
            // Do not leave a newly-created but unverifiable policy item behind. It would
            // be found on the next attempt and prevent the user from correcting the policy.
            let cleanupStatus = SecItemDelete(baseQuery() as CFDictionary)
            if cleanupStatus != errSecSuccess && cleanupStatus != errSecItemNotFound {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceAPI",
                    level: "error",
                    "Could not remove an unverifiable newly-created access policy (OSStatus \(cleanupStatus))."
                )
            }
            throw error
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            // With no explicit shared access group, the Data Protection Keychain
            // uses the signed app's private default access group.
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private static func legacyBaseQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecUseDataProtectionKeychain as String] = false
        return query
    }

    private static func itemQuery(returnData: Bool) -> [String: Any] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if returnData { query[kSecReturnData as String] = true }
        return query
    }

    private static func legacyItemQuery(returnData: Bool) -> [String: Any] {
        var query = legacyBaseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if returnData { query[kSecReturnData as String] = true }
        return query
    }

    private static func decodePolicy(from value: CFTypeRef?) throws -> SpaceAPIAccessPolicy {
        guard let data = value as? Data else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "Reading the saved policy did not return its data."
            )
        }
        do {
            return try JSONDecoder().decode(SpaceAPIAccessPolicy.self, from: data)
        } catch {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "The saved policy data does not match the expected format."
            )
        }
    }

    private static func removeLegacyPolicyIfPresent() {
        let status = SecItemDelete(legacyBaseQuery() as CFDictionary)
        guard status != errSecSuccess && status != errSecItemNotFound else { return }
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceAPI",
            level: "warning",
            "Could not remove the previous file-keychain access policy after migration (OSStatus \(status))."
        )
    }

    private static func checkStatus(_ status: OSStatus, _ message: String) throws {
        guard status == errSecSuccess else {
            throw NSError(
                domain: "DesktopRenamer.SpaceAPI.AccessControl",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(message, comment: "")]
            )
        }
    }
}

private enum SpaceAPIAccessError: LocalizedError {
    case invalidApplication
    case invalidKeychainItem(String)

    var diagnosticDetail: String? {
        guard case let .invalidKeychainItem(detail) = self else { return nil }
        return detail
    }

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            return NSLocalizedString("Choose a valid signed app or ad-hoc development app.", comment: "")
        case .invalidKeychainItem:
            return NSLocalizedString("The SpaceAPI access policy could not be verified. Access remains restricted.", comment: "")
        }
    }
}
