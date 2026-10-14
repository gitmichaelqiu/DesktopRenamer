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
        let status = SecItemCopyMatching(itemQuery(returnData: true, returnReference: true) as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        try checkStatus(status, "Could not read the SpaceAPI access policy from Keychain.")

        guard let values = result as? [String: Any],
              let data = values[kSecValueData as String] as? Data,
              let item = keychainItem(from: values[kSecValueRef as String]) else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "Reading the saved policy did not return its data and a Keychain item reference."
            )
        }
        try validateKeychainAccess(for: item)
        do {
            return try JSONDecoder().decode(SpaceAPIAccessPolicy.self, from: data)
        } catch {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "The saved policy data does not match the expected format."
            )
        }
    }

    private static func deleteStoredPolicy() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try checkStatus(status, "Could not replace the unreadable SpaceAPI access policy in Keychain.")
            return
        }
    }

    private static func writePolicy(_ policy: SpaceAPIAccessPolicy) throws {
        let data = try JSONEncoder().encode(policy)
        var existingResult: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary, &existingResult)

        if status == errSecSuccess {
            guard let item = keychainItem(from: existingResult) else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "Finding the saved policy did not return a Keychain item reference."
                )
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

        var createdItem: SecKeychainItem?
        do {
            var savedResult: CFTypeRef?
            try checkStatus(
                SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary, &savedResult),
                "Could not verify the SpaceAPI access policy in Keychain."
            )
            guard let item = keychainItem(from: savedResult) else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "The newly saved policy did not return a Keychain item reference."
                )
            }
            createdItem = item
            try validateKeychainAccess(for: item)
        } catch {
            // Do not leave a newly-created but unverifiable policy item behind. It would
            // be found on the next attempt and prevent the user from correcting the policy.
            let cleanupStatus = createdItem.map(SecKeychainItemDelete) ?? errSecItemNotFound
            if cleanupStatus != errSecSuccess && cleanupStatus != errSecItemNotFound {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceAPI",
                    level: "error",
                    "Could not remove an unverifiable newly-created access policy (OSStatus \(cleanupStatus))."
                )
            } else if createdItem == nil {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceAPI",
                    level: "error",
                    "Could not identify the newly-created access policy to remove after verification failed."
                )
            }
            throw error
        }
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

        // SecAccessCreate applies this app list to the restricted data-access ACL.
        // Preserve its other defaults: the owner ACL has no trusted apps (so changing
        // access prompts the user), and the safe encryption ACL may trust any app.
        return access
    }

    private static func validateKeychainAccess(for item: SecKeychainItem) throws {
        var access: SecAccess?
        try checkStatus(SecKeychainItemCopyAccess(item, &access), "Could not verify Keychain access controls.")
        guard let access else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "Keychain returned no access-control object for the saved policy."
            )
        }
        var aclList: CFArray?
        try checkStatus(SecAccessCopyACLList(access, &aclList), "Could not verify Keychain access controls.")
        guard let aclList = aclList as? [SecACL], !aclList.isEmpty else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "Keychain returned no readable access-control entries for the saved policy."
            )
        }

        let selfApplication = try makeTrustedApplicationForSelf()
        let selfData = try trustedApplicationData(selfApplication)
        var hasRestrictedDataAccess = false
        var hasAccessControlChange = false
        for (index, acl) in aclList.enumerated() {
            let authorizations = try aclAuthorizationNames(for: acl)
            if authorizations == [kSecACLAuthorizationEncrypt as String]
                || authorizations == [kSecACLAuthorizationIntegrity as String]
                || authorizations == [kSecACLAuthorizationPartitionID as String] {
                // Keychain adds OS-managed ACLs when saving this item. Their
                // authorization metadata is not a trusted-application list; they do
                // not grant data access or permission to change the item's ACL. Keep
                // validating the data-access and ACL-change entries below.
                continue
            }
            var applications: CFArray?
            var description: CFString?
            var promptSelector = SecKeychainPromptSelector()
            try checkStatus(
                SecACLCopyContents(acl, &applications, &description, &promptSelector),
                "Could not verify Keychain access controls."
            )
            guard let applications = applications as? [SecTrustedApplication] else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "Access-control entry \(index) [\(authorizations.joined(separator: ", "))] did not return a trusted-application list."
                )
            }

            if authorizations == [kSecACLAuthorizationChangeACL as String] {
                hasAccessControlChange = true
                let ownerIsRestricted: Bool
                switch applications.count {
                case 0:
                    ownerIsRestricted = true
                case 1:
                    ownerIsRestricted = try trustedApplicationData(applications[0]) == selfData
                default:
                    ownerIsRestricted = false
                }
                guard ownerIsRestricted else {
                    throw SpaceAPIAccessError.invalidKeychainItem(
                        "The access-control owner entry is not restricted to DesktopRenamer or the default user prompt."
                    )
                }
                continue
            }

            hasRestrictedDataAccess = hasRestrictedDataAccess
                || authorizations.contains(kSecACLAuthorizationDecrypt as String)
            hasAccessControlChange = hasAccessControlChange
                || authorizations.contains(kSecACLAuthorizationChangeACL as String)
            guard applications.count == 1 else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "Access-control entry \(index) contains \(applications.count) trusted apps; expected exactly one."
                )
            }
            guard try trustedApplicationData(applications[0]) == selfData else {
                throw SpaceAPIAccessError.invalidKeychainItem(
                    "Access-control entry \(index) does not identify this DesktopRenamer executable."
                )
            }
            // This legacy selector only controls prompts and is ignored by macOS 10.13.1+
            // when asking to add an app to the trusted list. The app list is the access
            // grant, so Keychain normalizing the selector must not invalidate an app-only ACL.
            _ = promptSelector
        }

        guard hasRestrictedDataAccess else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "The saved policy has no restricted data-access entry."
            )
        }
        guard hasAccessControlChange else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "The saved policy has no access-control change entry."
            )
        }
    }

    private static func aclAuthorizationNames(for acl: SecACL) throws -> [String] {
        guard let authorizations = SecACLCopyAuthorizations(acl) as? [String], !authorizations.isEmpty else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "A Keychain access-control entry did not return its authorization list."
            )
        }
        return authorizations
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
        guard let data else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "A trusted-app entry did not contain identity data."
            )
        }
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
    case invalidKeychainItem(String)
    case keychainAccessUnavailable

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
        case .keychainAccessUnavailable:
            return NSLocalizedString("Secure storage for the SpaceAPI access policy is unavailable.", comment: "")
        }
    }
}
