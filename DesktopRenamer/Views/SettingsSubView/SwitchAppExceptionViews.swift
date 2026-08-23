import AppKit
import ApplicationServices
import SwiftUI
struct AddAppExceptionView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var runningApps: [RunningAppInfo] = []
    
    struct RunningAppInfo: Identifiable, Hashable {
        var id: String { bundleIdentifier }
        let bundleIdentifier: String
        let appName: String
    }
    
    var onAdd: (AppGrabException) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add App Exception")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Select an active application below to add it as an exception.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(runningApps) { app in
                        AppListItemView(icon: ApplicationIconCache.icon(forBundleIdentifier: app.bundleIdentifier), name: app.appName, isSelectable: true) {
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
                    
                    Divider().padding(.vertical, 4)
                    
                    AppListItemView(icon: NSImage(), name: NSLocalizedString("Choose Application...", comment: ""), isSelectable: false) {
                        selectAppFromFinder()
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            
            HStack {
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 400, height: 380)
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
            // Header
            HStack(spacing: 12) {
                        Image(nsImage: ApplicationIconCache.icon(forBundleIdentifier: exception.bundleIdentifier))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exception.appName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(exception.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                Spacer()
            }
            .padding(.bottom, 5)
            
            // Sliders area
            SettingsSection(nil) {
                SliderSettingsRow(
                    "Grab offset X",
                    value: Binding(
                        get: { exception.grabOffsetX },
                        set: { exception.grabOffsetX = $0.rounded() }
                    ),
                    range: 0...300,
                    defaultValue: spaceManager.grabOffsetX,
                    valueString: { String(format: "%.0f px", $0) }
                )
                .onChange(of: exception.grabOffsetX) { _ in
                    if previewActive {
                        warpCursorToPreview()
                        checkDraggability()
                    }
                }
                
                Divider()
                
                SliderSettingsRow(
                    "Grab offset Y",
                    value: Binding(
                        get: { exception.grabOffsetY },
                        set: { exception.grabOffsetY = $0.rounded() }
                    ),
                    range: 0...300,
                    defaultValue: spaceManager.grabOffsetY,
                    valueString: { String(format: "%.0f px", $0) }
                )
                .onChange(of: exception.grabOffsetY) { _ in
                    if previewActive {
                        warpCursorToPreview()
                        checkDraggability()
                    }
                }
                
                Divider()
                
                SettingsRow(
                    "Drag window slightly before switching",
                    helperText: "For custom-drawn windows (like WeChat) that require mouse movement to start dragging. Enabling this may resolve some window movement failures."
                ) {
                    Toggle("", isOn: Binding(
                        get: { exception.dragBeforeSwitch ?? false },
                        set: { exception.dragBeforeSwitch = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            
            // Feedback status area
            if !feedbackText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: isFeedbackSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isFeedbackSuccess ? .green : .orange)
                    Text(feedbackText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isFeedbackSuccess ? .primary : .orange)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFeedbackSuccess ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isFeedbackSuccess ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Bottom control row
            HStack {
                Button(action: togglePreview) {
                    HStack {
                        Image(systemName: previewActive ? "eye.slash.fill" : "eye.fill")
                        Text(previewActive ? "Stop Preview" : "Preview Position")
                    }
                }
                .buttonStyle(.bordered)
                
                if previewActive {
                    Text("Use ← → ↑ ↓ to fine-tune, Esc to exit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    stopPreview()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 460, height: 400)
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
        bringAppWindowToFront()
        
        guard SpaceHelper.getAppWindowFrame(bundleIdentifier: exception.bundleIdentifier) != nil else {
            feedbackText = String(format: String(localized: "No visible window found for %@. Please open a window of the app and make it visible."), exception.appName)
            isFeedbackSuccess = false
            return
        }
        
        previewActive = true
        warpCursorToPreview()
        checkDraggability()
        startMonitoringKeys()
    }
    
    private func bringAppWindowToFront() {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == exception.bundleIdentifier }) else {
            return
        }
        let pid = runningApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        
        var windowListRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, "AXWindows" as CFString, &windowListRef)
        guard result == .success, let windows = windowListRef as? [AXUIElement], !windows.isEmpty else {
            return
        }
        
        for windowRef in windows {
            // Unminimize if minimized
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowRef, "AXMinimized" as CFString, &minimizedRef) == .success,
               let isMinimized = minimizedRef as? Bool, isMinimized {
                AXUIElementSetAttributeValue(windowRef, "AXMinimized" as CFString, false as CFTypeRef)
            }
            // Raise window to front
            AXUIElementPerformAction(windowRef, "AXRaise" as CFString)
        }
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
            case 36, 76: // Enter / Return
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

struct AppExceptionRow: View {
    let exception: AppGrabException
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
                    Image(nsImage: ApplicationIconCache.icon(forBundleIdentifier: exception.bundleIdentifier))
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(exception.appName)
                    .font(.system(size: 13, weight: .medium))
                Text(exception.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Text("X: \(Int(exception.grabOffsetX)) px, Y: \(Int(exception.grabOffsetY)) px")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Edit Exception")
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Exception")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

struct AppListItemView: View {
    let icon: NSImage
    let name: String
    let isSelectable: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isSelectable {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "plus.app")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                }
                
                Text(name)
                    .font(.system(size: 13))
                    .foregroundColor(isSelectable ? .primary : .accentColor)
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.gray.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
