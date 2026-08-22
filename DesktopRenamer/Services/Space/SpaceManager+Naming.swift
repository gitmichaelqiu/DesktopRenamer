import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    func getSpaceNum(_ spaceUUID: String) -> Int {
        if spaceUUID == "FULLSCREEN" { return 0 }
        if let space = spaceNameDict.first(where: { $0.id == spaceUUID }) { return space.num }
        return -1
    }
    
    private static func normalizeDisplayID(_ id: String, mainUUID: String?) -> String {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.isEmpty || cleanId.uppercased() == "MAIN" || cleanId.uppercased() == "UNKNOWN" {
            return mainUUID?.uppercased() ?? "MAIN"
        }
        return cleanId.uppercased()
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if spaceUUID == "FULLSCREEN" { return "Fullscreen" }
        
        let matched = spaceNameDict.first(where: { $0.id == spaceUUID })
        var ret = matched?.customName
        if ret == nil || ret == "" {
            if matched?.isFullscreen == true {
                ret = matched?.appName ?? "Fullscreen"
            } else {
                ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
            }
        }
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            UserDefaults.standard.removeObject(forKey: SpaceManager.nameCacheKey)
            UserDefaults.standard.removeObject(forKey: SpaceManager.indexCacheKey)
            self.spaceNameDict.removeAll()
            self.nameCache.removeAll()
            self.indexCache.removeAll()
            self.saveData()
            self.refreshSpaceState()
            self.scheduleWidgetUpdate()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            // Prevent renaming fullscreen spaces manually if needed, or just let it be overwritten on next refresh.
            // But UI filters them out, so this is mostly safe.
            spaceNameDict[index].customName = trimmedName
            let space = spaceNameDict[index]
            
            if !space.isFullscreen {
                let desktopsOnSameDisplay = spaceNameDict.filter { $0.displayID == space.displayID && !$0.isFullscreen }
                if let dIndex = desktopsOnSameDisplay.firstIndex(where: { $0.id == space.id }) {
                    let desktopNum = dIndex + 1
                    let indexKey = "\(space.displayID)|Desktop|\(desktopNum)"
                    let legacyIndexKey = "\(space.displayID)|\(space.num)"
                    
                    if trimmedName.isEmpty {
                        nameCache.removeValue(forKey: spaceUUID)
                        indexCache.removeValue(forKey: indexKey)
                        indexCache.removeValue(forKey: legacyIndexKey)
                    } else {
                        nameCache[spaceUUID] = trimmedName
                        indexCache[indexKey] = trimmedName
                    }
                }
            }
            saveData()
            scheduleWidgetUpdate()
        }
    }
    
}
