import Foundation

enum LauncherCommandType: String, Codable, CaseIterable {
    case switchToDesktop = "switch-to-desktop"
    case moveWindow = "move-window"
    case listWindows = "list-windows"
    case batchMoveWindows = "batch-move-windows"
    case renameCurrentSpace = "rename-current-space"
    case reloadLabels = "reload-labels"
    case toggleActiveLabel = "toggle-active-label"
    case togglePreviewLabel = "toggle-preview-label"
    case toggleActiveLabelVisibility = "toggle-active-label-visibility"
}

struct LauncherCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let type: LauncherCommandType
    let hasSubpage: Bool
    
    // Caching transformed string for performance
    let pinyinTitle: String
    let pinyinSubtitle: String
    
    init(type: LauncherCommandType, title: String, subtitle: String, iconName: String, hasSubpage: Bool) {
        self.id = type.rawValue
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.hasSubpage = hasSubpage
        
        let mutableTitle = NSMutableString(string: title)
        CFStringTransform(mutableTitle, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableTitle, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinTitle = (mutableTitle as String).lowercased().replacingOccurrences(of: " ", with: "")
        
        let mutableSubtitle = NSMutableString(string: subtitle)
        CFStringTransform(mutableSubtitle, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableSubtitle, nil, kCFStringTransformStripDiacritics, false)
        self.pinyinSubtitle = (mutableSubtitle as String).lowercased().replacingOccurrences(of: " ", with: "")
    }
}
