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
    private struct PendingApproval {
        let client: SpaceAPIApprovedClient
        var completions: [() -> Void]
    }

    @Published private(set) var isRestrictedForSettings = false
    @Published private(set) var approvedClients: [SpaceAPIApprovedClient] = []
    @Published private(set) var pendingApprovalRequest: SpaceAPIApprovedClient?
    @Published private(set) var errorMessage: String?
    @Published private(set) var canRepairPolicy = false

    @MainActor var policyDidChange: (@MainActor () -> Void)?
    var accessRequestDidArrive: (() -> Void)?

    private let lock = NSLock()
    private var policy = SpaceAPIAccessPolicy(isRestricted: false, approvedClients: [])
    private var isStoreUsable = true
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var pendingApprovalOrder: [String] = []
    private var pendingApprovalIDs = Set<String>()
    private var pendingApprovalTimeout: Task<Void, Never>?
    private var deniedRequestUntil: [String: Date] = [:]

    private let maximumPendingApplications = 2
    private let maximumPendingRequestsPerApp = 8
    private let accessRequestTimeout: TimeInterval = 45
    private let deniedRequestCooldown: TimeInterval = 300

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
        guard persistAndApply(updated) else { return }
        if !isRestricted {
            finishPendingApprovalsForUnrestrictedMode()
        }
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
            if persistAndApply(updated), pendingApprovalRequest?.id == client.id {
                finishPendingApproval(with: client.accessLevel, persistApproval: false)
            }
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
    func requestApproval(for client: SpaceAPIApprovedClient, completion: @escaping () -> Void) {
        guard isRestrictedForSettings else {
            completion()
            return
        }

        if currentPolicy().approvedClients.contains(where: { $0.id == client.id && $0.accessLevel == .noAccess }) {
            completion()
            return
        }

        let now = Date()
        deniedRequestUntil = deniedRequestUntil.filter { $0.value > now }
        if deniedRequestUntil[client.id] != nil {
            completion()
            return
        }

        if var pending = pendingApprovals[client.id] {
            guard pending.completions.count < maximumPendingRequestsPerApp else {
                completion()
                return
            }
            pending.completions.append(completion)
            pendingApprovals[client.id] = pending
            return
        }

        guard pendingApprovals.count < maximumPendingApplications else {
            completion()
            return
        }

        pendingApprovals[client.id] = PendingApproval(client: client, completions: [completion])
        pendingApprovalOrder.append(client.id)
        lock.lock()
        pendingApprovalIDs.insert(client.id)
        lock.unlock()
        showNextPendingApproval()
    }

    @MainActor
    func resolvePendingApproval(with accessLevel: SpaceAPIClientAccessLevel?) {
        finishPendingApproval(with: accessLevel)
    }

    @MainActor
    func cancelPendingApprovals() {
        guard !pendingApprovals.isEmpty else { return }
        pendingApprovalTimeout?.cancel()
        pendingApprovalTimeout = nil
        pendingApprovalRequest = nil
        let completions = pendingApprovals.values.flatMap(\.completions)
        pendingApprovals.removeAll()
        pendingApprovalOrder.removeAll()
        lock.lock()
        pendingApprovalIDs.removeAll()
        lock.unlock()
        completions.forEach { $0() }
    }

    func isPendingApproval(for identity: SpaceAPIPeerIdentity?) -> Bool {
        guard let identity, let id = Self.clientIdentifier(for: identity) else { return false }
        lock.lock()
        defer { lock.unlock() }
        return pendingApprovalIDs.contains(id)
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
    @discardableResult
    private func persistAndApply(_ updated: SpaceAPIAccessPolicy) -> Bool {
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
            return true
        } catch {
            failClosed(after: error)
            return false
        }
    }

    @MainActor
    private func finishPendingApproval(
        with accessLevel: SpaceAPIClientAccessLevel?,
        persistApproval: Bool = true,
        applyCooldown: Bool = true
    ) {
        guard let client = pendingApprovalRequest,
              let pending = pendingApprovals.removeValue(forKey: client.id) else { return }
        pendingApprovalTimeout?.cancel()
        pendingApprovalTimeout = nil
        pendingApprovalRequest = nil
        pendingApprovalOrder.removeAll { $0 == client.id }
        lock.lock()
        pendingApprovalIDs.remove(client.id)
        lock.unlock()

        var accessWasGranted = false
        if let accessLevel, accessLevel != .noAccess, persistApproval {
            var approvedClient = client
            approvedClient.accessLevel = accessLevel
            var updated = currentPolicy()
            updated.approvedClients.removeAll { $0.id == client.id }
            updated.approvedClients.append(approvedClient)
            updated.approvedClients.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            accessWasGranted = persistAndApply(updated)
        } else if let accessLevel, accessLevel != .noAccess {
            accessWasGranted = self.accessLevel(for: Self.peerIdentity(for: client)) == accessLevel
        }

        if !accessWasGranted, applyCooldown {
            deniedRequestUntil[client.id] = Date().addingTimeInterval(deniedRequestCooldown)
        }

        pending.completions.forEach { $0() }
        showNextPendingApproval()
    }

    @MainActor
    private func showNextPendingApproval() {
        guard pendingApprovalRequest == nil else { return }

        while let id = pendingApprovalOrder.first, let pending = pendingApprovals[id] {
            if isAuthorized(Self.peerIdentity(for: pending.client)) {
                pendingApprovalOrder.removeFirst()
                pendingApprovals.removeValue(forKey: id)
                lock.lock()
                pendingApprovalIDs.remove(id)
                lock.unlock()
                pending.completions.forEach { $0() }
                continue
            }

            pendingApprovalRequest = pending.client
            accessRequestDidArrive?()
            let timeout = accessRequestTimeout
            pendingApprovalTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finishPendingApproval(with: nil, applyCooldown: false)
            }
            return
        }
    }

    @MainActor
    private func finishPendingApprovalsForUnrestrictedMode() {
        pendingApprovalTimeout?.cancel()
        pendingApprovalTimeout = nil
        pendingApprovalRequest = nil
        let completions = pendingApprovals.values.flatMap(\.completions)
        pendingApprovals.removeAll()
        pendingApprovalOrder.removeAll()
        lock.lock()
        pendingApprovalIDs.removeAll()
        lock.unlock()
        completions.forEach { $0() }
    }

    private func accessLevel(for identity: SpaceAPIPeerIdentity) -> SpaceAPIClientAccessLevel {
        accessLevel(for: Optional(identity))
    }

    private static func peerIdentity(for client: SpaceAPIApprovedClient) -> SpaceAPIPeerIdentity {
        SpaceAPIPeerIdentity(designatedRequirement: client.designatedRequirement, codeHash: client.codeHash)
    }

    private static func clientIdentifier(for identity: SpaceAPIPeerIdentity) -> String? {
        if let requirement = identity.designatedRequirement {
            return "requirement:\(requirement)"
        }
        if let codeHash = identity.codeHash {
            return "hash:\(codeHash)"
        }
        return nil
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
        cancelPendingApprovals()
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
              let data = values[kSecValueData as String] as? Data else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                "Reading the saved policy did not return its data and Keychain item reference."
            )
        }
        try validateKeychainAccess(for: result)
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
        let status = SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary,
                                         &existingResult)

        if status == errSecSuccess {
            try validateKeychainAccess(for: existingResult)
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

        do {
            var savedResult: CFTypeRef?
            try checkStatus(
                SecItemCopyMatching(itemQuery(returnData: false, returnReference: true) as CFDictionary,
                                    &savedResult),
                "Could not verify the SpaceAPI access policy in Keychain."
            )
            try validateKeychainAccess(for: savedResult)
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
        // This non-sandboxed app has no Data Protection Keychain access-group
        // entitlement. Keep the policy in the file-based keychain, whose ACL can
        // restrict it to DesktopRenamer's code identity.
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

    private static func makeAppOnlyAccess() throws -> SecAccess {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        var status = errSecSuccess
        guard let access = DRCreateSpaceAPIKeychainAccess(executablePath, &status) else {
            try checkStatus(status, "Could not protect the SpaceAPI access policy in Keychain.")
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        return access
    }

    private static func validateKeychainAccess(for value: CFTypeRef?) throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw SpaceAPIAccessError.keychainAccessUnavailable
        }
        var failureReason: NSString?
        guard DRValidateSpaceAPIKeychainAccess(value, executablePath, &failureReason) else {
            throw SpaceAPIAccessError.invalidKeychainItem(
                failureReason as String? ?? "Could not verify the SpaceAPI access policy's Keychain access controls."
            )
        }
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
