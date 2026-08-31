import Foundation
import Combine

// Helper class for testing both compatibility and structured SpaceAPI paths.
final class APITester: NSObject, ObservableObject {
    @Published var responseText: String = ""
    @Published var structuredResponseText: String = ""

    private let distributedCenter = DistributedNotificationCenter.default()
    private var pendingStructuredRequestID: String?

    override init() {
        super.init()

        distributedCenter.addObserver(
            self, selector: #selector(handleCurrentSpaceResponse(_:)),
            name: SpaceAPI.returnActiveSpace, object: nil, suspensionBehavior: .deliverImmediately)
        distributedCenter.addObserver(
            self, selector: #selector(handleAllSpacesResponse(_:)), name: SpaceAPI.returnSpaceList,
            object: nil, suspensionBehavior: .deliverImmediately)
        distributedCenter.addObserver(
            self, selector: #selector(handleRPCResponse(_:)), name: SpaceAPI.rpcResponse,
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit {
        distributedCenter.removeObserver(self)
    }

    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        distributedCenter.postNotificationName(
            SpaceAPI.getActiveSpace, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        distributedCenter.postNotificationName(
            SpaceAPI.getSpaceList, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func sendStructuredAPIInfoRequest() {
        let requestID = UUID().uuidString
        pendingStructuredRequestID = requestID
        let request = SpaceAPIJSONRPCRequest(id: requestID, method: "getAPIInfo")
        do {
            let payload = try SpaceAPIJSONRPCCodec.encode(request)
            structuredResponseText = "Requesting structured API information..."
            distributedCenter.postNotificationName(
                SpaceAPI.rpcRequest,
                object: nil,
                userInfo: [DesktopRenamerAPIContract.payloadKey: payload],
                deliverImmediately: true
            )
        } catch {
            pendingStructuredRequestID = nil
            structuredResponseText = "Could not encode request: \(error.localizedDescription)"
        }
    }

    @objc private func handleCurrentSpaceResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo else {
                self.responseText = "Received empty response"
                return
            }
            let name = userInfo["spaceName"] as? String ?? "N/A"
            let num =
                (userInfo["spaceNumber"] as? NSNumber)?.intValue
                ?? (userInfo["spaceNumber"] as? Int) ?? -1
            let uuid = userInfo["spaceUUID"] as? String ?? "N/A"
            self.responseText = "Current Space:\nName: \(name)\n#: \(num)\nUUID: \(uuid)"
        }
    }

    @objc private func handleAllSpacesResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo,
                let spaces = userInfo["spaces"] as? [[String: Any]]
            else {
                self.responseText = "Received empty space list"
                return
            }
            var result = "All Spaces (\(spaces.count)):\n"
            for space in spaces {
                let name = space["spaceName"] as? String ?? "N/A"
                let num = (space["spaceNumber"] as? NSNumber)?.intValue ?? -1
                let uuid = (space["spaceUUID"] as? String)?.prefix(8) ?? "N/A"
                result += "#\(num): \(name) [\(uuid).. ]\n"
            }
            self.responseText = result
        }
    }

    @objc private func handleRPCResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let payload = notification.userInfo?[DesktopRenamerAPIContract.payloadKey] as? String else {
                self.structuredResponseText = "Received empty structured response"
                return
            }

            do {
                let response = try SpaceAPIJSONRPCCodec.decodeResponse(payload)
                guard response.id == self.pendingStructuredRequestID else { return }
                self.pendingStructuredRequestID = nil
                if let error = response.error {
                    self.structuredResponseText = "Structured API error \(error.code): \(error.message)"
                } else if let result = response.result,
                          let info = try? result.decode(SpaceAPIInfo.self) {
                    self.structuredResponseText = "Structured API \(info.contractVersion), JSON-RPC \(info.jsonRPCVersion)"
                } else {
                    self.structuredResponseText = "Received structured API response"
                }
            } catch {
                self.pendingStructuredRequestID = nil
                self.structuredResponseText = "Invalid structured response: \(error.localizedDescription)"
            }
        }
    }
}
