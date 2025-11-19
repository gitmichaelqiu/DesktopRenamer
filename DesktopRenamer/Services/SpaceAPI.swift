import Foundation
import AppKit
import Combine // REQUIRED: Import Combine to watch for changes

class SpaceAPI {
    // MARK: - Final API Constants
    static let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    static let getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    static let returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    
    static let getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    static let returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    
    static let apiToggleNotification = Notification.Name("\(apiPrefix).APIToggleState")
    
    private let spaceManager: SpaceManager
    private var cancellables = Set<AnyCancellable>() // Store the observer
    
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
        
        // 1. Listen for External Requests (Pull)
        dnc.addObserver(
            self,
            selector: #selector(handleActiveSpaceRequest(_:)),
            name: SpaceAPI.getActiveSpace,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        dnc.addObserver(
            self,
            selector: #selector(handleSpaceListRequest(_:)),
            name: SpaceAPI.getSpaceList,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 2. Listen for Internal Changes (Push)
        // This is the missing piece: When SpaceManager changes the space, we broadcast it.
        spaceManager.$currentSpaceUUID
            .dropFirst() // Ignore the initial value on setup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
            }
            .store(in: &cancellables)
            
        // Also listen for name changes (renaming a space)
        spaceManager.$spaceNameDict
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
                self?.broadcastSpaceList() // Also update list if names change
            }
            .store(in: &cancellables)
        
        print("SpaceAPI: Listening enabled (Pull & Push)")
    }
    
    func removeListener() {
        DistributedNotificationCenter.default().removeObserver(self)
        cancellables.removeAll() // Stop watching internal changes
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
    
    // MARK: - Broadcasting Logic
    
    // Shared function used by both the Request Handler and the Auto-Broadcaster
    private func broadcastCurrentSpace() {
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
        
        // Post "ReturnActiveSpace" to the system
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnActiveSpace,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        print("SpaceAPI: Broadcasted Active Space -> \(spaceName)")
    }
    
    private func broadcastSpaceList() {
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
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnSpaceList,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    // MARK: - Request Handlers
    
    @objc private func handleActiveSpaceRequest(_ notification: Notification) {
        // Just trigger the broadcast function
        broadcastCurrentSpace()
    }
    
    @objc private func handleSpaceListRequest(_ notification: Notification) {
        broadcastSpaceList()
        print("SpaceAPI: Replied to Space List Request")
    }
}
