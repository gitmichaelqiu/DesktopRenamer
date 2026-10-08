import Foundation

struct SpaceAPIApprovedClient: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let applicationPath: String
    let designatedRequirement: String?
    let codeHash: String?

    var identityDescription: String {
        NSLocalizedString(designatedRequirement == nil ? "Development build" : "Signed app", comment: "")
    }
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
        guard storeAvailable else { return false }
        guard restricted else { return true }
        guard let identity else { return false }

        return approvedClients.contains { approved in
            if let requirement = approved.designatedRequirement,
               let peerRequirement = identity.designatedRequirement,
               requirement == peerRequirement {
                return true
            }
            return approved.codeHash != nil && approved.codeHash == identity.codeHash
        }
    }
}
