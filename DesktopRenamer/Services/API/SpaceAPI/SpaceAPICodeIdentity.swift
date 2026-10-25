import Darwin
import Foundation
import Security

struct SpaceAPIAuthenticatedClient {
    let peerIdentity: SpaceAPIPeerIdentity
    let application: SpaceAPIApprovedClient?
}

enum SpaceAPICodeIdentity {
    private static let adHocSignatureFlag = SecCodeSignatureFlags.adhoc.rawValue
    private static let maximumParentProcessDepth = 16

    static func identity(forAuditToken tokenData: Data) -> SpaceAPIPeerIdentity? {
        guard let staticCode = staticCode(forAuditToken: tokenData) else { return nil }
        return identity(for: staticCode)
    }

    static func authenticatedClient(forAuditToken tokenData: Data) -> SpaceAPIAuthenticatedClient? {
        guard let auditToken = auditToken(from: tokenData),
              let processCode = staticCode(forAuditToken: tokenData) else { return nil }

        if let application = applicationClient(for: processCode) {
            return application
        }

        // Extension runtimes such as Node may live outside their host app bundle. Resolve
        // the host only through the kernel-reported process ancestry and verify its signature.
        if let application = responsibleApplication(for: auditToken) {
            return application
        }

        guard let identity = identity(for: processCode) else { return nil }
        return SpaceAPIAuthenticatedClient(
            peerIdentity: identity,
            application: executableClient(for: processCode, identity: identity)
        )
    }

    private static func executableClient(
        for staticCode: SecStaticCode,
        identity: SpaceAPIPeerIdentity
    ) -> SpaceAPIApprovedClient? {
        var codePath: CFURL?
        guard SecCodeCopyPath(staticCode, SecCSFlags(), &codePath) == errSecSuccess,
              let codePath else {
            return nil
        }

        let executableURL = codePath as URL
        let name = executableURL.deletingPathExtension().lastPathComponent

        if let codeHash = identity.codeHash {
            return SpaceAPIApprovedClient(
                id: "hash:\(codeHash)",
                name: name,
                bundleIdentifier: nil,
                applicationPath: executableURL.standardizedFileURL.path,
                designatedRequirement: nil,
                codeHash: codeHash,
                accessLevel: .readOnly
            )
        }

        guard let requirement = identity.designatedRequirement else { return nil }
        return SpaceAPIApprovedClient(
            id: "requirement:\(requirement)",
            name: name,
            bundleIdentifier: nil,
            applicationPath: executableURL.standardizedFileURL.path,
            designatedRequirement: requirement,
            codeHash: nil,
            accessLevel: .readOnly
        )
    }

    private static func applicationClient(for processCode: SecStaticCode) -> SpaceAPIAuthenticatedClient? {
        var codePath: CFURL?
        guard SecCodeCopyPath(processCode, SecCSFlags(), &codePath) == errSecSuccess,
              let codePath,
              let applicationURL = containingApplicationBundle(for: codePath as URL),
              let applicationCode = staticCode(at: applicationURL),
              let identity = identity(for: applicationCode),
              let client = approvedClient(
                identity: identity,
                applicationURL: applicationURL
              ) else {
            return nil
        }

        return SpaceAPIAuthenticatedClient(peerIdentity: identity, application: client)
    }

    private static func approvedClient(
        identity: SpaceAPIPeerIdentity,
        applicationURL: URL
    ) -> SpaceAPIApprovedClient? {
        let bundle = Bundle(url: applicationURL)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier
        let path = applicationURL.standardizedFileURL.path

        if let codeHash = identity.codeHash {
            return SpaceAPIApprovedClient(
                id: "hash:\(codeHash)",
                name: name,
                bundleIdentifier: bundleIdentifier,
                applicationPath: path,
                designatedRequirement: nil,
                codeHash: codeHash,
                accessLevel: .readOnly
            )
        }

        guard let requirement = identity.designatedRequirement else { return nil }
        return SpaceAPIApprovedClient(
            id: "requirement:\(requirement)",
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationPath: path,
            designatedRequirement: requirement,
            codeHash: nil,
            accessLevel: .readOnly
        )
    }

    private static func responsibleApplication(for auditToken: audit_token_t) -> SpaceAPIAuthenticatedClient? {
        var processID = pid_t(auditToken.val.5)
        var visited = Set<pid_t>()

        for _ in 0..<maximumParentProcessDepth {
            guard visited.insert(processID).inserted,
                  let parentID = parentProcessID(of: processID),
                  parentID > 1,
                  parentID != processID else {
                return nil
            }

            if let parentCode = staticCode(for: parentID),
               let application = applicationClient(for: parentCode) {
                return application
            }
            processID = parentID
        }

        return nil
    }

    private static func parentProcessID(of processID: pid_t) -> pid_t? {
        var information = proc_bsdinfo()
        let informationSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, &information, informationSize) == informationSize else {
            return nil
        }
        return pid_t(information.pbi_ppid)
    }

    private static func staticCode(for processID: pid_t) -> SecStaticCode? {
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributePid: NSNumber(value: processID)] as CFDictionary,
            SecCSFlags(),
            &guest
        )
        guard status == errSecSuccess,
              let guest,
              SecCodeCheckValidity(guest, SecCSFlags(), nil) == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, SecCSFlags(), &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static func staticCode(at url: URL) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else {
            return nil
        }
        return staticCode
    }

    private static func auditToken(from data: Data) -> audit_token_t? {
        guard data.count == MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { destination in
            data.copyBytes(to: destination)
        }
        return token
    }

    private static func staticCode(forAuditToken tokenData: Data) -> SecStaticCode? {
        guard let auditToken = auditToken(from: tokenData) else { return nil }
        var token = auditToken

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
        var containingApplication: URL?
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" {
                // Prefer the outer app when helper apps are nested inside the host bundle.
                containingApplication = candidate
            }
            candidate.deleteLastPathComponent()
        }
        return containingApplication
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
