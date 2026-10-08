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

    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "dev.mqiu.DesktopRenamer.SpaceAPI.socket.accept")
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clients: [ObjectIdentifier: SpaceAPISocketClient] = [:]
    private var accessController: SpaceAPIAccessController?
    private var requestHandler: ((String, SpaceAPIPeerIdentity?, @escaping (String) -> Void) -> Void)?

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listenerDescriptor >= 0
    }

    @discardableResult
    func start(
        accessController: SpaceAPIAccessController,
        requestHandler: @escaping (String, SpaceAPIPeerIdentity?, @escaping (String) -> Void) -> Void
    ) -> Bool {
        stateLock.lock()
        guard listenerDescriptor < 0 else {
            self.accessController = accessController
            self.requestHandler = requestHandler
            stateLock.unlock()
            closeUnauthorizedConnections()
            return true
        }
        stateLock.unlock()

        let path = Self.endpoint.path
        var address = sockaddr_un()
        let pathBufferCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count + 1 <= pathBufferCapacity else {
            return false
        }
        guard prepareSocketPath(path) else { return false }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
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
        guard bindStatus == 0,
              chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              listen(descriptor, Int32(Self.maximumConnectedClients)) == 0 else {
            Darwin.close(descriptor)
            unlink(path)
            return false
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: acceptQueue)
        var socketInfo = stat()
        guard lstat(path, &socketInfo) == 0 else {
            Darwin.close(descriptor)
            unlink(path)
            return false
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
            SpaceAPIAccessController.identity(forAuditToken: client.auditToken)
        }
        for client in authorizedClients {
            client.enqueue(data, authorization: { [weak self, weak client] in
                guard let self, let client else { return false }
                return self.isAuthorized(client.auditToken)
            })
        }
    }

    func closeUnauthorizedConnections() {
        stateLock.lock()
        let activeClients = Array(clients.values)
        stateLock.unlock()

        for client in activeClients where !isAuthorized(client.auditToken) {
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
            let controller = accessController
            stateLock.unlock()
            if controller?.isRestricted == true, !isAuthorized(client.auditToken) {
                let denial = SpaceAPIJSONRPCCodec.errorResponse(
                    id: nil,
                    code: SpaceAPIJSONRPCCode.permissionDenied,
                    message: "This app is not approved to use SpaceAPI."
                )
                if let payload = try? SpaceAPIJSONRPCCodec.encode(denial) {
                    client.enqueue(Data(payload.utf8), authorization: { true }) { client.close() }
                } else {
                    client.close()
                }
                continue
            }

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

            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak client] in
                guard let self, let client else { return }
                self.run(client)
            }
        }
    }

    private func run(_ client: SpaceAPISocketClient) {
        defer {
            client.close()
            remove(client)
        }

        while !client.isClosed {
            guard let header = client.readExactly(SpaceAPISocketFraming.headerLength) else { return }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= DesktopRenamerAPIContract.maxPayloadBytes else {
                client.close()
                return
            }
            guard let payload = client.readExactly(Int(length)) else { return }
            guard let text = String(data: payload, encoding: .utf8) else {
                sendError(to: client, id: nil, code: SpaceAPIJSONRPCCode.parseError, message: "Request is not valid UTF-8.")
                continue
            }

            guard isAuthorized(client.auditToken) else {
                sendError(
                    to: client,
                    id: Self.recoverableRequestID(from: text),
                    code: SpaceAPIJSONRPCCode.permissionDenied,
                    message: "This app is not approved to use SpaceAPI."
                )
                return
            }

            stateLock.lock()
            let handler = requestHandler
            stateLock.unlock()
            guard let handler else { return }

            let semaphore = DispatchSemaphore(value: 0)
            handler(text, SpaceAPIAccessController.identity(forAuditToken: client.auditToken)) { [weak self, weak client] response in
                guard let self, let client else {
                    semaphore.signal()
                    return
                }
                client.enqueue(Data(response.utf8), authorization: { [weak self, weak client] in
                    guard let self, let client else { return false }
                    return self.isAuthorized(client.auditToken)
                }) {
                    semaphore.signal()
                }
            }
            if semaphore.wait(timeout: .now() + Self.clientTimeoutSeconds) == .timedOut {
                return
            }
        }
    }

    private func sendError(to client: SpaceAPISocketClient, id: String?, code: Int, message: String) {
        let response = SpaceAPIJSONRPCCodec.errorResponse(id: id, code: code, message: message)
        guard let payload = try? SpaceAPIJSONRPCCodec.encode(response) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        client.enqueue(Data(payload.utf8), authorization: { [weak self, weak client] in
            guard let self, let client else { return false }
            return self.isAuthorized(client.auditToken)
        }) {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func isAuthorized(_ auditToken: Data) -> Bool {
        stateLock.lock()
        let controller = accessController
        stateLock.unlock()
        guard let controller else { return false }
        return controller.isAuthorized(SpaceAPIAccessController.identity(forAuditToken: auditToken))
    }

    private func remove(_ client: SpaceAPISocketClient) {
        stateLock.lock()
        clients.removeValue(forKey: ObjectIdentifier(client))
        stateLock.unlock()
    }

    private func prepareSocketPath(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK,
                  info.st_uid == getuid(),
                  unlink(path) == 0 else {
                return false
            }
        } else if errno != ENOENT {
            return false
        }
        return true
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
}

private final class SpaceAPISocketClient {
    let auditToken: Data
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
        auditToken = status == 0 && tokenLength == MemoryLayout<audit_token_t>.size
            ? Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
            : Data()
    }

    var isClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return closed
    }

    func readExactly(_ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let result = data.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return recv(descriptor, baseAddress.advanced(by: offset), count - offset, 0)
            }
            if result == 0 { return nil }
            if result < 0 {
                if errno == EINTR { continue }
                return nil
            }
            offset += result
        }
        return data
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
