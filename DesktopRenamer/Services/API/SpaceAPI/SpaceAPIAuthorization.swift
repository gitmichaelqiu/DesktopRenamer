import Foundation

enum SpaceAPIClientAccessLevel: String, Codable, CaseIterable, Identifiable {
    case noAccess
    case readOnly
    case fullAccess

    var id: Self { self }

    func allows(_ requiredAccess: SpaceAPIRequestAccess) -> Bool {
        switch (self, requiredAccess) {
        case (.fullAccess, _), (.readOnly, .read):
            return true
        case (.noAccess, _), (.readOnly, .write):
            return false
        }
    }
}

struct SpaceAPIApprovedClient: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let applicationPath: String
    let designatedRequirement: String?
    let codeHash: String?
    var accessLevel: SpaceAPIClientAccessLevel

    init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        applicationPath: String,
        designatedRequirement: String?,
        codeHash: String?,
        accessLevel: SpaceAPIClientAccessLevel = .fullAccess
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.designatedRequirement = designatedRequirement
        self.codeHash = codeHash
        self.accessLevel = accessLevel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case bundleIdentifier
        case applicationPath
        case designatedRequirement
        case codeHash
        case accessLevel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        applicationPath = try values.decode(String.self, forKey: .applicationPath)
        designatedRequirement = try values.decodeIfPresent(String.self, forKey: .designatedRequirement)
        codeHash = try values.decodeIfPresent(String.self, forKey: .codeHash)
        accessLevel = try values.decodeIfPresent(SpaceAPIClientAccessLevel.self, forKey: .accessLevel) ?? .fullAccess
    }
}

struct SpaceAPIApprovalPrompt: Equatable, Identifiable {
    let client: SpaceAPIApprovedClient
    let requestedAccess: SpaceAPIRequestAccess?

    var id: String { client.id }
}

struct SpaceAPIPeerIdentity: Equatable {
    let designatedRequirement: String?
    let codeHash: String?
}

enum SpaceAPIAuthorization {
    static func authorizedRecipients<Client>(
        from clients: [Client],
        identity: (Client) -> SpaceAPIPeerIdentity?,
        restricted: Bool,
        approvedClients: [SpaceAPIApprovedClient],
        storeAvailable: Bool
    ) -> [Client] {
        clients.filter {
            isAuthorized(
                identity($0),
                restricted: restricted,
                approvedClients: approvedClients,
                storeAvailable: storeAvailable
            )
        }
    }

    static func isAuthorized(
        _ identity: SpaceAPIPeerIdentity?,
        restricted: Bool,
        approvedClients: [SpaceAPIApprovedClient],
        storeAvailable: Bool
    ) -> Bool {
        accessLevel(
            for: identity,
            restricted: restricted,
            approvedClients: approvedClients,
            storeAvailable: storeAvailable
        ) != .noAccess
    }

    static func accessLevel(
        for identity: SpaceAPIPeerIdentity?,
        restricted: Bool,
        approvedClients: [SpaceAPIApprovedClient],
        storeAvailable: Bool
    ) -> SpaceAPIClientAccessLevel {
        guard storeAvailable else { return .noAccess }
        guard restricted else { return .fullAccess }
        guard let identity else { return .noAccess }

        return approvedClients.first { approved in
            if let requirement = approved.designatedRequirement,
               let peerRequirement = identity.designatedRequirement,
               requirement == peerRequirement {
                return true
            }
            return approved.codeHash != nil && approved.codeHash == identity.codeHash
        }?.accessLevel ?? .noAccess
    }
}
