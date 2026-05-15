import ApplicationServices
import Cocoa

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false

    private init() {
        checkPermissions()
        // Re-verify permissions when the application returns to the foreground.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func checkPermissions() {
        // Accessibility check.
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(axOptions)
        self.isAccessibilityGranted = trusted
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func openSystemSettings(type: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
