import SwiftUI
import UniformTypeIdentifiers

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var labelManager: SpaceLabelManager
    @StateObject private var permissionManager = PermissionManager.shared
    
    @State private var showingAddExceptionSheet = false
    @State private var editingException: AppGrabException? = nil
    
    var body: some View {
        SettingsContainer(.sswitch) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts", helperText: "If you want to use Control + Arrow, disable the system's one in Settings → Keyboard → Keyboard Shortcuts... → Mission Control.") {
                    
                    SettingsRow(
                        "Switch to previous space",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission.",
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchLeft))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchLeft)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchLeft)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchLeft))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow(
                        "Switch to next space",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchRight))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchRight)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchRight)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchRight))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow(
                        "Switch to space number",
                        helperText: "Press modifiers and a number to set the shortcut."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchSpaceNumber))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchSpaceNumber)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchSpaceNumber)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchSpaceNumber))
                        }
                    }
                }
                
                SettingsSection(nil) {
                    SettingsRow("Move window to previous space") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowPrevious))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowPrevious)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowPrevious)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowPrevious))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to next space") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNext))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNext)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNext)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNext))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to space number", helperText: "Press modifiers and a number to set the shortcut.") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNumber))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNumber)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNumber)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNumber))
                        }
                    }   
                }

                SettingsSection(nil) {
                    SettingsRow("Move window to previous display") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowPreviousDisplay))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowPreviousDisplay)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowPreviousDisplay)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowPreviousDisplay))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to next display") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNextDisplay))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNextDisplay)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNextDisplay)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNextDisplay))
                        }
                    }
                }

                SettingsSection(nil) {
                    SettingsRow("Toggle lock for current space",
                        helperText: "When a space switch is triggered by opening the window of an app, move that window back to the original space. This way, you are always focused in the locked space.",
                        demoVideoName: "LockSpace"
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .toggleLock))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .toggleLock)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .toggleLock)
                            }
                            .disabled(hotkeyManager.isDefault(for: .toggleLock))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Restore windows moved by lock",
                        helperText: "Restore windows moved by lock to the last space that windows are manually assigned to."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .restoreWindows))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .restoreWindows)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .restoreWindows)
                            }
                            .disabled(hotkeyManager.isDefault(for: .restoreWindows))
                        }
                    }
                }
                
                // Gesture-based switching configuration.
                SettingsSection("Trackpad Switch Gesture Override") {
                    SettingsRow(
                        "Enable switch gesture override",
                        helperText:
                            "Replaces system switch gestures with instant space switching.\n\nRequired: You must disable 'Swipe between full screen apps' in System Settings → Trackpad → More Gestures or change to different number of fingers to prevent conflicts.\n\nNotice, you must click at the fullscreen app to make it active to avoid issues when leaving the app.",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission.",
                        demoVideoName: "SwitchOverride"
                    ) {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
                        Divider()     

                        SettingsRow(
                            "Instant switch without animations",
                            helperText:
                                "Bypasses the macOS sliding animation using synthetic high-velocity gestures.\n\nRequires 'Swipe between full-screen applications' enabled in System Settings → Trackpad.\n\nRecommended: Disable 'Automatically rearrange spaces based on most recent use' in Desktop & Dock settings to prevent miscalculations.",
                            warningText: permissionManager.isAccessibilityGranted
                            ? nil : "Requires Accessibility permission."
                        ) {
                            Toggle("", isOn: $spaceManager.instantSpaceSwitch)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider()

                        SettingsRow("Gesture type", helperText: "When set to 3 fingers, you can still use 4 fingers to trigger native swipe.") {
                            Picker("", selection: $gestureManager.fingerCount) {
                                Text("3 Fingers").tag(3)
                                Text("4 Fingers").tag(4)
                            }
                            .labelsHidden()
                        }

                        Divider()
                        
                        SettingsRow("Switch display with") {
                            Picker("", selection: $gestureManager.switchOverride) {
                                Text("Cursor").tag(GestureManager.SwitchOverrideMode.cursor)
                                Text("Active Window").tag(
                                    GestureManager.SwitchOverrideMode.activeWindow)
                            }
                            .labelsHidden()
                        }
                        
                        Divider()
                        
                        SliderSettingsRow(
                            "Switch override threshold",
                            helperText: "Controls how much distance the fingers have to move before switching the desktop.",
                            value: $gestureManager.swipeThreshold,
                            range: 0.05...0.50,
                            defaultValue: 0.10,
                            step: 0.05,
                            valueString: { String(format: "%.0f%%", $0 * 100) }
                        )
                    }
                }
                

                SettingsSection("Advanced") {
                    SliderSettingsRow(
                        "Grab offset X",
                        helperText: "Adjust the position where the mouse grabs the window to move across spaces.",
                        value: $spaceManager.grabOffsetX,
                        range: 0...100,
                        defaultValue: 6.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                    
                    Divider()
                    
                    SliderSettingsRow(
                        "Grab offset Y",
                        value: $spaceManager.grabOffsetY,
                        range: 0...100,
                        defaultValue: 27.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                }
                
                SettingsSection("Per-App Grabbing Offsets") {
                    if spaceManager.appGrabExceptions.isEmpty {
                        Text("No per-app exceptions defined. Standard grab offsets will be used for all apps.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(spaceManager.appGrabExceptions) { exception in
                                HStack {
                                    Image(nsImage: getAppIcon(bundleIdentifier: exception.bundleIdentifier))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                    
                                    Text(exception.appName)
                                        .font(.system(size: 13, weight: .medium))
                                    
                                    Spacer()
                                    
                                    Text("X: \(Int(exception.grabOffsetX)) px, Y: \(Int(exception.grabOffsetY)) px")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .padding(.trailing, 10)
                                    
                                    Button {
                                        editingException = exception
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                    }
                                    .buttonStyle(.borderless)
                                    
                                    Button {
                                        if let idx = spaceManager.appGrabExceptions.firstIndex(where: { $0.bundleIdentifier == exception.bundleIdentifier }) {
                                            spaceManager.appGrabExceptions.remove(at: idx)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                
                                if exception.bundleIdentifier != spaceManager.appGrabExceptions.last?.bundleIdentifier {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Spacer()
                        Button("Add App Exception...") {
                            showingAddExceptionSheet = true
                        }
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: gestureManager.isEnabled)
            .environment(\.settingsTab, .sswitch)
            .sheet(isPresented: $showingAddExceptionSheet) {
                AddAppExceptionView(spaceManager: spaceManager) { newException in
                    spaceManager.appGrabExceptions.append(newException)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        editingException = newException
                    }
                }
            }
            .sheet(item: $editingException) { exception in
                if let idx = spaceManager.appGrabExceptions.firstIndex(where: { $0.bundleIdentifier == exception.bundleIdentifier }) {
                    EditAppExceptionView(
                        spaceManager: spaceManager,
                        exception: Binding(
                            get: { spaceManager.appGrabExceptions[idx] },
                            set: { spaceManager.appGrabExceptions[idx] = $0 }
                        )
                    )
                } else {
                    Text("Error locating exception").padding()
                }
            }
        }
    }
}

struct AddAppExceptionView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var runningApps: [RunningAppInfo] = []
    @State private var selectedRunningAppID: String = ""
    
    struct RunningAppInfo: Identifiable, Hashable {
        var id: String { bundleIdentifier }
        let bundleIdentifier: String
        let appName: String
    }
    
    var onAdd: (AppGrabException) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add App Exception")
                .font(.headline)
            
            Text("Select a currently running app, or choose one from your Applications folder.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if runningApps.isEmpty {
                Text("No running apps found...")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Picker("Running Apps", selection: $selectedRunningAppID) {
                    Text("Select a running app...").tag("")
                    ForEach(runningApps) { app in
                        Text(app.appName).tag(app.bundleIdentifier)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 320)
            }
            
            HStack(spacing: 12) {
                Button("Select App Bundle...") {
                    selectAppFromFinder()
                }
                
                Spacer()
                
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Add") {
                    if let app = runningApps.first(where: { $0.bundleIdentifier == selectedRunningAppID }) {
                        let newException = AppGrabException(
                            bundleIdentifier: app.bundleIdentifier,
                            appName: app.appName,
                            grabOffsetX: spaceManager.grabOffsetX,
                            grabOffsetY: spaceManager.grabOffsetY
                        )
                        onAdd(newException)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(selectedRunningAppID.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding(25)
        .frame(width: 420, height: 220)
        .onAppear {
            loadRunningApps()
        }
    }
    
    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !($0.bundleIdentifier ?? "").isEmpty }
            .map { RunningAppInfo(bundleIdentifier: $0.bundleIdentifier ?? "", appName: $0.localizedName ?? "") }
            .sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
        
        self.runningApps = apps
    }
    
    private func selectAppFromFinder() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.application]
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if openPanel.runModal() == .OK {
            guard let url = openPanel.url else { return }
            let appBundle = Bundle(url: url)
            let bundleID = appBundle?.bundleIdentifier ?? ""
            let appName = (appBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (appBundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            
            guard !bundleID.isEmpty else { return }
            
            let newException = AppGrabException(
                bundleIdentifier: bundleID,
                appName: appName,
                grabOffsetX: spaceManager.grabOffsetX,
                grabOffsetY: spaceManager.grabOffsetY
            )
            onAdd(newException)
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct EditAppExceptionView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Binding var exception: AppGrabException
    @Environment(\.presentationMode) var presentationMode
    
    @State private var previewActive = false
    @State private var keyMonitor: Any? = nil
    @State private var feedbackText: String = ""
    @State private var isFeedbackSuccess: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(nsImage: getAppIcon(bundleIdentifier: exception.bundleIdentifier))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exception.appName)
                        .font(.title2).fontWeight(.bold)
                    Text(exception.bundleIdentifier)
                        .font(.caption).foregroundColor(.secondary).monospaced()
                }
                Spacer()
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Grab offset X")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $exception.grabOffsetX, in: 0...300, step: 1.0)
                    Text("\(Int(exception.grabOffsetX)) px")
                        .frame(width: 50, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .onChange(of: exception.grabOffsetX) { _ in
                    if previewActive {
                        warpCursorToPreview()
                        checkDraggability()
                    }
                }
                
                HStack {
                    Text("Grab offset Y")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $exception.grabOffsetY, in: 0...300, step: 1.0)
                    Text("\(Int(exception.grabOffsetY)) px")
                        .frame(width: 50, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .onChange(of: exception.grabOffsetY) { _ in
                    if previewActive {
                        warpCursorToPreview()
                        checkDraggability()
                    }
                }
            }
            
            VStack(spacing: 8) {
                HStack {
                    Button(action: {
                        togglePreview()
                    }) {
                        HStack {
                            Image(systemName: previewActive ? "eye.slash.fill" : "eye.fill")
                            Text(previewActive ? "Stop Preview" : "Preview Position")
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    if previewActive {
                        Text("Arrow keys adjustment active. Press arrow keys to move.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                if !feedbackText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: isFeedbackSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isFeedbackSuccess ? .green : .orange)
                        Text(feedbackText)
                            .font(.caption)
                            .foregroundColor(isFeedbackSuccess ? .primary : .orange)
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isFeedbackSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }
            }
            .padding(.vertical, 8)
            
            HStack {
                Spacer()
                Button("Done") {
                    stopPreview()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(25)
        .frame(width: 480, height: 350)
        .onDisappear {
            stopPreview()
        }
    }
    
    private func togglePreview() {
        if previewActive {
            stopPreview()
        } else {
            startPreview()
        }
    }
    
    private func startPreview() {
        guard SpaceHelper.getAppWindowFrame(bundleIdentifier: exception.bundleIdentifier) != nil else {
            feedbackText = "No visible window found for \(exception.appName). Please open a window of the app and make it visible."
            isFeedbackSuccess = false
            return
        }
        
        previewActive = true
        warpCursorToPreview()
        checkDraggability()
        startMonitoringKeys()
    }
    
    private func stopPreview() {
        previewActive = false
        stopMonitoringKeys()
    }
    
    private func warpCursorToPreview() {
        guard let frame = SpaceHelper.getAppWindowFrame(bundleIdentifier: exception.bundleIdentifier) else { return }
        let targetPoint = CGPoint(
            x: frame.origin.x + CGFloat(exception.grabOffsetX),
            y: frame.origin.y + CGFloat(exception.grabOffsetY)
        )
        CGWarpMouseCursorPosition(targetPoint)
    }
    
    private func checkDraggability() {
        let (status, working) = SpaceHelper.getGrabPositionStatus(
            forBundleID: exception.bundleIdentifier,
            x: exception.grabOffsetX,
            y: exception.grabOffsetY
        )
        feedbackText = status
        isFeedbackSuccess = working
    }
    
    private func startMonitoringKeys() {
        stopMonitoringKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard previewActive else { return event }
            
            switch event.keyCode {
            case 123: // Left arrow
                exception.grabOffsetX = max(0, exception.grabOffsetX - 1)
                warpCursorToPreview()
                checkDraggability()
                return nil
            case 124: // Right arrow
                exception.grabOffsetX = min(300, exception.grabOffsetX + 1)
                warpCursorToPreview()
                checkDraggability()
                return nil
            case 125: // Down arrow
                exception.grabOffsetY = min(300, exception.grabOffsetY + 1)
                warpCursorToPreview()
                checkDraggability()
                return nil
            case 126: // Up arrow
                exception.grabOffsetY = max(0, exception.grabOffsetY - 1)
                warpCursorToPreview()
                checkDraggability()
                return nil
            case 53: // Esc
                stopPreview()
                return nil
            default:
                return event
            }
        }
    }
    
    private func stopMonitoringKeys() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

private func getAppIcon(bundleIdentifier: String) -> NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSWorkspace.shared.icon(forFileType: "app")
}
