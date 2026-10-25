import Foundation
import Darwin
import Security

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    failures.append(message)
}

private func testFrameRoundTripAndPartialReads() throws {
    let first = Data("{\"id\":\"one\"}".utf8)
    let second = Data("{\"id\":\"two\"}".utf8)
    let firstFrame = try SpaceAPISocketFraming.encode(first, maximumPayloadBytes: 128)
    let secondFrame = try SpaceAPISocketFraming.encode(second, maximumPayloadBytes: 128)

    var buffer = Data(firstFrame.prefix(3))
    let incompleteFrames = try SpaceAPISocketFraming.extractFrames(from: &buffer, maximumPayloadBytes: 128)
    check(incompleteFrames.isEmpty, "incomplete header is retained")
    buffer.append(firstFrame.dropFirst(3))
    let reconstructedFrames = try SpaceAPISocketFraming.extractFrames(from: &buffer, maximumPayloadBytes: 128)
    check(reconstructedFrames == [first], "frame split across reads is reconstructed")

    buffer.append(firstFrame)
    buffer.append(secondFrame)
    let multipleFrames = try SpaceAPISocketFraming.extractFrames(from: &buffer, maximumPayloadBytes: 128)
    check(multipleFrames == [first, second], "multiple frames in one read are extracted")
    check(buffer.isEmpty, "all complete frame bytes are consumed")
}

private func testFrameLimits() throws {
    do {
        _ = try SpaceAPISocketFraming.encode(Data(), maximumPayloadBytes: 4)
        failures.append("empty payload must be rejected")
    } catch let error as SpaceAPISocketFrameError {
        check(error == .emptyPayload, "empty payload has a stable error")
    }

    do {
        _ = try SpaceAPISocketFraming.encode(Data(repeating: 0x41, count: 5), maximumPayloadBytes: 4)
        failures.append("oversized payload must be rejected")
    } catch let error as SpaceAPISocketFrameError {
        check(error == .payloadTooLarge, "oversized payload has a stable error")
    }

    var zeroLength = Data([0, 0, 0, 0])
    do {
        _ = try SpaceAPISocketFraming.extractFrames(from: &zeroLength, maximumPayloadBytes: 4)
        failures.append("zero-length frame must be rejected")
    } catch let error as SpaceAPISocketFrameError {
        check(error == .emptyPayload, "zero-length frame has a stable error")
    }

    var oversized = Data([0, 0, 0, 5])
    do {
        _ = try SpaceAPISocketFraming.extractFrames(from: &oversized, maximumPayloadBytes: 4)
        failures.append("oversized frame header must be rejected before buffering payload")
    } catch let error as SpaceAPISocketFrameError {
        check(error == .payloadTooLarge, "oversized frame has a stable error")
    }
}

private func testSocketReadDeadline() throws {
    func makeSocketPair() throws -> [Int32] {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return descriptors
    }

    func setSafetyReadTimeout(_ descriptor: Int32) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }

    let idlePair = try makeSocketPair()
    defer {
        Darwin.close(idlePair[0])
        Darwin.close(idlePair[1])
    }
    setSafetyReadTimeout(idlePair[0])
    let idleStart = DispatchTime.now().uptimeNanoseconds
    let idleRead = SpaceAPISocketFraming.readExactly(
        SpaceAPISocketFraming.headerLength,
        from: idlePair[0],
        deadline: .now() + .milliseconds(100)
    )
    let idleDuration = DispatchTime.now().uptimeNanoseconds - idleStart
    check(idleRead == nil, "an idle peer is closed by the first-frame deadline")
    check(idleDuration < 700_000_000, "an idle peer does not hold its read until the fallback socket timeout")

    let partialPair = try makeSocketPair()
    defer {
        Darwin.close(partialPair[0])
        Darwin.close(partialPair[1])
    }
    setSafetyReadTimeout(partialPair[0])
    let partialHeader = Data([0, 0])
    _ = partialHeader.withUnsafeBytes { bytes in
        Darwin.write(partialPair[1], bytes.baseAddress!, bytes.count)
    }
    let partialHeaderStart = DispatchTime.now().uptimeNanoseconds
    let partialRead = SpaceAPISocketFraming.readExactly(
        SpaceAPISocketFraming.headerLength,
        from: partialPair[0],
        deadline: .now() + .milliseconds(100)
    )
    let partialHeaderDuration = DispatchTime.now().uptimeNanoseconds - partialHeaderStart
    check(partialRead == nil, "a peer that stalls mid-header is closed by the same deadline")
    check(partialHeaderDuration < 700_000_000, "a partial header does not hold its read until the fallback socket timeout")

    let partialPayloadPair = try makeSocketPair()
    defer {
        Darwin.close(partialPayloadPair[0])
        Darwin.close(partialPayloadPair[1])
    }
    setSafetyReadTimeout(partialPayloadPair[0])
    let completeHeader = Data([0, 0, 0, 5])
    _ = completeHeader.withUnsafeBytes { bytes in
        Darwin.write(partialPayloadPair[1], bytes.baseAddress!, bytes.count)
    }
    let payloadDeadline = DispatchTime.now() + .milliseconds(100)
    let headerRead = SpaceAPISocketFraming.readExactly(
        SpaceAPISocketFraming.headerLength,
        from: partialPayloadPair[0],
        deadline: payloadDeadline
    )
    let partialPayloadStart = DispatchTime.now().uptimeNanoseconds
    let payloadRead = SpaceAPISocketFraming.readExactly(5, from: partialPayloadPair[0], deadline: payloadDeadline)
    let partialPayloadDuration = DispatchTime.now().uptimeNanoseconds - partialPayloadStart
    check(headerRead == completeHeader, "a complete header is read before the payload deadline")
    check(payloadRead == nil, "a peer that stalls mid-payload is closed by the original frame deadline")
    check(partialPayloadDuration < 700_000_000, "a partial payload does not hold its read until the fallback socket timeout")

    let slowDripPair = try makeSocketPair()
    defer {
        Darwin.close(slowDripPair[0])
        Darwin.close(slowDripPair[1])
    }
    setSafetyReadTimeout(slowDripPair[0])
    let writerGroup = DispatchGroup()
    writerGroup.enter()
    DispatchQueue.global().async {
        defer { writerGroup.leave() }
        for byte: UInt8 in [0, 0, 0, 5] {
            var byte = byte
            _ = withUnsafePointer(to: &byte) { Darwin.write(slowDripPair[1], $0, 1) }
            usleep(80_000)
        }
    }
    let slowDripStart = DispatchTime.now().uptimeNanoseconds
    let slowDripRead = SpaceAPISocketFraming.readExactly(
        SpaceAPISocketFraming.headerLength,
        from: slowDripPair[0],
        deadline: .now() + .milliseconds(200)
    )
    let slowDripDuration = DispatchTime.now().uptimeNanoseconds - slowDripStart
    _ = writerGroup.wait(timeout: .now() + .seconds(1))
    check(slowDripRead == nil, "a slow-drip peer cannot extend the original absolute frame deadline")
    check(slowDripDuration < 700_000_000, "a slow-drip peer is closed before the fallback socket timeout")

    let completePair = try makeSocketPair()
    defer {
        Darwin.close(completePair[0])
        Darwin.close(completePair[1])
    }
    let expected = Data([0, 0, 0, 5])
    _ = expected.withUnsafeBytes { bytes in
        Darwin.write(completePair[1], bytes.baseAddress!, bytes.count)
    }
    let completeRead = SpaceAPISocketFraming.readExactly(
        expected.count,
        from: completePair[0],
        deadline: .now() + .seconds(1)
    )
    check(completeRead == expected, "a complete first request frame is read normally")

    let persistentPair = try makeSocketPair()
    defer {
        Darwin.close(persistentPair[0])
        Darwin.close(persistentPair[1])
    }
    _ = expected.withUnsafeBytes { bytes in
        Darwin.write(persistentPair[1], bytes.baseAddress!, bytes.count)
    }
    let persistentRead = SpaceAPISocketFraming.readExactly(expected.count, from: persistentPair[0])
    check(persistentRead == expected, "reads without an initial-frame deadline preserve the persistent socket path")
}

private func testAuthorizationIdentities() {
    let signedClient = SpaceAPIApprovedClient(
        id: "requirement:anchor apple generic and identifier \"com.example.signed\"",
        name: "Signed App",
        bundleIdentifier: "com.example.signed",
        applicationPath: "/Applications/Signed.app",
        designatedRequirement: "anchor apple generic and identifier \"com.example.signed\"",
        codeHash: nil
    )
    let developmentClient = SpaceAPIApprovedClient(
        id: "hash:YWJj",
        name: "Development App",
        bundleIdentifier: "com.example.dev",
        applicationPath: "/Applications/Development.app",
        designatedRequirement: nil,
        codeHash: "YWJj"
    )
    let readOnlyClient = SpaceAPIApprovedClient(
        id: "requirement:read-only",
        name: "Read Only App",
        bundleIdentifier: "com.example.read-only",
        applicationPath: "/Applications/Read Only.app",
        designatedRequirement: "requirement:read-only",
        codeHash: nil,
        accessLevel: .readOnly
    )
    let deniedClient = SpaceAPIApprovedClient(
        id: "requirement:denied",
        name: "Denied App",
        bundleIdentifier: "com.example.denied",
        applicationPath: "/Applications/Denied.app",
        designatedRequirement: "requirement:denied",
        codeHash: nil,
        accessLevel: .noAccess
    )

    check(
        SpaceAPIAuthorization.isAuthorized(
            nil,
            restricted: false,
            approvedClients: [],
            storeAvailable: true
        ),
        "unrestricted mode preserves access for clients without a signing identity"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            nil,
            restricted: true,
            approvedClients: [],
            storeAvailable: true
        ),
        "an empty allowlist denies all clients"
    )
    check(
        SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: signedClient.designatedRequirement, codeHash: nil),
            restricted: true,
            approvedClients: [signedClient],
            storeAvailable: true
        ),
        "a signed client is approved by designated requirement"
    )
    let readOnlyIdentity = SpaceAPIPeerIdentity(
        designatedRequirement: readOnlyClient.designatedRequirement,
        codeHash: nil
    )
    check(
        SpaceAPIAuthorization.approvedClient(for: readOnlyIdentity, in: [readOnlyClient]) == readOnlyClient,
        "an authenticated identity resolves to its saved per-app access decision"
    )
    let readOnlyAccess = SpaceAPIAuthorization.accessLevel(
        for: readOnlyIdentity,
        restricted: true,
        approvedClients: [readOnlyClient],
        storeAvailable: true
    )
    check(readOnlyAccess.allows(.read), "read-only app may issue read requests")
    check(!readOnlyAccess.allows(.write), "read-only app cannot issue write requests")
    check(
        SpaceAPIAuthorization.accessLevel(
            for: readOnlyIdentity,
            restricted: false,
            approvedClients: [readOnlyClient],
            storeAvailable: true
        ) == .fullAccess,
        "disabling the restriction restores full access regardless of saved per-app level"
    )
    check(
        SpaceAPIAuthorization.isAuthorized(
            readOnlyIdentity,
            restricted: true,
            approvedClients: [readOnlyClient],
            storeAvailable: true
        ),
        "read-only app may connect to the socket and receive read events"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: deniedClient.designatedRequirement, codeHash: nil),
            restricted: true,
            approvedClients: [deniedClient],
            storeAvailable: true
        ),
        "no-access app is denied at connection authorization"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: "identifier \"com.example.other\"", codeHash: nil),
            restricted: true,
            approvedClients: [signedClient],
            storeAvailable: true
        ),
        "bundle ID or a different designated requirement does not inherit approval"
    )
    check(
        SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: nil, codeHash: "YWJj"),
            restricted: true,
            approvedClients: [developmentClient],
            storeAvailable: true
        ),
        "an ad-hoc development client is approved by exact code hash"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: nil, codeHash: "ZGVm"),
            restricted: true,
            approvedClients: [developmentClient],
            storeAvailable: true
        ),
        "rebuilding an ad-hoc client with a different code hash requires approval again"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: signedClient.designatedRequirement, codeHash: nil),
            restricted: true,
            approvedClients: [],
            storeAvailable: true
        ),
        "revoking a client immediately removes its authorization"
    )
    check(
        !SpaceAPIAuthorization.isAuthorized(
            SpaceAPIPeerIdentity(designatedRequirement: signedClient.designatedRequirement, codeHash: nil),
            restricted: true,
            approvedClients: [signedClient],
            storeAvailable: false
        ),
        "unavailable protected policy fails closed"
    )

    let legacyClientData = Data(
        #"{"id":"legacy","name":"Legacy","applicationPath":"/Applications/Legacy.app","designatedRequirement":"requirement:legacy"}"#.utf8
    )
    let decodedLegacyClient = try? JSONDecoder().decode(SpaceAPIApprovedClient.self, from: legacyClientData)
    check(decodedLegacyClient?.accessLevel == .fullAccess, "existing app approvals preserve full access after policy migration")
    let encodedReadOnlyClient = try? JSONEncoder().encode(readOnlyClient)
    let decodedReadOnlyClient = encodedReadOnlyClient.flatMap {
        try? JSONDecoder().decode(SpaceAPIApprovedClient.self, from: $0)
    }
    check(decodedReadOnlyClient?.accessLevel == .readOnly, "per-app access level survives policy serialization")

    let legacyPolicyData = Data(
        #"{"isRestricted":true,"approvedClients":[]}"#.utf8
    )
    let decodedLegacyPolicy = try? JSONDecoder().decode(SpaceAPIAccessPolicy.self, from: legacyPolicyData)
    check(decodedLegacyPolicy?.isRestricted == true, "legacy access policies keep their SpaceAPI restriction")
    check(decodedLegacyPolicy?.isAppleScriptRestricted == false, "AppleScript restriction defaults off for existing installs")

    let appleScriptPolicy = SpaceAPIAccessPolicy(
        isRestricted: false,
        isAppleScriptRestricted: true,
        approvedClients: [readOnlyClient]
    )
    let encodedPolicy = try? JSONEncoder().encode(appleScriptPolicy)
    let decodedPolicy = encodedPolicy.flatMap { try? JSONDecoder().decode(SpaceAPIAccessPolicy.self, from: $0) }
    check(decodedPolicy == appleScriptPolicy, "AppleScript restriction and shared approvals survive policy serialization")

    let recipients = SpaceAPIAuthorization.authorizedRecipients(
        from: ["approved", "read-only", "denied", "unapproved"],
        identity: { client in
            switch client {
            case "approved":
                return SpaceAPIPeerIdentity(designatedRequirement: signedClient.designatedRequirement, codeHash: nil)
            case "read-only":
                return readOnlyIdentity
            default:
                return SpaceAPIPeerIdentity(designatedRequirement: "other", codeHash: nil)
            }
        },
        restricted: true,
        approvedClients: [signedClient, readOnlyClient, deniedClient],
        storeAvailable: true
    )
    check(recipients == ["approved", "read-only"], "restricted socket events reach full and read-only apps, but not denied clients")
}

private func testKernelAuditTokenIdentity() {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    var staticCode: SecStaticCode?
    check(
        SecStaticCodeCreateWithPath(executableURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
        "test executable has a readable code signature"
    )
    guard let staticCode else { return }
    check(
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess,
        "test executable code signature is valid"
    )
    guard let expectedIdentity = SpaceAPICodeIdentity.identity(for: staticCode) else {
        failures.append("test executable exposes its signed or ad-hoc identity")
        return
    }

    var descriptors: [Int32] = [0, 0]
    check(
        socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0,
        "create a local socket pair for the audit-token test"
    )
    guard descriptors.allSatisfy({ $0 >= 0 }) else { return }
    defer {
        close(descriptors[0])
        close(descriptors[1])
    }

    var auditToken = audit_token_t()
    var tokenLength = socklen_t(MemoryLayout<audit_token_t>.size)
    let tokenStatus = getsockopt(
        descriptors[0],
        SOL_LOCAL,
        LOCAL_PEERTOKEN,
        &auditToken,
        &tokenLength
    )
    check(tokenStatus == 0, "the kernel provides a peer audit token")
    check(tokenLength == MemoryLayout<audit_token_t>.size, "the audit token has the expected size")
    guard tokenStatus == 0, tokenLength == MemoryLayout<audit_token_t>.size else { return }

    let tokenData = withUnsafeBytes(of: &auditToken) { Data($0) }
    check(
        SpaceAPICodeIdentity.identity(forAuditToken: tokenData) == expectedIdentity,
        "audit-token resolution returns the connected process code identity"
    )
}

private func testSignedApplicationRequirement() {
    let applicationURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var staticCode: SecStaticCode?
    check(
        SecStaticCodeCreateWithPath(applicationURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
        "Finder code signature can be inspected"
    )
    guard let staticCode else { return }
    let identity = SpaceAPICodeIdentity.identity(for: staticCode)
    check(identity?.designatedRequirement?.isEmpty == false, "signed apps expose a designated code requirement")
    check(identity?.codeHash == nil, "signed apps are not treated as ad-hoc development builds")
}

@main
struct SpaceAPISocketTests {
    static func main() {
        do {
            try testFrameRoundTripAndPartialReads()
            try testFrameLimits()
            try testSocketReadDeadline()
            testAuthorizationIdentities()
            testKernelAuditTokenIdentity()
            testSignedApplicationRequirement()
        } catch {
            failures.append("unexpected test error: \(error)")
        }

        if failures.isEmpty {
            print("SpaceAPI socket framing and authorization tests passed")
        } else {
            for failure in failures { print("FAIL: \(failure)") }
            exit(1)
        }
    }
}
