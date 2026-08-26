import SwiftUI
import AVKit

struct OnboardingView: View {
    @Environment(\.openURL) var openURL
    @ObservedObject var hotkeyManager: HotkeyManager
    var onClose: () -> Void
    
    @State private var currentPage = 0
    @State private var movingForward = true
    private let totalPages = 10

    var body: some View {
        VStack(spacing: 0) {
            // Current page content
            ZStack {
                switch currentPage {
                case 0:
                    WelcomePage()
                        .transition(pageTransition)
                case 1:
                    RenamePage()
                        .transition(pageTransition)
                case 2:
                    MissionControlPage()
                        .transition(pageTransition)
                case 3:
                    MenuBarSwitchPage()
                        .transition(pageTransition)
                case 4:
                    FastSwitchingPage()
                        .transition(pageTransition)
                case 5:
                    LaunchersPage(
                        openURL: openURL,
                        hotkeyManager: hotkeyManager,
                        launcherViewModel: LauncherWindowController.shared.viewModel
                    )
                        .transition(pageTransition)
                case 6:
                    ManageWindowsPage()
                        .transition(pageTransition)
                case 7:
                    LockSpacePage()
                        .transition(pageTransition)
                case 8:
                    PermissionsPage()
                        .transition(pageTransition)
                case 9:
                    MoreAppsPage()
                        .transition(pageTransition)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Navigation controls
            HStack {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                
                Spacer()
                
                // Navigation: Skip
                if currentPage < totalPages - 1 {
                    Button("Skip") {
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
                }

                // Navigation: Back
                if currentPage > 0 {
                    Button("Back") {
                        movingForward = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
                }
                
                // Navigation: Next / Completion
                Button(action: {
                    if currentPage < totalPages - 1 {
                        movingForward = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    } else {
                        onClose()
                    }
                }) {
                    Text(currentPage < totalPages - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(currentPage < totalPages - 1 ? Color.primary : .white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if currentPage < totalPages - 1 {
                                    Color.secondary.opacity(0.15)
                                } else {
                                    Color.accentColor
                                }
                            }
                        )
                        .cornerRadius(8)
                        .animation(.easeInOut(duration: 0.25), value: currentPage)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .frame(width: 700, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var pageTransition: AnyTransition {
        if movingForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

// Pages

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

    var body: some View {
        VStack(spacing: 10) {
            SingleVideoFeaturePage(
                title: NSLocalizedString("Faster Switching Override", comment: ""),
                subtitle: NSLocalizedString("Bypass native macOS animation lag. Enable trackpad overrides or hotkeys for instant, zero-delay switching.", comment: ""),
                videoName: "SwitchOverride"
            )

            HStack(alignment: .top, spacing: 40) {
                Toggle("Enable switch gesture override", isOn: $gestureEnabled)
                    .toggleStyle(.switch)

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

struct LaunchersPage: View {
    var openURL: OpenURLAction
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var launcherViewModel: LauncherViewModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Text("Launchers")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Choose Raycast or the built-in launcher to manage your Spaces and windows.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }

            HStack(alignment: .top, spacing: 20) {
                LauncherShowcase(
                    title: "Raycast",
                    imageName: "RaycastExtension",
                    imageFallbackSymbol: "puzzlepiece.extension.fill"
                ) {
                    Button(action: {
                        if let url = URL(string: "https://www.raycast.com/michael_qiu/desktoprenamer") {
                            openURL(url)
                        }
                    }) {
                        Label("Install Extension", systemImage: "arrow.down.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                LauncherShowcase(
                    title: "DesktopRenamer",
                    imageName: "DesktopRenamerLauncher",
                    imageFallbackSymbol: "rectangle.and.text.magnifyingglass"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Open launcher")
                            Spacer()
                            Text(hotkeyManager.description(for: .launcher))
                                .foregroundColor(.secondary)
                            Button("◉") {
                                hotkeyManager.startListening(for: .launcher)
                            }
                            .disabled(hotkeyManager.isListening)
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .launcher)
                            }
                            .disabled(hotkeyManager.isDefault(for: .launcher))
                        }

                        Toggle("Automatically rank commands", isOn: $launcherViewModel.automaticallyRankCommands)
                            .toggleStyle(.switch)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 20)
    }
}

private struct LauncherShowcase<Controls: View>: View {
    let title: String
    let imageFallbackSymbol: String
    let image: NSImage?
    @ViewBuilder let controls: () -> Controls

    init(
        title: String,
        imageName: String,
        imageFallbackSymbol: String,
        @ViewBuilder controls: @escaping () -> Controls
    ) {
        self.title = title
        self.imageFallbackSymbol = imageFallbackSymbol
        self.image = Bundle.main.url(forResource: imageName, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        self.controls = controls
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                Image(systemName: imageFallbackSymbol)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            controls()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct ManageWindowsPage: View {
    var body: some View {
        SingleVideoFeaturePage(
            title: NSLocalizedString("Manage Windows", comment: ""),
            subtitle: NSLocalizedString("Move all windows of an app to another Space in one command.", comment: ""),
            videoName: "RaycastBatchMove"
        )
    }
}

struct PermissionsPage: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.red, .orange]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Require Permissions")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("DesktopRenamer requires Accessibility permission for hotkeys and trackpad overrides to function correctly.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    permissionManager.requestAccessibilityPermission()
                }) {
                    HStack {
                        Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .white)
                        Text("Accessibility")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(permissionManager.isAccessibilityGranted ? Color.blue : Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
}

struct MoreAppsPage: View {
    @Environment(\.colorScheme) var colorScheme
    var iconSuffix: String {
        colorScheme == .dark ? "_Dark" : "_Default"
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Discover More Apps")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Check out these other productivity tools we've built.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 12) {
                // OptClicker
                OtherAppRow(
                    imageName: "OptClickerIcon\(iconSuffix)",
                    appName: "OptClicker",
                    description: NSLocalizedString("Let you right-click with the Option key.", comment: ""),
                    url: "https://optclicker.mqiu.dev"
                )
                
                // SpaceSwitcher
                OtherAppRow(
                    imageName: "SpaceSwitcherIcon\(iconSuffix)",
                    appName: "SpaceSwitcher",
                    description: NSLocalizedString("Control which app and dock to show in each space.", comment: ""),
                    url: "https://spaceswitcher.mqiu.dev"
                )

                OtherAppRow(
                    imageName: "VTPlayerIcon\(iconSuffix)",
                    appName: "VTPlayer",
                    description: NSLocalizedString("Real-time video enhancing player.", comment: ""),
                    url: "https://vtplayer.mqiu.dev"
                )
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct LockSpacePage: View {
    var body: some View {
        SingleVideoFeaturePage(
            title: NSLocalizedString("Lock Your Spaces", comment: ""),
            subtitle: NSLocalizedString("Prevent applications or macOS from automatically switching spaces. Keep your workspace focused by locking important desktops.", comment: ""),
            videoName: "LockSpace"
        )
    }
}
