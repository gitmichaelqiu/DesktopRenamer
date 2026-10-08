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

    let recipients = SpaceAPIAuthorization.authorizedRecipients(
        from: ["approved", "unapproved"],
        identity: { client in
            client == "approved"
                ? SpaceAPIPeerIdentity(designatedRequirement: signedClient.designatedRequirement, codeHash: nil)
                : SpaceAPIPeerIdentity(designatedRequirement: "other", codeHash: nil)
        },
        restricted: true,
        approvedClients: [signedClient],
        storeAvailable: true
    )
    check(recipients == ["approved"], "restricted socket events are delivered only to approved recipients")
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
