import ApplicationServices
import Cocoa

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isAutomationGranted: Bool = false

    private init() {
        checkPermissions()
        // Listen for app becoming active to re-check permissions
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
        // Check for accessibility (we need this to detect space changes)
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)

        // Check for automation (to talk to System Events)
        let targetBundleID = "com.apple.systemevents"
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: targetBundleID)
        if let aeDesc = targetDesc.aeDesc {
            let status = AEDeterminePermissionToAutomateTarget(
                aeDesc, typeWildCard, typeWildCard, false)
            self.isAutomationGranted = (status == noErr)
        } else {
            self.isAutomationGranted = false
        }
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(axOptions)
        self.isAccessibilityGranted = trusted
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func requestAutomationPermission() {
        let targetBundleID = "com.apple.systemevents"
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: targetBundleID)
        if let aeDesc = targetDesc.aeDesc {
            let status = AEDeterminePermissionToAutomateTarget(
                aeDesc, typeWildCard, typeWildCard, true)
            self.isAutomationGranted = (status == noErr)
            openSystemSettings(type: "Privacy_Automation")
        }
    }

    func openSystemSettings(type: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
