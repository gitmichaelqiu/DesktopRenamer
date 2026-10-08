import Darwin
import Foundation
import Security

enum SpaceAPICodeIdentity {
    private static let adHocSignatureFlag = SecCodeSignatureFlags.adhoc.rawValue

    static func identity(forAuditToken tokenData: Data) -> SpaceAPIPeerIdentity? {
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
        return identity(for: staticCode)
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
