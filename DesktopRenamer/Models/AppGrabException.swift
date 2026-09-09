import Foundation

struct AppGrabException: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let appName: String
    var grabOffsetX: Double
    var grabOffsetY: Double
    var dragBeforeSwitch: Bool?

    var shouldDragBeforeSwitch: Bool {
        dragBeforeSwitch ?? false
    }

    init(bundleIdentifier: String, appName: String, grabOffsetX: Double, grabOffsetY: Double, dragBeforeSwitch: Bool? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.grabOffsetX = grabOffsetX
        self.grabOffsetY = grabOffsetY
        self.dragBeforeSwitch = dragBeforeSwitch
    }
}
