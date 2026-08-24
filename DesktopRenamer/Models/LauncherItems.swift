import Foundation
import AppKit

struct SpaceGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let displayID: String
    let num: Int
    let isFullscreen: Bool
    let appPath: String?

    // Caching transformed string for performance
    let pinyinName: String
    let pinyinDisplayName: String

    init(id: String, name: String, displayName: String, displayID: String = "", num: Int, isFullscreen: Bool, appPath: String? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.displayID = displayID
        self.num = num
        self.isFullscreen = isFullscreen
        self.appPath = appPath

        let mutableName = NSMutableString(string: name)
        CFStringTransform(mutableName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinName = (mutableName as String).lowercased().replacingOccurrences(of: " ", with: "")

        let mutableDisplayName = NSMutableString(string: displayName)
        CFStringTransform(mutableDisplayName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableDisplayName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinDisplayName = (mutableDisplayName as String).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

struct WindowEntry: Identifiable, Equatable {
    let id: Int // WindowID
    let pid: Int32
    let ownerName: String
    let appPath: String
    let title: String
    let space: SpaceGroup
    let isMinimized: Bool
    let isHidden: Bool

    // Caching transformed string for performance
    let pinyinTitle: String
    let pinyinOwnerName: String

    init(id: Int, pid: Int32, ownerName: String, appPath: String, title: String, space: SpaceGroup, isMinimized: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.pid = pid
        self.ownerName = ownerName
        self.appPath = appPath
        self.title = title
        self.space = space
        self.isMinimized = isMinimized
        self.isHidden = isHidden

        let mutableTitle = NSMutableString(string: title)
        CFStringTransform(mutableTitle, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableTitle, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinTitle = (mutableTitle as String).lowercased().replacingOccurrences(of: " ", with: "")

        let mutableOwnerName = NSMutableString(string: ownerName)
        CFStringTransform(mutableOwnerName, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableOwnerName, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinOwnerName = (mutableOwnerName as String).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

enum BatchStagedActionType: Equatable {
    case move(targetSpace: SpaceGroup)
    case close
    case minimize
    case hide
    case enterFullScreen
    case exitFullScreen
    case quit
    case restore
    case restoreTo(targetSpace: SpaceGroup)

    var description: String {
        switch self {
        case .move(let space): return "→ \(space.name)"
        case .close: return "→ Close"
        case .minimize: return "→ Minimize"
        case .hide: return "→ Hide"
        case .enterFullScreen: return "→ Enter Full Screen"
        case .exitFullScreen: return "→ Exit Full Screen"
        case .quit: return "→ Quit"
        case .restore: return "→ Restore"
        case .restoreTo(let space): return "→ Restore to \(space.name)"
        }
    }
}

struct BatchStagedAction: Equatable {
    let window: WindowEntry
    let actionType: BatchStagedActionType
}

enum BatchMoveItem: Identifiable, Equatable {
    case staged(action: BatchStagedAction, index: Int)
    case unstaged(window: WindowEntry, index: Int)

    var id: String {
        switch self {
        case .staged(let action, _): return "staged_\(action.window.id)"
        case .unstaged(let window, _): return "unstaged_\(window.id)"
        }
    }

    var index: Int {
        switch self {
        case .staged(_, let index): return index
        case .unstaged(_, let index): return index
        }
    }

    static func == (lhs: BatchMoveItem, rhs: BatchMoveItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct BatchMoveSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [BatchMoveItem]
}

struct ListWindowsItem: Identifiable, Equatable {
    let window: WindowEntry
    let index: Int

    var id: String { "list_window_\(window.id)" }

    static func == (lhs: ListWindowsItem, rhs: ListWindowsItem) -> Bool {
        lhs.window.id == rhs.window.id && lhs.index == rhs.index
    }
}

struct ListWindowsSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [ListWindowsItem]
}
