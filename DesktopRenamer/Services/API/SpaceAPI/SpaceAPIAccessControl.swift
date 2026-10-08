import AppKit
import Combine
import Foundation
import Security

private struct SpaceAPIAccessPolicy: Codable {
    var isRestricted: Bool
    var approvedClients: [SpaceAPIApprovedClient]
}

/// Keeps the allowlist in a Keychain item whose access list is restricted to this app.
/// Authentication reads a lock-protected in-memory snapshot and never trusts peer-supplied
/// process IDs, bundle identifiers, or paths.
final class SpaceAPIAccessController: ObservableObject {
    @Published private(set) var isRestrictedForSettings = false
    @Published private(set) var approvedClients: [SpaceAPIApprovedClient] = []
    @Published private(set) var errorMessage: String?

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
            errorMessage = error.localizedDescription
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
            let client = try Self.approvedClient(at: url)
            var updated = currentPolicy()
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
            errorMessage = nil
            policyDidChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                codeHash: encodedHash
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
            codeHash: nil
        )
    }

    static func identity(forAuditToken tokenData: Data) -> SpaceAPIPeerIdentity? {
        SpaceAPICodeIdentity.identity(forAuditToken: tokenData)
    }

    private static func readPolicy() throws -> SpaceAPIAccessPolicy? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery(returnData: true, returnReference: true) as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        try checkStatus(status, "Could not read the SpaceAPI access policy from Keychain.")

        guard let values = result as? [String: Any],
              let data = values[kSecValueData as String] as? Data,
              let item = keychainItem(from: values[kSecValueRef as String]) else {
            throw SpaceAPIAccessError.invalidKeychainItem
        }
        try validateKeychainAccess(for: item)
        do {
            return try JSONDecoder().decode(SpaceAPIAccessPolicy.self, from: data)
        } catch {
            throw SpaceAPIAccessError.invalidKeychainItem
        }
    }

    private static func writePolicy(_ policy: SpaceAPIAccessPolicy) throws {
        let data = try JSONEncoder().encode(policy)
        var existingResult: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary, &existingResult)

        if status == errSecSuccess {
            guard let item = keychainItem(from: existingResult) else {
                throw SpaceAPIAccessError.invalidKeychainItem
            }
            try validateKeychainAccess(for: item)
            let update = [kSecValueData as String: data]
            try checkStatus(
                SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary),
                "Could not update the SpaceAPI access policy in Keychain."
            )
            return
        }
        guard status == errSecItemNotFound else {
            try checkStatus(status, "Could not find the SpaceAPI access policy in Keychain.")
            return
        }

        let access = try makeAppOnlyAccess()
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccess as String] = access
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            try writePolicy(policy)
            return
        }
        try checkStatus(addStatus, "Could not save the SpaceAPI access policy in Keychain.")

        var savedResult: CFTypeRef?
        try checkStatus(
            SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary, &savedResult),
            "Could not verify the SpaceAPI access policy in Keychain."
        )
        guard let item = keychainItem(from: savedResult) else {
            throw SpaceAPIAccessError.invalidKeychainItem
        }
        try validateKeychainAccess(for: item)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func itemQuery(returnData: Bool, returnReference: Bool) -> [String: Any] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if returnData { query[kSecReturnData as String] = true }
        if returnReference { query[kSecReturnRef as String] = true }
        return query
    }

    private static func keychainItem(from value: Any?) -> SecKeychainItem? {
        guard let value else { return nil }
        if let values = value as? [String: Any], let reference = values[kSecValueRef as String] {
            return keychainItem(from: reference)
        }
        let reference = value as CFTypeRef
        guard CFGetTypeID(reference) == SecKeychainItemGetTypeID() else { return nil }
        return unsafeBitCast(reference, to: SecKeychainItem.self)
    }

    private static func makeAppOnlyAccess() throws -> SecAccess {
        guard let executableURL = Bundle.main.executableURL else {
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        var trustedApplication: SecTrustedApplication?
        let trustedStatus = executableURL.path.withCString {
            SecTrustedApplicationCreateFromPath($0, &trustedApplication)
        }
        try checkStatus(trustedStatus, "Could not identify DesktopRenamer for Keychain access.")
        guard let trustedApplication else { throw SpaceAPIAccessError.keychainAccessUnavailable }

        var access: SecAccess?
        try checkStatus(
            SecAccessCreate(
                "DesktopRenamer SpaceAPI access policy" as CFString,
                [trustedApplication] as CFArray,
                &access
            ),
            "Could not protect the SpaceAPI access policy in Keychain."
        )
        guard let access else { throw SpaceAPIAccessError.keychainAccessUnavailable }

        // SecAccessCreate's application list is a starting point, not a guarantee that
        // every ACL (especially the ACL-change entry) is restricted to this app.
        // Rewrite each ACL before the item is created and verify it again after saving.
        var aclList: CFArray?
        try checkStatus(SecAccessCopyACLList(access, &aclList), "Could not protect the SpaceAPI access policy in Keychain.")
        guard let aclList = aclList as? [SecACL], !aclList.isEmpty else {
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        for acl in aclList {
            try checkStatus(
                SecACLSetContents(
                    acl,
                    [trustedApplication] as CFArray,
                    "DesktopRenamer SpaceAPI access policy" as CFString,
                    restrictedPromptSelector
                ),
                "Could not protect the SpaceAPI access policy in Keychain."
            )
        }
        return access
    }

    private static var restrictedPromptSelector: SecKeychainPromptSelector {
        // Override the default prompt policy for unsigned and invalidly signed callers.
        // The application list remains the access grant for every ACL, including ACL changes.
        SecKeychainPromptSelector(rawValue: 0x00A0)
    }

    private static func validateKeychainAccess(for item: SecKeychainItem) throws {
        var access: SecAccess?
        try checkStatus(SecKeychainItemCopyAccess(item, &access), "Could not verify Keychain access controls.")
        guard let access else { throw SpaceAPIAccessError.invalidKeychainItem }
        var aclList: CFArray?
        try checkStatus(SecAccessCopyACLList(access, &aclList), "Could not verify Keychain access controls.")
        guard let aclList = aclList as? [SecACL], !aclList.isEmpty else {
            throw SpaceAPIAccessError.invalidKeychainItem
        }

        let selfApplication = try makeTrustedApplicationForSelf()
        let selfData = try trustedApplicationData(selfApplication)
        for acl in aclList {
            var applications: CFArray?
            var description: CFString?
            var promptSelector = SecKeychainPromptSelector()
            try checkStatus(
                SecACLCopyContents(acl, &applications, &description, &promptSelector),
                "Could not verify Keychain access controls."
            )
            guard let applications = applications as? [SecTrustedApplication],
                  applications.count == 1,
                  try trustedApplicationData(applications[0]) == selfData,
                  promptSelector == restrictedPromptSelector else {
                throw SpaceAPIAccessError.invalidKeychainItem
            }
        }
    }

    private static func makeTrustedApplicationForSelf() throws -> SecTrustedApplication {
        guard let path = Bundle.main.executableURL?.path else {
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        var application: SecTrustedApplication?
        try checkStatus(
            path.withCString { SecTrustedApplicationCreateFromPath($0, &application) },
            "Could not identify DesktopRenamer for Keychain access."
        )
        guard let application else { throw SpaceAPIAccessError.keychainAccessUnavailable }
        return application
    }

    private static func trustedApplicationData(_ application: SecTrustedApplication) throws -> Data {
        var data: CFData?
        try checkStatus(
            SecTrustedApplicationCopyData(application, &data),
            "Could not verify Keychain access controls."
        )
        guard let data else { throw SpaceAPIAccessError.invalidKeychainItem }
        return data as Data
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
    case invalidKeychainItem
    case keychainAccessUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            return NSLocalizedString("Choose a valid signed app or ad-hoc development app.", comment: "")
        case .invalidKeychainItem:
            return NSLocalizedString("The SpaceAPI access policy could not be verified. Access remains restricted.", comment: "")
        case .keychainAccessUnavailable:
            return NSLocalizedString("Secure storage for the SpaceAPI access policy is unavailable.", comment: "")
        }
    }
}
