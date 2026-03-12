import SwiftUI
import ServiceManagement
import Combine
import Cocoa

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalSelector = #selector(getter: canCollapse)
        let swizzledSelector = #selector(getter: swizzledCanCollapse)

        guard
            let originalMethod = class_getInstanceMethod(NSSplitViewItem.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledSelector)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        if let window = viewController.view.window,
           window.identifier?.rawValue == "SettingsWindow" {
            return false
        }
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        _ = swizzler
    }
}

@available(macOS 14.0, *)
extension View {
    func removeSidebarToggle() -> some View {
        toolbar(removing: .sidebarToggle)
            .toolbar {
                Color.clear
            }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager!
    var gestureManager: GestureManager!
    
    private var cancellables = Set<AnyCancellable>()
    var splashWindowController: NSWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        NSApp.setActivationPolicy(.accessory)
        
        let hasInitialized = UserDefaults.standard.bool(forKey: "HasInitializedDefaults")
        if !hasInitialized {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "HasInitializedDefaults")
        }
        
        // Show splash screen on first launch
        let hasSeenSplash = UserDefaults.standard.bool(forKey: "hasSeenSplashScreen")
        if !hasSeenSplash {
            showSplashScreen()
        }
        
        self.hotkeyManager = HotkeyManager()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.spaceManager = SpaceManager()
            self.gestureManager = GestureManager(spaceManager: self.spaceManager)
            
            self.statusBarController = StatusBarController(
                spaceManager: self.spaceManager,
                hotkeyManager: self.hotkeyManager,
                gestureManager: self.gestureManager
            )
            
            self.setupHotkeyBindings()
        }

        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
                }
            }
        }
    }
    
    private func setupHotkeyBindings() {
        hotkeyManager.switchLeftTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.spaceManager.switchToPreviousSpace() }
            .store(in: &cancellables)
            
        hotkeyManager.switchRightTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.spaceManager.switchToNextSpace() }
            .store(in: &cancellables)
            
        hotkeyManager.moveWindowNextTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.spaceManager.moveActiveWindowToNextSpace() }
            .store(in: &cancellables)
            
        hotkeyManager.moveWindowPreviousTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.spaceManager.moveActiveWindowToPreviousSpace() }
            .store(in: &cancellables)
            
        hotkeyManager.moveWindowNumberTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] number in self?.spaceManager.moveActiveWindowToSpace(number: number) }
            .store(in: &cancellables)
    }
    
    func showSplashScreen(on parentWindow: NSWindow? = nil) {
        if let existing = splashWindowController {
            if let window = existing.window, window.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        let splashView = SplashView { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasSeenSplashScreen")
            if let parent = parentWindow, let sheet = self?.splashWindowController?.window {
                parent.endSheet(sheet)
            } else {
                self?.splashWindowController?.close()
                self?.splashWindowController = nil
            }
        }
        
        let hostingController = NSHostingController(rootView: splashView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        
        let windowController = NSWindowController(window: window)
        self.splashWindowController = windowController
        
        if let parent = parentWindow {
            parent.beginSheet(window) { _ in
                self.splashWindowController = nil
            }
        } else {
            window.center()
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        spaceManager?.prepareForTermination()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.openSettingsWindow()
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "desktoprenamer",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host == "switch",
              let queryItems = components.queryItems
        else { return }

        // Priority 1: UUID (Unique across all displays)
        if let uuid = queryItems.first(where: { $0.name == "uuid" })?.value {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let manager = self.spaceManager else { return }
                if let space = manager.spaceNameDict.first(where: { $0.id == uuid }) {
                    manager.switchToSpace(space)
                }
            }
            return
        }
        
        // If switch by UUID failed, try by number (Legacy / Ambiguous on multi-display)
        if let numString = queryItems.first(where: { $0.name == "num" })?.value,
           let spaceNum = Int(numString) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let manager = self.spaceManager else { return }
                // Fallback: This might pick the wrong display if numbers are duplicated (1, 1).
                // But strictly speaking, it picks the *first* match.
                if let space = manager.spaceNameDict.first(where: { $0.num == spaceNum }) {
                    manager.switchToSpace(space)
                }
            }
        }
    }
}

@main
struct DesktopRenamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        NSSplitViewItem.swizzle()
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
