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
    
    deinit {
        removeListener()
    }
    
    // MARK: - API Toggle and Listener Management
    
    func setupListener() {
        // Check if already observing to prevent duplicates (though DistributedNotificationCenter handles this well)
        removeListener()

        // FIXED: Added suspensionBehavior: .deliverImmediately
        // This ensures the app responds even if it is in the background/menu bar mode.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpaceRequest(_:)),
            name: SpaceAPI.requestCurrentSpaceNotification,
            object: nil, // Listen for any object sending this name
            suspensionBehavior: .deliverImmediately
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
        
        // Ensure the UUID is not "FULLSCREEN" and is valid
        let uuidToSend = (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID
        
        // Note: UserInfo in DistributedNotificationCenter must be Property List objects (String, Number, Date, etc)
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
        
        print("API: Responded to request for space: \(spaceName)")
    }
}
