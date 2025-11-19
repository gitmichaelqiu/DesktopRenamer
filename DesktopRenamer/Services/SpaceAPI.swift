import Foundation
import AppKit

class SpaceAPI {
    // The name of the API. Other apps will use this to communicate.
    static let apiName = "com.gitmichaelqiu.DesktopRenamer"
    
    // Notifications used by the API
    static let requestCurrentSpaceNotification = Notification.Name(rawValue: "\(apiName).GetActiveSpace")
    static let responseCurrentSpaceNotification = Notification.Name(rawValue: "\(apiName).ReturnActiveSpace")
    
    // NEW: Notifications for getting all spaces
    static let requestAllSpacesNotification = Notification.Name(rawValue: "\(apiName).GetSpaceList")
    static let responseAllSpacesNotification = Notification.Name(rawValue: "\(apiName).ReturnSpaceList")
    
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

        // Listener for Current Space
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpaceRequest(_:)),
            name: SpaceAPI.requestCurrentSpaceNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // NEW: Listener for All Spaces
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAllSpacesRequest(_:)),
            name: SpaceAPI.requestAllSpacesNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        print("SpaceAPI listener enabled.")
    }
    
    func removeListener() {
        DistributedNotificationCenter.default().removeObserver(self, name: SpaceAPI.requestCurrentSpaceNotification, object: nil)
        DistributedNotificationCenter.default().removeObserver(self, name: SpaceAPI.requestAllSpacesNotification, object: nil)
        print("SpaceAPI listener disabled.")
    }
    
    func toggleAPIState(isEnabled: Bool) {
        if isEnabled {
            setupListener()
        } else {
            removeListener()
        }
    }
    
    // MARK: - Request Handlers
    
    @objc private func handleSpaceRequest(_ notification: Notification) {
        guard spaceManager.isAPIEnabled else { return }
        
        let spaceUUID = spaceManager.currentSpaceUUID
        let spaceName = spaceManager.getSpaceName(spaceUUID)
        let spaceNum = spaceManager.getSpaceNum(spaceUUID)
        
        let uuidToSend = (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID
        
        let userInfo: [String: Any] = [
            "spaceUUID": uuidToSend,
            "spaceName": spaceName,
            "spaceNumber": NSNumber(value: spaceNum)
        ]
        
        // Respond Locally (For internal testing)
        NotificationCenter.default.post(
            name: SpaceAPI.responseCurrentSpaceNotification,
            object: nil,
            userInfo: userInfo
        )
        
        // Respond Externally
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.responseCurrentSpaceNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    // NEW: Handle request for all spaces
    @objc private func handleAllSpacesRequest(_ notification: Notification) {
        guard spaceManager.isAPIEnabled else { return }
        
        // Map the spaces to a dictionary format
        // We use spaceManager.getSpaceName to ensure we get the correct display name (e.g., "Space 1") if customName is empty
        let spacesList = spaceManager.spaceNameDict.sorted(by: { $0.num < $1.num }).map { space -> [String: Any] in
            return [
                "spaceUUID": space.id,
                "spaceName": spaceManager.getSpaceName(space.id),
                "spaceNumber": NSNumber(value: space.num)
            ]
        }
        
        let userInfo: [String: Any] = [
            "spaces": spacesList
        ]
        
        // Respond Locally (For internal testing)
        NotificationCenter.default.post(
            name: SpaceAPI.responseAllSpacesNotification,
            object: nil,
            userInfo: userInfo
        )
        
        // Respond Externally
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.responseAllSpacesNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        print("API: Responded to request for all spaces. Count: \(spacesList.count)")
    }
}
