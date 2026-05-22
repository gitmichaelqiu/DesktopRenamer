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
    
    init(type: LauncherCommandType, title: String, subtitle: String, iconName: String, hasSubpage: Bool) {
        self.id = type.rawValue
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.hasSubpage = hasSubpage
    }
}
