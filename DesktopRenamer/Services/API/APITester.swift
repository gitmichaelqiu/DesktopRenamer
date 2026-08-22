import Foundation
import Combine

// Helper class for testing SpaceAPI functionality.
class APITester: ObservableObject {
    @Published var responseText: String = ""

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCurrentSpaceResponse(_:)),
            name: SpaceAPI.returnActiveSpace, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAllSpacesResponse(_:)), name: SpaceAPI.returnSpaceList,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getActiveSpace, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getSpaceList, object: nil, userInfo: nil, deliverImmediately: true)
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
}
