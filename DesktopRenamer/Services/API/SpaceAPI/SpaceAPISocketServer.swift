import Darwin
import Foundation
import Security

final class SpaceAPISocketServer {
    static var endpoint: URL {
        URL(fileURLWithPath: "/tmp/dev.mqiu.DesktopRenamer-\(getuid()).sock")
    }

    private static let maximumConnectedClients = 32
    fileprivate static let maximumQueuedBytes = 4 * 1024 * 1024
    private static let clientTimeoutSeconds: TimeInterval = 120
    // Bound incomplete frames from unapproved peers without expiring authorized event-only connections.
    private static let initialRequestTimeoutSeconds = 30

    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "dev.mqiu.DesktopRenamer.SpaceAPI.socket.accept")
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var startupFailure: String?
    private var clients: [ObjectIdentifier: SpaceAPISocketClient] = [:]
    private var accessController: SpaceAPIAccessController?
    private var requestHandler: ((String, SpaceAPIPeerIdentity?, SpaceAPIApprovedClient?, @escaping (String) -> Void) -> Void)?

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listenerDescriptor >= 0
    }

    var lastStartupFailure: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startupFailure
    }

    @discardableResult
    func start(
        accessController: SpaceAPIAccessController,
        requestHandler: @escaping (String, SpaceAPIPeerIdentity?, SpaceAPIApprovedClient?, @escaping (String) -> Void) -> Void
    ) -> Bool {
        stateLock.lock()
        guard listenerDescriptor < 0 else {
            self.accessController = accessController
            self.requestHandler = requestHandler
            startupFailure = nil
            stateLock.unlock()
            closeUnauthorizedConnections()
            return true
        }
        startupFailure = nil
        stateLock.unlock()

        let path = Self.endpoint.path
        var address = sockaddr_un()
        let pathBufferCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count + 1 <= pathBufferCapacity else {
            return failStart("The socket path exceeds the platform limit.")
        }
        if let failure = prepareSocketPath(path) {
            return failStart(failure)
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return failStart("Could not create the Unix socket: \(posixErrorDescription()).")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathCString = path.utf8CString
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: pathBufferCapacity) { destination in
                pathCString.withUnsafeBufferPointer { buffer in
                    destination.update(from: buffer.baseAddress!, count: buffer.count)
                }
            }
        }

        let bindStatus = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindStatus == 0 else {
            let failure = "Could not bind the Unix socket: \(posixErrorDescription())."
            Darwin.close(descriptor)
            return failStart(failure)
        }
        guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            let failure = "Could not set socket permissions: \(posixErrorDescription())."
            Darwin.close(descriptor)
            unlink(path)
            return failStart(failure)
        }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let failure = "Could not configure the socket listener: \(posixErrorDescription())."
            Darwin.close(descriptor)
            unlink(path)
            return failStart(failure)
        }
        guard listen(descriptor, Int32(Self.maximumConnectedClients)) == 0 else {
            let failure = "Could not listen on the Unix socket: \(posixErrorDescription())."
            Darwin.close(descriptor)
            unlink(path)
            return failStart(failure)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: acceptQueue)
        var socketInfo = stat()
        guard lstat(path, &socketInfo) == 0 else {
            let failure = "Could not inspect the socket after binding: \(posixErrorDescription())."
            Darwin.close(descriptor)
            unlink(path)
            return failStart(failure)
        }
        source.setEventHandler { [weak self] in self?.acceptConnections(from: descriptor) }
        source.setCancelHandler {
            Darwin.close(descriptor)
            var currentInfo = stat()
            if lstat(path, &currentInfo) == 0,
               currentInfo.st_dev == socketInfo.st_dev,
               currentInfo.st_ino == socketInfo.st_ino {
                unlink(path)
            }
        }

        stateLock.lock()
        listenerDescriptor = descriptor
        listenerSource = source
        startupFailure = nil
        self.accessController = accessController
        self.requestHandler = requestHandler
        stateLock.unlock()
        source.resume()
        return true
    }

    func stop() {
        stateLock.lock()
        let source = listenerSource
        listenerSource = nil
        listenerDescriptor = -1
        requestHandler = nil
        accessController = nil
        startupFailure = nil
        let currentClients = Array(clients.values)
        clients.removeAll()
        stateLock.unlock()

        currentClients.forEach { $0.close() }
        source?.cancel()
    }

    func broadcast(_ payload: String) {
        stateLock.lock()
        let activeClients = Array(clients.values)
        let controller = accessController
        stateLock.unlock()

        guard let controller else { return }
        let data = Data(payload.utf8)
        let authorizedClients = controller.authorizedRecipients(from: activeClients) { client in
            client.authenticatedClient?.peerIdentity
        }
        for client in authorizedClients {
            client.enqueue(data, authorization: { [weak self, weak client] in
                guard let self, let client else { return false }
                return self.isAuthorized(client)
            })
        }
    }

    func closeUnauthorizedConnections() {
        stateLock.lock()
        let activeClients = Array(clients.values)
        let controller = accessController
        stateLock.unlock()

        guard let controller else { return }
        for client in activeClients {
            guard !isAuthorized(client),
                  !controller.isPendingApproval(for: client.authenticatedClient?.peerIdentity) else {
                continue
            }
            client.close()
            remove(client)
        }
    }

    private func acceptConnections(from listener: Int32) {
        while true {
            let descriptor = Darwin.accept(listener, nil, nil)
            guard descriptor >= 0 else {
                if errno == EINTR { continue }
                return
            }
            _ = fcntl(descriptor, F_SETFL, 0)

            var noSignal: Int32 = 1
            _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

            let client = SpaceAPISocketClient(descriptor: descriptor)
            stateLock.lock()
            let count = clients.count
            if count < Self.maximumConnectedClients {
                clients[ObjectIdentifier(client)] = client
            }
            stateLock.unlock()

            guard count < Self.maximumConnectedClients else {
                client.close()
                continue
            }

            let initialRequestDeadline = isAuthorized(client)
                ? nil
                : DispatchTime.now() + .seconds(Self.initialRequestTimeoutSeconds)
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak client] in
                guard let self, let client else { return }
                self.run(client, initialRequestDeadline: initialRequestDeadline)
            }
        }
    }

    private func run(_ client: SpaceAPISocketClient, initialRequestDeadline: DispatchTime?) {
        defer {
            client.close()
            remove(client)
        }

        let authenticatedClient = client.authenticatedClient
        var hasCompletedAuthorizedRequest = initialRequestDeadline == nil
        while !client.isClosed {
            let deadline = hasCompletedAuthorizedRequest ? nil : initialRequestDeadline
            guard let header = client.readExactly(SpaceAPISocketFraming.headerLength, deadline: deadline) else { return }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= DesktopRenamerAPIContract.maxPayloadBytes else {
                client.close()
                return
            }
            guard let payload = client.readExactly(Int(length), deadline: deadline) else { return }
            guard let text = String(data: payload, encoding: .utf8) else {
                sendError(to: client, id: nil, code: SpaceAPIJSONRPCCode.parseError, message: "Request is not valid UTF-8.")
                hasCompletedAuthorizedRequest = isAuthorized(client)
                continue
            }

            stateLock.lock()
            let handler = requestHandler
            stateLock.unlock()
            guard let handler else { return }

            let semaphore = DispatchSemaphore(value: 0)
            handler(text, authenticatedClient?.peerIdentity, authenticatedClient?.application) { [weak self, weak client] response in
                guard let self, let client else {
                    semaphore.signal()
                    return
                }
                let isPermissionDenied = Self.isPermissionDeniedResponse(response)
                client.enqueue(Data(response.utf8), authorization: { [weak self, weak client] in
                    guard let self, let client else { return false }
                    return self.isAuthorized(client) || isPermissionDenied
                }) {
                    if !self.isAuthorized(client) {
                        client.close()
                    }
                    semaphore.signal()
                }
            }
            if semaphore.wait(timeout: .now() + Self.clientTimeoutSeconds) == .timedOut {
                return
            }
            hasCompletedAuthorizedRequest = isAuthorized(client)
        }
    }

    private func sendError(to client: SpaceAPISocketClient, id: String?, code: Int, message: String) {
        let response = SpaceAPIJSONRPCCodec.errorResponse(id: id, code: code, message: message)
        guard let payload = try? SpaceAPIJSONRPCCodec.encode(response) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        client.enqueue(Data(payload.utf8), authorization: { [weak self, weak client] in
            guard let self, let client else { return false }
            return self.isAuthorized(client)
        }) {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func isAuthorized(_ client: SpaceAPISocketClient) -> Bool {
        stateLock.lock()
        let controller = accessController
        stateLock.unlock()
        guard let controller else { return false }
        return controller.isAuthorized(client.authenticatedClient?.peerIdentity)
    }

    private func remove(_ client: SpaceAPISocketClient) {
        stateLock.lock()
        clients.removeValue(forKey: ObjectIdentifier(client))
        stateLock.unlock()
    }

    private func prepareSocketPath(_ path: String) -> String? {
        var info = stat()
        if lstat(path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK else {
                return "The socket endpoint already exists and is not a socket."
            }
            guard info.st_uid == getuid() else {
                return "The existing socket endpoint belongs to another user."
            }
            guard unlink(path) == 0 else {
                return "Could not remove the stale socket endpoint: \(posixErrorDescription())."
            }
        } else if errno != ENOENT {
            return "Could not inspect the socket endpoint: \(posixErrorDescription())."
        }
        return nil
    }

    private func failStart(_ reason: String) -> Bool {
        stateLock.lock()
        startupFailure = reason
        stateLock.unlock()
        DiagnosticEventLog.shared.record(subsystem: "SpaceAPI.Socket", level: "error", "Listener startup failed: \(reason)")
        return false
    }

    private func posixErrorDescription() -> String {
        let code = errno
        return "\(String(cString: strerror(code))) (errno \(code))"
    }

    private static func recoverableRequestID(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dictionary = object as? [String: Any],
              let id = dictionary["id"] as? String,
              !id.isEmpty else {
            return nil
        }
        return id
    }

    private static func isPermissionDeniedResponse(_ payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let code = (error["code"] as? NSNumber)?.intValue else {
            return false
        }
        return code == SpaceAPIJSONRPCCode.permissionDenied
    }
}

private final class SpaceAPISocketClient {
    let authenticatedClient: SpaceAPIAuthenticatedClient?
    private let descriptor: Int32
    private let stateLock = NSLock()
    private let outputQueue = DispatchQueue(label: "dev.mqiu.DesktopRenamer.SpaceAPI.socket.output")
    private var closed = false
    private var queuedBytes = 0

    init(descriptor: Int32) {
        self.descriptor = descriptor
        var token = audit_token_t()
        var tokenLength = socklen_t(MemoryLayout<audit_token_t>.size)
        let status = getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &tokenLength)
        let socketError = status == 0 ? nil : errno
        guard status == 0, tokenLength == MemoryLayout<audit_token_t>.size else {
            authenticatedClient = nil
            let reason = status == 0
                ? "Unexpected local peer audit-token size \(tokenLength)."
                : "Could not read local peer audit token (errno \(socketError ?? 0))."
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceAPI.Socket",
                level: "warning",
                "Socket peer authentication could not start: \(reason)"
            )
            return
        }

        let peerToken = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        authenticatedClient = SpaceAPICodeIdentity.authenticatedClient(forAuditToken: peerToken)
        let processID = token.val.5
        if let authenticatedClient {
            let app = authenticatedClient.application
            let identityType = authenticatedClient.peerIdentity.codeHash == nil
                ? "signedRequirement"
                : "adHocCodeHash"
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceAPI.Socket",
                level: "debug",
                "Authenticated socket peer pid=\(processID) name=\(app?.name ?? "unknown") bundleID=\(app?.bundleIdentifier ?? "unknown") identityType=\(identityType)."
            )
        } else {
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceAPI.Socket",
                level: "warning",
                "Could not resolve code identity for socket peer pid=\(processID)."
            )
        }
    }

    var isClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return closed
    }

    func readExactly(_ count: Int, deadline: DispatchTime? = nil) -> Data? {
        SpaceAPISocketFraming.readExactly(count, from: descriptor, deadline: deadline)
    }

    func enqueue(_ payload: Data, authorization: @escaping () -> Bool, completion: (() -> Void)? = nil) {
        guard let frame = try? SpaceAPISocketFraming.encode(
            payload,
            maximumPayloadBytes: DesktopRenamerAPIContract.maxPayloadBytes
        ) else {
            close()
            completion?()
            return
        }

        stateLock.lock()
        guard !closed, queuedBytes + frame.count <= SpaceAPISocketServer.maximumQueuedBytes else {
            stateLock.unlock()
            close()
            completion?()
            return
        }
        queuedBytes += frame.count
        stateLock.unlock()

        outputQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            defer {
                self.stateLock.lock()
                self.queuedBytes = max(0, self.queuedBytes - frame.count)
                self.stateLock.unlock()
                completion?()
            }
            guard !self.isClosed, authorization(), self.writeAll(frame) else {
                self.close()
                return
            }
        }
    }

    func close() {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true
        stateLock.unlock()

        _ = shutdown(descriptor, SHUT_RDWR)
        outputQueue.async { [descriptor] in Darwin.close(descriptor) }
    }

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            var offset = 0
            while offset < data.count {
                let result = send(descriptor, baseAddress.advanced(by: offset), data.count - offset, 0)
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if result == 0 { return false }
                offset += result
            }
            return true
        }
    }
}
