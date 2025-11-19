import Foundation
import AppKit

class SpaceAPI {
    // The name of the API. Other apps will use this to communicate.
    static let apiName = "com.gitmichaelqiu.DesktopRenamer.SpaceAPI"
    
    // Notifications used by the API
    static let requestCurrentSpaceNotification = Notification.Name(rawValue: "\(apiName).RequestCurrentSpace")
    static let responseCurrentSpaceNotification = Notification.Name(rawValue: "\(apiName).ResponseCurrentSpace")
    static let apiToggleNotification = Notification.Name(rawValue: "\(apiName).APIToggleState")
    
    private let spaceManager: SpaceManager
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        
        // Listen for requests only if the API is enabled
        if spaceManager.isAPIEnabled {
            setupListener()
        }
    }
    
    // MARK: - API Toggle and Listener Management
    
    func setupListener() {
        // Register to receive current space requests from other processes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpaceRequest(_:)),
            name: SpaceAPI.requestCurrentSpaceNotification,
            object: nil
        )
        print("SpaceAPI listener enabled.")
    }
    
    func removeListener() {
        DistributedNotificationCenter.default().removeObserver(self, name: SpaceAPI.requestCurrentSpaceNotification, object: nil)
        print("SpaceAPI listener disabled.")
    }
    
    func toggleAPIState(isEnabled: Bool) {
        if isEnabled {
            setupListener()
        } else {
            removeListener()
        }
        
        // Broadcast the API state change to all listeners
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": isEnabled],
            deliverImmediately: true
        )
    }
    
    // MARK: - Request Handler
    
    @objc private func handleSpaceRequest(_ notification: Notification) {
        // Only respond if the API is enabled
        guard spaceManager.isAPIEnabled else { return }
        
        // 1. Prepare the data
        let spaceUUID = spaceManager.currentSpaceUUID
        let spaceName = spaceManager.getSpaceName(spaceUUID)
        let spaceNum = spaceManager.getSpaceNum(spaceUUID)
        
        // Ensure the UUID is not "FULLSCREEN" and is valid, although we provide the name "Fullscreen"
        let uuidToSend = (spaceUUID == "FULLSCREEN") ? "" : spaceUUID
        
        let userInfo: [String: Any] = [
            "spaceUUID": uuidToSend,
            "spaceName": spaceName,
            "spaceNumber": spaceNum
        ]
        
        // 2. Respond via DistributedNotificationCenter
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.responseCurrentSpaceNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}
