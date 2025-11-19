import Foundation
import AppKit

class SpaceAPI {
    // MARK: - Final API Constants
    // Prefix: com.michaelqiu.DesktopRenamer
    static let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    // Notifications
    static let getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    static let returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    
    static let getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    static let returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    
    static let apiToggleNotification = Notification.Name("\(apiPrefix).APIToggleState")
    
    private let spaceManager: SpaceManager
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        if spaceManager.isAPIEnabled {
            setupListener()
        }
    }
    
    deinit {
        removeListener()
    }
    
    // MARK: - Listener Management
    
    func setupListener() {
        removeListener()
        
        let dnc = DistributedNotificationCenter.default()
        
        // Listen for "GetActiveSpace"
        dnc.addObserver(
            self,
            selector: #selector(handleActiveSpaceRequest(_:)),
            name: SpaceAPI.getActiveSpace,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // Listen for "GetSpaceList"
        dnc.addObserver(
            self,
            selector: #selector(handleSpaceListRequest(_:)),
            name: SpaceAPI.getSpaceList,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        print("SpaceAPI: Listening for \(SpaceAPI.getActiveSpace.rawValue)")
    }
    
    func removeListener() {
        DistributedNotificationCenter.default().removeObserver(self)
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
    
    // MARK: - Request Handlers
    
    @objc private func handleActiveSpaceRequest(_ notification: Notification) {
        guard spaceManager.isAPIEnabled else { return }
        
        let spaceUUID = spaceManager.currentSpaceUUID
        let spaceName = spaceManager.getSpaceName(spaceUUID)
        let spaceNum = spaceManager.getSpaceNum(spaceUUID)
        
        // Ensure non-nil UUID
        let uuidToSend = (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID
        
        let userInfo: [String: Any] = [
            "spaceUUID": uuidToSend,
            "spaceName": spaceName,
            "spaceNumber": NSNumber(value: spaceNum)
        ]
        
        // Post "ReturnActiveSpace"
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnActiveSpace,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        print("SpaceAPI: Sent ReturnActiveSpace")
    }
    
    @objc private func handleSpaceListRequest(_ notification: Notification) {
        guard spaceManager.isAPIEnabled else { return }
        
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
        
        // Post "ReturnSpaceList"
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnSpaceList,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        print("SpaceAPI: Sent ReturnSpaceList (\(spacesList.count) spaces)")
    }
}
