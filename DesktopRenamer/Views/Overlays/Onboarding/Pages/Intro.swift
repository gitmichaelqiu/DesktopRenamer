import SwiftUI
import AVKit

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(radius: 5)
            }
            
                VStack(spacing: 12) {
                    Text("Welcome to")
                        .font(.system(size: 30, weight: .medium, design: .rounded))


                    Text("DesktopRenamer")
                        .font(.custom("Syncopate-Bold", size: 28))
                }
                .multilineTextAlignment(.center)
                
                Text("Take back control of your macOS spaces.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()
    }
}


struct RenamePage: View {
    var body: some View {
        SingleVideoFeaturePage(
            title: NSLocalizedString("Rename at Menu Bar", comment: ""),
            subtitle: NSLocalizedString("Quickly give your desktop spaces a custom name directly from the menu bar.", comment: ""),
            videoName: "Rename"
        )
    }
}

struct MissionControlPage: View {
    @AppStorage("kShowPreviewLabels") private var showPreviewLabels = true
    @AppStorage("kHideWhenSwitching") private var hideWhenSwitching = false
    @AppStorage("kShowActiveLabels") private var showActiveLabels = true
    @AppStorage("kShowOnDesktop") private var showOnDesktop = false

    var body: some View {
        VStack(spacing: 10) {
            DoubleVideoFeaturePage(
                title: NSLocalizedString("Crystal Clear Labels", comment: ""),
                subtitle: NSLocalizedString("See large, aesthetic name labels when you enter Mission Control, and discreet active labels when you switch spaces.", comment: ""),
                videoName1: "MissionControl",
                videoName2: "ActiveLabel",
                label1: NSLocalizedString("Preview Label", comment: ""),
                label2: NSLocalizedString("Active Space Label", comment: "")
            )
            
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show preview labels", isOn: $showPreviewLabels)
                            .toggleStyle(.switch)

                        if showPreviewLabels {
                            Toggle("Hide when switching spaces", isOn: $hideWhenSwitching)
                                .toggleStyle(.switch)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show active space labels", isOn: $showActiveLabels)
                            .toggleStyle(.switch)
                        
                        if showActiveLabels {
                            Toggle("Keep visible on desktop", isOn: $showOnDesktop)
                                .toggleStyle(.switch)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .padding(.bottom, 10)
        }
        .animation(.easeInOut(duration: 0.25), value: showPreviewLabels)
        .animation(.easeInOut(duration: 0.25), value: showActiveLabels)
    }
}

struct MenuBarSwitchPage: View {
    var body: some View {
        DoubleVideoFeaturePage(
            title: NSLocalizedString("Switch & Move", comment: ""),
            subtitle: NSLocalizedString("Click a space in the menu bar to jump right to it.\nHold the Option (⌥) key to instantly teleport your active window.", comment: ""),
            videoName1: "SwitchSpace",
            videoName2: "MoveWindow",
            label1: NSLocalizedString("Switch Space", comment: ""),
            label2: NSLocalizedString("Option + Click to Move", comment: "")
        )
    }
}

struct FastSwitchingPage: View {
    @AppStorage("GestureManager.Enabled") private var gestureEnabled = false
    @AppStorage("GestureManager.FingerCount") private var fingerCount = 3
    @AppStorage("GestureManager.MoveWindowOnOption") private var moveWindowOnOption = false

    var body: some View {
        VStack(spacing: 10) {
            SingleVideoFeaturePage(
                title: NSLocalizedString("Faster Switching Override", comment: ""),
                subtitle: NSLocalizedString("Bypass native macOS animation lag. Enable trackpad overrides or hotkeys for instant, zero-delay switching.", comment: ""),
                videoName: "SwitchOverride"
            )

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable switch gesture override", isOn: $gestureEnabled)
                        .toggleStyle(.switch)

                    if gestureEnabled {
                        Toggle("Move window when holding Option", isOn: $moveWindowOnOption)
                            .toggleStyle(.switch)
                    }
                }

                if gestureEnabled {
                    HStack(spacing: 8) {
                        Text("Gesture type")

                        Picker("Gesture type", selection: $fingerCount) {
                            Text("3 Fingers").tag(3)
                            Text("4 Fingers").tag(4)
                        }
                        .labelsHidden()
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.25), value: gestureEnabled)
    }
}
