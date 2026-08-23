import ApplicationServices

extension SpaceHelper {
    @discardableResult
    static func closeWindow(_ window: AXUIElement) -> Bool {
        var closeButtonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXCloseButtonAttribute as CFString,
            &closeButtonRef
        ) == .success,
        let closeButtonRef,
        CFGetTypeID(closeButtonRef) == AXUIElementGetTypeID(),
        let closeButton = closeButtonRef as? AXUIElement
        else {
            return false
        }

        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }
}
