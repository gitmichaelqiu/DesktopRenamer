import ApplicationServices
import Cocoa
import CoreGraphics

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isEventSynthesisGranted: Bool = false
    @Published var isScreenCaptureGranted: Bool = false
    @Published private(set) var isRestarting: Bool = false

    /// Accessibility and event synthesis are separate TCC checks, but macOS
    /// presents both through the same user-facing Accessibility settings.
    /// Keep them combined for the permission requirement shown to users.
    var hasAccessibilityPermission: Bool {
        isAccessibilityGranted && isEventSynthesisGranted
    }

    /// Both services are needed before DesktopRenamer can inject events.
    var hasEventInjectionPermission: Bool {
        hasAccessibilityPermission
    }

    /// All permissions required by DesktopRenamer's core features.
    var hasAllRequiredPermissions: Bool {
        hasAccessibilityPermission && isScreenCaptureGranted
    }

    private struct PermissionSnapshot: Equatable {
        let accessibility: Bool
        let eventSynthesis: Bool
        let screenCapture: Bool
    }

    private struct ObserverRegistration {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private var lastSnapshot: PermissionSnapshot?
    private var notificationObservers: [ObserverRegistration] = []
    private var refreshWorkItem: DispatchWorkItem?
    private var refreshGeneration = 0
    private var refreshDeadline: Date?

    private init() {
        checkPermissions()
        installNotificationObservers()
    }

    deinit {
        refreshWorkItem?.cancel()
        for observer in notificationObservers {
            observer.center.removeObserver(observer.token)
        }
    }

    /// Re-reads TCC state immediately and keeps checking while the permission
    /// UI is in use so a change made in System Settings has time to propagate
    /// to this process.
    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
            return
        }

        checkPermissions()
        scheduleRefresh(
            duration: 90.0,
            interval: 0.5,
            reason: "manual refresh"
        )
    }

    /// Performs a synchronous read when already on the main thread. TCC can
    /// update while the app is inactive, so callers should use `refresh()`
    /// when they are reacting to an external settings change.
    func checkPermissions() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkPermissions()
            }
            return
        }

        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        let snapshot = PermissionSnapshot(
            accessibility: AXIsProcessTrustedWithOptions(axOptions),
            eventSynthesis: CGPreflightPostEventAccess(),
            screenCapture: CGPreflightScreenCaptureAccess()
        )

        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        isAccessibilityGranted = snapshot.accessibility
        isEventSynthesisGranted = snapshot.eventSynthesis
        isScreenCaptureGranted = snapshot.screenCapture

        DiagnosticEventLog.shared.record(
            subsystem: "PermissionManager",
            level: "info",
            "Permission state changed: accessibility=\(snapshot.accessibility), eventSynthesis=\(snapshot.eventSynthesis), screenCapture=\(snapshot.screenCapture)"
        )
    }

    func requestAccessibilityPermission() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestAccessibilityPermission()
            }
            return
        }

        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(axOptions)
        _ = CGRequestPostEventAccess()
        checkPermissions()
        openSystemSettings(type: "Privacy_Accessibility")
        scheduleRefresh(
            duration: 90.0,
            interval: 0.5,
            reason: "Accessibility settings opened"
        )
    }

    func requestScreenCapturePermission() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestScreenCapturePermission()
            }
            return
        }

        _ = CGRequestScreenCaptureAccess()
        checkPermissions()
        openSystemSettings(type: "Privacy_ScreenCapture")
        scheduleRefresh(
            duration: 90.0,
            interval: 0.5,
            reason: "Screen Recording settings opened"
        )
    }

    /// Relaunches this exact application bundle so macOS can apply newly
    /// granted permissions to a fresh process. The current process remains
    /// available if launching the replacement fails.
    func restartApplication() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.restartApplication()
            }
            return
        }

        guard !isRestarting else { return }

        let applicationURL = Bundle.main.bundleURL.standardizedFileURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        isRestarting = true

        DiagnosticEventLog.shared.record(
            subsystem: "PermissionManager",
            level: "info",
            "Restarting application from \(applicationURL.path)"
        )

        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) {
            [weak self] application, error in
            DispatchQueue.main.async {
                guard error == nil, application != nil else {
                    self?.isRestarting = false
                    DiagnosticEventLog.shared.record(
                        subsystem: "PermissionManager",
                        level: "error",
                        "Application restart failed: \(error?.localizedDescription ?? "no application returned")"
                    )
                    return
                }

                NSApp.terminate(nil)
            }
        }
    }

    func openSystemSettings(type: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.openSystemSettings(type: type)
            }
            return
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)") {
            _ = NSWorkspace.shared.open(url)
        }
        scheduleRefresh(
            duration: 90.0,
            interval: 0.5,
            reason: "System Settings opened"
        )
    }

    private func installNotificationObservers() {
        let applicationCenter = NotificationCenter.default
        notificationObservers.append(
            ObserverRegistration(
                center: applicationCenter,
                token: applicationCenter.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleRefresh(
                        duration: 4.0,
                        interval: 0.25,
                        reason: "application became active"
                    )
                }
            )
        )
        notificationObservers.append(
            ObserverRegistration(
                center: applicationCenter,
                token: applicationCenter.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleRefresh(
                        duration: 90.0,
                        interval: 0.5,
                        reason: "application resigned active status"
                    )
                }
            )
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationObservers.append(
            ObserverRegistration(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleRefresh(
                        duration: 4.0,
                        interval: 0.25,
                        reason: "workspace application activated"
                    )
                }
            )
        )
        notificationObservers.append(
            ObserverRegistration(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleRefresh(
                        duration: 4.0,
                        interval: 0.25,
                        reason: "workspace application terminated"
                    )
                }
            )
        )
        notificationObservers.append(
            ObserverRegistration(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleRefresh(
                        duration: 10.0,
                        interval: 0.5,
                        reason: "system wake"
                    )
                }
            )
        )
    }

    private func scheduleRefresh(
        duration: TimeInterval,
        interval: TimeInterval,
        reason: String
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleRefresh(
                    duration: duration,
                    interval: interval,
                    reason: reason
                )
            }
            return
        }

        let requestedDeadline = Date().addingTimeInterval(duration)
        if let refreshDeadline, refreshDeadline >= requestedDeadline {
            checkPermissions()
            return
        }

        refreshWorkItem?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshDeadline = requestedDeadline
        DiagnosticEventLog.shared.record(
            subsystem: "PermissionManager",
            level: "debug",
            "Scheduled permission refresh: reason=\(reason), duration=\(String(format: "%.1f", duration))s"
        )
        checkPermissions()
        scheduleRefreshStep(
            generation: generation,
            interval: interval
        )
    }

    private func scheduleRefreshStep(
        generation: Int,
        interval: TimeInterval
    ) {
        guard generation == refreshGeneration,
              let deadline = refreshDeadline else {
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            refreshWorkItem = nil
            refreshDeadline = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.refreshGeneration else {
                return
            }

            self.refreshWorkItem = nil
            self.checkPermissions()
            self.scheduleRefreshStep(
                generation: generation,
                interval: interval
            )
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + min(interval, remaining),
            execute: workItem
        )
    }

}
