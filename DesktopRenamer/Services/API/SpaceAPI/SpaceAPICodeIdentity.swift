import Darwin
import Foundation
import Security

struct SpaceAPIAuthenticatedClient {
    let peerIdentity: SpaceAPIPeerIdentity
    let application: SpaceAPIApprovedClient?
}

enum SpaceAPICodeIdentity {
    private static let adHocSignatureFlag = SecCodeSignatureFlags.adhoc.rawValue

    static func identity(forAuditToken tokenData: Data) -> SpaceAPIPeerIdentity? {
        guard let staticCode = staticCode(forAuditToken: tokenData) else { return nil }
        return identity(for: staticCode)
    }

    static func authenticatedClient(forAuditToken tokenData: Data) -> SpaceAPIAuthenticatedClient? {
        guard let staticCode = staticCode(forAuditToken: tokenData),
              let identity = identity(for: staticCode) else { return nil }
        return SpaceAPIAuthenticatedClient(
            peerIdentity: identity,
            application: approvedClient(for: staticCode, identity: identity)
        )
    }

    private static func approvedClient(
        for staticCode: SecStaticCode,
        identity: SpaceAPIPeerIdentity
    ) -> SpaceAPIApprovedClient? {
        var codePath: CFURL?
        guard SecCodeCopyPath(staticCode, SecCSFlags(), &codePath) == errSecSuccess,
              let codePath else {
            return nil
        }

        let executableOrBundleURL = codePath as URL
        let applicationURL = containingApplicationBundle(for: executableOrBundleURL) ?? executableOrBundleURL
        let bundle = Bundle(url: applicationURL)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent

        if let codeHash = identity.codeHash {
            return SpaceAPIApprovedClient(
                id: "hash:\(codeHash)",
                name: name,
                bundleIdentifier: bundle?.bundleIdentifier,
                applicationPath: applicationURL.standardizedFileURL.path,
                designatedRequirement: nil,
                codeHash: codeHash,
                accessLevel: .readOnly
            )
        }

        guard let requirement = identity.designatedRequirement else { return nil }
        return SpaceAPIApprovedClient(
            id: "requirement:\(requirement)",
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            applicationPath: applicationURL.standardizedFileURL.path,
            designatedRequirement: requirement,
            codeHash: nil,
            accessLevel: .readOnly
        )
    }

    private static func staticCode(forAuditToken tokenData: Data) -> SecStaticCode? {
        guard tokenData.count == MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { destination in
            tokenData.copyBytes(to: destination)
        }

        var guest: SecCode?
        let guestStatus = withUnsafePointer(to: &token) { tokenPointer in
            let data = Data(bytes: tokenPointer, count: MemoryLayout<audit_token_t>.size)
            return SecCodeCopyGuestWithAttributes(
                nil,
                [kSecGuestAttributeAudit: data] as CFDictionary,
                SecCSFlags(),
                &guest
            )
        }
        guard guestStatus == errSecSuccess,
              let guest,
              SecCodeCheckValidity(guest, SecCSFlags(), nil) == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }
        return staticCode
    }

    private static func containingApplicationBundle(for url: URL) -> URL? {
        var candidate = url.standardizedFileURL
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    static func identity(for staticCode: SecStaticCode) -> SpaceAPIPeerIdentity? {
        var information: CFDictionary?
        // The designated requirement is omitted unless requirement information is requested.
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSRequirementInformation),
            &information
        ) == errSecSuccess,
        let info = information as? [CFString: Any] else {
            return nil
        }

        let flags = (info[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        if flags & adHocSignatureFlag != 0 {
            guard let hash = info[kSecCodeInfoUnique] as? Data, !hash.isEmpty else { return nil }
            return SpaceAPIPeerIdentity(designatedRequirement: nil, codeHash: hash.base64EncodedString())
        }

        guard let requirementValue = info[kSecCodeInfoDesignatedRequirement],
              CFGetTypeID(requirementValue as CFTypeRef) == SecRequirementGetTypeID() else {
            return nil
        }
        let requirement = requirementValue as! SecRequirement
        var text: CFString?
        guard SecRequirementCopyString(requirement, SecCSFlags(), &text) == errSecSuccess,
              let text else {
            return nil
        }
        return SpaceAPIPeerIdentity(designatedRequirement: text as String, codeHash: nil)
    }
}
