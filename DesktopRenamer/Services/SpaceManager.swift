import Foundation
import AppKit
import SwiftUI

let POLL_INTERVAL = 0.8

class SpaceManager: ObservableObject {
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let isStableEnabledKey = "com.michaelqiu.desktoprenamer.isstableenabled"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published var spaceNameDict: [DesktopSpace] = []
    
    static var isAPIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isAPIEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isAPIEnabledKey) }
    }
    static var isStableEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isStableEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStableEnabledKey) }
    }
    
    private var pollingTimer: Timer?
    
    public var currentTotalSpace = 0
    
    // Keep reference to API
    public var spaceAPI: SpaceAPI?
    
    init() {
        loadSavedSpaces()
        
        // Initialize API
        self.spaceAPI = SpaceAPI(spaceManager: self)
        
        // Set initial state based on saved setting
        if SpaceManager.isAPIEnabled {
            self.spaceAPI?.setupListener()
            
            DistributedNotificationCenter.default().postNotificationName(
                SpaceAPI.apiToggleNotification,
                object: nil,
                userInfo: ["isEnabled": true],
                deliverImmediately: true
            )
            print("SpaceAPI: Sent Toggle Notification -> true")
        } else {
            self.spaceAPI?.removeListener()
        }
        
        SpaceHelper.startMonitoring { [weak self] newSpaceUUID in
            self?.handleSpaceChange(newSpaceUUID)
        }
        
        if SpaceManager.isStableEnabled {
            startPolling()
        }
    }
    
    func togglePolling() {
        SpaceManager.isStableEnabled.toggle()
        
        if SpaceManager.isStableEnabled {
            startPolling()
        } else {
            stopPolling()
        }
    }
    
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(POLL_INTERVAL), repeats: true) { [weak self] _ in
            self?.pollCurrentSpace()
        }
        // Add the timer to the common run loop mode to ensure it fires reliably
        if let timer = pollingTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func pollCurrentSpace() {
        SpaceHelper.getSpaceUUID { [weak self] newSpaceUUID in
            self?.handleSpaceChange(newSpaceUUID)
        }
    }
    
    func prepareForTermination() {
        print("SpaceManager: Shutting down...")
        stopPolling() // Stop the timer
        // Explicitly send "False" notification
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": false],
            deliverImmediately: true
        )
        print("SpaceAPI: Sent Toggle Notification -> false")
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
        stopPolling()
    }
    
    private func handleSpaceChange(_ newSpaceUUID: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(newSpaceUUID) }
            return
        }
        
        guard currentSpaceUUID != newSpaceUUID else {
            return
        }

        currentSpaceUUID = newSpaceUUID // Publishes change and triggers API update
        
        if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
            currentTotalSpace += 1
            spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
            saveSpaces()
        }
    }
    
    private func loadSavedSpaces() {
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
            currentTotalSpace = spaceNameDict.count
        }
    }
    
    public func saveSpaces() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    func getSpaceNum(_ spaceUUID: String) -> Int {
        if spaceUUID == "FULLSCREEN" { return 0 }
        return spaceNameDict.first(where: { $0.id == spaceUUID })?.num ?? -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if spaceUUID == "FULLSCREEN" { return "Fullscreen" }
        var ret = spaceNameDict.first(where: {$0.id == spaceUUID})?.customName
        if ret == nil || ret == "" {
            ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
        }
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            self.currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            
            // Re-identify the current space after reset
            SpaceHelper.getSpaceUUID { spaceUUID in
                self.currentSpaceUUID = spaceUUID
                // Call handleSpaceChange which will ensure the current space is re-added
                // and the API is notified of the fresh state.
                self.handleSpaceChange(spaceUUID)
            }
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = newName
            saveSpaces()
        }
    }
}
