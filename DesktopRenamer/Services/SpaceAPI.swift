import Foundation
import AppKit
import Combine

class SpaceAPI {
    static let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    static let getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    static let returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    static let getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    static let returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    static let apiToggleNotification = Notification.Name("\(apiPrefix).ReturnAPIState")
    
    // Use weak to avoid retain cycle (SpaceManager owns API, API shouldn't strongly own SpaceManager)
    private weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }
    
    func setupListener() {
        guard let spaceManager = spaceManager else { return }
        removeListener()
        
        let dnc = DistributedNotificationCenter.default()
        
        // 1. Listen for Requests
        dnc.addObserver(self, selector: #selector(handleActiveSpaceRequest), name: SpaceAPI.getActiveSpace, object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(handleSpaceListRequest), name: SpaceAPI.getSpaceList, object: nil, suspensionBehavior: .deliverImmediately)
        
        // 2. Observe Space Changes (Push Updates)
        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.broadcastCurrentSpace() }
            .store(in: &cancellables)
            
        spaceManager.$spaceNameDict
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSpace()
                self?.broadcastSpaceList()
            }
            .store(in: &cancellables)
            
        print("SpaceAPI: Listener Started")
    }
    
    func removeListener() {
        DistributedNotificationCenter.default().removeObserver(self)
        cancellables.removeAll()
        print("SpaceAPI: Listener Stopped")
    }
    
    // MARK: - State Management
    
    func toggleAPIState() {
        SpaceManager.isAPIEnabled.toggle()
        
        if SpaceManager.isAPIEnabled {
            setupListener()
        } else {
            removeListener()
        }
        
        // NOTIFY other apps that the API is now ON or OFF
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": SpaceManager.isAPIEnabled],
            deliverImmediately: true
        )
        print("SpaceAPI: Sent Toggle Notification -> \(SpaceManager.isAPIEnabled)")
    }
    
    // MARK: - Broadcasting
    
    private func broadcastCurrentSpace() {
        guard let sm = spaceManager, SpaceManager.isAPIEnabled else { return }
        
        let spaceUUID = sm.currentSpaceUUID
        let userInfo: [String: Any] = [
            "spaceUUID": (spaceUUID == "FULLSCREEN") ? "FULLSCREEN" : spaceUUID,
            "spaceName": sm.getSpaceName(spaceUUID),
            "spaceNumber": NSNumber(value: sm.getSpaceNum(spaceUUID))
        ]
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnActiveSpace, object: nil, userInfo: userInfo, deliverImmediately: true
        )
    }
    
    private func broadcastSpaceList() {
        guard let sm = spaceManager, SpaceManager.isAPIEnabled else { return }
        
        let list = sm.spaceNameDict.sorted(by: { $0.num < $1.num }).map { space -> [String: Any] in
            [
                "spaceUUID": space.id,
                "spaceName": sm.getSpaceName(space.id),
                "spaceNumber": NSNumber(value: space.num)
            ]
        }
        
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.returnSpaceList, object: nil, userInfo: ["spaces": list], deliverImmediately: true
        )
    }
    
    @objc private func handleActiveSpaceRequest() { broadcastCurrentSpace() }
    @objc private func handleSpaceListRequest() { broadcastSpaceList() }
}
