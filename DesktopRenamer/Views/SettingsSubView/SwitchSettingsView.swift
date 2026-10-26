import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var gestureManager: GestureManager
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var navigationState: SettingsNavigationState
    @StateObject private var permissionManager = PermissionManager.shared
    
    @State private var showingAddExceptionSheet = false
    @State private var editingException: AppGrabException? = nil
    
    
    var body: some View {
        SettingsContainer(.sswitch) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Space Lock") {
                    SettingsRow("Automatically restore windows when unlocking") {
                        Toggle("", isOn: $spaceManager.autoRestoreWindowsOnUnlock)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                // Gesture-based switching configuration.
                SettingsSection("Trackpad Switch Gesture Override") {
                    SettingsRow(
                        "Enable switch gesture override",
                        helperText:
                            "Use instant space switching for trackpad gestures. Disable ‘Swipe between full-screen apps’ in System Settings → Trackpad → More Gestures to avoid conflicts.",
                        requirements: [
                            .accessibility(isGranted: permissionManager.hasEventInjectionPermission)
                        ],
                        demoVideoName: "SwitchOverride"
                    ) {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
                        Divider()

                        SettingsRow("Gesture type", helperText: "With 3 fingers selected, 4 fingers can still trigger the native swipe.") {
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
                        
                        SettingsRow(
                            "Move window when holding Option",
                            requirements: [
                                .accessibility(isGranted: permissionManager.hasEventInjectionPermission),
                                .screenRecording(isGranted: permissionManager.isScreenCaptureGranted)
                            ]
                        ) {
                            Toggle("", isOn: $gestureManager.moveWindowOnOption)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider()

                        SliderSettingsRow(
                            "Switch duration",
                            helperText: "Set to 0 to switch instantly without the macOS animation.",
                            value: $gestureManager.switchDuration,
                            range: 0...1.0,
                            defaultValue: 0.30,
                            step: 0.05,
                            valueString: {String(format: "%.2fs", $0) }
                        )

                        Divider()
                        
                        SliderSettingsRow(
                            "Switch override threshold",
                            helperText: "Sets how far you need to move your fingers before switching.",
                            value: $gestureManager.swipeThreshold,
                            range: 0.05...0.50,
                            defaultValue: 0.10,
                            step: 0.05,
                            valueString: { String(format: "%.0f%%", $0 * 100) }
                        )
                    }
                }
                

                SettingsSection("Window Movement") {
                    SliderSettingsRow(
                        "Grab offset X",
                        helperText: "Adjust where the pointer grabs a window when moving it between spaces.",
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

                SettingsSection(nil) {
                    SettingsRow("Exceptions") {
                        Button("Add app exception...") {
                            showingAddExceptionSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    if spaceManager.appGrabExceptions.isEmpty {
                        Divider()
                        HStack {
                            Spacer()
                            Text("No per-app exceptions defined. Standard grab offsets will be used for all apps.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                    } else {
                        Divider()
                        VStack(spacing: 0) {
                            ForEach(spaceManager.appGrabExceptions) { exception in
                                AppExceptionRow(
                                    exception: exception,
                                    onEdit: { editingException = exception },
                                    onDelete: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if let idx = spaceManager.appGrabExceptions.firstIndex(where: { $0.bundleIdentifier == exception.bundleIdentifier }) {
                                                spaceManager.appGrabExceptions.remove(at: idx)
                                            }
                                        }
                                    }
                                )

                                if exception.bundleIdentifier != spaceManager.appGrabExceptions.last?.bundleIdentifier {
                                    Divider().padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: spaceManager.appGrabExceptions)
                
}
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: gestureManager.isEnabled)
            .environment(\.settingsTab, .sswitch)
            .onAppear {
                if let bundleID = spaceManager.autoEditBundleID {
                    if let exception = spaceManager.appGrabExceptions.first(where: { $0.bundleIdentifier == bundleID }) {
                        editingException = exception
                    }
                    spaceManager.autoEditBundleID = nil
                }
            }
            .onChange(of: spaceManager.autoEditBundleID) { bundleID in
                if let bundleID = bundleID {
                    if let exception = spaceManager.appGrabExceptions.first(where: { $0.bundleIdentifier == bundleID }) {
                        editingException = exception
                    }
                    spaceManager.autoEditBundleID = nil
                }
            }
            .sheet(isPresented: $showingAddExceptionSheet) {
                AddAppExceptionView(spaceManager: spaceManager) { newException in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        spaceManager.appGrabExceptions.append(newException)
                    }
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
                    .environmentObject(navigationState)
                } else {
                    Text("Error locating exception").padding()
                }
            }
        }
    }
}
