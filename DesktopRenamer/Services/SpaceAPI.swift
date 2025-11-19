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
        removeListener()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpaceRequest(_:)),
            name: SpaceAPI.requestCurrentSpaceNotification,
            object: nil,
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
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": isEnabled],
            deliverImmediately: true
        )
    }
    
    // MARK: - Request Handler
    
    @objc private func handleSpaceRequest(_ notification: Notification) {
        guard spaceManager.isAPIEnabled else { return }
        
        // 1. Prepare the data
        let spaceUUID = spaceManager.currentSpaceUUID
        let spaceName = spaceManager.getSpaceName(spaceUUID)
        let spaceNum = spaceManager.getSpaceNum(spaceUUID)
        
        // Ensure the UUID is not "FULLSCREEN" and is valid
        let uuidToSend = (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID
        
        // Use NSNumber for Ints to ensure DistributedNotificationCenter compatibility
        let userInfo: [String: Any] = [
            "spaceUUID": uuidToSend,
            "spaceName": spaceName,
            "spaceNumber": NSNumber(value: spaceNum)
        ]
        
        // 2. Respond LOCALLY (For the internal Test Button)
        NotificationCenter.default.post(
            name: SpaceAPI.responseCurrentSpaceNotification,
            object: nil,
            userInfo: userInfo
        )
        
        // 3. Respond EXTERNALLY (For other apps)
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.responseCurrentSpaceNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        print("API: Responded to request for space: \(spaceName)")
    }
}
