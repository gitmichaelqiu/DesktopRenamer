import SwiftUI
import AVKit

struct SplashView: View {
    @Environment(\.openURL) var openURL
    var onClose: () -> Void
    
    @State private var currentPage = 0
    @State private var movingForward = true
    private let totalPages = 6

    var body: some View {
        VStack(spacing: 0) {
            // Current page content
            ZStack {
                switch currentPage {
                case 0:
                    WelcomePage()
                        .transition(pageTransition)
                case 1:
                    MissionControlPage()
                        .transition(pageTransition)
                case 2:
                    SwitchMovePage()
                        .transition(pageTransition)
                case 3:
                    OrganizeSpacesPage()
                        .transition(pageTransition)
                case 4:
                    PowerToolsPage(openURL: openURL)
                        .transition(pageTransition)
                case 5:
                    SetupPage()
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

                if currentPage < totalPages - 1 {
                    Button("Skip") {
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
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
                        .animation(.none, value: currentPage)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .frame(width: 760, height: 600)
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
        VStack(spacing: 20) {
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 92)
                    .shadow(radius: 5)
            }
            
            VStack(spacing: 10) {
                Text("Welcome to DesktopRenamer")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Name, organize, and move through your macOS Spaces with confidence.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 12) {
                SplashValueCard(icon: "rectangle.3.group", title: "See", detail: "Clear labels for every Space")
                SplashValueCard(icon: "arrow.left.arrow.right", title: "Switch", detail: "Jump or move windows instantly")
                SplashValueCard(icon: "square.3.layers.3d", title: "Organize", detail: "Reorder and protect your workspace")
            }
            .padding(.horizontal, 26)
        }
        .padding()
    }
}

struct SplashValueCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SwitchMovePage: View {
    var body: some View {
        DoubleVideoFeaturePage(
            title: NSLocalizedString("Switch and Move", comment: ""),
            subtitle: NSLocalizedString("Jump between Spaces from the menu bar, or move the active window with Option-click.", comment: ""),
            videoName1: "SwitchSpace",
            videoName2: "MoveWindow",
            label1: NSLocalizedString("Switch Space", comment: ""),
            label2: NSLocalizedString("Option-click to move", comment: "")
        )
    }
}

struct OrganizeSpacesPage: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Organize Your Spaces")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Keep your workspace predictable, even when macOS or fullscreen apps rearrange it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 14) {
                SplashValueCard(icon: "arrow.up.arrow.down.square", title: "Rearrange", detail: "Drag or use shortcuts to reorder Spaces.")
                SplashValueCard(icon: "lock.shield", title: "Lock", detail: "Prevent unwanted Space changes.")
                SplashValueCard(icon: "rectangle.inset.filled.and.person.filled", title: "Fullscreen", detail: "Keep fullscreen Spaces in the right place.")
            }
            .padding(.horizontal, 28)

            HStack(spacing: 14) {
                Image(systemName: "display.2")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Multiple displays are supported, including moving windows between displays.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 28)
        }
        .padding(.top, 28)
    }
}

struct PowerToolsPage: View {
    var openURL: OpenURLAction

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Power Tools")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Automate Space management from your favorite tools.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                VStack(spacing: 10) {
                    if let imageURL = Bundle.main.url(forResource: "RaycastExtension", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: imageURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Raycast")
                        .font(.headline)
                    Text("Switch Spaces and batch-move windows in one command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    SplashValueCard(icon: "terminal", title: "SpaceAPI", detail: "Control and inspect Spaces from scripts and integrations.")
                    SplashValueCard(icon: "arrow.left.arrow.right.square", title: "App automation", detail: "Customize how individual apps move between Spaces.")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)

            Button {
                guard let url = URL(string: "https://www.raycast.com/michael_qiu/desktoprenamer") else { return }
                openURL(url)
            } label: {
                Label("Install Raycast Extension", systemImage: "arrow.up.right.square")
                    .fontWeight(.semibold)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 26)
    }
}

struct SetupPage: View {
    @AppStorage("kShowPreviewLabels") private var showPreviewLabels = true
    @AppStorage("kShowActiveLabels") private var showActiveLabels = true
    @AppStorage("kShowOnDesktop") private var showOnDesktop = false
    @AppStorage("GestureManager.Enabled") private var gestureEnabled = false
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Make It Yours")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Choose the essentials now. Everything can be changed later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show preview labels in Mission Control", isOn: $showPreviewLabels)
                Toggle("Show active Space labels", isOn: $showActiveLabels)
                if showActiveLabels {
                    Toggle("Keep active labels visible on the desktop", isOn: $showOnDesktop)
                }
                Toggle("Enable faster switching gestures", isOn: $gestureEnabled)
            }
            .toggleStyle(.switch)
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 70)

            HStack(spacing: 10) {
                Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.shield.fill" : "lock.shield")
                    .foregroundStyle(permissionManager.isAccessibilityGranted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission")
                        .font(.subheadline.weight(.semibold))
                    Text("Needed for gestures, hotkeys, and moving windows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(permissionManager.isAccessibilityGranted ? "Granted" : "Allow") {
                    permissionManager.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)
                .disabled(permissionManager.isAccessibilityGranted)
            }
            .padding(.horizontal, 70)
        }
        .padding(.top, 26)
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
                    Toggle("Show preview labels", isOn: $showPreviewLabels)
                        .toggleStyle(.switch)
                    
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

    var body: some View {
        VStack(spacing: 10) {
            SingleVideoFeaturePage(
                title: NSLocalizedString("Faster Switching Override", comment: ""),
                subtitle: NSLocalizedString("Bypass native macOS animation lag. Enable trackpad overrides or hotkeys for instant, zero-delay switching.", comment: ""),
                videoName: "SwitchOverride"
            )

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable switch gesture override", isOn: $gestureEnabled)
                    .toggleStyle(.switch)
            }
            .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.25), value: gestureEnabled)
    }
}

struct RaycastFeaturePage: View {
    var openURL: OpenURLAction

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Text("Raycast Integration")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Are you a power user? Integrate directly with Raycast to manage and switch spaces elegantly via your favorite launcher.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }
            
            // Raycast extension preview.
            if let imageURL = Bundle.main.url(forResource: "RaycastExtension", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 40)
            } else if let nsImageFallback = NSImage(named: "RaycastExtension") {
                Image(nsImage: nsImageFallback)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 40)
            } else {
                // Fallback icon for missing extension image.
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
            }

            Button(action: {
                if let url = URL(string: "https://www.raycast.com/michael_qiu/desktoprenamer") {
                    openURL(url)
                }
            }) {
                HStack {
                    Image(systemName: "command.square.fill")
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("Install Raycast Extension")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    Color.red
                )
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8)
        }
        .padding(.top, 20)
    }
}

struct RaycastBatchMovePage: View {
    var body: some View {
        SingleVideoFeaturePage(
            title: NSLocalizedString("Raycast: Batch Move", comment: ""),
            subtitle: NSLocalizedString("Use the Raycast extension to move all windows of an app to another space in one command.", comment: ""),
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
