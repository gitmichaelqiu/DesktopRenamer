import ApplicationServices

extension SpaceHelper {
    enum WindowAccessibilityAction {
        case close
        case minimize
        case restore
        case enterFullScreen
        case exitFullScreen
    }

    @discardableResult
    static func performWindowAction(
        _ action: WindowAccessibilityAction,
        on window: AXUIElement
    ) -> Bool {
        let succeeded: Bool
        switch action {
        case .close:
            succeeded = closeWindow(window)
        case .minimize:
            succeeded = setWindowAttribute(kAXMinimizedAttribute, value: true, on: window)
        case .restore:
            succeeded = setWindowAttribute(kAXMinimizedAttribute, value: false, on: window)
        case .enterFullScreen:
            succeeded = setWindowAttribute("AXFullScreen", value: true, on: window)
        case .exitFullScreen:
            succeeded = setWindowAttribute("AXFullScreen", value: false, on: window)
        }

        if !succeeded {
            DiagnosticEventLog.shared.record(
                subsystem: "Accessibility",
                level: "error",
                "Window action failed: " + actionDescription(action) + "."
            )
        }
        return succeeded
    }

    private static func actionDescription(_ action: WindowAccessibilityAction) -> String {
        switch action {
        case .close: return "close"
        case .minimize: return "minimize"
        case .restore: return "restore"
        case .enterFullScreen: return "enter fullscreen"
        case .exitFullScreen: return "exit fullscreen"
        }
    }

    @discardableResult
    private static func setWindowAttribute(
        _ attribute: String,
        value: Bool,
        on window: AXUIElement
    ) -> Bool {
        AXUIElementSetAttributeValue(window, attribute as CFString, value as CFTypeRef) == .success
    }

    @discardableResult
    static func closeWindow(_ window: AXUIElement) -> Bool {
        var closeButtonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXCloseButtonAttribute as CFString,
            &closeButtonRef
        ) == .success,
        let closeButtonRef,
        CFGetTypeID(closeButtonRef) == AXUIElementGetTypeID()
        else {
            return false
        }

        let closeButton = unsafeBitCast(closeButtonRef, to: AXUIElement.self)
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }
}
